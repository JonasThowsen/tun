# En eldre Tun nekter en database en nyere hovedversjon har åpnet

- loop: major-guard
- mode: autonomous
- stage: ship
- base: 4ee9d7c3099692a3e75726c01dbce779908e2aa3
- verified: 28b54133a0f05aed89e3bf996e770c298431bb82
- shown: 28b54133a0f05aed89e3bf996e770c298431bb82

## Brief

Jonas, 2026-10-28, at gate A of the loop that makes Tun 2.0 rename a
tenant's setting keys: «All of it», including «a 1.23.1 release that
refuses a renamed database, taken by clients before 2.0». Without it, a
1.x binary started on a database 2.0 has migrated, by a rollback or a
blue/green switch, silently makes new secret settings, and every link
already mailed and every push subscription stops working.

## Criteria

1. Opening a database records the mark `core-major-1` once in
   `schema_history` (`module` `tun-core`, `statement`
   `core major 1 opened this database`), on SQLite and Postgres; opening
   it again adds none, and core's own migration numbers are unchanged.
2. A database whose history holds `core-major-2` (or any major above 1)
   is refused on SQLite and Postgres before anything is migrated or
   written: opening signals an error naming both majors, the history and
   tables are as they were, and `open-application` closes the
   connections it opened, so the server exits with code 2 and the message
   on stderr (a check of the built server, or the argument from its
   toplevel at gate B).
3. A database with only `core-major-1`, or none (one written before this
   release), opens as before.
4. `spec/store.md` §2 item 10 states the rule and what it does not guard;
   `spec/core.md` §6.4 and `spec/tun-platform.md` §4 point to it.
5. `tests/store-tests.lisp` shows 1–3 on SQLite, and on Postgres where
   the suite has it; core 1.23.1.

## Decisions

- The mark is a row in the existing `schema_history`, not a new table, so
  every Tun since the history existed can read it, and 2.0 needs nothing
  new to write its own.
- Refused before anything is migrated, in the same transaction that would
  migrate, so a refused start changes nothing.
- The rule is general for any major, so 3.0 needs no new guard.
- The mark's module is `tun-core`, which no module name can match, and
  not `core`, whose row count numbers core's own migrations.
- It guards only from 1.23.1 on and only at start; the spec says so, and
  a higher major records its mark no later than its first incompatible
  change.
- A patch release, 1.23.1: no behaviour changes for a database of this
  major.

- **The server refuses as its other start checks do.** `main` catches
  `newer-database`, prints `NAME: <the message>` on stderr and exits with
  code 2, like the sign-in and mail refusals. `open-application` closes
  the store in an `unwind-protect` cleanup once the migrate transaction
  has unwound; closing from a `handler-bind` inside it would take the
  writer's mutex the transaction holds.

## Evidence

- Criterion 2 on the built server: `bin/serve --client test-client
  --db mg.sqlite --test-clock --claimed-identity` on a SQLite database
  whose history holds `core-major-2` exited 2 and printed `test-client:
  Core major 2 has opened this database; core 1.23.1 (major 1) cannot
  read what it may have changed and refuses to start.`; the
  `schema_history` row count was unchanged. The same database had first
  opened with one `core-major-1` row.
- `bin/pressure` (tun-acceptance, sirkusagio) on this tree: P1–P6 pass;
  P7 failed one run of three, which ran none of its 20 `debug_ping`s
  (nothing ran twice). P7 alone, five runs each, passes on this tree and
  on main 4ee9d7c alike.

## Log

- 2026-10-28 06:14  started, autonomous
- 2026-10-28 06:14  gate A asked of a reviewer
- 2026-10-28 06:17  gate A: changes (reviewer): the spec overclaims (only 1.23.1 on checks, and only at start; a running old process is not stopped); put the rule in §2 and add a line to core.md §6.4 and tun-platform.md §4; the mark's module must be one no module can have, and say what goes in statement
- 2026-10-28 06:19  gate A asked of a reviewer
- 2026-10-28 06:22  gate A: changes (reviewer): the three earlier requests are met and the rule is buildable as written; tun-platform.md §4 still said a rollback to a lower major is refused at start, which is false for a pin back to 1.23.0 or earlier
- 2026-10-28 06:22  gate A asked of the person
- 2026-10-28 06:23  gate A: approve (Jonas): «Approve»
- 2026-10-28 06:56  verify 1: passed build, test, check
- 2026-10-28 06:57  shown (/)
- 2026-10-28 07:09  gate B asked of a reviewer
- 2026-10-28 07:14  gate B: approve (reviewer): the guard runs in the migrate write transaction right after ensure-schema-history on both stores, so a refusal rolls back everything; open-application closes the store once the transaction unwinds and main exits 2 with the message; the store tests fail on both stores with the guard removed, and criterion 2 reproduced on the built server
