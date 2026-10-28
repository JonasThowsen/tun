;;;; tests/introspection-tests.lisp -- core.md §8: request identity and
;;;; retention (12.1), the introspection tools and eval (12.2), and what a
;;;; stalled accounting port and a stored balance edited outside the ledger
;;;; look like through them.

(in-package #:tun.tests)

(def-suite introspection :in core)
(in-suite introspection)

(defclass live-patch-test-app (application) ())
(defun live-patch-test-value () 1)
(defgeneric live-patch-test-computed (app))
(defmethod live-patch-test-computed ((app live-patch-test-app)) 1)

(test live-patches-identify-function-and-method-replacement-once
  (with-test-app (:class 'live-patch-test-app :debug-tools t)
    (let* ((original (symbol-function 'live-patch-test-value))
           (generic (symbol-function 'live-patch-test-computed))
           (method (first (closer-mop:generic-function-methods generic))))
      (unwind-protect
          (progn
            (is (= 0 (length (jget (call-ok "introspect_runtime" "admin:a") "live_patches"))))
            (setf (symbol-function 'live-patch-test-value) (compile nil '(lambda () 2)))
            (eval '(defmethod live-patch-test-computed ((app live-patch-test-app)) 2))
            (let ((patches (jget (call-ok "introspect_runtime" "admin:a") "live_patches")))
              (is (= 2 (length patches)))
              (is (every (lambda (patch) (and (stringp (jget patch "symbol"))
                                             (stringp (jget patch "time")))) patches))
              (is (= 64 (length (jget (find "TUN.TESTS:LIVE-PATCH-TEST-VALUE" (coerce patches 'list)
                                           :test #'equal :key (lambda (p) (jget p "symbol"))) "source_hash"))))
              (is (= 2 (length (jget (call-ok "introspect_runtime" "admin:a") "live_patches"))))))
        (setf (symbol-function 'live-patch-test-value) original)
        (remove-method generic (first (closer-mop:generic-function-methods generic)))
        (add-method generic method)))))

(defun mcp-post (port actor payload)
  "POST a JSON-RPC PAYLOAD (a jobj) to /mcp: values status, parsed body (or NIL), the request id header."
  (multiple-value-bind (status body headers) (http-post port "/mcp" (to-json-string payload) :actor actor)
    (values status (and (plusp (length body)) (parse-json body))
            (cdr (assoc :x-tun-request-id headers)))))

(defun http-tool (port actor tool arguments)
  "Values: the tools/call result object, the header request id."
  (multiple-value-bind (status json rid)
      (mcp-post port actor (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/call"
                                 "params" (jobj "name" tool "arguments" arguments)))
    (declare (ignore status))
    (values (jget json "result") rid)))

(defun trace-of (rid) (call-ok "introspect_request" "admin:ada" "request_id" rid))
(defun step-kinds (trace) (map 'list (lambda (s) (jget s "kind")) (jget trace "steps")))
(defun recent (kind &rest more) (coerce (jget (apply #'call-ok "introspect_recent" "admin:ada" "kind" kind more) "items") 'list))

;;; core.md §8.1 Request identity and retention

(test i-every-response-carries-a-request-id
  (with-test-server (port)
    (let ((ids '()))
      (multiple-value-bind (status json rid) (mcp-post port "viewer:vera" (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/list"))
        (is (= 200 status)) (is (jget json "result")) (is (stringp rid)) (push rid ids))
      (multiple-value-bind (status json rid) (mcp-post port nil (jobj "jsonrpc" "2.0" "id" 2 "method" "tools/list"))
        (declare (ignore status))
        (is (jget json "error") "no actor: a JSON-RPC error") (is (stringp rid) "it still has an id") (push rid ids))
      (multiple-value-bind (status json rid) (mcp-post port "viewer:vera" (jobj "jsonrpc" "2.0" "method" "notifications/initialized"))
        (is (= 202 status)) (is (null json)) (is (stringp rid)) (push rid ids))
      (multiple-value-bind (result rid) (http-tool port "employee:anna" "widgets_create" (jobj "name" "Med id"))
        (is (equal rid (jget (jget result "_meta") "request_id")) "_meta.request_id is the header's id")
        (push rid ids))
      (multiple-value-bind (result rid) (http-tool port "viewer:vera" "widgets_create" (jobj "name" "Nei"))
        (is (eq t (jget result "isError")))
        (is (equal rid (jget (jget result "_meta") "request_id")) "an error result carries it too")
        (push rid ids))
      (is (= (length ids) (length (remove-duplicates ids :test #'string=))) "ids are unique")
      (is (stringp (cdr (assoc :x-tun-request-id (nth-value 2 (web-request port "/health")))))
          "/health too"))))

(test i-every-mcp-request-is-retained-with-its-trace
  (with-test-server (port :db (scratch-path "trace"))
    (multiple-value-bind (result rid)
        (http-tool port "employee:anna" "widgets_create" (jobj "name" "Sporet" "request_key" "k1"))
      (is (null (jget result "isError")))
      (let ((trace (trace-of rid)))
        (is (equal rid (jget trace "request_id")))
        (is (string= "widgets_create" (jget trace "tool")))
        (is (string= "ok" (jget trace "outcome")))
        (is (string= "employee:anna" (jget trace "actor")))
        (is (equal '("name") (jkeys (jget trace "input"))) "input as given, minus request_key")
        (is (equal '("employee" "employee" "allow")
                   (let ((p (jget trace "policy"))) (list (jget p "required") (jget p "actor_role") (jget p "decision")))))
        (dolist (kind '("policy" "decode" "idempotency" "operation" "store" "audit" "commit"))
          (is (member kind (step-kinds trace) :test #'string=) "a ~a step: ~s" kind (step-kinds trace)))
        (is (plusp (jget trace "store_statements")))
        (is (every (lambda (s) (and (realp (jget s "started_ms")) (realp (jget s "duration_ms")))) (jget trace "steps")))
        (is (null (jget trace "backtrace")) "no backtrace for ok")))
    (multiple-value-bind (status json rid) (mcp-post port "viewer:vera" (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/list"))
      (declare (ignore status json))
      (is (string= "tools/list" (jget (trace-of rid) "tool")) "every /mcp request is retained"))
    (multiple-value-bind (result rid) (http-tool port "viewer:vera" "no_such_tool" (jobj))
      (declare (ignore result))
      (let ((trace (trace-of rid)))
        (is (string= "error" (jget trace "outcome")))
        (is (string= "invalid_params" (jget (jget trace "error") "code")) "an unknown tool is retained too")))
    (is (string= "not_found" (nth-value 1 (call "introspect_request" "admin:ada" "request_id" "req_ukjent"))))))

(test i-outcomes-rejected-and-error-with-a-backtrace
  (with-test-app ()
    (call "widgets_create" "viewer:vera" "name" "Nei")
    (let ((forbidden (first (recent "rejected"))))
      (is (string= "widgets_create" (jget forbidden "tool")))
      (let ((trace (trace-of (jget forbidden "request_id"))))
        (is (equal '("rejected" "deny" "forbidden")
                   (list (jget trace "outcome") (jget (jget trace "policy") "decision") (jget (jget trace "error") "code"))))
        (is (null (jget trace "backtrace")) "a rejection is not a fault")))
    (call "widgets_explode" "employee:anna" "name" "Bom")
    (let* ((failed (first (recent "errors")))
           (trace (trace-of (jget failed "request_id"))))
      (is (string= "conflict" (jget failed "error_code")))
      (is (string= "error" (jget trace "outcome")))
      (is (string= "tun.core:fail" (aref (jget trace "backtrace") 0)) "the backtrace starts where it failed: ~s"
          (jget trace "backtrace"))
      (is (find "widgets-explode" (coerce (jget trace "backtrace") 'list) :test #'search)
          "and shows the operation that failed"))
    (call "widgets_create" "employee:anna" "name" 42)
    (is (string= "invalid_input" (jget (first (recent "errors")) "error_code")) "invalid_input is an error outcome")))

(test i-recent-is-newest-first-and-falls-back-for-slow
  (with-test-app ()
    (call-ok "widgets_create" "employee:anna" "name" "En")
    (call "widgets_get" "viewer:vera" "id" "wdg_mangler")
    (call-ok "widgets_create" "employee:anna" "name" "To")
    (let ((all (recent "all" "limit" 3)))
      (is (= 3 (length all)))
      (is (equal '("widgets_create" "widgets_get" "widgets_create") (mapcar (lambda (i) (jget i "tool")) all))
          "completion order, newest first")
      (is (every (lambda (i) (every (lambda (k) (nth-value 1 (jget i k))) '("request_id" "at" "actor" "tool" "outcome" "total_ms")))
                 all)))
    (is (string= "widgets_get" (jget (first (recent "errors")) "tool")))
    (is (plusp (length (recent "slow"))) "nothing reached 1 s: the slowest are listed")
    (is (= 1 (length (recent "all" "limit" 1))))))

(test i-inflight-shows-running-and-lock-waiting-requests
  (with-deadline-ms (1500)
    (let ((*app* (debug-app :db (scratch-path "inflight"))))
      (unwind-protect
           (let* ((app *app*)
                  (holder (sb-thread:make-thread
                           (lambda () (let ((*app* app)) (call "widgets_slow_create" "employee:anna" "name" "Holder")))))
                  (waiter (progn (sleep 0.3)
                                 (sb-thread:make-thread
                                  (lambda () (let ((*app* app)) (call "widgets_create" "employee:anna" "name" "Venter")))))))
             (sleep 0.3)
             (let ((items (coerce (jget (call-ok "introspect_inflight" "admin:ada") "items") 'list)))
               (is (equal "running" (jget (find-by "tool" "widgets_slow_create" items) "state")) "~s" items)
               (is (equal "waiting_write_lock" (jget (find-by "tool" "widgets_create" items) "state")) "~s" items)
               (is (>= (jget (find-by "tool" "widgets_slow_create" items) "elapsed_ms") 300))
               (is (null (find-by "tool" "introspect_inflight" items)) "not itself"))
             (sb-thread:join-thread holder) (sb-thread:join-thread waiter)
             (let ((waited (find "widgets_create" (recent "all" "limit" 10) :key (lambda (i) (jget i "tool")) :test #'equal)))
               (is (> (jget (trace-of (jget waited "request_id")) "write_lock_wait_ms") 100)
                   "the wait for the lock is in its trace")))
        (tun.runtime:close-application *app*)))))

(define-workflow test-broken (:kind "test_broken" :label "Feiler alltid") (wf)
  (declare (ignore wf))
  (error "Malen finnes ikke"))

(test i-workflows-show-a-failed-handler-and-its-trace
  (with-test-app ()
    (plan "test_broken" "2026-03-02T09:00:00Z")
    (plan "test_ping" "2026-03-05T09:00:00Z")
    (call-ok "clock_set" "admin:ada" "now" "2026-03-03T10:00:00Z")
    (let* ((items (coerce (jget (call-ok "introspect_workflows" "admin:ada" "limit" 1000) "items") 'list))
           (broken (find-by "kind" "test_broken" items))
           (pending (find-by "kind" "test_ping" items)))
      (is (equal '("failed" 1) (list (jget broken "status") (jget broken "attempts"))))
      (is (search "Malen finnes ikke" (jget broken "note")))
      (is (equal '("planned" 0) (list (jget pending "status") (jget pending "attempts"))))
      (is (equal '("test_ping") (map 'list (lambda (w) (jget w "kind"))
                                     (jget (call-ok "introspect_workflows" "admin:ada" "status" "planned") "items")))))
    (let ((run (find "workflow:test_broken" (recent "errors") :key (lambda (i) (jget i "tool")) :test #'equal)))
      (is (not (null run)) "the failed run is its own request")
      (let ((trace (trace-of (jget run "request_id"))))
        (is (string= "system:workflow" (jget trace "actor")))
        (is (find "test-broken" (coerce (jget trace "backtrace") 'list) :test #'search))))))

(defun simple-order-catalog ()
  "Values customer, a one-unit rental, a service."
  (values (jget (call-ok "customers_create" "employee:anna" "name" "Kari" "email" "kari@example.no") "id")
          (jget (call-ok "products_create" "employee:anna" "name" "Hoppeslott" "kind" "rental" "unit" "stk"
                         "unit_price_minor" 120000 "stock_tracked" nil "units_owned" 1) "id")
          (jget (call-ok "products_create" "employee:anna" "name" "Oppsett" "kind" "service" "unit" "stk"
                         "unit_price_minor" 30000 "stock_tracked" nil) "id")))

(defun audit-count () (length (jget (call-ok "audit_list" "viewer:vera" "limit" 100) "items")))

(test i-explain-is-a-dry-run-with-the-real-numbers
  (with-test-app ()
    (multiple-value-bind (customer slott oppsett) (simple-order-catalog)
      (let* ((input (jobj "customer_id" customer "event_date" "2026-07-01"
                          "lines" (jarr (list (jobj "product_id" slott "quantity" 1) (jobj "product_id" oppsett "quantity" 2)))))
             (orders (jget (call-ok "orders_list" "viewer:vera") "returned"))
             (audits (audit-count))
             (explained (call-ok "explain" "admin:ada" "tool" "orders_create" "input" input)))
        (is (equal (list t nil "allow") (list (jget explained "input_valid") (jget explained "confirm_required")
                                              (jget (jget explained "policy") "decision"))))
        (is (= orders (jget (call-ok "orders_list" "viewer:vera") "returned")) "nothing stored")
        (is (= audits (audit-count)) "no audit entry")
        (let ((real (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-07-01"
                             "lines" (jget input "lines"))))
          (dolist (key '("subtotal_minor" "discount_minor" "total_minor"))
            (is (equal (jget real key) (jget (jget explained "would") key)) "~a" key))
          (is (equalp #() (jget (jget explained "would") "bookings")) "a create books nothing")
          ;; A second order for the one unit on the same date: confirming it would fail.
          (let ((first (jget real "id"))
                (second (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-07-01"
                                       "lines" (jarr (list (jobj "product_id" slott "quantity" 1)))) "id")))
            (dolist (id (list first second))
              (call-ok "orders_send_quote" "employee:anna" "id" id)
              (call-ok "orders_accept" "employee:anna" "id" id))
            (let ((token (jget (call-ok "orders_confirm" "employee:anna" "id" first) "confirmation_token")))
              (call-ok "orders_confirm" "employee:anna" "id" first "confirmation_token" token))
            (let* ((explained (call-ok "explain" "admin:ada" "tool" "orders_confirm" "input" (jobj "id" second)))
                   (line (aref (jget (jget explained "would") "availability") 0)))
              (is (eq t (jget explained "confirm_required")))
              (is (equal (list slott nil 0) (list (jget line "product_id") (jget line "ok") (jget line "available"))))
              (is (string= "accepted" (jget (call-ok "orders_get" "viewer:vera" "id" second) "status"))))))
        (let ((bad (call-ok "explain" "admin:ada" "tool" "orders_create" "input" (jobj "customer_id" customer))))
          (is (null (jget bad "input_valid")))
          (is (find "lines" (coerce (jget bad "input_errors") 'list) :key (lambda (e) (jget e "field")) :test #'equal)))
        (is (string= "not_found" (jget (jget (call-ok "explain" "admin:ada" "tool" "orders_create"
                                                       "input" (jobj "customer_id" "kun_mangler"
                                                                     "lines" (jarr (list (jobj "product_id" slott "quantity" 1)))))
                                              "would_error")
                                        "code"))
            "a call that would fail says how")))))

(test i-schema-and-runtime
  (with-test-app (:db (scratch-path "schema"))
    (let* ((schema (call-ok "introspect_schema" "admin:ada"))
           (customers (find-by "name" "customers" (jget schema "tables"))))
      (is (not (null customers)))
      (is (find-by "name" "email" (jget customers "columns")))
      (is (every (lambda (m) (stringp (jget m "id"))) (coerce (jget schema "migrations") 'list)))
      (is (find-by "name" "on_hand" (jget (find-by "name" "stock_levels" (jget schema "tables")) "columns"))))
    (let ((runtime (call-ok "introspect_runtime" "admin:ada")))
      (is (string= "Common Lisp" (jget (jget runtime "build") "language")))
      (is (plusp (jget runtime "rss_bytes")))
      (is (string= "threads" (jget (jget runtime "workers") "kind")))
      (is (string= "test" (jget (jget runtime "clock") "mode")))
      (is (integerp (jget runtime "write_queue_depth")))
      (is (= *deadline-ms* (jget runtime "deadline_ms"))))))

(test i-introspection-tools-are-admin-reads
  (with-test-app ()
    (let ((tools '("introspect_record" "introspect_request" "introspect_recent" "introspect_inflight"
                   "introspect_workflows" "explain" "introspect_schema" "introspect_runtime" "introspect_extensions")))
      (dolist (tool tools)
        (let ((op (find-operation-by-tool tool)))
          (is (and op (eq :admin (operation-policy op)) (eq :read (operation-kind op)) (null (operation-entity op))
                   (eq :core (operation-source op)))
              "~a" tool))
        (is (string= "forbidden" (nth-value 1 (call tool "employee:anna"))) "~a is admin-only" tool)))))

;;; eval (--allow-eval)

(test i-eval-exists-only-with-the-flag-and-is-read-only
  (with-test-app ()
    (signals unknown-tool (call-tool "eval" (jobj "code" "1") :application *app* :actor (parse-actor "admin:ada"))))
  (with-test-app (:allow-eval t :db (scratch-path "eval"))
    (let ((widget (jget (call-ok "widgets_create" "employee:anna" "name" "Før") "id")))
      (is (equalp #("2") (jget (call-ok "eval" "admin:ada" "code" "(+ 1 1)") "values")))
      (is (string= "hei" (jget (call-ok "eval" "admin:ada" "code" "(princ \"hei\")") "output")))
      (is (equalp #("1") (jget (call-ok "eval" "admin:ada" "code" "(length (tun:select 'tun.tests::widget))") "values"))
          "reads the store")
      (multiple-value-bind (json code)
          (call "eval" "admin:ada" "code" "(tun.core:insert (make-instance 'tun.tests::widget :name \"Ny\"))")
        (is (string= "read_only" code) "~s" json))
      (is (string= "read_only" (nth-value 1 (call "eval" "admin:ada" "code" "(tun.store.sqlite::exec \"DELETE FROM widgets\")")))
          "SQL on the read connection is refused by SQLite (query_only)")
      (is (= 1 (jget (call-ok "widgets_count" "viewer:vera") "count")) "nothing changed")
      (is (string= "Før" (jget (call-ok "widgets_get" "viewer:vera" "id" widget) "name")))
      (let ((big (call-ok "eval" "admin:ada" "code" "(progn (princ (make-string 70000 :initial-element #\\x)) 1)")))
        (is (= 65536 (length (jget big "output"))))
        (is (eq t (jget big "output_truncated"))))
      (is (string= "invalid_input" (nth-value 1 (call "eval" "admin:ada" "code" "(+ 1"))) "unreadable code")
      (is (string= "invalid_input" (nth-value 1 (call "eval" "admin:ada" "code" "#.(+ 1 1)"))) "*read-eval* is off")
      (is (string= "forbidden" (nth-value 1 (call "eval" "employee:anna" "code" "1"))))
      (is (<= 3 (count "eval" (map 'list (lambda (e) (jget e "tool")) (jget (call-ok "audit_list" "viewer:vera" "limit" 20) "items"))
                       :test #'equal))
          "eval calls are audited"))))

(test i-eval-runs-under-the-deadline
  (with-deadline-ms (300)
    (with-test-app (:allow-eval t)
      (is (string= "deadline_exceeded" (nth-value 1 (call "eval" "admin:ada" "code" "(loop)")))))))

;;; Faults seen through the tools

(test i-external-outage-ends-at-the-external-step
  (with-deadline-ms (600)
    (with-test-app (:db (scratch-path "outage"))
      (setf (tun.accounting.fake:fake-latency-ms (application-accounting *app*)) 5000)
      (let* ((invoice (invoice-ready)))
        (is (string= "deadline_exceeded" (nth-value 1 (send-invoice invoice))))
        (is (string= "draft" (jget (call-ok "invoices_get" "viewer:vera" "id" invoice) "status")))
        (let* ((trace (trace-of (jget (first (recent "errors")) "request_id")))
               (external (find "external" (coerce (jget trace "steps") 'list) :key (lambda (s) (jget s "kind")) :test #'equal)))
          (is (string= "invoices_send" (jget trace "tool")))
          (is (string= "accounting.create_invoice" (jget external "name")))
          (is (> (jget external "duration_ms") 400) "the stall is the external step")
          (is (string= "deadline_exceeded" (jget (jget trace "error") "code"))))
        (let ((intents (jget (jget (call-ok "introspect_record" "admin:ada" "entity" "invoice" "id" invoice)
                                   "related")
                             "invoice_send_intents")))
          (is (equal '("pending") (map 'list (lambda (i) (jget i "status")) intents))
              "the intent has no outcome"))))))

(test i-stock-drift-is-visible-to-the-tools
  (let ((db (scratch-path "drift")))
    (with-test-app (:db db)
      (let ((product (stock-product 50)))
        ;; The stored balance is the product's article's.
        (with-application (*app*)
          (with-transaction (:write)
            (tun.store.sqlite::exec "UPDATE articles SET balance = balance + 37 WHERE id = ?"
                                    (tun.catalog:product-article-id (fetch 'tun.catalog:product product)))))
        (is (= 87 (jget (call-ok "inventory_balance" "viewer:vera" "product_id" product) "on_hand"))
            "inventory_balance shows the stored balance")
        (is (= 50 (jget (aref (jget (call-ok "inventory_movements" "viewer:vera" "product_id" product) "items") 0)
                        "balance_after"))
            "the ledger does not")
        (let* ((article (jget (call-ok "inventory_balance" "viewer:vera" "product_id" product) "article_id"))
               (record (call-ok "introspect_record" "admin:ada" "entity" "article" "id" article)))
          (is (= 87 (jget (jget record "stored") "balance"))))))))
