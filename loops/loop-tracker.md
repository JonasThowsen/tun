# Løkkens tilstand speiles i en tracker

- loop: loop-tracker
- mode: autonomous
- stage: done
- base: 3522fe69d113239ff0ade0c62b0e3fe38ddaa143
- verified: 845f7e4402367db8db045f6298d849ba2d100338
- shown: 845f7e4402367db8db045f6298d849ba2d100338

## Brief

Requested by Jonas on 2026-10-26, through an agent working on a client
that tracks its work in a tracker of its own (spec/loop.md §8, step 4):

> `tun loop start … [--item REF]` records `- item: REF` in the record
> (opaque to Tun: a URL or an id); `tun loop status` (and --json) shows it.
> `TUN_TRACKER` names a program, like TUN_REVIEWER, that tun loop runs on
> the loop's events: start; a gate asked (with who decides: person or
> reviewer, and the exact text to tell the person); decide (gate,
> approve/changes, by, why); verify (pass/fail and what failed); show (the
> preview link); log lines; finish. The program gets the event and the
> record's path, plus the fields as JSON on stdin or args. On start without
> --item, the program may print an item reference, which tun records as
> `item`. The tracker is a mirror, never the source of truth: a failing or
> slow program logs a line in Log, and the loop carries on. Without
> TUN_TRACKER, nothing changes. docs/loop.md: with a tracker, a person's
> gate is also asked on the item so they can answer from their phone; the
> agent waits for the answer there and records it with `tun loop decide`.
> Tests with a fake tracker program that records its calls.

Jonas's condition: the parts in Tun know nothing of the client that asked.

## Criteria

1. `tun loop start NAME --title T --item REF` records `- item: REF`;
   `tun loop status` prints it and `--json` has `"item"`. A REF with a
   line break, or an empty one, is a usage error (exit 2).
2. With `TUN_TRACKER` set, each of start, gate, decide, verify, show, log,
   resume and finish runs it as `COMMAND EVENT RECORD`, after the record is
   saved, with the JSON of spec/loop.md §6.1 on standard input, each member
   of the type §6.1 gives: the common members and each event's own (a
   person's gate carries the exact text `tun loop gate` prints for them; a
   reviewer's gate is a gate event, then a decide event with the reasons).
   A refused step sends nothing.
3. At start without `--item`, when the tracker exits 0 within the limit,
   the first non-blank line it prints becomes `item`, and later events
   carry it; a line over 500 characters is not taken and the log says so;
   on a failure, or with `--item`, what it prints is not read.
4. A tracker that exits non-zero, or runs past the time limit (30 s), adds
   `tracker: EVENT failed: …` to the log, which sends no event of its own;
   the step still does what it would have and exits as it would have. Its
   standard error is added to `.build/loop/NAME/tracker.log`.
5. Without `TUN_TRACKER`, no program runs and the record is as before.
6. Shown by `tests/loop-tests.lisp`: a stand-in tracker that records its
   calls, through a loop from start to finish; a failing one and a hanging
   one.

## Decisions

- The event and the record's path are arguments; everything else is JSON
  on standard input. Arguments let a small shell adapter dispatch on the
  event; JSON carries text with any characters without quoting rules.
- `sh -c`, as for `TUN_REVIEWER`, so `TUN_TRACKER` may be a command with
  arguments.
- The time limit is 30 s and is not configurable: the tracker is a mirror,
  and a step that waits longer for it costs the agent more than a missed
  comment. The tests lower it through a special variable.
- `resume` is an event too, since it moves the stage; the request named the
  others.
- Not a change to the kernel's runtime: `tun loop` is the command line. The
  core version still goes to 1.17.0, so a client can name the Tun that has
  it.
- The time limit is kept with a child process and a deadline, not
  coreutils' `timeout`, so it needs nothing on PATH beyond `sh`.


## Log

- 2026-10-26 16:06  started, autonomous
- 2026-10-26 16:08  gate A asked of a reviewer
- 2026-10-26 16:09  gate A: changes (reviewer): §6.1 must give each field's JSON type and shape (time, commits, steps/failed/paths, round, reasons); say the item is taken only on exit 0 within the limit and what a line over 500 characters does; --item with a newline is a usage error (2); the failure line sends no log event, and a refused step sends nothing
- 2026-10-26 16:10  gate A asked of a reviewer
- 2026-10-26 16:12  gate A: approve (reviewer): §6.1 now gives every member's type, the item rule and the failure rules; criteria decidable by tests; nothing names a client
- 2026-10-26 16:22  verify 1: passed build, test, check
- 2026-10-26 16:23  shown (/)
- 2026-10-26 16:23  gate B asked of a reviewer
- 2026-10-26 16:26  gate B: approve (reviewer): criteria 1-5 met and tested (156/156), spec and versions agree; show event and person gates at A/B untested but simple
- 2026-10-26 16:26  finished at tun e7570bd
