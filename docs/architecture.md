# Tun architecture

How the platform is put together, for an agent or a person about to change it.
Read this before `client-api.md` (how a client extends the platform) and
`../reference/` (how we write Common Lisp).

## Layers

| Layer | What it is | Where |
|---|---|---|
| Kernel | Registry, execution path, store, workflows, settings, accounts and credentials, MCP and HTTP, generated UI, introspection. Owns no business entities. | `tun.asd`, `src/` |
| Module | Reusable business behaviour: entities, operations, rules, workflows, templates, screens, migrations, and the extension points it publishes. | `modules/<name>/` |
| Client | One business's own code. It enables modules, extends them through their published points and adds its own definitions. | its own repository (`tun new`) |
| Tenant | One deployed client: one process, one database (SQLite or Postgres), one set of pins. | a Nix-built server |

A tenant is a single process. Clients never share a process or a database, so
an agent working on one client cannot touch another's data.

## Repository map

```
tun.asd            kernel systems: tun/core, tun/memory, tun/sqlite, tun/postgres, tun, tun/tests
tun-test-support.asd   test helpers for the kernel's suite and every client's
tun-cli.asd        the tun command (spec/cli.md)
flake.nix          dev shell, the kernel package, the tun command, buildClient and
                   clientShell for client flakes
src/core/          defining macros, types, entities, operations, execution, store port, modules
src/store/         store adapters: memory (tests), SQLite and Postgres (tenants)
src/jobs/          background jobs, their workers and crash recovery, schedules in
                   Norwegian time, triggers (spec/jobs.md)
src/platform/      workflows (on jobs), platform tools, introspection, live definitions,
                   recorded errors and request log lines (spec/errors.md)
src/auth/          accounts, sign-in providers, access tokens, sessions, setup (spec/auth.md)
src/mail/          sending mail: the mail record, its delivery job, the log and Resend
                   adapters (spec/mail.md)
src/push/          push notifications: subscriptions, notify-push, the delivery job, Web Push
                   encryption and VAPID (spec/push.md)
src/agent/         MCP JSON-RPC and the HTTP server
src/web/           HTML renderer, the design system (ui/), the generated UI built from it,
                   and login and /access pages
src/ports/, src/adapters/   the accounting port and its fake adapter
src/cli/           the tun command, and under template/ the files of a new client
src/public.lisp    the TUN package: the public interface clients use
src/runtime.lisp   open-application and main, the one entry point for every server
modules/<name>/    one ASDF system, flake and README per module
clients/<name>/    a client you add locally: its own flake pinning core and every module
tests/             the kernel and module suite (no client loaded); support.lisp and
                   scenarios.lisp are the test support clients use too
tests/client/      the test client: the client surface, run in a suite of its own
checks/showcase/   the client Tun's own browser checks drive, and its checks
docs/loop.md       the feature loop's procedure for agents; docs/review.md, a reviewer's
loops/             the records of feature loops run in Tun (spec/loop.md 5)
spec/              behaviour contracts
bin/, scripts/     build, test, serve and check tooling
reference/         Common Lisp style, idioms and sources for agents
```

## One definition, every surface

The defining macros expand into ordinary Common Lisp and register metadata
that every surface reads at call time.

```lisp
(define-entity customer (:label "Kunde" :id-prefix "cus" :table "customers")
  ((name  :type (string :min 1 :max 120) :required t :label "Navn")
   (email :type email :required t :label "E-post")))

(define-operation customers-get ((id :type (id customer) :required t :label "Kunde-ID"))
    (:entity customer :kind :read :title "Hent kunde")
  (fetch! 'customer id))
```

- **`define-entity`** expands to a `defclass` with the `entity-class`
  metaclass. Field metadata lives on custom slot definitions. JSON
  projection, input validation, JSON Schema, SQL columns, migrations,
  `registry_describe` and UI forms all read it through the metaobject
  protocol (closer-mop).
- **`define-operation`** expands to a `defgeneric` with the `operation`
  method combination, one primary method, and a registered operation object
  holding the tool name, kind, policy and confirmation flag.
- **The MCP tool list, `registry_describe` and the UI** are computed from the
  live classes and operation objects, so a client's definitions appear with
  no registration step.
- **Every definition records its owner**, decided from `*package*` at
  macroexpansion: `core`, a module name, or `client`.

## The execution path

The `operation` method combination is the security boundary. Its effective
method wraps every call, whether it comes from MCP, the UI, a workflow or
plain Lisp:

1. actor, then policy, before any lookup; a refusal is audited;
2. input validation against the declared parameters;
3. for `:confirm t`, a one-time token bound to actor, tool and input;
4. a write transaction: idempotency receipt, token, `:before` methods, the
   primary method, `:after` methods, audit entry, receipt.

Read operations run in a read transaction, where any store write is an error.
The combination accepts only `:before`, `:after` and one primary method, so a
client cannot wrap an operation with `:around` or replace its body. Start-up
refuses a deployment that tries. Hooks run in a fixed order: modules in
dependency order, then the client.

## Identity

Every call runs as an actor, `role:name`, and the execution path decides
from it alone. Where the actor comes from is the transport's business
(`spec/auth.md`):

- **Agents** call `/mcp` with `Authorization: Bearer tun_...`, an access
  token that acts as its account and never as more. A person makes tokens
  for themselves at `/access`, so their agent has exactly their access; an
  admin makes them for agent accounts, never for another person. A request
  without a valid token gets 401 before its body is read.
- **Other systems** call one tool with `POST /api/TOOL` and the same
  token (`spec/api.md`): the same callers, the same execution path, and
  the tool's result as the answer, without JSON-RPC.
- **People** log in at `/login` and get a session cookie, through an
  identity provider the application lists in `define-application`'s
  `(:sign-in …)`: usually WorkOS AuthKit, whose page handles passwords,
  codes by email, passkeys and single sign-on, or Google. Tun keeps no
  passwords. A provider only proves an email address, so an admin creates
  the account first, and the first sign-in links the provider's identity
  to it.
- **The first admin** of a new tenant is created at a one-time
  `/setup/CODE` the server prints at start.
- **`--claimed-identity`** makes the server believe `X-Tun-Actor` and
  `/login?actor=`. Tests, previews and local development use it; a
  deployed server never does.

Credentials are stored as hashes, in records whose hash fields are marked
`:secret` and read as `"***"` everywhere. A new token reaches its
caller through `show-once`, so the idempotency receipt never holds it.
Each audit entry and request trace records the credential its call used.

## The web UI

Every page is built from the design system's components (`src/web/ui/`,
`spec/ui.md`); nothing else styles a page. A staff page is an `app-shell`
with the menu: the resources, then the staff pages the actor may see, each
with the icon its registration names. A page for someone not logged in
(login, setup, a customer's offer) is the same frame
without the menu. A client that declares `(:web-app ...)` can be
installed as an app: every page links its manifest and icons, and a
service worker keeps the stylesheet and scripts and shows an offline
page, never a signed-in page (`spec/ui.md` §4.2). It also shows the
notifications Tun pushes to the devices where people turned them on
(`spec/push.md`).

The screens are generated from the registry. A list is a `table` of the
fields that name and place a record (its name or id, status, the records it
refers to, a date, its total); a record is a `summary-list` of the fields
that have a value, with its status operations in the page header (a menu
when there are more than two); a create form chooses each control from the
input's type and puts a refusal's field errors at the fields and in an
`error-summary`; a `:confirm` operation shows a `confirm-panel`. Amounts in
øre are shown in kroner, dates the Norwegian way, references by the name of
the record. Modules and clients build their own pages from the same
components, through `TUN.UI`; a client defines one with `define-page`.

## Extension points

A client's features are mixin classes of its application class. Methods
specialise on the feature class, so they never collide and run in class
precedence order. The full API is in `client-api.md`. In short:

| Need | Mechanism |
|---|---|
| A field on a module's entity | `extend-entity` adds a mixin superclass to the live class |
| A validation | `define-rule` runs on every insert or update of the entity |
| A derived value | `define-computed-field`, evaluated when the record is read |
| React to an operation | `:before` or `:after` method on the operation's generic function |
| A domain decision inside an operation | a method on a published seam, such as `order-discount` or `booking-window` |
| Work later, again when it fails, or on a timetable | `define-job` and `enqueue-job`; `define-schedule` with a cron time |
| Timed behaviour about an order | `define-workflow` and `schedule-workflow` |
| Email | `send-mail` in an operation; the provider is `(:mail ...)` in `define-application` |
| Messages | `define-message-template`, overriding a module's non-final template |
| A screen | a method on `render-screen` for the screen's keyword |
| Configuration | `define-setting`, typed, with durable per-tenant values, or read from the environment with `:env` |
| Call another system's API | `http-json-post`, in a read; `remote-failure` when it gives no usable answer |
| Install as an app | `(:web-app :icons "icons/" ...)` in `define-application`: manifest, icons, service worker |
| Notify people's phones | `ui:push-switch` on a page, and `notify-push` in an operation (installable clients) |

Seams exist where a module needs the client's answer inside the operation,
before it saves. An `:after` method could only patch the record afterwards.
Each seam is a documented generic function with a neutral default.

## The boundary

A client package uses only `CL` and `TUN`, and the components in `TUN.UI`
for its pages. Three layers keep it there. None
of them is a sandbox: they stop honest mistakes and make review possible.

1. **The interface check** in the client suites reads every client file with
   the Lisp reader. It refuses `::`, internal symbols, `in-package` into
   another package, reflective operators such as `intern` or `eval`, and an
   `.asd` with anything but data options. Modules get the same check against
   the kernel's public packages (`TUN.CORE`, `TUN.WORKFLOWS`, `TUN.JOBS`, `TUN.WEB`,
   `TUN.UI`, `TUN.ACCOUNTING`) and the interfaces of the modules they depend on.
2. **Package locks** stop redefinition of kernel and module definitions from
   client packages. SBCL does not enforce a lock while that package is
   current, which is why layer 1 refuses `in-package` into it.
3. **The integrity check** snapshots every function and method of the
   kernel and each module after loading. Start-up refuses a changed,
   wrapped or removed definition. Without `--debug-tools` the same check
   runs before every tool call and workflow pass.

Writes are guarded too. Through `TUN`, `insert` and `save` let a client store
its own entities and its own fields on module records, never a module-owned
field. A seam method that changes a module-owned field on a record it was
handed makes the request fail.

## Store

- **The store is a port; Postgres is the store.** The in-memory and
  SQLite adapters remain until the kernel suite runs on Postgres, and get
  no new features. `--db` picks one: a file path for SQLite,
  a `postgresql://` URL for Postgres, or `DATABASE_URL` when `--db` is
  absent. All three pass the same contract tests. `spec/store.md` is the
  contract.
- **One writer at a time per database.** Read transactions see one snapshot
  and never wait. Write transactions run one at a time: on SQLite through
  `BEGIN IMMEDIATE`, on Postgres through an advisory lock each write
  transaction takes first, which holds across processes. No write returns
  before it is durable.
- **SQLite runs in WAL mode**, with all writes on one connection and group
  commit batching them, up to 16 per fsync.
- **Postgres** lets the old and new process of a blue/green switch share
  the database for a moment: writers queue across both, and a due job
  runs once, whichever process takes it.
- **Reads beyond `select` are SQL**, in `define-query`: `{entity}` for a
  table, `:name` for a parameter, records or typed rows back. Every query
  runs once at start, so a schema change that breaks one stops the start.
  Writes never go through SQL.
- **Record policies** limit which records each role reaches: an SQL
  condition per role on the entity, which the Postgres adapter puts into
  every statement that reads or writes it. A record outside the condition
  is not found, and a write that would leave one outside is `forbidden`,
  on every surface alike.
- **Migrations are derived from the entity classes.** They are additive
  only: new tables, new nullable columns and constant defaults. They are
  namespaced per module, `<module>_<nnnn>_<name>`, and run at start in
  dependency order.
- **Client fields** on a module's entity are stored apart from the
  module's columns, so module migrations never see them.

## Jobs, workflows, settings, ports

- **Jobs are the one queue** (`spec/jobs.md`). `enqueue-job` stores a job
  in the caller's transaction; a worker per queue runs due jobs, each
  attempt in a request of its own as `system:job`, retrying failures with
  growing delays. Each process writes a heartbeat, and the running jobs of
  one that is gone are recovered by another within a minute.
  `define-schedule` enqueues a job at each occurrence of a cron time in
  Norwegian time, once whichever process runs.
- **Workflows run on jobs.** `schedule-workflow` stores the workflow and
  its job, due when it is. The job runs it as `system:workflow`, in its
  own transaction, at most once. A failing handler is rolled back and
  marked failed with its error.
- **Settings are typed declarations.** Defaults live in code and overrides
  in the tenant's store. Secrets are masked in every listing.
- **Mail is queued, then delivered.** `send-mail` stores the mail and
  its delivery job in the caller's transaction. The job sends it after
  commit through the application's provider (Resend, or a log adapter
  that sends nothing) and retries temporary failures with growing
  delays. Every attempt carries the mail's id as the idempotency key
  (`spec/mail.md`).
- **Push notifications are queued the same way** (`spec/push.md`):
  `notify-push` enqueues a job per device in the caller's transaction,
  and each job encrypts the message for its device and posts it to the
  browser's push service, retrying as mail does.
- **External systems sit behind ports with fake adapters.** Accounting and
  the messaging module's customer messages and inbound mail are faked, and
  no external service is called. A port call happens outside any
  transaction. The intent is committed first and the outcome recorded
  after, and start-up reconciles intents that have no outcome.

## Runtime properties

| Property | How |
|---|---|
| Deadlines | Every operation and workflow run gets `--deadline-ms`. Cooperative checks unwind at store access and in loops. A watchdog interrupts code that never checks. |
| Backpressure | Above `--max-inflight` requests, the server answers 503 at once. Nothing queues. |
| Fault isolation | A `serious-condition` fails only its own request or workflow run. |
| Bounded input | Headers, body size, JSON depth, string length and number length are capped before parsing. |

## Introspection and live code

A running tenant explains itself through admin-only MCP tools:

- `introspect_request` and `introspect_recent` give request traces with every
  step: policy, hooks, rules, SQL, port calls, commit wait and backtrace.
  The traces live in memory; a request that ends in a fault, an error the
  code did not mean, is also kept in the store, grouped with the others of
  its cause (`errors_list`, `errors_get`, `spec/errors.md`), and a server
  writes a JSON line per request to standard output.
- `introspect_record` shows a record with its sources, relations and audit.
- `explain` dry-runs a tool call and shows the hooks and effects.
- `introspect_extensions` lists every extension with `file:line`.
- `introspect_runtime` reports build revisions, modules, memory, threads
  and the clock. Its `live_patches` lists functions and methods that changed
  in the running image after start.

`--allow-eval` adds a read-only `eval` tool. `--debug-tools --repl-port N`
starts a Swank REPL inside the image, with full access and no
authentication. `bin/drift` compares the loaded source with a checkout and
fails on any live patch. Both exist for diagnosis. Production changes go
through git and a build, never through the REPL.

## Tenants and deployment

- **The kernel is a Nix package.** `flake.nix` builds it from kernel sources
  only. Each module is its own flake.
- **A client is a flake that pins the kernel and every module by git
  revision.** `buildClient` checks each module against the kernel's version
  range and its dependencies, builds everything, and wraps a launcher. The
  launcher refuses to start unless all code resolves under `/nix/store`.
- **`tun new NAME MODULE...` creates a client repository** (`spec/cli.md`):
  a flake with one input for the kernel and one per module, all locked at
  one Tun revision, the client's ASDF system and application, a test-suite
  with the public-interface check, and a dev shell (`clientShell`) with the
  pinned code, Postgres and `tun` itself. `tun add MODULE` enables another
  module later, pinned at the kernel's revision, and `tun update` locks the
  kernel and every module at one newer revision.
- **A client deploys with nixploy** (`spec/deploy.md`): `nix build .#docker`
  builds an image whose entrypoint is the server, and the targets in the
  client's `deploy.nix` get Tun's defaults (host network, `PORT` from the
  slot, `/health`). The database URL is a SOPS secret on the target. The
  database is the tenant's data; the host backs it up and restores it
  (`spec/deploy.md` §4).
- **A rollback of a pin starts with a preflight.** The newer server, run
  with `--rollback-preflight REGISTRY --db DB`, reads the tenant's database
  against the older code's `registry_describe` and refuses when it holds
  values the older code cannot read. There are no down-migrations.

## Commands

All of these run inside `nix develop .`.

```
bin/build                      compile everything; any warning fails
bin/test                       kernel and module suite, then the test client's and each client's suite
bin/serve --client NAME --port N --db PATH|URL [--test-clock] [--debug-tools] [--allow-eval]
          [--claimed-identity]
bin/repl [--port N] [SYSTEM]   an image for Emacs and SLY, Slynk on 127.0.0.1:4010
lisp start|eval|frame|restart-frame|compile|...  an image for an agent: eval, the debugger, compile (docs/lisp.md)
bin/with-postgres COMMAND...   run COMMAND with DATABASE_URL on a throwaway Postgres
bin/tun list|new|add|update    the tun command from this checkout (spec/cli.md)
bin/tun preview --dir CLIENT   a client on this working tree of Tun, at a tailnet link (spec/preview.md)
bin/check [NAME...]            Tun's browser checks, on the showcase client, in Chromium
bin/tun loop ...               the feature loop: its record, verify, show and gates (spec/loop.md, docs/loop.md)
bin/test-cli                   tun new, build, test, image, restore, serve, preview, check, loop, tun add and tun update
bin/drift --url URL            loaded code against this checkout (TUN_TOKEN: an access token)
bin/recompute --url URL --order ID   reprice one order through the audited path (TUN_TOKEN too)
```

## Known limits

These hold today and matter before a real customer:

- **The UI has no CSRF tokens.** A POST from another origin is refused by
  its `Sec-Fetch-Site` header, or its `Origin` from a browser without one, and the session cookie is
  `SameSite=Lax`; there is no token check besides.
- **The REPL and `eval` are full process access.** They belong on a
  developer machine, never on a public interface.
- **Migrations are additive only.** Renames, drops, type changes and
  computed backfills are not supported.
- **One writer.** Both durable adapters run one write transaction at a time
  per database. A SQLite tenant cannot have two processes at once, which
  rules out a blue/green switch on one file; a Postgres tenant can.
- **Modules share one image.** Module boundaries are held by the same checks
  as clients, not by process isolation. Modules write each other's records
  only by convention.
- **The Nix build is not the strict build.** `bin/build` refuses warnings.
  The Nix build compiles but does not apply that gate.
- **Workflows do not retry.** A failed handler stays cancelled until
  someone acts.
