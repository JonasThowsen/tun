# tun loop records estimates, cost and actuals

- loop: loop-metrics
- mode: reviewed
- stage: build
- base: 932792b188947434b781cacc93930e68949b179c
- item: sak_817by05z6pvdzsmt

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
   or likely > worst, a REF or TAG with a space or comma, and an estimate
   of a loop that is done (loop-tests).
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
- Core version: the next free minor at merge (main is 2.15.0 at the start).

## Log

- 2026-11-08 15:51  started, reviewed
- 2026-11-08 15:53  gate A asked of a reviewer
- 2026-11-08 17:48  gate A: approve (jonas): «ja»
