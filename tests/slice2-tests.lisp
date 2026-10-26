;;;; tests/slice2-tests.lisp -- stock, requirements and plans with core alone:
;;;; the reviews and warehouse modules (their READMEs), the
;;;; kernel's client on-open hook and the rollback preflight on newer
;;;; documents (core.md §6.4).

(in-package #:tun.tests)

(def-suite slice2 :in core)
(in-suite slice2)

;;; ------------------------------------------------------------------
;;; Warehouse tasks, invariant 16

(defun task-events (task)
  (map 'list (lambda (e) (jget e "kind")) (jget (call-ok "task_events_list" "viewer:v" "id" task) "items")))

(test tasks-stay-in-their-department-with-one-event-per-mutation
  (with-test-app (:class 'departments-app)
    (let* ((tor (jget (make-employee "Tor" :department "nord") "id"))
           (tea (jget (make-employee "Tea" :department "nord") "id"))
           (kim (jget (make-employee "Kim" :department "sør") "id"))
           (task (call-ok "tasks_create" "admin:a" "department" "nord" "title" "  Telle beger  "
                          "description" "Hele lageret" "due_date" "2026-06-01" "assignee_id" tor))
           (id (jget task "id")))
      (is (equal '("nord" "Telle beger" "open" 1 "admin:a")
                 (list (jget task "department") (jget task "title") (jget task "status") (jget task "revision")
                       (jget task "created_by"))))
      (is (equal '("created") (task-events id)))
      (is (string= tor (jget (aref (jget (call-ok "task_events_list" "viewer:v" "id" id) "items") 0) "recipient_id")))
      ;; Validation: nothing stored.
      (is-error "invalid_input" "Ansvarlig må tilhøre samme avdeling som lageroppgaven"
                (call "tasks_create" "admin:a" "department" "nord" "title" "Feil" "assignee_id" kim))
      (is-error "invalid_input" nil (call "tasks_create" "admin:a" "department" "nord" "title" "x"))
      (is-error "invalid_input" nil (call "tasks_create" "admin:a" "department" "nord"
                                          "title" (make-string 161 :initial-element #\x)))
      (is-error "invalid_input" nil (call "tasks_create" "admin:a" "department" "nord" "title" "Lang"
                                          "description" (make-string 2001 :initial-element #\x)))
      (is-error "invalid_input" nil (call "tasks_create" "admin:a" "title" "Uten avdeling"))
      (is-error "invalid_input" nil (call "tasks_create" "admin:a" "department" "trondheim" "title" "Ukjent"))
      (is-error "forbidden" nil (call "tasks_create" "employee:tor" "department" "nord" "title" "Ansatt"))
      (is (= 1 (length (coerce (jget (call-ok "tasks_list" "viewer:v") "items") 'list))))
      ;; Stale revisions; update; assign.
      (is-error "conflict" nil (call "tasks_update" "admin:a" "id" id "revision" 9 "title" "Ny"))
      (is (= 2 (jget (call-ok "tasks_update" "admin:a" "id" id "revision" 1 "title" "Telle alle beger") "revision")))
      (is-error "invalid_input" "Oppgaven er allerede tildelt denne personen"
                (call "tasks_assign" "admin:a" "id" id "revision" 2 "assignee_id" tor))
      (call-ok "tasks_assign" "admin:a" "id" id "revision" 2 "assignee_id" tea)
      (let ((unassigned (call-ok "tasks_assign" "admin:a" "id" id "revision" 3 "assignee_id" :null))
            (last (car (last (coerce (jget (call-ok "task_events_list" "viewer:v" "id" id) "items") 'list)))))
        (is (json-null-p (jget unassigned "assignee_id")))
        (is (equal '("changed" t) (list (jget last "kind") (jget (jget last "details") "assignment_removed")))))
      (call-ok "tasks_assign" "admin:a" "id" id "revision" 4 "assignee_id" tea)
      ;; Completion: the assignee, in the department, at the current revision.
      (is-error "forbidden" "Bare nåværende ansvarlig kan fullføre lageroppgaven"
                (call "tasks_complete" "employee:tor" "id" id "revision" 5))
      (call-ok "employees_update" "admin:a" "id" tea "department" "sør")
      (is-error "forbidden" "Du må tilhøre samme avdeling som lageroppgaven for å fullføre den"
                (call "tasks_complete" "employee:tea" "id" id "revision" 5))
      (call-ok "employees_update" "admin:a" "id" tea "department" "nord")
      (is-error "conflict" nil (call "tasks_complete" "employee:tea" "id" id "revision" 4))
      (let ((done (call-ok "tasks_complete" "employee:tea" "id" id "revision" 5)))
        (is (equal '("completed" "employee:tea" 6) (list (jget done "status") (jget done "completed_by") (jget done "revision"))))
        (is (stringp (jget done "completed_at"))))
      (is-error "invalid_transition" nil (call "tasks_complete" "admin:a" "id" id "revision" 6))
      (is-error "forbidden" nil (call "tasks_reopen" "employee:tea" "id" id "revision" 6))
      (let ((open (call-ok "tasks_reopen" "admin:a" "id" id "revision" 6)))
        (is (equal (list "open" :null :null) (list (jget open "status") (jget open "completed_at") (jget open "completed_by")))))
      (is (equal '("created" "changed" "assigned" "changed" "assigned" "completed" "reopened") (task-events id)))
      (is (string= "completed" (jget (call-ok "tasks_complete" "admin:a" "id" id "revision" 7) "status"))
          "an admin completes any task")
      ;; The list: open first by due date (none last), then completed; filters and mine.
      (call-ok "tasks_create" "admin:a" "department" "nord" "title" "Rydde hylle" "due_date" "2026-05-20")
      (call-ok "tasks_create" "admin:a" "department" "nord" "title" "Bestille kopper")
      (call-ok "tasks_create" "admin:a" "department" "sør" "title" "Vaske maskiner" "due_date" "2026-05-15")
      (flet ((titles (&rest args)
               (map 'list (lambda (x) (jget x "title")) (jget (apply #'call-ok "tasks_list" args) "items"))))
        (is (equal '("Vaske maskiner" "Rydde hylle" "Bestille kopper" "Telle alle beger") (titles "viewer:v")))
        (is (equal '("Vaske maskiner") (titles "viewer:v" "department" "sør")))
        (is (equal '("Telle alle beger") (titles "viewer:v" "status" "completed")))
        (is (equal '("Bestille kopper") (titles "viewer:v" "query" "KOPPER")))
        (is (equal '("Vaske maskiner") (titles "employee:kim" "mine" t)))
        (is (null (titles "employee:ukjent" "mine" t)) "no employee record, no tasks of mine")))))

;;; ------------------------------------------------------------------
;;; Reviews, invariant 11 (the generic part) and 18

(defclass zz-review-handler () ())
(defclass zz-review-app (zz-review-handler application) ())

(defmethod tun.reviews:resolve-review ((app zz-review-handler) review decision)
  (if (string= (tun.reviews:review-kind review) "zz_test")
      (cond ((equal (jget (tun.reviews:review-proposal review) "id") "stale") (values "superseded" "Utdatert"))
            ((string= decision "approve") "approved")
            (t "rejected"))
      (call-next-method)))

(defmethod tun.reviews:review-details ((app zz-review-handler) review json)
  (when (string= (tun.reviews:review-kind review) "zz_test")
    (setf (gethash "diff" json) (jarr '())))
  (call-next-method))

(defun request-test-review (kind proposal &key (priority "normal") (key (format nil "~a:~a" kind proposal)))
  (with-application (*app*)
    (with-transaction (:write)
      (entity-id (tun.reviews:request-review
                  :kind kind :priority priority :subject (jobj "type" "ting" "id" "t1" "revision" 1)
                  :proposal (jobj "type" "forslag" "id" proposal "revision" 2)
                  :source (jobj "type" "test" "id" "s1") :idempotency-key key
                  :title "Test" :summary "Test" :requested-by "system:test")))))

(test reviews-are-generic-idempotent-and-resolved-once
  (with-test-app (:class 'zz-review-app)
    (let ((a (request-test-review "zz_test" "p1" :priority "normal")))
      (is (string= a (request-test-review "zz_test" "p1" :key "another key")) "one pending review per proposal")
      (is (string= a (request-test-review "zz_test" "p9" :key "zz_test:p1")) "the idempotency key names one review")
      (let ((b (request-test-review "zz_test" "p2" :priority "critical"))
            (c (request-test-review "zz_test" "stale" :priority "high"))
            (d (request-test-review "zz_other" "p3")))
        (is (equal (list b c a d)
                   (map 'list (lambda (r) (jget r "id")) (jget (call-ok "reviews_list" "viewer:v") "items")))
            "critical, high, then normal by requested_at")
        (is (equalp #() (jget (call-ok "reviews_get" "viewer:v" "id" a) "diff")) "the kind adds its details")
        (is-error "forbidden" nil (call "reviews_resolve" "employee:e" "id" a "decision" "approve"))
        (let ((ok (call-ok "reviews_resolve" "admin:a" "id" a "decision" "approve" "note" "Greit")))
          (is (equal '("approved" "approved" "admin:a" "Greit")
                     (list (jget ok "result") (jget (jget ok "review") "status") (jget (jget ok "review") "reviewed_by")
                           (jget (jget ok "review") "note")))))
        (is-error "invalid_transition" "Gjennomgangen er allerede behandlet"
                  (call "reviews_resolve" "admin:a" "id" a "decision" "reject"))
        (is (equal '("superseded" "Utdatert")
                   (let ((r (call-ok "reviews_resolve" "admin:a" "id" c "decision" "approve")))
                     (list (jget r "result") (jget r "reason")))))
        (is (string= "rejected" (jget (call-ok "reviews_resolve" "admin:a" "id" b "decision" "reject") "result")))
        (is-error "invalid_transition" nil (call "reviews_resolve" "admin:a" "id" d "decision" "approve"))
        (is (string= "pending" (jget (call-ok "reviews_get" "viewer:v" "id" d) "status")) "no handler: still pending")
        (with-application (*app*) (with-transaction (:write) (tun.reviews:supersede-reviews :proposal-id "p3")))
        (is (string= "superseded" (jget (call-ok "reviews_get" "viewer:v" "id" d) "status")))
        (is (equal (list a) (map 'list (lambda (r) (jget r "id"))
                                 (jget (call-ok "reviews_list" "viewer:v" "status" "approved") "items"))))))
    ;; §12.18: a review knows no order.
    (is (notany (lambda (f) (search "order" (field-json-name f))) (entity-fields 'tun.reviews:review)))))

;;; ------------------------------------------------------------------
;;; The kernel: a client's on-open functions (the lagervarsel schedule)

(defun zz-note-opened ()
  (write-setting "zz.opened" (1+ (or (read-setting "zz.opened") 0))))

(define-application zz-on-open-app ()
  (:on-open zz-note-opened))

(test a-client-runs-its-on-open-functions-in-a-write-transaction
  (let ((db (scratch-path "on-open")))
    (dotimes (i 2)
      (let ((app (tun.runtime:open-application 'zz-on-open-app :db db :test-clock t)))
        (unwind-protect
             (is (= (1+ i) (with-application (app) (with-transaction (:read) (read-setting "zz.opened")))))
          (tun.runtime:close-application app))))))

;;; ------------------------------------------------------------------
;;; The rollback preflight on newer documents (core.md §6.4)

(defclass zz-slice2-app (zz-review-handler two-departments application) ())

(defun preflight-findings (db)
  (tun.runtime::rollback-preflight 'application db (lite-registry-path)))

(defun finding-count (findings prefix)
  (let ((finding (find-if (lambda (f) (eql 0 (search prefix (car f)))) findings)))
    (and finding (cdr finding))))

(test the-preflight-counts-tasks-and-pending-reviews
  (let ((db (scratch-path "s2-preflight-a")))
    (with-test-app (:db db :class 'zz-slice2-app)
      (make-customer)
      (call-ok "tasks_create" "admin:a" "department" "nord" "title" "Telle beger")
      (request-test-review "zz_test" "p1")
      (let ((done (request-test-review "zz_test" "p2")))
        (call-ok "reviews_resolve" "admin:a" "id" done "decision" "approve")))
    (let ((findings (preflight-findings db)))
      (is (eql 1 (finding-count findings "task: ")) "~s" findings)
      (is (eql 1 (finding-count findings "review: pending")) "a resolved review is history: ~s" findings)
      (is (= 2 (length findings)) "~s" findings))))

;;; ------------------------------------------------------------------
;;; Articles and the ledger (inventory README §2–§4)

(defun make-article (name &rest args)
  (jget (apply #'call-ok "articles_create" "admin:a" "name" name "unit" "stk" args) "id"))

(defun ledger-of (article)
  (map 'list (lambda (m) (list (jget m "revision") (jget m "kind") (jget m "quantity") (jget m "balance_after")))
       (jget (call-ok "inventory_movements" "viewer:v" "article_id" article "limit" 100) "items")))

(test the-balance-is-a-ledger-projection
  (with-test-app (:class 'departments-app)
    (let ((sb (make-article "Slushbeger" "opening_balance" 100 "sku" "SB-1" "package_size" 50)))
      (is (equal '((1 "aapning" 100 100)) (ledger-of sb)) "the opening is one aapning row")
      (is (equal '((1 "aapning" 0 0)) (ledger-of (make-article "Null"))) "an opening of 0 is a row too")
      (call-ok "inventory_receive" "employee:e" "article_id" sb "quantity" 10)
      (call-ok "inventory_adjust" "admin:a" "article_id" sb "delta" -2 "reason" "Knust")
      (call-ok "articles_recount" "admin:a" "article_id" sb "quantity" 42.5 "reason" "Telling")
      (call-ok "inventory_receive" "employee:e" "article_id" sb "quantity" 5)
      (is (equal '((5 "mottak" 5 47.5d0) (4 "telling" 42.5d0 42.5d0) (3 "justering" -2 108) (2 "mottak" 10 110)
                   (1 "aapning" 100 100))
                 (ledger-of sb)))
      (let ((article (call-ok "articles_get" "viewer:v" "id" sb)))
        (is (equal '(47.5d0 5) (list (jget article "balance") (jget article "movement_revision")))))
      ;; Nothing sets the balance but the ledger; refusals store nothing.
      (is-error "invalid_input" nil (call "articles_update" "admin:a" "id" sb "balance" 5))
      (is-error "invalid_input" nil (call "articles_update" "admin:a" "id" sb "department" "nord"))
      (is-error "conflict" nil (call "articles_create" "admin:a" "name" "Dobbel" "unit" "stk" "sku" "SB-1"))
      (is-error "invalid_input" nil (call "articles_create" "admin:a" "name" "Lenke" "unit" "stk"
                                          "supplier" (jobj "order_url" "https://ola:pw@grossist.example.no/")))
      (is-error "invalid_input" nil (call "articles_create" "admin:a" "name" "Pakning" "unit" "stk" "package_size" 0))
      (is-error "insufficient_stock" nil (call "inventory_adjust" "admin:a" "article_id" sb "delta" -100 "reason" "x"))
      (is-error "invalid_input" "Oppgi årsaken til lagerkorrigeringen"
                (call "articles_recount" "admin:a" "article_id" sb "quantity" 1))
      (is (= 5 (length (ledger-of sb))))
      ;; Archived: no receipt, adjustment or recount; reactivated by update.
      (call-ok "articles_archive" "admin:a" "id" sb)
      (is-error "invalid_input" "Lagerartikkelen er arkivert"
                (call "inventory_receive" "employee:e" "article_id" sb "quantity" 1))
      (is-error "invalid_input" "Lagerartikkelen er arkivert"
                (call "articles_recount" "admin:a" "article_id" sb "quantity" 1 "reason" "x"))
      (is (null (find sb (map 'list (lambda (a) (jget a "id")) (jget (call-ok "articles_list" "viewer:v") "items"))
                      :test #'equal)))
      (call-ok "articles_update" "admin:a" "id" sb "active" t)
      (call-ok "inventory_receive" "employee:e" "article_id" sb "quantity" 1)
      ;; A stock-tracked product's article: no opening row;
      ;; two products may share one article.
      (let* ((cup (call-ok "products_create" "employee:e" "name" "Plastkopp" "kind" "forbruk" "unit" "stk"
                           "unit_price_ore" 300 "stock_tracked" t))
             (pack (jget (call-ok "products_create" "employee:e" "name" "Plastkopp pakke" "kind" "forbruk" "unit" "stk"
                                  "unit_price_ore" 3000 "stock_tracked" nil) "id"))
             (article (jget cup "article_id")))
        (is (stringp article))
        (is (null (ledger-of article)))
        (is (= 1 (jget (call-ok "inventory_receive" "employee:e" "product_id" (jget cup "id") "quantity" 7) "revision")))
        (is-error "forbidden" nil (call "products_update" "employee:e" "id" pack "article_id" article))
        (call-ok "products_update" "admin:a" "id" pack "article_id" article)
        (is (= 7 (jget (call-ok "inventory_balance" "viewer:v" "product_id" pack) "on_hand")))
        (is-error "invalid_input" nil (call "inventory_receive" "employee:e" "product_id"
                                            (jget (call-ok "products_create" "employee:e" "name" "Tjeneste"
                                                           "kind" "tjeneste" "unit" "time" "unit_price_ore" 1
                                                           "stock_tracked" nil) "id")
                                            "quantity" 1))))))

(test an-older-databases-stock-is-adopted-at-start
  ;; An older core kept the balance in the product's stock level;
  ;; the database is made to look like one it wrote.
  (let ((db (scratch-path "s2-adopt")) product)
    (with-test-app (:db db)
      (setf product (jget (call-ok "products_create" "employee:e" "name" "Popcornbeger" "kind" "forbruk" "unit" "stk"
                                   "unit_price_ore" 500 "stock_tracked" t) "id"))
      (call-ok "inventory_receive" "employee:e" "product_id" product "quantity" 30)
      (call-ok "inventory_adjust" "admin:a" "product_id" product "delta" -4 "reason" "Svinn")
      (with-application (*app*)
        (with-transaction (:write)
          (tun.store.sqlite::exec "DELETE FROM articles")
          (tun.store.sqlite::exec "UPDATE products SET article_id = NULL")
          (tun.store.sqlite::exec "UPDATE inventory_movements SET article_id = NULL, \"by\" = NULL")
          (tun.store.sqlite::exec "INSERT INTO stock_levels (id, product_id, on_hand, revision) VALUES (?, ?, 26, 2)"
                                  product product))))
    (with-test-app (:db db)
      (let ((balance (call-ok "inventory_balance" "viewer:v" "product_id" product)))
        (is (equal '(26 0 26) (list (jget balance "on_hand") (jget balance "reserved") (jget balance "available"))))
        (is (equal '((2 "justering" -4 26) (1 "mottak" 30 30)) (ledger-of (jget balance "article_id"))))
        (is (equal "system:migration"
                   (jget (aref (jget (call-ok "inventory_movements" "viewer:v" "product_id" product) "items") 0) "by")))))
    (is (null (preflight-findings db)) "an untouched adoption is what the older core reads")
    (with-test-app (:db db)
      (is (= 3 (jget (call-ok "inventory_receive" "employee:e" "product_id" product "quantity" 1) "revision"))
          "the ledger continues from the adopted count"))
    (is (eql 1 (finding-count (preflight-findings db) "article: ")) "a moved article is refused")))

;;; ------------------------------------------------------------------
;;; Catalog requirements and the resolver (catalog README §6–§10)

(defun req (kind target quantity basis &rest more)
  (apply #'jobj "target" (jobj "kind" kind "id" target) "quantity" quantity "basis" basis more))

(defun set-reqs (product &rest requirements)
  (call "products_set_requirements" "admin:a" "product_id" product "requirements" (jarr requirements)))

(defun changes-of (n)
  (map 'list (lambda (c) (list (jget c "resource_type") (jget c "operation") (coerce (jget c "changed_fields") 'list)))
       (jget (call-ok "catalog_changes_list" "viewer:v" "limit" n) "items")))

(test requirement-declarations-target-one-thing
  (with-test-app ()
    (let* ((cup (make-article "Kopp"))
           (syrup (make-article "Sirup"))
           (r1 (jget (call-ok "recipes_create" "admin:a" "name" "Jordbær"
                              "lines" (jarr (list (jobj "article_id" syrup "quantity" 0.05)))) "id"))
           (group (jget (call-ok "choice_groups_create" "admin:a" "name" "Smaker" "members" (jarr (list r1))) "id"))
           (product (make-product :name "Prøve" :kind "tjeneste")))
      (flet ((refused (message &rest requirement)
               (is-error "invalid_input" message (set-reqs product (apply #'jobj requirement)))))
        (refused "Fyll inn mengde og hva kravet beregnes fra" "target" (jobj "kind" "article" "id" cup) "basis" "per_line")
        (refused "Fyll inn mengde og hva kravet beregnes fra" "target" (jobj "kind" "article" "id" cup) "quantity" 1)
        (refused "Fyll inn mengde og hva kravet beregnes fra" "target" (jobj "kind" "article" "id" cup) "quantity" 0
                 "basis" "per_line")
        (refused "Velg en lagerartikkel for dette kravet" "target" (jobj "kind" "article") "quantity" 1 "basis" "per_line")
        (refused "Velg en oppskrift for dette kravet" "target" (jobj "kind" "recipe") "quantity" 1 "basis" "per_line")
        (refused "Velg en oppskriftgruppe for dette kravet" "target" (jobj "kind" "choice_group") "quantity" 1
                 "basis" "per_serving" "picks" 1)
        (refused "Antall valg må være minst 1" "target" (jobj "kind" "choice_group" "id" group) "quantity" 1
                 "basis" "per_serving" "picks" 0)
        (refused "Antall valg må være minst 1" "target" (jobj "kind" "choice_group" "id" group) "quantity" 1
                 "basis" "per_serving")
        (refused "Antall valg er kun tillatt for valggruppe-krav" "target" (jobj "kind" "article" "id" cup)
                 "quantity" 1 "basis" "per_line" "picks" 2)
        (refused "Valggruppe-krav må beregnes per porsjon" "target" (jobj "kind" "choice_group" "id" group)
                 "quantity" 1 "basis" "per_line" "picks" 2)
        (refused "Mengder kan ha høyst tre desimaler" "target" (jobj "kind" "article" "id" cup) "quantity" 0.0005
                 "basis" "per_line"))
      (is-error "not_found" nil (set-reqs product (req "article" "art_nope" 1 "per_line")))
      (is-error "forbidden" nil (call "products_set_requirements" "employee:e" "product_id" product
                                      "requirements" (jarr '())))
      (is (equalp #() (jget (call-ok "products_get" "viewer:v" "id" product) "requirements")) "nothing stored")
      ;; Each requirement written is a catalog change; ids and positions kept.
      (let* ((set (set-reqs product (req "article" cup 1 "per_serving" "name" "Kopper")
                            (req "choice_group" group 1 "per_serving" "picks" 1)))
             (ids (map 'list (lambda (r) (jget r "id")) (jget set "requirements"))))
        (is (equal '(0 1) (map 'list (lambda (r) (jget r "position")) (jget set "requirements"))))
        (is (equal '(("requirement" "created" ()) ("requirement" "created" ())) (changes-of 2)))
        (set-reqs product (jobj "id" (first ids) "target" (jobj "kind" "article" "id" cup) "quantity" 2
                                "basis" "per_serving" "name" "Kopper"))
        (is (equal '(("requirement" "deleted" ()) ("requirement" "updated" ("quantity"))) (changes-of 2)))
        (is-error "invalid_input" nil (set-reqs product (jobj "id" "krv_ukjent" "target" (jobj "kind" "article" "id" cup)
                                                              "quantity" 1 "basis" "per_line"))))
      ;; Recipes and groups: writes are catalog changes; no recipe twice in a group.
      (is-error "invalid_input" nil (call "choice_groups_create" "admin:a" "name" "Dobbel" "members" (jarr (list r1 r1))))
      (call-ok "recipes_update" "admin:a" "id" r1 "lines" (jarr (list (jobj "article_id" syrup "quantity" 0.1))))
      (is (equal '(("recipe" "updated" ("lines"))) (changes-of 1)))
      (call-ok "recipes_archive" "admin:a" "id" r1)
      (is (equal '(("recipe" "updated" ("active"))) (changes-of 1))))))

(defun resolved (product &rest args)
  "RESOLVE-LINE's entries for PRODUCT as (article quantity source_key) lists."
  (with-application (*app*)
    (with-transaction (:read)
      (mapcar (lambda (e) (list (first e) (second e) (jget (third e) "source_key")))
              (apply #'tun.catalog:resolve-line product args)))))

(test the-resolver-expands-every-basis
  (with-test-app ()
    (let* ((cup (make-article "Kopp")) (straw (make-article "Sugerør"))
           (strawberry (make-article "Jordbærsirup")) (blueberry (make-article "Blåbærsirup")) (ice (make-article "Is"))
           (rj (call-ok "recipes_create" "admin:a" "name" "Jordbær" "lines" (jarr (list (jobj "article_id" strawberry "quantity" 0.05)))))
           (rb (call-ok "recipes_create" "admin:a" "name" "Blåbær" "lines" (jarr (list (jobj "article_id" blueberry "quantity" 0.05)))))
           (ri (call-ok "recipes_create" "admin:a" "name" "Isbiter" "lines" (jarr (list (jobj "article_id" ice "quantity" 0.1)))))
           (group (jget (call-ok "choice_groups_create" "admin:a" "name" "Smaker"
                                 "members" (jarr (list (jget rj "id") (jget rb "id")))) "id"))
           (slush (make-product :name "Slush" :units-owned 9))
           (reqs (jget (call-ok "products_set_requirements" "admin:a" "product_id" slush "requirements"
                                (jarr (list (req "choice_group" group 1 "per_serving" "picks" 2 "name" "Smaker")
                                            (req "article" cup 1 "per_serving") (req "article" straw 2 "per_quantity")
                                            (req "recipe" (jget ri "id") 1 "per_day") (req "article" straw 10 "per_line"))))
                       "requirements"))
           (rid (lambda (i) (jget (aref reqs i) "id")))
           (choices (jobj (funcall rid 0) (jarr (list (jget rj "id") (jget rb "id"))))))
      ;; §12.7: picks on half the servings, static cups on the full servings.
      (is (equal `((,strawberry 5 ,(format nil "krav:~a:~a:1:~a:~a" (funcall rid 0) (jget rj "id")
                                          (jget (aref (jget rj "lines") 0) "id") strawberry))
                   (,blueberry 5 ,(format nil "krav:~a:~a:2:~a:~a" (funcall rid 0) (jget rb "id")
                                         (jget (aref (jget rb "lines") 0) "id") blueberry))
                   (,cup 200 ,(format nil "krav:~a:~a" (funcall rid 1) cup))
                   (,straw 2 ,(format nil "krav:~a:~a" (funcall rid 2) straw))
                   (,ice 3/10 ,(format nil "krav:~a:~a:~a:~a" (funcall rid 3) (jget ri "id")
                                       (jget (aref (jget ri "lines") 0) "id") ice))
                   (,straw 10 ,(format nil "krav:~a:~a" (funcall rid 4) straw)))
                 (resolved slush :quantity 1 :servings 200 :choices choices :days 3)))
      (is (equal (list (list ice 1/10)) (mapcar (lambda (e) (subseq e 0 2))
                                                (remove-if-not (lambda (e) (equal (first e) ice))
                                                               (resolved slush :servings 200 :choices choices))))
          "one day when dateless")
      (is (equal (list straw ice straw)
                 (mapcar #'first (remove-if-not (lambda (e) (plusp (second e)))
                                                (resolved slush :servings 0 :choices choices :days 1))))
          "servings 0: per-serving and choice entries come to nothing (a plan keeps positive lines only)")
      (is (null (remove-if-not (lambda (e) (member (first e) (list strawberry blueberry)))
                               (resolved slush :servings 201 :choices choices)))
          "servings not divisible by picks resolve no picks")
      ;; §4.3: the choices on a line.
      (flet ((check (quantity servings choices)
               (with-application (*app*)
                 (with-transaction (:read)
                   (handler-case (progn (tun.catalog:check-line-choices slush quantity servings choices) nil)
                     (operation-error (e) (operation-error-message e)))))))
        (is (null (check 1 200 choices)))
        (is (equal "Ordrelinjer med valggruppekrav må ha antall 1. Legg til én linje per enhet." (check 2 200 choices)))
        (is (equal "Smaker krever 2 valg (1 valgt)" (check 1 200 (jobj (funcall rid 0) (jarr (list (jget rj "id")))))))
        (is (equal "Smaker krever 2 valg (0 valgt)" (check 1 200 nil)) "missing choices count as zero picks")
        (is (equal "Porsjoner må deles likt på 2 valg" (check 1 201 choices)))
        (is (equal "Smaker inneholder ugyldige valg"
                   (check 1 200 (jobj (funcall rid 0) (jarr (list (jget rj "id") (jget ri "id")))))))
        (call-ok "recipes_archive" "admin:a" "id" (jget rb "id"))
        (is (equal "Smaker inneholder ugyldige valg" (check 1 200 choices)) "an archived pick")))))

(test lite-recipes-resolve-to-ceil-per-100
  (with-test-app ()
    (let* ((beger (call-ok "products_create" "employee:e" "name" "Beger" "kind" "forbruk" "unit" "stk"
                           "unit_price_ore" 500 "stock_tracked" t))
           (kjerner (call-ok "products_create" "employee:e" "name" "Kjerner" "kind" "forbruk" "unit" "pose"
                             "unit_price_ore" 15000 "stock_tracked" t))
           (machine (make-product :name "Popcornmaskin")))
      (with-application (*app*)
        (with-transaction (:write)
         (with-actor ((make-actor :employee "e"))
          (tun.catalog:set-lite-recipe (fetch 'tun.catalog:product machine)
                                       (list (cons (jget beger "article_id") 100) (cons (jget kjerner "article_id") 1))))))
      (let ((product (call-ok "products_get" "viewer:v" "id" machine)))
        (is (equal '(("recipe" "per_serving" 1 "ceil_per_100"))
                   (map 'list (lambda (r) (list (jget (jget r "target") "kind") (jget r "basis") (jget r "quantity")
                                                (jget r "rounding")))
                        (jget product "requirements")))))
      ;; §12.8: ceil(servings x per_100 / 100) per component.
      (is (equal (list (list (jget beger "article_id") 250) (list (jget kjerner "article_id") 3))
                 (mapcar (lambda (e) (subseq e 0 2)) (resolved machine :servings 250)))))))

;;; ------------------------------------------------------------------
;;; Plans, reviews, correction and catalog impact (orders README §9, §11; reviews README)

(defun plans-of (order)
  (map 'list (lambda (p) (list (jget p "revision") (jget p "status") (jget p "activation")))
       (jget (call-ok "plans_list" "viewer:v" "order_id" order) "items")))

(defun plan-state-of (order)
  (let ((p (jget (call-ok "orders_get" "viewer:v" "id" order) "plan")))
    (list (jget p "active_revision") (jget p "proposed_revision") (not (json-null-p (jget p "pending_review_id")))
          (jget p "consumption_applied") (jget p "correction_required"))))

(defun reserved-of (article) (jget (call-ok "inventory_balance" "viewer:v" "article_id" article) "reserved"))

(defun set-quantity (order quantity)
  (let* ((o (call-ok "orders_get" "viewer:v" "id" order))
         (line (aref (jget o "lines") 0)))
    (call "orders_update" "employee:e" "id" order "revision" (jget o "revision")
          "lines" (jarr (list (jobj "id" (jget line "id") "product_id" (jget line "product_id") "quantity" quantity))))))

(defun catalog-pass (time) (call-ok "clock_set" "admin:a" "now" time))

(test plans-follow-the-activation-rules
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (machine (make-product :name "Popcornmaskin" :units-owned 9))
           (reqs (jget (call-ok "products_set_requirements" "admin:a" "product_id" machine
                                "requirements" (jarr (list (req "article" cup 10 "per_quantity"))))
                       "requirements"))
           (rid (jget (aref reqs 0) "id"))
           (customer (make-customer))
           (order (jget (new-order customer "event_date" "2026-06-20" "lines" (jarr (list (line machine 2)))) "id")))
      (catalog-pass "2026-03-01T09:00:10Z")
      (let ((p1 (aref (jget (call-ok "plans_list" "viewer:v" "order_id" order) "items") 0)))
        (is (equal '(1 "active" "automatic" "employee:anna" 1)
                   (list (jget p1 "revision") (jget p1 "status") (jget p1 "activation") (jget p1 "activated_by")
                         (jget p1 "order_revision"))))
        (is (= 64 (length (jget p1 "fingerprint")))))
      (is (equal '(1 :null nil nil nil) (plan-state-of order)))
      ;; A requirement-neutral edit keeps the plan; an edit in utkast activates.
      (let ((o (call-ok "orders_get" "viewer:v" "id" order)))
        (is (= 2 (jget (call-ok "orders_update" "employee:e" "id" order "revision" (jget o "revision")
                                "tags" (jarr (list "utleie")))
                       "revision"))))
      (is (equal '((1 "active" "automatic")) (plans-of order)))
      (call-ok "orders_update" "employee:e" "id" order "revision" 2
               "lines" (jarr (list (jobj "id" (jget (aref (jget (call-ok "orders_get" "viewer:v" "id" order) "lines") 0) "id")
                                         "product_id" machine "quantity" 3))))
      (is (equal '((2 "active" "automatic") (1 "superseded" "automatic")) (plans-of order)))
      (is (= 20 (jget (aref (jget (call-ok "plans_get" "viewer:v"
                                           "id" (jget (aref (jget (call-ok "plans_list" "viewer:v" "order_id" order) "items") 1) "id"))
                                  "lines") 0)
                      "quantity"))
          "plans are immutable: revision 1 still holds 20")
      ;; Confirmed: the active plan reserves; an own edit activates at once (rule 7).
      (advance-to-accepted order)
      (two-step "orders_confirm" "employee:anna" "id" order)
      (is (= 30 (reserved-of cup)))
      (set-quantity order 4)
      (is (equal '(3 :null nil nil nil) (plan-state-of order)))
      (is (= 40 (reserved-of cup)) "the reservation follows at once")
      ;; A catalog change on a bekreftet order proposes (rule 6); only the active plan reserves.
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 12
                                                "basis" "per_quantity"))))
      (catalog-pass "2026-03-01T09:01:00Z")
      (is (equal '(3 4 t nil nil) (plan-state-of order)))
      (is (= 40 (reserved-of cup)))
      (let* ((review-id (jget (jget (call-ok "orders_get" "viewer:v" "id" order) "plan") "pending_review_id"))
             (review (call-ok "reviews_get" "viewer:v" "id" review-id)))
        (is (equal (list "order_plan" "pending" 3 4 "catalog_change" "system:workflow")
                   (list (jget review "kind") (jget review "status") (jget (jget review "subject") "revision")
                         (jget (jget review "proposal") "revision") (jget (jget review "source") "type")
                         (jget review "requested_by"))))
        (is (equal (list (list "Beger" 40 48 "increased"))
                   (map 'list (lambda (d) (list (jget d "article_name") (jget d "before") (jget d "after") (jget d "change")))
                        (jget review "diff"))))
        ;; Rule 4: the same snapshot keeps the proposal and its review.
        (call-ok "recipes_create" "admin:a" "name" "Uten betydning")
        (catalog-pass "2026-03-01T09:02:00Z")
        (is (equal '(3 4 t nil nil) (plan-state-of order)))
        (is (= 4 (length (plans-of order))))
        ;; Approval activates the proposal, re-reserves and re-syncs the checklist (invariant 11).
        (is-error "forbidden" nil (call "reviews_resolve" "employee:e" "id" review-id "decision" "approve"))
        (is (string= "approved" (jget (call-ok "reviews_resolve" "admin:a" "id" review-id "decision" "approve") "result")))
        (is (equal '(4 "active" "review") (first (plans-of order))))
        (is (= 48 (reserved-of cup)))
        (is (equal '(48) (map 'list (lambda (i) (jget i "computed_quantity"))
                              (jget (call-ok "checklists_list" "viewer:v" "order_id" order) "items"))))
        (is-error "invalid_transition" "Gjennomgangen er allerede behandlet"
                  (call "reviews_resolve" "admin:a" "id" review-id "decision" "approve")))
      ;; Rule 1: back to the active snapshot supersedes a proposal and its review.
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 15
                                                "basis" "per_quantity"))))
      (catalog-pass "2026-03-01T09:03:00Z")
      (let ((pending (jget (jget (call-ok "orders_get" "viewer:v" "id" order) "plan") "pending_review_id")))
        (call-ok "products_set_requirements" "admin:a" "product_id" machine
                 "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 12
                                                  "basis" "per_quantity"))))
        (catalog-pass "2026-03-01T09:04:00Z")
        (is (equal '(4 :null nil nil nil) (plan-state-of order)))
        (is (string= "superseded" (jget (call-ok "reviews_get" "viewer:v" "id" pending) "status"))))
      ;; Rule 5: a rejected snapshot is not proposed again.
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 20
                                                "basis" "per_quantity"))))
      (catalog-pass "2026-03-01T09:05:00Z")
      (let ((pending (jget (jget (call-ok "orders_get" "viewer:v" "id" order) "plan") "pending_review_id")))
        (is (string= "rejected" (jget (call-ok "reviews_resolve" "admin:a" "id" pending "decision" "reject") "result"))))
      (call-ok "recipes_create" "admin:a" "name" "Igjen uten betydning")
      (catalog-pass "2026-03-01T09:06:00Z")
      (is (equal '(4 :null nil nil nil) (plan-state-of order)))
      (is (equal '((6 "rejected" :null) (5 "superseded" :null) (4 "active" "review")
                   (3 "superseded" "automatic") (2 "superseded" "automatic") (1 "superseded" "automatic"))
                 (plans-of order))
          "at most one active and one proposed; revisions unique"))))

(defun last-impact-status (order)
  (jget (car (last (coerce (jget (call-ok "plan_impacts_list" "viewer:v" "order_id" order) "items") 'list))) "status"))

(test resolution-fails-closed-and-consumed-orders-need-a-correction
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (machine (make-product :name "Popcornmaskin" :units-owned 9))
           (rid (jget (aref (jget (call-ok "products_set_requirements" "admin:a" "product_id" machine
                                           "requirements" (jarr (list (req "article" cup 10 "per_quantity"))))
                                  "requirements") 0) "id"))
           (customer (make-customer))
           (orders (loop for date in '("2026-03-02" "2026-06-20" "2026-06-21" "2026-06-22")
                         collect (confirmed-order customer machine date))))
      (destructuring-bind (soon stale-status stale-catalog consumed) orders
        (catalog-pass "2026-03-01T09:00:10Z")
        (call-ok "orders_complete" "employee:anna" "id" consumed)
        (two-step "orders_reopen" "admin:a" "id" consumed)
        (call-ok "products_set_requirements" "admin:a" "product_id" machine
                 "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 11
                                                  "basis" "per_quantity"))))
        (catalog-pass "2026-03-01T09:01:00Z")
        (flet ((review-of (order) (jget (jget (call-ok "orders_get" "viewer:v" "id" order) "plan") "pending_review_id")))
          (is (string= "critical" (jget (call-ok "reviews_get" "viewer:v" "id" (review-of soon)) "priority")) "1 day away")
          ;; The consumed order: a conflict, no proposal; a correction is required.
          (is (equal '(1 :null nil t t) (plan-state-of consumed)))
          (is (equal "conflict" (last-impact-status consumed)))
          ;; Stale: the order left bekreftet; the catalog changed after the proposal.
          (let ((review (review-of stale-status)))
            (call-ok "orders_reactivate" "employee:e" "id" stale-status)
            (is (equal '("superseded" "Ordrestatusen tillater ikke lenger godkjenning")
                       (let ((r (call-ok "reviews_resolve" "admin:a" "id" review "decision" "approve")))
                         (list (jget r "result") (jget r "reason"))))))
          (let ((review (review-of stale-catalog)))
            (call-ok "products_set_requirements" "admin:a" "product_id" machine
                     "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 13
                                                      "basis" "per_quantity"))))
            (is (equal '("superseded" "Katalogen eller ordren er endret etter forslaget")
                       (let ((r (call-ok "reviews_resolve" "admin:a" "id" review "decision" "approve")))
                         (list (jget r "result") (jget r "reason"))))))
          ;; Rule 2 on edit; the correction.
          (is-error "invalid_input" "Ordren har lagerforbruk og krever en eksplisitt korrigering" (set-quantity consumed 2))
          (is-error "invalid_transition" "Det finnes ingen registrert lagerforbruk å korrigere"
                    (two-step "orders_correct_plan" "admin:a" "id" soon "note" "x"))
          (is-error "forbidden" nil (call "orders_correct_plan" "employee:e" "id" consumed "note" "x"))
          (is-error "invalid_input" "Oppgi en merknad for korrigeringen"
                    (two-step "orders_correct_plan" "admin:a" "id" consumed "note" "  "))
          (let* ((before (call-ok "orders_get" "viewer:v" "id" consumed))
                 (done (two-step "orders_correct_plan" "admin:a" "id" consumed "note" "Ny oppskrift")))
            (is (= (1+ (jget before "revision")) (jget done "revision")))
            (is (= (jget before "total_ore") (jget done "total_ore")) "pricing is never touched")
            (is (equal '(2 "active" "correction") (first (plans-of consumed))))
            (is (= 13 (jget (aref (jget (call-ok "inventory_movements" "viewer:v" "article_id" cup "limit" 1) "items") 0)
                            "quantity"))
                "consumption re-synced at the new revision")
            (is (equal "corrected" (last-impact-status consumed)))
            (is (equal '(2 :null nil t nil) (plan-state-of consumed))))
          (is-error "invalid_transition" "Det finnes ingen ny kravendring å korrigere"
                    (two-step "orders_correct_plan" "admin:a" "id" consumed "note" "igjen")))))))

(test catalog-impact-reaches-future-orders-each-independently
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (machine (make-product :name "Popcornmaskin" :units-owned 9))
           (rid (jget (aref (jget (call-ok "products_set_requirements" "admin:a" "product_id" machine
                                           "requirements" (jarr (list (req "article" cup 10 "per_quantity"))))
                                  "requirements") 0) "id"))
           (customer (make-customer))
           (consumed (confirmed-order customer machine "2026-06-01"))
           (draft (jget (new-order customer "event_date" "2026-06-02" "lines" (jarr (list (line machine 1)))) "id"))
           (confirmed (confirmed-order customer machine "2026-06-03"))
           (past (jget (new-order customer "event_date" "2026-02-01" "lines" (jarr (list (line machine 1)))) "id"))
           (dateless (jget (new-order customer "lines" (jarr (list (line machine 1)))) "id"))
           (cancelled (confirmed-order customer machine "2026-06-04")))
      (call-ok "orders_complete" "employee:anna" "id" consumed)
      (two-step "orders_reopen" "admin:a" "id" consumed)
      (two-step "orders_cancel" "employee:anna" "id" cancelled)
      (catalog-pass "2026-03-01T09:00:10Z")
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 11
                                                "basis" "per_quantity"))))
      (let ((change (jget (aref (jget (call-ok "catalog_changes_list" "viewer:v" "limit" 1) "items") 0) "id")))
        (is (>= (jget (catalog-pass "2026-03-01T09:01:00Z") "executed_workflows") 1))
        (flet ((impacts (order)
                 (map 'list (lambda (i) (list (jget i "status") (jget i "detail") (jget i "plan_revision")))
                      (remove change (coerce (jget (call-ok "plan_impacts_list" "viewer:v" "order_id" order) "items") 'list)
                              :key (lambda (i) (jget i "catalog_change_id")) :test-not #'equal))))
          (is (equal '(("conflict" "Ordren har lagerforbruk og krever en eksplisitt korrigering" :null)) (impacts consumed)))
          (is (equal '(("applied" "Ny kravplan aktivert automatisk" 2)) (impacts draft)) "one conflict blocks no other")
          (is (equal '(("proposed" "Forslag opprettet for gjennomgang" 2)) (impacts confirmed)))
          (is (equal '(nil nil nil) (list (impacts past) (impacts dateless) (impacts cancelled)))
              "past, dateless and closed orders are left alone")
          (is (= 11 (jget (aref (jget (call-ok "orders_get" "viewer:v" "id" draft) "requirements") 0) "quantity"))))))))

;;; ------------------------------------------------------------------
;;; Consumption (inventory README §6, orders README §10)

(defun forbruk-of (article order)
  (map 'list (lambda (m) (list (jget m "quantity") (jget m "balance_updated")))
       (remove-if-not (lambda (m) (and (equal "forbruk" (jget m "kind")) (equal order (jget m "order_id"))))
                      (coerce (jget (call-ok "inventory_movements" "viewer:v" "article_id" article "limit" 100) "items")
                              'list))))

(defun balance-of (article) (jget (call-ok "articles_get" "viewer:v" "id" article) "balance"))

(test consumption-follows-the-plan-once-and-a-recount-wins
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 500))
           (kernel (make-article "Kjerner" "unit" "kg" "opening_balance" 10))
           (machine (make-product :name "Popcornmaskin" :units-owned 9))
           (customer (make-customer)))
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (req "article" cup 100 "per_quantity") (req "article" kernel 0.5 "per_quantity"))))
      (let ((k1 (confirmed-order customer machine "2026-06-01")))
        (is (equal '(100 0.5d0) (list (reserved-of cup) (reserved-of kernel))) "the active plan is reserved")
        (let ((picked (call-ok "orders_register_pickup" "employee:e" "id" k1 "condition" "ok")))
          (is (eq t (jget (jget picked "plan") "consumption_applied"))))
        (is (equal '((100 t)) (forbruk-of cup k1)) "one row per article at pickup")
        (is (equal '(400 9.5d0 0 0) (list (balance-of cup) (balance-of kernel) (reserved-of cup) (reserved-of kernel))))
        (let ((row (aref (jget (call-ok "inventory_movements" "viewer:v" "article_id" cup "limit" 1) "items") 0)))
          (is (equal (list "Reservert for ordre" k1 "employee:e")
                     (list (jget row "reason") (jget row "order_id") (jget row "by")))))
        (call-ok "orders_register_return" "employee:e" "id" k1 "condition" "ok")
        (call-ok "orders_ready_for_invoice" "employee:e" "id" k1)
        (call-ok "orders_complete" "employee:e" "id" k1)
        (is (equal '(((100 t)) 400) (list (forbruk-of cup k1) (balance-of cup))) "completion after pickup adds nothing"))
      ;; Completion from bekreftet consumes; reopen does not reverse; again nothing.
      (let ((k2 (confirmed-order customer machine "2026-06-02")))
        (call-ok "orders_complete" "employee:e" "id" k2)
        (two-step "orders_reopen" "admin:a" "id" k2)
        (is (equal '(300 0) (list (balance-of cup) (reserved-of cup))) "consumed, reopened: nothing reserved")
        (call-ok "orders_complete" "employee:e" "id" k2)
        (is (equal '(((100 t)) 300) (list (forbruk-of cup k2) (balance-of cup)))))
      ;; insufficient_stock aborts the pickup and changes nothing.
      (let ((k3 (confirmed-order customer machine "2026-06-03")))
        (call-ok "products_set_requirements" "admin:a" "product_id" machine
                 "requirements" (jarr (list (req "article" cup 1000 "per_quantity"))))
        ;; An own change of the snapshot activates it (a neutral edit would not, 13.2.23).
        (set-quantity k3 2)
        (is-error "insufficient_stock" nil (call "orders_register_pickup" "employee:e" "id" k3 "condition" "ok"))
        (is (equal (list "bekreftet" nil 300)
                   (list (jget (call-ok "orders_get" "viewer:v" "id" k3) "status") (forbruk-of cup k3) (balance-of cup))))
        (two-step "orders_cancel" "employee:e" "id" k3))
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (req "article" cup 100 "per_quantity") (req "article" kernel 0.5 "per_quantity"))))
      ;; Cancelling after a recount: the recounted article stays counted, the other is restored.
      (let ((k4 (confirmed-order customer machine "2026-06-04")))
        (call-ok "orders_register_pickup" "employee:e" "id" k4 "condition" "ok")
        (is (equal '(200 8.5d0) (list (balance-of cup) (balance-of kernel))))
        (call-ok "articles_recount" "admin:a" "article_id" cup "quantity" 150 "reason" "Telling")
        (call-ok "orders_register_return" "employee:e" "id" k4 "condition" "ok")
        (call-ok "orders_ready_for_invoice" "employee:e" "id" k4)
        (two-step "orders_cancel" "employee:e" "id" k4)
        (is (equal '(150 9 nil nil) (list (balance-of cup) (balance-of kernel) (forbruk-of cup k4) (forbruk-of kernel k4))))
        (is (eq nil (jget (jget (call-ok "orders_get" "viewer:v" "id" k4) "plan") "consumption_applied"))))
      ;; Archived articles are still consumed and reversed.
      (let ((k5 (confirmed-order customer machine "2026-06-05")))
        (call-ok "articles_archive" "admin:a" "id" kernel)
        (call-ok "orders_complete" "employee:e" "id" k5)
        (is (equal '((0.5d0 t)) (forbruk-of kernel k5)))
        (two-step "orders_reopen" "admin:a" "id" k5)
        (two-step "orders_cancel" "employee:e" "id" k5)
        (is (= 9 (balance-of kernel)))))))

(test the-consumption-command-rules
  ;; 6.2.2: older commands and repeats are no-ops; the same revision and date
  ;; with another payload is a conflict (not reachable through the tools,
  ;; 13.1.9); a recount between commands makes the new row not deduct.
  (with-test-app ()
    (let ((cup (make-article "Beger" "opening_balance" 100)))
      (flet ((sync (revision date quantity)
               (with-application (*app*)
                 (with-transaction (:write)
                   (with-actor ((make-actor :admin "a"))
                     (handler-case (progn (tun.inventory:sync-consumption "ord_test" revision date
                                                                          (and quantity (list (cons cup quantity))))
                                          :ok)
                       (operation-error (e) (operation-error-code e))))))))
        (is (eq :ok (sync 3 "2026-06-01" 10)))
        (is (equal '(90 ((10 t))) (list (balance-of cup) (forbruk-of cup "ord_test"))))
        (sync 2 "2026-06-01" 50)
        (sync 3 "2026-05-01" 50)
        (sync 3 "2026-06-01" 10)
        (is (equal '(90 ((10 t))) (list (balance-of cup) (forbruk-of cup "ord_test"))) "older and repeated: no-ops")
        (is (eq :conflict (sync 3 "2026-06-01" 20)))
        (is (eq :ok (sync 4 "2026-06-01" 20)))
        (is (equal '(80 ((20 t))) (list (balance-of cup) (forbruk-of cup "ord_test"))) "replaced wholesale")
        (call-ok "articles_recount" "admin:a" "article_id" cup "quantity" 70 "reason" "Telling")
        (is (eq :ok (sync 5 "2026-06-01" 25)))
        (is (equal '(70 ((25 nil))) (list (balance-of cup) (forbruk-of cup "ord_test")))
            "after a recount the row does not deduct")
        (is (eq :ok (sync 6 "2026-06-01" nil)))
        (is (equal '(70 nil) (list (balance-of cup) (forbruk-of cup "ord_test"))) "a row that did not deduct restores nothing")))))

;;; ------------------------------------------------------------------
;;; Forecast, shortages, suggestions; capacity and grid
;;; (inventory README §7–§10, catalog README §3)

(defun forecast-of (article from to &rest args)
  (aref (jget (apply #'call-ok "inventory_forecast" "viewer:v" "from" from "to" to "article_id" article args) "articles") 0))

(test the-forecast-counts-committed-demand-once
  (with-test-app ()
    (call-ok "clock_set" "admin:a" "now" "2026-04-01T09:00:00Z")
    (let* ((sugar (make-article "Sukker" "opening_balance" 50 "package_size" 25 "lead_days" 5
                                "supplier" (jobj "name" "Grossisten AS")))
           (lids (make-article "Lokk" "opening_balance" 20 "min_level" 30 "package_size" 100))
           (machine (make-product :name "Sukkerspinn" :units-owned 99))
           (lidset (make-product :name "Lokksett" :kind "tjeneste"))
           (customer (make-customer)))
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (req "article" sugar 10 "per_quantity"))))
      (call-ok "products_set_requirements" "admin:a" "product_id" lidset
               "requirements" (jarr (list (req "article" lids 25 "per_line"))))
      (call-ok "clock_set" "admin:a" "now" "2026-04-01T09:00:30Z")
      (flet ((order (quantity date &key (product machine) (to :confirmed))
               (let ((id (jget (new-order customer "event_date" date "lines" (jarr (list (line product quantity)))) "id")))
                 (case to
                   (:confirmed (advance-to-accepted id) (two-step "orders_confirm" "employee:anna" "id" id))
                   (:picked (advance-to-accepted id) (two-step "orders_confirm" "employee:anna" "id" id)
                    (call-ok "orders_register_pickup" "employee:e" "id" id "condition" "ok"))
                   (:cancelled (two-step "orders_cancel" "employee:anna" "id" id)))
                 id)))
        (order 1 "2026-04-08" :to :picked)          ; consumed: 10 already in the balance
        (order 2 "2026-04-10")                      ; 20
        (order 4 "2026-04-12")                      ; 40
        (order 9 "2026-04-11" :to :cancelled)
        (order 1 "2026-04-02")                      ; between today and from: carried to from
        (order 1 "2026-03-30")                      ; past: historical
        (order 1 "2026-04-13" :to :draft)           ; not committed
        (order 1 "2026-04-15" :product lidset)
        (let ((f (forecast-of sugar "2026-04-05" "2026-04-14")))
          (is (equal '(40 -30 "shortage") (list (jget f "start_balance") (jget f "end_balance") (jget f "status"))))
          (is (equal '(("2026-04-05" 10) ("2026-04-10" 20) ("2026-04-12" 40))
                     (loop for d across (jget f "days") unless (zerop (jget d "demand"))
                           collect (list (jget d "date") (jget d "demand"))))
              "consumed, cancelled and unconfirmed orders add nothing; carried demand lands on from")
          (is (equal '(30 30 30 30 30 10 10 -30 -30 -30) (map 'list (lambda (d) (jget d "balance")) (jget f "days")))))
        (let ((f (forecast-of sugar "2026-03-28" "2026-04-03")))
          (is (equal '(("2026-03-30" 10 40 t) ("2026-04-01" 0 40 nil) ("2026-04-02" 10 30 nil))
                     (loop for d across (jget f "days") when (member (jget d "date") '("2026-03-30" "2026-04-01" "2026-04-02") :test #'equal)
                           collect (list (jget d "date") (jget d "demand") (jget d "balance") (jget d "historical"))))
              "historical days subtract nothing"))
        (is (= -40 (jget (forecast-of sugar "2026-04-05" "2026-04-14" "include_unconfirmed" t) "end_balance"))
            "include_unconfirmed adds the utkast order")
        (is (equal "shortage" (jget (forecast-of lids "2026-04-01" "2026-04-20") "status")) "20 on hand, 25 needed")
        (is-error "invalid_input" nil (call "inventory_forecast" "viewer:v" "from" "2026-01-01" "to" "2027-06-01"))
        ;; Shortages: committed demand over today..before_date.
        (is (equal '(("Sukker" 70 40 30))
                   (map 'list (lambda (i) (list (jget i "name") (jget i "needed") (jget i "on_hand") (jget i "shortfall")))
                        (remove "Sukker" (coerce (jget (call-ok "inventory_shortages" "viewer:v" "before_date" "2026-04-30") "items") 'list)
                                :key (lambda (i) (jget i "name")) :test-not #'equal))))
        ;; Suggestions: package rounding, lead days, min level.
        (let ((items (coerce (jget (call-ok "inventory_purchase_suggestions" "viewer:v" "days" 30) "items") 'list)))
          (is (equal '(("Sukker" 30 2 50 "2026-04-12" "2026-04-07" "Grossisten AS") ("Lokk" 35 1 100 "2026-04-15" "2026-04-15" nil))
                     (mapcar (lambda (s) (list (jget s "name") (jget s "shortage_quantity") (jget s "packages")
                                               (jget s "order_quantity") (jget s "first_shortage_date") (jget s "order_by")
                                               (let ((name (jget (jget s "supplier") "name"))) (and (stringp name) name))))
                             items))))))))

(test the-capacity-guard-and-the-grid-agree-with-bookings
  (with-test-app ()
    (let* ((castle (make-product :name "Hoppeslott" :units-owned 3))
           (customer (make-customer))
           (a (confirmed-order customer castle "2026-06-10"))
           (b (confirmed-order customer castle "2026-06-10")))
      (declare (ignore b))
      (is-error "invalid_input" "Antall enheter kan ikke settes til 1; opptil 2 er allerede booket i aktive ordrer."
                (call "products_update" "employee:e" "id" castle "units_owned" 1))
      (is-error "invalid_input" "Tilgjengelighet kan ikke deaktiveres mens opptil 2 er booket i aktive ordrer."
                (call "products_update" "employee:e" "id" castle "kind" "tjeneste"))
      (is (= 2 (jget (call-ok "products_update" "employee:e" "id" castle "units_owned" 2) "units_owned")))
      (let ((days (jget (aref (jget (call-ok "inventory_availability_grid" "viewer:v" "from" "2026-06-09" "to" "2026-06-11"
                                             "product_ids" (jarr (list castle)))
                                    "items") 0)
                        "days")))
        (loop for d across days
              for check = (call-ok "availability_check" "viewer:v" "product_id" castle "date" (jget d "date"))
              do (is (equal (list (jget check "blocked") (jget check "available") (jget check "units_owned"))
                            (list (jget d "booked") (jget d "available") (jget d "total"))))))
      (is-error "invalid_input" nil (call "inventory_availability_grid" "viewer:v" "from" "2026-06-09" "to" "2026-06-10"
                                          "product_ids" (jarr (make-list 7 :initial-element castle))))
      (two-step "orders_cancel" "employee:anna" "id" a)
      (is-error "invalid_input" nil (call "products_update" "employee:e" "id" castle "units_owned" 0))
      (is (= 1 (jget (call-ok "products_update" "employee:e" "id" castle "units_owned" 1) "units_owned"))))))

;;; ------------------------------------------------------------------
;;; Slice 2 13.2 (the reviews' findings)

(test a-neutral-own-edit-keeps-a-pending-proposal
  ;; 13.2.23: a catalog change never rides into activation on a neutral edit.
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (machine (make-product :name "Maskin" :units-owned 9))
           (rid (jget (aref (jget (call-ok "products_set_requirements" "admin:a" "product_id" machine
                                           "requirements" (jarr (list (req "article" cup 10 "per_quantity"))))
                                  "requirements") 0) "id"))
           (order (confirmed-order (make-customer) machine "2026-06-20")))
      (catalog-pass "2026-03-01T09:00:10Z")
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 12
                                                "basis" "per_quantity"))))
      (catalog-pass "2026-03-01T09:01:00Z")
      (is (equal '(1 2 t nil nil) (plan-state-of order)))
      (let ((o (call-ok "orders_get" "viewer:v" "id" order)))
        (call-ok "orders_update" "employee:e" "id" order "revision" (jget o "revision") "tags" (jarr (list "utleie"))))
      (is (equal '(1 2 t nil nil) (plan-state-of order)) "the proposal and its review stay")
      (is (= 10 (reserved-of cup)))
      (set-quantity order 2)
      (is (equal '(3 :null nil nil nil) (plan-state-of order)) "an own change activates the fresh snapshot")
      (is (= 24 (reserved-of cup))))))

(test consumption-on-every-path-and-reactivation-reverses
  ;; 13.2.24, 13.2.25
  (with-test-app ()
    (let* ((cup (make-article "Serviett" "opening_balance" 100))
           (service (make-product :name "Servering" :kind "tjeneste"))
           (customer (make-customer)))
      (call-ok "products_set_requirements" "admin:a" "product_id" service
               "requirements" (jarr (list (req "article" cup 10 "per_line"))))
      (let ((a (confirmed-order customer service "2026-06-01")))
        (call-ok "orders_ready_for_invoice" "employee:e" "id" a)
        (is (equal '(90 ((10 t))) (list (balance-of cup) (forbruk-of cup a))) "invoicing readiness consumes without pickup")
        (call-ok "orders_complete" "employee:e" "id" a)
        (is (= 90 (balance-of cup)) "and completion adds nothing"))
      (let ((b (confirmed-order customer service "2026-06-02")))
        (call-ok "orders_complete" "employee:e" "id" b)
        (two-step "orders_reopen" "admin:a" "id" b)
        (call-ok "orders_reactivate" "employee:e" "id" b)
        (is (equal '(90 nil) (list (balance-of cup) (forbruk-of cup b))))
        (is (eq nil (jget (jget (call-ok "orders_get" "viewer:v" "id" b) "plan") "consumption_applied")))
        (is (= 2 (jget (aref (jget (set-quantity b 2) "lines") 0) "quantity")) "editable again")))))

(test catalog-impact-is-bounded-and-commits-its-progress
  ;; 13.2.28: only orders that reference the change; a deadline reschedules the rest.
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (machine (make-product :name "Maskin" :units-owned 99))
           (other (make-product :name "Annet" :units-owned 99))
           (rid (jget (aref (jget (call-ok "products_set_requirements" "admin:a" "product_id" machine
                                           "requirements" (jarr (list (req "article" cup 10 "per_quantity"))))
                                  "requirements") 0) "id"))
           (customer (make-customer))
           (referencing (loop repeat 3 collect (jget (new-order customer "event_date" "2026-06-20"
                                                                "lines" (jarr (list (line machine 1)))) "id")))
           (unrelated (jget (new-order customer "event_date" "2026-06-20" "lines" (jarr (list (line other 1)))) "id")))
      (catalog-pass "2026-03-01T09:00:10Z")
      (call-ok "recipes_create" "admin:a" "name" "Ingen bruker denne")
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 11
                                                "basis" "per_quantity"))))
      ;; Every order's unit of work runs out of time: nothing is lost, the rest waits.
      (flet ((impacts (o) (map 'list (lambda (i) (jget i "status"))
                               (jget (call-ok "plan_impacts_list" "viewer:v" "order_id" o) "items"))))
        (let ((before (mapcar #'impacts (cons unrelated referencing))))
          (let ((tun.core:*deadline-ms* -1000))
            (with-application (*app*)
              (with-actor ((system-actor "test"))
                (tun.workflows:run-due-workflows))))
          (is (equal before (mapcar #'impacts (cons unrelated referencing))) "no impact yet")
          (is (find "katalog_endring" (coerce (jget (call-ok "introspect_workflows" "admin:a" "status" "planlagt") "items") 'list)
                    :key (lambda (w) (jget w "kind")) :test #'equal)
              "the remaining work is planned for the next pass")
          (catalog-pass "2026-03-01T09:01:00Z")
          (is (equal (first before) (impacts unrelated))
              "an order that does not reference the change gets no impact")
          (loop for o in referencing
                for old in (rest before)
                do (is (equal (append old '("applied")) (impacts o)))))))))

(test quantities-and-lists-are-bounded
  ;; 13.2.29, 13.2.30
  (with-test-app ()
    (let* ((cup (make-article "Beger"))
           (machine (make-product :name "Maskin" :units-owned 99)))
      (is-error "invalid_input" nil (set-reqs machine (req "article" cup 1000000001 "per_line")))
      (is-error "invalid_input" nil (call "recipes_create" "admin:a" "name" "Stor"
                                          "lines" (jarr (list (jobj "article_id" cup "quantity" 1000000001)))))
      (set-reqs machine (req "article" cup 1000000000 "per_quantity"))
      (is-error "invalid_input" nil (call "orders_create" "employee:e" "customer_id" (make-customer)
                                          "lines" (jarr (list (line machine 1001)))))
      (let ((order (jget (new-order (make-customer) "lines" (jarr (list (line machine 1)))) "id")))
        (set-quantity order 2)
        (let ((page (call-ok "plans_list" "viewer:v" "order_id" order "limit" 1)))
          (is (equal '(1 t) (list (jget page "returned") (jget page "has_more")))))
        (is-error "invalid_input" nil (call "plans_list" "viewer:v" "order_id" order "limit" 101))))))

;;; ------------------------------------------------------------------
;;; Department transfers (catalog README §4, inventory README §11)

(test ownership-moves-only-through-audited-transfers
  (with-test-app (:class 'departments-app)
    (let* ((tent (make-article "Telt" "department" "nord" "opening_balance" 7))
           (article (call-ok "articles_get" "viewer:v" "id" tent)))
      (is (equal '("nord" 1) (list (jget article "department") (jget article "department_revision"))))
      (flet ((transfer (actor &rest args) (apply #'call "articles_transfer" actor "id" tent args)))
        (is-error "invalid_input" "Velg avdelingen lageret skal overføres til"
                  (transfer "admin:a" "note" "Flytting" "department_revision" 1))
        (is-error "invalid_input" "Velg en annen avdeling"
                  (transfer "admin:a" "department" "nord" "note" "Flytting" "department_revision" 1))
        (is-error "invalid_input" "Oppgi årsaken til overføringen"
                  (transfer "admin:a" "department" "sør" "note" "  " "department_revision" 1))
        (is-error "invalid_input" nil (transfer "admin:a" "department" "trondheim" "note" "x" "department_revision" 1))
        (is-error "conflict" nil (transfer "admin:a" "department" "sør" "note" "Flytting" "department_revision" 0))
        (is-error "conflict" nil (transfer "admin:a" "department" "sør" "note" "Flytting"))
        (is-error "forbidden" nil (transfer "employee:e" "department" "sør" "note" "Flytting" "department_revision" 1))
        (let ((moved (transfer "admin:a" "department" "sør" "note" "Til sør" "department_revision" 1)))
          (is (equal '("sør" 2 7 1) (list (jget moved "department") (jget moved "department_revision")
                                          (jget moved "balance") (jget moved "movement_revision")))
              "ownership moves, quantities never do"))
        (transfer "admin:a" "department" "nord" "note" "Tilbake" "department_revision" 2))
      (let ((records (coerce (jget (call-ok "transfers_list" "viewer:v" "target_type" "article" "target_id" tent) "items") 'list)))
        (is (equal '(("sør" "nord" "Tilbake" "admin:a") ("nord" "sør" "Til sør" "admin:a"))
                   (mapcar (lambda (r) (list (jget r "from_department") (jget r "to_department") (jget r "note") (jget r "by")))
                           records))
            "append-only, newest first"))
      (is-error "invalid_input" nil (call "articles_update" "admin:a" "id" tent "department" "sør"))
      (let ((product (call-ok "products_create" "employee:e" "name" "Telt" "kind" "utleie" "unit" "stk"
                              "unit_price_ore" 1000 "stock_tracked" nil "units_owned" 1)))
        (is-error "invalid_input" nil (call "products_update" "employee:e" "id" (jget product "id") "department" "nord"))
        (let ((moved (call-ok "products_transfer" "admin:a" "id" (jget product "id") "department" "nord"
                              "note" "Eies av nord" "department_revision" (jget product "department_revision"))))
          (is (equal '("nord" 2) (list (jget moved "department") (jget moved "department_revision")))))
        (is (equal '((:null "nord"))
                   (map 'list (lambda (r) (list (if (json-null-p (jget r "from_department")) :null (jget r "from_department"))
                                                (jget r "to_department")))
                        (jget (call-ok "transfers_list" "viewer:v" "target_type" "product" "target_id" (jget product "id"))
                              "items"))))))))

;;; ------------------------------------------------------------------
;;; The rollback preflight against an older core (core.md §6.4): the newer
;;; documents are counted by kind; a database the older core can take
;;; passes.  tests/fixtures/slice1-registry.json is the registry_describe of
;;; a client deployment on that older core (c9b02a4), named slice1 below.

(defun slice1-registry-path ()
  (merge-pathnames "tests/fixtures/slice1-registry.json" (asdf:system-source-directory "tun")))

(test the-preflight-refuses-slice-2-documents-for-the-slice-1-core
  (let ((compatible (scratch-path "s2-preflight-compatible"))
        (slice2 (scratch-path "s2-preflight-slice2")))
    ;; Customers, a service order without requirements (an empty plan), a
    ;; plain product: what the slice 1 core reads the same way.
    (with-test-app (:db compatible :class 'departments-app)
      (let ((service (make-product :name "Rørlegger" :kind "tjeneste")))
        (confirmed-order (make-customer) service "2026-06-20")))
    (let ((findings (tun.runtime::rollback-preflight 'application compatible (slice1-registry-path))))
      (is (= 1 (length findings)))
      (is (search "delivery:" (caar findings))))
    (with-test-app (:db slice2 :class 'zz-slice2-app)
      (let* ((cup (make-article "Beger" "opening_balance" 100 "department" "nord"))
             (syrup (make-article "Sirup" "opening_balance" 10))
             (r1 (jget (call-ok "recipes_create" "admin:a" "name" "Jordbær" "lines" (jarr (list (jobj "article_id" syrup "quantity" 1)))) "id"))
             (r2 (jget (call-ok "recipes_create" "admin:a" "name" "Blåbær" "lines" (jarr (list (jobj "article_id" syrup "quantity" 1)))) "id"))
             (group (jget (call-ok "choice_groups_create" "admin:a" "name" "Smaker" "members" (jarr (list r1 r2))) "id"))
             (machine (make-product :name "Maskin" :units-owned 9))
             (slush (make-product :name "Slush" :units-owned 9))
             (rid (jget (aref (jget (call-ok "products_set_requirements" "admin:a" "product_id" machine
                                             "requirements" (jarr (list (req "article" cup 10 "per_quantity"))))
                                    "requirements") 0) "id"))
             (gid (jget (aref (jget (call-ok "products_set_requirements" "admin:a" "product_id" slush
                                             "requirements" (jarr (list (req "choice_group" group 1 "per_serving" "picks" 2))))
                                    "requirements") 0) "id"))
             (customer (make-customer)))
        (confirmed-order customer machine "2026-06-20")
        (new-order customer "lines" (jarr (list (line slush 1 "choices" (jobj gid (jarr (list r1 r2)))))))
        (call-ok "clock_set" "admin:a" "now" "2026-03-01T09:00:10Z")
        (call-ok "products_set_requirements" "admin:a" "product_id" machine
                 "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 12
                                                  "basis" "per_quantity"))))
        (call-ok "clock_set" "admin:a" "now" "2026-03-01T09:01:00Z")
        (call-ok "articles_transfer" "admin:a" "id" cup "department" "sør" "note" "Flytt" "department_revision" 1)
        (call-ok "tasks_create" "admin:a" "department" "nord" "title" "Telle beger")))
    (let ((findings (tun.runtime::rollback-preflight 'application slice2 (slice1-registry-path))))
      (dolist (kind '("article: stock kept on an article" "plan: active plan with requirements"
                      "plan: proposed plan awaiting review" "review: pending review" "task: warehouse task"
                      "transfer: department transfer" "order.lines[].choices set"
                      "inventory_movement.kind = aapning"))
        (is (finding-count findings kind) "~a is counted: ~s" kind findings))
      (is (eql 2 (finding-count findings "article: ")) "both articles")
      (is (eql 1 (finding-count findings "order.lines[].choices set")) "the line with choices"))))
