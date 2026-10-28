;;;; tests/slice2-review-tests.lisp -- regressions in stock, requirements, plans
;;;; and catalog impact: each test guards a defect an independent review found.

(in-package #:tun.tests)

(def-suite slice2-review :in core)
(in-suite slice2-review)

;;; Exact decimals (core.md §2.1): a decimal written through a single-float
;;; would keep about seven significant digits in a SQLite store.
(test s2r-1-decimals-round-trip-exactly-through-the-store
  (let ((type (make-instance 'tun.core::decimal-type :scale 3)))
    (dolist (value (list 123456789/1000 (expt 10 12) 999999999999999/1000 20000001 -1/1000 7/2 0))
      (is (= value (tun.core::db->type type (tun.core::type->db type value))) "~a as text" value))
    (is (equal "123456.789" (tun.core::type->db type 123456789/1000)))
    (is (equal "1000000000000" (tun.core::type->db type (expt 10 12)))))
  ;; JSON delivers doubles: the decimal they were written as is what is kept.
  (is (= 999999999999999/1000 (tun.core::json-number->rational 999999999999.999d0)))
  (is (= 123456789/1000 (tun.core::json-number->rational 123456.789d0)))
  (let ((db (scratch-path "s2r-decimals")) a b c d order)
    (flet ((check (when)
             (is (= 123456.789d0 (balance-of a)) "~a: 123456.789" when)
             (is (= (expt 10 12) (balance-of b)) "~a: 10^12" when)
             (is (= 999999999999.998d0 (balance-of c)) "~a: counted to 999999999999.998" when)
             (is (equal '((1 "opening" 123456.789d0 123456.789d0)) (ledger-of a)) "~a: ~s" when (ledger-of a))
             (is (equal '((2 "recount" 999999999999.998d0 999999999999.998d0)
                          (1 "opening" 999999999999.999d0 999999999999.999d0))
                        (ledger-of c))
                 "~a: ~s" when (ledger-of c))
             (is (equal '((20000001 t)) (consumption-of d order)) "~a: the forbruk row" when)
             (is (= 9999999 (balance-of d)) "~a: the balance dropped by the row" when)))
      (with-test-app (:db db)
        (setf a (make-article "Sirup" "opening_balance" 123456.789d0)
              b (make-article "Vann" "unit" "ml" "opening_balance" (expt 10 12))
              c (make-article "Olje" "unit" "ml" "opening_balance" 999999999999.999d0)
              d (make-article "Tank" "unit" "ml" "opening_balance" 30000000))
        (call-ok "articles_recount" "admin:a" "article_id" c "quantity" 999999999999.998d0 "reason" "Telling")
        (let ((machine (make-product :name "Fyllmaskin" :units-owned 9)))
          (call-ok "products_set_requirements" "admin:a" "product_id" machine
                   "requirements" (jarr (list (req "article" d 20000001 "per_line"))))
          (setf order (confirmed-order (make-customer) machine "2026-06-01"))
          (is (= 20000001 (reserved-of d)) "the reservation")
          (call-ok "orders_complete" "employee:e" "id" order))
        (check "open"))
      (with-test-app (:db db)
        (check "reopened")))))

;;; The same defect in money texts: (/ ore 100) printed with ~,2f went
;;; through a single-float, so 200000.01 kr read 200000.00 in a quote.
(test s2r-1b-kroner-texts-are-exact
  (is (equal (list "200 000,01 kr" "1 234 567,89 kr" "0,05 kr" "−1,50 kr" "0,00 kr")
             (with-language ("nb")
               (mapcar (lambda (amount) (substitute #\Space #\No-break_space
                                                    (money-text amount :currency "NOK")))
                       '(20000001 123456789 5 -150 0)))))
  (with-test-app ()
    ;; A message's amounts are written as the tenant writes them.
    (call-ok "settings_set" "admin:a" "key" "locale.language" "value" "nb")
    (call-ok "settings_set" "admin:a" "key" "locale.currency" "value" "NOK")
    (let* ((product (jget (call-ok "products_create" "employee:anna" "name" "Telt" "kind" "rental" "unit" "stk"
                                   "unit_price_minor" 20000001 "stock_tracked" nil "units_owned" 2)
                          "id"))
           (order (jget (new-order (make-customer) "event_date" "2026-06-01" "lines" (jarr (list (line product 1))))
                        "id")))
      (advance-to-accepted order)
      (is (search "totalt 200 000,01 kr"
                  (substitute #\Space #\No-break_space
                              (jget (call-ok "orders_confirm" "employee:anna" "id" order) "summary"))))
      (let ((quote (find-by "template" "quote" (jget (call-ok "messages_list" "viewer:vera" "order_id" order) "items"))))
        (is (search "200 000,01 kr" (substitute #\Space #\No-break_space (jget quote "body")))
            "~s" (jget quote "body"))))))

;;; Finding 3: the transitions synced consumption at the revision before their
;;; save, the correction at the one after; so after a correction, cancel and
;;; reactivate sent the correction's revision and date again with another
;;; payload and got conflict (probe p1).
(test s2r-3-cancel-and-reactivate-after-a-correction-reverse-the-consumption
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (service (make-product :name "Servering" :kind "service" :units-owned 0))
           (customer (make-customer)))
      (call-ok "products_set_requirements" "admin:a" "product_id" service
               "requirements" (jarr (list (req "article" cup 10 "per_line"))))
      (flet ((corrected (date &optional reopen)
               ;; Consumed at ready_for_invoice (and REOPEN-ed), then corrected to 20.
               (let ((order (confirmed-order customer service date)))
                 (call-ok "orders_ready_for_invoice" "employee:e" "id" order)
                 (when reopen (two-step "orders_reopen" "admin:a" "id" order))
                 (call-ok "products_set_requirements" "admin:a" "product_id" service
                          "requirements" (jarr (list (req "article" cup 20 "per_line"))))
                 (multiple-value-bind (json code) (two-step "orders_correct_plan" "admin:a" "id" order "note" "Mer brukt")
                   (is (null code) "~a" (to-json-string json)))
                 (call-ok "products_set_requirements" "admin:a" "product_id" service
                          "requirements" (jarr (list (req "article" cup 10 "per_line"))))
                 order)))
        (let ((order (corrected "2026-06-01")))
          (is (equal '(((20 t)) 980) (list (consumption-of cup order) (balance-of cup))))
          (multiple-value-bind (json code) (two-step "orders_cancel" "employee:e" "id" order)
            (is (null code) "cancel after a correction: ~a" (to-json-string json)))
          (is (equal '(nil 1000) (list (consumption-of cup order) (balance-of cup))) "the correction is reversed"))
        (let ((order (corrected "2026-06-02" t)))
          (is (equal '(((20 t)) 980) (list (consumption-of cup order) (balance-of cup))))
          (multiple-value-bind (json code) (call "orders_reactivate" "employee:e" "id" order)
            (is (null code) "reactivate after a correction: ~a" (to-json-string json)))
          (is (equal '(nil 1000) (list (consumption-of cup order) (balance-of cup))))
          (is (equal "draft" (jget (call-ok "orders_get" "viewer:v" "id" order) "status"))))))))

;;; A neutral edit (orders README §9.1): comparing order-sensitive
;;; fingerprints would let swapping two lines activate a pending catalog proposal
;;; without its review.
(test s2r-5-reordering-lines-is-a-neutral-edit
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (lid (make-article "Lokk" "opening_balance" 1000))
           (one (make-product :name "Tjeneste 1" :kind "service" :units-owned 0))
           (two (make-product :name "Tjeneste 2" :kind "service" :units-owned 0))
           (rid (jget (aref (jget (set-reqs one (req "article" cup 10 "per_quantity")) "requirements") 0) "id"))
           (customer (make-customer)))
      (set-reqs two (req "article" lid 10 "per_quantity"))
      (let ((order (jget (new-order customer "event_date" "2026-06-20"
                                    "lines" (jarr (list (line one 1) (line two 1))))
                         "id")))
        (advance-to-accepted order)
        (two-step "orders_confirm" "employee:anna" "id" order)
        (catalog-pass "2026-03-01T09:00:10Z")
        (call-ok "products_set_requirements" "admin:a" "product_id" one
                 "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 50
                                                  "basis" "per_quantity"))))
        (catalog-pass "2026-03-01T09:01:00Z")
        (is (equal '(1 2 t nil nil) (plan-state-of order)))
        (let* ((o (call-ok "orders_get" "viewer:v" "id" order))
               (swapped (reverse (map 'list (lambda (l) (jobj "id" (jget l "id") "product_id" (jget l "product_id")
                                                              "quantity" (jget l "quantity")))
                                      (jget o "lines")))))
          (call-ok "orders_update" "employee:e" "id" order "revision" (jget o "revision") "lines" (jarr swapped)))
        (is (equal (list two one) (map 'list (lambda (l) (jget l "product_id"))
                                       (jget (call-ok "orders_get" "viewer:v" "id" order) "lines")))
            "the lines are swapped")
        (is (equal '(1 2 t nil nil) (plan-state-of order)) "the proposal and its review stay")
        (is (= 10 (reserved-of cup)) "the reservation is the active plan's")))))

;;; Finding 6: orders_create and orders_update computed their stock warnings
;;; inside the write transaction, asking every committed order (completed
;;; history included) for its demand once per article of the plan.
(defclass zz-demand-probe (application) ())
(defvar *demand-calls* '())
(defmethod tun.inventory:article-demand :before ((app zz-demand-probe) &key include-unconfirmed from)
  (push (list tun.core::*transaction-mode* include-unconfirmed from) *demand-calls*))

(test s2r-6-stock-warnings-ask-once-after-the-commit-and-skip-history
  (with-test-app (:class 'zz-demand-probe)
    (let* ((articles (loop for name in '("Beger" "Lokk" "Sugerør") collect (make-article name "opening_balance" 1)))
           (service (make-product :name "Servering" :kind "service" :units-owned 0))
           (customer (make-customer)))
      (call-ok "products_set_requirements" "admin:a" "product_id" service
               "requirements" (jarr (mapcar (lambda (a) (req "article" a 5 "per_line")) articles)))
      (flet ((shortages (json) (map 'list (lambda (w) (list (jget w "kind") (jget w "quantity"))) (jget json "stock_warnings"))))
        (setf *demand-calls* '())
        (let ((order (call-ok "orders_create" "employee:e" "customer_id" customer "event_date" "2026-06-01"
                              "request_key" "s2r-6" "lines" (jarr (list (line service 1))))))
          (is (equal '(("shortage" 4) ("shortage" 4) ("shortage" 4)) (shortages order)))
          (is (equal '((:read nil "2026-03-01")) *demand-calls*)
              "once, after the commit, from today: ~s" *demand-calls*)
          (setf *demand-calls* '())
          (let ((again (call-ok "orders_create" "employee:e" "customer_id" customer "event_date" "2026-06-01"
                                "request_key" "s2r-6" "lines" (jarr (list (line service 1))))))
            (is (equal (jget order "id") (jget again "id")) "the replay")
            (is (equal (shortages order) (shortages again)) "shows the warnings too"))
          (setf *demand-calls* '())
          (let ((updated (call-ok "orders_update" "employee:e" "id" (jget order "id") "revision" (jget order "revision")
                                  "tags" (jarr (list "rental")))))
            (is (equal (shortages order) (shortages updated)))
            (is (equal '((:read nil "2026-03-01")) *demand-calls*) "~s" *demand-calls*))
          (setf *demand-calls* '())
          (is (equal (shortages order) (shortages (call-ok "orders_get" "viewer:v" "id" (jget order "id")))))
          (is (= 1 (length *demand-calls*))))))))

;;; A recount wins (inventory README §6.4), across a second correction too: the
;;; row the first correction wrote (balance_updated false) comes after the
;;; recount, and the next sync must not deduct again.
(test s2r-7-recount-wins-carries-forward
  (with-test-app ()
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (service (make-product :name "Servering" :kind "service" :units-owned 0))
           (order (progn (call-ok "products_set_requirements" "admin:a" "product_id" service
                                  "requirements" (jarr (list (req "article" cup 30 "per_line"))))
                         (confirmed-order (make-customer) service "2026-06-01"))))
      (flet ((correct (quantity)
               (call-ok "products_set_requirements" "admin:a" "product_id" service
                        "requirements" (jarr (list (req "article" cup quantity "per_line"))))
               (multiple-value-bind (json code) (two-step "orders_correct_plan" "admin:a" "id" order "note" "Telt")
                 (is (null code) "~a" (to-json-string json)))
               (list (consumption-of cup order) (balance-of cup))))
        (call-ok "orders_ready_for_invoice" "employee:e" "id" order)
        (is (equal '(((30 t)) 970) (list (consumption-of cup order) (balance-of cup))))
        (call-ok "articles_recount" "admin:a" "article_id" cup "quantity" 500 "reason" "Telling")
        (is (equal '(((60 nil)) 500) (correct 60)) "the recount counted the use")
        (is (equal '(((90 nil)) 500) (correct 90)) "a second correction does not deduct either")
        (call-ok "inventory_receive" "employee:e" "article_id" cup "quantity" 10)
        (is (equal '(((120 t)) 390) (correct 120)) "after a receipt newer than the recount it deducts again")
        (two-step "orders_cancel" "employee:e" "id" order)
        (is (equal '(nil 510) (list (consumption-of cup order) (balance-of cup))) "and a cancel restores that")))))

;;; Catalog impact (orders README §11): katalog_endring reads each order's
;;; status again when it reaches it, and an order that runs out of time
;;; does not come first again in every pass.
(defun impacts-of (order change)
  (map 'list (lambda (i) (list (jget i "status") (jget i "detail")))
       (remove change (coerce (jget (call-ok "plan_impacts_list" "viewer:v" "order_id" order) "items") 'list)
               :key (lambda (i) (jget i "catalog_change_id")) :test-not #'equal)))

(defun last-change-id ()
  (jget (aref (jget (call-ok "catalog_changes_list" "viewer:v" "limit" 1) "items") 0) "id"))

(defmacro with-decide-plan-wrapped ((order-var) before-form &body body)
  "Run BODY with DECIDE-PLAN running BEFORE-FORM (ORDER-VAR bound) first."
  (let ((f (gensym)) (args (gensym)))
    `(progn
       (sb-ext:without-package-locks
         (sb-int:encapsulate 'tun.orders::decide-plan 'zz-review
                             (lambda (,f ,order-var &rest ,args)
                               ,before-form
                               (apply ,f ,order-var ,args))))
       (unwind-protect (progn ,@body)
         (sb-ext:without-package-locks
           (sb-int:unencapsulate 'tun.orders::decide-plan 'zz-review))))))

(test s2r-9-an-order-closed-before-its-turn-gets-impact-unchanged
  (with-test-app (:debug-tools t)
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (machine (make-product :name "Maskin" :units-owned 9))
           (rid (jget (aref (jget (set-reqs machine (req "article" cup 10 "per_quantity")) "requirements") 0) "id"))
           (customer (make-customer))
           (cancelled (confirmed-order customer machine "2026-06-20"))
           (completed (confirmed-order customer machine "2026-06-21"))
           (first-order (confirmed-order customer machine "2026-06-22"))
           (mid-run (confirmed-order customer machine "2026-06-23")))
      (catalog-pass "2026-03-01T09:00:10Z")
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 11
                                                "basis" "per_quantity"))))
      (let ((change (last-change-id)))
        ;; Closed after the change, before the run.
        (two-step "orders_cancel" "employee:e" "id" cancelled)
        (call-ok "orders_complete" "employee:e" "id" completed)
        ;; Cancelled while the run is under way: at another order's turn.
        (with-decide-plan-wrapped (order)
            (when (equal (entity-id order) first-order)
              (let ((other (fetch 'tun.orders:order mid-run)))
                (setf (tun.orders:order-status other) "cancelled")
                (save other)))
          (catalog-pass "2026-03-01T09:01:00Z"))
        (let ((unchanged '(("unchanged" "The requirement plan was already up to date"))))
          (is (equal unchanged (impacts-of cancelled change)) "cancelled before the run")
          (is (equal unchanged (impacts-of completed change)) "completed before the run")
          (is (equal unchanged (impacts-of mid-run change)) "cancelled during the run"))
        (is (equal '(("proposed" "A proposal was made for review")) (impacts-of first-order change)))
        (dolist (o (list cancelled completed mid-run))
          (is (equal '(1 :null nil) (subseq (plan-state-of o) 0 3)) "no proposal, no review"))))))

(defun pass-at (time deadline-ms)
  "Move the test clock to TIME and run the due workflows with DEADLINE-MS (the
scheduler's way; clock_set would answer past its own deadline)."
  (with-application (*app*)
    (tun.core::set-test-clock (application-clock *app*) (tun.core::parse-rfc3339 time))
    (let ((tun.core:*deadline-ms* deadline-ms))
      (with-actor ((system-actor "test"))
        (tun.workflows:run-due-workflows)))))

(test s2r-10-an-order-out-of-time-three-times-fails-and-the-others-go-on
  (with-test-app (:debug-tools t)
    (let* ((cup (make-article "Beger" "opening_balance" 1000))
           (machine (make-product :name "Maskin" :units-owned 9))
           (rid (jget (aref (jget (set-reqs machine (req "article" cup 10 "per_quantity")) "requirements") 0) "id"))
           (customer (make-customer))
           (slow (jget (new-order customer "event_date" "2026-06-20" "lines" (jarr (list (line machine 1)))) "id"))
           (others (loop for d in '("2026-06-21" "2026-06-22")
                         collect (jget (new-order customer "event_date" d "lines" (jarr (list (line machine 1)))) "id"))))
      (catalog-pass "2026-03-01T09:00:10Z")
      (call-ok "products_set_requirements" "admin:a" "product_id" machine
               "requirements" (jarr (list (jobj "id" rid "target" (jobj "kind" "article" "id" cup) "quantity" 11
                                                "basis" "per_quantity"))))
      (let ((change (last-change-id)))
        (flet ((planned () (count "catalog_change" (jget (call-ok "introspect_workflows" "admin:a" "status" "planned") "items")
                                  :key (lambda (w) (jget w "kind")) :test #'equal)))
          (with-decide-plan-wrapped (order)
              (when (equal (entity-id order) slow) (sleep-with-deadline 5000))
            (pass-at "2026-03-01T09:01:00Z" 300)
            (pass-at "2026-03-01T09:02:00Z" 300)
            (is (equal '(("applied" "A new requirement plan was activated automatically") ("applied" "A new requirement plan was activated automatically"))
                       (mapcan (lambda (o) (impacts-of o change)) others))
                "the others are not held up by the slow one")
            (is (null (impacts-of slow change)) "two deadlines: tried again")
            (is (= 1 (planned)))
            (pass-at "2026-03-01T09:03:00Z" 300))
          (let ((impacts (impacts-of slow change)))
            (is (equal "failed" (first (first impacts))) "the third deadline fails it: ~s" impacts)
            (is (eql 0 (search "The impact could not be computed; see request req_" (second (first impacts))))))
          (is (= 0 (planned)) "and the run is over")
          (is (= 10 (jget (aref (jget (call-ok "orders_get" "viewer:v" "id" slow) "requirements") 0) "quantity"))
              "the failed order keeps its plan"))))))

;;; Finding 11: picks from an archived choice group passed (only the recipe's
;;; flag was checked), and an archived article was accepted as a new
;;; requirement target (probe p4).
(test s2r-11-archived-groups-and-targets-are-refused
  (with-test-app ()
    (let* ((syrup (make-article "Sirup" "opening_balance" 100))
           (old (make-article "Gammel" "opening_balance" 100))
           (r1 (jget (call-ok "recipes_create" "admin:a" "name" "Jordbær" "lines" (jarr (list (jobj "article_id" syrup "quantity" 1)))) "id"))
           (r2 (jget (call-ok "recipes_create" "admin:a" "name" "Cola" "lines" (jarr (list (jobj "article_id" syrup "quantity" 1)))) "id"))
           (group (jget (call-ok "choice_groups_create" "admin:a" "name" "Smaker" "members" (jarr (list r1 r2))) "id"))
           (slush (make-product :name "Slush" :units-owned 9))
           (gid (jget (aref (jget (set-reqs slush (req "choice_group" group 1 "per_serving" "picks" 2 "name" "Smaker"))
                                  "requirements") 0) "id"))
           (customer (make-customer)))
      (call-ok "choice_groups_archive" "admin:a" "id" group)
      (multiple-value-bind (json code)
          (call "orders_create" "employee:e" "customer_id" customer
                "lines" (jarr (list (line slush 1 "choices" (jobj gid (jarr (list r1 r2)))))))
        (is (equal "invalid_input" code))
        (is (equal "Smaker holds choices that are not valid" (jget (jget json "error") "message"))))
      (call-ok "articles_archive" "admin:a" "id" old)
      (let ((machine (make-product :name "Maskin" :units-owned 9)))
        (multiple-value-bind (json code) (set-reqs machine (req "article" old 1 "per_line"))
          (is (equal "invalid_input" code))
          (is (equal "The stock article is archived" (jget (jget json "error") "message"))))
        (is-error "invalid_input" nil (set-reqs machine (req "choice_group" group 1 "per_serving" "picks" 2)))
        (call-ok "recipes_archive" "admin:a" "id" r2)
        (is-error "invalid_input" nil (set-reqs machine (req "recipe" r2 1 "per_line"))))
      ;; A requirement that already targets what was archived since stays editable.
      (let* ((kept (make-product :name "Beholdt" :units-owned 9))
             (rid (progn (call-ok "articles_create" "admin:a" "name" "Ny" "unit" "stk")
                         (jget (aref (jget (set-reqs kept (req "article" syrup 1 "per_line")) "requirements") 0) "id"))))
        (call-ok "articles_archive" "admin:a" "id" syrup)
        (multiple-value-bind (json code)
            (set-reqs kept (jobj "id" rid "target" (jobj "kind" "article" "id" syrup) "quantity" 2 "basis" "per_line"))
          (is (null code) "~a" (to-json-string json)))))))

;;; Finding 12 (platform 2.3, 2.5): orders selected inventory's ledger table
;;; directly; the boundary check allowed every exported symbol of a
;;; dependency, so it missed that the entity is not published.
(test s2r-12-a-module-names-another-modules-table-only-when-it-is-published
  (flet ((check (text)
           (public-interface-violations text :package "TUN.ORDERS"
                                             :public-packages (append +kernel-public-packages+ '("TUN.INVENTORY" "TUN.CATALOG"))
                                             :module-packages '("TUN.INVENTORY" "TUN.CATALOG"))))
    (is (check "(select 'tun.inventory:inventory-movement :where '(:= \"kind\" \"mottak\"))"))
    (is (check "(fetch 'tun.inventory:reservation \"res_1\")"))
    (is (null (check "(fetch 'tun.inventory:article \"art_1\")")) "a published entity")
    (is (null (check "(tun.inventory:received-since-p \"art_1\" 0)")) "a function of the module")
    (is (null (check "(make-instance 'tun.catalog:product-requirement)")) "an embedded entity has no table"))
  (is (null (module-violations "orders")) "~s" (module-violations "orders")))

;;; Finding 13: the rollback preflight counted articles only; a product
;;; relinked onto another product's adopted article, or unlinked, reads its
;;; stock differently in the older core and was not counted.
(test s2r-13-the-preflight-counts-relinked-and-unlinked-products
  (let ((db (scratch-path "s2r-relink")) cups lids)
    (with-test-app (:db db)
      (flet ((tracked (name)
               (jget (call-ok "products_create" "employee:e" "name" name "kind" "consumable" "unit" "stk"
                              "unit_price_minor" 500 "stock_tracked" t) "id")))
        (setf cups (tracked "Beger") lids (tracked "Lokk")))
      ;; As an older core left it: stock levels, no articles.
      (with-application (*app*)
        (with-transaction (:write)
          (tun.store.sqlite::exec "DELETE FROM articles")
          (tun.store.sqlite::exec "UPDATE products SET article_id = NULL")
          (dolist (p (list cups lids))
            (tun.store.sqlite::exec "INSERT INTO stock_levels (id, product_id, on_hand, revision) VALUES (?, ?, 10, 0)"
                                    p p)))))
    (with-test-app (:db db) (call-ok "products_get" "viewer:v" "id" cups))
    (is (null (preflight-findings db)) "adopted and untouched: ~s" (preflight-findings db))
    (with-test-app (:db db)
      (let ((cup-article (jget (call-ok "products_get" "viewer:v" "id" cups) "article_id")))
        (call-ok "products_update" "admin:a" "id" lids "article_id" cup-article)))
    (let ((findings (preflight-findings db)))
      (is (eql 1 (finding-count findings "product: ")) "the relinked product: ~s" findings))
    (with-test-app (:db db)
      (call-ok "products_update" "admin:a" "id" cups "article_id" :null))
    (let ((findings (preflight-findings db)))
      (is (= 2 (reduce #'+ (remove-if-not (lambda (f) (eql 0 (search "product: " (car f)))) findings) :key #'cdr))
          "and the unlinked one: ~s" findings))
    ;; A core that has articles reads the links the same way: rolling one
    ;; module back between such revisions counts no product.
    (let ((registry (scratch-path "s2r-relink-registry")))
      (with-test-app (:db db)
        (with-open-file (out registry :direction :output :if-exists :supersede :external-format :utf-8)
          (write-string (to-json-string (call-ok "registry_describe" "viewer:v")) out)))
      (let ((findings (tun.runtime::rollback-preflight 'application db registry)))
        (is (null (finding-count findings "product: ")) "~s" findings)))))

;;; ------------------------------------------------------------------
;;; Slice 2 13.2.36 (amended) to 13.2.39, added to the review round.

(test s2r-36-a-balance-above-10^12-is-refused
  (with-test-app ()
    (let ((full (make-article "Full" "opening_balance" (expt 10 12)))
          (almost (make-article "Nesten" "opening_balance" 999999999999.999d0)))
      (is-error "invalid_input" nil (call "articles_create" "admin:a" "name" "For mye" "unit" "stk"
                                          "opening_balance" (1+ (expt 10 12))))
      (multiple-value-bind (json code) (call "inventory_receive" "employee:e" "article_id" full "quantity" 1)
        (is (equal "invalid_input" code))
        (is (equal "The balance can be at most 1000000000000" (jget (jget json "error") "message"))))
      (is-error "invalid_input" nil (call "inventory_adjust" "admin:a" "article_id" almost "delta" 1 "reason" "x"))
      (is-error "invalid_input" nil (call "articles_recount" "admin:a" "article_id" almost
                                          "quantity" 1000000000000.001d0 "reason" "Telling"))
      (is (equal (list (expt 10 12) 999999999999.999d0) (list (balance-of full) (balance-of almost))) "unchanged")
      (call-ok "inventory_adjust" "admin:a" "article_id" full "delta" -1 "reason" "Svinn")
      (call-ok "inventory_receive" "employee:e" "article_id" full "quantity" 1)
      (is (= (expt 10 12) (balance-of full)) "up to the bound is fine"))))

(test s2r-37-order-dates-are-bounded-at-create-and-update
  (with-test-app ()
    (let* ((machine (make-product :name "Maskin" :units-owned 9))
           (customer (make-customer)))
      (flet ((create (&rest dates)
               (apply #'call "orders_create" "employee:e" "customer_id" customer
                      "lines" (jarr (list (line machine 1))) dates)))
        (dolist (dates '(("event_date" "1969-12-31") ("event_date" "3000-01-01")
                         ("event_date" "2026-06-01" "end_date" "3000-01-01")
                         ("event_date" "2026-06-01" "end_date" "2028-06-02")))
          (multiple-value-bind (json code) (apply #'create dates)
            (is (equal "invalid_input" code) "~s: ~a" dates (to-json-string json))))
        (is (null (nth-value 1 (create "event_date" "2026-06-01" "end_date" "2028-06-01"))) "731 days")
        (is (null (nth-value 1 (create "event_date" "1970-01-01"))))
        (is (null (nth-value 1 (create "event_date" "2999-12-31"))))
        (let ((order (jget (create "event_date" "2026-06-01") "id")))
          (two-step "orders_confirm" "employee:anna" "id" (progn (advance-to-accepted order) order))
          (dolist (dates '(("event_date" "9999-12-31") ("end_date" "2028-06-02") ("event_date" "1900-01-01")))
            (let ((o (call-ok "orders_get" "viewer:v" "id" order)))
              (multiple-value-bind (json code) (apply #'call "orders_update" "employee:e" "id" order
                                                      "revision" (jget o "revision") dates)
                (is (equal "invalid_input" code) "update ~s: ~a" dates (to-json-string json))))))))))

(test s2r-38-stock-warnings-need-no-per-day-series
  (with-test-app (:debug-tools t)
    (let* ((cup (make-article "Beger" "opening_balance" 10))
           (service (make-product :name "Servering" :kind "service" :units-owned 0))
           (customer (make-customer))
           (calls 0))
      (set-reqs service (req "article" cup 6 "per_line"))
      (sb-ext:without-package-locks
        (sb-int:encapsulate 'tun.inventory:forecast 'zz-count
                            (lambda (f &rest args) (incf calls) (apply f args))))
      (unwind-protect
           (flet ((order (date) (call-ok "orders_create" "employee:e" "customer_id" customer "event_date" date
                                         "lines" (jarr (list (line service 1))))))
             (confirmed-order customer service "2026-06-01")
             (is (equalp #() (jget (order "2026-05-31") "stock_warnings")) "before the committed demand: 10 - 6")
             (is (equal '(("shortage" 2)) (map 'list (lambda (w) (list (jget w "kind") (jget w "quantity")))
                                                (jget (order "2999-06-01") "stock_warnings")))
                 "10 - 6 committed - 6 own")
             (is (= 0 calls) "no forecast, so no day-by-day series up to 2999"))
        (sb-ext:without-package-locks (sb-int:unencapsulate 'tun.inventory:forecast 'zz-count))))))

(test s2r-39-serve-fails-loudly-when-the-port-is-taken
  (with-test-app ()
    (let* ((holder (usocket:socket-listen "127.0.0.1" 0 :reuse-address nil))
           (port (usocket:get-local-port holder))
           (*error-output* (make-string-output-stream)))
      (unwind-protect
           (let ((code (catch 'exited
                         (tun.runtime::start-listening *app* :port port :address "127.0.0.1" :max-inflight 4
                                                             :exit (lambda (code) (throw 'exited code)))
                         :returned)))
             (is (eql 1 code) "exits non-zero instead of serving")
             (let ((said (get-output-stream-string *error-output*)))
               (is (search (format nil "cannot listen on 127.0.0.1:~d" port) said) "~a" said)
               (is (not (search "listening" said)))))
        (usocket:socket-close holder)))))
