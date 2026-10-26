;;;; tests/extension-tests.lisp -- each kind of extension point, through the
;;;; client's definition of it.

(in-package #:test-client.tests)

(def-suite extensions :in client)
(in-suite extensions)

(defun field-of (describe entity field)
  "FIELD of ENTITY in DESCRIBE, a registry_describe result."
  (find-by "name" field (jget (find-by "name" entity (jget describe "entities")) "fields")))

(defun source-of (key name items)
  "The source of the item of ITEMS whose KEY is NAME."
  (jget (find-by key name items) "source"))

(test describe-marks-client-additions
  (with-client ()
    (let ((d (call-ok "registry_describe" "viewer:vera")))
      (loop for (entity field source) in '(("customer" "name" "core")
                                           ("customer" "email" "core")
                                           ("customer" "kind" "client")
                                           ("customer" "org_number" "client")
                                           ("customer" "loyalty_tier" "client")
                                           ("product" "cleaning_days" "client")
                                           ("order_line" "hours" "client")
                                           ("order" "lines" "core"))
            do (is (equal source (jget (field-of d entity field) "source")) "~a.~a" entity field))
      (is (eq t (jget (field-of d "customer" "loyalty_tier") "computed")))
      (is (string= "client" (source-of "name" "products_set_cleaning_days" (jget d "operations"))))
      (is (string= "client" (source-of "name" "business_customers_need_org_number"
                                       (jget (find-by "name" "customer" (jget d "entities"))
                                             "rules"))))
      (is (string= "client" (source-of "kind" "tilbud_påminnelse" (jget d "workflows"))))
      (is (string= "client" (source-of "name" "påminnelse" (jget d "message_templates")))))))

(defun tool (name tools)
  "The tool definition called NAME among TOOLS."
  (find name tools :key (lambda (tool) (jget tool "name")) :test #'string=))

(test client-fields-flow-into-every-schema
  (with-client ()
    (let* ((tools (mapcar #'tun.core:tool-definition (tun.core:visible-operations *app*)))
           (create (jget (tool "customers_create" tools) "inputSchema"))
           (props (jget create "properties"))
           (orders (jget (tool "orders_create" tools) "inputSchema"))
           (line (jget (jget (jget orders "properties") "lines") "items")))
      (is (equalp #("privat" "bedrift") (jget (jget props "kind") "enum")))
      (is (member "kind" (coerce (jget create "required") 'list) :test #'string=))
      (is (jget props "org_number"))
      (is (jget (jget line "properties") "hours") "the order line schema has the client's hours")
      (is (not (member "hours" (coerce (jget line "required") 'list) :test #'string=))))))

(test a-client-rule-runs-on-every-write-of-the-entity
  (with-client ()
    (flet ((create (&rest fields)
             (nth-value 1 (apply #'call "customers_create" "employee:anna" "name" "Firma AS"
                                 "email" "post@example.no" fields))))
      (is (string= "invalid_input" (create "kind" "bedrift")))
      (is (string= "invalid_input" (create "kind" "bedrift" "org_number" "12345678")))
      (is (string= "invalid_input" (create "kind" "privat" "org_number" "12ab")))
      (is (string= "invalid_input" (create)) "kind is required")
      (is (null (create "kind" "bedrift" "org_number" "987654321")))
      (is (null (create "kind" "privat"))))))

(test a-computed-field-and-a-seam-price-the-order
  (is (equal '("bronse" "bronse" "sølv" "sølv" "sølv" "gull" "gull")
             (mapcar #'test-client:loyalty-tier-for '(0 1 2 3 4 5 9))))
  (is (equal '(0 5 10) (mapcar #'test-client:tier-discount-percent '("bronse" "sølv" "gull"))))
  (with-client ()
    (let* ((id (customer "Åse" "ase@example.no" "kind" "privat"))
           (stored (call-ok "customers_get" "viewer:vera" "id" id))
           (order (call-ok "orders_create" "employee:anna" "customer_id" id
                           "lines" (lines-of (list "product_id" (rental "Telt") "quantity" 1)))))
      (is (string= "bronse" (jget stored "loyalty_tier")))
      (is (eq :null (jget stored "org_number" :absent)))
      (is (= 0 (jget order "discount_ore")) "bronse gives no discount"))))

(test a-client-operation-stores-the-clients-own-field
  (with-client ()
    (let ((tent (rental "Telt")))
      (flet ((set-days (actor product days)
               (call "products_set_cleaning_days" actor "product_id" product "days" days)))
        (is (= 1 (jget (call-ok "products_get" "viewer:vera" "id" tent) "cleaning_days")))
        (let ((updated (set-days "employee:anna" tent 3)))
          (is (= 3 (jget updated "cleaning_days")))
          (is (= 2 (jget updated "revision")) "setting the field is an update"))
        (is (string= "not_found" (nth-value 1 (set-days "employee:anna" "prd_x" 1))))
        (is (string= "forbidden" (nth-value 1 (set-days "viewer:vera" tent 1))))))))

(defun confirm-booking (customer product date &optional end)
  "Quote, accept and confirm an order of PRODUCT on DATE (to END): the
confirmed order, or the refusal of the confirmation."
  (let ((id (jget (apply #'call-ok "orders_create" "employee:anna" "customer_id" customer
                         "event_date" date
                         "lines" (lines-of (list "product_id" product "quantity" 1))
                         (and end (list "end_date" end)))
                  "id")))
    (call-ok "orders_send_quote" "employee:anna" "id" id)
    (call-ok "orders_accept" "employee:anna" "id" id)
    (let ((first (call "orders_confirm" "employee:anna" "id" id)))
      (if (jget first "confirmation_token")
          (call "orders_confirm" "employee:anna" "id" id
                "confirmation_token" (jget first "confirmation_token"))
          first))))

(test the-booking-window-seam-widens-a-booking-on-both-sides
  (with-client ()
    (let ((tent (rental "Telt" :cleaning-days 1))
          (id (customer "Kari" "kari@example.no" "kind" "privat")))
      (let* ((order (confirm-booking id tent "2026-06-01" "2026-06-10"))
             (booking (aref (jget order "bookings") 0)))
        (is (equal '("2026-05-31" "2026-06-11") (list (jget booking "from") (jget booking "to")))))
      (dolist (case '(("2026-05-30" t) ("2026-05-31" nil) ("2026-06-06" nil) ("2026-06-11" nil)
                      ("2026-06-12" t)))
        (destructuring-bind (date free) case
          (is (eq free (jget (call-ok "availability_check" "viewer:vera" "product_id" tent
                                      "date" date)
                             "ok"))
              "~a" date)))
      (is (equal "unavailable" (error-code-of (confirm-booking id tent "2026-06-11" "2026-06-14")))
          "06-11 is cleaning")
      (is (equal "bekreftet"
                 (jget (confirm-booking id tent "2026-06-12" "2026-06-14") "status"))))))

(test the-clients-template-is-registered-as-the-clients
  (with-client ()
    (tun.core:with-application (*app*)
      (let ((template (tun.core:find-message-template "påminnelse")))
        (is (not (null template)))
        (is (eq :client (tun.core:message-template-source template)))))))

(test feature-mixins-order-the-after-methods
  (let ((precedence (mapcar #'class-name
                            (sb-mop:class-precedence-list (find-class 'test-client:nordvik)))))
    (is (< (position 'test-client::workflow-feature precedence)
           (position 'tun:application precedence))))
  ;; A module may have its own :after method on the operation too; the
  ;; client's specialises on its feature class, not on the application.
  (let ((afters (remove-if-not (lambda (m) (equal '(:after) (method-qualifiers m)))
                               (sb-mop:generic-function-methods #'tun:orders-send-quote)))
        (feature (find-class 'test-client::workflow-feature)))
    (is (= 1 (count feature afters :key (lambda (m) (first (sb-mop:method-specializers m)))))))
  (is (tun.core:check-operation-methods)
      "the client's methods respect the operation method combination"))

(defun reminders (order)
  "Status and due time of each quote reminder of ORDER."
  (loop for workflow across (jget (call-ok "workflows_list" "viewer:vera" "order_id" order) "items")
        when (equal "tilbud_påminnelse" (jget workflow "kind"))
          collect (list (jget workflow "status") (jget workflow "due_at"))))

(defun messages-of (order)
  "The messages sent about ORDER, oldest first."
  (coerce (jget (call-ok "messages_list" "viewer:vera" "order_id" order) "items") 'list))

(test the-after-methods-plan-and-cancel-the-reminder
  (with-client ()
    (let* ((id (customer "Anders" "anders@example.no" "kind" "privat"))
           (tent (rental "Telt"))
           (open (jget (call-ok "orders_create" "employee:anna" "customer_id" id
                                "event_date" "2026-06-20"
                                "lines" (lines-of (list "product_id" tent "quantity" 1)))
                       "id"))
           (answered (jget (call-ok "orders_create" "employee:anna" "customer_id" id
                                    "lines" (lines-of (list "product_id" tent "quantity" 1)))
                           "id")))
      (call-ok "orders_send_quote" "employee:anna" "id" open)
      (call-ok "orders_send_quote" "employee:anna" "id" answered)
      (is (equal '(("planlagt" "2026-03-03T09:00:00Z")) (reminders open)))
      (call-ok "orders_accept" "employee:anna" "id" answered)
      (is (equal "avbrutt" (first (first (reminders answered)))) "accepting cancels the reminder")
      (call-ok "clock_set" "admin:ada" "now" "2026-03-03T08:59:59Z")
      (is (equal "planlagt" (first (first (reminders open)))) "not due yet")
      (call-ok "clock_set" "admin:ada" "now" "2026-03-03T09:00:00Z")
      (is (equal "utført" (first (first (reminders open)))))
      (let ((reminder (car (last (messages-of open)))))
        (is (equal "påminnelse" (jget reminder "template")))
        (is (search "Hei Anders" (jget reminder "body")))
        (is (search "Vi har fortsatt et tilbud til deg" (jget reminder "subject"))))
      (is (notany (lambda (message) (equal "påminnelse" (jget message "template")))
                  (messages-of answered))))))
