;;;; tests/review-tests.lisp -- regressions for defects found in review.

(in-package #:tun.tests)

(def-suite review :in core)
(in-suite review)

(test code-inside-a-request-cannot-confirm-for-the-caller
  (with-test-app ()
    (let ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Beskyttet") "id")))
      (is (string= "confirmation_invalid" (nth-value 1 (call "widgets_archive_now" "employee:anna" "id" id))))
      (is (string= "aktiv" (jget (call-ok "widgets_get" "viewer:vera" "id" id) "status")))
      ;; The nested rejection was audited even though the outer call rolled back.
      (let ((entry (find "widgets_archive" (coerce (jget (call-ok "audit_list" "viewer:vera") "items") 'list)
                         :key (lambda (e) (jget e "tool")) :test #'string=)))
        (is (not (null entry)))
        (is (equal (list "rejected" "confirmation_invalid" "widget" id)
                   (list (jget entry "outcome") (jget entry "error_code")
                         (jget entry "entity_type") (jget entry "entity_id")))))
      ;; The ordinary two-step flow across two requests still works.
      (let ((token (jget (call-ok "widgets_archive" "employee:anna" "id" id) "confirmation_token")))
        (is (string= "arkivert" (jget (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token)
                                      "status")))))))

(defclass feature-a () ())
(defclass ordered-app (feature-a application) ())

(defmethod widgets-touch :before ((app application) input) (declare (ignore input)) (push :core-before *touch-log*))
(defmethod widgets-touch :after ((app application) input) (declare (ignore input)) (push :core-after *touch-log*))
(defmethod widgets-touch :before ((app feature-a) input) (declare (ignore input)) (push :feature-before *touch-log*))
(defmethod widgets-touch :after ((app feature-a) input) (declare (ignore input)) (push :feature-after *touch-log*))

(test before-and-after-methods-run-in-the-documented-order
  (with-test-app (:class 'ordered-app)
    (let ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Rekkefølge") "id")))
      (setf *touch-log* '())
      (call-ok "widgets_touch" "employee:anna" "id" id)
      ;; tun-platform.md 2.7: core and the modules first (dependency order),
      ;; the client last, in both phases.
      (is (equal '(:core-before :feature-before :primary :core-after :feature-after)
                 (reverse *touch-log*))
          "core's :before and :after run before the extension's"))))

(test unicode-digits-are-not-dates
  (is (null (parse-date "٢٠٢٦-03-01")))
  (is (null (parse-rfc3339 "٢٠٢٦-03-01T09:00:00Z")))
  (with-test-app ()
    (let ((customer (jget (call-ok "customers_create" "employee:anna" "name" "X" "email" "x@example.no") "id"))
          (machine (jget (call-ok "products_create" "employee:anna" "name" "M" "kind" "rental" "unit" "stk"
                                  "unit_price_minor" 1 "stock_tracked" nil)
                         "id")))
      (is (string= "invalid_input"
                   (nth-value 1 (call "orders_create" "employee:anna" "customer_id" customer
                                      "event_date" "٢٠٢٦-03-01"
                                      "lines" (jarr (list (jobj "product_id" machine "quantity" 1))))))))))

(test rollback-actions-run-when-the-outermost-transaction-fails
  (with-test-app ()
    (with-application (*app*)
      (let ((log '()))
        (ignore-errors
         (with-transaction (:write)
           (on-rollback (lambda () (push :undone log)))
           (error "boom")))
        (is (equal '(:undone) log))
        (setf log '())
        (with-transaction (:write) (on-rollback (lambda () (push :undone log))))
        (is (null log) "nothing to undo after a commit")))))

(test workflow-runs-are-audited-as-the-workflow-actor
  (with-test-app ()
    (plan "test_ping" "2026-03-02T09:00:00Z")
    (plan "test_boom" "2026-03-02T09:00:00Z")
    (call-ok "clock_set" "admin:ada" "now" "2026-03-02T10:00:00Z")
    (let ((entries (coerce (jget (call-ok "audit_list" "viewer:vera" "entity_type" "workflow") "items") 'list)))
      (is (= 2 (length entries)))
      (is (every (lambda (e) (string= "system:workflow" (jget e "actor"))) entries))
      (is (equal '(("workflow:test_boom" "rejected") ("workflow:test_ping" "ok"))
                 (sort (mapcar (lambda (e) (list (jget e "tool") (jget e "outcome"))) entries)
                       #'string< :key #'first))))))

(test post-bodies-need-a-bounded-content-length
  (with-test-server (port)
    (flet ((raw (request)
             (let ((socket (usocket:socket-connect "127.0.0.1" port :element-type '(unsigned-byte 8))))
               (unwind-protect
                    (let ((stream (usocket:socket-stream socket)))
                      (write-sequence (sb-ext:string-to-octets request :external-format :latin-1) stream)
                      (finish-output stream)
                      (let ((line (make-array 12 :element-type '(unsigned-byte 8))))
                        (read-sequence line stream)
                        (sb-ext:octets-to-string line :external-format :latin-1)))
                 (usocket:socket-close socket)))))
      (is (search " 411" (raw (format nil "POST /mcp HTTP/1.1~c~cHost: x~c~cX-Tun-Actor: admin:a~c~cTransfer-Encoding: chunked~c~c~c~c5~c~c{\"a\":~c~c0~c~c~c~c"
                                      #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline
                                      #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline
                                      #\Return #\Newline))))
      (is (search " 413" (raw (format nil "POST /mcp HTTP/1.1~c~cHost: x~c~cContent-Length: 99999999~c~c~c~c"
                                      #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline))))
      ;; Any path: Hunchentoot would otherwise read (and allocate) the declared body.
      (is (search " 413" (raw (format nil "GET /health HTTP/1.1~c~cHost: x~c~cContent-Length: 999999999999~c~c~c~c"
                                      #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline))))
      (is (search " 200" (raw (format nil "GET /health HTTP/1.1~c~cHost: x~c~c~c~c"
                                      #\Return #\Newline #\Return #\Newline #\Return #\Newline)))))))
