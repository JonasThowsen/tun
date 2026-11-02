;;;; outbound/outbound.lisp -- calling other systems' JSON APIs
;;;; (spec/outbound.md).
;;;;
;;;; HTTP-JSON-POST posts a JSON body and returns the parsed answer, or
;;;; signals REMOTE-FAILURE, an operation error with code unavailable, so a
;;;; client either handles it or lets the operation fail.  HTTP-JSON-GET is
;;;; the same call as a GET, with a query and no body.  The call runs in
;;;; a bounded thread of its own (CALL-WITH-TIME-LIMIT, as mail delivery
;;;; does), held to the operation's deadline, and is one :external step in
;;;; the request's trace.  A test answers for the other system by binding
;;;; *HTTP-JSON-HANDLER*.
;;;;
;;;; HTTP-POST is the same call for Tun's own ports whose body is not JSON,
;;;; such as a push notification (spec/outbound.md 5): it answers any
;;;; status and leaves its meaning to the port.
;;;;
;;;; Running a program on the server, the same idea for a command-line
;;;; tool, is in programs.lisp (spec/outbound.md 6).

(defpackage #:tun.outbound
  (:use #:cl #:tun.core)
  (:export #:http-json-post #:http-json-get #:*http-json-handler* #:http-post
           #:query-string
           #:remote-failure #:remote-failure-status #:remote-failure-body #:remote-failure-url
           #:run-program #:*program-handler* #:missing-programs
           #:program-failure #:program-failure-name #:program-failure-output
           #:program-failure-error-output))

(in-package #:tun.outbound)

(declaim (optimize (safety 3) (debug 2)))

(defvar *http-json-handler* nil
  "NIL, or a function of the URL, the body and the headers that answers in
place of the network, with the status (NIL for no answer) and the body as a
JSON value or a text (spec/outbound.md 4).")

(defparameter +connect-seconds+ 3
  "How long a call has to connect.  A system that is up connects in well under
a second.  usocket on SBCL reports a refused connection only when this time
runs out, so it is kept shorter than a call's whole time.")

(defparameter +deadline-margin-seconds+ 1
  "How much of the operation's deadline a call leaves, so the operation can
still answer when the other system does not.")

(define-condition remote-failure (operation-error)
  ((url :initarg :url :reader remote-failure-url)
   (status :initarg :status :initform nil :reader remote-failure-status
           :documentation "The answer's status, or NIL when no answer came.")
   (body :initarg :body :initform nil :reader remote-failure-body
         :documentation "The answer's body as JSON, else as text; NIL without an answer."))
  (:default-initargs :code :unavailable)
  (:documentation "A call to another system that did not give a usable answer."))

;;; ------------------------------------------------------------------
;;; The URL, as messages and the trace show it

(defparameter +url-scanner+
  (cl-ppcre:create-scanner "^(https?://)(?:[^\\s/?#@]*@)?([^\\s/?#@]+)([^\\s?#]*)")
  "The scheme, an optional user and password (dropped), the host and port,
and the path.")

(defun url-parts (url)
  "Values the scheme, the host and the path of URL, or NIL when it is not an
http or https URL."
  (cl-ppcre:register-groups-bind (scheme host path) (+url-scanner+ url)
    (values scheme host path)))

(defun url-host (url)
  (nth-value 1 (url-parts url)))

(defun shown-url (url)
  "URL without a user and password or a query, either of which may hold a key."
  (multiple-value-bind (scheme host path) (url-parts url)
    (concatenate 'string scheme host path)))

(defun remote-failure (url status body control &rest arguments)
  (error 'remote-failure :url url :status status :body body
         :message (format nil "~a ~?" (url-host url) control arguments)))

;;; ------------------------------------------------------------------
;;; A query

(defun url-encode (string)
  "STRING percent-encoded as RFC 3986 wants a query value: UTF-8, every byte
but the unreserved characters escaped."
  (with-output-to-string (out)
    (loop for byte across (sb-ext:string-to-octets string :external-format :utf-8)
          for char = (code-char byte)
          do (if (or (char<= #\a char #\z) (char<= #\A char #\Z) (char<= #\0 char #\9)
                     (find char "-._~"))
                 (write-char char out)
                 (format out "%~2,'0X" byte)))))

(defun query-string (parameters)
  "PARAMETERS, an alist of strings, as a URL query without the ?."
  (format nil "~{~a~^&~}"
          (mapcar (lambda (pair)
                    (format nil "~a=~a" (url-encode (car pair)) (url-encode (cdr pair))))
                  parameters)))

(defun url-with-query (url query)
  "URL without its fragment, with QUERY, an alist of strings, appended after
?, or after & when URL has a query already, or after nothing when URL ends
in either (spec/outbound.md 1.2)."
  (let* ((url (subseq url 0 (position #\# url)))
         (last (and (plusp (length url)) (char url (1- (length url))))))
    (cond ((null query) url)
          ((member last '(#\? #\&)) (concatenate 'string url (query-string query)))
          ((find #\? url) (concatenate 'string url "&" (query-string query)))
          (t (concatenate 'string url "?" (query-string query))))))

(defun check-query (query)
  "Signal an error unless QUERY is an alist of strings."
  (unless (and (listp query)
               (every (lambda (pair)
                        (and (consp pair) (stringp (car pair)) (stringp (cdr pair))))
                      query))
    (error "http-json-get: the query is an alist of strings, not ~s" query)))

;;; ------------------------------------------------------------------
;;; One call

(defun check-call (caller url headers timeout)
  "Signal an error naming CALLER unless URL, HEADERS and TIMEOUT are what a
call takes."
  (unless (and (stringp url) (url-parts url))
    (error "~(~a~): ~s is not an http or https URL" caller url))
  (unless (every (lambda (header)
                   (and (consp header) (stringp (car header)) (stringp (cdr header))))
                 headers)
    (error "~(~a~): the headers are an alist of strings, not ~s" caller headers))
  (unless (typep timeout '(real 1 60))
    (error "~(~a~): the timeout is from 1 to 60 seconds, not ~s" caller timeout)))

(defun seconds-allowed (timeout)
  "TIMEOUT, held to the running operation's deadline less the margin."
  (let ((left (deadline-remaining-ms)))
    (if left
        (min timeout (- (/ left 1000) +deadline-margin-seconds+))
        timeout)))

(defun url-on-the-wire (url)
  "URL as the request sends it (spec/outbound.md 1): without its fragment,
and with / for an empty path.  drakma, sending a URL as written, takes its
path to be everything after the host up to a /, so https://host?q=1 would
be sent as / and lose its query."
  (let* ((url (subseq url 0 (position #\# url)))
         (host (+ (search "://" url) 3))
         (path (position-if (lambda (char) (member char '(#\/ #\?))) url :start host)))
    (if (and path (char= (char url path) #\?))
        (concatenate 'string (subseq url 0 path) "/" (subseq url path))
        url)))

(defun user-agent-header-p (header)
  (string-equal "User-Agent" (car header)))

(defun request-over-network (method url content content-type accept headers seconds)
  "Send a request with METHOD, :GET or :POST, to URL, with CONTENT, a text or
octets, as CONTENT-TYPE, or with neither for a GET, asking for ACCEPT.  The
first User-Agent in HEADERS takes the place of drakma's own, which drakma
would otherwise send beside it (spec/outbound.md 1.3).
Values the status and the body's text.  Runs in the bounded thread: SBCL's
deadline ends a read that drakma, which has no read timeout on SBCL, would
wait on for ever, so an abandoned call ends too.  SBCL signals
DEADLINE-TIMEOUT, which is not an error; the caller is given
DEADLINE-EXCEEDED, which is."
  (handler-case
      (sb-sys:with-deadline (:seconds seconds)
        (multiple-value-bind (body status)
            (drakma:http-request (url-on-the-wire url) :method method
                                 :content-type content-type
                                 :content content
                                 :accept accept
                                 :user-agent (or (cdr (find-if #'user-agent-header-p headers))
                                                 :drakma)
                                 :additional-headers (remove-if #'user-agent-header-p headers)
                                 :external-format-out :utf-8
                                 :force-binary t :redirect nil
                                 ;; As the caller wrote it: drakma would
                                 ;; otherwise escape a query's % escapes again.
                                 :preserve-uri t
                                 :verify :required
                                 :connection-timeout (min seconds +connect-seconds+))
          (values status (if body (sb-ext:octets-to-string body :external-format :utf-8) ""))))
    (sb-sys:deadline-timeout ()
      (error 'deadline-exceeded))))

(defun answer-from-network (method url content content-type accept headers seconds)
  "Values the status and the body's text of the call, or NIL, a message and
what the trace shows when no answer came."
  (if (not (provider-call-capacity-p))
      (values nil "ble ikke spurt: for mange kall til andre systemer pågår" "full")
      (handler-case (with-request-state (:external-call)
                      (call-with-time-limit
                       (lambda ()
                         (request-over-network method url content content-type accept
                                               headers seconds))
                       seconds))
        (deadline-exceeded ()
          (let ((whole (ceiling seconds)))
            (values nil (format nil "svarte ikke innen ~d ~:[sekunder~;sekund~]" whole (= whole 1))
                    "timeout")))
        (error (e)
          (values nil "kunne ikke nås" (princ-to-string e))))))

(defun answer-from-handler (handler url text headers)
  "What HANDLER, standing in for the other system, answers, as
ANSWER-FROM-NETWORK values it.  TEXT is the body sent, which HANDLER is given
parsed, or NIL for a GET, which has none."
  (multiple-value-bind (status answer) (funcall handler url (and text (parse-json text)) headers)
    (unless (or (null status) (typep status '(integer 100 599)))
      (error "*http-json-handler* answered the status ~s, not NIL or an HTTP status" status))
    (if status
        (values status answer)
        (values nil "svarte ikke" "no answer"))))

(defun answer-json (answer)
  "ANSWER, a body's text or a JSON value from a handler, as JSON, and
whether it is JSON."
  (cond ((not (stringp answer)) (values answer t))
        ((every (lambda (c) (member c '(#\Space #\Tab #\Return #\Newline))) answer)
         (values :null t))
        (t (handler-case (values (parse-json answer) t)
             (json-parse-failure () (values nil nil))))))

(defun recorded-call (name function)
  "Call FUNCTION, which makes one call to another system and values the
status and the answer, or NIL, a message and a detail; record it as the
:external step NAME in the trace.  Values the status and the answer, or NIL
and the message."
  (let ((started (trace-clock-us)))
    (multiple-value-bind (status answer detail) (funcall function)
      (note-step :external :name name :source :core
                 ;; What the other system answered is clipped as the trace shows it.
                 :detail (cond (status (princ-to-string status))
                               ((and (stringp detail) (> (length detail) 300))
                                (concatenate 'string (subseq detail 0 300) "…"))
                               (t detail))
                 :started started :duration (- (trace-clock-us) started))
      (values status answer))))

(defparameter +no-time-message+ "ble ikke spurt: operasjonen har under ett sekund igjen")

(defun http-post (url body &key headers (content-type "application/octet-stream") (timeout 10)
                             (name (format nil "POST ~a" (shown-url url))))
  "POST BODY, octets or a text, to URL as CONTENT-TYPE, with HEADERS (an
alist of strings), for Tun's own ports (spec/outbound.md 5).  Values the
status and the answer's text, whatever the status; or NIL and a message when
no answer came within TIMEOUT seconds (and the operation's deadline).  The
call is the :external step NAME in the trace."
  (check-call 'http-post url headers timeout)
  (let ((seconds (seconds-allowed timeout)))
    (recorded-call name (lambda ()
                          (if (< seconds 1)
                              (values nil +no-time-message+ "no time")
                              (answer-from-network :post url body content-type "*/*"
                                                   headers seconds))))))

(defun json-call (method url text headers timeout)
  "Send TEXT, a JSON text, or NIL for a GET, to URL with METHOD and HEADERS,
and value the answer's JSON and its status, or signal REMOTE-FAILURE
(spec/outbound.md 1)."
  (let ((seconds (seconds-allowed timeout))
        (handler *http-json-handler*))
    (multiple-value-bind (status answer)
        (recorded-call (format nil "~a ~a" method (shown-url url))
                       (lambda ()
                         (cond ((< seconds 1) (values nil +no-time-message+ "no time"))
                               (handler (answer-from-handler handler url text headers))
                               (t (answer-from-network method url text
                                                       (and text "application/json")
                                                       "application/json" headers seconds)))))
      (when (null status)
        (remote-failure url nil nil "~a" answer))
      (multiple-value-bind (json parsed) (answer-json answer)
        (cond ((not (<= 200 status 299))
               (remote-failure url status (if parsed json answer) "svarte ~d" status))
              ((not parsed)
               (remote-failure url status answer "svarte ~d, men ikke med JSON" status))
              (t (values json status)))))))

(defun http-json-post (url body &key headers (timeout 10))
  "POST BODY, a JSON value, to URL with HEADERS (an alist of strings).
Values the answer's JSON and its status.  Signals REMOTE-FAILURE without an
answer within TIMEOUT seconds (and the operation's deadline), or for a
status outside 200 to 299 or a body that is not JSON (spec/outbound.md 1)."
  (check-call 'http-json-post url headers timeout)
  (json-call :post url (to-json-string body) headers timeout))

(defun http-json-get (url &key query headers (timeout 10))
  "GET URL with QUERY appended, an alist of names and values that are
percent-encoded, and with HEADERS (an alist of strings).  Values the
answer's JSON and its status, and signals REMOTE-FAILURE, whose URL is the
one sent, as HTTP-JSON-POST does (spec/outbound.md 1.2)."
  (check-call 'http-json-get url headers timeout)
  (check-query query)
  (json-call :get (url-with-query url query) nil headers timeout))
