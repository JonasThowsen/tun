# tun loop records estimates, cost and actuals

- loop: loop-metrics
- mode: reviewed
- stage: done
- base: 932792b188947434b781cacc93930e68949b179c
- item: sak_817by05z6pvdzsmt
- estimate: 2h 4h 8h
- like: tun/client-subdir tun/caller-kind tun/outbound-methods
- tags: kind:cli module:loop
- verified: 90c84a6680eac2ec2871d76647dc533c5614b1b4
- shown: 90c84a6680eac2ec2871d76647dc533c5614b1b4

## Brief

Factory 6, step 1 (Ferdig sak_hn50ds8wx9fw3h84; this loop's item
sak_817by05z6pvdzsmt). Jonas, 2026-11-07, from «The Pragmatic Programmer»:
estimates get better when broken into smaller ones and compared with
similar earlier work, and every project the factory makes needs one that
improves with each system built. On what to estimate: «I am thinking the
total time is the most important, but Token cost and general cost is also
important to measure optimizations over time.» On the factory, 2026-11-08:
the measure is how often, and for how long, a person has to step in.

The 71 loop records so far time every stage, but say nothing of an
estimate made beforehand, of tokens or cost, of the kind of change, of the
time before `tun loop start`, or of a person's own minutes at a gate. The
orchestrator and the dashboard need the actuals in a form they can read.

## Criteria

1. `tun loop estimate --best 30m --likely 1h --worst 3h --like ferdig/i18n --tag kind:cli`
   sets the fields `estimate: 30m 1h 3h`, `like` and `tags`, and logs
   `estimated 30m 1h 3h at STAGE, like ferdig/i18n` (loop-tests).
2. A DURATION such as `1h30m` reads as 90 minutes and writes back as
   `1h30m`; `90`, `1.5h` and `0m` are usage errors, and so is best > likely
   or likely > worst, and a REF or TAG with a space or comma; an estimate
   of a loop that is done is a step out of order, exit 1 (loop-tests).
3. `tun loop cost --tokens-in 1000 --usd 0.25`, then `--tokens-in 500
   --tokens-out 20 --usd 0.5 --minutes 12`, leave the fields at 1500, 20,
   0.75 and 12; `cost` with no value is a usage error (loop-tests).
4. `tun loop decide A approve --by jonas --why "«ja»" --minutes 3` logs
   `gate A: approve (jonas) [3 min]: «ja»`; who decided, and who decides
   the next gate, are read as before (loop-tests).
5. The actuals of a record with a known log give total, waiting_person and
   waiting_reviewer by who decided, working, the first and latest estimate
   with the stage each was made at, within_estimate, ratio, verify rounds
   and failed ones, changes at each gate, interventions (gates a person
   decided and resumes) and cost (loop-tests).
6. A record from before this loop, such as an existing one in loops/, has
   actuals with `null` for estimate, ratio, within_estimate and cost
   (loop-tests).
7. `tun loop finish` writes `## Actuals` before `## Log` with one JSON
   object equal to `tun loop actuals NAME --json`, and a `tun loop log`
   after it still goes into Log; the tracker's `finish` event carries the
   same actuals, and `estimate` and `cost` are tracker events (loop-tests).
8. `tun loop actuals --json` without NAME prints an array of every loop at
   the top, oldest first; `tun loop status --json` has `"actuals"` (loop-tests).
9. In a client made by `tun new`, the loop bin/test-cli runs is estimated,
   costed and finished, and its record ends with Actuals before Log
   (bin/test-cli).
10. spec/loop.md §6.2, docs/loop.md (when to estimate, which past loops to
    compare with, reporting cost) and `tun --help` describe it.

## Decisions

- The estimate is of the loop's total time, start to end with the waiting,
  since that is what a customer is promised (Jonas, 2026-11-07); the
  actuals split it into waiting for a person, waiting for a reviewer and
  working, so an estimate can be judged on each.
- Re-estimating is allowed at any stage before done and kept in the log;
  the actuals compare with the first estimate, the one made before the
  work, and give the latest beside it.
- `--like` takes free names (`REPOSITORY/LOOP`) and is not checked against
  records, since the loops compared with are often in other repositories.
- Cost is reported, not measured: Tun has no harness of its own, so the
  agent (or the orchestrator running `claude -p --output-format json`)
  passes the numbers. No parser of one harness's output goes into Tun.
- Waiting is split by who decided, not by who was asked, so a reviewer's
  gate the person answers counts as the person's time.
- The Actuals section is regenerated whenever a done loop is saved, so a
  cost reported after finish is in it; it sits before Log, since Log is
  appended to.
- `interventions` counts gate decisions by a person and resumes: the
  factory's measure of how often a person stepped in.
- No refusal at gate A without an estimate: older procedures and clients
  keep working. `next-step` at `brief` names the estimate instead.
- This loop itself: mode reviewed, gate A asked of Jonas, gate B by a
  reviewer agent (Jonas agreed 2026-11-08 that a reviewer may take the
  gates of internal work). Its own estimate is recorded with the new
  command once built: best 2h, likely 4h, worst 8h, like tun/client-subdir,
  tun/outbound-methods, tun/caller-kind.
- Core version: the next free minor at merge: 2.17.0, since another loop took 2.16.0 meanwhile.

## Actuals

```json
{"loop":"loop-metrics","title":"tun loop records estimates, cost and actuals","repository":"tun","mode":"reviewed","stage":"done","item":"sak_817by05z6pvdzsmt","tags":["kind:cli","module:loop"],"like":["tun/client-subdir","tun/caller-kind","tun/outbound-methods"],"started":"2026-11-08 15:51","ended":"2026-11-09 19:56","minutes":{"total":1685,"waiting_person":115,"waiting_reviewer":6,"working":1564,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":120,"likely":240,"worst":480,"at":"build"},"latest_estimate":{"best":120,"likely":240,"worst":480,"at":"build"},"within_estimate":false,"ratio":7.02,"verify":{"rounds":3,"failed":1},"changes":{"A":0,"B":1,"C":0},"interventions":1,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-08 15:51  started, reviewed
- 2026-11-08 15:53  gate A asked of a reviewer
- 2026-11-08 17:48  gate A: approve (jonas): «ja»
- 2026-11-08 17:49  estimated 2h 4h 8h at build, like tun/client-subdir tun/caller-kind tun/outbound-methods
- 2026-11-08 17:55  verify 1: failed test
- 2026-11-08 17:56  verify 1: the preview suite's test clashed with another session's preview on port 4201 (its Postgres socket lock in /run/user/1000/tun-preview-4201); the suite passes alone
- 2026-11-08 18:04  verify 2: passed build, test, check
- 2026-11-08 18:05  shown (/)
- 2026-11-08 18:05  gate B asked of a reviewer
- 2026-11-08 18:09  gate B: changes (reviewer)
  I reviewed this by reading the code only. Running `nix` and `bin/tun` needs approval this non-interactive session can't get, so the behaviour described below is traced from the source, not observed.
  
  **What is right**
  - All three steps in `verify.txt` passed (round 2). Round 1's failure is logged as a preview port clash.
  - The commit matches the packet's diff, and the core version is raised in both places.
  - `spec/loop.md` §6.2, `docs/loop.md` and `tun --help` cover the change (criterion 10). The spec's tracker table matches the events sent.
  - Criteria 1, 3, 4, 6, 7 and 8 have tests that would fail without the change. The `decisions` regex still reads `(jonas) [3 min]`, so who decides the next gate is unaffected.
  - Actuals are computed correctly for the known log, and the Actuals section is rewritten in place when a record is saved again.
  - The screenshots show only the showcase home page, which is expected for a CLI-only change.
  
  **Changes**
  
  1. **Criterion 9 has no evidence.** It names `bin/test-cli` as its check, but that is not a verify step: `verify.txt` shows only build, test and check, and the record's log never mentions it. Earlier loops log it when run by hand (`loops/loop-links.md:58`, `loops/client-subdir.md:118`). The new steps at `bin/test-cli:401-418` include a Python assertion on the JSON that nothing shows has run. Run it on this tree and record the result with `tun loop log`.
  
  2. **A free-text log line can break the record** (`src/cli/loop.lisp:671-672`). `tun loop log "estimated two more hours at build"` matches `^estimated (\S+) (\S+) (\S+) at`, and `parse-duration` then refuses `two`.
     - After that, `status` exits 2, and so does `actuals` without NAME, for every loop at that top.
     - `finish`, or any save of a done loop, fails the same way, and the orchestrator and dashboard read these commands.
     - Fix: match only duration-shaped tokens, and add a test with such a line.
  
  3. **`format-amount` can write a value it cannot read back** (`src/cli/loop.lisp:591`).
     - A non-integer amount that rounds to six zero decimals is written as `0.` or `1.`, for example `--usd 0.0000001`. A total with float noise such as `1.0000000000000002` does the same, and that is the kind of number a harness reports.
     - `parse-amount`'s regex refuses that value, so `status`, `actuals` and `finish` all fail on the record.
     - Fix: trim the trailing `.` as well, and add a test.
  
  4. **Criterion 5 is only partly tested.** `*known-log*` (`tests/loop-tests.lisp:771-783`) has no `resumed (…)` line, and neither does the end-to-end test. Removing the resume count would leave the suite green, yet resumes are half of the factory's measure in the brief. Add a resume to the known log and raise the expected `interventions` at `tests/loop-tests.lisp:812`.
  
  5. **Criterion 2 does not match what is built.**
     - It says an estimate of a done loop is a usage error, but the code uses `fail-step` and the test expects exit 1 (`tests/loop-tests.lisp:887`). The code follows `spec/loop.md:303` (a step out of order exits 1), so correct the criterion's wording in the record.
     - The criterion also lists likely > worst, a REF with a space, and a bad TAG. The tests cover only best > likely and `a,b` on `--like`, so add those cases.
  
  **A question for Jonas, not blocking**
  Time a loop sits `stuck` waiting for a person's `resume` counts as `working`, because `waiting_person` covers gates only. The brief's measure is "how often, and for how long, a person has to step in", so this understates it. The spec approved at gate A defines it this way, and actuals are recomputed from the log, so it can change later without losing data.
- 2026-11-09 19:46  verify 4: passed build, test, check
- 2026-11-09 19:52  bin/test-cli passed on afdf646: tun new, build, test, image, restore, serve, preview, check, loop (with estimate, cost and Actuals), tun add and tun update
- 2026-11-09 19:52  shown (/)
- 2026-11-09 19:53  gate B asked of a reviewer
- 2026-11-09 19:55  gate B: approve (reviewer)
  **Gate B review of loop-metrics: approve.** All five requested changes from the first review are addressed, and I found nothing new that blocks.
  
  I reviewed by reading the code and comparing git trees. `nix` needs approval this session can't get, so I did not run `bin/tun` or the suites. Behaviour below is traced from the source.
  
  **The first review's changes**
  1. **Criterion 9:** the log records `bin/test-cli` passing on afdf646, including estimate, cost and Actuals. That line is the builder's own, not a `verify.txt` step, but it follows earlier practice and names the commit under review.
  2. **Free-text log lines:** the regex in `loop-actuals` now needs three duration-shaped tokens, and a `handler-case` covers ones like `0m`. `*known-log*` includes `estimated two more hours at build`.
  3. **`format-amount`:** a value that rounds to a whole number now takes the integer path, and the `.` is trimmed. `an-amount-is-written-so-it-reads-back` covers both failing inputs from the first review.
  4. **Resumes:** the known log has a `resumed (jonas)` line and expects 3 interventions. Its format matches what `resume` writes (`src/cli/loop.lisp:870`).
  5. **Criterion 2:** the wording now says exit 1 for a done loop, and the tests add likely > worst, a REF with a space and a bad TAG.
  
  **The rest**
  - **Criteria:** each of 1–9 has a test that would fail without the change, and 10 is met in `spec/loop.md` §6.2, `docs/loop.md` and `tun --help`.
  - **Log parsing:** the patterns the actuals read match the lines the code writes for gates, verify, finish and resume. All 42 done records have a `finished at` line, so none reads as open.
  - **Tree:** the verified tree `90c84a6` differs from afdf646 only under `loops/`, which the loop's tree leaves out by design, so the shown code is HEAD.
  - **Verification:** build, test and check all passed in round 4, and no browser check in `checks/` records a failure.
  - **Screenshots:** the report lists only the showcase home page at both widths, and I didn't open them. That is expected for a CLI-only change.
  - **Code:** it follows `AGENTS.md`, its comments explain why rather than narrate history, and the core version is raised in both places.
  
  **Not blocking**
  - A `tun loop log` line that mimics a generated one, such as `finished at the office`, can skew the numbers until the real line follows. It can no longer make a record unreadable.
  - The first review's question for Jonas is still open: time a loop sits `stuck` waiting for a `resume` counts as `working`. It can change later without losing data, because actuals are recomputed from the log.
- 2026-11-09 19:56  cost: not reported; this session's harness gives the agent no token or cost figures (the factory's claude -p runs will)
- 2026-11-09 19:56  finished at tun 97b9046
