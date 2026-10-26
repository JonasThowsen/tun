;;;; auth/oidc.lisp -- the OpenID Connect authorization code flow with PKCE,
;;;; as a client (spec/auth.md 3.5).
;;;;
;;;; Three steps belong to the protocol and nothing else: the URL that sends
;;;; a browser to the provider, the exchange of the code it brings back for
;;;; an ID token, and the checks on that token's claims.  Which account the
;;;; claims belong to is sign-in.lisp's business.
;;;;
;;;; The ID token comes straight from the provider's token endpoint over TLS,
;;;; in exchange for the client secret, so its signature is not checked
;;;; (OpenID Connect Core 3.1.3.7, item 6); its claims are.

(in-package #:tun.auth)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +provider-time-limit+ 10 "Seconds the token exchange may take.")
(defparameter +clock-leeway+ 60 "Seconds the provider's clock and ours may differ.")

(defconstant +unix-epoch+ 2208988800
  "1970-01-01T00:00:00Z in universal time, the epoch a JWT counts its times
from (RFC 7519 2, NumericDate); Tun's clock counts from 1900.")

(defun numeric-date (value)
  "VALUE, a JWT NumericDate, in universal time; NIL when it is not a number."
  (and (realp value) (+ (floor value) +unix-epoch+)))

(define-condition provider-failure (error)
  ((detail :initarg :detail :reader provider-failure-detail))
  (:documentation "The provider did not answer as the protocol says.  DETAIL
is for the server's log and never holds a secret.")
  (:report (lambda (c s) (format s "Identity provider: ~a" (provider-failure-detail c)))))

(defun provider-failure (control &rest arguments)
  (error 'provider-failure :detail (apply #'format nil control arguments)))

;;; ------------------------------------------------------------------
;;; Encodings

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

(defun base64url (octets)
  "OCTETS in unpadded base64url (RFC 4648 5), as PKCE and JWTs use it."
  (let ((standard (cl-base64:usb8-array-to-base64-string octets)))
    (string-right-trim "=" (substitute #\_ #\/ (substitute #\- #\+ standard)))))

(defun base64url-octets (string)
  "The octets STRING encodes in base64url, padded or not."
  (let ((standard (substitute #\/ #\_ (substitute #\+ #\- string))))
    (cl-base64:base64-string-to-usb8-array
     (concatenate 'string standard
                  (make-string (mod (- (length standard)) 4) :initial-element #\=)))))

(defun pkce-challenge (verifier)
  "The S256 code challenge of VERIFIER (RFC 7636 4.2)."
  (base64url (ironclad:digest-sequence
              :sha256 (sb-ext:string-to-octets verifier :external-format :ascii))))

;;; ------------------------------------------------------------------
;;; The three steps

(defun authorization-url (endpoint &key client-id redirect-uri scopes state nonce verifier
                                     extra-parameters)
  "Where to send the browser to sign in: ENDPOINT with the parameters of an
authorization code request with PKCE, then EXTRA-PARAMETERS (an alist)."
  (format nil "~a~:[?~;&~]~a" endpoint (find #\? endpoint)
          (query-string (append `(("response_type" . "code")
                                  ("client_id" . ,client-id)
                                  ("redirect_uri" . ,redirect-uri)
                                  ("scope" . ,scopes)
                                  ("state" . ,state)
                                  ("nonce" . ,nonce)
                                  ("code_challenge" . ,(pkce-challenge verifier))
                                  ("code_challenge_method" . "S256"))
                                extra-parameters))))

(defun post-form (url parameters)
  "POST PARAMETERS (an alist) form-encoded to URL.  Values the status and the
body as a string.  HTTPS is verified against the system's certificates."
  (multiple-value-bind (body status)
      (drakma:http-request url :method :post
                           :content-type "application/x-www-form-urlencoded"
                           :content (query-string parameters)
                           :additional-headers '(("Accept" . "application/json"))
                           :external-format-out :utf-8
                           :force-binary t :redirect nil
                           :verify :required :connection-timeout +provider-time-limit+)
    (values status (if body (sb-ext:octets-to-string body :external-format :utf-8) ""))))

(defun get-json (url)
  "The JSON object at URL, fetched as POST-FORM posts: HTTPS verified, within
the provider's time limit.  Signals PROVIDER-FAILURE when it cannot be had."
  (multiple-value-bind (body status)
      (handler-case
          (call-with-time-limit
           (lambda ()
             (drakma:http-request url :additional-headers '(("Accept" . "application/json"))
                                      :force-binary t :redirect nil
                                      :verify :required :connection-timeout +provider-time-limit+))
           +provider-time-limit+)
        (error (e) (provider-failure "~a unreachable: ~a" url e)))
    (let ((json (and (eql status 200)
                     (handler-case (parse-json (sb-ext:octets-to-string body :external-format :utf-8))
                       (error () nil)))))
      (unless (hash-table-p json)
        (provider-failure "~a answered ~a, not a JSON object" url status))
      json)))

(defun exchange-code (endpoint &key code client-id client-secret redirect-uri verifier)
  "Trade CODE for tokens at the token ENDPOINT (client_secret_post).  The
ID token the provider answers with; signals PROVIDER-FAILURE otherwise."
  (multiple-value-bind (status body)
      (handler-case
          (call-with-time-limit
           (lambda ()
             (post-form endpoint `(("grant_type" . "authorization_code")
                                   ("code" . ,code)
                                   ("redirect_uri" . ,redirect-uri)
                                   ("client_id" . ,client-id)
                                   ("client_secret" . ,client-secret)
                                   ("code_verifier" . ,verifier))))
           +provider-time-limit+)
        (error (e) (provider-failure "token endpoint unreachable: ~a" e)))
    (let ((json (handler-case (parse-json body)
                  (error () nil))))
      (unless (and (eql status 200) (hash-table-p json))
        ;; The error code (such as invalid_grant) is the provider's word for
        ;; what went wrong; the body may echo nothing secret of ours.
        (provider-failure "token endpoint answered ~a~@[ (~a)~]" status
                          (and (hash-table-p json) (stringp (jget json "error"))
                               (jget json "error"))))
      (let ((id-token (jget json "id_token")))
        (unless (stringp id-token)
          (provider-failure "token endpoint answered without an id_token"))
        id-token))))

(defun id-token-claims (id-token)
  "The claims (a JSON object) in the payload of the compact JWT ID-TOKEN."
  (let ((parts (cl-ppcre:split "\\." id-token)))
    (unless (= (length parts) 3)
      (provider-failure "the id_token is not a JWT"))
    (let ((claims (handler-case
                      (parse-json (sb-ext:octets-to-string (base64url-octets (second parts))
                                                           :external-format :utf-8))
                    (error () nil))))
      (unless (hash-table-p claims)
        (provider-failure "the id_token's payload is not a JSON object"))
      claims)))

(defun claim-problem (claims &key issuers client-id nonce (now (now)))
  "Why CLAIMS from an ID token are not to be trusted, as a string for the
log, or NIL when they pass: the issuer is one of ISSUERS, the audience is
CLIENT-ID, the token is current, its NONCE is ours, and it names a
verified email."
  (let ((issuer (jget claims "iss"))
        (audience (jget claims "aud"))
        (expires (numeric-date (jget claims "exp")))
        (issued (numeric-date (jget claims "iat")))
        (verified (jget claims "email_verified")))
    (cond ((not (member issuer issuers :test #'equal))
           (format nil "issuer ~s is not ~{~s~^ or ~}" issuer issuers))
          ((not (or (equal audience client-id)
                    (and (vectorp audience) (not (stringp audience))
                         (find client-id audience :test #'equal)
                         (equal (jget claims "azp") client-id))))
           "the audience is not our client id")
          ((not (and expires (< now (+ expires +clock-leeway+))))
           "the id_token has expired")
          ((not (and issued (<= issued (+ now +clock-leeway+))))
           "the id_token was issued in the future")
          ((not (and (stringp (jget claims "nonce"))
                     (constant-time-string= (jget claims "nonce") nonce)))
           "the nonce is not ours")
          ((not (stringp (jget claims "sub")))
           "the id_token has no subject")
          ((not (and (stringp (jget claims "email")) (plusp (length (jget claims "email")))))
           "the id_token has no email")
          ((not (or (eq verified t) (equal verified "true")))
           "the email is not verified")
          (t nil))))
