# Løkkens journal nevner ikke maskinens adresse

- loop: loop-links
- mode: autonomous
- stage: done
- base: 581e0cbe7c57bfeb673c3376d767371867587279
- verified: 2c8679a5c3ef0f4b834ba56e16625b34616860a2
- shown: 2c8679a5c3ef0f4b834ba56e16625b34616860a2

## Brief

Jonas, 2026-10-26: the record of the first loop pushed to the public Tun
carried the shared preview's link, which names the dev machine and its
tailnet (`tun loop show` writes it to the record's `preview` field and its
log). Asked whether to fix `tun loop` so committed records never carry
preview links, «the link stays in .build/, the log says only the paths
shown», he answered «Yes, as a short loop first».

## Criteria

1. `tun loop show` writes no `preview` field and no link to the record;
   its log line is `shown (PATH, …)`, and the link is in
   `.build/loop/NAME/show/link`.
2. `tun loop status` gives the link from that file, as text and as
   `"preview"` in `--json`; without the file, none.
3. Gate B's text for the person, the tracker's `show` event, and the gate
   B and C packets (as `link`, which `docs/review.md` names) still carry
   the link.
4. Saving a record takes out an older `tun loop`'s `preview` field and the
   link in its `shown at LINK (…)` lines, leaving `shown (…)`.
5. Shown by `tests/loop-tests.lisp`: `record-shown`, which `show-loop`
   calls once its preview runs, leaves no link in the record and writes
   the file; the person's message at gate B, `status --json` and the gate
   B packet read the link from it; a record with an older `preview` field
   and `shown at` line loses both when saved. And by `bin/test-cli`, which
   runs `tun loop show` end to end: after it, the link file exists and the
   record has no `preview:` field and no `shown at` line.

## Decisions

- The tracker still gets the link at `show`: it is the person's own
  mirror, outside the repository, and a link to the preview is what makes
  answering gate B from a phone possible.
- A record that already has a `preview` field loses it, and the links in
  its `shown at` lines, the next time `tun loop` saves it, so the loops
  open when this was made (`web-push` and `board-order`) need no editing
  by hand.
- Not a core change: no version bump.


## Log

- 2026-10-26 19:42  started, autonomous
- 2026-10-26 19:43  gate A asked of a reviewer
- 2026-10-26 19:45  gate A: changes (reviewer): the packet and docs/review.md must say where the link is (docs/review.md says it is in the record); bin/test-cli already runs show end to end, so check the link file and the record there; optionally scrub old preview fields on save
- 2026-10-26 19:45  gate A asked of a reviewer
- 2026-10-26 19:47  gate A: approve (reviewer): earlier points met: the packet's link, bin/test-cli end to end, old links taken out on save; criteria cover the brief
- 2026-10-26 19:54  bin/test-cli passed by hand (it is not a verify step): tun loop show keeps the link in .build/loop/home-list/show/link and none in the record
- 2026-10-26 20:00  verify 1: passed build, test, check
- 2026-10-26 20:00  shown (/)
- 2026-10-26 20:00  gate B asked of a reviewer
- 2026-10-26 20:02  gate B: approve (reviewer): criteria 1-5 met and tested (172/172, test-cli by hand); no link in the record; the regex matches only tun loop's own show lines
- 2026-10-26 20:02  finished at tun 8391b54
