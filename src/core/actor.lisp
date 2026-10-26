;;;; core/actor.lisp -- actors, roles and policy.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(deftype role () '(member :viewer :employee :admin :system :customer))
(deftype policy () '(member :viewer :employee :admin))

(defstruct (actor (:constructor %make-actor (role name)))
  (role :viewer :type role :read-only t)
  (name "" :type string :read-only t))

(defvar *actor* nil "The actor of the current request. Request-scoped, never global state.")

(defvar *credential* nil
  "How the transport established *ACTOR* (spec/auth.md 7): an access token's id
(tok_...), a session's id (ses_...), the WorkOS identity's id for an OAuth
client (aid_...), \"claimed\", or NIL for work the process does itself.  Request-scoped, like *ACTOR*.")

(declaim (ftype (function (role) (values (integer 0 3) &optional)) role-rank))
(defun role-rank (role)
  (ecase role (:viewer 0) (:customer 0) (:employee 1) (:admin 2) (:system 3)))

(defun parse-actor (string)
  "Parse \"role:name\" (role admin|employee|viewer). NIL when malformed.
The :SYSTEM role cannot be claimed from outside."
  (when (and (stringp string) (<= 3 (length string) 128))
    (let ((colon (position #\: string)))
      (when colon
        (let ((role (subseq string 0 colon))
              (name (subseq string (1+ colon))))
          (when (and (plusp (length name))
                     (notany (lambda (c) (or (whitespace-char-p c) (char= c #\:)
                                             (< (char-code c) 32)))
                             name))
            (let ((role (cond ((string= role "admin") :admin)
                              ((string= role "employee") :employee)
                              ((string= role "viewer") :viewer))))
              (and role (%make-actor role (coerce name 'simple-string))))))))))

(defun make-actor (role name)
  (declare (type role role) (type string name))
  (%make-actor role name))

(defun system-actor (&optional (name "workflow"))
  (%make-actor :system name))

(defun actor-string (actor)
  (format nil "~a:~a" (string-downcase (symbol-name (actor-role actor))) (actor-name actor)))

(declaim (ftype (function (actor policy) (values boolean &optional)) actor-permits-p))
(defun actor-permits-p (actor policy)
  (>= (role-rank (actor-role actor)) (role-rank policy)))

(defmacro with-actor ((actor) &body body)
  `(let ((*actor* ,actor)) ,@body))
