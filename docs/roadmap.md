# What core still needs

Status: draft, 2026-10-14; principles and order agreed the same day. A list of the parts nearly every business
application needs, what Tun has of each today, and what is missing. It is
measured against Ash (Elixir) and Laravel (PHP), the two frameworks whose
designs Tun borrows most from (`reference/sources.md`).

The rule behind it: the hard, generic work lives in core, so a client is
business logic and little else. A client that needs a job with retries
declares the job and its attempts; it never writes the retry loop.

## Principles

Decided 2026-10-14:

- **Lean, and ours.** Tun takes ideas from Ash and Laravel, not their
  size. A piece goes into core when a real client needs it, in its
  smallest useful form. Most of the table below is not built until then.
- **No ORM.** Reads that `select` cannot express are SQL in `define-query`
  (`spec/store.md` §5); writes go through entities, where rules, ownership
  and audit apply. Relationships, aggregates and pagination are SQL.
- **Postgres only.** One dialect. The memory and SQLite adapters go once
  the kernel suite runs on Postgres.
- **Compile time stays small.** Ash is slow to compile because its
  macros do their work at compile time and depend on each other. Tun's
  macros expand small and read no other definition while expanding
  (`reference/style.md`, Macros); everything else looks definitions up when
  it runs. A full build took 13 s on 2026-10-14 (kernel, 12 modules, two
  clients, tests), and redefining one entity or operation in a running image about
  40 ms. A change that doubles either needs a reason.

## Where Tun stands

Core already does what many frameworks leave to the application:

- One definition, every surface: an entity is a table, a JSON shape, a
  JSON Schema, a form and an MCP tool's input (`define-entity`,
  `define-operation`).
- One guarded execution path: role policy, validation, confirmation,
  transaction, idempotency, audit, for MCP, UI, workflows and Lisp alike.
- Accounts, sessions, sign-in through WorkOS AuthKit, Google or any OIDC
  provider (Tun keeps no passwords), bearer tokens that act as their
  person, and OAuth for MCP clients through WorkOS (`spec/auth.md`).
- Postgres and SQLite behind one store contract, additive migrations derived
  from the entity classes (`spec/store.md`).
- Request traces, introspection tools, deadlines, backpressure, bounded
  input.
- A design system with generated list, record and form screens
  (`spec/ui.md`).
- `tun new`, `tun add`, `tun update`, a Nix image and nixploy deploys,
  backups (`spec/cli.md`, `spec/deploy.md`).

## The gaps

Each row: the need, what Ash and Laravel call it, what Tun has, what is
missing. **Tracker** marks what the first client, a feedback and work
tracker, needs in its first version.

### Data

| Need | Ash / Laravel | Tun today | Missing |
|---|---|---|---|
| Queries, joins, aggregates | `Ash.Query`, aggregates / query builder, `withCount` | `select` for one entity by field; **`define-query`** for SQL reads, checked at start | List parameters (`= ANY(:ids)`) |
| Timestamps | `create_timestamp`, `update_timestamp` / `timestamps()` | written by hand where wanted | **Tracker.** `created_at` and `updated_at` on every stored entity, set by the store |
| Column types | (Postgres types) | booleans as `BIGINT`, timestamps as `TEXT`, from the SQLite days | Postgres's own types, once SQLite is gone |
| Archiving | AshArchival / `SoftDeletes` | `delete-entity`: a row is gone or kept forever | Archive instead of delete; later |
| State machines | AshStateMachine / (packages) | `:kind :transition` operations, each checking state itself | **Tracker.** Declared states and transitions on the entity; the UI offers only the transitions the record allows (today «Handlinger» lists every action) |
| History | AshPaperTrail / (packages) | an audit entry per operation | **Tracker.** A record's timeline from the audit, as a component |
| Search | (AshPostgres full text) / Scout | none | Postgres full text with the `norwegian` dictionary; later |

### Migrations

Derived migrations are additive only: new tables, nullable columns,
constant defaults. Ash generates migrations from snapshots of the resources;
Laravel has hand-written migration files. Tun keeps deriving the additive
part and needs explicit steps for the rest:

- rename a field or entity, drop one, change a type, backfill computed
  values;
- written as expand and contract across two deploys, because the old and
  new process share the database during a blue/green switch
  (`spec/store.md` §3);
- a backfill runs as a job, in batches, not inside the start-up migration.

Not needed for the tracker's first version. Needed soon after real data
exists.

### Jobs and scheduling

| Need | Ash / Laravel | Tun today | Missing |
|---|---|---|---|
| Background jobs | AshOban, Oban / queues | **`define-job`** with typed arguments and **`enqueue-job`** in the caller's transaction, started as soon as it commits; workflows, mail delivery and the messaging outbox run on them (`spec/jobs.md`) | |
| Retries | Oban `max_attempts`, backoff / `$tries`, `backoff()` | attempts, Oban's backoff with jitter or a list, `cancel-job`, `snooze-job`, `fail-job`, a failed state admins see and retry (`jobs_retry`) | |
| Queues and concurrency | Oban queues / named queues, Horizon | named queues with a limit each, `(:queues (:mail 1))`; presence locks recover a lost process's jobs | |
| Unique jobs | Oban `unique` / `ShouldBeUnique` | `:unique` by arguments, period and states | |
| Recurring tasks | Oban cron / scheduler | **`define-schedule`**: cron in the tenant's time zone, once per occurrence across processes, bounded catch-up | |
| Work per record | AshOban triggers / (scheduled commands) | **`define-trigger`**: a job for every record meeting a condition, unique by the record, cancelled when the record no longer meets it | |
| Multi-step work | Reactor / job chains, batches | ports record intent and outcome | Chains and compensation; later |

Built 2026-10-20 (`spec/jobs.md`): jobs, schedules, and mail delivery,
workflows and the messaging outbox on them: Tun has one queue. Triggers
2026-10-21.

### Authorization

| Need | Ash / Laravel | Tun today | Missing |
|---|---|---|---|
| Who may call an operation | policies / gates | `:viewer`, `:employee`, `:admin` per operation | Roles a client declares (a customer, a supplier), not only three ranks |
| Which records | filter checks / policy methods, scopes | **`:record-policy`** on the entity: an SQL condition per role, applied by Postgres to every read and write (`spec/store.md` §6) | A client adding a policy to a module's entity; a write condition apart from the read one |
| Which fields | field policies / `$hidden` | `:secret` fields read as `"***"` | Fields only some roles see, such as an internal note on an item |

### Pages and routing

| Need | Ash / Laravel | Tun today | Missing |
|---|---|---|---|
| Routes | Phoenix router / `Route::get('/items/{item}')` | generated screens; **`define-page`** for a client's own pages: a path prefix, a role, the handler splitting the rest (`spec/ui.md` §8) | Path patterns such as `/saker/:item` with typed parameters (an `(id item)` parameter loads the record, through its policy, or answers 404) |
| Links | verified routes / `route('items.show', $item)` | literal strings | **Tracker.** A link names its page and parameters, so a moved path breaks the build, not the link |
| Page state | LiveView / Livewire | full page loads; plain forms | Partial updates for small interactions (add a comment without a reload); later |

The public page dispatcher in core still knows one module's path
(`offer/.../open`); routing would remove that.

### Mail and notifications

| Need | Ash / Laravel | Tun today | Missing |
|---|---|---|---|
| Sending mail | Swoosh / Mail | **`send-mail`** queues in the caller's transaction; a worker delivers through **Resend** (or logs), retrying temporary failures with backoff, with an idempotency key (`spec/mail.md`) | Several recipients, attachments; bounce webhooks. The messaging module's customer outbox still has its own fake transport |
| Notifications | notifiers / Notifications with channels | a client sends its own with `send-mail`, a key per record, and `account-address` | `define-notification` with channels (mail, in the app), a person's unread list and preferences, when a second client wants the same |
| Invites | AshAuthentication add-ons / (packages) | **`accounts_create` with `invite`** mails the person how to sign in: the provider and address (`spec/auth.md` §3.6); a client invites through `(invoke 'accounts-create …)` | Sending an invitation again; an invitation that expires unused |

### Files

Ash and Laravel both have file storage with a local disk and S3. Tun has
none. A storage port with a disk adapter and an S3-compatible one, an
attachment field type, size and type limits. Not in the tracker's first
version.

### Connected systems

Several systems built on Tun should be able to work as one suite: a module
shipped in one system can feed a whole system built earlier. The first case
is feedback (`spec/feedback.md`): people report a problem from any page of a
client, and it arrives as an item in a tracker system, where agents work
it. Each system stays its own tenant; they meet only through each
other's MCP tools, with a token, behind a port.

| Need | Tun today | Missing |
|---|---|---|
| Reporting into a tracker | none | **Feedback.** The `feedback` module: a form on every page, a report queued and delivered as mail is, status read back |
| One Tun system calling another | none | Named links to other tenants (a URL and a token from the environment) and calls to their operations with typed answers, drawn out of feedback when a second pair of systems needs it |
| One place to debug every tenant | each tenant's introspection tools, each its own MCP server | **Idea** (`spec/fleet.md`): a registry of tenants, their tools by name, the fleet's health at once, and a log of diagnoses; later, when the fleet outgrows a list of MCP servers |

### Security and personal data

| Need | Tun today | Missing |
|---|---|---|
| Browser headers | HSTS, `Referrer-Policy` on public pages | `Content-Security-Policy`, `X-Content-Type-Options`, `frame-ancestors` on every page |
| CSRF | `Sec-Fetch-Site` / `Origin` check, `SameSite=Lax` | A token as well (a known limit in `docs/architecture.md`) |
| Rate limits | login, per email and process; connections, requests in progress and waits held per client address, by the trusted proxy's forwarded address (`spec/core.md` §7.5) | A limit of requests over time per account and per address |
| Personal data (GDPR) | customer erasure and trace erasure in the orders module | Fields marked personal; an export of everything about one person; erasure and retention as core features. A selling point to Norwegian businesses, and a duty |
| Encrypted fields | none | Encryption at rest for the few fields that need it (AshCloak); later |

### Operations

| Need | Tun today | Missing |
|---|---|---|
| Logs | a JSON line on stdout per request (`--log`); the requests in memory on the dashboard's «Logg», each with its steps (`spec/errors.md`) | A log store that keeps the lines, searchable; later |
| Errors | faults grouped by cause and kept in the store, `errors_*` tools, the dashboard's «Feil», a mail on a new error (`(:error-mail ...)`) | Errors sent into a tracker through the feedback module |
| Health and metrics | `/health`; queue depth and failed jobs on «Jobber» and in `jobs_summary` | Slow requests and request rates over time (Pulse); later |

### Testing and development

| Need | Ash / Laravel | Tun today | Missing |
|---|---|---|---|
| Test data | generators / factories, seeders | each test builds its records | **Tracker.** Factories derived from the entity's types (a valid record in one call, any field overridable), and `tun seed` for a development database |
| Fakes | `Mail::fake()`, `Http::fake()`, `Queue::fake()` | fake adapters behind every port | Assertions on them for clients: "one mail was sent to x" |
| Page tests | Dusk, `$this->get()` | `bin/ui-shots`, in-process requests in the kernel suite | The same helpers for a client's suite |
| Previews | — / Laravel Cloud preview environments | **`tun preview`**: a working tree at a tailnet link with fresh data and anyone's sign-in, also on a Tun worktree; scenarios (`spec/preview.md`) | |
| Browser checks | — / Dusk | **`tun check`**: committed checks, each on a fresh preview of its scenario, with touch; Tun's own on the showcase (`bin/check`) | |

## Deliberately not

- **Caching.** One process per tenant at small-business scale; the database
  is fast enough. Revisit with measurements.
- **Multitenancy in one process.** Decided: one process per tenant.
- **A JSON or GraphQL API.** MCP is the API for agents; the UI is the API
  for people. A JSON API for a client's own integrations comes when one
  needs it.
- **Code generators** (`artisan make:`, Igniter). The macros are short and
  agents write them; skills teach the shapes.

## Order

Each step is a spec change, then the code, then its tests.

1. **`define-query`.** Done 2026-10-14 (`spec/store.md` §5).
2. **Record policies.** Done 2026-10-14 (`spec/store.md` §6): one SQL
   condition per role decides reads and writes.
3. **`tun new` the tracker**, and from here on build only what it pulls.
   Done 2026-10-15: the tracker's items, comments, questions and pages,
   which pulled `define-page` and `TUN.UI` for clients (`spec/ui.md` §8).
   It keeps its own timestamps and status table for now. Mail through
   Resend, with retries, done 2026-10-15 (`spec/mail.md`). Notifications
   (in the client, on `send-mail`), invites, jobs and schedules (in core,
   with the tracker's daily summary on them) done 2026-10-20. Next, factories,
   security headers, and timestamps and state machines in core when a
   second client wants the same.
4. **Postgres only**: the kernel suite on Postgres, then the memory and
   SQLite adapters removed and Postgres's own column types. Between
   tracker steps, when the suite's speed on Postgres is measured.
5. **Feedback into a tracker** (`spec/feedback.md`), when a second client
   exists: files in core first, then the `feedback` module and the
   tracker's side, then the status read back. The general link between Tun systems
   follows from it.

6. **Previews and checks** (`spec/preview.md`). Done 2026-10-24.
7. **The feature loop** (`spec/loop.md`): agents take a request from idea
   to deploy, with a person or a reviewer approving at gates. The
   procedure, the record and `tun loop`, hands-on and reviewed, built
   2026-10-24; next, a client's request run through it, then the loop's
   state in the tracker.

Everything else in the tables waits for a client that needs it.
