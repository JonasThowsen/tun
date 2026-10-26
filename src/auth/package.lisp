;;;; auth/package.lisp -- TUN.AUTH: accounts and the credentials that prove
;;;; who a request runs as (spec/auth.md).
;;;;
;;;; The transports ask this package for an actor: MCP with an access token
;;;; (AUTHENTICATE-TOKEN), the UI with a session cookie
;;;; (AUTHENTICATE-SESSION).  Everything after that, policy, audit and
;;;; receipts, is the execution path's, as for any other actor.

(defpackage #:tun.auth
  (:use #:cl #:tun.core)
  (:import-from #:tun.mail #:send-mail)
  (:export
   ;; accounts
   #:account #:account-name #:account-display-name #:account-kind #:account-role
   #:account-email #:account-status #:account-actor #:find-account-by-name
   #:account-address #:account-welcomed-p #:actor-account-kind #:account-names #:accounts-create
   ;; access tokens
   #:access-token #:authenticate-token
   ;; sessions and logging in
   #:+session-cookie+ #:+session-lifetime+ #:authenticate-session #:log-out
   ;; the first administrator
   #:setup-code #:setup-code-valid-p #:announce-setup
   ;; signing in with an identity provider
   #:sign-in-strategy #:oidc-strategy #:google-strategy
   #:workos-strategy #:strategy-domain #:strategy-button-label
   #:strategy-name #:strategy-label #:strategy-issuer #:strategy-issuers
   #:strategy-authorization-endpoint #:strategy-token-endpoint #:strategy-client-id
   #:strategy-scopes #:sign-in-strategies #:sign-in-problems
   #:identity-providers #:find-identity-provider
   #:start-sign-in #:finish-sign-in #:sign-in-refused #:sign-in-refused-status
   #:sign-in-refused-message #:sign-in-refused-detail #:+sign-in-cookie+
   #:+attempt-lifetime+ #:account-identity #:check-account-names
   ;; MCP clients through WorkOS (OAuth)
   #:oauth-strategy #:protected-resource-metadata #:authorization-server-metadata
   #:authenticate-oauth-token #:provider-failure))
