;;;; auth/tools.lisp -- the account and token tools (spec/auth.md 6).
;;;;
;;;; Ordinary operations, so policy, validation, idempotency and audit apply
;;;; as everywhere.  A new token reaches only the caller that created it,
;;;; through SHOW-ONCE: the receipt holds null in its place.

(in-package #:tun.auth)

(declaim (optimize (safety 3) (debug 2)))

(defun account->json (account)
  (let ((json (entity->json account)))
    (setf (gethash "sign_in" json) (jarr (account-strategies account)))
    json))

(defun token->json (token)
  "TOKEN without its hash, with its account's name and its state."
  (let ((json (entity->json token))
        (account (fetch 'account (access-token-account-id token))))
    (remhash "token_hash" json)
    (setf (gethash "account_name" json) (if account (account-name account) :null)
          (gethash "state" json) (token-state token))
    json))

(defmacro refuse-field (field control &rest arguments)
  "Refuse the call with invalid_input on FIELD, its message the literal
CONTROL with ARGUMENTS, written where it is shown (spec/i18n.md 3.1)."
  `(fail-fields (list (cons ,field (deferred-tr ,control ,@arguments)))))

;;; ------------------------------------------------------------------
;;; Accounts

(define-operation accounts-whoami ()
    (:kind :read :title "Who am I"
           :description "The actor the call runs as, the account it belongs to (if there is
one) and how it is proven: token, session, oauth or claimed.")
  (let ((account (find-account-by-name (actor-name *actor*))))
    (jobj "actor" (actor-string *actor*)
          "role" (string-downcase (symbol-name (actor-role *actor*)))
          "credential" (cond ((null *credential*) :null)
                             ((string-prefix-p "tok_" *credential*) "token")
                             ((string-prefix-p "ses_" *credential*) "session")
                             ((string-prefix-p "aid_" *credential*) "oauth")
                             (t *credential*))
          "account" (if account (account->json account) :null))))

(define-operation accounts-list ((limit :type (integer :min 1 :max 500) :default 100
                                        :label "Most results"))
    (:entity account :kind :read :policy :admin :title "List accounts"
             :description "Every account with its role and status, without tokens.")
  (jobj "items" (jarr (mapcar #'account->json
                              (select 'account :order-by '(("name" :asc)) :limit limit)))))

(defun inviter-name ()
  "How an invitation names the caller: their display name, else their name."
  (let ((account (caller-account)))
    (or (and account (account-display-name account))
        (actor-name *actor*))))

(defun invitation-text (account)
  "What an invitation tells ACCOUNT, a new person: who let them in, and how
to come in (spec/auth.md 3.6)."
  (tr "~a has given you access to ~a.~%~%Sign in with ~@[~{~a~^ or ~} and ~]the email address ~a:~%~a"
          (inviter-name) (application-title *application*)
          (remove nil (mapcar #'strategy-button-label (identity-providers)))
          (account-email account) (absolute-url "/login")))

(defparameter +invitation-interval+ 300
  "Seconds after an invitation before accounts_invite sends another to the
same person (spec/auth.md 3.6).")

(defun send-invitation (account)
  "Mail ACCOUNT, a person, how to come in, in the caller's transaction, and
note when.  The mail is written in the tenant's language (spec/i18n.md 3.5).
The first invitation's mail key is invite:ID, a later one's invite:ID:TIME,
so each is sent once."
  (let ((previous (account-invited-at account)))
    (setf (account-invited-at account) (now))
    (send-mail :to (account-email account)
               :subject (tr "You have been given access to ~a" (application-title *application*))
               :text (invitation-text account)
               :key (format nil "invite:~a~@[:~a~]" (entity-id account)
                            (and previous (format-rfc3339 (account-invited-at account)))))))

(define-operation accounts-create ((:draft account)
                                   (invite :type boolean :label "Send an invitation by email"
                                           :description "Sends the person an email about how they sign in: with which email, and where."))
    (:entity account :kind :create :policy :admin :title "Create account"
             :description "Creates a person (with an email) or an agent. A person signs in
with their email at the sign-in service, such as WorkOS or Google. With invite the person is
told by email.")
  (cond ((not (account-name-p (account-name account)))
         (refuse-field "name"
                       "only lower-case letters, digits, full stops, underscores and hyphens"))
        ((and (person-p account) (null (account-email account)))
         (refuse-field "email" "a person needs an email to sign in"))
        ((and (not (person-p account)) (account-email account))
         (refuse-field "email" "an agent does not sign in and has no email"))
        ((and invite (not (person-p account)))
         (refuse-field "invite" "an agent does not sign in and gets no invitation")))
  (when (account-email account)
    (setf (account-email account) (normalize-email (account-email account))))
  (when (find-account-by-name (account-name account))
    (fail :conflict "The account name ~a is in use" (account-name account)))
  (when (and (account-email account) (find-account-by-email (account-email account)))
    (fail :conflict "The email ~a already has an account" (account-email account)))
  (setf (account-status account) "active"
        (account-created-at account) (now)
        (account-created-by account) (actor-string *actor*))
  (insert account)
  (when invite
    (send-invitation account)
    (save account))
  account)

(define-operation accounts-invite ((id :type (id account) :required t :label "Account"))
    (:entity account :kind :update :policy :admin :title "Send an invitation"
             :description "Sends an active person the invitation by email: who gave them
access, which email they sign in with, and where. It can be sent again, but not more often
than every five minutes to the same person.")
  (let ((account (fetch! 'account id)))
    (cond ((not (person-p account))
           (refuse-field "id" "an agent does not sign in and gets no invitation"))
          ((not (account-active-p account))
           (refuse-field "id" "~a is disabled; enable the account first" (account-name account))))
    (let ((previous (account-invited-at account)))
      (when (and previous (< (- (now) previous) +invitation-interval+))
        (fail :conflict "~a got an invitation less than five minutes ago"
              (account-name account))))
    (send-invitation account)
    (save account)))

(define-operation accounts-update
    ((id :type (id account) :required t :label "Account")
     (display-name :type (string :max 120) :label "Display name")
     (role :type (enum "admin" "employee" "viewer") :label "Role")
     (email :type email :label "Email")
     (status :type (enum "active" "disabled") :label "Status"))
    (:entity account :kind :update :policy :admin :title "Change account"
             :description "Changes the display name, role, email or status. A disabled
account loses its sessions and tokens at once. A new email unlinks the account's identities
at providers such as Google, so the next sign-in links the new address. The last active
administrator who is a person cannot be disabled or lose the role.")
  (let ((account (fetch! 'account id)))
    (when (and (person-p account) (account-active-p account)
               (equal (account-role account) "admin")
               (or (and role (string/= role "admin"))
                   (equal status "disabled"))
               (null (active-admin-people id)))
      (fail :conflict "~a is the last active administrator; give another person the role first"
            (account-name account)))
    (when email
      (unless (person-p account)
        (refuse-field "email" "an agent has no email"))
      (let ((other (find-account-by-email email)))
        (when (and other (not (equal (entity-id other) id)))
          (fail :conflict "The email ~a already has an account" (normalize-email email))))
      (unless (equal (account-email account) (normalize-email email))
        (unlink-identities account))
      (setf (account-email account) (normalize-email email)))
    (when (input-provided-p :display-name)
      (setf (account-display-name account) display-name))
    (when role (setf (account-role account) role))
    (when status
      (setf (account-status account) status)
      (when (equal status "disabled")
        (end-account-sessions account)
        (account-disabled *application* account)))
    (save account)))

;;; ------------------------------------------------------------------
;;; Access tokens
;;;
;;; A token acts as its account (spec/auth.md 3.2), so who may hold one is
;;; the account's own business: a person manages their own tokens, and an
;;; admin those of agents.  No one makes a token for another person.

(defun caller-account ()
  "The account *ACTOR* acts for, or NIL: the process itself, a customer, or a
claimed actor that no account has."
  (and (member (actor-role *actor*) '(:admin :employee :viewer))
       (find-account-by-name (actor-name *actor*))))

(defun admin-caller-p ()
  (eq (actor-role *actor*) :admin))

(defun own-account-p (account-id)
  (let ((own (caller-account)))
    (and own (equal (entity-id own) account-id))))

(defun own-account ()
  "The caller's account, or invalid_input when the caller has none."
  (or (caller-account)
      (fail :invalid-input "~a has no account; give account_id" (actor-string *actor*))))

(defun listed-account-id (account-id)
  "The account whose tokens tokens_list shows: ACCOUNT-ID, or for someone
not an admin, their own.  NIL means every account's."
  (cond ((admin-caller-p) account-id)
        ((or (null account-id) (own-account-p account-id)) (entity-id (own-account)))
        (t (reject :forbidden "You can only see your own access tokens"))))

(defun token-account (account-id)
  "The account a new token is for: ACCOUNT-ID, or the caller's own."
  (cond ((or (null account-id) (own-account-p account-id))
         (let ((own (own-account)))
           ;; A token that could make its own successor would outlive its
           ;; revocation; a new token for oneself takes a session.  An OAuth
           ;; client's token is held to the same rule.
           (when (and *credential* (or (string-prefix-p "tok_" *credential*)
                                       (string-prefix-p "aid_" *credential*)))
             (reject :forbidden
                     "An access token cannot make new tokens for its own account; make them in the browser"))
           own))
        ((not (admin-caller-p))
         (reject :forbidden "You can only make access tokens for your own account"))
        (t (let ((account (fetch! 'account account-id)))
             (when (person-p account)
               (refuse-field "account_id" "~a makes their own tokens" (account-name account)))
             account))))

(define-operation tokens-list ((account-id :type (id account) :label "Account"))
    (:entity access-token :kind :read :policy :viewer :title "List access tokens"
             :description "Your own access tokens; for an admin every one, or one account's:
start, description, role, times and state. Never the token itself.")
  (let ((account-id (listed-account-id account-id)))
    (jobj "items" (jarr (mapcar #'token->json
                                (select 'access-token
                                        :where (and account-id `(:= "account_id" ,account-id))
                                        :order-by '(("seq" :desc))))))))

(define-operation tokens-create
    ((account-id :type (id account) :label "Account"
                 :description "Without it: your own account. An admin can choose an agent's account.")
     (label :type (string :min 1 :max 120) :required t :label "Description"
            :description "What the token is for, such as “Claude Code on my laptop”.")
     (role :type (enum "admin" "employee" "viewer") :label "Role"
           :description "At most the account's role; without it, the account's.")
     (expires-at :type timestamp :label "Expires"))
    (:entity access-token :kind :create :policy :viewer :viewer-mutation t
             :title "Create access token"
             :description "A token for MCP, sent as Authorization: Bearer, that acts as the
account it belongs to. The answer has the token in token, and that is the only copy. A
person makes tokens for themselves, in the browser; an admin also for agents.")
  (let ((account (token-account account-id)))
    (unless (account-active-p account)
      (fail :conflict "~a is disabled" (account-name account)))
    (when (and role (string/= (lower-role role (account-role account)) role))
      (refuse-field "role" "cannot be higher than the account's role (~a)"
                    (label "account" "role" (account-role account))))
    (when (and expires-at (<= expires-at (now)))
      (refuse-field "expires_at" "must be in the future"))
    (let* ((secret (new-access-token-string))
           (token (insert (make-instance 'access-token
                                         :account-id (entity-id account) :label label
                                         :role (or role (account-role account))
                                         :prefix (subseq secret (length +token-prefix+)
                                                         (+ (length +token-prefix+) 8))
                                         :token-hash (sha256-hex secret)
                                         :expires-at expires-at :created-at (now)
                                         :created-by (actor-string *actor*)))))
      (show-once "token" secret)
      token)))

(define-operation tokens-revoke ((id :type (id access-token) :required t :label "Token"))
    (:entity access-token :kind :update :policy :viewer :viewer-mutation t
             :title "Revoke access token"
             :description "The token stops working at once. You revoke your own; an admin
any. Revoking a token already revoked changes nothing.")
  (let ((token (fetch! 'access-token id)))
    (unless (or (admin-caller-p) (own-account-p (access-token-account-id token)))
      (reject :forbidden "You can only revoke your own access tokens"))
    (unless (access-token-revoked-at token)
      (setf (access-token-revoked-at token) (now))
      (save token))
    token))

(defmethod result->json ((token access-token))
  (token->json token))

(defmethod result->json ((account account))
  (account->json account))
