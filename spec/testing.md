# Generated tests

Status: draft, 2026-11-07. A client gets tests it did not write: Tun
derives them from what the client declares (its entities, operations,
policies, pages and scenarios), so every client is checked the same way,
and a check added to Tun reaches every client with `tun update`.

## 1. The generated suite

- A client's `tests/tests.lisp` holds one form,
  `(define-generated-tests "NAME" :package "PACKAGE")`, from
  `tun.test-support`, in the client's suite. NAME is the client's system;
  PACKAGE its package. The application class is the value of
  `*APPLICATION-CLASS*` in PACKAGE.
- It defines the generated tests in the suite. Today they are:
  1. the client's package uses only `CL` and `TUN`;
  2. its sources use only Tun's public interface;
  3. its application opens on a fresh Postgres database, which runs every
     record policy and query (`store.md` §5, §6), with the modules it
     enables and no others;
  4. every text of its own has a translation into each language it offers
     besides its source language, and no entry of its catalogues is unused
     (`i18n.md` §3.7);
  5. every scenario the client defines makes its records, each on a
     fresh database (`preview.md` §3). The client's scenarios are those
     defined in its packages: PACKAGE and the package the form is in, its
     tests' package, where `tun new` puts them. Tun's and other systems'
     scenarios loaded in the same image are not the client's, and two
     packages may each define a scenario of the same name.
  6. every tool of the client withstands fuzzing (§2).
- Each generated test is named for what it checks, prefixed
  `generated-`, so a failure says which check found it.
- **Isolation.** A scenario may install handlers that answer for other
  systems for every thread, such as `*program-handler*` or
  `*http-json-handler*` (`outbound.md`). Around each generated test, and
  around each scenario the scenario test runs, Tun rebinds to NIL its own
  such variables, `*program-handler*` and `*http-json-handler*`, and those
  the client names:
  `(define-generated-tests "NAME" :package "PACKAGE" :isolate (VARIABLE...))`.
  What one scenario or test installs never reaches the next. A variable
  Tun adds of this kind joins the list in `tun.test-support`.
- **Fast.** A client's generated tests together take at most 30 seconds
  on the machine its suite runs on, so they run with every change.
- A client keeps its own tests beside the form, in the same suite or in
  other files. Removing or editing a generated test is not how a client
  skips one: a check that does not fit a client is fixed in Tun.
- `tun new` writes the form. A client made before writes it once in place
  of its copies of the checks.

## 2. Fuzzing every tool

The sixth generated test, `generated-every-tool-withstands-fuzzing`,
calls every tool of the client with inputs Tun makes up, and checks what
must hold whatever a caller sends.

- **Which tools.** Every tool of an operation the client defines. Tun's own
  tools, core's and the modules', are fuzzed in Tun's own suite, once, the
  same way, from a scenario of that suite's with a record or two of each
  kind the modules keep: a client does not fuzz them again. Left out,
  because they exist only to test or to debug: the test clock's
  `clock_get` and `clock_set`, the `debug_…` tools and `eval` (`core.md`
  §3.10, §7.6, §8.3).
- **Where.** For each tool a fresh database in memory, filled by the
  client's `default` scenario when it has one, so an id can name a record
  that exists. The scenario runs once, and each tool's database is a copy
  of the one it filled, with the values it left the variables of
  Isolation (§1) with. A client that defines a query or an entity with a
  record policy, which only Postgres runs (`store.md` §5, §6), gets its
  copies on the test Postgres server instead. The tool's calls run one
  after another on its copy. Each call goes the way `tools/call` does
  (`core.md` §3): its input written and parsed as a request's JSON,
  decoded against the tool's schema, the policy, the transaction, the
  audit, and its result written as JSON. No HTTP. (That the application
  opens on Postgres is §1's third test.)
- **Who.** `admin:fuzz`, `employee:fuzz` and `viewer:fuzz`, and each actor
  the `default` scenario names, so record policies that compare
  `:actor_name` see the people who own the records.
- **What.** The inputs come from the tool's input schema (`core.md` §3.9):
  - *valid* ones: each property within its type, length, range and
    choices, required ones present, an id of an existing record of the
    entity it refers to when there is one;
  - *edge* ones: empty and longest texts, the least and greatest numbers,
    each choice, text in other scripts, emoji, combining and
    right-to-left marks, an id of a record another actor owns;
  - *hostile* ones: a property of the wrong JSON type, a required one
    missing or null, unknown properties, text one character too long,
    control characters and NUL, markup and SQL fragments, numbers beyond
    any range, deep arrays and objects, an id that names nothing.
  An id is chosen among the entity's records by the order they were
  inserted in, not by its text, so the same seed chooses the same record.
  The run is on the test clock, so what depends on time, such as a
  token's expiry, happens the same way each time.
- **Confirmation.** A tool that asks for confirmation (`core.md` §3.6)
  answers its first call with a token and changes nothing. The fuzzer
  then calls it again with the same input and the token, so the operation
  itself runs, and also with a wrong token and with the token and other
  input, which must be refused with `confirmation_invalid`; the other
  input may instead be refused with `invalid_input` when it is refused
  before the token is read (`core.md` §3.6).
- **What must hold**, for every call:
  1. the answer is a result or an error whose code is one of `core.md`
     §3's; never a fault, an error Tun did not expect, which `errors.md`
     records, and never `deadline_exceeded`: no input may make a tool run
     past its deadline;
  2. a call answered with an error changes no record of any entity that
     is not internal (`:internal`, such as the audit's entries); settings
     count;
  3. nothing leaves the process: during the run Tun answers every call
     to another system through `*http-json-handler*` or
     `*program-handler*` as that system being unreachable, no job runs,
     so mail and push wait in their queues, and an attempt to look up or
     connect to another host fails the test (a Unix socket, such as the
     test database's, still connects);
  4. a waiting tool (`waiting.md`) waits no time.
- **Reproducible.** The calls follow from a seed. `bin/test` uses the
  same seed every run, so a run fails only when the code changed what it
  meets. `TUN_FUZZ_SEED=N` sets another, and `TUN_FUZZ_SEED=random` takes
  a new one each run, for deep runs that look further. A failure names the
  tool, the actor, the seed and the input, shrunk: Tun drops properties,
  shortens texts and simplifies numbers while the failure stays, replaying
  the tool's calls up to it from a fresh database each time, or only the
  call that asked for its confirmation when it fails after that alone,
  and shows the smallest input that still fails, an id as the record it
  names by insertion order.
- **Fast.** A fixed number of calls per tool and actor, a constant in
  `tun.test-support` (8) chosen so a client's generated tests stay within
  30 seconds (§1). `TUN_FUZZ_CALLS=N` sets it for a longer, deeper run,
  and the test says how many calls it made and how long they took.
- The generators are Tun's, in `tun.test-support`, so a client's own test
  can use them: one for an input schema, and those it is made of.

## 3. Not yet

Policy properties, sequences of operations and every page for every role
come in later loops, each a section here.
