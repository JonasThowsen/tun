;;;; auth/oauth.lisp -- MCP clients that sign in through WorkOS AuthKit: the
;;;; resource server's half of OAuth (spec/auth.md 5.1).
;;;;
;;;; AuthKit is the authorization server: an MCP client such as Claude Code
;;;; registers with it, sends the person there to sign in, and brings back an
;;;; access token, an RS256 JWT.  Tun publishes where AuthKit is, checks a
;;;; token's signature against AuthKit's key set and its claims against this
;;;; resource, and finds the person by the WorkOS identity their first
;;;; sign-in in the browser linked (sign-in.lisp).  The key set and AuthKit's
;;;; metadata are fetched when needed and kept in the process.

(in-package #:tun.auth)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +key-refetch-interval+ 60 "Fewest seconds between fetches of AuthKit's key set.")
(defparameter +metadata-lifetime+ 3600 "Seconds AuthKit's metadata is kept.")
(defparameter +min-rsa-bits+ 2048 "The smallest RSA modulus a signing key may have.")

(defun oauth-strategy (&optional (application *application*))
  "The WorkOS strategy MCP clients sign in through, or NIL: OAuth is on when
APPLICATION signs in with WorkOS."
  (find-if (lambda (strategy) (typep strategy 'workos-strategy))
           (sign-in-strategies application)))

;;; ------------------------------------------------------------------
;;; What AuthKit said, kept per application

(defstruct (oauth-cache (:constructor make-oauth-cache ()))
  (lock (sb-thread:make-mutex :name "oauth cache"))
  (keys '())                    ; ((kid n . e) ...): AuthKit's signing keys
  (keys-fetched-at nil)
  (keys-problem nil)            ; why the last fetch failed, or NIL
  (metadata nil)
  (metadata-fetched-at nil))

(defun oauth-cache (&optional (application *application*))
  (let ((state (auth-state application)))
    (sb-thread:with-mutex ((auth-state-lock state))
      (or (auth-state-oauth state)
          (setf (auth-state-oauth state) (make-oauth-cache))))))

(defun authkit-endpoint (strategy path)
  (concatenate 'string (strategy-issuer strategy) path))

;;; ------------------------------------------------------------------
;;; Discovery (RFC 9728, RFC 8414)

(defun protected-resource-metadata (strategy resource)
  "Where an MCP client signs in to reach RESOURCE, the URL of /mcp."
  (jobj "resource" resource
        "authorization_servers" (jarr (list (strategy-issuer strategy)))
        "bearer_methods_supported" (jarr (list "header"))))

(defun authorization-server-metadata (strategy)
  "AuthKit's own metadata, kept for an hour, for clients that ask the
resource for it.  Signals PROVIDER-FAILURE when it cannot be fetched."
  (let ((cache (oauth-cache)))
    (sb-thread:with-mutex ((oauth-cache-lock cache))
      (let ((fetched (oauth-cache-metadata-fetched-at cache)))
        (unless (and fetched (< (now) (+ fetched +metadata-lifetime+)))
          (setf (oauth-cache-metadata cache)
                (get-json (authkit-endpoint strategy "/.well-known/oauth-authorization-server"))
                (oauth-cache-metadata-fetched-at cache) (now)))
        (oauth-cache-metadata cache)))))

;;; ------------------------------------------------------------------
;;; AuthKit's signing keys (RFC 7517)

(defun octets-integer (octets)
  "OCTETS as an unsigned big-endian integer."
  (ironclad:octets-to-integer octets))

(defun key-set-keys (json)
  "The keys of the JWK set JSON that may check an RS256 signature, as
((kid n . e) ...)."
  (let ((keys (jget json "keys")))
    (unless (and (vectorp keys) (not (stringp keys)))
      (provider-failure "the key set has no keys"))
    (loop for key across keys
          when (and (hash-table-p key)
                    (equal (jget key "kty") "RSA")
                    (member (jget key "use") '(nil "sig") :test #'equal)
                    (member (jget key "alg") '(nil "RS256") :test #'equal)
                    (every (lambda (field) (stringp (jget key field))) '("kid" "n" "e")))
          collect (list* (jget key "kid")
                         (octets-integer (base64url-octets (jget key "n")))
                         (octets-integer (base64url-octets (jget key "e")))))))

(defun fetch-keys-p (cache)
  "True, noting the fetch, when the key set may be fetched again now.  Called
with CACHE's lock held."
  (let ((fetched (oauth-cache-keys-fetched-at cache)))
    (when (or (null fetched) (>= (- (now) fetched) +key-refetch-interval+))
      (setf (oauth-cache-keys-fetched-at cache) (now)))))

(defun signing-key (strategy kid)
  "The (n . e) of AuthKit's key KID, or NIL when it has none by that id.  An
unknown KID fetches the key set again, at most once a minute; while the last
fetch failed, signals PROVIDER-FAILURE."
  (let ((cache (oauth-cache)))
    (flet ((known () (cdr (assoc kid (oauth-cache-keys cache) :test #'equal))))
      (multiple-value-bind (key fetch problem)
          (sb-thread:with-mutex ((oauth-cache-lock cache))
            (let ((key (known)))
              (values key (and (null key) (fetch-keys-p cache)) (oauth-cache-keys-problem cache))))
        (cond (key key)
              (fetch
               (handler-case
                   (let ((keys (key-set-keys (get-json (authkit-endpoint strategy "/oauth2/jwks")))))
                     (sb-thread:with-mutex ((oauth-cache-lock cache))
                       (setf (oauth-cache-keys cache) keys
                             (oauth-cache-keys-problem cache) nil)
                       (known)))
                 (provider-failure (e)
                   (sb-thread:with-mutex ((oauth-cache-lock cache))
                     (setf (oauth-cache-keys-problem cache) (provider-failure-detail e)))
                   (error e))))
              (problem (provider-failure "~a" problem))
              (t nil))))))

;;; ------------------------------------------------------------------
;;; Checking an access token

(defparameter +sha256-digest-info+
  (coerce #(#x30 #x31 #x30 #x0d #x06 #x09 #x60 #x86 #x48 #x01 #x65 #x03 #x04 #x02 #x01
            #x05 #x00 #x04 #x20)
          '(simple-array (unsigned-byte 8) (*)))
  "What PKCS #1 puts before a SHA-256 digest: its DER DigestInfo prefix
(RFC 8017 9.2, note 1).")

(defun rs256-valid-p (n e message signature)
  "True when SIGNATURE is an RSASSA-PKCS1-v1_5 signature with SHA-256 of
MESSAGE (both octets) under the public key N, E (RFC 8017 8.2.2).  The
encoded message is built whole and compared, never parsed."
  (let ((k (ceiling (integer-length n) 8)))
    (and (= (length signature) k)
         (let ((s (octets-integer signature))
               (digest (concatenate '(simple-array (unsigned-byte 8) (*))
                                    +sha256-digest-info+
                                    (ironclad:digest-sequence :sha256 message))))
           (and (< s n)
                (ironclad:constant-time-equal
                 (ironclad:integer-to-octets (ironclad:expt-mod s e n) :n-bits (* 8 k))
                 (concatenate '(simple-array (unsigned-byte 8) (*))
                              #(0 1)
                              (make-array (- k (length digest) 3)
                                          :element-type '(unsigned-byte 8)
                                          :initial-element #xff)
                              #(0)
                              digest)))))))

(defun jwt-parts (token)
  "The header and claims of the compact JWT TOKEN, as JSON objects, then its
signing input and its signature as octets; NIL when TOKEN is not one."
  (let ((parts (cl-ppcre:split "\\." token)))
    (when (= (length parts) 3)
      (handler-case
          (flet ((json (part)
                   (parse-json (sb-ext:octets-to-string (base64url-octets part)
                                                        :external-format :utf-8))))
            (let ((header (json (first parts)))
                  (claims (json (second parts))))
              (when (and (hash-table-p header) (hash-table-p claims))
                (values header claims
                        (sb-ext:string-to-octets (format nil "~a.~a" (first parts) (second parts))
                                                 :external-format :ascii)
                        (base64url-octets (third parts))))))
        (error () nil)))))

(defun access-token-problem (claims &key issuer resource (now (now)))
  "Why CLAIMS from an access token do not let it reach RESOURCE, as a string
for the log, or NIL when they pass: AuthKit at ISSUER issued it for RESOURCE,
it is current, and it names its subject."
  (let ((audience (jget claims "aud"))
        (expires (numeric-date (jget claims "exp")))
        (issued (numeric-date (jget claims "iat")))
        (subject (jget claims "sub")))
    (cond ((not (equal (jget claims "iss") issuer))
           (format nil "issuer ~s is not ~s" (jget claims "iss") issuer))
          ((not (or (equal audience resource)
                    (and (vectorp audience) (not (stringp audience))
                         (find resource audience :test #'equal))))
           (format nil "audience ~s is not ~s" audience resource))
          ((not (and expires (< now (+ expires +clock-leeway+))))
           "the token has expired")
          ((not (and issued (<= issued (+ now +clock-leeway+))))
           "the token was issued in the future")
          ((not (and (stringp subject) (plusp (length subject))))
           "the token has no subject")
          (t nil))))

(defun verified-claims (strategy token resource)
  "The claims of TOKEN when it is an access token AuthKit signed for
RESOURCE.  Values NIL and why not otherwise; signals PROVIDER-FAILURE when
AuthKit's keys cannot be had."
  (multiple-value-bind (header claims input signature) (jwt-parts token)
    (cond ((null header) (values nil "not a JWT"))
          ((not (equal (jget header "alg") "RS256"))
           (values nil (format nil "alg ~s is not RS256" (jget header "alg"))))
          ((not (stringp (jget header "kid"))) (values nil "the token names no key"))
          (t
           (let ((key (signing-key strategy (jget header "kid"))))
             (cond ((null key)
                    (values nil (format nil "AuthKit has no key ~s" (jget header "kid"))))
                   ((< (integer-length (car key)) +min-rsa-bits+)
                    (values nil "the key is shorter than 2048 bits"))
                   ((not (rs256-valid-p (car key) (cdr key) input signature))
                    (values nil "the signature does not verify"))
                   (t (let ((problem (access-token-problem
                                      claims :issuer (strategy-issuer strategy)
                                      :resource resource)))
                        (if problem (values nil problem) claims)))))))))

(defun authenticate-oauth-token (token resource)
  "Values the actor and the credential for TOKEN, a bearer token that is not
Tun's own, when it is an AuthKit access token for RESOURCE, the URL of /mcp
(spec/auth.md 5.1).  Otherwise NIL, then why: :INVALID, :UNLINKED (its
person has not signed in in the browser yet) or :UNREACHABLE (AuthKit's
keys cannot be had), and a detail for the server's log."
  (let ((strategy (oauth-strategy)))
    (if (null strategy)
        (values nil :invalid "OAuth is off: the application does not sign in with WorkOS")
        (multiple-value-bind (claims problem)
            (handler-case (verified-claims strategy token resource)
              (provider-failure (e)
                (return-from authenticate-oauth-token
                  (values nil :unreachable (provider-failure-detail e)))))
          (if (null claims)
              (values nil :invalid problem)
              (with-transaction (:read)
                (let* ((identity (select-one 'account-identity
                                             :where `(:and (:= "strategy" ,(strategy-name strategy))
                                                           (:= "subject" ,(jget claims "sub")))))
                       (account (and identity
                                     (fetch 'account (account-identity-account-id identity)))))
                  (cond ((null identity)
                         (values nil :unlinked (format nil "no account has WorkOS identity ~a"
                                                       (jget claims "sub"))))
                        ((not (and account (account-active-p account) (person-p account)))
                         (values nil :invalid "the account is disabled"))
                        (t (values (account-actor account) (entity-id identity)))))))))))
