;;;; core/store.lisp -- the store port.
;;;;
;;;; Core and modules talk to persistence only through these generic
;;;; functions.  Three adapters implement them: an in-memory store (tests),
;;;; SQLite and Postgres (spec/store.md).  Write transactions run one at a
;;;; time per database on both durable adapters, so STORE-LOCK-ROW needs no
;;;; lock of its own there.
;;;;
;;;; Queries use a small WHERE language over JSON field names, never SQL text:
;;;;   (:= "status" "bekreftet") (:in "status" ("a" "b")) (:<= "due_at" ts)
;;;;   (:null "x") (:not-null "x") (:and ...) (:or ...)
;;;; ORDER-BY is a list of ("field" :asc|:desc); "seq" is insertion order.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defclass store ()
  ((presences :initform '() :accessor store-presences
              :documentation "The presence keys this process holds, for an adapter whose
database has one process.")
   (commits :initform 0 :accessor store-commits
            :documentation "How many write transactions this process has committed, for
AWAIT to see that something changed (spec/waiting.md 1).  Guarded by COMMIT-LOCK.")
   (commit-lock :initform (sb-thread:make-mutex :name "store commits") :reader store-commit-lock)
   (commit-queue :initform (sb-thread:make-waitqueue :name "store commits")
                 :reader store-commit-queue))
  (:documentation "Abstract store. Adapters subclass this."))

(defvar *store* nil "The store of the current application.")
(defvar *transaction-mode* nil "NIL outside a transaction, else :READ or :WRITE.")

(defvar *under-eval* nil
  "True in the thread of an eval call and in every thread started from it
(the eval module wraps SB-THREAD:MAKE-THREAD to pass it on): no write
transaction opens there (core.md §8.3).")

(defgeneric store-open (store) (:documentation "Open connections; idempotent."))
(defgeneric store-close (store))
(defgeneric store-migrate (store classes)
  (:documentation "Create or extend tables so every stored entity class fits. Additive only."))
(defgeneric store-call-in-transaction (store function mode)
  (:documentation "Call FUNCTION inside a transaction. MODE :WRITE takes the write lock;
nested calls use savepoints. Non-local exit rolls back."))
(defgeneric store-describe-schema (store)
  (:documentation "Values: a JSON array of tables ({name, columns:[{name,type,nullable}]})
and a JSON array of applied migrations ({id, applied_at, statement})."))
(defgeneric store-write-queue-depth (store)
  (:documentation "Writers waiting for the write lock now.")
  (:method (store) (declare (ignore store)) 0))
(defgeneric store-insert (store entity))
(defgeneric store-update (store entity))
(defgeneric store-delete (store class-name id))
(defgeneric store-find (store class-name id))
(defgeneric store-select (store class-name &key where order-by limit offset))
(defmethod store-find :around ((store store) class-name id)
  (declare (ignore store class-name id))
  (let ((record (call-next-method)))
    (and record (or (not *under-eval*) (entity-readable-p record *actor*)) record)))
(defmethod store-select :around ((store store) class-name &key where order-by limit offset)
  (declare (ignore store class-name where order-by limit offset))
  (let ((records (call-next-method)))
    (if *under-eval* (remove-if-not (lambda (record) (entity-readable-p record *actor*)) records) records)))
(defgeneric store-runs-queries-p (store)
  (:documentation "True when STORE runs DEFINE-QUERY's SQL (spec/store.md 5.8).")
  (:method ((store store)) (declare (ignore store)) nil))
(defgeneric store-query (store sql parameters)
  (:documentation "Run the read-only SQL with PARAMETERS as $1, $2...: (values ROWS
COLUMNS), each row a list of stored values (NIL for NULL) in the order of
COLUMNS, the result's column names.")
  (:method ((store store) sql parameters)
    (declare (ignore sql parameters))
    (error "Queries need the Postgres store; this application runs on ~a"
           (store-description store))))

(defun check-record-policy-store (store class-name)
  "Refuse to reach CLASS-NAME's records on STORE when the entity has a
record policy and STORE cannot apply it (spec/store.md 6.7)."
  (when (and (entity-record-policy (find-entity-class class-name))
             (not (store-runs-queries-p store)))
    (error "~(~a~) has a record policy, which needs the Postgres store; this application ~
            runs on ~a" class-name (store-description store))))

(defmethod store-find :before ((store store) class-name id)
  (declare (ignore id))
  (check-record-policy-store store class-name))
(defmethod store-select :before ((store store) class-name &key where order-by limit offset)
  (declare (ignore where order-by limit offset))
  (check-record-policy-store store class-name))
(defmethod store-insert :before ((store store) entity)
  (check-record-policy-store store (class-name (class-of entity))))
(defmethod store-update :before ((store store) entity)
  (check-record-policy-store store (class-name (class-of entity))))
(defmethod store-delete :before ((store store) class-name id)
  (declare (ignore id))
  (check-record-policy-store store class-name))

(defgeneric store-write-content (store id octets)
  (:documentation "Store OCTETS, a file's content, under ID in the current write
transaction (spec/files.md 5.1).  A file's content never changes once written.")
  (:method ((store store) id octets)
    (declare (ignore id octets))
    (error "Files need the Postgres store; this application runs on ~a"
           (store-description store))))

(defgeneric store-read-content (store id start length)
  (:documentation "At most LENGTH octets of the content stored under ID, from octet
START, in the current transaction: a vector shorter than LENGTH at the end,
empty past it, and NIL when there is no content under ID.")
  (:method ((store store) id start length)
    (declare (ignore id start length))
    (error "Files need the Postgres store; this application runs on ~a"
           (store-description store))))

(defgeneric store-delete-content (store id)
  (:documentation "Delete the content stored under ID, in the current write transaction.")
  (:method ((store store) id)
    (declare (ignore id))
    (error "Files need the Postgres store; this application runs on ~a"
           (store-description store))))

(defgeneric store-claim-presence (store key)
  (:documentation "Take the presence KEY, an integer from 0 below 2^31, and hold it for as
long as this process keeps STORE open, so other processes can tell it runs
(spec/store.md 3).  True when it took it, NIL when another holds it.")
  (:method ((store store) key)
    (unless (member key (store-presences store))
      (push key (store-presences store)))))

(defgeneric store-present-p (store key)
  (:documentation "True when a process holds the presence KEY on STORE.  The default, for
a database with one process, knows only this process's.")
  (:method ((store store) key)
    (and (member key (store-presences store)) t)))

(defgeneric store-lock-row (store class-name id)
  (:documentation "Pessimistically lock one row for the rest of the write transaction."))
(defgeneric store-description (store))

;;; ------------------------------------------------------------------
;;; Transactions

(defmacro with-transaction ((&optional (mode :write)) &body body)
  "Run BODY in a transaction on *STORE*. MODE is :READ or :WRITE."
  `(call-in-transaction (lambda () ,@body) ,mode))

(defvar *rollback-actions* nil
  "In-memory undo actions of the outermost write transaction (see ON-ROLLBACK).")

(defun on-rollback (function)
  "Run FUNCTION if the outermost write transaction does not commit. For
in-memory state that mirrors stored state (the test clock). Internal."
  (assert-writable)
  (push function *rollback-actions*))

(defvar *commit-actions* nil
  "Actions to run once the outermost write transaction has committed (see ON-COMMIT).")

(defun on-commit (function)
  "Run FUNCTION after the outermost write transaction commits, outside it;
never when it rolls back.  For work that must not start before the data it
needs is visible, such as waking the worker of a job just enqueued."
  (assert-writable)
  (push function *commit-actions*))

(define-condition read-only-violation (error)
  ((message :initarg :message :reader read-only-violation-message))
  (:report (lambda (c s) (write-string (read-only-violation-message c) s)))
  (:documentation "A write was attempted in a read transaction (a read operation, explain, eval)."))

(defun call-in-transaction (function mode)
  (declare (type (member :read :write) mode))
  (check-deadline)
  (cond ((null *store*) (error "No store is active"))
        ((and (eq *transaction-mode* :read) (eq mode :write))
         (error 'read-only-violation :message "Cannot open a write transaction inside a read transaction"))
        ((and *under-eval* (eq mode :write))
         (error 'read-only-violation :message "Cannot open a write transaction in a thread started by eval"))
        ((and (null *transaction-mode*) (eq mode :write))
         (let ((after-commit '()))
           (multiple-value-prog1
               (let ((*transaction-mode* :write)
                     (*rollback-actions* '())
                     (*commit-actions* '())
                     (committed nil))
                 (unwind-protect
                      (multiple-value-prog1 (store-call-in-transaction *store* function :write)
                        (setf committed t
                              after-commit (reverse *commit-actions*)))
                   (unless committed
                     (mapc #'funcall *rollback-actions*))))
             (note-commit *store*)
             (mapc #'funcall after-commit))))
        (t (let ((*transaction-mode* (if (eq *transaction-mode* :write) :write mode)))
             (store-call-in-transaction *store* function *transaction-mode*)))))

(defun note-commit (store)
  "Count a write transaction STORE has committed, and wake every call that
waits for one (WAIT-FOR-COMMIT)."
  (sb-thread:with-mutex ((store-commit-lock store))
    (incf (store-commits store))
    (sb-thread:condition-broadcast (store-commit-queue store))))

(defun wait-for-commit (store seen seconds)
  "Wait until STORE has committed more than SEEN write transactions, or
SECONDS have passed."
  (let ((end (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
    (sb-thread:with-mutex ((store-commit-lock store))
      (loop while (= (store-commits store) seen)
            do (let ((left (/ (- end (get-internal-real-time)) internal-time-units-per-second)))
                 ;; CONDITION-WAIT returns NIL when its time is up, and then
                 ;; without the lock: wait no more, and touch nothing it guards.
                 (unless (and (plusp left)
                              (sb-thread:condition-wait (store-commit-queue store)
                                                        (store-commit-lock store)
                                                        :timeout left))
                   (return)))))))

(defun assert-writable ()
  (unless (eq *transaction-mode* :write)
    (error 'read-only-violation
           :message (format nil "Store write outside a write transaction (mode ~s)" *transaction-mode*))))

(defun assert-in-transaction ()
  (unless *transaction-mode*
    (error "Store access outside a transaction")))

;;; ------------------------------------------------------------------
;;; Convenience used by modules

(defvar *now-function* nil "Function returning the current universal time (set by the clock).")

(defun prepare-for-write (entity)
  (let ((class (class-of entity)))
    (when (and (typep entity 'stored-entity) (null (entity-id entity)))
      (setf (entity-id entity) (new-id (entity-id-prefix class))))
    (let ((created (find-field class "created_at")))
      (when (and created (null (field-value entity created)) *now-function*)
        (setf (field-value entity created) (funcall *now-function*))))
    (validate-entity entity)))

(defun insert (entity)
  "Validate ENTITY (fields and rules), give it an id, and store it."
  (assert-writable)
  (check-deadline)
  (prepare-for-write entity)
  (store-insert *store* entity)
  entity)

(defun save (entity)
  "Validate and store the current state of an existing ENTITY. Revisioned
entities get their revision incremented here: every accepted update counts."
  (assert-writable)
  (check-deadline)
  (when (entity-revisioned-p (class-of entity))
    (let ((field (find-field (class-of entity) "revision")))
      (setf (field-value entity field) (1+ (or (field-value entity field) 0)))))
  (validate-entity entity)
  (store-update *store* entity)
  entity)

(defun delete-entity (entity)
  (assert-writable)
  (store-delete *store* (class-name (class-of entity)) (entity-id entity)))

(defun fetch (class-name id)
  "The entity of CLASS-NAME with ID, or NIL."
  (assert-in-transaction)
  (check-deadline)
  (and (stringp id) (store-find *store* class-name id)))

(defun record-not-found (class-name id)
  "Fail not_found for the record of CLASS-NAME with ID."
  (fail :not-found "Fant ikke ~a med id ~a"
        (string-downcase (or (entity-label (find-entity-class class-name)) "objekt")) id))

(defun fetch! (class-name id)
  "Like FETCH but signals not_found."
  (or (fetch class-name id)
      (record-not-found class-name id)))

(defun select (class-name &key where order-by limit offset)
  (assert-in-transaction)
  (check-deadline)
  (store-select *store* class-name :where where :order-by order-by :limit limit :offset offset))

(defun select-one (class-name &key where order-by)
  (first (select class-name :where where :order-by order-by :limit 1)))

(defun lock-row (class-name id)
  (assert-writable)
  (store-lock-row *store* class-name id))

;;; Shared helpers for adapters: WHERE language validation and evaluation.

(defun where-field (class json-name)
  (if (string= json-name "seq")
      nil
      (or (find-field class json-name)
          (error "Unknown field ~s in query on ~a" json-name (entity-json-name class)))))

(defun where-value->db (class json-name value)
  (let ((field (where-field class json-name)))
    (if field (type->db (field-type field) value) value)))
