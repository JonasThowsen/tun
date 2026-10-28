;;;; tests/store-tests.lisp -- the store port on every adapter (spec/store.md):
;;;; real transactions, restart durability, additive migration, the ledger
;;;; invariant under truly concurrent requests, and two applications on one
;;;; Postgres database.  Postgres runs when TUN_TEST_POSTGRES names a server
;;;; (bin/test provides one), and is skipped otherwise.

(in-package #:tun.tests)

(def-suite store :in core)
(in-suite store)

(defmacro with-each-store ((label) &body body)
  "Run BODY on a fresh store of every adapter: memory, SQLite and, when the
test server is there, Postgres."
  `(loop for (,label . db) in (cons (cons "memory" nil) (scratch-databases "contract"))
         do (with-test-app (:db db)
              (with-application (*app*)
                ,@body))))

(defmacro with-each-durable-store ((label db name) &body body)
  "Run BODY with DB bound to a fresh database NAME on SQLite and, when the test
server is there, on Postgres."
  `(loop for (,label . ,db) in (scratch-databases ,name)
         do (progn ,@body)))

(test postgres-urls
  (is (tun.store.postgres:postgres-url-p "postgresql://db.example/tun"))
  (is (tun.store.postgres:postgres-url-p "postgres://db.example/tun"))
  (is (not (tun.store.postgres:postgres-url-p "/var/lib/tun/tun.sqlite")))
  (is (equal '(:database "tun" :user "app" :password "p@ss/ord" :host "db.example" :port 6543)
             (tun.store.postgres:parse-postgres-url "postgresql://app:p%40ss%2ford@db.example:6543/tun")))
  (is (equal '(:database "tun" :user "tun" :password nil :host "/tmp/pg dir" :port 5432)
             (tun.store.postgres:parse-postgres-url "postgresql://tun@/tun?host=/tmp/pg%20dir"))
      "a host parameter names the socket directory")
  (is (eq :unix (getf (tun.store.postgres:parse-postgres-url "postgresql://tun@/tun") :host))
      "no host: the default socket")
  (signals error (tun.store.postgres:parse-postgres-url "postgresql://db.example/tun?sslmode=require"))
  (signals error (tun.store.postgres:parse-postgres-url "postgresql://db.example/"))
  (is (string= "postgres:postgresql://app:***@db.example/tun"
               (store-description (make-instance 'tun.store.postgres:postgres-store
                                                 :url "postgresql://app:secret@db.example/tun")))
      "the description never shows the password"))

(test postgres-adapter-under-test
  (if (postgres-available-p)
      (pass "the store tests run on Postgres too")
      (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")))

(test store-contract
  (with-each-store (store)
    (with-transaction (:write)
      (dolist (n '("C" "A" "B"))
        (insert (make-instance 'widget :name n))))
    (with-transaction (:read)
      (let ((all (select 'widget)))
        (is (equal '("C" "A" "B") (mapcar #'widget-name all)) "~a: insertion order" store)
        (is (equal '("A" "B" "C") (mapcar #'widget-name (select 'widget :order-by '(("name" :asc))))))
        (is (equal '("B") (mapcar #'widget-name (select 'widget :order-by '(("name" :asc)) :limit 1 :offset 1))))
        (is (equal '("A" "C") (sort (mapcar #'widget-name (select 'widget :where '(:in "name" ("A" "C" "Z"))))
                                    #'string<)))
        (is (equal '("C") (mapcar #'widget-name (select 'widget :where '(:and (:>= "name" "B") (:/= "name" "B")))))
            "~a: compound where" store)
        (let ((one (fetch 'widget (entity-id (first all)))))
          (is (string= "C" (widget-name one)))
          (is (null (fetch 'widget "wdg_missing"))))))
    ;; update and delete
    (let ((id (with-transaction (:read) (entity-id (select-one 'widget :where '(:= "name" "A"))))))
      (with-transaction (:write)
        (let ((w (fetch! 'widget id)))
          (setf (widget-status w) "arkivert")
          (save w)))
      (with-transaction (:read)
        (is (string= "arkivert" (widget-status (fetch 'widget id)))))
      (with-transaction (:write) (delete-entity (fetch 'widget id)))
      (with-transaction (:read) (is (null (fetch 'widget id)))))))

(test transactions-roll-back
  (with-each-store (store)
    (ignore-errors
     (with-transaction (:write)
       (insert (make-instance 'widget :name "borte"))
       (error "boom")))
    (with-transaction (:read)
      (is (null (select 'widget)) "~a: a failed transaction leaves nothing" store))
    ;; A savepoint rolls back alone; the outer transaction commits.
    (with-transaction (:write)
      (insert (make-instance 'widget :name "ytre"))
      (ignore-errors
       (with-transaction (:write)
         (insert (make-instance 'widget :name "indre"))
         (error "inner"))))
    (with-transaction (:read)
      (is (equal '("ytre") (mapcar #'widget-name (select 'widget))) "~a: savepoint" store))))

(test unique-constraints-map-to-conflict
  (with-each-store (store)
    (with-transaction (:write)
      (insert (make-instance 'tun.core::setting :key "x" :value 1)))
    (signals operation-error
      (with-transaction (:write)
        (insert (make-instance 'tun.core::setting :key "x" :value 2))))))

(test writes-need-a-write-transaction
  (with-each-store (store)
    (signals error (insert (make-instance 'widget :name "uten transaksjon")))
    (signals error (with-transaction (:read) (insert (make-instance 'widget :name "i lesing"))))))

;;; ------------------------------------------------------------------
;;; Restart durability

(test restart-durability
  (with-each-durable-store (store db "restart")
    (restart-durability-on db)))

(defun restart-durability-on (db)
  (let (customer-id product-id token widget-id)
    (with-test-app (:db db)
      (setf customer-id (jget (call-ok "customers_create" "employee:anna" "name" "Varig Kunde"
                                       "email" "varig@example.no" "request_key" "varig")
                              "id"))
      (setf product-id (jget (call-ok "products_create" "employee:anna" "name" "Begre" "kind" "forbruk"
                                      "unit" "stk" "unit_price_ore" 100 "stock_tracked" t)
                             "id"))
      (call-ok "inventory_receive" "employee:anna" "product_id" product-id "quantity" 7)
      (setf widget-id (jget (call-ok "widgets_create" "employee:anna" "name" "Før omstart") "id"))
      (setf token (jget (call-ok "widgets_archive" "employee:anna" "id" widget-id) "confirmation_token"))
      (call-ok "clock_set" "admin:ada" "now" "2026-03-01T09:05:00Z"))
    ;; A new process image would see exactly this: a fresh application on the same file.
    (with-test-app (:db db)
      (is (string= "2026-03-01T09:05:00Z" (jget (call-ok "clock_get" "viewer:vera") "now"))
          "the virtual clock survives restart")
      (is (string= "Varig Kunde" (jget (call-ok "customers_get" "viewer:vera" "id" customer-id) "name")))
      (is (= 7 (jget (call-ok "inventory_balance" "viewer:vera" "product_id" product-id) "on_hand")))
      (is (string= customer-id
                   (jget (call-ok "customers_create" "employee:anna" "name" "Varig Kunde"
                                  "email" "varig@example.no" "request_key" "varig")
                         "id"))
          "idempotency receipts are durable")
      (is (string= "arkivert" (jget (call-ok "widgets_archive" "employee:anna" "id" widget-id
                                             "confirmation_token" token)
                                    "status"))
          "a confirmation token issued before restart is still valid (stored hashed)")
      (is (plusp (length (jget (call-ok "audit_list" "viewer:vera") "items")))))))

(test additive-migration-backfills-defaults
  (with-each-durable-store (store db "migrate")
    (with-test-app (:db db)
      (call-ok "widgets_create" "employee:anna" "name" "Gammel rad"))
    (with-test-app (:db db)
      (with-application (*app*)
        (with-transaction (:read)
          (let ((history (raw-sql "SELECT statement FROM schema_history
                                   WHERE statement LIKE '%widgets%'")))
            (is (= 1 (length history)) "~a: reopening applies no DDL twice: ~s" store history)))))
    ;; Simulate a column added later by an extension: drop it from the
    ;; schema, then migrate again.
    (with-test-app (:db db)
      (with-application (*app*)
        (with-transaction (:write)
          (raw-sql "ALTER TABLE widgets DROP COLUMN status"))))
    (with-test-app (:db db)
      (let ((items (jget (call-ok "widgets_count" "viewer:vera") "count")))
        (is (= 1 items)))
      (with-application (*app*)
        (with-transaction (:read)
          (is (string= "aktiv" (widget-status (select-one 'widget)))
              "~a: ALTER TABLE ... ADD COLUMN ... DEFAULT backfilled the existing row" store))))))

;;; ------------------------------------------------------------------
;;; Which core major opened a database (spec/store.md 2, item 10)

(defun core-major-marks ()
  "The (migration statement) rows recorded under the major marks' module."
  (with-application (*app*)
    (with-transaction (:read)
      (raw-sql (format nil "SELECT migration, statement FROM schema_history
                            WHERE module = '~a' ORDER BY seq" +core-major-module+)))))

(defun schema-snapshot (db)
  "DB's tables, columns and history as JSON text, read without migrating."
  (let ((store (tun.runtime::make-store db)))
    (store-open store)
    (unwind-protect
         (multiple-value-bind (tables migrations) (store-describe-schema store)
           (list (to-json-string tables) (to-json-string migrations)))
      (store-close store))))

(defun store-connected-p (store)
  (and (etypecase store
         (tun.store.sqlite:sqlite-store (tun.store.sqlite::writer-connection store))
         (tun.store.postgres:postgres-store (tun.store.postgres::writer-connection store)))
       t))

(test opening-a-database-records-its-core-major-once
  (with-each-durable-store (store db "major-mark")
    (with-test-app (:db db))
    (with-test-app (:db db)
      (is (equal '(("core-major-1" "core major 1 opened this database")) (core-major-marks))
          "~a: one mark after two starts" store)
      (multiple-value-bind (tables migrations) (with-application (*app*) (store-describe-schema *store*))
        (declare (ignore tables))
        (is (find "core-major-1" (coerce migrations 'list) :key (lambda (m) (jget m "id")) :test #'equal)
            "~a: introspect_schema lists the mark" store)))))

(test a-database-with-no-mark-opens-and-gains-one
  (with-each-durable-store (store db "major-unmarked")
    (with-test-app (:db db)
      (call-ok "widgets_create" "employee:anna" "name" "Fra 1.23.0")
      ;; A database from before 1.23.1 has no mark.
      (with-application (*app*)
        (with-transaction (:write)
          (raw-sql (format nil "DELETE FROM schema_history WHERE module = '~a'" +core-major-module+)))))
    (with-test-app (:db db)
      (is (= 1 (jget (call-ok "widgets_count" "viewer:vera") "count")) "~a: it opens as before" store)
      (is (equal '("core-major-1") (mapcar #'first (core-major-marks)))))))

(test a-database-a-newer-major-opened-is-refused
  (with-each-durable-store (store db "major-newer")
    (with-test-app (:db db)
      (call-ok "widgets_create" "employee:anna" "name" "Fra 2.0")
      (with-application (*app*)
        (with-transaction (:write)
          ;; What a 2.0 start would leave: its mark beside 1's, and a
          ;; column this major's migration would add back if it ran.
          (raw-sql (format nil "INSERT INTO schema_history (statement, applied_at, module, migration)
                                VALUES ('core major 2 opened this database', '2026-11-01T00:00:00Z',
                                        '~a', 'core-major-2')" +core-major-module+))
          (raw-sql "ALTER TABLE widgets DROP COLUMN status"))))
    (let ((before (schema-snapshot db))
          (opened (tun.runtime::make-store db)))
      (let ((refusal (handler-case (progn (tun.runtime:open-application 'application :store opened
                                                                           :test-clock t)
                                          nil)
                       (newer-database (e) e))))
        (is (typep refusal 'newer-database) "~a: the start is refused" store)
        (when refusal
          (is (string= (format nil "Core major 2 has opened this database; core ~a (major 1) ~
                                    cannot read what it may have changed and refuses to start."
                               +core-version+)
                       (princ-to-string refusal))
              "~a: the message names both majors" store)))
      (is (not (store-connected-p opened)) "~a: the refused start closed its connections" store)
      (is (equal before (schema-snapshot db))
          "~a: nothing was migrated or recorded" store))))

;;; ------------------------------------------------------------------
;;; Ledger invariant under concurrency

(defun stock-product (on-hand)
  (let ((id (jget (call-ok "products_create" "employee:anna" "name" "Sukkerspinnpinner" "kind" "forbruk"
                           "unit" "stk" "unit_price_ore" 200 "stock_tracked" t)
                  "id")))
    (call-ok "inventory_receive" "employee:anna" "product_id" id "quantity" on-hand)
    id))

(defun check-ledger (product-id)
  "The invariant: revisions 1..n consecutive, every balance_after equals the
running sum, on_hand equals the sum of stock movements."
  (let* ((movements (reverse (coerce (jget (call-ok "inventory_movements" "viewer:vera"
                                                    "product_id" product-id "limit" 100)
                                           "items")
                                     'list)))
         (running 0)
         (ok t))
    (loop for m in movements
          for expected-revision from 1
          do (let ((q (jget m "quantity")))
               (setf running (+ running (cond ((member (jget m "kind") '("mottak" "justering") :test #'string=) q)
                                              ((string= (jget m "kind") "forbruk") (- q))
                                              (t 0))))
               (unless (and (= expected-revision (jget m "revision")) (= running (jget m "balance_after")))
                 (setf ok nil))))
    (values ok running
            (jget (call-ok "inventory_balance" "viewer:vera" "product_id" product-id) "on_hand"))))

(defun overdraw-outcomes (results)
  (map 'list (lambda (r)
               (cond ((typep r 'error) (princ-to-string r))
                     ((jget r "error") (jget (jget r "error") "code"))
                     (t "ok")))
       results))

(test concurrent-overdraw-in-process
  (with-each-durable-store (store db "overdraw")
    (with-test-app (:db db)
      (overdraw-in-process))))

(defun overdraw-in-process ()
  (let* ((product (stock-product 12))
         (results (run-concurrently 20 (lambda (i)
                                         (call "inventory_adjust" "admin:ada" "product_id" product
                                               "delta" -1 "reason" (format nil "uttak ~d" i)))))
         (outcomes (overdraw-outcomes results)))
    (is (= 12 (count "ok" outcomes :test #'string=)) "~s" outcomes)
    (is (= 8 (count "insufficient_stock" outcomes :test #'string=)) "~s" outcomes)
    (is (equal (loop for i from 0 below 12 collect i)
               (sort (loop for r across results
                           when (and (hash-table-p r) (not (jget r "error"))) collect (jget r "balance_after"))
                     #'<))
        "every successful movement saw a distinct balance: no interleaving")
    (multiple-value-bind (ok sum on-hand) (check-ledger product)
      (is (eq t ok))
      (is (= 0 sum on-hand)))))

(test concurrent-overdraw-over-http
  (with-each-durable-store (store db "overdraw_http")
    (with-test-server (port :db db)
      (overdraw-over-http port))))

(defun overdraw-over-http (port)
  (let* ((product (stock-product 5))
         (results (run-concurrently 8 (lambda (i)
                                        (multiple-value-bind (json error-p)
                                            (http-tool-call port "admin:ada" "inventory_adjust"
                                                            (jobj "product_id" product "delta" -1 "reason" "test"
                                                                  "request_key" (format nil "uttak-~d" i)))
                                          (declare (ignore error-p))
                                          json))))
         (outcomes (overdraw-outcomes results)))
    (is (= 5 (count "ok" outcomes :test #'string=)) "~s" outcomes)
    (is (= 3 (count "insufficient_stock" outcomes :test #'string=)) "~s" outcomes)
    (multiple-value-bind (ok sum on-hand) (check-ledger product)
      (is (eq t ok))
      (is (= 0 sum on-hand)))))

(test customer-notes-arrive-by-additive-migration
  (with-each-durable-store (store db "notes")
    (customer-notes-on db)))

(defun customer-notes-on (db)
  ;; A database created before customers had notes: drop the column, as an
  ;; older core would have left it, then start again.
  (let (old)
    (with-test-app (:db db)
      (setf old (jget (call-ok "customers_create" "employee:anna" "name" "Før" "email" "for@example.no") "id"))
      (with-application (*app*)
        (with-transaction (:write)
          (raw-sql "ALTER TABLE customers DROP COLUMN notes"))))
    (with-test-app (:db db)
      (with-application (*app*)
        (is (member "notes" (table-columns "customers") :test #'string=)
            "the column is added at start-up"))
      (let ((before (call-ok "customers_get" "viewer:vera" "id" old)))
        (is (string= "Før" (jget before "name")))
        (is (eq :null (jget before "notes")) "existing rows have no notes"))
      (let ((new (call-ok "customers_create" "employee:anna" "name" "Etter" "email" "etter@example.no"
                          "notes" "Ring før levering")))
        (is (string= "Ring før levering" (jget (call-ok "customers_get" "viewer:vera" "id" (jget new "id")) "notes"))))
      (is (string= "invalid_input"
                   (nth-value 1 (call "customers_create" "employee:anna" "name" "Lang" "email" "lang@example.no"
                                      "notes" (make-string 501 :initial-element #\x)))))
      (let ((notes (find-by "name" "notes" (jget (find-by "name" "customer" (jget (call-ok "registry_describe" "viewer:vera") "entities"))
                                                 "fields"))))
        (is (equal '("core" "Merknad" nil) (list (jget notes "source") (jget notes "label") (jget notes "required"))))))))

;;; ------------------------------------------------------------------
;;; Two applications on one Postgres database (spec/store.md 3): the old and
;;; the new process of a blue/green switch.

(defmacro with-two-applications ((first second name) &body body)
  "Run BODY with FIRST and SECOND bound to two applications, each with its own
store and connections, opened one after the other on one fresh Postgres
database."
  (let ((db (gensym "DB")))
    `(let* ((,db (scratch-postgres ,name))
            (,first (tun.runtime:open-application 'application :db ,db :test-clock t)))
       (unwind-protect
            (let ((,second (tun.runtime:open-application 'application :db ,db :test-clock t)))
              (unwind-protect (progn ,@body)
                (tun.runtime:close-application ,second)))
         (tun.runtime:close-application ,first)))))

(defun run-on-applications (applications function)
  "Call FUNCTION with indices 0..N-1 in threads that start together, thread I
on the Ith of APPLICATIONS; the vector of results (an error as the condition)."
  (let* ((n (length applications))
         (results (make-array n :initial-element nil))
         (gate (sb-thread:make-semaphore :count 0))
         (threads (loop for i from 0
                        for app in applications
                        collect (let ((i i) (app app))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (let ((*app* app))
                                       (sb-thread:wait-on-semaphore gate)
                                       (setf (aref results i)
                                             (handler-case (funcall function i) (error (e) e)))))
                                   :name (format nil "test application ~d" i))))))
    (sb-thread:signal-semaphore gate n)
    (mapc #'sb-thread:join-thread threads)
    results))

(defun migration-count (app)
  (with-application (app)
    (with-transaction (:read)
      (let ((*app* app))
        (first (first (raw-sql "SELECT COUNT(*) FROM schema_history")))))))

(test two-applications-write-one-postgres-database-one-at-a-time
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (with-two-applications (old new "two_writers")
        (let* ((*app* old)
               (product (stock-product 12))
               (outcomes (overdraw-outcomes
                          (run-on-applications
                           (loop for i below 20 collect (if (evenp i) old new))
                           (lambda (i)
                             (call "inventory_adjust" "admin:ada" "product_id" product
                                   "delta" -1 "reason" (format nil "uttak ~d" i)))))))
          (is (= 12 (count "ok" outcomes :test #'string=)) "~s" outcomes)
          (is (= 8 (count "insufficient_stock" outcomes :test #'string=)) "~s" outcomes)
          (dolist (*app* (list old new))
            (multiple-value-bind (ok sum on-hand) (check-ledger product)
              (is (eq t ok) "both applications' movements form one ledger")
              (is (= 0 sum on-hand))))
          (is (= (migration-count old) (migration-count new))
              "the second application found the schema migrated and added nothing")))))

(defvar *store-test-runs* (list 0) "Runs of the test_store_count workflow, a cell for ATOMIC-INCF.")

(test a-process-is-present-while-its-store-is-open
  ;; spec/store.md 3: on Postgres a process's presence lock is free the
  ;; moment its connection closes, so its running jobs are recovered at once.
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (let* ((db (scratch-postgres "presence"))
             (old (tun.runtime:open-application 'application :db db :test-clock t))
             (new (tun.runtime:open-application 'application :db db :test-clock t)))
        (unwind-protect
             (let ((old-key (with-application (old)
                              (with-transaction (:read)
                                (tun.jobs:job-process-lock-key
                                 (fetch 'tun.jobs:job-process (tun.jobs:process-id)))))))
               (is (store-present-p (application-store new) old-key) "the old process holds its lock")
               (let ((job (with-application (old)
                            (with-actor ((system-actor "test"))
                              (with-transaction (:write)
                                (tun.jobs:enqueue-job 'mark-job :text "på vei")))
                            (with-transaction (:write)
                              (let ((job (select-one 'tun.jobs:job)))
                                (setf (tun.jobs:job-state job) "running"
                                      (tun.jobs:job-claimed-by job) (tun.jobs:process-id)
                                      (tun.jobs:job-attempts job) 1)
                                (save job)
                                (entity-id job))))))
                 (is (zerop (with-application (new) (tun.jobs:rescue-orphaned-jobs)))
                     "a present process keeps its running job")
                 ;; As if it died: its connections close without its row going.
                 (store-close (application-store old))
                 ;; Postgres ends the closed connection's backend, and frees
                 ;; its lock, a moment after the socket closes.
                 (is (loop repeat 100
                           unless (store-present-p (application-store new) old-key) return t
                           do (sleep 0.02))
                     "the lock is free once the connection has closed")
                 (is (= 1 (with-application (new) (tun.jobs:rescue-orphaned-jobs))))
                 (is (equal "retrying" (with-application (new)
                                         (with-transaction (:read)
                                           (tun.jobs:job-state (fetch 'tun.jobs:job job))))))))
          (tun.runtime:close-application new)
          ;; The old store is closed already, so removing its row fails;
          ;; that is the death the test plays.
          (ignore-errors (tun.runtime:close-application old))))))

(define-workflow store-test-count (:kind "test_store_count" :label "Telling") (wf)
  (declare (ignore wf))
  (sb-ext:atomic-incf (car *store-test-runs*)))

(test a-due-workflow-runs-once-whichever-application-takes-it
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (with-two-applications (old new "workflows_once")
        (setf (car *store-test-runs*) 0)
        (with-application (old)
          (with-transaction (:write)
            (dotimes (i 20)
              (tun.workflows:schedule-workflow "test_store_count" :due-at (now)))))
        (let ((executed (run-on-applications (list old new)
                                             (lambda (i)
                                               (declare (ignore i))
                                               (with-application (*app*)
                                                 (tun.workflows:run-due-workflows))))))
          (is (every #'integerp executed) "~s" executed)
          (is (= 20 (reduce #'+ executed)) "the two schedulers ran ~s" executed)
          (is (= 20 (car *store-test-runs*)) "each workflow ran exactly once"))
        (with-application (new)
          (with-transaction (:read)
            (is (every (lambda (wf) (string= "utført" (tun.workflows:workflow-status wf)))
                       (select 'tun.workflows:workflow))))))))
