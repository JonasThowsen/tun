# A client reads a program's progress while it runs

- loop: program-progress
- mode: hands-on
- stage: done
- base: 417e0f7e1ea03f6c9004027f6c24ca9f5c5bf4cc
- verified: 5a6b5946d530be7fa5513ef867a2fe105e608f82
- shown: 5a6b5946d530be7fa5513ef867a2fe105e608f82

## Brief

Jonas, 2026-10-30, for nixploy-dashboard, a client that runs nixploy:
«let us move on to the next loop», the loop that deploys from the
dashboard, by a person or an agent. A deploy takes minutes; nixploy
writes one line to standard error per stage (`building: Building and
loading the image`, a heartbeat every 30 seconds while Nix builds,
`switching: …`), and the dashboard should show those lines while the
deploy runs, not only when it ends. `run-program` (core 2.2.0) gives a
program's output only when it has ended.

## Criteria

1. `(run-program … :on-error-line F)` calls F with each line the program
   writes to its standard error as soon as the line is complete, while
   the program still runs: a program that writes a line, then sleeps,
   has F called before it ends.
2. A line is passed without its newline and decoded as UTF-8 with an
   invalid byte replaced; a last line without a newline is passed when
   the program ends; a line longer than 16 KiB is passed in pieces of
   16 KiB; a line split across reads is passed once, whole.
3. The lines are still in the standard error `run-program` values, and
   standard output is unchanged.
4. An error F signals stops the program and its group as running past
   its time does, and is signalled from `run-program`.
5. With `*program-handler*` answering, F is called with each line of the
   handler's error output before `run-program` returns.
6. Without `:on-error-line` nothing changes: the suites and the programs
   tests pass as before. Core version 2.3.0.

## Decisions

- **Standard error only.** That is where nixploy, Nix and most tools
  write progress; standard output stays the answer, parsed whole when
  the program ends (`--json`).
- **Lines, not chunks.** A client records and shows lines; splitting
  them in Tun once spares each client the same buffer. 16 KiB bounds
  what one call can be handed.
- **Called between reads, in the running thread.** The client records a
  line through an operation of its own, its own transaction, from a job
  with `:transaction nil`; Tun adds no thread or queue. The pipe's
  buffer holds what the program writes meanwhile.
- **Nothing to show in a page.** The change is to the client interface;
  the showcase does not change, and nixploy-dashboard's loop `deploys`
  shows it in use.
- Spec: `spec/outbound.md` §6 and §6.1.

## Log

- 2026-10-30 19:44  started, hands-on
- 2026-10-30 19:45  gate A asked of the person
- 2026-10-30 19:54  gate A: approve (jonas): «Approve both»
- 2026-10-30 20:11  verify 1: passed build, test, check
- 2026-10-30 20:11  shown (/)
- 2026-10-30 20:11  gate B asked of the person
- 2026-10-30 20:12  gate B: approve (jonas): «Approve and push»
- 2026-10-30 20:12  finished at tun d23c669
