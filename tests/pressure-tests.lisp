;;;; tests/pressure-tests.lisp -- core.md §7: the required runtime properties.

(in-package #:tun.tests)

(def-suite pressure :in core)
(in-suite pressure)

(defmacro with-deadline-ms ((ms) &body body)
  "Set the server-wide deadline (a global, so server threads see it too)."
  (let ((saved (gensym)))
    `(let ((,saved *deadline-ms*))
       (unwind-protect (progn (setf *deadline-ms* ,ms) ,@body)
         (setf *deadline-ms* ,saved)))))

(defun timed-call (tool actor &rest args)
  "Values code (or NIL), milliseconds."
  (let ((start (get-internal-real-time)))
    (multiple-value-bind (json code) (apply #'call tool actor args)
      (declare (ignore json))
      (values code (round (* 1000 (- (get-internal-real-time) start)) internal-time-units-per-second)))))

(defun debug-app (&rest args)
  (apply #'tun.runtime:open-application 'application :debug-tools t :test-clock t args))

;;; core.md §7.1 Deadlines

(test p-deadline-interrupts-burn-and-sleep
  (with-deadline-ms (300)
    (let ((*app* (debug-app)))
      (dolist (tool '("debug_burn" "debug_sleep"))
        (multiple-value-bind (code ms) (timed-call tool "employee:anna" "ms" 5000)
          (is (string= "deadline_exceeded" code) "~a" tool)
          (is (< ms 1000) "~a stopped at the deadline, not after 5 s (~d ms)" tool ms)))
      (let ((entries (coerce (jget (call-ok "audit_list" "viewer:vera" "limit" 10) "items") 'list)))
        (dolist (tool '("debug_burn" "debug_sleep"))
          (is (find-if (lambda (e) (and (string= tool (jget e "tool")) (string= "rejected" (jget e "outcome"))
                                        (string= "deadline_exceeded" (jget e "error_code"))))
                       entries)
              "audit has a rejected ~a entry" tool))))))

(test p-deadline-rolls-back-the-transaction
  (with-deadline-ms (300)
    (with-test-app ()
      (is (string= "deadline_exceeded" (timed-call "widgets_slow_create" "employee:anna" "name" "Treg")))
      (is (= 0 (jget (call-ok "widgets_count" "viewer:vera") "count")) "the insert before the expiry rolled back"))))

(test p-watchdog-stops-code-without-deadline-checks
  (with-deadline-ms (300)
    (with-test-app ()
      (multiple-value-bind (code ms) (timed-call "widgets_spin" "viewer:vera" "ms" 5000)
        (is (string= "deadline_exceeded" code))
        (is (< ms (+ 300 *watchdog-grace-ms* 700)) "interrupted by the watchdog (~d ms)" ms)))))

(test p-deadline-leaves-other-requests-alone
  (with-deadline-ms (1500)
    (with-test-server (port :class 'application :db (scratch-path "others"))
      ;; SQLite: the in-memory store serializes reads and writes on one mutex.
      (setf (application-debug-tools-p *app*) t)
      (let* ((runaway (sb-thread:make-thread
                       (lambda () (http-tool-call port "employee:anna" "debug_sleep" (jobj "ms" 10000)))))
             (start (get-internal-real-time)))
        (sleep 0.1)
        (is (null (nth-value 1 (http-tool-call port "employee:anna" "customers_create"
                                               (jobj "name" "Ikke berørt" "email" "x@example.no")))))
        (is (< (- (get-internal-real-time) start) (* 1 internal-time-units-per-second))
            "a write ran while the runaway was blocked")
        (is (string= "deadline_exceeded" (error-code-of (sb-thread:join-thread runaway))))))))

(define-workflow test-slow (:kind "test_slow" :label "Treg arbeidsflyt") (wf)
  (declare (ignore wf))
  (sleep-with-deadline 5000))

(test p-workflow-past-its-deadline-is-cancelled
  ;; Normal mode: every scheduled workflow run has its own deadline.  (In test
  ;; mode workflows run inside clock_set and share that operation's deadline.)
  (with-deadline-ms (300)
    (with-test-app (:test-clock nil)
      (with-application (*app*)
        (with-transaction (:write)
          (tun.workflows:schedule-workflow "test_slow" :due-at (- (get-universal-time) 1)))
        (let ((*actor* (system-actor)))
          (is (= 0 (tun.workflows:run-due-workflows))))
        (with-transaction (:read)
          (is (string= "feilet" (tun.workflows:workflow-status (select-one 'tun.workflows:workflow)))))))))

;;; core.md §7.2 Backpressure

(defun raw-post (port actor body)
  "Values status, headers and body string of one POST /mcp."
  (multiple-value-bind (bytes status headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d/mcp" port) :method :post
                           :content (sb-ext:string-to-octets body :external-format :utf-8)
                           :content-type "application/json" :force-binary t
                           :additional-headers (list (cons "X-Tun-Actor" actor)))
    (values status headers (if bytes (sb-ext:octets-to-string bytes :external-format :utf-8) ""))))

(test p-backpressure-sheds-at-once
  (let ((*app* (debug-app :db (scratch-path "shed") :identity :claimed)))
    (let* ((port (free-port))
           (acceptor (tun.http:start-server *app* :port port :max-inflight 2)))
      (unwind-protect
           (let* ((sleepy (to-json-string (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/call"
                                                "params" (jobj "name" "debug_sleep" "arguments" (jobj "ms" 1500)))))
                  (results (run-concurrently 6 (lambda (i)
                                                 (declare (ignore i))
                                                 (let ((start (get-internal-real-time)))
                                                   (multiple-value-bind (status headers body)
                                                       (raw-post port "employee:anna" sleepy)
                                                     (list status headers body
                                                           (round (* 1000 (- (get-internal-real-time) start))
                                                                  internal-time-units-per-second)))))))
                  (shed (remove 503 (coerce results 'list) :key #'first :test-not #'eql))
                  (served (remove 200 (coerce results 'list) :key #'first :test-not #'eql)))
             (is (= 2 (length served)) "two in flight are served")
             (is (= 4 (length shed)) "the rest are shed")
             (dolist (r shed)
               (is (string= "1" (cdr (assoc :retry-after (second r)))))
               (is (= -32001 (jget (jget (parse-json (third r)) "error") "code")))
               (is (string= "overbelastet" (jget (jget (parse-json (third r)) "error") "message")))
               (is (< (fourth r) 500) "shed at once, not queued (~d ms)" (fourth r))))
        (tun.http:stop-server acceptor)))))

;;; core.md §7.4 Fault isolation

(test p-a-serious-condition-fails-only-its-request
  (with-test-server (port :db (scratch-path "fault"))
    (let ((exploding (to-json-string (jobj "jsonrpc" "2.0" "id" 3 "method" "tools/call"
                                           "params" (jobj "name" "widgets_overflow"
                                                          "arguments" (jobj "name" "Bom"))))))
      (multiple-value-bind (status body) (http-post port "/mcp" exploding :actor "employee:anna")
        (is (= 200 status))
        (is (= -32603 (jget (jget (parse-json body) "error") "code"))
            "a stack exhaustion (not an ERROR) is a JSON-RPC internal error: ~a" body))
      (is (null (nth-value 1 (http-tool-call port "employee:anna" "widgets_create" (jobj "name" "Etter"))))
          "the next request is served")
      (with-application (*app*)
        (with-transaction (:read)
          (is (equal '("Etter") (mapcar #'widget-name (select 'widget)))
              "the failed request's write was rolled back"))))))

;;; core.md §7.3 External calls outside write transactions; reconciliation

(test p-a-stalled-port-delays-only-its-request
  (with-test-server (port :db (scratch-path "stall"))
    (setf (tun.accounting.fake:fake-latency-ms (application-accounting *app*)) 1500)
    (let* ((invoice (invoice-ready))
           (token (jget (call-ok "invoices_send" "admin:ada" "id" invoice) "confirmation_token"))
           (sender (sb-thread:make-thread
                    (lambda () (http-tool-call port "admin:ada" "invoices_send"
                                               (jobj "id" invoice "confirmation_token" token))))))
      (sleep 0.3)
      (let ((start (get-internal-real-time)))
        (is (null (nth-value 1 (http-tool-call port "employee:anna" "customers_create"
                                               (jobj "name" "Mens vi venter" "email" "w@example.no")))))
        (is (< (- (get-internal-real-time) start) (* 0.5 internal-time-units-per-second))
            "a write is not held up by the stalled accounting call"))
      (is (string= "sendt" (jget (sb-thread:join-thread sender) "status"))))))

(test p-reconciliation-at-start-up-uses-lookup
  (let ((db (scratch-path "reconcile"))
        invoice)
    (with-test-app (:db db)
      (setf (application-accounting *app*) (make-instance 'observing-fake) *port-calls* '())
      (setf invoice (invoice-ready))
      ;; The outcome is lost after the port call (as if killed in between).
      (let ((*invoice-write-failures* 1)) (signals error (send-invoice invoice)))
      (is (string= "utkast" (jget (call-ok "invoices_get" "viewer:vera" "id" invoice) "status")))
      (is (= 1 (length *port-calls*))))
    ;; Restart: the pending intent is looked up and completed, without a new create.
    (with-test-app (:db db)
      (setf (application-accounting *app*) (make-instance 'observing-fake)))
    (with-test-app (:db db)
      (let ((sent (call-ok "invoices_get" "viewer:vera" "id" invoice)))
        (is (string= "sendt" (jget sent "status")) "reconciled at start-up")
        (is (= 1 (length *port-calls*)) "no second create")
        (is (= 1 (reported-calls invoice)))
        (is (string= (jget sent "external_ref")
                     (jget (find-by "invoice_id" invoice (jget (call-ok "accounting_status" "admin:ada") "invoices"))
                           "external_ref")))
        (is (find "invoices_send.reconciled" (coerce (jget (call-ok "audit_list" "viewer:vera") "items") 'list)
                  :key (lambda (e) (jget e "tool")) :test #'equal))))))

;;; core.md §7.5 Bounded inputs before authentication

(test p-header-count-is-bounded
  (with-test-server (port)
    (is (search " 431" (princ-to-string
                        (raw-exchange port (apply #'crlf "GET /health HTTP/1.1" "Host: x"
                                                  (append (loop for i below 150 collect (format nil "X-H~d: 1" i))
                                                          (list "")))))))
    (is (search " 200" (raw-exchange port (crlf "GET /health HTTP/1.1" "Host: x" "X-A: 1" ""))))))

(defun nested-json (depth)
  (concatenate 'string (make-string depth :initial-element #\[) (make-string depth :initial-element #\])))

(defun json-string-of (length)
  (concatenate 'string "\"" (make-string length :initial-element #\a) "\""))

(test p-json-depth-and-string-length-are-bounded
  (finishes (parse-json (nested-json 64)))
  (signals json-parse-failure (parse-json (nested-json 65)))
  (signals json-parse-failure (parse-json (nested-json 100000)))
  (is (= 1048576 (length (parse-json (json-string-of 1048576)))))
  (signals json-parse-failure (parse-json (json-string-of 1048577)))
  (with-test-server (port)
    (multiple-value-bind (status body)
        (http-post port "/mcp" (format nil "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\",\"params\":{\"x\":~a}}"
                                       (nested-json 1000))
                   :actor "viewer:vera")
      (is (= 200 status))
      (is (= -32700 (jget (jget (parse-json body) "error") "code")) "too deep: a parse error, not a crash"))))

;;; core.md §7.6 Scheduler and debug flags

(test p-debug-tools-only-with-the-flag
  (with-test-app ()
    (let ((names (mapcar #'operation-tool (visible-operations *app*))))
      (is (not (member "debug_burn" names :test #'string=)))
      (is (member "workflows_get" names :test #'string=) "workflows_get is always there"))
    (signals unknown-tool (call "debug_burn" "employee:anna" "ms" 1)))
  (let ((*app* (debug-app)))
    (let ((names (mapcar #'operation-tool (visible-operations *app*))))
      (dolist (tool '("debug_burn" "debug_sleep" "debug_schedule" "workflows_get"))
        (is (member tool names :test #'string=) "~a" tool)))
    (let ((ops (jget (call-ok "registry_describe" "viewer:vera") "operations")))
      (is (eq :null (jget (find-by "name" "debug_burn" ops) "entity")))
      (is (string= "core" (jget (find-by "name" "debug_schedule" ops) "source")))
      (is (string= "admin" (jget (find-by "name" "debug_schedule" ops) "policy"))))))

(test p-policy-runs-before-the-work
  (let ((*app* (debug-app)))
    (multiple-value-bind (code ms) (timed-call "debug_burn" "viewer:vera" "ms" 5000)
      (is (string= "forbidden" code))
      (is (< ms 100) "no burning for a forbidden caller (~d ms)" ms))
    (is (string= "forbidden" (timed-call "debug_schedule" "employee:anna" "due_in_ms" 10)))))

(test p-debug-schedule-runs-on-the-scheduler-tick
  (let ((*app* (tun.runtime:open-application 'application :debug-tools t)))
    (let* ((scheduled (call-ok "debug_schedule" "admin:ada" "due_in_ms" 500))
           (id (jget scheduled "id")))
      (is (stringp (jget scheduled "due_at")))
      (is (string= "planlagt" (jget (call-ok "workflows_get" "viewer:vera" "id" id) "status")))
      (unwind-protect
           (progn
             (tun.runtime:start-scheduler *app* :interval 0.2)
             (loop repeat 50
                   until (string= "utført" (jget (call-ok "workflows_get" "viewer:vera" "id" id) "status"))
                   do (sleep 0.1))
             (let ((wf (call-ok "workflows_get" "viewer:vera" "id" id)))
               (is (string= "utført" (jget wf "status")))
               (is (string= "debug_ping" (jget wf "kind")))
               (is (stringp (jget wf "executed_at")))))
        (tun.runtime:stop-scheduler)))))

(test p-debug-schedule-never-fires-early
  ;; Stored times are whole seconds; the due time is rounded up from the
  ;; millisecond clock, so it is never before the call plus due_in_ms.
  (let ((*app* (tun.runtime:open-application 'application :debug-tools t)))
    (with-application (*app*)
      (dotimes (i 5)
        (let* ((before (now-ms))
               (due-in (+ 1000 (* 250 i)))
               (due-at (parse-rfc3339 (jget (call-ok "debug_schedule" "admin:ada" "due_in_ms" due-in) "due_at"))))
          (is (>= (* 1000 due-at) (+ before due-in)) "due ~d ms after ~d, got ~d" due-in before (* 1000 due-at))
          (is (< (* 1000 due-at) (+ before due-in 2000)) "and not more than a second late"))
        (sleep 0.13))))
  (let ((clock (make-instance 'tun.core::system-clock)))
    (is (<= (abs (- (floor (tun.core::clock-now-ms clock) 1000) (get-universal-time))) 1)
        "the millisecond clock agrees with GET-UNIVERSAL-TIME")))
