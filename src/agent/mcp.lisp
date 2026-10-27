;;;; agent/mcp.lisp -- MCP over HTTP (JSON-RPC 2.0, JSON responses, no SSE).
;;;;
;;;; This adapter only translates: JSON-RPC -> CALL-TOOL -> JSON-RPC.  It
;;;; holds no policy, confirmation, idempotency or audit logic; those run in
;;;; the operation's effective method (core/execution.lisp), so the web UI and
;;;; in-process callers get identical behaviour.  HANDLE-MCP is independent of
;;;; the HTTP server so it can be tested in-process.

(defpackage #:tun.mcp
  (:use #:cl #:tun.core)
  (:export #:handle-mcp #:+protocol-version+ #:*server-info* #:+missing-actor-message+
           #:+too-many-values+
           #:*progress-token* #:progress-notification))

(in-package #:tun.mcp)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +protocol-version+ "2025-06-18")
(defparameter *supported-versions* '("2025-06-18" "2025-03-26" "2024-11-05"))
(defparameter *server-info* (jobj "name" "tun" "title" "tun (Common Lisp)" "version" "0.1.0"))

(define-condition rpc-error (error)
  ((code :initarg :code :reader rpc-error-code)
   (message :initarg :message :reader rpc-error-message)))

(defun rpc-fail (code control &rest args)
  (error 'rpc-error :code code :message (apply #'format nil control args)))

(defun rpc-result (id result)
  (jobj "jsonrpc" "2.0" "id" id "result" result))

(defun rpc-error-response (id code message)
  (jobj "jsonrpc" "2.0" "id" (if (null id) :null id) "error" (jobj "code" code "message" message)))

(defun tool-result (json error-p)
  "A tools/call result; _meta.request_id is the handle for introspect_request (core.md §8.1)."
  (jobj "content" (jarr (list (jobj "type" "text" "text" (to-json-string json))))
        "structuredContent" json
        "isError" (json-bool error-p)
        "_meta" (jobj "request_id" *request-id*)))

(defun valid-id-p (id)
  (or (stringp id) (integerp id)))

(defparameter +instructions+
  "Alle verktøy er generert fra registeret. Muterende verktøy tar request_key for idempotens; verktøy som krever bekreftelse returnerer et confirmation_token som må sendes i et nytt kall."
  "Tun's own instructions for every agent, before the client's.")

(defun handle-initialize (application params)
  (let* ((requested (jget params "protocolVersion"))
         (version (if (member requested *supported-versions* :test #'equal)
                      requested
                      +protocol-version+)))
    (jobj "protocolVersion" version
          "capabilities" (jobj "tools" (jobj "listChanged" nil))
          "serverInfo" *server-info*
          ;; The client's paragraphs after Tun's (spec/waiting.md 4).
          "instructions" (format nil "~{~a~^~%~%~}"
                                 (cons +instructions+ (application-instructions application))))))

(defvar *progress-token* nil
  "The progressToken of the tools/call being handled, from its
params._meta, or NIL: where a waiting call's progress goes (spec/waiting.md 2).")

(defun progress-notification (seconds)
  "The notifications/progress for *PROGRESS-TOKEN* after SECONDS of waiting."
  (jobj "jsonrpc" "2.0" "method" "notifications/progress"
        "params" (jobj "progressToken" *progress-token*
                       "progress" seconds
                       "message" (format nil "Venter fortsatt (~d s)" seconds))))

(defun handle-tools-call (application actor params)
  (let ((name (jget params "name"))
        (arguments (jget params "arguments" (jobj))))
    (unless (stringp name) (rpc-fail -32602 "tools/call krever params.name"))
    (when (json-null-p arguments) (setf arguments (jobj)))
    (unless (hash-table-p arguments) (rpc-fail -32602 "params.arguments må være et objekt"))
    (let ((*request-id* (or *request-id* (new-id "req")))
          (*progress-token* (let* ((meta (jget params "_meta"))
                                   (token (and (hash-table-p meta) (jget meta "progressToken"))))
                              (and (or (stringp token) (integerp token)) token))))
      (handler-case (tool-result (call-tool name arguments :application application :actor actor) nil)
        (operation-error (e) (tool-result (operation-error-json e) t))
        (unknown-tool () (rpc-fail -32602 "Ukjent verktøy: ~a" (shown-name name)))))))

(defun dispatch (application actor method params)
  ;; The record clips the method or tool's name as it keeps it.
  (when *request-record*
    (setf (request-tool *request-record*)
          (if (and (string= method "tools/call") (stringp (jget params "name"))) (jget params "name") method))
    (let ((arguments (if (string= method "tools/call") (jget params "arguments") params)))
      (when (hash-table-p arguments)
        (setf (request-input *request-record*)
              (recorded-input (make-input arguments)
                              (and (string= method "tools/call") (stringp (jget params "name"))
                                   (find-operation-by-tool (jget params "name"))))))))
  (cond ((string= method "initialize") (handle-initialize application params))
        ((string= method "ping") (jobj))
        ((string= method "tools/list")
         (with-application (application)
           (jobj "tools" (jarr (tool-definitions application)))))
        ((string= method "tools/call") (handle-tools-call application actor params))
        (t (rpc-fail -32601 "Ukjent metode: ~a" (shown-name method)))))

(defun rpc-code-name (code)
  (case code
    (-32700 "parse_error") (-32600 "invalid_request") (-32601 "method_not_found")
    (-32602 "invalid_params") (-32603 "internal_error") (-32000 "invalid_actor")
    (t (format nil "jsonrpc_~d" code))))

(defparameter +missing-actor-message+
  "Mangler eller ugyldig X-Tun-Actor (forventet rolle:navn, rolle er admin, employee eller viewer)")

(defun encoded-response (json record)
  "Values JSON, a JSON-RPC response, and its text.  When it cannot be encoded
(a definition left a value JSON has no form for), RECORD's request ends as
an error and the response is a -32603 error instead."
  (handler-case (values json (to-json-string json))
    (error (e)
      (ignore-errors (format *error-output* "~&;; tun mcp: the response cannot be encoded: ~a~%" e))
      (set-request-outcome record "error" :code :internal-error
                                          :message (format nil "Svaret kan ikke skrives som JSON: ~a" e))
      (let ((failure (rpc-error-response (jget json "id") -32603
                                         "Intern feil: svaret kan ikke skrives som JSON")))
        (values failure (to-json-string failure))))))

(defun handle-mcp (application actor body &key credential (parsed nil parsed-p))
  "Handle one POST /mcp, BODY its octets or text, as ACTOR, which the transport
established (an ACTOR, or NIL when a claimed X-Tun-Actor was missing or
malformed) with CREDENTIAL; with PARSED, the body's JSON the transport has
already parsed, which is never parsed again
(spec/auth.md 7).  Returns (values http-status response-json-or-nil
session-id-or-nil response-text-or-nil).  Every /mcp request is retained
(core.md §8.1, §8.4): a record is opened here, and the operation a tools/call
runs takes it over; the response is encoded inside it, so a response that
cannot be is that request's error."
  (check-type actor (or null actor))
  (let ((*request-id* (or *request-id* (new-id "req")))
        (*credential* credential))
    (with-request-record (:id *request-id* :kind :mcp :claimable t :application application
                          :at (let ((*application* application)) (now))
                          :actor (and actor (actor-string actor)) :credential credential
                          :tool "mcp" :input (jobj))
      (let ((record *request-record*))
        (multiple-value-bind (status json session)
            (%handle-mcp application actor body parsed parsed-p)
          ;; A JSON-RPC error no operation recorded: unknown tool or method, bad JSON, no actor.
          (let ((err (and json (jget json "error"))))
            (when (and err (not (request-outcome record)))
              (set-request-outcome record "error" :code (rpc-code-name (jget err "code"))
                                                  :message (jget err "message"))))
          (if json
              (multiple-value-bind (json text) (encoded-response json record)
                (values status json session text))
              (values status nil session nil)))))))

(defparameter +too-many-values+
  (format nil "Forespørselen har for mange JSON-verdier (høyst ~,,' :d)."
          +max-request-json-values+)
  "Why a body with more JSON values than a request may hold is refused (core.md §7.5).")

(defun %handle-mcp (application actor body parsed parsed-p)
  "Without an actor the body is not parsed at all (the error carries id null).
With PARSED-P, PARSED is the body's JSON, whatever its kind."
  (unless actor
    (return-from %handle-mcp
      (values 200 (rpc-error-response nil -32000 +missing-actor-message+) nil)))
  (let ((request (handler-case (if parsed-p parsed (parse-request-json body))
                   (json-too-many-values ()
                     (return-from %handle-mcp
                       (values 413 (rpc-error-response nil -32600 +too-many-values+) nil)))
                   (json-number-out-of-range (refusal)
                     (return-from %handle-mcp
                       (values 200 (rpc-error-response nil -32700 (json-number-message refusal))
                               nil)))
                   (json-parse-failure ()
                     (return-from %handle-mcp
                       (values 200 (rpc-error-response nil -32700 "Ugyldig JSON") nil))))))
    (unless (hash-table-p request)
      (return-from %handle-mcp
        (values 200 (rpc-error-response nil -32600 "Forespørselen må være ett JSON-RPC-objekt (batch støttes ikke)") nil)))
    (multiple-value-bind (id has-id) (jget request "id")
      (let ((method (jget request "method"))
            (params (jget request "params" (jobj))))
        (cond
          ((or (not (equal (jget request "jsonrpc") "2.0")) (not (stringp method))
               (and has-id (not (valid-id-p id))))
           (values 200 (rpc-error-response (and (valid-id-p id) id) -32600 "Ugyldig JSON-RPC-forespørsel") nil))
          ;; Notifications (no id) get no body.
          ((not has-id) (values 202 nil nil))
          (t
           (handler-case
               (let ((result (dispatch application actor method
                                       (if (hash-table-p params) params (jobj)))))
                 (values 200 (rpc-result id result)
                         (and (string= method "initialize") (new-id "mcp"))))
             (rpc-error (e) (values 200 (rpc-error-response id (rpc-error-code e) (rpc-error-message e)) nil))
             (actor-error (e) (values 200 (rpc-error-response id -32000 (actor-error-message e)) nil))
             ;; SERIOUS-CONDITION, not just ERROR: a stack or heap
             ;; exhaustion fails this request alone (core.md §7.4).
             (serious-condition (e)
               (ignore-errors (format *error-output* "~&;; tun mcp: internal ~a in ~a: ~a~%"
                                      (type-of e) method e))
               (values 200 (rpc-error-response id -32603 "Intern feil") nil)))))))))
