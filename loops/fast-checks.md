# A verify round in minutes: one image and one database server per round, scenarios as templates, checks and suites in parallel inside the one lock

- loop: fast-checks
- mode: reviewed
- stage: done
- base: 44a39c177392b9ae5fbb6108ddfbffa1496d1250
- item: sak_y2wez8ch679ffv0w
- estimate: 6h 9h 16h
- like: tun/checks-under-load tun/test-timing
- tags: kind:tooling core
- verified: 0b61f00586a0b5e3dc16afc8b01093fb56c8d770
- shown: 0b61f00586a0b5e3dc16afc8b01093fb56c8d770

## Brief

Item sak_y2wez8ch679ffv0w («fast-checks: a verify round in minutes: one
image and one database server per round, scenarios as templates, checks
and suites in parallel inside the one lock»), written by the factory's
orchestrating session on 2026-11-17 from a client's round measured on a
quiet machine:

> test 13 min (strict compile from scratch, then 823 tests in one
> process), check 30 min (100 checks one after another, each starting a
> fresh server with a fresh database: start 15 s, stop 4 s, the scenario
> under 1 s, the check's clicks a few seconds). Wanted: the round keeps one
> hold of the verify lock but runs in minutes: the application built once
> per round as an image a check server starts from; one database server
> per round, each scenario seeded once as a template database and copied
> per check; checks run by several workers inside the one lock, with the
> load each adds measured; the test step's suites in parallel processes
> where they are independent; a Tun loop's client runs in parallel.
> Measured before and after on Tun's showcase and on a client with 100
> checks; every check still passes with no new flakiness over repeated
> rounds.

The owner, the same day, on hearing that a round takes 13 + 30 minutes
(brought by the orchestrator): «that's not acceptable at all … I'm kind
of starting to question why the application takes 13 minutes to build
and test. I would like a more specific analysis … how long does it take
to do a clean build? How much does each type of test take? And we have to
minimize or basically almost remove the browser checks. 30 minutes is
unacceptable … one of the reasons we want to use Common Lisp is fast
iteration. If we're not able to do that with Common Lisp, we have to look
for alternatives». So this loop first measures and proposes («Measured»,
and the proposal under Decisions), and stops before gate A for the
owner's decision.

## Measured

On netcup-dev (12 processors, 31 GB), 2026-11-17 18:50 to 19:40, at a
load average of 2 to 8 (another builder's verify ran meanwhile), Tun at
`bf706a67` (core 2.48.0). «The client» is a client with 100 browser
checks, from a scratch clone of its repository; that repository holds a
second client with 10. Seconds are wall time unless said.

**Building**

| What | Tun's showcase / Tun | The client |
|---|---|---|
| Tun compiled from nothing, strictly (`bin/build`, kernel, modules, tests, test client) | 21.8 s core + 1.6 s test client, 27.6 s the whole command | not compiled: the client's shell loads Tun precompiled from the Nix store |
| No-op `bin/build` | 11.0 s (5.7 s core) | |
| Tun's CLI, first start (compiles it) / later | 15.0 s / 4.4 s | |
| The client's `bin/test` compile phase: ASDF 0.4 s, Tun and the libraries loaded from the store 3.7 s, the client's own systems and its modules compiled afresh | | 15.4 s; 20.2 s the whole process |
| Loading the already compiled client (own fasls) | 1.9 s showcase | 5.1 s own systems, 9.9 s the whole process on its pinned Tun; 3.4 s on Tun's worktree |
| An image saved with the client and its tests loaded | | 5.6 s to load and save, 294 MB; a process starts from it in 0.05 s |

**Testing** (`bin/test`)

| What | Tun | The client |
|---|---|---|
| The whole step | 192 to 217 s: 102 suites in parallel processes (`scripts/run-suites`, 12 at once), 1885 s if run one after another | 13 min: 823 tests in one process after the compile (the orchestrator's measurement; it is timing each test now) |
| The longest suites | loop 72 s, two heap suites 67 and 63 s, policy-checks 51 s, core-migration 41 s | |
| The kinds Tun generates, on Tun's test client | generated 18.7 s, generated-choice 18.5 s, fuzz 21.6 / fuzz-core 17.5 / fuzz-modules 22.9 s, record-policies 17.3 s, policy-checks 50.5 s, sequences 17.1 / 13.8 / 14.7 s, pages 21.8 s, cases 18.0 s, i18n 12.0 s | the orchestrator's numbers |
| The guards | test-lint 10.0 s, test-repl 15.0 s, test-indent 1.5 s | |
| A Tun loop's client runs (each client's `bin/test` on Tun's tree, one after another, loop `posted-sets`) | dashboard 2 min, ferdig 1, kurs 1, the client 14 (its first client; the second's suite is apart), factory not told apart from its lock wait in that log; at least 18 min of suites, plus a wait for the lock between holds (78 min in that loop) | |

**The client's test step, test by test.** The orchestrator's run
(2026-11-17 18:59 to 19:12 UTC, load about 5, the client at a later
commit on Tun 2.46.0, its output stamped line by line): SBCL and ASDF
0.5 s, Tun and the libraries loaded 4.5 s, the client and its 11
modules compiled 15 s, then 811 tests in 777 s. A line of FiveAM's output
ends when the test after it begins, so each stamp is the end of the test
on its line; read so (one test later than a first reading had them):

| Kind | Tests | Seconds |
|---|---|---|
| Generated: every tool fuzzed (169 tools, 10930 calls of about 10 ms, 8 per tool and actor; 52 s of processor time in 110 s alone) | 1 | 112 |
| Generated: every scenario makes its records (each scenario once on a fresh database) | 1 | 47 |
| Generated: every page for every role | 1 | 16.5 |
| Generated: tools in sequence, record policies, the rest | 7 | 11 |
| The client's and its modules' own property tests: seeded random sequences of operations checked against invariants | 7 | 124 |
| One test of the day's boundary in each time zone the client reckons | 1 | 34 |
| Tests that open a fresh database and make a scenario or a fixture of many records first, then check a page or a rule (2 to 5 s each) | 65 | 217 |
| Speed tests with thousands of records | 2 | 21 |
| Tests from 0.5 to 2 s | 102 | 80 |
| Tests under 0.5 s | 623 | 60 |
| By suite: the client's own (the generated ones among them) 514, the modules' 92, 69, 39, 25, 11, 9 and under 4 | 811 | 777 |

Why the 2-to-5-second tests are slow, from running them alone with a
profiler: a fresh database is 0.04 s; opening the application on it
(migrations) 0.4 to 0.8 s; the scenario 2.0 s (default) to 2.6 s (the
most used) in a test, made through operations of about 10 ms each, half
of it this process's processor time and half waiting for Postgres; the
test's own requests then; and a test that makes documents runs Typst
about 13 times, 0.4 to 0.6 s in all. Tun's integrity check at an
application's open costs 1 ms. The fuzzer alone spends 48 to 52 s of this
process's processor time in its 103 to 110 s; the rest is waiting, which
was not traced further (Postgres's work and the round trips to it are
where its calls go). So the time is the
volume of work: records made again for every test, the property tests'
and the fuzzer's thousands of operations, and all of it in one process
on one of the 12 processors.

**A preview's start and stop** (each the mean of 3; `tun check` starts
one per check)

| Part | Showcase | The client (its most used scenario) |
|---|---|---|
| Database server: `initdb` | 0.47 to 0.52 s | the same |
| `pg_ctl start` / `createdb` | 0.12 s / 0.04 s | the same |
| `start-database` as `tun` runs it | 0.88 s | 0.85 to 0.94 s |
| SBCL's start and setup | 0.34 s | 0.36 s |
| Loading the client and its tests (compiled before) | 1.85 s | 3.3 to 3.4 s |
| Opening the application: migrations, checking policies and queries | 0.36 s | 0.80 s |
| The scenario's records | 0.19 s | 3.6 s (default) to 5.2 s (the most used) |
| The rest of the server's start until `/health` answers (the HTTP server, the job runner, the poll every 0.5 s) | about 2.3 s | about 1 s |
| The start in all (`start-preview`) | 6.3 s | 11.2 s |
| The stop (`stop-preview`: server 0.1 s, database 0.26 to 0.32 s) | 0.42 s | 0.49 s |
| The same start from a saved image and a copied template database: image start 0.05 s, `CREATE DATABASE … TEMPLATE` of the seeded 15 MB database 0.04 to 0.07 s, opening the copy (no migration to run) 0.6 s | | about 0.7 s, plus the HTTP server's start |

The 15 s start and 4 s stop in the brief include `tun`'s own process
(4.4 s for any `bin/tun` command) and a busier machine; inside `tun
check`, which starts one `tun` for all its checks, the stop is half a
second.

**Browser checks**

| What | Showcase | The client |
|---|---|---|
| Checks / a full run (`tun check`, one after another) | 55 checks, 726 s (a verify round of loop `typescript-client`) | 100 checks, 1751 s, every one passed (the last run in a finished worktree of the client) |
| One check, its start, its run and its stop: median (quartiles) | 10 s (9 to 13); longest 55 s | 17 s (15 to 19); longest 43 s |
| Of which the preview's start and stop | 6.7 s | 11.7 s |
| The check's own time: Python, Playwright and Chromium started, then its steps | about 3 s | 3.4 to 13.9 s, mean 7.3 s (8 checks of the most used scenario run against one preview) |
| Of which the runner with Chromium and one page, nothing else | 0.8 to 1.0 s | the same |
| Assertions recorded in a full run | | 5546 |

**What the client's checks assert.** Every `t.check` of the client's 100
checks and the second client's 10 (their shared helpers, 53 files),
classified by reading each: whether a browser is needed to decide it, or
whether an HTTP request to the server and what it answers (the page's
HTML, a fragment asked for with htmx's headers, the answer and redirect
of a form's POST, a PDF, a mail on the outbox's page) decides it.

| | Sites | % |
|---|---|---|
| Decided by the server's answer to a GET or POST | 826 | 72 |
| Decided by asking for the fragment or posting the form an htmx swap would | 53 | 5 |
| Need a browser | 276 | 24 |
| of which «the page does not scroll sideways» (`scrollWidth <= innerWidth`) after a step, at 390 and 1280 px | 205 | 18 |
| of which anything else | 71 | 6 |
| Sites in all | 1155 | |

The 71 others, by kind: a chooser that narrows as one types, the
toolbar's popovers and sheets, and their sheet at 390 px against a
popover at 1280 px (about 20); controls sized for a finger and rows
spanning a phone's width (about 19); something on the first screen or
within two screens, a warning above its button (about 15); a table's head
row shown, a wide table scrolling in its own box, columns in sight (about
7); the search dialog (Ctrl K and its focus, Enter, the phone's button,
5); the date picker (4); a file control's status line and thumbnails
loaded (4); the scroll position kept and only the list swapped after a
tap (3); the focus put in a field by an alert's link, the page kept after
a download, a tap on a label ticking its box (1 each). Besides, the
runner fails a check whose page has a JavaScript error.

Two more facts from the reading: 96 of the 100 checks are 48 pairs, the
same helper run in English and in Norwegian; none of the Norwegian twins
exercises browser behaviour the English one does not (their differences
are texts, scenario and data). And the long flows reach most of their
assertions through clicks and taps that only stand for a GET or a POST.

**Tun's showcase.** Its 56 checks are Tun's components in a browser:
dragging on a board by touch and mouse, files chosen, dropped and
pasted, push notifications, motion, sheets, dialogs, choosers, preloads,
the loading sign. About ten (downloads, PDFs, the mail preview, sign-in's
return, the public page's title, posted sets, policies' refusals, files
without JavaScript) assert what the server answers; the rest need the
browser.

## Criteria

This loop builds (a) and (c) of the proposal below, as the orchestrator
decided (Decisions, «The direction»).

1. **A client's suite in parallel.** `tun.test-support` exports
   `run-tests-in-parallel`, taking the tests' packages to run (the
   client's and each module's) or FiveAM suite names. A package's suite
   is the FiveAM suite named as the package without `TUN.` and `.TESTS`
   (`NOTES.TESTS` → `NOTES`, `TUN.BILLING.TESTS` → `BILLING`) when
   `fiveam:get-test` names a suite of that name, which must then be what
   the package's `RUN-TESTS` runs; otherwise its `RUN-TESTS` runs whole,
   as one unit. With more than one
   worker it forks the workers from its own process, the strictly
   compiled image, each with its own output; they take units, a test of a
   suite or a share of a split test, the longest first by the times of
   the last run in `.build/test/times` and one with no time before them
   all. At the end it prints a line a unit, `ok` or `FAIL` with its name,
   then each failed unit's output in full, then one line per suite with
   its tests and failures and one with the units, the workers and the
   seconds, and returns true only when every check of
   every unit passed. A worker that ends while running a unit fails that
   unit, naming it. A suite of passing, failing, erroring and crashing
   tests gives the same verdicts in workers as one after another; a
   package with no suite of its name, or a symbol of that name that is
   not a suite, runs its `RUN-TESTS` whole. (test)
2. **One worker is today's run.** With one worker (`TUN_TEST_JOBS=1`, or
   a machine that allows one) it runs each package's `RUN-TESTS`, or
   each suite with `run!`, in this process, one after another, as
   `tests/run.lisp` does today, forking nothing. (test)
3. **How many workers.** `TUN_TEST_JOBS` when set, else the smaller of
   the processors and the available memory less 4 GB over 1.5 GB a
   worker, at least 1. (test)
4. **Split tests.** The generated fuzzing test and the scenario test
   (`testing.md` §1, tests 5 and 6) run as up to four units each, every
   one over every Nth tool or scenario, so that together they fuzz every
   tool and make every scenario once; the fuzzer's summary names its
   share. Run whole (one worker), they are as today. (test)
5. **The template calls it.** `tun new`'s `tests/run.lisp` runs the
   client's suite and its modules' through `run-tests-in-parallel`;
   `bin/test-cli`'s new client passes `bin/test` with it, and a failing
   test is named in its output. A client keeps its `tests/run.lisp`
   until it changes it; `docs/client-api.md` says what to change. (test,
   bin/test-cli)
6. **Checks from one image.** Unless `TUN_CHECK_IMAGE=0`, `tun check`
   starts one SBCL that loads the client and its tests (compiling what has
   changed) and saves an image, starts one Postgres server for the run,
   and makes each scenario its checks start from once for each worker
   that runs one of them, in a template database served from that
   worker's port. Each check then gets a database copied from its
   scenario's template and a server of its own started from the image,
   both removed when it ends: no check sees what another changed
   (`preview.md` §2, §4). (test, bin/check, client runs)
7. **A scenario that is more than records is made per check.** Making a
   scenario's template, Tun compares the global variables of the client's
   own packages, and Tun's isolated variables (`testing.md` §1), before
   and after: one whose value changed, or whose hash table's count or
   list's length did, makes the scenario per check, on an empty
   database, as today, and `tun check` says so, naming the scenario. A
   scenario that sets a variable is found and one that only makes
   records is copied. (test)
8. **Workers.** `tun check` runs its checks in `TUN_CHECK_JOBS` workers,
   else the smaller of 4, a third of the processors and the available
   memory less 6 GB over 1.5 GB a worker, at least 1, each with its own
   port and database. It prints each check's result in the order of the
   files, in today's words, and ends as today: «Every check passed» or
   «N of M checks failed», exit 1 on a failure, `NAME.json` and its
   screenshots in `.build/checks/`. With one worker the checks run one
   after another. `TUN_CHECK_IMAGE=0` runs today's way, a fresh preview
   per check. (test, bin/check)
9. **Ready for a check Tun makes.** The runner runs a list of checks,
   each a name, a scenario and the file the runner drives, so a check
   that Tun generates (the next loop) joins the list. (test)
10. **A Tun loop's clients at once.** `tun clients test DIR... [--jobs N]
    [--log DIR]` runs each client's `bin/test` on this Tun's committed
    head: in the dev shell of the client's flake (the nearest `flake.nix`
    at or above DIR), with `--override-input` for every input of its
    `flake.lock` that is Tun's repository (the kernel, and each module by
    its `dir`), each command given as a list of arguments, never through
    a shell. N at once (`--jobs`, else the available memory less 4 GB
    over 4 GB, at least 1), the whole run under one hold of the verify
    lock, and each client's `bin/test` given `TUN_TEST_JOBS` of the
    processors over N, at least 1, so N clients' workers do not crowd the
    machine; each client's output in `--log`'s `NAME.log` (default
    `.build/clients/`), NAME the client's directory's name, with its
    repository's before it when two are the same; one line a client,
    `ok` or `FAIL`, its name and seconds; exit 1 when one failed. It
    refuses a working tree with changes, whose head is not what it would
    test, and a client whose `flake.lock` pins no Tun, naming it. (test,
    proof run)
11. **Measured after.** On this machine, each three times or more, before
    and after, under the verify lock, with its pass rate, times and the
    lowest available memory in the Log: the client's test step, with its
    `tests/run.lisp` changed to call `run-tests-in-parallel` in a scratch
    clone (13 minutes before; after: at most 3); its 100 checks (29
    minutes; after: at most 8); Tun's showcase checks (12 minutes; after:
    at most 5); and a Tun loop's client runs by `tun clients test`
    (factory, nixploy-dashboard, ferdig, kurs and both clients of the
    two-client repository; after: within 3 minutes of the slowest one's
    `bin/test` alone). (Log)
12. **No new flakiness.** Every check that passes one after another
    passes in the workers, in every repeated run; one that does not is
    mended by waiting for the event it reads (`preview.md` §4), never by
    a fixed wait, and named here; a client's check that fails for a
    reason of its own is named, not changed. (Log)
13. **Clients unchanged.** Every client passes its own `bin/test`
    unchanged against this tree, from scratch clones, run by `tun clients
    test`. (Log)
14. **Where people read it.** `spec/testing.md` (running a suite in
    parallel, the split tests), `spec/tooling.md` («Running the tests»),
    `spec/preview.md` §4 (the image, the templates, the workers),
    `spec/cli.md` §5.2, `spec/loop.md` §6 and `docs/loop.md` §5 (`tun
    clients test`), `spec/cli.md` §6 (the template), `docs/client-api.md` («Previews,
    scenarios and browser checks», and the client's `tests/run.lisp`).
    Core 2.50.0 (`+core-version+`, `coreVersion`); `bin/build`
    warning-free, `bin/test` and `bin/check` green. (verify)

## Decisions

**What the numbers say.** The build is not where the time goes: Tun
compiles from nothing in 22 s and the client in 15 s, and Tun is not
compiled in a client's build at all (it comes compiled from the Nix
store). A client's round is 13 minutes of tests in one process on one of
twelve processors, and 30 minutes of browser checks of which two thirds
is starting and stopping a server per check (11.7 s of a median 17 s)
and the rest mostly assertions a browser is not needed for. Lisp's own
iteration is fast here: a test of the client runs in a live image in
milliseconds to seconds, and a change compiles in seconds; the verify
round is slow because it does all of the work, serially, every time.

**Proposal**, for the owner to choose from; minutes for the client's
round (today 13 + 30 = 43 minutes for its first client), each part
alone and then together.

*(a) The test step: from 13 minutes to about 2.*

1. The suite in parallel processes, as Tun's own `bin/test` already runs
   its 102 suites (1885 s of work in 192 to 217 s). The strict compile
   stays once (20 s) and is saved as an image (6 s); then up to N
   workers start from it in 0.05 s each, N from the processors and the
   memory available (8 here), and take the tests longest first: each
   module's suite, the client's suite split by test, each generated test
   apart, and the fuzzer split by tool across the workers. Work 777 s / 8
   is about 100 s; the floor is the longest single test (the scenario
   test, 47 s, or a property test, 42 s). So about 2 minutes with the
   compile: **saves about 11 minutes.** Output still names every
   failure, by its test, as now; `bin/test` stays the command. Each
   client's `tests/run.lisp` changes once to call it (the template's
   does in Tun), so it reaches a client when that client takes it.
2. A scenario made once per run, copied per test: a test that makes a
   scenario on a fresh database pays 2.4 to 3.4 s for migrations and the
   scenario; a Postgres template database copies in 0.04 to 0.07 s.
   About 80 tests do this: **saves about 200 s of work** (25 s of wall
   time once in parallel). Tun's `with-test-app` and `run-scenario` take
   it without the client changing where the scenario only makes records
   (below, (c), for the in-memory part).
3. Not proposed: making the fuzzer or the property tests smaller for a
   loop's verify. Split across workers they cost their wall time once
   (the longest, 42 s), and a smaller count finds less; if the owner
   wants a loop's verify smaller still, that is the owner's choice
   (report).
4. Not proposed: caching the compile across steps or rounds. It is 20 s.

*(b) Few browser checks: from 30 minutes to about 4, or 1 with (c).*

The rule: **a browser check only for what only a browser decides**:
script behaviour (a chooser narrowing as one types, dialogs, sheets and
popovers, a date picker, keyboard and focus, a page's timers), touch,
and layout at 390 and 1280 px. Whatever the server's answer decides (a
page's texts, parts, links, fields and their values, a status, a
redirect after a POST, a fragment, a PDF, a mail on the outbox, the
language of a page) is a test in the suite over HTTP, with Tun's
`with-test-server`, `web-login` and `web-request` and a small reader of
the answer's parts and forms that Tun would add. A language twin is one
test of the texts, or nothing where Tun's generated translation tests
already decide it.

What it means for the client: of its 1155 assertions, 879 (77 %) move to
HTTP tests. Of the 276 that need a browser, 205 are «the page does not
scroll sideways», which becomes **one check that Tun generates**: every
page the page sweep (`open-every-page`) reaches, for each role, at 390
and 1280 px, with no sideways scroll and no JavaScript error, and its
screenshot. The other 71 fit in about 6 checks of the client's own: the
chooser and the toolbar's popovers and sheets; the search dialog and the
date picker; controls sized for a finger and what must be on the first
screen; tables on a phone (head row, scrolling in their own box);
files (status line, thumbnails); a tap that keeps the scroll and swaps
only the list. So **about 7 browser checks instead of 100** (the second
client's 10 to 1 or 2). Today's machinery runs 7 checks in about 7 × (12
s + 10 to 20 s) = 3 to 4 minutes; the HTTP tests that take their place
cost about 1 to 2 minutes of work, about 15 s of wall time in parallel
((a)). **Saves about 26 minutes.** The checks are the client's to
convert, in a loop of its own; Tun's part is the rule (its
`docs/loop.md` «Criteria a browser shows become browser checks», and
the factory's playbook step 7 that asks for a browser check at both
widths for every criterion), the reader for HTTP tests, and the
generated width sweep.

*(c) What remains of the image, template and workers plan: worth it,
smaller.*

- For the client after (b): 7 checks of which 12 s each is the server's
  start and stop. A saved image (load 3.4 s → 0.05 s), one database
  server per round (0.9 s start and 0.3 s stop → once), the scenario
  copied from a template (migrations and the scenario, 3 to 6 s → 0.6
  s) bring a check's server to about 1 s; with 3 workers the check step
  is **about 1 minute: saves 2 to 3 more minutes**.
- For Tun's own verify, where it matters more: the showcase's 56 checks
  are nearly all real browser behaviour (dragging, files, push, motion,
  sheets), 12 minutes today, 6.7 s of each the server's start and stop.
  With (c), **about 6 minutes serially and about 2 with 4 workers: saves
  about 10 minutes** of every Tun loop's round.
- A Tun loop's client runs: one `tun` command that runs every client's
  suite against the tree, in parallel, under one hold of the lock
  (today a builder's script, at least 18 minutes of suites plus lock
  waits between holds); with (a) in the clients, **about 3 minutes**.
- The template needs a care the brief did not have: two clients'
  scenarios set global variables (a fake service's state, a handler for
  calls to other systems) besides making records, which a copied
  database does not carry. The safe reading: the scenario is made once,
  and a scenario that changed a global variable of the client's own
  packages or one of Tun's isolated ones is made per server as today,
  so only scenarios that make records alone are copied.

*Together:* the client's round from 43 minutes to about 3 or 4 (test 2,
checks 1, the rest build and bookkeeping), and Tun's own round from
about 16 minutes (test 3.5, check 12) to about 6.

*Order, if the owner takes it all:* (a)1 and (c) are Tun's, this loop
or two; the generated width sweep and the HTTP reader of (b) are Tun's,
a loop of their own; the conversion of the client's checks is the
client's, after them.

**The direction.** The orchestrator, 2026-11-17, within the owner's
direction of the same day («we have to minimize or basically almost
remove the browser checks … we need to spend some time optimizing
this»): this loop builds (a), the test step in parallel workers from one
strictly compiled image, longest work first, the fuzzer and the client's
suite split, with each client's `tests/run.lisp` calling it; and (c), the
image, the template databases (only for scenarios that only make
records), parallel check workers inside the one lock, and one `tun`
command that runs a Tun loop's client suites in parallel under one hold
of the lock. The answers to the three questions of the proposal: (a)
and (c) here and (b) next; browser checks only for what a browser alone
decides, the owner's own direction, which is (b) and so the next Tun
loop's (the reader of a page's parts and forms for HTTP tests, the
generated sweep of every page and role at both widths, the rule in
`docs/loop.md`): this loop does not build it, but leaves the check runner
ready for a check Tun generates (criterion 9); and the fuzzer and the
property tests at full size, split across workers.

- **The test workers are forks of the compiled process.** After the
  strict compile, the process holds exactly the image the brief asks
  for, and only its main thread runs (measured: forking it three times
  gave three children that saw the client's packages). A fork costs
  milliseconds and shares the memory until a worker writes it; a saved
  image would cost 6 s and 294 MB on disk and then the same. No test
  runs before the fork, as the parent only compiled.
- **The check servers start from a saved image.** They are programs
  `tun` starts, not children of the client's process, and each must be
  a server of its own (its port, its database, its state). The image is
  saved by an SBCL loaded as a preview's server is, into the check's
  data directory, and removed when the run ends; never kept across
  runs, so never across a change of the code. A server from it sets up
  ASDF's registry again as a preview's does, and starts from the random
  state SBCL starts with, which the image keeps (a fresh SBCL's is the
  same every start, so a scenario that draws random values makes the
  same data in a check as in a preview; a first version seeded it anew
  in every server, previews too, which gate B's reviewer found).
- **The worker counts are from memory as much as processors.** 31 GB
  here and other builders beside: the defaults keep 4 GB (tests) and
  6 GB (checks) free beyond what the workers take (1.5 GB each, to be
  confirmed by the peaks measured in the Log), and the variables
  override them.
- **One worker is today.** `TUN_TEST_JOBS=1` runs `run!` as before;
  `TUN_CHECK_JOBS=1` runs the checks one after another, from the image;
  `TUN_CHECK_IMAGE=0` is today's path itself, kept for a client whose
  scenario the comparison cannot judge.
- **A scenario's state.** The safe reading from the proposal: a template
  holds records only; the comparison of globals finds a scenario that
  sets a variable (two clients' do: a fake service's state, a handler
  for calls to other systems), whose checks then make it per server as
  today. A scenario that changes an object in place without changing a
  variable, a count or a length is not seen; `TUN_CHECK_IMAGE=0` is the
  way back for such a client, and the spec says so.
- **A template for each worker's port** (after gate A, from the build).
  The client's scenarios make mails whose links hold their server's
  address (`--public-url`): a template made at one address and copied to
  a server at another would show links to the first, which another
  check's server may answer. Made with a sentinel address, every one of
  the client's scenarios held it (in its mails and its messages to
  customers). So a worker keeps one port for all its checks and makes a
  scenario's template, served from that port, the first time it runs a
  check of the scenario: the records are those a preview on that port
  would have made, never rewritten. A scenario costs at most one making
  per worker (four), still once rather than once per check.
- **`expect_post` waits for the page a form's post leads to.** In the
  second round of workers (after-0, Log) the client's `crm-nb` failed
  once, «the refusal's reason is shown in place», its screenshot a blank
  page: the check posts a form the browser sends itself (no htmx), takes
  the answer from `expect_post`, and reads the form at once, while the
  browser is still putting the answer's page in place. Playwright gives
  the answer as soon as its head arrives, so on a busier machine the read
  comes before the page: a wait that guessed the page would be there. The
  runner's `expect_post` now, for such a post, waits for the page the
  answer leads to (after a redirect, the one it leads to), loaded, as the
  check reads it next (`preview.md` §4); an answer that is a download or
  no content leads to no page and is not waited for. The client's check
  is not changed: it passes with the runner as it is (the rounds after,
  Log). No fixed wait was added anywhere.
- **`page.goto` waits for the page's service worker to be in place.**
  ui-fields failed twice in about sixteen runs of the showcase in
  workers (verifies 3 and 8), at the same step: a `page.goto` whose page
  never had its load event in 120 s. The kept server log of the second
  shows the server answered that page in 11 ms, in the same second as the
  browser fetched `/sw.js`, the worker's assets and `/offline`: the
  showcase's service worker was installing (it had changed with the
  page's language), and its `activate` claims the open pages
  (`src/web/web-app.lisp`); a navigation begun while it does can wait
  for its load for ever in Chromium. The runner's `goto` now first waits
  until no service worker of the page is installing, waiting or
  activating (the event the navigation needs, with the page's one
  deadline), then navigates. The registrations come in a promise, which
  Playwright's `wait_for_function` does not wait for (a first version
  took the promise for a true value), and a page polled by its own
  timers stands still under `page.clock`: the runner asks with
  `evaluate`, which waits for the promise, between the check's own waits
  (`poll_until`). A first form that polled in the page waited 120 s in
  every check that holds the page's clock. Whether a
  person's browser can stall the same way, a page claimed mid-load, is
  the service worker's question for a later loop (report); the check
  and the worker are unchanged.
- **`tun clients test` takes clones, not repositories.** It runs the
  client in the directory it is given and writes nothing there but what
  its `bin/test` writes; the builder clones first, as the playbook says.
  A module input is overridden at the same commit with its `dir`; the
  command is a list of arguments, so an `&` in a URL is never a shell's.
- **Left out of this loop:** the scenario templates in the suite's own
  tests (proposal (a)2, about 200 s of work, 25 s of wall time once the
  tests run in parallel), not in the direction; and everything of (b).
- **Estimate.** 6h / 9h / 16h, like `tun/checks-under-load` (14h 41m,
  with hours of proof runs) and `tun/test-timing`: three parts in Tun's
  test support and CLI, each with tests, and proof runs of the client's
  suite and its 100 checks, three times each before and after, under a
  lock other builders share. The measurements did not change the
  brief's guess much; the proof runs are what is long.

## Clients

What a client changes to take the parallel suite: the last form of its
`tests/run.lisp`, the one that calls each `RUN-TESTS`, becomes the call of
`run-tests-in-parallel` with its tests' package and each module's
(`docs/client-api.md`, «Previews, scenarios and browser checks»), once it
is on core 2.50.0; a second client of a repository the same in its own
`tests/run.lisp`, with its package alone. Until then its suite runs in
one process, as before. Its checks need no change: `tun check` runs them
from one image in workers on any client, and a scenario that sets a
variable (two of the client's, a module's controls of a fake service) is
made per check, as `tun check` says.

Nothing of a client's checks has to change for the workers: every one
passed in them (Log). A test of the client's that relied on another having
run before it would fail only in the workers (`docs/client-api.md`); none
did.

## Actuals

```json
{"loop":"fast-checks","title":"A verify round in minutes: one image and one database server per round, scenarios as templates, checks and suites in parallel inside the one lock","repository":"tun","mode":"reviewed","stage":"done","item":"sak_y2wez8ch679ffv0w","tags":["kind:tooling","core"],"like":["tun/checks-under-load","tun/test-timing"],"started":"2026-11-17 18:51","ended":"2026-11-18 12:27","minutes":{"total":1056,"waiting_person":0,"waiting_reviewer":9,"working":1047,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":360,"likely":540,"worst":960,"at":"brief"},"latest_estimate":{"best":360,"likely":540,"worst":960,"at":"brief"},"within_estimate":false,"ratio":1.96,"verify":{"rounds":9,"failed":3},"changes":{"A":1,"B":3,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-17 18:51  started, reviewed
- 2026-11-17 19:26  measured before any change (record, «Measured»): Tun compiles from nothing in 22 s and the client in 15 s; the client's test step is 777 s of tests in one process; its 100 checks 1751 s, a median 17 s each of which 11.7 s the server's start and stop; of the client's 1155 check assertions 77 % need no browser and 205 of the other 276 are one sideways-scroll check. Proposal under Decisions; stopped before gate A for the owner's direction
- 2026-11-17 19:34  estimated 6h 9h 16h at brief, like tun/checks-under-load tun/test-timing
- 2026-11-17 19:35  gate A asked of a reviewer
- 2026-11-17 19:36  gate A: changes (reviewer)
  I'm recommending changes at gate A. The criteria cover what the brief and the recorded direction ask for, almost all of them can be checked, and the spec text matches them closely. Three things need fixing before the build starts, and two smaller ones are worth fixing at the same time.
  
  **What is right**
  - **The criteria cover the direction, (a) and (c), and stop there.** Parallel suites (1–4), the template calling it (5), the image, templates and workers for checks (6–8), the runner ready for checks Tun generates (9), `tun clients test` (10), before/after timings with numbers to hit (11), no new flakiness (12) and clients unchanged (13). Leaving out (b) and (a)2 is said plainly under Decisions.
  - **Each one can be decided.** Each criterion says how it is checked (test, `bin/test-cli`, `bin/check`, Log, proof run), and the timings in 11 are concrete: at most 3 minutes for the client's test step, 8 for its checks, 5 for the showcase.
  - **The spec agrees with the criteria.** `spec/preview.md` §4 and `spec/testing.md` «In parallel» match criteria 1–4 and 6–9, including the worker formulas, the "longest first, no time before all" order, the split-test shares, the scenario-variable test and its message, and the `TUN_CHECK_IMAGE=0` way back.
  - **Hard cases are handled.** A scenario that changes state in place isn't detected, and the spec says so. The `&` in a URL is never passed through a shell. The image is never kept across runs.
  
  **Changes**
  
  1. **How `tests/run.lisp` picks a module's suite is in the spec but in no criterion, and the rule is unsafe** (`spec/cli.md` §6 in the diff, and the `docs/client-api.md` snippet, diff lines 20–24).
     - The rule: run the suite named after the module (`TUN.NAME.TESTS::NAME`) if a symbol of that name exists, otherwise the module's `RUN-TESTS` whole.
     - `find-symbol` returns any symbol of that name, not only a FiveAM suite. And a module whose `RUN-TESTS` does more than `(run! 'NAME)` (more suites, or setup) would silently lose tests.
     - Fix: take the suite only when it is one (`fiveam:get-test` names a suite), and say in the spec that it must stand for the module's `RUN-TESTS`. Then add this to criterion 5 with a test, for example a module with no suite of its name still running whole.
  
  2. **`spec/cli.md` §5.2 says more than criterion 10.** It also:
     - gives each client `TUN_TEST_JOBS` = processors / N;
     - refuses a client that pins no Tun;
     - defaults `--log` to `.build/clients/`;
     - names clients from the same repository apart (`tun-erp-second`).
  
     These are real behaviours, and the `TUN_TEST_JOBS` share is what keeps N clients from oversubscribing the machine in criterion 11's measurement. Add them to criterion 10 so they get tested, or take them out of the spec.
  
  3. **Criterion 2's wording contradicts the spec.** "runs each suite in its own process with `run!`" reads as one process per suite. `spec/testing.md` says "in this process … one after another, and forks nothing". Change the criterion to say "in this process".
  
  4. **The direction should come from the owner, but the Log doesn't show it did.** The Brief says the loop "stops before gate A for the owner's decision". Under Decisions, «The direction» is the orchestrator's, "within the owner's direction". Most importantly, putting off "almost remove the browser checks", (b), to a later loop is a choice the owner set up for themself, and there is no Log line for it. Add a Log entry saying who decided (a)+(c) now and (b) next, and when. If the owner hasn't answered, ask them before the build starts.
  
  5. **Small: the `docs/client-api.md` snippet hard-codes the example's names.** It uses `NOTES-CLIENT` / `NOTES-CLIENT.TESTS` (the docs' running example) with no note that a client puts its own package and suite there. A client copying it word for word would fail at `find-symbol`. Add one sentence saying so.
- 2026-11-17 19:36  direction (Decisions, «The direction»): decided by the factory's orchestrator on 2026-11-17, within the owner's direction of the same day («we have to minimize or basically almost remove the browser checks … we need to spend some time optimizing this»), brought to this loop in the orchestrator's message: this loop builds (a), the suite in parallel workers, and (c), the image, the templates, the check workers and tun clients test; (b), the HTTP reader, the generated width sweep and the rule in docs/loop.md, is the next Tun loop, which the orchestrator starts when this one lands; the fuzzer and property tests at full size, split across workers. Not asked of the owner here: a builder asks no person (the playbook); the report names it
- 2026-11-17 19:37  gate A asked of a reviewer
- 2026-11-17 19:38  gate A: approve (reviewer)
  I approve gate A. All five changes from the first review are fixed, and I found nothing new that blocks the build.
  
  **The first review's five points**
  
  1. **How a package's suite is chosen** is now in criterion 1, with tests. The suite is used only when `fiveam:get-test` names one, and it must be what the package's `RUN-TESTS` runs. A package with no suite of its name, or with a symbol of that name that is not a suite, runs its `RUN-TESTS` whole. `spec/testing.md` (diff lines 225–231) says the same, and also covers a package that runs more than one suite.
  2. **Criterion 10 now has what `spec/cli.md` §5.2 says.** It covers each client's share of `TUN_TEST_JOBS`, refusing a client that pins no Tun, the default `.build/clients/` log folder, naming two same-named clients apart, refusing a changed tree, and passing commands as a list of arguments. All of these are now tested.
  3. **Criterion 2 now says "in this process … forking nothing"**, which matches `spec/testing.md` (diff lines 234–237).
  4. **The Log now says who chose the direction.** The orchestrator decided on 2026-11-17 to build (a) and (c) here and (b) in the next Tun loop. It did so within the owner's quoted words, did not ask the owner, and the report will say so. The orchestrator wrote the item, so it is the asker. Its choice follows the owner's words: (a) and (c) are the optimizing, and (b) is the next loop, which the orchestrator starts when this one lands. The owner was not asked, but that is now on record rather than hidden. I don't think it needs to be asked again at this gate.
  5. **The `docs/client-api.md` snippet now says to put in the client's own tests' package** (diff line 26). I compared it with `src/cli/template/tests/run.lisp:57-63`. It gets the module packages the same way (`tun-NAME/tests` → `TUN.NAME.TESTS`) and replaces the same last form.
  
  **The criteria and the brief**
  
  - **The brief is covered:**
    - one image per round (6);
    - one database server and scenario templates (6, 7);
    - check workers inside the one lock, with the load each adds measured (8, 11);
    - suites in parallel (1–4);
    - a Tun loop's clients run in parallel (10);
    - timings before and after on the showcase and the client (11);
    - no new flakiness (12).
  - **Nothing is added beyond what was decided.** Leaving out (b) and (a)2 is stated.
  - **Each criterion can be decided.** Each names how it is checked. Criterion 11 has numbers to hit: 3, 8 and 5 minutes, and within 3 minutes of the slowest client.
  - **Templates are only used where they are safe.** A copied database cannot carry a variable a scenario sets, so such a scenario is made per check, and `tun check` names it. The spec states the case that cannot be seen, an object changed in place, and gives `TUN_CHECK_IMAGE=0` as the way back.
  
  **The spec against the criteria**
  
  `spec/preview.md` §4 matches criteria 6–9, with the same worker formulas, template rule, message and old way back. `spec/testing.md` «In parallel» matches 1–4, including longest first by the last run's times and each share of a split test taking every Nth tool or scenario. `spec/cli.md` §5.2 matches criterion 10.
  
  The spec adds a few details the criteria leave open:
  - the socket folder;
  - `.build/test/units/UNIT.log`;
  - a closing line saying how many passed;
  - "within its git repository" for finding a flake.
  
  These are how the parts work, not new behaviour, so they don't need changes.
- 2026-11-17 20:21  before, from the last full check run kept in each worktree (.build/checks, the span of its results' times): the client's checks, 17 runs from 2026-11-16 00:23 to 2026-11-17 20:07 at 84 to 102 checks, 1366 to 1878 s, every check passed in 16 of them (one run of another loop's tree in progress, 100 of 102); the last five, 98 to 102 checks, 1751 to 1878 s (29 to 31 min). Tun's showcase, 7 runs from 2026-11-15 to 2026-11-17 at 50 to 55 checks, 641 to 797 s, every check passed in all
- 2026-11-17 20:52  a first round after (dev-1, 20:28 to 20:44, under one hold of the verify lock, Tun at 6b45430b, the client at a scratch clone of its main 15c8f50 with its tests/run.lisp calling run-tests-in-parallel): the client's suite in 7 workers, 833 units, every one passed, 275 s in the workers and 336 s for the step (13 min before); its second client's 31 units 16 s, 26 s for the step; the client's 102 checks in 4 workers 348 s, every one passed (29 to 31 min before), two scenarios made per check (they set a variable of a module); its second client's 10 checks 40 s; Tun's showcase, 55 checks, 163 s, every one passed (12 to 13 min before). The lowest available memory 12.7 to 13.1 GB of 31 at loads of 7 to 12. The workers' units took 1858 s together against 777 s one after another: each unit was a fork of its own, so each paid a fork and its first collections; the workers now take units until none is left (one fork a worker)
- 2026-11-17 22:07  verify 2: passed build, test, check
- 2026-11-17 22:08  shown (/)
- 2026-11-17 22:35  rounds after on d7263e15 (each under its own hold of the verify lock): after-0 (22:08 to 22:20) the client's suite 165 s for the step, 833 units in 138 s on 8 workers, every one passed; second client 24 s; the client's 102 checks 360 s, crm-nb failed once («the refusal's reason is shown in place», a blank page: read before the page its form's post led to was in place; Decisions); second client's checks 42 s; showcase 163 s, every one passed. after-1 (22:20 to 22:33) suite 169 s (833 units in 146 s on 7 workers), second client 22 s, the client's 102 checks 350 s, its second client's 43 s, showcase 165 s, every test and check passed. Lowest available memory 12.1 to 13.9 GB, loads 6 to 11
- 2026-11-17 23:31  verify 3: failed check
- 2026-11-17 23:39  verify 3 failed one showcase check, ui-fields: in its last part, page.goto("/fields") had no page in 120 s (Playwright's timeout of the page's deadline), after 64 of its 65 checks had passed; the check's server log went with the check's data, so its cause was not seen. Alone, three of three passed; among seven other long checks in four workers, two of two passed. A failed check's server log is now kept beside its results (NAME-server.log), and the rounds go on to see whether it comes again
- 2026-11-18 00:28  verify 4: passed build, test, check
- 2026-11-18 02:20  rounds after on the final tree (93ddca96; one hold of the verify lock from 01:13 to 02:17 for the three rounds, the suite before and tun clients test): final-1 the client's suite 208 s for the step (833 units in 147 s on 7 workers; the step's nix shell built Tun anew at this revision), second client 24 s, the client's 102 checks 354 s, second client's 10 checks 44 s, showcase 55 checks 165 s, every test and check passed; final-2 suite 159 s (136 s on 8 workers), 20 s, checks 368 s with payment-references failing 5 of its 12 (the scenario's newest invoice was not the one its scenario made last; not seen again in three runs of it and seven others in four workers; cause not found, as its scenario's template log is not kept), 43 s, showcase 161 s every one passed; final-3 suite 155 s (133 s on 8 workers), 22 s, checks 344 s, 38 s, showcase 163 s, every test and check passed. Lowest available memory 12.7 to 14.5 GB of 31, loads 6 to 11
- 2026-11-18 02:20  before, the same tree and the client's same commit (15c8f50), its tests/run.lisp unchanged: the client's suite in one process 760 s, every test passed (01:51 to 02:03, under the same hold)
- 2026-11-18 02:20  tun clients test, every client from scratch clones (tunworks 87cbde1: factory, nixploy-dashboard, ferdig; kurs c2579ae; the two-client repository 15c8f50 and its second client), on Tun 2fb33135 (the final tree), 3 at once with TUN_TEST_JOBS 4 each, the lock taken once: tun-erp 762 s, factory 78 s, nixploy-dashboard 105 s, ferdig 62 s, kurs 48 s, service-trade 45 s, 6 of 6 passed, no compiler warning, 770 s in all (the slowest alone 760 s); the lowest available memory 14.5 GB. Before, one after another (loop posted-sets): at least 18 min of suites. The clients run their tests/run.lisp unchanged, so each suite is in one process until it changes it
- 2026-11-18 02:20  pass rates, every run in workers from dev-1 on: the client's suite 6 of 6 runs every test passed (2.6 to 3.5 min a step once the workers took units until none was left, 5.6 min in dev-1 before; 12.7 to 13 min one after another); its checks 4 of 6 runs every check passed, 610 of 612 checks (crm-nb once before expect_post waited for the page, payment-references once after; 29 to 31 min before, 5.7 to 6.1 min after); its second client's suite and checks 6 of 6; Tun's showcase 8 of 9 runs every check passed (the round's check step 2.7 min against 12 to 13), ui-fields once in verify 3 (its page had not loaded in 120 s; three of three alone and two of two among seven long checks after); verify rounds 2 and 4 passed build, test and check in 6 min against 16. No check was changed and no fixed wait was added; the one mend is the runner's expect_post
- 2026-11-18 02:21  shown (/)
- 2026-11-18 02:21  gate B asked of a reviewer
- 2026-11-18 02:23  gate B: changes (reviewer)
  I'm asking for changes at gate B. The build is solid and fast, but two browser checks failed in the workers and their causes weren't found. The brief asks for "no new flakiness over repeated rounds", and criterion 12 asks for each such failure to be mended or shown to be the client's own.
  
  **What is right**
  - **Verify round 4 passed** build, test and check, and every result in `checks/` passed.
  - **The suite in parallel (criteria 1–5) is built as specified.** Workers are forked from the compiled process and claim units through an exclusive create (`tests/parallel.lisp:2280`). They run the longest first, unknown times before all. A worker that ends while running a unit fails that unit, naming it, and is replaced. One job runs `run!` or `RUN-TESTS` here as before. A package without a suite of its name, or with a non-suite symbol of that name, runs whole. Each of these has a test in `tests/parallel-tests.lisp`, and the shares and the fuzzer's summary are covered by `tests/client/tests/generated-tests.lisp`. The template and the `docs/client-api.md` snippet agree.
  - **Checks from one image (criteria 6–9) are built as specified.** One image and one Postgres server per run, a template per scenario and worker port, and a per-check copy dropped when the check ends. A scenario that sets a variable is found and made per check. Results print in file order, and `TUN_CHECK_IMAGE=0` is the old path untouched. The runner takes a list of checks (`browser-check`).
  - **`tun clients test` (criterion 10)** passes each command as a list of arguments and overrides every input of Tun's repository, modules' `dir` included. It refuses a dirty tree and a client that pins no Tun, and is tested at the unit level.
  - **The measurements meet criterion 11** (with one caveat below): client checks 344–368 s against 29–31 min, showcase 161–165 s against 12–13 min, all clients 770 s against the slowest alone at 760 s. The client's test step is 155–169 s in four of its five final rounds.
  
  **Changes**
  
  1. **Criterion 12 is not met.** Before this change the client's checks passed in 16 of 16 completed runs, and the showcase in 7 of 7. In the workers, payment-references failed in final-2 and ui-fields in verify 3. Neither is mended, and neither is shown to fail one after another, so neither is shown to be the client's own (Log 02:20, 23:39).
     - **Keep the template's log.** A template's `server.log` (`src/cli/check.lisp:641`) is deleted with the data directory when the run ends, so payment-references' cause can't be seen. Keep it beside a failed check's results, as `NAME-server.log` is now (`check.lisp:766-771`).
     - **Investigate one likely cause.** `serve-preview` now calls `(setf *random-state* (make-random-state t))` for every server (`tests/scenarios.lisp`, diff line 2629). That includes templates, plain previews and the `TUN_CHECK_IMAGE=0` path. Before, each fresh SBCL started from the same fixed random state, so a scenario that draws random values made the same data every time. Now it doesn't. That could explain "the scenario's newest invoice was not the one its scenario made last".
     - **Then decide each failure.** Run payment-references and ui-fields repeatedly in the workers and with `TUN_CHECK_IMAGE=0`, and either mend the cause or show that it fails one after another too, as criterion 12 asks.
  2. **Revert the unrelated re-indentation.** The diff re-indents untouched code in:
     - `src/cli/check.lisp`, `src/cli/preview.lisp`, `src/cli/main.lisp`
     - `tests/fuzzing.lisp`, `tests/generated.lisp`, `tests/scenarios.lisp`, `tests/support.lisp`
  
     Several hunks are now harder to read. For example, in `preview.lisp`'s `start-server` (diff lines 1274–1283), the forms after `do` sit level with the loop keywords, and the continuation line of the `fail-step` format string no longer lines up. In `check.lisp`'s lock reporter (diff 419–425), `format` is no longer aligned with `sleep` inside `loop`. These hunks add noise to the review and to `git blame` and change no behaviour. Keep only the lines the change touches.
  3. **Small: put the thread fallback in the spec.** `run-tests-in-parallel` silently runs in this process when other threads exist (`tests/parallel.lisp:2366-2372`). `spec/testing.md` «In parallel» should say so in one sentence.
  
  **Not blocking**
  - **One test step went over 3 minutes.** The client's step was 208 s in final-1, over criterion 11's 3 minutes, because its nix shell rebuilt Tun. Say in the Log that a rebuild is outside the measure, or count it.
  - **Some helpers are duplicated.** `check.lisp`'s `available-gb`, `environment-jobs` and `default-check-jobs` repeat `tests/parallel.lisp`'s `available-memory-gb`, `jobs-from-environment` and `default-jobs`, and the two treat bad input differently.
- 2026-11-18 02:34  gate B 1: changes. Done: the re-indentation of code the change does not touch is taken back (each file's diff is now only its lines); a server no longer seeds its random state anew: a fresh SBCL starts from the same one every time (277986140 its first draw, twice), so the image keeps the state its maker started with and a check's server starts from it, as a preview's does; a failed check keeps its template's server log too (NAME-template.log); the spec says a process with threads runs its suites in itself. The final-1 step of 208 s includes nix building the shell anew for the revision (the units took 147 s); the measure is the step as a builder runs it. Neither failure came again: payment-references with seven other billing checks in four workers 3 of 3 and alone the old way 2 of 2; ui-fields with seven other long checks in four workers 3 of 3 and alone the old way 2 of 2. Payment-references' scenario makes its invoices through calls whose answers it does not check, and the newest invoice it read was not the one the scenario made last; with the random state now that of a preview, the rounds on this tree say whether it comes again
- 2026-11-18 02:40  verify 5: failed test
- 2026-11-18 02:42  verify 5 failed the core suite waiting, a test this loop does not touch: a-wait-outlasts-two-rechecks-in-real-time, «woken by the change at 11 s, not a later look: 11.00 s, not at least 11 s (wall time; load 9.63 on 12 processors)», the wall clock at the boundary under another builder's load; alone it passed 54 of 54; verify again
- 2026-11-18 02:48  verify 6: passed build, test, check
- 2026-11-18 03:39  verify 6 passed build (11 s), test (179 s) and check (164 s). Rounds after on this tree (6462d1d3, one hold of the verify lock from 02:48 to 03:38 for three rounds and tun clients test): the client's suite 197, 161 and 163 s for the step (833 units in 136, 138 and 141 s on 7 or 8 workers; the first step's nix shell built Tun anew for the revision), every test passed; second client 25, 20 and 20 s; the client's 102 checks 356, 344 and 344 s, every check passed; its second client's 10 checks 46, 43 and 44 s; Tun's showcase 167, 163 and 165 s, every check passed. tun clients test: tun-erp 752 s, factory 78 s, nixploy-dashboard 111 s, ferdig 63 s, kurs 48 s, service-trade 43 s, 6 of 6, 757 s in all. Lowest available memory 12.6 to 14.6 GB of 31, loads 6 to 13. Over every run in workers on the tree since expect_post waited for the page (final-1 to 3, last-1 to 3): the client's 612 checks passed but one (payment-references in final-2), Tun's showcase 6 of 6 runs every check passed besides verifies 4 and 6, the suites every test
- 2026-11-18 03:39  shown (/)
- 2026-11-18 03:39  gate B asked of a reviewer
- 2026-11-18 03:41  gate B: changes (reviewer)
  I'm asking for changes. Everything gate B 1 asked for has been done, but taking back the re-indentation left two of the changed functions indented in a way that hides how they nest.
  
  **What is right**
  - **Verification:** verify round 6 passed build, test and check, and none of the results in `checks/` failed.
  - **The three requested changes are in:**
    - **Random state.** Servers no longer seed their random state anew. The image saves the state SBCL started with (`tests/scenarios.lisp`, `save-check-image`, and `build-check-image` in `check.lisp`), so a check's server starts from the same state as a preview's. `spec/preview.md` §4 says so (diff 280–283).
    - **Template log.** A failed check keeps `NAME-template.log` beside `NAME-server.log` (`check.lisp`, `run-one-check`, diff 714–723). The path it reads is the one `seed-template` writes to, and the spec says so (diff 317–318).
    - **Thread fallback.** `spec/testing.md` now says a process that runs threads runs its suites in itself (diff 358–359).
  - **The unrelated re-indentation is gone.** The `main.lisp`, `fuzzing.lisp`, `generated.lisp`, `support.lisp` and `check.lisp` hunks now touch only the changed lines.
  - **Criterion 12 is now reasonably met.**
    - **payment-references** failed once (final-2). That was on the tree that reseeded every server, which plausibly explains its "newest invoice is not the one made last". Since that was taken back, verify 6 and three full rounds on this tree all passed: 102 checks per round for the client, the showcase every time.
    - **ui-fields** failed once, in verify 3. It has not come back in any run since, in the workers or alone.
    - Both are named in the Log. No check was changed and no fixed wait was added.
  - **Criteria 1–11 and 13** are as the first gate B review found them, with tests in `tests/parallel-tests.lisp`, `tests/check-run-tests.lisp` and `generated-tests.lisp`. The timings in criterion 11 are met: client checks about 345 s against 29 minutes, the showcase about 165 s against 12, the client's suite 161–163 s (197 s when nix rebuilt the shell), and `tun clients test` 757 s against the slowest client alone at 752 s.
  
  **Changes**
  
  1. **`tests/scenarios.lisp:245-253`, `serve-preview`'s `:before-serving` lambda (diff 2199–2209).** The change wrapped the old body in `(cond (seed …) (t (when (and scenario (not made)) …)))`, but the old lines kept their old columns:
     - `(let ((*app* application))` sits to the left of the `when` that contains it.
     - `(when report` lines up with `(cond`, so it reads as the cond's sibling. In fact it is inside the `t` clause, so a template server never writes the preview report.
  
     Re-indent this lambda (`bin/indent` on the form, or by hand) so the columns show the nesting. The lines are part of the change, so this is not the unrelated re-indentation gate B 1 asked to take back.
  2. **`src/cli/preview.lisp:374-383`, `client-lisp-command` (diff 1086–1108).** The `let*` was removed and its body became the function's body, but only some lines were moved. `(append` is at column 4, its first argument at 5, the `if` branches at 7, and the `loop` and `(list "--end-toplevel-options")` at 3. The `loop` therefore looks like a sibling of `append` when it is one of its arguments. Indent the whole body as one form, as `image-lisp-command` just below it is.
  
  **Not blocking**
  - Add one Log line closing criterion 12. It should say that payment-references' failure is put down to the reseeding that was taken back, since it has not come back in any run since, and that ui-fields is named but its cause is unknown. That way the record says what was concluded, not only the counts.
  - **Duplicated helpers.** `check.lisp`'s `available-gb`, `environment-jobs` and `default-check-jobs` still repeat `tests/parallel.lisp`'s helpers, and the two copies treat a bad value differently: `"3x"` is accepted by one and refused by the other.
- 2026-11-18 03:42  gate B 2: changes, the indentation of two changed forms (serve-preview's before-serving, client-lisp-command's body), now each indented as it nests. Criterion 12, concluded: crm-nb's failure was the runner's expect_post handing back a form's answer before its page was in place, mended there (it has not failed in the 6 rounds since); payment-references' one failure (final-2) is put down to the random state every server was then seeded with anew, which made a scenario's data differ from a preview's, and which is taken back: it has not failed in any run since (3 full rounds, 3 runs among billing checks in workers, 2 alone the old way); ui-fields' one failure (verify 3, its page not loaded in 120 s) is named with its cause unknown: it has not come back in 12 runs since, in the workers and alone, and a failed check now keeps its server's and its template's logs for the next one
- 2026-11-18 03:48  verify 7: passed build, test, check
- 2026-11-18 03:48  shown (/)
- 2026-11-18 03:48  gate B asked of a reviewer
- 2026-11-18 03:49  gate B: approve (reviewer)
  I approve gate B. Both indentation fixes asked for at the second gate B review are done. The refactor that came with one of them keeps the old behaviour. Nothing else in the change has changed since that review.
  
  **What is right**
  - **Verification:** verify round 7 passed build, test and check (`verify.txt`).
  - **`serve-preview`'s `:before-serving` (diff 2209–2216):** the code is now indented to show how it nests. The `let` sits inside its `when`, and `(when report …)` is clearly inside the `t` clause. So a template server visibly makes no preview report, which is what the code does.
  - **`client-lisp-command` (diff 1103–1112):** its body is now one `append`, indented like `image-lisp-command` below it. The source-registry and output-translation forms now come from a shared `client-registry-forms` (diff 1052–1071), so the two commands no longer repeat that code. The order of arguments is the same as before: Tun's `setup.lisp` (or ASDF), then the registry, then the output translations, then the forms. `image-lisp-command` uses the same default `preview-fasl` translation as the server it replaces.
  - **Criterion 12 is closed in the Log (03:42) as asked.**
    - crm-nb's failure was mended in the runner's `expect_post`.
    - payment-references' one failure is put down to the per-server reseeding, which has been taken back. It has not failed in any run since.
    - ui-fields is named with its cause unknown. It has not failed again in 12 runs, and a failed check now keeps its server's and template's logs.
  - **Criteria 1–11 and 13 stand as the two earlier gate B reviews found them:** each has tests, and the timings meet criterion 11's targets.
  
  **Not blocking**
  - `check.lisp`'s `available-gb`, `environment-jobs` and `default-check-jobs` still repeat the helpers in `tests/parallel.lisp`, and the two copies treat a bad value differently. This is worth merging in a later change.
- 2026-11-18 03:51  rebased: tun bf706a6 → 44a39c1
- 2026-11-18 04:01  verify 8: failed check
- 2026-11-18 04:02  verify 8 (after the rebase onto 44a39c1, core 2.50.0) failed one showcase check, ui-fields, the same step as in verify 3: in its Norwegian part, page.goto("/fields") had no load event in 120 s. Its kept server log shows the server answered that GET /fields in 11 ms, the last request it had; the same second the page's browser installed the showcase's service worker (/sw.js, its kept assets and /offline fetched) and the worker's activate claims the open pages; the page's assets come from the worker's cache then, and its load never came. So the stall is the browser's, between a navigation and the service worker taking the page, not the server's and not the database's; two in about sixteen runs of the showcase in workers, none in twelve runs one after another (seven before the loop, five alone during it). Not mended here: the check and the worker are Tun's own, outside what this loop changes; named for the next loop. Verify again
- 2026-11-18 04:09  verify 9: passed build, test, check
- 2026-11-18 04:34  verify 9 passed build (10 s), test (183 s), check (167 s). On the rebased tree (97a96849, core 2.50.0), one hold of the verify lock from 04:09 to 04:34: the client's suite 163 s for the step (833 units in 135 s on 8 workers), second client 24 s, the client's 102 checks 356 s, second client's 10 checks 44 s, showcase 169 s, every test and check passed; tun clients test 6 of 6 (tun-erp 761 s, factory 78, nixploy-dashboard 110, ferdig 62, kurs 47, service-trade 44), 768 s in all; lowest available memory 13.1 to 14.8 GB
- 2026-11-18 04:35  shown (/)
- 2026-11-18 04:35  gate B asked of a reviewer
- 2026-11-18 04:36  gate B: changes (reviewer)
  I'm asking for changes: the change itself is fine after the rebase, but ui-fields failed again in the workers, and criterion 12 says that check must be fixed, not just named.
  
  **What is right**
  - **Verification passes.** Verify round 9 passed build, test and check (`verify.txt`), and none of the results in `checks/` failed, ui-fields included.
  - **The rebase added nothing of substance.** Since the last approval, the only new lines in the diff are the version bump to 2.50.0. It is in `+core-version+` (`src/core/module.lisp`, diff 1155), `coreVersion` (`flake.nix`, diff 91) and the regenerated header of `checks/showcase/screen/src/api.ts`, which is what criterion 14 asks for.
  - **The earlier reviews still hold.** Criteria 1–11 and 13 stand as the three earlier gate B reviews found them, each with its tests. The round on the rebased tree meets criterion 11's targets again:
    - the client's test step 163 s
    - its checks 356 s
    - the showcase 169 s
    - `tun clients test` 768 s, against the slowest client alone at 761 s
  - **crm-nb and payment-references are settled**, as the Log's 03:42 entry concluded.
  
  **Changes**
  
  1. **Criterion 12 is no longer met for ui-fields** (Log 04:02).
     - The last approval accepted ui-fields as one failure with an unknown cause that had not come back. It has now come back, at the same step: `page.goto("/fields")` got no load event in 120 s.
     - That is 2 failures in about 16 showcase runs in the workers, and none in 12 runs one after another. That is the "new flakiness" the brief rules out.
     - Criterion 12 lets a check be "named, not changed" only when it is a *client's* check failing for its own reason. ui-fields and the service worker are Tun's own, so the criterion asks for a fix by waiting for the event the check reads. "Outside what this loop changes; named for the next loop" does not satisfy that.
     - A flake in about one showcase run in eight also costs every later Tun loop's verify rounds, which is what this loop is meant to speed up.
     - The cause is now located: the showcase's service worker installs, then calls `skipWaiting` and `clients.claim` (`src/web/web-app.lisp:116`, `:124`, `:196`) during the navigation, and the page's load never comes. Do one of:
       - **Fix it in the runner or the check by waiting for an event, not a fixed delay.** For example, wait until the page's service worker is in control (`navigator.serviceWorker.ready` and a `controller`, or a `controllerchange` once claimed) before the navigations that follow. Then show ui-fields passing over repeated rounds in four workers, in the Log.
       - **Or fix the worker itself**, if a page that gets claimed mid-load can stall in a real browser too. That would be a user-facing bug, not only a check problem.
       - **Or show the failure is not new**: run ui-fields one after another (`TUN_CHECK_JOBS=1`, and `TUN_CHECK_IMAGE=0`) enough times, under a similar load, to show it stalls at a comparable rate there too. Then record it in the Log as an existing flake rather than a new one.
  
  **Not blocking**
  - `check.lisp` still duplicates the job and memory helpers in `tests/parallel.lisp` (`available-gb`, `environment-jobs`, `default-check-jobs`), and the two copies handle a bad value differently.
- 2026-11-18 05:00  gate B 4: changes, ui-fields (Decisions, «page.goto waits for the page's service worker to be in place»). The runner's goto now waits until no service worker of the page is installing, waiting or activating; ui-fields and twelve other checks of workers and page clocks in four workers 2 of 2, every check passed (a first form, polled in the page, never saw the worker settle under page.clock and failed five checks 3 of 3; not kept)
- 2026-11-18 05:06  verify 10: passed build, test, check
- 2026-11-18 05:32  verify 10 passed build (11 s), test (182 s), check (172 s). With goto's wait (5d2af2b6), one hold of the verify lock from 05:06 to 05:32, three rounds of the client's 102 checks and Tun's 55 in four workers: the client's 356, 344 and 341 s, every check passed; the showcase 177, 173 and 171 s, every check passed, ui-fields among them (4 of 4 with verify 10); the wait costs the showcase about 8 s a round. Since goto's wait, every check of both, in every run
- 2026-11-18 05:33  shown (/)
- 2026-11-18 05:33  gate B asked of a reviewer
- 2026-11-18 05:34  gate B: approve (reviewer)
  I approve gate B. The only change since the last review is the fix for the ui-fields failure, and it does what that review asked for, with one gap noted below.
  
  **What is right**
  - **Every step passed.** Verify round 10 passed build, test and check (`verify.txt`). All 60 results in `checks/` passed, ui-fields included.
  - **ui-fields is fixed by waiting for an event, not a fixed delay**, as criterion 12 asks. This was one of the fixes the last review suggested.
    - Before each navigation, the runner's `goto` now waits until no service worker of the page is installing, waiting or activating (`scripts/tun_check.py`, `WORKER_SETTLED` and `goto`, diff 124–155).
    - It uses the existing `poll_until`, so it shares the page's one deadline. It asks with `evaluate`, which waits for the `getRegistrations` promise and is not held by `page.clock`. The Decisions entry explains why an earlier version, which polled inside the page, was dropped.
    - A page with no service worker, or one that is not on http(s), such as the first `about:blank`, passes at once.
  - **It is safe for clients' pages.** Tun's workers, both the installing one and the removing one, call `skipWaiting` (`src/web/web-app.lisp:116`, `:196`). So no registration stays in the waiting state and stalls every `goto`. The client's 102 checks passed in all three rounds after the change.
  - **The spec matches.** `spec/preview.md` §4 describes the new `goto` (diff 291–296), and Decisions has an entry for it, «`page.goto` waits for the page's service worker to be in place».
  - **The evidence:** ui-fields passed in 2 of 2 targeted runs and in 4 of 4 full showcase rounds in four workers. The client's checks passed in 3 of 3 rounds, with no check changed and no fixed wait added. The wait adds about 8 s to a showcase round, which still meets criterion 11 (171–177 s against the 5-minute target).
  - **Criteria 1–11, 13 and 14 still hold**, as the earlier gate B reviews found. Apart from this fix, nothing has changed since the approved rebased tree.
  
  **Not blocking**
  - **The wait can't catch every case.** Before the install starts, while `/sw.js` is still being fetched for a new or changed worker, no registration shows the worker as installing. So the check passes and the navigation goes ahead. The server log from verify 8 shows `/sw.js` fetched in the same second as `GET /fields`, so the fix makes the stall less likely but may not rule it out. Six clean runs against an earlier rate of about one in eight is encouraging but not proof. A failed check now keeps both server logs, so the next failure, if one comes, will show which case it was.
  - **A real user may hit the same stall.** A page whose service worker takes control during a navigation may stall in a person's browser too. That is left to a later loop, which is reasonable because the worker existed before this change. The report should list it.
  - **Duplicated helpers.** `check.lisp`'s `available-gb`, `environment-jobs` and `default-check-jobs` still repeat the helpers in `tests/parallel.lisp`, and the two copies treat a bad value differently.
- 2026-11-18 12:27  finished at tun 8585e5b5
