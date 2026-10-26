;;;; tests/fake-provider.lisp -- a fake OpenID Connect provider, and walking a
;;;; browser through signing in with it (spec/auth.md 3.5).
;;;;
;;;; The provider runs in the test process.  It checks what Tun sends it as a
;;;; real one would (the client secret, the redirect URI, the PKCE verifier
;;;; against the challenge) and answers with the identity a test chooses, so
;;;; the flow is tested over real HTTP from the button to the session.  Tun
;;;; keeps no passwords, so every test that needs a person's session signs in
;;;; here.

(in-package #:tun.tests)

;;; ------------------------------------------------------------------
;;; The fake provider

(defclass fake-provider (hunchentoot:acceptor)
  ((app :initarg :app :reader provider-app)
   (identity :initform nil :accessor provider-identity
             :documentation "The claims the person who signs in has: sub, email, name...")
   (overrides :initform nil :accessor provider-overrides
              :documentation "Claims to put in the next ID tokens instead of the right ones.")
   (failing :initform nil :accessor provider-failing
            :documentation "True to answer the token request with invalid_grant.")
   (codes :initform (make-hash-table :test 'equal) :reader provider-codes
          :documentation "code -> the authorization request's parameters, an alist.")
   (token-requests :initform nil :accessor provider-token-requests
                   :documentation "The parameters of each token request, newest first.")
   (signing-keys :initform nil :accessor provider-signing-keys
                 :documentation "((kid . RSA key pair) ...): the key set it publishes,
as AuthKit does for its access tokens (oauth-tests.lisp).")
   (key-fetches :initform 0 :accessor provider-key-fetches
                :documentation "How many times its key set was fetched.")
   (down :initform nil :accessor provider-down
         :documentation "True to answer every request 503, as a provider that is down."))
  (:default-initargs :address "127.0.0.1" :access-log-destination nil
                     :message-log-destination nil))

(defparameter +client-id+ "tun-test-client")
(defparameter +client-secret+ "en hemmelighet som bare testen kjenner")

(defun provider-url (provider &optional (path ""))
  (format nil "http://127.0.0.1:~d~a" (hunchentoot:acceptor-port provider) path))

(defun base64url (octets)
  "OCTETS in unpadded base64url, written here apart from Tun's own."
  (string-right-trim "=" (map 'string (lambda (c) (case c (#\+ #\-) (#\/ #\_) (t c)))
                              (cl-base64:usb8-array-to-base64-string octets))))

(defun s256 (verifier)
  "The PKCE challenge of VERIFIER (RFC 7636 4.2)."
  (base64url (ironclad:digest-sequence :sha256 (sb-ext:string-to-octets verifier))))

(defun encode-claims (claims)
  "A compact JWT whose payload is CLAIMS (alist) and whose signature is junk:
Tun does not check it (spec/auth.md 3.5)."
  (flet ((part (json)
           (base64url (sb-ext:string-to-octets (to-json-string json) :external-format :utf-8))))
    (format nil "~a.~a.c2lnbmF0dXJl"
            (part (jobj "alg" "RS256" "typ" "JWT"))
            (part (apply #'jobj (loop for (key . value) in claims append (list key value)))))))

(defun unix-now (provider)
  "The time on the test clock of PROVIDER's application, as a provider puts
it in a JWT: seconds since 1970, not since 1900 as Tun counts them."
  (- (with-application ((provider-app provider)) (now)) 2208988800))

(defun provider-claims (provider request)
  "The ID token's claims for the authorization REQUEST: the identity, the
issuer, audience, times and nonce, then the test's overrides."
  (let* ((now (unix-now provider))
         (claims (append (provider-identity provider)
                         `(("iss" . ,(provider-url provider))
                           ("aud" . ,+client-id+)
                           ("iat" . ,now)
                           ("exp" . ,(+ now 3600))
                           ("nonce" . ,(cdr (assoc "nonce" request :test #'equal)))))))
    (dolist (override (provider-overrides provider) claims)
      (setf claims (cons override (remove (car override) claims :key #'car :test #'equal))))))

(defun answer-token-request (provider)
  (let* ((parameters (hunchentoot:post-parameters*))
         (request (gethash (cdr (assoc "code" parameters :test #'equal))
                           (provider-codes provider))))
    (flet ((param (name) (cdr (assoc name parameters :test #'equal)))
           (ask (name) (cdr (assoc name request :test #'equal))))
      (push parameters (provider-token-requests provider))
      (setf (hunchentoot:content-type*) "application/json")
      (cond ((or (provider-failing provider)
                 (null request)
                 (not (equal (param "grant_type") "authorization_code"))
                 (not (equal (param "client_id") +client-id+))
                 (not (equal (param "client_secret") +client-secret+))
                 (not (equal (param "redirect_uri") (ask "redirect_uri")))
                 (not (equal (s256 (or (param "code_verifier") "")) (ask "code_challenge"))))
             (setf (hunchentoot:return-code*) 400)
             (to-json-string (jobj "error" "invalid_grant")))
            (t
             (remhash (param "code") (provider-codes provider))
             (to-json-string (jobj "access_token" "at" "token_type" "Bearer"
                                   "id_token"
                                   (encode-claims (provider-claims provider request)))))))))

(defmethod hunchentoot:acceptor-dispatch-request ((provider fake-provider) request)
  (let ((path (hunchentoot:script-name request)))
    (cond ((provider-down provider)
           (setf (hunchentoot:return-code*) 503)
           "")
          ((member path '("/authorize" "/oauth2/authorize") :test #'string=)
           ;; The person chose the identity the test set: back with a code.
           (let ((parameters (hunchentoot:get-parameters*))
                 (code (new-secret-token)))
             (setf (gethash code (provider-codes provider)) parameters
                   (hunchentoot:return-code*) 302
                   (hunchentoot:header-out :location)
                   (format nil "~a?code=~a&state=~a"
                           (cdr (assoc "redirect_uri" parameters :test #'equal)) code
                           (cdr (assoc "state" parameters :test #'equal))))
             ""))
          ((member path '("/token" "/oauth2/token") :test #'string=)
           (answer-token-request provider))
          ((string= path "/oauth2/jwks")
           (incf (provider-key-fetches provider))
           (setf (hunchentoot:content-type*) "application/json")
           (to-json-string (jobj "keys" (jarr (mapcar #'public-jwk (provider-signing-keys provider))))))
          ((string= path "/.well-known/oauth-authorization-server")
           (setf (hunchentoot:content-type*) "application/json")
           (to-json-string (jobj "issuer" (provider-url provider)
                                 "authorization_endpoint" (provider-url provider "/oauth2/authorize")
                                 "token_endpoint" (provider-url provider "/oauth2/token")
                                 "jwks_uri" (provider-url provider "/oauth2/jwks"))))
          (t (setf (hunchentoot:return-code*) 404) ""))))

(defun public-jwk (entry)
  "ENTRY, (kid . RSA key pair), as the public JWK a key set lists."
  (multiple-value-bind (n e) (key-integers (cdr entry))
    (flet ((octets (integer) (base64url (ironclad:integer-to-octets integer))))
      (jobj "kty" "RSA" "kid" (car entry) "use" "sig" "alg" "RS256"
            "n" (octets n) "e" (octets e)))))

(defun provider-strategy (provider &key (class 'tun.auth:oidc-strategy))
  (make-instance class :name "test" :label "Testleverandør"
                 :issuer (provider-url provider) :issuers nil
                 :authorization-endpoint (provider-url provider "/authorize")
                 :token-endpoint (provider-url provider "/token")
                 :client-id +client-id+ :client-secret +client-secret+))

(defmacro with-provider ((provider) &body body)
  "Run BODY with PROVIDER serving and *APP* signing in through it."
  `(let ((,provider (make-instance 'fake-provider :port (free-port) :app *app*)))
     (hunchentoot:start ,provider)
     (unwind-protect
          (progn
            (setf (tun.auth:sign-in-strategies *app*) (list (provider-strategy ,provider)))
            ,@body)
       (hunchentoot:stop ,provider))))

(defun person-at (provider sub email &rest claims)
  "Make the person who signs in at PROVIDER the one with SUB and EMAIL."
  (setf (provider-identity provider)
        (append `(("sub" . ,sub) ("email" . ,email) ("email_verified" . t))
                (loop for (key value) on claims by #'cddr collect (cons key value)))))

;;; ------------------------------------------------------------------
;;; Walking through the flow

(defun absolute-request (url &key (method :get) jar headers)
  "Values status, body and headers of METHOD on URL, sent as it is, as a
browser follows a redirect; redirects are not followed."
  (multiple-value-bind (bytes status response-headers)
      (drakma:http-request url :method method :cookie-jar jar :preserve-uri t
                           :additional-headers headers :redirect nil
                           :external-format-out :utf-8 :force-binary t)
    (values status (if bytes (sb-ext:octets-to-string bytes :external-format :utf-8) "")
            response-headers)))

(defun location-url (headers)
  (cdr (assoc :location headers)))

(defun go-to-provider (port &key (jar (make-instance 'drakma:cookie-jar)) (path "/auth/test")
                              parameters)
  "Press the button: POST PATH.  Values the authorization URL and the jar."
  (multiple-value-bind (status body headers)
      (web-request port path :method :post :jar jar :parameters parameters)
    (declare (ignore body))
    (values (and (= status 303) (location-url headers)) jar)))

(defun come-back (authorization-url)
  "The provider's part: its redirect back to Tun's callback, as a URL."
  (multiple-value-bind (status body headers) (absolute-request authorization-url)
    (declare (ignore body))
    (and (= status 302) (location-url headers))))

(defun sign-in-over-provider (port &key (jar (make-instance 'drakma:cookie-jar))
                                     (path "/auth/test"))
  "Sign in with the fake provider from the button at PATH to the callback.
Values the callback's status, its body and headers, and the jar."
  (let* ((authorization (go-to-provider port :jar jar :path path))
         (callback (come-back authorization)))
    (multiple-value-bind (status body headers) (absolute-request callback :jar jar)
      (values status body headers jar))))

(defun encoded (string)
  (drakma:url-encode string :utf-8))

(defun home-location (port)
  "Where / sends a browser: where a login lands."
  (location (nth-value 2 (web-request port "/"))))

(defun account-by-name (name)
  (find name (admin-items "accounts_list") :key (lambda (a) (jget a "name")) :test #'equal))

(defun audited (tool)
  "How many audit entries record TOOL."
  (count tool (admin-items "audit_list" "limit" 100)
         :key (lambda (entry) (jget entry "tool")) :test #'equal))

;;; ------------------------------------------------------------------
;;; A person's session

(defun sign-in-as (port provider email)
  "Sign in at PORT through PROVIDER as the person whose email is EMAIL (also
their subject there).  Values the callback's status and the cookie jar."
  (person-at provider email email)
  (multiple-value-bind (status body headers jar) (sign-in-over-provider port)
    (declare (ignore body headers))
    (values status jar)))

(defun setup-path ()
  "The /setup/CODE path the server announces, or NIL."
  (let ((line (with-output-to-string (out) (tun.auth:announce-setup *app* out))))
    (and (search "/setup/" line)
         (string-trim '(#\Newline) (subseq line (search "/setup/" line))))))

(defun set-up-admin (port provider &key (name "kari") (email "kari@example.no") display-name)
  "Make the first admin, NAME, through /setup and PROVIDER.  Values the
callback's status, its headers and the cookie jar of the admin's session."
  (person-at provider email email)
  (let* ((jar (make-instance 'drakma:cookie-jar))
         (authorization (go-to-provider port :jar jar :path (setup-path)
                                        :parameters `(("name" . ,name) ("provider" . "test")
                                                      ,@(and display-name
                                                             `(("display_name" . ,display-name))))))
         (callback (come-back authorization)))
    (multiple-value-bind (status body headers) (absolute-request callback :jar jar)
      (declare (ignore body))
      (values status headers jar))))

(defun admin-session (port provider)
  "The cookie jar of kari's session, the first admin, made through /setup."
  (nth-value 2 (set-up-admin port provider)))

