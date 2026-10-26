# Løkkens base flyttes når grenen flyttes

- loop: loop-rebase
- mode: autonomous
- stage: ship
- base: f45cb27261d8947efb9081879c8a53628f7ebca3
- verified: 7174b8ede924b5fd5a805be6df04f081cc79ed0a
- shown: 7174b8ede924b5fd5a805be6df04f081cc79ed0a

## Brief

Jonas, 2026-10-26, asked whether to fix the gap three reviews met that
day (a record's `base` stays at the commit the loop began from after the
repository moves under it, so a packet's diff shows other work as the
loop's): «yes, do that».

## Criteria

1. `tun loop rebase` sets `base` to the checked-out commit, or with
   `--onto REV` to REV's commit, and logs the old and new base; with a
   client, `client-base` likewise, to the client's checked-out commit or
   `--client-onto REV`'s.
2. After it, the packet's `diff.patch` and the person's diffstat hold only
   the change since the new base.
3. A loop at `verified`, `shown` or `ship` goes back to `build`, and gate
   B then needs a new verify and show; at `brief` and `build` the stage
   stays.
4. It refuses, exit 1, while the loop waits at a gate, is `stuck`, at
   `deploy` or `done`; and when a repository that had a change since its
   old base would have none since its new one, naming `--onto` or
   `--client-onto`. A REV that is not a commit is a usage error, exit 2.
5. With `TUN_TRACKER`, `rebase` is an event with `from_stage` and
   `bases` ({repository, old, new}, full revisions), as spec/loop.md §6.1
   gives.
6. Shown by `tests/loop-tests.lisp`: a loop whose repository gains a
   commit under it, rebased, with each of the above, the tracker's event
   included.

## Decisions

- An explicit command, not a base worked out by itself: after a rewritten
  history the old base is no ancestor of anything, and only the agent
  knows what its work builds on. `docs/loop.md` §5 says when to run it.
- Back to build past verify: the tree that will be committed is not the
  one that was checked and shown, so the gate that approved it no longer
  speaks for it. That is what the loops did by hand that day.
- Refused while waiting at a gate, so a decision is never recorded for a
  packet whose diff has since changed.
- `rebase` is an event for the tracker, as `resume` is, because it moves
  the stage.
- The refusal is per repository and only for one whose change would
  vanish, so a client not changed yet can be rebased, and committed work
  is never dropped from the diff without a word.
- No version bump. The core version is the kernel's contract, which
  modules' `core` ranges check; `tun loop`'s commands are not part of it,
  and a client names the Tun it uses by revision. loop-links followed this;
  loop-tracker's bump to 1.17.0 was not needed for its reason.


## Log

- 2026-10-26 21:02  started, autonomous
- 2026-10-26 21:02  gate A asked of a reviewer
- 2026-10-26 21:05  gate A: changes (reviewer): rebase must be a tracker event; client-base needs its own --client-onto and the no-change refusal must say which repository; stage table, exit code for a bad REV, 'may differ', and docs/loop.md's conditions and --onto; say why no version bump
- 2026-10-26 21:05  gate A asked of a reviewer
- 2026-10-26 21:07  gate A: approve (reviewer): the earlier points met; criteria cover the brief and each is decidable by a test
- 2026-10-26 21:13  verify 1: failed check
- 2026-10-26 21:19  verify 2: failed check
- 2026-10-26 21:27  verify 3: passed build, test, check
- 2026-10-26 21:27  shown (/)
- 2026-10-26 21:27  gate B asked of a reviewer
- 2026-10-26 21:29  gate B: changes (reviewer): no test with a client (client-base, --client-onto, the refusal naming it, the second bases entry); test shown back to build, brief staying, and a refusal at stuck/deploy/done; the message says back at build when it already was
- 2026-10-26 21:39  verify 4: passed build, test, check
- 2026-10-26 21:39  shown (/)
- 2026-10-26 21:39  gate B asked of a reviewer
- 2026-10-26 21:42  gate B: approve (reviewer): the three earlier points met; each criterion has a failing-without test; loop suite 230/230; verify 4 green
