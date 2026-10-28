;;;; tests/introspection-tests.lisp -- introspection with a client loaded:
;;;; the client's hooks in explain and in request traces, and its extensions
;;;; with their source locations.

(in-package #:test-client.tests)

(def-suite introspection :in client)
(in-suite introspection)

(defun recent-id (tool)
  "The request id of the newest call of TOOL."
  (let ((recent (call-ok "introspect_recent" "admin:ada" "kind" "all" "limit" 50)))
    (jget (find tool (coerce (jget recent "items") 'list)
                :key (lambda (item) (jget item "tool")) :test #'equal)
          "request_id")))

(defun client-hooks (request-id)
  "The steps of request REQUEST-ID that are hooks the client defined."
  (let ((trace (call-ok "introspect_request" "admin:ada" "request_id" request-id)))
    (remove-if-not (lambda (step)
                     (and (equal "hook" (jget step "kind")) (equal "client" (jget step "source"))))
                   (coerce (jget trace "steps") 'list))))

(defun hook-listed-p (explained phase name)
  "Whether EXPLAINED, an explain result, lists the hook NAME in PHASE."
  (find-if (lambda (hook) (and (equal phase (jget hook "phase")) (equal name (jget hook "name"))))
           (coerce (jget explained "hooks") 'list)))

(test explain-runs-the-client-hooks-and-matches-the-real-create
  (with-client ()
    (let* ((id (customer "Kari" "kari@example.no" "kind" "privat"))
           (lines (lines-of (list "product_id" (rental "Telt") "quantity" 1 "hours" 3)))
           (input (jobj "customer_id" id "event_date" "2026-08-01" "lines" lines))
           (explained (call-ok "explain" "admin:ada" "tool" "orders_create" "input" input))
           (real (call-ok "orders_create" "employee:anna" "customer_id" id
                          "event_date" "2026-08-01" "lines" lines))
           (would (jget explained "would")))
      (dolist (key '("subtotal_minor" "discount_minor" "total_minor"))
        (is (equal (jget real key) (jget would key)) "~a" key))
      (is (hook-listed-p explained "order_discount" "loyalty-feature")
          "the discount seam's client method is listed")
      (let ((quote (call-ok "explain" "admin:ada" "tool" "orders_send_quote"
                            "input" (jobj "id" (jget real "id")))))
        (is (hook-listed-p quote "after" "workflow-feature")
            "the reminder hook is listed, after the operation")
        (is (string= "draft" (jget (call-ok "orders_get" "viewer:vera" "id" (jget real "id"))
                                    "status"))
            "explain sent nothing")))))

(defun hook-names (request-id)
  "The names of the client's hooks in request REQUEST-ID, in the order they ran."
  (mapcar (lambda (hook) (jget hook "name")) (client-hooks request-id)))

(test request-traces-show-client-hooks-in-order
  (with-client ()
    (let* ((id (customer "Ola" "ola@example.no" "kind" "privat"))
           (lines (lines-of (list "product_id" (rental "Telt") "quantity" 1)))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" id
                                 "event_date" "2026-09-01" "lines" lines)
                        "id")))
      (is (equal '("order_discount:loyalty-feature") (hook-names (recent-id "orders_create"))))
      (is (every #'integerp (mapcar (lambda (hook) (jget hook "order"))
                                    (client-hooks (recent-id "orders_create")))))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (is (equal '("after:workflow-feature") (hook-names (recent-id "orders_send_quote")))))))

(defparameter +client-location-prefix+ "clients/test-client/"
  "How a source location names a file of this client: clients/<system>/<file>.")

(defun location-line (location)
  "The text of the source line LOCATION (\"clients/test-client/FILE:LINE\") names."
  (let* ((colon (position #\: location :from-end t))
         (file (subseq location (length +client-location-prefix+) colon))
         (line (parse-integer location :start (1+ colon))))
    (with-open-file (in (merge-pathnames file (asdf:system-source-directory "test-client")))
      (loop repeat (1- line) do (read-line in))
      (read-line in))))

(defparameter +client-extensions+
  '(("field" "customer" "kind" "(extend-entity customer")
    ("field" "customer" "org_number" "(extend-entity customer")
    ("rule" "customer" "business_customers_need_org_number" "(define-rule")
    ("computed" "customer" "loyalty_tier" "(define-computed-field customer loyalty-tier")
    ("before" "order_discount" "loyalty-feature" "(defmethod order-discount")
    ("field" "order_line" "hours" "(extend-entity order-line")
    ("operation" "product" "products_set_cleaning_days" "(define-operation")
    ("field" "product" "cleaning_days" "(extend-entity product")
    ("before" "booking_window" "cleaning-feature" "(defmethod booking-window")
    ("after" "orders_send_quote" "workflow-feature" "(defmethod orders-send-quote :after")
    ("after" "orders_accept" "workflow-feature" "(defmethod orders-accept :after")
    ("workflow" "quote_reminder" "quote-reminder" "(define-workflow quote-reminder")
    ("template" "påminnelse" "reminder-message" "(define-message-template reminder-message")
    ("screen" "order_detail" "order-screen-feature" "(defmethod render-screen")
    ("screen" "customer_list" "customer-list-feature" "(defmethod render-screen"))
  "Each extension of the client, as kind, target and name, with the text its
definition starts with.")

(defun starts-with-p (prefix text)
  "Whether TEXT starts with PREFIX."
  (eql 0 (search prefix text)))

(test extensions-list-every-row-at-its-definition
  (with-client ()
    (let ((items (coerce (jget (call-ok "introspect_extensions" "admin:ada") "items") 'list)))
      (loop for (kind target name text) in +client-extensions+
            for item = (find-if (lambda (i) (and (equal kind (jget i "kind"))
                                                 (equal target (jget i "target"))
                                                 (equal name (jget i "name"))))
                                items)
            do (is (not (null item)) "~a ~a ~a is listed" kind target name)
               (when item
                 (let ((location (jget item "source_location")))
                   (is (starts-with-p text (location-line location))
                       "~a ~a: ~a points at ~s" kind name location (location-line location)))))
      (is (every (lambda (i) (starts-with-p +client-location-prefix+ (jget i "source_location")))
                 (remove-if-not (lambda (i) (equal "client" (jget i "module"))) items))
          "the client's own definitions point into the client")
      (is (every (lambda (i) (starts-with-p (format nil "modules/~a/" (jget i "module"))
                                            (jget i "source_location")))
                 (remove-if (lambda (i) (member (jget i "module") '("client" "core") :test #'equal))
                            items))
          "the modules' extensions of each other point into the module"))))
