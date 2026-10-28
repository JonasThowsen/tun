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
               (let ((provider (tun.auth:strategy-button-label strategy)))
                 (if provider (tr "Sign in with ~a" provider) (tr "Sign in")))))))

(defun login-card (error)
  "The card with a button per identity provider, with ERROR after a refused
sign-in (spec/auth.md 3.4)."
  (ui:card ()
    (apply #'ui:stack* (list :gap :lg)
           (when error
             (ui:alert (:variant :destructive :title (tr "You were not signed in")) error))
           (or (mapcar #'provider-form (tun.auth:identity-providers))
               (list `(:p ,(tr "This Tun has no way to sign in yet.")))))))

(defun no-account-yet ()
  (ui:card (:title (tr "No account yet?") :heading-level 2)
    `(:p ,(tr "An administrator gives you access with your email address. Sign in with it afterwards."))))

(defun login-page (status &key error)
  (guest-page status (tr "Sign in")
              (login-card error)
              (or (claimed-login-hint) (no-account-yet))
              :description (tr "Sign in to ~a." (application-title *web-app*))))

(defun claimed-login (raw)
  "GET /login?actor=role:name on a server with claimed identity."
  (cond ((parse-actor raw)
         ;; SameSite=Strict: a cross-site form post never carries the claim.
         (hunchentoot:set-cookie +actor-cookie+ :value (hunchentoot:url-encode raw :utf-8)
                                 :path "/" :http-only t :same-site "Strict")
         (see-other (home-path)))
        (t (respond 400 (tr "Sign in")
                    (list (ui:alert (:variant :destructive :title (tr "Invalid actor"))
                            (format nil "~a " (tr "Use"))
                            `(:code ,(tr "/login?actor=role:name"))
                            (format nil " ~a" (tr "with the role admin, employee or viewer."))))
                    :guest t :home "/login"))))

(defun handle-login (method)
  (let ((claim (hunchentoot:get-parameter "actor")))
    (cond ((not (eq method :get)) nil)
          ((and claim (claimed-identity-p *web-app*)) (claimed-login claim))
          (*actor* (see-other (home-path)))
          (t (login-page 200)))))

(defun handle-logout (method)
  (cond ((eq method :post)
         ;; The device stops getting the person's notifications (spec/push.md 3).
         (when (and (stringp *credential*) (string-prefix-p "ses_" *credential*))
           (with-transaction (:write)
             (tun.push:forget-session-subscriptions *credential*)))
         (tun.auth:log-out (hunchentoot:cookie-in tun.auth:+session-cookie+))
         (clear-login-cookies)
         (see-other "/login"))
        (t (respond 200 (tr "Sign out")
                    (list `(:form (:@ :method "post" :action "/logout")
                                  ,(ui:button (:type "submit" :icon :log-out)
                                     (tr "Sign out"))))))))

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
                          ;; The server's log is for developers: source text.
                          (with-language (:source) (tun.auth:sign-in-refused-message refusal)))))
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
  (let ((fields (mapcar (lambda (field)
                          (cons (error-path-name (car field)) (render-text (cdr field))))
                        (operation-error-fields condition))))
    (values fields (unless fields (operation-error-message condition)))))

(defun form-errors (form-id errors message labels)
  "The error summary at the top of the setup form: ERRORS link to their
fields (LABELS maps a name to its label), MESSAGE stands alone."
  (when (or errors message)
    (ui:error-summary* (list :title (if errors (tr "There is a problem") (tr "That did not work"))
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
  (respond 404 (tr "Not found")
           (list (ui:alert (:variant :warning :title (tr "The link does not work"))
                   (tr "The link is unknown, used or expired. Ask an administrator for a new one.")))
           :guest t :home "/login"))

(defun setup-labels ()
  "The labels of the setup form's fields, by their names."
  (list (cons "name" (tr "Name")) (cons "display_name" (tr "Display name"))))

(defun setup-fields (form-id errors name display-name)
  "The fields of the first administrator's account, with their ERRORS: the
email comes from the provider."
  (flet ((id (field) (control-id form-id field))
         (error-of (field) (field-error-message field errors)))
    (list (ui:text-input (:label (tr "Name") :name "name" :value name
                                 :required t :autocomplete "username" :width 20
                                 :id (id "name") :error (error-of "name")
                                 :hint (tr "Lower-case letters, such as alex.")))
          (ui:text-input (:label (tr "Display name") :name "display_name"
                                 :value display-name :optional t
                                 :id (id "display_name") :error (error-of "display_name")
                                 :hint (tr "How others see you, such as Alex Morgan."))))))

(defun setup-actions ()
  "The setup form's buttons: one per identity provider."
  (apply #'ui:form-actions* nil
         (mapcar (lambda (strategy)
                   (ui:button (:type "submit" :name "provider"
                                     :value (tun.auth:strategy-name strategy) :icon :log-in)
                     (let ((provider (tun.auth:strategy-button-label strategy)))
                       (if provider (tr "Continue with ~a" provider) (tr "Continue")))))
                 (tun.auth:identity-providers))))

(defun setup-page (status code &key errors message name display-name)
  (private-page)
  (let ((form-id "setup"))
    (guest-page
     status (tr "Create the first administrator")
     (ui:card ()
       `(:form (:@ :method "post" :action ,(format nil "/setup/~a" code) :novalidate t)
               ,(ui:stack (:gap :lg)
                  (form-errors form-id errors message (setup-labels))
                  (setup-fields form-id errors name display-name)
                  (setup-actions))))
     (ui:card (:title (tr "What happens now?") :heading-level 2)
       (ui:stack (:gap :sm)
         `(:p ,(tr "The account you make here can create the other accounts and the access tokens."))
         `(:p ,(tr "The link works only until the first administrator is made."))))
     :description (tr "Tun has no administrator yet."))))

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
  "How ACCOUNT, a person, logs in: the providers linked to it; «Waiting»
before the first time."
  (let ((ways (map 'list (lambda (name)
                           (let ((strategy (tun.auth:find-identity-provider name)))
                             (if strategy (tun.auth:strategy-label strategy) name)))
                   (jget account "sign_in" #()))))
    (cond (ways (format nil "~{~a~^, ~}" ways))
          ((equal (jget account "kind") "person") (tr "Waiting"))
          (t "–"))))

(defun account-select (account field label values)
  "A select of ACCOUNT's FIELD among VALUES, labelled for screen readers only."
  (ui:select (:label (tr "~a for ~a" label (jget account "name")) :label-hidden t
                     :name field :selected (jget account field)
                     :options (mapcar (lambda (value) (list value (humanize value))) values))))

(defun account-controls (account)
  "The form that changes ACCOUNT's role and status."
  (let ((action (format nil "/access/accounts/~a/update" (jget account "id"))))
    `(:form (:@ :method "post" :action ,action)
            ,(hidden "request_key" (new-id "web"))
            ,(ui:cluster (:align :end)
               (account-select account "role" (tr "Role") '("admin" "employee" "viewer"))
               (account-select account "status" (tr "Status") '("active" "disabled"))
               (ui:button (:type "submit" :variant :outline :size :sm) (tr "Save"))))))

(defun accounts-table (accounts)
  (ui:table (:columns (list (tr "Name") (tr "Display name") (tr "Type") (tr "Email")
                            (tr "Sign-in") (tr "Role and status"))
                      :rows (mapcar (lambda (account)
                                      (list (jget account "name")
                                            (display-value (jget account "display_name"))
                                            (humanize (jget account "kind"))
                                            (display-value (jget account "email"))
                                            (sign-in-state account)
                                            (account-controls account)))
                                    accounts))))

(defun ways-to-sign-in ()
  "How people log in to this tenant, in words: «WorkOS», «Google or WorkOS», …"
  (tr "~{~a~^ or ~}" (mapcar #'tun.auth:strategy-label (tun.auth:identity-providers))))

(defun items (tool &rest keys-and-values)
  (coerce (jget (web-call tool (apply #'jobj keys-and-values)) "items" #()) 'list))

(defun token-table (tokens &key accounts)
  "TOKENS as a table; with ACCOUNTS, which account each acts as."
  (ui:table* (list :columns (append (list (tr "Description") (tr "Token"))
                                    (when accounts (list (tr "Account")))
                                    (list (tr "Role") (tr "State") (tr "Last used")
                                          (tr "Expires") (tr "Action")))
                   :empty (tr "No tokens yet.")
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
                                                           (tr "Revoke"))
                                              "–"))))
                                 tokens))))

(defun timestamp-or-dash (value)
  (if (stringp value) (timestamp-text value) "–"))

(defun form-failure (failed form)
  "The refused submission FAILED, (FORM ERROR-JSON VALUES), when it came from
FORM; else NIL."
  (and failed (equal (first failed) form) failed))

(defun own-tokens-text ()
  "What /access says about a person's own tokens."
  (tr "An agent or a script, such as Claude Code, calls MCP with a token in Authorization: Bearer and may do the same as you, never more. The token is shown only when it is made."))

(defun own-tokens-section (account failed)
  "The caller's own tokens and the form for a new one: every person's part of
/access (spec/auth.md 3.2)."
  (if (json-null-p account)
      (list (section (tr "My tokens")
              `(:p ,(tr "~a has no account, and so no tokens." (actor-string *actor*)))))
      (let ((mine (form-failure failed "tokens_create")))
        (list (when (tun.auth:oauth-strategy *web-app*)
                (ui:section (:title (tr "Connect without a token")
                             :description (tr "Claude Code and other MCP clients that can do OAuth sign in as you through WorkOS, without a token."))
                  (ui:code-block (:title (tr "For Claude Code")
                                  :copy-label (tr "Copy the command"))
                                 (format nil "claude mcp add --transport http ~a ~a"
                                         (server-name) (site-url "/mcp")))))
              (ui:section (:title (tr "My tokens") :description (own-tokens-text))
                (token-table (items "tokens_list" "account_id" (jget account "id"))))
              (operation-form (find-operation-by-tool "tokens_create") "/access/tokens"
                              :title (tr "New token for me") :submit (tr "Create token")
                              :omit '("account_id")
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
    (list (ui:section (:title (tr "Accounts")
                       :description (tr "People sign in with ~a, agents with tokens."
                                        (ways-to-sign-in)))
            (accounts-table accounts))
          (operation-form (find-operation-by-tool "accounts_create") "/access/accounts"
                          :title (tr "New account") :submit (tr "Create account")
                          :error-json (second account-form) :values (third account-form))
          (section (tr "All access tokens") (token-table (items "tokens_list") :accounts t))
          (if agents
              (operation-form (find-operation-by-tool "tokens_create") "/access/tokens"
                              :title (tr "New token for an agent") :submit (tr "Create token")
                              :choices (list (cons "account_id" agents))
                              :error-json (second agent-form) :values (third agent-form))
              (ui:alert (:variant :info :title (tr "No agents yet"))
                (tr "An agent gets tokens when it has an account of the type agent."))))))

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
           (ui:alert (:variant :warning :title (tr "Copy it now: it will not be shown again.")))
           body)))

(defun token-shown-before ()
  "What a new token's form sent again is told: the token is not shown twice."
  (ui:alert (:variant :info)
    (tr "The token was made earlier with the same form; it is not shown again.")))

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
        (shown-once (tr "New access token")
                    (ui:code-block (:title (tr "Access token") :wrap t
                                    :copy-label (tr "Copy the token"))
                                   token)
                    (ui:code-block (:title (tr "For Claude Code")
                                    :copy-label (tr "Copy the command"))
                                   (claude-command token)))
        (token-shown-before))))

(defun provider-notice (json)
  (ui:flash () (tr "The account is created. ~a signs in with ~a with the email ~a."
                   (jget json "name") (ways-to-sign-in) (jget json "email"))))

(defun invitation-notice (json)
  (ui:flash () (tr "The account is created, and ~a has been sent an invitation at ~a."
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
                     (constant-notice (tr "The account is saved."))))
              ((and (equal collection "tokens") (null id))
               (call "tokens_create" (form "tokens_create") #'token-notice
                     (if (posted "account_id" params) "tokens_create:agent" "tokens_create")))
              ((and (equal collection "tokens") (equal verb "revoke"))
               (call "tokens_revoke" (jobj "id" id)
                     (constant-notice (tr "The token is revoked."))))
              (t (values nil
                         (list nil (jobj "error" (jobj "code" "not_found"
                                                       "message" (tr "Unknown action"))))
                         :not-found)))))))

(defun staff-access-page (method parts form query)
  (declare (ignore form query))
  (private-page)
  (if (eq method :post)
      (multiple-value-bind (notice failed code) (access-action parts)
        (values (if code (error-status code) 200)
                (tr "Access") (access-body :notice notice :failed failed)))
      (values 200 (tr "Access") (access-body))))

(register-staff-page "access" #'staff-access-page :policy :viewer :title "Access"
                     :icon :shield-check :group :system)
