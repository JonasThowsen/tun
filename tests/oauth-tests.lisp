;;;; tests/oauth-tests.lisp -- MCP clients that sign in through WorkOS
;;;; (spec/auth.md 5.1), over real HTTP against the fake provider, which
;;;; plays AuthKit: it publishes RSA keys of its own and signs access tokens
;;;; with them.

(in-package #:tun.tests)

(def-suite oauth :in core)
(in-suite oauth)

;;; ------------------------------------------------------------------
;;; Signing as AuthKit does

(defun new-rsa-key (&optional (bits 2048))
  "A new RSA key pair, as (private public)."
  (multiple-value-list (ironclad:generate-key-pair :rsa :num-bits bits)))

(defvar *test-rsa-keys* (make-hash-table :test 'eql)
  "Bits -> an RSA key pair, made once: making one takes a moment.")

(defun test-rsa-key (&optional (bits 2048))
  (or (gethash bits *test-rsa-keys*)
      (setf (gethash bits *test-rsa-keys*) (new-rsa-key bits))))

(defun key-integers (key)
  "The modulus, the public and the private exponent of the RSA key pair KEY."
  (destructuring-bind (private public) key
    (values (getf (ironclad:destructure-public-key public) :n)
            (getf (ironclad:destructure-public-key public) :e)
            (getf (ironclad:destructure-private-key private) :d))))

(defun rs256-signature (key message)
  "The RSASSA-PKCS1-v1_5 SHA-256 signature of MESSAGE (octets) with KEY,
written here apart from Tun's check (RFC 8017 8.2.1)."
  (multiple-value-bind (n e d) (key-integers key)
    (declare (ignore e))
    (let* ((k (ceiling (integer-length n) 8))
           (digest (concatenate '(vector (unsigned-byte 8))
                                #(#x30 #x31 #x30 #x0d #x06 #x09 #x60 #x86 #x48 #x01 #x65 #x03
                                  #x04 #x02 #x01 #x05 #x00 #x04 #x20)
                                (ironclad:digest-sequence :sha256 message)))
           (encoded (concatenate '(vector (unsigned-byte 8))
                                 #(0 1) (make-array (- k (length digest) 3) :initial-element #xff)
                                 #(0) digest)))
      (ironclad:integer-to-octets (ironclad:expt-mod (ironclad:octets-to-integer encoded) d n)
                                  :n-bits (* 8 k)))))

(defun json-part (&rest keys-and-values)
  (base64url (sb-ext:string-to-octets (to-json-string (apply #'jobj keys-and-values))
                                      :external-format :utf-8)))

(defun signed-jwt (key header claims)
  "The compact JWT of HEADER and CLAIMS (alists) signed with KEY."
  (let ((input (format nil "~a.~a"
                       (apply #'json-part (loop for (k . v) in header append (list k v)))
                       (apply #'json-part (loop for (k . v) in claims append (list k v))))))
    (format nil "~a.~a" input
            (base64url (rs256-signature key (sb-ext:string-to-octets input :external-format :ascii))))))

(defun mcp-url (port) (format nil "http://127.0.0.1:~d/mcp" port))

(defun access-token (provider port &key (sub "user_kari") (kid "k1") (key (test-rsa-key))
                                     (alg "RS256") claims)
  "An access token PROVIDER, as AuthKit, gives an MCP client for /mcp at
PORT, signed with KEY; CLAIMS (an alist) replace the right ones."
  (let* ((now (unix-now provider))
         (right `(("iss" . ,(provider-url provider)) ("aud" . ,(mcp-url port))
                  ("sub" . ,sub) ("iat" . ,now) ("exp" . ,(+ now 300))
                  ("client_id" . "client_mcp") ("jti" . "jti_1"))))
    (dolist (claim claims)
      (setf right (cons claim (remove (car claim) right :key #'car :test #'equal))))
    (signed-jwt key `(("alg" . ,alg) ("kid" . ,kid) ("typ" . "JWT")) right)))

(defun publish-key (provider kid &optional (key (test-rsa-key)))
  "Make PROVIDER's key set hold KEY, a key pair, as KID too."
  (push (cons kid key) (provider-signing-keys provider)))

(defmacro with-workos ((provider port) &body body)
  "Run BODY with an authenticated server on PORT signing in through PROVIDER
as WorkOS, whose key set holds the test key as k1."
  `(with-test-server (,port :identity :authenticated)
     (with-provider (,provider)
       (setf (tun.auth:sign-in-strategies *app*)
             (list (make-instance 'tun.auth:workos-strategy :domain (provider-url ,provider)
                                  :client-id +client-id+ :client-secret +client-secret+)))
       (publish-key ,provider "k1")
       ,@body)))

(defun link-in-browser (port provider sub email)
  "Sign in through WorkOS in the browser as SUB, which links the identity."
  (person-at provider sub email)
  (sign-in-over-provider port :path "/auth/workos"))

(defun oauth-call (port token tool &optional (arguments (jobj)))
  (token-call port token tool arguments))

(defun get-json-at (port path)
  "Values the status and the JSON of GET PATH."
  (multiple-value-bind (status body) (web-request port path)
    (values status (and (= status 200) (parse-json body)))))

;;; ------------------------------------------------------------------
;;; Tests

(test without-workos-there-is-no-oauth
  (with-test-server (port :identity :authenticated)
    (dolist (path '("/.well-known/oauth-protected-resource"
                    "/.well-known/oauth-protected-resource/mcp"
                    "/.well-known/oauth-authorization-server"))
      (is (= 404 (web-request port path)) "~a" path))
    (multiple-value-bind (status json headers) (mcp-request port "{}")
      (declare (ignore json))
      (is (= 401 status))
      (is (equal "Bearer realm=\"tun\"" (cdr (assoc :www-authenticate headers)))))))

(test the-resource-says-where-to-sign-in
  (with-workos (provider port)
    (dolist (path '("/.well-known/oauth-protected-resource"
                    "/.well-known/oauth-protected-resource/mcp"))
      (multiple-value-bind (status json) (get-json-at port path)
        (is (= 200 status))
        (is (equal (mcp-url port) (jget json "resource")))
        (is (equalp (vector (provider-url provider)) (jget json "authorization_servers")))
        (is (equalp #("header") (jget json "bearer_methods_supported")))))
    (multiple-value-bind (status json) (get-json-at port "/.well-known/oauth-authorization-server")
      (is (= 200 status))
      (is (equal (provider-url provider "/oauth2/authorize") (jget json "authorization_endpoint"))
          "AuthKit's own metadata"))
    (multiple-value-bind (status json headers) (mcp-request port "{}")
      (declare (ignore json))
      (is (= 401 status))
      (is (equal (format nil "Bearer realm=\"tun\", resource_metadata=\"http://127.0.0.1:~d/.well-known/oauth-protected-resource\"" port)
                 (cdr (assoc :www-authenticate headers)))))
    (multiple-value-bind (status json headers) (mcp-request port "{}" :token "junk")
      (declare (ignore json))
      (is (= 401 status))
      (is (search "error=\"invalid_token\"" (cdr (assoc :www-authenticate headers))))
      (is (search "resource_metadata=" (cdr (assoc :www-authenticate headers))))))
  (with-test-server (port :identity :authenticated :public-url "https://tun.example")
    (with-provider (provider)
      (setf (tun.auth:sign-in-strategies *app*)
            (list (make-instance 'tun.auth:workos-strategy :domain (provider-url provider)
                                 :client-id +client-id+ :client-secret +client-secret+)))
      (is (equal "https://tun.example/mcp"
                 (jget (nth-value 1 (get-json-at port "/.well-known/oauth-protected-resource"))
                       "resource"))
          "the resource is at the public URL"))))

(test an-access-token-calls-as-its-person
  (with-workos (provider port)
    (make-account "kari" "person" "employee" "kari@example.no")
    (is (= 303 (link-in-browser port provider "user_kari" "kari@example.no")))
    (let* ((token (access-token provider port))
           (whoami (oauth-call port token "accounts_whoami")))
      (is (equal "employee:kari" (jget whoami "actor")))
      (is (equal "oauth" (jget whoami "credential")))
      (multiple-value-bind (json error-p) (oauth-call port token "tokens_create" (jobj "label" "x"))
        (is (eq t error-p))
        (is (string= "forbidden" (error-code-of json)) "no token for oneself through OAuth")))
    (let ((jar (nth-value 3 (link-in-browser port provider "user_kari" "kari@example.no"))))
      (is (search (format nil "claude mcp add --transport http ~a ~a"
                          (string-downcase (application-name *app*)) (mcp-url port))
                  (nth-value 1 (web-request port "/access" :jar jar)))
          "/access shows how to connect without a token"))
    (is (= 403 (token-status port (access-token provider port :sub "user_ola")))
        "a person who never signed in in the browser")
    (multiple-value-bind (status json) (mcp-request port (tools-call-body "accounts_whoami" (jobj))
                                                    :token (access-token provider port :sub "user_ola"))
      (is (= 403 status))
      (is (search "/login" (jget (jget json "error") "message"))))
    (update-account (account-by-name "kari") "status" "disabled")
    (is (= 401 (token-status port (access-token provider port))) "a disabled person")))

(test every-check-on-an-access-token
  (with-workos (provider port)
    (make-account "kari" "person" "employee" "kari@example.no")
    (link-in-browser port provider "user_kari" "kari@example.no")
    (is (= 200 (token-status port (access-token provider port))))
    (let ((now (unix-now provider)))
      (dolist (case (list (list (access-token provider port :claims `(("iss" . "https://elsewhere.example")))
                                "another issuer")
                          (list (access-token provider port :claims '(("aud" . "client_123")))
                                "the client id as audience")
                          (list (access-token provider port :claims `(("exp" . ,(- now 61))))
                                "expired")
                          (list (access-token provider port :claims `(("iat" . ,(+ now 120))))
                                "issued in the future")
                          (list (access-token provider port :claims '(("sub" . "")))
                                "no subject")
                          (list (access-token provider port :alg "HS256") "another algorithm")
                          (list (access-token provider port :kid "unknown") "an unknown key")
                          (list (let ((token (access-token provider port)))
                                  (concatenate 'string token "x"))
                                "a changed signature")
                          (list (let* ((token (access-token provider port))
                                       (dot (position #\. token)))
                                  (concatenate 'string (subseq token 0 (1+ dot))
                                               (json-part "iss" (provider-url provider)
                                                          "aud" (mcp-url port) "sub" "user_kari"
                                                          "iat" now "exp" (+ now 99999))
                                               (subseq token (position #\. token :from-end t))))
                                "changed claims")))
        (destructuring-bind (token what) case
          (is (= 401 (token-status port token)) "~a is refused" what))))
    (is (= 200 (token-status port (access-token provider port
                                                :claims `(("aud" . ,(vector "x" (mcp-url port)))))))
        "an audience list holding the resource")
    (publish-key provider "short" (test-rsa-key 1024))
    (advance-clock 60)
    (is (= 401 (token-status port (access-token provider port :kid "short" :key (test-rsa-key 1024))))
        "a key under 2048 bits")))

(test a-new-key-is-fetched-at-most-once-a-minute
  (with-workos (provider port)
    (make-account "kari" "person" "employee" "kari@example.no")
    (link-in-browser port provider "user_kari" "kari@example.no")
    (is (= 200 (token-status port (access-token provider port))))
    (is (= 1 (provider-key-fetches provider)) "fetched when first needed")
    (is (= 200 (token-status port (access-token provider port))))
    (is (= 1 (provider-key-fetches provider)) "and kept")
    (let ((rotated (new-rsa-key)))
      (publish-key provider "k2" rotated)
      (advance-clock 60)
      (is (= 200 (token-status port (access-token provider port :kid "k2" :key rotated)))
          "a key AuthKit has added since")
      (is (= 2 (provider-key-fetches provider)))
      (is (= 401 (token-status port (access-token provider port :kid "k3" :key rotated))))
      (is (= 2 (provider-key-fetches provider)) "not again within the minute")
      (advance-clock 60)
      (publish-key provider "k3" rotated)
      (is (= 200 (token-status port (access-token provider port :kid "k3" :key rotated))))
      (is (= 3 (provider-key-fetches provider))))))

(test without-authkit-a-new-key-cannot-be-checked
  (with-workos (provider port)
    (make-account "kari" "person" "employee" "kari@example.no")
    (link-in-browser port provider "user_kari" "kari@example.no")
    (is (= 200 (token-status port (access-token provider port))))
    (let ((later (access-token provider port :kid "k2")))
      (setf (provider-down provider) t)
      (advance-clock 60)
      (is (= 200 (token-status port (access-token provider port))) "a kept key still checks")
      (is (= 503 (token-status port later)) "AuthKit is unreachable")
      (is (= 503 (token-status port later)) "and not asked again within the minute")
      (is (= 502 (web-request port "/.well-known/oauth-authorization-server"))))))
