# A reviewer's gate passes to the person after three «changes» in a row, not two

- loop: gate-three
- mode: reviewed
- stage: done
- base: d4cdbfa2688c9dca6e4cda60c7a8f93e335b0c73
- item: sak_n5a3tqn1vdjznjn7
- tags: kind:loop module:cli
- estimate: 30m 1h 2h30m
- like: rebase-named-base loop-rebase
- verified: 29e5635f33a606426f2c29dd7765908fd180f286
- shown: 29e5635f33a606426f2c29dd7765908fd180f286

## Brief

Jonas, 2026-11-10, on Ferdig item sak_n5a3tqn1vdjznjn7 (part of «Software
factory», sak_eenmv3mb25nms8m2):

> i find that the reviewer hands it back twice too often, so we should not
> hand it to me then, maybe after 3 times

Today a reviewer's gate passes to the person after two answers of
*changes* in a row at one gate (spec/loop.md §4, docs/loop.md §9). Make it
three, in the spec, the docs, the code and the tests, with the number in
one place in the code. Brought by the factory's orchestrator, mode
reviewed.

## Criteria

1. In the reviewed mode, after one or two answers of *changes* in a row
   from a reviewer at a gate, that gate is still the reviewer's
   (`tests/loop-tests.lisp`, a-gate-goes-to-the-person-or-a-reviewer-by-the-mode).
2. After three answers of *changes* in a row from a reviewer at a gate,
   that gate is the person's: `tun loop gate` asks the person, and `tun
   loop decide … --by reviewer` is refused there (same test, and the loop
   run from start to finish in its own repository, where gate A gets three
   reviewer *changes* and the fourth asking goes to the person).
3. Three *changes* at another gate, or three not in a row (a person's
   answer between them), leave the gate the reviewer's (same test).
4. The number is one definition in `src/cli/loop.lisp`, which the gate's
   decider reads; spec/loop.md §4 and §7 and docs/loop.md §9 say three.

## Decisions

- The count stays «in a row, at one gate, from a reviewer», as today; only
  the number changes. A person's answer between them starts it again.
- No core version change: `tun loop` is the command line, not the kernel
  that clients build against (as in the loop rebase-named-base).
- Shown in the showcase like any change to `tun loop`; it changes no page,
  so the screenshots are the showcase's start page and the evidence is
  the tests.

## Actuals

```json
{"loop":"gate-three","title":"A reviewer's gate passes to the person after three «changes» in a row, not two","repository":"tun","mode":"reviewed","stage":"done","item":"sak_n5a3tqn1vdjznjn7","tags":["kind:loop","module:cli"],"like":["rebase-named-base","loop-rebase"],"started":"2026-11-10 08:37","ended":"2026-11-10 08:49","minutes":{"total":12,"waiting_person":0,"waiting_reviewer":2,"working":10,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":30,"likely":60,"worst":150,"at":"brief"},"latest_estimate":{"best":30,"likely":60,"worst":150,"at":"brief"},"within_estimate":false,"ratio":0.2,"verify":{"rounds":1,"failed":0},"changes":{"A":0,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-10 08:37  started, reviewed
- 2026-11-10 08:38  estimated 30m 1h 2h30m at brief, like rebase-named-base loop-rebase
- 2026-11-10 08:38  gate A asked of a reviewer
- 2026-11-10 08:39  gate A: approve (reviewer)
  The spec change matches the brief: Jonas asked for three, and the change makes it three without altering anything else.
  
  **Criteria against the brief**
  - The brief asks for one thing: a reviewer's gate goes to the person after three *changes* instead of two. Criteria 1 and 2 cover both sides of that boundary. After one or two *changes* the gate stays the reviewer's, and after three it is the person's. That catches an off-by-one in either direction.
  - Criterion 3 keeps the existing rules for what counts: the three must be at one gate, in a row. Criterion 4 asks for the number to be defined once, as the brief says. Nothing beyond the brief is added.
  - Each criterion names its test (`a-gate-goes-to-the-person-or-a-reviewer-by-the-mode`, and the full loop run in its own repository), and a test can decide each one. Criterion 2's full-loop case, where the fourth asking at A goes to the person, is concrete enough to check.
  
  **Spec and docs against the criteria**
  - `spec/loop.md` §4 now says three, and the status line records the change with its date. §7's evidence lists both the two-*changes* and three-*changes* cases and the full loop passing A to the person. `docs/loop.md` §9 says three. That is every place criterion 4 names.
  - I found no other mention of "two" in the spec or docs. Two places in the code still say "two", and gate B should confirm they change:
    - `src/cli/loop.lisp:434-442`: the docstring of `gate-decider` and its hard-coded `last-two` / `(= 2 …)`.
    - `tests/loop-tests.lisp:43`: the test name "two requests for changes in a row".
  
  **Decisions**
  - Keeping the count "in a row, at one gate, from a reviewer" is what the brief implies: Jonas asked only about the number.
  - Leaving the core version alone follows the earlier loop `rebase-named-base`, where `tun loop` was also treated as command-line tooling rather than kernel.
  - Using the tests as evidence instead of screenshots is reasonable, since no page changes.
  - None of these needed Jonas's answer.
  
  **A small note, not blocking:** §4 also says an approval between the *changes* restarts the count. That is true of today's code, because an approval breaks the run of *changes*, but no criterion or test covers it. In practice, once a gate is approved the loop doesn't come back to it.
- 2026-11-10 08:47  verify 1: passed build, test, check
- 2026-11-10 08:47  shown (/)
- 2026-11-10 08:47  gate B asked of a reviewer
- 2026-11-10 08:48  gate B: approve (reviewer)
  I approve this one. The change does what the brief asks, every criterion has a test that decides it, and verification passed.
  
  **Criteria**
  1. **One or two *changes* stay the reviewer's.** `tests/loop-tests.lisp:40-43` checks that after one and after two *changes* from a reviewer, the gate is still the reviewer's. The two-*changes* case gives `:person` under the old code, so that test fails without the change.
  2. **Three *changes* go to the person.**
     - The unit test at `tests/loop-tests.lisp:44-46` checks three *changes* in a row.
     - The full loop in its own repository (`tests/loop-tests.lisp:150-158`) runs three reviewer *changes* at A. The fourth asking then prints "waits for the person" and leaves the stage at `gate-a` without running the reviewer. `decide A approve --by reviewer` is refused with "the person's to decide", and only the person's answer moves the loop on to `build`.
     - The expected log lines are updated to match ("gate A asked of the person", "gate A: approve (jonas): «ja»"). Under the old code the third round would already have gone to the person, so this test fails without the change too.
  3. **Another gate, or not in a row, stays the reviewer's.**
     - Three *changes* at A leave B the reviewer's (line 50).
     - A person's answer between them restarts the count (lines 53-56): four *changes*, but only the last one after the person's answer counts.
     - An approval between them restarts it too (lines 57-60). This also covers the gap gate A noted, and fails under the old code.
  4. **The number is defined once.** `+reviewer-changes+` is defined once in `src/cli/loop.lisp:16`, the same way as `+verify-rounds+`. `gate-decider` (lines 436-448) reads it for both the `last` and the length test, and its docstring no longer says "two". `spec/loop.md` §4, §7 and the status line, and `docs/loop.md` §9, all say three. I found no other "two" for this rule in `src/cli/loop.lisp`, `spec/` or `docs/`. The two places gate A flagged are fixed: the hard-coded `last-two` is gone, and the old test name is now the "still the reviewer's" case.
  
  **Brief:** Jonas asked for "maybe after 3 times", and it is now three, with the counting rule unchanged. The message `tun loop gate` prints for the person mentions no count, so nothing else needed changing.
  
  **Code:**
  - The diff is small and readable, with no debugging left in and no dead code.
  - The new test "in the autonomous mode too" describes behaviour that already existed: `gate-decider` treats only hands-on and C as special. It is accurate, not a special case.
  - No core version bump, following `rebase-named-base`, which is sound.
  
  **Verification:** build, test and check all passed in round 1. As decided at A, the screenshots only show the showcase's start page, since no page changes, and the tests are the evidence.
- 2026-11-10 08:49  finished at tun f3d64c0
