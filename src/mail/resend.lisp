;;;; mail/resend.lisp -- the Resend adapter (spec/mail.md 4).
;;;;
;;;; One POST per attempt to Resend's emails endpoint.  Resend answers 200
;;;; with the email's id, or an error whose status and name say whether
;;;; trying again can help: a rate limit, a request with the same
;;;; idempotency key still in progress, or Resend's own failure can; a
;;;; refused address, sender or key cannot.

(in-package #:tun.mail)

(declaim (optimize (safety 3) (debug 2)))

(defclass resend-mail (mail-adapter)
  ((api-key :initarg :api-key :reader resend-api-key)
   (from :initarg :from :reader resend-from
         :documentation "The sender, such as \"Saker <varsel@example.no>\", at a domain
verified in Resend.")
   (endpoint :initarg :endpoint :initform "https://api.resend.com/emails"
             :reader resend-endpoint
             :documentation "Where mail is posted; a test points it at a fake Resend."))
  (:documentation "Sends mail through Resend's HTTP API."))

(defmethod print-object ((adapter resend-mail) stream)
  ;; Never the API key: an adapter may end up in a log line or a backtrace.
  (print-unreadable-object (adapter stream :type t)
    (format stream "from ~s" (resend-from adapter))))

(defmethod provider-name ((adapter resend-mail)) "resend")

(defun resend-body (adapter mail)
  "The JSON body of the request that sends MAIL."
  (let ((json (jobj "from" (resend-from adapter)
                    "to" (jarr (list (mail-to mail)))
                    "subject" (mail-subject mail)
                    "text" (mail-text mail))))
    (when (mail-html mail)
      (setf (gethash "html" json) (mail-html mail)))
    (when (mail-reply-to mail)
      (setf (gethash "reply_to" json) (mail-reply-to mail)))
    json))

(defun temporary-answer-p (status name)
  "True when Resend's answer STATUS, with the error NAME, may succeed later."
  (or (= status 429)
      (>= status 500)
      (and (= status 409) (equal name "concurrent_idempotent_requests"))))

(defun resend-outcome (status body)
  "What Resend's answer, STATUS with BODY, means for the mail: values :SENT
and the email's id, or :RETRY or :FAILED and a reason."
  (let* ((json (handler-case (parse-json body)
                 (error () nil)))
         (object (and (hash-table-p json) json)))
    (flet ((text (key)
             (let ((value (and object (jget object key))))
               (and (stringp value) (plusp (length value)) value))))
      (if (and (= status 200) (text "id"))
          (values :sent (text "id"))
          (values (if (or (= status 200) (temporary-answer-p status (text "name")))
                      :retry
                      :failed)
                  (format nil "resend ~d~@[ ~a~]~@[: ~a~]" status (text "name")
                          (if (= status 200) "answered without an id" (text "message"))))))))

(defmethod deliver-mail ((adapter resend-mail) mail)
  (multiple-value-bind (body status)
      (drakma:http-request (resend-endpoint adapter)
                           :method :post
                           :content-type "application/json"
                           :content (to-json-string (resend-body adapter mail))
                           :additional-headers
                           `(("Authorization" . ,(format nil "Bearer ~a" (resend-api-key adapter)))
                             ("Idempotency-Key" . ,(entity-id mail))
                             ("Accept" . "application/json"))
                           :external-format-out :utf-8
                           :force-binary t :redirect nil
                           :verify :required :connection-timeout +mail-time-limit+)
    (resend-outcome status (if body (sb-ext:octets-to-string body :external-format :utf-8) ""))))
