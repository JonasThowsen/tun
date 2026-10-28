;;;; auth/sign-in.lisp -- the ways an application lets people sign in, and
;;;; signing in with an identity provider (spec/auth.md 3.5).
;;;;
;;;; An application lists its strategies in define-application's (:sign-in
;;;; ...) option; each becomes an instance of a strategy class.  A preset is
;;;; a subclass that fills in a provider: GOOGLE-STRATEGY is OIDC-STRATEGY
;;;; with Google's issuer and endpoints, WORKOS-STRATEGY with those of an
;;;; AuthKit domain.
;;;;
;;;; Signing in takes two requests.  START-SIGN-IN stores an attempt and
;;;; gives the URL that sends the browser to the provider; FINISH-SIGN-IN
;;;; takes the code the browser brings back, asks the provider who it is,
;;;; and logs in the account that identity is linked to.  The provider only
;;;; proves an email address: an admin creates the account for it first.

(in-package #:tun.auth)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Strategies

(defclass sign-in-strategy ()
  ((name :initarg :name :reader strategy-name
         :documentation "The strategy's name in URLs, such as \"google\".")
   (label :initarg :label :reader strategy-label
          :documentation "What people see, such as \"Google\"."))
  (:documentation "A way to sign in that an application offers."))

(defclass oidc-strategy (sign-in-strategy)
  ((issuer :initarg :issuer :reader strategy-issuer)
   (issuers :initarg :issuers :initform nil
            :documentation "Every iss value the provider's ID tokens may carry; by
default only ISSUER.")
   (authorization-endpoint :initarg :authorization-endpoint
                           :reader strategy-authorization-endpoint)
   (token-endpoint :initarg :token-endpoint :reader strategy-token-endpoint)
   (client-id :initarg :client-id :reader strategy-client-id)
   (client-secret :initarg :client-secret :reader strategy-client-secret)
   (scopes :initarg :scopes :initform "openid email profile" :reader strategy-scopes)
   (authorization-parameters :initarg :authorization-parameters :initform nil
                             :reader strategy-authorization-parameters
                             :documentation "More parameters for the authorization request,
an alist of strings."))
  (:documentation "An OpenID Connect provider, signed in to with the
authorization code flow and PKCE."))

(defclass google-strategy (oidc-strategy) ()
  (:default-initargs
   :name "google" :label "Google"
   :issuer "https://accounts.google.com"
   :issuers '("https://accounts.google.com" "accounts.google.com")
   :authorization-endpoint "https://accounts.google.com/o/oauth2/v2/auth"
   :token-endpoint "https://oauth2.googleapis.com/token"
   :authorization-parameters '(("prompt" . "select_account")))
  (:documentation "Google's accounts, Gmail and Workspace alike."))

(defclass workos-strategy (oidc-strategy)
  ((domain :initarg :domain :reader strategy-domain
           :documentation "The environment's AuthKit domain, such as \"acme.authkit.app\"."))
  (:default-initargs :name "workos" :label "WorkOS"
                     ;; AuthKit's own session outlives a logout from Tun.
                     :authorization-parameters '(("prompt" . "login")))
  (:documentation "WorkOS AuthKit: its own hosted page signs people in, with
Google, Microsoft, email and whatever else the WorkOS environment allows, so
the button names no provider.  AuthKit is an OpenID Connect provider whose
issuer and endpoints follow from its domain."))

(defun authkit-url (domain)
  "DOMAIN as the URL WorkOS issues tokens from: https:// unless DOMAIN names
its scheme, without a trailing slash."
  (let ((text (string-right-trim "/" (trim domain))))
    (if (search "://" text) text (concatenate 'string "https://" text))))

(defmethod initialize-instance :after ((strategy workos-strategy) &key)
  (when (slot-boundp strategy 'domain)
    (let ((url (authkit-url (strategy-domain strategy))))
      (unless (or (string-prefix-p "https://" url) (string-prefix-p "http://" url))
        (error ":domain ~s is not a host name or an http(s) URL" (strategy-domain strategy)))
      (setf (slot-value strategy 'issuer) url
            (slot-value strategy 'authorization-endpoint) (concatenate 'string url "/oauth2/authorize")
            (slot-value strategy 'token-endpoint) (concatenate 'string url "/oauth2/token")))))

(defgeneric strategy-button-label (strategy)
  (:documentation "The provider a sign-in button names, «Sign in with Google»,
or NIL for a plain «Sign in».")
  (:method ((strategy sign-in-strategy)) (strategy-label strategy))
  (:method ((strategy workos-strategy)) nil))

(defgeneric required-settings (strategy)
  (:documentation "The settings STRATEGY cannot do without, once its class has
filled in its own.")
  (:method ((strategy oidc-strategy))
    '(:issuer :authorization-endpoint :token-endpoint :client-id :client-secret :name :label))
  (:method ((strategy workos-strategy))
    '(:domain :client-id :client-secret :name :label)))

(defun strategy-issuers (strategy)
  (or (slot-value strategy 'issuers) (list (strategy-issuer strategy))))

(defparameter *strategy-classes*
  '((:google . google-strategy)
    (:workos . workos-strategy)
    (:oidc . oidc-strategy))
  "The strategy each keyword in (:sign-in ...) names.")

(defun make-strategy (spec)
  "The strategy SPEC, one entry of (:sign-in ...), describes.  Values it and a
list of problems; the strategy is NIL when there are any."
  (destructuring-bind (kind &rest settings) spec
    (let ((class (cdr (assoc kind *strategy-classes*)))
          (initargs '())
          (problems '()))
      (when (eq kind :password)
        (return-from make-strategy
          (values nil (list (format nil "(:password) is no strategy: Tun keeps no passwords ~
                                         (spec/auth.md 3.1); sign in through a provider, ~
                                         such as (:workos ...)")))))
      (unless class
        (return-from make-strategy
          (values nil (list (format nil "~(~s~) is not a sign-in strategy; ~
                                         there are ~{~(~s~)~^, ~}"
                                    kind (mapcar #'car *strategy-classes*))))))
      (loop for (key value) on settings by #'cddr
            do (multiple-value-bind (text missing)
                   (configured-value value)
                 (if missing
                     (push (format nil "~(~a ~s~) needs ~a" kind key missing) problems)
                     (setf initargs (list* key text initargs)))))
      (let ((prototype (and (null problems)
                            (handler-case (apply #'make-instance class initargs)
                              (error (e)
                                (push (format nil "~(~a~): ~a" kind e) problems)
                                nil)))))
        (when (typep prototype 'oidc-strategy)
          (dolist (key (required-settings prototype))
            (unless (slot-boundp prototype (find-symbol (symbol-name key) '#:tun.auth))
              (push (format nil "~(~a~) needs ~(~s~)" kind key) problems)))
          (unless (every (lambda (c) (or (lower-case-p c) (digit-char-p c) (char= c #\-)))
                         (strategy-name prototype))
            (push (format nil "~(~a~) :name ~s: lowercase letters, digits and -"
                          kind (strategy-name prototype))
                  problems)))
        (if problems
            (values nil (reverse problems))
            (values prototype nil))))))

(defun make-strategies (specs)
  "The strategies SPECS describe, those that can be made.  Values them and
the problems with the rest."
  (let ((strategies '()) (problems '()))
    (dolist (spec specs)
      (multiple-value-bind (strategy trouble) (make-strategy spec)
        (if strategy
            (push strategy strategies)
            (setf problems (append problems trouble)))))
    (values (nreverse strategies) problems)))

(defun application-strategies (&optional (application *application*))
  "The ways people sign in to APPLICATION: what its (:sign-in ...) lists and
can be made, or (:NONE).  Made once per process."
  (let ((state (auth-state application)))
    (sb-thread:with-mutex ((auth-state-lock state))
      (or (auth-state-strategies state)
          (setf (auth-state-strategies state)
                (or (make-strategies (application-sign-in-specs application))
                    (list :none)))))))

(defun sign-in-strategies (&optional (application *application*))
  "The strategies APPLICATION offers, in the order the client listed them."
  (remove :none (application-strategies application)))

(defun (setf sign-in-strategies) (strategies &optional (application *application*))
  "Make STRATEGIES the ways people sign in to APPLICATION, for tests and the REPL."
  (let ((state (auth-state application)))
    (sb-thread:with-mutex ((auth-state-lock state))
      (setf (auth-state-strategies state) (or strategies (list :none))))))

(defun sign-in-problems (application-class)
  "What keeps APPLICATION-CLASS from letting anyone sign in, as lines for the
server's log: a strategy it lists that cannot be made, or no strategy at
all (spec/auth.md 3.4).  NIL when every one can be made."
  (let ((specs (application-sign-in-specs application-class)))
    (if specs
        (nth-value 1 (make-strategies specs))
        (list (format nil "no way to sign in: list an identity provider in ~
                           define-application's (:sign-in ...), such as (:workos :domain ... ~
                           :client-id ... :client-secret ...)")))))

(defun identity-providers (&optional (application *application*))
  "APPLICATION's OpenID Connect strategies."
  (remove-if-not (lambda (s) (typep s 'oidc-strategy)) (sign-in-strategies application)))

(defun find-identity-provider (name &optional (application *application*))
  (find name (identity-providers application) :key #'strategy-name :test #'equal))

;;; ------------------------------------------------------------------
;;; Records

(define-entity account-identity (:label "Sign-in identity" :id-prefix "aid"
                                        :table "account_identities" :internal t
                                        :unique (("strategy" "subject") ("account_id" "strategy"))
                                        :indexes (("account_id")))
  ((account-id :type (id account) :required t :input nil)
   (strategy :type (string :max 64) :input nil)
   (issuer :type (string :max 400) :input nil)
   (subject :type (string :max 255) :input nil)
   (email :type (string :max 320) :input nil)
   (linked-at :type timestamp :input nil)
   (last-used-at :type timestamp :input nil)))

(define-entity sign-in-attempt (:label "Sign-in attempt" :id-prefix "sia"
                                       :table "sign_in_attempts" :internal t
                                       :unique (("state_hash")))
  ((strategy :type (string :max 64) :input nil)
   (state-hash :type (string :max 64) :input nil :secret t)
   (nonce :type (string :max 64) :input nil :secret t)
   (verifier :type (string :max 128) :input nil :secret t)
   (purpose :type (enum "login" "setup") :input nil)
   (setup-hash :type (string :max 64) :input nil :secret t)
   (account-name :type (string :max 64) :input nil)
   (display-name :type (string :max 120) :input nil)
   (expires-at :type timestamp :input nil)))

(defparameter +attempt-lifetime+ 600 "Seconds a sign-in attempt waits for the provider.")
(defparameter +sign-in-cookie+ "tun_sign_in")

(defun account-strategies (account)
  "The names of the strategies linked to ACCOUNT, such as (\"google\")."
  (sort (mapcar #'account-identity-strategy
                (select 'account-identity :where `(:= "account_id" ,(entity-id account))))
        #'string<))

(defun account-welcomed-p (name)
  "True when the account NAME is an active person who has been invited
(spec/auth.md 3.6) or has signed in: someone who knows the client and may
be mailed about it.  A person created quietly, for their records to be
imported first, is not yet (spec/auth.md 2)."
  (let ((account (find-account-by-name name)))
    (and account (person-p account) (account-active-p account)
         (or (account-invited-at account) (account-strategies account))
         t)))

(defun unlink-identities (account)
  "Remove ACCOUNT's identities, in the caller's write transaction."
  (dolist (identity (select 'account-identity :where `(:= "account_id" ,(entity-id account))))
    (delete-entity identity)))

;;; ------------------------------------------------------------------
;;; Refusals

(define-condition sign-in-refused (error)
  ((status :initarg :status :reader sign-in-refused-status)
   (message :initarg :message
            :documentation "A string, or a TEXT written in the language of the place
it is shown (spec/i18n.md 3.1).")
   (detail :initarg :detail :initform nil :reader sign-in-refused-detail))
  (:documentation "A sign-in through a provider that did not log anyone in:
STATUS and MESSAGE are for the person, DETAIL for the server's log.")
  (:report (lambda (c s)
             (format s "Sign-in refused (~d): ~a~@[; ~a~]" (sign-in-refused-status c)
                     (sign-in-refused-message c) (sign-in-refused-detail c)))))

(defun sign-in-refused-message (condition)
  "CONDITION's message for the person, written in the current language."
  (render-text (slot-value condition 'message)))

(defun refuse-sign-in (status message &optional detail)
  (error 'sign-in-refused :status status :message message :detail detail))

(defun attempt-unusable ()
  (deferred-tr "The sign-in could not be completed. Try again."))

;;; ------------------------------------------------------------------
;;; Starting

(defun check-account-names (name display-name)
  "Refuse, with invalid_input as accounts_create would, a NAME or
DISPLAY-NAME the first admin cannot have: checked before setup sends the
browser to a provider."
  (let ((problems '()))
    (unless (and (stringp name) (account-name-p name))
      (push (cons "name"
                  (deferred-tr "only lower-case letters, digits, full stops, underscores and hyphens"))
            problems))
    (when (and (stringp display-name) (> (length display-name) 120))
      (push (cons "display_name" (deferred-tr "at most ~d characters" 120)) problems))
    (when problems
      (fail-fields (nreverse problems)))))

(defun start-sign-in (strategy redirect-uri &key setup-code name display-name)
  "Begin signing in with STRATEGY, an OIDC strategy, whose callback is
REDIRECT-URI.  With SETUP-CODE the attempt creates the first admin, NAME,
when it comes back.  Values the state, for the tun_sign_in cookie, and the
URL to send the browser to."
  (check-type strategy oidc-strategy)
  (check-type redirect-uri string)
  (let ((state (new-secret-token))
        (nonce (new-secret-token))
        (verifier (new-secret-token)))
    (with-transaction (:write)
      (dolist (stale (select 'sign-in-attempt :where `(:<= "expires_at" ,(now))))
        (delete-entity stale))
      (insert (make-instance 'sign-in-attempt
                             :strategy (strategy-name strategy)
                             :state-hash (sha256-hex state) :nonce nonce :verifier verifier
                             :purpose (if setup-code "setup" "login")
                             :setup-hash (and setup-code (sha256-hex setup-code))
                             :account-name name :display-name display-name
                             :expires-at (+ (now) +attempt-lifetime+))))
    (values state
            (authorization-url (strategy-authorization-endpoint strategy)
                               :client-id (strategy-client-id strategy)
                               :redirect-uri redirect-uri :scopes (strategy-scopes strategy)
                               :state state :nonce nonce :verifier verifier
                               :extra-parameters (strategy-authorization-parameters strategy)))))

;;; ------------------------------------------------------------------
;;; Finishing

(defun take-attempt (strategy state cookie)
  "The attempt STATE names, removed so it is used once, when it is
STRATEGY's, unexpired, and COOKIE (the browser's tun_sign_in) is STATE."
  (let ((attempt (and (stringp state) (= (length state) 64)
                      (with-transaction (:write)
                        (let ((row (select-one 'sign-in-attempt
                                               :where `(:= "state_hash" ,(sha256-hex state)))))
                          (when row (delete-entity row))
                          row)))))
    (unless (and attempt
                 (equal (sign-in-attempt-strategy attempt) (strategy-name strategy))
                 (< (now) (sign-in-attempt-expires-at attempt))
                 (constant-time-string= cookie state))
      (refuse-sign-in 400 (attempt-unusable)
                      (if attempt "attempt expired, for another strategy, or not this browser's"
                          "no such attempt")))
    attempt))

(defun provider-claims (strategy attempt code redirect-uri)
  "The checked claims of the ID token STRATEGY's provider gives for CODE."
  (handler-case
      (let* ((claims (id-token-claims
                      (exchange-code (strategy-token-endpoint strategy)
                                     :code code :redirect-uri redirect-uri
                                     :client-id (strategy-client-id strategy)
                                     :client-secret (strategy-client-secret strategy)
                                     :verifier (sign-in-attempt-verifier attempt))))
             (problem (claim-problem claims :issuers (strategy-issuers strategy)
                                     :client-id (strategy-client-id strategy)
                                     :nonce (sign-in-attempt-nonce attempt))))
        (when problem
          (provider-failure "~a" problem))
        claims)
    (provider-failure (e)
      (refuse-sign-in 502 (deferred-tr "~a did not answer as expected. Try again."
                                       (strategy-label strategy))
                      (provider-failure-detail e)))))

(defun no-account (email)
  (refuse-sign-in 403 (deferred-tr "There is no account for ~a here. Ask an administrator for access."
                                   email)))

(defun link-identity (account strategy claims)
  "Link the identity CLAIMS name to ACCOUNT, audited, in the caller's write
transaction."
  (insert (make-instance 'account-identity
                         :account-id (entity-id account) :strategy (strategy-name strategy)
                         :issuer (jget claims "iss") :subject (jget claims "sub")
                         :email (normalize-email (jget claims "email"))
                         :linked-at (now) :last-used-at (now)))
  (with-actor ((account-actor account))
    (write-system-audit "identity_linked" "ok" :entity-type "account"
                        :entity-id (entity-id account))))

(defun identity-account (strategy claims)
  "The account the identity in CLAIMS signs in to, linking it by email on
its first sign-in, in the caller's write transaction.  Refuses when there
is none."
  (let* ((email (normalize-email (jget claims "email")))
         (identity (select-one 'account-identity
                               :where `(:and (:= "strategy" ,(strategy-name strategy))
                                             (:= "subject" ,(jget claims "sub"))))))
    (if identity
        (let ((account (fetch 'account (account-identity-account-id identity))))
          (unless (and account (account-active-p account) (person-p account))
            (no-account email))
          (setf (account-identity-last-used-at identity) (now))
          (save identity)
          account)
        (let ((account (find-account-by-email email)))
          (unless (and account (account-active-p account) (person-p account)
                       (null (select-one 'account-identity
                                         :where `(:and (:= "account_id" ,(entity-id account))
                                                       (:= "strategy"
                                                           ,(strategy-name strategy))))))
            (no-account email))
          (link-identity account strategy claims)
          account))))

(defun log-in-session (account action)
  "Start a session for ACCOUNT, audited as ACTION, in the caller's write
transaction.  Values the cookie value and the account."
  (end-dead-sessions account)
  (multiple-value-bind (cookie session) (start-session account)
    (let ((*credential* (entity-id session)))
      (with-actor ((account-actor account))
        (write-system-audit action "ok" :entity-type "account" :entity-id (entity-id account))))
    (values cookie account)))

(defun setup-admin (strategy attempt claims)
  "Create the first admin from the setup ATTEMPT and the identity in CLAIMS,
in the caller's write transaction, when setup is still open in this process."
  (let ((code (current-setup-code)))
    (unless (and code (constant-time-string= (sha256-hex code)
                                             (sign-in-attempt-setup-hash attempt))
                 (null (active-admin-people)))
      (refuse-sign-in 404 (deferred-tr "Setup has already been done.")))
    (let* ((display-name (or (sign-in-attempt-display-name attempt)
                             (let ((name (jget claims "name")))
                               (and (stringp name) (plusp (length name))
                                    (subseq name 0 (min 120 (length name)))))))
           (arguments (jobj "name" (sign-in-attempt-account-name attempt) "kind" "person"
                            "role" "admin" "email" (jget claims "email")))
           (account (progn
                      (when display-name
                        (setf (gethash "display_name" arguments) display-name))
                      (fetch 'account
                             (jget (handler-case
                                       (with-actor ((system-actor "setup"))
                                         (call-tool "accounts_create" arguments))
                                     (operation-error (e)
                                       (refuse-sign-in 409 (operation-error-message e)
                                                       (with-language (:source)
                                                         (operation-error-message e)))))
                                   "id")))))
      (link-identity account strategy claims)
      (log-in-session account "setup"))))

(defun finish-sign-in (strategy &key state cookie code error redirect-uri)
  "Finish signing in with STRATEGY: the browser came back with STATE, and
CODE or the provider's ERROR, carrying COOKIE.  Values the new session's
cookie value, the account, and :SETUP or :LOGIN for what the attempt was;
signals SIGN-IN-REFUSED when nobody is logged in."
  (check-type strategy oidc-strategy)
  (let ((attempt (take-attempt strategy state cookie)))
    (when (or error (not (stringp code)))
      (refuse-sign-in 400 (deferred-tr "Signing in with ~a was cancelled."
                                       (strategy-label strategy))
                      (format nil "provider error ~a" (or error "without a code"))))
    (let ((claims (provider-claims strategy attempt code redirect-uri)))
      (if (equal (sign-in-attempt-purpose attempt) "setup")
          (multiple-value-bind (cookie account)
              (with-transaction (:write) (setup-admin strategy attempt claims))
            (setup-code)                ; closes setup in this process
            (values cookie account :setup))
          (multiple-value-bind (cookie account)
              (with-transaction (:write)
                (log-in-session (identity-account strategy claims) "login"))
            (values cookie account :login))))))
