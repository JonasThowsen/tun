;;;; core/conditions.lisp -- the domain error vocabulary.
;;;;
;;;; Every failure an operation can report is an OPERATION-ERROR with one of
;;;; the codes in ERROR-CODE.  FAIL is declaimed with that type, so a
;;;; misspelled literal code is a compile-time warning, which bin/test turns
;;;; into a failure.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(deftype error-code ()
  '(member :forbidden :invalid-input :not-found :conflict :invalid-transition
    :unavailable :insufficient-stock :confirmation-invalid :idempotency-conflict
    :deadline-exceeded :read-only))

(define-condition operation-error (error)
  ((code :initarg :code :reader operation-error-code :type error-code)
   (message :initarg :message :reader operation-error-message :type string)
   (fields :initarg :fields :initform nil :reader operation-error-fields
           :documentation "List of (json-field-path . message) for invalid_input.")
   (details :initarg :details :initform nil :reader operation-error-details
            :documentation "Extra JSON object entries (plist of string keys and values)."))
  (:report (lambda (c s)
             (format s "~a: ~a" (json-name-of (operation-error-code c)) (operation-error-message c)))))

(declaim (ftype (function (error-code string &rest t) nil) fail))
(defun fail (code control &rest args)
  "Signal an OPERATION-ERROR with CODE and a Norwegian message."
  (error 'operation-error :code code :message (apply #'format nil control args)))

(defun fail-with-details (code details control &rest args)
  (declare (type error-code code))
  (error 'operation-error :code code :details details :message (apply #'format nil control args)))

(defun fail-fields (field-errors)
  "Signal invalid_input for FIELD-ERRORS, a list of (path . message)."
  (error 'operation-error
         :code :invalid-input
         :fields field-errors
         :message (format nil "Ugyldig input: ~{~a~^; ~}"
                          (mapcar (lambda (fe) (format nil "~a: ~a" (car fe) (cdr fe))) field-errors))))

(defun operation-error-json (condition)
  "The {\"error\":{...}} document for CONDITION."
  (let ((err (jobj "code" (json-name-of (operation-error-code condition))
                   "message" (operation-error-message condition))))
    (when (operation-error-fields condition)
      (setf (gethash "fields" err)
            (jarr (mapcar (lambda (fe) (jobj "field" (car fe) "message" (cdr fe)))
                          (operation-error-fields condition)))))
    (loop for (k v) on (operation-error-details condition) by #'cddr
          do (setf (gethash k err) v))
    (jobj "error" err)))

(defun error-status (code)
  "The HTTP status an operation error with CODE answers with, on a page and
on the HTTP API (spec/api.md 3)."
  (case code
    (:forbidden 403)
    (:not-found 404)
    ((:conflict :idempotency-conflict :invalid-transition :unavailable :insufficient-stock) 409)
    (t 422)))

;;; Raised by the transport when the actor header is missing or malformed.
(define-condition actor-error (error)
  ((message :initarg :message :reader actor-error-message))
  (:report (lambda (c s) (write-string (actor-error-message c) s))))

;;; Raised when a client extension breaks a core invariant at load/start time.
(define-condition extension-error (error)
  ((message :initarg :message :reader extension-error-message))
  (:report (lambda (c s) (write-string (extension-error-message c) s))))

(defun extension-error (control &rest args)
  (error 'extension-error :message (apply #'format nil control args)))
