;;;; auth/accounts.lisp -- accounts and their credentials (spec/auth.md 2-4).
;;;;
;;;; An account is a person or an agent with a role; its actor is
;;;; role:name.  The credentials live in records of their own, each holding a
;;;; hash and never the secret: an account's access tokens and a person's
;;;; sessions.  The secrets exist only in the response that hands them out.
;;;; Tun keeps no passwords: a person signs in through an identity provider
;;;; (sign-in.lisp).

(in-package #:tun.auth)

(declaim (optimize (safety 3) (debug 2)))

(define-entity account (:label "Account" :id-prefix "acc" :table "accounts"
                               :unique (("name") ("email")))
  ((name :type (string :min 1 :max 64) :required t :label "Name"
         :description "The actor's name: lower-case letters, digits, full stops, underscores or hyphens.")
   (display-name :type (string :max 120) :label "Display name")
   (kind :type (enum "person" "agent") :required t :label "Type"
         :description "A person signs in in the browser; an agent uses access tokens only.")
   (role :type (enum "admin" "employee" "viewer") :required t :label "Role")
   (email :type email :label "Email" :description "The address a person signs in with.")
   (status :type (enum "active" "disabled") :input nil :initform "active" :label "Status")
   (created-at :type timestamp :input nil :label "Created")
   (created-by :type (string :max 200) :input nil :label "Created by")
   (invited-at :type timestamp :input nil :label "Invited"
               :description "When the last invitation by email was sent.")))

(define-entity access-token (:label "Access token" :id-prefix "tok" :table "access_tokens"
                                    :unique (("token_hash")) :indexes (("account_id")))
  ((account-id :type (id account) :required t :input nil :label "Account")
   (label :type (string :min 1 :max 120) :input nil :label "Description")
   (role :type (enum "admin" "employee" "viewer") :input nil :label "Role")
   (prefix :type (string :max 16) :input nil :label "Start"
           :description "The first characters after tun_, to recognise the token by.")
   (token-hash :type (string :max 64) :input nil :secret t :label "SHA-256 of the token")
   (expires-at :type timestamp :input nil :label "Expires")
   (created-at :type timestamp :input nil :label "Created")
   (created-by :type (string :max 200) :input nil :label "Created by")
   (last-used-at :type timestamp :input nil :label "Last used")
   (revoked-at :type timestamp :input nil :label "Revoked")))

(define-entity session (:label "Session" :id-prefix "ses" :table "sessions" :internal t
                               :unique (("token_hash")) :indexes (("account_id")))
  ((account-id :type (id account) :required t :input nil)
   (token-hash :type (string :max 64) :input nil :secret t)
   (created-at :type timestamp :input nil)
   (last-seen-at :type timestamp :input nil)))

;;; ------------------------------------------------------------------
;;; Accounts

(defun role-keyword (role)
  "The role keyword of ROLE, a role name as accounts and tokens store it."
  (cond ((string= role "admin") :admin)
        ((string= role "employee") :employee)
        ((string= role "viewer") :viewer)
        (t (error "Unknown role ~s" role))))

(defun lower-role (a b)
  "The lower of the role names A and B."
  (if (<= (role-rank (role-keyword a)) (role-rank (role-keyword b))) a b))

(defun account-actor (account &optional (role (account-role account)))
  "The actor ACCOUNT acts as, with ROLE (a role name) when that is lower."
  (make-actor (role-keyword (lower-role role (account-role account))) (account-name account)))

(defun account-name-p (name)
  (and (<= 1 (length name) 64)
       (every (lambda (c) (or (lower-case-p c) (digit-char-p c) (find c "._-"))) name)))

(defun account-active-p (account)
  (equal (account-status account) "active"))

(defun person-p (account)
  (equal (account-kind account) "person"))

(defun find-account-by-name (name)
  "The account whose name, and so whose actor's name, is NAME, or NIL."
  (select-one 'account :where `(:= "name" ,name)))

(defun account-address (name)
  "The email of the account NAME when it is an active person, or NIL: where
a client mails that person (spec/auth.md 2)."
  (let ((account (find-account-by-name name)))
    (and account (person-p account) (account-active-p account)
         (account-email account))))

(defun actor-account-kind (actor)
  "The kind of the active account ACTOR acts for, :PERSON or :AGENT, or NIL
when it acts for none: a claimed actor no account has, the process itself, a
customer (spec/auth.md 2)."
  (let ((account (and (member (actor-role actor) '(:admin :employee :viewer))
                      (find-account-by-name (actor-name actor)))))
    (and account (account-active-p account)
         (if (person-p account) :person :agent))))

(defun account-names (&key role)
  "The names of the active people, in name order; only those with ROLE, a
keyword such as :ADMIN, when it is given (spec/auth.md 2)."
  (let ((active '(:= "status" "active")))
    (mapcar #'account-name
            (remove-if-not #'person-p
                           (select 'account
                                   :where (if role
                                              `(:and ,active (:= "role" ,(string-downcase role)))
                                              active)
                                   :order-by '(("name" :asc)))))))

(defun find-account-by-email (email)
  (select-one 'account :where `(:= "email" ,(normalize-email email))))

(defun normalize-email (email)
  (string-downcase (trim email)))

(defun active-admin-people (&optional except-id)
  "Active admin accounts that are people, other than the one EXCEPT-ID names."
  (remove-if (lambda (account) (or (not (person-p account)) (equal (entity-id account) except-id)))
             (select 'account :where '(:and (:= "role" "admin") (:= "status" "active")))))

;;; ------------------------------------------------------------------
;;; Access tokens

(defparameter +token-prefix+ "tun_")
(defparameter +token-length+ 40 "Characters after tun_: 200 random bits.")
(defparameter *token-touch-seconds* 60 "How stale last_used_at may get before a use writes it.")

(defun new-access-token-string ()
  (concatenate 'string +token-prefix+ (random-token-string +token-length+)))

(defun token-state (token)
  "active, expired or revoked."
  (cond ((access-token-revoked-at token) "revoked")
        ((let ((expires (access-token-expires-at token)))
           (and expires (<= expires (now))))
         "expired")
        (t "active")))

(defun authenticate-token (token)
  "Values the actor and the token's id for TOKEN, the value of an
Authorization: Bearer header, or NIL when it is not a usable token."
  (when (and (stringp token)
             (= (length token) (+ (length +token-prefix+) +token-length+))
             (string-prefix-p +token-prefix+ token))
    (multiple-value-bind (actor id stale)
        (with-transaction (:read)
          (let* ((row (select-one 'access-token :where `(:= "token_hash" ,(sha256-hex token))))
                 (account (and row (equal (token-state row) "active")
                               (fetch 'account (access-token-account-id row)))))
            (when (and account (account-active-p account))
              (values (account-actor account (access-token-role row))
                      (entity-id row)
                      (let ((used (access-token-last-used-at row)))
                        (or (null used) (>= (- (now) used) *token-touch-seconds*)))))))
      (when stale (touch-token id))
      (values actor id))))

(defun touch-token (id)
  "Record that token ID was used.  A failure here never fails the request."
  (handler-case
      (with-transaction (:write)
        (let ((row (fetch 'access-token id)))
          (when row
            (setf (access-token-last-used-at row) (now))
            (save row))))
    (error (e)
      (format *error-output* "~&;; tun auth: could not record use of ~a: ~a~%" id e))))

;;; ------------------------------------------------------------------
;;; Sessions

(defparameter +session-cookie+ "tun_session")
(defparameter +session-lifetime+ (* 30 86400) "Seconds from login to a session's end.")
(defparameter +session-idle+ (* 7 86400) "Seconds without use that end a session sooner.")
(defparameter *session-touch-seconds* 3600
  "How stale last_seen_at may get before a use writes it.")

(defun session-live-p (session)
  (let ((now (now)))
    (and (< now (+ (session-created-at session) +session-lifetime+))
         (< now (+ (session-last-seen-at session) +session-idle+)))))

(defun start-session (account)
  "A new session for ACCOUNT in the caller's write transaction.  Values the
cookie value, which is not stored, and the session record."
  (let* ((cookie (new-secret-token))
         (session (insert (make-instance 'session :account-id (entity-id account)
                                         :token-hash (sha256-hex cookie)
                                         :created-at (now) :last-seen-at (now)))))
    (values cookie session)))

(defgeneric account-disabled (application account)
  (:method-combination progn)
  (:documentation "Called in the write that disables ACCOUNT, after its sessions end,
so the kernel's other parts let go of what belongs to it: push subscriptions
(spec/push.md 3).  Every method is a PROGN method; the default does nothing.")
  (:method progn (application account)
    (declare (ignore application account))
    nil))

(defun end-account-sessions (account &key except)
  "End every session of ACCOUNT but EXCEPT (a session id), in the caller's write transaction."
  (dolist (session (select 'session :where `(:= "account_id" ,(entity-id account))))
    (unless (equal (entity-id session) except)
      (delete-entity session))))

(defun end-dead-sessions (account)
  (dolist (session (select 'session :where `(:= "account_id" ,(entity-id account))))
    (unless (session-live-p session)
      (delete-entity session))))

(defun authenticate-session (cookie)
  "Values the actor and the session's id for COOKIE, the tun_session
cookie's value, or NIL when it names no live session."
  (when (and (stringp cookie) (= (length cookie) 64))
    (multiple-value-bind (actor id stale)
        (with-transaction (:read)
          (let* ((session (select-one 'session :where `(:= "token_hash" ,(sha256-hex cookie))))
                 (account (and session (session-live-p session)
                               (fetch 'account (session-account-id session)))))
            (when (and account (account-active-p account) (person-p account))
              (values (account-actor account) (entity-id session)
                      (>= (- (now) (session-last-seen-at session)) *session-touch-seconds*)))))
      (when stale (touch-session id))
      (values actor id))))

(defun touch-session (id)
  (handler-case
      (with-transaction (:write)
        (let ((session (fetch 'session id)))
          (when session
            (setf (session-last-seen-at session) (now))
            (save session))))
    (error (e)
      (format *error-output* "~&;; tun auth: could not record use of ~a: ~a~%" id e))))

(defun log-out (cookie)
  "End the session COOKIE names, if any."
  (when (stringp cookie)
    (with-transaction (:write)
      (let ((session (select-one 'session :where `(:= "token_hash" ,(sha256-hex cookie)))))
        (when session (delete-entity session))))))

;;; ------------------------------------------------------------------
;;; Per-process state: the setup code, the ways to sign in and what AuthKit
;;; said, never stored.

(defstruct (auth-state (:constructor make-auth-state ()))
  (lock (sb-thread:make-mutex :name "auth state"))
  (setup-code nil)
  (strategies nil)                              ; the ways to sign in (sign-in.lisp)
  (oauth nil))                                  ; AuthKit's keys and metadata (oauth.lisp)

(defvar *auth-state-lock* (sb-thread:make-mutex :name "auth state creation"))

(defun auth-state (&optional (application *application*))
  (sb-thread:with-mutex (*auth-state-lock*)
    (or (application-auth-state application)
        (setf (application-auth-state application) (make-auth-state)))))

;;; ------------------------------------------------------------------
;;; The first administrator (spec/auth.md 4)

(defun setup-needed-p ()
  (null (with-transaction (:read) (active-admin-people))))

(defun setup-code (&optional (application *application*))
  "The code that opens /setup/CODE while the tenant has no active admin
person, made when first needed; NIL once there is one."
  (let ((state (auth-state application))
        (needed (with-application (application) (setup-needed-p))))
    (sb-thread:with-mutex ((auth-state-lock state))
      (if needed
          (or (auth-state-setup-code state)
              (setf (auth-state-setup-code state) (new-secret-token)))
          (setf (auth-state-setup-code state) nil)))))

(defun current-setup-code ()
  "This process's setup code as it stands, without asking the store whether
setup is still needed: for code inside a transaction that checks that itself."
  (let ((state (auth-state)))
    (sb-thread:with-mutex ((auth-state-lock state))
      (auth-state-setup-code state))))

(defun setup-code-valid-p (code)
  "True when CODE is this process's setup code and setup is still open."
  (let ((current (setup-code)))
    (and current (stringp code) (constant-time-string= code current))))

(defun announce-setup (&optional (application *application*) (stream *standard-output*))
  "Print where to create the first administrator, when the tenant needs one:
the whole link when the server knows its public URL."
  (let ((code (setup-code application)))
    (when code
      (format stream "~&tun: no administrator yet; create one at ~@[~a~]/setup/~a~%"
              (application-public-url application) code)
      (finish-output stream))
    code))
