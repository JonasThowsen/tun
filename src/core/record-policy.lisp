;;;; core/record-policy.lisp -- which records the actor reaches (spec/store.md 6).
;;;;
;;;; An entity's record policy is an SQL condition per role, kept on the
;;;; class by DEFINE-ENTITY.  The Postgres adapter puts the condition of the
;;;; request's actor into every statement that reads or writes the entity
;;;; (RECORD-CONDITION), so Postgres decides, in the same statement, which
;;;; rows a select returns and whether a write may stand.  A query gets it
;;;; through {ENTITY} (RECORD-SOURCE-SQL).  At start each condition runs once
;;;; against the real database (CHECK-RECORD-POLICIES).

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(declaim (ftype (function (t t &rest t) *) reject))

(defun actor-record-clause (class)
  "What *ACTOR* reaches of CLASS's records: :ALL, :NONE, or the parts of the
condition that decides it.  Signals an error when CLASS has a policy and
there is no actor."
  (let ((policy (entity-record-policy class)))
    (cond ((null policy) :all)
          ((null *actor*)
           (error "~a has a record policy, so reading or writing it needs an actor"
                  (entity-json-name class)))
          ((eq (actor-role *actor*) :system) :all)
          (t (destructuring-bind (&optional role text parts)
                 (assoc (actor-role *actor*) policy)
               (declare (ignore role))
               (cond ((null text) :none)
                     ((eq text t) :all)
                     (t parts)))))))

(defun actor-parameter-value (name)
  "The value of the record policy parameter NAME for *ACTOR*."
  (cond ((string= name "actor") (actor-string *actor*))
        ((string= name "actor_name") (actor-name *actor*))
        (t (error "Unknown record policy parameter :~a" name))))

(defun condition-sql (class parts first-parameter)
  "The condition PARTS of CLASS's policy as SQL in parentheses, with its
parameters numbered from FIRST-PARAMETER: (values SQL NAMES), NAMES the
parameters in the order of their numbers.  The parenthesis closes on a
line of its own, so a -- comment at the end of the text stays inside."
  (let ((names '()))
    (values (with-output-to-string (out)
              (write-char #\( out)
              (dolist (part parts)
                (if (stringp part)
                    (write-string part out)
                    (ecase (first part)
                      (:entity (write-string (table-sql (sql-entity-class (second part)
                                                                          (entity-source class)))
                                             out))
                      (:parameter
                       (let ((name (second part)))
                         (unless (member name names :test #'string=)
                           (setf names (append names (list name))))
                         (format out "$~d" (+ first-parameter
                                              (position name names :test #'string=))))))))
              (format out "~%)"))
            names)))

(defun record-condition (class first-parameter)
  "The SQL condition that limits CLASS's records to those *ACTOR* reaches,
the record being THIS, with its parameters numbered from FIRST-PARAMETER:
(values SQL VALUES).  SQL is NIL when the actor reaches every record and
FALSE when none (spec/store.md 6.2)."
  (check-type first-parameter (integer 1))
  (let ((clause (actor-record-clause class)))
    (case clause
      (:all (values nil '()))
      (:none (values "FALSE" '()))
      (t (multiple-value-bind (sql names) (condition-sql class clause first-parameter)
           (values sql (mapcar #'actor-parameter-value names)))))))

(defun record-source-sql (class first-parameter &key check)
  "What {ENTITY} for CLASS stands for in a query: its table, or the records
of it *ACTOR* reaches (spec/store.md 6.4), with the values of the parameters
numbered from FIRST-PARAMETER: (values SQL VALUES).  With CHECK, an entity
with a policy is given in that form without records and without an actor."
  (let ((table (table-sql class)))
    (cond ((and check (entity-record-policy class))
           (values (format nil "(SELECT * FROM ~a AS this WHERE FALSE)" table) '()))
          (t (multiple-value-bind (condition values) (record-condition class first-parameter)
               (if condition
                   (values (format nil "(SELECT * FROM ~a AS this WHERE ~a)" table condition)
                           values)
                   (values table '())))))))

(defun refuse-record-write (class)
  "Refuse a write of a record of CLASS that its record policy does not
admit: forbidden, audited as a rejection (spec/store.md 6.5)."
  (reject :forbidden "You do not have access to save ~(~a~) this way"
          (entity-label-text class)))

;;; ------------------------------------------------------------------
;;; Checking every policy at start

(defun record-condition-problem (class parts)
  "Why the condition PARTS of CLASS's policy cannot run on the current
store, or NIL: run once with NULL parameters and no rows wanted."
  (handler-case
      (with-transaction (:read)
        (multiple-value-bind (sql names) (condition-sql class parts 1)
          (store-query *store* (format nil "SELECT 1 FROM ~a AS this WHERE ~a LIMIT 0"
                                       (table-sql class) sql)
                       (make-list (length names)))
          nil))
    (error (e)
      (substitute #\Space #\Newline (princ-to-string e)))))

(defun check-record-policies ()
  "Refuse to start when a record policy's condition cannot run on this
application's store (spec/store.md 6.6)."
  (when (store-runs-queries-p *store*)
    (let ((problems
           (loop for class in (all-entity-classes)
                 append (loop for (role text parts) in (entity-record-policy class)
                              for problem = (and (stringp text)
                                                 (record-condition-problem class parts))
                              when problem
                              collect (format nil "~a~@[ (~a)~], ~(~a~): ~a"
                                              (entity-json-name class) (entity-location class)
                                              role problem)))))
      (when problems
        (extension-error "Record policies that cannot run:~{~%  ~a~}" problems)))))
