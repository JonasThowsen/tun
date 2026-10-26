;;;; Erasure includes retained diagnostics and customer-bearing notification text.
(in-package #:tun.tests)
(def-suite slice3-review-round4 :in core)
(in-suite slice3-review-round4)

(defun recorded-review-call (tool actor &rest arguments)
  (let ((id (new-id "req")))
    (values (with-request-record (:id id :force-new t :claimable t)
              (apply #'call-ok tool actor arguments)) id)))

(test s3r4-39-erasure-redacts-create-and-contact-form-traces
  (with-test-app (:db (scratch-path "erased-traces"))
    (let ((name "Privacy Probe") (email "privacy.probe@example.no") (phone "+47 912 34 567"))
      (multiple-value-bind (customer create-id)
          (recorded-review-call "customers_create" "employee:e" "name" name "email" email "phone" phone "request_key" "private-create")
        (multiple-value-bind (form form-id)
            (recorded-review-call "henvendelser_create" "viewer:v" "name" name "email" email
                                 "message" (format nil "~a ~a ~a" name email phone) "marketing_consent" t "request_key" "private-form")
          (declare (ignore form))
          (multiple-value-bind (other other-id)
              (recorded-review-call "customers_create" "employee:e" "name" "Unrelated Person" "email" "other@example.no")
            (declare (ignore other))
            (dolist (id (list create-id form-id))
              (let ((trace (to-json-string (trace-of id))))
                (dolist (needle (list name email phone)) (is (search needle trace)))))
            (two-step "customers_erase" "admin:a" "id" (jget customer "id"))
            (dolist (id (list create-id form-id))
              (let ((trace (trace-of id)))
                (is (equal id (jget trace "request_id")))
                (is (equal "ok" (jget trace "outcome")))
                (dolist (needle (list name email phone)) (is (not (search needle (to-json-string trace)))))
              (let ((record (find-request id)))
                (dolist (needle (list name email phone))
                  (is (not (search needle (to-json-string (request-input record)))))
                  (is (not (search needle (princ-to-string (map 'list #'trace-step-detail (request-steps record)))))))))
            (multiple-value-bind (replay replay-id)
                (recorded-review-call "customers_create" "employee:e" "name" name "email" email "phone" phone
                                     "request_key" "private-create")
              (is (equal (jget customer "id") (jget replay "id")))
              (dolist (needle (list name email phone)) (is (not (search needle (to-json-string (trace-of replay-id)))))))
            (multiple-value-bind (replay replay-id)
                (recorded-review-call "henvendelser_create" "viewer:v" "name" name "email" email
                                     "message" (format nil "~a ~a ~a" name email phone) "marketing_consent" t
                                     "request_key" "private-form")
              (declare (ignore replay))
              (dolist (needle (list name email phone)) (is (not (search needle (to-json-string (trace-of replay-id)))))))
            (is (equal "Unrelated Person" (jget (jget (trace-of other-id) "input") "name"))))))))))

(test s3r4-39-erasure-protects-inflight-and-later-trace-details
  (with-test-app ()
    (let* ((customer (make-customer "In Flight Person")) (id (new-id "req")))
      (with-request-record (:id id :force-new t :input (jobj "customer_id" customer))
        (note-step :store :detail (jobj "statement" "INSERT private" "binds" (jarr '("In Flight Person"))))
        (two-step "customers_erase" "admin:a" "id" customer)
        (note-step :external :detail (jobj "output" "In Flight Person"))
        (set-request-outcome *request-record* "error" :code :internal-error :message "In Flight Person")
        (is (not (search "In Flight Person" (to-json-string (request->json *request-record*))))))
      (is (not (search "In Flight Person" (to-json-string (trace-of id))))))))

(test s3r4-39-refused-erasure-retains-useful-diagnostics
  (with-test-app ()
    (multiple-value-bind (customer id)
        (recorded-review-call "customers_create" "employee:e" "name" "Retained Person" "email" "retained@example.no")
      (new-order (jget customer "id") "lines" (lines (make-product) 1))
      (multiple-value-bind (first code) (call "customers_erase" "admin:a" "id" (jget customer "id"))
        (declare (ignore code))
        (is (equal "conflict" (nth-value 1 (call "customers_erase" "admin:a" "id" (jget customer "id")
                              "confirmation_token" (jget first "confirmation_token"))))))
      (is (equal "Retained Person" (jget (jget (trace-of id) "input") "name"))))))

(test s3r4-44-erasure-redacts-only-linked-notifications-and-their-receipts
  (with-communication-templates
    (tun.core::register-message-template "neste_år" 'unit-note :source :client :manual t
      :subject "Next year" :text "Hello {{kunde.navn}}")
    (with-test-app ()
      (make-employee "Ada" :role "admin")
      (let* ((customer (make-customer "Notice Person"))
             (other (make-customer "Other Person"))
             (order (jget (new-order customer "lines" (lines (make-product) 1)) "id")))
        (call-ok "messaging_provider_set" "admin:a" "mode" "reject")
        (dolist (binding (list (list "customer_id" customer) (list "order_id" order)))
          (let* ((template (if (equal "customer_id" (first binding)) "neste_år" "unit_note"))
                 (preview (apply #'call-ok "messages_preview" "employee:e" "template" template binding)))
            (apply #'call-ok "messages_send" "employee:e" "template" template
                   "snapshot_hash" (jget preview "snapshot_hash") binding)))
        (with-application (*app*) (with-transaction (:write)
          ;; Older/customer-specific reply notifications can contain the customer's name.
          (tun.notifications:publish-notification "kundesvar_mottatt" "legacy-reply"
            "Notice Person har svart." (format nil "/orders/~a" order) "henvendelse" "hen_old"
            :order-id order :recipients '("admin:ada"))
          (tun.notifications:publish-notification "leveranse_feilet" "unrelated-failure"
            "Notice Person is unrelated here." (format nil "/customers/~a" other) "message" "msg_other"
            :recipients '("admin:ada"))))
        (let* ((before (jget (call-ok "notifications_list" "admin:ada") "items"))
               (reply (find-by "type" "kundesvar_mottatt" before)))
          (is (= 4 (length before)))
          (call-ok "notifications_mark_read" "admin:ada" "id" (jget reply "id") "request_key" "read-before-erasure")
          (two-step "orders_cancel" "employee:e" "id" order)
          (two-step "customers_erase" "admin:a" "id" customer)
          (let ((after (jget (call-ok "notifications_list" "admin:ada") "items")))
            (is (= 4 (length after)))
            (loop for item across after do
              (if (equal (jget item "event_id") "unrelated-failure")
                  (is (equal "Notice Person is unrelated here." (jget item "text")))
                  (progn (is (not (search "Notice Person" (jget item "text"))))
                         (is (search "[slettet]" (jget item "text"))))))
            (is (jget (find-by "id" (jget reply "id") after) "read_at")))
          (is (equal "[slettet] har svart."
                (jget (call-ok "notifications_mark_read" "admin:ada" "id" (jget reply "id")
                              "request_key" "read-before-erasure") "text"))))))))

(test s3r4-39-trace-redaction-rolls-back-with-the-write-transaction
  (with-test-app ()
    (multiple-value-bind (customer id)
        (recorded-review-call "customers_create" "employee:e" "name" "Rollback Person" "email" "rollback@example.no")
      (with-application (*app*)
        (signals simple-error
          (with-transaction (:write)
            (redact-request-traces (list (jget customer "id") "Rollback Person"))
            (is (not (search "Rollback Person" (to-json-string (trace-of id)))))
            (error "Abort erasure transaction"))))
      (is (equal "Rollback Person" (jget (jget (trace-of id) "input") "name"))))))
