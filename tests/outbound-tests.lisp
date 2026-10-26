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
             :documentation "Each request as a plist (:path :query :authorization
:content-type :accept :body), newest first."))
  (:default-initargs :address "127.0.0.1" :access-log-destination nil
                     :message-log-destination nil))

(defmethod hunchentoot:acceptor-dispatch-request ((remote fake-remote) request)
  (push (list :path (hunchentoot:script-name request)
              :query (hunchentoot:query-string request)
              :authorization (hunchentoot:header-in* :authorization)
              :content-type (hunchentoot:header-in* :content-type)
              :accept (hunchentoot:header-in* :accept)
              :body (parse-json (hunchentoot:raw-post-data :force-text t :external-format :utf-8)))
        (remote-requests remote))
  (destructuring-bind (status text &optional headers)
      (or (pop (remote-answers remote)) (list 200 "{\"ok\":true}"))
    (setf (hunchentoot:return-code*) status
          (hunchentoot:content-type*) "application/json")
    (loop for (name . value) in headers
          do (setf (hunchentoot:header-out name) value))
    text))

(defmacro with-fake-remote ((remote url) &body body)
  "Run BODY in a fresh application with REMOTE, another system serving on a
free port, and URL bound to its /v1/check."
  (let ((port (gensym "PORT")))
    `(let* ((,port (free-port))
            (,remote (make-instance 'fake-remote :port ,port))
            (,url (format nil "http://127.0.0.1:~d/v1/check" ,port)))
       (hunchentoot:start ,remote)
       (unwind-protect
            (with-test-app () (with-application (*app*) ,@body))
         (hunchentoot:stop ,remote)))))

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
      (let* ((url (format nil "http://127.0.0.1:~d/" (free-port)))
             (start (get-internal-real-time))
             (c (failure-of (lambda () (http-json-post url (jobj))))))
        (is (null (remote-failure-status c)))
        (is (equal (format nil "~a kunne ikke nås" (host-of url)) (operation-error-message c)))
        (is (< (elapsed-since start) 4) "within the time to connect, not the call's ten seconds")))))

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
;;; In an operation, in the trace, and answered by a test (spec/outbound.md 2, 4)

(defvar *remote-url* nil "Where WIDGETS-ASK-REMOTE asks.")

(define-operation widgets-ask-remote ((text :type (string :max 200) :required t))
    (:entity widget :kind :read :title "Spør et annet system")
  (http-json-post *remote-url* (jobj "input" text)
                  :headers '(("Authorization" . "Bearer sk-hemmelig"))))

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
    (is (search "miljøvariabelen TYPESAFE_API_KEY" html))
    (is (not (search "<form" html))))
  (is (search "<form" (tun.html:render-html
                       (tun.web::setting-card (jobj "key" "lenker.base_url" "type" "url" "secret" nil
                                                    "value" "https://tun.example" "description" ""))))))
