;;;; agent/http.lisp -- the HTTP server: one Hunchentoot acceptor serving
;;;; POST /mcp (agents), POST /api/TOOL (other systems, spec/api.md) and the
;;;; generated UI (people).  Hunchentoot's
;;;; one-thread-per-connection taskmaster gives truly concurrent requests.

(defpackage #:tun.http
  (:use #:cl #:tun.core)
  (:export #:start-server #:stop-server #:server-port #:tun-acceptor #:acceptor-application
           #:dispatch-web #:register-json-endpoint #:same-origin-p #:header-utf-8
           #:https-request-p #:public-url #:mcp-caller #:close-after-answer
           #:upload-admission #:upload-refusal #:signed-in-p #:*posted-files*
           #:*large-body-bytes* #:*multipart-body-bytes* #:*large-body-places*
           #:*large-body-seconds* #:*small-body-seconds* #:*header-seconds*
           #:*place-body-bytes* #:*connections-per-address* #:*requests-per-address*
           #:parse-ip-address #:address-key))

(in-package #:tun.http)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *max-body-bytes* (* 2 1024 1024))
(defparameter *max-header-bytes* (* 32 1024)
  "Budget for the request line plus all header lines of one request: kept as
text while it is read, about four times as much heap (core.md §7.5).")
(defparameter *max-header-lines* 100
  "Most lines (request line + headers) one request may send before its body.")

;;; Bodies that carry files (spec/files.md 4.3).
(defparameter *large-body-bytes* (* 16 1024 1024)
  "The largest body to /mcp, or to /api for a tool that takes files.")
(defparameter *multipart-body-bytes* (* 26 1024 1024)
  "The largest multipart/form-data body to a page.")
(defparameter *large-body-places* 4
  "How many requests with a body over *MAX-BODY-BYTES* are answered at once.")
(defparameter *large-body-seconds* 120
  "How long a body over *PLACE-BODY-BYTES* has to arrive, from when it is read.")
(defparameter *small-body-seconds* 30
  "How long a body of at most *PLACE-BODY-BYTES* has to arrive, from when it is read.")
(defparameter *header-seconds* 30
  "How long a request line and its headers have to arrive, from their first byte.")

;;; ------------------------------------------------------------------
;;; Bounded connection streams.  Hunchentoot and Chunga read the request line
;;; and headers into strings without limit, so every connection is wrapped in
;;; a stream with a byte budget: *MAX-HEADER-BYTES* until the headers are
;;; read, then raised by the accepted Content-Length for the body, and reset
;;; for the next request on a kept-alive connection.  Overflow answers 431
;;; and drops the connection.

(define-condition request-too-large (error) ()
  (:report "Request line or headers exceed the size limit"))

(define-condition request-too-slow (error) ()
  (:report "Request line or headers did not arrive in time"))

(defclass bounded-stream (sb-gray:fundamental-binary-input-stream sb-gray:fundamental-binary-output-stream)
  ((inner :initarg :inner :reader bounded-inner)
   (used :initform 0 :accessor bounded-used)
   (limit :initform *max-header-bytes* :accessor bounded-limit)
   (lines :initform 0 :accessor bounded-lines
          :documentation "Line feeds seen while still in the header phase (NIL once the
body may be read).")
   (close-after :initform nil :accessor bounded-close-after
                :documentation "True when the connection ends after the answer being made.")
   (header-deadline :initform nil :accessor bounded-header-deadline
                    :documentation "When the request line and headers being read must
have arrived, in internal real time; NIL before their first byte.")
   (unread :initform 0 :accessor bounded-unread
           :documentation "How many octets of a body left unread may still come
before the connection ends.")))

(defun answer-and-drop (stream status condition)
  "Answer STATUS (431 or 408) on STREAM before a request's headers are read,
with no body, and signal CONDITION, which ends the connection."
  ;; The client may be gone; the connection ends either way.
  (ignore-errors
   (write-sequence (sb-ext:string-to-octets
                    (format nil "HTTP/1.1 ~d ~a~c~cConnection: close~c~cX-Tun-Request-Id: ~a~c~c~
                                 Content-Length: 0~c~c~c~c"
                            status (if (= status 431)
                                       "Request Header Fields Too Large"
                                       "Request Timeout")
                            #\Return #\Newline #\Return #\Newline (new-id "req") #\Return #\Newline
                            #\Return #\Newline #\Return #\Newline)
                    :external-format :latin-1)
                   (bounded-inner stream))
   (finish-output (bounded-inner stream)))
  (error condition))

(defun bounded-overflow (stream)
  (answer-and-drop stream 431 'request-too-large))

(defmethod stream-element-type ((stream bounded-stream)) '(unsigned-byte 8))
(defmethod open-stream-p ((stream bounded-stream)) (open-stream-p (bounded-inner stream)))
(defmethod close ((stream bounded-stream) &key abort) (close (bounded-inner stream) :abort abort))

(defun header-timeout (stream)
  "Answer 408 on STREAM, whose request line and headers did not arrive in
*HEADER-SECONDS*, and end its connection."
  (answer-and-drop stream 408 'request-too-slow))

(defun read-header-byte (stream)
  "The next byte of the request line or headers on STREAM, or :EOF, read by
the deadline their first byte set: a sender that trickles them is answered
408.  A byte already at hand is read without a deadline."
  (let ((inner (bounded-inner stream))
        (deadline (bounded-header-deadline stream)))
    (cond ((or (null deadline) (listen inner)) (read-byte inner nil :eof))
          (t (let ((left (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)))
               (when (<= left 0) (header-timeout stream))
               (handler-case (sb-sys:with-deadline (:seconds left) (read-byte inner nil :eof))
                 (sb-sys:deadline-timeout () (header-timeout stream))))))))

(defmethod sb-gray:stream-read-byte ((stream bounded-stream))
  (when (>= (bounded-used stream) (bounded-limit stream))
    (bounded-overflow stream))
  (let ((byte (if (bounded-lines stream)
                  (read-header-byte stream)
                  (read-byte (bounded-inner stream) nil :eof))))
    (unless (eq byte :eof)
      (incf (bounded-used stream))
      (when (bounded-lines stream)
        ;; The first byte of a request starts the clock for its headers.
        (unless (bounded-header-deadline stream)
          (setf (bounded-header-deadline stream)
                (+ (get-internal-real-time) (* *header-seconds* internal-time-units-per-second))))
        (when (and (eql byte 10) (> (incf (bounded-lines stream)) *max-header-lines*))
          (bounded-overflow stream))))
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
   (inflight :initform (list 0) :reader acceptor-inflight-cell)
   (large-bodies :initform (list 0) :reader acceptor-large-bodies-cell
                 :documentation "Requests with a body over *MAX-BODY-BYTES* being answered.")
   (trusted-proxy :initarg :trusted-proxy :initform nil :reader acceptor-trusted-proxy
                  :documentation "--trusted-proxy as an address's octets, or NIL: the peer
whose X-Forwarded-For names the client (core.md 7.5).")
   (connections :initform (make-key-counts "connections") :reader acceptor-connections
                :documentation "Open connections by the address of a peer that is not the proxy.")
   (proxied-requests :initform (make-key-counts "proxied requests")
                     :reader acceptor-proxied-requests
                     :documentation "Requests in progress through the proxy, by client address."))
  (:default-initargs :access-log-destination nil))

(defun inflight (acceptor) (car (acceptor-inflight-cell acceptor)))

(defun shed ()
  "503 at once, without reading the body: Retry-After 1 and the error
overbelastet, as the API's error document on /api/, else as a JSON-RPC
error -32001."
  (refuse-body 503)
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
shed.  A call that waits leaves the count while it waits (*WAITING-LEAVES*,
spec/waiting.md 1)."
  (let ((cell (acceptor-inflight-cell acceptor)))
    (if (>= (sb-ext:atomic-incf (car cell)) (acceptor-max-inflight acceptor))
        (progn (sb-ext:atomic-decf (car cell)) (shed))
        (unwind-protect
             (let ((*waiting-leaves* (cons (lambda (phase)
                                             (if (eq phase :leave)
                                                 (sb-ext:atomic-decf (car cell))
                                                 (sb-ext:atomic-incf (car cell))))
                                           *waiting-leaves*)))
               (funcall function))
          (sb-ext:atomic-decf (car cell))))))

;;; ------------------------------------------------------------------
;;; What one client address holds (core.md 7.5).  A connection from any
;;; peer but the trusted proxy counts against the peer's address while it is
;;; open; a request through the proxy counts against the client the proxy
;;; names while it is answered.  Addresses are octet vectors, as usocket
;;; gives them; a count's key is text.

(defparameter *connections-per-address* 64
  "Connections one address, not the trusted proxy's, may have open at once.")

(defparameter *requests-per-address* 16
  "Requests through the trusted proxy one client may have in progress at once.")

(defun parse-ipv4 (text)
  "TEXT, an IPv4 address in dotted decimal, as four octets, or NIL."
  (let ((parts (uiop:split-string text :separator ".")))
    (when (and (= 4 (length parts))
               (every (lambda (part)
                        (and (<= 1 (length part) 3) (every #'digit-char-p part)
                             (<= (parse-integer part) 255)))
                      parts))
      (map '(vector (unsigned-byte 8)) #'parse-integer parts))))

(defun parse-ipv6 (text)
  "TEXT, an IPv6 address, as sixteen octets, or NIL.  An IPv4 address may end
it, as in ::ffff:203.0.113.7."
  (let* ((colon (position #\: text :from-end t))
         (tail (and colon (find #\. text) (parse-ipv4 (subseq text (1+ colon)))))
         (text (if tail
                   (format nil "~a~x:~x" (subseq text 0 (1+ colon))
                           (+ (* 256 (aref tail 0)) (aref tail 1))
                           (+ (* 256 (aref tail 2)) (aref tail 3)))
                   text)))
    (when (and colon
               (<= 2 (length text) 39)
               (every (lambda (c) (or (digit-char-p c 16) (char= c #\:))) text)
               (every (lambda (group) (<= (length group) 4))
                      (uiop:split-string text :separator ":"))
               (<= (count-substrings "::" text) 1))
      ;; usocket's parser takes what the checks above leave, and signals on
      ;; the rest, such as too many groups: that is an answer, not an error.
      (handler-case (usocket:ipv6-host-to-vector text)
        (error () nil)))))

(defun count-substrings (part text)
  (loop for start = 0 then (1+ found)
        for found = (search part text :start2 start)
        while found
        count t))

(defun parse-ip-address (text)
  "TEXT, an IPv4 or IPv6 address, as its octets (4 or 16 of them), or NIL
when it is not one."
  (let ((text (string-trim " " text)))
    (or (parse-ipv4 text) (parse-ipv6 text))))

(defun ipv4-mapped-p (octets)
  "True for an IPv6 address that writes an IPv4 one, ::ffff:a.b.c.d."
  (and (= 16 (length octets))
       (every #'zerop (subseq octets 0 10))
       (= 255 (aref octets 10) (aref octets 11))))

(defun plain-address (octets)
  "OCTETS as the address they name: an IPv4 address written as IPv6 as its
four octets, any other address as it is."
  (if (ipv4-mapped-p octets) (subseq octets 12) octets))

(defun address-key (octets)
  "The text OCTETS, an address, count under: an IPv4 address itself, an IPv6
one its first 64 bits, the network one subscriber is commonly given."
  (let ((address (plain-address octets)))
    (if (= 4 (length address))
        (format nil "~{~d~^.~}" (coerce address 'list))
        (format nil "~{~(~x~)~^:~}::/64"
                (loop for i below 8 by 2
                      collect (+ (* 256 (aref address i)) (aref address (1+ i))))))))

(defun trusted-proxy-p (acceptor octets)
  "True when OCTETS, a peer's address, are ACCEPTOR's trusted proxy's."
  (let ((proxy (acceptor-trusted-proxy acceptor)))
    (and proxy octets (equalp proxy (plain-address octets)))))

(defun forwarded-address ()
  "The address the last entry of this request's X-Forwarded-For names, the
one the proxy wrote, as octets, or NIL without one."
  (let ((header (hunchentoot:header-in* :x-forwarded-for)))
    (and header
         (parse-ip-address (subseq header (1+ (or (position #\, header :from-end t) -1)))))))

(defun request-client (acceptor)
  "This request's client key, and whether it came through the trusted proxy:
then the address the proxy names, or the proxy's own without one; else its
peer's."
  (let ((peer (parse-ip-address (hunchentoot:remote-addr*))))
    (cond ((null peer) (values nil nil))
          ((trusted-proxy-p acceptor peer)
           (values (address-key (or (forwarded-address) peer)) t))
          (t (values (address-key peer) nil)))))

(defun call-as-client (acceptor function)
  "Call FUNCTION for this request's client: its waits count for it, and
through the trusted proxy it takes one of the client's
*REQUESTS-PER-ADDRESS* until the answer, leaving it while it waits.  With
none left, shed at once."
  (multiple-value-bind (client proxied) (request-client acceptor)
    (let ((*wait-client* client)
          (counts (acceptor-proxied-requests acceptor)))
      (cond ((not proxied) (funcall function))
            ((take-count counts client *requests-per-address*)
             (unwind-protect
                  (let ((*waiting-leaves*
                          (cons (lambda (phase)
                                  ;; Back over the bound or not: a finished
                                  ;; wait is never refused its answer.
                                  (if (eq phase :leave)
                                      (give-back-count counts client)
                                      (take-count counts client nil)))
                                *waiting-leaves*)))
                    (funcall function))
               (give-back-count counts client)))
            (t (shed))))))

(defun socket-peer (socket)
  "The address SOCKET's peer has, as octets, or NIL when the connection has
ended already."
  (handler-case (usocket:get-peer-address socket)
    (error () nil)))

(defparameter +address-refusal+
  (sb-ext:string-to-octets
   (format nil "HTTP/1.1 503 Service Unavailable~c~cRetry-After: 1~c~cConnection: close~c~c~
                Content-Length: 0~c~c~c~c"
           #\Return #\Newline #\Return #\Newline #\Return #\Newline #\Return #\Newline
           #\Return #\Newline)
   :external-format :latin-1)
  "The answer to a connection past its address's *CONNECTIONS-PER-ADDRESS*.")

(defun refuse-connection (socket)
  "Answer 503 on SOCKET, whose address has its connections, and close it.
What the caller has sent so far, at most *MAX-HEADER-BYTES*, is read and
dropped first, as closing with it unread would reset the connection and
could lose the answer; nothing waits for more, so a refused connection
never holds its thread."
  (let ((stream (usocket:socket-stream socket)))
    ;; The caller may be gone: the connection ends either way.
    (ignore-errors
     (write-sequence +address-refusal+ stream)
     (finish-output stream)
     (loop repeat *max-header-bytes*
           while (listen stream)
           do (read-byte stream nil)))
    (ignore-errors (usocket:socket-close socket))))

(defmethod hunchentoot:process-connection :around ((acceptor tun-acceptor) socket)
  ;; Counted and given back in this one extent, so no way a connection
  ;; ends can leave its count behind.
  (let* ((peer (socket-peer socket))
         (address (and peer (not (trusted-proxy-p acceptor peer)) (address-key peer)))
         (counts (acceptor-connections acceptor)))
    (cond ((null address) (call-next-method))
          ((take-count counts address *connections-per-address*)
           (unwind-protect (call-next-method)
             (give-back-count counts address)))
          (t (refuse-connection socket)))))

(defun octets (string) (sb-ext:string-to-octets string :external-format :utf-8))

(defun request-body-octets ()
  "This request's body, read as octets: JSON is parsed from them as they are."
  (or (hunchentoot:raw-post-data :force-binary t)
      (make-array 0 :element-type '(unsigned-byte 8))))

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

(defun content-length ()
  "This request's Content-Length: NIL without one, :INVALID when it is not
plain digits (Hunchentoot joins repeated headers with commas, so several
values are not), else its value."
  (let ((header (hunchentoot:header-in* :content-length)))
    (cond ((null header) nil)
          ((or (zerop (length header)) (notevery (lambda (c) (char<= #\0 c #\9)) header)) :invalid)
          ;; Longer than any bound: no need to read every digit.
          ((> (length header) 15) most-positive-fixnum)
          (t (parse-integer header)))))

(defun multipart-request-p ()
  "True for a multipart/form-data request: a form that may carry files."
  (let ((type (hunchentoot:header-in* :content-type)))
    (and type (string-prefix-p "multipart/form-data" (string-downcase (trim type))))))

(defgeneric upload-admission (acceptor path)
  (:documentation "Whether this request's session lets it post files to PATH
(spec/files.md 4.3): :ADMITTED, :REFUSED when the page at PATH does not
admit the person's role, :NO-SESSION without a signed-in person, or
:CROSS-ORIGIN for a post another site's page sent.  The web UI decides;
without it no one may.")
  (:method (acceptor path)
    (declare (ignore acceptor path))
    :no-session))

(defgeneric upload-refusal (acceptor status message)
  (:documentation "The answer's body when a page's post is refused with STATUS
and MESSAGE before its body is read, or when its parts cannot be read: the
web UI answers a page.  The default answers MESSAGE as text.")
  (:method (acceptor status message)
    (declare (ignore acceptor status))
    (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
    message))

(defun files-caller-p (acceptor tool &optional (actor (mcp-caller acceptor)))
  "True when ACTOR, this request's caller, may send a body that carries files:
TOOL, a tool's name, takes files and admits the caller's role, or, with TOOL
NIL (/mcp), some tool that takes files does."
  (let ((application (acceptor-application acceptor)))
    (and actor
         (some (lambda (op)
                 (and op (tun.files:operation-takes-files-p op)
                      (operation-visible-p op application)
                      (actor-permits-p actor (operation-policy op))))
               (if tool (list (find-operation-by-tool tool)) (all-operations)))
         t)))

(defun web-post-path-p (path)
  "True for a POST to a page: not /mcp or /api, which take JSON."
  (not (or (string= path "/mcp") (string-prefix-p "/api/" path))))

(defparameter +cross-origin-refused+
  (deferred-tr "The form came from another site and was refused.")
  "What a page's multipart post another site sent is told.")

(defparameter *place-body-bytes* (* 256 1024)
  "A body over this takes one of the *LARGE-BODY-PLACES* before it is read:
what reading and parsing a body costs grows with it (core.md §7.5).")

(defparameter +anonymous-large-refused+
  (deferred-tr "Without being signed in you can send at most 256 KB.")
  "Why a page's body over *PLACE-BODY-BYTES* from no known caller is refused.")

(defgeneric signed-in-p (acceptor)
  (:documentation "True when this request carries the session of a signed-in
person (or, with claimed identity, a claimed actor).  The web UI decides;
without it no one is.")
  (:method (acceptor)
    (declare (ignore acceptor))
    nil))

(defun body-decision (acceptor path method)
  "Values the most octets this request's body may have; the status it is
refused with before the body is read, or NIL; for a page's post the
refusal's message when it is not the status's usual one; and whether the
request takes one of the *LARGE-BODY-PLACES* (core.md §7.5, spec/files.md
4.3).  It refuses 400 for a Content-Length that is not plain digits, 411
for any Transfer-Encoding (chunked bodies would be read without bound) and
for a POST without Content-Length, 401 or 403 for a multipart post another
site sent or without a person who may send files there, and 413 for a body
over its bound, or over *PLACE-BODY-BYTES* from a caller with no session,
token or port secret (KNOWN-CALLER-P).  Every body over *PLACE-BODY-BYTES*
takes a place."
  (let* ((length (content-length))
         (placed (and (integerp length) (> length *place-body-bytes*))))
    (cond ((eq length :invalid) (values 0 400))
          ((hunchentoot:header-in* :transfer-encoding) (values 0 411))
          ((and (eq method :post) (null length)) (values 0 411))
          ((null length) (values 0 nil))
          ((and (eq method :post) (multipart-request-p) (web-post-path-p path))
           (let ((admission (upload-admission acceptor path)))
             (cond ((eq admission :cross-origin) (values 0 403 +cross-origin-refused+))
                   ((eq admission :no-session) (values 0 401))
                   ((<= length *max-body-bytes*) (values *max-body-bytes* nil nil placed))
                   ((eq admission :refused) (values 0 403))
                   ((> length *multipart-body-bytes*) (values 0 413))
                   (t (values *multipart-body-bytes* nil nil t)))))
          ((and placed (not (known-caller-p acceptor path)))
           (values 0 413 +anonymous-large-refused+))
          ((<= length *max-body-bytes*) (values *max-body-bytes* nil nil placed))
          ((and (eq method :post) (<= length *large-body-bytes*)
                (or (and (string= path "/mcp") (files-caller-p acceptor nil))
                    (and (string-prefix-p "/api/" path) (files-caller-p acceptor (subseq path 5)))))
           (values *large-body-bytes* nil nil t))
          (t (values 0 413)))))

(defun large-body-p ()
  "True when this request's body is over the usual bound: one that carries files."
  (let ((length (content-length)))
    (and length (> length *max-body-bytes*))))

(defun close-after-answer (&optional (unread 0))
  "End this request's connection once its answer is sent, whatever the
client asked: what it sends next, such as an unread body, is never read as
another request.  Hunchentoot decides keep-alive only as it sends the
headers, so the connection's stream carries the decision to
RESET-CONNECTION-STREAM, which ends the connection after the answer, and
first drops up to UNREAD octets of a body the client may still be sending."
  (setf hunchentoot::*close-hunchentoot-stream* t)
  (unless hunchentoot::*headers-sent*
    (setf (hunchentoot:header-out :connection) "close"))
  (let ((stream (connection-stream (hunchentoot::content-stream hunchentoot:*request*))))
    (when stream
      (setf (bounded-close-after stream) t
            (bounded-unread stream) unread))))

(defun connection-stream (stream)
  "The connection's BOUNDED-STREAM under STREAM, which may be it or the
chunked stream Hunchentoot puts over it for a chunked body; NIL when it is
neither."
  (typecase stream
    (bounded-stream stream)
    (chunga:chunked-stream (connection-stream (chunga:chunked-stream-stream stream)))
    (t nil)))

(defun refuse-body (status)
  "Answer STATUS without reading the body, and end the connection after it.
Hunchentoot's SEND-RESPONSE otherwise reads the whole declared body
(allocating it) before replying, on any path, and keep-alive would read the
unread body as the next request; marking it consumed and closing the
connection avoids both."
  (setf (slot-value hunchentoot:*request* 'hunchentoot::raw-post-data) t
        (hunchentoot:return-code*) status)
  (close-after-answer (let ((length (content-length))) (if (integerp length) length 0)))
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
     (values 401 :unauthenticated "No access token: send Authorization: Bearer <token>"
             (challenge acceptor)))
    (:invalid-token
     (values 401 :unauthenticated "The access token is unknown, expired or revoked"
             (challenge acceptor "invalid_token")))
    (:unlinked
     (values 403 :unauthenticated
             (format nil "Sign in in the browser first, at ~a, so that Tun knows your ~
                          WorkOS account" (site-url acceptor "/login"))))
    (:unreachable
     (values 503 :unauthenticated
             "The token cannot be checked with WorkOS just now. Try again shortly."))))

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
                                     (format nil ": waiting ~d s~%~%" seconds)))))
      (multiple-value-bind (status json session text)
          (let ((*await-heartbeat* #'beat)) (funcall function))
        (cond ((null stream) (values status json session text))
              (t (when text
                   (write-event stream (format nil "event: message~%data: ~a~%~%" text)))
                 nil))))))

;;; A body that may carry files (spec/files.md 4.3), from a caller who may
;;; send them: it is parsed with the long strings a file's data needs, and
;;; refused unless that data is the only long string in it, keys included.

(defparameter +usual-string-length+ 1048576
  "The longest string anywhere but in a file's data (core.md §7.5).")

(defun short-string-p (string)
  "True when STRING is no longer than +USUAL-STRING-LENGTH+ and is not a
file's data set aside, which was."
  (and (<= (length string) +usual-string-length+)
       (not (tun.files:set-aside-p string))))

(defun short-json-p (json)
  "True when no string in JSON, value or key, is longer than +USUAL-STRING-LENGTH+."
  (cond ((stringp json) (short-string-p json))
        ((hash-table-p json)
         (loop for key being the hash-keys of json using (hash-value value)
               always (and (short-string-p key) (short-json-p value))))
        ((vectorp json) (every #'short-json-p json))
        (t t)))

(defun short-except-p (object long-key)
  "True when OBJECT, a JSON object, has no long string but under LONG-KEY."
  (loop for key being the hash-keys of object using (hash-value value)
        always (and (short-string-p key)
                    (or (equal key long-key) (short-json-p value)))))

(defun short-file-p (file)
  "True when FILE, one item of a FILES value, has no long string but a
string under data."
  (if (hash-table-p file)
      (loop for key being the hash-keys of file using (hash-value value)
            always (and (short-string-p key)
                        (or (and (equal key "data") (stringp value)) (short-json-p value))))
      (short-json-p file)))

(defun only-file-data-long-p (arguments op)
  "True when no string in ARGUMENTS, OP's, is long but a file's data in one
of OP's parameters of type FILES."
  (loop for key being the hash-keys of arguments using (hash-value value)
        for parameter = (find key (operation-parameters op) :key #'parameter-json-name
                                                            :test #'string=)
        always (and (short-string-p key)
                    (if (and parameter (tun.files:files-parameter-p parameter) (vectorp value))
                        (every #'short-file-p value)
                        (short-json-p value)))))

(defun parse-file-json (body)
  "Values BODY, its files' data set aside, parsed, and :PARSED; or NIL and
:NOT-JSON, or NIL and :TOO-MANY when it holds more values than a request
may."
  (handler-case (values (parse-request-json body) :parsed)
    (json-too-many-values () (values nil :too-many))
    (json-parse-failure () (values nil :not-json))))

(defun call-with-file-data-set-aside (function)
  "Call FUNCTION with this request's body, each long string in it a file's
data set aside (TUN.FILES:SET-ASIDE-FILE-DATA) for the call to read; or
with NIL when what is left is longer than *MAX-BODY-BYTES*, which is all a
body may hold besides its files' data."
  (let* ((tun.files:*set-aside* (make-hash-table :test 'equal))
         (rest (tun.files:set-aside-file-data (request-body-octets))))
    (funcall function (and (<= (length rest) *max-body-bytes*) rest))))

(defparameter +rest-too-long+ "Besides its files' content, a request can be at most 2 MB."
  "Why a body is refused when what it holds besides its files' data is over 2 MiB.")

(defparameter +large-body-refused+ "More than 2 MB is taken only for a tool that takes files."
  "Why a body over 2 MiB that does not call a tool that takes files is refused.")

(defparameter +long-string-refused+ "Only a file's content can be longer than 1 MB."
  "Why a body with a long string that is not a file's data is refused.")

(defun files-call-refusal (request)
  "Why REQUEST, a /mcp body parsed by PARSE-FILE-JSON, is refused, or NIL:
a body over 2 MiB must be one tools/call of a tool that takes files, and no
string in it but its files' data may be long."
  (let* ((params (and (hash-table-p request) (jget request "params")))
         (name (and (hash-table-p params) (jget params "name")))
         (op (and (stringp name) (find-operation-by-tool name)))
         (arguments (and op (jget params "arguments")))
         (files-call (and (equal (jget request "method") "tools/call")
                          op (tun.files:operation-takes-files-p op) (hash-table-p arguments))))
    (cond ((and (large-body-p) (not files-call)) +large-body-refused+)
          ((short-json-p request) nil)
          ((and files-call
                (short-except-p request "params")
                (short-except-p params "arguments")
                (only-file-data-long-p arguments op))
           nil)
          (t +long-string-refused+))))

(defun refuse-files-call (application message)
  "Answer a /mcp body FILES-CALL-REFUSAL refuses: 413, with the JSON-RPC
error -32600 and MESSAGE, retained as a rejected request."
  (with-request-record (:id *request-id* :kind :mcp :tool "mcp" :input (jobj)
                        :application application
                        :at (let ((*application* application)) (now)))
    (set-request-outcome *request-record* "rejected" :code :invalid-input :message message))
  (setf (hunchentoot:return-code*) 413
        (hunchentoot:content-type*) "application/json; charset=utf-8")
  (octets (to-json-string (jobj "jsonrpc" "2.0" "id" :null
                                "error" (jobj "code" -32600 "message" message)))))

(defun answer-mcp (acceptor actor credential body &optional (parsed nil parsed-p))
  "Answer BODY, a /mcp request's octets, as ACTOR; with PARSED, its JSON
already parsed, never parsed again."
  (let ((application (acceptor-application acceptor)))
    (multiple-value-bind (status json session text)
        (flet ((handle ()
                 (if parsed-p
                     (tun.mcp:handle-mcp application actor body :credential credential
                                                                :parsed parsed)
                     (tun.mcp:handle-mcp application actor body :credential credential))))
          (if (accepts-event-stream-p)
              (call-streaming #'handle)
              (let ((*await-limit* +plain-wait-seconds+)) (handle))))
      (cond ((null status) nil)         ; streamed
            (t (setf (hunchentoot:return-code*) status)
               (when session (setf (hunchentoot:header-out "Mcp-Session-Id") session))
               (cond (json
                      (setf (hunchentoot:content-type*) "application/json; charset=utf-8")
                      (octets text))
                     (t (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
                        "")))))))

(defun serve-mcp (acceptor)
  (let ((application (acceptor-application acceptor)))
    (when (foreign-origin)
      (return-from serve-mcp
        (refuse-caller application :mcp "mcp" 403 :forbidden
                       (format nil "Requests from another site (~a) are refused"
                               (foreign-origin)))))
    (multiple-value-bind (actor credential) (mcp-caller acceptor)
      (multiple-value-bind (status code message authenticate) (caller-refusal acceptor credential)
        (cond (status
               (refuse-caller application :mcp "mcp" status code message authenticate))
              ((files-caller-p acceptor nil actor)
               ;; A caller who may send files: a file's data may be long.
               (call-with-file-data-set-aside
                (lambda (body)
                  (multiple-value-bind (request outcome)
                      (if body (parse-file-json body) (values nil :too-long))
                    (let ((refusal (case outcome
                                     (:too-long +rest-too-long+)
                                     (:too-many tun.mcp:+too-many-values+)
                                     (:parsed (files-call-refusal request))
                                     (t (and (large-body-p) +large-body-refused+)))))
                      (cond (refusal (refuse-files-call application refusal))
                            ((eq outcome :parsed)
                             (answer-mcp acceptor actor credential body request))
                            (t (answer-mcp acceptor actor credential body))))))))
              (t (answer-mcp acceptor actor credential (request-body-octets))))))))

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
  "The arguments a request's BODY, its octets, holds, a JSON object; {} for
an empty body.  NIL when it is not an object, :TOO-MANY when it holds more
values than a request may, or the JSON-NUMBER-OUT-OF-RANGE refusal of a
number in it (core.md §7.5)."
  (if (every (lambda (octet) (member octet '(32 9 13 10))) body)
      (jobj)
      (let ((json (handler-case (parse-request-json body)
                    (json-too-many-values () :too-many)
                    (json-number-out-of-range (refusal) refusal)
                    (json-parse-failure () nil))))
        (and (or (hash-table-p json) (eq json :too-many) (typep json 'json-number-out-of-range))
             json))))

(defun call-api (application actor credential tool)
  "Call TOOL as ACTOR with the request body's arguments, retained as a
request of kind api that the operation takes over.  For a tool that takes
files, from a caller it admits, the files' data is set aside before the
body is parsed, and the body refused when anything else is long
(spec/files.md 4.3)."
  (let ((*credential* credential))
    (with-request-record (:id *request-id* :kind :api :claimable t :application application
                          :at (let ((*application* application)) (now))
                          :actor (actor-string actor) :credential credential
                          :tool tool :input (jobj))
      (let* ((op (find-operation-by-tool tool))
             (files (and op (tun.files:operation-takes-files-p op)
                         (actor-permits-p actor (operation-policy op)))))
        (if files
            (call-with-file-data-set-aside
             (lambda (body)
               (if body
                   (answer-api application actor tool op t (api-arguments body))
                   (api-failure 413 "invalid_input" +rest-too-long+))))
            (answer-api application actor tool op nil (api-arguments (request-body-octets))))))))

(defun answer-api (application actor tool op files arguments)
  "Answer the call of TOOL, OP's, as ACTOR with ARGUMENTS, what API-ARGUMENTS
made of the body; FILES when the body may carry files."
  (cond
    ((null arguments)
     (api-failure 400 "invalid_json" "The body must be one JSON object: the tool's arguments"))
    ((eq arguments :too-many)
     (api-failure 413 "invalid_input" tun.mcp:+too-many-values+))
    ((typep arguments 'json-number-out-of-range)
     (api-failure 400 "invalid_json" (json-number-message arguments)))
    ((and files (not (only-file-data-long-p arguments op)))
     (api-failure 413 "invalid_input" +long-string-refused+))
    (t
     (setf (request-input *request-record*) (recorded-input (make-input arguments) op))
     (handler-case
         (api-answer 200 (call-tool tool arguments :application application :actor actor))
       (operation-error (e)
         (api-answer (error-status (operation-error-code e))
                     (with-language (:source) (operation-error-json e))))
       (unknown-tool ()
         (api-failure 404 "unknown_tool" (format nil "Unknown tool: ~a" (shown-name tool))))
       ;; SERIOUS-CONDITION, as on /mcp: a stack or heap exhaustion fails
       ;; this request alone.
       (serious-condition (e)
         (ignore-errors (format *error-output* "~&;; tun api: internal ~a in ~a: ~a~%"
                                (type-of e) tool e))
         (api-failure 500 "internal_error" "Internal error"))))))

(defun serve-api (acceptor tool)
  "POST /api/TOOL (spec/api.md): who calls is decided as on /mcp."
  (let ((application (acceptor-application acceptor)))
    (when (foreign-origin)
      (return-from serve-api
        (refuse-caller application :api tool 403 :forbidden
                       (format nil "Requests from another site (~a) are refused"
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

(defparameter *drain-seconds* 2
  "How long the rest of a refused body is read and dropped before its
connection closes.")

(defun drain-unread (stream)
  "Read and drop the rest of a body left unread on STREAM, a BOUNDED-STREAM:
its BOUNDED-UNREAD octets, at most *MULTIPART-BODY-BYTES*, for at most
*DRAIN-SECONDS*.  Closed while the client still sends, the connection would
be reset, and the client could lose the answer it was sent."
  (let ((buffer (make-array (min 65536 (max 1 (bounded-unread stream)))
                            :element-type '(unsigned-byte 8)))
        (left (min (bounded-unread stream) *multipart-body-bytes*)))
    (handler-case
        (sb-sys:with-deadline (:seconds *drain-seconds*)
          (loop for read = (if (plusp left)
                               (read-sequence buffer (bounded-inner stream)
                                              :end (min left (length buffer)))
                               0)
                while (plusp read)
                do (decf left read)))
      ((or error sb-sys:deadline-timeout) () nil))))

(defmethod hunchentoot:reset-connection-stream ((acceptor tun-acceptor) stream)
  (let* ((stream (call-next-method))
         (bounded (connection-stream stream)))
    (cond ((null bounded))
          ((bounded-close-after bounded)
           ;; CLOSE-AFTER-ANSWER: Hunchentoot's loop ends here and closes.
           (drain-unread bounded)
           (setf hunchentoot::*finish-processing-socket* t))
          (t (setf (bounded-used bounded) 0
                   (bounded-lines bounded) 0
                   (bounded-header-deadline bounded) nil
                   (bounded-limit bounded) *max-header-bytes*)))
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
    (prog1 (handler-case (call-as-client acceptor
                                         (lambda () (dispatch-request acceptor request)))
             (serious-condition (c)
               ;; Reporting must not fail the answer: the condition may not print.
               (ignore-errors (format *error-output* "~&;; tun http: ~a while handling ~a: ~a~%"
                                      (type-of c) (hunchentoot:script-name request) c))
               (setf (hunchentoot:return-code*) 500)
               ""))
      (leave-unread-body))))

(defun leave-unread-body ()
  "When this request declared a body that nothing read, such as a post to
/health or one sent to HTTPS, end the connection after the answer instead:
Hunchentoot would otherwise read the body before it answers, with no
deadline but its read timeout (core.md §7.5)."
  (let ((length (content-length)))
    (when (and (integerp length) (plusp length)
               (null (slot-value hunchentoot:*request* 'hunchentoot::raw-post-data)))
      (setf (slot-value hunchentoot:*request* 'hunchentoot::raw-post-data) t)
      (close-after-answer length))))

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

(defparameter +upload-refusals+
  (list (cons 400 (deferred-tr "The form did not arrive whole. Try again."))
        (cons 401 (deferred-tr "You must be signed in to send files. Sign in and try again."))
        (cons 403 (deferred-tr "This page is not for you, so it takes no files from you."))
        (cons 413 (deferred-tr "The form is too large: at most 25 MB of files at a time."))
        (cons 503 (deferred-tr "The server is taking many files now. Try again in a moment.")))
  "What a page's multipart post refused before its body is read is told.")

(defun page-text (acceptor text)
  "TEXT, a TEXT or a string, written for a page of ACCEPTOR's application in
its tenant's language: a refusal answered before any request reads the
tenant's settings."
  (with-application ((acceptor-application acceptor))
    (let ((*locale* (or *locale* (request-locale))))
      (render-text text))))

(defun refuse-request (acceptor status &optional message)
  "Answer STATUS without reading the body: to a page's multipart post, or a
page's post refused with MESSAGE, a page that says why (UPLOAD-REFUSAL),
with MESSAGE or the status's own."
  (refuse-body status)
  (when (= status 503)
    (setf (hunchentoot:header-out "Retry-After") "1"))
  (if (and (web-post-path-p (hunchentoot:script-name*)) (or (multipart-request-p) message))
      (upload-refusal acceptor status
                      (page-text acceptor (or message (cdr (assoc status +upload-refusals+)))))
      ""))

(defun dispatch-request (acceptor request)
  (let* ((path (hunchentoot:script-name request))
         (method (hunchentoot:request-method request))
         (upgrade (https-upgrade acceptor method)))
    (multiple-value-bind (bound refusal message placed) (body-decision acceptor path method)
      (cond (refusal                    ; first: before anything reads the body
             (refuse-request acceptor refusal message))
            ((string= path "/health")
             (setf (hunchentoot:content-type*) "text/plain; charset=utf-8")
             "ok")
            (upgrade
             (setf (hunchentoot:return-code*) 301
                   (hunchentoot:header-out :location) upgrade)
             "")
            (t (call-bounded acceptor
                             (lambda () (dispatch-bounded acceptor request bound placed))))))))

(defvar *json-endpoints* (make-hash-table :test 'equal)
  "Path -> (HANDLER . AUTHORIZE) of each JSON port REGISTER-JSON-ENDPOINT made.")

(defun register-json-endpoint (path handler &key authorize)
  "Serve POST PATH with HANDLER, a function of the body's JSON and the
X-Tun-Inbound-Secret header's value that values a status and a JSON
answer.  AUTHORIZE, when given, is a function of that secret, called before
the body is parsed: NIL answers 403 and the body is never parsed."
  (when (gethash path *json-endpoints*) (extension-error "HTTP endpoint ~a is already registered" path))
  (setf (gethash path *json-endpoints*) (cons handler authorize)))

(defun inbound-secret ()
  "The X-Tun-Inbound-Secret header as UTF-8, or NIL."
  (let ((header (hunchentoot:header-in* "X-Tun-Inbound-Secret")))
    (when header
      (handler-case
          (sb-ext:octets-to-string (sb-ext:string-to-octets header :external-format :latin-1)
                                   :external-format :utf-8)
        (error () nil)))))

(defun serve-json-endpoint (acceptor endpoint)
  "Answer a POST to ENDPOINT, (HANDLER . AUTHORIZE) of REGISTER-JSON-ENDPOINT."
  (destructuring-bind (handler . authorize) endpoint
    (flet ((answer (status json)
             (setf (hunchentoot:return-code*) status
                   (hunchentoot:content-type*) "application/json; charset=utf-8")
             (to-json-string json)))
      (handler-case
          (with-application ((acceptor-application acceptor))
            (let ((secret (inbound-secret)))
              (if (and authorize (not (funcall authorize secret)))
                  (answer 403 (jobj "error" (jobj "code" "forbidden"
                                                  "message" "Invalid secret")))
                  (multiple-value-call #'answer
                    (funcall handler (parse-request-json (request-body-octets)) secret)))))
        (operation-error (error)
          (answer 422 (with-language (:source) (operation-error-json error))))
        (json-number-out-of-range (refusal)
          (answer 400 (jobj "error" (jobj "code" "invalid_json"
                                          "message" (json-number-message refusal)))))
        (json-too-many-values ()
          (answer 413 (jobj "error" (jobj "code" "invalid_input"
                                          "message" tun.mcp:+too-many-values+))))
        (error ()
          (answer 422 (jobj "error" (jobj "code" "invalid_input" "message" "Invalid JSON"))))))))

(defun known-caller-p (acceptor path)
  "True when this request to PATH comes from a caller Tun knows before its
body is read: on /mcp and /api a token (or a claimed actor), on a JSON
port with :AUTHORIZE its secret, elsewhere a signed-in person's session
(SIGNED-IN-P).  Only such a caller may send a body over *PLACE-BODY-BYTES*
(core.md §7.5)."
  (let ((endpoint (gethash path *json-endpoints*)))
    (cond ((or (string= path "/mcp") (string-prefix-p "/api/" path))
           (and (mcp-caller acceptor) t))
          (endpoint
           (and (cdr endpoint)
                (handler-case (with-application ((acceptor-application acceptor))
                                (funcall (cdr endpoint) (inbound-secret)))
                  (error () nil))
                t))
          (t (signed-in-p acceptor)))))

(defun call-with-large-place (acceptor function)
  "Call FUNCTION holding one of the *LARGE-BODY-PLACES* until it returns: the
place is taken before the body is read and kept while the request is
answered (spec/files.md 4.3).  With every place taken, answer 503 without
reading the body."
  (let ((cell (acceptor-large-bodies-cell acceptor)))
    (if (> (sb-ext:atomic-incf (car cell)) (1- *large-body-places*))
        (progn (sb-ext:atomic-decf (car cell))
               (if (web-post-path-p (hunchentoot:script-name*))
                   (refuse-request acceptor 503)
                   ;; As the error document on /api, a JSON-RPC error on /mcp.
                   (shed)))
        (unwind-protect (funcall function)
          (sb-ext:atomic-decf (car cell))))))

(defun read-body-in-time (seconds)
  "Read this request's body within SECONDS; NIL when it did not arrive in
time, whether it came too slowly or stopped coming, which the connection's
read timeout ends.  Hunchentoot keeps what was read for RAW-POST-DATA.
SBCL's deadline ends only a blocking read of the connection, so nothing
else is unwound."
  (handler-case (sb-sys:with-deadline (:seconds seconds)
                  (hunchentoot:raw-post-data :force-binary t)
                  t)
    ((or sb-sys:deadline-timeout sb-sys:io-timeout) () nil)))

(defvar *posted-files* '()
  "While a page's multipart post is answered: its parts with a file, as
(NAME FILENAME HANDLE) in order, each HANDLE in TUN.FILES:*UPLOADS*.")

(defun call-with-posted-form (acceptor function)
  "Call FUNCTION with this multipart post's parts read (spec/files.md 4.3):
its text parts as Hunchentoot's post parameters, its files in *POSTED-FILES*.
A post Tun does not read is answered with a page that says why."
  (handler-case
      (multiple-value-bind (texts files)
          (let ((body (or (hunchentoot:raw-post-data :force-binary t)
                          (make-array 0 :element-type '(unsigned-byte 8)))))
            ;; Marked as read and its parts given as the post parameters, so
            ;; Hunchentoot never parses the body itself, which would write
            ;; every file to a temporary file.
            (setf (slot-value hunchentoot:*request* 'hunchentoot::raw-post-data) t)
            (tun.files:parse-multipart
             body (tun.files:multipart-boundary (hunchentoot:header-in* :content-type))))
        (setf (slot-value hunchentoot:*request* 'hunchentoot::post-parameters) texts)
        (let* ((tun.files:*uploads* (make-hash-table :test 'equal))
               (*posted-files* (loop for (name filename octets) in files
                                     collect (list name filename
                                                   (tun.files:register-upload filename octets)))))
          (funcall function)))
    (tun.files:multipart-refused (refusal)
      (setf (hunchentoot:return-code*) (tun.files:multipart-refused-status refusal))
      (upload-refusal acceptor (tun.files:multipart-refused-status refusal)
                      (page-text acceptor (tun.files:multipart-refused-message refusal))))))

(defparameter +most-form-pairs+ 1000 "The most fields a urlencoded post has.")
(defparameter +most-form-name+ 1024 "The longest name of a urlencoded post's field.")
(defparameter +most-form-value+ (* 1024 1024) "The longest value of a urlencoded post's field.")

(defun urlencoded-request-p ()
  "True for an application/x-www-form-urlencoded request: a plain form."
  (let ((type (hunchentoot:header-in* :content-type)))
    (and type (string-prefix-p "application/x-www-form-urlencoded" (string-downcase (trim type))))))

(defun walk-form-text (octets start end emit)
  "Call EMIT with each character's code that OCTETS from START to END encode
in a urlencoded form: + is a space, %XX an octet, and the octets UTF-8,
each invalid sequence one U+FFFD.  Nothing is made on the way."
  (let ((i start))
    (labels ((hex (index) (digit-char-p (code-char (aref octets index)) 16))
             (next ()
               ;; The next octet, or NIL at the end.
               (when (< i end)
                 (let ((octet (aref octets i)))
                   (cond ((= octet 43) (incf i) 32)
                         ((and (= octet 37) (<= (+ i 3) end) (hex (+ i 1)) (hex (+ i 2)))
                          (prog1 (+ (* 16 (hex (+ i 1))) (hex (+ i 2))) (incf i 3)))
                         (t (incf i) octet)))))
             (continuation ()
               ;; The next octet's six bits when it continues a sequence, else
               ;; NIL with nothing consumed.
               (let ((mark i) (octet (next)))
                 (if (and octet (= (logand octet #xC0) #x80))
                     (logand octet #x3F)
                     (progn (setf i mark) nil)))))
      (loop for octet = (next)
            while octet
            do (funcall emit
                        (multiple-value-bind (more least code)
                            (cond ((< octet #x80) (values 0 0 octet))
                                  ((= (logand octet #xE0) #xC0) (values 1 #x80 (logand octet #x1F)))
                                  ((= (logand octet #xF0) #xE0)
                                   (values 2 #x800 (logand octet #x0F)))
                                  ((= (logand octet #xF8) #xF0)
                                   (values 3 #x10000 (logand octet #x07)))
                                  (t (values nil 0 0)))
                          (block sequence
                            (unless more (return-from sequence #xFFFD))
                            (dotimes (k more)
                              (let ((bits (continuation)))
                                (unless bits (return-from sequence #xFFFD))
                                (setf code (logior (ash code 6) bits))))
                            ;; Overlong, past Unicode, or a surrogate.
                            (if (or (< code least) (> code #x10FFFF) (<= #xD800 code #xDFFF))
                                #xFFFD
                                code))))))))

(defun form-decode (octets start end most)
  "The text OCTETS from START to END encode in a urlencoded form, as one
string made once at its length (WALK-FORM-TEXT); NIL when it is longer
than MOST characters."
  (let ((length 0))
    (walk-form-text octets start end (lambda (code) (declare (ignore code)) (incf length)))
    (when (<= length most)
      (let ((text (make-string length)) (at 0))
        (walk-form-text octets start end
                        (lambda (code) (setf (schar text at) (code-char code)) (incf at)))
        text))))

(defun form-pairs (octets)
  "The fields of OCTETS, a urlencoded body, as (NAME . VALUE) in order (core.md
§7.5).  Counted before anything is made of them: more than
+MOST-FORM-PAIRS+ fields, or a name or value past its bound, signals
TUN.FILES:MULTIPART-REFUSED with 413."
  (flet ((refuse (message) (error 'tun.files:multipart-refused :status 413 :message message)))
    (when (> (1+ (count 38 octets)) +most-form-pairs+)
      (refuse (deferred-tr "The form has too many fields (at most ~:d)." +most-form-pairs+)))
    (loop for start = 0 then (1+ end)
          for end = (or (position 38 octets :start start) (length octets))
          for equals = (or (position 61 octets :start start :end end) end)
          ;; A name or value percent-encoded is at most three times as long.
          when (or (> (- equals start) (* 3 +most-form-name+))
                   (> (- end equals) (* 3 +most-form-value+)))
            do (refuse (deferred-tr "A field of the form is too long."))
          when (< start end)
            collect (let ((name (form-decode octets start equals +most-form-name+))
                          (value (form-decode octets (min end (1+ equals)) end +most-form-value+)))
                      (unless (and name value)
                        (refuse (deferred-tr "A field of the form is too long.")))
                      (cons name value))
          while (< end (length octets)))))

(defun call-with-form-pairs (acceptor function)
  "Call FUNCTION with this urlencoded post's fields read by Tun, within their
bounds, as Hunchentoot's post parameters: Hunchentoot never parses the body
itself, which would make a table of any number of pairs.  A post past the
bounds is answered with a page that says why."
  (handler-case
      (let ((pairs (form-pairs (or (hunchentoot:raw-post-data :force-binary t)
                                   (make-array 0 :element-type '(unsigned-byte 8))))))
        (setf (slot-value hunchentoot:*request* 'hunchentoot::raw-post-data) t
              (slot-value hunchentoot:*request* 'hunchentoot::post-parameters) pairs)
        (funcall function))
    (tun.files:multipart-refused (refusal)
      (setf (slot-value hunchentoot:*request* 'hunchentoot::raw-post-data) t)
      (setf (hunchentoot:return-code*) (tun.files:multipart-refused-status refusal))
      (upload-refusal acceptor (tun.files:multipart-refused-status refusal)
                      (page-text acceptor (tun.files:multipart-refused-message refusal))))))

(defun dispatch-bounded (acceptor request bound placed)
  "Answer REQUEST, its body at most BOUND octets; PLACED, holding one of the
large-body places from before its body is read until it is answered.  A
body is read first, within *SMALL-BODY-SECONDS*, or *LARGE-BODY-SECONDS*
when PLACED, and answered 408 when it does not arrive in time, so a slow
sender holds a request's place for a bounded time."
  (let ((length (content-length)))
    (when (and length (<= length bound))
      (allow-body length))
    (flet ((read-then-dispatch (seconds)
             (if (read-body-in-time seconds)
                 (dispatch-read acceptor request)
                 (refuse-body 408))))
      (cond (placed
             (call-with-large-place acceptor
                                    (lambda () (read-then-dispatch *large-body-seconds*))))
            ((and length (plusp length)) (read-then-dispatch *small-body-seconds*))
            (t (dispatch-read acceptor request))))))

(defun dispatch-read (acceptor request)
  (let ((path (hunchentoot:script-name request))
        (method (hunchentoot:request-method request)))
    (cond ((string= path "/mcp")
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
          ((and (eq method :post) (multipart-request-p))
           (call-with-posted-form acceptor (lambda () (page-or-not-found acceptor method path))))
          ((and (eq method :post) (urlencoded-request-p))
           (call-with-form-pairs acceptor (lambda () (page-or-not-found acceptor method path))))
          (t (page-or-not-found acceptor method path)))))

(defun page-or-not-found (acceptor method path)
  "Answer METHOD on PATH through the web UI, or 404 when no page takes it."
  (or (dispatch-page acceptor method path)
      (progn (setf (hunchentoot:return-code*) 404)
             "")))

(defun dispatch-page (acceptor method path)
  "Answer METHOD on PATH through the web UI (DISPATCH-WEB), or NIL."
  (with-request-record (:id *request-id* :kind :web
                        :tool (format nil "web:~a ~a" method path)
                        :application (acceptor-application acceptor)
                        :at (let ((*application* (acceptor-application acceptor))) (now)))
    (dispatch-web acceptor method path)))

(defparameter *max-threads* 1024
  "Connection threads Hunchentoot may run. Well above --max-inflight, so excess
requests reach our JSON 503 instead of Hunchentoot's own plain 503.")

(defun start-server (application &key (port 8080) (address "127.0.0.1") (max-inflight 64)
                                      trusted-proxy)
  "Serve APPLICATION on ADDRESS:PORT; the acceptor.  TRUSTED-PROXY, an IP
address as text or NIL, is the proxy whose X-Forwarded-For names the client
(core.md 7.5, spec/deploy.md 1)."
  ;; Forms and query strings arrive without a charset; read them as UTF-8.
  (setf hunchentoot:*hunchentoot-default-external-format* (flex:make-external-format :utf-8 :eol-style :lf))
  (let ((acceptor (make-instance 'tun-acceptor :application application
                                               :port port :address address
                                               :max-inflight max-inflight
                                               :trusted-proxy
                                               (and trusted-proxy
                                                    (plain-address
                                                     (or (parse-ip-address trusted-proxy)
                                                         (error "~s is not an IP address"
                                                                trusted-proxy))))
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
