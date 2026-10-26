;;;; tests/record-policy-tests.lisp -- record policies (spec/store.md 6): which
;;;; records each role reads and writes, through fetch, select, queries and
;;;; writes, the start check, and the stores that cannot apply a policy.  The
;;;; database tests run on Postgres when TUN_TEST_POSTGRES names a server.

(in-package #:tun.tests)

(def-suite record-policies :in core)
(in-suite record-policies)

;;; A memo is its author's, and an employee also reaches the memos shared
;;; with them.  These stay defined, so every Postgres application the suite
;;; opens checks the policy at start; it must stay valid.

(define-entity memo (:label "Notat" :id-prefix "mmo" :table "test_memos"
                            :record-policy
                            ((:admin t)
                             (:employee "author = :actor_name
                                  OR EXISTS (SELECT 1 FROM {memo-share} s
                                             WHERE s.memo_id = this.id
                                               AND s.shared_with = :actor_name) -- or shared")))
  ((text :type (string :min 1 :max 200) :required t :label "Tekst")
   (author :type (string :max 64) :required t :label "Forfatter")))

(define-entity memo-share (:label "Deling" :id-prefix "mms" :table "test_memo_shares")
  ((memo-id :type (id memo) :required t :label "Notat")
   (shared-with :type (string :max 64) :required t :label "Delt med")))

(define-operation memos-create ((:draft memo))
    (:entity memo :kind :create :policy :employee :title "Lag notat")
  (insert memo))

(define-query memos-counted ()
  (:returns (:rows (memos :type integer)))
  "SELECT count(*) AS memos FROM {memo}")

(define-query memos-with-text ((text :required t))
  (:returns memo)
  "SELECT m.* FROM {memo} m WHERE m.text = :text ORDER BY m.seq")

(defun as (actor)
  (if (string= actor "system") (system-actor) (parse-actor actor)))

(defmacro as-actor ((actor &optional (mode :read)) &body body)
  "Run BODY as ACTOR (\"role:name\" or \"system\") in a MODE transaction."
  `(with-actor ((as ,actor))
     (with-transaction (,mode)
       ,@body)))

(defun memo-texts (actor)
  (as-actor (actor) (mapcar #'memo-text (select 'memo))))

(defun add-memos ()
  "Kari's two memos, Ola's one, and Ola's shared with Kari: their ids."
  (as-actor ("system" :write)
            (let ((k1 (insert (make-instance 'memo :text "k1" :author "kari")))
                  (k2 (insert (make-instance 'memo :text "k2" :author "kari")))
                  (o1 (insert (make-instance 'memo :text "o1" :author "ola")))
                  (o2 (insert (make-instance 'memo :text "o2" :author "ola"))))
              (insert (make-instance 'memo-share :memo-id (entity-id o2) :shared-with "kari"))
              (mapcar #'entity-id (list k1 k2 o1 o2)))))

;;; ------------------------------------------------------------------
;;; The definition

(test a-record-policy-is-refused-when-compiled
  (dolist (policy '(((:owner "author = :actor_name"))
                    ((:employee t) (:employee t))
                    ((:employee 42))
                    ((:employee "author = :user"))
                    ((:employee "author = :actor_name; DELETE FROM test_memos"))
                    ((:employee "author = :actor_name) OR (TRUE"))
                    ((:employee "(author = :actor_name"))
                    (:employee "author = :actor_name")))
    (is (eq :refused (handler-case
                         (progn (macroexpand-1 `(define-entity refused-memo
                                                    (:record-policy ,policy)
                                                  ((author))))
                                :defined)
                       (error () :refused)))
        "~s is refused" policy))
  (signals error (macroexpand-1 '(define-entity refused-line
                                  (:embedded t :record-policy ((:admin t)))
                                  ((text))))))

(test registry-describe-shows-the-record-policy
  (let ((policy (jget (tun.core::describe-entity (find-class 'memo)) "record_policy")))
    (is (equal '("admin" "employee") (map 'list (lambda (c) (jget c "role")) policy)))
    (is (eq t (jget (aref policy 0) "condition")))
    (is (search "author = :actor_name" (jget (aref policy 1) "condition"))))
  (is (not (nth-value 1 (gethash "record_policy"
                                 (tun.core::describe-entity (find-class 'widget)))))
      "an entity without a policy has no key"))

;;; ------------------------------------------------------------------
;;; Reads

(test each-role-reads-the-records-its-clause-admits
  (with-postgres-app ()
    (add-memos)
    (is (equal '("k1" "k2" "o1" "o2") (memo-texts "admin:jonas")))
    (is (equal '("k1" "k2" "o1" "o2") (memo-texts "system")) "the system reaches every record")
    (is (equal '("k1" "k2" "o2") (memo-texts "employee:kari")) "her own, and the one shared")
    (is (equal '("o1" "o2") (memo-texts "employee:ola")))
    (is (null (memo-texts "viewer:vera")) "a role without a clause reaches none")
    ;; Without an actor.
    (signals error (with-transaction (:read) (select 'memo)))))

(test a-record-outside-the-policy-is-not-found
  (with-postgres-app ()
    (destructuring-bind (k1 k2 o1 o2) (add-memos)
      (declare (ignore k2))
      (as-actor ("employee:kari")
                (is (fetch 'memo k1))
                (is (fetch 'memo o2))
                (is (null (fetch 'memo o1)))
                (is (eq :not-found (handler-case (fetch! 'memo o1)
                                     (operation-error (e) (operation-error-code e)))))
                (is (equal '("k2") (mapcar #'memo-text
                                           (select 'memo :where '(:in "text" ("k2" "o1"))
                                                   :order-by '(("text" :asc)))))
                    "a where and the policy together")
                (is (equal "k2" (memo-text (select-one 'memo :order-by '(("seq" :desc))
                                                       :where '(:= "author" "kari")))))))))

(test a-query-reads-only-the-records-the-policy-admits
  (with-postgres-app ()
    (add-memos)
    (flet ((counted (actor) (as-actor (actor) (jget (first (memos-counted)) "memos"))))
      (is (= 4 (counted "admin:jonas")))
      (is (= 3 (counted "employee:kari")))
      (is (= 0 (counted "viewer:vera"))))
    (as-actor ("employee:kari")
              (is (= 1 (length (memos-with-text :text "o2"))) "shared with her")
              (is (null (memos-with-text :text "o1")) "the query's parameter and the policy's together"))))

;;; ------------------------------------------------------------------
;;; Writes

(defun memo-count ()
  (as-actor ("system") (length (select 'memo))))

(test an-insert-must-satisfy-the-policy
  (with-postgres-app ()
    (as-actor ("employee:kari" :write)
              (insert (make-instance 'memo :text "mitt" :author "kari"))
              (signals tun.core::rejection (insert (make-instance 'memo :text "hans" :author "ola")))
              (handler-case (insert (make-instance 'memo :text "hans" :author "ola"))
                (tun.core::rejection () nil))
              (is (= 1 (length (select 'memo)))))
    (is (= 1 (memo-count)) "a refused insert leaves nothing, even when handled")
    (signals tun.core::rejection (as-actor ("viewer:vera" :write)
                                           (insert (make-instance 'memo :text "v" :author "vera"))))
    (is (= 1 (memo-count)))))

(test a-save-must-satisfy-the-policy-before-and-after
  (with-postgres-app ()
    (destructuring-bind (k1 k2 o1 o2) (add-memos)
      (declare (ignore k2 o2))
      (let ((theirs (as-actor ("system") (fetch 'memo o1)))
            (mine (as-actor ("system") (fetch 'memo k1))))
        (as-actor ("employee:kari" :write)
                  (setf (memo-text theirs) "endret")
                  (is (eq :not-found (handler-case (progn (save theirs) nil)
                                       (operation-error (e) (operation-error-code e)))))
                  (setf (memo-author mine) "ola")
                  (handler-case (save mine) (tun.core::rejection () nil))
                  (setf (memo-author mine) "kari" (memo-text mine) "k1 endret")
                  (save mine))
        (as-actor ("system")
                  (is (equal "o1" (memo-text (fetch 'memo o1))))
                  (is (equal "kari" (memo-author (fetch 'memo k1))) "the refused save left nothing")
                  (is (equal "k1 endret" (memo-text (fetch 'memo k1)))))))))

(test a-delete-must-satisfy-the-policy
  (with-postgres-app ()
    (destructuring-bind (k1 k2 o1 o2) (add-memos)
      (declare (ignore k2 o2))
      (let ((theirs (as-actor ("system") (fetch 'memo o1)))
            (mine (as-actor ("system") (fetch 'memo k1))))
        (as-actor ("employee:kari" :write)
                  (signals operation-error (delete-entity theirs))
                  (delete-entity mine))
        (is (= 3 (memo-count)))
        (let ((kept (as-actor ("system") (fetch 'memo o1))))
          (is (typep kept 'memo)))))))

(test a-refused-write-in-an-operation-is-audited-as-rejected
  (with-postgres-app ()
    (is (equal "forbidden"
               (nth-value 1 (call "memos_create" "employee:kari" "text" "hans" "author" "ola"))))
    (call-ok "memos_create" "employee:kari" "text" "mitt" "author" "kari")
    (is (= 1 (memo-count)))
    (as-actor ("system")
              (is (equal '(("rejected" "forbidden") ("ok" nil))
                         (mapcar (lambda (entry) (list (audit-entry-outcome entry)
                                                       (audit-entry-error-code entry)))
                                 (select 'audit-entry :where '(:= "tool" "memos_create"))))))))

;;; ------------------------------------------------------------------
;;; The start check and the other stores

(defpackage #:record-policy-test-client
  (:use #:cl #:tun)
  ;; Standing for a client that got hold of a kernel entity's symbol.
  (:import-from #:tun.core #:audit-entry))

(defun define-in (package form)
  "Evaluate the definition FORM as code in PACKAGE."
  (let ((*package* (find-package package)))
    (eval form)))

(defun forget-entities (&rest names)
  (setf tun.core::*entities* (set-difference tun.core::*entities* names))
  (tun.core::invalidate-field-caches))

(test start-refuses-a-record-policy-that-cannot-run
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (let ((broken (intern "BROKEN-MEMO" '#:tun.tests))
            (nosy (intern "NOSY-MEMO" '#:record-policy-test-client)))
        (unwind-protect
             (progn
               (define-in '#:tun.tests
                   `(define-entity ,broken (:id-prefix "bmo" :table "test_broken_memos"
                                                       :record-policy ((:employee "nope = :actor_name")
                                                                       (:viewer "author")))
                      ((author))))
               (define-in '#:record-policy-test-client
                   `(define-entity ,nosy (:id-prefix "nmo" :table "test_nosy_memos"
                                                     :record-policy
                                                     ((:employee "EXISTS (SELECT 1 FROM {audit-entry})")))
                      ((author))))
               (let ((refusal (handler-case
                                  (progn (tun.runtime:open-application
                                          'application :db (scratch-postgres "refused"))
                                         nil)
                                (extension-error (e) (princ-to-string e)))))
                 (is (stringp refusal) "the application does not open")
                 (is (search "broken_memo" (or refusal "")))
                 (is (cl-ppcre:scan "employee: .*column \"nope\" does not exist" (or refusal "")))
                 (is (cl-ppcre:scan "viewer: .*argument of WHERE must be type boolean"
                                    (or refusal "")))
                 (is (cl-ppcre:scan "nosy_memo.*employee.*secret data" (or refusal "")))
                 (is (not (search "test_memos" (or refusal ""))) "a valid policy is not named")))
          (forget-entities broken nosy)))))

(test the-other-stores-refuse-an-entity-with-a-record-policy
  (dolist (db (list nil (scratch-path "record-policy")))
    (with-test-app (:db db)
      (with-application (*app*)
        (as-actor ("admin:jonas" :write)
                  (signals error (select 'memo))
                  (signals error (insert (make-instance 'memo :text "x" :author "jonas")))
                  (is (null (select 'widget)) "an entity without a policy is unaffected"))))))
