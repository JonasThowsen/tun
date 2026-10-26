# Identity and access

Status: v1, 2026-10-13; sign-in with an identity provider (§3.5),
2026-10-14; WorkOS, providers in place of passwords (§3.1, §3.4) and
OAuth for MCP clients (§5.1), 2026-10-21; `accounts_invite` and
`actor-account-kind`, 2026-10-21. Who a request runs as, and how a tenant knows it.
Every call already runs as an actor, a role and a name such as
`employee:kari` (`core.md` §3.2); policy, audit, receipts and
confirmation tokens are bound to it. This contract says where the actor
comes from: an account's session in the UI, an account's access token on
MCP, or, only on a server started for development or tests, the claim in
the request.

## 1. Two modes

A server runs in one of two identity modes, fixed at start:

- **Authenticated**, the default. The actor comes from a credential the
  tenant issued (§3): a session started through an identity provider, or
  an access token. A request without a valid one is
  anonymous: MCP refuses it (§5), and the UI shows only public pages and
  the login page.
- **Claimed**, with `--claimed-identity`. The `X-Tun-Actor: role:name`
  header on `/mcp` and in the UI, and `GET /login?actor=role:name`, set the
  actor as before. Credentials work as well. It exists for tests,
  previews and local development. The server says so in its start-up line,
  and `introspect_runtime` reports `"identity": "claimed"`.

The image (`deploy.md` §2) starts authenticated. Nothing in Tun passes
`--claimed-identity` to a deployed server.

## 2. Accounts

An account is a record of the core entity `account` (id prefix `acc`):

| Field | Meaning |
|---|---|
| `name` | The actor's name: 1 to 64 lowercase letters, digits, `.`, `_` or `-`. Unique. |
| `display_name` | How people see it, up to 120 characters. |
| `kind` | `person`, who logs in to the UI, or `agent`, which only holds tokens. |
| `role` | `admin`, `employee` or `viewer`. |
| `email` | The address a person signs in with, stored in lowercase. Required for a person, absent for an agent. Unique. |
| `status` | `active` or `disabled`. |
| `created_at`, `created_by` | When, and which actor created it. |
| `invited_at` | When the last invitation was mailed (§3.6), or null. |

- The account's actor is `role:name`. Changing its role changes the actor
  that audit entries, receipts and other records name from then on.
- A disabled account's sessions and tokens stop working at its next
  request. Enabling it again does not bring back ended sessions.
- Once a tenant has an active admin who is a person, it keeps one: a
  change that would disable or demote the last one is refused with
  `conflict`.
- A client finds whom to mail through two functions in the TUN package,
  never the account records: `(account-address NAME)`, the email of the
  account NAME when it is an active person, else NIL; and
  `(account-names &key role)`, the names of the active people, in name
  order, only those with ROLE (such as `:admin`) when given. Agents and
  disabled accounts are neither mailed nor listed.
- `(account-welcomed-p NAME)` is true when NAME is an active person who
  has been invited (§3.6) or has signed in. A person created quietly, so
  their records could be imported first, is not: a client mails people
  about its work only once this holds.
- A client tells a person from an agent with `(actor-account-kind
  ACTOR)`: `:person` or `:agent`, the kind of the active account ACTOR
  acts for, or NIL when it acts for none (a claimed actor no account
  has, the process itself, a customer). `(actor-account-kind *actor*)`
  is the caller's.
- Credentials (token and session hashes, and the identities a provider
  vouches for) are stored in internal entities apart from the account. They are secret
  fields (§7) and never appear in any tool's output.

## 3. Credentials

### 3.1 Passwords

Tun keeps no passwords. A person signs in through an identity provider
(§3.5), usually WorkOS (§3.5.1), whose page owns passwords and their
reset, codes by email, second factors, passkeys and a company's single
sign-on, and which tells Tun only a verified email. How the login page
offers the providers is §3.4.

### 3.2 Access tokens

- An access token belongs to one account and lets an agent or a script
  call MCP as that account. It is sent as `Authorization: Bearer TOKEN`.
- A token is `tun_` followed by 40 characters (200 random bits). The
  tenant stores its SHA-256 and its first 8 characters after `tun_`, to
  tell tokens apart. The token itself is in the result of `tokens_create`
  and nowhere else: not in the receipt, the audit log or the trace.
- A token acts as its account and never as more: every call through it
  meets the same policy as the account's own calls in the UI, because the
  UI calls the same tools.
- Who creates a token:
  - A person creates tokens for their own account, whatever their role,
    on `/access` or with `tokens_create` without `account_id`.
  - An admin creates tokens for agent accounts.
  - Nobody creates a token for another person, so no one can act under a
    person's name without signing in as that person.
- A token cannot create another token for its own account: that is done
  in a session (or in-process code, or claimed mode).
  A leaked token is gone once it is revoked; it cannot leave a copy.
- A token has a `role` no higher than its account's when it is created.
  It acts with the lower of the two: a viewer token on an admin account
  calls as `viewer:name`.
- A token has a `label`, an optional `expires_at`, `created_at`,
  `created_by`, `last_used_at` (written at most once a minute) and
  `revoked_at`. A revoked, expired or disabled-account token is refused.

### 3.3 Sessions

- A successful login starts a session. Its cookie `tun_session` holds 256
  random bits; the tenant stores their SHA-256, the account, the creation
  time and the last use (written at most once an hour).
- A session ends 30 days after login, after 7 days without use, at logout,
  or when its account is disabled.
- The cookie is `HttpOnly`, `SameSite=Lax`, `Path=/`, and `Secure` when
  the request came over HTTPS (directly, or `X-Forwarded-Proto: https`
  from the proxy in front).
- Logout is `POST /logout`.
- A POST from another origin is refused before it is read, which with
  `SameSite` keeps another site from acting with the cookie. A browser
  that sends `Sec-Fetch-Site` is judged by it alone: `same-origin` or
  `none` passes. Its `Origin` can be `null` on a page sent with
  `Referrer-Policy: no-referrer`: setup, `/access` and the public pages. Without `Sec-Fetch-Site`, `Origin`, when present,
  must be the server's own `scheme://host:port`.

### 3.4 Logging in

- `GET /login` shows a button per identity provider (§3.5), in the order
  the application lists them, and says that an administrator gives
  people access by their email. After a refused sign-in it shows why.
- An application lists at least one provider. An authenticated server
  whose application lists none refuses to start, with exit status 2 and
  a line saying to add one, such as `(:workos ...)`; so does one that
  lists `(:password)`, which is no strategy. A claimed server starts
  without them and says so.
- `POST /login` answers 404.
- A tenant that once had passwords keeps its `passwords` and
  `password_links` tables, unread: migrations are additive
  (`store.md` §2).

### 3.5 Signing in with an identity provider

A person can sign in with an account they already have elsewhere, such as
Google, through OpenID Connect (the authorization code flow with PKCE).
The tenant never sees a password, and still decides who may come in: a
provider only proves an email address, and an admin creates the account
for it first.

**Choosing the ways.** `define-application` lists them in its
`(:sign-in …)` option (`docs/client-api.md`), each a strategy with its
settings, at least one (§3.4).

```lisp
(define-application feedback ()
  (:modules customers)
  (:sign-in (:google :client-id (:env "GOOGLE_CLIENT_ID")
                     :client-secret (:env "GOOGLE_CLIENT_SECRET"))))
```

| Strategy | Settings |
|---|---|
| `(:google …)` | `:client-id`, `:client-secret` |
| `(:workos …)` | `:domain`, `:client-id`, `:client-secret`, optional `:label` |
| `(:oidc …)` | `:name`, `:label`, `:issuer`, `:authorization-endpoint`, `:token-endpoint`, `:client-id`, `:client-secret`, optional `:scopes` |

- `:google` is `:oidc` with Google's issuer (`https://accounts.google.com`)
  and endpoints filled in, named `google` and labelled «Google». It asks
  Google to let the person choose among their accounts
  (`prompt=select_account`).
  `:workos` is `:oidc` with WorkOS AuthKit (§3.5.1), named `workos` and
  labelled «WorkOS». `:oidc`
  is any other OpenID Connect provider. Its `:name` (lowercase letters,
  digits and `-`) is in its URLs; its `:label` is on its button. `:scopes`
  defaults to `openid email profile`.
- A setting is a string, or `(:env "NAME")`: the value of that environment
  variable, read when the server starts. A client secret belongs in the
  environment, never in the repository; a deployment puts it in the
  target's SOPS file beside `DATABASE_URL` (`deploy.md` §3).
- In authenticated mode a server whose strategy lacks a value refuses to
  start, with exit status 2 and a line naming what is missing. In claimed
  mode it starts without that strategy and says so.
**The flow**, for a strategy named NAME:

1. The login page has a button per provider, «Logg inn med Google», that
   posts to `/auth/NAME`.
2. The server starts an attempt: a `state` of 256 random bits, a `nonce`
   and a PKCE verifier. It stores the state's SHA-256, the nonce, the
   verifier and what the attempt is for (a login, or setup: §4), for 10
   minutes, and sets the cookie `tun_sign_in` to the state (`HttpOnly`,
   `SameSite=Lax`, `Path=/auth/`, `Secure` as in §3.3, 10 minutes). It
   answers 303 to the provider's authorization endpoint with
   `response_type=code`, `client_id`, `redirect_uri`, `scope`, `state`,
   `nonce`, `code_challenge` and `code_challenge_method=S256`.
3. The provider sends the browser back to `GET /auth/NAME/callback` with
   `code` and `state`. The attempt must be for NAME, unexpired, and its
   state must equal the `tun_sign_in` cookie. It is used up whatever
   happens next, and the cookie is cleared.
4. The server exchanges the code at the token endpoint: a POST with
   `client_id`, `client_secret`, the same `redirect_uri` and the verifier,
   over HTTPS with the provider's certificate verified, within 10 seconds.
   The ID token in the answer came straight from the provider over TLS, in
   exchange for the client secret, so its signature is not checked
   (OpenID Connect Core §3.1.3.7); its claims are. `iss` is the provider's
   issuer; `aud` is the client ID or a list holding it, and then `azp` is
   the client ID; `exp` has not passed and `iat` is not in the future,
   each with 60 seconds of leeway; `nonce` is the attempt's; `email` is
   there and `email_verified` is true.
5. Who it is: the account the identity (NAME, `sub`) is linked to. When
   it is linked to none, the active person whose email is the claim's,
   if that account has no identity from NAME yet: the identity is linked
   to it now, audited as `identity_linked`. Nobody else signs in: there
   is no account to sign up for.
6. A session starts (§3.3), audited as `login`
   with the session as the credential, and the answer is 303 to the home
   page.

Refusals answer the login page with a message (LABEL is the strategy's
label), are not audited, and are retained as rejected requests
(`introspect_recent`), as failed logins are:

| Case | Status | Message |
|---|---|---|
| Unknown, used or expired attempt, or a state that does not match | 400 | «Innloggingen kunne ikke fullføres. Prøv igjen.» |
| The provider answers with `error` (the person cancelled, for one) | 400 | «Innloggingen med LABEL ble avbrutt.» |
| The exchange fails, or a claim fails its check | 502 | «LABEL svarte ikke som forventet. Prøv igjen.» |
| No account for the email, or its account is disabled | 403 | «Det finnes ingen konto for E-POST her. Be en administrator om tilgang.» |

**The callback URL** is the server's public URL (`deploy.md` §1) followed
by `/auth/NAME/callback`, else the scheme and host the request came with.
It is what the provider must know: for Google, an authorized redirect URI
of a web application's OAuth client.

**3.5.1 WorkOS.** AuthKit, WorkOS's hosted sign-in page, is an OpenID
Connect provider; it signs people in with whatever the WorkOS environment
allows, such as Google, Microsoft, email with a code, passkeys and a
company's single sign-on, and gives Tun a verified email as any provider
does.

- `:domain` is the environment's AuthKit domain, such as
  `acme.authkit.app` or a custom one such as `login.acme.no`: `https://`
  is added unless it names its scheme, and a trailing `/` is dropped.
  That URL is the issuer; the authorization endpoint is
  `DOMAIN/oauth2/authorize` and the token endpoint `DOMAIN/oauth2/token`.
- The client id and secret are those of a first-party OAuth application
  in the WorkOS dashboard (Connect → OAuth applications), whose redirect
  URI is the callback URL below.
- It asks AuthKit to show its sign-in page every time (`prompt=login`),
  even to someone AuthKit still remembers. Tun's logout (§3.3) ends only
  Tun's session, and AuthKit offers Tun no way to end its own, so without
  it the next «Logg inn» would come straight back signed in.
- Its buttons name no provider, since AuthKit's page offers the choice:
  «Logg inn» on the login page, «Fortsett» at setup (§4). An invitation
  (§3.6) says to log in with the person's email address.

**Identities** are records of the internal entity `account_identity`: the
account, the strategy's name, the issuer, the subject, the email it was
linked with, and when it was linked and last used. One subject of one
strategy belongs to one account, and an account has at most one identity
per strategy. A change of an account's email by `accounts_update` removes
its identities, so the next sign-in links the new address.

### 3.6 Invites

`accounts_create` with `invite: true` also mails the new person how to
come in, through `send-mail` (`mail.md`) in the same transaction, so a
refused call mails nobody.

- The subject is «Du har fått tilgang til TITTEL», the application's
  title.
- The text names who invited them (the caller's display name, else
  their account name), the providers to sign in with (those whose button
  names one: §3.5.1), the address to use, and the link to `/login` at the
  public URL (`deploy.md` §1).
- The mail's key is `invite:ACCOUNT-ID` for the first invitation and
  `invite:ACCOUNT-ID:INVITED-AT` for a later one, so a replay sends
  nothing more. Each invitation sets the account's `invited_at`.
- `invite` for an agent is `invalid_input`: an agent does not sign in.
- `/access` offers it as «Send invitasjon på e-post» on the form for a
  new account, and says the invitation was sent.
- `accounts_invite` with an account's `id` mails an active person the
  same invitation, for an account created without one or a person who
  lost it. Within five minutes of the last invitation to that account it
  is refused with `conflict`, so a double click or a loop mails no one
  twice; a call with the same `request_key` answers the first result and
  mails nothing. An agent or a disabled account is `invalid_input` on
  `id`.

## 4. The first administrator

- When the server starts in authenticated mode and the tenant has no
  active admin person, it prints one line to standard output:
  `tun: no administrator yet; create one at /setup/CODE`. The code has
  256 random bits, lives only in this process's memory, and is new at
  every start.
- `GET /setup/CODE` shows a form for the name and display name of the
  first admin, with a button per provider (§3.5): «Fortsett med Google»,
  or «Fortsett» for WorkOS. A button posts the name and display name with
  `provider=NAME`; they are checked as `accounts_create` would, and then
  the browser goes to the provider as in §3.5 with an attempt for setup
  that holds the code, the name and the display name. Its callback
  creates the admin with the claim's email (and its `name` as display
  name when none was given), links the identity, logs in and closes
  setup, when the code is still this process's and the tenant still has
  no admin; else it answers 404.
- Once an active admin person exists, every `/setup/...` answers 404, in
  every process on the database.
- When the server knows its public URL, the line gives the whole link,
  `create one at https://HOST/setup/CODE`.
- The host's log is where the operator finds the code (`nixploy logs`).

## 5. MCP

- In authenticated mode a `POST /mcp` needs a valid bearer token. Without
  one the answer is HTTP 401 with `WWW-Authenticate: Bearer realm="tun"`
  (and `error="invalid_token"` when a token was sent but refused), and a
  JSON-RPC error with id null, code -32000 and a message. The body is not
  read. The request is retained with outcome `rejected` and code
  `unauthenticated`.
- `X-Tun-Actor` is ignored in authenticated mode.
- A request with an `Origin` header other than the server's own
  `scheme://host` is refused with 403, as the MCP transport requires
  against DNS rebinding.
- Everything after that is unchanged: `tools/list` lists every tool, and
  each call's policy decides by the actor's role.

### 5.1 OAuth through WorkOS

When the application signs in with `(:workos …)` (§3.5.1), an MCP client
that speaks OAuth, such as Claude Code or a Claude.ai connector, connects
as a person without a token from `/access`: AuthKit is the authorization
server, and Tun the resource server, as the MCP authorization
specification and RFC 9728 describe.

- **The resource** is the server's public URL (`deploy.md` §1) followed
  by `/mcp`, else the scheme and host the request came with.
- **`GET /.well-known/oauth-protected-resource`**, and the same with
  `/mcp` after it, answer JSON: `resource`, `authorization_servers` (a
  list holding the AuthKit URL) and `bearer_methods_supported`
  (`["header"]`). For clients that ask the resource for the authorization
  server's metadata, `GET /.well-known/oauth-authorization-server`
  answers AuthKit's own, fetched from
  `DOMAIN/.well-known/oauth-authorization-server` and kept for an hour;
  502 when AuthKit cannot be reached. Without a WorkOS strategy all three
  answer 404.
- **The 401** of §5 also names the metadata, so a client finds AuthKit:
  `WWW-Authenticate: Bearer realm="tun",
  resource_metadata="RESOURCE-METADATA-URL"`, with `error="invalid_token"`
  when a token was sent but refused.
- **A bearer token** that does not start with `tun_` is taken as an
  AuthKit access token, a JWT, and accepted when:
  - its header's `alg` is `RS256` and its `kid` names an RSA key of at
    least 2048 bits in AuthKit's key set, `DOMAIN/oauth2/jwks`, and the
    signature verifies (RSASSA-PKCS1-v1_5 with SHA-256). The key set is
    fetched when a token names a key not yet known, at most once a minute,
    and kept;
  - `iss` is the AuthKit URL, `aud` is the resource or a list holding it,
    `exp` has not passed and `iat` is not in the future, each with 60
    seconds of leeway, and `sub` is there.
- **Who it is**: the active person whose WorkOS identity (§3.5) has that
  `sub`. The identity is linked at the person's first sign-in in the
  browser, so a person who has never signed in is refused with 403 and a
  message saying to sign in at `/login` first. A token that fails a check,
  or whose person is disabled, is 401 with `error="invalid_token"`; when
  AuthKit's key set cannot be fetched, 503. Refusals are retained as
  rejected requests with code `unauthenticated`, as in §5.
- The call acts as the person's account with its role. Its credential is
  the identity's id (`aid_...`), which `accounts_whoami` reports as
  `oauth`. Like an access token, it cannot create tokens for its own
  account (§3.2).
- **In the WorkOS dashboard**: turn on Client ID Metadata Documents and
  Dynamic Client Registration (Connect → Configuration), so MCP clients
  can register, and add the resource as a Resource Indicator, so AuthKit
  puts it in the token's `aud`.

## 6. Tools

| Tool | Policy | Does |
|---|---|---|
| `accounts_whoami` | viewer | The caller's actor, account (when it has one) and credential kind: `token`, `session`, `oauth` or `claimed`. |
| `accounts_list` | admin | Every account, without credentials, with `sign_in`: the strategies linked to it, such as `["workos"]`. |
| `accounts_create` | admin | Creates an account. With `invite`, a person is mailed how to sign in (§3.6). |
| `accounts_update` | admin | Changes `display_name`, `role`, `email` or `status`. A new email unlinks the account's identities (§3.5). |
| `accounts_invite` | admin | Mails an active person the invitation again (§3.6); at most once every five minutes per account. |
| `tokens_list` | viewer | The caller's own tokens; for an admin, every token, optionally one account's. Prefix, label, role, times; never the token. |
| `tokens_create` | viewer | A token for the caller's own account, or an admin's for an agent account (§3.2): `label`, optional `account_id`, `role` and `expires_at`. The result's `token` is the only copy. |
| `tokens_revoke` | viewer | Revokes one of the caller's own tokens; an admin revokes any. |

Refusals: a call about another account's tokens by someone who is not
an admin, and `tokens_create` for one's own account through a token, are
`forbidden`; an admin's `tokens_create` for another person is
`invalid_input` on `account_id`.

They are ordinary operations: policy, validation, idempotency and audit
apply. A replay of `tokens_create` with the same `request_key` returns the
original result with `token` set to null. The UI's page
`/access` ("Tilgang") calls the same tools: every person sees their own
tokens there, and an admin also sees accounts and every token.

## 7. Secrets in records and results

- A field declared `:secret t` reads as `"***"` in every JSON projection
  of its record, including `introspect_record`.
- An operation hands a credential it creates to its caller with
  `(show-once key value)`: the key is in the result of that call only,
  and the receipt holds null in its place, so a replay returns null.
- Every audit entry records the credential the call was made with: the
  token id (`tok_...`), the session id (`ses_...`), the WorkOS identity's
  id for OAuth (`aid_...`, §5.1), `claimed`, or null for work the system
  did itself. `introspect_request` shows the same.

## 8. Not yet

- OAuth for MCP clients through providers other than WorkOS.
- Signing up by signing in, such as everyone with a verified address at
  one domain; providers that speak OAuth 2.0 without OpenID Connect, such
  as GitHub; reading a provider's endpoints from its discovery document;
  and unlinking an identity on its own.
- Tokens limited to some tools. Which records a person reaches is the
  entity's record policy (`spec/store.md` §6).
- Rate limits by address. Behind a proxy every request comes from
  loopback; the provider limits attempts to sign in.

## 9. Evidence

- `tests/auth-tests.lisp` covers each rule above over real HTTP: tokens
  (use, role cap, expiry, revocation, disabled account, no copy in the
  receipt, who may create, list and revoke which), the 401 and its
  header, the Origin check, `X-Tun-Actor` ignored, sessions (login
  through the fake provider below, logout, expiry), setup (only without
  an admin, closed after), the login page without passwords, the
  last-admin guard, masking and the credential in audit entries; invites
  (§3.6), for an agent, and on the `/access` form.
- `tests/sign-in-tests.lisp` covers §3.5 and setup with a provider over
  real HTTP, against a fake OpenID Connect provider in the test process
  that checks what it is sent (the client secret, the redirect URI, the
  PKCE verifier against the challenge) and answers with the identity a
  test chooses: the attempt and its cookie, each claim check, linking by
  email and then by subject, refusals, the WorkOS preset, a changed
  email, and a server that refuses to start without its settings or
  without a provider.
- `tests/oauth-tests.lisp` covers §5.1 over real HTTP against the fake
  provider, which also signs access tokens with an RSA key of its own and
  serves its key set and metadata: the protected resource metadata and
  the proxied authorization server metadata, the 401's
  `resource_metadata`, a token that calls as its person, each check on
  the signature and the claims, a key fetched when a new one appears, an
  unlinked identity, a disabled person, and no token for oneself.
- `bin/test-cli` checks that the client's image starts authenticated:
  `/mcp` without a token is 401, the log has the setup line, and setup
  through a fake WorkOS makes the admin who then makes a token.
- Previews and their browser checks run with `--claimed-identity`
  (`preview.md`).
