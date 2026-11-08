# Tools called one after another keep what must hold

- loop: sequences
- mode: reviewed
- stage: build
- base: 2ceb1296b6e5c94006b68e55c0f5cc1654b3b039
- after: policy-properties
- verified: 3ebe37d90e8a24da8266498179c90f15a10e142d
- shown: 3ebe37d90e8a24da8266498179c90f15a10e142d

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
   a number of steps. A step's tool is dealt from a deck: the client's
   fuzzed tools that some actor of the run (§2's) may call, in an order
   shuffled from the seed, a new shuffle when the deck runs out, one deck
   across the run's sequences, so a run with at least as many steps (not
   counting replays) as tools calls every one of them (Jonas, gate A
   round 2). The step's actor is one, from the seed, whom the tool's own
   policy admits (`actor-permits-p`); its input is of the `:valid` or
   `:edge` kind (§2), its ids naming records as they are when the step
   runs, so a record an earlier step made can be named. A mutating tool's input carries a
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
   instead repeats one such step (chosen when the steps are made: a slot
   whose step performed no mutation does nothing, the run counting only
   the replays made): the same actor, tool and arguments as
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
   - orders, which keeps the count: a customer's `completed_orders`
     equals the number of its orders currently `completed` (orders
     README §2.2);
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
   a run with as many steps as tools calls each of them; the summary
   line names sequences, steps, calls, replays, gets, seconds and the
   seed, how many of the fuzzed tools were called and how many mutating
   ones replayed, and names each tool never called and each never
   answered with a result.
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
- 2026-11-08 11:09  gate A asked of a reviewer
- 2026-11-08 11:14  gate A: changes (reviewer): Round 1 fixed. Not every tool is guaranteed a call: independent picks from a fixed seed leave ~9 of the dashboard's 49 tools (and ~40 of Tun's 173) never called, every run, silently. Deal each actor's admitted tools from a seeded shuffle; summary names tools never called or never answered with a result; planted check that a run with as many steps as tools calls each. Optional: one wording for when invariants are checked; §4 to mention picking another actor, the forbidden probe once per sequence and actor, English descriptions; completed_orders declared in orders.
- 2026-11-08 11:15  gate A asked of the person
- 2026-11-08 11:15  gate A: approve (jonas): Gate A passed to Jonas after two reviewer rounds of changes; he chose «Take the fix, approve»: tools dealt from a seeded shuffled deck so a run with enough steps calls every tool, summary names tools never called or never answered with a result, a planted check for it, and the reviewer's small wording fixes.
- 2026-11-08 11:41  rebased onto main 2ceb129 (core 2.13.1); this loop is core 2.14.0
- 2026-11-08 11:41  the sequence test found two defects in its own first probe, each only a sequence reaches: a create that took a parent id naming nothing (then the parts invariant broke), and reaches-p answered no for an entity without a record policy, so made records were never asked of their get; both fixed
- 2026-11-08 11:41  replays compare JSON as written: a first result's NIL and a receipt's null differ as Lisp values, not as JSON
- 2026-11-08 11:41  tools taking revision get the record's current one three times in four (a random one is always stale, conflict)
- 2026-11-08 11:41  Tun's own run: core 46 of 46 tools called, modules 121 of 121, nothing broke; many module tools never answer with a result, held by rules their schemas do not state (configured departments, the actor form, stock-tracked products, name and unit required on articles_create but not in its schema); named in the summary and in testing.md 5
- 2026-11-08 11:41  clients on this Tun: ferdig 756 checks pass, sequence test 2.1 s, 31 of 31 tools, its 3 invariants hold; kurs 350 pass, 4.0 s (half a second per fresh application, as its fuzzing pays per tool); dashboard 1141 pass, 1.7 s
- 2026-11-08 11:41  dashboard generated tests back to back: 26.8 s on this Tun against 24.5 s on its pin (fuzzing 22.7 against 22.1), within 30 s
- 2026-11-08 11:41  bin/build no warnings; bin/test 72 suites green in 163 s
- 2026-11-08 11:49  verify 1: passed build, test, check
- 2026-11-08 11:49  shown (/ui)
- 2026-11-08 11:50  gate B asked of a reviewer
- 2026-11-08 11:57  gate B: changes (reviewer): Blocking: orders and inventory now use define-invariant (core 2.14.0) but declare >= 2.0.0; the replay check skips keys the receipt holds as null without comparing the replay (a secret shown twice passes); articles_create's schema lacks name and unit, which the README requires (criterion 8 says fix); a breach before the first step does not name the scenario. Also: ferdig/kurs generated totals, replays chosen at generation are often wasted, reproduce line wrong in Tun's suites, a leftover progn, attach client test output.
- 2026-11-08 12:05  gate B round 1 fixes: orders and inventory build against core >= 2.14.0 (they use define-invariant); the replay is compared with every key its receipt holds, and the receipt with the first result but for values shown once (a secret shown twice now fails, unit-tested); articles_create's schema requires name and unit, as inventory README 2.1 says (the body's own check and its message are gone); a breach before the first step names the scenario; Tun's own suites read TUN_SEQUENCES and TUN_SEQUENCE_STEPS, so their reproduce line works; testing.md 4 says a replay slot whose step performed no mutation does nothing
- 2026-11-08 12:05  open for gate C: schema-made inputs reach few states in the modules. In Tun's run 55 of 121 module tools never answer with a result (orders_create, orders_update, orders_accept, orders_confirm, articles_create, inventory_receive, inventory_adjust among them), and 11 of 67 mutating tools are replayed, so orders' and inventory's invariants are checked over the scenario's records and the few calls that succeed, not over sequences that move stock or orders. Deeper inputs (examples a module supplies, or inputs made from records) are a later loop's
- 2026-11-08 12:24  fuzzing made faster (criterion 10): on the dashboard the generated tests reached 31.3 s against 26.6 s on its pin in one loaded run, so a tool's calls now start on the copy the tool before it used when that one changed no record but the audit's entries (testing.md 2); a fresh copy cost a database and an application per tool. Tun's fuzz-core 12.5 s to 4.7 s, fuzz-modules 18.9 s to 9.8 s, fuzz 16.2 s to 9.1 s; all pass
- 2026-11-08 12:24  generated tests back to back, this Tun against each client's pin (.build/loop/sequences/clients/): dashboard 22.3 s against 25.8 s (fuzzing 18.1 against 23.1, sequences 1.7); ferdig 15.0 s against 15.3 s (fuzzing 10.4 against 12.8, sequences 2.1); kurs 14.9 s against 10.7 s (fuzzing 7.9 both, sequences 4.2: half a second to open each fresh application). Clients' bin/test on this Tun: ferdig 756, kurs 350, dashboard 1141 checks, none failed; logs in the same folder
