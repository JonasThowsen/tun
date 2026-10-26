;;;; tests/waiting-tests.lisp -- operations that wait for a change
;;;; (spec/waiting.md 6).

(in-package #:tun.tests)

(def-suite waiting :in core)
(in-suite waiting)

(define-operation widgets-set-status ((id :type (id widget) :required t)
                                      (status :type (enum "aktiv" "arkivert") :required t))
    (:entity widget :kind :update :title "Sett status")
  (let ((widget (fetch! 'widget id)))
    (setf (widget-status widget) status)
    (save widget)))

(define-operation widgets-await-archived ((id :type (id widget) :required t)
                                         (seconds :type (integer :min 0 :max 600) :default 5))
    (:entity widget :kind :wait :title "Vent til dingsen er arkivert")
  (multiple-value-bind (widget archived)
      (await (:seconds seconds :until (lambda (widget) (equal (widget-status widget) "arkivert")))
        (fetch! 'widget id))
    (jobj "status" (widget-status widget) "archived" (json-bool archived))))

(define-operation widgets-await-in-a-read ((id :type (id widget) :required t))
    (:entity widget :kind :read :title "Vent i en lesing")
  (await (:seconds 1) (fetch! 'widget id)))

(define-application waiting-instructions-app ()
  (:instructions "Start med å si hvem du er." "Vent på svaret med questions_wait."))

(defun new-widget ()
  (jget (call-ok "widgets_create" "employee:anna" "name" "Dings") "id"))

(defun archive-later (id seconds)
  "Archive the widget ID from another thread after SECONDS."
  (let ((app *app*))
    (sb-thread:make-thread (lambda ()
                             (sleep seconds)
                             (let ((*app* app))
                               (call-ok "widgets_set_status" "employee:anna"
                                        "id" id "status" "arkivert")))
                           :name "archive later")))

(defun elapsed-since (start)
  (/ (- (get-internal-real-time) start) internal-time-units-per-second))

(defmacro with-global ((place value) &body body)
  "Run BODY with the global value of PLACE set to VALUE, as server threads see it."
  (let ((old (gensym)))
    `(let ((,old ,place))
       (setf ,place ,value)
       (unwind-protect (progn ,@body) (setf ,place ,old)))))

(test a-wait-returns-at-the-commit-that-satisfies-it
  (with-test-app ()
    (let* ((id (new-widget))
           (thread (archive-later id 0.3))
           (start (get-internal-real-time))
           (json (call-ok "widgets_await_archived" "employee:anna" "id" id "seconds" 30)))
      (sb-thread:join-thread thread)
      (is (string= "arkivert" (jget json "status")))
      (is (eq t (jget json "archived")))
      (is (< (elapsed-since start) 3) "woken by the commit, not the next look"))))

(test a-wait-ends-with-its-last-value-when-time-is-up
  (with-test-app ()
    (let* ((id (new-widget))
           (start (get-internal-real-time))
           (json (call-ok "widgets_await_archived" "employee:anna" "id" id "seconds" 1)))
      (is (string= "aktiv" (jget json "status")))
      (is (eq nil (jget json "archived")) "and says it did not happen")
      (is (<= 1 (elapsed-since start) 3)))
    (is (string= "not_found" (nth-value 1 (call "widgets_await_archived" "employee:anna"
                                                "id" "wdg_none" "seconds" 5)))
        "an error ends the wait")))

(test await-is-only-for-a-wait-operation
  (with-test-app ()
    (signals error (await (:seconds 1) t) "outside any operation")
    (let ((id (new-widget)))
      (signals error (call "widgets_await_in_a_read" "employee:anna" "id" id)
        "in a read, which holds a transaction"))))

(test a-waiting-call-holds-no-transaction-and-is-not-in-flight
  (with-test-server (port)
    (let* ((id (new-widget))
           (cell (application-inflight-cell *app*))
           (app *app*)
           (caller (sb-thread:make-thread
                    (lambda ()
                      (let ((*app* app))
                        (http-tool-call port "employee:anna" "widgets_await_archived"
                                        (jobj "id" id "seconds" 30))))
                    :name "waiting caller")))
      (loop repeat 100 until (= 1 (waiting-count)) do (sleep 0.02))
      (is (= 1 (waiting-count)) "the call waits")
      (is (= 0 (car cell)) "and has left the requests in flight")
      ;; A write while it waits: the waiting call holds no lock.
      (call-ok "widgets_set_status" "employee:anna" "id" id "status" "arkivert")
      (sb-thread:join-thread caller)
      (is (= 0 (waiting-count))))))

(test a-wait-looks-again-and-again-until-its-time-is-up
  ;; Each look but the last ends a timed wait for a commit, which returns
  ;; without the lock (CONDITION-WAIT's contract): many of them here.
  (with-global (tun.core::+await-recheck-seconds+ 0.2)
    (with-test-app ()
      (let ((id (new-widget)))
        (is (string= "aktiv" (jget (call-ok "widgets_await_archived" "employee:anna"
                                            "id" id "seconds" 2)
                                   "status"))
            "ten looks and no change")
        (let ((thread (archive-later id 1)))
          (is (string= "arkivert" (jget (call-ok "widgets_await_archived" "employee:anna"
                                                 "id" id "seconds" 5)
                                        "status"))
              "a change after several looks")
          (sb-thread:join-thread thread))))))

(test a-wait-outlasts-two-rechecks-in-real-time
  (with-test-app ()
    (let* ((id (new-widget))
           (thread (archive-later id 11))
           (start (get-internal-real-time))
           (json (call-ok "widgets_await_archived" "employee:anna" "id" id "seconds" 30)))
      (sb-thread:join-thread thread)
      (is (string= "arkivert" (jget json "status")) "after looks at 5 and 10 seconds")
      (is (<= 11 (elapsed-since start) 14)))))

(test waiting-calls-are-capped
  (with-test-app ()
    (let ((id (new-widget))
          (*max-waiting* 0))
      (is (string= "unavailable" (nth-value 1 (call "widgets_await_archived" "employee:anna"
                                                    "id" id "seconds" 5))))
      (is (= 0 (waiting-count))))))

(test a-wait-outlasts-the-deadline
  (with-test-app ()
    (let ((id (new-widget))
          (tun.core::*deadline-ms* 300))
      (is (string= "aktiv" (jget (call-ok "widgets_await_archived" "employee:anna"
                                          "id" id "seconds" 1)
                                 "status"))
          "a one-second wait under a 300 ms deadline"))))

;;; ------------------------------------------------------------------
;;; Over MCP and the HTTP API (spec/waiting.md 2, 3)

(defun mcp-wait-call (port id seconds &key progress-token (accept "application/json, text/event-stream"))
  "tools/call widgets_await_archived over /mcp.  Values the status, the body
text and the headers."
  (let ((params (jobj "name" "widgets_await_archived" "arguments" (jobj "id" id "seconds" seconds))))
    (when progress-token
      (setf (gethash "_meta" params) (jobj "progressToken" progress-token)))
    (multiple-value-bind (bytes status headers)
        (drakma:http-request (format nil "http://127.0.0.1:~d/mcp" port)
                             :method :post :content-type "application/json"
                             :content (sb-ext:string-to-octets
                                       (to-json-string (jobj "jsonrpc" "2.0" "id" 7
                                                             "method" "tools/call" "params" params))
                                       :external-format :utf-8)
                             :additional-headers (list (cons "X-Tun-Actor" "employee:anna")
                                                       (cons "Accept" accept))
                             :connection-timeout 60
                             :force-binary t)
      (values status (sb-ext:octets-to-string bytes :external-format :utf-8) headers))))

(defun event-data (text)
  "The JSON of each data: line of the server-sent events in TEXT."
  (loop for line in (cl-ppcre:split "\\n" text)
        when (eql 0 (search "data: " line))
          collect (parse-json (subseq line 6))))

(test a-long-wait-over-mcp-becomes-a-stream-with-progress
  (with-global (tun.core::+await-heartbeat-seconds+ 1)
    (with-test-server (port)
      (let ((id (new-widget)))
        (multiple-value-bind (status text headers) (mcp-wait-call port id 0)
          (is (= 200 status))
          (is (search "application/json" (cdr (assoc :content-type headers)))
              "a call that waits for nothing is plain JSON")
          (is (search "\"aktiv\"" text)))
        (multiple-value-bind (status text headers) (mcp-wait-call port id 2 :progress-token "tok-1")
          (is (= 200 status))
          (is (search "text/event-stream" (cdr (assoc :content-type headers))))
          (let* ((events (event-data text))
                 (progress (remove "notifications/progress" events
                                   :key (lambda (e) (jget e "method")) :test-not #'equal))
                 (answer (car (last events))))
            (is (plusp (length progress)) "progress while it waits")
            (is (equal "tok-1" (jget (jget (first progress) "params") "progressToken")))
            (is (= 7 (jget answer "id")) "the answer is the last event")
            (is (search "\"aktiv\"" (to-json-string (jget answer "result"))))))
        (multiple-value-bind (status text) (mcp-wait-call port id 2)
          (is (= 200 status))
          (is (cl-ppcre:scan "(?m)^: venter" text) "a comment without a progressToken")
          (is (= 7 (jget (car (last (event-data text))) "id"))))
        (multiple-value-bind (status text headers)
            (with-global (tun.http::+plain-wait-seconds+ 1)
              (let ((start (get-internal-real-time)))
                (multiple-value-prog1 (mcp-wait-call port id 30 :accept "application/json")
                  (is (< (elapsed-since start) 5) "a client that takes only JSON waits less"))))
          (declare (ignore text))
          (is (= 200 status))
          (is (search "application/json" (cdr (assoc :content-type headers)))))))))

(test a-wait-over-mcp-streams-in-real-time
  (with-test-server (port)
    (let ((id (new-widget)))
      (multiple-value-bind (status text headers) (mcp-wait-call port id 27 :progress-token 9)
        (is (= 200 status))
        (is (search "text/event-stream" (cdr (assoc :content-type headers))))
        (let ((events (event-data text)))
          (is (equal "notifications/progress" (jget (first events) "method"))
              "progress at 25 seconds")
          (is (= 7 (jget (car (last events)) "id")))
          (is (null (jget (car (last events)) "error")) "and the answer, not an error")
          (is (search "\"aktiv\"" (to-json-string (jget (car (last events)) "result")))))))))

(test a-wait-over-the-api-is-a-long-poll
  (with-global (tun.http::+plain-wait-seconds+ 1)
    (with-test-server (port)
      (let* ((id (new-widget))
             (start (get-internal-real-time)))
        (multiple-value-bind (bytes status)
            (drakma:http-request (format nil "http://127.0.0.1:~d/api/widgets_await_archived" port)
                                 :method :post :content-type "application/json"
                                 :content (to-json-string (jobj "id" id "seconds" 30))
                                 :additional-headers '(("X-Tun-Actor" . "employee:anna"))
                                 :force-binary t)
          (is (= 200 status))
          (is (string= "aktiv" (jget (parse-json (sb-ext:octets-to-string bytes :external-format :utf-8))
                                     "status")))
          (is (< (elapsed-since start) 5) "held to what a proxy lets stay silent"))))))

(test instructions-reach-initialize
  (let ((text (jget (tun.mcp::handle-initialize 'waiting-instructions-app (jobj)) "instructions")))
    (is (search "Alle verktøy er generert" text) "Tun's own first")
    (is (search (format nil "~%~%Start med å si hvem du er.~%~%Vent på svaret med questions_wait.")
                text)
        "then the client's paragraphs")))
