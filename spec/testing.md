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
  6. every tool of the client withstands fuzzing (§2);
  7. every tool of the client keeps to its record policies (§3);
  8. the client's tools called in sequence keep what must hold, and
     every invariant of the application (§4).
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
  2. a call answered with an error changes no record of any entity,
     internal ones (`:internal`) and settings included, but the audit's
     entries, which a refusal writes (`core.md` §3.8): no job, mail or
     reservation is left behind;
  3. nothing leaves the process: during the run Tun answers every call
     to another system through `*http-json-handler*` or
     `*program-handler*` as that system being unreachable, no job runs,
     so mail and push wait in their queues, and an attempt to look up or
     connect to another host fails the test (a Unix socket, such as the
     test database's, still connects);
  4. a waiting tool (`waiting.md`) waits no time;
  5. a call refused as `forbidden`, `confirmation_invalid` or
     `idempotency_conflict` leaves its audit entry, `outcome: "rejected"`
     (`core.md` §3.8), whatever its input holds;
  6. no object in a result has an `id` naming a record that the calling
     actor's record policy hides (`store.md` §6), judged after the call:
     one the system actor reads and the actor does not. An id is matched
     to its entity by its prefix. A record the call itself inserted does
     not count, nor does any record a tool declared
     `:beyond-record-policy` (`store.md` §6 item 9) shows;
  7. a call as an actor of role `viewer` changes no record of any
     entity, internal ones included, but the audit's entries, whatever
     it answers, unless its tool is a viewer mutation (a mutating tool
     whose policy is `viewer`, which `:viewer-mutation` allows).
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

## 3. Record policies in every tool

The seventh generated test,
`generated-every-tool-keeps-to-the-record-policies`, checks that each
tool of the client answers as the record policies (`store.md` §6) say,
for each role: a record an actor's policy hides is not there for that
actor, through any tool.

- **Which tools.** Every tool of the client with an input property that
  takes ids of an entity with a record policy: a parameter of the tool,
  or a field of a create's draft. A client without such an entity passes
  at once, and the test says so.
- **Where and who.** As for fuzzing (§2): the database the `default`
  scenario filled, on the test Postgres server, nothing leaving the
  process, the same actors. One copy serves the test's calls, made again
  before a pair (below) when a call since the last copy changed a record
  other than the audit's entries; never between a confirmation's ask
  and its confirming call.
  What an actor reaches is what the store reads as that actor, against
  what it reads as the system actor, judged at each call. An actor the
  tool's own policy (`core.md` §3.3) refuses is skipped.
- **A hidden record is a missing one.** For each actor and each such
  property, the tool is called with a valid input (§2) holding an id
  that names nothing, then with the same input holding the id of the
  first record, by insertion order, that the actor's policy hides. The
  input's other ids name records the actor reaches. Both calls end
  alike: with a result each, or with the same error code, so the caller
  cannot tell a hidden record from one that does not exist (`forbidden`
  for one and `not_found` for the other tells it). A tool that asks for
  confirmation is confirmed as in §2, and the confirming calls are
  compared. When the first call is refused as `invalid_input`, which
  says nothing about the id, up to three other valid inputs are tried,
  and the last pair is compared all the same. The test says how many
  pairs it compared, how many of those past input validation, how many
  it skipped for the tool's policy and how many it could not make.
- **A get agrees.** A read tool (`:kind :read`) whose only required
  property takes ids of its own entity, which has a record policy, is
  called with only that property: first with an id that names nothing,
  then with each of the first three records, by insertion order, the
  actor's policy admits. Unless the first is refused as `forbidden`, no
  admitted record is answered `not_found`.
- **What else must hold.** Every call of this test is checked as a
  fuzzed call is (§2): an erring call changes nothing, and no answer
  shows a hidden record, among the rest.
- **Reproducible and fast** as §2: the inputs follow from the same seed,
  a failure names the tool, the actor, the seed, the input and the record
  by insertion order, and the test counts in §1's 30 seconds.

## 4. Tools called in sequence

The eighth generated test,
`generated-tools-called-in-sequence-keep-the-invariants`, calls the
client's tools one after another on one database, so each call meets what
the calls before it made, changed and removed, and checks after each call
what must hold, the application's invariants among it.

- **Where and who.** As for fuzzing (§2): the database the `default`
  scenario filled, in memory or on the test Postgres server, nothing
  leaving the process, jobs held, the test clock, the same actors. Each
  sequence starts from a fresh copy of it.
- **Steps.** A run is a number of sequences of a number of steps. Each
  step's tool is dealt from a deck of the client's tools that §2 fuzzes
  and some actor may call, shuffled from the seed and shuffled again when
  it runs out, one deck across the run, so a run with as many steps as
  tools calls every one. The step's actor is one whom the tool's own
  policy (`core.md` §3.3) admits, and its input a *valid* or *edge* one
  (§2) whose ids name records as they are when the step runs, those
  earlier steps made among them. A mutating tool's input
  carries a `request_key` of its own. A tool that asks for confirmation
  (`core.md` §3.6) is asked and then confirmed with the token it gave: two
  calls, one step.
- **Replays.** When an earlier step of the sequence performed a mutation,
  one step in five instead repeats one such: the same actor, tool and
  arguments as the first call sent them, ids as they were then,
  `request_key` included, without a confirmation token. It changes no
  record but the audit's entries, and answers with what its receipt holds
  (`core.md` §3.7): the first result, with each value shown once
  (`auth.md` §7) as null. The keys a tool's live view adds after the
  commit, which describe the records as they are at the replay, are not
  compared; nor is the result when the receipt was redacted since (a
  module anonymised the record it holds).
- **What must hold after each call:**
  1. all of §2's checks, judged against the records as they were just
     before the call;
  2. a record the call made, which the calling actor reaches (`store.md`
     §6), is not answered `not_found` by its entity's *get*, asked as that
     actor; a record the call removed is answered `not_found` by it. A get
     is a read tool of the client whose only required property takes ids
     of its own entity. An actor the get's policy refuses is skipped, as
     is a get that answers `forbidden` for an id that names nothing (a
     system-only read, as in §3), asked once per sequence and actor. These
     gets are checked as calls too;
  3. every invariant of the application holds (below).
- **Invariants.** `define-invariant` (`core.md` §1.1) states what holds
  across records, which a rule, one record at its write, cannot: an
  item's project is at the item's customer. Its body reads the records as
  the system actor, in a read transaction, and returns the breaches, each
  a text naming the records, or none, and its description says in English
  what holds: both are for developers, never translated. Core, the modules
  the application enables and the client declare them, and
  `registry_describe` lists them.
  The test checks every one on the scenario's records before the first
  step, and again after each call that committed. A breach before the
  first step fails the test, naming the scenario; a body that signals an
  error fails it as the invariant's fault.
- **Shrinking.** A failing sequence is shrunk: steps are dropped while it
  still fails with the same kind of problem, each candidate replayed from
  a fresh copy, at most 200 replays. A replay is dropped with the step it
  repeats. Then the failing step's input is shrunk as in §2. The report
  lists the steps that remain, each with its actor, tool, input (an id as
  the record it names by insertion order) and how it ended; what broke;
  and the variables that make it again. A failure that does not happen
  again on a fresh copy is reported as it happened, unshrunk, saying so.
- **Reproducible.** The sequences follow from the fuzzing seed
  (`TUN_FUZZ_SEED`, §2), so one seed makes both tests again.
- **Fast.** 4 sequences of 25 steps, constants in `tun.test-support`, so a
  client's generated tests stay within 30 seconds (§1). `TUN_SEQUENCES=N`
  and `TUN_SEQUENCE_STEPS=N` set others for a deeper run. The test says
  how many sequences, steps and calls it made and how long they took, how
  many of the tools it called and replayed, and names each tool it never
  called and each that never answered with a result.
- **Tun's own tools** are called in sequence in Tun's own suite, the same
  way, from the scenario its fuzz test uses, with core's and the modules'
  invariants, and more steps.

## 5. Not yet

Every page for every role comes in a later loop, a section here. A running
server does not check the invariants (§4); tests do. Not checked by §2, §3
and §4: that a list shows every record the actor reaches (lists have their
own filters and limits); ids a result mentions as references to other
records, such as an item's `project_id`, which a record the actor reaches
may hold for one it does not; ids inside an input's arrays and nested
objects; and Tun's own tools in a client's run, alone or in sequence. Of
those, `attachments_…` read the record as the caller (`files.md` §4.2) and
`audit_list` keeps to the policies (`core.md` §3.8), each checked by tests
of its own in Tun's suite.
