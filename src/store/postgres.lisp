;;;; store/postgres.lisp -- Postgres adapter for the store port (spec/store.md).
;;;;
;;;; * One writer at a time per database, across processes.  Each write
;;;;   transaction runs at READ COMMITTED and first takes a transaction-scoped
;;;;   advisory lock, so it sees everything committed before it got the lock
;;;;   and no other writer commits until it is done: the guarantee SQLite's
;;;;   BEGIN IMMEDIATE gives, which the kernel relies on.  Within one process
;;;;   writers also queue on a mutex for the one writer connection, so the
;;;;   wait is visible (STORE-WRITE-QUEUE-DEPTH) and bounded by the deadline;
;;;;   lock_timeout bounds the wait for the advisory lock the same way.
;;;; * Read transactions take a connection from a pool and run REPEATABLE
;;;;   READ, READ ONLY: one snapshot, never waiting for a writer.
;;;; * Nested transactions are SAVEPOINTs.  Postgres aborts a whole
;;;;   transaction on any error, where SQLite fails only the statement, so a
;;;;   write that may break a unique constraint runs in its own savepoint:
;;;;   the caller can handle the conflict and go on, as on SQLite.
;;;; * Values are those the kernel's types give for the store (TYPE->DB), so
;;;;   both adapters hold the same data.  Text columns use the "C" collation
;;;;   (code point order) and ORDER BY puts NULLs first ascending, as SQLite
;;;;   and the memory store do.
;;;; * Statements with parameters are prepared once per connection and kept.
;;;; * An entity's record policy (spec/store.md 6) is a condition in every
;;;;   statement that reads or writes it, the row being THIS: Postgres decides
;;;;   which rows a select returns, and a write's RETURNING says whether the
;;;;   row as written is still admitted.
;;;; * Migrations follow the SQLite adapter's rules and migration ids;
;;;;   Postgres's DDL is transactional, and it runs under the write lock, so
;;;;   two processes starting at once do not both migrate.

(defpackage #:tun.store.postgres
  (:use #:cl #:tun.core)
  (:export #:postgres-store #:postgres-url-p #:parse-postgres-url #:postgres-create-database))

(in-package #:tun.store.postgres)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Connection URLs

(defun postgres-url-p (string)
  "True when STRING is a Postgres connection URL rather than a file path."
  (and (stringp string)
       (or (string-prefix-p "postgresql://" string)
           (string-prefix-p "postgres://" string))))

(defun percent-decode (string)
  "STRING with its %XX escapes decoded as UTF-8."
  (let ((octets (make-array (length string) :element-type '(unsigned-byte 8) :fill-pointer 0))
        (i 0))
    (loop while (< i (length string))
          do (if (and (char= (char string i) #\%) (<= (+ i 3) (length string)))
                 (progn (vector-push (parse-integer string :start (1+ i) :end (+ i 3) :radix 16)
                                     octets)
                        (incf i 3))
                 (let ((char-octets (sb-ext:string-to-octets string :start i :end (1+ i)
                                                                    :external-format :utf-8)))
                   (dotimes (j (length char-octets))
                     (vector-push-extend (aref char-octets j) octets))
                   (incf i))))
    (sb-ext:octets-to-string (coerce octets '(simple-array (unsigned-byte 8) (*)))
                             :external-format :utf-8)))

(defparameter *url-pattern*
  "^postgres(?:ql)?://(?:([^:@/]*)(?::([^@/]*))?@)?([^:/?]*)(?::([0-9]+))?/([^?]+)(?:\\?(.*))?$"
  "user, password, host, port, database and query of a Postgres URL.")

(defun parse-postgres-url (url)
  "The connection parameters URL names, as a plist (:database :user :password
:host :port), or an error naming what is wrong.  :HOST is a socket directory
\(a string starting with /), a host name, or :UNIX for the default socket."
  (check-type url string)
  (multiple-value-bind (match groups) (cl-ppcre:scan-to-strings *url-pattern* url)
    (unless match
      (error "Not a Postgres URL: ~
              postgresql://[user[:password]@][host][:port]/database[?host=DIR]"))
    (destructuring-bind (user password host port database query) (coerce groups 'list)
      (let ((socket-directory nil))
        (when query
          (dolist (pair (cl-ppcre:split "&" query))
            (destructuring-bind (key &optional value) (cl-ppcre:split "=" pair :limit 2)
              (unless (and (string= key "host") value)
                (error "Unsupported parameter ~s in a Postgres URL (only host=DIR)" key))
              (setf socket-directory (percent-decode value)))))
        (list :database (percent-decode database)
              :user (if (plusp (length user))
                        (percent-decode user)
                        (or (uiop:getenv "USER") "postgres"))
              :password (and password (percent-decode password))
              :host (cond (socket-directory)
                          ((plusp (length host)) (percent-decode host))
                          (t :unix))
              :port (if port (parse-integer port) 5432))))))

(defun redacted-url (url)
  "URL without its password, for logs."
  (cl-ppcre:regex-replace "^(postgres(?:ql)?://[^:@/]*):[^@/]*@" url "\\1:***@"))

;;; ------------------------------------------------------------------
;;; The store and its connections

(defstruct (connection (:constructor make-connection (handle)))
  (handle nil :read-only t)
  (statements (make-hash-table :test 'equal)))   ; SQL text -> prepared statement name

(defclass postgres-store (store)
  ((url :initarg :url :reader postgres-store-url)
   (parameters :reader parameters)
   (pool :initform '() :accessor pool)
   (pool-lock :initform (sb-thread:make-mutex :name "postgres pool") :reader pool-lock)
   (write-lock :initform (sb-thread:make-mutex :name "postgres writer") :reader write-lock)
   (writer :initform nil :accessor writer-connection)
   (presence :initform nil :accessor presence-connection
             :documentation "The connection holding this process's presence lock, open as long as the store is.")
   (writers-waiting :initform (list 0) :reader writers-waiting)) ; (count), for ATOMIC-INCF
  (:documentation "A store on the Postgres database a postgresql:// URL names (spec/store.md)."))

(defmethod initialize-instance :after ((store postgres-store) &key url)
  (setf (slot-value store 'parameters) (parse-postgres-url url)))

(defvar *connection* nil "Connection of the transaction running in this thread.")
(defvar *savepoint* 0)

(defparameter *statement-cache-size* 512
  "Prepared statements kept per connection; beyond that they are all dropped
and prepared again as they recur (IN lists of many lengths make many texts).")

(defconstant +write-lock-key+ #x74756E
  "The advisory lock every write transaction takes (\"tun\" in ASCII).  One
tenant per database, so one key serialises all of a tenant's writers.")

(defconstant +presence-lock-class+ #x74756E
  "The first key of every presence lock, in Postgres's two-key space, which
the write lock's one key never meets.")

(defmethod store-description ((store postgres-store))
  (format nil "postgres:~a" (redacted-url (postgres-store-url store))))

(defmacro ignoring-connection-failure (&body body)
  "Run BODY, a clean-up step on a connection that may already be broken: a
failure of the database or of its socket is ignored, since the transaction
is over either way."
  `(handler-case (progn ,@body)
     ((or cl-postgres:database-error stream-error) () nil)))

(defun open-connection (store)
  (destructuring-bind (&key database user password host port) (parameters store)
    (let ((handle (without-deadline-interrupts
                    (cl-postgres:open-database database user password host port
                                               :no "postgres" "tun"))))
      ;; cl-postgres signals every notice as a Lisp warning; a server says
      ;; nothing the kernel acts on below WARNING.
      (cl-postgres:exec-query handle "SET client_min_messages TO WARNING")
      (make-connection handle))))

(defun close-connection (connection)
  (ignoring-connection-failure
    (cl-postgres:close-database (connection-handle connection))))

(defun connection-open-p (connection)
  (cl-postgres:database-open-p (connection-handle connection)))

(defun checkout (store)
  (or (sb-thread:with-mutex ((pool-lock store)) (pop (pool store)))
      (open-connection store)))

(defun checkin (store connection)
  "Return CONNECTION to the pool, or close it when the server dropped it."
  (if (connection-open-p connection)
      (sb-thread:with-mutex ((pool-lock store)) (push connection (pool store)))
      (close-connection connection)))

(defmethod store-open ((store postgres-store))
  (checkin store (checkout store))
  (sb-thread:with-mutex ((write-lock store))
    (unless (writer-connection store)
      (setf (writer-connection store) (open-connection store))))
  store)

(defmethod store-close ((store postgres-store))
  (sb-thread:with-mutex ((pool-lock store))
    (mapc #'close-connection (pool store))
    (setf (pool store) '()))
  (sb-thread:with-mutex ((write-lock store))
    (when (writer-connection store)
      (close-connection (writer-connection store))
      (setf (writer-connection store) nil)))
  ;; Closing the connection releases the presence lock with it.
  (when (presence-connection store)
    (close-connection (presence-connection store))
    (setf (presence-connection store) nil
          (store-presences store) '()))
  store)

;;; ------------------------------------------------------------------
;;; Presence (spec/store.md 3): a session advisory lock on a connection of
;;; its own, which Postgres releases the moment the process or the
;;; connection dies.

(defun try-lock (connection function key)
  "Call the advisory lock FUNCTION, such as pg_try_advisory_lock, on
CONNECTION for the presence KEY; true when it answered true."
  (eq t (caar (cl-postgres:exec-query (connection-handle connection)
                                      (format nil "SELECT ~a(~d, ~d)" function
                                              +presence-lock-class+ key)
                                      'cl-postgres:list-row-reader))))

(defmethod store-claim-presence ((store postgres-store) key)
  (unless (presence-connection store)
    (setf (presence-connection store) (open-connection store)))
  (when (try-lock (presence-connection store) "pg_try_advisory_lock" key)
    (push key (store-presences store))
    t))

(defmethod store-present-p ((store postgres-store) key)
  (or (and (member key (store-presences store)) t)
      (let ((connection (checkout store)))
        (unwind-protect
             (if (try-lock connection "pg_try_advisory_lock" key)
                 ;; We got it, so no one held it: give it back at once.
                 (progn (try-lock connection "pg_advisory_unlock" key) nil)
                 t)
          (checkin store connection)))))

(defmethod store-write-queue-depth ((store postgres-store))
  (car (writers-waiting store)))

;;; ------------------------------------------------------------------
;;; Statements

(defun sql-parameter (value)
  "VALUE as cl-postgres sends it: NIL is NULL here, never false."
  (if (null value) :null value))

(defun sql-row (row)
  "ROW with SQL NULLs as NIL."
  (substitute nil :null row))

(defun prepared-name (connection sql)
  "The name SQL is prepared under on CONNECTION, preparing it the first time."
  (let ((statements (connection-statements connection))
        (handle (connection-handle connection)))
    (or (gethash sql statements)
        (progn
          (when (>= (hash-table-count statements) *statement-cache-size*)
            (cl-postgres:exec-query handle "DEALLOCATE ALL")
            (clrhash statements))
          (let ((name (format nil "tun_~d" (hash-table-count statements))))
            (cl-postgres:prepare-query handle name sql)
            (setf (gethash sql statements) name))))))

(cl-postgres:def-row-reader named-row-reader (fields)
  ;; The column names first, then the rows: unlike LIST-ROW-READER, the
  ;; names survive a result without rows.
  (cons (map 'list #'cl-postgres:field-name fields)
        (loop while (cl-postgres:next-row)
              collect (loop for field across fields
                            collect (cl-postgres:next-field field)))))

(defun send-statement (sql params reader)
  "SQL's result on this thread's connection, read by READER: prepared when
there are PARAMS, else as one simple query."
  (let ((handle (connection-handle *connection*)))
    (if params
        (cl-postgres:exec-prepared handle (prepared-name *connection* sql)
                                   (mapcar #'sql-parameter params) reader)
        (cl-postgres:exec-query handle sql reader))))

(defun run (sql params &optional (reader 'cl-postgres:list-row-reader))
  "Run SQL with PARAMS on this thread's connection; what READER makes of the
result.  A statement left halfway by a non-local exit other than the
server's own error (an interrupt) leaves the connection in the middle of the
protocol, so it is closed; the next transaction opens a new one."
  (let ((started (trace-clock-us))
        (finished nil))
    (unwind-protect
         (multiple-value-prog1
             (handler-bind ((cl-postgres:database-error
                              (lambda (e) (declare (ignore e)) (setf finished t))))
               (without-deadline-interrupts (send-statement sql params reader)))
           (setf finished t)
           (note-store-statement sql started))
      (unless finished
        (close-connection *connection*)))))

(defun exec (sql &rest params)
  (run sql params)
  (values))

(defun query (sql &rest params)
  "SQL's rows, NULLs as NIL."
  (mapcar #'sql-row (run sql params)))

;;; ------------------------------------------------------------------
;;; Transactions

(defun take-write-lock ()
  "Wait for the database's write lock, no longer than the deadline allows."
  (let ((remaining (deadline-remaining-ms)))
    ;; 0 means no limit, which is right when there is no deadline.
    (query "SELECT set_config('lock_timeout', $1, true)"
           (format nil "~dms" (if remaining (max 1 (ceiling remaining)) 0))))
  (handler-case (query (format nil "SELECT pg_advisory_xact_lock(~d)" +write-lock-key+))
    (cl-postgres-error:lock-not-available ()
      (error 'deadline-exceeded))))

(defun call-with-top-transaction (begin function)
  (let ((ok nil))
    (exec begin)
    (unwind-protect
         (multiple-value-prog1 (funcall function)
           (exec "COMMIT")
           (setf ok t))
      (unless ok
        (ignoring-connection-failure (exec "ROLLBACK"))))))

(defun call-with-savepoint (function)
  (let ((name (format nil "sp~d" (incf *savepoint*)))
        (ok nil))
    (exec (format nil "SAVEPOINT ~a" name))
    (unwind-protect
         (multiple-value-prog1 (let ((*savepoint* *savepoint*)) (funcall function))
           (exec (format nil "RELEASE ~a" name))
           (setf ok t))
      (unless ok
        (ignoring-connection-failure
          (exec (format nil "ROLLBACK TO ~a" name))
          (exec (format nil "RELEASE ~a" name)))))))

(defun grab-write-mutex (store)
  "Wait in line for STORE's writer connection, no longer than the deadline
allows; true when it was taken."
  (let ((waiting (writers-waiting store)))
    (sb-ext:atomic-incf (car waiting))
    (unwind-protect
         (with-request-state (:waiting-write-lock)
           (let ((remaining (deadline-remaining-ms)))
             (sb-thread:grab-mutex (write-lock store)
                                   :timeout (and remaining (/ remaining 1000.0)))))
      (sb-ext:atomic-decf (car waiting)))))

(defun call-in-write-transaction (store function)
  "Run FUNCTION as one write transaction on the writer connection; return its
values once the commit is durable."
  (let ((outer-interruptible *interruptible*)
        (wait-start (trace-clock-us))
        (got nil))
    ;; The deadline watchdog unwinds a thread only where *INTERRUPTIBLE* is
    ;; true: inside FUNCTION.  Everywhere else here it waits, so it never
    ;; leaves a caller unsure whether its COMMIT happened.  The waits have
    ;; their own limits instead: the mutex's timeout and lock_timeout.
    (let ((*interruptible* nil))
      (unwind-protect
           (progn
             (setf got (grab-write-mutex store))
             (unless got
               (note-write-lock-wait (- (trace-clock-us) wait-start))
               (error 'deadline-exceeded))
             (unless (and (writer-connection store) (connection-open-p (writer-connection store)))
               (setf (writer-connection store) (open-connection store)))
             (let ((*connection* (writer-connection store))
                   (*savepoint* 0))
               (call-with-top-transaction
                "BEGIN ISOLATION LEVEL READ COMMITTED"
                (lambda ()
                  (take-write-lock)
                  (note-write-lock-wait (- (trace-clock-us) wait-start))
                  (let ((*interruptible* outer-interruptible))
                    (funcall function))))))
        (when got
          (sb-thread:release-mutex (write-lock store)))))))

(defmethod store-call-in-transaction ((store postgres-store) function mode)
  (cond (*connection*
         (if (eq mode :write) (call-with-savepoint function) (funcall function)))
        ((eq mode :write)
         (call-in-write-transaction store function))
        (t
         (let ((connection (checkout store)))
           (unwind-protect
                (let ((*connection* connection)
                      (*savepoint* 0))
                  (call-with-top-transaction "BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY"
                                             function))
             (checkin store connection))))))

;;; ------------------------------------------------------------------
;;; SQL helpers

(defun quote-ident (name)
  ;; Postgres would silently cut a longer name to 63 bytes.
  (unless (and (cl-ppcre:scan "^[a-z_][a-z0-9_]*$" name) (<= (length name) 63))
    (error "Unsafe SQL identifier ~s" name))
  (format nil "\"~a\"" name))

(defun index-name (prefix table columns)
  "PREFIX_TABLE_COLUMNS, shortened with a hash when it exceeds Postgres's 63."
  (let ((name (format nil "~a_~a_~{~a~^_~}" prefix table columns)))
    (if (<= (length name) 63)
        name
        (let ((digest (ironclad:digest-sequence
                       :sha256 (sb-ext:string-to-octets name :external-format :utf-8))))
          (format nil "~a_~(~a~)" (subseq name 0 54)
                  (subseq (ironclad:byte-array-to-hex-string digest) 0 8))))))

(defun table-name (class) (quote-ident (entity-table class)))

(defun column-type (field)
  "The Postgres column type of FIELD, from the kernel's SQLite name for it."
  (let ((sql (type-sql (field-type field))))
    (cond ((string= sql "INTEGER") "BIGINT")
          ((string= sql "TEXT") "TEXT COLLATE \"C\"")
          (t sql))))

(defstruct (class-sql (:constructor %make-class-sql))
  fields         ; the ENTITY-FIELDS list this was computed from (identity check)
  columns        ; stored fields except id, in column order
  column-list    ; "seq", "id", ... for SELECT
  insert update find)

(defvar *class-sql* (make-hash-table :test 'eq :synchronized t)
  "Entity class -> CLASS-SQL: generated SQL text, rebuilt when the class's fields change.")

(defun placeholders (from count)
  "The parameter markers $FROM ... $(FROM+COUNT-1)."
  (loop for i from from below (+ from count) collect (format nil "$~d" i)))

(defun class-sql (class)
  (let ((fields (entity-fields class))
        (cached (gethash class *class-sql*)))
    (if (and cached (eq (class-sql-fields cached) fields))
        cached
        (let* ((columns (remove "id" (entity-stored-fields class)
                                :key #'field-json-name :test #'string=))
               (names (mapcar (lambda (f) (quote-ident (field-json-name f))) columns))
               (table (table-name class))
               (column-list (join-strings (cons "\"seq\", \"id\"" names) ", ")))
          (setf (gethash class *class-sql*)
                (%make-class-sql
                 :fields fields :columns columns :column-list column-list
                 :insert (format nil "INSERT INTO ~a AS this (\"id\"~{, ~a~}) VALUES (~{~a~^, ~})"
                                 table names (placeholders 1 (1+ (length names))))
                 :update (format nil "UPDATE ~a AS this SET ~{~a = ~a~^, ~} WHERE \"id\" = $~d"
                                 table (mapcan #'list names (placeholders 1 (length names)))
                                 (1+ (length names)))
                 :find (format nil "SELECT ~a FROM ~a AS this WHERE \"id\" = $1"
                               column-list table)))))))

(defun stored-columns (class)
  "Stored fields except id (id has its own column)."
  (class-sql-columns (class-sql class)))

(defun row->entity (class row)
  (let ((instance (make-instance class)))
    (setf (entity-id instance) (second row))
    (loop for field in (stored-columns class)
          for value in (cddr row)
          do (setf (field-value instance field) (db->type (field-type field) value)))
    instance))

(defun call-with-constraint-mapping (class function)
  "Call FUNCTION, turning a unique violation into the conflict error.  When
CLASS has unique fields, in a savepoint, so the transaction survives it."
  (flet ((attempt ()
           (handler-case (funcall function)
             (cl-postgres-error:unique-violation ()
               (fail :conflict "Already exists (a unique value was repeated)")))))
    (if (entity-unique class)
        (call-with-savepoint #'attempt)
        (attempt))))

(defun field-parameters (entity fields)
  (mapcar (lambda (f) (type->db (field-type f) (field-value entity f))) fields))

(defun call-in-policy-savepoint (condition function)
  "Call FUNCTION, in a savepoint when there is a record policy CONDITION, so
a write the policy refuses leaves nothing behind (spec/store.md 6.5)."
  (if condition
      (call-with-savepoint function)
      (funcall function)))

(defmethod store-insert ((store postgres-store) entity)
  (let* ((class (class-of entity))
         (info (class-sql class))
         (parameters (cons (entity-id entity) (field-parameters entity (class-sql-columns info)))))
    (multiple-value-bind (condition values)
        (record-condition class (1+ (length parameters)))
      (call-in-policy-savepoint
       condition
       (lambda ()
         (call-with-constraint-mapping
          class
          (lambda ()
            (if condition
                (unless (first (first (apply #'query (format nil "~a RETURNING ~a"
                                                             (class-sql-insert info) condition)
                                             (append parameters values))))
                  (refuse-record-write class))
                (apply #'exec (class-sql-insert info) parameters)))))))
    entity))

(defmethod store-update ((store postgres-store) entity)
  (let* ((class (class-of entity))
         (info (class-sql class))
         (parameters (append (field-parameters entity (class-sql-columns info))
                             (list (entity-id entity)))))
    (multiple-value-bind (condition values)
        (record-condition class (1+ (length parameters)))
      (call-in-policy-savepoint
       condition
       (lambda ()
         (call-with-constraint-mapping
          class
          (lambda ()
            (if condition
                ;; Admitted before: the WHERE.  Admitted after: the RETURNING.
                (let ((rows (apply #'query (format nil "~a AND ~a RETURNING ~a"
                                                   (class-sql-update info) condition condition)
                                   (append parameters values))))
                  (cond ((null rows) (record-not-found (class-name class) (entity-id entity)))
                        ((not (first (first rows))) (refuse-record-write class))))
                (apply #'exec (class-sql-update info) parameters)))))))
    entity))

(defmethod store-delete ((store postgres-store) class-name id)
  (let ((delete (format nil "DELETE FROM ~a AS this WHERE \"id\" = $1"
                        (table-name (find-class class-name)))))
    (multiple-value-bind (condition values) (record-condition (find-class class-name) 2)
      (if condition
          (unless (apply #'query (format nil "~a AND ~a RETURNING 1" delete condition) id values)
            (record-not-found class-name id))
          (exec delete id))))
  t)

(defmethod store-find ((store postgres-store) class-name id)
  (let ((class (find-class class-name)))
    (multiple-value-bind (condition values) (record-condition class 2)
      (let ((row (first (apply #'query (format nil "~a~@[ AND ~a~]"
                                               (class-sql-find (class-sql class)) condition)
                               id values))))
        (and row (row->entity class row))))))

(defmethod store-lock-row ((store postgres-store) class-name id)
  (declare (ignore class-name id))
  ;; The write transaction already holds the database's write lock.
  t)

(defun compile-where (class where params)
  "SQL text for WHERE; pushes parameters onto the PARAMS cell (a list in a cons)."
  (if (null where)
      "TRUE"
      (destructuring-bind (op &rest args) where
        (flet ((col (name) (where-field class name) (quote-ident name))
               (param (name v)
                 (push (where-value->db class name v) (car params))
                 (format nil "$~d" (length (car params))))
               (each (wheres) (mapcar (lambda (w) (compile-where class w params)) wheres)))
          (ecase op
            (:and (format nil "(~{~a~^ AND ~})" (each args)))
            (:or (format nil "(~{~a~^ OR ~})" (each args)))
            ((:= :/= :< :<= :> :>=)
             (format nil "~a ~a ~a" (col (first args))
                     (ecase op (:= "=") (:/= "<>") (:< "<") (:<= "<=") (:> ">") (:>= ">="))
                     (param (first args) (second args))))
            (:in (if (null (second args))
                     "FALSE"
                     (format nil "~a IN (~{~a~^, ~})" (col (first args))
                             (mapcar (lambda (v) (param (first args) v)) (second args)))))
            (:null (format nil "~a IS NULL" (col (first args))))
            (:not-null (format nil "~a IS NOT NULL" (col (first args)))))))))

(defun order-term (class spec)
  "SQL for one ORDER-BY entry (\"field\" :asc|:desc): NULLs first ascending."
  (destructuring-bind (field direction) spec
    (where-field class field)
    (format nil "~a ~a" (quote-ident field)
            (ecase direction (:asc "ASC NULLS FIRST") (:desc "DESC NULLS LAST")))))

(defmethod store-select ((store postgres-store) class-name &key where order-by limit offset)
  (let* ((class (find-class class-name))
         (params (list '()))
         (where-sql (compile-where class where params))
         (order (mapcar (lambda (spec) (order-term class spec))
                        (append order-by '(("seq" :asc))))))
    (multiple-value-bind (condition values)
        (record-condition class (1+ (length (car params))))
      (let ((sql (format nil "SELECT ~a FROM ~a AS this WHERE ~a~@[ AND ~a~] ~
                              ORDER BY ~{~a~^, ~}~@[ LIMIT ~d~]~@[ OFFSET ~d~]"
                         (class-sql-column-list (class-sql class)) (table-name class) where-sql
                         condition order limit offset)))
        (mapcar (lambda (row) (row->entity class row))
                (apply #'query sql (append (reverse (car params)) values)))))))

(defmethod store-runs-queries-p ((store postgres-store))
  t)

(defmethod store-query ((store postgres-store) sql parameters)
  (destructuring-bind (columns &rest rows) (run sql parameters 'named-row-reader)
    (values (mapcar #'sql-row rows) columns)))

;;; ------------------------------------------------------------------
;;; Schema description

(defun table-names ()
  (mapcar #'first (query "SELECT table_name FROM information_schema.tables
                          WHERE table_schema = current_schema() AND table_type = 'BASE TABLE'
                          ORDER BY table_name")))

(defun table-columns-json (table)
  (jarr (loop for (column type nullable)
                in (query "SELECT column_name, data_type, is_nullable
                           FROM information_schema.columns
                           WHERE table_schema = current_schema() AND table_name = $1
                           ORDER BY ordinal_position"
                          table)
              collect (jobj "name" column "type" type
                            "nullable" (json-bool (string= nullable "YES"))))))

(defmethod store-describe-schema ((store postgres-store))
  (store-call-in-transaction
   store
   (lambda ()
     (values
      (jarr (loop for name in (table-names)
                  collect (jobj "name" name "columns" (table-columns-json name))))
      (jarr (loop for (seq statement applied-at module migration)
                    in (query "SELECT seq, statement, applied_at, module, migration
                               FROM schema_history ORDER BY seq")
                  collect (jobj "id" migration "seq" seq "applied_at" applied-at
                                "module" (or module :null) "statement" statement)))))
   :read))

;;; ------------------------------------------------------------------
;;; Migrations

(defun ddl (sql &key (module "core") (name "schema"))
  "Run the DDL statement SQL and record it as migration <module>_<nnnn>_<name>."
  (exec sql)
  (ddl-record sql module name))

(defun ddl-record (sql module name)
  (let ((number (1+ (first (first (query "SELECT COUNT(*) FROM \"schema_history\"
                                          WHERE \"module\" = $1"
                                         module))))))
    (exec "INSERT INTO \"schema_history\" (\"statement\", \"applied_at\", \"module\", \"migration\")
           VALUES ($1, $2, $3, $4)"
          sql (format-rfc3339 (get-universal-time)) module
          (format nil "~a_~4,'0d_~a" module number name))))

(defun column-default (field)
  "SQL literal for FIELD's constant initform, so rows that predate a new
column (e.g. one a client extension adds) get the field's default."
  (let ((form (closer-mop:slot-definition-initform field)))
    (cond ((integerp form) (format nil "~d" form))
          ((eq form t) "1")             ; a boolean that defaults to true
          ((and (stringp form) (cl-ppcre:scan "^[^']*$" form)) (format nil "'~a'" form))
          (t nil))))

(defun column-definition (field)
  (format nil "~a ~a~@[ DEFAULT ~a~]" (quote-ident (field-json-name field)) (column-type field)
          (column-default field)))

(defun existing-columns (table)
  (mapcar #'first (query "SELECT column_name FROM information_schema.columns
                          WHERE table_schema = current_schema() AND table_name = $1
                          ORDER BY ordinal_position"
                         table)))

(defun index-exists-p (name)
  (query "SELECT 1 FROM pg_indexes WHERE schemaname = current_schema() AND indexname = $1" name))

(defun ensure-schema-history ()
  (exec "CREATE TABLE IF NOT EXISTS \"schema_history\" (
           \"seq\" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
           \"statement\" TEXT NOT NULL, \"applied_at\" TEXT NOT NULL,
           \"module\" TEXT, \"migration\" TEXT)"))

(defun client-owned-p (owner)
  (string= owner "client"))

(defun create-table (class pass)
  "Create CLASS's table with the columns its owner adds in PASS: on the
platform pass a client's columns on a module's table are left for the
client's own migrations."
  (let ((table (entity-table class)))
    (ddl (format nil "CREATE TABLE ~a (\"seq\" BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, ~
                      \"id\" TEXT COLLATE \"C\" NOT NULL UNIQUE~{, ~a~})"
                 (quote-ident table)
                 (mapcar #'column-definition
                         (remove-if (lambda (field)
                                      (and (eq pass :platform)
                                           (client-owned-p (field-module field))))
                                    (stored-columns class))))
         :module (entity-module class) :name (format nil "create_~a" table))))

(defun create-indexes (class)
  (let ((table (entity-table class)))
    (dolist (columns (entity-indexes class))
      (let ((name (index-name "idx" table columns)))
        (unless (index-exists-p name)
          (ddl (format nil "CREATE INDEX ~a ON ~a (~{~a~^, ~})"
                       (quote-ident name) (quote-ident table) (mapcar #'quote-ident columns))
               :module (entity-module class) :name name))))
    (dolist (columns (entity-unique class))
      (let ((name (index-name "uq" table columns)))
        (unless (index-exists-p name)
          (exec (format nil "CREATE UNIQUE INDEX ~a ON ~a (~{~a~^, ~})"
                        (quote-ident name) (quote-ident table) (mapcar #'quote-ident columns))))))))

(defun numbered-parameters (sql)
  "SQL with each ? parameter as Postgres's $1, $2 ...; the migration's SQL
holds no ? inside a string."
  (let ((n 0))
    (cl-ppcre:regex-replace-all "\\?" sql (lambda (&rest args)
                                              (declare (ignore args))
                                              (format nil "$~d" (incf n)))
                                :simple-calls t)))

(defun migration-access ()
  "This connection's SQL, as core 2.0's migration takes it (core/core-migration.lisp)."
  (make-database-access :query (lambda (sql &rest params)
                                 (apply #'query (numbered-parameters sql) params))
                        :run (lambda (sql &rest params)
                               (apply #'exec (numbered-parameters sql) params))
                        :table-p (lambda (table) (and (existing-columns table) t))))

(defmethod store-revert-to-core-1 ((store postgres-store))
  (store-call-in-transaction
   store
   (lambda ()
     (ensure-schema-history)
     (revert-database store (migration-access)))
   :write))

(defmethod store-migrate ((store postgres-store) classes)
  (store-call-in-transaction
   store
   (lambda ()
     (ensure-schema-history)
     ;; A newer major refused, a 1.x database checked and core's own data
     ;; renamed, with the major's mark (spec/i18n.md 4.4), before anything
     ;; is added.
     (prepare-database store (migration-access))
     (ensure-contents-table)
     ;; Two passes, as on SQLite: the kernel's and the modules' tables and
     ;; columns in dependency order, then the client's (tun-platform.md 2.6
     ;; and 2.7).
     (dolist (pass '(:platform :client))
       (flet ((in-pass-p (owner) (eq pass (if (client-owned-p owner) :client :platform))))
         (dolist (class (remove-if #'entity-embedded-p classes))
           (let ((table (entity-table class)))
             (when (and (null (existing-columns table)) (in-pass-p (entity-module class)))
               (create-table class pass))
             (let ((existing (existing-columns table)))
               (when existing
                 (dolist (field (stored-columns class))
                   (unless (or (member (field-json-name field) existing :test #'string=)
                               (not (in-pass-p (field-module field))))
                     (ddl (format nil "ALTER TABLE ~a ADD COLUMN ~a"
                                  (quote-ident table) (column-definition field))
                          :module (field-module field)
                          :name (format nil "add_~a_~a" table (field-json-name field)))))
                 (when (eq pass :client)
                   (create-indexes class)))))))))
   :write)
  store)

;;; ------------------------------------------------------------------
;;; Files' content (spec/files.md 5.1): a table of its own, so a record's
;;; list of files never reads their bytes, written in the record's
;;; transaction.  Read a part at a time, so no answer holds a whole file.

(defparameter +contents-table-sql+
  "CREATE TABLE \"attachment_contents\" (\"id\" TEXT COLLATE \"C\" PRIMARY KEY,
                                         \"content\" BYTEA NOT NULL)")

(defun ensure-contents-table ()
  (unless (existing-columns "attachment_contents")
    (ddl +contents-table-sql+ :name "create_attachment_contents")))

(defmethod store-write-content ((store postgres-store) id octets)
  (assert-writable)
  (exec "INSERT INTO \"attachment_contents\" (\"id\", \"content\") VALUES ($1, $2)"
        id (coerce octets '(simple-array (unsigned-byte 8) (*))))
  id)

(defmethod store-read-content ((store postgres-store) id start length)
  ;; substring counts from 1.
  (let ((row (first (query "SELECT substring(\"content\" FROM $2 FOR $3)
                            FROM \"attachment_contents\" WHERE \"id\" = $1"
                           id (1+ start) length))))
    (and row (first row))))

(defmethod store-delete-content ((store postgres-store) id)
  (assert-writable)
  (exec "DELETE FROM \"attachment_contents\" WHERE \"id\" = $1" id)
  t)

;;; ------------------------------------------------------------------
;;; Tooling

(defun postgres-create-database (url name)
  "Create the empty database NAME on the server URL names, and return a URL
for it.  For tests and tooling; NAME is an identifier, never user input."
  (check-type url string)
  (check-type name string)
  (let ((*connection* (open-connection (make-instance 'postgres-store :url url))))
    (unwind-protect (exec (format nil "CREATE DATABASE ~a" (quote-ident name)))
      (close-connection *connection*)))
  (cl-ppcre:regex-replace "^(postgres(?:ql)?://[^/]*/)[^?]+" url (format nil "\\1~a" name)))
