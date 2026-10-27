# Jobs and schedules

Status: built, 2026-10-21; drafted 2026-10-20 and the questions of §14
decided the same day; every step of §15 is built. It draws on
Oban (Elixir), AshOban, Laravel's queues and scheduler, Rails' Solid
Queue and GoodJob, River (Go) and pg-boss, read the same day; §13 says
what was taken from whom and what was left.

Work that should happen later, again when it fails, or on a timetable:
a reminder in two days, a mail that must survive Resend being down, a
summary every weekday at 07:00. Every application needs it, so it is
core's, and a client declares the work and never writes the loop.

## 0. Why now

- A tracker client wants a daily summary, which needs a timetable.
- Tun has three queues of its own, each written by hand: workflows (once,
  at a time, never retried), mail delivery (retries with backoff,
  `mail.md` §3), and the messaging module's outbox (claims, a watchdog
  workflow, an unknown outcome left for a person). Jobs are the one engine
  under all three (§12).
- Mail requeues every `sending` mail when a process opens. During a
  blue/green switch that is the other process's mail; Resend's idempotency
  key saves it, a general queue cannot count on one (§7).

## 1. Words

| Word | Meaning |
|---|---|
| **job kind** | Work defined once with `define-job`: its arguments, its body, how it is retried. |
| **job** | One row: a kind, its arguments, when it is due, its state and its attempts. |
| **attempt** | One run of a job's body. A job has at most `max-attempts`. |
| **queue** | A name jobs wait in, with a limit on how many run at once in a process. |
| **schedule** | A timetable that enqueues a job at each occurrence: «hverdager kl. 07». |

## 2. Defining a job

```lisp
(define-job remind-reporter ((item-id :type (id item) :required t))
    (:max-attempts 5 :unique (:keys (item-id)))
  "Remind the reporter of an item that waits for their answer."
  (let ((item (fetch 'item item-id)))
    (unless (and item (waiting-p item))
      (cancel-job "Saken venter ikke lenger på svar"))
    (send-reminder item)))
```

- Arguments are declared as an operation's inputs are, with field types.
  They are checked when the job is enqueued and stored as JSON, so a job
  takes ids and values, never records: the record is read when the job
  runs, as it is then.
- So `define-job` refuses, when it is compiled, an argument of a type a
  job cannot carry: `(files ...)` (`files.md` §4.1), alone or in a
  `list-of`, and a `list-of` an embedded entity. The message names the
  job and the argument and says what to pass instead: attach the files to
  a record in the operation and pass the record's id; pass ids or a
  `json` argument instead of records. An argument that reuses an
  entity's field, `(:field ENTITY NAME)`, takes the field's type, and the
  entity may be defined after the job, so it is checked when an
  application opens: one such argument whose field's type a job cannot
  carry, or whose entity or field does not exist, keeps it from opening,
  with a message naming the job, the argument and the entity.
- An argument given as NIL is not stored: a job reads it as absent, so a
  boolean argument means «yes» when given and «no» when left out.
- The body runs as the actor `system:job`, in its own request: its own
  trace (`introspect_request`), audit scope and deadline. The job records
  who enqueued it.

| Option | Default | Meaning |
|---|---|---|
| `:queue` | `:default` | The queue it waits in (§6). |
| `:max-attempts` | 20 | Attempts before it fails for good. |
| `:backoff` | `15 + 2^attempt` seconds | Seconds before the next attempt: a list such as `(30 120 600)`, whose last element repeats, or a function of the attempt. The formula and a list get up to a tenth more at random, so jobs that failed together do not retry together; exact in test mode. |
| `:timeout` | 10 s in a transaction, 60 s outside | Seconds one attempt may take; past it, the attempt fails and is retried. |
| `:transaction` | `t` | `t`: the body and the job's completion commit together (§4.1). `nil`: the body runs outside any transaction (§4.2). |
| `:unique` | none | When a second enqueue returns the first job instead (§5). |
| `:priority` | 0 | 0 to 9, 0 first, within a queue. |
| `:after-crash` | `:retry` | What a job whose process died mid-attempt becomes (§7): `:retry`, or `:fail` for work whose outcome a person must check. |

## 3. Enqueueing

```lisp
(enqueue-job 'remind-reporter :item-id (entity-id item) :in (* 2 24 3600))
```

- `(enqueue-job kind &rest arguments &key at in)` is called inside a write:
  an operation, a job, a workflow or an `:on-open` function. The job is
  part of that transaction. If the operation fails, no job exists, so no
  outbox or after-commit hook is needed: the jobs table is the outbox.
- `:at` is an instant, `:in` seconds from now; without either, the job is
  due now. Bad arguments signal an error, so the operation fails
  `invalid_input`.
- It returns the job. When `:unique` matches a job already there, it
  returns that job and stores nothing (§5).
- A job enqueued to run now starts as soon as its transaction commits:
  the commit wakes a worker for its queue (§6).

## 4. Running

### 4.1 In a transaction (the default)

The process claims the job, then runs the body in one write transaction
and marks the job `succeeded` in the same transaction (River's
`JobCompleteTx`). Work that only writes Tun's own records is therefore
done exactly once: if the body fails, its writes roll back with the
completion, and the failure is recorded in a transaction of its own.

Tun has one writer at a time per database (`store.md` §2), so a body in a
transaction holds every other write back while it runs. Its timeout is
short, and a body that calls another system belongs in §4.2.

### 4.2 Outside a transaction

For work that talks to another system, such as sending mail or calling an
API. Claiming commits first; the body runs outside any transaction,
opening short write transactions of its own; then the outcome is recorded.
A crash between the call and the record means the call may be made again,
so the job must be idempotent: send the job's id as the provider's
idempotency key, as mail does, or check before acting. A client's body
writes through operations (`invoke`), each its own transaction.

### 4.3 What a body can say

| The body | The job becomes |
|---|---|
| returns | `succeeded` |
| signals an error, or runs past its timeout | `retrying`, due after its backoff, or `failed` after its last attempt |
| calls `(cancel-job reason)` | `cancelled`: no longer needed, not an error |
| calls `(snooze-job seconds)` | `queued`, due in SECONDS; the attempt is given back and counted as a snooze. With 0 the job is not ready for a reason that passes, such as a provider with no room: due again at once, and this pass of its queue ends, so the next tick, drain or `clock_set` tries it |
| calls `(fail-job reason)` | `failed` at once, with no more attempts: trying again will not help |

`cancel-job`, `snooze-job` and `fail-job` signal conditions the runner
handles, the way `fail` ends an operation. `(last-attempt-p)` is true
during a job's last attempt, so a body can record on its own records that
the work failed for good. Each failure adds `{attempt, at, error}` to
the job's `errors`, which keeps the last ten.

### 4.4 States

```
queued ──→ running ──→ succeeded
  ↑           │
  │           ├──→ retrying ──→ (due) running …
  │           ├──→ failed       (last attempt, or after a crash with :after-crash :fail)
  │           └──→ cancelled
  └── jobs_retry (from failed or cancelled), snooze
```

A queued job not yet due is still `queued`, with its `due_at`; Tun needs
no separate «scheduled» state or a process to move jobs between them.

## 5. Unique jobs

`:unique (:keys (item-id) :period 3600 :states :incomplete)`:

- **keys**: the arguments that make two jobs the same; all of them when
  absent.
- **period**: seconds within which a second enqueue is a duplicate; for
  ever when absent.
- **states**: `:incomplete` (queued, running, retrying), the default, or
  `:all`, so a job that once succeeded is never enqueued again.

A duplicate returns the existing job. Because writes are serialised
(`store.md` §2), looking for the job and inserting it in one write
transaction cannot race: Tun needs neither Oban's advisory lock, which its
own documentation says can race, nor River's partial unique index.

## 6. Queues, workers and the tick

```lisp
(define-application tracker-application ()
  (:queues (:default 2) (:mail 1)))
```

- Each queue runs at most N jobs at once in a process. N is what the
  application's `(:queues ...)` says; without it, the default Tun
  declares for one of its own queues, which is 2 for `:push`
  (`push.md` §5); and 1 for every other queue, `:default` and `:mail`
  among them. `(:queues (:push 1))` overrides Tun's default.
- The scheduler's tick (every second) starts a worker for each queue
  with room and a due job, and a commit that enqueued a job due now
  starts one at once; a worker takes the queue's due jobs by priority,
  then due time, then age, until none is left. An application a test
  opens without a scheduler runs its jobs only when told (§11).
- During a blue/green switch both processes may run a queue, so for a
  moment a queue runs up to 2N. A job that must never run twice at the
  same time says so with `:unique`.

## 7. Processes, crashes and shutdown

- Each process has a row in `job_processes` with its presence lock
  (`store.md` §3), which it holds while it runs. A running job names the
  process that claimed it.
- A process whose lock no one holds is gone: it was killed, crashed or
  lost its database connection. Its running jobs become `retrying`, the
  attempt counted, or `failed` for a kind with `:after-crash :fail`. A
  process looks when it opens and every 10 seconds, so a crash is
  recovered as soon as the restarted process opens, and a process that is
  merely busy is never robbed of its jobs, however long its attempt runs.
- On shutdown a process stops claiming, lets each running attempt finish
  within its timeout, then removes its row, so the other process recovers
  at once anything left running.

## 8. Schedules

```lisp
(define-schedule daily-summary "0 7 * * 1-5" send-daily-summary)
```

- **Times** are cron's five fields (minute, hour, day of month, month,
  weekday) with ranges, steps and names, or `@hourly`, `@daily`,
  `@weekly`, `@monthly`, read in Norwegian time (Europe/Oslo).
- **Once, whatever runs.** Each tick looks for the latest occurrence at
  or before now. When it has no run yet, it enqueues the job and records
  the run in `job_schedules`: the schedule's name, when it was first
  seen, and its last occurrence, under the write lock. Two processes, a
  restart or a deploy cannot enqueue an occurrence twice, and there is no
  leader to elect.
- **Summer time.** An occurrence is a local wall time, such as
  `2026-10-25 02:30`. A time that does not exist (02:30 on the last Sunday
  of March) runs at the first valid minute after it; a time that happens
  twice (the last Sunday of October) runs once, the first time.
- **After downtime**, the latest missed occurrence runs once, if it is
  less than a day old (`:catch-up`, in seconds, or `nil` to skip it);
  never several, and never an occurrence before the schedule existed.
- **A job kind with arguments** gets them from the schedule:
  `(define-schedule … send-report :customer-id "kun_…")`.
- **A schedule's job must exist** and accept its arguments, or the
  application does not start.

### 8.1 Triggers

A schedule runs one job at each occurrence. A trigger runs a job for
every record where a condition holds, the way AshOban's triggers do:
«remind the reporter of every item that has waited two days for an
answer», «close every quote past its expiry».

```lisp
(define-trigger remind-reporter (item)
    (:where `(:and (:= "status" "venter_på_svar") (:null "reminded_at")
                   (:< "asked_at" ,(- (now) (* 2 86400))))
     :cron "0 * * * *")
  "Remind the reporter of an item that has waited two days for an answer."
  (send-reminder item)
  (setf (item-reminded-at item) (now))
  (save item))
```

- **The condition** is a form that gives a `select` condition on the
  entity. It is evaluated at each sweep and again when each job runs, so
  it may read the clock. `(item)` names the variable the body gets and the
  entity it sweeps. `((quote order-quote))` names them separately, as
  `defmethod` does.
- **The sweep** happens at each occurrence of `:cron`, every minute
  unless it says otherwise. It is recorded in `job_schedules` as a
  schedule's occurrence is, with the same catch-up after downtime (§8),
  and enqueues the job for each matching record that has no job waiting
  or running, at most `:limit` (1000) new jobs a sweep.
- **The job** is a job kind named after the trigger, with one argument,
  `record_id`, unique by it while the job is incomplete (§5). Every other
  option of `define-job` applies (`:queue`, `:max-attempts`,
  `:transaction`…). When it runs it reads the record again with the
  condition. If the record is gone or no longer matches, the job cancels
  itself, so work queued before a person acted is never done after.
- **The body should make the condition false**, as the reminder above
  records `reminded_at`. A record that still matches after its job
  succeeded gets a new job at the next sweep.
- **The job runs as `system:job`**, which reaches every record, so a
  record policy never hides a record from its trigger.
- `schedules_list` shows a trigger with the schedules, as kind
  `trigger`, its entity and how many jobs its last sweep enqueued.
  `schedules_run` sweeps at once.

## 9. Tools and screens

| Tool | Policy | Does |
|---|---|---|
| `jobs_list` | admin | The latest jobs, narrowed by state, kind or queue: arguments, state, attempts, due time, last error. |
| `jobs_summary` | admin | How many jobs are in each state, how many succeeded and failed in the last 24 hours, each queue (its limit, jobs waiting, due later and running, the oldest waiting), and each process running jobs (when it started, whether it is alive, how many it runs). |
| `jobs_get` | admin | One job with its `errors` and the request of each attempt. |
| `jobs_retry` | admin | A `failed` or `cancelled` job queued again, due now, with its attempts reset. |
| `jobs_cancel` | admin | A queued or retrying job cancelled. |
| `schedules_list` | admin | Each schedule and trigger: its times, as cron and in words («hverdager kl. 07:00»), its last occurrence and job (a trigger: how many jobs its last sweep enqueued), its next occurrence. |
| `schedules_run` | admin | Enqueue a schedule's job now, or sweep a trigger now, outside its timetable. |

The module `dashboard` (`modules/dashboard/README.md`) shows it
all as a page, «Jobber», with the lists by state, each job's history, the
schedules, and buttons to retry, cancel and run now.

## 10. Keeping the table small

Every hour each server process deletes succeeded and cancelled jobs
finished more than 14 days ago and failed jobs after 90, a thousand at a
time. Arguments can hold personal data, so they do not live for ever. It
is the process's own housekeeping, not a schedule, so it never shows as a
job.

## 11. Tests

- In test mode there are no workers. `clock_set` enqueues the jobs of
  schedules whose latest occurrence has come, as a tick would, so a jump
  of three days runs a daily schedule once; then it runs every job due at
  the new time, including the jobs they enqueue, and answers how many
  attempts it made (`job_attempts`).
- `tun.test-support` gains:
  - `(enqueued-jobs kind &rest arguments)`: the queued jobs of KIND whose
    arguments include ARGUMENTS;
  - `(perform-job kind &rest arguments)`: the body run once, its
    arguments through JSON as in a real run, answering its outcome;
  - `(drain-jobs &key queue)`: run every due job until none is left.

## 12. What becomes of today's queues

1. **Mail delivery** is a job kind outside a transaction in the `:mail`
   queue, with mail's own backoff list (`mail.md` §3). The mail record
   keeps its status for `mail_list`, and recovery after a crash comes from
   §7 instead of requeuing every `sending` mail. Done 2026-10-20.
2. **Workflows** run on jobs: `schedule-workflow` stores the workflow and
   enqueues `run_workflow` in the `:workflows` queue, due when it is. The
   job runs the workflow as before, its handler at most once in a
   transaction with the status change, and fails at once when the handler
   fails; a crash before that commit leaves the workflow planned for the
   job's next attempt. `define-workflow`, the workflow record and tools
   stay as they are for the acceptance suites. A planned workflow without
   a job, stored before this, gets one when the application opens. Done
   2026-10-20.
3. **The messaging outbox** runs on jobs: each delivery has a
   `send_delivery` job in the `:outbox` queue, one attempt,
   `:after-crash :fail`; its claim still decides whether the provider is
   called, once ever, and a job that finds the provider busy yields
   (`snooze-job 0`) rather than wait (messaging README §10). Done 2026-10-20.

## 13. Taken and left

Taken:

- Oban's model: one table, states, attempts, `errors`, priority, a body
  that succeeds, fails, cancels or snoozes, and its backoff formula.
- River's completion in the job's own transaction, for work that only
  touches Tun's records.
- Laravel's finite timeouts and backoff lists; its warning that a timeout
  longer than the lease runs a job twice.
- Solid Queue's and GoodJob's schedules made unique in the database
  instead of by a leader, and GoodJob's process locks instead of a
  one-hour rescue: a process is gone exactly when its lock is free, with
  no timeout to guess.
- GoodJob's bounded catch-up after downtime.
- Oban.Testing's enqueued-job assertions, `perform_job` and draining.

Left, on purpose:

- `FOR UPDATE SKIP LOCKED`, `LISTEN/NOTIFY` and leader election: with one
  writer per database and a tick a second, claiming cannot race, and
  nothing waits more than a second.
- Locks in a cache or in Redis (Laravel's `ShouldBeUnique`,
  `onOneServer`): they are not part of the business write's transaction.
- Global rate limits, partitions, batches, chains and workflows of jobs:
  Oban Pro's ground, not needed at a few thousand jobs a day.
- Comparing against the database's `now()`: Tun's clock is the
  application's, so that the test clock moves jobs too, and both
  processes of a blue/green switch run on one host.

## 14. Decisions

2026-10-20:

1. **Max attempts by default: 20**, Oban's, about twelve days. A job
   whose work can go stale checks that it still applies and cancels
   itself; mail keeps its seven attempts over five hours.
2. **A job acts as `system:job`**, which reaches every record, as
   workflows do. It records who enqueued it.
3. **Norwegian time only** for schedules, as Tun's clock knows it.
4. **Triggers later**, when a client needs one: AshOban's «for every
   record where this query holds, run this job», swept on a schedule,
   each record's job unique, and the job re-checking the query and
   cancelling itself when it no longer holds. Asked for on 2026-10-21;
   §8.1. The condition is a `select` condition rather than a
   `define-query`, so that the job can check one record against it.

## 15. Order

Each step is spec, code and tests, and ships on its own.

1. Jobs: `define-job`, `enqueue-job`, both kinds of run, retries, unique
   jobs, queues, heartbeats, the tools, the test helpers.
2. Schedules, and a client's daily summary on them.
3. Mail delivery on jobs; then workflows on jobs, with the acceptance
   suites unchanged.
4. Pruning, the «Jobber» page, and the queue figures in
   `introspect_runtime`.
5. Triggers (§8.1) and the messaging outbox.
