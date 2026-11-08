;;;; core/invariant.lisp -- invariants: what holds across records, which a
;;;; rule, one record at its write, cannot say.  Tests check every invariant
;;;; of an application after each call of the generated sequence test
;;;; (spec/testing.md 4); a running server does not.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defclass invariant ()
  ((name :initarg :name :reader invariant-name)
   (description :initarg :description :reader invariant-description
                :documentation "What holds, in English, for the developers who read a breach.")
   (function :initarg :function :reader invariant-function
             :documentation "A function of no arguments: the breaches, each a text, or NIL.")
   (source :initarg :source :reader invariant-source)
   (module :initarg :module :initform "core" :reader invariant-module)
   (location :initarg :location :initform nil :reader invariant-location)))

(defvar *invariants* '()
  "Every invariant defined, in definition order.")

(defmacro define-invariant (name (&key description) &body body)
  "Define the invariant NAME: BODY reads records and returns the breaches,
a list of texts each naming the records that break it, or NIL when it holds.
It runs as the system actor in a read transaction (CHECK-INVARIANT).
DESCRIPTION, a literal non-blank string in English, says what holds."
  (unless (and (stringp description) (not (blank-p description)))
    (error "define-invariant ~(~a~): :description must be a text saying what holds, not ~s"
           name description))
  `(progn
     (defun ,name () ,@body)
     (register-invariant ',name #',name :description ,description
                                        :source ,(current-definition-source)
                                        :module ,(current-definition-module)
                                        :location ,(current-source-location))
     ',name))

(defun register-invariant (name function &key description source (module "core") location)
  "Register the invariant NAME, replacing one of the same name."
  (setf *invariants*
        (append (remove name *invariants* :key #'invariant-name)
                (list (make-instance 'invariant :name name :function function
                                                :description description :source source
                                                :module module :location location))))
  name)

(defun application-invariants (&optional (application *application*))
  "The invariants that hold in APPLICATION: core's, the client's, and those
of the modules it enables."
  (let ((modules (mapcar (lambda (entry) (module-name (first entry)))
                         (enabled-modules application))))
    (remove-if-not (lambda (invariant)
                     (let ((module (invariant-module invariant)))
                       (or (member module '("core" "client") :test #'string=)
                           (member module modules :test #'string=))))
                   *invariants*)))

(defun check-invariant (invariant)
  "The breaches of INVARIANT in *APPLICATION*, a list of texts: its body run
as the system actor in a read transaction.  A body that returns anything but
a list of texts is an error of the invariant's."
  (let ((breaches (with-actor ((system-actor "invariant"))
                    (with-transaction (:read)
                      (funcall (invariant-function invariant))))))
    (unless (and (listp breaches) (every #'stringp breaches))
      (error "The invariant ~(~a~) returned ~s, not a list of texts"
             (invariant-name invariant) breaches))
    breaches))
