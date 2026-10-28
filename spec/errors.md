# Errors and logs

Status: built, 2026-10-21, after a request the same day for an error
dashboard, «possibly a full logging dashboard». It draws on Sentry's issues, Rails'
Solid Errors, Laravel's Telescope and Pulse, and Hangfire's dashboard, read
that day; §9 says what was taken and what was left.

What went wrong in a tenant, and what it has been doing, for the developer
and the agents who keep it running: every error grouped by its cause and
kept across restarts, a mail when a new one appears, a log line for every
request, and pages for all of it.

## 0. Why now

- A request's record (`core/trace.lisp`, `core.md` §8.1) lives in memory: the
  last 1000 requests, gone on restart. `introspect_recent` finds the errors
  of the last minutes, if the process has not restarted since. An error at
  03:00 has scrolled away by 09:00, and nobody hears of it.
- Jobs keep each attempt's error on the job (`jobs.md` §4.3), but a job that
  fails twenty times shows as twenty lines and one failed job, not as one
  cause.
- The roadmap's «Operations» asks for logs, an error page and a mail when
  a new kind of error appears.

## 1. Words

| Word | Meaning |
|---|---|
| **request** | One MCP call, web request, job attempt or workflow run, with its record and its trace (`core.md` §8.1). |
| **fault** | A request that ended in an error the code did not mean (§2). |
| **error** | The faults with one cause, known by a fingerprint (§3): Sentry's «issue». |
| **occurrence** | One fault of an error. |

## 2. Faults

A request is a fault when its outcome is `error` with one of these codes:

| Code | When |
|---|---|
| `internal_error` | An operation or a web page signalled a condition no one handled. |
| `job_failed` | A job's attempt signalled an error (`jobs.md` §4.3). |
| `deadline_exceeded` | An operation or a job attempt ran past its deadline. |

An answer the code meant is not a fault: `fail` with `invalid_input`,
`not_found`, `conflict` or `invalid_transition`, a refusal (`forbidden`,
`unauthenticated`), a JSON-RPC error for an unknown tool, or a job that
cancels or fails itself with `cancel-job` or `fail-job`. A web page that
fails records the condition's own text, not «Forespørselen ble avbrutt».

## 3. Grouping

An error's fingerprint is a hash of:

- the code;
- for `deadline_exceeded`, the tool, since the backtrace shows only where the
  clock ran out;
- otherwise, the condition's type and the first eight frames of its
  backtrace (function names, no arguments), or the tool when there is no
  backtrace.

The message is not part of it: it holds ids, names and amounts, which
differ between occurrences of one cause.

## 4. What is kept

`error_groups`, one row per error:

| Field | |
|---|---|
| `fingerprint` | unique |
| `code`, `error_type` | such as `job_failed`, `tun.mail::mail-not-delivered` |
| `message`, `tool`, `backtrace`, `request_id` | of the latest occurrence |
| `first_seen_at`, `last_seen_at`, `count` | when it was first and last seen, and how many times it happened |
| `status` | `open`, `resolved` or `ignored` |
| `status_changed_at`, `status_changed_by` | |
| `notified_at` | when the last mail about it went |

`error_occurrences`, the latest 50 of each error: when, the request's id and
kind, tool, actor, message and time taken. A request's input is not kept:
it can hold secrets and personal data. `introspect_request` shows it while
the process still has the request in memory.

- **Recording.** When a fault's request ends, outside its transaction, core
  records it in a write of its own: a new error, or one more occurrence of
  the error with its fingerprint. A request that ends inside a write, such
  as a test's, records in that write. One that ends in a read, or while the
  store is down, is not recorded, and stderr says why. A request in a
  thread `eval` started is not recorded: such a thread may not write.
- **A resolved error that occurs again** is open again: the fix did not
  hold. An ignored one stays ignored and keeps counting.
- **Erasure.** Erasing a customer's personal data (`redact-request-traces`)
  also erases matching messages and actors in the recorded errors, in the
  same transaction.
- **Pruning.** A resolved or ignored error not seen for 90 days is deleted,
  with its occurrences, when the next error is recorded.

## 5. Mail

```lisp
(define-application tracker-application ()
  (:error-mail (:env "ERROR_MAIL_TO")))
```

`(:error-mail address...)` names who hears of new errors; each address is a
string or `(:env NAME)`. When an error is new, or open again after being
resolved, core sends each address a mail in the recording write, in the
tenant's language: «New error in Saker: …» («Ny feil i Saker: …»), with the message, where it happened, how many times, and a link
to its page at the public URL. At most one mail per error an hour, so an
error that flaps is one mail. Without `:error-mail`, nothing is sent, and
the errors are on the page and in the tools.

## 6. Log lines

A server (`serve`) writes one JSON line to standard output for every
request when it ends, for `nixploy logs`, the journal or a log store:

```json
{"at":"2026-10-21T07:00:01Z","level":"error","request_id":"req_…","kind":"job",
 "tool":"job:send_queued_mail","actor":"system:job","outcome":"error",
 "code":"job_failed","ms":312.4,"statements":3,"message":"…","error_id":"err_…"}
```

`level` is `error` for a fault, `warn` for any other error or a refusal,
and `info` otherwise. `message` and `error_id` appear only on faults: a
refusal's message often repeats what someone typed. The
input and the trace are not logged. `--log none` turns the lines off. Tests
and the REPL write none.

## 7. Tools

| Tool | Policy | Does |
|---|---|---|
| `errors_list` | admin | Errors in one status (`open` by default), latest seen first: type, code, message, tool, how many times, first and last seen. |
| `errors_get` | admin | One error with its backtrace and its latest occurrences. |
| `errors_set_status` | admin | An error marked `resolved`, `ignored` or `open`. |
| `introspect_recent` | admin | Gains `request_kind` (`operation`, `mcp`, `web`, `job`, `workflow`) and `tool`, a part of the tool's name, to narrow the requests in memory; each item gains its `kind` and its error's `message`. |

## 8. Pages

The `dashboard` module (`modules/dashboard/README.md`) gains two pages for
admins:

- **«Errors»** («Feil») at `/errors`: the errors by status, each with its count and
  when it was first and last seen; one error with its backtrace, its
  occurrences, and buttons to resolve, ignore or open it again.
- **«Log»** («Logg») at `/log`: the requests the process has in memory, newest
  first, narrowed to errors, refusals or slow ones and to one kind; one
  request with its input, its steps in time order, drawn against the
  request's whole time, and its backtrace.

## 9. Taken and left

Taken:

- Sentry's grouping by stack, and its statuses resolved and ignored, with a
  resolved issue reopening when it recurs.
- Solid Errors' two tables, errors and occurrences, in the application's own
  database, and its mail when an error first appears.
- Telescope's request list and request page, read from the trace Tun
  already keeps.
- Hangfire's dashboard as the place it is shown.

Left:

- **Keeping every request in the database.** Tun has one writer per
  database (`store.md` §2), and a row per request would make every read a
  write. The requests stay in memory and in the log lines; only faults are
  stored.
- Log messages written by hand (`log-info "…"`): a request's steps already
  say what it did, and a client that needs more records it on its own
  records.
- Sending errors to Sentry or another tenant: later, through the feedback
  module (`feedback.md`), when a tracker collects them.
- Metrics over time (Pulse's slow queries, request rates): later, as a page
  of the dashboard.
