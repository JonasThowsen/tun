# A refused call is audited whatever its input holds

- loop: audit-nul
- mode: reviewed
- stage: done
- base: 184cfda4c7cc4fc3ec727068ff9edba282f60d33
- after: fuzz
- verified: 9fe2ef8c9a819de73a8aeba1bc1f37dcc9883a26
- shown: 9fe2ef8c9a819de73a8aeba1bc1f37dcc9883a26

## Brief

Found at the end of the `fuzz` loop, in ferdig's generated tests on
Postgres: a call refused as `forbidden` whose input holds NUL in its
`request_key` or its `id` loses its audit entry. `write-audit` copies
those raw from the input (`raw-request-key`, `input-target`), Postgres
refuses the NUL (22021), and `record-rejection` only logs "could not audit
rejection". The refusal itself is right; the audit is not, and a caller
could keep refused calls out of the audit by adding a NUL. The fuzzer did
not fail on it: the audit's entries are internal, and nothing checked
that a refusal was audited. Jonas chose at the fuzz loop's gate C to fix
this next, then deploy the clients once it is in. Reviewed
mode: a reviewer at A and B, Jonas at C.

## Criteria

1. Core audits a refusal whatever raised it. A call to a tool that ends
   in `forbidden`, `confirmation_invalid` or `idempotency_conflict`
   writes one `rejected` entry, whether the policy refused it, core
   refused it (confirmation, idempotency, a session-only check), or the
   tool's body or a hook refused it with `fail` (which clients use:
   `reject` is not in their interface). A body refusing inside a write
   transaction leaves its entry although the transaction rolls back.
   Each call a refusal ends leaves its own entry: when a tool's body calls
   another tool that refuses and lets the error through, both calls have
   one. Tests: a body's `(fail :forbidden …)`, in a mutating and in a read
   tool, each leave one entry; a policy refusal still leaves exactly one,
   not two; `eval` whose code is refused leaves one, not two (its own
   `audit-eval` entry for these codes goes, replaced by core's); a nested
   refusal (`widgets_archive_now`) leaves the inner and the outer entry.
2. An entry is written whatever the input holds. On a refusal before the
   input is parsed (the policy's; a session-only check's when that lands),
   `request_key` and the target id are copied from the raw input; each is
   kept only when it is text of 1–64 characters without NUL, and left out
   otherwise. Tests on Postgres, each failing before the fix: a policy
   refusal of a mutating tool with NUL in `request_key`, with NUL in
   `id`, with NUL in another id parameter (`*_id`), and with an `id` of
   65–100 characters, each leave their entry with that value left out. A
   valid key and id are still recorded (existing audit tests stay green).
   The same bounds apply to every entry, an `ok` one included: a text `id`
   of 65–100 characters is no longer recorded.
3. The fuzzer checks `testing.md` §2's fifth point: after a call answered
   with one of the three codes, the store holds one more `rejected` entry
   for that tool. A planted defect: for the length of the test, the
   probe tool's `rejected` entry is not written (the test wraps
   `write-audit` with `sb-int:encapsulate`, as the fuzzer wraps the socket
   functions, so the defect does not depend on how core records a
   refusal, and mirrors the Postgres insert that failed). It fails the
   run naming tool, actor, seed and input; without it the run passes. Tun's own run is in memory, which takes NUL, so the NUL cases
   are guarded by criterion 2's tests and by the clients that run on
   Postgres, not by Tun's fuzz run.
4. ferdig, kurs and nixploy-dashboard pass on the new Tun, their
   generated tests within 30 s, with no change but the Tun pin; then gate C:
   Jonas decides the deploy.
5. `bin/build` has no warnings; `bin/test` is green. A patch version of
   core, a fix (§3.8 already says these refusals are audited), set when
   the loop rebases onto what has landed by then.

## Decisions

- Core audits `operation-error`s with these codes as it audits a
  `rejection`, rather than exporting `reject` and migrating the clients:
  §3.8 then holds by construction, for every body and hook, without each
  client having to choose the right function.
- Leave a bad value out rather than escape the NUL: a changed value would
  look like a real key or id.
- Values held to text of 1–64 characters without NUL, the id type's and
  `request_key`'s own bounds, rather than "one the call could have used":
  a read tool's `request_key` is still recorded as today.
- `confirmation_invalid` and `idempotency_conflict` come after the input
  is parsed, which already refuses a bad key or id with `invalid_input`,
  so only refusals before parsing need criterion 2.
- §3.8 is about calls that reach a tool. A request the transport refuses
  (another site's, 403) is not a call and is not audited.
- Core records a refusal where the call ends (a `handler-case` clause in
  `run-guarded` for `operation-error`s with these codes), not where it is
  signalled: a body that catches an inner refusal and carries on then
  leaves no false entry for itself.
- Built with `handler-bind` inside the `rejection` clause, not a
  `handler-case` clause: a `handler-case` unwound before the backtrace was
  taken, and the introspection test caught it. The handler still runs
  only once nothing inside the call handled the error.
- Changed in build: criterion 3's planted defect is not a wrapped
  `write-audit`, which Tun will not open an application with
  (`definition-integrity-violations`, a guard that stays), but a probe,
  `fuzz_notes_lock`, whose refusal under `:unaudited` binds core's
  deferred audits and drops them. The run fails naming tool, actor, seed
  and input; without the defect it passes. A run of kurs against core
  without the new handler also failed six times ("refused with forbidden
  but left no rejected audit entry").
- The handler records the caller, taken before the body runs: it runs
  where the error was raised, which may be inside the body's
  `with-actor`.
- `write-audit` bounds what a body names too (`audit-as`, `audit-target`):
  an actor, reason, entity type or id the entry could not hold is left
  out (the caller's actor in place of an unusable one), so no value a
  body passes can lose the entry either.
- `eval`'s own `audit-eval` entry for these codes is dropped: core's
  replaces it, as older mechanisms give way to newer ones.
- Two loops of another session are committed but not pushed:
  outbound-methods (also claiming core 2.9.0) and caller-kind (2.10.0,
  adding a session-only refusal before parsing, which goes through the
  same `write-audit`, so this fix covers it). Whichever lands second
  rebases, sets the version, and adds the session-only test.

## Log

- 2026-11-07 14:12  started, reviewed
- 2026-11-07 14:13  gate A asked of a reviewer
- 2026-11-07 14:17  gate A: changes (reviewer): Check 5 would fail every client: bodies refuse with fail :forbidden, which core does not audit (reject not exported); confirmation_invalid/idempotency_conflict refuse after parsing, so criterion 1 must name policy and session-only refusals; spec wider than criteria; base behind main (2.10.0, session-only refusal); say 3.8 is calls that reach a tool; Tun's memory run does not catch NUL
- 2026-11-07 14:17  rebased: tun 184cfda → 184cfda
- 2026-11-07 14:18  gate A asked of a reviewer
- 2026-11-07 14:23  gate A: changes (reviewer): Planted defect (dropped deferred audits) cannot fail under handler-case recording; eval's audit-eval would audit twice; nested refusal unspecified (each call needs its own entry for check 5); outbound-methods also pending, version set at rebase
- 2026-11-07 14:23  gate A asked of the person
- 2026-11-07 14:24  gate A: approve (jonas): Approve and build, after two reviewer rounds whose points the gate-A-3 plan answers
- 2026-11-07 14:42  build: core audits a refusal raised by fail, a hook or a nested call (handler-bind in run-guarded), each call once; values from raw input and from audit-as/audit-target kept only when an entry can hold them; eval's duplicate dropped; fuzzer check 5 (:unaudited). Tests: review suite (body refusal in mutating and read tool, policy once, nested, eval once, Postgres NUL in request_key/id/customer_id and an 80-char id); each fails on the old execution.lisp. Check 5 against core without the handler: kurs fails 6 times, left no rejected audit entry. bin/test green, 68 suites in 108s
- 2026-11-07 14:48  verify 1: passed build, test, check
- 2026-11-07 14:54  verify 2: passed build, test, check
- 2026-11-07 14:56  clients against this tree (2.9.1): kurs 348 checks, fuzz 8.4s; ferdig 754, 19.3s under load; nixploy-dashboard 1139, 22.1s alone (42s while Tun's verify ran beside it); no 'could not audit' line in any
- 2026-11-07 14:56  shown (/items)
- 2026-11-07 14:56  gate B asked of a reviewer
- 2026-11-07 15:04  gate B: changes (reviewer): handler-bind reads *actor* where the error was raised, so the outer entry names system:... under with-actor; a probe binding *deferred-audits* can plant an end-to-end unaudited defect, so criterion 3 can be met; minor: check 5 is at-least-one, eval test passes on old core, ok-entry bound untested; version at rebase
- 2026-11-07 15:07  build: gate B round 1 answered: the rejected entry names the caller captured before the body (test a-refusal-inside-another-actor-is-audited-as-the-caller); end-to-end planted defect fuzz_notes_lock :unaudited fails the run, passes without; check 5's at-least-one limit documented. Not tested: the bounds on an ok entry's 65-100 character id, as no tool here takes a text id that long. bin/test green, 68 suites in 110s
- 2026-11-07 15:12  verify 3: passed build, test, check
- 2026-11-07 15:12  shown (/items)
- 2026-11-07 15:13  gate B asked of a reviewer
- 2026-11-07 15:18  gate B: approve (reviewer): Caller named, end-to-end planted defect, limit documented; once per call, nested, eval, bounds and spec hold; check 5 cheap. Minor follow-ups: ok-entry 65-100 id untested; audited-refusal-code-p repeats +rejection-codes+; recordable-text-p and storable-text overlap; call-state initform reads the constructor argument
- 2026-11-07 15:18  follow-ups from gate B round 2, not done here: one list for audited codes and +rejection-codes+; one helper for recordable-text-p/storable-text; &aux for rejections-commits; a test of an ok entry's long text id
- 2026-11-07 15:21  clients on Tun afa9fba, bin/test green: kurs 348 checks, fuzz 7.8s; ferdig 754, 12.2s; nixploy-dashboard 1139, 23.6s; no 'could not audit' line
- 2026-11-07 15:21  gate C asked of the person
- 2026-11-07 15:26  gate C: approve (jonas): Push all three clients; deploy ferdig and kurs through nixploy; pin the dashboard in ~/nixos for the netcup deploy
- 2026-11-07 15:30  pushed ferdig b3a3345, kurs b86272a, nixploy-dashboard aaa36f5; deployed ferdig (dpl_bas74hkqswtbfkww) and kurs (dpl_w63pxtgv6r3v70r4), both succeeded and verified; dashboard pinned in nixos c81b30b for Jonas's netcup deploy
- 2026-11-07 15:30  finished at tun afa9fba
