;;;; tests/fixtures/core-1.23.1/make-fixture.lisp KIND OUT -- one tenant as
;;;; core 1.23.1 wrote it, on SQLite (OUT/KIND.sqlite) and on the Postgres of
;;;; DATABASE_URL (its URL in OUT/KIND.pgurl).  Run by make-fixtures.sh, from
;;;; a checkout of core 1.23.1.
;;;;
;;;; Every kind holds core's data: an account, the three settings core 2.0
;;;; renames (lenker.base_url set, the two secrets made at first start), a
;;;; workflow in each status, and a mail.  core adds a client's own table
;;;; named customers, with rows; business adds the customers module's table
;;;; with a customer; inbox loads the inbox module, which makes its secret,
;;;; and holds no inquiry.

(load "scripts/setup.lisp")
(in-package #:tun-build)

(load-quietly "alexandria" "bordeaux-threads" "cl-base64" "cl-ppcre" "closer-mop" "com.inuoe.jzon"
              "drakma" "fiveam" "hunchentoot" "ironclad" "sqlite" "cl-postgres" "swank" "usocket")

(defparameter *kind* (second sb-ext:*posix-argv*))
(defparameter *out* (third sb-ext:*posix-argv*))

(load-quietly "tun" "tun-test-support")
(cond ((string= *kind* "business") (load-quietly "tun-customers"))
      ((string= *kind* "inbox") (load-quietly "tun-inbox")))

(in-package #:tun.test-support)

(defun add-client-customers (postgres)
  "A table named customers that the client created, with rows."
  (raw-sql (format nil "CREATE TABLE \"customers\" (\"seq\" ~a, \"id\" TEXT NOT NULL UNIQUE, ~
                        \"name\" TEXT, \"status\" TEXT)"
                   (if postgres
                       "BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY"
                       "INTEGER PRIMARY KEY AUTOINCREMENT")))
  (raw-sql "INSERT INTO schema_history (statement, applied_at, module, migration)
            VALUES ('CREATE TABLE \"customers\" (...)', '2026-10-28T08:00:00Z', 'client',
                    'client_0001_create_customers')")
  (raw-sql "INSERT INTO customers (id, name, status)
            VALUES ('kun_1', 'Fjord AS', 'planlagt'), ('kun_2', 'Nordvik AS', 'ny')"))

(defun fill-database (db postgres)
  (with-test-app (:db db :debug-tools t)
    (call-ok "accounts_create" "admin:ada" "name" "ada" "kind" "person" "role" "admin"
             "email" "ada@example.no")
    (call-ok "settings_set" "admin:ada" "key" "lenker.base_url" "value" "https://tenant.example")
    (dotimes (i 4)
      (call-ok "debug_schedule" "admin:ada" "due_in_ms" (* (1+ i) 3600000)))
    (with-application (*app*)
      (with-transaction (:write)
        (tun.mail:send-mail :to "kari@example.no" :subject "Hei" :text "Velkommen")
        (let ((ids (mapcar #'first (raw-sql "SELECT id FROM workflows ORDER BY seq"))))
          (loop for id in (rest ids)
                for status in '("utført" "avbrutt" "feilet")
                do (raw-sql (format nil "UPDATE workflows SET status = '~a' WHERE id = '~a'"
                                    status id))))
        (when (string= tun-build::*kind* "core")
          (add-client-customers postgres))))
    (when (string= tun-build::*kind* "business")
      (call-ok "customers_create" "admin:ada" "name" "Kari Nordmann" "email" "kari@example.no"))))

(let ((sqlite (format nil "~a/~a.sqlite" tun-build::*out* tun-build::*kind*))
      (url (tun.store.postgres:postgres-create-database
            (uiop:getenv "DATABASE_URL") (format nil "fixture_~a" tun-build::*kind*))))
  (fill-database sqlite nil)
  (fill-database url t)
  (with-open-file (out (format nil "~a/~a.pgurl" tun-build::*out* tun-build::*kind*)
                       :direction :output :if-exists :supersede)
    (write-string url out)))

(sb-ext:exit :code 0)
