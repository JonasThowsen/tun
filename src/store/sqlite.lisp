;;;; store/sqlite.lisp -- SQLite adapter for the store port.
;;;;
;;;; * Read transactions take a connection from a pool; WAL mode so readers
;;;;   never block the writer and see only committed data.
;;;; * Write transactions run one at a time under an in-process mutex, on one
;;;;   dedicated writer connection, inside BEGIN IMMEDIATE: SQLite's single
;;;;   write lock covers every row, which is what STORE-LOCK-ROW asks for
;;;;   (Postgres would use SELECT ... FOR UPDATE).  busy_timeout makes another
;;;;   process's writer queue instead of failing.
;;;; * Group commit.  With synchronous=FULL every COMMIT is an fsync, and the
;;;;   fsync was half of the time a writer held the lock.  So each write
;;;;   transaction runs as a SAVEPOINT ("member") of a batch transaction; when
;;;;   it is done and other writers are already queued for the mutex, it passes
;;;;   the mutex on without committing, and the last member of the batch (no
;;;;   one queued, or MAX-BATCH members) commits once for all.  A member
;;;;   returns only after its batch is durable, so a caller never sees success
;;;;   for data that is not on disk; a member that fails rolls back to its own
;;;;   savepoint and leaves the batch intact; if the COMMIT fails, every member
;;;;   of the batch fails.  Readers never see a batch before its COMMIT.  A
;;;;   member does see the uncommitted writes of earlier members of its batch
;;;;   (they are serialized before it), so a member that fails may have failed
;;;;   on a state that a failing COMMIT then discarded; it stored nothing.
;;;;   MAX-BATCH 1 (--group-commit 1) commits every transaction alone.
;;;; * Nested transactions are SAVEPOINTs.
;;;; * Migrations are additive and derived from the entity classes: create
;;;;   missing tables, add missing columns (client extensions add columns),
;;;;   create indexes.  Every DDL statement is recorded in schema_history
;;;;   with the module that owns it and a migration id
;;;;   <module>_<nnnn>_<name> (tun-platform.md 2.6): the kernel's and the
;;;;   modules' tables and columns first, in dependency order, then the
;;;;   client's.  Columns are nullable (constant defaults at most), so the
;;;;   previous revision can run against the migrated database.

(defpackage #:tun.store.sqlite
  (:use #:cl #:tun.core)
  (:export #:sqlite-store #:sqlite-store-path))

(in-package #:tun.store.sqlite)

(declaim (optimize (safety 3) (debug 2)))

(defclass sqlite-store (store)
  ((path :initarg :path :reader sqlite-store-path)
   (pool :initform '() :accessor pool)
   (connections :initform '() :accessor connections)
   (pool-lock :initform (sb-thread:make-mutex :name "sqlite pool") :reader pool-lock)
   (write-lock :initform (sb-thread:make-mutex :name "sqlite writer") :reader write-lock)
   (writer :initform nil :accessor writer-connection)
   (writers-waiting :initform (list 0) :reader writers-waiting) ; (count), for ATOMIC-INCF
   (batch :initform nil :accessor open-batch)                    ; guarded by WRITE-LOCK
   (batch-lock :initform (sb-thread:make-mutex :name "sqlite batch") :reader batch-lock)
   (batch-done :initform (sb-thread:make-waitqueue :name "sqlite batch done") :reader batch-done)
   (max-batch :initarg :max-batch :initform 16 :reader max-batch :type (integer 1))
   (commit-count :initform 0 :accessor commit-count) ; batches committed (diagnostics, tests)
   (busy-timeout :initarg :busy-timeout :initform 30000 :reader busy-timeout)
   ;; FULL fsyncs the WAL on every commit (durable across power loss); NORMAL
   ;; fsyncs only at checkpoints (durable across a process kill, not across
   ;; an OS crash).  Default FULL; --sqlite-synchronous normal is the knob.
   (synchronous :initarg :synchronous :initform :full :reader sqlite-synchronous
                :type (member :full :normal))))

(defvar *connection* nil "Connection of the transaction running in this thread.")
(defparameter *statement-cache-size* 256 "Prepared statements kept per connection.")
(defvar *savepoint* 0)

(defmethod store-description ((store sqlite-store))
  (format nil "sqlite:~a" (sqlite-store-path store)))

(defun open-connection (store &key read-only)
  (let ((db (without-deadline-interrupts
              (sqlite:connect (sqlite-store-path store) :busy-timeout (busy-timeout store)))))
    ;; cl-sqlite keeps 16 prepared statements per connection; a write
    ;; transaction alone cycles through more, so every statement was parsed
    ;; again.  256 holds every statement the application generates.
    (setf (sqlite::cache db) (make-instance 'sqlite.cache:mru-cache
                                            :cache-size *statement-cache-size*
                                            :destructor #'sqlite::really-finalize-statement))
    (sqlite:execute-single db "PRAGMA journal_mode=WAL")
    (sqlite:execute-non-query db (ecase (sqlite-synchronous store)
                                   (:full "PRAGMA synchronous=FULL")
                                   (:normal "PRAGMA synchronous=NORMAL")))
    (sqlite:execute-non-query db "PRAGMA foreign_keys=ON")
    ;; Pool connections serve read transactions only (writes use the writer
    ;; connection): SQLite itself refuses a write on them.
    (when read-only (sqlite:execute-non-query db "PRAGMA query_only=ON"))
    db))

(defun checkout (store)
  (or (sb-thread:with-mutex ((pool-lock store)) (pop (pool store)))
      (let ((db (open-connection store :read-only t)))
        (sb-thread:with-mutex ((pool-lock store)) (push db (connections store)))
        db)))

(defun checkin (store db)
  (sb-thread:with-mutex ((pool-lock store)) (push db (pool store))))

(defmethod store-open ((store sqlite-store))
  (checkin store (checkout store))
  (sb-thread:with-mutex ((write-lock store))
    (unless (writer-connection store)
      (setf (writer-connection store) (open-connection store))))
  store)

(defmethod store-close ((store sqlite-store))
  ;; Readers first: the writer, closing last, checkpoints the WAL.
  (sb-thread:with-mutex ((pool-lock store))
    (dolist (db (connections store))
      (ignore-errors (sqlite:disconnect db)))
    (setf (connections store) '() (pool store) '()))
  (sb-thread:with-mutex ((write-lock store))
    (when (writer-connection store)
      (ignore-errors (sqlite:disconnect (writer-connection store)))
      (setf (writer-connection store) nil)))
  store)

(defmethod store-write-queue-depth ((store sqlite-store))
  (car (writers-waiting store)))

(defmethod store-describe-schema ((store sqlite-store))
  (store-call-in-transaction
   store
   (lambda ()
     (values
      (jarr (loop for (name) in (query "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
                  collect (jobj "name" name
                                "columns" (jarr (loop for (nil column type notnull nil pk) in (query (format nil "PRAGMA table_info(~a)" (quote-ident name)))
                                                      collect (jobj "name" column "type" type
                                                                    "nullable" (json-bool (and (eql notnull 0) (eql pk 0)))))))))
      (jarr (loop for (seq statement applied-at module migration)
                    in (query (format nil "SELECT seq, statement, applied_at, ~:[NULL, NULL~;module, migration~] FROM schema_history ORDER BY seq"
                                      (member "migration" (existing-columns "schema_history") :test #'string=)))
                  collect (jobj "id" (or migration (princ-to-string seq)) "seq" seq "applied_at" applied-at
                                "module" (or module :null) "statement" statement)))))
   :read))

(defun exec (sql &rest params)
  (let ((started (trace-clock-us)))
    (multiple-value-prog1
        (without-deadline-interrupts (apply #'sqlite:execute-non-query *connection* sql params))
      (note-store-statement sql started))))

(defun query (sql &rest params)
  (let ((started (trace-clock-us)))
    (multiple-value-prog1
        (without-deadline-interrupts (apply #'sqlite:execute-to-list *connection* sql params))
      (note-store-statement sql started))))

(defstruct (batch (:constructor make-batch ()))
  (state :open :type (member :open :committed :failed))
  (error nil)
  (members 0 :type fixnum))

(define-condition batch-commit-failed (error)
  ((cause :initarg :cause :reader batch-commit-failed-cause))
  (:report (lambda (c s) (format s "COMMIT of a write batch failed: ~a" (batch-commit-failed-cause c)))))

(defun commit-batch (store batch)
  "Commit BATCH (the open one; the caller holds the write lock) and wake its members."
  (let ((*connection* (writer-connection store)))
    (setf (open-batch store) nil)
    (let ((failure (handler-case (progn (exec "COMMIT") nil)
                     (error (e) (ignore-errors (exec "ROLLBACK")) e))))
      (sb-thread:with-mutex ((batch-lock store))
        (if failure
            (setf (batch-error batch) failure (batch-state batch) :failed)
            (progn (incf (commit-count store))
                   (setf (batch-state batch) :committed)))
        (sb-thread:condition-broadcast (batch-done store))))))

(defun abort-batch (store batch cause)
  "SQLite rolled BATCH's transaction back on its own (an I/O error, a full
disk): fail it now, so that no later writer joins a transaction that no
longer exists (its SAVEPOINT would open a new one and commit on RELEASE).
The caller holds the write lock."
  (let ((*connection* (writer-connection store)))
    (ignore-errors (exec "ROLLBACK")))
  (setf (open-batch store) nil)
  (sb-thread:with-mutex ((batch-lock store))
    (setf (batch-error batch) cause (batch-state batch) :failed)
    (sb-thread:condition-broadcast (batch-done store))))

(defun await-batch (store batch)
  "Wait until BATCH is committed; signal BATCH-COMMIT-FAILED if it failed.
Members normally wait on the condition variable; if the writers that were
queued when the mutex was handed on went away (a lock wait that hit its
deadline), a waiting member commits the batch itself."
  (loop while (eq (batch-state batch) :open)
        do (sb-thread:with-mutex ((batch-lock store))
             (when (eq (batch-state batch) :open)
               (sb-thread:condition-wait (batch-done store) (batch-lock store) :timeout 0.005)))
           (when (and (eq (batch-state batch) :open)
                      (sb-thread:grab-mutex (write-lock store) :waitp nil))
             (unwind-protect
                  (when (eq (open-batch store) batch)
                    (commit-batch store batch))
               (sb-thread:release-mutex (write-lock store)))))
  (when (eq (batch-state batch) :failed)
    (error 'batch-commit-failed :cause (batch-error batch))))

(defun finish-member (store batch)
  "The caller holds the write lock and is done with BATCH (or failed before
joining one).  Commit when no other writer is queued or the batch is full,
else hand the lock on with the batch open; then release the lock."
  (unwind-protect
       (when (and batch (eq (open-batch store) batch)
                  (or (zerop (car (writers-waiting store)))
                      (>= (batch-members batch) (max-batch store))))
         (commit-batch store batch))
    (sb-thread:release-mutex (write-lock store))))

(defun call-in-write-batch (store function)
  "Run FUNCTION as one write transaction (a member of a group-commit batch);
return its values once the batch is durable."
  (let ((outer-interruptible *interruptible*)
        (lock (write-lock store))
        (waiting (writers-waiting store))
        (got nil) (batch nil) (values '()) (released nil)
        (commit-start nil) (members 0))
    ;; Interrupts (the deadline watchdog among them) are deferred everywhere
    ;; but inside FUNCTION and the wait for the mutex, and *INTERRUPTIBLE* is
    ;; NIL around the rest: once a member's savepoint is released its data
    ;; commits with the batch, so it must not unwind as if nothing was stored.
    (let ((*interruptible* nil))
      (sb-sys:without-interrupts
        (unwind-protect
             (progn
               (sb-ext:atomic-incf (car waiting))
               (let ((wait-start (trace-clock-us)))
                 (setf got (unwind-protect
                                (with-request-state (:waiting-write-lock)
                                  (sb-sys:allow-with-interrupts
                                    (let ((remaining (deadline-remaining-ms)))
                                      (sb-thread:grab-mutex lock :timeout (and remaining (/ remaining 1000.0))))))
                             (sb-ext:atomic-decf (car waiting))
                             (note-write-lock-wait (- (trace-clock-us) wait-start)))))
               (unless got (error 'deadline-exceeded))
               (unless (writer-connection store)
                 (setf (writer-connection store) (open-connection store)))
               (let ((*connection* (writer-connection store))
                     (*savepoint* 0))
                 (setf batch (or (open-batch store)
                                 (progn (exec "BEGIN IMMEDIATE")
                                        (setf (open-batch store) (make-batch)))))
                 (exec "SAVEPOINT member")
                 (incf (batch-members batch))
                 (unwind-protect
                      (progn
                        (setf values (multiple-value-list
                                      (sb-sys:with-local-interrupts
                                        (let ((*interruptible* outer-interruptible))
                                          (funcall function)))))
                        (exec "RELEASE member")
                        (setf released t
                              commit-start (trace-clock-us)
                              members (batch-members batch)))
                   (unless released
                     (let ((cause (nth-value 1 (ignore-errors (exec "ROLLBACK TO member")
                                                              (exec "RELEASE member")
                                                              t))))
                       (when cause (abort-batch store batch cause)))))))
          (when got (finish-member store batch))))
      (await-batch store batch)
      (when commit-start
        (note-step :commit :name "group commit" :source :core :started commit-start
                           :duration (- (trace-clock-us) commit-start)
                           :detail (format nil "member ~d of the batch; COMMIT when the batch is full or nothing waits"
                                           members))))
    (values-list values)))

(defun call-with-savepoint (function)
  (let* ((name (format nil "sp~d" (incf *savepoint*)))
         (ok nil))
    (exec (format nil "SAVEPOINT ~a" name))
    (unwind-protect
         (multiple-value-prog1 (let ((*savepoint* *savepoint*)) (funcall function))
           (exec (format nil "RELEASE ~a" name))
           (setf ok t))
      (unless ok
        (ignore-errors (exec (format nil "ROLLBACK TO ~a" name)))
        (ignore-errors (exec (format nil "RELEASE ~a" name)))))))

(defun call-with-top-transaction (begin function)
  (let ((ok nil))
    (exec begin)
    (unwind-protect
         (multiple-value-prog1 (funcall function)
           (exec "COMMIT")
           (setf ok t))
      (unless ok (ignore-errors (exec "ROLLBACK"))))))

(defmethod store-call-in-transaction ((store sqlite-store) function mode)
  (cond (*connection*
         (if (eq mode :write) (call-with-savepoint function) (funcall function)))
        ((eq mode :write) (call-in-write-batch store function))
        (t (let ((db (checkout store)))
             ;; A connection whose transaction failed is usable again once rolled back.
             (unwind-protect
                  (let ((*connection* db)
                        (*savepoint* 0))
                    (call-with-top-transaction "BEGIN" function))
               (checkin store db))))))

;;; ------------------------------------------------------------------
;;; SQL helpers

(defun quote-ident (name)
  (unless (cl-ppcre:scan "^[a-z_][a-z0-9_]*$" name)
    (error "Unsafe SQL identifier ~s" name))
  (format nil "\"~a\"" name))

(defun table-name (class) (quote-ident (entity-table class)))

(defstruct (class-sql (:constructor %make-class-sql))
  fields         ; the ENTITY-FIELDS list this was computed from (identity check)
  columns        ; stored fields except id, in column order
  column-list    ; "seq", "id", ... for SELECT
  insert update find)

(defvar *class-sql* (make-hash-table :test 'eq :synchronized t)
  "Entity class -> CLASS-SQL: generated SQL text, rebuilt when the class's fields change.")

(defun class-sql (class)
  (let ((fields (entity-fields class))
        (cached (gethash class *class-sql*)))
    (if (and cached (eq (class-sql-fields cached) fields))
        cached
        (let* ((columns (remove "id" (entity-stored-fields class) :key #'field-json-name :test #'string=))
               (names (mapcar (lambda (f) (quote-ident (field-json-name f))) columns))
               (table (table-name class))
               (column-list (join-strings (cons "\"seq\", \"id\"" names) ", ")))
          (setf (gethash class *class-sql*)
                (%make-class-sql
                 :fields fields :columns columns :column-list column-list
                 :insert (format nil "INSERT INTO ~a (\"id\"~{, ~a~}) VALUES (?~{~*, ?~})" table names names)
                 :update (format nil "UPDATE ~a SET ~{~a = ?~^, ~} WHERE \"id\" = ?" table names)
                 :find (format nil "SELECT ~a FROM ~a WHERE \"id\" = ?" column-list table)))))))

(defun stored-columns (class)
  "Stored fields except id (id has its own column)."
  (class-sql-columns (class-sql class)))

(defun column-list (class)
  (class-sql-column-list (class-sql class)))

(defun row->entity (class row)
  (let ((instance (make-instance class)))
    (setf (entity-id instance) (second row))
    (loop for field in (stored-columns class)
          for value in (cddr row)
          do (setf (field-value instance field) (db->type (field-type field) value)))
    instance))

(defmacro with-constraint-mapping (&body body)
  `(handler-case (progn ,@body)
     (sqlite:sqlite-constraint-error (e)
       (declare (ignore e))
       (fail :conflict "Already exists (a unique value was repeated)"))))

(defmethod store-insert ((store sqlite-store) entity)
  (let* ((class (class-of entity))
         (info (class-sql class))
         (fields (class-sql-columns info))
         (sql (class-sql-insert info)))
    (with-constraint-mapping
      (apply #'exec sql (entity-id entity)
             (mapcar (lambda (f) (type->db (field-type f) (field-value entity f))) fields)))
    entity))

(defmethod store-update ((store sqlite-store) entity)
  (let* ((class (class-of entity))
         (info (class-sql class))
         (fields (class-sql-columns info))
         (sql (class-sql-update info)))
    (with-constraint-mapping
      (apply #'exec sql (append (mapcar (lambda (f) (type->db (field-type f) (field-value entity f))) fields)
                                (list (entity-id entity)))))
    entity))

(defmethod store-delete ((store sqlite-store) class-name id)
  (exec (format nil "DELETE FROM ~a WHERE \"id\" = ?" (table-name (find-class class-name))) id)
  t)

(defmethod store-find ((store sqlite-store) class-name id)
  (let* ((class (find-class class-name))
         (row (first (query (class-sql-find (class-sql class)) id))))
    (and row (row->entity class row))))

(defmethod store-lock-row ((store sqlite-store) class-name id)
  (declare (ignore class-name id))
  ;; BEGIN IMMEDIATE already holds SQLite's database-wide write lock.
  t)

(defun compile-where (class where params)
  "SQL text for WHERE; pushes parameters onto the PARAMS cell (a list in a cons)."
  (if (null where)
      "1"
      (destructuring-bind (op &rest args) where
        (flet ((col (name) (where-field class name) (quote-ident name))
               (param (name v) (push (where-value->db class name v) (car params)) "?"))
          (ecase op
            (:and (format nil "(~{~a~^ AND ~})" (mapcar (lambda (w) (compile-where class w params)) args)))
            (:or (format nil "(~{~a~^ OR ~})" (mapcar (lambda (w) (compile-where class w params)) args)))
            ((:= :/= :< :<= :> :>=)
             (format nil "~a ~a ~a" (col (first args))
                     (ecase op (:= "=") (:/= "<>") (:< "<") (:<= "<=") (:> ">") (:>= ">="))
                     (param (first args) (second args))))
            (:in (if (null (second args))
                     "0"
                     (format nil "~a IN (~{~a~^, ~})" (col (first args))
                             (mapcar (lambda (v) (param (first args) v)) (second args)))))
            (:null (format nil "~a IS NULL" (col (first args))))
            (:not-null (format nil "~a IS NOT NULL" (col (first args)))))))))

(defmethod store-select ((store sqlite-store) class-name &key where order-by limit offset)
  (let* ((class (find-class class-name))
         (params (list '()))
         (where-sql (compile-where class where params))
         (order (append order-by '(("seq" :asc))))
         (limit-sql (cond ((and limit offset) (format nil " LIMIT ~d OFFSET ~d" limit offset))
                          (limit (format nil " LIMIT ~d" limit))
                          (offset (format nil " LIMIT -1 OFFSET ~d" offset))
                          (t "")))
         (sql (format nil "SELECT ~a FROM ~a WHERE ~a ORDER BY ~{~a~^, ~}~a"
                      (column-list class) (table-name class) where-sql
                      (mapcar (lambda (o)
                                (where-field class (first o))
                                (format nil "~a ~a" (quote-ident (first o))
                                        (ecase (second o) (:asc "ASC") (:desc "DESC"))))
                              order)
                      limit-sql)))
    (mapcar (lambda (row) (row->entity class row))
            (apply #'query sql (reverse (car params))))))

;;; ------------------------------------------------------------------
;;; Migrations

(defun ddl (sql &key (module "core") (name "schema"))
  "Run the DDL statement SQL and record it as migration <module>_<nnnn>_<name>."
  (exec sql)
  (ddl-record sql module name))

(defun column-default (field)
  "SQL literal for FIELD's constant initform, so rows that predate a new
column (e.g. one a client extension adds) get the field's default."
  (let ((form (closer-mop:slot-definition-initform field)))
    (cond ((integerp form) (format nil "~d" form))
          ((eq form t) "1")             ; a boolean that defaults to true
          ((and (stringp form) (cl-ppcre:scan "^[^']*$" form)) (format nil "'~a'" form))
          ((and (consp form) (eq (first form) 'quote) (null (second form))) nil)
          (t nil))))

(defun existing-columns (table)
  (mapcar #'second (query (format nil "PRAGMA table_info(~a)" (quote-ident table)))))

(defun ensure-schema-history ()
  "The migration log; a database from before modules gains its module and
migration columns (recorded as the kernel's own first migrations)."
  (exec "CREATE TABLE IF NOT EXISTS \"schema_history\" (\"seq\" INTEGER PRIMARY KEY AUTOINCREMENT, \"statement\" TEXT NOT NULL, \"applied_at\" TEXT NOT NULL)")
  (let ((columns (existing-columns "schema_history")))
    (dolist (column '("module" "migration"))
      (unless (member column columns :test #'string=)
        (let ((sql (format nil "ALTER TABLE \"schema_history\" ADD COLUMN ~a TEXT" (quote-ident column))))
          (exec sql)
          (when (string= column "migration")
            (ddl-record sql "core" "schema_history_modules")))))))

(defun ddl-record (sql module name)
  (let ((number (1+ (first (first (query "SELECT COUNT(*) FROM \"schema_history\" WHERE \"module\" = ?" module))))))
    (exec "INSERT INTO \"schema_history\" (\"statement\", \"applied_at\", \"module\", \"migration\") VALUES (?, ?, ?, ?)"
          sql (format-rfc3339 (get-universal-time)) module (format nil "~a_~4,'0d_~a" module number name))))

(defun column-owner (field)
  (field-module field))

(defun migration-access ()
  "This connection's SQL, as core 2.0's migration takes it (core/core-migration.lisp)."
  (make-database-access :query #'query :run #'exec
                        :table-p (lambda (table) (and (existing-columns table) t))))

(defmethod store-revert-to-core-1 ((store sqlite-store))
  (store-call-in-transaction
   store
   (lambda ()
     (ensure-schema-history)
     (revert-database store (migration-access)))
   :write))

(defmethod store-migrate ((store sqlite-store) classes)
  (store-call-in-transaction
   store
   (lambda ()
     (ensure-schema-history)
     ;; A newer major refused, a 1.x database checked and core's own data
     ;; renamed, with the major's mark (spec/i18n.md 4.4), before anything
     ;; is added.
     (prepare-database store (migration-access))
     ;; Two passes: the kernel's and the modules' tables and columns in
     ;; dependency order (the order the classes were defined), then the
     ;; client's (tun-platform.md 2.6 and 2.7).
     (dolist (pass '(:platform :client))
       (dolist (class classes)
         (unless (entity-embedded-p class)
           (let* ((table (entity-table class))
                  (owner (entity-module class))
                  (existing (existing-columns table)))
             (when (and (null existing)
                        (eq pass (if (string= owner "client") :client :platform)))
               (ddl (format nil "CREATE TABLE ~a (\"seq\" INTEGER PRIMARY KEY AUTOINCREMENT, \"id\" TEXT NOT NULL UNIQUE~{, ~a~})"
                            (quote-ident table)
                            ;; Only the owner's columns: a client's columns on a
                            ;; module's table are the client's own migrations.
                            (mapcar (lambda (field)
                                      (format nil "~a ~a~@[ DEFAULT ~a~]" (quote-ident (field-json-name field))
                                              (type-sql (field-type field)) (column-default field)))
                                    (remove-if (lambda (field)
                                                 (and (eq pass :platform) (string= (column-owner field) "client")))
                                               (stored-columns class))))
                    :module owner :name (format nil "create_~a" table))
               (setf existing (existing-columns table)))
             (when existing
               (dolist (field (stored-columns class))
                 (unless (or (member (field-json-name field) existing :test #'string=)
                             (not (eq pass (if (string= (column-owner field) "client") :client :platform))))
                   (ddl (format nil "ALTER TABLE ~a ADD COLUMN ~a ~a~@[ DEFAULT ~a~]" (quote-ident table)
                                (quote-ident (field-json-name field)) (type-sql (field-type field))
                                (column-default field))
                        :module (column-owner field)
                        :name (format nil "add_~a_~a" table (field-json-name field))))))
             (when (and existing (eq pass :client))
               (dolist (columns (entity-indexes class))
                 (let ((name (format nil "idx_~a_~{~a~^_~}" table columns)))
                   (unless (query "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?" name)
                     (ddl (format nil "CREATE INDEX IF NOT EXISTS ~a ON ~a (~{~a~^, ~})"
                                  (quote-ident name) (quote-ident table) (mapcar #'quote-ident columns))
                          :module owner :name name))))
               (dolist (columns (entity-unique class))
                 (exec (format nil "CREATE UNIQUE INDEX IF NOT EXISTS ~a ON ~a (~{~a~^, ~})"
                               (quote-ident (format nil "uq_~a_~{~a~^_~}" table columns))
                               (quote-ident table) (mapcar #'quote-ident columns))))))))))
   :write)
  store)
