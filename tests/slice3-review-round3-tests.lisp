;;;; slice3-review-round3-tests.lisp -- messaging, inbox and notifications rules (their READMEs).
(in-package #:tun.tests)
(def-suite slice3-review-round3 :in core)
(in-suite slice3-review-round3)

(defclass paused-outbox-app (application)
  ((paused :initform t :accessor outbox-paused-p)))
(defmethod application-after-request :around ((app paused-outbox-app))
  (unless (outbox-paused-p app) (call-next-method)))
(defun drain-review-outbox ()
  (with-application (*app*) (tun.messaging::drain-outbox *app*)))
(defun queue-review-message (order template &optional (subject "Queued"))
  (let ((preview (call-ok "messages_preview" "employee:e" "order_id" order "template" template "subject" subject)))
    (jget (call-ok "messages_send" "employee:e" "order_id" order "template" template "subject" subject
                  "snapshot_hash" (jget preview "snapshot_hash")) "id")))
(defun review-delivery (id)
  (jget (call-ok "messages_get" "admin:a" "id" id) "delivery"))

(test s3r3-37-claim-rechecks-consent-and-erasure
  (with-communication-templates
    (dolist (erasure '(nil t))
      (with-test-app (:class 'paused-outbox-app)
        (make-employee "Ada" :role "admin")
        (let* ((customer (make-customer))
               (order (jget (new-order customer "lines" (lines (make-product) 1)) "id")))
          (call-ok "customers_set_consent" "employee:e" "id" customer "marketing_consent" t "source" "manual")
          (let ((message (queue-review-message order (if erasure "unit_note" "unit_marketing"))))
            (is (equal "queued" (jget (review-delivery message) "status")))
            (if erasure
                (progn (two-step "orders_cancel" "employee:e" "id" order)
                       (two-step "customers_erase" "admin:a" "id" customer))
                (call-ok "customers_set_consent" "employee:e" "id" customer "marketing_consent" nil "source" "unsubscribe"))
            (drain-review-outbox)
            (let ((delivery (review-delivery message)))
              (is (equal "failed" (jget delivery "status")))
              (is (equal "suppressed" (jget delivery "error_code")))
              (is (equal "The message was not sent: the customer has withdrawn consent or been erased."
                         (jget delivery "safe_error_message")))
              (is (= 0 (jget delivery "attempt_count"))))
            (is (= 0 (jget (call-ok "messaging_provider_get" "admin:a") "calls")))
            (is (zerop (length (jget (call-ok "notifications_list" "admin:ada") "items"))))
            (is (find "suppressed" (jget (call-ok "audit_list" "admin:a" "entity_type" "message" "entity_id" message) "items")
                      :test #'equal :key (lambda (row) (jget row "error_code"))))))))))

(test s3r3-38-inbound-and-outbound-mask-both-code-representations
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "order_message" 'unit-quoted :source :client :manual t
      :subject "Quoted reply" :text "{{message}}" :variables '("message"))
    (with-test-server (port)
      (let* ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (call-ok "orders_send_quote" "employee:e" "id" order)
      (let* ((raw (jget (call-ok "quotes_get" "admin:a" "order_id" order) "access_code"))
             (dashed (format nil "~a-~a" (subseq raw 0 5) (subseq raw 5)))
             (body (format nil "Quoted ~a and ~a" raw dashed))
             (item (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "reply@example.no"
                           "subject" (format nil "[ref:~a] ~a ~a" order raw dashed) "body" body) "inquiry"))
             (id (jget item "id"))
             (preview (call-ok "messages_preview" "admin:a" "template" "order_message" "order_id" order "text" body))
             (outbound (jget (call-ok "messages_send" "admin:a" "template" "order_message" "order_id" order "text" body
                                    "snapshot_hash" (jget preview "snapshot_hash")) "id")))
        (dolist (actor '("viewer:v" "employee:e"))
          (dolist (json (list (call-ok "messages_get" actor "id" outbound) (call-ok "messages_get" actor "id" id)
                             (call-ok "messages_list" actor "order_id" order)))
            (is (not (search raw (to-json-string json))))
            (is (not (search dashed (to-json-string json))))))
        (dolist (message-id (list id outbound))
          (let ((admin (call-ok "messages_get" "admin:a" "id" message-id)))
            (is (search raw (jget admin "body"))) (is (search dashed (jget admin "body")))))
        (dolist (path (list (format nil "/orders/~a" order) (format nil "/inquiries/~a" id) "/inquiries"))
          (multiple-value-bind (status html) (web-request port path :jar (web-login port "employee:e"))
            (is (= 200 status)) (is (not (search raw html))) (is (not (search dashed html))))))))))

(test s3r3-38-unthreaded-forwarded-codes-are-also-masked
  (with-test-server (port)
    (let ((order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (call-ok "orders_send_quote" "employee:e" "id" order)
      (let* ((raw (jget (call-ok "quotes_get" "admin:a" "order_id" order) "access_code"))
             (dashed (format nil "~a-~a" (subseq raw 0 5) (subseq raw 5)))
             (item (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "forwarded@example.no"
                           "subject" "A forwarded offer without a reference"
                           "body" (format nil "~a ~a" raw dashed)) "inquiry"))
             (id (jget item "id")))
        (dolist (json (list (call-ok "messages_get" "viewer:v" "id" id)
                           (call-ok "messages_list" "employee:e" "kind" "inbound")
                           (call-ok "inquiries_get" "employee:e" "id" id)))
          (is (not (search raw (to-json-string json))))
          (is (not (search dashed (to-json-string json)))))
        (dolist (path (list "/inquiries" (format nil "/inquiries/~a" id)))
          (multiple-value-bind (status html) (web-request port path :jar (web-login port "employee:e"))
            (is (= 200 status)) (is (not (search raw html))) (is (not (search dashed html)))))
        (is (search raw (jget item "body"))) (is (search dashed (jget item "body")))))))

(test s3r3-38-known-code-lookup-is-indexed-and-migration-is-idempotent
  (let ((path (scratch-path "quote-code-index")))
    (dotimes (i 2)
      (declare (ignorable i))
      (with-test-app (:db path)
        (with-application (*app*) (with-transaction (:read)
          (is (search "idx_quotes_access_code" (princ-to-string
                (sqlite:execute-to-list tun.store.sqlite::*connection*
                  "EXPLAIN QUERY PLAN SELECT * FROM quotes WHERE access_code IN (?)" "ABCDEFGHIJ"))))
          (let ((rows (sqlite:execute-to-list tun.store.sqlite::*connection*
                        "SELECT module, migration FROM schema_history WHERE statement LIKE '%idx_quotes_access_code%'")))
            (is (= 1 (length rows)))
            (when rows (is (equal "orders" (caar rows))) (is (search "orders_" (second (first rows))))))))))))

(test s3r3-39-introspection-keeps-notification-ownership
  (with-test-app (:allow-eval t)
    (let* ((employee (make-employee "Anna"))
           (order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (call-ok "assignments_create" "admin:a" "order_id" order "employee_id" (jget employee "id"))
      (let* ((notification (aref (jget (call-ok "notifications_list" "employee:anna") "items") 0))
             (id (jget notification "id")))
        (is (equal "not_found" (nth-value 1 (call "introspect_record" "admin:a" "entity" "notification" "id" id))))
        (is (not (search id (to-json-string (call-ok "introspect_record" "admin:a" "entity" "order" "id" order)))))
        (is (equal "not_found" (nth-value 1 (call "eval" "admin:a" "code"
                  (format nil "(tun.core:fetch! 'tun.notifications:notification ~s)" id)))))
        (is (equal "0" (aref (jget (call-ok "eval" "admin:a" "code"
                            "(length (tun.core:select 'tun.notifications:notification))") "values") 0))))
      (with-application (*app*) (with-transaction (:write)
        (tun.notifications:publish-notification "private" "private-event" "Own admin notification" "/orders" "order" order
          :recipients '("admin:a"))))
      (let ((id (jget (aref (jget (call-ok "notifications_list" "admin:a") "items") 0) "id")))
        (is (equal "Own admin notification" (jget (jget (call-ok "introspect_record" "admin:a" "entity" "notification" "id" id) "stored") "text")))))))

(test s3r3-39-introspection-redacts-erased-content
  (with-test-app ()
    (let* ((customer (make-customer)) (order (jget (new-order customer "lines" (lines (make-product) 1)) "id"))
           (item (jget (call-ok "inbound_mail_receive" "admin:a" "from_email" "reply@example.no"
                       "subject" (format nil "[ref:~a]" order) "body" "Private original message") "inquiry")))
      (two-step "orders_cancel" "employee:e" "id" order)
      (two-step "customers_erase" "admin:a" "id" customer)
      (let ((record (call-ok "introspect_record" "admin:a" "entity" "inquiry" "id" (jget item "id"))))
        (is (equal "[slettet]" (jget (jget record "stored") "body")))
        (is (not (search "Private original message" (to-json-string record))))))))

(defclass held-message-provider (tun.messaging:fake-message-transport)
  ((gate :initform (sb-thread:make-semaphore :count 0) :reader held-provider-gate)
   (lock :initform (sb-thread:make-mutex) :reader held-provider-lock)
   (active :initform 0 :accessor held-provider-active)
   (peak :initform 0 :accessor held-provider-peak)
   (calls :initform 0 :accessor held-provider-calls)))
(defmethod tun.messaging:deliver-snapshot ((adapter held-message-provider) request mode number)
  (declare (ignore request mode))
  (sb-thread:with-mutex ((held-provider-lock adapter))
    (incf (held-provider-calls adapter)) (incf (held-provider-active adapter))
    (setf (held-provider-peak adapter) (max (held-provider-peak adapter) (held-provider-active adapter))))
  (unwind-protect
       (progn (when (<= number 4) (sb-thread:wait-on-semaphore (held-provider-gate adapter)))
              (values "accepted" nil "held-provider-answer"))
    (sb-thread:with-mutex ((held-provider-lock adapter)) (decf (held-provider-active adapter)))))
(defun release-held-provider (adapter)
  (dotimes (i 4) (declare (ignorable i)) (sb-thread:signal-semaphore (held-provider-gate adapter)))
  (loop repeat 200 while (plusp (held-provider-active adapter)) do (sleep .01)))

(test s3r3-40-timeouts-continue-but-abandoned-calls-are-bounded
  (with-communication-templates
    (with-test-app (:class 'paused-outbox-app)
      (let* ((adapter (make-instance 'held-message-provider))
             (order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id"))
             (ids (loop for i below 6 collect (queue-review-message order "unit_note" (format nil "Queued ~d" i)))))
        (setf (application-message-transport *app*) adapter)
        (unwind-protect
             (progn
               (drain-review-outbox)
               (dolist (id (subseq ids 0 4))
                 (is (equal "outcome_unknown" (jget (review-delivery id) "status")))
                 (is (equal "timeout" (jget (review-delivery id) "error_code"))))
               (is (= 4 (held-provider-calls adapter)))
               (is (= 4 (jget (call-ok "messaging_provider_get" "admin:a") "calls")))
               (is (<= (held-provider-peak adapter) 4))
               (dolist (id (subseq ids 4)) (is (equal "queued" (jget (review-delivery id) "status"))))
               (sb-thread:signal-semaphore (held-provider-gate adapter))
               (loop repeat 200 while (= 4 (held-provider-active adapter)) do (sleep .01))
               (drain-review-outbox)
               (dolist (id (subseq ids 4)) (is (equal "accepted" (jget (review-delivery id) "status"))))
               (is (<= (held-provider-peak adapter) 4))
               (is (equal "outcome_unknown" (jget (review-delivery (first ids)) "status"))))
          (release-held-provider adapter))))))

(test s3r3-40-shutdown-is-bounded-by-one-provider-deadline
  (with-communication-templates
    (with-test-app (:class 'paused-outbox-app)
      (let* ((adapter (make-instance 'held-message-provider))
             (order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
        (dotimes (i 6) (queue-review-message order "unit_note" (format nil "Closing ~d" i)))
        (setf (application-message-transport *app*) adapter)
        (unwind-protect
             (progn
               (let ((app *app*))
                 (with-application (app) (start-worker (lambda () (tun.messaging::drain-outbox app)) "shutdown probe")))
               (loop repeat 200 until (plusp (held-provider-calls adapter)) do (sleep .01))
               (let ((started (get-internal-real-time)))
                 (tun.runtime:close-application *app*)
                 (is (< (/ (- (get-internal-real-time) started) internal-time-units-per-second) 4.5)))
               (is (= 1 (held-provider-calls adapter))))
          (release-held-provider adapter))))))

(test s3r3-41-overlapping-http-routes-are-refused
  (dolist (paths '(("round3" "/round3") ("round3" "/round3/more") ("round3/more" "/round3")))
    (let ((tun.web::*public-pages* (make-hash-table :test 'equal))
          (tun.http::*json-endpoints* (make-hash-table :test 'equal)))
      (signals extension-error
        (let ((*package* (find-package "TUN.CUSTOMERS")))
          (tun.web:register-public-page (first paths) 'identity)
          (let ((*package* (find-package "TUN.NOTIFICATIONS")))
            (tun.http:register-json-endpoint (second paths) 'identity))
          (with-test-app () nil))))))

(test routes-overlap-by-whole-path-parts
  (is (tun.web::route-within-p "/log" "/log"))
  (is (tun.web::route-within-p "/log" "/log/req_1"))
  (is (not (tun.web::route-within-p "/log" "/login")) "/log and /login are two routes")
  (is (not (tun.web::route-within-p "/log/req_1" "/log"))))

(test s3r3-42-unicode-postcode-boundaries-and-signoffs
  (is (equal '("2040" "7010") (tun.inbox::request-postcodes "😀2040☃ _7010_")))
  (dolist (text '("Å2040" "2040中" "٤2040" "2040٤" "20.06.2027" "2027-06-20"))
    (is (null (tun.inbox::request-postcodes text))))
  (is (equal '("٢٠٤٠") (tun.inbox::request-postcodes "😀٢٠٤٠😀")))
  (is (tun.inbox::request-text-matches-p "\\d+\\s*gjester" (format nil "٤٢~c~cgjester" #\Return #\Newline)))
  (dolist (signoff '("Hilsen—" "mvh؛" "Vennlig hilsen…" "Med vennlig hilsen！？"))
    (let ((item (make-instance 'tun.inbox:inquiry :from-email "fallback@example.no"
                              :body (format nil "Hello~%~a~c~cUnicode Person" signoff #\Return #\Newline))))
      (is (equal "Unicode Person" (tun.inbox::request-name item))))))

(test s3r3-43-every-module-readme-states-its-current-core-range
  (dolist (module (all-modules))
    (let ((text (file-text (merge-pathnames "README.md" (asdf:system-source-directory (format nil "tun-~a" (module-name module)))))))
      (dolist (constraint (module-core-range module))
        (is (search constraint text) "~a README must state ~a" (module-name module) constraint)))))

(test s3r3-42-signoffs-ignore-unicode-dashes-outside-punctuation
  (dolist (code '(#x2212 #x207b #x208b))
    (let ((item (make-instance 'tun.inbox:inquiry :from-email "fallback@example.no"
                  :body (format nil "Hilsen~c~%Ada Example" (code-char code)))))
      (is (equal "Ada Example" (tun.inbox::request-name item))))))

(test s3r3-39-eval-store-ports-preserve-notification-ownership
  (with-test-app (:allow-eval t)
    (let* ((employee (make-employee "Anna"))
           (order (jget (new-order (make-customer) "lines" (lines (make-product) 1)) "id")))
      (call-ok "assignments_create" "admin:a" "order_id" order "employee_id" (jget employee "id"))
      (let ((id (jget (aref (jget (call-ok "notifications_list" "employee:anna") "items") 0) "id")))
        (is (equal "0" (aref (jget (call-ok "eval" "admin:a" "code"
                     (format nil "(if (tun.core:store-find tun.core:*store* 'tun.notifications:notification ~s) 1 0)" id)) "values") 0)))
        (is (equal "0" (aref (jget (call-ok "eval" "admin:a" "code"
                     "(length (tun.core:store-select tun.core:*store* 'tun.notifications:notification))") "values") 0)))))))
