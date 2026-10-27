;;;; tests/mail-tests.lisp -- sending mail (spec/mail.md): a mail stored in
;;;; the sender's write, delivery with retries through a scripted provider,
;;;; the tools, the provider an application names, and the Resend adapter
;;;; over real HTTP against a fake Resend in the test process.

(in-package #:tun.tests)

(def-suite mail :in core)
(in-suite mail)

;;; ------------------------------------------------------------------
;;; A provider that answers as the test says

(defclass scripted-mail (tun.mail:mail-adapter)
  ((outcomes :initarg :outcomes :initform nil :accessor scripted-outcomes
             :documentation "What the next calls answer, in order: (OUTCOME DETAIL), :ERROR
to signal, or :SILENT to answer too late.  Then (:SENT \"ok\").")
   (calls :initform nil :accessor scripted-calls
          :documentation "The id of the mail each call sent, newest first."))
  (:documentation "A mail provider whose answers the test chooses."))

(defmethod tun.mail:provider-name ((adapter scripted-mail)) "scripted")

(defmethod tun.mail:deliver-mail ((adapter scripted-mail) mail)
  (push (entity-id mail) (scripted-calls adapter))
  (let ((next (or (pop (scripted-outcomes adapter)) '(:sent "ok"))))
    (case next
      (:error (error "the connection to the provider broke"))
      (:silent (sleep 3) (values :sent "too late"))
      (t (values-list next)))))

(define-operation mail-test-send ((to :type string) (subject :type string) (text :type string)
                                  (html :type string) (reply-to :type string) (key :type string)
                                  (then-fail :type boolean))
    (:kind :update :policy :employee :title "Send e-post (test)")
  ;; A tree cannot travel as JSON: HTML is the text of a paragraph.
  (let ((mail (tun.mail:send-mail :to to :subject subject :text text :html (and html `(:p ,html))
                                  :reply-to reply-to :key key)))
    (when then-fail
      (fail :conflict "Arbeidet feilet etter at e-posten ble lagt i køen"))
    (jobj "id" (entity-id mail))))

(defmacro with-mail ((adapter &rest outcomes) &body body)
  "Run BODY in a fresh application whose mail provider is ADAPTER, a
SCRIPTED-MAIL answering OUTCOMES."
  `(let ((,adapter (make-instance 'scripted-mail :outcomes (list ,@outcomes))))
     (with-test-app (:mail ,adapter)
       ,@body)))

(defun queue-mail (&rest arguments)
  "The id of a mail Kari sends with ARGUMENTS, after a to, subject and text."
  (jget (apply #'call-ok "mail_test_send" "employee:kari"
               (append arguments '("to" "ola@example.no" "subject" "Hei" "text" "Hei, Ola.")))
        "id"))

(defun framed-html-p (markup html)
  "True when HTML is a mail's framed document holding MARKUP."
  (and (stringp html) (eql 0 (search "<!doctype html>" html)) (search markup html) t))

(defun mail-of (id)
  (call-ok "mail_get" "admin:ada" "id" id))

(defun mail-field (id field)
  (jget (mail-of id) field))

(defun deliver ()
  "Run the due delivery jobs now, as the worker does; how many attempts it made."
  (drain-jobs :queue "mail"))

(defun delivery-job (id)
  "The job that delivers the mail ID, as JSON."
  (call-ok "jobs_get" "admin:ada" "id" (mail-field id "job_id")))

(defun clock-at (time)
  (with-application (*app*) (set-test-clock (application-clock *app*) time)))

(defun clock-time ()
  (with-application (*app*) (now)))

;;; ------------------------------------------------------------------
;;; Sending (spec/mail.md 2)

(test a-mail-exists-only-when-its-write-commits
  (with-mail (provider)
    (let ((id (queue-mail "html" "Hei, Ola." "reply_to" "kari@example.no")))
      (let ((mail (mail-of id)))
        (is (equal "queued" (jget mail "status")))
        (is (equal "ola@example.no" (jget mail "to")))
        (is (equal "Hei" (jget mail "subject")))
        (is (equal "Hei, Ola." (jget mail "text")))
        (is (framed-html-p "<p>Hei, Ola.</p>" (jget mail "html")))
        (is (equal "kari@example.no" (jget mail "reply_to")))
        (is (= 0 (jget mail "attempts")))))
    (is (equal "conflict" (nth-value 1 (call "mail_test_send" "employee:kari" "to" "per@example.no"
                                             "subject" "Hei" "text" "Hei" "then_fail" t))))
    (is (zerop (length (jget (call-ok "mail_list" "admin:ada" "to" "per@example.no") "items")))
        "the failed work left no mail")
    (is (= 1 (deliver)))
    (is (null (rest (scripted-calls provider))) "and none was sent")))

(test a-mail-is-checked-as-its-fields-are
  (with-mail (provider)
    (flet ((refused (&rest arguments)
             (multiple-value-bind (json code) (apply #'call "mail_test_send" "employee:kari"
                                                     arguments)
               (and (equal code "invalid_input")
                    (map 'list (lambda (f) (jget f "field"))
                         (jget (jget json "error") "fields"))))))
      (is (equal '("to") (refused "to" "ola@example" "subject" "Hei" "text" "Hei")))
      (is (equal '("subject") (refused "to" "ola@example.no" "text" "Hei")))
      (is (equal '("text") (refused "to" "ola@example.no" "subject" "Hei" "text" "  ")))
      (is (equal '("reply_to") (refused "to" "ola@example.no" "subject" "Hei" "text" "Hei"
                                        "reply_to" "kari")))
      (is (equal '("subject") (refused "to" "ola@example.no" "text" "Hei"
                                       "subject" (make-string 999 :initial-element #\x)))))
    (is (zerop (length (jget (call-ok "mail_list" "admin:ada") "items"))))))

(test a-key-sends-a-mail-once
  (with-mail (provider)
    (let ((first (queue-mail "key" "svar:kom_1")))
      (is (equal first (queue-mail "key" "svar:kom_1")))
      (is (= 1 (deliver)))
      (is (equal first (queue-mail "key" "svar:kom_1")) "a sent mail keeps its key")
      (is (not (equal first (queue-mail "key" "svar:kom_2"))))
      (is (= 2 (length (jget (call-ok "mail_list" "admin:ada") "items")))))))

;;; ------------------------------------------------------------------
;;; Delivery (spec/mail.md 3)

(test delivery-records-what-the-provider-said
  (with-mail (provider '(:sent "p-1"))
    (let ((id (queue-mail)))
      (is (= 1 (deliver)))
      (is (= 0 (deliver)) "nothing is due")
      (let ((mail (mail-of id)))
        (is (equal "sent" (jget mail "status")))
        (is (equal "scripted" (jget mail "provider")))
        (is (equal "p-1" (jget mail "provider_id")))
        (is (= 1 (jget mail "attempts")))
        (is (equal "2026-03-01T09:00:00Z" (jget mail "sent_at"))))
      (is (equal (list id) (scripted-calls provider))))))

(test a-temporary-failure-waits-longer-each-time
  (with-mail (provider '(:retry "opptatt") '(:retry "opptatt") '(:retry "opptatt")
                       '(:retry "opptatt") '(:retry "opptatt") '(:retry "opptatt")
                       '(:retry "fortsatt opptatt"))
    (let ((id (queue-mail)))
      (dolist (delay tun.mail:+mail-retry-delays+)
        (is (= 1 (deliver)))
        (is (equal "queued" (mail-field id "status")))
        (is (equal "opptatt" (mail-field id "last_error")))
        (let ((due (+ (clock-time) delay)))
          (is (equal (format-rfc3339 due) (jget (delivery-job id) "due_at")))
          (clock-at (1- due))
          (is (= 0 (deliver)) "not before its time")
          (clock-at due)))
      (is (= 1 (deliver)) "the seventh attempt")
      (let ((mail (mail-of id)))
        (is (equal "failed" (jget mail "status")))
        (is (= 7 (jget mail "attempts")))
        (is (equal "fortsatt opptatt" (jget mail "last_error")))
        (is (json-null-p (jget mail "sent_at")))
        (is (equal "failed" (jget (delivery-job id) "state")) "and so is its job"))
      (clock-at (+ (clock-time) 86400))
      (is (= 0 (deliver)) "a failed mail stays failed")
      (call-ok "mail_retry" "admin:ada" "id" id)
      (is (equal "queued" (mail-field id "status")))
      (is (= 0 (mail-field id "attempts")))
      (is (= 1 (deliver)))
      (is (equal "sent" (mail-field id "status")))
      (is (json-null-p (mail-field id "last_error")))
      (is (= 8 (length (scripted-calls provider))))
      (is (every (lambda (call) (equal id call)) (scripted-calls provider))
          "every attempt sent the same idempotency key"))))

(test a-permanent-failure-fails-at-once
  (with-mail (provider '(:failed "ugyldig mottaker"))
    (let ((id (queue-mail)))
      (deliver)
      (is (equal "failed" (mail-field id "status")))
      (is (equal "ugyldig mottaker" (mail-field id "last_error")))
      (is (= 1 (mail-field id "attempts")))
      (is (equal "failed" (jget (delivery-job id) "state")) "no more attempts")
      (call-ok "mail_retry" "admin:ada" "id" id)
      (deliver)
      (is (equal "invalid_transition" (nth-value 1 (call "mail_retry" "admin:ada" "id" id)))
          "only a failed mail is retried"))))

(test an-error-or-silence-from-the-provider-is-temporary
  (with-mail (provider :error :silent '(:wrong "answer"))
    (let ((id (queue-mail)))
      (deliver)
      (is (equal "queued" (mail-field id "status")))
      (is (search "connection to the provider broke" (mail-field id "last_error")))
      (clock-at (+ (clock-time) 30))
      (let ((tun.mail:+mail-time-limit+ 1))
        (deliver))
      (is (equal "queued" (mail-field id "status")))
      (is (equal "no answer within 1 seconds" (mail-field id "last_error")))
      (clock-at (+ (clock-time) 120))
      (deliver)
      (is (equal "queued" (mail-field id "status")))
      (is (search "the adapter answered :WRONG" (mail-field id "last_error")))
      (is (= 3 (mail-field id "attempts"))))))

(test a-mail-whose-process-died-mid-send-is-sent-by-another
  (with-mail (provider)
    (let ((id (queue-mail)))
      ;; As a process that has since gone left it: sending, its job running.
      (with-application (*app*)
        (with-transaction (:write)
          (let ((mail (fetch 'tun.mail:mail id))
                (job (fetch 'tun.jobs:job (mail-field id "job_id"))))
            (setf (tun.mail:mail-status mail) "sending"
                  (tun.jobs:job-state job) "running"
                  (tun.jobs:job-claimed-by job) "jpr_gone"
                  (tun.jobs:job-attempts job) 1)
            (save mail)
            (save job))))
      (is (= 0 (deliver)) "a running job is not claimed again")
      (with-application (*app*) (tun.jobs:rescue-orphaned-jobs))
      (is (= 1 (deliver)) "the job is retried")
      (is (equal "sent" (mail-field id "status")))
      (is (equal (list id) (scripted-calls provider)) "with the mail's id as its key"))))

(test the-scheduler-delivers-mail-in-the-mail-queue
  (let ((provider (make-instance 'scripted-mail)))
    (with-test-app (:test-clock nil :mail provider)
      (let ((ids (list (queue-mail) (queue-mail "key" "to"))))
        (is (equal "mail" (jget (delivery-job (first ids)) "queue")))
        (tun.jobs:tend-jobs *app*)
        (wait-for-workers *app*)
        (is (equal '("sent" "sent") (mapcar (lambda (id) (mail-field id "status")) ids)))
        (is (= 2 (length (scripted-calls provider))))))))

(test clock-set-delivers-due-mail
  (with-test-app ()
    (is (typep (application-mail *app*) 'tun.mail:log-mail)
        "an application that names no provider logs mail")
    (let ((id (queue-mail)))
      (is (= 1 (jget (call-ok "clock_set" "admin:ada" "now" "2026-03-01T09:00:01Z")
                     "job_attempts")))
      (is (equal "sent" (mail-field id "status")))
      (is (equal "log" (mail-field id "provider")))
      (is (= 0 (jget (call-ok "clock_set" "admin:ada" "now" "2026-03-01T09:00:02Z")
                     "job_attempts"))))))

(test mail-is-stored-and-found-on-postgres
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (let ((provider (make-instance 'scripted-mail :outcomes (list '(:retry "opptatt")))))
        (with-test-app (:db (scratch-postgres "mail") :mail provider)
          (let ((id (queue-mail "key" "en" "reply_to" "kari@example.no")))
            (is (equal id (queue-mail "key" "en")))
            (deliver)
            (is (equal "queued" (mail-field id "status")))
            (clock-at (+ (clock-time) 30))
            (deliver)
            (is (equal "sent" (mail-field id "status")))
            (is (equal (list id)
                       (map 'list (lambda (m) (jget m "id"))
                            (jget (call-ok "mail_list" "admin:ada" "to" "ola@example.no"
                                           "status" "sent")
                                  "items")))))))))

;;; ------------------------------------------------------------------
;;; Tools (spec/mail.md 5)

(test only-admins-read-and-retry-mail
  (with-mail (provider)
    (let ((first (queue-mail "html" "Hei")))
      (deliver)
      (let ((second (jget (call-ok "mail_test_send" "employee:kari" "to" "per@example.no"
                                   "subject" "Hallo" "text" "Hallo, Per.")
                          "id")))
        (dolist (tool '("mail_list" "mail_get" "mail_retry"))
          (is (equal "forbidden" (nth-value 1 (call tool "employee:kari" "id" first)))
              "~a is for admins" tool))
        (let ((items (coerce (jget (call-ok "mail_list" "admin:ada") "items") 'list)))
          (is (equal (list second first) (mapcar (lambda (m) (jget m "id")) items))
              "newest first")
          (is (notany (lambda (m) (or (nth-value 1 (gethash "text" m))
                                      (nth-value 1 (gethash "html" m))))
                      items)
              "without the text"))
        (flet ((ids (&rest filter)
                 (map 'list (lambda (m) (jget m "id"))
                      (jget (apply #'call-ok "mail_list" "admin:ada" filter) "items"))))
          (is (equal (list first) (ids "status" "sent")))
          (is (equal (list second) (ids "status" "queued")))
          (is (equal (list second) (ids "to" "per@example.no"))))
        (is (framed-html-p "<p>Hei</p>" (mail-field first "html")))))))

;;; ------------------------------------------------------------------
;;; The provider an application names (spec/mail.md 1)

(define-application resend-application ()
  (:mail (:resend :api-key "re_test_key" :from "Saker <varsel@example.no>")))

(define-application unset-mail-application ()
  (:mail (:resend :api-key (:env "TUN_TEST_MAIL_UNSET") :from "Saker <varsel@example.no>")))

(test the-provider-comes-from-the-application
  (is (null (uiop:getenv "TUN_TEST_MAIL_UNSET")))
  (flet ((problems (spec) (nth-value 1 (tun.mail:make-mail-adapter spec))))
    (is (null (problems nil)))
    (is (typep (tun.mail:make-mail-adapter nil) 'tun.mail:log-mail))
    (is (typep (tun.mail:make-mail-adapter '(:log)) 'tun.mail:log-mail))
    (is (equal '("resend :api-key needs the environment variable TUN_TEST_MAIL_UNSET")
               (tun.mail:mail-problems 'unset-mail-application)))
    (is (equal '("resend needs :from") (problems '(:resend :api-key "k"))))
    (is (search ":smtp is not a mail provider; there are :resend, :log"
                (first (problems '(:smtp)))))
    (is (search "resend:" (first (problems '(:resend :api-key "k" :from "a@b.no" :port "25"))))
        "an unknown setting"))
  (is (null (tun.mail:mail-problems 'resend-application)))
  (with-test-app (:class 'resend-application)
    (let ((adapter (application-mail *app*)))
      (is (typep adapter 'tun.mail:resend-mail))
      (is (equal "Saker <varsel@example.no>" (tun.mail:resend-from adapter)))
      (is (equal "https://api.resend.com/emails" (tun.mail:resend-endpoint adapter)))
      (is (not (search "re_test_key" (prin1-to-string adapter)))
          "a printed adapter hides its key")))
  (with-test-app (:class 'unset-mail-application)
    (is (typep (application-mail *app*) 'tun.mail:log-mail) "an in-process application logs"))
  (signals error (macroexpand-1 '(define-application broken-mail () (:mail :resend)))))

;;; ------------------------------------------------------------------
;;; Resend over HTTP (spec/mail.md 4)

(defclass fake-resend (hunchentoot:acceptor)
  ((answers :initform nil :accessor resend-answers
            :documentation "The next answers, in order: (STATUS JSON-OBJECT).  Then 200
with a fresh id.")
   (requests :initform nil :accessor resend-requests
             :documentation "Each request as a plist (:authorization :idempotency-key
:content-type :body), newest first."))
  (:default-initargs :address "127.0.0.1" :access-log-destination nil
                     :message-log-destination nil))

(defmethod hunchentoot:acceptor-dispatch-request ((resend fake-resend) request)
  (push (list :path (hunchentoot:script-name request)
              :authorization (hunchentoot:header-in* :authorization)
              :idempotency-key (hunchentoot:header-in* :idempotency-key)
              :content-type (hunchentoot:header-in* :content-type)
              :body (parse-json (hunchentoot:raw-post-data :force-text t
                                                           :external-format :utf-8)))
        (resend-requests resend))
  (destructuring-bind (status json)
      (or (pop (resend-answers resend))
          (list 200 (jobj "id" (format nil "re-~d" (length (resend-requests resend))))))
    (setf (hunchentoot:return-code*) status
          (hunchentoot:content-type*) "application/json")
    (to-json-string json)))

(defun resend-error (status name message)
  (list status (jobj "statusCode" status "name" name "message" message)))

(defmacro with-fake-resend ((resend) &body body)
  "Run BODY in a fresh application that sends through Resend's adapter to
RESEND, a fake Resend serving on a free port."
  (let ((port (gensym "PORT")))
    `(let* ((,port (free-port))
            (,resend (make-instance 'fake-resend :port ,port)))
       (hunchentoot:start ,resend)
       (unwind-protect
            (with-test-app (:mail (make-instance 'tun.mail:resend-mail
                                                 :api-key "re_test_key"
                                                 :from "Saker <varsel@example.no>"
                                                 :endpoint (format nil "http://127.0.0.1:~d/emails"
                                                                   ,port)))
              ,@body)
         (hunchentoot:stop ,resend)))))

(test resend-receives-the-mail-with-its-key
  (with-fake-resend (resend)
    (let ((id (queue-mail "html" "Hei, Ola." "reply_to" "kari@example.no")))
      (is (= 1 (deliver)))
      (let ((mail (mail-of id))
            (request (first (resend-requests resend))))
        (is (equal "sent" (jget mail "status")))
        (is (equal "resend" (jget mail "provider")))
        (is (equal "re-1" (jget mail "provider_id")))
        (is (equal "/emails" (getf request :path)))
        (is (equal "Bearer re_test_key" (getf request :authorization)))
        (is (equal id (getf request :idempotency-key)))
        (is (search "application/json" (getf request :content-type)))
        (let ((body (getf request :body)))
          (is (equal "Saker <varsel@example.no>" (jget body "from")))
          (is (equalp #("ola@example.no") (jget body "to")))
          (is (equal "Hei" (jget body "subject")))
          (is (equal "Hei, Ola." (jget body "text")))
          (is (framed-html-p "<p>Hei, Ola.</p>" (jget body "html")))
          (is (equal "kari@example.no" (jget body "reply_to"))))))
    (queue-mail "key" "uten-html")
    (deliver)
    (let ((body (getf (first (resend-requests resend)) :body)))
      (is (not (nth-value 1 (gethash "html" body))) "no html when the mail has none")
      (is (not (nth-value 1 (gethash "reply_to" body)))))))

(test resend-answers-decide-what-happens-next
  (with-fake-resend (resend)
    (setf (resend-answers resend)
          (list (resend-error 429 "rate_limit_exceeded" "Too many requests")
                (resend-error 500 "application_error" "Something went wrong")
                (resend-error 422 "validation_error" "Invalid `to` field")))
    (let ((id (queue-mail)))
      (deliver)
      (is (equal "queued" (mail-field id "status")))
      (is (equal "resend 429 rate_limit_exceeded: Too many requests" (mail-field id "last_error")))
      (clock-at (+ (clock-time) 30))
      (deliver)
      (is (equal "queued" (mail-field id "status")))
      (is (equal "resend 500 application_error: Something went wrong"
                 (mail-field id "last_error")))
      (clock-at (+ (clock-time) 120))
      (deliver)
      (is (equal "failed" (mail-field id "status")))
      (is (equal "resend 422 validation_error: Invalid `to` field" (mail-field id "last_error")))
      (is (= 3 (length (resend-requests resend))))
      (is (every (lambda (r) (equal id (getf r :idempotency-key))) (resend-requests resend))
          "each attempt with the same idempotency key"))))

(test resend-outcomes
  (flet ((outcome (status json)
           (multiple-value-list (tun.mail::resend-outcome status (to-json-string json)))))
    (is (equal '(:sent "abc") (outcome 200 (jobj "id" "abc"))))
    (is (eq :retry (first (outcome 200 (jobj)))) "an answer without an id is retried")
    (is (eq :retry (first (outcome 409 (jobj "name" "concurrent_idempotent_requests")))))
    (is (eq :failed (first (outcome 409 (jobj "name" "invalid_idempotent_request")))))
    (is (eq :retry (first (outcome 503 (jobj "name" "service_unavailable")))))
    (is (eq :failed (first (outcome 403 (jobj "name" "validation_error")))))
    (is (eq :failed (first (outcome 401 (jobj "name" "missing_api_key"))))))
  (is (equal '(:retry "resend 502") (multiple-value-list
                                     (tun.mail::resend-outcome 502 "<html>Bad gateway</html>")))))

(test an-unreachable-resend-is-temporary
  (with-test-app (:mail (make-instance 'tun.mail:resend-mail
                                       :api-key "re_test_key" :from "varsel@example.no"
                                       :endpoint (format nil "http://127.0.0.1:~d/emails"
                                                         (free-port))))
    (let ((id (queue-mail)))
      (deliver)
      (is (equal "queued" (mail-field id "status")))
      (is (not (search "re_test_key" (mail-field id "last_error")))))))
