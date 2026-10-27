# Tun core contract

Status: v1, 2026-10-26. The kernel's base contract: what every client gets
from core whatever modules it enables. The MCP surface, actors and policy,
confirmation, idempotency and audit, workflows, ports, tenants, runtime
properties and introspection. It states the rules as the kernel implements
them. Where another document is the contract for a part, this one points to
it instead of repeating it:

| Part | Contract |
|---|---|
| Modules: identity, dependencies, boundary, extension points, migrations, pins | `tun-platform.md` |
| Accounts, sign-in, access tokens, sessions | `auth.md` |
| `POST /api/TOOL` for other systems | `api.md` |
| Jobs, schedules and triggers | `jobs.md` |
| Store adapters and transactions | `store.md` |
| Recorded errors and log lines | `errors.md` |
| Mail | `mail.md` |
| Waiting calls | `waiting.md` |
| Files attached to records | `files.md` |
| The generated UI and the design system | `ui.md` |
| A business module's own entities, tools and rules | `modules/NAME/README.md` |

Examples use an invented rental business, Nordvik Utleie.

## 1. Core and clients

### 1.1 What a client adds

Core is client-agnostic and owns no business entities. A client adds its
own behaviour without editing core or module source, through these
extension kinds and no others (`docs/client-api.md` has the forms):

| Kind | Example | Shows in |
|---|---|---|
| field on an entity | a customer's `kind` (`privat` \| `bedrift`) and `org_number` | input schemas, results, `registry_describe` with `"source": "client"` |
| rule | `bedrift` needs a nine-digit `org_number` | every insert and update of the entity, as `invalid_input` |
| computed field | a loyalty tier from the customer's completed orders | read results, marked `computed` |
| behaviour before or after an operation | plan a reminder after `orders_send_quote` | the operation's result and side effects, in a fixed order (§1.3) |
| a published seam | the order discount, the booking window | the module's computed values |
| operation | `products_set_cleaning_days` | `tools/list`, the UI |
| workflow | a reminder 48 hours after a quote | `workflows_list` (§4) |
| message template | `påminnelse` | the module's message tools |
| screen | the order page gains a section | `/orders/ID` |

There is no generic "run code anywhere" hook. A client cannot turn off
policy, confirmation, idempotency or audit (§3).

### 1.2 The boundary

A client and core are separately built units. A client uses only the public
interface, the `TUN` package (and `TUN.UI` for its pages); its suite runs
the interface check that fails when it reaches an internal. Modules are held
to the same rule against the kernel's public packages and the modules they
depend on. `docs/architecture.md`, "The boundary", has the three layers that
enforce it; `tun-platform.md` §2.3 is the rule for modules.

### 1.3 Modules and attribution

Business behaviour lives in modules between core and the client
(`tun-platform.md` §2). Every entity, field, operation, rule, workflow,
template, screen and extension item is attributed twice:

- `source`: `core` or `client`. A module's definitions are `core`, since
  to a client they are part of the platform.
- `module`: `core`, the module's name, or `client`: the owner.

`registry_describe` (§3.9) and `introspect_extensions` (§8.2) report both,
and `registry_describe` also lists the modules and the extension points they
publish. `introspect_runtime` lists each enabled module with its revision,
its dependencies and `enabled_by`: `client` when the client's manifest names
it, else the module that needs it. Hooks and rules run in dependency order of
the modules, then the client's, last.

## 2. Conventions

### 2.1 Data

- **Money** is integer øre, NOK, in fields ending `_ore`. Never a float.
- **Dates** are `YYYY-MM-DD`. **Local times** are `HH:MM`, 24 hours,
  Norwegian wall-clock time (§2.2), never converted unless a contract says
  so. **Instants** are RFC 3339 UTC. "Today" is the clock's instant as a
  Norwegian local date.
- **Identifiers** are opaque strings with a per-entity prefix, `cus_…`.
- **Revisions** are integers starting at 1; every accepted update of a
  record increments its revision. A tool that takes `revision` refuses a
  stale one with `conflict`.
- **Decimals** (the `decimal` field type) are exact: three fractional
  digits, up to 10¹². Every store reads back exactly what was written
  (123456.789 and 10¹² round-trip). A value beyond 10¹² is `invalid_input`.
- **Entity names** in `registry_describe` are singular: `customer`,
  `order`, `workflow`.

### 2.2 Norwegian time

Defined without a time-zone database. CET is +01:00, CEST +02:00. Summer
time runs from the last Sunday of March 01:00 UTC to the last Sunday of
October 01:00 UTC (exclusive).

- `to_utc(date, time)` computes both candidates: exactly one valid gives
  that instant; both valid is *ambiguous*; neither is *non-existent*.
- A whole-day interval is `[local midnight of the start date, local
  midnight of the day after the end date)`. A timed interval is
  `[to_utc(start), to_utc(end))`, one continuous span. Intervals are
  half-open: touching boundaries do not overlap.
- Pinned examples: 2026-01-15 09:00 → 08:00Z; 2026-07-15 09:00 → 07:00Z;
  2026-03-29 02:30 does not exist; 2026-03-29 01:59 → 00:59Z and 03:00 →
  01:00Z; 2026-10-25 02:30 is ambiguous; 2026-10-25 03:00 → 02:00Z;
  2026-03-29 has 23 hours and 2026-10-25 has 25.

`summer-time-p` in `src/core/util.lisp` implements this. Schedules use the
same rule (`jobs.md`).

### 2.3 The clock

All server time comes from one clock. In normal mode it is the real clock.
`--test-clock` makes it a virtual clock that `clock_get` reads and
`clock_set` moves (§3.10):

- It is stored, so it survives a restart. It starts at
  `2026-03-01T09:00:00Z` only on a fresh database.
- Setting it to its current value or backwards is allowed and runs nothing.
- A date-based workflow timer is due at `09:00:00Z` on its date. An
  hour-based timer is relative to the clock when it is scheduled.

### 2.4 Lists

List tools take `limit`, default 20, at most 100, and answer
`{"items", "returned", "has_more"}`, `has_more` true when items exist
beyond `limit`. `query` is a case-insensitive substring match on the fields
the tool names (a customer's name and email, a product's name).

### 2.5 Language

Identifiers are English. Labels, descriptions, titles and messages are
Norwegian, with `æ`, `ø` and `å` preserved. Status values are Norwegian
words and part of the API (`utkast`, `bekreftet`, `fullført`).

### 2.6 Manual order

Records a person puts in order, such as the cards of a board's column
(`ui.md` §6.1), carry a rank key: a string, stored in a `string` field
of the record, that the records are sorted by. Moving one record changes
only its own key.

- `(rank-between LOW HIGH)` returns a new key that sorts after the key
  LOW and before the key HIGH. LOW `nil` means there is nothing above
  (the top), HIGH `nil` nothing below (the end); both `nil` gives the
  first key, `"a0"`. It is a pure function: the same arguments give the
  same key, and the caller reads the neighbours' keys in its own
  transaction and stores the result.
- Keys compare by code point, the order every store sorts text in
  (`store.md` §2, item 6): `:order-by '(("rank" :asc))` with `select`, or
  `ORDER BY rank` in a `define-query`.
- **Every record in an ordered set has a key.** `nil` is only an
  argument, for no neighbour; a stored NULL or `""` is not a key. Records
  that have none yet, such as those that existed before the field was
  added, are given keys in their current order, each
  `(rank-between PREVIOUS nil)` with PREVIOUS the key just given (`nil`
  for the first), before the set is ordered by hand.

**The format.** Clients store these keys, so the format is fixed: every
later version of Tun reads the keys stored before it and sorts them the
same. It is fractional indexing in base 62, after rocicorp's
`fractional-indexing`:

- The digits are `0-9A-Za-z`, 62 of them, in code-point order.
- A key is a *whole part* followed by a *fraction*. The whole part's
  first character is a letter that gives its length, itself included:
  `a` gives 2 and each next letter one more, up to `z`, 27; `Z` gives 2
  and each earlier letter one more, down to `A`, 27. The rest of the
  whole part is digits. Whole parts starting with `a`…`z` are the
  integers from zero upwards (`a0`, `a1`, …, `az`, `b00`, …), those
  starting with `Z`…`A` the integers below zero (`Zz` is the one just
  below `a0`).
- The fraction is zero or more digits and does not end in `0`.
- A string is a key when it is not empty, has only digits, starts with
  a letter, is at least as long as its whole part, has a fraction that
  does not end in `0`, and is not exactly the smallest whole part, `A`
  followed by 26 `0`s. Any other string, `""` among them, given as LOW
  or HIGH is a `type-error`. LOW not before HIGH signals
  `rank-order-error`, whose readers `rank-order-error-low` and
  `rank-order-error-high` give the two keys. Both arguments are checked
  for being keys first, so a call with a non-key is a `type-error` even
  when the two are also out of order.
- **At the end** (HIGH `nil`), the new key is the whole part after
  LOW's, with no fraction. When LOW's whole part is the largest (`z` and
  26 `z`s), it is instead LOW's whole part with a fraction after LOW's.
- **At the top** (LOW `nil`):
  - when HIGH's whole part is the smallest (`A` and 26 `0`s), the new
    key is that whole part with a fraction before HIGH's (HIGH then
    always has a fraction, since the smallest whole part alone is not a
    key);
  - otherwise, when HIGH has a fraction, the new key is HIGH's whole
    part alone;
  - otherwise it is the whole part before HIGH's, with no fraction.
- **Between two keys** with the same whole part, the new key is that
  whole part with a fraction between theirs. With different whole
  parts, it is the whole part after LOW's when that sorts before HIGH,
  else LOW's whole part with a fraction after LOW's.
- **A fraction between** a fraction A (possibly empty) and a fraction B,
  or nothing for no upper bound, is made digit by digit. The digits the
  two share at the start, A read with `0` where it has run out, are
  kept. Then, with DA the value of A's next digit (0 when A has run out)
  and DB that of B's (62 when there is no B):
  - when DB − DA > 1, the fraction ends with the digit ⌊(DA + DB + 1) /
    2⌋, the one halfway between, a half rounded up;
  - else, when what is left of B is longer than one digit, it ends with
    B's next digit;
  - else, the digit DA is kept, and the fraction goes on with the
    fraction between the rest of A and no upper bound.
  So between `a0` and `a1` comes `a0V`, then between `a0V` and `a1`
  `a0l`.

**Growth.** A key added at the top or at the end steps the whole part,
which gets a character longer only each time the keys added there grow
about 62-fold: ten thousand keys added one after another at the end, or
at the top, are at most four characters each. Keys added one after
another directly after the same key (each between it and the key added
last) take about one more character per six keys, as the halving digits
run V, G, 8, 4, 2, 1; keys added directly before the same key take one
more per five (V, l, t, x, z). So a thousand of them are at most 210
characters (169 and 202 from `a0` and `a1`), within a `string` field's
default 1000.

`tests/rank-tests.lisp` shows each of these.

## 3. MCP contract

### 3.1 Transport

`POST /mcp` with a JSON-RPC 2.0 body. The methods are `initialize`,
`notifications/initialized` (a notification: 202 or 200 with no body),
`tools/list` and `tools/call`. A server that issues `Mcp-Session-Id` on
`initialize` also accepts requests without one. A plain call answers with
JSON; a waiting call may answer with a stream (`waiting.md`). Other systems
call one tool at a time with `POST /api/TOOL` (`api.md`).

### 3.2 Actors and roles

Every call runs as an actor, `role:name`, with role `admin`, `employee` or
`viewer`. Internal work runs as `system:workflow`, `system:job` or
`system:inbound`; a customer on a public page as `customer:ID`. The actor is
decided per request, never at start. A deployed server takes it from an
access token or a session (`auth.md`); with `--claimed-identity`, for tests,
previews and local development, it takes `X-Tun-Actor: role:name` from the
request. A request without a valid actor gets a JSON-RPC error `-32000`
before its body is used.

### 3.3 Policy

Each operation declares its policy, the least role that may call it:
`viewer` (reads), `employee` (the default for writes) or `admin`. `admin`
may call everything. Policy is enforced in the operation, not the transport,
so a direct call, a workflow and the UI are refused alike. It runs before
any lookup: a refused actor gets `forbidden` even for an unknown id.
Record policies narrow which records a role reaches (`store.md` §6).

### 3.4 Tools and their schemas

Every tool is an operation and every operation is a tool, under the same
name, matching `^[a-z][a-z0-9_]*$`. `tools/list` is a projection of the
registry: `name`, a Norwegian `title`, `description`, `inputSchema` (JSON
Schema with `required`) and `annotations` with `readOnlyHint` and
`destructiveHint`. Mutating tools list `request_key` in their properties and
have `readOnlyHint: false`; confirm tools also list `confirmation_token`.
Platform tools have `"entity": null`.

### 3.5 Results and error codes

`tools/call` answers
`{"content":[{"type":"text","text":"<JSON object>"}],"isError":false}`, and
the result object carries `"_meta": {"request_id"}` (§8.1). An error has
`isError: true` and the text
`{"error":{"code":"<code>","message":"<Norwegian text>"}}`, with `fields`
for field errors:

| Code | When |
|---|---|
| `forbidden` | policy refuses the actor |
| `invalid_input` | the input breaks its schema or a rule; nothing is stored |
| `not_found` | an unknown id |
| `conflict` | a stale revision, a duplicate, a state that forbids the change |
| `invalid_transition` | a status machine refuses the step |
| `unavailable` | capacity is exceeded |
| `insufficient_stock` | a ledger would go negative |
| `confirmation_invalid` | a token that is wrong, expired, used, or bound to another actor or input (§3.6) |
| `idempotency_conflict` | the same `request_key` with other input (§3.7) |
| `deadline_exceeded` | the operation ran past its deadline (§7.1) |
| `read_only` | `eval` tried to write (§8.3) |

A well-formed JSON-RPC error answering a `tools/call`, such as `-32603`
from a handler that crashed, is a failed call, not a protocol failure.

### 3.6 Confirmation

An operation marked *confirm*, called without `confirmation_token`, changes
nothing and answers normally with
`{"confirmation_required": true, "confirmation_token", "expires_at",
"summary"}`. The token:

- is high-entropy, single-use, stored as a hash, and expires 10 minutes of
  server time after it was issued;
- is bound to the actor, the tool and the input minus `confirmation_token`
  and `request_key`;
- is checked before the operation's own state checks: a reused token, or one
  presented for another target, is `confirmation_invalid`, never
  `invalid_transition`.

The second call, with the token, performs the operation. A rejected
presentation does not use the token up. The first call stores no idempotency
receipt. A domain error (`unavailable`, `invalid_transition`,
`invalid_input`) may surface on either call.

### 3.7 Idempotency

Every mutating tool accepts an optional `request_key`, 1 to 64 characters
(longer is `invalid_input`). The same actor, tool, key and input returns the
original result, identifiers included; the same key with other input is
`idempotency_conflict`. The key belongs to the actor: another actor with the
same key performs a new operation. Concurrent calls with one key perform one
mutation. Receipts are durable and stored only for performed mutations: an
error is not replayed, the call runs again.

### 3.8 Audit

Every mutating call writes an audit entry in the transaction of its
mutation. A call refused as `forbidden`, `confirmation_invalid` or
`idempotency_conflict` writes an entry with `outcome: "rejected"` and
changes nothing else; it names `entity_type` and `entity_id` when the input
names its target. Other refusals may or may not be audited. Work a workflow
or job does is audited with its system actor. Entries never hold tokens or
secrets, and record the credential the call used (`auth.md`).

### 3.9 registry_describe

A read for `viewer` and up, computed from the live definitions:

- `entities`: each with its `fields` (`name`, `type`, `label`, `required`,
  `source`, `module`, `computed` for a computed field) and its `rules`;
- `operations`: `name`, `entity` (or null), `kind` (`read`, `create`,
  `update`, `transition`, `workflow`), `confirm`, `idempotent`, `policy`,
  `source`, `module`;
- `workflows`, `message_templates`, `settings` (without values), `modules`
  and `extension_points`.

A client's additions appear with `"source": "client"` and no registration
step.

### 3.10 Platform tools

| Tool | Policy | Input | Output |
|---|---|---|---|
| `registry_describe` | viewer | `{}` | §3.9 |
| `clock_get` | viewer, test clock only | `{}` | `{"now"}` |
| `clock_set` | admin, test clock only | `{"now"}` | `{"now", "executed_workflows"}`; runs every due workflow in `due_at` order before it answers |
| `audit_list` | viewer | `{"entity_type"?, "entity_id"?, "limit"?}` | `{"items":[{"id","at","actor","tool","outcome","entity_type"?,"entity_id"?,"request_key"?}]}`, newest first |
| `accounting_status` | admin | `{}` | the accounting adapter and, per invoice, its external reference and the number of calls (§5.2) |
| `workflows_get` | viewer | `{"id"}` | one workflow (§4) |

The account, job, mail, error and setting tools are in their own contracts.

## 4. Workflows

### 4.1 Durability and scheduling

A workflow is a stored, timed piece of work about a subject, usually an
order: `{"id", "kind", "key", "order_id"?, "customer_id"?, "subject_id"?,
"due_at", "status", "executed_at"?, "request_id", "note"}`, with status
`planlagt`, `utført`, `avbrutt` (cancelled) or `feilet` (failed). A kind
has exactly one handler (`define-workflow`), which declares the templates it
may send.

- A workflow survives a restart and its handler runs at most once, in a
  transaction with its status change. Workflows run on jobs (`jobs.md`
  §12): due when the clock passes `due_at`; in test mode at once inside
  `clock_set`; in normal mode at the next scheduler pass, at least every
  `--tick-ms` (default 60000).
- A workflow already due when it is scheduled runs at the next pass.
  `executed_at` lies between `due_at` and the pass that ran it.
- Scheduling a kind and key that is already planned keeps the one planned.
  Cancelling a subject's planned workflows marks them `avbrutt` with a note.
- `workflows_list {order_id}` lists an order's workflows by `due_at`.

### 4.2 Runs are requests

Every run executes as a request with its own id, as `system:workflow`:
`workflows_list` and `workflows_get` show its `request_id`, and
`introspect_request` returns the run's steps (policy, the operation
`workflow:KIND`, the handler's store statements, commit or rollback)
exactly as for a tool call. A handler that calls an operation does so
through the guarded path, audited as `system:workflow`.

### 4.3 Failure and notes

A handler that signals any condition is rolled back, and its workflow is
marked `feilet` with the condition's text as its `note` and the run's
`request_id`; the failure is recorded as an error (`errors.md`). It never
affects another workflow or request (§7.4). A handler that decides there is
nothing to do completes normally and says why in the note (`ikke nødvendig:
…`), and so does a handler that could not do all of its work, such as one
that found no recipient: what it did not do is not marked done, so the
next run tries again.

### 4.4 Long runs make progress

A kind whose work can grow with the data runs in transactions of its own:
each unit of work (one order, say) commits alone under its own deadline, and
a deadline reschedules what is left for the next pass instead of rolling
back what was done. One such run never blocks the others.

## 5. Ports, messages, settings and links

### 5.1 Notify, and a tenant without messaging

Modules ask for a message about an order through `notify`; the messaging
module, when it is enabled, registers the adapter that renders and sends
(its contract is `modules/messaging/README.md`). On a tenant without the
messaging module a notification sends nothing and every other effect of the
operation happens: sending a quote records the quote and moves the order on
without sending mail.

### 5.2 The accounting port

The accounting system sits behind a port, `create_invoice(intent) →
external_ref`, idempotent on the intent's id, with `lookup(intent_id)`.
Only a fake adapter exists; it records each call and takes
`--fake-accounting-latency-ms` (or `FAKE_ACCOUNTING_LATENCY_MS`, default 0).
The port and the adapter are replaceable apart; a real adapter keeps its
credentials outside the application. A call through the port follows §7.3.

### 5.3 Settings

Modules and the client declare typed settings (`define-setting`): a key, a
type (`string`, `email`, `url`, `int`, `bool`, `actor`, `secret`), a
default, a description. Values are data in the store, audited, and read when
used, with no restart; a setting may instead be read from the environment
(`:env`, `outbound.md`). `settings_list` (admin) lists every setting with
secrets as `"***"`; `settings_get` (employee) refuses a secret with
`forbidden`; `settings_set` (admin) checks the value against the type and
answers `not_found` for an undeclared key. Core declares `lenker.base_url`
(absolute links in messages), `lenker.hemmelighet` (the secret behind
links, generated at first start) and `push.hemmelighet` (the secret Tun's
key for push notifications is derived from, `push.md` §6.3, generated
the same way).

### 5.4 Link tokens

A link a customer follows from a message (an offer, feedback, unsubscribe)
carries a token made from its purpose and its subject's id: the first
twenty base32 characters of an HMAC-SHA256 over `PURPOSE:ID` with
`lenker.hemmelighet` (`link-token`). A token made for one purpose does not
match another, and rotating the secret invalidates every link issued with
it. A public page
resolves the token, then acts as `customer:ID` through ordinary operations.

## 6. Tenants, pins, upgrade and rollback

### 6.1 Core and modules as pinned packages

Core is a Nix package, and each module is a flake of its own. A client is
its own repository and flake (`tun new`, `cli.md`) that pins core and each
module it enables by git revision, in its `flake.lock`, and builds only from
those pins, never from a working tree. Each module declares the core range
it builds against; a build or a load outside it is refused, naming the
range. Ranges between modules are optional (`tun-platform.md` §2, §4).

### 6.2 More than one client on one core

Core is client-agnostic: two clients with different fields, rules, seams,
workflows and screens build from the same core revision and modules, and
neither sees the other's additions in its registry. Tun's own suite checks
this with the test client (`tests/client/`), and a client may carry more
than one manifest (a default one and a minimal one, say), each enabling a
different set of modules.

### 6.3 Upgrade on the same database

Moving one pin forward runs on the existing database. Migrations are
additive (new tables, nullable columns, constant defaults), namespaced per
module and run at start in dependency order (`tun-platform.md` §2.6). The
data written before the move is read the same way after it.

### 6.4 The rollback preflight

Additive migrations let an older core start on a newer database, but not
read everything in it. Before a tenant moves back to an older core or
module, the newer server checks the database against the older code's
vocabulary:

```
SERVER --rollback-preflight OLDER-REGISTRY.json --db DATABASE
```

`OLDER-REGISTRY.json` is the older deployment's `registry_describe`, taken
from it on an empty database. The preflight reads every stored record and
reports, counted and named by kind:

- a value of an enum field outside the older vocabulary (a status, a price
  mode, a movement kind it lacks): it cannot decode it;
- an enum field the older code does not have, set to anything but its
  default;
- a field the older code does not know whose value its next write would
  drop, and documents of kinds it does not have at all (each module's
  README names its own: plans, reviews, tasks, line choices …).

It exits 0 when the older code can take the database, 3 when not, and
changes nothing either way. A finding the older code would only lose
without misreading, such as an optional text field, is reported, not
refused. There are no down-migrations.

## 7. Runtime properties

A tenant is one process. These hold for every request, workflow run and job.

### 7.1 Deadlines

Every operation and workflow run runs under `--deadline-ms` (default
10000). On expiry it is cancelled, its transaction rolled back, the caller
gets `deadline_exceeded`, and an audit entry with outcome `rejected` is
written. Checks are cooperative at store access and in loops, and a watchdog
interrupts code that never checks, except inside a foreign call. Other
requests are unaffected.

### 7.2 Backpressure

In-flight work is bounded by `--max-inflight` (default 64). Beyond it the
server answers at once with HTTP 503, `Retry-After: 1` and the error
`overbelastet` (a JSON-RPC error `-32001` on `/mcp`, the API's error
document on `/api/`). Nothing queues without bound, and no request waits
more than 30 seconds for an answer.

### 7.3 External calls outside write transactions

A call to another system (a port, `http-json-post`) happens outside any
write transaction. The operation commits a durable intent first, calls, and
records the outcome in a new transaction. A stalled system delays only its
own request. At start an intent with no recorded outcome is reconciled
through the port's `lookup` before any retry, so the external system sees
one create per intent.

### 7.4 Fault isolation

A condition in a request, a client hook or a workflow handler never ends the
process or affects another request. A failing workflow is marked `feilet`
(§4.3). Control-stack and heap exhaustion inside a request fail that request
alone.

### 7.5 Bounded inputs

Before authentication, the server caps the request line and headers (32 KiB
and 100 lines), the body (2 MiB), JSON depth (64), string length (1 MiB) and
numeric literal length (64 characters). Each cap answers with an error at
once, not after reading on. Requests that carry files, from an
authenticated caller, have larger bounds, stated in `files.md` §4.3.

**A body's length.** A `Content-Length` that is not plain digits (a sign,
spaces, a second value, which Hunchentoot joins to the first with a comma)
is answered 400 before the body is read. A chunked body, and a `POST`
without `Content-Length`, are answered 411.

**Anonymous callers send at most 256 KiB.** A body over 256 KiB from a
caller Tun does not know before reading it is answered 413 and its
connection ended, unread, on every path, public pages and `/login`
included: a known caller has a token or, with claimed identity, an
`X-Tun-Actor` on `/mcp` and `/api`, the right secret on a JSON port with
`:authorize`, and a signed-in person's session on a page. A page's post is
told «Uten å være logget inn kan du sende høyst 256 KB.»

**Large bodies take a place.** Every body over 256 KiB, of any kind (JSON
to `/mcp` and `/api`, a plain form, a multipart post, anything else), takes
one of four places before it is read, and holds it until its answer is
sent. With the four taken it
is answered 503 with `Retry-After: 1` at once, unread (as the error
document on `/api`, a JSON-RPC error `-32001` on `/mcp`, a page for a
page's multipart post). So at most 4 bodies over 256 KiB and, with
`--max-inflight`, 64 requests in all are being answered at once.

**Deadlines.** A request line and its headers must arrive within 30
seconds of their first byte. A body is read before anything else is done
with the request (a body declared to a path that answers without one, such
as `/health` or the redirect to HTTPS, is dropped for at most 2 seconds and
its connection ended), and must arrive within 30 seconds when it is at most
256 KiB, and within 120 seconds when it has a place. One that comes too
slowly, or stops coming (the connection's read timeout, 20 seconds
without a byte), is answered 408 and its connection ended, and the
request's slot and place are freed: a sender that trickles holds one for
a bounded time.

**JSON values.** A request's JSON holds at most 10 000 values, counted as
its brackets, commas and colons outside strings, in the same pass that
checks number lengths, before anything is parsed. More is answered 413
with «Forespørselen har for mange JSON-verdier (høyst 10 000).», on `/mcp`
as the JSON-RPC error `-32600`.

**Numbers.** The same pass holds a caller's numbers (what
`parse-request-json` reads: `/mcp`, `/api`, JSON ports and a form's JSON
fields) to what Tun takes as input, before the parser sees them:

| A number with | Is answered |
|---|---|
| more than 19 significant digits (an integer of 64 bits has 19, a double needs 17) | «Et tall kan ha høyst 19 sifre.» |
| an exponent of more than 4 digits, a magnitude over 1.7976931348623157e308, or one under 2.2250738585072014e-308 other than 0 (a subnormal double) | «Et tall må være 0, eller mellom 2.2250738585072014e-308 og 1.7976931348623157e308, med eller uten minus.» |

Each is answered 400 `invalid_json`, on `/mcp` the JSON-RPC error
`-32700`, at once: past these the parser works in big integers, in time
that grows with the square of the exponent (`1e99999999` took minutes) or
several kilobytes a number. A caller's number is at most 64 characters.
JSON Tun wrote itself (a json field, a receipt) and answers from other
systems are never held to these: only an exponent of more than 4 digits,
which Tun never writes, and a literal over 1 000 characters are refused
there. Tun writes a number that is not a whole one of modest size in its
shortest form (`1.5e300`), never digit by digit.

A posted integer or decimal field of a generated form longer than 40
characters is passed on as text, never parsed, and refused as invalid
input: «er for langt for et tall: høyst 40 tegn».

**JSON ports.** A port of `register-json-endpoint` (such as the inbox's
`/inbound/mail`) that names an `:authorize` function checks the
`X-Tun-Inbound-Secret` header with it before the body is parsed; a wrong
secret is answered 403 and the body never parsed. A port answers JSON of
more than 10 000 values 413, and a number out of range 400. JSON is parsed from the body's octets as
they came, never from a copy of them as text, and a string of ASCII
characters only is kept one octet a character.

**Plain forms.** A plain form's post (`application/x-www-form-urlencoded`),
to any page and from anyone, is read by Tun from the bounded body, never by
Hunchentoot: at most 1 000 fields, counted before any is decoded, each
name at most 1 KiB and value at most 1 MiB. Each name and value is decoded
once, straight from the body's octets into one string made at its length:
`+` a space, `%XX` an octet, the octets UTF-8 with each invalid sequence
one U+FFFD. More is answered 413 with a page: «Skjemaet har for mange felt
(høyst 1 000).» or «Et felt i skjemaet er for langt.».

**Request records.** A request's record (§8.1) keeps what a caller sent
only as text it has clipped, each field to its bound, in UTF-8 octets:

| Field | At most |
|---|---|
| the tool, the JSON-RPC method, or the page's method and path | 256 octets |
| the actor, the credential, the error's code and type | 256 octets each |
| the error's message | 4 096 octets |
| the backtrace's frame names | 8 192 octets |
| the input | 48 KiB |
| all of it | 64 KiB |

A field cut short ends in `…`, cut at a character's boundary. The record's
slots are typed to these bounds, and every writer clips what it is given,
so no field can hold more. The input is only what the operation declares
(its parameters, and a draft's fields), never a key it does not know,
written as JSON straight into its octets; a value that does not fit in
what is left is kept as «[utelatt: posten holder høyst 48 KB av input]»,
and is not written out first. Without an operation a record keeps no
input. `introspect_request` parses the input when asked. An error repeats
at most 100 characters of a name the caller sent («Ukjent verktøy: …»,
«Ukjent metode: …» among them), and lists at most 20 unknown names,
counting the rest. A step of the trace keeps a name from the definitions
and, from a call to another system, at most 300 characters of its detail.

**Connections.** Every answer given before a body is read, the 400, 408,
411, 413 and 503 among them, ends its connection (`files.md` §4.3), after
reading and dropping the rest of the body the client declared, for at most
2 seconds, so a client still sending it can read the answer.

**Per client address.** The server runs at most 1 024 connection
threads, and a connection holds one while its headers come, for up to 30
seconds, so a caller that keeps connecting could otherwise hold them all.
The server counts what each client address holds and refuses the rest at
once:

- **A connection** from any peer but the trusted proxy (`deploy.md` §1,
  `--trusted-proxy`) counts against the peer's address from when it is
  accepted until it ends, the time it is kept alive between requests
  included. With 64 open from one address, the next is answered
  `503 Service Unavailable` with `Retry-After: 1` and `Connection: close`
  at once, without reading its request, and closed. What it has already
  sent by then, up to 32 KiB (the headers' budget), is read and dropped
  first, without waiting for more, so that closing does not reset the
  connection and the caller can read the 503; a refused connection never
  holds its thread waiting. Other addresses are served as before.
- **A request through the trusted proxy** counts against the client the
  proxy names: the last address in `X-Forwarded-For`, the one the proxy
  wrote. It counts from when its headers are read until its answer is
  sent, so an upload counts while its body comes and a download while
  its file is sent; the proxy's connections themselves are not counted.
  With 16 being answered for one client, the next is answered as an
  overloaded server answers (§7.2), at once, its body unread and its
  connection ended. A request from the proxy without `X-Forwarded-For`,
  or whose last entry is not an IP address, counts against the proxy's
  own address.
- **A call that waits** (`waiting.md` §1) through the proxy leaves its
  client's count while it waits, as it leaves `--max-inflight`, and
  comes back to it, over the bound or not, when the wait ends: agents or
  an office behind one address may hold many waits. The work before and
  after the wait counts. A call that waits on a direct connection keeps
  its connection, which counts as any other.
- **Waits have a bound of their own per client:** at most 32 of the 256
  calls that may wait at once in a process (`waiting.md` §1) wait for one
  client, the address it is counted under above (the one the proxy names
  through the trusted proxy, the peer's otherwise). One more for that
  client is refused before it waits, as a wait past the process's bound
  is, while other clients' waits are taken.
- `X-Forwarded-For` is read from the trusted proxy only. From any other
  peer, and on a server without `--trusted-proxy`, it is ignored, so a
  caller cannot choose the address it is counted under.
- An IPv6 address counts by its first 64 bits, the smallest network
  commonly given to one subscriber or site; one who holds a larger
  network (a /56 or a /48) has that many /64s, so this bounds one
  network, not one holder. An IPv4 address written as IPv6
  (`::ffff:203.0.113.7`) counts as that IPv4 address.

Through the proxy a request is work in progress, as the proxy itself
keeps the connections a browser holds open; its bound, a quarter of the
64 requests answered at once (§7.2), keeps one client from taking the
server's capacity. Most requests are answered in milliseconds, so 16 at
once is what dozens of people behind one office address reach only
with long transfers, and of those the server takes at most four bodies
over 256 KiB at once from everyone together (above). A connection counted directly
may be idle between requests, and on a developer's machine the browser,
the tests, the checks and a load suite share one address, so its bound
is higher.

**The memory budget.** With every limit reached at once, the server stays
within its default heap of 2 GiB (`--dynamic-space-size 2048`). Each line
is measured by the test that names it, in `tests/hostile-tests.lisp`,
against a server in a process of its own with that heap. What a request
costs is everything the server allocates while answering it alone, at its
costliest (a hostile caller's body at the bound); what it holds at once is
less.

| Line | At once | Each, measured | Each, allowed | Total allowed | Test |
|---|---|---|---|---|---|
| The image and its data at rest | 1 | 102 MiB live | 128 MiB | 128 MiB | `hostile-callers-at-every-limit-at-once-keep-the-server-up` |
| Requests with a body up to 256 KiB, and without one | 64 | 7.5 MiB (the first fault of its kind whose message is 256 KiB; 4.6 MiB after); 3.9 MiB (JSON at the value bound); 1.5 MiB (9 900 numbers at a double's edge) | 8 MiB | 512 MiB | `each-kind-of-request-costs-at-most-its-line-of-the-budget` |
| Requests with a body over 256 KiB, in a place | 4 | JSON, 2 MiB: 14.3 MiB, of 9 990 numbers of 64 characters: 1.9 MiB; a form, 2 MiB: 10.1 MiB; files as JSON, 16 MiB: 57.3 MiB; a multipart post, 26 MiB: 121 MiB | 16, 12, 72, 169 MiB | 676 MiB | `each-kind-of-request-costs-at-most-its-line-of-the-budget` |
| Files being checked | in the request above | one file at a time, its output one buffer of its size | — | — | the line above |
| A file being sent | in the 64 | 1 MiB a part | — | — | `thirty-two-fetches-of-a-large-file-fit-the-default-heap` |
| The request history | 1 000 records | 54 KiB of text, 53.6 MiB for a thousand | 64 KiB of text | 96 MiB | `hostile-text-in-every-record-field-is-kept-clipped` |
| Connections reading their headers | 1 024 threads, from 16 addresses or more | 141 MiB for a thousand with 32 KiB of headers each, from 20 addresses | 192 KiB | 192 MiB | `a-thousand-connections-in-their-headers-fit-the-budget` |
| **Total** | | | | **1 604 MiB of 2 048** | |

With every limit reached at once, 60 small requests and 8 large ones three
times over, from anonymous callers, viewers and employees on every path,
the heap measured at its highest, garbage included, was 264 MiB; the test
holds it under the total, and the live heap after them at what it was.

### 7.6 Scheduler and debug tools

`--tick-ms` sets the normal-mode scheduler interval (default 60000).
`--debug-tools` adds these platform tools, present only with the flag;
their policy runs before the work, so a viewer calling `debug_burn` gets
`forbidden` without burning:

| Tool | Policy | Input | Does |
|---|---|---|---|
| `debug_burn` | employee | `{"ms"}` | spins the CPU inside the operation for `ms` |
| `debug_sleep` | employee | `{"ms"}` | blocks inside the operation for `ms` |
| `debug_schedule` | admin | `{"due_in_ms"}` | schedules a `debug_ping` workflow that only records; `{"id", "due_at"}` |

### 7.7 Serving

The server exits non-zero when it cannot bind its port, and never logs that
it listens before the socket is bound. `/health` answers once the
application is open.

### 7.8 Measured pressure

These properties are measured against a running tenant under load, with the
real clock, `--debug-tools --tick-ms 500 --deadline-ms 10000 --max-inflight
64`, three runs each, judged on the median. The suite reaches the server
directly, without a trusted proxy, so its connections are counted by
address (§7.5): P6's 256 workers come from eight loopback addresses
(`127.0.0.2` to `127.0.0.9`, 32 each), so they meet `--max-inflight` and
not the bound of 64 per address. The load suite itself belongs
with a client, outside this repository; `tun loop verify` runs it when
`TUN_PRESSURE` names it (`loop.md` §6).

| Scenario | Load | Passes when |
|---|---|---|
| P1 Storm | 32 workers for 20 s, 60 % reads, 40 % writes including two-step confirmations | no error but expected domain errors; the process lives |
| P2 Timer fidelity | 20 `debug_schedule` calls 1–5 s ahead during P1 | each `debug_ping` runs once, at most 2 s late |
| P3 Heavy requests | 4 workers `debug_burn 2000` beside 16 readers | read p99 ≤ 500 ms |
| P4 Deadline | 4 × `debug_burn 60000` and 4 × `debug_sleep 60000` beside 16 readers | each ends `deadline_exceeded` within 11 s, audited; read p99 ≤ 500 ms; a viewer's `debug_burn` is `forbidden` in < 100 ms |
| P5 Stalled accounting | the fake port answers after 5 s; invoices sent beside other writes | other writes p99 ≤ 1000 ms; each invoice sent with one port call |
| P6 Overload | 256 workers from 8 addresses for 10 s, then 50 reads | nothing slower than 30 s; no 5xx but 503; the 50 reads each < 100 ms |
| P7 Kill under load | SIGKILL during a storm, restart on the same database | ledgers consistent, no duplicate invoice, no workflow run twice; reads served within 5 s |

## 8. Introspection

A running tenant explains itself to an admin, without its source.

### 8.1 Request identity

Every HTTP response carries `X-Tun-Request-Id`, and every `tools/call`
result carries `"_meta": {"request_id"}`: the handle for
`introspect_request`. A call from outside any request (a workflow run, a
job, a Lisp call) starts a request record of its own. The last 1000 requests
(`--request-history N`) are kept in memory, every `/mcp` and `/api/` call
included, refused and failed ones too; a fault is also kept in the store
(`errors.md`).

### 8.2 Tools

Reads with policy `admin`, entity null and source `core`, always present.
Inputs are shown as given minus `confirmation_token` and `request_key`,
with `"***"` for a secret: the value of `settings_set` for a secret
setting, and any parameter declared `:secret t` or reusing a secret field,
such as `push_subscribe`'s `auth`.

| Tool | Input | Output |
|---|---|---|
| `introspect_record` | `{"entity", "id"}` | every stored field (client fields included), computed fields, `field_sources`, related records (for an order: invoices, bookings, workflows, messages) and its last 20 audit entries |
| `introspect_request` | `{"request_id"}` | actor, tool, input, `outcome` (`ok`, `rejected`, `error`), the error, the policy decision, and every step in order (`policy`, `decode`, `idempotency`, `confirmation`, `rule`, `hook`, `operation`, `store`, `external`, `audit`, `commit`, with `source`, `order`, start and duration), store statements, write-lock wait, total time, and a backtrace when it failed |
| `introspect_recent` | `{"kind": "errors" \| "slow" \| "rejected" \| "all", "since"?, "limit"?}` | requests, newest first by completion; `slow` is ≥ 1000 ms, else the slowest kept |
| `introspect_inflight` | `{}` | running requests with `elapsed_ms` and `state` (`running`, `waiting_write_lock`, `external_call`, `waiting_admission`) |
| `introspect_workflows` | `{"status"?, "due_before"?, "limit"?}` | workflows with `attempts` and `note` (§4.3) |
| `explain` | `{"tool", "input"}` | a dry run in a read transaction (no mutation, receipt or token): the policy decision, input errors, whether it needs confirmation, the rules, the hooks in execution order, and what it `would` produce (for order writes the amounts, requirements and bookings, `[]` until confirmation; for a confirmation the availability per line) |
| `introspect_schema` | `{}` | tables with columns, and the applied migrations |
| `introspect_runtime` | `{}` | build revisions (core, client, each module), uptime, memory, workers, in-flight and limits, write queue depth, the deadline, the clock's mode and time, the modules (§1.3), and `live_patches`: functions and methods changed in the image after start |
| `introspect_extensions` | `{}` | every extension with `kind`, `target`, `name`, `order`, `source`, `module` and `source_location` as `file:line` (a client's as `clients/SYSTEM/FILE:LINE`, a module's as `modules/NAME/FILE:LINE`) |

### 8.3 eval and the REPL

With `--allow-eval`, `eval {"code"}` evaluates Lisp in the running process
under the operation's deadline, inside a read transaction: a store write
fails with `read_only`. Its output is captured and capped at 64 KiB, and the
call is audited. With `--debug-tools --repl-port N` the image serves a
Swank REPL on localhost, with full access and no authentication, for
diagnosis on a developer's machine only. `bin/drift` compares the loaded
code with a checkout and fails on a live patch (`docs/architecture.md`).

### 8.4 Outcome, retention and field sources

- `outcome` is `rejected` only for `forbidden`, `confirmation_invalid` and
  `idempotency_conflict`. Every other error, `invalid_input` and
  `deadline_exceeded` included, is `error`, with a backtrace.
- `field_sources` covers an entity's own top-level fields; the fields of an
  embedded entity, such as an order line, appear under that entity.
- UI and `/health` requests need not be kept.
- A balance or other stored value is read from the store, never from a
  cache that an outside change to the store would leave stale.
