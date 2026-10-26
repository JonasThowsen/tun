;;;; slice3-review-tests.lisp -- regressions for the independent communication review.
(in-package #:tun.tests)
(def-suite slice3-review :in core)
(in-suite slice3-review)

(test s3r-1-erasure-redacts-receipt-replays
  (with-communication-templates
    (with-test-app ()
      (let* ((args '("name" "Receipt Person" "email" "receipt@example.no" "request_key" "customer"))
             (customer (jget (apply #'call-ok "customers_create" "employee:e" args) "id"))
             (order (jget (new-order customer "lines" (lines (make-product) 1)) "id"))
             (preview (call-ok "messages_preview" "employee:e" "template" "unit_note" "order_id" order))
             (send (list "template" "unit_note" "order_id" order "snapshot_hash" (jget preview "snapshot_hash") "request_key" "message")))
        (apply #'call-ok "messages_send" "employee:e" send)
        (two-step "orders_cancel" "employee:e" "id" order)
        (two-step "customers_erase" "admin:a" "id" customer)
        (is (search "@slettet.local" (jget (apply #'call-ok "customers_create" "employee:e" args) "email")))
        (is (equal "[slettet]" (jget (apply #'call-ok "messages_send" "employee:e" send) "body")))))))

(test s3r-2-staff-projections-mask-quote-code
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "unit_code" 'unit-code :source :client :manual t
      :subject "Offer" :text "Code {{tilbud.kode}}" :variables '("tilbud.kode"))
    (with-test-app ()
      (let* ((customer (make-customer)) (order (jget (new-order customer "lines" (lines (make-product) 1)) "id")))
        (call-ok "orders_send_quote" "employee:e" "id" order)
        (let* ((raw-code (jget (call-ok "quotes_get" "admin:a" "order_id" order) "access_code"))
               (code (format nil "~a-~a" (subseq raw-code 0 5) (subseq raw-code 5)))
               (preview (call-ok "messages_preview" "employee:e" "template" "unit_code" "order_id" order))
               (message (call-ok "messages_send" "employee:e" "template" "unit_code" "order_id" order "snapshot_hash" (jget preview "snapshot_hash"))))
          (is (not (search code (to-json-string preview))))
          (is (not (search code (to-json-string (call-ok "messages_get" "viewer:v" "id" (jget message "id"))))))
          (is (not (search code (to-json-string (call-ok "messages_list" "viewer:v" "order_id" order)))))
          (is (search code (to-json-string (call-ok "messages_get" "admin:a" "id" (jget message "id"))))))))))

(test s3r-3-form-reference-cannot-change-another-customer
  (with-test-app ()
    (let* ((customer (make-customer)) (order (jget (new-order customer "lines" (lines (make-product) 1)) "id")))
      (call-ok "orders_send_quote" "employee:e" "id" order)
      (with-application (*app*) (with-transaction (:write)
        (insert (make-instance 'tun.workflows:workflow :kind "tilbud_påminnelse" :order-id order :due-at (+ (now) 3600)))))
      (call-ok "henvendelser_create" "viewer:v" "name" "Stranger" "email" "stranger@example.no"
        "message" (format nil "[ref:~a]" order) "marketing_consent" t)
      (is (null (jget (call-ok "customers_get" "viewer:v" "id" customer) "marketing_consent")))
      (is (find "planlagt" (jget (call-ok "workflows_list" "viewer:v" "order_id" order "kind" "tilbud_påminnelse") "items")
                :key (lambda (item) (jget item "status")) :test #'equal))
      (is (not (find "referanse" (jget (call-ok "henvendelser_list" "employee:e") "items") :key (lambda (x) (jget x "match")) :test #'equal))))))

(defclass unrecognised-slow-provider (tun.messaging:fake-message-transport) ())
(defmethod tun.messaging:deliver-snapshot ((adapter unrecognised-slow-provider) request mode call-number)
  (declare (ignore request mode call-number))
  (sleep 11)
  (values "accepted" nil "late-answer"))
(test s3r-4-provider-deadline-is-independent-of-mode
  (with-communication-templates
    (with-test-app ()
      (setf (application-message-transport *app*) (make-instance 'unrecognised-slow-provider))
      (let* ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id"))
             (p (call-ok "messages_preview" "employee:e" "template" "unit_note" "order_id" order))
             (start (get-internal-real-time))
             (m (call-ok "messages_send" "employee:e" "template" "unit_note" "order_id" order "snapshot_hash" (jget p "snapshot_hash"))))
        (is (< (- (get-internal-real-time) start) internal-time-units-per-second))
        (setf start (get-internal-real-time))
        (call-ok "orders_get" "viewer:v" "id" order)
        (is (< (- (get-internal-real-time) start) internal-time-units-per-second))
        (loop repeat 110 until (equal "outcome_unknown" (jget (jget (call-ok "messages_get" "viewer:v" "id" (jget m "id")) "delivery") "status")) do (sleep .05))
        (is (equal "outcome_unknown" (jget (jget (call-ok "messages_get" "viewer:v" "id" (jget m "id")) "delivery") "status")))
        (call-ok "messages_resolve" "admin:a" "id" (jget m "id") "outcome" "failed" "note" "Provider checked")
        (sleep 7.2)
        (is (equal "failed" (jget (jget (call-ok "messages_get" "viewer:v" "id" (jget m "id")) "delivery") "status")))))))

(defclass seam-refusing-app (application) ())
(defclass seam-throwing-app (application) ())
(defclass seam-error-result-app (application) ())
(defmethod tun.inbox:request-defaults ((app seam-error-result-app) item)
  (declare (ignore item)) (jobj "error" (jobj "code" "invalid_input" "message" "draft returned an error")))
(defmethod tun.inbox:request-defaults ((app seam-refusing-app) item)
  (declare (ignore item)) (fail :invalid-input "draft refused"))
(defmethod tun.inbox:request-defaults ((app seam-throwing-app) item)
  (declare (ignore item))
  (insert (make-instance 'tun.customers:customer :name "Rolled back" :email "rollback@example.no"))
  (error "draft threw"))
(defun check-failed-draft-retention (class)
  (with-test-app (:class class)
    (let ((item (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "draft@example.no" "subject" "New" "body" "Draft") "henvendelse")))
      (is (search "utkast ikke opprettet: draft" (jget item "note")))
      (is (= 1 (length (jget (call-ok "henvendelser_list" "employee:e") "items"))))
      (is (= 0 (length (jget (call-ok "customers_list" "viewer:v") "items")))))))
(test s3r-5-refusing-seam-retains-enquiry (check-failed-draft-retention 'seam-refusing-app))
(test s3r-5-throwing-seam-retains-enquiry (check-failed-draft-retention 'seam-throwing-app))
(test s3r-5-returned-error-retains-enquiry (check-failed-draft-retention 'seam-error-result-app))

(test s3r-6-delivery-notices-are-admin-only
  (with-communication-templates
    (with-test-app ()
      (make-employee "Ada" :role "admin")
      (let* ((employee (make-employee "Anna"))
             (order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
        (call-ok "assignments_create" "admin:ada" "order_id" order "employee_id" (jget employee "id"))
        (call-ok "messaging_provider_set" "admin:ada" "mode" "reject")
        (let ((p (call-ok "messages_preview" "employee:anna" "template" "unit_note" "order_id" order)))
          (call-ok "messages_send" "employee:anna" "template" "unit_note" "order_id" order "snapshot_hash" (jget p "snapshot_hash")))
        (sleep .1)
        (is (not (find "leveranse_feilet" (jget (call-ok "notifications_list" "employee:anna") "items") :key (lambda (x) (jget x "type")) :test #'equal)))
        (is (find "leveranse_feilet" (jget (call-ok "notifications_list" "admin:ada") "items") :key (lambda (x) (jget x "type")) :test #'equal))))))

(test s3r-7-invalid-public-requests-allocate-no-sessions
  (let ((before (hash-table-count tun.web::*public-sessions*)))
    (with-test-server (port)
      (dotimes (i 5) (declare (ignorable i)) (web-request port "/avmeld/INVALID"))
      (is (= before (hash-table-count tun.web::*public-sessions*))))))

(test s3r-8-newest-quote-across-duplicate-emails
  (with-test-app ()
    (let* ((first (make-customer "Shared")) (second (make-customer "Shared")) (product (make-product))
           (old (jget (new-order first "lines" (lines product 1)) "id"))
           (new (jget (new-order second "lines" (lines product 1)) "id")))
      (call-ok "orders_send_quote" "employee:e" "id" old)
      (call-ok "orders_send_quote" "employee:e" "id" new)
      (is (equal new (jget (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "shared@example.no" "subject" "Reply" "body" "Hello") "henvendelse") "order_id"))))))

(test s3r-9-unknown-reference-is-skipped
  (with-test-app ()
    (let ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (is (equal order (jget (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "reply@example.no" "subject" "[ref:ord_missing]"
        "body" (format nil "[ref:~a]" order)) "henvendelse") "order_id"))))))

(test s3r-10-screen-shows-newest-hundred-api-stays-oldest-first
  (with-test-app ()
    (let* ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (with-application (*app*) (with-transaction (:write)
        (dotimes (i 101)
          (insert (make-instance 'tun.inbox:henvendelse :order-id order :subject (format nil "History~3,'0d" i) :body "Reply" :received-at (now) :from-email "reply@example.no")))))
      (is (equal "History000" (jget (aref (jget (call-ok "messages_list" "viewer:v" "order_id" order "limit" 100) "items") 0) "subject")))
      (with-application (*app*) (with-actor ((parse-actor "viewer:v")) (with-transaction (:read)
        (let ((html (tun.html:render-html (cons :div (tun.web:render-resource-extras *app* 'tun.orders:order (call-ok "orders_get" "viewer:v" "id" order))))))
          (is (search "History100" html)) (is (not (search "History000" html))))))))))

(test s3r-11-contact-body-has-recognisable-structured-fields
  (with-test-app ()
    (let ((item (call-ok "henvendelser_create" "viewer:v" "name" "Contact" "email" "contact@example.no" "message" "2040"
                 "event_date" "2027-06-20" "guests" 42 "marketing_consent" t)))
      (is (search "Dato: 20.06.2027" (jget item "body")))
      (is (search "Gjester: 42" (jget item "body"))))))

(test s3r-12-same-function-template-override-increments-version
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "unit_override" 'same-renderer :source :core :module "messaging" :text "Original")
    (tun.core::register-message-template "unit_override" 'same-renderer :source :client :module "client" :text "Override")
    (is (= 2 (tun.core::message-template-version (tun.core::find-message-template "unit_override"))))))

(test s3r-13-keyed-workflow-lookup-uses-composite-index
  (with-test-app (:db (scratch-path "workflow-index"))
    (with-application (*app*) (with-transaction (:read)
      (let ((plan (sqlite:execute-to-list tun.store.sqlite::*connection*
                    "EXPLAIN QUERY PLAN SELECT id FROM workflows WHERE kind = 'test' AND key = 'missing' AND status = 'planlagt'")))
        (is (search "idx_workflows_kind_key_status" (to-json-string (jarr (mapcar #'jarr plan))))))))))

(test s3r-14-inbound-secret-header-is-utf8
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "innboks.hemmelighet" "value" "blå-hemmelighet")
    (let* ((secret (sb-ext:octets-to-string (sb-ext:string-to-octets "blå-hemmelighet" :external-format :utf-8) :external-format :latin-1))
           (status (nth-value 1 (drakma:http-request (format nil "http://127.0.0.1:~d/inbound/mail" port) :method :post
             :content-type "application/json" :content (to-json-string (jobj "from_email" "wire@example.no" "subject" "Wire" "body" "Hello"))
             :additional-headers (list (cons "X-Tun-Inbound-Secret" secret))))))
      (is (= 200 status)))))

(test s3r-7-session-expiry-and-oldest-eviction
  (let ((tun.web::*public-sessions* (make-hash-table :test 'equal)))
    (dotimes (i 10000)
      (setf (gethash (princ-to-string i) tun.web::*public-sessions*) (tun.web::make-public-session :created-at (+ 1000 i))))
    ;; All rows are younger than an hour; the oldest is evicted at capacity.
    (setf (tun.web::public-session-created-at (gethash "0" tun.web::*public-sessions*)) 999)
    (tun.web::find-public-session nil t 1100)
    (is (= 10000 (hash-table-count tun.web::*public-sessions*)))
    (is (null (gethash "0" tun.web::*public-sessions*)))
    (clrhash tun.web::*public-sessions*)
    (multiple-value-bind (session cookie) (tun.web::find-public-session nil t 1000)
      (is (eq session (tun.web::find-public-session cookie nil 4599)))
      (is (not (eq session (tun.web::find-public-session cookie nil 8199))))
      (is (= 0 (hash-table-count tun.web::*public-sessions*))))))

(test s3r-13-workflow-index-migration-is-namespaced-and-idempotent
  (let ((path (scratch-path "workflow-index-reopen")))
    (dotimes (i 2)
      (declare (ignorable i))
      (with-test-app (:db path)
        (with-application (*app*) (with-transaction (:read)
          (let ((rows (sqlite:execute-to-list tun.store.sqlite::*connection*
            "SELECT module, migration FROM schema_history WHERE statement LIKE '%idx_workflows_kind_key_status%'")))
            (is (= 1 (length rows))) (is (equal "core" (caar rows)))
            (is (search "core_" (second (first rows)))))))))))

(test s3r-7-same-second-sessions-evict-in-creation-order
  (let ((tun.web::*public-sessions* (make-hash-table :test 'equal))
        (tun.web::+public-session-limit+ 2))
    (let ((first (nth-value 1 (tun.web::find-public-session nil t 1000)))
          (second (nth-value 1 (tun.web::find-public-session nil t 1000))))
      (tun.web::find-public-session nil t 1000)
      (is (null (gethash first tun.web::*public-sessions*)))
      (is (not (null (gethash second tun.web::*public-sessions*)))))))

(test s3r-2-order-and-inbox-screens-mask-stored-credentials
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "unit_code" 'unit-code :source :client :manual t
      :subject "Offer" :text "Code {{tilbud.kode}}" :variables '("tilbud.kode"))
    (with-test-server (port)
      (let* ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
        (call-ok "orders_send_quote" "employee:e" "id" order)
        (let* ((raw (jget (call-ok "quotes_get" "admin:a" "order_id" order) "access_code"))
               (code (format nil "~a-~a" (subseq raw 0 5) (subseq raw 5)))
               (preview (call-ok "messages_preview" "employee:e" "template" "unit_code" "order_id" order))
               (message (call-ok "messages_send" "employee:e" "template" "unit_code" "order_id" order "snapshot_hash" (jget preview "snapshot_hash")))
               (item (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "reply@example.no"
                            "subject" (format nil "[ref:~a]" order) "body" code) "henvendelse")))
          (with-application (*app*) (with-transaction (:read)
            (is (search code (field-value (fetch 'tun.messaging:message (jget message "id"))
                                         (find-field 'tun.messaging:message "body"))))))
          (multiple-value-bind (status body) (web-request port (format nil "/orders/~a" order) :jar (web-login port "viewer:v"))
            (is (= 200 status)) (is (not (search code body))) (is (search "•••••-•••••" body)))
          (multiple-value-bind (status body) (web-request port (format nil "/henvendelser/~a" (jget item "id")) :jar (web-login port "employee:e"))
            (is (= 200 status)) (is (not (search code body))) (is (search "•••••-•••••" body)))
          (is (equal "•••••-•••••" (jget (call-ok "henvendelser_get" "employee:e" "id" (jget item "id")) "body"))))))))

(test s3r-14-latin1-secret-is-refused
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "innboks.hemmelighet" "value" "blå-hemmelighet")
    (is (= 403 (nth-value 1 (drakma:http-request (format nil "http://127.0.0.1:~d/inbound/mail" port) :method :post
             :content-type "application/json" :content (to-json-string (jobj "from_email" "wire@example.no" "subject" "Wire" "body" "Hello"))
             :additional-headers (list (cons "X-Tun-Inbound-Secret" "blå-hemmelighet"))))))))

(test s3r-1-upgrade-repairs-receipts-of-already-erased-customers
  (with-communication-templates
    (with-test-app (:db (scratch-path "legacy-erasure"))
      (let* ((args '("name" "Old Receipt" "email" "old-receipt@example.no" "request_key" "old-customer"))
             (original (apply #'call-ok "customers_create" "employee:e" args))
             (customer (jget original "id"))
             (order (jget (new-order customer "lines" (lines (make-product) 1)) "id"))
             (p (call-ok "messages_preview" "employee:e" "template" "unit_note" "order_id" order))
             (send (list "template" "unit_note" "order_id" order "snapshot_hash" (jget p "snapshot_hash") "request_key" "old-message"))
             (message (apply #'call-ok "messages_send" "employee:e" send))
             (path (tun.store.sqlite:sqlite-store-path (application-store *app*))))
        (two-step "orders_cancel" "employee:e" "id" order)
        (two-step "customers_erase" "admin:a" "id" customer)
        ;; Simulate 2ff9e41: fresh entities are anonymous, retained receipts are not.
        (with-application (*app*) (with-transaction (:write)
          (dolist (pair (list (cons "old-customer" original) (cons "old-message" message)))
            (let ((receipt (select-one 'tun.core::receipt :where `(:= "request_key" ,(car pair)))))
              (setf (tun.core::receipt-result receipt) (to-json-string (cdr pair))) (save receipt)))))
        (tun.runtime:close-application *app*)
        (setf *app* (tun.runtime:open-application 'application :db path :test-clock t))
        (is (search "@slettet.local" (jget (apply #'call-ok "customers_create" "employee:e" args) "email")))
        (is (equal "[slettet]" (jget (apply #'call-ok "messages_send" "employee:e" send) "body")))))))

(test s3r-1-erasure-keeps-quote-receipt-credentials-private
  (with-test-app ()
    (let* ((customer (make-customer)) (order (jget (new-order customer "lines" (lines (make-product) 1)) "id")))
      (call-ok "orders_send_quote" "employee:e" "id" order)
      (let* ((quote (call-ok "quotes_get" "admin:a" "order_id" order))
             (args (list "quote_id" (jget quote "id") "revision" (jget quote "revision") "access_code" (jget quote "access_code")
                         "response" "decline" "request_key" "quote-response")))
        (is (json-null-p (jget (apply #'call-ok "quotes_respond" "viewer:v" args) "access_code")))
        (two-step "orders_cancel" "employee:e" "id" order)
        (two-step "customers_erase" "admin:a" "id" customer)
        (let ((replay (apply #'call-ok "quotes_respond" "viewer:v" args)))
          (is (json-null-p (jget replay "access_code")))
          (is (not (nth-value 1 (gethash "basis" replay)))))))))

(def-suite slice3-review-round2 :in core)
(in-suite slice3-review-round2)

(test s3r2-preview-hash-covers-the-complete-snapshot
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "unit_code" 'unit-code :source :client :manual t
      :subject "Offer" :text "Code {{tilbud.kode}}" :variables '("tilbud.kode"))
    (with-communication-templates
    (with-test-app ()
      (let* ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
        (call-ok "orders_send_quote" "employee:e" "id" order)
        (let* ((employee (call-ok "messages_preview" "employee:e" "template" "unit_code" "order_id" order))
               (admin (call-ok "messages_preview" "admin:a" "template" "unit_code" "order_id" order)))
          (is (equal (jget admin "snapshot_hash") (jget employee "snapshot_hash")))
          (is (not (equal (jget admin "body") (jget employee "body"))))
          (is (equal "sendt" (jget (call-ok "messages_send" "employee:e" "template" "unit_code" "order_id" order
                                  "snapshot_hash" (jget admin "snapshot_hash")) "status")))))))))

(defclass briefly-delayed-provider (tun.messaging:fake-message-transport)
  ((request-context :initform :not-called :accessor brief-provider-context)))
(defmethod tun.messaging:deliver-snapshot :before ((adapter briefly-delayed-provider) request mode number)
  (declare (ignore request mode number))
  (setf (brief-provider-context adapter) (list *request-id* *request-record* *inside-operation* *transaction-mode*))
  (sleep .03))
(test s3r2-fast-outbox-drains-before-the-next-request
  (with-test-app ()
    (let* ((adapter (make-instance 'briefly-delayed-provider))
           (order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (setf (application-message-transport *app*) adapter)
      (call-ok "orders_send_quote" "employee:e" "id" order)
      (let ((message (aref (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items") 0)))
        (is (equal "accepted" (jget (jget message "delivery") "status")))
        (is (equal '(nil nil nil nil) (brief-provider-context adapter)))))))
(test s3r2-customer-bound-failure-notifies-admin-before-the-next-request
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "neste_år" 'unit-note :source :client :manual t
      :subject "Next year" :text "Hello {{kunde.navn}}")
    (with-test-app ()
    (let ((customer (call-ok "customers_create" "employee:e" "name" "Pia Pause" "email" "pia@example.no")))
      (make-employee "Ada" :role "admin")
      (call-ok "messaging_provider_set" "admin:a" "mode" "reject")
      (setf (application-message-transport *app*) (make-instance 'briefly-delayed-provider))
      (let* ((preview (call-ok "messages_preview" "employee:e" "template" "neste_år" "customer_id" (jget customer "id")))
             (message (call-ok "messages_send" "employee:e" "template" "neste_år" "customer_id" (jget customer "id")
                                "snapshot_hash" (jget preview "snapshot_hash")))
             (notices (jget (call-ok "notifications_list" "admin:ada") "items")))
        (is (equal "failed" (jget (jget (call-ok "messages_get" "viewer:v" "id" (jget message "id")) "delivery") "status")))
        (is (= 1 (length notices)))
        (when (= 1 (length notices))
          (is (equal "En e-post til Pia Pause kunne ikke sendes." (jget (aref notices 0) "text")))
          (is (equal (format nil "/customers/~a" (jget customer "id")) (jget (aref notices 0) "link")))))))))
(test s3r2-session-renews-and-expires-on-the-server-clock
  (with-test-app ()
    (let ((tun.web::*public-sessions* (make-hash-table :test 'equal)))
      (with-application (*app*)
        (let ((start (now)))
          (multiple-value-bind (session cookie) (tun.web::find-public-session nil t)
            (call-ok "clock_set" "admin:a" "now" (format-rfc3339 (+ start 3599)))
            (is (eq session (tun.web::find-public-session cookie nil)))
            (call-ok "clock_set" "admin:a" "now" (format-rfc3339 (+ start 3601)))
            (is (eq session (tun.web::find-public-session cookie nil)))
            (call-ok "clock_set" "admin:a" "now" (format-rfc3339 (+ start 7201)))
            (is (not (eq session (tun.web::find-public-session cookie nil))))
            (is (zerop (hash-table-count tun.web::*public-sessions*)))))))))
(test s3r2-hidden-sleep-ok-device-is-not-in-the-schema
  (with-test-app ()
    (let ((schema (tool-definition (find-operation 'tun.messaging::messaging-provider-set))))
      (is (not (find "sleep_ok" (jget (jget (jget (jget schema "inputSchema") "properties") "mode") "enum") :test #'equal))))
    (is (equal "sleep_ok" (jget (call-ok "messaging_provider_set" "admin:a" "mode" "sleep_ok") "mode")))))
(test s3r2-normal-mode-drains-on-the-scheduler-tick
  (with-test-app (:test-clock nil)
    (let ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (call-ok "orders_send_quote" "employee:e" "id" order)
      (sleep .3)
      (is (= 0 (jget (call-ok "messaging_provider_get" "admin:a") "calls")))
      (is (equal "queued" (jget (jget (aref (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items") 0) "delivery") "status")))
      ;; The scheduler's tick: it tends the jobs, the outbox's among them.
      (tun.jobs:tend-jobs *app*)
      (wait-for-workers *app*)
      (is (= 1 (jget (call-ok "messaging_provider_get" "admin:a") "calls")))
      (is (equal "accepted" (jget (jget (aref (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items") 0) "delivery") "status"))))))
