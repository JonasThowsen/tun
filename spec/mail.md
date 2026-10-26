# Mail

Status: v1, 2026-10-15. How an application sends email: a mail is
written in the same transaction as the work that sends it, and delivered
after that work commits, through the application's mail provider, with
retries. Resend is the provider Tun ships; without one, mail is recorded
and logged but not sent.

## 1. Choosing the provider

`define-application` names it in its `(:mail …)` option
(`docs/client-api.md`):

```lisp
(define-application tracker-application ()
  (:mail (:resend :api-key (:env "RESEND_API_KEY")
                  :from (:env "MAIL_FROM"))))
```

| Provider | Settings |
|---|---|
| `(:resend …)` | `:api-key`, `:from` |
| `(:log)` | none |

- A setting is a string, or `(:env "NAME")`: the value of that
  environment variable, read when the server starts, as for sign-in
  (`auth.md` §3.5). The API key belongs in the deployment's SOPS file
  (`deploy.md` §3), never in the repository.
- `:from` is the sender, such as `Saker <varsel@example.no>`. Resend
  sends only from a domain verified in its dashboard.
- Without the option, the provider is `(:log)`.
- In authenticated mode a server whose provider lacks a value refuses to
  start, with exit status 2 and a line naming what is missing. In claimed
  mode, and in an application opened in-process (a test), it uses
  `(:log)` instead and says so.
- `(:log)` sends nothing. It accepts every mail at once, records it as
  sent by `log`, and writes the recipient and subject, not the text, to
  the server's standard output.

## 2. Sending

`(send-mail &key to subject text html reply-to key)`, in the TUN package,
is called inside a write: an operation, a workflow, or an `:on-open`
function.

- `to` is one address. `subject` (at most 998 characters) and `text` (at
  most 100 000) are required; `html` (at most 500 000) and `reply-to` (one
  address) are optional. An address is checked as the `email` field type
  checks it. A bad argument signals an error, so the operation fails
  `invalid_input` and nothing is written.
- It stores a mail with status `queued` and returns it. The mail is part
  of the caller's transaction: when the operation fails or rolls back, no
  mail exists and none is sent.
- `key`, a string of at most 200 characters, makes the send once only:
  when a mail with that key exists, in any status, `send-mail` returns it
  and stores nothing. A notification uses one, such as
  `"answer:kom_…"`, so sending it again is harmless.

## 3. Delivery

Each mail is delivered by a job (`jobs.md`), `send_queued_mail`, enqueued
with it in the sender's transaction; the mail's `job_id` names it.

- The job runs in the `:mail` queue, one at a time unless the application
  says otherwise (`(:queues (:mail N))`), outside any transaction, so a
  slow provider never holds the writer lock or delays other work.
- In test mode `clock_set` runs it with the other due jobs and answers
  how many attempts they made, as `job_attempts`.
- An attempt marks the mail `sending` and counts it, calls the provider
  within 10 seconds, then records the outcome:

| Outcome | Status | Next |
|---|---|---|
| accepted | `sent`, with `provider`, `provider_id` and `sent_at` | none |
| temporary (a timeout, no connection, 409 from a request already in progress, 429, 5xx) | `queued` | the job's next attempt, after 30 s, 2, 10 and 30 minutes, 1 hour, then 3 hours |
| permanent (any other answer) | `failed` | none: the job fails at once (`fail-job`) |

- After the seventh attempt a temporary outcome also leaves the mail
  `failed`, and its job failed. Each delay gets up to a tenth more at
  random, so mails that failed together do not retry together; in test
  mode it is exact.
- `last_error` holds the last attempt's reason, such as `resend 422
  validation_error: …`, until the mail is sent. The job keeps every
  attempt's (`jobs_get`).
- A mail left `sending` by a process that stopped during the call is
  attempted again when its job is recovered (`jobs.md` §7), within a
  minute, by whichever process notices. Nothing is requeued when a
  process merely starts, so the other process of a blue/green switch
  keeps its own.
- Every attempt sends the mail's id as the provider's idempotency key.
  Resend keeps a key for 24 hours, and every retry falls within that, so
  a retry after a lost answer never sends the mail twice.

## 4. Resend

The adapter POSTs to `https://api.resend.com/emails`, over HTTPS with the
certificate verified, with `Authorization: Bearer API-KEY`,
`Idempotency-Key: MAIL-ID` and a JSON body: `from`, `to` (a list of one),
`subject`, `text`, and `html` and `reply_to` when the mail has them. A
200 answer's `id` is the mail's `provider_id`. An error answer's `name`
and `message` go into `last_error`. The API key is never written to a
record, a log line or a printed adapter.

## 5. Tools

Admin only. Mails are stored records, read through the tools:

| Tool | Does |
|---|---|
| `mail_list` | The latest 100 mails, newest first, optionally only one `status` or one `to`: id, to, subject, status, attempts, last error and times, without the text. |
| `mail_get` | One mail with its text and html. |
| `mail_retry` | Queue a `failed` mail again with a new delivery job, due at once, its attempts reset; any other status is `invalid_transition`. |

A mail's text is shown only to admins.

## 6. Not yet

- Several recipients, copies, attachments and templates. A client builds
  its text and html itself.
- Another provider (SMTP, Postmark). Each is one class with one method
  (`docs/client-api.md`).
- Webhooks for what happens after the provider accepts a mail: bounces,
  complaints, opens.

## 7. Evidence

- `tests/mail-tests.lisp`: sending inside a write and nothing after a
  rollback; the key; validation; delivery through a scripted provider
  (accepted, temporary with each delay, permanent, the seventh attempt);
  a mail whose process stopped mid-send, recovered with its job; the
  delivery job in the `:mail` queue, run by the scheduler's worker;
  `clock_set`; the three tools and who may call them; the provider chosen
  from `(:mail …)` and the problems reported for missing settings; the Resend adapter over
  real HTTP against a fake Resend in the test process that checks the
  key, the idempotency key and the body, and answers 200, 422, 429 and
  500.
