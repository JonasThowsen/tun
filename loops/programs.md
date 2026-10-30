# A client runs a declared program, such as nixploy, behind a port with a fake for tests

- loop: programs
- mode: hands-on
- stage: done
- base: 2ba9aab7f9dd238bebd2e6b7041dee56c2c381a3
- verified: 53448c89e3345fc1ac335276cbcda461e100ae9c
- shown: 53448c89e3345fc1ac335276cbcda461e100ae9c

## Brief

Jonas, 2026-10-30: «A web wrapper / dashboard for nixploy. So that i can
inspect the different machines that have nixploy images running, check
logs, run deploys, etc. This also means i need a way for a web backend to
run the Nixploy commands automatically, and have the Nixploy web backend
running on this always on VPS.» He chose a Tun client of its own
(`nixploy-dashboard`), run as a systemd service on the VPS, reachable on
the tailnet only with sign-in, read-only first. A client may use only
Tun's public interface, and every external system sits behind a port
with a fake adapter; Tun has one for HTTP (`http-json-post`) and none
for running a program. This loop adds it; the client's first loop
(`fleet-overview`) uses it.

## Criteria

1. `(:programs NAME…)` in `define-application` declares the programs an
   application may run. `run-program` with an undeclared name signals an
   error that is not `program-failure`. A server (`bin/serve`, the built
   server) whose `PATH` lacks a declared program exits 2 at start with a
   line naming it; tests and `open-application` do not look.
2. `run-program` values the program's standard output, its exit code and
   its standard error. ARGUMENTS reach the program as they are, with no
   shell: an argument holding `;`, `$(…)`, quotes, a space or a newline
   arrives as one argument, unchanged. DIRECTORY is where it runs, INPUT
   its standard input. An exit code other than 0 is returned, not
   signalled.
3. The program sees only `PATH`, `HOME`, `TMPDIR`, `LANG` and
   `SSH_AUTH_SOCK` of the server's environment, and ENVIRONMENT: a
   `DATABASE_URL` and any other variable the server has do not reach it.
4. `program-failure`, code `unavailable`, with the program's name and
   what it had written, when the program cannot be started, runs past
   its time, writes more than 8 MB to either stream, or is a fifth at
   once in the tenant. Past its time, the program and every process it
   started are gone within six seconds (a test whose program leaves a
   child sleeping finds no process of its group). The messages are
   English with Norwegian in the catalogue.
5. TIMEOUT outside 1 to 3600 seconds is an error in the client's code;
   inside an operation the run is held to the operation's deadline less
   one second.
6. Each run is an `external` step in the trace named by the program and
   its arguments (clipped to 300 characters), with `exit N` or what came
   instead as its detail; input, environment and output are not in it.
7. `*program-handler*` answers in place of the program, with the same
   checks, step and failures.
8. `spec/outbound.md` §6 and `docs/client-api.md` describe it; TUN exports
   `run-program`, `*program-handler*`, `program-failure` and its readers;
   core 2.2.0; `bin/test` green and `bin/build` warning-free.

## Decisions

- **Beside `http-json-post`, in the outbound module.** It is the same
  idea, another system reached from client code, with the same failure
  (an operation error, `unavailable`), trace step and test handler, so a
  client learns one pattern.
- **Declared programs only.** A list in `define-application` keeps what a
  server may run in one place a reviewer reads, and a missing program is
  found at start, not at the first click. Only the server checks, so a
  client's tests that answer through `*program-handler*` need no program
  installed.
- **An exit code is an answer.** nixploy exits 1 with a JSON error on its
  standard output, and 2 for a held marker; the client reads them.
  Signalling would throw that away. `http-post` answers every status for
  the same reason.
- **A small environment.** The server's environment holds the database
  URL and every secret of its SOPS file; a program needs few of them.
  The five passed are what nixploy, git, ssh and Nix need to find
  themselves, a home and the SSH agent; a key goes in ENVIRONMENT from a
  setting declared with `:env`.
- **A process group, stopped as a whole.** nixploy starts ssh, nix and
  podman; stopping only nixploy would leave them running past the
  timeout, holding the output open.
- **Limits as for calls:** four at once per tenant (its own count, not
  shared with HTTP calls, so a slow deploy does not stop mail), 8 MB per
  stream, up to an hour.
- **No streaming yet.** Showing a deploy's progress line by line is the
  dashboard's second loop; it adds an option then, without changing
  this.
- No browser check: no page changes. Tun 2.2.0, additive.

## Evidence

Tests in `tests/program-tests.lisp` (suite `programs`), against the dev
shell's `sh`, `printf`, `env`, `cat`, `head` and `sleep`:

1. `only-a-declared-program-runs` (an undeclared name is an error, not
   `program-failure`), `a-program-is-a-file-name`,
   `tests-and-open-application-do-not-look-for-programs` (an application
   declaring a missing program opens; the start check exits 2 naming only
   that one), `a-server-without-a-declared-program-does-not-start` (a real
   server process from `tests/fixtures/programs-server.lisp` exits 2 with
   `programs-server: the program tun-test-no-such-program is not on PATH`).
2. `arguments-reach-the-program-as-they-are` (`;`, `$(…)`, quotes,
   backquotes, `*`, a space, a newline, `æøå` and an empty argument arrive
   whole; the `$(touch …)` file is not made),
   `a-program-runs-in-its-directory-with-its-input`,
   `an-exit-code-is-an-answer` (exit 2 returned; a signal gives 128+N),
   `both-outputs-are-read-as-they-come` (1 MB to each stream, no deadlock),
   `output-is-utf-8-with-invalid-bytes-replaced`.
3. `a-program-sees-only-a-few-variables-and-its-own`: with `DATABASE_URL`
   and `TUN_TEST_SECRET` set in the test process, `env` shows neither,
   shows the server's `PATH`, an ENVIRONMENT entry, and ENVIRONMENT's
   `HOME` in place of the server's; nothing outside the five and its own.
4. `a-program-that-cannot-start-fails` (missing program, missing
   directory), `a-program-past-its-time-is-stopped-with-what-it-started`
   (fails at 1 s with its output so far; the group of `sh` and its
   background `sleep` is gone within 6 s; a group ignoring SIGTERM is
   still there at first and gone within 6 s, by SIGKILL),
   `a-program-that-ends-has-ended-though-its-children-hold-its-output`,
   `a-program-may-write-at-most-8-mb-to-a-stream` (exactly 8 MB is an
   answer, one octet more on either stream fails, the group is stopped),
   `a-tenant-runs-four-programs-at-once` (the fifth fails at once; HTTP
   calls keep their own places),
   `program-failures-are-in-norwegian-on-a-norwegian-page`; the i18n
   suite's untranslated and unused checks cover the five messages.
5. `the-timeout-is-from-1-to-3600-seconds` (0, 3601, -1, "10" and NIL are
   errors, not `program-failure`; so are bad arguments, directory, input
   and environment), `a-program-leaves-the-operation-time-to-answer`
   (a 2.6 s deadline stops the run at 1.6 s; under a second left, not
   started).
6. `the-trace-shows-the-run-and-not-what-went-in-or-out` (name, `exit 0`,
   a duration; neither input, environment nor output in the trace; a long
   name clipped to 300; `timeout`, `could not start`, `exit 3`).
7. `a-handler-answers-for-the-program` (arguments as given, the step, NIL
   code as could not start, the same checks, no program installed needed,
   an answer that is not text is the test's mistake).
8. `spec/outbound.md` §6 and `docs/client-api.md` describe it,
   `docs/architecture.md` has its row; TUN exports `run-program`,
   `*program-handler*`, `program-failure` and its three readers; core
   2.2.0 in `flake.nix` and `+core-version+`. `bin/build`: 0 warnings
   (core, test-client). `bin/test`: core 7820 checks, 7820 passed;
   test-client 148 checks, 148 passed.

## Log

- 2026-10-30 10:28  started, hands-on
- 2026-10-30 10:31  gate A asked of the person
- 2026-10-30 10:46  gate A: approve (jonas): «Approve» (after asking whether projects go in source code: no, (:programs ...) names the tools; projects are added on the page)
- 2026-10-30 11:32  verify 1: passed build, test, check
- 2026-10-30 11:33  shown (/)
- 2026-10-30 11:33  gate B asked of the person
- 2026-10-30 11:35  gate B: approve (jonas): «Approve and push»
- 2026-10-30 11:35  finished at tun ecc038c
