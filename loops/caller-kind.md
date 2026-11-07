# An operation only a person signed in on the page may run

- loop: caller-kind
- mode: hands-on
- stage: done
- base: 9627863ac7e751208c77fa9c2704fdf1153eeed8
- item: sak_xd7z5aj2ms4y5xjz
- verified: 824cd1040e4519872f34c42e9e20029786901dc4
- shown: 824cd1040e4519872f34c42e9e20029786901dc4

## Brief

Prerequisite (b) for Factory 1 (Ferdig sak_317zg468h4qapk2q), item
sak_xd7z5aj2ms4y5xjz. Its spec, approved by Jonas at gate A on 2026-11-07,
says: «Anyone admin (you or an agent) asks for a host. Only you, signed in
on the page, approve, refuse or remove one: an access token or OAuth
connection cannot, so an agent never makes a host by itself.» It names
this prerequisite: «the caller's credential kind (session, token, oauth)
in Tun's public interface, so an operation can require a person on the
page.» Jonas, the same day: «Yes, build them first (Or at the same time,
while other things are running).»

Today `*credential*` holds `tok_…`, `ses_…`, `aid_…` or `"claimed"`;
only `accounts_whoami`, the token rule, push and «Access» read its prefix,
each on its own, and the public `TUN` package has none of it.

## Criteria

1. `(tun:credential-kind)` is `:session` in a page request with a session
   cookie, `:token` with a `tun_` bearer token, `:oauth` with an AuthKit
   token, `:claimed` under `--claimed-identity`, and NIL in a workflow, a
   job, or in-process code with no credential bound.
2. `accounts_whoami`'s `credential`, the refusal of `tokens_create` for
   one's own account through a token or OAuth, and the session-only uses
   in push and «Access» read `credential-kind`; their tests pass unchanged.
3. An operation declared `:session-only t` runs for a signed-in person on
   the page whose role meets its policy, and under `--claimed-identity`.
4. Called over `/mcp` or `/api` with an admin's access token, or an OAuth
   connection, it is `forbidden` with a message saying to do it signed in
   on the page; nothing changes, and an audit entry has outcome
   `rejected` and the call's credential.
5. Called from a workflow, or in-process with no credential, it is
   `forbidden` and does nothing.
6. A caller below its policy is refused by the policy, with today's
   message.
7. It is absent from `tools/list`; `registry_describe` gives it
   `session_only: true` and every other operation `false`; `explain` for a
   token caller says `session_only: true` and decision `deny`.
8. A client using `tun:credential-kind` and `:session-only` passes the
   interface check; core is 2.12.0.

## Decisions

- A declarative option, `:session-only t` on `define-operation`, beside
  `:policy`, rather than each client checking the credential in its
  body: the kernel then refuses, audits and hides it alike everywhere,
  and the registry shows it. `credential-kind` is public too, for a page
  or a body that needs to tell callers apart.
- `:claimed` counts as signed in: `--claimed-identity` has no security
  (anyone may claim admin), and previews and browser checks must be able
  to press the button. A deployed server never runs claimed.
- The process's own work (NIL) is refused: a workflow or job approving a
  host is the agent-made spending the rule exists to stop.
- Hidden from `tools/list` but still in `registry_describe` and on pages:
  an MCP client cannot run it, so offering it would only invite a refusal;
  agents still see in the registry that it exists and why they cannot.
- The check runs after the policy, so a viewer gets the policy's message,
  and before any lookup, as the policy does (`core.md` §3.3).
- Core 2.12.0 (2.9.0–2.10.0 went to fuzz, audit-nul and policy-properties, 2.11.0 to outbound-methods): a new option and a new
  public function. Nothing to deploy:
  nixploy-dashboard takes it with Factory 1.

## Log

- 2026-11-07 11:15  started, hands-on
- 2026-11-07 11:17  gate A asked of the person
- 2026-11-07 13:21  gate A: approve (jonas): «Approved»
- 2026-11-07 13:28  verify 1: passed build, test, check
- 2026-11-07 13:29  shown (/access)
- 2026-11-07 13:29  gate B asked of the person
- 2026-11-07 14:02  gate B: approve (jonas): «approve»
- 2026-11-07 14:02  finished at tun 80ff405
