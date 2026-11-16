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
;;;; A mail's attachments are copies of its own, made when it is queued and
;;;; kept until it is sent, so what it carries does not change with the
;;;; files it was made from (spec/mail.md 2.2).
;;;;
;;;; An adapter is a class with one method, DELIVER-MAIL.  This file has the
;;;; log adapter, which sends nothing; resend.lisp has Resend's.  html.lisp
;;;; makes a mail's HTML and text parts from a node tree.

(defpackage #:tun.mail
  (:use #:cl #:tun.core)
  (:import-from #:tun.jobs #:define-job #:enqueue-job #:fail-job #:last-attempt-p)
  (:import-from #:tun.html #:render-html #:trusted #:node-parts)
  (:import-from #:tun.files #:servable-attachment #:stored-file-octets #:checked-upload
                #:attachment-filename #:attachment-content-type #:attachment-size
                #:attachment-sha256 #:upload-filename #:upload-content-type #:upload-octets
                #:upload-sha256 #:make-upload #:given-file-p #:given-upload)
  (:export #:mail #:mail-to #:mail-subject #:mail-text #:mail-html #:mail-reply-to #:mail-key
           #:mail-status #:mail-attempts #:mail-job-id #:mail-last-error
           #:mail-provider #:mail-provider-id #:mail-created-at #:mail-sent-at
           #:send-mail #:render-mail #:+mail-retry-delays+ #:+mail-time-limit+
           #:mail-attachment #:mail-attachment-mail-id #:mail-attachment-filename
           #:mail-attachment-content-type #:mail-attachment-size #:mail-attachment-sha256
           #:mail-attachment-file-id #:mail-attachment-kept #:mail-attachments
           #:mail-file #:make-mail-file #:mail-file-filename #:mail-file-content-type
           #:mail-file-octets #:+most-mail-files+ #:+most-mail-octets+
           #:mail-adapter #:deliver-mail #:provider-name #:log-mail
           #:resend-mail #:resend-endpoint #:resend-from
           #:make-mail-adapter #:mail-problems #:send-queued-mail
           #:mail-list #:mail-get #:mail-retry
           ;; The node grammar's checks and the text made from a tree, which
           ;; a PDF's document shares (spec/pdf.md 2.1)
           #:proper-list-p #:shown #:scheme-p #:+style-value+ #:+mail-style-properties+
           #:tree-text))

(in-package #:tun.mail)

(declaim (optimize (safety 3) (debug 2)))

(define-entity mail (:label "Email" :id-prefix "mail" :table "mails" :internal t
                            :indexes (("status") ("key") ("to")))
  ((to :type (email :max 320) :required t :input nil :label "To")
   (subject :type (string :min 1 :max 998) :required t :input nil :label "Subject")
   (text :type (string :min 1 :max 100000) :required t :input nil :label "Text")
   (html :type (string :max 500000) :input nil :label "HTML")
   (reply-to :type (email :max 320) :input nil :label "Reply to")
   (key :type (string :max 200) :input nil :label "Key"
        :description "Makes the send once only: a second send with the key returns the first mail.")
   (status :type (enum "queued" "sending" "sent" "failed") :input nil :initform "queued"
           :label "Status")
   (attempts :type integer :input nil :initform 0 :label "Attempts")
   (job-id :type id :input nil :label "Job"
           :description "The job that delivers it; jobs_get shows when it tries next.")
   (last-error :type (string :max 2000) :input nil :label "Last error")
   (provider :type (string :max 64) :input nil :label "Provider")
   (provider-id :type (string :max 200) :input nil :label "Provider's ID")
   (created-at :type timestamp :input nil :label "Created")
   (sent-at :type timestamp :input nil :label "Sent")))

(define-entity mail-attachment (:label "Email attachment" :id-prefix "mat" :table "mail_attachments"
                                       :internal t :indexes (("mail_id")))
  ((mail-id :type (string :min 1 :max 64) :required t :input nil :label "Email")
   (filename :type (string :min 1 :max 255) :required t :input nil :label "Filename")
   (content-type :type (string :min 1 :max 40) :required t :input nil :label "Type")
   (size :type integer :required t :input nil :label "Size")
   (sha256 :type (string :max 64) :required t :input nil :label "SHA-256")
   (file-id :type (string :max 64) :input nil :label "File"
            :description "The stored file it was copied from; NIL for bytes the sender gave.")
   (kept :type boolean :input nil :initform t :label "Kept"
         :description "Whether its bytes are still stored: until the mail is sent.")))

(defparameter +most-mail-files+ 10 "The most files one mail carries.")

(defparameter +most-mail-octets+ (* 10 1024 1024)
  "The most octets a mail's files have together, as stored: about 13.4 MB
in base64, which most mail servers take.")

(defstruct mail-file
  "A file of a mail as its provider is given it."
  filename content-type octets)

;;; ------------------------------------------------------------------
;;; Sending

(defun mail-argument (name value &key required)
  "VALUE checked as the mail's field NAME checks its input, or NIL; an
error is collected for COLLECTING-INPUT-ERRORS."
  (if (null value)
      (when required (input-error name "must be filled in"))
      (coerce-input (field-type (find-field (find-class 'mail) name)) value name)))

(defun send-mail (&key to subject text html reply-to key attachments)
  "Queue a mail to TO, inside the current write, and return it: it is sent
after the write commits, and never when it rolls back (spec/mail.md 2).
HTML is a node tree, rendered as RENDER-MAIL renders it; without TEXT, the
text part is made from it.  ATTACHMENTS is a list of files (2.2): a stored
file's id, an attachment object, or (:FILENAME NAME :CONTENT OCTETS); the
mail keeps a copy of each.  When a mail with KEY exists, return that one
and store nothing.  A bad argument fails the operation with invalid_input,
a stored file the caller may not see with not_found."
  (destructuring-bind (mail . files)
      (collecting-input-errors
       (let ((to (mail-argument "to" to :required t))
             (subject (mail-argument "subject" subject :required t)))
         (multiple-value-bind (html-part text-part) (checked-parts html subject text)
           (cons (make-instance 'mail :to to :subject subject :text text-part :html html-part
                                      :reply-to (mail-argument "reply_to" reply-to)
                                      :key (mail-argument "key" key))
                 (mail-attachment-files attachments)))))
    (or (and (mail-key mail)
             (select-one 'mail :where `(:= "key" ,(mail-key mail))))
        (progn
          (setf (mail-created-at mail) (now))
          (insert mail)
          (dolist (file files)
            (store-mail-attachment mail file))
          (queue-delivery mail)))))

;;; ------------------------------------------------------------------
;;; Attachments (spec/mail.md 2.2)

(defun mail-attachment-files (attachments)
  "ATTACHMENTS, send-mail's, as (UPLOAD . FILE-ID) in order, each read and
checked; input errors for what cannot be sent are collected."
  (let ((items (if (typep attachments 'sequence) (coerce attachments 'list) :invalid)))
    (cond ((eq items :invalid)
           (input-error "attachments" "must be a list of files"))
          ((> (length items) +most-mail-files+)
           (input-error "attachments" "A mail can carry at most ~d files." +most-mail-files+))
          (t (let ((files (loop for item in items
                                for i from 0
                                for file = (mail-attachment-file item (format nil "attachments[~d]" i))
                                when file collect file)))
               (when (> (reduce #'+ files :key (lambda (file) (length (upload-octets (car file)))))
                        +most-mail-octets+)
                 (input-error "attachments" "A mail's files can be at most 10 MB together."))
               files)))))

(defun mail-attachment-file (item path)
  "ITEM, one of send-mail's attachments, as (UPLOAD . FILE-ID): a stored
file read as the caller, or bytes checked as an uploaded file.  NIL with an
input error at PATH when it cannot be sent."
  (cond ((given-file-p item)
         (let ((upload (given-upload item path)))
           (and upload (cons upload nil))))
        ((or (stringp item) (and (hash-table-p item) (stringp (jget item "id"))))
         (stored-mail-file (if (stringp item) item (jget item "id"))))
        (t (input-error path "must be a file's id, an attachment object or (:filename NAME :content OCTETS)"))))

(defun stored-mail-file (id)
  "The stored file ID, as (UPLOAD . ID), read as GET /files/ID serves it to
the caller; not_found when they may not see it or it is gone."
  (let* ((attachment (servable-attachment id))
         (octets (and attachment (stored-file-octets id (attachment-size attachment)))))
    (unless octets
      (fail :not-found "Could not find the file ~a" id))
    (cons (make-upload :filename (attachment-filename attachment)
                       :content-type (attachment-content-type attachment)
                       :octets octets
                       :sha256 (attachment-sha256 attachment))
          id)))

(defun store-mail-attachment (mail file)
  "Store FILE, (UPLOAD . FILE-ID), as MAIL's own copy, in the current write."
  (destructuring-bind (upload . file-id) file
    (let ((attachment (make-instance 'mail-attachment
                                     :mail-id (entity-id mail)
                                     :filename (upload-filename upload)
                                     :content-type (upload-content-type upload)
                                     :size (length (upload-octets upload))
                                     :sha256 (upload-sha256 upload)
                                     :file-id file-id
                                     :kept t)))
      (setf (entity-id attachment) (concatenate 'string "mat_" (random-token-string 26)))
      (insert attachment)
      (store-write-content *store* (entity-id attachment) (upload-octets upload)))))

(defun mail-attachments (mail-ids)
  "The attachments of the mails MAIL-IDS, in each mail's order."
  (and mail-ids
       (select 'mail-attachment :where `(:in "mail_id" ,mail-ids) :order-by '(("seq" :asc)))))

(defun mail-files (mail-id)
  "In a transaction: the files of the mail MAIL-ID with their bytes, in
order.  NIL and the name of the first one whose bytes are gone, when one is."
  (let ((files '()))
    (dolist (attachment (mail-attachments (list mail-id)) (values (nreverse files) nil))
      (let ((octets (and (mail-attachment-kept attachment)
                         (stored-file-octets (entity-id attachment) (mail-attachment-size attachment)))))
        (unless octets
          (return (values nil (mail-attachment-filename attachment))))
        (push (make-mail-file :filename (mail-attachment-filename attachment)
                              :content-type (mail-attachment-content-type attachment)
                              :octets octets)
              files)))))

(defun drop-sent-files (mail-id)
  "In a write: delete the bytes of the sent mail MAIL-ID's attachments,
keeping what they were."
  (dolist (attachment (mail-attachments (list mail-id)))
    (when (mail-attachment-kept attachment)
      (store-delete-content *store* (entity-id attachment))
      (setf (mail-attachment-kept attachment) nil)
      (save attachment))))

;;; ------------------------------------------------------------------
;;; Adapters

(defclass mail-adapter () ()
  (:documentation "A mail provider.  A subclass has a DELIVER-MAIL method and a
PROVIDER-NAME."))

(defgeneric deliver-mail (adapter mail files)
  (:documentation "Send MAIL through ADAPTER's provider, with (ENTITY-ID MAIL) as
the idempotency key, carrying FILES, its attachments as MAIL-FILEs in order.
Values :SENT and the provider's id for the mail, or :RETRY or :FAILED and a
reason.  An error it signals counts as :RETRY."))

(defgeneric provider-name (adapter)
  (:documentation "The provider's name in a mail's provider field, such as \"resend\"."))

(defclass log-mail (mail-adapter) ()
  (:documentation "Sends nothing: accepts each mail and writes its recipient and
subject, not its text, to standard output (spec/mail.md 1)."))

(defmethod provider-name ((adapter log-mail)) "log")

(defmethod deliver-mail ((adapter log-mail) mail files)
  (unless (test-mode-p)
    (format t "~&tun: mail ~a to ~a, not sent (no mail provider): ~a~@[, ~d files~]~%"
            (entity-id mail) (mail-to mail) (mail-subject mail) (and files (length files)))
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

(defun attempt-delivery (adapter mail files)
  "Values the outcome and its detail of one call to ADAPTER for MAIL with
FILES, within +MAIL-TIME-LIMIT+ seconds."
  (let ((app *application*))
    (handler-case
        (multiple-value-bind (outcome detail)
            (call-with-time-limit (lambda () (with-application (app) (deliver-mail adapter mail files)))
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
             (mail-last-error current) nil)
       (drop-sent-files (entity-id current)))
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
      (multiple-value-bind (outcome detail)
          (multiple-value-bind (files missing) (with-transaction (:read) (mail-files mail-id))
            (if missing
                ;; Never sent without one of its files (spec/mail.md 3).
                (values :failed (format nil "the attachment ~a is no longer stored" missing))
                (attempt-delivery adapter mail files)))
        (with-transaction (:write)
          (record-outcome mail adapter outcome detail))
        (case outcome
          (:failed (fail-job detail))
          (:retry (error 'mail-not-delivered :reason detail)))))))

;;; ------------------------------------------------------------------
;;; Tools (spec/mail.md 5)

(defun mail-attachment-json (attachment)
  "A mail's ATTACHMENT as the tools give it: what it is, never its bytes."
  (jobj "id" (entity-id attachment)
        "filename" (mail-attachment-filename attachment)
        "content_type" (mail-attachment-content-type attachment)
        "size" (mail-attachment-size attachment)
        "sha256" (mail-attachment-sha256 attachment)
        "file_id" (or (mail-attachment-file-id attachment) :null)
        "kept" (and (mail-attachment-kept attachment) t)))

(defun mails->json (mails &key with-text)
  "MAILS as the tools give them, each with its attachments, read in one query."
  (let ((attachments (make-hash-table :test 'equal)))
    (dolist (attachment (mail-attachments (mapcar #'entity-id mails)))
      (push (mail-attachment-json attachment)
            (gethash (mail-attachment-mail-id attachment) attachments)))
    (mapcar (lambda (mail)
              (let ((json (entity->json mail)))
                (unless with-text
                  (remhash "text" json)
                  (remhash "html" json))
                (setf (gethash "attachments" json)
                      (jarr (reverse (gethash (entity-id mail) attachments))))
                json))
            mails)))

(defun mail->json (mail &key with-text)
  (first (mails->json (list mail) :with-text with-text)))

(define-operation mail-list ((status :type (enum "queued" "sending" "sent" "failed")
                                     :label "Status")
                             (to :type (email :max 320) :label "To"))
    (:entity mail :kind :read :policy :admin :title "Email"
             :description "The last 100 mails, newest first, without their text: recipient,
subject, status, attempts, last error and attachments (name, type and size). Can be limited to
one status or one recipient.")
  (let ((conditions (remove nil (list (and status `(:= "status" ,status))
                                      (and to `(:= "to" ,to))))))
    (jobj "items" (jarr (mails->json (select 'mail :where (and conditions `(:and ,@conditions))
                                             :order-by '(("seq" :desc)) :limit 100))))))

(define-operation mail-get ((id :type (id mail) :required t :label "Email"))
    (:entity mail :kind :read :policy :admin :title "Read an email"
             :description "One mail with its text, HTML and attachments: each file's name, type,
size and SHA-256, never its bytes.")
  (mail->json (fetch! 'mail id) :with-text t))

(define-operation mail-retry ((id :type (id mail) :required t :label "Email"))
    (:entity mail :kind :update :policy :admin :title "Send an email again"
             :description "Queues a mail that failed again, with its attempts set to zero. It
is sent at once, with the copies of its files it was queued with.")
  (let ((mail (fetch! 'mail id)))
    (unless (equal (mail-status mail) "failed")
      (fail :invalid-transition "Only an email that failed can be sent again; this one is ~a"
            (label "mail" "status" (mail-status mail))))
    (setf (mail-status mail) "queued"
          (mail-attempts mail) 0)
    (mail->json (queue-delivery mail))))
