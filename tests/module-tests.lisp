;;;; tests/module-tests.lisp -- phase 4: the business modules with core
;;;; alone (no client): customers, catalog, inventory, orders, availability,
;;;; invoicing + accounting port, messages and the workflow engine.

(in-package #:tun.tests)

(def-suite modules :in core)
(in-suite modules)

(defun make-product (&rest args &key (name "Maskin") (kind "rental") (unit "stk") (price 150000)
                                     (stock-tracked nil) (units-owned 2) &allow-other-keys)
  (declare (ignore args))
  (jget (call-ok "products_create" "employee:anna" "name" name "kind" kind "unit" unit
                 "unit_price_minor" price "stock_tracked" stock-tracked "units_owned" units-owned)
        "id"))

(defun make-customer (&optional (name "Ola Nordmann"))
  (jget (call-ok "customers_create" "employee:anna" "name" name
                 "email" (format nil "~a@example.no" (string-downcase (remove #\Space name))))
        "id"))

(defun lines (&rest specs)
  "Order lines from (product-id quantity) pairs."
  (jarr (loop for (product quantity) on specs by #'cddr
              collect (jobj "product_id" product "quantity" quantity))))

(defun two-step (tool actor &rest args)
  "Call a confirm tool twice (request, then with the token)."
  (multiple-value-bind (first code) (apply #'call tool actor args)
    (if code
        (values first code)
        (apply #'call tool actor "confirmation_token" (jget first "confirmation_token") args))))

(defun advance-to-accepted (order-id)
  (call-ok "orders_send_quote" "employee:anna" "id" order-id)
  (call-ok "orders_accept" "employee:anna" "id" order-id))

(test order-pricing-and-validation
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product))
           (order (call-ok "orders_create" "employee:anna" "customer_id" customer
                           "lines" (lines machine 2))))
      (is (string= "draft" (jget order "status")))
      (is (equal '(300000 0 300000) (list (jget order "subtotal_minor") (jget order "discount_minor")
                                          (jget order "total_minor")))
          "core gives no discount")
      (is (equalp #() (jget order "requirements")) "core derives no requirements")
      (is (equalp #() (jget order "bookings")))
      (let ((line (aref (jget order "lines") 0)))
        (is (string-prefix-p "lin_" (jget line "id")))
        (is (= 150000 (jget line "unit_price_minor")))
        (is (= 300000 (jget line "line_total_minor"))))
      (is (null (jget order "servings")) "servings is a client field, absent in core")
      (is (string= "not_found" (nth-value 1 (call "orders_create" "employee:anna" "customer_id" "cus_x"
                                                  "lines" (lines machine 1)))))
      (is (string= "not_found" (nth-value 1 (call "orders_create" "employee:anna" "customer_id" customer
                                                  "lines" (lines "prd_x" 1)))))
      (is (string= "invalid_input" (nth-value 1 (call "orders_create" "employee:anna" "customer_id" customer
                                                      "lines" (jarr '())))))
      (is (string= "invalid_input" (nth-value 1 (call "orders_create" "employee:anna" "customer_id" customer
                                                      "lines" (lines machine 0)))))
      (is (= 1 (jget (call-ok "orders_list" "viewer:vera" "customer_id" customer) "returned"))))))

(test order-status-machine-bookings-and-availability
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 2))
           (a (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
                             "lines" (lines machine 1))
                    "id")))
      (is (string= "invalid_transition" (nth-value 1 (call "orders_accept" "employee:anna" "id" a))))
      (call-ok "orders_send_quote" "employee:anna" "id" a)
      (let ((msgs (coerce (jget (call-ok "messages_list" "viewer:vera" "order_id" a) "items") 'list)))
        (is (= 1 (length msgs)))
        (is (string= "quote" (jget (first msgs) "template")) "core default template")
        (is (string= "sent" (jget (first msgs) "status"))))
      (is (equalp #() (jget (call-ok "workflows_list" "viewer:vera" "order_id" a) "items"))
          "core schedules no workflows of its own")
      (call-ok "orders_accept" "employee:anna" "id" a)
      (let ((confirmed (two-step "orders_confirm" "employee:anna" "id" a)))
        (is (string= "confirmed" (jget confirmed "status")))
        (is (equalp (list "2026-06-20" "2026-06-20")
                    (let ((b (aref (jget confirmed "bookings") 0))) (list (jget b "from") (jget b "to"))))
            "core books the event date only"))
      (let ((av (call-ok "availability_check" "viewer:vera" "product_id" machine "date" "2026-06-20" "quantity" 2)))
        (is (equal '(2 1 1 nil) (list (jget av "units_owned") (jget av "blocked") (jget av "available") (jget av "ok"))))
        (is (string= a (jget (aref (jget av "conflicts") 0) "order_id"))))
      (is (eq t (jget (call-ok "availability_check" "viewer:vera" "product_id" machine "date" "2026-06-21"
                               "quantity" 2)
                      "ok")))
      ;; A second order needing both units on the same day is unavailable.
      (let ((b (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
                              "lines" (lines machine 2))
                     "id")))
        (advance-to-accepted b)
        (is (string= "unavailable" (nth-value 1 (two-step "orders_confirm" "employee:anna" "id" b))))
        (is (string= "accepted" (jget (call-ok "orders_get" "viewer:vera" "id" b) "status"))))
      ;; Confirming needs an event date.
      (let ((c (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "lines" (lines machine 1)) "id")))
        (advance-to-accepted c)
        (is (string= "invalid_input" (nth-value 1 (two-step "orders_confirm" "employee:anna" "id" c)))))
      ;; Stale revision, then completion, then no more changes.
      (let ((rev (jget (call-ok "orders_get" "viewer:vera" "id" a) "revision")))
        (is (string= "conflict" (nth-value 1 (call "orders_update" "employee:anna" "id" a "revision" (1- rev)
                                                   "delivery_address" "Ny vei 1"))))
        (is (string= "Ny vei 1" (jget (call-ok "orders_update" "employee:anna" "id" a "revision" rev
                                               "delivery_address" "Ny vei 1")
                                      "delivery_address"))))
      (call-ok "orders_complete" "employee:anna" "id" a)
      (is (= 1 (jget (call-ok "customers_get" "viewer:vera" "id" customer) "completed_orders")))
      (is (string= "invalid_transition" (nth-value 1 (call "orders_complete" "employee:anna" "id" a))))
      (is (string= "invalid_transition"
                   (nth-value 1 (call "orders_update" "employee:anna" "id" a
                                      "revision" (jget (call-ok "orders_get" "viewer:vera" "id" a) "revision")
                                      "delivery_address" "x")))))))

(test cancel-releases-bookings
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 1))
           (a (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-07-01"
                             "lines" (lines machine 1))
                    "id")))
      (advance-to-accepted a)
      (two-step "orders_confirm" "employee:anna" "id" a)
      (is (= 1 (jget (call-ok "availability_check" "viewer:vera" "product_id" machine "date" "2026-07-01") "blocked")))
      (let ((first (call-ok "orders_cancel" "employee:anna" "id" a)))
        (is (eq t (jget first "confirmation_required")))
        (is (string= "confirmed" (jget (call-ok "orders_get" "viewer:vera" "id" a) "status"))))
      (is (string= "cancelled" (jget (two-step "orders_cancel" "employee:anna" "id" a) "status")))
      (is (= 0 (jget (call-ok "availability_check" "viewer:vera" "product_id" machine "date" "2026-07-01") "blocked")))
      (is (string= "invalid_transition" (nth-value 1 (two-step "orders_cancel" "employee:anna" "id" a)))))))

;;; The domain protocols, specialized by a test application (as a client would).

(defclass consumables-app (application) ()
  (:documentation "Test deployment: forbruk lines are requirements; 10 % discount."))

(defmethod tun.orders:compute-order-requirements ((app consumables-app) order)
  (append (call-next-method)
          (loop for line in (tun.orders:order-lines order)
                for product = (tun.catalog:find-product (tun.orders:order-line-product-id line))
                when (tun.catalog:stock-tracked-consumable-p product)
                  collect (cons (entity-id product) (tun.orders:order-line-quantity line)))))

(defmethod tun.orders:order-discount ((app consumables-app) order customer)
  (declare (ignore customer))
  (floor (tun.orders:order-subtotal-minor order) 10))

(test protocols-reservations-and-consumption
  (with-test-app (:class 'consumables-app)
    (let* ((customer (make-customer))
           (cups (make-product :name "Begre" :kind "consumable" :price 100 :stock-tracked t :units-owned 0))
           (order (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
                           "lines" (lines cups 5 cups 3)))
           (id (jget order "id")))
      (is (= 80 (jget order "discount_minor")) "the application's discount method applied")
      (is (equal (list (list cups 8)) (map 'list (lambda (r) (list (jget r "product_id") (jget r "quantity")))
                                           (jget order "requirements")))
          "duplicate requirements are summed")
      (call-ok "inventory_receive" "employee:anna" "product_id" cups "quantity" 6)
      (advance-to-accepted id)
      (is (= 0 (jget (call-ok "inventory_balance" "viewer:vera" "product_id" cups) "reserved"))
          "nothing is reserved before confirmation")
      (two-step "orders_confirm" "employee:anna" "id" id)
      (let ((bal (call-ok "inventory_balance" "viewer:vera" "product_id" cups)))
        (is (equal '(6 8 -2) (list (jget bal "on_hand") (jget bal "reserved") (jget bal "available")))))
      (let ((short (aref (jget (call-ok "inventory_shortages" "viewer:vera" "before_date" "2026-06-30") "items") 0)))
        (is (equal (list cups 8 6 2) (list (jget short "product_id") (jget short "needed") (jget short "on_hand")
                                           (jget short "shortfall")))))
      (is (equalp #() (jget (call-ok "inventory_shortages" "viewer:vera" "before_date" "2026-06-19") "items")))
      ;; Completion with too little stock aborts everything.
      (is (string= "insufficient_stock" (nth-value 1 (call "orders_complete" "employee:anna" "id" id))))
      (is (string= "confirmed" (jget (call-ok "orders_get" "viewer:vera" "id" id) "status")))
      (is (= 0 (jget (call-ok "customers_get" "viewer:vera" "id" customer) "completed_orders")))
      (is (= 6 (jget (call-ok "inventory_balance" "viewer:vera" "product_id" cups) "on_hand")))
      (call-ok "inventory_receive" "employee:anna" "product_id" cups "quantity" 2)
      (call-ok "orders_complete" "employee:anna" "id" id)
      (let ((bal (call-ok "inventory_balance" "viewer:vera" "product_id" cups))
            (newest (aref (jget (call-ok "inventory_movements" "viewer:vera" "product_id" cups) "items") 0)))
        (is (equal '(0 0 0) (list (jget bal "on_hand") (jget bal "reserved") (jget bal "available"))))
        (is (equal (list "consumption" 8 0 id) (list (jget newest "kind") (jget newest "quantity")
                                                 (jget newest "balance_after") (jget newest "order_id"))))))))

(test inventory-operations
  (with-test-app ()
    (let ((cups (make-product :name "Begre" :kind "consumable" :price 100 :stock-tracked t :units-owned 0))
          (machine (make-product)))
      (let ((m (call-ok "inventory_receive" "employee:anna" "product_id" cups "quantity" 10 "reason" "levering")))
        (is (equal (list "receipt" 10 10 1 cups "levering")
                   (list (jget m "kind") (jget m "quantity") (jget m "balance_after") (jget m "revision")
                         (jget m "product_id") (jget m "reason")))))
      (is (string= "invalid_input" (nth-value 1 (call "inventory_receive" "employee:anna" "product_id" machine
                                                      "quantity" 1)))
          "only stock-tracked products have a ledger")
      (is (string= "invalid_input" (nth-value 1 (call "inventory_receive" "employee:anna" "product_id" cups
                                                      "quantity" 0))))
      (is (string= "forbidden" (nth-value 1 (call "inventory_adjust" "employee:anna" "product_id" cups
                                                  "delta" -1 "reason" "x"))))
      (is (string= "invalid_input" (nth-value 1 (call "inventory_adjust" "admin:ada" "product_id" cups
                                                      "delta" 0 "reason" "x"))))
      (is (string= "insufficient_stock" (nth-value 1 (call "inventory_adjust" "admin:ada" "product_id" cups
                                                           "delta" -11 "reason" "svinn"))))
      (is (= -3 (jget (call-ok "inventory_adjust" "admin:ada" "product_id" cups "delta" -3 "reason" "svinn")
                      "quantity")))
      (is (equal '(2 1) (map 'list (lambda (m) (jget m "revision"))
                             (jget (call-ok "inventory_movements" "viewer:vera" "product_id" cups) "items")))))))

(test invoicing-and-the-accounting-port
  (with-test-app ()
    (let* ((customer (make-customer "Kari Faktura"))
           (machine (make-product))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
                                 "lines" (lines machine 1))
                        "id")))
      (is (string= "invalid_transition" (nth-value 1 (call "invoices_create_from_order" "employee:anna"
                                                           "order_id" order))))
      (advance-to-accepted order)
      (two-step "orders_confirm" "employee:anna" "id" order)
      (let* ((invoice (call-ok "invoices_create_from_order" "employee:anna" "order_id" order))
             (id (jget invoice "id")))
        (is (equal (list "draft" order 150000) (list (jget invoice "status") (jget invoice "order_id")
                                                      (jget invoice "total_minor"))))
        (is (string= "Kari Faktura" (jget (jget invoice "customer") "name")))
        (is (string= "Maskin" (jget (aref (jget invoice "lines") 0) "description")))
        (is (string= "conflict" (nth-value 1 (call "invoices_create_from_order" "employee:anna" "order_id" order))))
        ;; The invoice is a copy: later order changes do not alter it.
        (call-ok "orders_update" "employee:anna" "id" order
                 "revision" (jget (call-ok "orders_get" "viewer:vera" "id" order) "revision")
                 "lines" (lines machine 2))
        (is (= 150000 (jget (call-ok "invoices_get" "viewer:vera" "id" id) "total_minor")))
        (is (string= "forbidden" (nth-value 1 (call "invoices_send" "employee:anna" "id" id))))
        (let ((sent (two-step "invoices_send" "admin:ada" "id" id)))
          (is (string= "sent" (jget sent "status")))
          (is (string-prefix-p "FAKE-" (jget sent "external_ref")))
          (is (string= "2026-03-01T09:00:00Z" (jget sent "sent_at")))
          (is (string= "invalid_transition" (nth-value 1 (two-step "invoices_send" "admin:ada" "id" id))))
          (let ((status (call-ok "accounting_status" "admin:ada")))
            (is (string= "fake" (jget status "adapter")))
            (is (equal (list id (jget sent "external_ref") 1)
                       (let ((e (find-by "invoice_id" id (jget status "invoices"))))
                         (list (jget e "invoice_id") (jget e "external_ref") (jget e "calls")))))))
        (is (find-by "template" "invoice" (jget (call-ok "messages_list" "viewer:vera" "order_id" order) "items")))
        (is (= 1 (jget (call-ok "invoices_list" "viewer:vera" "status" "sent") "returned")))))))

;;; Workflow engine, with workflow kinds defined here (as a client would).

(defvar *pings* 0)

(define-workflow test-ping (:kind "test_ping" :label "Test") (wf)
  (declare (ignore wf))
  (incf *pings*))

(define-workflow test-chain (:kind "test_chain" :label "Test-kjede") (wf)
  (declare (ignore wf))
  (tun.workflows:schedule-workflow "test_ping" :due-at (now)))

(define-workflow test-boom (:kind "test_boom" :label "Feiler") (wf)
  (declare (ignore wf))
  (error "bevisst feil"))

(defun plan (kind due)
  (with-application (*app*)
    (with-transaction (:write)
      (tun.workflows:schedule-workflow kind :due-at (parse-rfc3339 due)))))

(test workflow-engine
  (with-test-app (:db (scratch-path "workflows"))
    (setf *pings* 0)
    (plan "test_ping" "2026-03-02T09:00:00Z")
    (plan "test_boom" "2026-03-02T08:00:00Z")
    (plan "test_chain" "2026-03-03T09:00:00Z")
    (plan "test_ping" "2026-04-01T09:00:00Z")
    (let ((r (call-ok "clock_set" "admin:ada" "now" "2026-03-03T09:00:00Z")))
      (is (= 3 (jget r "executed_workflows")) "ping, chain and the ping the chain planned")
      (is (= 2 *pings*)))
    (is (= 0 (jget (call-ok "clock_set" "admin:ada" "now" "2026-03-03T09:00:00Z") "executed_workflows"))
        "at most once")
    (with-application (*app*)
      (with-transaction (:read)
        (let ((rows (select 'tun.workflows:workflow :order-by '(("due_at" :asc)))))
          (is (equal '("failed" "executed" "executed" "executed" "planned")
                     (mapcar #'tun.workflows:workflow-status rows)))
          (is (search "bevisst feil" (tun.workflows:workflow-note (first rows)))))))
    (is (string= "forbidden" (nth-value 1 (call "clock_set" "employee:anna" "now" "2026-05-01T00:00:00Z"))))))

;;; The method combination is the security boundary.

(defclass sneaky-app (application) ())

(defun bypass-attempt-fails-p ()
  "True when (1) the start-up check refuses the deployment and (2) a call on an
application built without that check still errors instead of bypassing."
  (and (handler-case (progn (check-operation-methods) nil) (tun.core::extension-error () t))
       (handler-case (progn (tun.runtime:open-application 'sneaky-app) nil)
         (tun.core::extension-error () t))
       (let ((*app* (make-instance 'sneaky-app)))
         (handler-case (progn (call "widgets_create" "viewer:vera" "name" "x") nil)
           (error () t)))))

(test extensions-cannot-wrap-or-replace-an-operation
  (let ((around (eval '(defmethod widgets-create :around ((app sneaky-app) input)
                        (declare (ignore input))
                        (jobj "bypassed" t)))))
    (unwind-protect (is (bypass-attempt-fails-p) ":around is refused")
      (remove-method #'widgets-create around)))
  (let ((primary (eval '(defmethod widgets-create ((app sneaky-app) input)
                         (declare (ignore input))
                         (jobj "replaced" t)))))
    (unwind-protect (is (bypass-attempt-fails-p) "a second primary is refused")
      (remove-method #'widgets-create primary)))
  (is (check-operation-methods) "clean again"))

;;; Core stands alone, and normal mode runs workflows on a scheduler tick.

(test core-suite-runs-without-any-client
  (is (null (find-package "TEST-CLIENT")) "no client code is loaded in this image")
  (is (null (asdf:component-loaded-p "test-client"))))

(test scheduler-runs-due-workflows-in-normal-mode
  (with-test-app (:test-clock nil)
    (setf *pings* 0)
    (is (not (test-mode-p *app*)))
    (is (find-operation-by-tool "clock_set") "clock tools are registered ...")
    (is (not (member "clock_set" (mapcar #'operation-tool (visible-operations *app*)) :test #'string=))
        "... but hidden outside test mode")
    (with-application (*app*)
      (with-transaction (:write)
        (tun.workflows:schedule-workflow "test_ping" :due-at (- (get-universal-time) 3600))))
    (unwind-protect
         (progn
           (tun.runtime:start-scheduler *app* :interval 0.1)
           (loop repeat 50 until (= 1 *pings*) do (sleep 0.1))
           (is (= 1 *pings*) "the scheduler ran the due workflow")
           (sleep 0.3)
           (is (= 1 *pings*) "and only once"))
      (tun.runtime:stop-scheduler))))
