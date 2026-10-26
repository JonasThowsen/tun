;;;; tests/mcp-tests.lisp -- phase 2: MCP JSON-RPC, in-process and over HTTP.

(in-package #:tun.tests)

(def-suite mcp :in core)
(in-suite mcp)

(defun rpc (method &key (params (jobj)) (id 1) (actor "employee:anna"))
  "Call HANDLE-MCP in-process as ACTOR, a claimed role:name the way a server
with claimed identity parses it; returns (values status response-json session)."
  (tun.mcp:handle-mcp *app* (parse-actor actor)
                      (to-json-string (if id
                                          (jobj "jsonrpc" "2.0" "id" id "method" method "params" params)
                                          (jobj "jsonrpc" "2.0" "method" method "params" params)))))

(defun tool-call (name arguments &key (actor "employee:anna"))
  "tools/call in-process; returns (values parsed-text-json is-error)."
  (let* ((response (nth-value 1 (rpc "tools/call" :params (jobj "name" name "arguments" arguments)
                                                  :actor actor)))
         (result (jget response "result")))
    (values (parse-json (jget (aref (jget result "content") 0) "text"))
            (jget result "isError"))))

(test initialize-and-notifications
  (with-test-app ()
    (multiple-value-bind (status json session)
        (rpc "initialize" :params (jobj "protocolVersion" "2025-06-18" "capabilities" (jobj)
                                        "clientInfo" (jobj "name" "test" "version" "1")))
      (is (= 200 status))
      (is (string= "2025-06-18" (jget (jget json "result") "protocolVersion")))
      (is (jget (jget (jget json "result") "capabilities") "tools"))
      (is (stringp session)))
    (multiple-value-bind (status json) (rpc "notifications/initialized" :id nil)
      (is (= 202 status))
      (is (null json)))))

(test actor-header-is-required
  (with-test-app ()
    (dolist (bad (list nil "" "employee" "boss:anna" "employee:" "employee:an na"))
      (let ((json (nth-value 1 (rpc "tools/list" :actor bad))))
        (is (= -32000 (jget (jget json "error") "code")) "header ~s" bad)))))

(test protocol-errors
  (with-test-app ()
    (is (= -32700 (jget (jget (nth-value 1 (tun.mcp:handle-mcp *app* (parse-actor "employee:anna") "{nope")) "error") "code")))
    (is (= -32601 (jget (jget (nth-value 1 (rpc "nonsense/method")) "error") "code")))
    (is (= -32602 (jget (jget (nth-value 1 (rpc "tools/call" :params (jobj "name" "finnes_ikke"))) "error")
                        "code")))))

(test tools-list-is-the-registry
  (with-test-app ()
    (let* ((tools (coerce (jget (jget (nth-value 1 (rpc "tools/list" :actor "viewer:vera")) "result") "tools") 'list))
           (names (mapcar (lambda (tl) (jget tl "name")) tools))
           (create (find "customers_create" tools :key (lambda (tl) (jget tl "name")) :test #'string=)))
      (is (equal (sort (copy-list names) #'string<)
                 (sort (mapcar #'operation-tool (visible-operations *app*)) #'string<)))
      (is (string= "Opprett kunde" (jget create "title")))
      (is (stringp (jget create "description")))
      (is (member "name" (coerce (jget (jget create "inputSchema") "required") 'list) :test #'string=))
      (is (eq nil (jget (jget create "annotations") "readOnlyHint")))
      (is (member "destructiveHint" (jkeys (jget create "annotations")) :test #'string=)))))

(test tools-call-results-and-errors
  (with-test-app ()
    (multiple-value-bind (json error-p)
        (tool-call "customers_create" (jobj "name" "Ola" "email" "ola@example.no"))
      (is (eq nil error-p))
      (is (string-prefix-p "cus_" (jget json "id"))))
    (multiple-value-bind (json error-p)
        (tool-call "customers_create" (jobj "name" "Ola" "email" "ola@example.no") :actor "viewer:vera")
      (is (eq t error-p))
      (is (string= "forbidden" (error-code-of json)))
      (is (stringp (jget (jget json "error") "message"))))
    (multiple-value-bind (json error-p) (tool-call "customers_get" (jobj "id" "cus_x") :actor "viewer:vera")
      (is (eq t error-p))
      (is (string= "not_found" (error-code-of json))))))

;;; Over real HTTP (helpers in tun.test-support)

(test mcp-over-http
  (with-test-server (port)
    (multiple-value-bind (status body headers)
        (http-post port "/mcp" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}"
                   :actor "admin:ada")
      (is (= 200 status))
      (is (search "application/json" (cdr (assoc :content-type headers))))
      (is (string= "2025-06-18" (jget (jget (parse-json body) "result") "protocolVersion")))
      (is (cdr (assoc :mcp-session-id headers))))
    (is (= 202 (http-post port "/mcp" "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}"
                          :actor "admin:ada")))
    (let ((missing (parse-json (nth-value 1 (http-post port "/mcp" "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}")))))
      (is (= -32000 (jget (jget missing "error") "code"))))
    (multiple-value-bind (json error-p status)
        (http-tool-call port "employee:anna" "customers_create" (jobj "name" "Åsmund Bø" "email" "asmund@bø.no"))
      (is (= 200 status))
      (is (eq nil error-p))
      (is (string= "Åsmund Bø" (jget json "name")) "æøå survive the HTTP round trip")
      (is (string= "Åsmund Bø"
                   (jget (http-tool-call port "viewer:vera" "customers_get" (jobj "id" (jget json "id"))) "name"))))))

(test concurrent-http-requests
  (with-test-server (port :db (scratch-path "http"))
    (let ((results (run-concurrently 16 (lambda (i)
                                          (http-tool-call port "employee:anna" "customers_create"
                                                          (jobj "name" (format nil "Kunde ~d" i)
                                                                "email" (format nil "k~d@example.no" i)
                                                                "request_key" (format nil "k~d" i)))))))
      (is (every #'hash-table-p results) "~s" results)
      (is (= 16 (length (remove-duplicates (map 'list (lambda (r) (jget r "id")) results) :test #'equal))))
      (is (= 16 (jget (call-ok "customers_list" "viewer:vera" "limit" 100) "returned"))))))

(test texts-in-definitions-are-written-out
  (signals error (macroexpand-1 '(define-operation texts-op ((note :type string
                                                                  :description +note-text+))
                                    (:kind :read)
                                  nil))
    "a parameter's description is not evaluated, so a constant's name is refused")
  (signals error (macroexpand-1 '(define-entity texts-entity ()
                                   ((note :type string :label +note-label+))))
    "nor a field's label")
  (is (consp (macroexpand-1 '(define-operation texts-op ((note :type string :description "Notat"))
                                (:kind :read)
                              nil)))))

(test a-response-that-cannot-be-encoded-is-the-requests-error
  (with-test-app ()
    (let* ((parameter (find "id" (operation-parameters (find-operation 'widgets-get))
                            :key #'parameter-json-name :test #'string=))
           (before (slot-value parameter 'tun.core::description)))
      ;; What a definition from before the check could leave in the registry.
      (setf (slot-value parameter 'tun.core::description) 'unencodable-text)
      (unwind-protect
           (multiple-value-bind (status json session text)
               (tun.mcp:handle-mcp *app* (parse-actor "employee:anna")
                                   (to-json-string (jobj "jsonrpc" "2.0" "id" 3
                                                         "method" "tools/list")))
             (declare (ignore session))
             (is (= 200 status))
             (is (= -32603 (jget (jget json "error") "code")) "a JSON-RPC error, not an HTTP 500")
             (is (search "-32603" text))
             (is (find "error" (coerce (jget (call-ok "introspect_recent" "admin:root"
                                                      "request_kind" "mcp")
                                             "items")
                                       'list)
                       :key (lambda (item) (jget item "outcome")) :test #'equal)
                 "and the request is retained as an error"))
        (setf (slot-value parameter 'tun.core::description) before)))))
