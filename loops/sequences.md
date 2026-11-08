# Tools called one after another keep what must hold

- loop: sequences
- mode: reviewed
- stage: brief
- base: fac67a3716221af6f4d8483956b86398e693eb16
- after: policy-properties

## Brief

Loop 5 of the test programme Jonas set on 2026-11-06 ("the generated
tests need to be fast and reliable … fuzz testing, and all other sorts of
important test types"): stateful sequences with invariants. Reviewed
mode: a reviewer at A and B, Jonas at C.

What holds today, and what does not:

- Each tool is fuzzed alone (`testing.md` §2): its calls run one after
  another on a fresh copy of the scenario's database, but no other tool
  runs between them. A tool never meets a record another tool made,
  changed or removed: a get that faults on an item whose parent another
  tool reopened, or on a project whose customer was renamed, passes.
- Idempotency is tested by hand in core's suite: a replayed `request_key`
  answers with the original result (`core.md` §3.7). Nothing checks that
  it still does after other calls changed the records it named, for
  every mutating tool of a client.
- Nothing checks that what a create returns can be found again by its
  get, or that a removed record is gone from it, across a client's
  tools.
- A rule (`define-rule`) checks one record when it is written. What
  holds across records has no form at all: ferdig's "an item's project
  is at the item's customer" and "an item is never its own ancestor"
  (`ferdig.md` §2, §3.6), orders' "at most one active and one proposed
  plan per order" (orders README §9.1), inventory's ledger. Each lives
  in prose and in hand-written tests of the tools that write it today;
  a tool added later is not tested against it.
- The dashboard's generated tests take about 25 s of their 30 (fuzzing
  23.6 s on 2026-11-08, measured before this loop): a new test has
  little room there.

## Criteria

1. **Sequences.** A new generated test, the eighth,
   `generated-tools-called-in-sequence-keep-the-invariants`
   (`testing.md` §1, new §4). From the `default` scenario's database,
   made as for fuzzing (§2: in memory, or on the test Postgres server for
   a client that needs it; nothing leaves the process; jobs held; the
   test clock), it runs a number of sequences, each on a fresh copy, each
   a number of steps. A step picks, from the seed: an actor of the fuzz
   run (§2's), then one of the client's fuzzed tools whose own policy
   admits that actor (`actor-permits-p`; a step with no such tool picks
   another actor), and an input of the `:valid` or `:edge` kind (§2), its
   ids naming records as they are when the step runs, so a record an
   earlier step made can be named. A mutating tool's input carries a
   `request_key` of its own, unique in the run. A tool that asks for
   confirmation is asked and then confirmed with the token it gave, two
   calls of one step. Defaults: 4 sequences of 25 steps;
   `TUN_SEQUENCES` and `TUN_SEQUENCE_STEPS` set others; the seed is the
   fuzzing seed (`TUN_FUZZ_SEED`), so one seed makes both again.
2. **Every call is checked as a fuzzed one**: §2's seven checks, judged
   against the records as they were before that call (not before the
   sequence).
3. **A replay answers as the first call did.** When an earlier step of
   the sequence performed a mutation (it answered with a result, and was
   not an ask for confirmation), one step in five, chosen from the seed,
   instead repeats one such step: the same actor, tool and arguments as
   the first call sent them (ids as they were resolved then, not record
   refs read again), `request_key` included, without a confirmation token
   (a receipt is replayed before a token is asked for, `core.md` §3.6,
   §3.7). It must change no record but the audit's entries, and answer
   with what its receipt holds: the first result, with each value shown
   once (`show-once`, `auth.md` §7) as null. Not compared: the keys a
   tool's live view adds after the commit (orders' `stock_warnings`,
   orders README §12.3), which describe the records as they are at the
   replay; and the whole result when the receipt was redacted since (a
   module anonymised the record, `redact-entity-receipts`).
4. **What a call makes, its get finds; what it removes, its get no
   longer does.** A *get* is a client read tool (`:kind :read`) whose
   only required property takes ids of its own entity (as §3, whether
   or not the entity has a record policy). After a call answered with a
   result, for each entity with a get: each record that exists after the
   call and did not before, and that the calling actor reaches
   (`store.md` §6, judged after the call), is asked of the get as that
   actor and must not be answered `not_found`; each record that existed
   before and does not after must be answered `not_found` by the get,
   asked as the calling actor. Skipped: an actor the get's own policy
   refuses, and a get that answers `forbidden` for an id that names
   nothing, asked once per sequence and actor (a system-only read, as
   in §3). These gets are checked as calls too (criterion 2), and count
   as calls, not steps.
5. **Invariants.** `define-invariant NAME (&key description) &body BODY`
   (new; `core.md` §1.1, `docs/client-api.md`): BODY reads records, run
   as the system actor in a read transaction of the application, and
   returns a list of breaches, each a text naming the records that break
   it, or NIL when it holds. DESCRIPTION, a non-blank text in English,
   says what holds; breaches are developers' text, not translated. Core,
   a module and a client may declare them; each is attributed to its
   module as a rule is (`"source"`, `"module"`). `registry_describe`
   lists them as `invariants` (`name`, `description`, `source`,
   `module`), so an agent sees the application's rules across records. A
   module's invariants count only where the module is enabled. The
   sequence test checks every invariant of the application on the
   scenario's records before the first step (a breach there fails the
   test, naming the scenario), and again after every call that
   committed. A body that signals an error fails the test as a fault of
   the invariant, naming it. A running server does not check them (not
   yet, `testing.md` §5).
6. **Module invariants.** Each of these is declared in its module and
   holds through Tun's own sequence run (criterion 8):
   - orders: at most one `active` and one `proposed` plan per order
     (orders README §9.1);
   - orders and customers: a customer's `completed_orders` equals the
     number of its orders currently `completed` (orders README §2.2);
   - inventory: an article's ledger rows have distinct revisions, none
     above its `movement_revision` (inventory README §3.2, which counts
     every row written; a consumption re-sync deletes rows, §6.3, so the
     revisions may have gaps);
   - inventory: at most one `consumption` movement per order and article
     (inventory README §3.1).
   A breach the sequences find in a module is fixed in this loop when
   the README already says what must hold; otherwise it is named in the
   record and brought to gate C.
7. **Shrinking and the report.** A sequence that fails is shrunk: its
   steps are dropped, first halves and then single steps, while it still
   fails with the same kind of problem, each candidate replayed from a
   fresh copy, at most 200 replays; a confirmation's two calls and a
   replay's original stay together (a replay whose original is dropped
   is dropped with it). Then the failing step's input is shrunk as §2
   shrinks one, after the remaining steps. The report names the
   sequence, the seed and the kind; lists each remaining step with its
   actor, tool, input (an id as ‹ENTITY #N›, by insertion order, as §2)
   and how it ended; says what broke; and gives the variables that make
   it again (`TUN_FUZZ_SEED`, `TUN_SEQUENCES`, `TUN_SEQUENCE_STEPS`). A
   failure that does not happen again on a fresh copy is reported
   unshrunk, saying so.
8. **Tun's own tools in sequence.** Tun's suite runs the same test over
   core's and the modules' tools from the scenario its fuzz test uses
   (`fuzz-records`), with core's and the modules' invariants, in a suite
   of its own that `bin/test` runs as its own process, with more steps
   than a client's default (8 sequences of 40). What it finds in core or
   a module is fixed in this loop when the spec already says what must
   hold, and recorded with the fix; otherwise named and brought to gate
   C.
9. **Planted defects, each failing its check, each run passing without
   it.** In Tun's suite, on probe tools under `*planted-defects*`:
   - a get that faults on a record whose parent another tool closed:
     the per-tool fuzzer passes it (no other tool runs between its
     calls), the sequence test fails it, shrunk to the steps that reach
     it;
   - a get that answers `not_found` for a record made after the
     scenario (it looks only among the records there were when it was
     first called): criterion 4;
   - a get that keeps what it read in a cache of its own, so a record
     removed since is still found: criterion 4;
   - a receipt deleted between a call and its replay (the test removes
     it), so the replay performs the mutation again: criterion 3;
   - a probe invariant broken by one tool and kept by the others:
     criterion 5, shrunk to that tool's step; and one the scenario
     already breaks, reported before the first step;
   - an invariant whose body signals: reported as the invariant's fault.
   Also: the same seed makes the same sequences, steps and report again;
   the defaults' summary line names sequences, steps, calls, seconds and
   the seed.
10. **Fast.** A client's generated tests together stay within 30 s
    (§1). The log records, per client, the new test's time and the
    generated tests' total, measured against the Tun pinned before back
    to back. If the dashboard goes past 30 s, the fuzzing test is made
    faster in this loop (where its time goes is measured first: today
    a fingerprint of every table after each committing call is about a
    third of it), not the sequence defaults cut below 4 × 25.
11. **Clients.** ferdig, kurs and nixploy-dashboard pass on the new Tun
    (ferdig and the dashboard in tunworks). ferdig declares three
    invariants from its spec: an item's project is at the item's
    customer (§3); an item's parent is at the same customer (§3.6); no
    item is its own ancestor (§3.6). A failure the new test finds in a
    client is fixed where its cause is and shown at gate C before
    anything is pushed.
12. `bin/build` has no warnings; `bin/test` is green. A minor version of
    core (a new form, a new registry field, a new generated test), on
    top of whatever has landed when the loop rebases.

## Decisions

- One step is one call (or one confirmation's two), on one shared
  database per sequence, so a sequence reaches states per-tool fuzzing
  cannot; sequences restart from the scenario's copy so a failure is
  short to replay and shrink.
- Inputs are valid or edge, never hostile: a hostile input is refused
  and changes nothing, so in a sequence it is a wasted step; §2 already
  sends hostile ones to every tool.
- Steps pick only tools the actor's policy admits: refusals are §2's
  work, and a refused step moves no state.
- Replays send the input without a confirmation token: core replays a
  receipt before it would ask for one (`execution.lisp` step 4), which
  is the path a client retrying a confirmed call takes.
- Invariants are a test-time form. Checking them in a running server
  after every write would put arbitrary reads in every write's path;
  a tool that checks them on demand is a later loop's question.
- An invariant returns breaches, not true or false, so a failure says
  which records break it without a second query.
- The get check of criterion 4 asks only "not `not_found`" for a new
  record and "`not_found`" for a removed one: a get may refuse a record
  for its state, as §3 allows.
- A client's run calls only the client's tools, as §2; Tun's tools run
  in sequence in Tun's suite (criterion 8).

## Log

- 2026-11-08 11:02  started, reviewed
- 2026-11-08 11:04  gate A asked of a reviewer
- 2026-11-08 11:08  gate A: changes (reviewer): Replays: show-once secrets are null in receipts and live views (stock_warnings) are added after commit, so 'equal as JSON' fails on specified behaviour; replay must send the original resolved arguments. Inventory ledger invariant is false by design (consumption replacement deletes rows without a movement). docs example uses :not, which the where language lacks (:not-null). ferdig rule is in §3, not §2. testing.md §4: unshrunk report, gets checked as calls, reflow §5.
