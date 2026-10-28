;;;; tests/auth-tests.lisp -- accounts, access tokens, sessions and setup over
;;;; real HTTP (spec/auth.md 9).  People sign in through the fake provider of
;;;; fake-provider.lisp.

(in-package #:tun.tests)

(def-suite auth :in core)
(in-suite auth)

;;; ------------------------------------------------------------------
;;; Helpers

(defun mcp-request (port body &key token headers)
  "POST BODY to /mcp, with TOKEN as a bearer token.  Values the status, the
parsed body (NIL when empty) and the headers."
  (multiple-value-bind (bytes status response-headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d/mcp" port)
                           :method :post :content-type "application/json"
                           :content (sb-ext:string-to-octets body :external-format :utf-8)
                           :additional-headers
                           (append (and token (list (cons "Authorization"
                                                          (format nil "Bearer ~a" token))))
                                   headers)
                           :force-binary t)
    (let ((text (if bytes (sb-ext:octets-to-string bytes :external-format :utf-8) "")))
      (values status (and (plusp (length text)) (parse-json text)) response-headers))))

(defun tools-call-body (tool arguments)
  (to-json-string (jobj "jsonrpc" "2.0" "id" 1 "method" "tools/call"
                        "params" (jobj "name" tool "arguments" arguments))))

(defun token-call (port token tool arguments &key headers)
  "tools/call TOOL over HTTP with TOKEN.  Values the tool's JSON, isError and the status."
  (multiple-value-bind (status json)
      (mcp-request port (tools-call-body tool arguments) :token token :headers headers)
    (let ((result (and json (jget json "result"))))
      (values (and result (parse-json (jget (aref (jget result "content") 0) "text")))
              (and result (jget result "isError"))
              status))))

(defun whoami (port token)
  "The actor TOKEN calls as, or NIL when it is refused."
  (let ((json (token-call port token "accounts_whoami" (jobj))))
    (and json (jget json "actor"))))

(defun token-status (port token)
  "The HTTP status of a call with TOKEN."
  (nth-value 2 (token-call port token "accounts_whoami" (jobj))))

(defun admin-items (tool &rest keys-and-values)
  "The items TOOL lists, called in-process as an admin."
  (coerce (jget (apply #'call-ok tool "admin:root" keys-and-values) "items") 'list))

(defun refusal (tool &rest keys-and-values)
  "The error code of TOOL called in-process as an admin, or NIL when it succeeds."
  (nth-value 1 (apply #'call tool "admin:root" keys-and-values)))

(defun make-account (name kind role &optional email)
  "Create an account in-process, as the code of an admin; its JSON."
  (apply #'call-ok "accounts_create" "admin:root" "name" name "kind" kind "role" role
         (and email (list "email" email))))

(defun make-token (account &rest keys-and-values)
  "A new token for ACCOUNT (its JSON); the token string."
  (jget (apply #'call-ok "tokens_create" "admin:root" "account_id" (jget account "id")
               "label" "test" keys-and-values)
        "token"))

(defun update-account (account &rest keys-and-values)
  (apply #'call-ok "accounts_update" "admin:root" "id" (jget account "id") keys-and-values))

(defun advance-clock (seconds)
  (let ((clock (application-clock *app*)))
    (set-test-clock clock (+ (test-clock-now clock) seconds))))

(defun cookie-header (headers name)
  "The Set-Cookie header that sets NAME, or NIL."
  (find-if (lambda (header) (and (eq (car header) :set-cookie)
                                 (string-prefix-p (format nil "~a=" name) (cdr header))))
           headers))

(defun logged-in-status (port jar)
  "303 when JAR holds a live session (/login-info sends the person home), else 401."
  (web-request port "/login-info" :jar jar))

;;; ------------------------------------------------------------------
;;; MCP and access tokens

(test mcp-without-a-valid-token-is-401
  (with-test-server (port :identity :authenticated)
    (let ((body (tools-call-body "accounts_whoami" (jobj))))
      (multiple-value-bind (status json headers)
          (mcp-request port body :headers '(("X-Tun-Actor" . "admin:mallory")))
        (is (= 401 status) "X-Tun-Actor is ignored")
        (is (string= "Bearer realm=\"tun\"" (cdr (assoc :www-authenticate headers))))
        (is (= -32000 (jget (jget json "error") "code")))
        (is (json-null-p (jget json "id"))))
      (multiple-value-bind (status json headers) (mcp-request port body :token "tun_nope")
        (declare (ignore json))
        (is (= 401 status))
        (is (search "error=\"invalid_token\"" (cdr (assoc :www-authenticate headers)))))
      (is (<= 2 (count "unauthenticated" (admin-items "introspect_recent" "kind" "rejected")
                       :key (lambda (item) (jget item "error_code")) :test #'equal))
          "both refusals are retained"))))

(test a-token-calls-as-its-account
  (with-test-server (port :identity :authenticated)
    (let* ((claude (make-account "claude" "agent" "admin"))
           (token (make-token claude)))
      (is (string-prefix-p "tun_" token))
      (is (= 44 (length token)))
      (multiple-value-bind (json error-p status)
          (token-call port token "accounts_whoami" (jobj))
        (is (= 200 status))
        (is (eq nil error-p))
        (is (string= "admin:claude" (jget json "actor")))
        (is (string= "token" (jget json "credential")))
        (is (string= "claude" (jget (jget json "account") "name"))))
      ;; A mutation through the token is audited with the token's id.
      (let* ((created (token-call port token "accounts_create"
                                  (jobj "name" "robot" "kind" "agent" "role" "viewer")))
             (entry (first (admin-items "audit_list" "entity_type" "account"
                                        "entity_id" (jget created "id")))))
        (is (string= "robot" (jget created "name")))
        (is (string= "admin:claude" (jget entry "actor")))
        (is (string-prefix-p "tok_" (jget entry "credential"))))
      (is (stringp (jget (first (admin-items "tokens_list")) "last_used_at"))
          "the token's use is recorded"))))

(test a-token-acts-with-the-lower-of-its-role-and-its-accounts
  (with-test-server (port :identity :authenticated)
    (let* ((boss (make-account "boss" "agent" "admin"))
           (reader (make-token boss "role" "viewer"))
           (full (make-token boss)))
      (is (string= "viewer:boss" (whoami port reader)))
      (multiple-value-bind (json error-p) (token-call port reader "accounts_list" (jobj))
        (is (eq t error-p))
        (is (string= "forbidden" (error-code-of json))))
      (let ((clerk (make-account "clerk" "agent" "employee")))
        (is (string= "invalid_input" (refusal "tokens_create" "account_id" (jget clerk "id")
                                              "label" "x" "role" "admin"))
            "a token cannot outrank its account"))
      (update-account boss "role" "employee")
      (is (string= "employee:boss" (whoami port full))
          "demoting the account lowers what its tokens can do"))))

(test revoked-expired-and-disabled-tokens-are-refused
  (with-test-server (port :identity :authenticated)
    (let* ((agent (make-account "agent" "agent" "employee"))
           (revoked (make-token agent))
           (soon (format-rfc3339 (+ (with-application (*app*) (now)) 60)))
           (expiring (make-token agent "expires_at" soon))
           (other (make-token agent)))
      (is (= 200 (token-status port revoked)))
      (let ((token (find (subseq revoked 4 12) (admin-items "tokens_list")
                         :key (lambda (item) (jget item "prefix")) :test #'equal)))
        (call-ok "tokens_revoke" "admin:root" "id" (jget token "id")))
      (is (= 401 (token-status port revoked)) "revoked")
      (is (= 200 (token-status port expiring)))
      (advance-clock 61)
      (is (= 401 (token-status port expiring)) "expired")
      (is (= 200 (token-status port other)))
      (update-account agent "status" "disabled")
      (is (= 401 (token-status port other)) "its account is disabled")
      (update-account agent "status" "active")
      (is (= 200 (token-status port other)) "enabled again"))))

(test the-token-is-shown-once
  (with-test-app ()
    (let* ((agent (make-account "agent" "agent" "viewer"))
           (first (call-ok "tokens_create" "admin:root" "account_id" (jget agent "id")
                           "label" "x" "request_key" "k1"))
           (again (call-ok "tokens_create" "admin:root" "account_id" (jget agent "id")
                           "label" "x" "request_key" "k1"))
           (record (call-ok "introspect_record" "admin:root" "entity" "access_token"
                            "id" (jget first "id"))))
      (is (stringp (jget first "token")))
      (is (json-null-p (jget again "token")) "a replay does not repeat the token")
      (is (string= (jget first "id") (jget again "id")))
      (is (string= "***" (jget (jget record "stored") "token_hash")))
      (with-application (*app*)
        (with-transaction (:read)
          (is (notany (lambda (receipt)
                        (search (jget first "token") (jget (entity->json receipt) "result")))
                      (select 'receipt))
              "no receipt holds the token"))))))

(test people-make-their-own-tokens-and-admins-make-agents
  (with-test-server (port :identity :authenticated)
    (with-provider (provider)
      (let* ((per (make-account "per" "person" "employee" "per@example.no"))
             (ola (make-account "ola" "person" "employee" "ola@example.no"))
             (agent (make-account "robot" "agent" "employee"))
             (agent-token (make-token agent)))
        (flet ((code (tool actor &rest keys-and-values)
                 (nth-value 1 (apply #'call tool actor keys-and-values)))
               (prefixes (items)
                 (mapcar (lambda (item) (jget item "prefix")) items)))
          (is (string= "invalid_input" (code "tokens_create" "admin:root" "label" "x"
                                             "account_id" (jget per "id")))
              "an admin cannot make a token that acts as another person")
          (is (string= "invalid_input" (code "tokens_create" "admin:root" "label" "x"))
              "admin:root has no account of its own")
          (is (string= "forbidden" (code "tokens_create" "employee:per" "label" "x"
                                         "account_id" (jget agent "id")))
              "only an admin makes tokens for agents")
          (multiple-value-bind (status jar) (sign-in-as port provider "per@example.no")
            (is (= 303 status))
            (multiple-value-bind (status body) (web-request port "/access" :jar jar)
              (is (= 200 status))
              (is (search "New token for me" body))
              (is (not (search "All access tokens" body)) "accounts are for admins"))
            (let* ((body (nth-value 1 (web-request port "/access/tokens" :method :post :jar jar
                                                   :parameters '(("label" . "Claude Code")
                                                                 ("request_key" . "web_per")))))
                   (token (cl-ppcre:scan-to-strings "tun_[0-9a-z]{40}" body)))
              (is (stringp token))
              (is (string= "employee:per" (whoami port token)) "the token acts as per")
              (multiple-value-bind (json error-p) (token-call port token "tokens_create"
                                                              (jobj "label" "kopi"))
                (is (eq t error-p))
                (is (string= "forbidden" (error-code-of json)) "a token cannot copy itself"))
              (is (equal (list (subseq token 4 12))
                         (prefixes (coerce (jget (token-call port token "tokens_list" (jobj))
                                                 "items")
                                           'list)))
                  "per lists only per's own token")
              (is (string= "forbidden"
                           (error-code-of (token-call port token "tokens_list"
                                                      (jobj "account_id" (jget ola "id"))))))
              (let ((agent-id (jget (find (subseq agent-token 4 12) (admin-items "tokens_list")
                                          :key (lambda (item) (jget item "prefix")) :test #'equal)
                                    "id"))
                    (own-id (jget (first (admin-items "tokens_list" "account_id" (jget per "id")))
                                  "id")))
                (is (string= "forbidden" (error-code-of (token-call port token "tokens_revoke"
                                                                    (jobj "id" agent-id)))))
                (is (= 200 (token-status port agent-token)))
                (is (null (nth-value 1 (token-call port token "tokens_revoke" (jobj "id" own-id))))
                    "per revokes their own token")
                (is (= 401 (token-status port token)))))))))))

(test mcp-refuses-another-sites-origin
  (with-test-server (port :identity :authenticated)
    (let ((token (make-token (make-account "agent" "agent" "viewer"))))
      (flet ((status (origin)
               (nth-value 2 (token-call port token "accounts_whoami" (jobj)
                                        :headers (list (cons "Origin" origin))))))
        (is (= 403 (status "https://evil.example")))
        (is (= 200 (status (format nil "http://127.0.0.1:~d" port))))))))

(test claimed-identity-takes-the-header-and-tokens
  (with-test-server (port)
    (let ((claimed (http-tool-call port "admin:ada" "accounts_whoami" (jobj))))
      (is (string= "admin:ada" (jget claimed "actor")))
      (is (string= "claimed" (jget claimed "credential"))))
    (let ((token (make-token (make-account "agent" "agent" "viewer"))))
      (is (string= "viewer:agent" (whoami port token))))
    (is (= 401 (token-status port "tun_wrong"))
        "a token that was sent and refused is refused in claimed mode too")
    (is (string= "claimed" (jget (call-ok "introspect_runtime" "admin:root") "identity")))))

;;; ------------------------------------------------------------------
;;; Setup and sessions

(test setup-creates-the-first-admin-once
  (with-test-server (port :identity :authenticated)
    (is (string= "authenticated"
                 (jget (call-ok "introspect_runtime" "admin:root") "identity")))
    (with-provider (provider)
      (let ((path (setup-path)))
        (is (stringp path))
        (is (= 404 (web-request port "/setup/0000")))
        (is (= 200 (web-request port path)))
        (multiple-value-bind (status headers jar)
            (set-up-admin port provider :email "Kari@Example.no" :display-name "Kari Nordmann")
          (is (= 303 status))
          (is (string= "/access" (location headers)))
          (let ((cookie (cdr (cookie-header headers "tun_session"))))
            (is (search "HttpOnly" cookie))
            (is (search "SameSite=Lax" cookie))
            (is (not (search "Secure" cookie)) "plain HTTP: no Secure flag"))
          (multiple-value-bind (status body) (web-request port "/access" :jar jar)
            (is (= 200 status))
            (is (search "admin:kari" body))))
        (is (= 404 (web-request port path)) "setup is closed")
        (is (null (setup-path)) "and not announced again")
        (let ((kari (account-by-name "kari")))
          (is (string= "kari@example.no" (jget kari "email")))
          (is (string= "Kari Nordmann" (jget kari "display_name"))))
        (is (= 303 (sign-in-as port provider "Kari@Example.no")) "kari signs in again")))))

(test logging-in-and-out
  (with-test-server (port :identity :authenticated)
    (with-provider (provider)
      (make-account "per" "person" "employee" "per@example.no")
      (is (= 200 (web-request port "/login")))
      (is (= 401 (web-request port "/orders")) "no session, no pages")
      (is (= 403 (sign-in-as port provider "ingen@example.no")) "no account, no session")
      (multiple-value-bind (status jar) (sign-in-as port provider "PER@example.no")
        (is (= 303 status))
        (is (= 303 (logged-in-status port jar)) "logged in")
        (is (= 303 (web-request port "/logout" :method :post :jar jar)))
        (is (= 401 (logged-in-status port jar)) "logged out")))))

(test sessions-end
  (with-test-server (port :identity :authenticated)
    (with-provider (provider)
      (let ((eva (make-account "eva" "person" "employee" "eva@example.no")))
        (let ((jar (nth-value 1 (sign-in-as port provider "eva@example.no"))))
          (is (= 303 (logged-in-status port jar)))
          (advance-clock (* 8 86400))
          (is (= 401 (logged-in-status port jar)) "idle for more than 7 days"))
        (let ((jar (nth-value 1 (sign-in-as port provider "eva@example.no"))))
          (advance-clock (* 6 86400))
          (is (= 303 (logged-in-status port jar)) "in use within the week")
          (update-account eva "status" "disabled")
          (is (= 401 (logged-in-status port jar)) "the account was disabled"))))))

(test the-last-admin-person-stays
  (with-test-app ()
    (let ((kari (make-account "kari" "person" "admin" "kari@example.no"))
          (bot (make-account "bot" "agent" "admin")))
      (flet ((change (&rest keys-and-values)
               (apply #'refusal "accounts_update" "id" (jget kari "id") keys-and-values)))
        (is (string= "conflict" (change "role" "employee")))
        (is (string= "conflict" (change "status" "disabled"))))
      (update-account bot "role" "viewer")
      (make-account "ola" "person" "admin" "ola@example.no")
      (is (string= "employee" (jget (update-account kari "role" "employee") "role"))
          "another admin person exists"))))

(test account-rules
  (with-test-app ()
    (flet ((create (&rest arguments) (apply #'refusal "accounts_create" arguments)))
      (is (string= "invalid_input" (create "name" "Kari" "kind" "agent" "role" "viewer")))
      (is (string= "invalid_input" (create "name" "ka ri" "kind" "agent" "role" "viewer")))
      (is (string= "invalid_input" (create "name" "kari" "kind" "person" "role" "viewer"))
          "a person needs an email")
      (is (string= "invalid_input" (create "name" "kari" "kind" "agent" "role" "viewer"
                                           "email" "kari@example.no"))
          "an agent has none")
      (is (null (create "name" "bjørn.å-2" "kind" "agent" "role" "viewer")))
      (is (string= "conflict" (create "name" "bjørn.å-2" "kind" "agent" "role" "viewer")))
      (is (null (create "name" "kari" "kind" "person" "role" "viewer"
                        "email" "Kari@Example.no")))
      (is (string= "conflict" (create "name" "kari2" "kind" "person" "role" "viewer"
                                      "email" "kari@example.no"))
          "emails are compared in lowercase")
      (is (string= "forbidden" (nth-value 1 (call "accounts_list" "employee:per")))))))

(test clients-find-whom-to-mail
  (with-test-app (:public-url "https://tun.example")
    (make-account "kari" "person" "admin" "kari@example.no")
    (make-account "ola" "person" "employee" "ola@example.no")
    (make-account "bot" "agent" "admin")
    (update-account (make-account "eva" "person" "admin" "eva@example.no") "status" "disabled")
    (with-application (*app*)
      (with-transaction (:read)
        (is (equal "ola@example.no" (tun:account-address "ola")))
        (is (null (tun:account-address "bot")) "an agent has no address")
        (is (null (tun:account-address "eva")) "nor a disabled person")
        (is (null (tun:account-address "nobody")))
        (is (equal '("kari" "ola") (tun:account-names)))
        (is (equal '("kari") (tun:account-names :role :admin))))
      (is (equal "https://tun.example/saker/sak_1" (tun:absolute-url "/saker/sak_1"))))
    (with-test-app ()
      (with-application (*app*)
        (is (equal "/saker/sak_1" (tun:absolute-url "/saker/sak_1"))
            "without a public URL, the path alone")))))

(defun mail-texts ()
  "Every mail so far, oldest first, as (to subject text)."
  (reverse (map 'list (lambda (mail)
                        (let ((full (call-ok "mail_get" "admin:root" "id" (jget mail "id"))))
                          (list (jget full "to") (jget full "subject") (jget full "text"))))
                (jget (call-ok "mail_list" "admin:root") "items"))))

(test an-invitation-says-how-to-sign-in
  (with-test-app (:public-url "https://tun.example")
    (setf (tun.auth:sign-in-strategies *app*)
          (list (make-instance 'tun.auth:google-strategy :client-id "id" :client-secret "s")))
    (make-account "ola" "person" "employee" "ola@example.no")
    (is (null (mail-texts)) "no invite, no mail")
    (let* ((kari (call-ok "accounts_create" "admin:root" "name" "kari" "kind" "person"
                          "role" "employee" "email" "kari@example.no" "invite" t
                          "request_key" "invite-kari"))
           (mails (mail-texts))
           (text (third (first mails))))
      (is (null (gethash "password_link" kari)) "no password link")
      (is (= 1 (length mails)))
      (is (equal "kari@example.no" (first (first mails))))
      (is (equal (format nil "You have been given access to ~a" (application-title *app*))
                 (second (first mails))))
      (is (search "root has given you access to" text))
      (is (search (format nil "Sign in with Google and the email address kari@example.no:~%~
                               https://tun.example/login")
                  text))
      (call-ok "accounts_create" "admin:root" "name" "kari" "kind" "person"
               "role" "employee" "email" "kari@example.no" "invite" t
               "request_key" "invite-kari")
      (is (= 1 (length (mail-texts))) "a replay sends nothing more"))
    (is (string= "invalid_input" (refusal "accounts_create" "name" "bot" "kind" "agent"
                                          "role" "viewer" "invite" t)))))

(test an-invitation-is-in-the-tenants-language
  ;; spec/i18n.md 3.5, 8: written in the tenant's language when it is
  ;; stored, though the call that sent it came in over MCP.
  (with-test-app (:public-url "https://tun.example")
    (setf (tun.auth:sign-in-strategies *app*)
          (list (make-instance 'tun.auth:google-strategy :client-id "id" :client-secret "s")))
    (call-ok "settings_set" "admin:root" "key" "locale.language" "value" "nb")
    (call-ok "accounts_create" "admin:root" "name" "kari" "kind" "person"
             "role" "employee" "email" "kari@example.no" "invite" t)
    (destructuring-bind (to subject text) (first (mail-texts))
      (is (equal "kari@example.no" to))
      (is (equal (format nil "Du har fått tilgang til ~a" (application-title *app*)) subject))
      (is (search "root har gitt deg tilgang til" text))
      (is (search (format nil "Logg inn med Google og e-postadressen kari@example.no:~%~
                               https://tun.example/login")
                  text)))))

(test an-invitation-can-be-sent-again
  (with-test-app ()
    (let ((kari (make-account "kari" "person" "employee" "kari@example.no")))
      (is (json-null-p (jget kari "invited_at")) "created quietly")
      (let ((invited (call-ok "accounts_invite" "admin:root" "id" (jget kari "id")
                              "request_key" "invite-kari-1")))
        (is (stringp (jget invited "invited_at")) "it says when")
        (is (= 1 (length (mail-texts))))
        (is (equal "kari@example.no" (first (first (mail-texts))))))
      (call-ok "accounts_invite" "admin:root" "id" (jget kari "id") "request_key" "invite-kari-1")
      (is (= 1 (length (mail-texts))) "a replay sends nothing more")
      (is (string= "conflict" (refusal "accounts_invite" "id" (jget kari "id")))
          "not again within five minutes")
      (advance-clock 301)
      (call-ok "accounts_invite" "admin:root" "id" (jget kari "id"))
      (is (= 2 (length (mail-texts))) "but after them")
      (is (string= "forbidden" (nth-value 1 (call "accounts_invite" "employee:ola"
                                                  "id" (jget kari "id"))))
          "admins only")
      (update-account kari "status" "disabled")
      (is (string= "invalid_input" (refusal "accounts_invite" "id" (jget kari "id")))
          "not a disabled person"))
    (is (string= "invalid_input"
                 (refusal "accounts_invite" "id" (jget (make-account "bot" "agent" "viewer") "id")))
        "nor an agent")))

(test a-person-is-welcomed-once-invited-or-signed-in
  (with-test-app ()
    (let ((kari (make-account "kari" "person" "employee" "kari@example.no")))
      (make-account "ola" "person" "employee" "ola@example.no")
      (make-account "erp" "agent" "employee")
      (flet ((welcomed (name)
               (with-application (*app*)
                 (with-transaction (:read) (tun:account-welcomed-p name)))))
        (is (not (welcomed "kari")) "created quietly")
        (call-ok "accounts_invite" "admin:root" "id" (jget kari "id"))
        (is (eq t (welcomed "kari")) "invited")
        (with-application (*app*)
          (with-transaction (:write)
            (insert (make-instance 'tun.auth::account-identity
                                   :account-id (entity-id (tun.auth::find-account-by-name "ola"))
                                   :strategy "workos" :issuer "https://auth.example"
                                   :subject "ola-1" :email "ola@example.no"))))
        (is (eq t (welcomed "ola")) "signed in, never invited")
        (is (not (welcomed "erp")) "an agent is never mailed")
        (is (not (welcomed "nobody")))
        (update-account kari "status" "disabled")
        (is (not (welcomed "kari")) "nor a disabled person")))))

(test clients-tell-people-from-agents
  (with-test-app ()
    (make-account "kari" "person" "employee" "kari@example.no")
    (make-account "erp" "agent" "employee")
    (update-account (make-account "eva" "person" "employee" "eva@example.no") "status" "disabled")
    (with-application (*app*)
      (with-transaction (:read)
        (flet ((kind (actor) (tun:actor-account-kind (parse-actor actor))))
          (is (eq :person (kind "employee:kari")))
          (is (eq :agent (kind "employee:erp")))
          (is (null (kind "employee:eva")) "a disabled account is none")
          (is (null (kind "admin:nobody")) "nor is a claimed actor without one"))))))

(test redirects-are-recorded-as-ok
  (with-test-server (port)
    (is (= 303 (web-request port "/")))
    (let ((item (find "web:GET /" (admin-items "introspect_recent")
                      :key (lambda (item) (jget item "tool")) :test #'equal)))
      (is (string= "ok" (jget item "outcome"))))))

;;; ------------------------------------------------------------------
;;; /access

(test the-access-page-hands-out-tokens
  (with-test-server (port :identity :authenticated)
    (with-provider (provider)
      (let ((jar (admin-session port provider))
            (agent (make-account "claude" "agent" "admin")))
        (let ((page (nth-value 1 (web-request port "/access" :jar jar))))
          (is (search (format nil "value=\"~a\">claude (" (jget agent "id")) page)
              "the agent token form offers the agents")
          (is (not (search ">kari (" page)) "and not the people"))
        (flet ((post (path parameters) (web-request port path :method :post :jar jar
                                                    :parameters parameters))
               (token-form () `(("account_id" . ,(jget agent "id")) ("label" . "Claude Code")
                                ("role" . "viewer") ("request_key" . "web_1"))))
          (multiple-value-bind (status body) (post "/access/tokens" (token-form))
            (let ((token (cl-ppcre:scan-to-strings "tun_[0-9a-z]{40}" body)))
              (is (= 200 status))
              (is (stringp token))
              (is (search "claude mcp add --transport http" body))
              (is (string= "viewer:claude" (whoami port token)))
              (is (not (search token (nth-value 1 (post "/access/tokens" (token-form)))))
                  "sending the form again does not show the token")
              (let ((id (jget (first (admin-items "tokens_list")) "id")))
                (is (= 200 (post (format nil "/access/tokens/~a/revoke" id) '()))))
              (is (= 401 (token-status port token)))))
          (multiple-value-bind (status body)
              (post "/access/accounts" '(("name" . "ola") ("kind" . "person") ("role" . "admin")
                                         ("email" . "ola@example.no")))
            (is (= 200 status))
            (is (search "ola signs in with Testleverandør with the email ola@example.no" body)))
          (is (= 409 (post "/access/accounts" '(("name" . "ola") ("kind" . "agent")
                                                ("role" . "viewer")))))
          (multiple-value-bind (status body)
              (post "/access/accounts" '(("name" . "eva") ("kind" . "person") ("role" . "employee")
                                         ("email" . "eva@example.no") ("invite" . "on")))
            (is (= 200 status))
            (is (search "eva has been sent an invitation at eva@example.no" body))
            (is (equal '("eva@example.no") (mapcar #'first (mail-texts)))))
          (let ((kari (find "kari" (admin-items "accounts_list")
                            :key (lambda (item) (jget item "name")) :test #'equal)))
            (update-account kari "role" "employee")
            (multiple-value-bind (status body) (web-request port "/access" :jar jar)
              (is (= 200 status))
              (is (not (search "Kontoer" body))
                  "accounts are for admins: kari is an employee now that ola is the admin"))))))))
