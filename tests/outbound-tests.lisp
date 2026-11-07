;;;; tests/outbound-tests.lisp -- calling other systems' JSON APIs and
;;;; settings read from the environment (spec/outbound.md).

(in-package #:tun.tests)

(def-suite outbound :in core)
(in-suite outbound)

;;; ------------------------------------------------------------------
;;; Another system, in the test process

(defclass fake-remote (hunchentoot:acceptor)
  ((answers :initform nil :accessor remote-answers
            :documentation "The next answers, in order: (STATUS TEXT &optional HEADERS).
Then 200 with {\"ok\":true}.")
   (requests :initform nil :accessor remote-requests
             :documentation "Each request as a plist (:method :path :query :authorization
:user-agent :content-type :accept :text :body), newest first: :text is the
body as sent, and :body that parsed when it is JSON."))
  (:default-initargs :address "127.0.0.1" :access-log-destination nil
                     :message-log-destination nil))

(defmethod hunchentoot:acceptor-dispatch-request ((remote fake-remote) request)
  (let ((text (hunchentoot:raw-post-data :force-text t :external-format :utf-8)))
    (push (list :method (hunchentoot:request-method request)
                :path (hunchentoot:script-name request)
                :query (hunchentoot:query-string request)
                :authorization (hunchentoot:header-in* :authorization)
                :user-agent (hunchentoot:header-in* :user-agent)
                :content-type (hunchentoot:header-in* :content-type)
                :accept (hunchentoot:header-in* :accept)
                :text text
                :body (and text (plusp (length text))
                           (ignore-errors (parse-json text))))
          (remote-requests remote)))
  (destructuring-bind (status text &optional headers)
      (or (pop (remote-answers remote)) (list 200 "{\"ok\":true}"))
    (setf (hunchentoot:return-code*) status
          (hunchentoot:content-type*) "application/json")
    (loop for (name . value) in headers
          do (setf (hunchentoot:header-out name) value))
    text))

(defmacro with-fake-remote ((remote url) &body body)
  "Run BODY in a fresh application with REMOTE, another system serving on a
port of its own, and URL bound to its /v1/check."
  `(let ((,remote (make-instance 'fake-remote :port 0)))
     (hunchentoot:start ,remote)
     (unwind-protect
          (let ((,url (format nil "http://127.0.0.1:~d/v1/check"
                              (hunchentoot:acceptor-port ,remote))))
            (with-test-app () (with-application (*app*) ,@body)))
       (hunchentoot:stop ,remote))))

(defmacro with-silent-remote ((url) &body body)
  "Run BODY with URL at a server that takes connections and never answers."
  (let ((listener (gensym "LISTENER")) (acceptor (gensym "ACCEPTOR")))
    `(let* ((,listener (usocket:socket-listen "127.0.0.1" 0 :reuse-address t))
            (,acceptor (sb-thread:make-thread
                        (lambda () (loop (usocket:socket-accept ,listener)))
                        :name "silent remote"))
            (,url (format nil "http://127.0.0.1:~d/v1/check" (usocket:get-local-port ,listener))))
       (unwind-protect (progn ,@body)
         (sb-thread:terminate-thread ,acceptor)
         (usocket:socket-close ,listener)))))

(defun failure-of (function)
  "The REMOTE-FAILURE FUNCTION signals, or NIL."
  (handler-case (progn (funcall function) nil)
    (remote-failure (c) c)))

(defun host-of (url)
  "The host and port of URL, as messages name it."
  (subseq url (length "http://") (position #\/ url :start (length "http://"))))

(defun live-provider-calls ()
  (count-if #'sb-thread:thread-alive-p (tun.core::application-provider-calls *app*)))

;;; ------------------------------------------------------------------
;;; A JSON POST (spec/outbound.md 1)

(test a-post-returns-the-answer-and-its-status
  (with-fake-remote (remote url)
    (setf (remote-answers remote) (list (list 201 "{\"kind\":\"feil\",\"score\":0.9}")))
    (multiple-value-bind (json status)
        (http-json-post url (jobj "input" "Knappen virker ikke ø") :headers '(("Authorization" . "Bearer sk-1")))
      (is (= 201 status))
      (is (equal "feil" (jget json "kind")))
      (is (= 0.9d0 (jget json "score"))))
    (let ((request (first (remote-requests remote))))
      (is (equal "/v1/check" (getf request :path)))
      (is (equal "Bearer sk-1" (getf request :authorization)))
      (is (search "application/json" (getf request :content-type)))
      (is (equal "application/json" (getf request :accept)))
      (is (equal "Knappen virker ikke ø" (jget (getf request :body) "input")) "sent as UTF-8"))
    (setf (remote-answers remote) (list (list 204 "")))
    (is (json-null-p (http-json-post url (jobj))) "an empty answer is null")))

(test answers-outside-2xx-are-remote-failures
  (with-fake-remote (remote url)
    (setf (remote-answers remote)
          (list (list 503 "{\"error\":\"overloaded\"}")
                (list 422 "bad input")
                (list 200 "<html>")
                (list 302 "" '((:location . "https://elsewhere.example/")))))
    (let ((c (failure-of (lambda () (http-json-post url (jobj))))))
      (is (typep c 'operation-error))
      (is (eq :unavailable (operation-error-code c)))
      (is (= 503 (remote-failure-status c)))
      (is (equal "overloaded" (jget (remote-failure-body c) "error")) "the body as JSON")
      (is (equal url (remote-failure-url c)))
      (is (equal (format nil "~a svarte 503" (host-of url)) (operation-error-message c))
          "the message names the host, not the body"))
    (let ((c (failure-of (lambda () (http-json-post url (jobj))))))
      (is (= 422 (remote-failure-status c)))
      (is (equal "bad input" (remote-failure-body c)) "a body that is not JSON, as text"))
    (let ((c (failure-of (lambda () (http-json-post url (jobj))))))
      (is (= 200 (remote-failure-status c)))
      (is (search "ikke med JSON" (operation-error-message c))))
    (let ((c (failure-of (lambda () (http-json-post url (jobj))))))
      (is (= 302 (remote-failure-status c)) "a redirect is not followed"))
    (is (= 4 (length (remote-requests remote))))))

(test a-silent-remote-fails-in-time-and-its-call-ends
  (with-test-app ()
    (with-application (*app*)
      (with-silent-remote (url)
        (let* ((start (get-internal-real-time))
               (c (failure-of (lambda () (http-json-post url (jobj) :timeout 1)))))
          (is (<= 1 (elapsed-since start) 2.5))
          (is (null (remote-failure-status c)))
          (is (null (remote-failure-body c)))
          (is (equal (format nil "~a svarte ikke innen 1 sekund" (host-of url))
                     (operation-error-message c))))
        (loop repeat 100 until (zerop (live-provider-calls)) do (sleep 0.02))
        (is (zerop (live-provider-calls)) "the abandoned thread has given up too")))))

(test a-remote-that-cannot-be-reached
  (with-test-app ()
    (with-application (*app*)
      (with-refused-port (port)
        (let* ((url (format nil "http://127.0.0.1:~d/" port))
               (start (get-internal-real-time))
               (c (failure-of (lambda () (http-json-post url (jobj))))))
          (is (null (remote-failure-status c)))
          (is (equal (format nil "~a kunne ikke nås" (host-of url)) (operation-error-message c)))
          (is (< (elapsed-since start) 4)
              "within the time to connect, not the call's ten seconds"))))))

(test a-call-leaves-the-operation-time-to-answer
  (with-test-app ()
    (with-application (*app*)
      (with-silent-remote (url)
        (let* ((start (get-internal-real-time))
               (c (failure-of (lambda ()
                                (tun.core::with-deadline (:ms 2600) (http-json-post url (jobj)))))))
          (is (<= 1.5 (elapsed-since start) 2.3) "1.6 seconds: the deadline less one")
          (is (search "svarte ikke innen 2 sekunder" (operation-error-message c))))
        (let* ((start (get-internal-real-time))
               (c (failure-of (lambda ()
                                (tun.core::with-deadline (:ms 1500) (http-json-post url (jobj)))))))
          (is (< (elapsed-since start) 0.2) "under a second left: no call")
          (is (search "ble ikke spurt" (operation-error-message c))))))))

(test calls-to-other-systems-are-bounded-per-tenant
  (with-test-app ()
    (with-application (*app*)
      (with-silent-remote (url)
        (let* ((app *app*)
               (threads (loop repeat 4
                              collect (sb-thread:make-thread
                                       (lambda ()
                                         (with-application (app)
                                           (failure-of (lambda () (http-json-post url (jobj) :timeout 2)))))
                                       :name "busy caller"))))
          (loop repeat 100 until (= 4 (live-provider-calls)) do (sleep 0.02))
          (let* ((start (get-internal-real-time))
                 (c (failure-of (lambda () (http-json-post url (jobj))))))
            (is (< (elapsed-since start) 0.2) "the fifth fails at once")
            (is (search "for mange kall" (operation-error-message c))))
          (mapc #'sb-thread:join-thread threads))))))

(test a-call-is-checked-before-it-is-made
  (with-test-app ()
    (with-application (*app*)
      (signals error (http-json-post "ftp://example.no/" (jobj)))
      (signals error (http-json-post "example.no/v1" (jobj)))
      (signals error (http-json-post "https://example.no/" (jobj) :headers '(("Authorization" . 42))))
      (signals error (http-json-post "https://example.no/" (jobj) :timeout 0))
      (signals error (http-json-post "https://example.no/" (jobj) :timeout 61)))))

;;; ------------------------------------------------------------------
;;; A GET (spec/outbound.md 1.2) and the User-Agent (1.3)

(test a-get-sends-its-query-encoded-and-no-body
  (with-fake-remote (remote url)
    (setf (remote-answers remote) (list (list 200 "{\"price\":430.5}")))
    (multiple-value-bind (json status)
        (http-json-get url :query '(("symbol" . "^GSPC") ("city" . "Bodø"))
                           :headers '(("Authorization" . "Bearer sk-1")))
      (is (= 200 status))
      (is (= 430.5d0 (jget json "price"))))
    (let ((request (first (remote-requests remote))))
      (is (eq :get (getf request :method)))
      (is (equal "/v1/check" (getf request :path)))
      (is (equal "symbol=%5EGSPC&city=Bod%C3%B8" (getf request :query)))
      (is (equal "Bearer sk-1" (getf request :authorization)))
      (is (equal "application/json" (getf request :accept)))
      (is (null (getf request :content-type)) "no body, so no content type")
      (is (null (getf request :body))))))

(test a-get-query-joins-the-url-it-is-given
  (with-fake-remote (remote url)
    (flet ((query-sent (url &optional query)
             (http-json-get url :query query)
             (getf (first (remote-requests remote)) :query)))
      (is (null (query-sent url)) "no query, no ?")
      (is (null (query-sent url '())) "an empty query, no ?")
      (is (equal "a=1" (query-sent (format nil "~a?a=1" url))) "a URL's own query, as it is")
      (is (equal "a=1&b=2" (query-sent (format nil "~a?a=1" url) '(("b" . "2")))))
      (is (equal "b=2" (query-sent (format nil "~a?" url) '(("b" . "2")))))
      (is (equal "a=1&b=2" (query-sent (format nil "~a?a=1&" url) '(("b" . "2")))))
      (is (equal "b=2" (query-sent (format nil "~a#top" url) '(("b" . "2"))))
          "the query goes before the fragment, which is not sent"))
    (signals error (http-json-get url :query '(("a" . 1))))
    (signals error (http-json-get url :query "a=1"))))

(test a-url-is-sent-as-written-without-its-fragment
  (with-fake-remote (remote url)
    (let ((root (subseq url 0 (search "/v1/check" url))))
      (http-json-get root :query '(("symbol" . "EQNR.OL")))
      (let ((request (first (remote-requests remote))))
        (is (equal "/" (getf request :path)) "an empty path is sent as /")
        (is (equal "symbol=EQNR.OL" (getf request :query)) "and keeps its query"))
      (http-json-post (format nil "~a?q=1" root) (jobj))
      (is (equal "q=1" (getf (first (remote-requests remote)) :query))
          "for a POST too"))
    (http-json-post (format nil "~a?q=%5E#top" url) (jobj))
    (let ((request (first (remote-requests remote))))
      (is (equal "/v1/check" (getf request :path)) "a POST's fragment is not sent")
      (is (equal "q=%5E" (getf request :query)) "and its escapes are not escaped again"))))

(test a-get-fails-as-a-post-does-and-names-the-url-it-sent
  (with-fake-remote (remote url)
    (setf (remote-answers remote) (list (list 503 "{\"error\":\"overloaded\"}")
                                        (list 200 "<html>")))
    (let ((c (failure-of (lambda () (http-json-get url :query '(("q" . "ø")))))))
      (is (eq :unavailable (operation-error-code c)))
      (is (= 503 (remote-failure-status c)))
      (is (equal "overloaded" (jget (remote-failure-body c) "error")))
      (is (equal (format nil "~a?q=%C3%B8" url) (remote-failure-url c)) "the URL as sent")
      (is (equal (format nil "~a svarte 503" (host-of url)) (operation-error-message c))))
    (is (search "ikke med JSON" (operation-error-message (failure-of (lambda ()
                                                                         (http-json-get url))))))))

(test a-user-agent-in-the-headers-is-the-one-sent
  (with-fake-remote (remote url)
    (flet ((agent-sent (call)
             (funcall call)
             (getf (first (remote-requests remote)) :user-agent)))
      (let ((agent "kurs/1.0 (jonas@example.no)"))
        (is (equal agent (agent-sent (lambda ()
                                       (http-json-get url :headers `(("User-Agent" . ,agent))))))
            "in place of drakma's, not beside it")
        (is (equal agent (agent-sent (lambda ()
                                       (http-json-post url (jobj)
                                                       :headers `(("user-agent" . ,agent))))))
            "in any case, for a POST too"))
      (is (equal "first"
                 (agent-sent (lambda ()
                               (http-json-get url :headers '(("User-Agent" . "first")
                                                             ("USER-AGENT" . "second"))))))
          "of two, the first")
      (is (search "Drakma" (agent-sent (lambda () (http-json-get url))))
          "without one, the library's own"))))

;;; ------------------------------------------------------------------
;;; A form (spec/outbound.md 1.4)

(defun error-text (function)
  "The text of the error FUNCTION signals, or NIL."
  (handler-case (progn (funcall function) nil)
    (error (e) (princ-to-string e))))

(test a-form-is-sent-encoded-and-its-json-returned
  (with-fake-remote (remote url)
    (setf (remote-answers remote)
          (list (list 201 "{\"access_token\":\"t1\",\"expires_in\":1200}")))
    (multiple-value-bind (json status)
        (http-form-post url '(("grant_type" . "refresh_token") ("note" . "a b&c=d")
                              ("city" . "Bodø") ("a b" . "c"))
                        :headers '(("Authorization" . "Basic abc")))
      (is (= 201 status))
      (is (equal "t1" (jget json "access_token")))
      (is (= 1200 (jget json "expires_in"))))
    (let ((request (first (remote-requests remote))))
      (is (eq :post (getf request :method)))
      (is (equal "/v1/check" (getf request :path)))
      (is (equal "application/x-www-form-urlencoded" (getf request :content-type)))
      (is (equal "application/json" (getf request :accept)))
      (is (equal "Basic abc" (getf request :authorization)))
      (is (equal "grant_type=refresh_token&note=a%20b%26c%3Dd&city=Bod%C3%B8&a%20b=c"
                 (getf request :text))
          "names and values encoded, in the form's order, and a value keeps its & and ="))
    (is (eq (find-symbol "HTTP-FORM-POST" "TUN") 'tun.outbound:http-form-post)
        "a client reaches it through TUN")))

(test a-form-may-be-empty-and-an-empty-answer-is-null
  (with-fake-remote (remote url)
    (setf (remote-answers remote) (list (list 204 "")))
    (is (json-null-p (http-form-post url '())))
    (is (member (getf (first (remote-requests remote)) :text) '(nil "") :test #'equal))))

(test a-form-fails-as-a-post-does
  (with-fake-remote (remote url)
    (setf (remote-answers remote)
          (list (list 400 "{\"error\":\"invalid_grant\"}")
                (list 200 "<html>")
                (list 302 "" '((:location . "https://elsewhere.example/")))))
    (let ((c (failure-of (lambda () (http-form-post url '(("a" . "b")))))))
      (is (eq :unavailable (operation-error-code c)))
      (is (= 400 (remote-failure-status c)))
      (is (equal "invalid_grant" (jget (remote-failure-body c) "error")))
      (is (equal url (remote-failure-url c)))
      (is (equal (format nil "~a svarte 400" (host-of url)) (operation-error-message c))))
    (is (search "ikke med JSON"
                (operation-error-message (failure-of (lambda () (http-form-post url '()))))))
    (is (= 302 (remote-failure-status (failure-of (lambda () (http-form-post url '())))))
        "a redirect is not followed")
    (with-silent-remote (silent)
      (let ((c (failure-of (lambda () (http-form-post silent '(("a" . "b")) :timeout 1)))))
        (is (null (remote-failure-status c)) "no answer in time")
        (is (search "svarte ikke innen 1 sekund" (operation-error-message c)))))))

(test a-form-names-its-user-agent-once
  (with-fake-remote (remote url)
    (http-form-post url '() :headers '(("user-agent" . "kurs/1.0")))
    (is (equal "kurs/1.0" (getf (first (remote-requests remote)) :user-agent)))))

(test a-mistake-in-a-form-or-a-header-shows-no-value
  (with-fake-remote (remote url)
    (flet ((refused (form)
             (let ((text (error-text (lambda () (http-form-post url form)))))
               (is (search "http-form-post" text) "~a" text)
               (is (not (search "SECRET" text)) "shown: ~a" text)
               text)))
      (is (search "client_secret" (refused '(("client_id" . "SECRET") ("client_secret" . nil))))
          "it says which name is at fault")
      (refused "grant_type=SECRET")
      (refused '("SECRET"))
      (refused '(("a" . "SECRET") . "SECRET"))
      (refused '(("a" "SECRET")))
      (refused '((:name . "SECRET")))
      (refused '(("a" . "SECRET") nil)))
    (dolist (headers '((("Authorization" . "SECRET") ("X-Key" . 42))
                       (("Authorization" . "SECRET") . "SECRET")
                       (("Authorization" . "SECRET") nil)
                       ("SECRET")))
      (dolist (call (list (lambda () (http-form-post url '() :headers headers))
                          (lambda () (http-json-post url (jobj) :headers headers))
                          (lambda () (http-json-get url :headers headers))))
        (let ((text (error-text call)))
          (is (search "the headers" text) "~a" text)
          (is (not (search "SECRET" text)) "shown: ~a" text))))
    (dolist (query '((("key" . "SECRET") ("n" . 1))
                     (("key" . "SECRET") nil)))
      (let ((text (error-text (lambda () (http-json-get url :query query)))))
        (is (search "http-json-get" text) "~a" text)
        (is (not (search "SECRET" text)) "shown: ~a" text)))
    (is (null (remote-requests remote)) "none of them was sent")))

(test a-handler-answers-for-a-form
  (with-test-app ()
    (with-application (*app*)
      (let* ((seen nil)
             (*http-json-handler* (lambda (url body headers)
                                    (setf seen (list url body headers))
                                    (values 200 (jobj "ok" t)))))
        (is (eq t (jget (http-form-post "https://auth.example/token"
                                        '(("a" . "first") ("b" . "ø") ("a" . "last"))
                                        :headers '(("X-Key" . "1")))
                        "ok")))
        (is (equal "https://auth.example/token" (first seen)))
        (is (equal "last" (jget (second seen) "a")) "of a name given twice, the last")
        (is (equal "ø" (jget (second seen) "b")) "as the other system would read it")
        (is (equal '(("X-Key" . "1")) (third seen)))
        (http-form-post "https://auth.example/token" '())
        (is (hash-table-p (second seen)) "an empty form is an empty object")
        (is (zerop (hash-table-count (second seen))))))))

;;; In an operation, in the trace, and answered by a test (spec/outbound.md 2, 4)

(defvar *remote-url* nil "Where WIDGETS-ASK-REMOTE asks.")

(define-operation widgets-ask-remote ((text :type (string :max 200) :required t))
    (:entity widget :kind :read :title "Spør et annet system")
  (http-json-post *remote-url* (jobj "input" text)
                  :headers '(("Authorization" . "Bearer sk-hemmelig"))))

(define-operation widgets-read-remote ((symbol :type (string :max 20) :required t))
    (:entity widget :kind :read :title "Read from another system")
  (http-json-get *remote-url* :query `(("symbol" . ,symbol) ("key" . "sk-i-adressen"))))

(defun trace-steps (request-id)
  "The steps of the request REQUEST-ID, read in a request of its own."
  (let ((*request-id* nil))
    (coerce (jget (call-ok "introspect_request" "admin:anna" "request_id" request-id) "steps")
            'list)))

(test the-trace-shows-the-call-and-not-its-key
  (with-fake-remote (remote url)
    (let ((*remote-url* (format nil "~a?key=sk-i-adressen" url))
          (*request-id* (new-id "req")))
      (is (eq t (jget (call-ok "widgets_ask_remote" "employee:anna" "text" "Hei") "ok")))
      (is (equal "key=sk-i-adressen" (getf (first (remote-requests remote)) :query)))
      (let* ((steps (trace-steps *request-id*))
             (step (find "external" steps :key (lambda (s) (jget s "kind")) :test #'equal)))
        (is (equal (format nil "POST ~a" url) (jget step "name")) "the URL without its query")
        (is (equal "200" (jget step "detail")))
        (is (numberp (jget step "duration_ms")))
        (let ((text (to-json-string (jarr steps))))
          (is (not (search "sk-hemmelig" text)) "no headers")
          (is (not (search "sk-i-adressen" text)))
          (is (not (search "Hei" text)) "no body")))))
  (with-test-app ()
    (let ((*remote-url* "https://bruker:passord@api.example.no/v1/check")
          (*request-id* (new-id "req"))
          (*http-json-handler* (lambda (url body headers)
                                 (declare (ignore url body headers))
                                 (values 200 (jobj)))))
      (call-ok "widgets_ask_remote" "employee:anna" "text" "Hei")
      (let ((step (find "external" (trace-steps *request-id*)
                        :key (lambda (s) (jget s "kind")) :test #'equal)))
        (is (equal "POST https://api.example.no/v1/check" (jget step "name"))
            "nor its user and password")))))

(define-operation widgets-post-form ((key :type (string :max 200) :required t :secret t))
    (:entity widget :kind :read :title "Post a form")
  (http-form-post *remote-url* `(("client_secret" . ,key))
                  :headers `(("Authorization" . ,key))))

(test the-trace-shows-a-form-s-call-and-not-its-values
  (with-test-app ()
    (let ((*remote-url* "https://auth.example/token?x=1")
          (*request-id* (new-id "req"))
          (*http-json-handler* (lambda (url body headers)
                                 (declare (ignore url body headers))
                                 (values 200 (jobj "ok" t)))))
      (call-ok "widgets_post_form" "employee:anna" "key" "SECRET")
      (let* ((steps (trace-steps *request-id*))
             (step (find "external" steps :key (lambda (s) (jget s "kind")) :test #'equal)))
        (is (equal "POST https://auth.example/token" (jget step "name")))
        (is (equal "200" (jget step "detail")))
        (is (not (search "SECRET" (to-json-string (jarr steps)))))))))

(test the-trace-shows-a-get-without-its-query
  (with-test-app ()
    (let ((*remote-url* "https://api.example.no/v8/chart")
          (*request-id* (new-id "req"))
          (*http-json-handler* (lambda (url body headers)
                                 (declare (ignore url body headers))
                                 (values 200 (jobj "ok" t)))))
      (call-ok "widgets_read_remote" "employee:anna" "symbol" "EQNR.OL")
      (let ((step (find "external" (trace-steps *request-id*)
                        :key (lambda (s) (jget s "kind")) :test #'equal)))
        (is (equal "GET https://api.example.no/v8/chart" (jget step "name")))
        (is (equal "200" (jget step "detail")))))))

(test a-handler-answers-for-a-get
  (with-test-app ()
    (let* ((seen '())
           (*remote-url* "https://api.example.no/v8/chart")
           (*http-json-handler* (lambda (url body headers)
                                  (push (list url body headers) seen)
                                  (values 200 (jobj "symbol" "EQNR.OL")))))
      (is (equal "EQNR.OL" (jget (call-ok "widgets_read_remote" "employee:anna"
                                          "symbol" "EQNR.OL")
                                 "symbol")))
      (destructuring-bind (url body headers) (first seen)
        (is (equal "https://api.example.no/v8/chart?symbol=EQNR.OL&key=sk-i-adressen" url)
            "the URL with its query")
        (is (null body) "a GET has no body")
        (is (null headers))))))

(test a-handler-answers-for-the-other-system
  (with-test-app ()
    (let* ((seen '())
           (*remote-url* "https://api.example.no/v1/check")
           (*http-json-handler* (lambda (url body headers)
                                  (push (list url body headers) seen)
                                  (if (equal "feil" (jget body "input"))
                                      (values 500 (jobj "error" "boom"))
                                      (values 200 (jobj "echo" (jget body "input")))))))
      (is (equal "Hei" (jget (call-ok "widgets_ask_remote" "employee:anna" "text" "Hei") "echo")))
      (destructuring-bind (url body headers) (first seen)
        (is (equal "https://api.example.no/v1/check" url))
        (is (hash-table-p body) "the body as the other system reads it")
        (is (equal "Bearer sk-hemmelig" (cdr (assoc "Authorization" headers :test #'equal)))))
      (multiple-value-bind (json code) (call "widgets_ask_remote" "employee:anna" "text" "feil")
        (is (equal "unavailable" code) "an unhandled failure fails the operation")
        (is (equal "api.example.no svarte 500" (jget (jget json "error") "message"))))
      (let ((*http-json-handler* (lambda (url body headers)
                                   (declare (ignore url body headers))
                                   nil)))
        (is (equal "unavailable" (nth-value 1 (call "widgets_ask_remote" "employee:anna" "text" "Hei")))
            "a status of NIL is no answer"))
      (let ((*http-json-handler* (lambda (url body headers)
                                   (declare (ignore url body headers))
                                   (values "200" "{}"))))
        (signals error (call "widgets_ask_remote" "employee:anna" "text" "Hei")
          "a handler that answers no status is the test's mistake, not a failure")))))

;;; ------------------------------------------------------------------
;;; Settings from the environment (spec/outbound.md 3)

(defmacro with-environment-variable ((name value) &body body)
  "Run BODY with the environment variable NAME set to VALUE, or unset for NIL."
  (let ((old (gensym "OLD")))
    `(let ((,old (sb-posix:getenv ,name)))
       (flet ((put (value) (if value (sb-posix:setenv ,name value 1) (sb-posix:unsetenv ,name))))
         (put ,value)
         (unwind-protect (progn ,@body) (put ,old))))))

(test a-setting-can-come-from-the-environment
  (let ((tun.core::*setting-declarations* (make-hash-table :test 'equal)))
    (define-setting "test.remote_key" (:type "secret" :env "TUN_TEST_REMOTE_KEY"
                                       :description "Nøkkelen til et annet system."))
    (define-setting "test.remote_url" (:type "url" :env "TUN_TEST_REMOTE_URL"
                                       :default "https://api.example.no"))
    (flet ((item (key) (find-by "key" key (jget (call-ok "settings_list" "admin:a") "items")))
           (value (key) (with-application (*app*)
                          (with-transaction (:read) (setting-value-at-use key)))))
      (with-environment-variable ("TUN_TEST_REMOTE_KEY" nil)
        (with-environment-variable ("TUN_TEST_REMOTE_URL" nil)
          (with-test-app ()
            (is (null (value "test.remote_key")) "unset: no value, and the server started")
            (is (json-null-p (jget (item "test.remote_key") "value")))
            (is (equal "TUN_TEST_REMOTE_KEY" (jget (item "test.remote_key") "env")))
            (is (null (with-application (*app*)
                        (with-transaction (:read)
                          (select-one 'tun.core::setting :where '(:= "key" "test.remote_key")))))
                "no random secret is stored for it")
            (is (equal "https://api.example.no" (value "test.remote_url")) "unset: the default")
            (sb-posix:setenv "TUN_TEST_REMOTE_KEY" "sk-fra-miljoet" 1)
            (is (equal "sk-fra-miljoet" (value "test.remote_key")) "read when it is used")
            (is (equal "***" (jget (item "test.remote_key") "value")) "set, and masked")
            (is (not (search "sk-fra-miljoet" (to-json-string (call-ok "settings_list" "admin:a")))))
            (is (equal "forbidden" (nth-value 1 (call "settings_get" "employee:a" "key" "test.remote_key"))))
            (is (equal "invalid_input" (nth-value 1 (call "settings_set" "admin:a" "key" "test.remote_key"
                                                          "value" "sk-annen")))
                "it is changed in the environment, not here")
            (sb-posix:setenv "TUN_TEST_REMOTE_URL" "https://jev.example.no" 1)
            (is (equal "https://jev.example.no"
                       (jget (call-ok "settings_get" "employee:a" "key" "test.remote_url") "value")))
            (sb-posix:setenv "TUN_TEST_REMOTE_URL" "file:///etc/passwd" 1)
            (handler-case (progn (value "test.remote_url") (is nil "an invalid value is an error"))
              (error (e)
                (is (search "TUN_TEST_REMOTE_URL" (princ-to-string e)))
                (is (not (search "passwd" (princ-to-string e))) "naming the variable, not the value")))))))))

(test only-a-text-setting-comes-from-the-environment
  (let ((tun.core::*setting-declarations* (make-hash-table :test 'equal)))
    (signals extension-error (define-setting "test.hours" (:type "int" :env "TUN_TEST_HOURS")))
    (signals extension-error (define-setting "test.key" (:type "secret" :env "NOT A NAME")))))

(test the-settings-page-shows-the-variable-instead-of-a-form
  (let ((html (tun.html:render-html
               (tun.web::setting-card (jobj "key" "typesafe.api_key" "type" "secret" "secret" t
                                            "value" "***" "env" "TYPESAFE_API_KEY"
                                            "description" "Nøkkelen til TypeSafe.")))))
    (is (search "the environment variable TYPESAFE_API_KEY" html))
    (is (not (search "<form" html))))
  (is (search "<form" (tun.html:render-html
                       (tun.web::setting-card (jobj "key" "test.url" "type" "url" "secret" nil
                                                    "value" "https://tun.example" "description" ""))))))
