;;;; mail/mail.lisp -- sending email (spec/mail.md).
;;;;
;;;; SEND-MAIL stores a mail in the caller's transaction, with the job that
;;;; delivers it, so a mail exists only when the work that sends it commits.
;;;; Delivery is that job (spec/jobs.md), in the :mail queue: each attempt
;;;; calls the application's mail adapter outside any transaction and
;;;; records the outcome on the mail.  A temporary failure is retried after a
;;;; growing delay; every attempt carries the mail's id as the provider's
;;;; idempotency key, so a retry after a lost answer is not a second mail.
;;;;
;;;; An adapter is a class with one method, DELIVER-MAIL.  This file has the
;;;; log adapter, which sends nothing; resend.lisp has Resend's.  html.lisp
;;;; makes a mail's HTML and text parts from a node tree.

(defpackage #:tun.mail
  (:use #:cl #:tun.core)
  (:import-from #:tun.jobs #:define-job #:enqueue-job #:fail-job #:last-attempt-p)
  (:import-from #:tun.html #:render-html #:trusted #:node-parts)
  (:export #:mail #:mail-to #:mail-subject #:mail-text #:mail-html #:mail-reply-to #:mail-key
           #:mail-status #:mail-attempts #:mail-job-id #:mail-last-error
           #:mail-provider #:mail-provider-id #:mail-created-at #:mail-sent-at
           #:send-mail #:render-mail #:+mail-retry-delays+ #:+mail-time-limit+
           #:mail-adapter #:deliver-mail #:provider-name #:log-mail
           #:resend-mail #:resend-endpoint #:resend-from
           #:make-mail-adapter #:mail-problems #:send-queued-mail
           #:mail-list #:mail-get #:mail-retry))

(in-package #:tun.mail)

(declaim (optimize (safety 3) (debug 2)))

(define-entity mail (:label "E-post" :id-prefix "mail" :table "mails" :internal t
                            :indexes (("status") ("key") ("to")))
  ((to :type (email :max 320) :required t :input nil :label "Til")
   (subject :type (string :min 1 :max 998) :required t :input nil :label "Emne")
   (text :type (string :min 1 :max 100000) :required t :input nil :label "Tekst")
   (html :type (string :max 500000) :input nil :label "HTML")
   (reply-to :type (email :max 320) :input nil :label "Svar til")
   (key :type (string :max 200) :input nil :label "Nøkkel"
        :description "Makes the send once only: a second send with the key returns the first mail.")
   (status :type (enum "queued" "sending" "sent" "failed") :input nil :initform "queued"
           :label "Status")
   (attempts :type integer :input nil :initform 0 :label "Forsøk")
   (job-id :type id :input nil :label "Jobb"
           :description "The job that delivers it; jobs_get shows when it tries next.")
   (last-error :type (string :max 2000) :input nil :label "Siste feil")
   (provider :type (string :max 64) :input nil :label "Leverandør")
   (provider-id :type (string :max 200) :input nil :label "Leverandørens ID")
   (created-at :type timestamp :input nil :label "Opprettet")
   (sent-at :type timestamp :input nil :label "Sendt")))

;;; ------------------------------------------------------------------
;;; Sending

(defun mail-argument (name value &key required)
  "VALUE checked as the mail's field NAME checks its input, or NIL; an
error is collected for COLLECTING-INPUT-ERRORS."
  (if (null value)
      (when required (input-error name "må fylles ut"))
      (coerce-input (field-type (find-field (find-class 'mail) name)) value name)))

(defun send-mail (&key to subject text html reply-to key)
  "Queue a mail to TO, inside the current write, and return it: it is sent
after the write commits, and never when it rolls back (spec/mail.md 2).
HTML is a node tree, rendered as RENDER-MAIL renders it; without TEXT, the
text part is made from it.  When a mail with KEY exists, return that one
and store nothing.  A bad argument fails the operation with invalid_input."
  (let ((mail (collecting-input-errors
               (let ((to (mail-argument "to" to :required t))
                     (subject (mail-argument "subject" subject :required t)))
                 (multiple-value-bind (html-part text-part) (checked-parts html subject text)
                   (make-instance 'mail :to to :subject subject :text text-part :html html-part
                                        :reply-to (mail-argument "reply_to" reply-to)
                                        :key (mail-argument "key" key)))))))
    (or (and (mail-key mail)
             (select-one 'mail :where `(:= "key" ,(mail-key mail))))
        (progn
          (setf (mail-created-at mail) (now))
          (insert mail)
          (queue-delivery mail)))))

;;; ------------------------------------------------------------------
;;; Adapters

(defclass mail-adapter () ()
  (:documentation "A mail provider.  A subclass has a DELIVER-MAIL method and a
PROVIDER-NAME."))

(defgeneric deliver-mail (adapter mail)
  (:documentation "Send MAIL through ADAPTER's provider, with (ENTITY-ID MAIL) as
the idempotency key.  Values :SENT and the provider's id for the mail, or
:RETRY or :FAILED and a reason.  An error it signals counts as :RETRY."))

(defgeneric provider-name (adapter)
  (:documentation "The provider's name in a mail's provider field, such as \"resend\"."))

(defclass log-mail (mail-adapter) ()
  (:documentation "Sends nothing: accepts each mail and writes its recipient and
subject, not its text, to standard output (spec/mail.md 1)."))

(defmethod provider-name ((adapter log-mail)) "log")

(defmethod deliver-mail ((adapter log-mail) mail)
  (unless (test-mode-p)
    (format t "~&tun: mail ~a to ~a, not sent (no mail provider): ~a~%"
            (entity-id mail) (mail-to mail) (mail-subject mail))
    (finish-output))
  (values :sent (entity-id mail)))

(defparameter *mail-providers*
  '((:resend resend-mail :api-key :from)
    (:log log-mail))
  "Each provider (:mail ...) can name: its keyword, its adapter class, and the
settings it cannot do without.")

(defun make-mail-adapter (spec)
  "The adapter SPEC, a provider as (:mail ...) wrote it, describes; the log
adapter when SPEC is NIL.  Values it and NIL, or the log adapter and the
problems that kept SPEC's adapter from being made."
  (when (null spec)
    (return-from make-mail-adapter (values (make-instance 'log-mail) nil)))
  (destructuring-bind (kind &rest settings) spec
    (destructuring-bind (&optional class &rest required) (rest (assoc kind *mail-providers*))
      (let ((initargs '()) (problems '()))
        (if (null class)
            (push (format nil "~(~s~) is not a mail provider; there are ~{~(~s~)~^, ~}"
                          kind (mapcar #'first *mail-providers*))
                  problems)
            (progn
              (loop for (key value) on settings by #'cddr
                    do (multiple-value-bind (text missing) (configured-value value)
                         (if missing
                             (push (format nil "~(~a ~s~) needs ~a" kind key missing) problems)
                             (setf initargs (list* key text initargs)))))
              (dolist (key required)
                (unless (getf settings key)
                  (push (format nil "~(~a~) needs ~(~s~)" kind key) problems)))))
        (let ((adapter (and (null problems)
                            (handler-case (apply #'make-instance class initargs)
                              (error (e)
                                (push (format nil "~(~a~): ~a" kind e) problems)
                                nil)))))
          (if adapter
              (values adapter nil)
              (values (make-instance 'log-mail) (reverse problems))))))))

(defun mail-problems (application-class)
  "What keeps the mail provider APPLICATION-CLASS names from being used, as
lines for the server's log; NIL when it can be."
  (nth-value 1 (make-mail-adapter (application-mail-spec application-class))))

;;; ------------------------------------------------------------------
;;; Delivery (spec/mail.md 3)

(defparameter +mail-retry-delays+ '(30 120 600 1800 3600 10800)
  "Seconds to wait after each failed attempt, the first to the sixth; a mail
whose seventh attempt fails is failed for good.")

(defparameter +mail-time-limit+ 10
  "Seconds a provider has to answer one attempt.")

(defun queue-delivery (mail)
  "Enqueue the job that delivers MAIL, in the current write, and note it on
the mail.  Returns MAIL."
  (setf (mail-job-id mail) (entity-id (enqueue-job 'send-queued-mail :mail-id (entity-id mail))))
  (save mail)
  mail)

(defun start-attempt (mail-id)
  "In a write transaction: the mail MAIL-ID marked sending with this attempt
counted, or NIL when it is gone or already sent or failed."
  (let ((mail (fetch 'mail mail-id)))
    (when (and mail (member (mail-status mail) '("queued" "sending") :test #'string=))
      (setf (mail-status mail) "sending")
      (incf (mail-attempts mail))
      (save mail))))

(defun attempt-delivery (adapter mail)
  "Values the outcome and its detail of one call to ADAPTER for MAIL, within
+MAIL-TIME-LIMIT+ seconds."
  (let ((app *application*))
    (handler-case
        (multiple-value-bind (outcome detail)
            (call-with-time-limit (lambda () (with-application (app) (deliver-mail adapter mail)))
                                  +mail-time-limit+)
          (if (and (member outcome '(:sent :retry :failed)) (stringp detail))
              (values outcome detail)
              (values :retry (format nil "the adapter answered ~s ~s" outcome detail))))
      (deadline-exceeded ()
        (values :retry (format nil "no answer within ~d seconds" +mail-time-limit+)))
      (error (e)
        (values :retry (princ-to-string e))))))

(defun record-outcome (mail adapter outcome detail)
  "In a write transaction: store on MAIL what the attempt came to.  A
temporary failure leaves it queued for the job's next attempt, or failed
after the last."
  (let ((current (fetch 'mail (entity-id mail))))
    (setf (mail-provider current) (provider-name adapter))
    (ecase outcome
      (:sent
       (setf (mail-status current) "sent"
             (mail-provider-id current) detail
             (mail-sent-at current) (now)
             (mail-last-error current) nil))
      ((:retry :failed)
       (setf (mail-status current) (if (or (eq outcome :failed) (last-attempt-p)) "failed" "queued")
             (mail-last-error current) (subseq detail 0 (min 2000 (length detail))))))
    (save current)))

(define-condition mail-not-delivered (error)
  ((reason :initarg :reason :reader mail-not-delivered-reason))
  (:report (lambda (c s) (write-string (mail-not-delivered-reason c) s)))
  (:documentation "A temporary failure to deliver a mail: its job tries again."))

(define-job send-queued-mail ((mail-id :type (id mail) :required t))
    (:queue :mail :transaction nil :max-attempts 7 :backoff +mail-retry-delays+
     :unique (:keys (mail-id)))
  "Make one attempt to deliver the mail MAIL-ID through the application's
provider, with the mail's id as the idempotency key (spec/mail.md 3)."
  (let ((mail (with-transaction (:write) (start-attempt mail-id)))
        (adapter (or (application-mail *application*) (make-instance 'log-mail))))
    (when mail
      (multiple-value-bind (outcome detail) (attempt-delivery adapter mail)
        (with-transaction (:write)
          (record-outcome mail adapter outcome detail))
        (case outcome
          (:failed (fail-job detail))
          (:retry (error 'mail-not-delivered :reason detail)))))))

;;; ------------------------------------------------------------------
;;; Tools (spec/mail.md 5)

(defun mail->json (mail &key with-text)
  (let ((json (entity->json mail)))
    (unless with-text
      (remhash "text" json)
      (remhash "html" json))
    json))

(define-operation mail-list ((status :type (enum "queued" "sending" "sent" "failed")
                                     :label "Status")
                             (to :type (email :max 320) :label "Til"))
    (:entity mail :kind :read :policy :admin :title "E-post"
             :description "De siste 100 e-postene, nyeste først, uten tekst: mottaker, emne,
status, forsøk og siste feil. Kan begrenses til én status eller én mottaker.")
  (let ((conditions (remove nil (list (and status `(:= "status" ,status))
                                      (and to `(:= "to" ,to))))))
    (jobj "items" (jarr (mapcar #'mail->json
                                (select 'mail :where (and conditions `(:and ,@conditions))
                                        :order-by '(("seq" :desc)) :limit 100))))))

(define-operation mail-get ((id :type (id mail) :required t :label "E-post"))
    (:entity mail :kind :read :policy :admin :title "Les e-post"
             :description "Én e-post med tekst og HTML.")
  (mail->json (fetch! 'mail id) :with-text t))

(define-operation mail-retry ((id :type (id mail) :required t :label "E-post"))
    (:entity mail :kind :update :policy :admin :title "Send e-post på nytt"
             :description "Legger en e-post som feilet i køen igjen, med forsøkene nullstilt.
Den sendes straks.")
  (let ((mail (fetch! 'mail id)))
    (unless (equal (mail-status mail) "failed")
      (fail :invalid-transition "Bare en e-post som feilet kan sendes på nytt; denne er ~a"
            (mail-status mail)))
    (setf (mail-status mail) "queued"
          (mail-attempts mail) 0)
    (mail->json (queue-delivery mail))))
