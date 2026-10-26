;;;; web/access.lisp -- logging in and out through the identity providers,
;;;; the first administrator, and /access: each person's own access tokens,
;;;; and for an admin accounts and agents' tokens (spec/auth.md).
;;;;
;;;; The pages call TUN.AUTH for credentials and the accounts_* and tokens_*
;;;; tools for everything else, so an admin in the browser and an agent on
;;;; MCP change accounts through the same audited operations.

(in-package #:tun.web)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Cookies and headers

(defun set-session-cookie (value)
  (hunchentoot:set-cookie tun.auth:+session-cookie+
                          :value value :path "/" :http-only t :same-site "Lax"
                          :secure (tun.http:https-request-p) :max-age tun.auth:+session-lifetime+))

(defun clear-login-cookies ()
  (hunchentoot:set-cookie tun.auth:+session-cookie+
                          :value "" :path "/" :max-age 0 :http-only t :same-site "Lax"
                          :secure (tun.http:https-request-p))
  (when (hunchentoot:cookie-in +actor-cookie+)
    (hunchentoot:set-cookie +actor-cookie+ :value "" :path "/" :max-age 0)))

(defun private-page ()
  "Headers for a page whose URL or form carries a secret."
  (setf (hunchentoot:header-out "Referrer-Policy") "no-referrer"
        (hunchentoot:header-out "Cache-Control") "no-store"))

(defun note-refusal (message)
  "Record this web request as rejected: introspect_recent shows refused
sign-ins, which are not audited (spec/auth.md 3.5)."
  (when *request-record*
    (set-request-outcome *request-record* "rejected" :code :unauthenticated :message message)))

(defun guest-page (status title form-card aside &key description)
  "A narrow page for someone not logged in: FORM-CARD and below it the card
ASIDE that explains it."
  (respond status title (list form-card aside)
           :description description :guest t :home "/login" :width :narrow))

;;; ------------------------------------------------------------------
;;; Logging in and out

(defun provider-form (strategy)
  "A button that signs in with STRATEGY's provider (spec/auth.md 3.5)."
  `(:form (:@ :method "post" :action ,(format nil "/auth/~a" (tun.auth:strategy-name strategy)))
          ,(ui:form-actions ()
             (ui:button (:type "submit" :icon :log-in)
               (format nil "Logg inn~@[ med ~a~]" (tun.auth:strategy-button-label strategy))))))

(defun login-card (error)
  "The card with a button per identity provider, with ERROR after a refused
sign-in (spec/auth.md 3.4)."
  (ui:card ()
    (apply #'ui:stack* (list :gap :lg)
           (when error
             (ui:alert (:variant :destructive :title "Du ble ikke logget inn") error))
           (or (mapcar #'provider-form (tun.auth:identity-providers))
               (list '(:p "Denne Tun-en har ingen måte å logge inn på ennå."))))))

(defun no-account-yet ()
  (ui:card (:title "Ingen konto ennå?" :heading-level 2)
    '(:p "En administrator gir deg tilgang med e-postadressen din. Logg inn med den
etterpå.")))

(defun login-page (status &key error)
  (guest-page status "Logg inn"
              (login-card error)
              (or (claimed-login-hint) (no-account-yet))
              :description (format nil "Logg inn i ~a." (application-title *web-app*))))

(defun claimed-login (raw)
  "GET /login?actor=role:name on a server with claimed identity."
  (cond ((parse-actor raw)
         ;; SameSite=Strict: a cross-site form post never carries the claim.
         (hunchentoot:set-cookie +actor-cookie+ :value (hunchentoot:url-encode raw :utf-8)
                                 :path "/" :http-only t :same-site "Strict")
         (see-other (home-path)))
        (t (respond 400 "Logg inn"
                    (list (ui:alert (:variant :destructive :title "Ugyldig aktør")
                            "Bruk " '(:code "/login?actor=rolle:navn")
                            " med rolle admin, employee eller viewer."))
                    :guest t :home "/login"))))

(defun handle-login (method)
  (let ((claim (hunchentoot:get-parameter "actor")))
    (cond ((not (eq method :get)) nil)
          ((and claim (claimed-identity-p *web-app*)) (claimed-login claim))
          (*actor* (see-other (home-path)))
          (t (login-page 200)))))

(defun handle-logout (method)
  (cond ((eq method :post)
         (tun.auth:log-out (hunchentoot:cookie-in tun.auth:+session-cookie+))
         (clear-login-cookies)
         (see-other "/login"))
        (t (respond 200 "Logg ut"
                    (list `(:form (:@ :method "post" :action "/logout")
                                  ,(ui:button (:type "submit" :icon :log-out) "Logg ut")))))))

;;; ------------------------------------------------------------------
;;; Signing in with an identity provider (spec/auth.md 3.5)

(defun callback-url (strategy)
  "Where STRATEGY's provider sends the browser back: what the provider must
have registered."
  (site-url (format nil "/auth/~a/callback" (tun.auth:strategy-name strategy))))

(defun set-sign-in-cookie (value max-age)
  (hunchentoot:set-cookie tun.auth:+sign-in-cookie+
                          :value value :path "/auth/" :http-only t :same-site "Lax"
                          :secure (tun.http:https-request-p) :max-age max-age))

(defun start-provider-sign-in (strategy &key setup-code name display-name)
  "Send the browser to STRATEGY's provider, with a new attempt."
  (multiple-value-bind (state url)
      (tun.auth:start-sign-in strategy (callback-url strategy)
                              :setup-code setup-code :name name :display-name display-name)
    (set-sign-in-cookie state tun.auth:+attempt-lifetime+)
    (see-other url)))

(defun finish-provider-sign-in (strategy)
  "The provider sent the browser back: log in, or say why not."
  (private-page)
  (let ((cookie (hunchentoot:cookie-in tun.auth:+sign-in-cookie+)))
    (set-sign-in-cookie "" 0)
    (handler-case
        (multiple-value-bind (session account purpose)
            (tun.auth:finish-sign-in strategy
                                     :state (hunchentoot:get-parameter "state")
                                     :code (hunchentoot:get-parameter "code")
                                     :error (hunchentoot:get-parameter "error")
                                     :cookie cookie :redirect-uri (callback-url strategy))
          (declare (ignore account))
          (set-session-cookie session)
          (see-other (if (eq purpose :setup) "/access" (home-path))))
      (tun.auth:sign-in-refused (refusal)
        (let ((detail (or (tun.auth:sign-in-refused-detail refusal)
                          (tun.auth:sign-in-refused-message refusal))))
          (note-refusal (format nil "sign-in with ~a: ~a"
                                (tun.auth:strategy-name strategy) detail))
          (format *error-output* "~&;; tun auth: sign-in with ~a refused: ~a~%"
                  (tun.auth:strategy-name strategy) detail))
        (if (= (tun.auth:sign-in-refused-status refusal) 404)
            (not-found-page)
            (login-page (tun.auth:sign-in-refused-status refusal)
                        :error (tun.auth:sign-in-refused-message refusal)))))))

(defun handle-sign-in (method name step)
  "/auth/NAME and /auth/NAME/callback: NIL (404) for anything else."
  (let ((strategy (tun.auth:find-identity-provider name)))
    (cond ((null strategy) nil)
          ((and (null step) (eq method :post)) (start-provider-sign-in strategy))
          ((and (equal step "callback") (eq method :get)) (finish-provider-sign-in strategy))
          (t nil))))

;;; ------------------------------------------------------------------
;;; The first administrator (spec/auth.md 4)

(defun refusal-errors (condition)
  "What CONDITION, an operation-error refusing the first admin's names, says
about the form: values its field errors ((name . message) ...) and a message
for the rest."
  (let ((fields (mapcar (lambda (field) (cons (error-path-name (car field)) (cdr field)))
                        (operation-error-fields condition))))
    (values fields (unless fields (operation-error-message condition)))))

(defun form-errors (form-id errors message labels)
  "The error summary at the top of the setup form: ERRORS link to their
fields (LABELS maps a name to its label), MESSAGE stands alone."
  (when (or errors message)
    (ui:error-summary* (list :title (if errors
                                        "For å gå videre må du rette opp følgende feil:"
                                        "Det gikk ikke")
                             :errors (mapcar (lambda (entry)
                                               (list (control-id form-id (car entry))
                                                     (field-error-sentence
                                                      (or (cdr (assoc (car entry) labels
                                                                      :test #'string=))
                                                          (car entry))
                                                      (cdr entry))))
                                             errors))
                       (when message `(:p ,message)))))

(defun not-found-page ()
  (respond 404 "Finnes ikke"
           (list (ui:alert (:variant :warning :title "Lenken virker ikke")
                   "Lenken er ukjent, brukt eller utløpt. Be en administrator om en ny."))
           :guest t :home "/login"))

(defparameter +setup-labels+
  '(("name" . "Navn") ("display_name" . "Visningsnavn")))

(defun setup-fields (form-id errors name display-name)
  "The fields of the first administrator's account, with their ERRORS: the
email comes from the provider."
  (flet ((id (field) (control-id form-id field))
         (error-of (field) (field-error-message field errors)))
    (list (ui:text-input (:label "Navn" :name "name" :value name
                                 :required t :autocomplete "username" :width 20
                                 :id (id "name") :error (error-of "name")
                                 :hint "Små bokstaver, for eksempel kari."))
          (ui:text-input (:label "Visningsnavn" :name "display_name"
                                 :value display-name :optional t
                                 :id (id "display_name") :error (error-of "display_name")
                                 :hint "Slik andre ser deg, for eksempel Kari Nordmann.")))))

(defun setup-actions ()
  "The setup form's buttons: one per identity provider."
  (apply #'ui:form-actions* nil
         (mapcar (lambda (strategy)
                   (ui:button (:type "submit" :name "provider"
                                     :value (tun.auth:strategy-name strategy) :icon :log-in)
                     (format nil "Fortsett~@[ med ~a~]"
                             (tun.auth:strategy-button-label strategy))))
                 (tun.auth:identity-providers))))

(defun setup-page (status code &key errors message name display-name)
  (private-page)
  (let ((form-id "setup"))
    (guest-page
     status "Opprett den første administratoren"
     (ui:card ()
       `(:form (:@ :method "post" :action ,(format nil "/setup/~a" code) :novalidate t)
               ,(ui:stack (:gap :lg)
                  (form-errors form-id errors message +setup-labels+)
                  (setup-fields form-id errors name display-name)
                  (setup-actions))))
     (ui:card (:title "Hva skjer nå?" :heading-level 2)
       (ui:stack (:gap :sm)
         '(:p "Kontoen du lager her, kan opprette de andre kontoene og
tilgangsnøklene.")
         '(:p "Lenken virker bare til den første administratoren er laget.")))
     :description "Tun har ingen administrator ennå.")))

(defun handle-setup (method code)
  (cond ((not (tun.auth:setup-code-valid-p code)) (not-found-page))
        ((eq method :get) (setup-page 200 code))
        (t
         (let ((name (hunchentoot:post-parameter "name"))
               (display-name (hunchentoot:post-parameter "display_name"))
               (provider (let ((name (hunchentoot:post-parameter "provider")))
                           (and name (tun.auth:find-identity-provider name)))))
           (when provider
             (handler-case
                 (let ((display-name (and (plusp (length display-name)) display-name)))
                   (tun.auth:check-account-names name display-name)
                   (start-provider-sign-in provider :setup-code code :name name
                                           :display-name display-name))
               (operation-error (e)
                 (multiple-value-bind (errors message) (refusal-errors e)
                   (setup-page 422 code :errors errors :message message :name name
                               :display-name display-name)))))))))

;;; ------------------------------------------------------------------
;;; /access: one's own access tokens; accounts and agents' tokens for admins

(defun site-url (path)
  "PATH as an absolute URL of this server: at its public URL when it has one
(spec/deploy.md 1), else as the browser reached it."
  (let ((base (application-public-url *web-app*)))
    (if base
        (concatenate 'string base path)
        (format nil "~:[http~;https~]://~a~a" (tun.http:https-request-p)
                (hunchentoot:header-in* :host) path))))

(defun hidden (name value)
  `(:input (:@ :type "hidden" :name ,name :value ,value)))

(defun button-form (action label &key (variant :outline))
  "A one-button form posting to ACTION, with a request key of its own."
  `(:form (:@ :method "post" :action ,action)
          ,(hidden "request_key" (new-id "web"))
          ,(ui:button (:type "submit" :variant variant :size :sm) label)))

(defun sign-in-state (account)
  "How ACCOUNT, a person, logs in: the providers linked to it; Venter before
the first time."
  (let ((ways (map 'list (lambda (name)
                           (let ((strategy (tun.auth:find-identity-provider name)))
                             (if strategy (tun.auth:strategy-label strategy) name)))
                   (jget account "sign_in" #()))))
    (cond (ways (format nil "~{~a~^, ~}" ways))
          ((equal (jget account "kind") "person") "Venter")
          (t "–"))))

(defun account-select (account field label values)
  "A select of ACCOUNT's FIELD among VALUES, labelled for screen readers only."
  (ui:select (:label (format nil "~a for ~a" label (jget account "name")) :label-hidden t
                     :name field :selected (jget account field)
                     :options (mapcar (lambda (value) (list value (humanize value))) values))))

(defun account-controls (account)
  "The form that changes ACCOUNT's role and status."
  (let ((action (format nil "/access/accounts/~a/update" (jget account "id"))))
    `(:form (:@ :method "post" :action ,action)
            ,(hidden "request_key" (new-id "web"))
            ,(ui:cluster (:align :end)
               (account-select account "role" "Rolle" '("admin" "employee" "viewer"))
               (account-select account "status" "Status" '("active" "disabled"))
               (ui:button (:type "submit" :variant :outline :size :sm) "Lagre")))))

(defun accounts-table (accounts)
  (ui:table (:columns '("Navn" "Visningsnavn" "Type" "E-post" "Innlogging" "Rolle og status")
                      :rows (mapcar (lambda (account)
                                      (list (jget account "name")
                                            (display-value (jget account "display_name"))
                                            (humanize (jget account "kind"))
                                            (display-value (jget account "email"))
                                            (sign-in-state account)
                                            (account-controls account)))
                                    accounts))))

(defun ways-to-sign-in ()
  "How people log in to this tenant, in words: «WorkOS», «Google», …"
  (format nil "~{~a~^ eller ~}" (mapcar #'tun.auth:strategy-label (tun.auth:identity-providers))))

(defun items (tool &rest keys-and-values)
  (coerce (jget (web-call tool (apply #'jobj keys-and-values)) "items" #()) 'list))

(defun token-table (tokens &key accounts)
  "TOKENS as a table; with ACCOUNTS, which account each acts as."
  (ui:table* (list :columns (append '("Beskrivelse" "Nøkkel")
                                    (when accounts '("Konto"))
                                    '("Rolle" "Tilstand" "Sist brukt" "Utløper" "Handling"))
                   :empty "Ingen nøkler ennå."
                   :rows (mapcar (lambda (token)
                                   (append
                                    (list (jget token "label")
                                          `(:code "tun_" ,(jget token "prefix") "…"))
                                    (when accounts
                                      (list (display-value (jget token "account_name"))))
                                    (list (humanize (jget token "role"))
                                          (status-badge (jget token "state"))
                                          (timestamp-or-dash (jget token "last_used_at"))
                                          (timestamp-or-dash (jget token "expires_at"))
                                          (if (equal (jget token "state") "active")
                                              (button-form (format nil "/access/tokens/~a/revoke"
                                                                   (jget token "id"))
                                                           "Trekk tilbake")
                                              "–"))))
                                 tokens))))

(defun timestamp-or-dash (value)
  (if (stringp value) (timestamp-text value) "–"))

(defun form-failure (failed form)
  "The refused submission FAILED, (FORM ERROR-JSON VALUES), when it came from
FORM; else NIL."
  (and failed (equal (first failed) form) failed))

(defparameter +own-tokens-text+
  "En agent eller et skript, som Claude Code, kaller MCP med en nøkkel i Authorization: Bearer
og får gjøre det samme som du, aldri mer. Nøkkelen vises bare når den lages."
  "What /access says about a person's own tokens.")

(defun own-tokens-section (account failed)
  "The caller's own tokens and the form for a new one: every person's part of
/access (spec/auth.md 3.2)."
  (if (json-null-p account)
      (list (section "Mine nøkler"
              `(:p ,(format nil "~a har ingen konto, og så ingen nøkler."
                            (actor-string *actor*)))))
      (let ((mine (form-failure failed "tokens_create")))
        (list (when (tun.auth:oauth-strategy *web-app*)
                (ui:section (:title "Koble til uten nøkkel"
                                    :description "Claude Code og andre MCP-klienter som kan OAuth, logger
inn som deg gjennom WorkOS, uten nøkkel.")
                  (ui:code-block (:title "For Claude Code" :copy-label "Kopier kommandoen")
                                 (format nil "claude mcp add --transport http ~a ~a"
                                         (server-name) (site-url "/mcp")))))
              (ui:section (:title "Mine nøkler" :description +own-tokens-text+)
                (token-table (items "tokens_list" "account_id" (jget account "id"))))
              (operation-form (find-operation-by-tool "tokens_create") "/access/tokens"
                              :title "Ny nøkkel for meg" :submit "Lag nøkkel" :omit '("account_id")
                              :error-json (second mine) :values (third mine))))))

(defun agent-choices (accounts)
  "(id . label) for the active agents among ACCOUNTS."
  (loop for account in accounts
        when (and (equal (jget account "kind") "agent") (equal (jget account "status") "active"))
        collect (cons (jget account "id")
                      (format nil "~a (~a)" (jget account "name") (jget account "id")))))

(defun admin-sections (accounts failed)
  "Accounts, every token, and tokens for agents: what an admin also sees."
  (let ((agents (agent-choices accounts))
        (account-form (form-failure failed "accounts_create"))
        (agent-form (form-failure failed "tokens_create:agent")))
    (list (ui:section (:title "Kontoer"
                              :description (format nil "Personer logger inn med ~a, agenter med ~
                                                        nøkler." (ways-to-sign-in)))
            (accounts-table accounts))
          (operation-form (find-operation-by-tool "accounts_create") "/access/accounts"
                          :title "Ny konto" :submit "Opprett konto"
                          :error-json (second account-form) :values (third account-form))
          (section "Alle tilgangsnøkler" (token-table (items "tokens_list") :accounts t))
          (if agents
              (operation-form (find-operation-by-tool "tokens_create") "/access/tokens"
                              :title "Ny nøkkel for en agent" :submit "Lag nøkkel"
                              :choices (list (cons "account_id" agents))
                              :error-json (second agent-form) :values (third agent-form))
              (ui:alert (:variant :info :title "Ingen agenter ennå")
                "En agent får nøkler når den har en konto av typen agent.")))))

(defun access-body (&key notice failed)
  "The /access page: NOTICE after an action, and FAILED, (FORM ERROR-JSON
VALUES), after a refused one: a form's refusal is shown in that form, any
other at the top."
  (let ((account (jget (web-call "accounts_whoami" (jobj)) "account")))
    (append (list (when (and failed (null (first failed))) (error-alert (second failed)))
                  notice)
            (own-tokens-section account failed)
            (when (eq (actor-role *actor*) :admin)
              (admin-sections (items "accounts_list") failed)))))

(defun shown-once (title &rest body)
  "A secret shown once, with the warning that it will not be shown again."
  (ui:card (:title title :heading-level 2 :attributes (list :role "status"))
    (apply #'ui:stack* (list :gap :md)
           (ui:alert (:variant :warning :title "Kopier den nå: den vises ikke igjen."))
           body)))

(defun shown-before (what)
  (ui:alert (:variant :info)
    (format nil "~a ble laget tidligere med det samme skjemaet; den vises ikke ~
                 igjen." what)))

(defun server-name ()
  "This tenant's name for Claude Code's list of MCP servers: its application
name in lower case, with a hyphen for anything a shell would split on."
  (string-trim "-" (substitute-if-not #\- #'alphanumericp
                                      (string-downcase (application-name *web-app*)))))

(defun claude-command (token)
  "The command that connects Claude Code to this server's MCP with TOKEN."
  (format nil "claude mcp add --transport http ~a ~a \\~%  --header \"Authorization: Bearer ~a\""
          (server-name) (site-url "/mcp") token))

(defun token-notice (json)
  (let ((token (jget json "token")))
    (if (stringp token)
        (shown-once "Ny tilgangsnøkkel"
                    (ui:code-block (:title "Tilgangsnøkkel" :wrap t
                                           :copy-label "Kopier nøkkelen")
                                   token)
                    (ui:code-block (:title "For Claude Code" :copy-label "Kopier kommandoen")
                                   (claude-command token)))
        (shown-before "Nøkkelen"))))

(defun provider-notice (json)
  (ui:flash () (format nil "Kontoen er opprettet. ~a logger inn med ~a med e-posten ~a."
                       (jget json "name") (ways-to-sign-in) (jget json "email"))))

(defun invitation-notice (json)
  (ui:flash () (format nil "Kontoen er opprettet, og ~a har fått en invitasjon på ~a."
                       (jget json "name") (jget json "email"))))

(defun constant-notice (text)
  (constantly (ui:flash () text)))

(defun access-action (parts)
  "Carry out the POST to /access/PARTS.  Values the notice to show, or else
NIL, the refusal (FORM ERROR-JSON VALUES) where FORM names the form it came
from (NIL for a button), and the error's code."
  (let ((params (hunchentoot:post-parameters*)))
    (flet ((call (tool arguments notice &optional form)
             (setf (gethash "request_key" arguments)
                   (or (posted "request_key" params) (new-id "web")))
             (multiple-value-bind (json code) (web-call tool arguments)
               (if code
                   (values nil (list form json params) code)
                   (values (funcall notice json) nil nil))))
           (form (tool) (form-arguments (find-operation-by-tool tool) params)))
      (destructuring-bind (&optional collection id verb) parts
        (cond ((and (equal collection "accounts") (null id))
               (let ((arguments (form "accounts_create")))
                 (call "accounts_create" arguments
                       (lambda (json)
                         (cond ((not (equal (jget json "kind") "person")) nil)
                               ((eq t (jget arguments "invite")) (invitation-notice json))
                               (t (provider-notice json))))
                       "accounts_create")))
              ((and (equal collection "accounts") (equal verb "update"))
               (call "accounts_update"
                     (jobj "id" id "role" (posted "role" params) "status" (posted "status" params))
                     (constant-notice "Kontoen er lagret.")))
              ((and (equal collection "tokens") (null id))
               (call "tokens_create" (form "tokens_create") #'token-notice
                     (if (posted "account_id" params) "tokens_create:agent" "tokens_create")))
              ((and (equal collection "tokens") (equal verb "revoke"))
               (call "tokens_revoke" (jobj "id" id)
                     (constant-notice "Nøkkelen er trukket tilbake.")))
              (t (values nil
                         (list nil (jobj "error" (jobj "code" "not_found"
                                                       "message" "Ukjent handling")))
                         :not-found)))))))

(defun staff-access-page (method parts form query)
  (declare (ignore form query))
  (private-page)
  (if (eq method :post)
      (multiple-value-bind (notice failed code) (access-action parts)
        (values (if code (error-status code) 200)
                "Tilgang" (access-body :notice notice :failed failed)))
      (values 200 "Tilgang" (access-body))))

(register-staff-page "access" #'staff-access-page :policy :viewer :title "Tilgang"
                     :icon :shield-check :group :system)
