;;;; agent/http.lisp -- the HTTP server: one Hunchentoot acceptor serving
;;;; POST /mcp (agents), POST /api/TOOL (other systems, spec/api.md) and the
;;;; generated UI (people).  Hunchentoot's
;;;; one-thread-per-connection taskmaster gives truly concurrent requests.

(defpackage #:tun.http
  (:use #:cl #:tun.core)
  (:export #:start-server #:stop-server #:server-port #:tun-acceptor #:acceptor-application
           #:dispatch-web #:register-json-endpoint #:same-origin-p #:header-utf-8
           #:https-request-p #:public-url))

(in-package #:tun.http)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *max-body-bytes* (* 2 1024 1024))
(defparameter *max-header-bytes* (* 64 1024)
  "Budget for the request line plus all header lines of one request.")
(defparameter *max-header-lines* 100
  "Most lines (request line + headers) one request may send before its body.")

;;; ------------------------------------------------------------------
;;; Bounded connection streams.  Hunchentoot and Chunga read the request line
;;; and headers into strings without limit, so every connection is wrapped in
;;; a stream with a byte budget: *MAX-HEADER-BYTES* until the headers are
;;; read, then raised by the accepted Content-Length for the body, and reset
;;; for the next request on a kept-alive connection.  Overflow answers 431
;;; and drops the connection.

(define-condition request-too-large (error) ()
  (:report "Request line or headers exceed the size limit"))

(defclass bounded-stream (sb-gray:fundamental-binary-input-stream sb-gray:fundamental-binary-output-stream)
  ((inner :initarg :inner :reader bounded-inner)
   (used :initform 0 :accessor bounded-used)
   (limit :initform *max-header-bytes* :accessor bounded-limit)
   (lines :initform 0 :accessor bounded-lines
          :documentation "Line feeds seen while still in the header phase (NIL once the body may be read).")))

(defun bounded-overflow (stream)
  (ignore-errors
   (write-sequence (sb-ext:string-to-octets
                    (format nil "HTTP/1.1 431 Request Header Fields Too Large~c~cConnection: close~c~cX-Tun-Request-Id: ~a~c~cContent-Length: 0~c~c~c~c"
                            #\Return #\Newline #\Return #\Newline (new-id "req") #\Return #\Newline
                            #\Return #\Newline #\Return #\Newline)
                    :external-format :latin-1)
                   (bounded-inner stream))
   (finish-output (bounded-inner stream)))
  (error 'request-too-large))

(defmethod stream-element-type ((stream bounded-stream)) '(unsigned-byte 8))
(defmethod open-stream-p ((stream bounded-stream)) (open-stream-p (bounded-inner stream)))
(defmethod close ((stream bounded-stream) &key abort) (close (bounded-inner stream) :abort abort))

(defmethod sb-gray:stream-read-byte ((stream bounded-stream))
  (when (>= (bounded-used stream) (bounded-limit stream))
    (bounded-overflow stream))
  (let ((byte (read-byte (bounded-inner stream) nil :eof)))
    (unless (eq byte :eof)
      (incf (bounded-used stream))
      (when (and (eql byte 10) (bounded-lines stream)
                 (> (incf (bounded-lines stream)) *max-header-lines*))
        (bounded-overflow stream)))
    byte))

(defmethod sb-gray:stream-read-sequence ((stream bounded-stream) sequence &optional (start 0) end)
  (let* ((end (or end (length sequence)))
         (room (- (bounded-limit stream) (bounded-used stream))))
    (when (and (< start end) (<= room 0))
      (bounded-overflow stream))
    (let ((position (read-sequence sequence (bounded-inner stream)
                                   :start start :end (min end (+ start (max room 0))))))
      (incf (bounded-used stream) (- position start))
      position)))

(defmethod sb-gray:stream-listen ((stream bounded-stream)) (listen (bounded-inner stream)))
(defmethod sb-gray:stream-write-byte ((stream bounded-stream) byte)
  (write-byte byte (bounded-inner stream)))
(defmethod sb-gray:stream-write-sequence ((stream bounded-stream) sequence &optional (start 0) end)
  (write-sequence sequence (bounded-inner stream) :start start :end end))
(defmethod sb-gray:stream-finish-output ((stream bounded-stream)) (finish-output (bounded-inner stream)))
(defmethod sb-gray:stream-force-output ((stream bounded-stream)) (force-output (bounded-inner stream)))
(defmethod sb-gray:stream-clear-output ((stream bounded-stream)) (clear-output (bounded-inner stream)))

(defclass tun-acceptor (hunchentoot:acceptor)
  ((application :initarg :application :reader acceptor-application)
   (max-inflight :initarg :max-inflight :initform 64 :reader acceptor-max-inflight
                 :documentation "--max-inflight: requests processed at once; the rest get 503 at once.")
   (inflight :initform (list 0) :reader acceptor-inflight-cell))
  (:default-initargs :access-log-destination nil))

(defun inflight (acceptor) (car (acceptor-inflight-cell acceptor)))

(defun shed ()
  "503 at once: Retry-After 1 and the error overbelastet, as the API's error
document on /api/, else as a JSON-RPC error -32001."
  (setf (hunchentoot:return-code*) 503
        (hunchentoot:header-out "Retry-After") "1"
        (hunchentoot:content-type*) "application/json; charset=utf-8")
  (octets (to-json-string
           (if (string-prefix-p "/api/" (hunchentoot:script-name*))
               (jobj "error" (jobj "code" "unavailable" "message" "overbelastet"))
               (jobj "jsonrpc" "2.0" "id" :null
                     "error" (jobj "code" -32001 "message" "overbelastet"))))))

(defun call-bounded (acceptor function)
  "Run FUNCTION if fewer than MAX-INFLIGHT requests are being processed, else
shed.  A call that waits leaves the count while it waits (*IN-FLIGHT-CELL*,
spec/waiting.md 1)."
  (let ((cell (acceptor-inflight-cell acceptor)))
    (if (>= (sb-ext:atomic-incf (car cell)) (acceptor-max-inflight acceptor))
        (progn (sb-ext:atomic-decf (car cell)) (shed))
        (unwind-protect (let ((*in-flight-cell* cell)) (funcall function))
          (sb-ext:atomic-decf (car cell))))))

(defun octets (string) (sb-ext:string-to-octets string :external-format :utf-8))

(defun request-body-string ()
  (let ((raw (hunchentoot:raw-post-data :force-binary t)))
    (cond ((null raw) "")
          (t (handler-case (sb-ext:octets-to-string raw :external-format :utf-8)
               (error () "<invalid utf-8>"))))))

(defun header-utf-8 (name)
  "Header NAME decoded as UTF-8.  Hunchentoot reads header bytes as Latin-1;
re-encode them to the original octets and decode those as UTF-8 so an actor
like viewer:besøkende arrives intact.  Invalid UTF-8 is left as read."
  (let ((value (hunchentoot:header-in* name)))
    (when value
      (handler-case
          (if (every (lambda (c) (< (char-code c) 256)) value)
              (sb-ext:octets-to-string (sb-ext:string-to-octets value :external-format :latin-1)
                                       :external-format :utf-8)
              value)
        (error () value)))))

(defun body-length-problem (method)
  "An HTTP status when the request body must be refused, else NIL: 411 for
any Transfer-Encoding (chunked bodies would be read without bound) and for a
POST without Content-Length, 413 for a Content-Length above *MAX-BODY-BYTES*."
  (let* ((header (hunchentoot:header-in* :content-length))
         (length (and header (parse-integer header :junk-allowed t))))
    (cond ((hunchentoot:header-in* :transfer-encoding) 411)
          ((and length (> length *max-body-bytes*)) 413)
          ((and (eq method :post) (null length)) 411)
          (t nil))))

(defun refuse-body (status)
  "Answer STATUS without reading the body.  Hunchentoot's SEND-RESPONSE
otherwise reads the whole declared body (allocating it) before replying, on
any path; marking it consumed and closing the connection avoids that."
  (setf (slot-value hunchentoot:*request* 'hunchentoot::raw-post-data) t
        hunchentoot::*close-hunchentoot-stream* t
        hunchentoot::*finish-processing-socket* t
        (hunchentoot:header-out :connection) "close"
        (hunchentoot:return-code*) status)
  "")

(defun bearer-token ()
  "The token of the request's Authorization: Bearer header, or NIL."
  (let ((header (hunchentoot:header-in* :authorization)))
    (when (and header (< 7 (length header)) (string-equal "Bearer " header :end2 7))
      (string-trim " " (subseq header 7)))))

(defun same-origin-p (origin)
  "True when ORIGIN, an Origin header, is this server's own scheme://host:port
as the Host header names it."
  (let ((host (hunchentoot:header-in* :host)))
    (and host
         (member origin (list (format nil "http://~a" host) (format nil "https://~a" host))
                 :test #'string-equal)
         t)))

(defun site-url (acceptor path)
  "PATH at the public URL of ACCEPTOR's application, else at the scheme and
host this request came with."
  (or (public-url acceptor path)
      (format nil "~:[http~;https~]://~a~a" (https-request-p) (hunchentoot:header-in* :host) path)))

(defun oauth-caller (acceptor token)
  "Values the actor and credential of an AuthKit access TOKEN (spec/auth.md
5.1), or NIL and why not: :INVALID-TOKEN, :UNLINKED or :UNREACHABLE."
  (multiple-value-bind (actor credential detail)
      (with-application ((acceptor-application acceptor))
        (tun.auth:authenticate-oauth-token token (site-url acceptor "/mcp")))
    (cond (actor (values actor credential))
          (t (format *error-output* "~&;; tun auth: OAuth token refused: ~a~%" detail)
             (values nil (if (eq credential :invalid) :invalid-token credential))))))

(defun mcp-caller (acceptor)
  "Values the actor of this /mcp request and its credential (spec/auth.md 5).
A bearer token decides when there is one: Tun's own, else an AuthKit access
token.  Without one, a server with claimed identity takes X-Tun-Actor,
giving NIL when that is missing or malformed.  Otherwise there is no caller:
NIL and :NO-TOKEN, :INVALID-TOKEN, :UNLINKED or :UNREACHABLE."
  (let ((application (acceptor-application acceptor))
        (token (bearer-token)))
    (cond ((and token (string-prefix-p "tun_" token))
           (multiple-value-bind (actor id)
               (with-application (application) (tun.auth:authenticate-token token))
             (if actor (values actor id) (values nil :invalid-token))))
          (token (oauth-caller acceptor token))
          ((claimed-identity-p application)
           (let ((actor (parse-actor (header-utf-8 :x-tun-actor))))
             (values actor (and actor "claimed"))))
          (t (values nil :no-token)))))

(defun refuse-caller (application kind tool status code message &optional authenticate)
  "Answer this /mcp or /api request (KIND :MCP or :API, calling TOOL) with
STATUS without reading its body, retained as rejected with CODE: a JSON-RPC
error on /mcp, the error document on /api.  AUTHENTICATE is the
WWW-Authenticate challenge of a 401."
  (with-request-record (:id *request-id* :kind kind :tool tool :input (jobj)
                        :application application
                        :at (let ((*application* application)) (now)))
    (set-request-outcome *request-record* "rejected" :code code :message message))
  (refuse-body status)
  (when authenticate
    (setf (hunchentoot:header-out "WWW-Authenticate") authenticate))
  (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
  (octets (to-json-string
           (if (eq kind :mcp)
               (jobj "jsonrpc" "2.0" "id" :null "error" (jobj "code" -32000 "message" message))
               (jobj "error" (jobj "code" (json-name-of code) "message" message))))))

(defun oauth-on-p (acceptor)
  (with-application ((acceptor-application acceptor)) (tun.auth:oauth-strategy)))

(defun challenge (acceptor &optional error)
  "The WWW-Authenticate challenge of a 401 from /mcp: with ERROR, and, when
MCP clients sign in through WorkOS, where to find out how (spec/auth.md 5.1)."
  (format nil "Bearer realm=\"tun\"~@[, error=\"~a\"~]~@[, resource_metadata=\"~a\"~]"
          error (and (oauth-on-p acceptor)
                     (site-url acceptor "/.well-known/oauth-protected-resource"))))

(defun caller-refusal (acceptor credential)
  "Why a caller is refused whom MCP-CALLER gave CREDENTIAL, as values the
HTTP status, the code, the message and the WWW-Authenticate challenge; NIL
when the caller may go on."
  (case credential
    (:no-token
     (values 401 :unauthenticated "Mangler tilgangsnøkkel: send Authorization: Bearer <nøkkel>"
             (challenge acceptor)))
    (:invalid-token
     (values 401 :unauthenticated "Tilgangsnøkkelen er ukjent, utløpt eller trukket tilbake"
             (challenge acceptor "invalid_token")))
    (:unlinked
     (values 403 :unauthenticated
             (format nil "Logg inn i nettleseren først, på ~a, så kjenner Tun igjen ~
                          WorkOS-kontoen din" (site-url acceptor "/login"))))
    (:unreachable
     (values 503 :unauthenticated
             "Kan ikke sjekke nøkkelen hos WorkOS akkurat nå. Prøv igjen om litt."))))

(defun foreign-origin ()
  "The Origin of a request a browser sent from another site, else NIL.  Such
a page must not reach a server on the caller's machine or network (the MCP
transport's DNS rebinding rule), on /mcp and /api alike."
  (let ((origin (hunchentoot:header-in* :origin)))
    (and origin (not (same-origin-p origin)) origin)))

(defparameter +plain-wait-seconds+ 90
  "The longest a call waits when its answer is plain JSON: a proxy that drops
a connection silent for 100 seconds, as Cloudflare does, must not cut it
(spec/waiting.md 2, 3).")

(defun accepts-event-stream-p ()
  (let ((accept (hunchentoot:header-in* :accept)))
    (and accept (search "text/event-stream" accept) t)))

(defun write-event (stream text)
  "Write TEXT, the lines of one server-sent event, to STREAM, and send it now."
  (write-sequence (octets text) stream)
  (force-output stream))

(defun call-streaming (function)
  "Call FUNCTION, which handles one /mcp request and returns its HTTP status,
JSON, session and the JSON's text, with *AWAIT-HEARTBEAT* set: when a tool call waits long
enough for it to beat, the answer becomes an SSE stream, carrying progress
(or, without a progressToken, a comment) at each beat and the JSON-RPC
response as its last event (spec/waiting.md 2).  Values what FUNCTION
returned, or NIL when the stream already holds the answer."
  (let ((stream nil))
    (flet ((beat (seconds)
             (unless stream
               (setf (hunchentoot:return-code*) 200
                     (hunchentoot:content-type*) "text/event-stream"
                     (hunchentoot:header-out "Cache-Control") "no-cache"
                     stream (hunchentoot:send-headers)))
             (write-event stream (if tun.mcp:*progress-token*
                                     (format nil "event: message~%data: ~a~%~%"
                                             (to-json-string
                                              (tun.mcp:progress-notification seconds)))
                                     (format nil ": venter ~d s~%~%" seconds)))))
      (multiple-value-bind (status json session text)
          (let ((*await-heartbeat* #'beat)) (funcall function))
        (cond ((null stream) (values status json session text))
              (t (when text
                   (write-event stream (format nil "event: message~%data: ~a~%~%" text)))
                 nil))))))

(defun serve-mcp (acceptor)
  (let ((application (acceptor-application acceptor)))
    (when (foreign-origin)
      (return-from serve-mcp
        (refuse-caller application :mcp "mcp" 403 :forbidden
                       (format nil "Forespørsler fra en annen nettside (~a) avvises"
                               (foreign-origin)))))
    (multiple-value-bind (actor credential) (mcp-caller acceptor)
      (multiple-value-bind (status code message authenticate) (caller-refusal acceptor credential)
        (if status
            (refuse-caller application :mcp "mcp" status code message authenticate)
            (multiple-value-bind (status json session text)
                (flet ((handle ()
                         (tun.mcp:handle-mcp application actor (request-body-string)
                                             :credential credential)))
                  (if (accepts-event-stream-p)
                      (call-streaming #'handle)
                      (let ((*await-limit* +plain-wait-seconds+)) (handle))))
              (cond ((null status) nil)   ; streamed
                    (t (setf (hunchentoot:return-code*) status)
                       (when session (setf (hunchentoot:header-out "Mcp-Session-Id") session))
                       (cond (json
                              (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
                              (octets text))
                             (t (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
                                ""))))))))))

;;; ------------------------------------------------------------------
;;; The HTTP API (spec/api.md): POST /api/TOOL calls one tool, its body the
;;; arguments and its answer the result.  Like the MCP adapter it only
;;; translates; CALL-TOOL holds the policy, idempotency and audit.

(defun api-answer (status json)
  (setf (hunchentoot:return-code*) status
        (hunchentoot:content-type*) "application/json; charset=utf-8")
  (octets (to-json-string json)))

(defun api-failure (status code message)
  "Answer STATUS with the error document CODE and MESSAGE, and give the
request that outcome when no operation gave it one."
  (unless (request-outcome *request-record*)
    (set-request-outcome *request-record* (if (< status 500) "rejected" "error")
                         :code code :message message))
  (api-answer status (jobj "error" (jobj "code" code "message" message))))

(defun api-arguments (body)
  "The arguments a request's BODY holds, a JSON object; {} for an empty body.
NIL when it is not an object."
  (if (zerop (length (string-trim '(#\Space #\Tab #\Return #\Newline) body)))
      (jobj)
      (let ((json (handler-case (parse-json body) (json-parse-failure () nil))))
        (and (hash-table-p json) json))))

(defun call-api (application actor credential tool)
  "Call TOOL as ACTOR with the request body's arguments, retained as a
request of kind api that the operation takes over."
  (let ((*credential* credential))
    (with-request-record (:id *request-id* :kind :api :claimable t :application application
                          :at (let ((*application* application)) (now))
                          :actor (actor-string actor) :credential credential
                          :tool tool :input (jobj))
      (let ((arguments (api-arguments (request-body-string))))
        (if (null arguments)
            (api-failure 400 "invalid_json" "Innholdet må være ett JSON-objekt: verktøyets argumenter")
            (progn
              (setf (request-input *request-record*) (recorded-input (make-input arguments)))
              (handler-case
                  (api-answer 200 (call-tool tool arguments :application application :actor actor))
                (operation-error (e)
                  (api-answer (error-status (operation-error-code e)) (operation-error-json e)))
                (unknown-tool ()
                  (api-failure 404 "unknown_tool" (format nil "Ukjent verktøy: ~a" tool)))
                ;; SERIOUS-CONDITION, as on /mcp: a stack or heap exhaustion
                ;; fails this request alone.
                (serious-condition (e)
                  (ignore-errors (format *error-output* "~&;; tun api: internal ~a in ~a: ~a~%"
                                         (type-of e) tool e))
                  (api-failure 500 "internal_error" "Intern feil")))))))))

(defun serve-api (acceptor tool)
  "POST /api/TOOL (spec/api.md): who calls is decided as on /mcp."
  (let ((application (acceptor-application acceptor)))
    (when (foreign-origin)
      (return-from serve-api
        (refuse-caller application :api tool 403 :forbidden
                       (format nil "Forespørsler fra en annen nettside (~a) avvises"
                               (foreign-origin)))))
    (multiple-value-bind (actor credential) (mcp-caller acceptor)
      (multiple-value-bind (status code message authenticate) (caller-refusal acceptor credential)
        (cond (status
               (refuse-caller application :api tool status code message authenticate))
              ;; Claimed identity without a usable X-Tun-Actor.
              ((null actor)
               (refuse-caller application :api tool 401 :unauthenticated
                              tun.mcp:+missing-actor-message+))
              ;; A long poll, held to what a proxy lets stay silent.
              (t (let ((*await-limit* +plain-wait-seconds+))
                   (call-api application actor credential tool))))))))

(defparameter +protected-resource-paths+
  '("/.well-known/oauth-protected-resource" "/.well-known/oauth-protected-resource/mcp"))

(defun serve-well-known (acceptor path)
  "The OAuth discovery documents for MCP clients (spec/auth.md 5.1), public
and readable from any page; 404 without a WorkOS strategy."
  (flet ((answer (status &optional json)
           (setf (hunchentoot:return-code*) status
                 (hunchentoot:header-out "Access-Control-Allow-Origin") "*")
           (cond (json (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
                       (octets (to-json-string json)))
                 (t ""))))
    (with-application ((acceptor-application acceptor))
      (let ((strategy (tun.auth:oauth-strategy)))
        (cond ((null strategy) (answer 404))
              ((member path +protected-resource-paths+ :test #'string=)
               (answer 200 (tun.auth:protected-resource-metadata strategy
                                                                 (site-url acceptor "/mcp"))))
              ((string= path "/.well-known/oauth-authorization-server")
               (handler-case (answer 200 (tun.auth:authorization-server-metadata strategy))
                 (tun.auth:provider-failure (e)
                   (format *error-output* "~&;; tun auth: ~a~%" e)
                   (answer 502))))
              (t (answer 404)))))))

(defmethod hunchentoot:initialize-connection-stream ((acceptor tun-acceptor) stream)
  (make-instance 'bounded-stream :inner (call-next-method)))

(defmethod hunchentoot:reset-connection-stream ((acceptor tun-acceptor) stream)
  (let ((stream (call-next-method)))
    (when (typep stream 'bounded-stream)
      (setf (bounded-used stream) 0
            (bounded-lines stream) 0
            (bounded-limit stream) *max-header-bytes*))
    stream))

(defun allow-body (length)
  "Raise the connection's budget so a body of LENGTH bytes can be read."
  (let ((stream (hunchentoot::content-stream hunchentoot:*request*)))
    (when (typep stream 'bounded-stream)
      (setf (bounded-lines stream) nil
            (bounded-limit stream) (+ (bounded-used stream) length)))))

(defgeneric dispatch-web (acceptor method path)
  (:documentation "Hook for the generated UI (tun.web); NIL means not handled.")
  (:method (acceptor method path) (declare (ignore acceptor method path)) nil))

(defmethod hunchentoot:acceptor-dispatch-request ((acceptor tun-acceptor) request)
  ;; Every response carries X-Tun-Request-Id (core.md §8.1): the handle for
  ;; introspect_request.  The same id is the request's *REQUEST-ID*.
  (let ((*request-id* (new-id "req")))
    (setf (hunchentoot:header-out "X-Tun-Request-Id") *request-id*)
    ;; Hunchentoot handles ERROR; a stack or heap exhaustion while handling
    ;; must also end as a 500 for this request, not reach the debugger.
    (handler-case (dispatch-request acceptor request)
      (serious-condition (c)
        (ignore-errors (format *error-output* "~&;; tun http: ~a while handling ~a: ~a~%"
                               (type-of c) (hunchentoot:script-name request) c))
        (setf (hunchentoot:return-code*) 500)
        ""))))

(defun https-request-p ()
  "True when the browser reached us over HTTPS, directly or through the proxy."
  (or (hunchentoot:ssl-p)
      (string-equal (hunchentoot:header-in* :x-forwarded-proto) "https")))

(defun public-url (acceptor path)
  "PATH at the public URL of ACCEPTOR's application, or NIL when it has none."
  (let ((base (application-public-url (acceptor-application acceptor))))
    (and base (concatenate 'string base path))))

(defun https-upgrade (acceptor method)
  "When the application's public URL is https: mark an HTTPS answer for
browsers to keep to HTTPS, and send a GET or HEAD the proxy says came over
plain HTTP to the same place at the public URL (spec/deploy.md 1).  The
redirect's location, or NIL."
  (let ((base (application-public-url (acceptor-application acceptor))))
    (when (and base (string-prefix-p "https://" base))
      (cond ((https-request-p)
             (setf (hunchentoot:header-out "Strict-Transport-Security") "max-age=31536000")
             nil)
            ((and (member method '(:get :head))
                  (string-equal (hunchentoot:header-in* :x-forwarded-proto) "http"))
             (public-url acceptor (hunchentoot:request-uri*)))))))

(defun dispatch-request (acceptor request)
  (let* ((path (hunchentoot:script-name request))
         (method (hunchentoot:request-method request))
         (upgrade (https-upgrade acceptor method)))
    (cond ((body-length-problem method)        ; first: before anything reads the body
           (refuse-body (body-length-problem method)))
          ((string= path "/health")
           (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
           "ok")
          (upgrade
           (setf (hunchentoot:return-code*) 301
                 (hunchentoot:header-out :location) upgrade)
           "")
          (t (call-bounded acceptor (lambda () (dispatch-bounded acceptor request)))))))

(defvar *json-endpoints* (make-hash-table :test 'equal))
(defun register-json-endpoint (path handler)
  (when (gethash path *json-endpoints*) (extension-error "HTTP endpoint ~a is already registered" path))
  (setf (gethash path *json-endpoints*) handler))
(defun serve-json-endpoint (acceptor handler)
  (handler-case
      (with-application ((acceptor-application acceptor))
        (let ((body (parse-json (hunchentoot:raw-post-data :force-text t))))
          (multiple-value-bind (status result)
              (funcall handler body
                (let ((header (hunchentoot:header-in* "X-Tun-Inbound-Secret")))
                  (when header
                    (handler-case
                        (sb-ext:octets-to-string (sb-ext:string-to-octets header :external-format :latin-1)
                                                :external-format :utf-8)
                      (error () nil)))))
            (setf (hunchentoot:return-code*) status (hunchentoot:content-type*) "application/json; charset=utf-8")
            (to-json-string result))))
    (operation-error (error)
      (setf (hunchentoot:return-code*) 422 (hunchentoot:content-type*) "application/json; charset=utf-8")
      (to-json-string (operation-error-json error)))
    (error ()
      (setf (hunchentoot:return-code*) 422 (hunchentoot:content-type*) "application/json; charset=utf-8")
      (to-json-string (jobj "error" (jobj "code" "invalid_input" "message" "Ugyldig JSON"))))))

(defun dispatch-bounded (acceptor request)
  (let ((path (hunchentoot:script-name request))
        (method (hunchentoot:request-method request)))
    (let ((length (hunchentoot:header-in* :content-length)))
      (when (and length (not (body-length-problem method)))
        (allow-body (or (parse-integer length :junk-allowed t) 0))))
    (cond ((body-length-problem method)
           (refuse-body (body-length-problem method)))
          ((string= path "/mcp")
           (if (eq method :post)
               (serve-mcp acceptor)
               (progn (setf (hunchentoot:return-code*) 405
                            (hunchentoot:header-out "Allow") "POST")
                      "")))
          ((string-prefix-p "/api/" path)
           (if (eq method :post)
               (serve-api acceptor (subseq path (length "/api/")))
               (progn (setf (hunchentoot:return-code*) 405
                            (hunchentoot:header-out "Allow") "POST")
                      "")))
          ((string= path "/health")
           (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
           "ok")
          ((and (eq method :get) (string-prefix-p "/.well-known/" path))
           (serve-well-known acceptor path))
          ((and (eq method :post) (gethash path *json-endpoints*))
           (serve-json-endpoint acceptor (gethash path *json-endpoints*)))
          ((with-request-record (:id *request-id* :kind :web
                                 :tool (format nil "web:~a ~a" method path)
                                 :application (acceptor-application acceptor)
                                 :at (let ((*application* (acceptor-application acceptor))) (now)))
             (dispatch-web acceptor method path)))
          (t (setf (hunchentoot:return-code*) 404)
             ""))))

(defparameter *max-threads* 1024
  "Connection threads Hunchentoot may run. Well above --max-inflight, so excess
requests reach our JSON 503 instead of Hunchentoot's own plain 503.")

(defun start-server (application &key (port 8080) (address "127.0.0.1") (max-inflight 64))
  ;; Forms and query strings arrive without a charset; read them as UTF-8.
  (setf hunchentoot:*hunchentoot-default-external-format* (flex:make-external-format :utf-8 :eol-style :lf))
  (let ((acceptor (make-instance 'tun-acceptor :application application
                                               :port port :address address
                                               :max-inflight max-inflight
                                               :listen-backlog 1024
                                               :taskmaster (make-instance 'hunchentoot:one-thread-per-connection-taskmaster
                                                                          :max-thread-count *max-threads*
                                                                          :max-accept-count (+ *max-threads* 64))
                                               :message-log-destination *error-output*)))
    (hunchentoot:start acceptor)
    ;; For introspect_runtime: the bound and the live count.
    (setf (application-max-inflight application) max-inflight
          (application-inflight-cell application) (acceptor-inflight-cell acceptor))
    acceptor))

(defun stop-server (acceptor)
  (hunchentoot:stop acceptor :soft t))

(defun server-port (acceptor)
  (hunchentoot:acceptor-port acceptor))
