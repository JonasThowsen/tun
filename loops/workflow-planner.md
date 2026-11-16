# A workflow remembers who planned it, so a requeued run never acts as the system; and two checks' own races

- loop: workflow-planner
- mode: reviewed
- stage: done
- base: 918aea1f63587fe789b8849de4a1ab0d1964af6a
- item: sak_823jdn478xvtr6yj
- estimate: 3h 5h 9h
- like: tun/erase-audit-download tun/pdf tun/checks-under-load
- tags: kind:fix core
- verified: 738aca74ea7a751bc306d6c2d4522e1bb256bb77
- shown: 738aca74ea7a751bc306d6c2d4522e1bb256bb77

## Brief

Ferdig sak_823jdn478xvtr6yj («workflow-planner: a workflow remembers who
planned it, so a requeued run never acts as the system; and two checks'
own races»), brought by the factory's orchestrator on 2026-11-16, after
`erase-audit-download`, whose gate B named the first part as left open.
The item, as filed:

> One feature loop in Tun, after `erase-audit-download` (core 2.44.0,
> `sak_ygs66kh0329hq80h`), which left this open and said so (its gate B
> noted it).
>
> 1. **Who planned a workflow is not recorded.** Since 2.44.0 a job's
>    `enqueued_by` names who asked for it, and `erase-customer` (and
>    anything else that asks «who is behind this job») trusts it. A
>    workflow's run job that fails for good while the workflow stays
>    planned is queued again by the application when it opens, as the
>    system. What the workflow then does is judged as the system's own
>    decision, not as the decision of the person whose call planned it;
>    a caller who may not erase could in that case have an erasure run.
>    Wanted: the kernel's `workflows` table records who planned each
>    workflow (the outermost caller, as `*caller*` gives it); every run
>    job of that workflow, however it came to be queued (first run,
>    retry, requeue at start, a timer), carries that as its
>    `enqueued_by`; a workflow planned before this change, with nobody
>    recorded, is treated as planned by nobody who may do anything a
>    person must be allowed to do (refused, audited), never as the
>    system. Tests: the case above ends refused and audited; an admin's
>    planned workflow still erases after a requeue; a schedule's or
>    trigger's own workflow is still the system's. A migration for
>    existing rows.
> 2. **The docs say more than holds.** `modules/customers/README.md`
>    §5.1 and `docs/client-api.md` say an employee's workflow is always
>    refused. Until 1 lands that is not true in the case above; after
>    it, make the sentence true and say what «who asked» means for a job
>    and for a workflow in one place (`spec/jobs.md`), with the others
>    pointing to it.
> 3. **Review of the same question elsewhere.** List every place in the
>    kernel and the modules that decides by `enqueued_by`, `*caller*` or
>    «is this the system» (confirm tools called from jobs, `with-actor`,
>    schedules, triggers, timers, retries, the dead-letter retry tool
>    `jobs_retry`), and for each say in the record who the decision is
>    attributed to and why that is right; fix what is not. `jobs_retry`
>    in particular: a job retried by a person keeps who first asked for
>    it, and the retry itself is audited with who retried.
> 4. **Two checks with races of their own**, which cost other loops
>    verify rounds: the showcase check `loading-sign` reads the bar after
>    tapping «A fast page» while waiting for text the page already shows
>    (failed the same step in three rounds of the loop above, passed
>    alone); wait for the swap the tap causes (`with
>    page.expect_htmx():`) before reading. Look for the same pattern in
>    the other showcase checks (a wait for text that is already there)
>    and fix those too.
>
> Criteria, each decided by a test: as in 1; the list of 3 is in the
> record with a test per decision that changed; `loading-sign` passes 10
> of 10 under load (the method of `checks-under-load`); every client
> passes.
>
> Not in this loop: new features.

The orchestrator's brief adds: this is a security fix, to be thought
through as someone who may not do a thing and wants it done. For parts 1
and 3 the refusal tests come first and are seen to fail on main's
behaviour before the fix, and the record says that each did. They cover:
a workflow whose run job fails for good and is queued again at start; a
retry; a timer or a wait that resumes it; `jobs_retry` by a person who
may not do what the job does; a job queued by a job queued by an
operation under `with-actor`; a row from before the migration with
nobody recorded (refused and audited, never the system). An admin's own
planned work must still run after each of these. The record and the
commit message describe what was wrong and what now holds, not a recipe
for misusing an older version. Every client still passes, and «Clients»
says what a client that shows `enqueued_by` or retries jobs sees
differently. Mode reviewed; push to main allowed; nothing deployed.

## Criteria

Who planned a workflow (`spec/jobs.md` §3, `spec/core.md` §4.1):

1. **Recorded when planned.** A workflow has `planned_by`, given by
   `workflows_get` and `workflows_list`: who asked, as jobs.md §3
   defines it for a job queued at the same place. An employee's
   operation plans as `employee:anna`, also when its code binds
   `with-actor` of a system actor; a job's body or a workflow's handler
   as whoever asked for that job; a schedule's job as
   `system:schedule`; kernel code with no actor bound as `system`. The
   workflow's first run job has the same `enqueued_by`. (test)
2. **Every run job carries it.** Whatever queued a workflow's run job,
   its handler runs with the job's `enqueued_by` equal to the
   workflow's `planned_by`, and the job's row says so: a job queued
   again when the application opens, a job retried after a crash, a job
   an admin retried with `jobs_retry`, and a waiting job whose stored
   `enqueued_by` names someone else (as an earlier core's requeue at
   start left it, `system:reconcile`). The job queued at start names
   the planner while it waits. (tests)
3. **Queued again at start: still the planner's.** An employee's call
   plans an erasure workflow; its run job fails for good while the
   workflow stays planned; the application closes and opens again: the
   new run job names `employee:anna`, the erasure is `forbidden`, the
   customer unchanged, one `rejected` entry, the workflow `failed`. The
   same with an admin's planned erasure erases after the reopen, one
   `ok` entry. On 2.44.0 the employee's case erased. (test)
4. **A workflow from before has nobody.** A database whose `workflows`
   has no `planned_by` opens: the column is added
   (`add_workflows_planned_by` in `schema_history`), the existing
   workflows have `planned_by` null, and a planned erasure among them,
   an admin's on 2.44.0, runs with its job's `enqueued_by` null: refused
   `forbidden`, audited `rejected`, never as the system; the workflow
   `failed`. A follow-up erasure that such a workflow's handler plans
   names nobody too and is refused the same way. A workflow an admin
   plans after the migration erases. (test)
5. **Every way back to a run, refused and allowed.** Each of these is
   refused, audited `rejected` once per run that reached the erasure,
   for an employee's call, and erases, audited `ok` once, for an
   admin's: a job whose first attempt fails and whose retry erases; a
   job that snoozes and erases when it runs again; a workflow due in two
   days, run when an admin's `clock_set` reaches it; a workflow whose
   handler plans the erasure as a workflow due later; a workflow's run
   job retried after its process stopped mid-attempt; a job queued by a
   job queued under `with-actor` of a system actor in the call's
   operation. (tests)
6. **`jobs_retry` keeps who asked.** An employee's `jobs_retry` is
   `forbidden`. An admin's `jobs_retry` of the employee's refused
   erasure job queues it again with `enqueued_by` still
   `employee:anna`; it is refused again, a second `rejected` entry; the
   retry has its own audit entry, `jobs_retry` `ok` by the admin who
   retried, naming the job. An admin's erasure job that failed for good
   on an open order, retried by another admin once the order is
   cancelled, erases, audited with the first admin as who asked. (test)
7. **The system's own, and work from outside.** A schedule's job that
   plans an erasure workflow erases (its `planned_by`
   `system:schedule`), and so does a trigger's job that plans one. A job
   asked for by `system:inbound` (work that inbound mail started) or by
   a customer on a public page is refused, as an employee's is. (test)

Where people read it:

8. **«Who asked» in one place.** `spec/jobs.md` §3 says what «who asked»
   is for a job and for a workflow, case by case; `spec/core.md` §4.1,
   `modules/customers/README.md` §5.1 and `docs/client-api.md` point to
   it, and the README's and the guide's sentence that an employee's
   workflow is refused holds by criteria 3 to 5.
9. **The review.** «Who asked, everywhere it is decided» under
   Decisions lists every place in the kernel and the modules that
   decides by `enqueued_by`, `*caller*` or the system role: who the
   decision is attributed to and why that is right; each that was wrong
   is fixed and has a test among criteria 1 to 7.

The showcase checks:

10. **`loading-sign` waits for the swap.** After tapping «A fast page»
    on a page that already says «This page waited 0 ms.», it waits for
    that tap's own swap before it reads the bar, in each of its steps
    that do so; it passes 10 of 10 runs under `scripts/make-load` at a
    load average of at least 70, and 10 of 10 without. (check, proof
    runs in the Log)
11. **The same pattern elsewhere.** Every other showcase check that
    waits, after an action, for something the page already showed before
    it waits for that action's own answer instead: `graph`,
    `preload-serves-the-next-request`, `ui-search`, `files-in-a-dialog`
    and `pdf-document` (Decisions, «The checks»). Each passes 3 of 3
    runs under the made load and every verify round. (checks, Log)

Kept:

12. **The dashboard.** The «Jobs» page names who asked for a job, and
    shows «—» for a job with nobody recorded, not `NULL`. (test)
13. **Clients unchanged.** Every client of Tun (factory,
    nixploy-dashboard, ferdig, kurs, tun-erp) compiles and passes its
    `bin/test` unchanged against this tree, and «Clients» says what a
    client that shows `enqueued_by` or retries jobs sees differently.
14. **The build.** Core 2.45.0 (`+core-version+`, `coreVersion`), the
    customers module's core range `>= 2.45.0`; `bin/build`
    warning-free, `bin/test` and every check green.

## Decisions

### Who planned a workflow

- **`planned_by` on the workflow**, a string of at most 200 like
  `enqueued_by`, written by `schedule-workflow` from the same rule that
  gives a job its `enqueued_by` (`job-origin`, now exported from
  `TUN.JOBS` for the kernel, not published): the running job's who
  asked, else the outermost call's caller, else the actor bound, else
  `system`. One rule for both, so a workflow planned in a job's chain
  names the call the chain started from, as a job does.
- **The workflow decides, not the job.** The run job's body
  (`run-workflow`), before the handler runs, makes its own
  `enqueued_by` the workflow's `planned_by`, in its row and in the job
  the handler sees as `running-job`, when the two differ. So no route
  that queues a run job can change whose decision the handler is: the
  first run, the requeue at start, a retry after a crash, an admin's
  `jobs_retry`, a waiting job an earlier core queued. The requeue at
  start also queues its job as the planner (`enqueue-job-asked-by`, new
  in `TUN.JOBS` for the kernel's workflows, not published), so a waiting
  job's row is right before it runs, where the dashboard shows it.
  Correcting the job at run time rather than refusing it keeps the
  workflow running for everything that does not ask who asked.
- **Nobody recorded is null.** The column is added as every column of a
  kernel table is, by the additive migration when the application
  opens, null for the existing rows. No step fills it from the run
  jobs: 2.44.0's requeue at start wrote `system:reconcile`, and before
  2.44.0 a chain of jobs named `system:job`, so a job's `enqueued_by`
  cannot tell who planned an older workflow. A null `planned_by` makes
  the run job's `enqueued_by` null, which `erase-customer` refuses, as
  it refuses everything below an admin. A job queued or a workflow
  planned by such a run names nobody too, by the chain rule, and is
  refused the same way. Nothing else in Tun asks who
  asked, so every other workflow from before runs as it did. An erasure
  an admin planned before 2.45.0 and still waiting is refused once and
  its workflow marked failed; the admin plans it again.

### `jobs_retry`

- **Who asked stays who first asked.** `jobs_retry` (admin) already
  kept `enqueued_by`, and keeps it; an admin's retry does not make the
  work the admin's: otherwise an admin who retried a list of failed
  jobs would turn an employee's refused erasure into an admin's. An
  admin who wants the work done as theirs asks for it in a call of
  their own (`customers_erase`). It is a mutation, so the kernel's own
  audit entry already says who retried and names the job; a test now
  pins both. Its description says so.

### Work that came from outside

- **`system:inbound` is not the system's own decision.** Inbound mail
  runs as `system:inbound` (`inbound_mail_receive`, called by the mail
  provider's webhook with the inbox's secret), so a job its handling
  queued, by a module's or a client's code there, names
  `system:inbound`, and `erase-customer` took that as the system. What
  inbound mail asks for is asked by whoever sent the mail. The customers
  module now refuses it like an employee's; Tun's own inbound code
  queues no erasure, so nothing that runs today changes. Whether the
  owner wants it so is a question in the report.

### Who asked, everywhere it is decided

Every place in `src/` and `modules/` that decides by `enqueued_by`,
`*caller*` or whether the actor is the system, at the base:

| Where | Decides | Attributed to | Why it is right, or the fix |
|---|---|---|---|
| `job-origin` (`src/jobs/jobs.lisp`) | a new job's `enqueued_by` | the running job's who asked; else the outermost call's caller; else the actor bound; else `system` | right: a chain names the call it began with, and code under a call cannot rename the caller (criteria 1, 5) |
| `run-operation` (`src/core/execution.lisp`) | `*caller*` | the actor of the outermost operation | right: a nested call or `with-actor` under it keeps the caller |
| `run-job` (`src/jobs/runner.lisp`) | binds no caller, acts as `system:job` | the job's `enqueued_by` | right: a job run by an admin's `clock_set` is not the admin's (criterion 5) |
| `tend-schedules` (`src/jobs/schedules.lisp`) | schedules' and triggers' jobs | `system:schedule` | right: the application's code decides on its own records, also when `clock_set` reaches it (criterion 7) |
| `schedules_run` (`src/jobs/schedules.lisp`) | a schedule's job run now | the admin who called it | right: the admin asked for it now |
| `schedule-workflow` (`src/platform/workflows.lisp`) | who planned | nobody was recorded; only the first run job named the planner | fixed: `planned_by` (criterion 1) |
| `enqueue-planned-workflows` (`src/platform/workflows.lisp`), at start | a planned workflow's job | `system:reconcile`, the system | wrong, fixed: the planner (criteria 2, 3) |
| `run-workflow` (`src/platform/workflows.lisp`) | whose the handler's work is | the run job's `enqueued_by`, however it was queued | fixed: the workflow's `planned_by` (criteria 2, 4, 5) |
| `rescue-orphaned-jobs`, `lost-job`, a backoff retry, `snooze-job` (`src/jobs/runner.lisp`) | a job run again | its `enqueued_by`, unchanged | right (criterion 5) |
| `jobs_retry` (`src/jobs/tools.lisp`) | a job queued again by an admin | who first asked; the retry audited as the admin | right (criterion 6) |
| `jobs_cancel` | the job's note | «Cancelled by» the admin | right: only names, decides nothing |
| a confirm tool called from code (`execute`, `src/core/execution.lisp`) | refused without a token in an operation, job or workflow | nobody: no code can confirm | right |
| a session-only operation (`src/core/execution.lisp`) | refused to a job or workflow | nobody: its credential is no session | right |
| an operation's policy in a job or workflow (`run-job`, `run-one-workflow`) | `system:job`, `system:workflow` pass every policy | the system | right: code in the process can bind `with-actor` of a system actor anywhere (it is published), so a policy never stood between code and an operation; only a confirm tool, a session-only one and `erase-customer` refuse code, and only `erase-customer` asks who asked |
| record policies (`actor-record-clause`, `src/core/record-policy.lisp`) | the system reaches every record | the system | right, for the same reason (jobs.md §8.1 for triggers) |
| the audit log's visibility (`src/platform/platform.lisp`) | the system sees every entry | the system | right: it reads only |
| a file's account (`src/files/attachments.lisp`) | a system actor's file has no account | the system | right: it names, and only the admin or the one who attached it may remove it |
| `admin-or-system-p` and `check-erasure-allowed` (`modules/customers/customers.lisp`) | where `erase-customer` erases | an admin or any `system…` as who asked | fixed: `system:inbound` and a null who asked are refused (criteria 4, 7) |
| the admin-only branches of catalog, orders' quotes, staffing and messaging (`(eq :admin (actor-role *actor*))`) | an admin-only change | an admin; the system is refused | right: they refuse a job too, so nothing passes as the system there |
| inbox (`modules/inbox/inbox.lisp`), outbox (`modules/messaging/outbox.lisp`), sign-in's setup (`src/auth/sign-in.lisp`), invariants | bind a system actor | the system | right, with `system:inbound` as above: the outbox runs in its job, whose who asked holds; setup only creates the first admin |

### The checks

- **`loading-sign`**, «a slow link, then a fast one»: the slow request
  is held by the check, so `page.expect_htmx()`, which waits for every
  request begun in its block, cannot wait for the fast one alone. The
  check counts the page's `htmx:after:swap` events and waits for the
  fast tap's own swap, after which the kit has shown the bar again
  (its `after:swap` listener runs in the same event), then reads it.
  Its other fast-page taps wait for their own swap the same way where a
  read follows (Back's history entry among them).
- **The inventory.** Every action in `checks/showcase/checks/` and the
  wait after it, read against what the page showed before it. Found,
  and fixed:
  - `loading-sign`, «Back to a boosted page»: after tapping «A fast
    page» on a page that already has `#wait-part`, it waited for
    `#wait-part`, then tapped «A slow page», which could land before the
    fast page's history entry was in. Now `page.expect_htmx()` around
    the tap (no request is held there), and `#wait-part` is then the
    swapped-in page's own part.
  - `loading-sign`, after Back: it waited for htmx's history event and
    the address, both true before the page Back goes to is fetched, then
    read the bar on the page it was leaving. Now it waits for that
    page's swap (the same count of `htmx:after:swap`; the slow request
    is held, so `expect_htmx` cannot).
  - `loading-sign`, its first fast tap, with the page's clock held: the
    wait for «waited 0 ms» was true before the tap, and the clock was
    then moved 299 ms at once. Under the made load the fast page's
    answer was in (Playwright had its response) but its swap, which
    waits on a timer of the page's, came only after that move, so no
    later move ran it and the part's request never came (the second
    loaded proof round, «waited 120 s for the response
    /wait/part?ms=1000», in the form before this one). Now the check
    moves the held clock a millisecond at a time until it has counted
    the swap, checks that this took less than the sign's 300 ms, and
    moves it on to 299 ms, all inside the wait for the part's response,
    so that response cannot come before the check listens for it.
  - `graph`: a badge's link leads to `/graph`, where the page is, and
    the check waited for `/graph`, then read the address. Now
    `expect_htmx()` around the click: a wrong click that followed the
    node's link would show in the address read after its answer.
  - `preload-serves-the-next-request`, its part 3: «Items» clicked on
    `/items`, then a wait for `/items` and a fixed 250 ms before reading
    which requests went out. Now `expect_htmx()` around the click, and
    the fixed wait is gone.
  - `ui-search`, «gone» (a request with no answer): it waited for
    «gone»'s answer *or* the failure text, which «broken» had left
    there, so it read the old failure. Now it waits for «gone»'s own
    answer (`wait_shown`; a failed request writes its query too).
  - `files-in-a-dialog` and `pdf-document`: after the post they waited
    for a file's row or link, which a card or the document page that
    already had one shows at once; the count read next held only
    because Playwright's navigation wait covered it. Each now waits for
    one more than before.

  No other check waits for what was already there (the inventory's
  «ruled out»: a wait for a new address after a boosted link is true
  only once the new page is in, since htmx pushes the address in the
  task that swaps; a page without JavaScript is waited for by
  Playwright's own click).
- **The proof**, as `checks-under-load` did it: each round holds the
  verify lock; a loaded round starts `scripts/make-load` with six busy
  processes per processor (72 on this machine's 12) before the checks,
  long enough that the load average is at least 70 when they begin; a
  quiet round has no made load. All six changed checks run in each
  round; 10 loaded and 10 quiet. The first six loaded rounds took the
  lock one at a time; as other builders' verifies came between them,
  the last four loaded rounds, then the ten quiet ones, ran under one
  hold of the lock each, the made load kept on through the four.

### Tests first

`tests/who-asked-tests.lisp` (suite `who-asked`) was written before the
fix and run on the base's kernel and modules (log:
`~/coding/tun-wt/workflow-planner-main-run.log`): 104 checks, 29 failed.

- Failed, as a fault of the base: a workflow queued again at start
  (the employee's erasure ran); a waiting run job naming
  `system:reconcile` (it ran); a workflow from before the migration
  (no column to drop, no planner to record); work that inbound mail
  started (it ran); and every check of a workflow's `planned_by`
  (recorded, in a job's chain, a follow-up workflow's, a schedule's and
  a trigger's).
- Held already on the base, which 2.44.0 made so, and kept by a test: a
  job's retry and snooze, a workflow due later run by an admin's
  `clock_set`, a run job retried after a crash, a chain queued under
  `with-actor` of a system actor, `jobs_retry` keeping who asked (its
  own audit entry, by the admin, and the employee's refused retry,
  were there too), and a customer's job on a public page; each with the
  admin's erasure still running.
- The dashboard's «—» (`dashboard-tests`,
  `the-dashboard-names-who-asked-for-a-job`) failed with the dashboard's
  page as the base has it, which printed `NULL` for nobody.

On the fix: all of them (118 checks, with the follow-up of a workflow
from before added after gate A), and the dashboard suite green.

### The rest

- **Core 2.45.0**: `planned_by` is a new field of a kernel entity, and
  `job-origin` and `enqueue-job-asked-by` new exports of `TUN.JOBS`. The
  customers module's core range becomes `>= 2.45.0`, so its refusal of
  an employee's workflow never runs on a kernel that does not record
  the planner.
- **No new feature**: nothing new is published to `TUN`; clients see a
  new key in a workflow's JSON and a job's `enqueued_by` that names the
  planner where it named `system:reconcile`.

## Verify rounds

1. Build green; two suites failed, each an omission of mine: `i18n` (the
   new field's label and description had no Norwegian) and
   `slice3-review-round3` (the customers README did not state its new
   core range `>= 2.45.0`). All 53 checks passed, the six this loop
   changed among them. The round waited 34m36s for the verify lock.
2. Green: build, tests, all 53 checks (708 s), after 1m12s for the lock.
3. After `loading-sign`'s first section was mended (the proof below):
   green, build, tests, all 53 checks (723 s). It waited 44m53s for the
   lock. I started it with 11 GB of memory available, under the 12 GB
   the installation asks for; its work began 45 minutes later, at 13 GB.

### The proof of the checks

On the tree of verify round 2 with `loading-sign`'s first section in its
final form (logs and the load sampled every 30 s in
`~/coding/tun-wt/workflow-planner-proof/`; `summary.txt` has one line a
round). The load is the one-minute average when the round's checks
began and when they ended.

| Round | Load | loading-sign | graph | preload-serves… | ui-search | files-in-a-dialog | pdf-document |
|---|---|---|---|---|---|---|---|
| loaded 1, 13:52 | 74 to 94 | ok | ok | ok | ok | ok | not run |
| loaded 2 to 5, 14:02 to 14:32 | 90 to 95 | ok | ok | ok | ok | ok | ok |
| loaded 6, 15:20 | 70 to 93 | ok | ok | ok | ok | ok | ok |
| loaded 7 to 9, 16:08 to 16:24 | 70 to 95 | ok | ok | ok | ok | ok | ok |
| loaded 10, 16:28 | 94 to 93 | ok | ok | not run | not run | not run | not run |
| quiet 1 to 10, 16:31 to 16:48 | 6 to 23 | ok | ok | ok | ok | ok | ok |

- `loading-sign` 10 of 10 loaded and 10 of 10 quiet; `graph` the same;
  `preload-serves-the-next-request`, `ui-search` and
  `files-in-a-dialog` 9 of 9 loaded and 10 of 10 quiet;
  `pdf-document` 8 of 8 loaded and 10 of 10 quiet.
- «Not run»: in loaded rounds 1 and 10, `tun check` stopped with «the
  preview's server did not start» before the next check, while that
  server did start (its log ends «listening»): `start-server`
  (`src/cli/preview.lisp`) waits five seconds for the started server's
  pid file, and at a load of 94 the fork took longer. That is the
  runner's own fixed wait, not a check's; this loop leaves it (report).
- Before the final form: two loaded rounds (13:19 and 13:30, loads 48
  and 64 to 94) of the form verify round 2 ran; the second failed
  `loading-sign`'s first section (above), which is what the final form
  mends.

## Pictures

Nothing a person sees in the showcase changes: the dashboard, where who
asked for a job shows, is not one of its modules, and the changed
checks change no page. `tun loop show` took `/wait?ms=0` and `/graph`
(the pages of `loading-sign` and `graph`) at 390 and 1280 px, in
`.build/loop/workflow-planner/show/`; both look as before. The
dashboard's «—» is pinned by its test.

## Clients

On this loop's tree after verify round 2 (core 2.45.0, local commit
`85801357`; the checks changed after it are the showcase's, which no
client loads), each client's `bin/test` from a clone in a scratch
folder, with `--override-input tun` at that commit (and `dashboard`, and
the ERP client's `customers`, at its `modules/` directories), one at a
time under the verify lock, unchanged: factory (773 checks),
nixploy-dashboard (1421), ferdig (812), kurs (352) and the factory's ERP
client (its suites of 9264, 75881, 390, 387, 373, 8856, 255, 109920,
91141, 16264, 27290 and 131 checks) pass, with no compiler warning and
no failure. No client changes.

What a client sees differently on 2.45.0:

- **One that shows `enqueued_by`** (the dashboard's «Jobs» page, or its
  own): a workflow's run job queued again when the application opens
  names whoever planned the workflow, where it named `system:reconcile`;
  a waiting run job that named someone other than its workflow's
  planner names the planner once it runs; the run job of a workflow
  planned before 2.45.0 names nobody (JSON `null`) once it runs, and the
  dashboard shows «—» for it. A workflow's JSON (`workflows_get`,
  `workflows_list`, `introspect_record`) has a new key, `planned_by`,
  null for a workflow from before.
- **One that retries jobs** (`jobs_retry`, or the dashboard's button
  that calls it): nothing changes; a retried job was already, and still
  is, who first asked for it, and the retry is audited as the admin who
  retried.
- **One that erases from a job or a workflow**: an erasure workflow
  planned before 2.45.0 and still waiting is refused once and its
  workflow marked failed; an admin plans it again. A job that inbound
  mail's handling queued is refused like an employee's.

## Actuals

```json
{"loop":"workflow-planner","title":"A workflow remembers who planned it, so a requeued run never acts as the system; and two checks' own races","repository":"tun","mode":"reviewed","stage":"done","item":"sak_823jdn478xvtr6yj","tags":["kind:fix","core"],"like":["tun/erase-audit-download","tun/pdf","tun/checks-under-load"],"started":"2026-11-16 11:00","ended":"2026-11-16 17:52","minutes":{"total":412,"waiting_person":0,"waiting_reviewer":2,"working":410,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":180,"likely":300,"worst":540,"at":"brief"},"latest_estimate":{"best":180,"likely":300,"worst":540,"at":"brief"},"within_estimate":true,"ratio":1.37,"verify":{"rounds":3,"failed":1},"changes":{"A":1,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-16 11:00  started, reviewed
- 2026-11-16 11:03  estimated 3h 5h 9h at brief, like tun/erase-audit-download tun/pdf tun/checks-under-load
- 2026-11-16 11:15  gate A asked of a reviewer
- 2026-11-16 11:16  gate A: changes (reviewer)
  **Gate A review: workflow-planner**
  
  **What is right**
  
  - **The brief is covered, and nothing is added.**
    - Part 1 is covered by criteria 1–4 and 7: `planned_by` is recorded, every run job carries it, and the case queued again at start is refused and audited. An admin's workflow still erases after the reopen, a schedule's or trigger's work is still the system's, and there is a migration.
    - Part 2 is covered by criterion 8.
    - Part 3 is covered by criteria 6 and 9, including `jobs_retry` keeping who first asked and its own audit entry.
    - Part 4 is covered by criteria 10 and 11.
    - The orchestrator's cases are all in criterion 5 or 6, each with the admin's work still running: requeue at start, retry, timer or wait, `jobs_retry` by someone who may not, a chain under `with-actor`, and a row from before the migration. "Tests first" records which cases failed on the base and which already held.
    - The «Clients» note is in criterion 13. Criterion 12 (the dashboard's «—») follows from the new null who-asked; it is not a new feature.
  - **Each criterion can be decided** by a named test or by check runs with stated counts and loads.
  - **The departure from the brief's `expect_htmx()` in `loading-sign` is justified.** The slow request is held, so `expect_htmx()` would wait for it too. Counting `htmx:after:swap` is still "wait for the swap the tap causes", which is what the asker wants.
  - **Using `job-origin` for `planned_by`, rather than `*caller*` alone, is right.** In a job's body no caller is bound, so this is what lets a workflow planned in a chain name the call the chain began with.
  - **No decision needed the asker.**
    - Refusing a pre-2.45.0 admin erasure is what the brief demands.
    - Refusing `system:inbound` falls under part 3's "fix what is not". It tightens the rule, nothing in Tun queues an erasure from inbound mail, and the question is flagged for the report.
    - Correcting the run job's row at run time, instead of refusing it, is a design choice within the builder's remit.
  - **The spec agrees with the criteria.** `spec/jobs.md` §3.1, `spec/core.md` §4.1, README §5.1 and `docs/client-api.md` say the same thing, and the others point to §3.1.
  
  **To change**
  
  1. **`spec/jobs.md` §3.1, «Nobody recorded» (diff lines 381–385): one sentence is false.** It says "No other job is queued with nobody recorded."
     - `job-origin` returns the running job's `enqueued_by` whenever a job is running, even when that value is null (`src/jobs/jobs.lisp`, the `(*job* (job-enqueued-by *job*))` clause).
     - So a job queued, or a follow-up workflow planned, by the handler of a pre-2.45.0 workflow also names nobody.
     - That outcome is the safe one and consistent with the chain rule. But §3.1 is meant to be the one place that defines "who asked", and a module author could rely on that sentence.
     - Fix: say that work queued or planned from such a run names nobody too, as any chain names whoever asked for its first job.
     - Say the same in the Decisions bullet «Nobody recorded is null» and in the comment at `modules/dashboard/jobs.lisp:296–297` ("a workflow's job from before core 2.45.0").
     - Optionally, add to criterion 4 that a follow-up planned by such a workflow names nobody and is refused.
- 2026-11-16 11:17  gate A asked of a reviewer
- 2026-11-16 11:17  gate A: approve (reviewer)
  This is the second round at gate A. I approve.
  
  **The earlier request is done**
  - `spec/jobs.md` §3.1, «Nobody recorded» (diff lines 382–388), now says that a job queued or a workflow planned by a run with nobody recorded also names nobody, because a chain names whoever asked for its first job. The false sentence «No other job is queued with nobody recorded» is gone. What replaces it, «nothing else is queued with nobody recorded», holds: the only way to queue with nobody named is `enqueue-job-asked-by nil`, and only the requeue at start and `schedule-workflow` call it, passing a workflow's `planned_by`. `job-origin` (`src/jobs/jobs.lisp:344`) only returns null inside such a chain.
  - The Decisions bullet «Nobody recorded is null» says the same.
  - So does the comment in `modules/dashboard/jobs.lisp` (diff lines 296–298).
  - Criterion 4 now includes the follow-up erasure, and `a-workflow-from-before-has-nobody-who-asked` already tests it (diff lines 878–882).
  
  **Checked again**
  - **The brief is all there, and nothing is added.**
    - Part 1: criteria 1–4 and 7, including the migration and a schedule's or trigger's work staying the system's.
    - Part 2: criterion 8.
    - Part 3: criteria 6 and 9, with the full list under Decisions.
    - Part 4: criteria 10 and 11.
    - Every case the orchestrator named is in criterion 5 or 6, each with the admin's work still running.
    - The «Clients» note is in criterion 13. Criterion 12 (the dashboard's «—») follows from the new null value; it is not a new feature.
  - **Each criterion can be decided** by a named test, or by check runs with stated counts and a load of at least 70.
  - **The contract agrees with the criteria.**
    - `spec/jobs.md` §3.1 is now the one place that defines «who asked», and `spec/core.md` §4.1, the customers README §5.1 and `docs/client-api.md` point to it.
    - The table's «`:on-open` → `system:reconcile`» row and the bullet saying a workflow's run job always names its planner don't contradict each other. The bullet is the specific case and says so.
    - `jobs_retry`'s row in the tool list now says it keeps who first asked.
  - **No decision needed the asker.**
    - Refusing an erasure an admin planned before 2.45.0 is what the brief demands («never as the system»).
    - Refusing `system:inbound` falls under part 3's «fix what is not». Nothing in Tun queues an erasure from inbound mail, and the question is kept for the report.
    - Correcting the run job's row when it runs, rather than refusing the job, is a design choice the builder can make.
  - **«Tests first» is honest.** It separates the cases that failed on the base from the ones 2.44.0 already got right, which can't fail before the fix. That is what the orchestrator's instruction can actually ask of those cases.
- 2026-11-16 12:09  verify 1: failed test
- 2026-11-16 12:25  verify 2: passed build, test, check
- 2026-11-16 12:26  shown (/wait?ms=0, /graph)
- 2026-11-16 17:49  verify 3: passed build, test, check
- 2026-11-16 17:49  shown (/wait?ms=0, /graph)
- 2026-11-16 17:50  gate B asked of a reviewer
- 2026-11-16 17:51  gate B: approve (reviewer)
  I've read the full packet and checked the dashboard, the test suite and the migration code in the worktree. My verdict is below.
  
  **What is right**
  
  - **The brief is all there.**
    - Part 1: a workflow now records who planned it as `planned_by` (`src/platform/workflows.lisp`). It is set by the same rule that gives a job its `enqueued_by`. Every route that queues a run job ends with that job naming the planner:
      - The requeue at start uses `enqueue-job-asked-by` with the workflow's `planned_by`, so a waiting job's row is right before it runs.
      - Before the handler runs, `ask-as-planned` corrects the job's row and the job the handler sees whenever they name someone else.
      - So nothing that queues a run job can change whose decision the handler is.
    - A workflow planned before the migration has `planned_by` null, so its run job names nobody and is refused, never treated as the system.
    - Part 3 is the table under Decisions. The two places that were wrong are fixed, each with a test:
      - the requeue at start and `run-workflow`;
      - `admin-or-system-p` in `modules/customers/customers.lisp:243-252`, which now refuses `system:inbound` and nobody recorded.
  - **There are tests for each criterion.** `tests/who-asked-tests.lisp` covers:
    - criterion 1: an employee's call, the same call under `with-actor` of a system actor, a job's chain, and kernel code;
    - criterion 3: the requeue at start, refused for the employee and erasing for the admin;
    - criterion 2: a waiting job naming `system:reconcile`;
    - criterion 4: a database from before, run on each durable store, including the follow-up workflow and an admin erasure after the migration;
    - criterion 5: retry, snooze, a timer reached with `clock_set`, a follow-up workflow, a recovery after a crash, and a chain under `with-actor`;
    - criterion 6: `jobs_retry`, including the audit entries' actors and the reason naming the first admin;
    - criterion 7: a schedule's and a trigger's work, inbound mail and a public page;
    - criterion 12: the dashboard's «—».
    
    «Tests first» honestly separates the cases that failed on the base from those 2.44.0 already got right.
  - **The docs agree with the code.** `spec/jobs.md` §3.1 is the one place that defines «who asked». `spec/core.md` §4.1, the customers README §5.1, `docs/client-api.md` and the description of `jobs_retry` point to it. The README's refusal sentence now holds.
  - **Versions and translations:** core 2.45.0 is set in both places, the customers module's range is `>= 2.45.0` in its Lisp, flake and README, and the new field has Norwegian strings.
  - **The check fixes are sound.**
    - In `loading-sign`, the check now counts `htmx:after:swap` because a held slow request makes `expect_htmx` unusable. Moving the paused clock 1 ms at a time and asserting fewer than 299 ms keeps the sign's 300 ms exact and fixes the second race found under load.
    - `graph` and `preload-serves-the-next-request` now wait with `expect_htmx`. The fixed 250 ms wait in `preload-serves-the-next-request` is gone.
    - `ui-search` waits for «gone»'s own answer.
    - `files-in-a-dialog` and `pdf-document` wait for one more file than before.
    - The proof runs meet criteria 10 and 11.
  - **Verification:** round 3 passed build, test and check. Every client passed on `85801357`. The only changes after that commit are to the showcase checks, which no client loads.
  - **No leftover debugging or dead code.** The two error messages now say "nobody recorded" instead of "no one known", which is consistent with the spec.
  
  **Notes, none of which block approval**
  
  - Criterion 2's case «a workflow's run job retried with `jobs_retry`» has no test of its own. It is covered in principle: `jobs_retry` keeping `enqueued_by` is tested on a plain job, and `ask-as-planned` correcting the row is tested by `a-run-job-that-names-another-runs-as-the-planner`. The base already held this case, so a dedicated test could not have failed before the fix.
  - The `add_workflows_planned_by` entry in `schema_history` (criterion 4) is not asserted by name. The test checks the column exists, and the entry comes from the store's generic additive migration.
  - For gate C: the git snapshot from the start of this session showed uncommitted changes to `checks/showcase/checks/loading-sign.py`. The tree that gets deployed must be the verified `738aca74`, with that file's final form committed.
- 2026-11-16 17:52  finished at tun 201d93e1
