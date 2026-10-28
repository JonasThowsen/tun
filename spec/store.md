# Store adapters

Status: v1, 2026-10-12; queries (§5) and Postgres as the one store,
2026-10-14; record policies (§6), 2026-10-14. The kernel reaches persistence only through the store port
(`src/core/store.lisp`). This document is the contract every adapter
meets. `core.md` §2 and §7 say what the store must keep (exact decimals,
durability across a kill); this document is the rest.

## 1. Adapters

| Adapter | For | Selected by |
|---|---|---|
| memory | tests | no `--db` in an in-process test application |
| SQLite | a tenant whose database is one file | `--db PATH` |
| Postgres | a tenant whose database is a Postgres database | `--db postgresql://…` or `postgres://…` |

**Postgres is Tun's store.** Decided 2026-10-14: one dialect, so queries
can be written in SQL (§5) and features use what Postgres offers. The
memory and SQLite adapters stay only until the kernel suite runs on
Postgres; they do not run queries, and no new feature is built for them.

When `--db` is absent, the server reads the `DATABASE_URL` environment
variable instead, so a password stays off the command line. When neither
is given, it exits 2 and says so.

A Postgres URL has the form
`postgresql://[user[:password]@][host][:port]/database[?host=DIR]`.
A `host` query parameter, or a host that starts with `/`, names the
directory of a Unix socket. Percent-escapes are decoded. Any other query
parameter is refused at start.

## 2. The same behaviour on every adapter

1. **One writer at a time per database.** Write transactions are
   serialised across every process using the database, not only within
   one process. SQLite gets this from `BEGIN IMMEDIATE`. Postgres takes a
   transaction-scoped advisory lock as the first statement of every write
   transaction, at isolation level READ COMMITTED, so the transaction sees
   everything committed before it got the lock. `store-lock-row` needs no
   further lock on either.
2. **Waiting has a limit.** A write transaction waits for the lock no longer
   than its deadline, then fails with `deadline_exceeded`.
3. **Read transactions** see one consistent snapshot, never wait for a
   writer, and refuse writes. Postgres: REPEATABLE READ, READ ONLY.
4. **Nested write transactions** are savepoints.
5. **Durable writes.** A write transaction returns only after its commit is
   durable.
6. **Ordering.** `ORDER BY` compares text by code point, puts NULLs first
   when ascending and last when descending, and breaks ties by insertion
   order (`seq`). Postgres text columns use the `"C"` collation for this.
7. **Exact values.** Every field type round-trips exactly, through the
   representation the kernel's types give for the store: integers (64 bit),
   exact decimals, timestamps as RFC 3339 text, booleans as 0 and 1, JSON
   as text.
8. **Unique values.** A unique violation is the `conflict` error.
9. **Migrations** are additive and derived from the entity classes, with the
   same migration ids in `schema_history` (tun-platform.md §2.6). Postgres
   column types are `BIGINT` for integers and booleans, `NUMERIC` for
   decimals and `TEXT` for the rest. `introspect_schema` reports each
   adapter's own type names.
10. **A newer major's database is refused.** A process from core 1.23.1 on
    records once, inside its migrate transaction, that core's major
    version M has opened the database: a `schema_history` row with
    `module` `tun-core`, `migration` `core-major-M` and `statement`
    `core major M opened this database`. Before it migrates anything, in
    the same transaction, it refuses to start on a database where a
    higher major has recorded its mark: the server exits with code 2, names
    both majors on stderr and closes the connections it opened. A
    database with no mark, or only marks of its own major or lower, opens
    as before, and within one major nothing changes.
    - The module value `tun-core` has a hyphen, so no module can have it
      (module names are `[a-z][a-z0-9_]*`), and core's own migrations
      under `core` keep their numbers: `ddl-record` numbers a module's
      migrations by counting its rows.
    - The mark is not a migration, and its id is not of the
      `<module>_<nnnn>_<name>` form; `introspect_schema` lists it with the
      applied migrations.
    - What it guards: a Tun from 1.23.1 on, starting on a database a
      higher major has opened, whether in a blue/green switch, a rollback
      by pin or by mistake. What it does not: a process of a lower major
      that is already running is not stopped, and a pin back to 1.23.0 or
      earlier starts unchecked. A higher major therefore records its mark
      before, or in the same transaction as, its first change an older
      major cannot read.
    - The memory store keeps no history and is not affected.

## 3. Two processes on one Postgres database

During a blue/green switch, the old and the new process of a tenant use one
Postgres database for a short time. That is safe:

- Writers are serialised across both processes (§2.1).
- A due job is claimed inside a write transaction, so it runs once,
  whichever process gets it (`jobs.md` §7).
- **Presence.** A process can tell whether another is still running: each
  holds a lock of its own for as long as it has the store open
  (`store-claim-presence`), and another asks for it (`store-present-p`).
  On Postgres it is a session advisory lock on a connection of its own,
  in the two-key space, apart from the write lock's key, so Postgres
  releases it the moment the process dies or its connection breaks.
  SQLite and the memory store have one process, so a lock this process
  does not hold is no one's.
- Migrations are additive, so the older process keeps working on the newer
  schema. The new process migrates under the write lock.

Not shared between the two processes: public page sessions (an offer
unlocked in one must be unlocked again in the other) and the in-memory
request history behind `introspect_request`.

SQLite has one writer per file too, but a tenant on SQLite must still not
run two processes at once: the file is local to one container.

## 4. Adapter options

- `--group-commit N` and `--sqlite-synchronous full|normal` apply to SQLite
  only. With Postgres each write transaction commits on its own.
- The rollback preflight works on SQLite tenants only.

## 5. Queries

A read that needs more than one entity's rows by field (a join, a count,
a group) is written in SQL with `define-query`. Writes never are: they go
through `insert` and `save`, where rules, ownership and audit apply.

```lisp
(define-query open-orders ((customer-id :type (id customer) :required t)
                           (since :type timestamp))
    (:returns order :description "Åpne ordrer for en kunde.")
  "SELECT o.* FROM {order} o
    WHERE o.customer_id = :customer_id
      AND (:since::text IS NULL OR o.created_at >= :since)
    ORDER BY o.created_at DESC")

(define-query order-counts ()
    (:returns (:rows (customer-id :type (id customer)) (orders :type integer)))
  "SELECT customer_id, count(*) AS orders FROM {order} GROUP BY customer_id")
```

1. **The definition.** `define-query NAME (PARAMETER...) (OPTION...) SQL`
   defines a function NAME taking each parameter as a keyword argument.
   Parameters are written as operation parameters are: `(NAME :type T
   :required BOOLEAN)`, type `string` when omitted. The options are
   `:returns` (required) and `:description`. SQL is one string literal.
2. **The text.** SQL is one `SELECT`, or one `WITH ... SELECT`, in
   Postgres's dialect. In it:
   - `{ENTITY}` names an entity's table. `ENTITY` is the entity's symbol,
     read in the package of the definition, so a client names exactly the
     entities it can name in Lisp. A query never names a table directly.
   - `:NAME` is a parameter, NAME being its snake_case name
     (`customer-id` is `:customer_id`). Each declared parameter is used,
     and only declared parameters are. `::` is Postgres's cast, as usual.
   - Where Postgres cannot tell a parameter's type from its use (alone in
     `IS NULL`), the text casts it: `:since::text`.

   The definition refuses, when it is compiled: a `;` outside a string or
   comment, a `$` outside one (no positional parameters, no dollar
   quoting), a `{` not followed by a name and `}`, an unterminated string,
   quoted identifier or comment, parentheses that do not pair up, and text
   that does not start with `SELECT` or `WITH`.
3. **Values.** A parameter's value is given in Lisp, as a field of its type
   holds it (an id string, a universal time), and is sent as the store
   holds that type: a timestamp as RFC 3339 text, a boolean as 0 or 1. A
   required parameter that is NIL, or a value not of the type's Lisp type,
   is an error before anything is sent. NIL is SQL NULL, except for a
   `boolean` parameter, where it is false. Values are sent as
   statement parameters, never spliced into the text.
4. **Results.**
   - `(:returns ENTITY)`: a list of records of ENTITY. The result's columns
     are exactly `id` and the entity's stored fields, plus `seq` when
     selected (`SELECT o.*` gives this), matched by name.
   - `(:returns (:rows (NAME :type T)...))`: a list of JSON objects with
     exactly those keys, in that order, each value converted from its
     stored form to JSON as a field of type T is. The result's columns are
     exactly the snake_case names.

   Rows come in the order the SQL gives; without `ORDER BY` that order is
   unspecified.
5. **Where it runs.** A query is called inside a transaction, read or
   write, and sees that transaction's writes. It counts against the
   request's deadline, and its SQL appears in the request trace as a store
   step. Under the read-only `eval` tool, records are also filtered by
   `entity-readable-p` (the read operations' roles) as `select`'s are, and
   a `:rows` query is refused.
6. **Who may name what.** A query a client defines may not name
   an internal entity or one with a secret field (`spec/auth.md` §7):
   `session`, `access-token` and the like.
7. **Checked at start.** After migrating, a server on Postgres runs every
   defined query once, wrapped as `SELECT * FROM (SQL) AS q LIMIT 0` with
   every parameter NULL, in a read-only transaction. It refuses to start,
   naming each query and its problem, when an entity is unknown
   or not allowed, Postgres rejects the text (a renamed column, a syntax
   error, a statement that writes), or the result's columns are not what
   `:returns` says. A renamed field therefore stops the next start and the
   next `bin/test`, with the query's name, rather than one request in
   production.
8. **On the other adapters.** The memory and SQLite stores do not check
   queries at start, and calling one there is an error.

Not yet: list parameters (`= ANY(:ids)`), and Postgres's own column types
(booleans and timestamps are stored as `BIGINT` and `TEXT` while SQLite
exists).

## 6. Record policies

An operation's `:policy` says who may call it. A record policy says which
records of an entity each caller may read and write, wherever they are
read or written. It is declared once, on the entity, as an SQL condition
per role:

```lisp
(define-entity item (:id-prefix "itm" :label "Sak"
                     :record-policy
                     ((:admin t)
                      (:employee "author = :actor_name
                                  OR EXISTS (SELECT 1 FROM {question} q
                                             WHERE q.item_id = this.id
                                               AND q.asked = :actor_name)")))
  ((title :type (string :min 1 :max 200) :required t)
   (author :type (string :max 64) :input nil)))
```

1. **The definition.** `:record-policy (CLAUSE...)` in `define-entity`'s
   options. A CLAUSE is `(ROLE CONDITION)`: ROLE is `:viewer`, `:employee`
   or `:admin`, each at most once, and CONDITION is `t` (every record) or
   a string. An embedded entity has no policy. An entity without
   `:record-policy` has none: every caller an operation lets in reaches
   every record, as before.
2. **Whose records.** The policy applies to the request's actor. The
   clause of the actor's role applies, and only that one: a role without a
   clause reaches no record, so a forgotten role fails closed. The system
   actor (workflows, the kernel's own work) reaches every record. Reading
   or writing an entity with a policy without an actor is an error. Code
   that must reach records the actor cannot, such as a notification to an
   admin, binds the system actor with `with-actor`.
3. **The condition** is an SQL boolean expression over one record, written
   by the text rules of a query (§5.2), except that it is an expression,
   not a `SELECT`. The record's columns are its fields' snake_case names;
   inside a subquery, the record is `this` (`this.id`). Its parameters are
   `:actor`, the actor as the audit records it (`employee:kari`), and
   `:actor_name`, its name (`kari`), which an account keeps when its role
   changes. `{ENTITY}` names another entity's table, with that entity's own
   policy not applied: policies do not nest. Who may name what is §5.6,
   for the entity's definer. Refused when the definition is compiled: what
   §5.2 refuses, any other parameter, and a clause of another shape.
4. **Reads.** `fetch`, `select`, `select-one` and every `{ENTITY}` in a
   query see only the records the condition admits. A record outside it is
   not there: `fetch` returns NIL and `fetch!` fails `not_found`, the same
   answer as for an id that does not exist, so a caller does not learn it
   exists. Lists, counts and joins in queries hold only admitted records.
   Every surface reads through these, so the policy holds for MCP, the web
   UI, introspection and eval alike. In a query, `{ENTITY}` becomes
   `(SELECT * FROM TABLE AS this WHERE CONDITION)`, which needs Postgres 16
   or later when the query gives it no alias.
5. **Writes.** The same condition decides writes, checked by Postgres
   in the same statement:
   - `insert`: the new record must satisfy it, else `forbidden`.
   - `save`: the stored record must satisfy it, else `not_found`; and the
     record as saved must, else `forbidden`.
   - `delete-entity`: the stored record must satisfy it, else `not_found`.

   A refused write leaves nothing behind, even when the caller handles the
   error. `forbidden` is a rejection: an operation it ends is audited as
   rejected, like a call its `:policy` refuses.
6. **Checked at start.** After migrating, a server on Postgres runs each
   condition once, as `SELECT 1 FROM TABLE AS this WHERE (CONDITION)
   LIMIT 0` with NULL parameters, in a read-only transaction, and refuses
   to start, naming the entity, the role and the problem, when Postgres
   rejects it (a renamed column, a condition that is not boolean). The
   check of the queries (§5.7) gives each `{ENTITY}` with a policy the
   form of item 4.
7. **On the other adapters.** The memory and SQLite stores refuse to read
   or write an entity with a record policy.
8. **Introspection.** `registry_describe` lists an entity's policy as
   `record_policy`: `[{role, condition}]`, condition `true` or the text.

Not yet: a client adding a policy to a module's entity; a write condition
apart from the read condition; fields only some roles see.

## 7. Development and evidence

- The dev shell provides PostgreSQL. `bin/with-postgres COMMAND…` starts a
  private, throwaway server: a fresh cluster in a temporary directory,
  reachable only through a Unix socket, no TCP. It runs COMMAND with
  `DATABASE_URL` naming an empty database on it, then stops the server and
  deletes the cluster, whatever COMMAND's outcome; its exit status is
  COMMAND's.
- `bin/test` runs the store contract tests on memory, SQLite and Postgres
  (through `bin/with-postgres`), including the ledger invariant under
  concurrency, restart durability, additive migration, and two applications
  writing to one Postgres database at once.
- `tests/query-tests.lisp` covers §5 on Postgres: the text rules, both
  kinds of result, parameters and NULL, a write transaction's own rows,
  the start check refusing each kind of problem, and the call refused on
  the memory store.
- `tests/record-policy-tests.lisp` covers §6 on Postgres: each kind of
  read and write for each role, a condition with a subquery, queries,
  a refused write leaving nothing, the rejected audit entry, the start
  check, the compile-time refusals and the other stores refusing.
