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
   (message :initarg :message :type (or string text)
            :documentation "The message: a string, or a TEXT written in the language of
the place it is shown (spec/i18n.md 3.1).")
   (fields :initarg :fields :initform nil :reader operation-error-fields
           :documentation "List of (json-field-path . message) for invalid_input; each
message a string or a TEXT.")
   (details :initarg :details :initform nil :reader operation-error-details
            :documentation "Extra JSON object entries (plist of string keys and values)."))
  (:report (lambda (c s)
             (format s "~a: ~a" (json-name-of (operation-error-code c)) (operation-error-message c)))))

(defun operation-error-message (condition)
  "CONDITION's message, written in the current language."
  (render-text (slot-value condition 'message)))

(defun operation-error-text (condition)
  "CONDITION's message as it was given, a string or a TEXT, for a refusal
that passes it on to be written where it is shown."
  (slot-value condition 'message))

(declaim (ftype (function (error-code string &rest t) nil) fail))
(defun fail (code control &rest args)
  "Signal an OPERATION-ERROR with CODE and the message CONTROL formatted with
ARGS, written in the language of the place it is shown (spec/i18n.md 3.1)."
  (error 'operation-error :code code :message (make-text control args)))

(defun fail-with-details (code details control &rest args)
  (declare (type error-code code))
  (error 'operation-error :code code :details details :message (make-text control args)))

(defparameter +invalid-input-text+ "Invalid input: ~{~a: ~a~^; ~}"
  "The message of a refusal for its fields' errors.")

(note-text +invalid-input-text+ nil "core" "conditions.lisp")

(defun fail-fields (field-errors)
  "Signal invalid_input for FIELD-ERRORS, a list of (path . message)."
  (error 'operation-error
         :code :invalid-input
         :fields field-errors
         :message (make-text +invalid-input-text+
                             (list (loop for (path . message) in field-errors
                                         append (list path message))))))

;;; A refusal whose message is a literal is noted where its code is loaded,
;;; as TR's text is, so the checks know every text code writes
;;; (spec/i18n.md 3.7).  Each function keeps its own behaviour: the
;;; compiler macro only adds the note.

(defun noted-refusal (form control)
  "FORM, a call of a refusal whose message is CONTROL, with CONTROL noted
when it is a literal."
  (if (stringp control)
      `(progn
         (load-time-value (note-text ,control nil ,(current-definition-module)
                                     ,(definition-place)))
         (locally (declare (notinline ,(first form))) ,form))
      form))

(defun check-literal-code (code)
  "Warn, when compiling, about a literal CODE that is not an ERROR-CODE: the
call keeps the type check FAIL's declaration gives it."
  (when (and (keywordp code) (not (typep code 'error-code)))
    (warn "~s is not an error code (~s)" code '(member . error-code))))

(define-compiler-macro fail (&whole form code control &rest args)
  (declare (ignore args))
  (check-literal-code code)
  (noted-refusal form control))

(define-compiler-macro fail-with-details (&whole form code details control &rest args)
  (declare (ignore details args))
  (check-literal-code code)
  (noted-refusal form control))

(define-compiler-macro reject (&whole form code control &rest args)
  (declare (ignore args))
  (check-literal-code code)
  (noted-refusal form control))

(define-compiler-macro reject-as (&whole form actor code control &rest args)
  (declare (ignore actor args))
  (check-literal-code code)
  (noted-refusal form control))

(define-compiler-macro input-error (&whole form path control &rest args)
  (declare (ignore path args))
  (noted-refusal form control))

(defun operation-error-json (condition)
  "The {\"error\":{...}} document for CONDITION, its messages written in the
current language: source text for a machine (spec/i18n.md 7)."
  (let ((err (jobj "code" (json-name-of (operation-error-code condition))
                   "message" (operation-error-message condition))))
    (when (operation-error-fields condition)
      (setf (gethash "fields" err)
            (jarr (mapcar (lambda (fe) (jobj "field" (car fe) "message" (render-text (cdr fe))))
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
