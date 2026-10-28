# Messaging links from the public URL; links.base_url dropped

- loop: drop-base-url
- mode: hands-on
- stage: done
- base: d649e5f336edff7ed88de76ce0bf675559f3a27c
- verified: 55e7f1e4ce76e4291a966e8875383ded5d416586
- shown: 55e7f1e4ce76e4291a966e8875383ded5d416586

## Brief

Ferdig, the first client, in a message after moving production to 2.0.1,
2026-10-28: «`links.base_url` reads https://tun.example after the
migration. Nothing in src reads it, since links come from PUBLIC_URL, so
it's a dead setting with a placeholder default that looks like a
misconfiguration in settings_get. Consider dropping it or documenting it
as unused.» Only the messaging module reads it, for the offer, feedback
and unsubscribe links in its mails. Jonas, asked what to do, 2026-10-28:
«Drop it, use PUBLIC_URL», a contract removal in 2.x accepted since 2.0
is a day old.

## Criteria

1. The messaging module's `quote.link`, `link.feedback` and
   `link.unsubscribe` are `absolute-url` of `/offer/<quote id>`,
   `/feedback/<token>` and `/unsubscribe/<token>`: the server's public URL
   and the path, and the path alone on a server without one.
2. Core declares no `links.base_url`: `settings_list` leaves it out, and
   `settings_get` and `settings_set` answer `not_found` for it.
3. A database that stores a value for `links.base_url` (a 2.0 one where
   an administrator set it) opens and serves as before; the row stays in
   `setting`, unread and unlisted, and `--revert-to-core-1` still moves
   it back to `lenker.base_url`.
4. `spec/core.md` §5.3 drops the setting and states the rule for a
   setting no longer declared; `deploy.md` §1 and the messaging README
   say where the links come from; core 2.1.0.
5. Tests show 1–3; `bin/test` green, `bin/build` warning-free.

## Decisions

- **The stored row stays.** Deleting it would need a data migration of
  its own, which 2.x has no machinery for, and it would lose the value
  for an older 2.0.x started on the same database and for
  `--revert-to-core-1`. A setting nobody declares is already invisible:
  every reader goes through the declarations.
- **Core 2.1.0, not 3.0.** Removing a declared setting is a contract
  change, but the only reader is a module in this repository, which moves
  with it. A client that ran `nix flake update tun` alone, keeping
  messaging at 2.0.x, would mail `NIL/offer/…` links; no client runs
  messaging yet (Ferdig does not), so this is noted in the release
  rather than guarded.
- **No public URL, the path alone.** That is what `absolute-url` and
  core's own mail do (`mail.md`, `deploy.md` §1); a deployed target
  with a domain always gets `PUBLIC_URL`.
- **Link token purposes unchanged.** `avmeld` and `tilbakemelding` are
  HMAC purposes inside every token already mailed; renaming them would
  void those links.
- No browser check: nothing on a page changes. The showcase does not
  enable messaging.

## Evidence

- `bin/test`: core 7692 checks, test client 148, none failed; `bin/build`
  warning-free; the loop's verify round 1 green (build, test, check).
- Criterion 1: `message-links-are-at-the-public-url`; 2:
  `links-base-url-is-no-setting`; 3: `a-stored-links-base-url-stays-unread`
  on SQLite and Postgres, beside the 2.0 rename and revert tests, which
  pass unchanged.
- The preview's settings page (admin) lists `links.secret`, the three
  `locale.*` settings and `push.secret`, and no `links.base_url`.

## Log

- 2026-10-28 19:38  started, hands-on
- 2026-10-28 19:40  gate A asked of the person
- 2026-10-28 19:41  gate A: approve (jonas): «Approve»
- 2026-10-28 20:17  verify 1: passed build, test, check
- 2026-10-28 20:18  shown (/settings)
- 2026-10-28 20:18  gate B asked of the person
- 2026-10-28 20:19  gate B: approve (jonas): «Approve and push»
- 2026-10-28 20:19  finished at tun 525f944
