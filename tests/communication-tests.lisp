(in-package #:tun.tests)
(def-suite communication :in core)
(in-suite communication)

(defmacro with-communication-templates (&body body)
  `(let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
     (tun.core::register-message-template "unit_note" 'unit-note :source :client :manual t
        :subject "A note" :text "Hello {{customer.name}}")
     (tun.core::register-message-template "unit_marketing" 'unit-marketing :source :client :manual t :marketing t
        :subject "Marketing" :text "Hello {{customer.name}}")
     ,@body))

(test composer-stale-preview-replay-and-delivery-key-are-atomic
  (with-communication-templates
    (with-test-app ()
      (let* ((customer (make-customer)) (product (make-product))
             (order (jget (new-order customer "lines" (lines product 1)) "id"))
             (preview (call-ok "messages_preview" "employee:e" "template" "unit_note" "order_id" order))
             (hash (jget preview "snapshot_hash")))
        (call-ok "settings_set" "admin:a" "key" "sender.name" "value" "Updated")
        (is (equal "conflict" (nth-value 1 (call "messages_send" "employee:e" "template" "unit_note"
                                                "order_id" order "snapshot_hash" hash))))
        (is (= 0 (length (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items"))))
        (let* ((fresh (jget (call-ok "messages_preview" "employee:e" "template" "unit_note" "order_id" order) "snapshot_hash"))
               (args (list "template" "unit_note" "order_id" order "snapshot_hash" fresh "request_key" "one"))
               (sent (apply #'call-ok "messages_send" "employee:e" args)))
          (is (equal (jget sent "id") (jget (apply #'call-ok "messages_send" "employee:e" args) "id")))
          (is (equal (jget sent "id") (jget (call-ok "messages_send" "employee:e" "template" "unit_note"
                                                    "order_id" order "snapshot_hash" fresh "request_key" "two") "id")))
          (is (= 1 (length (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items")))))))))

(test marketing-is-guarded-on-preview-send-and-workflow-paths
  (with-communication-templates
    (with-test-app ()
      (let* ((customer (make-customer)) (product (make-product))
             (order (jget (new-order customer "lines" (lines product 1)) "id")))
        (is (equal "invalid_input" (nth-value 1 (call "messages_preview" "employee:e" "template" "unit_marketing" "order_id" order))))
        (is (equal "invalid_input" (nth-value 1 (call "messages_send" "admin:a" "template" "unit_marketing"
                                                     "order_id" order "snapshot_hash" "unknown"))))
        (with-application (*app*) (with-transaction (:write)
          (is (null (tun.messaging:send-message "unit_marketing" :order (tun.orders:find-order order)
                    :customer (fetch 'tun.customers:customer customer)))))
        (is (= 0 (length (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items")))))))))

(test provider-failures-are-safe-terminal-and-human-resolution-is-audited
  (with-communication-templates
    (with-test-app ()
      (let ((customer (make-customer)) (product (make-product)))
        (dolist (case '(("reject" "failed" "provider_rejected") ("unauthorized" "failed" "provider_unauthorized")
                        ("disabled" "failed" "provider_disabled") ("rate_limited" "outcome_unknown" "rate_limited")
                        ("transport" "outcome_unknown" "transport") ("crash" "outcome_unknown" "unknown_provider_outcome")))
          (call-ok "messaging_provider_set" "admin:a" "mode" (first case))
          (let* ((order (jget (new-order customer "lines" (lines product 1)) "id"))
                 (preview (call-ok "messages_preview" "employee:e" "template" "unit_note" "order_id" order))
                 (message (call-ok "messages_send" "employee:e" "template" "unit_note" "order_id" order
                                    "snapshot_hash" (jget preview "snapshot_hash")))
                 (id (jget message "id"))
                 (delivery (progn (wait-for-workers *app*) (jget (call-ok "messages_get" "viewer:v" "id" id) "delivery"))))
            (is (equal (second case) (jget delivery "status")))
            (is (equal (third case) (jget delivery "error_code")))
            (is (stringp (jget delivery "safe_error_message")))
            (is (= 1 (jget delivery "attempt_count")))
            (when (equal (second case) "outcome_unknown")
              (is (equal "forbidden" (nth-value 1 (call "messages_resolve" "employee:e" "id" id "outcome" "accepted" "note" "Checked"))))
              (call-ok "messages_resolve" "admin:resolver" "id" id "outcome" "accepted" "note" "Checked receipt")
              (is (equal "admin:resolver" (jget (jget (call-ok "messages_get" "viewer:v" "id" id) "delivery") "resolved_by")))
              (is (find "messages_resolve" (jget (call-ok "audit_list" "viewer:v" "entity_type" "message" "entity_id" id) "items")
                        :test #'equal :key (lambda (row) (jget row "tool")))))))))))

(test slow-provider-does-not-block-send-or-an-unrelated-read
  (with-communication-templates
    (with-test-app ()
      (call-ok "messaging_provider_set" "admin:a" "mode" "slow")
      (let* ((customer (make-customer)) (product (make-product))
             (order (jget (new-order customer "lines" (lines product 1)) "id"))
             (preview (call-ok "messages_preview" "employee:e" "template" "unit_note" "order_id" order))
             (started (get-internal-real-time))
             (message (call-ok "messages_send" "employee:e" "template" "unit_note" "order_id" order
                                "snapshot_hash" (jget preview "snapshot_hash"))))
        (is (< (- (get-internal-real-time) started) internal-time-units-per-second))
        (setf started (get-internal-real-time))
        (is (equal order (jget (call-ok "orders_get" "viewer:v" "id" order) "id")))
        (is (< (- (get-internal-real-time) started) internal-time-units-per-second))
        (loop repeat 80 until (equal "accepted" (jget (jget (call-ok "messages_get" "viewer:v" "id" (jget message "id")) "delivery") "status"))
              do (sleep 0.05))
        (is (equal "accepted" (jget (jget (call-ok "messages_get" "viewer:v" "id" (jget message "id")) "delivery") "status")))))))

(defvar *observed-message-calls* nil)
(defclass observing-message-provider (tun.messaging:fake-message-transport)
  ((observed :initform nil :accessor observed-provider-calls)))
(defmethod tun.messaging:deliver-snapshot :before ((adapter observing-message-provider) request mode call-number)
  (declare (ignore mode call-number))
  (push (list (json-copy request) *transaction-mode* *request-id*) (observed-provider-calls adapter)))

(defclass replenishing-message-provider (tun.messaging:fake-message-transport)
  ((producer :initarg :producer :reader message-producer)
   (calls :initform 0 :accessor replenishing-provider-calls)))

(defmethod tun.messaging:deliver-snapshot :after
    ((adapter replenishing-message-provider) request mode call-number)
  (declare (ignore request mode call-number))
  (when (< (incf (replenishing-provider-calls adapter)) 64)
    (funcall (message-producer adapter) (replenishing-provider-calls adapter))))

(test a-replenished-outbox-yields-to-due-workflows
  (with-communication-templates
    (with-test-app ()
      (let* ((customer (make-customer)) (product (make-product))
             (order (jget (new-order customer "lines" (lines product 1)) "id"))
             (adapter (make-instance 'replenishing-message-provider
                        :producer
                        (lambda (number)
                          (with-transaction (:write)
                            (let* ((entity (tun.orders:find-order order))
                                   (person (fetch 'tun.customers:customer customer))
                                   (snapshot (tun.messaging::render-message-snapshot
                                               "quote" entity person)))
                              (tun.messaging::enqueue-message-snapshot
                                snapshot entity person (format nil "continuous-~d" number))))))))
        (setf (application-message-transport *app*) adapter *pings* 0)
        (with-application (*app*)
          (funcall (message-producer adapter) 0)
          (with-transaction (:write)
            (tun.workflows:schedule-workflow "test_ping" :due-at (now)))
          (application-after-request *app*)
          (wait-for-workers *app*)
          (is (< (replenishing-provider-calls adapter) 64)
              "continuous enqueueing cannot monopolize a scheduler tick")
          (is (= 1 (tun.workflows:run-due-workflows)))
          (is (= 1 *pings*))
          (with-transaction (:read)
            (is (not (null (select 'tun.messaging::delivery :where '(:= "status" "queued"))))))
          (loop repeat 64 until (= 64 (replenishing-provider-calls adapter))
                do (application-after-request *app*) (wait-for-workers *app*))
          (with-transaction (:read)
            (let ((rows (select 'tun.messaging::delivery)))
              (is (= 64 (length rows)))
              (is (every (lambda (row)
                           (and (equal "accepted" (tun.messaging::delivery-status row))
                                (= 1 (tun.messaging::delivery-attempt-count row))))
                         rows)))))))))

(test outbound-snapshots-are-immutable-and-attempted-once-after-commit
  (with-test-app ()
    (let* ((customer (make-customer)) (product (make-product))
           (order (jget (new-order customer "event_date" "2026-06-01" "lines" (lines product 1)) "id")))
      (setf (application-message-transport *app*) (make-instance 'observing-message-provider))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (wait-for-workers *app*)
      (let* ((message (aref (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items") 0))
             (body (jget message "body")) (recipient (json-copy (jget message "recipient"))))
        (is (= 1 (length (observed-provider-calls (application-message-transport *app*)))))
        (is (null (second (first (observed-provider-calls (application-message-transport *app*))))) "provider is outside a transaction")
        (is (null (third (first (observed-provider-calls (application-message-transport *app*))))) "provider is outside the sender request")
        (is (equal "accepted" (jget (jget message "delivery") "status")))
        (is (= 1 (jget (jget message "delivery") "attempt_count")))
        (call-ok "settings_set" "admin:a" "key" "sender.name" "value" "Changed")
        (call-ok "products_update" "employee:anna" "id" product "name" "Changed product")
        (let ((again (call-ok "messages_get" "viewer:v" "id" (jget message "id"))))
          (is (equal body (jget again "body")))
          (is (equal (to-json-string recipient) (to-json-string (jget again "recipient"))))
          (is (equal "Tun" (jget (jget again "sender") "name"))))
        (call-ok "clock_set" "admin:a" "now" "2026-03-01T09:05:01Z")
        (is (= 1 (length (observed-provider-calls (application-message-transport *app*))))) "watchdog and further requests never resend"
        (is (equal "accepted" (jget (jget (call-ok "messages_get" "viewer:v" "id" (jget message "id")) "delivery") "status")))))))

(test composer-unicode-limits-count-graphemes-and-bytes
  (is (= 0 (message-grapheme-count "")))
  (is (= 1 (message-grapheme-count (format nil "a~c" (code-char #x301)))))
  (is (= 1 (message-grapheme-count "👨‍👩‍👧‍👦")))
  (is (= 25 (utf8-byte-count "👨‍👩‍👧‍👦"))))

(test slice2-staff-recipients-retain-their-storage-and-survive-restart
  (with-test-app (:db (scratch-path "legacy-staff-recipient"))
    (let ((id nil) (db (tun.store.sqlite:sqlite-store-path (application-store *app*))))
      (with-application (*app*) (with-transaction (:write)
        (setf id (entity-id (insert (make-instance 'tun.messaging:message :template "stock_alert"
                     :employee-id "emp_legacy" :recipient "admin:lager" :subject "Warehouse"
                     :body "Already delivered" :status "sent" :scheduled-at (now) :created-at (now)))))
        (is (equal "admin:lager" (caar (tun.store.sqlite::query "SELECT recipient FROM messages WHERE id = ?" id))))))
      (tun.runtime:close-application *app*)
      (setf *app* (tun.runtime:open-application 'application :db db :test-clock t))
      (let ((item (call-ok "messages_get" "viewer:v" "id" id)))
        (is (equal "admin:lager" (jget item "recipient")))
        (is (equal "Already delivered" (jget item "body")))))))

(test restart-after-provider-receipt-does-not-repeat-the-attempt
  (with-communication-templates
    (with-test-app (:db (scratch-path "outbox-receipt-cut"))
      (let* ((customer (make-customer)) (product (make-product))
             (order (jget (new-order customer "lines" (lines product 1)) "id"))
             (message-id nil)
             (db (tun.store.sqlite:sqlite-store-path (application-store *app*))))
        (with-application (*app*)
          (with-transaction (:write)
            (let* ((entity (tun.orders:find-order order)) (person (fetch 'tun.customers:customer customer))
                   (snapshot (tun.messaging::render-message-snapshot "unit_note" entity person :manual t)))
              (setf message-id (entity-id (tun.messaging::enqueue-message-snapshot snapshot entity person "receipt-cut")))))
          (multiple-value-bind (row mode calls) (progn (wait-for-workers *app*) (tun.messaging::claim-outbox-delivery))
            (is (equal "accepted" (tun.messaging:deliver-snapshot (make-instance 'tun.messaging:fake-message-transport)
                   (jobj "delivery_id" (entity-id row)) mode calls)))))
        ;; The provider answered, but its result was never committed.
        (tun.runtime:close-application *app*)
        (setf *app* (tun.runtime:open-application 'application :db db :test-clock t))
        (let ((delivery (jget (call-ok "messages_get" "viewer:v" "id" message-id) "delivery")))
          (is (equal "outcome_unknown" (jget delivery "status")))
          (is (equal "unknown_provider_outcome" (jget delivery "error_code")))
          (is (= 1 (jget delivery "attempt_count"))))
        (call-ok "clock_set" "admin:a" "now" "2026-03-01T09:05:01Z")
        (is (= 1 (jget (call-ok "messaging_provider_get" "admin:a") "calls")))))))

(test erasure-scrubs-outbound-and-inbound-content-and-keeps-the-delivery
  (with-communication-templates
    (with-test-app ()
      (let* ((customer (make-customer)) (product (make-product))
             (order (jget (new-order customer "lines" (lines product 1)) "id")))
        (call-ok "orders_send_quote" "employee:e" "id" order)
        (let* ((message (aref (jget (call-ok "messages_list" "viewer:v" "order_id" order) "items") 0))
               (mail (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "customer@example.no"
                                    "subject" (format nil "Reply [ref:~a]" order) "body" "Private reply") "inquiry")))
          (two-step "orders_cancel" "employee:e" "id" order)
          (two-step "customers_erase" "admin:a" "id" customer)
          (let ((scrubbed (call-ok "messages_get" "viewer:v" "id" (jget message "id"))))
            (is (equal "[slettet]" (jget scrubbed "body")))
            (is (equal "[slettet]" (jget (jget scrubbed "recipient") "email")))
            (is (equal "accepted" (jget (jget scrubbed "delivery") "status"))))
          (is (equal "[slettet]" (jget (call-ok "inquiries_get" "employee:e" "id" (jget mail "id")) "body")))
          (is (equal "invalid_input" (nth-value 1 (call "messages_preview" "employee:e" "template" "unit_note" "order_id" order)))))))))

(test quote-expiry-is-stored-keyed-and-notified-once
  (with-test-app ()
    (call-ok "employees_create" "admin:a" "name" "Admin" "actor" "admin:a" "role" "admin")
    (let* ((customer (make-customer)) (product (make-product))
           (order (jget (new-order customer "lines" (lines product 1)) "id")))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (wait-for-workers *app*)
      (let* ((quote (call-ok "quotes_get" "admin:a" "order_id" order))
             (id (jget quote "id")))
        (call-ok "clock_set" "admin:a" "now" (jget quote "expires_at"))
        (with-application (*app*)
          (with-transaction (:read)
            (is (equal "expired" (field-value (fetch 'tun.orders:order-quote id)
                                               (find-field 'tun.orders:order-quote "status"))))))
        (let ((rows (jget (call-ok "workflows_list" "viewer:v" "kind" "quote_expiry") "items")))
          (is (equal '("cancelled" "executed") (map 'list (lambda (wf) (jget wf "status")) rows)))
          (is (every (lambda (wf) (eq :null (jget wf "order_id"))) rows)))
        (let ((rows (jget (call-ok "notifications_list" "admin:a") "items")))
          (is (= 1 (count "quote_expired" rows :test #'equal :key (lambda (n) (jget n "type")))))
          (is (equal (format nil "The quote for order ~a has expired." order) (jget (aref rows 0) "text"))))
        (is (equal "conflict" (nth-value 1 (call "quotes_respond" "viewer:v" "quote_id" id "revision" 2
                                                  "access_code" (jget quote "access_code") "response" "accept"))))))))

(test calendar-month-shifts-clamp-before-the-next-shift
  (is (equal "2029-02-28" (date-add-months "2028-02-29" 12)))
  (is (equal "2028-11-28" (date-add-months (date-add-months "2028-02-29" 12) -3)))
  (is (equal "2026-02-28" (date-add-months "2026-01-31" 1)))
  (is (equal "2025-12-31" (date-add-months "2026-01-31" -1))))

(test public-offers-use-a-session-gate-and-a-revision-bound-proof
  (with-test-server (port)
    (let* ((customer (make-customer)) (product (make-product))
           (order (jget (new-order customer "lines" (lines product 1)) "id"))
           (jar (make-instance 'drakma:cookie-jar)))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (wait-for-workers *app*)
      (let* ((quote (call-ok "quotes_get" "admin:a" "order_id" order))
             (path (format nil "/offer/~a" (jget quote "id"))))
        (multiple-value-bind (status body headers) (web-request port path :jar jar)
          (is (= 200 status)) (is (search "name=\"code\"" body))
          (is (not (search (jget quote "access_code") body)))
          (is (equal "no-referrer" (cdr (assoc :referrer-policy headers)))))
        (dotimes (i 6)
          (is (= (if (= i 5) 429 422)
                 (web-request port (concatenate 'string path "/open") :jar jar :method :post :parameters '(("code" . "WRONG"))))))
        (multiple-value-bind (status body)
            (web-request port (concatenate 'string path "/open") :jar jar :method :post
                         :parameters (list (cons "code" (jget quote "access_code"))))
          (is (= 200 status)) (is (not (search (jget quote "access_code") body)))
          (multiple-value-bind (match groups) (cl-ppcre:scan-to-strings "name=\"proof\" value=\"([^\"]+)\"" body)
            (is (not (null match)))
            (let ((proof (aref groups 0)))
              (call-ok "orders_send_quote" "employee:anna" "id" order)
              (is (= 409 (web-request port (concatenate 'string path "/respond") :jar jar :method :post
                                     :parameters (list (cons "proof" proof) (cons "response" "accept"))))))))))))

(test the-offer-page-is-in-the-tenants-language
  ;; spec/i18n.md 2.3: a customer's page is in the tenant's language, with
  ;; its dates and amounts as Norwegian writes them, and no text missing.
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "locale.language" "value" "nb")
    (call-ok "settings_set" "admin:a" "key" "locale.currency" "value" "NOK")
    (let* ((missing '())
           (lock (sb-thread:make-mutex :name "missing texts"))
           (customer (make-customer)) (product (make-product))
           (order (jget (new-order customer "event_date" "2026-06-01" "lines" (lines product 1))
                        "id"))
           (jar (make-instance 'drakma:cookie-jar)))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (wait-for-workers *app*)
      (let* ((quote (call-ok "quotes_get" "admin:a" "order_id" order))
             (path (format nil "/offer/~a" (jget quote "id"))))
        ;; The page is written in the server's threads: the hook is set, not bound.
        (setf *missing-translation-hook*
              (lambda (language source context)
                (declare (ignore language))
                (sb-thread:with-mutex (lock)
                  (pushnew (list source context) missing :test #'equal))))
        (unwind-protect
             (progn
               (multiple-value-bind (status body) (web-request port path :jar jar)
                 (is (= 200 status))
                 (is (search "Tilbud fra" body) "~a" body)
                 (is (search "Koden står i e-posten med tilbudet" body)))
               (multiple-value-bind (status body)
                   (web-request port (concatenate 'string path "/open") :jar jar :method :post
                                :parameters (list (cons "code" (jget quote "access_code"))))
                 (is (= 200 status))
                 (dolist (text '("Dette er inkludert" "Gyldig til" "01.06.2026" "Godta tilbudet"
                                 "Avslå tilbudet" "Totalt" "kr"))
                   (is (search text body) "the offer page has ~s: ~a" text body)))
               (is (= 422 (web-request port (concatenate 'string path "/open") :jar jar
                                       :method :post :parameters '(("code" . "WRONG"))))))
          (setf *missing-translation-hook* nil))
        (is (null missing) "the offer page has no Norwegian for ~s" missing)))))

(test public-feedback-and-unsubscribe-are-subject-bound-and-audited
  (with-test-server (port)
    (let* ((customer (make-customer)) (product (make-product))
           (order (jget (new-order customer "event_date" "2026-06-01" "lines" (lines product 1)) "id"))
           (feedback (with-application (*app*) (with-transaction (:read) (link-token "tilbakemelding" order))))
           (unsubscribe (with-application (*app*) (with-transaction (:read) (link-token "avmeld" customer))))
           (reminder (with-application (*app*) (with-transaction (:write)
                       (entity-id (insert (make-instance 'tun.workflows:workflow
                                      :kind "quote_reminder" :order-id order :due-at (+ (now) 3600))))))))
      (is (= 404 (web-request port (format nil "/unsubscribe/~a" feedback))))
      (is (= 422 (web-request port (format nil "/feedback/~a" feedback) :method :post :parameters '(("message" . " ")))))
      (is (= 200 (web-request port (format nil "/feedback/~a" feedback) :method :post :parameters '(("message" . "Thanks <&>")))))
      (let ((workflow (call-ok "workflows_get" "viewer:v" "id" reminder)))
        (is (equal "cancelled" (jget workflow "status")))
        (is (equal "the customer has replied" (jget workflow "note"))))
      (let ((request (aref (jget (call-ok "inquiries_list" "employee:e" "kind" "feedback") "items") 0)))
        (is (equal "reference" (jget request "match")))
        (is (equal order (jget request "order_id")))
        (is (equal customer (jget request "customer_id")))
        (is (equal (format nil "customer:~a" customer)
                   (jget (aref (jget (call-ok "audit_list" "viewer:v" "entity_type" "inquiry" "entity_id" (jget request "id")) "items") 0) "actor"))))
      (dotimes (i 2) (is (= 200 (web-request port (format nil "/unsubscribe/~a" unsubscribe) :method :post))))
      (is (equal "unsubscribe" (jget (call-ok "customers_get" "viewer:v" "id" customer) "consent_source")))
      (call-ok "settings_set" "admin:a" "key" "links.secret" "value" "rotated-public-link-secret")
      (is (= 404 (web-request port (format nil "/unsubscribe/~a" unsubscribe))))
      (is (= 404 (web-request port (format nil "/feedback/~a" feedback)))))))

(test the-customers-pages-and-an-erased-name-are-in-the-tenants-language
  ;; spec/i18n.md 3.5, 3.7: the unsubscribe page and the customer list on a
  ;; Norwegian tenant, with every text of the customers module translated.
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "locale.language" "value" "nb")
    (let* ((customer (make-customer))
           (token (with-application (*app*)
                    (with-transaction (:read) (link-token "avmeld" customer))))
           (path (format nil "/unsubscribe/~a" token))
           (missing '())
           (old-hook *missing-translation-hook*))
      (setf *missing-translation-hook*
            (lambda (language source context)
              (declare (ignore language))
              (push (list source context) missing)))
      (unwind-protect
           (progn
             (let ((body (nth-value 1 (web-request port path))))
               (is (search "Meld meg av" body))
               (is (search "Du får ikke lenger tilbud og nyheter på e-post fra oss." body))
               (is (search "lang=\"nb\"" body)))
             (is (search "Du er avmeldt." (nth-value 1 (web-request port path :method :post))))
             (multiple-value-bind (status body) (web-request port "/unsubscribe/UKJENT")
               (is (= 404 status))
               (is (search "Siden finnes ikke" body))
               (is (search "Kontroller lenken i e-posten." body)))
             (is (search "Kunder" (nth-value 1 (web-request port "/customers"
                                                            :jar (web-login port "employee:e"))))))
        (setf *missing-translation-hook* old-hook))
      (let ((customers-texts (loop for (source nil owner) in (known-texts)
                                   when (equal owner "customers") collect source)))
        (is (null (remove-if-not (lambda (miss) (member (first miss) customers-texts :test #'equal))
                                 missing))
            "no text of the customers module lacks Norwegian: ~s" missing))
      (is (eql 0 (search "Slettet kunde "
                         (jget (two-step "customers_erase" "admin:a" "id" customer) "name")))
          "the placeholder name is stored in the tenant's language"))))

(test staff-inbox-filter-and-question-section-use-the-operation-results
  (with-test-server (port)
    (let* ((one (call-ok "inbound_mail_receive" "admin:a" "from_email" "first@example.no" "subject" "Keep new" "body" "Unprocessed text"))
           (two (call-ok "inbound_mail_receive" "admin:a" "from_email" "other@example.no" "subject" "Dismissed subject" "body" "Dismissed text"))
           (jar (web-login port "employee:e")))
      (declare (ignore one))
      (call-ok "inquiries_handle" "employee:e" "id" (jget (jget two "inquiry") "id") "action" "dismiss")
      (multiple-value-bind (status body) (web-request port "/inquiries?status=dismissed" :jar jar)
        (is (= 200 status)) (is (search "Dismissed subject" body))
        (is (not (search "Keep new" body)) "~a" body))
      (let* ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
        (with-application (*app*) (with-transaction (:write)
          (tun.orders:record-order-request order "hen_example" '("Question one?" "Question two?"))))
        (multiple-value-bind (status body) (web-request port (format nil "/orders/~a" order) :jar jar)
          (is (= 200 status)) (is (search "Question one?" body) "~a" body) (is (search "Question two?" body) "~a" body))))))

(defclass rejected-inbox-draft () ())
(defclass rejected-inbox-app (rejected-inbox-draft application) ())
(defmethod tun.inbox:request-defaults ((app rejected-inbox-draft) item)
  (declare (ignore item))
  (jobj "customer" (jobj "name" (make-string 121 :initial-element #\x)) "lines" #() "questions" #()))
(defclass refused-assignment-publication () ())
(defclass publication-failure-app (refused-assignment-publication application) ())
(defmethod tun.staffing:assignment-created :after ((app refused-assignment-publication) item)
  (declare (ignore item))
  (fail :invalid-input "publication failed"))

(test consent-is-explicit-durable-and-audited
  (with-test-app ()
    (let* ((without (make-customer "No Consent"))
           (with (call-ok "customers_create" "employee:anna" "name" "Consent" "email" "yes@example.no"
                          "marketing_consent" t)))
      (is (null (jget (call-ok "customers_get" "viewer:v" "id" without) "marketing_consent")))
      (is (equal "manual" (jget with "consent_source")))
      (is (stringp (jget with "consent_at")))
      (is (equal "forbidden" (nth-value 1 (call "customers_set_consent" "viewer:v" "id" without
                                               "marketing_consent" t "source" "manual"))))
      (let ((withdrawn (call-ok "customers_set_consent" "employee:anna" "id" (jget with "id")
                                "marketing_consent" nil "source" "email")))
        (is (null (jget withdrawn "marketing_consent")))
        (is (= 2 (jget withdrawn "revision")))
        (let ((audit (jget (call-ok "audit_list" "viewer:v" "entity_type" "customer"
                                   "entity_id" (jget with "id")) "items")))
          (is (equal "email" (jget (aref audit 0) "reason"))))))))

(test erasure-refuses-open-orders-and-anonymises-closed-quotes
  (with-test-app ()
    (let* ((customer (make-customer "Erase Person")) (product (make-product))
           (order (call-ok "orders_create" "employee:anna" "customer_id" customer "lines" (lines product 1)))
           (id (jget order "id")))
      (advance-to-accepted id)
      (is (equal "conflict" (nth-value 1 (two-step "customers_erase" "admin:ada" "id" customer))))
      (is (not (jget (call-ok "customers_get" "viewer:v" "id" customer) "erased")))
      (two-step "orders_cancel" "employee:anna" "id" id)
      (let ((erased (two-step "customers_erase" "admin:ada" "id" customer)))
        (is (jget erased "erased"))
        (is (null (jget erased "marketing_consent")))
        (is (search "@slettet.local" (jget erased "email")))
        (is (eq :null (jget erased "phone")))
        (is (eq :null (jget erased "notes")))
        (is (equal "[erased]" (jget (jget (call-ok "quotes_get" "admin:ada" "order_id" id) "snapshot") "customer_name")))
        (is (equal "invalid_input" (nth-value 1 (call "customers_set_consent" "admin:ada" "id" customer
                                                     "marketing_consent" t "source" "manual"))))))))

(test inbox-deduplication-and-draft-failure-retention
  (with-test-app (:class 'rejected-inbox-app)
    (let* ((args (list "from_email" "new@example.no" "subject" "Request" "body" "Hello" "message_ref" "<one>"))
           (first (apply #'call-ok "inbound_mail_receive" "admin:ada" args))
           (item (jget first "inquiry"))
           (second (apply #'call-ok "inbound_mail_receive" "admin:ada" args)))
      (is (equal "new" (jget item "status")))
      (is (eq :null (jget item "customer_id")))
      (is (eq :null (jget item "created_order_id")))
      (is (stringp (jget item "note")))
      (is (jget second "duplicate"))
      (is (equal (jget item "id") (jget (jget second "inquiry") "id")))
      (is (= 0 (length (jget (call-ok "customers_list" "viewer:v") "items"))))
      (is (= 1 (length (jget (call-ok "inquiries_list" "employee:anna") "items"))))
      (is (equal "forbidden" (nth-value 1 (apply #'call "inbound_mail_receive" "employee:anna" args))))
      (is (equal "invalid_input" (nth-value 1 (call "inquiries_create" "viewer:v" "name" "New"
                               "email" "contact@example.no" "message" "Hello" "marketing_consent" nil)))))))

(test notifications-are-private-idempotent-and-monotonic
  (with-test-app ()
    (make-employee "Ada" :role "admin")
    (make-employee "Anna")
    (with-application (*app*)
      (with-transaction (:write)
        (tun.notifications:publish-notification "event" "one" "A notification" "/orders/one" "order" "one")
        (tun.notifications:publish-notification "event" "one" "A notification" "/orders/one" "order" "one")))
    (let* ((mine (jget (call-ok "notifications_list" "admin:ada") "items"))
           (id (jget (aref mine 0) "id")))
      (is (= 1 (length mine)))
      (is (= 0 (length (jget (call-ok "notifications_list" "employee:anna") "items"))))
      (is (= 0 (length (jget (call-ok "notifications_list" "admin:other") "items"))))
      (is (equal "not_found" (nth-value 1 (call "notifications_mark_read" "admin:other" "id" id))))
      (let ((read (call-ok "notifications_mark_read" "admin:ada" "id" id)))
        (call-ok "clock_set" "admin:ada" "now" "2026-03-01T10:00:00Z")
        (is (equal (jget read "read_at") (jget (call-ok "notifications_mark_read" "admin:ada" "id" id) "read_at"))))
      (is (= 0 (jget (call-ok "notifications_unread_count" "admin:ada") "count"))))))

(test failed-publication-rolls-back-the-trigger-and-its-notification
  (with-test-app (:class 'publication-failure-app)
    (let* ((customer (make-customer)) (product (make-product)) (employee (make-employee "Anna"))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "lines" (lines product 1)) "id")))
      (is (equal "invalid_input" (nth-value 1 (call "assignments_create" "admin:ada" "order_id" order
                                                   "employee_id" (jget employee "id")))))
      (is (= 0 (length (jget (call-ok "assignments_list" "viewer:v" "order_id" order) "items"))))
      (is (= 0 (length (jget (call-ok "notifications_list" "employee:anna") "items")))))))

(define-workflow communication-failure (:kind "test_communication_failure" :debug t) (wf)
  (declare (ignore wf))
  (fail :invalid-input "kunde.navn mangler"))

(test workflow-request-ids-policy-and-failure-are-inspectable
  (with-test-app ()
    (with-application (*app*) (with-transaction (:write)
      (tun.workflows:schedule-workflow "test_communication_failure" :due-at (now) :key "failure:one")))
    (call-ok "clock_set" "admin:ada" "now" "2026-03-01T09:00:00Z")
    (let* ((wf (aref (jget (call-ok "workflows_list" "viewer:v" "kind" "test_communication_failure") "items") 0))
           (request (call-ok "introspect_request" "admin:ada" "request_id" (jget wf "request_id"))))
      (is (equal "failed" (jget wf "status")))
      (is (equal "system:workflow" (jget request "actor")))
      (is (equal "workflow:test_communication_failure" (jget request "tool")))
      (is (equal "error" (jget request "outcome")))
      (dolist (kind '("policy" "operation" "rollback"))
        (is (find-by "kind" kind (jget request "steps")))))))

;;; ------------------------------------------------------------------
;;; A Norwegian tenant (spec/i18n.md 3.5, 8): the modules' pages, the
;;; messages they render and the notes and notifications they store are in
;;; Norwegian, and each text they look up has its translation.

(defun call-collecting-misses (owners function)
  "Call FUNCTION and return the texts of OWNERS (module names) looked up in
the meantime with no translation, as (SOURCE CONTEXT).  The hook is set for
every thread, since the server and the outbox work in their own."
  (let ((owned (make-hash-table :test 'equal))
        (misses '())
        (lock (sb-thread:make-mutex :name "missing translations"))
        (previous *missing-translation-hook*))
    (loop for (source nil owner) in (known-texts)
          when (member owner owners :test #'equal)
            do (setf (gethash source owned) t))
    (setf *missing-translation-hook*
          (lambda (language source context)
            (declare (ignore language))
            (when (gethash source owned)
              (sb-thread:with-mutex (lock)
                (pushnew (list source context) misses :test #'equal)))))
    (unwind-protect (funcall function)
      (setf *missing-translation-hook* previous))
    misses))

(defun norwegian-page (port path jar)
  "The body of PATH, which must answer 200, with its no-break spaces as spaces."
  (multiple-value-bind (status body) (web-request port path :jar jar)
    (is (= 200 status) "~a answered ~a" path status)
    (substitute #\Space #\No-break_space body)))

(test a-norwegian-tenant-gets-its-messages-and-their-outcomes-in-norwegian
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "locale.language" "value" "nb")
    (make-employee "Ada" :role "admin")
    (let* ((customer (make-customer "Kari Nordmann")) (product (make-product))
           (order (jget (new-order customer "event_date" "2026-06-01" "lines" (lines product 1))
                        "id"))
           (jar (web-login port "admin:ada"))
           (misses
             (call-collecting-misses
              '("messaging")
              (lambda ()
                (call-ok "messaging_provider_set" "admin:a" "mode" "reject")
                (with-application (*app*)
                  (with-transaction (:write)
                    (tun.messaging:send-message "quote" :order (tun.orders:find-order order)
                                                :customer (fetch 'tun.customers:customer customer))))
                ;; A request's end starts the outbox, which writes the outcome.
                (call-ok "messaging_provider_get" "admin:a")
                (wait-for-workers *app*)
                (let ((quote (find-by "template" "quote"
                                      (jget (call-ok "messages_list" "viewer:v" "order_id" order)
                                            "items"))))
                  (is (equal 0 (search "Tilbud [ref:" (jget quote "subject"))))
                  (is (search "Hei Kari Nordmann, her er tilbudet ditt:" (jget quote "body")))
                  (is (equal "E-postleverandøren avviste meldingen. Kontroller mottaker og innhold."
                             (jget (jget quote "delivery") "safe_error_message"))))
                (is (equal "En e-post til Kari Nordmann kunne ikke sendes."
                           (jget (aref (jget (call-ok "notifications_list" "admin:ada") "items") 0)
                                 "text")))
                (let ((page (norwegian-page port (format nil "/orders/~a" order) jar)))
                  (dolist (text '("Kommunikasjon" "Kunne ikke sendes" "Ny melding til kunden"
                                  "Du ser meldingen før den legges i kø."))
                    (is (search text page) "the order page lacks ~s" text)))))))
      (is (null misses) "messaging texts with no Norwegian: ~s" misses)
      ;; A machine is answered in source text (spec/i18n.md 7).
      (is (equal "The template does not exist"
                 (jget (jget (call "messages_preview" "employee:e" "template" "missing"
                                   "order_id" order)
                             "error")
                       "message"))))))

(test a-norwegian-tenant-gets-the-inbox-and-its-feedback-page-in-norwegian
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "locale.language" "value" "nb")
    (make-employee "Ada" :role "admin")
    (let* ((jar (web-login port "admin:ada"))
           (order (jget (new-order (make-customer) "event_date" "2026-06-01"
                                   "lines" (lines (make-product) 1))
                        "id"))
           (feedback (with-application (*app*)
                       (with-transaction (:read) (link-token "tilbakemelding" order))))
           (misses
             (call-collecting-misses
              '("inbox")
              (lambda ()
                (let ((inquiry (jget (call-ok "inbound_mail_receive" "admin:a"
                                              "from_email" "ny@example.no" "subject" "Leie av telt"
                                              "body" "Hei")
                                     "inquiry")))
                  (is (equal "Du har fått en ny henvendelse."
                             (jget (aref (jget (call-ok "notifications_list" "admin:ada") "items") 0)
                                   "text")))
                  (let ((page (norwegian-page port "/inquiries" jar)))
                    (dolist (text '("Henvendelser" "Emne" "Mottatt" "Filtrer" "Behandlet"))
                      (is (search text page) "the inbox lacks ~s" text))
                    (is (search ">Ny<" page) "the status's label"))
                  (let ((page (norwegian-page port (format nil "/inquiries/~a" (jget inquiry "id"))
                                              jar)))
                    (dolist (text '("Behandle henvendelsen" "Opprett ordreutkast" "Knytt til ordre"))
                      (is (search text page) "the inquiry's page lacks ~s" text))))
                (let ((contact (call-ok "inquiries_create" "viewer:v" "name" "Kari" "email"
                                        "kari@example.no" "message" "Telt" "event_date" "2027-06-20"
                                        "guests" 42 "marketing_consent" t)))
                  (is (equal "Kontaktskjema" (jget contact "subject")))
                  (is (search "Dato: 20.06.2027" (jget contact "body")))
                  (is (search "Gjester: 42" (jget contact "body"))))
                (let ((path (format nil "/feedback/~a" feedback)))
                  (is (search "Hva tenker du?" (norwegian-page port path nil)))
                  (is (search "Tilbakemeldingen din" (norwegian-page port path nil)))
                  (multiple-value-bind (status body)
                      (web-request port path :method :post :parameters '(("message" . " ")))
                    (is (= 422 status))
                    (is (search "Skriv en melding." body))))))))
      (is (null misses) "inbox texts with no Norwegian: ~s" misses))))

(test a-norwegian-tenant-gets-its-notifications-in-norwegian
  (with-test-server (port)
    (call-ok "settings_set" "admin:a" "key" "locale.language" "value" "nb")
    (make-employee "Ada" :role "admin")
    (let* ((anna (make-employee "Anna"))
           (order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id"))
           (misses
             (call-collecting-misses
              '("notifications")
              (lambda ()
                (call-ok "assignments_create" "admin:ada" "order_id" order
                         "employee_id" (jget anna "id"))
                (is (equal "Du er tildelt en ny oppgave."
                           (jget (aref (jget (call-ok "notifications_list" "employee:anna") "items") 0)
                                 "text")))
                (let ((page (norwegian-page port "/notifications" (web-login port "employee:anna"))))
                  (dolist (text '("Varsler" "Uleste:" "Ulest" "Marker som lest"
                                  "Du er tildelt en ny oppgave."))
                    (is (search text page) "the notifications page lacks ~s" text)))))))
      (is (null misses) "notifications texts with no Norwegian: ~s" misses))))

(test message-links-are-at-the-public-url
  ;; messaging README: quote.link, link.feedback and link.unsubscribe are
  ;; absolute-url of their paths, the path alone without a public URL.
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "unit_links" 'unit-links :source :client :manual t
       :subject "Links" :text "{{quote.link}} {{link.feedback}} {{link.unsubscribe}}")
    (flet ((links (public-url)
             (with-test-app (:public-url public-url)
               (let* ((customer (make-customer)) (product (make-product))
                      (order (jget (new-order customer "lines" (lines product 1)) "id")))
                 (call-ok "orders_send_quote" "employee:anna" "id" order)
                 (wait-for-workers *app*)
                 (values (cl-ppcre:split " " (jget (call-ok "messages_preview" "employee:e"
                                                            "template" "unit_links" "order_id" order)
                                                   "body"))
                         (jget (call-ok "quotes_get" "admin:a" "order_id" order) "id"))))))
      (multiple-value-bind (links quote) (links "https://shop.example")
        (is (equal (format nil "https://shop.example/offer/~a" quote) (first links)))
        (is (string-prefix-p "https://shop.example/feedback/" (second links)))
        (is (string-prefix-p "https://shop.example/unsubscribe/" (third links))))
      (multiple-value-bind (links quote) (links nil)
        (is (equal (format nil "/offer/~a" quote) (first links)))
        (is (string-prefix-p "/feedback/" (second links)))
        (is (string-prefix-p "/unsubscribe/" (third links)))))))
