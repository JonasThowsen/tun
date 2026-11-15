# Tun's speed tests give the same verdict on a loaded machine

- loop: test-timing
- mode: reviewed
- stage: ship
- base: baa99df1e5bf20ce6627e99b5e1ddcb34a65f2e1
- item: sak_tm3r96p23ezpkxqn
- estimate: 1h30m 3h 5h
- like: tun/search-reads tun/form-nits
- tags: kind:tooling core
- verified: cfd0bcd9235d361f210cf5fa7300831b9afd80b2
- shown: cfd0bcd9235d361f210cf5fa7300831b9afd80b2

## Brief

Ferdig sak_tm3r96p23ezpkxqn («test-timing: Tun's speed tests give the
same verdict on a loaded machine»), brought by the factory's
orchestrator on 2026-11-15. From the item: «Tun's tests that pin a speed
(the search's every-kind limits on Postgres and in memory, the orders'
list limit, Markdown's proportional-time test, the fuzz deadline, a page
load in a browser check) fail when another suite loads the machine and
pass alone. The last three loops lost verify rounds to it: search-near
three rounds, ui-motion three rounds (about an hour), ui-choice one. A
builder cannot tell a real slowdown from a neighbour's suite.» The loop
is to make «the suite's verdict on a speed test not depend on what else
the machine is doing, and a real slowdown still fails», proven «by
running the speed tests under a made load and with a planted slowdown».

The orchestrator's brief adds what the last loops met (`search-near`,
`ui-motion`, `ui-choice`, `search-reads`, `ui-nits`): the search's
every-kind limit of 90 ms (Postgres medians of 94 to 259 ms at a load
average of 17 to 59, about 35 to 56 ms alone), also in memory; the
orders' list limit (50 ms; 50.0 and 52 ms more under load); Markdown's
proportional-time test; the fuzz test `a-day-past-the-last-date`
(`deadline_exceeded`); a browser check's page load over 30 s
(ui-fields); and the builders' workarounds, `TUN_TEST_JOBS=3` and
waiting for the load to drop. It asks: find every test and check that
asserts a duration or a deadline and list them here; decide the method
and write it in the spec before gate A, weighing a serial phase after
`bin/test`'s parallel run, the processor time of what is measured, a
failing measurement repeated alone with the load in the failure, a limit
against a calibration measured in the same moment, and a functional
test's deadline that should not be a speed limit at all. No limit is
loosened to hide a slowdown, and one helper carries the method, written
where a builder writing a test reads it, and in `docs/client-api.md` if
clients' suites use the same helper. Its criteria: every speed assertion
through the one helper, with a test that scans the sources; the same
verdict under a made load as on a quiet machine, five runs in a row,
with the numbers; a planted slowdown that fails loaded and quiet; a
failure naming the value, the limit and the load; `bin/test`'s time
grown by no more than a stated amount; what the browser checks that
waited on a fixed time or a 30 s page load do now; core 2.39.0 with the
five clients unchanged, and how tun-erp's own speed tests (its search
bound of 100 ms, the invoices filter) would move onto the helper,
without changing tun-erp.

## Criteria

1. **One helper.** `tests/timing.lisp`, in `tun-test-support`, is the
   one test source that reads a clock. It exports `is-fast`, which
   asserts a speed, `is-within-seconds`, which asserts when something
   happened, `measure-speed`, a speed measured without asserting (a base
   for a limit relative to it), and a stopwatch (`start-stopwatch`,
   `stop-stopwatch`, `lap-stopwatch`, `stopwatch-seconds`,
   `stopwatch-past-p`) for waits and reports, `with-deadline-lifted`
   (criterion 6), and `over-limit-p` and `measurement-milliseconds`
   (criterion 4). Every test and helper of
   the inventory below uses them. The test
   `only-the-timing-helper-reads-the-clock` reads every Lisp source of
   Tun's test systems (`tun/tests`, `tun-test-support`,
   `test-client/tests`) and fails, naming the file and the line, on a
   clock read (`get-internal-real-time`, `get-internal-run-time`,
   `clock-gettime`, `get-time-of-day`, `unix-gettimeofday`) outside the
   helper, and on a stopwatch's seconds inside a comparison or an
   assertion; given a planted source with each of these, it names each.
   (test)
2. **Speed is processor time.** `is-fast` runs its body a number of
   times (nine by default) and compares the median of the processor
   time it took, in this process (every thread) and in the Postgres
   server processes serving the test application's database, with the
   limit; the wall time is printed beside it but decides nothing. Tests
   pin that a body that only sleeps for 200 ms measures under 20 ms of
   processor time and at least 200 ms of wall time; that one that
   computes for 100 ms measures more than 5 ms and no more than its wall
   time and 5 ms (two clocks read a moment apart); and that a sort the Postgres server does is counted, most of
   it as the server's. (test)
3. **The same verdict under load.** With `scripts/make-load` running
   (twice as many busy processes as processors, and as many Postgres
   sessions as processors sorting on the suites' server), the suites
   with speed tests (`search`, `generated-choice`, `markdown`, `graphs`,
   `review2`, `hostile`, `pressure`, `timing`) and those whose functional
   tests met a deadline under load (`fuzz`, `files`) pass five runs in a
   row, run at once as `bin/test` runs them, as they do without it; the
   Log holds the speed tests' medians, loaded and not, with the load
   averages. The suites of when-tests (`programs`, `outbound`, `waiting`,
   `communication`, `slice1-review`, `slice3-review`,
   `slice3-review-round3`, `safety`, `loop`) run in the same proof runs
   and their verdicts are in the Log; they stay wall time and are not
   held to this criterion (Decisions). (proof run, Log)
4. **A planted slowdown fails.** The test-only switch
   `TUN_TEST_PLANT=slow-search` makes the test application's search do
   the work of every contributor three times (Tun refuses to serve once
   a kernel function such as `search-match` is wrapped, so the plant is
   in the test's own search feature); with it, the search's
   every-kind test fails, on a quiet machine and under
   `scripts/make-load`, both in the Log. In the suite, the every-kind
   test also measures one of its searches («nordmann») in memory
   unplanted, then with the search's work done as many times as brings
   it to one and a half times the limit as measured in that moment (at
   least three), and checks that `is-fast` would fail it
   (`over-limit-p`). (test, proof run, Log)
5. **A failure says why.** A failed `is-fast` names what was measured,
   the median processor time, the limit, the wall time, the load
   average and the processor count; a failed `is-within-seconds` names
   the seconds, the bounds, the load average and the processor count.
   A test checks both messages. (test)
6. **What is not a speed limit is not one.** `with-deadline-lifted`
   (the helper's) sets the operation's deadline to ten minutes around a
   test about something else; `a-day-past-the-last-date` (a refusal) and
   `files`' `sizes-are-bounded-per-file-per-call-and-per-record` and
   `a-file-is-read-and-sent-a-part-at-a-time` (files of 10 MiB, which
   ran past the 10 s deadline under the made load) use it. The tests of
   when a mechanism acts (deadlines, timeouts, a call not waiting for a
   slow provider) keep wall time and their bounds, through
   `is-within-seconds`, whose stopwatch reads the clock the kernel's
   deadlines read. (test, inventory)
7. **No limit loosened.** Every limit of the inventory keeps its number
   (90 ms, 100 ms, 50 ms, 1 s, eight times plus 20 ms, 0.5 s); the
   processor time of work in one thread is never more than its wall
   time, so no test passes now that would have passed only with more
   room. (inventory, diff)
8. **`bin/test`'s time.** On this machine, `bin/test` on this tree
   takes no more than 15 s longer than on the base, measured at about
   the same load; both times in the Log. (Log)
9. **Browser checks.** `scripts/tun_check.py` gives each page a default
   timeout of 120 s for a navigation and for any wait without a timeout
   of its own, in place of Playwright's 30 s: a page that takes 31 s
   to load on a loaded machine is waited for, and one that never loads
   still fails. A check's own timeouts, which say how soon something
   must happen, and the fixed waits for a transition are unchanged and
   listed in the record with what each does. (`scripts/tun_check.py`,
   verify's checks, inventory)
10. **Where a builder reads it.** `spec/tooling.md` gets «Speed and
    time in tests», the method and the rules; `reference/pitfalls.md`
    a rule pointing to it; `docs/client-api.md` the helper for clients'
    suites. The core is 2.39.0 (or the next free minor); `bin/test` and
    the browser checks are green; the five clients compile and pass
    unchanged at their `origin/main`. (verify, client runs)
11. **tun-erp's own speed tests.** The section «Clients» below shows
    tun-erp's search bound of 100 ms (`tests/search.lisp`, at its
    `origin/main`), its invoices' «Customer» filter test (150 ms, and 100
    ms more than the list without a find, in its `form-alerts` worktree,
    not yet on its `origin/main`) and its `within-seconds` (a hanging
    accounting or payment call ends at its deadline within 3 s) written
    with `is-fast`, `measure-speed` and `is-within-seconds`; tun-erp is
    not changed. (record)

## Decisions

- **Processor time, not a calibration, a serial phase or a repeat.**
  Measured on this machine before deciding (search suite's every-kind
  search, 2000 records of each kind, medians of nine; the Log has the
  numbers): at a load average of 20, Postgres medians of 37 to 69 ms
  wall and 39 to 70 ms of processor time (this process and the
  database's server processes); under `scripts/make-load` at a load of
  58 to 70, 289 to 526 ms wall but 51 to 67 ms of processor time. In
  memory, 22 to 45 ms wall at 20 against 51 to 311 ms at 60, with
  processor time 22 to 42 and 25 to 44 ms. A calibration loop timed
  beside each run grew 1.7 to 10 times under the made load, and a
  query's wall time divided by it moved by up to a third (Postgres 2.2
  to 4.1 at 20, 2.2 to 4.7 at 60), where processor time moved by up to
  a fifth; a limit scaled by it also needs a quiet figure for each
  machine, which processor time does not. A serial phase removes Tun's own
  suites but not another builder's, which is the load the loops met,
  and adds its time to every run. A repeat waits for luck. Processor
  time is what the code costs, whoever else runs.
- **What processor time does not see.** A slowdown that is waiting, not
  work (a sleep, a lock, a round trip to a server that does nothing),
  costs no processor time. Speed tests measure work; when something
  happens, or that something does not wait, is tested in wall time by
  `is-within-seconds`, with bounds the mechanism sets.
- **The Postgres server's share.** The database's server processes are
  found in `pg_stat_activity` by the test application's database, and
  their processor time read from `/proc/PID/schedstat` (in
  nanoseconds) before and after each run. When it cannot be read (a
  server on another machine), `is-fast` measures wall time and says so:
  the stricter reading.
- **The inventory's three kinds.** Each place that reads a clock in a
  test is a speed (how much work: `is-fast`), a when (a deadline, a
  timeout, an answer that must not wait: `is-within-seconds`), or a wait
  or a report (a loop that gives up after some seconds, a report's
  seconds: the stopwatch). The scan cannot tell a speed from a when; the
  spec says which is which, and the helper's names say what is meant.
- **The fuzz test's deadline.** `inventory_shortages` before
  9999-12-31 steps through every day until then (about 2.9 million)
  before it refuses the day after; that takes seconds, and under load
  more than the 10 s deadline. The test is about the refusal, so it
  lifts the deadline. That a tool walks millions of days is the
  inventory module's to decide, not this loop's (a question in the
  report).
- **When-tests stay wall time, and out of criterion 3.** A deadline, a
  timeout, an answer that must not wait: what they assert is wall time,
  and processor time would pass a mechanism that waits too long. Their
  bounds are the mechanism's, with room; at the made load (five busy
  processes per processor) a trial run had `programs`'
  `a-program-leaves-the-operation-time-to-answer` at 2.21 s against
  2.2 s. Widening their bounds would be loosening them, and repeating a
  test with side effects is not safe in general, so they are left as
  they are; a failure now names the load, so a builder sees why. A
  trial also had `outbound`'s lower bound fail at «1.00 s, not at least
  1 s»: the first stopwatch read a finer clock than the kernel's
  timeouts do, so it now reads `get-internal-real-time`, as the tests
  did before.
- **Browser checks.** Playwright's 30 s default is not a limit Tun
  states anywhere; a page's speed is the Lisp suites' to test. 120 s
  waits out a loaded machine and still ends a hung page. Checks that
  wait a fixed time for a transition keep their waits: a CSS transition
  runs by the clock, not by the processor.
- **Estimate.** 1h30m / 3h / 5h rather than the orchestrator's guess of
  50 / 100 / 200 minutes: the inventory is about forty places in twenty
  files, each moved onto the helper, besides the proof runs.

## Inventory

Every place in Tun's tests and checks, at the base, that reads a clock,
compares a duration or depends on a deadline, and what it becomes. Speed
→ `is-fast` (processor time); when → `is-within-seconds` (wall time,
bounds unchanged); wait or report → the stopwatch.

Speed (how much work):

- `search`: `every-kind-of-two-thousand-records-is-searched-within-the-limit`
  (median of nine under 90 ms, memory and Postgres, seven queries);
  `two-thousand-customers-are-searched-within-100-ms` (median of five
  under 100 ms, memory and Postgres).
- `generated-choice`: `two-thousand-records-are-chosen-among-within-100-ms`
  (`/choices/customer`, median of nine under 100 ms, memory and
  Postgres); `the-names-add-little-to-the-pages-that-show-them` (the
  orders' list and an order's page, 2000 customers against 10: at most
  50 ms more).
- `markdown`: `costly-texts-render-within-a-second` (each costly text
  under 1 s); `costly-texts-take-time-in-proportion-to-their-length`
  (four times the text in under eight times the time plus 20 ms, the
  shorter of two runs).
- `graphs`: `the-largest-graph-allowed-renders-within-a-second`.
- `review2`: `r2-4-long-numbers-are-refused-quickly` (three parses
  under 0.5 s each).
- `hostile`: `a-number-past-a-doubles-range-is-refused-at-once` (each
  refusal under 0.1 s, parsed and through `/api` and `/mcp`),
  `a-long-number-in-a-generated-form-is-not-parsed` (under 2 s),
  `a-long-amount-in-a-generated-form-is-not-read` (under 1 s): each
  says the work of reading a long number is not done.
- `pressure`: `p-policy-runs-before-the-work` (a forbidden caller's
  `debug_burn` under 100 ms: no burning).

When (a mechanism acts in time; wall time):

- `pressure`: `timed-call` with `p-deadline-interrupts-burn-and-sleep`
  (stopped under 1 s at a 300 ms deadline), `p-watchdog-stops-code-without-deadline-checks`,
  `p-deadline-leaves-other-requests-alone` (under 1 s),
  `p-backpressure-sheds-at-once`, `p-a-stalled-port-delays-only-its-request`
  (under 0.5 s); the deadline tests' own `*deadline-ms*` bindings.
- `programs`: `a-program-past-its-time-is-stopped-with-what-it-started`
  (1 to 1.5 s), `a-program-that-ends-has-ended-though-its-children-hold-its-output`
  (under 1 s), `a-tenant-runs-four-programs-at-once` (under 0.2 s),
  `a-program-leaves-the-operation-time-to-answer` (1.5 to 2.2 s; under
  0.2 s), `each-line-of-standard-error-comes-while-the-program-runs`,
  `an-error-in-on-error-line-stops-the-program` (under 1 s).
- `outbound`: `a-silent-remote-fails-in-time-and-its-call-ends` (1 to
  2.5 s), `a-remote-that-cannot-be-reached` (under 4 s),
  `a-call-leaves-the-operation-time-to-answer` (1.5 to 2.3 s; under 0.2
  s), `calls-to-other-systems-are-bounded-per-tenant` (under 0.2 s).
- `waiting`: `a-wait-returns-at-the-commit-that-satisfies-it` (under 3
  s), `a-wait-ends-with-its-last-value-when-time-is-up` (1 to 3 s),
  `a-wait-outlasts-two-rechecks-in-real-time`,
  `a-long-wait-over-mcp-becomes-a-stream-with-progress` (under 5 s),
  `a-wait-over-the-api-is-a-long-poll` (under 5 s).
- `communication`: `slow-provider-does-not-block-send-or-an-unrelated-read`
  (each under 1 s).
- `slice3-review`: `s3r-4-provider-deadline-is-independent-of-mode`
  (each under 1 s); `slice3-review-round3`:
  `s3r3-40-shutdown-is-bounded-by-one-provider-deadline` (under 4.5 s).
- `slice1-review`: `s1r-6-eval-is-read-only-in-the-threads-it-starts`
  (under 5 s, no wait for the deadline).
- `loop`: `a-tracker-that-fails-or-hangs-leaves-a-line-and-the-loop-goes-on`
  (under 10 s at a limit of 1 s).
- `files`: `a-reader-that-stops-is-cut-off` (closed under 3 s).
- `safety`: `refused-unread-p` through `raw-request` (answered under 2
  s), `a-large-body-must-arrive-in-time` (under 6 s),
  `a-body-past-its-time-ends-its-connection-at-once` (under 4 s).
- `hostile`: `a-large-body-that-stops-coming-is-answered-408` (under 5
  s), `headers-that-trickle-are-answered-408` (under 3 s),
  `bodies-sent-where-nothing-reads-them-end-their-connection` (under
  3.5 s), `small-bodies-that-trickle-free-their-places-in-time` (under
  3 s), `a-client-has-at-most-32-calls-waiting` (under 2 s).
- The fuzzer (`tests/fuzzing.lisp`, every client's generated test): a
  `:wait` tool that took over a second fails as «it waited»; its outcome
  now keeps a stopped stopwatch, and `stopwatch-past-p` decides.

Waits and reports (no assertion on the time):

- `hostile`'s `eventually`, `safety`'s `ordinary-reads`, `programs`'
  waits for a process group and a process, `pages.lisp`'s
  `recorded-fault`, the `widgets` fixture's runaway loop
  (`tests/widgets.lisp`); the seconds in the reports of the fuzzer, the
  page test, the record-policy test and the sequence test.

A deadline in a functional test:

- `fuzz`: `a-day-past-the-last-date-is-refused-not-a-fault`, whose
  `inventory_shortages` call ran past the operation's 10 s deadline
  under load: the deadline is lifted there (`with-deadline-lifted`).
- `files`: `sizes-are-bounded-per-file-per-call-and-per-record` and
  `a-file-is-read-and-sent-a-part-at-a-time`, whose 10 MiB attachments
  ran past it under the made load (found by this loop's trial run):
  lifted too.

Browser checks (`checks/showcase/checks/`), all run by
`scripts/tun_check.py`:

- Every navigation and every wait without a timeout of its own had
  Playwright's 30 s (ui-fields' `page.goto("/fields")` ran past it in
  ui-motion's verify 5): now 120 s.
- Fixed waits (`wait_for_timeout`, `time.sleep`, the touch finger's
  `stay` and `hold`) in 25 checks, most of 200 to 600 ms, wait for a
  transition, a debounce (150 ms) or a drag's autoscroll to finish:
  unchanged.
- Explicit timeouts that say how soon something must show (loading-sign's
  bar within 2 s of a slow request, a search's or a choice's answer
  within 3 to 4 s, the filters' and fields' answers within 10 s):
  unchanged.

## Clients

On this loop's tree as committed at 038b2e10 (verify round 1), each
client's `bin/test` with `--override-input tun` at it (and `dashboard`,
and tun-erp's `customers`, at their `modules/` directories), one at a
time, from clones of their `origin/main` in a scratch folder: factory,
nixploy-dashboard and ferdig (tunworks `0189370`; 690, 1421 and 812
checks), kurs `a82a83d` (352) and tun-erp `a7ae394` (its suites of
90871, 16264 and 26073 checks) pass, with no change to any of them.

How tun-erp moves onto the helper once it updates to this core; nothing
in tun-erp is changed by this loop. Its test packages already use
`tun.test-support`, so the names are there.

The search (`tests/search.lisp`, `every-kind-with-2000-customers-and-2000-orders-is-searched-within-100-ms`):
`search-ms` and the sorted nine go; each query becomes

```lisp
(is-fast (:why (format nil "the ERP's search of «~a», 2000 customers and 2000 orders on Postgres"
                       text)
          :limit-ms 100)
  (call-ok "search" "employee:anna" "query" text))
```

The invoices' «Customer» filter (`tests/lists.lisp`,
`the-invoices-customer-filter-reads-one-row-per-customer-and-is-quick`):
`timed-ms` goes; the two limits become

```lisp
(is-fast (:why "/invoices/customers, a find" :limit-ms 150)
  (web-request port "/invoices/customers" :parameters (list (cons "q" word))
                                          :headers +office-htmx+))
(let ((list (measure-speed (lambda () (web-request port "/invoices" :headers +office-htmx+))
                           :why "/invoices")))
  (is-fast (:why "/invoices with a find" :over list :limit-ms 100)
    (web-request port "/invoices" :parameters (list (cons "customer-find" word))
                                  :headers +office-htmx+)))
```

(`+office-htmx+` standing for its two headers.) The two need not be
timed in turn any more: processor time does not drift with the load.

`within-seconds` (`modules/billing/tests/tests.lisp`, used in
`retry-under-deadline` and in `payments.lisp`) times when a hanging call
ends, a when: the macro goes, and each use becomes
`(is-within-seconds (:why "ends at its deadline" :under 3) ...)`, whose
values are its body's, as before.

The measure counts the Postgres server's share when the application
being measured is `*app*`, which `with-test-server` and `with-test-app`
bind; a test that measures another application binds `*app*` to it.

## Log

- 2026-11-15 01:10  started, reviewed
- 2026-11-15 01:10  estimated 1h30m 3h 5h at brief, like tun/search-reads tun/form-nits
- 2026-11-15 01:40  gate A asked of a reviewer
- 2026-11-15 01:41  gate A: changes (reviewer)
  I've read the whole packet. My verdict is **changes**: the spec mostly fits the brief, but one thing the brief asks for is missing, one criterion would make a test fail when the code gets faster, and the spec and criteria disagree in two places.
  
  **What's right**
  
  - The inventory is complete and sorted into three kinds: speed, deadlines and timeouts ("when"), and waits or reports. Each kind maps to one helper, and the scan in criterion 1 enforces it.
  - Measuring processor time is argued with numbers measured on this machine (Decisions, loop.md:134–150). The brief asked the builder to choose the method, so this didn't need asking. The limits that wall time can't see (sleeps, locks) are written down.
  - Criteria 1, 2, 5, 6, 7, 8 and 9 can each be decided by a test or a check. Criterion 8 states its amount (15 s), as the brief asked.
  - `spec/tooling.md`, `reference/pitfalls.md`, `docs/client-api.md` and `spec/preview.md` match criteria 2, 5, 9 and 10.
  - No decision under **Decisions** belongs to the asker. Whether the inventory module should walk millions of days is correctly left as a question for the report.
  
  **Changes**
  
  1. **A brief item is missing.** The brief ends with "and how tun-erp's own speed tests (its search bound of 100 ms, the invoices filter) would move onto the helper, without changing tun-erp". No criterion covers it.
     - Add it to criterion 10 (loop.md:125–130) or as a new criterion: the record or `docs/client-api.md` shows both tun-erp tests written with `is-fast`, and tun-erp is not changed.
  
  2. **Criterion 4's check inside the suite fails when the search gets faster.** At loop.md:96–99, the every-kind test runs three searches in memory with the work done four times and requires at least one to go over 90 ms.
     - The builder's own Decisions give an in-memory processor time of 22 ms at the low end. Four times that is 88 ms, which is under the limit.
     - So on a fast machine, or after someone speeds up the search, this test fails. It's a timing-dependent test, just in the other direction.
     - Make the check relative. Either require the planted measurement to be at least, say, 2.5 times an unplanted one measured right beside it, or pick the repeat count from a baseline measured in the moment, so the plant always lands over the limit.
  
  3. **The fuzz deadline is never proven under load.** The brief names `a-day-past-the-last-date` (`deadline_exceeded`) as one of the tests that failed under load. Criterion 6 lifts its deadline, but criterion 3's loaded run (loop.md:85–87) doesn't include the `fuzz` suite.
     - Add `fuzz`, or at least that test, to criterion 3's five loaded runs.
     - I'd also recommend loading the suites with tight "when" bounds (`programs`, `outbound`: under 0.2 s). Otherwise the spec should say they are knowingly out of scope. The asker's complaint was a verdict that depends on the neighbours' load, and a 0.2 s wall-time bound at a load of 60 is that same risk.
  
  4. **The spec and criterion 1 disagree.**
     - Criterion 1 names `stop-stopwatch` and `lap-stopwatch`. "Speed and time in tests" (`spec/tooling.md`, diff.patch:241–244) lists only `start-stopwatch`, `stopwatch-seconds` and `stopwatch-past-p`.
     - The spec's `is-within-seconds` "runs BODY once". It doesn't mention the `:watch` form, which asserts a stopwatch stopped elsewhere, for example in another thread. That form is part of the contract (`tests/timing.lisp`, diff.patch:2098–2107).
     - Add both stopwatch functions and the `:watch` form to the spec, and to the short version in `docs/client-api.md`.
- 2026-11-15 01:53  gate A asked of a reviewer
- 2026-11-15 01:54  gate A: changes (reviewer)
  Nearly done: I've checked that the first gate A review's four points were fixed, and one is still open.
  
  ## Gate A review: test-timing (round 2)
  
  **What's right**
  
  - **Point 1 (tun-erp) is fixed.** Criterion 11 and the «Clients» section show tun-erp's search bound, its invoices «Customer» filter and its `within-seconds` written with `is-fast`, `measure-speed` and `is-within-seconds`. tun-erp itself is not changed.
  - **Point 3 (fuzz under load) is fixed.** Criterion 3 now loads `fuzz` and `files` too. The when-suites run in the same proof runs with their verdicts logged, and a Decision says why they stay out of the criterion. It gives a measured 2.21 s against 2.2 s and argues that widening those bounds would loosen them. That answers what the last review asked.
  - **Point 4 (spec vs criterion 1) is fixed.** `spec/tooling.md` (diff.patch:263–268) and `docs/client-api.md` (diff.patch:44–47) now list `stop-stopwatch`, `lap-stopwatch` and `is-within-seconds`'s `:watch` form.
  - The other criteria still match the brief and can each be decided by a test or check:
    - criterion 8 states its amount (15 s);
    - criterion 9 matches `spec/preview.md` and the spec section on the browser checks;
    - the clock scan in criterion 1 matches the spec's description.
  - No decision under **Decisions** belongs to the asker.
  
  **Changes**
  
  1. **Criterion 4 still describes the fragile check that the last review rejected, and no longer matches the code.** loop.md:103–106 says the every-kind test "measures three of its searches in memory with the search's work done four times, and checks that at least one is over its limit". The diff does something else, and does it better. `planted-slowdown-verdict` (diff.patch:1707–1722) measures one search («nordmann») in the same moment. It then sets the repeat count to `max(3, ceil(1.5 × 90 ms / measured))`, so the plant lands over the limit on a fast machine as well as a slow one.
     - Rewrite the second half of criterion 4 to say what the code does: one search measured unplanted, then with its work repeated as many times as brings it to 1.5 times the limit (at least 3), and `is-fast`'s judgement must be a failure.
     - As written, gate B would have to check the code against a criterion that the code doesn't meet. The criterion would also still carry the 22 ms × 4 = 88 ms < 90 ms flaw from the last review.
  
  That is the only change I'm asking for. It's a wording fix to the record, and the design itself is sound.
  
  (For gate B, not this gate: `planted-slowdown-verdict` reaches into `tun.test-support::` internals, `measurement-measured-ms`, `limit-measurement` and `measurement-within-p` (diff.patch:1718–1722). Either export them or give the helper a public way to ask "would this fail?".)
- 2026-11-15 01:55  gate A asked of a reviewer
- 2026-11-15 01:55  gate A: approve (reviewer)
  I've checked that the one open point from round 2 is fixed and found nothing new that needs a change.
  
  ## Gate A review: test-timing (round 3)
  
  **What's right**
  
  - **Round 2's open point is fixed.** Criterion 4 (loop.md:103–108) now describes what the code does. `planted-slowdown-verdict` (diff.patch:1710–1723) measures «nordmann» in memory without the plant. It then repeats the search's work `max(3, ceil(1.5 × 90 / measured))` times and asks `over-limit-p` whether `is-fast` would fail it. Because the repeat count comes from a measurement taken at that moment, the plant lands over the limit on a fast machine as well as a slow one. The 22 ms × 4 < 90 ms flaw from round 1 is gone.
  - **The round 2 note for gate B is also answered.** `over-limit-p` and `measurement-milliseconds` are exported (diff.patch:1861) and documented in «Speed and time in tests» (diff.patch:251–254). The test no longer reaches into `tun.test-support::` internals.
  - **The fixes from earlier rounds still hold:**
    - tun-erp's tests appear in criterion 11 and the «Clients» section, and tun-erp is not changed.
    - `fuzz` and `files` are in criterion 3's loaded runs, and the when-suites are logged and knowingly out of scope.
    - The spec and `docs/client-api.md` both list the full stopwatch set and the `:watch` form.
  - **The criteria cover the whole brief:**
    - one helper, with a test that scans the sources;
    - the same verdict five runs in a row under a made load;
    - a planted slowdown that fails both loaded and quiet;
    - a failure that names the value, the limit and the load;
    - `bin/test`'s extra time capped at 15 s;
    - the browser checks' 120 s default;
    - core 2.39.0 with the five clients unchanged;
    - how tun-erp's tests would move onto the helper.
  - **Each criterion can be decided** by a test, a proof run with its numbers in the Log, or a check.
  - **No limit is loosened** (criterion 7), and the inventory keeps each number.
  - **No decision belongs to the asker.** The brief asked the builder to choose the method, and the choice is argued with numbers measured on this machine. Whether the inventory module should walk millions of days is rightly left as a question for the report.
  
  **Minor (no change needed)**
  
  - Criterion 1's list of exports leaves out `over-limit-p` and `measurement-milliseconds`, which criterion 4 and the spec name. The criterion reads as the helper's main surface rather than a complete list, so this doesn't block approval.
- 2026-11-15 02:43  measured before deciding (search suite's every-kind search, 2000 of each, medians of nine; an experiment script timing wall time, this process's processor time, the Postgres server's processes' processor time and a calibration loop): at a load of 20 from other builders, memory wall 36-45 ms and processor 22-42 ms, Postgres wall 37-69 ms and processor (with the server's 10-13 ms) 39-70 ms, calibration 17-20 ms; under scripts/make-load (24 busy, 12 Postgres sessions) at a load of 58-70, memory wall 51-311 ms and processor 25-44 ms, Postgres wall 289-526 ms and processor 51-67 ms, calibration 29-173 ms
- 2026-11-15 02:43  base (baa99df1) bin/test at a load of 25-30: 268 s, search failed its every-kind limits (memory 103 and 113 ms, Postgres 117 to 194 ms wall against 90)
- 2026-11-15 02:43  proof, criterion 3: five runs under scripts/make-load (load 68 to 93) of the suites search, generated-choice, markdown, graphs, review2, hostile, pressure, timing, fuzz, files and the when-suites programs, outbound, waiting, communication, slice1-review, slice3-review, slice3-review-round3, safety, loop, run at once by scripts/run-suites with Postgres: 95 of 95 ok; five runs without the made load (load 86 falling to 17, other builders' suites running): 95 of 95 ok
- 2026-11-15 02:43  every-kind processor-time medians, loaded (load 64-93) against not (load 12-40), lowest-highest over five runs: memory kunde 1999 31.6-41.2 / 28.3-37.5 ms, nordmann 35.8-47.3 / 34.3-42.7, julebord rigging 27.3-38.7 / 27.8-30.1, zebra 19.4-25.1 / 16.3-23.5, 912 19 18.3-26.0 / 15.3-20.8, nordmnan 35.3-43.5 / 32.4-38.4, julebrod 28.2-33.0 / 26.3-28.2; Postgres kunde 1999 57.6-63.1 / 49.9-54.6, nordmann 62.8-69.7 / 55.1-63.4, julebord rigging 52.3-68.2 / 53.0-61.2, zebra 43.7-56.7 / 39.9-47.1, 912 19 45.6-57.5 / 40.0-54.0, nordmnan 62.2-82.1 / 55.1-62.9, julebrod 57.2-65.2 / 48.3-54.3; their wall medians loaded 48.9-526.6 ms. Every other speed test stayed under 0.76 of its limit loaded and not (nearest: markdown fences 100.8 of 133.5 ms loaded, table cells 44.2 of 59.3 ms not)
- 2026-11-15 02:43  processor time under the made load runs 10-30% over the quiet's (shared caches): the Postgres nordmnan search reached 82.1 ms of its 90, where its quiet medians are 55-63 ms
- 2026-11-15 02:43  proof, criterion 4: TUN_TEST_PLANT=slow-search bin/test --only search with Postgres: at load 11-12, every-kind fails 12 of 14 searches (memory 89.6-118.7 ms, Postgres 120.5-173.1 ms against 90); under make-load at load 64-67, 12 of 14 (memory 60.5-126.9, Postgres 157.6-199.3 ms); the suite fails both times. The in-suite planted check (search's work done enough times for 1.5 times the limit) passed in all ten proof runs
- 2026-11-15 02:43  criterion 8: bin/test alternating base and this tree: base 194 s (load 56 falling to 19; failed search, markdown, group-commit) and 169 s (load 24-22; failed search's limit), this tree 175 s (load 19-24) and 184 s (load 22-28), both green: 180 s against 182 s, no growth
- 2026-11-15 02:44  correction to the line before last: at load 11-12 the planted slowdown failed 11 of 14 searches (memory 60.7-118.7 ms, four of seven over 90; Postgres all seven, 120.5-173.1 ms)
- 2026-11-15 03:00  verify 1: passed build, test, check
- 2026-11-15 03:00  shown (/, /markdown)
- 2026-11-15 03:14  the five clients pass unchanged against 038b2e10: factory, nixploy-dashboard, ferdig (tunworks 0189370), kurs a82a83d, tun-erp a7ae394
- 2026-11-15 03:14  gate B asked of a reviewer
- 2026-11-15 03:15  gate B: approve (reviewer)
  I recommend approving. Every criterion is met, all three verify steps passed, and nothing I found is worth another round.
  
  **Criteria**
  - **1. One helper:** `tests/timing.lisp` is the only test source that reads a clock. The scan test fails on a clock read outside it, or on a stopwatch's seconds inside a comparison or assertion. A second test plants each of those and expects each one named with its line (diff.patch:1985–2005). The scan passes on the real sources, so the change moved every clock read onto the helper.
  - **2. Processor time:** `a-speed-is-processor-time-not-waiting` and `a-speed-on-postgres-counts-the-server-s-work` (diff.patch:2010–2040) pin the three behaviours the criterion names: a sleep costs under 20 ms, a computation costs processor time, and a Postgres sort counts mostly as the server's. One allowance: the computation test lets processor time run 5 ms over wall time; the criterion says "no more than".
  - **Counting is safe:** `scripts/run-suites` runs each suite in its own SBCL process. So "every thread of this process" never counts another suite's work.
  - **3. Same verdict under load:** the Log has five loaded runs (load 68–93) and five without the made load, all green, with the medians and load averages.
  - **4. Planted slowdown:** the in-suite check sets its repeat count from a speed measured at that moment, at least three repeats (diff.patch:1716–1729). The Log has the `TUN_TEST_PLANT=slow-search` runs failing both quiet and loaded. It also corrects the count from 12 to 11 of 14.
  - **5. Failure messages:** `a-failure-names-the-time-the-limit-and-the-load` checks both the `is-fast` and the `is-within-seconds` message.
  - **6. Deadlines lifted:** `with-deadline-lifted` wraps the fuzz refusal and the two 10 MiB file tests. The "when" tests keep their bounds through `is-within-seconds`.
  - **7. No limit loosened:** I compared the hunks and every number is unchanged:
    - the watchdog bound stays `(300 + grace + 700) / 1000`;
    - markdown keeps eight times plus 20 ms;
    - the hostile tests keep 0.1, 1 and 2 s.
    
    The `web-login` calls in the hostile tests now sit outside the timed part, which makes those tests stricter, not looser.
  - **8. `bin/test`'s time:** 180 s on the base against 182 s on this tree, both in the Log.
  - **9. Browser checks:** `scripts/tun_check.py:175–179` sets the 120 s default.
  - **10. Docs and versions:**
    - `spec/tooling.md`, `spec/preview.md`, `reference/pitfalls.md` and `docs/client-api.md` match the code.
    - Core is 2.39.0 in both `flake.nix` and `src/core/module.lisp`.
    - The five clients passed at 038b2e10, the same commit the preview shows (its only uncommitted change is the loop record).
  - **11. tun-erp:** the Clients section shows its three tests rewritten on the helper, and tun-erp is not changed.
  
  **Screenshots:** `/` and `/markdown` at phone and desktop widths. This is a tooling change, so there's nothing visible to compare beyond those.
  
  **Code:** it follows `AGENTS.md`: the spec changes where the behaviour does, comments explain why, and there's no leftover debugging.
  
  **Minor points, none blocking**
  - **Header typo:** `tests/timing.lisp:3` (diff.patch:2073) says "A measured is how much work something is"; it should probably be "A speed is …".
  - **Unrelated indentation churn:** files-tests.lisp around line 1317 (diff.patch:516–521) moves `(if …)` under `for`, when it's the second form of `do`. The line 1394 change is a correct realignment, but neither belongs to this loop.
  - **Unused option:** `every-kind-speeds` takes a `:texts` key (diff.patch:1704) that no caller passes.
  - **No test for criterion 9:** nothing fails if the 120 s default is removed. The criterion names the script and verify's checks as its proof, which gate A accepted.
  - **For the report:** one search's margin under load is thin. Postgres «nordmnan» reached 82.1 ms of its 90 under the made load, and the Log notes that processor time runs 10–30% higher under load. The criterion is met, but the asker should know the search's Postgres limit has the least room. It can't be raised without loosening it.
- 2026-11-15 03:37  verify 2: passed build, test, check
- 2026-11-15 03:37  shown (/, /markdown)
- 2026-11-15 03:37  gate B asked of a reviewer
- 2026-11-15 03:38  gate B: approve (reviewer)
  I've read the whole round-2 packet. The change still meets every criterion, all three fixes the first gate B review asked for are in, and nothing new needs another round.
  
  **What changed since the first gate B approval (commit cd81ce51)**
  - **Header fixed:** `tests/timing.lisp:3` (diff.patch:2055) now says "A speed is how much work something is".
  - **Unrelated reindentation gone:** `tests/files-tests.lisp` now has only this loop's three hunks: the two `with-deadline-lifted` wraps and the `is-within-seconds` in the cut-off reader (diff.patch:359–514). The `(if …)` moved under `for` no longer appears.
  - **Unused key gone:** `every-kind-speeds` takes only `:slowdown` (diff.patch:1686).
  - None of the three changes behaviour. One more thing changed at cd81ce51: `every-kind-speeds`' message only mentions the work multiplier when it is above 1 (`~@[…~]`). That is cosmetic.
  
  **Criteria (rechecked against the current diff)**
  - **1, one helper:** only `tests/timing.lisp` reads a clock. The scan test and its planted-source test still name every clock read and every compared stopwatch by line (diff.patch:1949–1987).
  - **2, processor time:**
    - The sleep, computation and Postgres-sort tests are unchanged (diff.patch:1992–2022).
    - `measure-run` adds this process's processor time to the server's change in `schedstat`, and keeps wall time apart (diff.patch:2193–2210).
  - **3, 4 and 8:** the Log's proof runs and numbers are as before.
    - Loaded and unloaded: 95 of 95 ok both times.
    - The planted slowdown fails both quiet and loaded.
    - `bin/test` takes 180 s on the base against 182 s on this tree.
    - The in-suite planted check derives its repeat count from a measurement taken in the moment and asks the public `over-limit-p` (diff.patch:1698–1711, 1744–1746).
  - **5, failure messages:** `a-failure-names-the-time-the-limit-and-the-load` covers both messages and the wall-only case.
  - **6, deadlines lifted:** `with-deadline-lifted` wraps the fuzz refusal and both 10 MiB file tests.
  - **7, no limit loosened:** I compared the hunks again and every number is the same (90, 100, 50, 1000, eight times plus 20, 500, 2000, and the watchdog's `300 + grace + 700`).
  - **9, browser checks:** `scripts/tun_check.py` sets the 120 s default for navigation and for waits (diff.patch:167–182).
  - **10, docs and version:** `spec/tooling.md`, `spec/preview.md`, `reference/pitfalls.md` and `docs/client-api.md` match the code, and the core is 2.39.0 in both places.
  - **11, tun-erp:** the record shows tun-erp's tests rewritten on the helper, and tun-erp is not changed.
  
  **Verification:** `verify.txt` round 2 passed all three steps (build, test, check). No result in `checks/` records a failure. The phone and desktop screenshots of `/` and `/markdown` are present. This is a tooling change, so nothing new is visible in them.
  
  **Code:** it follows the repository's rules. Comments say why, there's no leftover debugging, and the spec is changed where the behaviour is.
  
  **Minor, not blocking**
  - **Clients:** they were run against 038b2e10, and round 2 also touched `tests/timing.lisp`, which ships in `tun-test-support`. The only change there is the header comment, so the clients' result still holds.
  - **`over-limit-p` changes its argument:** it records the limit on the measurement it is given, through `limit-measurement`. Nothing uses the measurement afterwards, but a docstring line saying so would help the next reader.
  - **For the report (unchanged):** the search's Postgres limit has the least room. «nordmnan» reached 82.1 ms of its 90 under the made load.
