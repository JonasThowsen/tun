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

(defun refuse-field (field control &rest arguments)
  (fail-fields (list (cons field (apply #'format nil control arguments)))))

;;; ------------------------------------------------------------------
;;; Accounts

(define-operation accounts-whoami ()
    (:kind :read :title "Hvem er jeg"
           :description "Aktøren kallet kjører som, kontoen den hører til (om det finnes en)
og hvordan den er bekreftet: token, session, oauth eller claimed.")
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
                                        :label "Maks antall"))
    (:entity account :kind :read :policy :admin :title "List kontoer"
             :description "Alle kontoer med rolle og status, uten nøkler.")
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
  (format nil "~a har gitt deg tilgang til ~a.~%~%~
               Logg inn med ~@[~{~a~^ eller ~} og ~]e-postadressen ~a:~%~a"
          (inviter-name) (application-title *application*)
          (remove nil (mapcar #'strategy-button-label (identity-providers)))
          (account-email account) (absolute-url "/login")))

(defparameter +invitation-interval+ 300
  "Seconds after an invitation before accounts_invite sends another to the
same person (spec/auth.md 3.6).")

(defun send-invitation (account)
  "Mail ACCOUNT, a person, how to come in, in the caller's transaction, and
note when.  The first invitation's mail key is invite:ID, a later one's
invite:ID:TIME, so each is sent once."
  (let ((previous (account-invited-at account)))
    (setf (account-invited-at account) (now))
    (send-mail :to (account-email account)
               :subject (format nil "Du har fått tilgang til ~a" (application-title *application*))
               :text (invitation-text account)
               :key (format nil "invite:~a~@[:~a~]" (entity-id account)
                            (and previous (format-rfc3339 (account-invited-at account)))))))

(define-operation accounts-create ((:draft account)
                                   (invite :type boolean :label "Send invitasjon på e-post"
                                           :description "Sender personen en e-post om hvordan
de logger inn: med hvilken e-post, og hvor."))
    (:entity account :kind :create :policy :admin :title "Opprett konto"
             :description "Oppretter en person (med e-post) eller en agent. En person logger
inn med e-posten sin hos innloggingstjenesten, som WorkOS eller Google. Med invite får
personen beskjed på e-post.")
  (cond ((not (account-name-p (account-name account)))
         (refuse-field "name" "bare små bokstaver, sifre, punktum, understrek og bindestrek"))
        ((and (person-p account) (null (account-email account)))
         (refuse-field "email" "en person trenger e-post for å logge inn"))
        ((and (not (person-p account)) (account-email account))
         (refuse-field "email" "en agent logger ikke inn og har ingen e-post"))
        ((and invite (not (person-p account)))
         (refuse-field "invite" "en agent logger ikke inn og får ingen invitasjon")))
  (when (account-email account)
    (setf (account-email account) (normalize-email (account-email account))))
  (when (find-account-by-name (account-name account))
    (fail :conflict "Kontonavnet ~a er i bruk" (account-name account)))
  (when (and (account-email account) (find-account-by-email (account-email account)))
    (fail :conflict "E-posten ~a har allerede en konto" (account-email account)))
  (setf (account-status account) "active"
        (account-created-at account) (now)
        (account-created-by account) (actor-string *actor*))
  (insert account)
  (when invite
    (send-invitation account)
    (save account))
  account)

(define-operation accounts-invite ((id :type (id account) :required t :label "Konto"))
    (:entity account :kind :update :policy :admin :title "Send invitasjon"
             :description "Sender en aktiv person invitasjonen på e-post: hvem som ga dem
tilgang, med hvilken e-post de logger inn, og hvor. Kan sendes på nytt, men ikke oftere enn
hvert femte minutt til samme person.")
  (let ((account (fetch! 'account id)))
    (cond ((not (person-p account))
           (refuse-field "id" "en agent logger ikke inn og får ingen invitasjon"))
          ((not (account-active-p account))
           (refuse-field "id" "~a er deaktivert; aktiver kontoen først" (account-name account))))
    (let ((previous (account-invited-at account)))
      (when (and previous (< (- (now) previous) +invitation-interval+))
        (fail :conflict "~a fikk en invitasjon for under fem minutter siden" (account-name account))))
    (send-invitation account)
    (save account)))

(define-operation accounts-update
    ((id :type (id account) :required t :label "Konto")
     (display-name :type (string :max 120) :label "Visningsnavn")
     (role :type (enum "admin" "employee" "viewer") :label "Rolle")
     (email :type email :label "E-post")
     (status :type (enum "active" "disabled") :label "Status"))
    (:entity account :kind :update :policy :admin :title "Endre konto"
             :description "Endrer visningsnavn, rolle, e-post eller status. En deaktivert
konto mister øktene og nøklene sine med en gang. Ny e-post kobler fra kontoens
identiteter hos tilbydere som Google, så neste innlogging kobler den nye adressen. Den
siste aktive administratoren som er en person, kan ikke deaktiveres eller miste rollen.")
  (let ((account (fetch! 'account id)))
    (when (and (person-p account) (account-active-p account)
               (equal (account-role account) "admin")
               (or (and role (string/= role "admin"))
                   (equal status "disabled"))
               (null (active-admin-people id)))
      (fail :conflict "~a er den siste aktive administratoren; gi en annen person rollen først"
            (account-name account)))
    (when email
      (unless (person-p account)
        (refuse-field "email" "en agent har ingen e-post"))
      (let ((other (find-account-by-email email)))
        (when (and other (not (equal (entity-id other) id)))
          (fail :conflict "E-posten ~a har allerede en konto" (normalize-email email))))
      (unless (equal (account-email account) (normalize-email email))
        (unlink-identities account))
      (setf (account-email account) (normalize-email email)))
    (when (input-provided-p :display-name)
      (setf (account-display-name account) display-name))
    (when role (setf (account-role account) role))
    (when status
      (setf (account-status account) status)
      (when (equal status "disabled")
        (end-account-sessions account)))
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
      (fail :invalid-input "~a har ingen konto; oppgi account_id" (actor-string *actor*))))

(defun listed-account-id (account-id)
  "The account whose tokens tokens_list shows: ACCOUNT-ID, or for someone
not an admin, their own.  NIL means every account's."
  (cond ((admin-caller-p) account-id)
        ((or (null account-id) (own-account-p account-id)) (entity-id (own-account)))
        (t (reject :forbidden "Du kan bare se dine egne tilgangsnøkler"))))

(defun token-account (account-id)
  "The account a new token is for: ACCOUNT-ID, or the caller's own."
  (cond ((or (null account-id) (own-account-p account-id))
         (let ((own (own-account)))
           ;; A token that could make its own successor would outlive its
           ;; revocation; a new token for oneself takes a session.  An OAuth
           ;; client's token is held to the same rule.
           (when (and *credential* (or (string-prefix-p "tok_" *credential*)
                                       (string-prefix-p "aid_" *credential*)))
             (reject :forbidden "En tilgangsnøkkel kan ikke lage nye nøkler for sin egen konto; ~
                                 lag dem i nettleseren"))
           own))
        ((not (admin-caller-p))
         (reject :forbidden "Du kan bare lage tilgangsnøkler for din egen konto"))
        (t (let ((account (fetch! 'account account-id)))
             (when (person-p account)
               (refuse-field "account_id" "~a lager sine egne nøkler" (account-name account)))
             account))))

(define-operation tokens-list ((account-id :type (id account) :label "Konto"))
    (:entity access-token :kind :read :policy :viewer :title "List tilgangsnøkler"
             :description "Dine egne tilgangsnøkler; for en admin alle, eventuelt én kontos:
start, beskrivelse, rolle, tider og tilstand. Aldri selve nøkkelen.")
  (let ((account-id (listed-account-id account-id)))
    (jobj "items" (jarr (mapcar #'token->json
                                (select 'access-token
                                        :where (and account-id `(:= "account_id" ,account-id))
                                        :order-by '(("seq" :desc))))))))

(define-operation tokens-create
    ((account-id :type (id account) :label "Konto"
                 :description "Uten den: din egen konto. En admin kan velge en agentkonto.")
     (label :type (string :min 1 :max 120) :required t :label "Beskrivelse"
            :description "Hva nøkkelen er til, for eksempel «Claude Code på laptopen».")
     (role :type (enum "admin" "employee" "viewer") :label "Rolle"
           :description "Høyst kontoens rolle; uten den, kontoens.")
     (expires-at :type timestamp :label "Utløper"))
    (:entity access-token :kind :create :policy :viewer :viewer-mutation t
             :title "Opprett tilgangsnøkkel"
             :description "En nøkkel for MCP som sendes som Authorization: Bearer, og som
handler som kontoen den hører til. Svaret har nøkkelen i token, og det er den eneste
kopien. En person lager nøkler for seg selv, i nettleseren; en admin også for agenter.")
  (let ((account (token-account account-id)))
    (unless (account-active-p account)
      (fail :conflict "~a er deaktivert" (account-name account)))
    (when (and role (string/= (lower-role role (account-role account)) role))
      (refuse-field "role" "kan ikke være høyere enn kontoens rolle (~a)"
                    (account-role account)))
    (when (and expires-at (<= expires-at (now)))
      (refuse-field "expires_at" "må være fram i tid"))
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

(define-operation tokens-revoke ((id :type (id access-token) :required t :label "Nøkkel"))
    (:entity access-token :kind :update :policy :viewer :viewer-mutation t
             :title "Trekk tilbake tilgangsnøkkel"
             :description "Nøkkelen slutter å virke med en gang. Du trekker tilbake dine
egne; en admin hvilken som helst. Å trekke tilbake en nøkkel som allerede er trukket
tilbake, endrer ingenting.")
  (let ((token (fetch! 'access-token id)))
    (unless (or (admin-caller-p) (own-account-p (access-token-account-id token)))
      (reject :forbidden "Du kan bare trekke tilbake dine egne tilgangsnøkler"))
    (unless (access-token-revoked-at token)
      (setf (access-token-revoked-at token) (now))
      (save token))
    token))

(defmethod result->json ((token access-token))
  (token->json token))

(defmethod result->json ((account account))
  (account->json account))
