# bin/test runs its suites in parallel: the full run in under 2.5 minutes

- loop: fast-tests
- mode: reviewed
- stage: done
- base: 35a564ff81010f71f62be82d07e1e0648fc86eb7
- verified: e9b491bd4dfc7ab301af55473edf2ed3c64eb7fd
- shown: e9b491bd4dfc7ab301af55473edf2ed3c64eb7fd

## Brief

Jonas, 2026-11-06: «in order for Tun to be reliable at the client level,
the generated tests need to be fast and reliable ... We need to be able to
perform fuzz testing, and all other sorts of important test types that
ensure our systems run correctly, and it needs to happen fast. Make that
happen.» He approved a programme of six loops, this one first: the full
`bin/test` takes about 11 minutes, every suite one after another, on a
machine with 12 processors. He chose the reviewed mode: a reviewer decides
gates A and B, he decides gate C.

Measured on 35a564f, the core suites one after another: 596 s, of which
safety 108 s, core-migration 69 s, hostile 66 s, waiting 57 s, loop 36 s,
programs 28 s and files 22 s; the other 50 take seconds. The tooling checks
take 25 s, test-client 15 s with its compile, compiling core 15 s.

## Criteria

1. `bin/test` compiles core, its tests and every client system of the run
   once, strictly, then runs every child suite of `core`, each client suite
   and each tooling check as its own process, at most `TUN_TEST_JOBS` at
   once (default: processors). No suite process compiles; the tooling
   checks compile only into directories of their own, never the fasls the
   suites load.
2. Longest first, by `.build/test/times` from the last run; unknown first.
3. One line per suite as it ends (`ok`/`FAIL`, name, seconds); every
   suite runs whatever another's result; failed suites' output printed in
   full at the end; exit 1 when one failed, 0 otherwise; logs in
   `.build/test/`.
4. A test placed directly in `core` (settings) moves into a child suite;
   the run fails, naming the test, when `core` has one outside its children.
5. Every place a test takes a port holds it until it is done: a test
   server binds port 0 and reads the port it got, or retries on another
   when the one it chose was taken; a port handed to a child process is
   retried the same way. No test relies on a port staying unused: the one
   that needs a refused connection holds a bound socket that does not
   listen.
5a. `bin/with-postgres` lets the parallel suites connect at once
   (`max_connections` 300), and a run shows no "too many clients" error.
6. A deliberately failing test in one suite fails the run with exit 1,
   shows that suite's output, and the other suites still report `ok`.
7. Three full runs in a row on netcup-dev pass with every suite in
   parallel, each under 150 s wall clock, with each run's slowest suite and
   its time in the log, so the margin shows. `TUN_TEST_SUITES` and `--only` work
   as before.

## Decisions

- Processes, not threads: suites bind globals such as `*app*` and the
  clock, and a process is the isolation they were written for.
- One compile, loaded by every process from the fasls, so a run costs one
  compile and not one per suite.
- Every suite runs even after a failure: a reviewer sees every failure of a
  change at once.
- The slow suites: under load safety took up to 125 s and the run
  139–146 s, so, as gate A's reviewer advised, the tests that measure in a
  default-heap child left safety and hostile for suites of their own
  (default-heap-files, default-heap-bodies, default-heap-hostile).
  core-migration's helper read the whole Postgres schema twice per table,
  opening a store each time; it now reads it once (68 s to 22 s). The
  tests themselves are unchanged.
- Run alone, two tests showed what they had leaned on: module-system read
  `application`'s class precedence list without finalizing the class, and
  hostile's trickling-bodies test took its 3 s bound after joining senders
  whose connections close after the 2 s drain. Both are fixed at the root.
- group-commit's `gc-a-batch-sqlite-rolled-back-is-not-joined-again`
  failed once in a heavily loaded full run and passed 36 of 36 in a stress
  run; the cause is not found. It is noted for a loop of its own, not
  hidden here.
- Each process loads the fasls (3.5 s idle, about 8 s on a busy machine,
  64 times). A saved image would start in 0.2 s; that is a later loop if
  the margin matters.
- Clients' `bin/test` (template) is unchanged: their suites take seconds.

## Log

- 2026-11-07 08:33  started, reviewed
- 2026-11-07 08:34  gate A asked of a reviewer
- 2026-11-07 08:35  gate A: changes (reviewer): Criterion 5 too narrow (free-port used directly in many suites; one relies on a port staying closed); 'no process compiles' contradicts the tooling checks and clients; spec should say a test outside core's children fails the run; risks: Postgres connections, timing margin, fasls written by bin/repl, fixed paths
- 2026-11-07 08:36  gate A asked of a reviewer
- 2026-11-07 08:37  gate A: approve (reviewer): Criteria answer the earlier review and are decidable; spec agrees. Risks for build: bin/repl and lint write the shared .build/fasl; finish the one compile (third-party too) before fanning out; if safety pushes past 150 s, split it rather than lower jobs or target; suites may depend on state an earlier one left; a limited run merges into .build/test/times
- 2026-11-07 09:49  verify 1: passed build, test, check
- 2026-11-07 09:49  shown (/items)
- 2026-11-07 09:49  gate B asked of a reviewer
- 2026-11-07 09:55  gate B: changes (reviewer): Code and spec right; criterion 7 (three consecutive full runs with times and slowest suite) and criterion 6 (a deliberately failing core test) not shown in the record. Optional: the interrupt trap leaves a check's grandchildren running and exits 130 on TERM
- 2026-11-07 10:17  verify 2: passed build, test, check
- 2026-11-07 10:23  criterion 6: a deliberate failing test in rank, TUN_TEST_SUITES=core bin/test: exit 1, FAIL rank with its log (this test fails on purpose), 62 other suites ok, == 1 failed: rank; the test removed after
- 2026-11-07 10:23  a first set of three runs: run 2 failed in waiting (a-wait-outlasts-two-rechecks-in-real-time, 11 <= elapsed <= 14): the test took its start after starting the thread that archives at 11 s, so a stall between them measured under 11 s. Start now taken first, and the check prints the elapsed time
- 2026-11-07 10:23  stopping bin/test (TERM to run-suites) mid-run stopped all 14 suite processes, none left: each job runs in a process group of its own
- 2026-11-07 10:23  criterion 7, three full runs in a row after verify 2: 116 s, 115 s, 114 s wall, all exit 0; slowest waiting 65.9 s, 67.7 s, 66.3 s; no too-many-clients error in any log
- 2026-11-07 10:23  shown (/items)
- 2026-11-07 10:24  gate B asked of a reviewer
- 2026-11-07 10:25  gate B: approve (reviewer): Worktree equals verified tree; criteria 6 and 7 shown in the Log (three runs 114-116 s, slowest waiting ~66 s); the earlier waiting failure fixed at its cause; interrupt trap stops process groups; group-commit flake recorded for its own loop
- 2026-11-07 10:26  finished at tun 5b2d3d1
