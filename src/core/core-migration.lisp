;;;; core/core-migration.lisp -- how core 2.0 opens a database (spec/i18n.md
;;;; 4.3 to 4.6): refuse a newer major, refuse a 1.x database that holds
;;;; business-module data, refuse while another process uses a 1.x one, then
;;;; rename core's own Norwegian keys and statuses and store the locale the
;;;; database was written in, with the core-major-2 mark, in the migrate
;;;; transaction.  And the way back, --revert-to-core-1.
;;;;
;;;; The durable adapters call these in their own transaction and give them
;;;; their SQL: a function of a statement with ? parameters and its values
;;;; that returns the rows, one that runs a statement, and one that says
;;;; whether a table exists.  The SQL is plain enough for SQLite and
;;;; Postgres alike.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; What core 2.0 renames in its own data (spec/i18n.md 4.4)

(defparameter +renamed-settings+
  '(("lenker.base_url" . "links.base_url") ("lenker.hemmelighet" . "links.secret")
    ("push.hemmelighet" . "push.secret"))
  "Core's setting keys, 1.x to 2.0.  A stored value moves with its key.")

(defparameter +renamed-workflow-statuses+
  '(("planlagt" . "planned") ("utført" . "executed") ("avbrutt" . "cancelled")
    ("feilet" . "failed"))
  "Workflow statuses, 1.x to 2.0.")

(defparameter +locale-of-1x+ '(("locale.currency" . "NOK") ("locale.time_zone" . "Europe/Oslo"))
  "What a 1.x database was written in, besides its language (spec/i18n.md 4.4).")

;;; ------------------------------------------------------------------
;;; Business-module data (spec/i18n.md 4.3)

(defparameter +business-tables-1x+
  '(("calendar" "calendar_events")
    ("catalog" "products" "recipes" "choice_groups" "catalog_changes")
    ("customers" "customers")
    ("inbox" "henvendelser")
    ("inventory" "articles" "inventory_movements" "transfers" "consumption_commands"
     "stock_levels" "reservations")
    ("invoicing" "invoices" "invoice_send_intents")
    ("messaging" "messages" "deliveries")
    ("notifications" "notifications")
    ("orders" "orders" "bookings" "quotes" "checklist_items" "plans" "plan_impacts"
     "plan_impact_queue")
    ("reviews" "reviews")
    ("staffing" "employees" "assignments" "assignment_overrides" "unavailabilities"
     "work_sessions")
    ("warehouse" "tasks" "task_events"))
  "Each business module and its tables in core 1.22 and 1.23, by their 1.x names.")

(defparameter +business-settings-1x+
  '(("innboks.hemmelighet" . "inbox") ("avsender.navn" . "messaging")
    ("avsender.epost" . "messaging") ("avsender.svar_til" . "messaging")
    ("tilbud.gyldig_dager" . "orders") ("anmeldelse.url" . "messaging"))
  "The settings a business module declared or read in 1.x, and the module.")

(defparameter +business-workflow-kinds-1x+
  '(("tilbud_utløp" . "orders") ("katalog_endring" . "orders") ("leveranse_vakt" . "messaging")
    ("tilbud_påminnelse" . "orders") ("neste_år" . "orders"))
  "The workflow kinds of a business module in 1.x, and the module.")

(defparameter +business-job-kinds+ '(("send_delivery" . "messaging"))
  "The job kinds of a business module, the same in 1.x and 2.0.")

(defun renamed-business-table (table)
  "TABLE, a business module's 1.x table, by its 2.0 name."
  (if (string= table "henvendelser") "inquiries" table))

(defparameter +business-settings-2+
  '(("inbox.secret" . "inbox") ("sender.name" . "messaging") ("sender.email" . "messaging")
    ("sender.reply_to" . "messaging") ("quotes.valid_days" . "orders")
    ("customer_review.url" . "messaging"))
  "The same settings by their 2.0 keys.")

(defparameter +business-workflow-kinds-2+
  '(("quote_expiry" . "orders") ("catalog_change" . "orders") ("delivery_watchdog" . "messaging")
    ("quote_reminder" . "orders") ("next_year" . "orders"))
  "The same workflow kinds by their 2.0 names.")

;;; ------------------------------------------------------------------
;;; Refusals

(define-condition database-refused (error)
  ((reason :initarg :reason :reader database-refused-reason))
  (:report (lambda (c s) (write-string (database-refused-reason c) s)))
  (:documentation "Core 2.0 refuses to open a database, or to revert it, as
spec/i18n.md 4.3 to 4.6 says.  Like NEWER-DATABASE, it is signalled in the
migrate transaction, which then changes nothing, and the server exits 2."))

(defun refuse-database (control &rest args)
  (error 'database-refused :reason (apply #'format nil control args)))

(defvar *core-migration-fault* nil
  "For tests: a function of the step's name (:RENAMED, :MARKED) called in the
migrate transaction after that step, to plant a failure there.")

(defun migration-step (step)
  (when *core-migration-fault* (funcall *core-migration-fault* step)))

;;; ------------------------------------------------------------------
;;; Reading the database

(defstruct (database-access (:conc-name db-))
  "How the migration reads and writes the database being opened: QUERY and
RUN take a statement with ? parameters and the values; TABLE-P says whether
a table exists."
  query run table-p)

(defun db-rows (db sql &rest params)
  (apply (db-query db) sql params))

(defun db-exec (db sql &rest params)
  (apply (db-run db) sql params))

(defun schema-rows (db)
  "The module, migration id and statement of every schema_history row."
  (db-rows db "SELECT \"module\", \"migration\", \"statement\" FROM \"schema_history\""))

(defun major-marks (rows)
  "The major marks among ROWS of SCHEMA-ROWS."
  (loop for (module migration) in rows
        when (and (equal module +core-major-module+) migration) collect migration))

(defun created-tables (rows)
  "The tables ROWS of SCHEMA-ROWS show created, as (TABLE . MODULE): a
create_ row names its module; one from before modules has none."
  (loop for (module migration statement) in rows
        for table = (or (and migration
                             (cl-ppcre:register-groups-bind (name)
                                 ("^.+_\\d{4}_create_(.+)$" migration)
                               name))
                        (and (null module) (stringp statement)
                             (cl-ppcre:register-groups-bind (name)
                                 ("(?i)^\\s*CREATE TABLE\\s+\"([^\"]+)\"" statement)
                               name)))
        when table collect (cons table module)))

(defun new-database-p (rows)
  "True when ROWS of SCHEMA-ROWS show no table created, by a create_
migration or, from before modules, by its statement: a new database
(spec/i18n.md 4.3)."
  (null (created-tables rows)))

(defun table-has-rows-p (db table)
  (and (funcall (db-table-p db) table)
       (db-rows db (format nil "SELECT 1 FROM \"~a\" LIMIT 1" table))))

(defun business-data (db rows &key (tables +business-tables-1x+) (settings +business-settings-1x+)
                                (workflow-kinds +business-workflow-kinds-1x+)
                                (table-name #'identity))
  "The module whose data the database holds, by the names TABLES, SETTINGS
and WORKFLOW-KINDS give, or NIL (spec/i18n.md 4.3).  TABLE-NAME maps a 1.x
table to the name to look for."
  (let ((created (created-tables rows)))
    (or
     ;; A row in a table a business module created.
     (loop for (module . module-tables) in tables
           thereis (loop for old in module-tables
                         for table = (funcall table-name old)
                         for creator = (assoc table created :test #'string=)
                         thereis (and creator
                                      (or (equal (cdr creator) module) (null (cdr creator)))
                                      (table-has-rows-p db table)
                                      module)))
     ;; A business module's rows in core's own tables.
     (and (funcall (db-table-p db) "setting")
          (loop for (key . module) in settings
                thereis (and (db-rows db "SELECT 1 FROM \"setting\" WHERE \"key\" = ?" key) module)))
     (and (funcall (db-table-p db) "workflows")
          (loop for (kind . module) in workflow-kinds
                thereis (and (db-rows db "SELECT 1 FROM \"workflows\" WHERE \"kind\" = ?" kind)
                             module)))
     (and (funcall (db-table-p db) "jobs")
          (loop for (kind . module) in +business-job-kinds+
                thereis (and (db-rows db "SELECT 1 FROM \"jobs\" WHERE \"kind\" = ?" kind) module))))))

(defun another-process-p (store db)
  "True when another process uses the database: a row of job_processes whose
lock key another process holds (spec/i18n.md 4.5).  On SQLite and the memory
store no lock is another's."
  (and (funcall (db-table-p db) "job_processes")
       (loop for (key) in (db-rows db "SELECT \"lock_key\" FROM \"job_processes\"")
             thereis (and key (store-present-p store key)))))

;;; ------------------------------------------------------------------
;;; Renaming, both ways

(defun rename-core-data (db pairs)
  "Rename core's settings and workflow statuses by PAIRS of (FROM . TO) for
each: the forward or the reverse of +RENAMED-SETTINGS+ and
+RENAMED-WORKFLOW-STATUSES+."
  (destructuring-bind (settings statuses) pairs
    (when (funcall (db-table-p db) "setting")
      (loop for (from . to) in settings
            do (db-exec db "UPDATE \"setting\" SET \"key\" = ? WHERE \"key\" = ?" to from)))
    (when (funcall (db-table-p db) "workflows")
      (loop for (from . to) in statuses
            do (db-exec db "UPDATE \"workflows\" SET \"status\" = ? WHERE \"status\" = ?"
                        to from)))))

(defun reversed (pairs)
  (mapcar (lambda (pair) (cons (cdr pair) (car pair))) pairs))

(defun store-locale-of-1x (db)
  "Store the locale a 1.x database was written in (spec/i18n.md 4.4)."
  (let ((entries (append +locale-of-1x+
                         (when (member "nb" (if (and (boundp '*application*) *application*)
                                                (application-languages *application*)
                                                +languages+)
                                       :test #'equal)
                           '(("locale.language" . "nb"))))))
    (loop for (key . value) in entries
          unless (db-rows db "SELECT 1 FROM \"setting\" WHERE \"key\" = ?" key)
            do (db-exec db "INSERT INTO \"setting\" (\"id\", \"key\", \"value\") VALUES (?, ?, ?)"
                        (new-id "set") key (to-json-string value)))))

(defun record-major-mark (db)
  (multiple-value-bind (statement mark) (core-major-mark)
    (db-exec db "INSERT INTO \"schema_history\" (\"statement\", \"applied_at\", \"module\", \"migration\")
                 VALUES (?, ?, ?, ?)"
             statement (format-rfc3339 (get-universal-time)) +core-major-module+ mark)))

;;; ------------------------------------------------------------------
;;; Opening and reverting

(defun prepare-database (store db)
  "Open the database DB reads for core 2.0, in the migrate transaction,
before the additive migrations (spec/i18n.md 4.4): refuse a higher major,
refuse a 1.x database that holds business-module data or that another
process uses, then rename core's own keys and statuses, store the locale of
1.x and write the core-major-2 mark.  A new database gets the mark alone."
  (let* ((rows (schema-rows db))
         (marks (major-marks rows)))
    (check-core-major marks)
    (multiple-value-bind (statement mark) (core-major-mark)
      (declare (ignore statement))
      (cond ((member mark marks :test #'string=))
            ((new-database-p rows) (record-major-mark db))
            (t
             (let ((module (business-data db rows)))
               (when module
                 (refuse-database "This database holds data of the module ~a written by core 1.x. ~
                                   Core 2.0 renamed the modules' stored identifiers and does not ~
                                   migrate them (spec/i18n.md §4.3). Keep this tenant on core 1.x."
                                  module)))
             (when (another-process-p store db)
               (refuse-database "Another process uses this database. Core 2.0 renames what core ~
                                 1.x reads at its first start, so stop the other process first ~
                                 (spec/i18n.md §4.5)."))
             (rename-core-data db (list +renamed-settings+ +renamed-workflow-statuses+))
             (store-locale-of-1x db)
             (migration-step :renamed)
             (record-major-mark db)
             (migration-step :marked))))))

(defun revert-database (store db)
  "Undo PREPARE-DATABASE in the transaction DB writes in (spec/i18n.md 4.6):
refuse a database without the core-major-2 mark or with a higher one, one
another process uses, and one holding business-module data under 2.0's
names; rename back core's keys and statuses, delete every locale.* setting
and the mark."
  (let* ((rows (schema-rows db))
         (marks (major-marks rows))
         (highest (highest-major marks)))
    (when (> highest (running-major))
      (refuse-database "Core major ~d has opened this database since core ~a migrated it. ~
                        Core ~a cannot undo what it may have changed, and does not revert it ~
                        (spec/i18n.md §4.6)."
                       highest (running-major) +core-version+))
    (multiple-value-bind (statement mark) (core-major-mark)
      (declare (ignore statement))
      (unless (member mark marks :test #'string=)
        (refuse-database "This database has no core-major-2 mark: core 2.0 has not migrated it, ~
                          and there is nothing to revert (spec/i18n.md §4.6).")))
    (when (another-process-p store db)
      (refuse-database "Another process uses this database. Stop the server before reverting it ~
                        (spec/i18n.md §4.6)."))
    (let ((module (business-data db rows :settings +business-settings-2+
                                         :workflow-kinds +business-workflow-kinds-2+
                                         :table-name #'renamed-business-table)))
      (when module
        (refuse-database "This database holds data of the module ~a written by core 2.0, which ~
                          core 1.x cannot read. It cannot be reverted (spec/i18n.md §4.6)."
                         module)))
    (rename-core-data db (list (reversed +renamed-settings+) (reversed +renamed-workflow-statuses+)))
    (migration-step :renamed)
    (when (funcall (db-table-p db) "setting")
      (db-exec db "DELETE FROM \"setting\" WHERE \"key\" LIKE 'locale.%'"))
    (multiple-value-bind (statement mark) (core-major-mark)
      (declare (ignore statement))
      (db-exec db "DELETE FROM \"schema_history\" WHERE \"module\" = ? AND \"migration\" = ?"
               +core-major-module+ mark))
    (migration-step :marked)
    t))

(defgeneric store-revert-to-core-1 (store)
  (:documentation "Undo core 2.0's migration of STORE's database in one write
transaction (REVERT-DATABASE), or refuse with DATABASE-REFUSED."))
