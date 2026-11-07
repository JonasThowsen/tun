# tun loop rebase godtar en base som er navngitt, også når klienten ikke har noen endring

- loop: rebase-named-base
- mode: reviewed
- stage: ship
- base: a47f7486e9f01b9a67e3f9261aecf69ca6be1da9
- verified: 5e48df9235a95c90417ae06930aec20a890294b0
- shown: 5e48df9235a95c90417ae06930aec20a890294b0

## Brief

Found 2026-11-07 while fixing the chart tooltip (loop chart-tooltip-height,
client kurs) for Jonas. Its gate B reviewer asked to verify again against
kurs without another loop's work (watchlist-currency), once that was
committed: `tun loop rebase --client-onto <that commit>`, as docs/loop.md
§5 says. kurs's tree then equals that commit, and this loop changes nothing
in kurs, so the guard against work already committed refuses even the named
commit: «kurs has no change since 9f423bf, though it had one since the
loop's base: its work is committed there. Name the commit the work builds
on: bin/tun loop rebase --client-onto REV», which is what was given. The
loop cannot be rebased at all.

## Criteria

1. `tun loop rebase --client-onto REV` (or `--onto REV`) sets the base to
   REV even when the repository has no change since REV.
2. Without the option, a repository with a change since its old base and
   none since its checked-out commit is still refused, naming the option.
3. The existing rebase tests pass unchanged.

## Decisions

- The guard is there to stop a base taken by default from swallowing the
  loop's committed work; a named commit is the person's own word, and the
  refusal's own text tells them to name one. So only the default is
  guarded.
- No version change: `tun loop` is the command line, not the kernel the
  clients build against.

## Log

- 2026-11-07 11:59  started, reviewed
- 2026-11-07 12:00  gate A asked of a reviewer
- 2026-11-07 12:03  gate A: approve (reviewer): Criteria cover the brief, each decidable; the new assertion fails on the old code; spec agrees. Notes: --onto case and a docs half-sentence added at build.
- 2026-11-07 12:11  verify 1: failed test
- 2026-11-07 12:17  verify 2: passed build, test, check
- 2026-11-07 12:17  shown (/)
- 2026-11-07 12:17  gate B asked of a reviewer
- 2026-11-07 12:19  gate B: approve (reviewer): All three criteria met with tests that fail on the old code; spec and docs agree; verify passed.
