# A client's generated tests come from Tun, so tun update brings new ones

- loop: client-checks
- mode: reviewed
- stage: done
- base: 9627863ac7e751208c77fa9c2704fdf1153eeed8
- after: fast-tests
- verified: d610b9f1a5070c94dbf46c4b418139bae11144ec
- shown: d610b9f1a5070c94dbf46c4b418139bae11144ec

## Brief

The second loop of the programme Jonas approved on 2026-11-06 («the
generated tests need to be fast and reliable ... Make that happen»):
generated tests must reach clients. Today `tun new` copies five checks into
a client's `tests/tests.lisp`, so a check added to Tun never reaches a
client made before, and the copies drift: ferdig's lacks the translation
check, nixploy-dashboard's rebinds four variables around its scenarios that
the template does not. Reviewed mode: a reviewer decides gates A and B,
Jonas gate C.

## Criteria

1. `tun.test-support` exports `define-generated-tests`; with `NAME` and
   `:package` it defines the five checks of `spec/testing.md` §1 in the
   current suite, each named `generated-…`, with the same assertions as
   the template's checks today.
2. Around each generated test and around each scenario the scenario test
   runs, `*program-handler*` and `*http-json-handler*` and every variable
   named in `:isolate (VARIABLE...)` are rebound to NIL. A test shows that
   a handler one scenario sets does not reach the next scenario, nor the
   next generated test.
2a. The scenario test runs only the scenarios defined in the client's
   package; a scenario of Tun's or of another system loaded in the image
   is not run. Tun's test client defines one scenario, so the test checks
   something there.
3. `tun new` writes the one form in `tests/tests.lisp`; `bin/test-cli`'s
   client passes with it, and a check that fails in a generated test names
   it (`generated-…`) in the client's output.
4. Tun's own test client (`tests/client/`) uses the form, so `bin/test`
   runs the generated tests.
5. ferdig, kurs and nixploy-dashboard replace their copies of the five
   checks with the form (the dashboard with `:isolate` for its own
   variables) and keep their own tests (such as ferdig's
   every-tool-is-listed-over-mcp); all pass. A gap the generated tests find
   in one, such as an unused catalogue entry, is fixed in that client, not
   skipped.
6. Each of the three clients' generated tests takes at most 30 s in its
   `bin/test`, measured and logged.

## Decisions

- A macro, not a function the client calls: the checks are FiveAM tests in
  the client's own suite, so they are listed, run and reported like the
  client's own, and `--only`-style runs keep working.
- The checks keep their assertions: this loop moves them, it does not
  change what they find. New checks are loops 3 to 6.
- Variables to isolate are named, not guessed: Tun knows its own; a
  client names its own once, beside the form.
- ferdig offers only Norwegian, its source language: the translation check
  has nothing to check there and passes, as the spec says.
- The clients' changes are committed in each client after gate B, with a
  Tun update. On origin all three are on Tun f487a26 (2.8.1) already; this
  loop changes only Tun's test support, which no server loads, so there is
  nothing to deploy and gate C covers pushing the clients' test changes.

## Log

- 2026-11-07 10:27  started, reviewed
- 2026-11-07 10:28  gate A asked of a reviewer
- 2026-11-07 10:30  gate A: changes (reviewer): Isolation must also rebind around each scenario, not only each test; name the handler variables; correct the decision on what the clients' Tun update ships; PACKAGE::*APPLICATION-CLASS*; risks: ferdig's own test stays, scenario-names lists every loaded scenario, test client has none, ferdig's unused-entries check
- 2026-11-07 10:30  gate A asked of a reviewer
- 2026-11-07 10:32  gate A: approve (reviewer): Earlier points answered; criteria decidable; spec agrees. Risks: preview.md 169-170 still names the old test; *scenarios* keyed by name only, so define-scenario must record its package and two clients' default must not collide; the isolation test must show NIL after a setf, not just a binding; make the dashboard's change on origin/main; fix ferdig's unused entries in ferdig
- 2026-11-07 11:01  built (by a builder agent): define-generated-tests in tests/generated.lisp, the five checks as GENERATED-… tests; scenarios keyed by package and name; isolation by progv around each test and scenario; bin/test now always starts Postgres for client suites. Removing the progv made the isolation tests fail (mutation check)
- 2026-11-07 11:01  clients against this tree (override): ferdig 753 checks pass, generated tests 1.5 s; kurs 296, 3.2 s; nixploy-dashboard 1138, 1.9 s (isolates *checkout-directory*, *service-settings*); no gaps found in them; bin/test-cli passed in 4 min 6 s
- 2026-11-07 11:07  verify 1: passed build, test, check
- 2026-11-07 11:07  shown (/items)
- 2026-11-07 11:07  gate B asked of a reviewer
- 2026-11-07 11:11  gate B: approve (reviewer): Criteria met: isolation proved by values, scenarios keyed by package with default coexisting, clients keep their own tests, template matches; verify green. Notes: clients' server build changes store path without a behaviour change; --only generated needs Postgres
- 2026-11-07 11:13  clients on a65d785, committed locally and tested: ferdig 753 checks, kurs 296, nixploy-dashboard 1138, all pass
- 2026-11-07 11:13  gate C asked of the person
- 2026-11-07 11:14  gate C: approve (jonas): «Push all three»
- 2026-11-07 11:14  pushed the clients: ferdig 8952173, kurs 8e9d480, nixploy-dashboard 544b309; no deploy (tests only)
- 2026-11-07 11:14  finished at tun a65d785
