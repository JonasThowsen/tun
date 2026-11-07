# Every tool of a client is fuzzed: hostile input never makes it fail or half-write

- loop: fuzz
- mode: reviewed
- stage: done
- base: 14c0124d5d48ae86ee6d38c9b2951cb08788ffb5
- after: client-checks
- verified: e9f40d37b9015b15942cba21727ad832006680a6
- shown: e9f40d37b9015b15942cba21727ad832006680a6

## Brief

The third loop of the programme Jonas approved on 2026-11-06: «We need to
be able to perform fuzz testing, and all other sorts of important test
types that ensure our systems run correctly, and it needs to happen
fast.» Loop 2 put the generated tests in Tun (`define-generated-tests`);
this one adds fuzzing every tool to them. Reviewed mode: a reviewer at
gates A and B, Jonas at gate C.

## Criteria

1. `define-generated-tests` defines
   `generated-every-tool-withstands-fuzzing`, which calls every tool of
   the client's operations as spec/testing.md §2 says: a fresh database in
   memory per tool with the `default` scenario, `admin:fuzz`,
   `employee:fuzz`, `viewer:fuzz` and the scenario's actors, valid, edge
   and hostile inputs from each tool's input schema; a tool that asks for
   confirmation is also called with its token, a wrong one and the token
   with other input.
2. Its checks hold or fail the test: an answer is a result or an error of
   `core.md` §3's codes, never a fault nor `deadline_exceeded`; an error
   leaves every record of every entity that is not `:internal`, settings
   included, as it was; nothing leaves the
   process (tests show a tool that calls another system through each
   handler gets an unreachable system, no job runs, and an attempt to
   connect to another host fails the test); a waiting tool waits no time.
3. A planted defect is found: in Tun's test client, an operation that
   signals an unexpected error for some input, and one that writes before
   it refuses, each make the test fail, naming tool, actor, seed and a
   shrunk input; with the defect removed it passes.
4. Without `TUN_FUZZ_SEED` the seed is the same every run; the same seed
   gives the same calls, records chosen by creation order; the failure
   report's seed replays the failure; `TUN_FUZZ_SEED=random` varies it.
5. Shrinking: a test shows a failing input of many properties and long
   texts shrinks to the one property and short text that cause it.
6. Tun's own suite fuzzes every core and module tool the same way, the
   test clock's, debug and eval tools apart, and passes; anything it finds
   is fixed in Tun, at its cause.
7. ferdig, kurs and nixploy-dashboard pass with it (against this Tun);
   anything it finds in a client is fixed in that client. Each client's
   generated tests stay within 30 s; the times and the number of calls
   are logged.
8. `TUN_FUZZ_CALLS` raises the calls; a deeper run of each client, with
   at least ten times the default, is made once and logged.

## Decisions

- Tun's own engine, in `tun.test-support`: generators from JSON Schema and
  shrinking by dropping and simplifying, so the failure report speaks of
  tools and properties, and no library is added to every client.
- In process, through the tool call path, not HTTP: HTTP's own hostile
  input is the hostile and safety suites' already, and a call in process
  costs microseconds, not milliseconds.
- The seed is fixed in `bin/test` and random only in deep runs: Jonas's
  choice, «Fixed in bin/test, random in deep runs», so a commit goes red
  only for what it changed.
- One fresh database in memory per tool: the tool's calls share it, so a
  call sees what earlier ones made, and a failure replays from it. That
  the application runs on Postgres is checked by §1's third test.
- Excluded Tun tools: `clock_get`/`clock_set` move the clock and run due
  jobs, `debug_…` sleep or burn CPU on purpose, `eval` runs text as code;
  each exists only for tests or debugging.
- Records compared through the entities the application defines, not the
  database file: the audit and request records may grow on a refusal, as
  `core.md` §3 says they do for some.
- A fault found in Tun or a client is fixed in this loop when it is small.
  For a larger one the builder stops and asks Jonas (his choice, «Ask me
  each time»): fix it now, or a known fault with its own item and loop.
  The test is never weakened to pass.

## Log

- 2026-11-07 11:15  started, reviewed
- 2026-11-07 11:16  gate A asked of a reviewer
- 2026-11-07 11:21  gate A: changes (reviewer): Confirm tools must be confirmed with their token; push and Resend mail and clock_set's due jobs bypass the two handlers; say which Tun tools (clock, debug, eval) are out; actors disagree; a time-based count and random ids break replay; fresh database per what; check 2 by :internal entities; two decisions for Jonas (seed default, a large fault)
- 2026-11-07 11:21  gate A asked of a reviewer
- 2026-11-07 11:23  gate A: approve (reviewer): Earlier points answered; Jonas's two decisions recorded; criteria decidable. Fixed after: section references, settings in criterion 2, test clock and insertion order for replay, a fixed call count. Risks: a real hook below drakma/usocket for connections, planted defects must be switchable so Tun's suite stays green
- 2026-11-07 12:49  build: Tun bin/test green, 68 suites in 112s; fuzz-core 46 tools 1840 calls, fuzz-modules 121 tools 5062 calls (seed 20261107, 8 calls); found and fixed: day past 9999-12-31 a fault (inventory_forecast, inventory_shortages), blank required text reached bodies, NUL in text a Postgres fault
- 2026-11-07 12:49  build: kurs green, generated tests 9.7s, fuzz 14 tools 560 calls in 7.0s
- 2026-11-07 12:49  build: ferdig green (Postgres), generated tests 11.6s, fuzz 31 tools 1240 calls in 10.6s
- 2026-11-07 12:49  build: nixploy-dashboard green (Postgres), generated tests 22.1s, fuzz 49 tools 1960 calls in 20.6s
- 2026-11-07 12:49  build: deep runs, TUN_FUZZ_CALLS=80, TUN_FUZZ_SEED=random: kurs seed 1000797856 5600 calls 34.4s, ferdig seed 187135453 12400 calls 70.1s, nixploy-dashboard seed 1125366218 19600 calls 139.6s, Tun's tools seed 1825738497 69140 calls 144.5s: no failure
- 2026-11-07 12:56  verify 1: passed build, test, check
- 2026-11-07 12:56  shown (/items)
- 2026-11-07 12:57  gate B asked of a reviewer
- 2026-11-07 13:05  gate B: changes (reviewer): date-add-months still faults below 1900 (encode before kept-date); spec's blank-text rule wider than code (untrimmed required text); dead record-ref branch in other-input; hash cache keyed on whole-second write date; process-wide hook needs a docstring note; no final newline in postgres.lisp; rebase onto 2.8.2 -> 2.9.0. Noted for later loops: :internal entities (stock, jobs, mail) escape check 2
- 2026-11-07 13:06  build: gate B round 1 answered: date-add-months refuses a year outside 1900-9999 before encoding (test below 1900); spec says trimmed text only, :trim nil kept as sent; dead record-ref branch removed from other-input; source hash cache keyed on write date and length; process-wide connection hook documented; rebased onto origin/main
- 2026-11-07 13:12  verify 2: failed test
- 2026-11-07 13:18  verify 3: passed build, test, check
- 2026-11-07 13:19  shown (/items)
- 2026-11-07 13:19  gate B asked of a reviewer
- 2026-11-07 13:26  gate B: approve (reviewer): Round 1 answered (date-add-months below 1900, spec trimmed text, dead branch, cache key, hook docs, newline); kernel changes sound; criteria 1-8 met; verify 3 green. Notes: rebase onto origin/main (core 2.8.2 now pushed) keeping 2.9.0; other-input may break a pattern and get invalid_input on a confirm tool (latent); spec sentence should say trimmed text with no minimum
- 2026-11-07 13:26  rebased: tun 7977a7e → 14c0124
- 2026-11-07 13:27  build: rebased onto 14c0124 (core 2.8.2), version kept 2.9.0; a confirm tool's other input may be refused invalid_input before the token is read (core.md 3.6); spec: trimmed text with no minimum length
- 2026-11-07 13:33  verify 4: failed test
- 2026-11-07 13:33  verify 4: preview suite failed on a shared machine: another session's preview took port 4201, and its socket directory, 2 s before the test's preview did (a-start-that-fails-leaves-no-claim); unrelated to this change, run again
- 2026-11-07 13:39  verify 5: failed test
- 2026-11-07 13:43  build: verify 4 and 5 failed in preview: a test's preview chose a port whose socket directory another state directory's preview Postgres held (it listens on no TCP port, and its claim is in another state home). Fixed: choose-port skips a port whose socket directory a running Postgres holds, --port refuses it; spec/preview.md; test a-port-whose-socket-directory-a-running-database-holds-is-skipped
- 2026-11-07 13:49  verify 6: passed build, test, check
- 2026-11-07 13:49  shown (/items)
- 2026-11-07 13:49  gate B asked of a reviewer
- 2026-11-07 13:53  gate B: changes (reviewer): Code sound, rebase lost nothing, call-problem and socket check correct; but spec/testing.md Confirmation still says other input must be confirmation_invalid (code also takes invalid_input), and spec/preview.md --port bullet omits the held-socket-directory refusal. Notes: initdb gap remains a rarer race; unreadable socket lock counts as free
- 2026-11-07 13:53  build: gate B round 3 answered: spec/testing.md Confirmation names invalid_input for other input refused before the token is read; spec/preview.md --port bullet names the held socket directory
- 2026-11-07 13:59  verify 7: passed build, test, check
- 2026-11-07 13:59  shown (/items)
- 2026-11-07 13:59  gate B asked of a reviewer
- 2026-11-07 14:00  gate B: approve (jonas): Approve and push, after the reviewer's two change rounds were answered; verify 7 green
- 2026-11-07 14:03  clients on Tun fd65a0a, bin/test green: kurs 348 checks, fuzz 15 tools 600 calls 7.2s; ferdig 754, 31 tools 1240 calls 11.5s; nixploy-dashboard 1139, 49 tools 1960 calls 22.1s. Seen in ferdig's log: a rejection whose input holds NUL is not audited on Postgres (could not audit rejection of people_invite, 22021); the refusal is right, the audit entry is lost; for a follow-up loop
- 2026-11-07 14:03  gate C asked of the person
- 2026-11-07 14:11  gate C: approve (jonas): Push all three clients, no deploy; fix the NUL audit gap in a short loop next, deploy after it
- 2026-11-07 14:11  pushed ferdig 6807954, kurs 69a5324, nixploy-dashboard f2bcb2b on Tun fd65a0a; not deployed: Jonas chose to deploy after the audit loop
- 2026-11-07 14:11  finished at tun fd65a0a
