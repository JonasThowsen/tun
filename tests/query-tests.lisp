;;;; tests/query-tests.lisp -- DEFINE-QUERY (spec/store.md 5): the text
;;;; rules, both kinds of result, parameters, the start check and the stores
;;;; that do not run queries.  The database tests run on Postgres when
;;;; TUN_TEST_POSTGRES names a server (bin/test provides one).

(in-package #:tun.tests)

(def-suite queries :in core)
(in-suite queries)

;;; The suite's own queries stay defined, so every Postgres application the
;;; suite opens checks them at start; they must stay valid.

(define-query widgets-named ((name :required t))
  (:returns widget :description "Dingser med et navn.")
  "SELECT w.* FROM {widget} w WHERE w.name = :name ORDER BY w.seq")

(define-query widgets-since ((since :type timestamp))
  (:returns widget)
  "SELECT w.* FROM {widget} w
    WHERE :since::text IS NULL OR w.created_at >= :since -- :not_a_parameter
    ORDER BY w.seq")

(define-query widgets-by-status ()
  (:returns (:rows (status) (widgets :type integer)))
  "SELECT count(*) AS widgets, status FROM {widget} GROUP BY status ORDER BY status")

(defmacro with-postgres-app (() &body body)
  "Run BODY in a fresh application on a fresh Postgres database, or skip."
  `(if (postgres-available-p)
       (with-test-app (:db (scratch-postgres "queries"))
         (with-application (*app*)
           ,@body))
       (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")))

(defun add-widgets (&rest names-and-times)
  (with-transaction (:write)
    (loop for (name time) on names-and-times by #'cddr
          do (insert (make-instance 'widget :name name :created-at time)))))

;;; ------------------------------------------------------------------
;;; The text

(defun parts-of (text)
  (tun.core::split-query-text text (find-package '#:tun.tests)))

(test query-text-is-split-into-sql-entities-and-parameters
  (is (equal '("SELECT * FROM " (:entity widget) " w WHERE w.name = " (:parameter "name"))
             (parts-of "SELECT * FROM {widget} w WHERE w.name = :name")))
  (is (equal '("SELECT ':x {widget}', \"{y}\" /* :z */ -- :w {v}
 FROM t WHERE a = " (:parameter "a") "::text")
             (parts-of "SELECT ':x {widget}', \"{y}\" /* :z */ -- :w {v}
 FROM t WHERE a = :a::text"))
      "strings, quoted identifiers and comments are left alone; :: is a cast")
  (is (equal '("SELECT 'it''s' WHERE x = " (:parameter "x"))
             (parts-of "SELECT 'it''s' WHERE x = :x"))
      "a doubled quote stays inside the string")
  (let ((text "WITH a AS (SELECT 1) SELECT * FROM a"))
    (is (equal (list text) (parts-of text))))
  (is (equal '("  -- note
select 1") (parts-of "  -- note
select 1"))
      "the first word is found after comments, in any case"))

(test query-text-refusals
  (dolist (text '("SELECT 1; DELETE FROM widgets"
                  "SELECT * FROM widgets WHERE id = $1"
                  "SELECT $$x$$"
                  "SELECT * FROM {Widget}"
                  "SELECT * FROM {widget"
                  "SELECT * FROM {}"
                  "SELECT 'open"
                  "SELECT \"open"
                  "SELECT 1 /* open"
                  "SELECT 1 /* a /* b */ */"
                  "UPDATE widgets SET name = 'x'"
                  "DELETE FROM widgets"
                  "(SELECT 1)"))
    (is (eq :refused (handler-case (progn (parts-of text) :split) (error () :refused)))
        "~s is refused" text)))

(test query-parameters-are-numbered-and-all-used
  (multiple-value-bind (parts order)
      (tun.core::number-parameters (parts-of "SELECT :b, :a, :b") '("a" "b"))
    (is (equal '("SELECT " (:parameter 1) ", " (:parameter 2) ", " (:parameter 1)) parts))
    (is (equal '("b" "a") order)))
  (signals error (macroexpand-1 '(define-query q-unused ((name)) (:returns widget)
                                  "SELECT * FROM {widget}")))
  (signals error (macroexpand-1 '(define-query q-undeclared () (:returns widget)
                                  "SELECT * FROM {widget} WHERE name = :name")))
  (signals error (macroexpand-1 '(define-query q-no-returns () ()
                                  "SELECT * FROM {widget}")))
  (signals error (macroexpand-1 '(define-query q-bad-rows () (:returns (:columns (a)))
                                  "SELECT 1 AS a"))))

;;; ------------------------------------------------------------------
;;; Running on Postgres

(test a-query-returns-records-of-its-entity
  (with-postgres-app ()
    (add-widgets "Hammer" 3900000000 "Sag" 3900000100 "Hammer" 3900000200)
    (with-transaction (:read)
      (let ((found (widgets-named :name "Hammer")))
        (is (= 2 (length found)))
        (is (every (lambda (w) (typep w 'widget)) found))
        (is (equal '(3900000000 3900000200) (mapcar #'widget-created-at found))
            "a timestamp comes back as a universal time, as from select")
        (is (equal (mapcar #'entity-id (select 'widget :where '(:= "name" "Hammer")))
                   (mapcar #'entity-id found))
            "the same records select gives"))
      (is (null (widgets-named :name "Tang"))))))

(test a-query-returns-rows-of-declared-columns
  (with-postgres-app ()
    (add-widgets "A" 3900000000 "B" 3900000000)
    (with-transaction (:write)
      (let ((w (select-one 'widget :where '(:= "name" "B"))))
        (setf (widget-status w) "arkivert")
        (save w)))
    (with-transaction (:read)
      (let ((rows (widgets-by-status)))
        (is (equal '(("status" "widgets") ("status" "widgets")) (mapcar #'jkeys rows))
            "keys in the order :returns gives, whatever the SQL's order")
        (is (equal '(("aktiv" 1) ("arkivert" 1))
                   (mapcar (lambda (row) (list (jget row "status") (jget row "widgets")))
                           rows)))))))

(test query-parameters-take-lisp-values
  (with-postgres-app ()
    (add-widgets "A" 3900000000 "B" 3900000100 "C" 3900000200)
    (with-transaction (:read)
      (is (equal '("A" "B" "C") (mapcar #'widget-name (widgets-since))) "NIL is NULL")
      (is (equal '("B" "C") (mapcar #'widget-name (widgets-since :since 3900000100))))
      ;; A value of the wrong type, and a required parameter missing.
      (signals error (widgets-since :since "i går"))
      (signals error (widgets-named))
      (is (null (widgets-named :name "x'; DROP TABLE widgets --")) "values are never spliced"))
    (with-transaction (:read)
      (is (= 3 (length (widgets-since)))))))

(test a-query-sees-its-write-transaction-and-needs-one
  (with-postgres-app ()
    (with-transaction (:write)
      (insert (make-instance 'widget :name "Ny"))
      (is (= 1 (length (widgets-named :name "Ny"))) "the transaction's own write"))
    ;; Outside a transaction.
    (signals error (widgets-named :name "Ny"))))

(test eval-cannot-run-a-rows-query
  (with-postgres-app ()
    (with-transaction (:read)
      (let ((*under-eval* t)
            (*actor* (parse-actor "admin:test")))
        (signals error (widgets-by-status))
        (is (null (widgets-named :name "x")))))))

(test the-memory-store-does-not-run-queries
  (with-test-app ()
    (with-application (*app*)
      (with-transaction (:read)
        (signals error (widgets-named :name "x"))))))

;;; ------------------------------------------------------------------
;;; The start check

(defpackage #:query-test-client
  (:use #:cl #:tun)
  ;; Standing for a client that got hold of a kernel entity's symbol.
  (:import-from #:tun.core #:audit-entry))

(defun define-scratch-query (form &optional (package '#:tun.tests))
  (let ((*package* (find-package package)))
    (eval form)))

(defun forget-query (name)
  (remhash name tun.core::*queries*)
  (fmakunbound name))

(test start-refuses-a-query-that-cannot-run
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (let ((names '()))
        (flet ((define (name returns sql &optional (package '#:tun.tests))
                 (let ((symbol (intern (string name) package)))
                   (push symbol names)
                   (define-scratch-query `(define-query ,symbol () (:returns ,returns) ,sql)
                       package))))
          (unwind-protect
               (progn
                 (define "BROKEN-COLUMN" 'widget "SELECT w.*, w.nope FROM {widget} w")
                 (define "UNKNOWN-ENTITY" 'widget "SELECT * FROM {gizmo}")
                 (define "WRONG-COLUMNS" 'widget "SELECT w.id, w.name FROM {widget} w")
                 (define "WRONG-ROWS" '(:rows (name) (total :type integer))
                   "SELECT name FROM {widget}")
                 (define "WRITES" 'widget
                   "WITH gone AS (DELETE FROM {widget} RETURNING *) SELECT * FROM gone")
                 (define "CLIENT-READS-AUDIT" '(:rows (id)) "SELECT id FROM {audit-entry}"
                         '#:query-test-client)
                 (let ((refusal (handler-case
                                    (progn (tun.runtime:open-application
                                            'application :db (scratch-postgres "refused"))
                                           nil)
                                  (extension-error (e) (princ-to-string e)))))
                   (is (stringp refusal) "the application does not open")
                   (dolist (name '("broken-column" "unknown-entity" "wrong-columns" "wrong-rows"
                                   "writes" "client-reads-audit"))
                     (is (search name (or refusal "")) "~a is named" name))
                   (is (search "column w.nope does not exist HINT" (or refusal "")))
                   (is (search "{gizmo} is not a stored entity" (or refusal "")))
                   (is (cl-ppcre:scan "wrong-columns.*missing.*created_at" (or refusal "")))
                   (is (search "missing total" (or refusal "")))
                   (is (search "secret data" (or refusal "")))
                   (is (not (search "widgets-named" (or refusal ""))) "valid queries are not")))
            (mapc #'forget-query names))))))

(test the-same-entity-is-readable-by-a-kernel-query
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (unwind-protect
           (progn
             (define-scratch-query
                 '(define-query kernel-reads-audit () (:returns (:rows (tool)))
                   "SELECT tool FROM {audit-entry} ORDER BY seq"))
             (with-postgres-app ()
               (with-transaction (:read)
                 (is (listp (funcall 'kernel-reads-audit))))))
        (forget-query 'kernel-reads-audit))))
