;;;; tests/core-migration-tests.lisp -- how core 2.0 opens a database that
;;;; core 1.x wrote, and the way back (spec/i18n.md 4.3 to 4.7), on SQLite and
;;;; on Postgres, from the dumps in tests/fixtures/core-1.23.1/: core, a
;;;; tenant of core alone with a client's own table named customers;
;;;; business, one with a customers module's customer; inbox, one that loaded
;;;; the inbox module and holds only its secret.

(in-package #:tun.tests)

(def-suite core-migration :in core)
(in-suite core-migration)

;;; ------------------------------------------------------------------
;;; Restoring a dump, and reading a database without migrating it

(defparameter +fixtures+
  (merge-pathnames "tests/fixtures/core-1.23.1/" (asdf:system-source-directory "tun")))

(defun dump-statements (path)
  "The SQL statements of the dump at PATH, one per element: comments, blank
lines and psql's backslash commands left out."
  (let ((statements '()) (current '()))
    (with-open-file (in path :external-format :utf-8)
      (loop for line = (read-line in nil)
            while line
            do (cond ((or (zerop (length (string-trim " " line)))
                          (and (null current) (or (string-prefix-p "--" line)
                                                  (string-prefix-p "\\" line)))))
                     (t (push line current)
                        (when (char= #\; (char (string-right-trim " " line)
                                               (1- (length (string-right-trim " " line)))))
                          (push (format nil "~{~a~^~%~}" (reverse current)) statements)
                          (setf current '()))))))
    (nreverse statements)))

(defun durable-labels ()
  "The durable stores this run has: SQLite, and Postgres with the test server."
  (if (postgres-available-p) '("sqlite" "postgres") '("sqlite")))

(defun raw-store (db)
  (tun.runtime::make-store (tun.runtime::database-designator db)))

(defmacro with-raw-store ((store db mode) &body body)
  "Run BODY in a MODE transaction of the store of DB, opened without
migrating it, with STORE bound."
  `(let ((,store (raw-store ,db)))
     (store-open ,store)
     (unwind-protect
          (store-call-in-transaction ,store (lambda () ,@body) ,mode)
       (store-close ,store))))

(defun store-rows (store sql)
  "The rows of SQL on STORE's connection of the transaction open now."
  (etypecase store
    (tun.store.sqlite:sqlite-store (sqlite:execute-to-list tun.store.sqlite::*connection* sql))
    (tun.store.postgres:postgres-store (tun.store.postgres::query sql))))

(defun restore-fixture (kind label)
  "A fresh database on the store LABEL names holding the dump of KIND."
  (let ((statements (dump-statements (merge-pathnames (format nil "~a.~a.sql" kind label)
                                                      +fixtures+))))
    (if (string= label "sqlite")
        (let ((path (scratch-path (format nil "fixture-~a" kind))))
          (sqlite:with-open-database (connection (namestring path))
            (dolist (statement statements)
              (sqlite:execute-non-query connection statement)))
          (namestring path))
        (let ((url (scratch-postgres (format nil "fixture_~a" kind))))
          (with-raw-store (store url :write)
            (dolist (statement statements)
              (tun.store.postgres::exec statement)))
          url))))

(defun run-sql (db &rest statements)
  "Run STATEMENTS on DB in one write, without migrating it."
  (with-raw-store (store db :write)
    (dolist (statement statements)
      (store-rows store statement))))

(defun db-rows (db sql)
  "The rows of SQL on DB, read without migrating it."
  (with-raw-store (store db :read)
    (store-rows store sql)))

(defun table-names (db)
  (with-raw-store (store db :read)
    (loop for table across (store-describe-schema store)
          for name = (jget table "name")
          unless (string-prefix-p "sqlite_" name) collect name)))

(defun table-columns-of (db table)
  (with-raw-store (store db :read)
    (loop for entry across (store-describe-schema store)
          when (string= (jget entry "name") table)
            return (loop for column across (jget entry "columns")
                         collect (jget column "name")))))

(defun contents (db &key (tables (table-names db)) columns)
  "DB's tables as an alist of (TABLE . ROWS): each row the values of its
columns (COLUMNS, an alist of table to column names, or all), leaving out
seq and the identity counters, written as text; the rows sorted."
  (loop for table in tables
        for names = (remove "seq" (or (cdr (assoc table columns :test #'string=))
                                      (table-columns-of db table))
                            :test #'string=)
        collect (cons table
                      (sort (mapcar (lambda (row) (format nil "~{~s~^|~}" row))
                                    (db-rows db (format nil "SELECT ~{\"~a\"~^, ~} FROM \"~a\""
                                                        names table)))
                            #'string<))))

(defun dump-columns (db)
  "Each table of DB with its column names: what a later comparison reads."
  (loop for table in (table-names db) collect (cons table (table-columns-of db table))))

(defun setting-values (db)
  "The stored settings of DB as an alist of key to value."
  (db-rows db "SELECT \"key\", \"value\" FROM \"setting\" ORDER BY \"key\""))

(defun major-mark-ids (db)
  (mapcar #'first (db-rows db (format nil "SELECT \"migration\" FROM \"schema_history\"
                                          WHERE \"module\" = '~a'" +core-major-module+))))

(defun migrate-alone (db &key (classes (all-entity-classes)))
  "What a start of 2.0 does to DB before it serves: the migrate transaction
for CLASSES and the settings' initialisation, without the job process or a
tick."
  (let* ((store (raw-store db))
         (app (make-instance 'application :store store
                                          :clock (make-instance 'test-clock
                                                                :now (get-universal-time)))))
    (store-open store)
    (unwind-protect
         (progn (let ((*application* app))
                  (store-migrate store classes))
                (with-application (app)
                  (initialise-settings)))
      (store-close store))))

(defun start (db)
  "Start core 2.0 on DB and stop it again; the condition that refused it, or NIL."
  (handler-case (let ((app (tun.runtime:open-application 'application :db db :test-clock t)))
                  (tun.runtime:close-application app)
                  nil)
    ((or newer-database database-refused) (refusal) refusal)))

(defun drop-loaded-module-secrets (db)
  "Delete the secrets this test image's modules make at start: the image loads
every module, a 1.x tenant of core alone none."
  (run-sql db "DELETE FROM \"setting\" WHERE \"key\" = 'inbox.secret'"))

;;; ------------------------------------------------------------------
;;; Opening a 1.x database (spec/i18n.md 4.4)

(test core-renames-its-own-keys-and-statuses-and-stores-the-locale-of-1x
  (dolist (label (durable-labels))
    (dolist (marked '(t nil))
      (let* ((db (restore-fixture "core" label))
             (before (setting-values db)))
        (unless marked
          (run-sql db (format nil "DELETE FROM \"schema_history\" WHERE \"module\" = '~a'"
                              +core-major-module+)))
        (is (null (start db)) "~a~:[ without its mark~;~]: it opens" label marked)
        (let ((after (setting-values db)))
          ;; The secrets among them keep their values, so link tokens and
          ;; the push key are the ones 1.x made.
          (loop for (old . new) in tun.core::+renamed-settings+
                do (is (equal (second (assoc old before :test #'string=))
                              (second (assoc new after :test #'string=)))
                       "~a: ~a keeps its value as ~a" label old new)
                   (is (null (assoc old after :test #'string=)) "~a: ~a is gone" label old))
          (is (equal "\"NOK\"" (second (assoc "locale.currency" after :test #'string=))) "~a" label)
          (is (equal "\"Europe/Oslo\"" (second (assoc "locale.time_zone" after :test #'string=)))
              "~a" label)
          (is (equal "\"nb\"" (second (assoc "locale.language" after :test #'string=))) "~a" label))
        (is (equal '("cancelled" "executed" "failed" "planned")
                   (sort (mapcar #'first (db-rows db "SELECT \"status\" FROM \"workflows\""))
                         #'string<))
            "~a: the workflows' statuses are English" label)
        (is (equal '(("kun_1" "planlagt") ("kun_2" "ny"))
                   (db-rows db "SELECT \"id\", \"status\" FROM \"customers\" ORDER BY \"id\""))
            "~a: the client's own customers are untouched" label)
        (is (member "core-major-2" (major-mark-ids db) :test #'string=)
            "~a: the database has core 2.0's mark" label)))))

(test a-new-database-gets-the-mark-and-no-locale
  (dolist (label (durable-labels))
    (let ((db (if (string= label "sqlite")
                  (namestring (scratch-path "new-2"))
                  (scratch-postgres "new_2"))))
      (is (null (start db)) "~a: it opens" label)
      (is (equal '("core-major-2") (major-mark-ids db)) "~a: only 2.0's mark" label)
      (is (notany (lambda (row) (string-prefix-p "locale." (first row))) (setting-values db))
          "~a: no locale is stored, so the application's defaults hold" label))))

(test a-second-start-changes-nothing
  (dolist (label (durable-labels))
    (let ((db (restore-fixture "core" label)))
      (start db)
      (drop-loaded-module-secrets db)
      (let ((once (contents db :tables '("setting" "workflows" "customers"))))
        (start db)
        (drop-loaded-module-secrets db)
        (is (equal once (contents db :tables '("setting" "workflows" "customers")))
            "~a: the second start renames nothing" label)
        (is (equal 1 (count "core-major-2" (major-mark-ids db) :test #'string=))
            "~a: one mark" label)))))

(test a-failure-midway-leaves-the-database-as-it-was
  (dolist (label (durable-labels))
    (dolist (step '(:renamed :marked))
      (let* ((db (restore-fixture "core" label))
             (columns (dump-columns db))
             (before (contents db :columns columns)))
        (let ((*core-migration-fault* (lambda (at) (when (eq at step) (error "planted at ~a" at)))))
          (signals error (migrate-alone db)))
        (is (equal before (contents db :tables (mapcar #'car columns) :columns columns))
            "~a: a failure at ~a changes nothing" label step)
        (is (not (member "core-major-2" (major-mark-ids db) :test #'string=))
            "~a: no mark after a failure at ~a" label step)
        (is (null (start db)) "~a: the next start completes" label)
        (is (member "core-major-2" (major-mark-ids db) :test #'string=) "~a" label)))))

(test a-failure-in-the-additive-migrations-leaves-the-database-as-it-was
  (dolist (label (durable-labels))
    (let* ((db (restore-fixture "core" label))
           (tables (table-names db))
           (columns (dump-columns db))
           (before (contents db :columns columns)))
      ;; Not an entity class: the migration fails on it after it has renamed
      ;; core's data, marked the database and added every table and column
      ;; before it (spec/i18n.md 4.4, step 5).
      (signals error (migrate-alone db :classes (append (all-entity-classes) '(:not-an-entity))))
      (is (equal tables (table-names db)) "~a: no table was added" label)
      (is (equal before (contents db :tables tables :columns columns))
          "~a: nothing was renamed, stored or marked" label)
      (is (not (member "core-major-2" (major-mark-ids db) :test #'string=)) "~a: no mark" label))))

(defun pre-module-history (db)
  "Rewrite DB's schema_history as a database from before modules has it: no
module, no migration id and no major mark, each table known only by the
statement that created it."
  (run-sql db "DELETE FROM \"schema_history\" WHERE \"migration\" IS NULL
                 OR \"migration\" NOT LIKE '%create%'"
           "UPDATE \"schema_history\" SET \"module\" = NULL, \"migration\" = NULL"))

(test a-database-from-before-modules-is-not-new
  (dolist (label (durable-labels))
    (let ((db (restore-fixture "core" label)))
      (pre-module-history db)
      ;; Without modules, the client's own customers table is known by its
      ;; name alone, which is the customers module's: emptied, it holds no
      ;; business data.
      (run-sql db "DELETE FROM \"customers\"")
      (is (null (db-rows db "SELECT 1 FROM \"schema_history\" WHERE \"migration\" IS NOT NULL"))
          "~a: no row has a migration id" label)
      (let ((refusal (start db)))
        (is (null refusal) "~a: it opens: ~a" label refusal))
      (let ((after (setting-values db)))
        (is (equal "\"nb\"" (second (assoc "locale.language" after :test #'string=)))
            "~a: it is taken as 1.x's and gets the locale of 1.x" label)
        (is (null (assoc "lenker.hemmelighet" after :test #'string=))
            "~a: its keys are renamed" label))
      (is (equal '("cancelled" "executed" "failed" "planned")
                 (sort (mapcar #'first (db-rows db "SELECT \"status\" FROM \"workflows\""))
                       #'string<))
          "~a: its workflows' statuses are renamed" label))
    (let ((db (restore-fixture "business" label)))
      (pre-module-history db)
      (refused-unchanged-p db label "customers"))))

(test a-refused-start-says-why-and-the-server-exits
  ;; The server's main exits 2 when OPEN-FOR-SERVING answers NIL.
  (dolist (label (durable-labels))
    (let* ((db (restore-fixture "business" label))
           (said (make-string-output-stream))
           (app (let ((*error-output* said))
                  (tun.runtime::open-for-serving 'application "server" :db db :test-clock t))))
      (when app (tun.runtime:close-application app))
      (is (null app) "~a: refused" label)
      (is (search "server: " (get-output-stream-string said)) "~a: and says why" label))))

;;; ------------------------------------------------------------------
;;; Refusals (spec/i18n.md 4.3, 4.4 step 1, 4.5)

(defun refused-unchanged-p (db label what)
  "Check that starting on DB is refused with DATABASE-REFUSED naming WHAT and
changes nothing."
  (let* ((columns (dump-columns db))
         (before (contents db :columns columns))
         (refusal (start db)))
    (is (typep refusal 'database-refused) "~a: ~a is refused" label what)
    (when refusal
      (is (search what (princ-to-string refusal)) "~a: the refusal names ~a: ~a" label what refusal))
    (is (equal before (contents db :tables (mapcar #'car columns) :columns columns))
        "~a: the refused start changed nothing" label)
    (is (not (member "core-major-2" (major-mark-ids db) :test #'string=)) "~a: no mark" label)))

(test a-1x-database-with-business-module-data-is-refused
  (dolist (label (durable-labels))
    (refused-unchanged-p (restore-fixture "business" label) label "customers")
    (refused-unchanged-p (restore-fixture "inbox" label) label "inbox")
    (let ((db (restore-fixture "core" label)))
      (run-sql db "INSERT INTO \"workflows\" (\"id\", \"kind\", \"status\") VALUES ('wf_x', 'tilbud_utløp', 'planlagt')")
      (refused-unchanged-p db label "orders"))
    (let ((db (restore-fixture "core" label)))
      (run-sql db "INSERT INTO \"jobs\" (\"id\", \"kind\") VALUES ('job_x', 'send_delivery')")
      (refused-unchanged-p db label "messaging"))
    (let ((db (restore-fixture "core" label)))
      ;; A database from before modules: its create rows have no module.
      (run-sql db "CREATE TABLE \"henvendelser\" (\"id\" TEXT)"
               "INSERT INTO \"henvendelser\" VALUES ('hen_1')"
               "INSERT INTO \"schema_history\" (\"statement\", \"applied_at\")
                VALUES ('CREATE TABLE \"henvendelser\" (\"id\" TEXT)', '2026-01-01T00:00:00Z')")
      (refused-unchanged-p db label "inbox"))))

(test a-database-a-newer-major-opened-is-refused-before-the-rest
  (dolist (label (durable-labels))
    (let ((db (restore-fixture "business" label)))
      (run-sql db (format nil "INSERT INTO \"schema_history\" (\"statement\", \"applied_at\", \"module\", \"migration\")
                               VALUES ('core major 3 opened this database', '2026-11-01T00:00:00Z', '~a', 'core-major-3')"
                          +core-major-module+))
      (let ((before (contents db)))
        (is (typep (start db) 'newer-database) "~a: the higher major is refused first" label)
        (is (equal before (contents db)) "~a: nothing changed" label)))))

(test a-1x-database-another-process-uses-is-refused
  (when (postgres-available-p)
    (let* ((db (restore-fixture "core" "postgres"))
           (other (raw-store db)))
      (store-open other)
      (unwind-protect
           (let ((key 424242))
             (is (store-claim-presence other key))
             (run-sql db (format nil "INSERT INTO \"job_processes\" (\"id\", \"started_at\", \"lock_key\")
                                      VALUES ('jpr_other', '2026-10-28T08:00:00Z', ~d)" key))
             (refused-unchanged-p db "postgres" "Another process"))
        (store-close other))
      (is (null (start db)) "postgres: once the other process is gone, it migrates"))))

;;; ------------------------------------------------------------------
;;; The way back (spec/i18n.md 4.6)

(defun revert (db)
  "Run --revert-to-core-1 on DB; its exit code, and what it said on standard
error."
  (let* ((said (make-string-output-stream))
         (code (let ((*standard-output* (make-broadcast-stream))
                     (*error-output* said))
                 (tun.runtime::revert-to-core-1 db "test"))))
    (values code (get-output-stream-string said))))

(defun core-tables (db)
  "The contents of core's settings, by key and value since a stored locale
gets a new id each time, of its workflows and of the client's customers."
  (drop-loaded-module-secrets db)
  (contents db :tables '("setting" "workflows" "customers")
               :columns '(("setting" "key" "value"))))

(test reverting-the-migration-alone-gives-back-the-dump
  (dolist (label (durable-labels))
    (let* ((db (restore-fixture "core" label))
           (columns (dump-columns db))
           (before (contents db :columns columns)))
      (migrate-alone db)
      (let ((migrated (core-tables db)))
        (is (eql 0 (revert db)) "~a: it reverts" label)
        (let ((after (contents db :tables (mapcar #'car columns) :columns columns)))
          (loop for (table . rows) in before
                for now = (cdr (assoc table after :test #'string=))
                do (if (string= table "schema_history")
                       ;; 2.0's additive migrations stay recorded, which 1.x ignores.
                       (is (subsetp rows now :test #'string=)
                           "~a: schema_history keeps every row of the dump" label)
                       (is (equal rows now) "~a: ~a is as in the dump" label table))))
        (is (notany (lambda (row) (search "tun-core" row))
                    (set-difference (cdr (assoc "schema_history" (contents db :tables '("schema_history"))
                                                :test #'string=))
                                    (cdr (assoc "schema_history" before :test #'string=))
                                    :test #'string=))
            "~a: no major mark beyond the dump's" label)
        (is (equal '("core-major-1") (major-mark-ids db)) "~a: 2.0's mark is gone" label)
        (is (null (start db)) "~a: 2.0 opens it again" label)
        (let ((again (core-tables db)))
          (is (equal migrated again)
              "~a: and migrates it again to the same settings, workflows and customers: ~s"
              label (loop for (table . rows) in again
                          for before = (cdr (assoc table migrated :test #'string=))
                          collect (list table (set-difference rows before :test #'string=)
                                        (set-difference before rows :test #'string=)))))
        (is (member "core-major-2" (major-mark-ids db) :test #'string=) "~a" label)))))

(test reverting-after-a-real-start-gives-back-the-dump-but-what-a-server-writes
  (dolist (label (durable-labels))
    (let* ((db (restore-fixture "core" label))
           (kept (set-difference (table-names db)
                                 '("jobs" "job_processes" "job_schedules" "audit" "receipt"
                                   "schema_history")
                                 :test #'string=))
           (columns (dump-columns db))
           (before (contents db :tables kept :columns columns)))
      (start db)
      (with-test-app (:db db)
        (call-ok "settings_set" "admin:ada" "key" "locale.currency" "value" "SEK"))
      (drop-loaded-module-secrets db)
      (is (eql 0 (revert db)) "~a: it reverts" label)
      (is (equal before (contents db :tables kept :columns columns))
          "~a: the tables a server does not write for itself are as in the dump" label)
      (is (notany (lambda (row) (string-prefix-p "locale." (first row))) (setting-values db))
          "~a: every locale setting is gone, the admin's currency too" label)
      (is (equal '("core-major-1") (major-mark-ids db)) "~a: 2.0's mark is gone" label))))

(test the-revert-refuses-what-it-cannot-undo
  (dolist (label (durable-labels))
    (is (eql 2 (revert (restore-fixture "core" label))) "~a: a database 2.0 never opened" label)
    (flet ((refused-with (statement what)
             (let ((db (restore-fixture "core" label)))
               (migrate-alone db)
               (drop-loaded-module-secrets db)
               (run-sql db statement)
               (let ((before (contents db)))
                 (is (eql 2 (revert db)) "~a: refused with ~a" label what)
                 (is (equal before (contents db)) "~a: ~a: nothing changed" label what)))))
      (refused-with "INSERT INTO \"setting\" (\"id\", \"key\", \"value\") VALUES ('set_i', 'inbox.secret', '\"s\"')"
                    "inbox.secret")
      (refused-with "INSERT INTO \"workflows\" (\"id\", \"kind\", \"status\") VALUES ('wf_q', 'quote_expiry', 'planned')"
                    "a quote_expiry workflow")
      (refused-with "INSERT INTO \"inquiries\" (\"id\") VALUES ('hen_1')" "a row of inquiries"))
    (let ((db (restore-fixture "core" label)))
      (migrate-alone db)
      (drop-loaded-module-secrets db)
      (run-sql db (format nil "INSERT INTO \"schema_history\" (\"statement\", \"applied_at\", \"module\", \"migration\")
                               VALUES ('core major 3 opened this database', '2026-11-01T00:00:00Z', '~a', 'core-major-3')"
                          +core-major-module+))
      (let ((before (contents db)))
        (multiple-value-bind (code said) (revert db)
          (is (eql 2 code) "~a: a higher major's mark is refused" label)
          (is (search "does not revert it" said) "~a: as a revert, not a start: ~a" label said))
        (is (equal before (contents db)) "~a: nothing changed" label)))))

(test the-revert-refuses-while-another-process-uses-the-database
  (when (postgres-available-p)
    (let* ((db (restore-fixture "core" "postgres"))
           (other (raw-store db)))
      (migrate-alone db)
      (drop-loaded-module-secrets db)
      (store-open other)
      (unwind-protect
           (let ((key 424243))
             (is (store-claim-presence other key))
             (run-sql db (format nil "INSERT INTO \"job_processes\" (\"id\", \"started_at\", \"lock_key\")
                                      VALUES ('jpr_other', '2026-10-28T08:00:00Z', ~d)" key))
             (let ((before (contents db)))
               (multiple-value-bind (code said) (revert db)
                 (is (eql 2 code) "postgres: refused")
                 (is (search "Another process" said) "postgres: says why: ~a" said))
               (is (equal before (contents db)) "postgres: nothing changed")))
        (store-close other))
      (is (eql 0 (revert db)) "postgres: once the other process is gone, it reverts"))))

(test a-failure-midway-through-the-revert-leaves-the-database-migrated
  (dolist (label (durable-labels))
    (let ((db (restore-fixture "core" label)))
      (migrate-alone db)
      (drop-loaded-module-secrets db)
      (let ((before (contents db)))
        (let ((*core-migration-fault* (lambda (at) (when (eq at :renamed) (error "planted")))))
          (signals error (revert db)))
        (is (equal before (contents db)) "~a: nothing was reverted" label)))))

(test the-1x-guard-refuses-a-migrated-database-and-opens-a-reverted-one
  (dolist (label (durable-labels))
    (let ((db (restore-fixture "core" label)))
      (migrate-alone db)
      (signals newer-database
        (ensure-core-major (major-mark-ids db) (constantly nil) :running 1))
      (drop-loaded-module-secrets db)
      (revert db)
      (is (null (ensure-core-major (major-mark-ids db) (constantly nil) :running 1))
          "~a: core 1.23.1 opens the reverted database" label))))

(test the-preflight-refuses-while-the-mark-is-present
  (dolist (label (durable-labels))
    (let ((db (restore-fixture "core" label)))
      (is (not (tun.runtime::core-2-marked-p db)) "~a: a 1.x database is not marked" label)
      (migrate-alone db)
      (is (tun.runtime::core-2-marked-p db) "~a: a migrated one is" label)
      (drop-loaded-module-secrets db)
      (revert db)
      (is (not (tun.runtime::core-2-marked-p db)) "~a: a reverted one is not" label))))

(defun preflight (db registry)
  "Run --rollback-preflight REGISTRY on DB; its exit code and what it said."
  (let* ((said (make-string-output-stream))
         (code (let ((*standard-output* said) (*error-output* said))
                 (tun.runtime::preflight-command 'application db registry "test"))))
    (values code (get-output-stream-string said))))

(test the-preflight-names-the-revert-before-it-reads-the-registry
  (dolist (label (durable-labels))
    (let ((db (restore-fixture "core" label))
          (nowhere (namestring (scratch-path "no-such-registry.json"))))
      (migrate-alone db)
      (multiple-value-bind (code said) (preflight db nowhere)
        (is (eql 3 code) "~a: refused while marked, whatever the registry" label)
        (is (search "--revert-to-core-1" said) "~a: naming the revert: ~a" label said))
      (when (string= label "sqlite")
        (let ((saved (uiop:getenv "DATABASE_URL")))
          (unwind-protect
               (progn (setf (uiop:getenv "DATABASE_URL") db)
                      (is (eql 3 (preflight (tun.runtime::argv-database
                                             '("server" "--rollback-preflight" "x"))
                                            nowhere))
                          "with DATABASE_URL alone"))
            (setf (uiop:getenv "DATABASE_URL") (or saved "")))))
      (drop-loaded-module-secrets db)
      (revert db)
      (signals file-error (preflight db nowhere)
        "~a: after the revert it reads the registry" label)
      (when (string= label "sqlite")
        (multiple-value-bind (code said) (preflight db (namestring (lite-registry-path)))
          (is (member code '(0 3)) "~a: and checks it as before: ~a" label said)
          (is (search "rollback preflight: " said))
          (is (not (search "--revert-to-core-1" said)) "~a: with no word of the revert" label))))))

(test the-preflight-without-a-database-is-refused
  (multiple-value-bind (code said) (preflight nil "registry.json")
    (is (eql 2 code))
    (is (search "--db PATH|URL or DATABASE_URL" said) "says what it needs: ~a" said)))

(test the-revert-and-the-preflight-read-database-url
  (let ((db (restore-fixture "core" "sqlite"))
        (saved (uiop:getenv "DATABASE_URL")))
    (unwind-protect
         (progn (setf (uiop:getenv "DATABASE_URL") db)
                (is (equal db (tun.runtime::argv-database '("server" "--revert-to-core-1")))))
      (setf (uiop:getenv "DATABASE_URL") (or saved "")))
    (is (equal "other" (tun.runtime::argv-database '("server" "--db" "other"))))))
