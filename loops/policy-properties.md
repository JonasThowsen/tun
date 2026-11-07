# Every tool keeps to the record policies, and a viewer never writes

- loop: policy-properties
- mode: reviewed
- stage: build
- base: ff369f47d2bdfa55e9c964f0b122f4af9ed9b7a8
- after: audit-nul

## Brief

Loop 4 of the test programme Jonas set on 2026-11-06 ("the generated
tests need to be fast and reliable … fuzz testing, and all other sorts of
important test types"): policy properties. Per role, a tool that lists,
gets, changes or deletes a record agrees with the entity's record policy
(`store.md` §6), and a viewer never writes. Reviewed mode: a reviewer at
A and B, Jonas at C.

What holds today, and what does not:

- Record policies are applied by the store, so a tool that reads through
  `fetch`, `select` and queries keeps to them by construction. A tool can
  still step around them: a body that reads as the system actor
  (`with-actor`) shows records the caller's policy hides, and one that
  checks ownership itself answers `forbidden` for a hidden record and
  `not_found` for a missing one, which tells the caller it exists
  (`store.md` §6 item 4). Fuzzing sends ids of records another actor owns
  (an edge input), but nothing checks what the answer reveals.
- A viewer cannot write through a read: a read runs in a read
  transaction, which refuses a write, and a mutating tool refuses a
  viewer unless it is declared `:viewer-mutation`. A `:kind :wait` tool
  is neither: its body runs outside any transaction (`waiting.md` §1),
  its policy is `viewer` unless it says otherwise, and nothing stops it
  opening a write transaction, though `waiting.md` says it never writes.
  A body can also write from a thread of its own, outside its
  transaction.
- The fuzzer's second check ("an erring call changes no record") leaves
  out internal entities, so a refused call that leaves a job, a mail or
  a stock reservation behind passes (noted at the fuzz loop's end).

## Criteria

1. **A hidden record is a missing one.** A new generated test,
   `generated-every-tool-keeps-to-the-record-policies` (`testing.md` §1,
   §3), for every tool of the client with an input property that takes
   ids of an entity with a record policy: a top-level parameter, or a
   field of a create's draft (`operation-references`, top-level paths
   only). For each actor of the fuzz run (`admin:fuzz`, `employee:fuzz`,
   `viewer:fuzz` and the `default` scenario's) and each such property:
   - an actor the tool's own `:policy` refuses (`actor-permits-p`) is
     skipped, and counted as such;
   - the first record, by insertion order, of the property's entity that
     the actor's policy hides (one the system actor reads and the actor
     does not) is taken, judged just before the call; an actor with no
     hidden record is skipped;
   - the input is a valid one (the fuzz generators' `:valid` kind, from
     the fixed seed), its other id properties naming the first record
     the actor reaches of their entity, or, when it reaches none, left
     out if optional; when a required one cannot be filled the pair is
     counted as not compared;
   - the tool is called with that input holding an id that names
     nothing, then with it holding the hidden record's id. Both must end
     alike: with a result each, or with the same error code. A tool that
     asks for confirmation is confirmed as the fuzzer confirms it, and
     the confirming calls are compared. When the first ends in
     `invalid_input`, which says nothing about the id, up to three more
     valid inputs are tried, and the last pair is compared all the
     same.
   The summary says how many pairs were compared, how many were skipped
   for the tool's policy, and how many could not be compared.
2. **A get agrees with the policy.** In the same test, each `:kind :read`
   tool whose entity has a record policy and whose only required
   property takes ids of that entity is called, by each actor its
   `:policy` admits, with only that property: first with an id that names
   nothing, then with each of the first three records, by insertion
   order, that the actor's policy admits. When the first answers
   `forbidden` (a body that refuses the caller whatever the record, such
   as the dashboard's system-only reads), the actor is skipped; otherwise
   no admitted record may be answered `not_found`, the one answer a
   record policy decides. Other refusals, for a record's state, pass.
3. **No answer shows a hidden record.** A sixth check of every fuzzed
   call (`testing.md` §2) and of every call of criteria 1 and 2: no
   object in a result has an `id` naming a record of an entity with a
   record policy that the calling actor's policy hides, judged after the
   call. An id is matched to its entity by its prefix (each prefix
   belongs to one entity). Not counted: a reference to another record
   (`project_id`); a record the call itself inserted (one ferdig files
   for a colleague as the system actor); and a tool declared to show
   records beyond the record policy (criterion 4).
4. **A tool that shows records beyond the policy says so** (Jonas, gate A
   round 1). `define-operation` takes `:beyond-record-policy "WHY"`, a
   non-empty text saying why the tool shows records the caller's record
   policy hides (ferdig: a system at a customer reads the items its
   person reported, `ferdig.md` §5.2). `registry_describe` lists it as
   `beyond_record_policy`. Only the sixth check skips such a tool; every
   other check holds for it. `store.md` §6 says so. A tool that is not
   declared and shows a hidden record fails, naming the option.
5. **A viewer never writes.** A seventh check of every fuzzed call: a
   call as an actor of role `viewer` to a tool that is not a viewer
   mutation (a mutating tool whose policy is `viewer`, which
   `:viewer-mutation` allows) changes no record of any entity, internal
   ones included, but the audit's entries, whatever it answers. By
   construction too: a `:wait` tool's body may not open a write
   transaction; it fails `read-only-violation`, as a write in a read
   does (`waiting.md` §1). A refusal audited inside a wait's body still
   writes its entry.
6. **A refusal leaves no internal record either.** Check 2 counts every
   entity's records, internal ones included, but the audit's entries,
   which a refusal writes (`core.md` §3.8). Settings still count. (An
   ask for confirmation issues a confirmation, but it is answered with a
   result, which check 2 does not look at.)
7. **audit_list keeps to the record policies** (Jonas, gate A round 1).
   An entry whose entity has a record policy is listed only to a caller
   whose policy reaches its record; when the record no longer exists,
   only to a caller whose role's clause is `t` (`:admin t`, typically).
   Entries of other entities, and of none, are listed as today. `limit`
   counts the entries listed. `core.md` §3.8 says so. Tests on
   Postgres: an employee does not see the entries of another's memo, sees
   their own, and the admin sees both; an entry of a deleted memo is the
   admin's only; `entity_id` naming a hidden memo lists nothing, as for
   one that does not exist; `limit` is filled past hidden entries.
8. **Planted defects, each failing its check, each run passing without
   it.** On Postgres in Tun's suite, with a probe entity `fuzz-memo`
   whose policy is `(:admin t) (:employee "author = :actor_name")` (no
   viewer clause) and a scenario with memos by two people:
   - a list that reads as the system actor fails the sixth check,
     naming the tool, the actor, the seed, the input and the record; the
     same list declared `:beyond-record-policy` passes;
   - a get that fetches as the system actor answers a result for a
     hidden memo and `not_found` for a missing one: criterion 1;
   - a change that refuses another's memo with `forbidden` before it
     fetches: criterion 1;
   - a get that answers `not_found` for a memo the actor may read:
     criterion 2;
   - a read, of policy viewer, that writes a memo from a thread of its
     own: the seventh check (construction does not reach other threads);
   - a `:wait` tool whose body writes: refused by construction, which the
     fuzzer reports as a fault; without the construction the seventh
     check fails it (shown once, in the log);
   - a tool that queues a job from a thread of its own and then refuses:
     check 2 (which passes it today, the job being internal).
   Shrinking works on the sixth and seventh checks as on the others.
9. ferdig, kurs and nixploy-dashboard pass on the new Tun, their
   generated tests within 30 s each, and the log records each client's
   times for the fuzzing test and the new one. Their only changes are
   the pin and the `:beyond-record-policy` declarations ferdig's
   delegating tools need; a failure the new checks find otherwise is
   fixed where its cause is, in the client or in Tun, and shown at gate
   C before anything is pushed.
10. `bin/build` has no warnings; `bin/test` is green. A minor version of
    core (a new option, a new generated test, audit_list and waits
    changed), set when the loop rebases onto what has landed by then.

## Decisions

- The oracle is the store itself: which records an actor reaches is what
  `fetch` and `select` return as that actor, compared with the system
  actor. The checks do not parse policy conditions.
- Compare a hidden id with one that names nothing, not with an expected
  code: tools answer a missing record differently (`not_found`, an empty
  list, `invalid_input`), and what matters is that the caller cannot
  tell the two apart. Results are compared by kind only: a list filtered
  by a hidden project may rightly hold the caller's own records in it.
- The get check asks only that an admitted record is not `not_found`:
  that is what a record policy decides; a tool may refuse a record for
  its state (`questions_wait`-like reads refuse a comment that is not a
  question). `:wait` tools are left out of it.
- The sixth check counts the records a result shows, not the ids it
  mentions. A record the caller reaches may refer to one it does not, and
  hiding those ids would mean rewriting the record; `store.md` §6 says
  only that a hidden record "is not there". Listed as not checked.
- Deliberate delegation is declared on the tool (Jonas chose this over
  narrowing the check): loud, visible in the registry, and skipped by
  the one check it would otherwise fail, like `:viewer-mutation`.
- Not checked, listed in `testing.md` §4: that a list shows every record
  the actor reaches (lists have default filters and limits); ids inside
  arrays and nested objects of an input; Tun's own tools in a client's
  run (they are fuzzed in Tun's suite, where only the probe entity has a
  policy). `attachments_*` already read the record as the caller
  (`files.md` §4.2); `audit_list` is fixed here.
- Writes from another thread are left to the seventh check rather than
  refused by construction: refusing them would mean every thread a read
  starts inherits the refusal, a worker pool started lazily from a read
  among them.
- Time: actors a tool's policy refuses are skipped before any call, and
  the new test uses one copy of the scenario's database for all its
  tools, made again only after a call that changed a record other than
  the audit's entries (most calls are refusals, which change none). A
  tool whose pairs are all skipped makes no call. The fuzzing test keeps
  a copy per tool. Measured per client at the end (criterion 9).
- A new generated test, not more checks in the fuzzing test: its name
  says what failed, and it runs only where a record policy is (on a
  client without one it passes at once, saying so).

## Log

- 2026-11-07 19:55  started, reviewed
- 2026-11-07 19:58  gate A asked of a reviewer
- 2026-11-07 20:06  gate A: changes (reviewer): Get exemption fails dashboard system-only reads (needs own missing-id call); read tool undefined (questions_wait); vacuous pairs (other ids hidden, policy-refused); confirmation ask writes; 30s budget plan contradicts spec; ask Jonas on audit_list now; say when hides is judged
- 2026-11-07 20:10  gate A asked of a reviewer
- 2026-11-07 20:19  gate A: approve (reviewer): Round 1 answered; claims match code; no false positives. In build: no recopy between ask and confirm; compare invalid_input pairs anyway; fix testing.md 4, core 3.9/3.8 wording, audit entry without entity_id; keep dashboard under 30s
- 2026-11-07 21:07  build: generated-every-tool-keeps-to-the-record-policies (tests/policy-checks.lisp): hidden-vs-missing pairs, gets, one database copy remade only after a change; fuzz checks 6 (no hidden record shown, judged after the call, inserted records and :beyond-record-policy tools left out) and 7 (a viewer never writes); check 2 counts internal records but the audit's; :beyond-record-policy in define-operation and registry_describe; a wait's body refuses writes (*writes-refused*), its refusal still audited; audit_list keeps to the record policies, paging past what it leaves out. Planted defects in tests/policy-tests.lisp on Postgres, each found, each passing without it
- 2026-11-07 21:07  shown once: without the wait's write refusal, the fuzzer fails a viewer's fuzz_memos_watch that writes a note (check 2: refused with not_found but changed records of fuzz_note); without the audit's exemption inside a wait, check 5 fails the refusal (left no rejected audit entry). A wait writing a memo was already refused for viewers by the record policy, so the probe writes a note
- 2026-11-07 21:07  clients against this tree: kurs 349 checks, fuzz 8.0s, nothing to check (no record policy); ferdig 755, fuzz 12.2s, policies 1.3s (22 tools, 43 pairs, 42 past validation, 9 gets); nixploy-dashboard 1140, fuzz 23.0-23.9s against 21.8s on Tun afa9fba at the same load, policies 0.8s (0 pairs: only viewers have hidden records and its tools refuse viewers; 28 gets). ferdig declares :beyond-record-policy on items_get and items_list (ferdig.md 5.2); no fuzz actor is a system at a customer, so those paths are not exercised
