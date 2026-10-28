# tun module `dashboard`

ASDF system `tun-dashboard`, package `tun.dashboard`; pinned by clients
through `flake.nix` in this directory (tun-platform.md §2, §4). Enable it
with `tun add dashboard`.

- **Owns:** no records. It is the developer's dashboard: pages for admins
  that show how the application runs. «Jobber» at `/jobs` shows what its
  background work does (spec/jobs.md), as Hangfire's dashboard does for
  .NET; «Feil» at `/errors` the errors it has had, grouped by cause, as
  Sentry lists issues; «Logg» at `/log` the requests the process has in
  memory, as Laravel's Telescope lists them (spec/errors.md).
- **Depends on:** no module.
- **Core range:** builds against core `>= 2.0.0, < 3.0` (`flake.nix`
  `core`, and `define-module` in the Lisp source): the jobs, schedules,
  triggers and `jobs_summary`, and the recorded errors and `errors_*`
  tools, of core 1.4.
- **Publishes:** nothing. Every figure comes from core's tools
  (`jobs_summary`, `jobs_list`, `jobs_get`, `schedules_list`,
  `errors_list`, `errors_get`, `introspect_recent`, `introspect_inflight`,
  `introspect_request`) and every button calls one (`jobs_retry`,
  `jobs_cancel`, `schedules_run`, `errors_set_status`), as the admin logged
  in, so an agent over MCP sees and does the same.

## The pages

The paths were `/jobber`, `/feil` and `/logg` before core 2.0; those
answer 301 to `/jobs`, `/errors` and `/log` (`spec/i18n.md` §4.8).

| Path | Shows |
|---|---|
| `/jobs` | **Oversikt**: how many jobs wait, run, retry and failed, and how many succeeded and failed in the last 24 hours; each queue with its limit, what waits and runs in it, and its oldest waiting job; the processes running jobs, whether each is alive and how many jobs it runs; the latest failures. |
| `/jobs/list?state=STATE` | **Jobber** in one state, newest first: type, queue, arguments, attempts, when it is due or finished, its last error. A tab per state, with its count. |
| `/jobs/JOB-ID` | **One job**: its fields, its arguments, and the history of its attempts with each error and the request it ran in. «Kjør på nytt» for a failed or cancelled job, «Avbryt» for one that waits. |
| `/jobs/schedules` | **Tidsplaner**: each schedule and trigger, when it runs in words («hverdager kl. 07:00») and as cron, its job, its last and next occurrence (for a trigger, how many jobs its last sweep enqueued), and «Kjør nå». |
| `/errors?status=STATUS` | **Feil**, open, resolved or ignored, latest seen first: the message, the condition's type, where it happened, how many times, last seen. A tab per status, with its count. |
| `/errors/ERROR-ID` | **One error**: its fields, its message, its backtrace, and its latest 50 occurrences, each linking to its request. «Merk som løst» and «Ignorer» for an open error, «Åpne igjen» for the others. |
| `/log?selection=SELECTION&kind=KIND` | **Logg**: the latest 200 requests in memory, newest first: all, errors, refusals or slow ones, of every kind or one (tools, web pages, jobs, workflows, MCP); and the requests running now. |
| `/log/REQUEST-ID` | **One request**: who, what, its outcome and error, its time, store calls and wait for the write lock, its input, its steps in time order with each step's time drawn against the whole, and its backtrace. |

The requests are the process's own and are not stored: after a restart
«Logg» starts again, while «Feil» keeps every error. A refused button shows
the refusal on the page it came from, with its status. The pages are in the
menu only of an application that enables the module, and only for admins.

## Contract

### 1. What the module does

The dashboard owns no records and adds no tools. Its pages are admin pages
(policy `admin`, core.md §3.3): each figure is the result of a core tool
called as the admin logged in, and each button calls a core tool, so the
pages show and do exactly what an agent can over MCP. A refused call is
drawn on the page it came from, with the refusal's status.

### 2. «Jobber»

`/jobs` and its subpages show the application's background work: jobs by
state, one job's attempts, the queues, the processes running jobs, and the
schedules and triggers (spec/jobs.md §9). They read `jobs_summary`,
`jobs_list`, `jobs_get` and `schedules_list`; «Kjør på nytt» calls
`jobs_retry`, «Avbryt» `jobs_cancel`, «Kjør nå» `schedules_run`. An
occurrence's key, a wall-clock time in the tenant's zone, is written as
the page's language writes an instant (`spec/i18n.md` §6.2).

### 3. «Feil»

`/errors` shows the recorded errors, grouped by cause, in one status (`open`,
`resolved`, `ignored`) with a count per status; `/errors/ERROR-ID` one error
with its backtrace and its latest occurrences (spec/errors.md §3, §8). They
read `errors_list` and `errors_get`; «Merk som løst», «Ignorer» and «Åpne
igjen» call `errors_set_status`. Errors are stored, so the page keeps them
across restarts.

### 4. «Logg»

`/log` shows the latest 200 requests the process keeps in memory, newest
first, narrowed by selection (`all`, `errors`, `rejected`, `slow`) and kind
(`operation`, `web`, `job`, `workflow`, `mcp`), and the requests running now
(spec/errors.md §8). `/log/REQUEST-ID` shows one request: actor, tool,
outcome, error, time, store calls, wait for the write lock, input, up to
300 steps in time order drawn against the whole, and its backtrace. The
pages read `introspect_recent`, `introspect_inflight` and
`introspect_request`; a request's identity and trace are the kernel's
(core.md §8.1, §8.2). The requests are not stored: after a restart «Logg»
starts again.
