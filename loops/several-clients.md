# A repository with several clients: one verify round, show and the gate packets cover each, and generated tests choose Postgres by the modules a client loads

- loop: several-clients
- mode: reviewed
- stage: done
- base: 4e349c6473419674cbb3478dc39d6d43096dd413
- item: sak_2qy4dngq8pfq4f3h
- estimate: 4h 6h 10h
- like: tun/workflow-planner tun/checks-under-load tun/client-modules
- tags: kind:tooling core
- verified: 5850af64d20fc5e871eb7bdf54c621930cb80565
- shown: 5850af64d20fc5e871eb7bdf54c621930cb80565

## Brief

Ferdig sak_2qy4dngq8pfq4f3h («A repository with two clients: verify,
show and the gates cover only the one at the top, and generated tests
pick Postgres only from the client's own tree»), filed by Jonas on
2026-11-16 and brought by the factory's orchestrator. The item, as
filed:

> Found by a client's loop on core 2.41.0 that added a second client in
> the same repository (`clients/NAME/` with its own `.asd`, sharing the
> repository's `modules/`).
>
> 1. **Verify, show and the gate packets cover only the client at the
>    loop's top.** `tun loop verify` runs `bin/test` and `tun check` at the
>    repository's top; the second client's browser checks were run by
>    hand (`tun check --dir clients/NAME`) on each verified tree and logged
>    by hand, and `tun loop show` and the reviewer's packet show only the
>    first client's pages. Wanted: a loop knows the repository's clients
>    (those `spec/testing.md` §1 already recognises by a `flake.nix` beside
>    an `.asd`) and verifies, shows and packs each; or `--dir` on verify
>    and show, recorded in the loop.
>
> 2. **Generated tests choose Postgres only from the client's own tree.**
>    A client that uses modules from beside it (a symbolic link `modules
>    -> ../../modules`) has its generated tests run on the in-memory
>    store, where an entity with a record policy that needs a query cannot
>    be read; and a client has no public way to ask which store it is on.
>    The loop moved a field off another module's entity because of it.
>    Wanted: the generated tests decide from the modules the client loads,
>    not from where their files lie; and an exported predicate a client
>    may call (modules have `store-runs-queries-p`; say whether a client
>    may use it).
>
> 3. Smaller: a second client needs a `flake.nix` that builds nothing,
>    only to be recognised, and a symbolic link to the modules so `tun
>    preview --dir` and `tun check --dir` find them. Wanted: a documented
>    layout for several clients in one repository that needs neither.
>
> Criteria, each decided by a test: in a repository with two clients,
> one verify round runs both suites and both sets of checks and fails if
> either fails; show takes pictures of a named client; the generated
> tests of a client that loads a module with a queried record policy run
> on Postgres; `docs/client-api.md` says how a second client is laid out.

The orchestrator's brief adds: one verify round runs every client's
suite and browser checks, fails if any fails and records which client
each result is of; `tun loop show` takes pictures of a named client; the
gate's packet names every client's results; a repository with one client
behaves exactly as today; the lock is taken once for the whole round, not
per client. For point 2, decide and document whether a client may call
`store-runs-queries-p`, or publish the right name. For point 3, `tun new`
or a short command that adds a second client in that layout if that is
small; if not, document the layout and leave the command out, saying so.
Also in this loop, the same runner: `tun check`'s `start-server`
(`src/cli/preview.lisp`) waits a fixed 5 s for a started server's pid
file, which fails on a loaded machine although the server starts, and
leaves the server running; make it wait as the check helpers wait (no
short fixed limit of its own) and stop the server it started when it
gives up, a test proving both. Every client of the installation passes
unchanged on this tree, and the two-client client repository's loop
verify, in a scratch copy, shows one round covering both clients. The
repository that needs this is a private client repository with two
clients; this record says «a client repository with two clients» and
uses its shape only as the model of the tests' own fixture. Mode
reviewed; push to main allowed; nothing deployed.

## Criteria

The repository's clients (`spec/loop.md` §6):

1. **Found.** In a client repository, the repository's clients are the
   loop's top and each directory `clients/CLIENT/` directly under it that
   holds an `.asd` at its own top, with a `flake.nix` or without, in the
   order of their names. A test with a fixture of the two-client shape
   (a top client with `modules/`, `clients/second/` with its own `.asd`,
   `bin/test` and `checks/`) finds both, with and without a `flake.nix`
   and a `modules` link in `clients/second/`; a repository of one client
   finds only its top; Tun's repository has no further clients, whatever
   its `clients/` holds. (test)
2. **One round runs every client.** In the fixture, `tun loop verify` runs
   one round of four steps: the top's `bin/test` and `tun check`, then
   `bin/test` and `tun check` in `clients/second/`, each in its client's
   directory; they are named `test`, `check`, `test:second` and
   `check:second` in the output, in `summary.txt` (with the directory
   each ran in), in the log's line and in the tracker's `steps`, and
   logged to `test.log`, `check.log`, `test-second.log` and
   `check-second.log`. A further client without browser checks has no
   `check:CLIENT` step. (test, with stand-in `bin/test`s and a stand-in
   `tun` on the path that record where and how they ran)
3. **Any failing client fails the round, and the record says which.**
   With only the second client's `bin/test` failing, the round fails, the
   stage goes back to `build`, the log's line is `verify N: failed
   test:second` and the tracker's `failed` is `["test:second"]`; the same
   for its checks alone (`check:second`); a further client with no
   `bin/test` fails `test:CLIENT`, its log saying so. (test)
4. **The lock once.** With `TUN_VERIFY_LOCK` naming a file, the round
   takes the lock once, before its first step: every step, the second
   client's included, runs with `TUN_VERIFY_LOCK_HELD` naming it while
   the lock is held (`flock -n` on it fails inside each step). (test)
5. **One client as before.** In a repository of one client, the round's
   steps are `test` and `check` as before, `show --client` is refused,
   and a gate's packet has the files it had. The loop tests that existed
   pass unchanged. (tests)
6. **Show a named client.** `tun loop show --client second` shows
   `clients/second/`: its preview, and its report, screenshots and link
   in `.build/loop/NAME/show/clients/second/`, and the log's line
   `shown clients/second (PATH, …)`. A show from `verified` clears all
   of `show/`; a later show of the same tree clears only the folder of
   the client it shows, so the top's and the second's pictures stand side
   by side. `--client` naming no further client, in a repository of one
   client or in Tun, is a usage error naming the clients. (test of the
   choice of client and folder and of the clearing, without a preview;
   and by hand, `show --client` in a scratch copy of the two-client
   client repository on this tree, its screenshots looked at, Log)
7. **The packet names every client's results.** At gate B the packet's
   README names the repository's clients; `verify.txt` lists each step
   with its client's directory; `checks/` holds the top's check results
   and `checks/second/` the second's (from `clients/second/.build/checks/`);
   `shots/` the top's show and `shots/second/` the second's; gate B's
   message gives each shown client's link. (test)

The layout without a flake or a link (`docs/client-api.md`):

8. **`tun loop` from the second client's directory.** Run in
   `clients/second/` without a `flake.nix`, `tun loop` acts on the top's
   loop; with one, on a loop of its own, as before. (test)
9. **Its server finds the repository's modules.** The server of a
   preview or a check of `TOP/clients/second/`, where TOP holds a client,
   names `TOP/modules/` in its source registry after the client's own
   directory and its own `modules/`, before the dev shell's and Tun's, on
   a pinned Tun and on a Tun worktree; a client at a repository's top, and
   a client in Tun's own `clients/`, get no such entry. (test)
10. **The first client leaves the second's files out.** The first
    client's generated test 2 leaves out the files under `clients/second/`
    without a `flake.nix` while no system of its `.asd` is loaded, and
    keeps a file there that a loaded system has as a component. (test,
    beside the one for a second client with a `flake.nix`)
11. **The layout is documented.** `docs/client-api.md` «Several clients in
    one repository» gives the files, the further client's
    `tests/run.lisp` source registry, its `bin/test`, the root flake's
    build of it, how preview, check, verify and show run it, what its
    generated tests check (and what neither client checks), and why `tun
    new` does not make one; `spec/loop.md` §6, `spec/preview.md` §2,
    `spec/testing.md` §1 and §2 and `docs/loop.md` §5 and §6 say the same.
    (review)

Postgres by the modules a client loads (`spec/testing.md` §2):

12. **The choice follows the enabled modules.** The generated tests run a
    client on Postgres when its package, or a package of a module its
    application enables (named and their dependencies; every loaded module
    when it names none), defines a query or an entity with a record
    policy, wherever the module's files lie; else in memory. Test: the test
    client's class (whose packages and modules define neither) is in
    memory; the same check with a module enabled whose package holds an
    entity with a record policy and whose files are in no client's tree
    is on Postgres. By hand: the two-client client repository's second
    client, whose modules lie beside it, runs its generated tests on
    Postgres on this tree (Log). (test, client run)
13. **A client may ask which store.** `application-runs-queries-p`, in
    `TUN` and `TUN.CORE`, is true for an application (default
    `*application*`) on Postgres and NIL on the memory and SQLite stores
    and with no application. A client's source calling it passes the
    public-interface check, and `store-runs-queries-p` stays out of `TUN`.
    `docs/client-api.md` («Record policies») and `spec/store.md` §6 item 7
    say so. (test)

The runner's start of a server (`spec/preview.md` §2):

14. **Waited for as long as the server is.** `start-server` waits for the
    started server's process to be known with the server's own deadline
    (`+ready-seconds+`, 180 s), not 5 s: a start whose fork is slowed 6 s
    returns the server's process, which runs. (test)
15. **Stopped when given up.** When the wait gives up (its deadline
    shortened in the test), `start-server` fails, and the command it
    started is not running then, nor a while after the slowed fork has
    written its file. (test)

Everything else:

16. **Clients unchanged.** factory, ferdig and nixploy-dashboard,
    kurs, and the two-client client repository's two clients pass their
    `bin/test` unchanged on this tree, one at a time under the verify
    lock. In a scratch copy of the two-client client repository, on this
    tree, with its second client's `flake.nix` and `modules` link removed,
    one `tun loop verify` round runs both clients' suites and checks
    (its summary names `test:CLIENT` and `check:CLIENT`), and `show
    --client` takes the second's pictures. Nothing is pushed or changed in
    that repository. (client runs, Log)
17. **Core 2.46.0** (`+core-version+`, `coreVersion`); `bin/build`
    warning-free, `bin/test` and `bin/check` green. (verify)

## Decisions

- **Which directories are the repository's clients.** The item asks for
  «those `spec/testing.md` §1 already recognises»: a directory with a
  `flake.nix` and an `.asd` none of whose systems is loaded. That rule
  also matches a module the client does not enable (a `flake.nix` and a
  `tun-NAME.asd`), and it is the `flake.nix` that point 3 wants gone. So
  a further client is a directory `clients/CLIENT/` directly under the
  loop's top holding an `.asd` at its own top, with a `flake.nix` or
  without: the place the item and the client repository use, and one
  rule for the old layout and the new. Anywhere else a second client is
  not a loop's (it never was); `docs/client-api.md` names `clients/`.
  Tun's own repository is left out: its `clients/` holds clients a
  person added locally, and a loop in Tun names its client with
  `--client` at start, as before.
- **Steps named by client, the top's unchanged.** A further client's
  steps are `test:CLIENT` and `check:CLIENT` (CLIENT the directory's
  name), logged to `test-CLIENT.log` and `check-CLIENT.log`, so the log's
  line, `summary.txt` and the tracker say whose step failed without a
  new field. The top's stay `test` and `check`, so a repository of one
  client, and the tracker's readers, see what they saw.
- **Each client's own `bin/test` and `tun check`, in its directory.**
  The further client's suite is its own program, as the top's is; verify
  runs it rather than knowing how a client is tested. A further client
  without `bin/test` fails its step rather than being skipped: a client
  whose suite verify cannot run is not verified. Checks are run only
  where there are some, as for the top.
- **The lock: the round's, once.** The round already holds the verify
  lock around all its steps and sets `TUN_VERIFY_LOCK_HELD` for them
  (`checks-under-load`), so a further client's `tun check` runs inside
  the same hold; nothing new takes it.
- **Show: `--client CLIENT`.** `tun loop` already takes `--client` (at
  start, in Tun, the client a change is shown in); at show it names which
  of the repository's clients to show, the same meaning for one show. A
  further client's pictures go to `show/clients/CLIENT/`, so they stand
  beside the top's, which stay in `show/` where the packet, status and
  gate B have always read them. The first show on a verified tree clears
  `show/` as today; a later show of the same tree replaces only its own
  client's folder. A show of every client is not required: the builder
  shows the clients the change reaches (`docs/loop.md` §6).
- **The packet.** Each further client's results go to `checks/CLIENT/`
  and `shots/CLIENT/`, beside the top's in `checks/` and `shots/`, so
  the reviewer sees whose results they are; the README names the
  repository's clients, and `verify.txt` (the round's summary) names
  each step's client.
- **The tree leaves out what tun writes in a further client.** A further
  client's `tun check` and preview write `clients/CLIENT/.build/` and
  `.data/`; the usual `.gitignore` ignores them at any depth, but one that
  anchors them at the top (`/.build/`) would make the tree change between
  verify and show. So the loop's tree leaves out `clients/*/.build` and
  `clients/*/.data` as it leaves out the top's.
- **The server finds the repository's modules, not a link.** A preview's
  or a check's server of `TOP/clients/CLIENT/`, where TOP holds a client
  (a `flake.nix` and an `.asd`) and is not Tun's repository, gets
  `TOP/modules/` in its source registry after the client's own directory
  and own `modules/`. With an old link in place both name the same
  directory, which ASDF takes once.
- **The second client's generated tests.** With no link, the
  repository's modules are not under the second client's tree, so they
  are not its own modules (test 10), as they were not with the link
  either (the link resolves outside its tree): the first client checks
  them as modules, fuzzes their tools and checks their translations. The
  first client's sources leave `clients/CLIENT/` out when no system of
  its `.asd` is loaded, as a directory with a `flake.nix` was. A module
  only a further client enables is checked as a module by neither; the
  docs say so (enable it in the first, or keep it out of `modules/`).
- **Postgres by the enabled modules.** `needs-postgres-p` looked at the
  client's package and its own modules' (those under its tree). It now
  looks at the client's package and the packages of every module the
  application enables, with their dependencies (`enabled-modules`'s
  rule: every loaded module when the class names none). Tun's own modules
  define no query and no entity with a record policy, so no client that
  enables only Tun's modules moves to Postgres; a client whose modules
  lie beside it does, as one with them in its tree did.
- **The name a client asks with: `application-runs-queries-p`.**
  `store-runs-queries-p` is a generic function of a store, in `TUN.CORE`,
  the modules' interface; a client cannot reach a store (`application-store`
  is not in `TUN`), so publishing it alone would not answer the question,
  and publishing the store would hand a client the adapter. So `TUN`
  publishes one predicate of an application, `(application-runs-queries-p
  &optional (application *application*))`, true on Postgres, NIL on the
  memory and SQLite stores and outside an application; `TUN.CORE`
  exports it too, so a module may ask the same way. A client may not
  call `store-runs-queries-p`, and the docs say so.
- **No `tun new` for a further client.** `tun new` writes a repository
  with its own flake, lock, dev shell and `.envrc`, and `tun add` and
  `tun update` edit a client's flake; a further client has none of these
  and is built by the root flake, whose shape is the client's own (which
  modules each client takes, which images). Writing its files is easy,
  but a command that also edits the root flake, and that `tun add` must
  then understand, is not small. So the layout is documented, with what
  to copy, and the command is left out; the report says so.
- **`start-server` waits within the server's own deadline.** The pid
  file is written by the shell `setsid --fork` starts, before it becomes
  the server; on a busy machine the fork took more than the 5 s that
  `start-server` gave it (`workflow-planner`, two loaded rounds), though
  the server then started and kept running with no one to stop it. It now
  waits as long as `wait-until-ready` waits for an answer
  (`+ready-seconds+`, 180 s), the one deadline a start has. When it gives
  up, it leaves a file beside the pid file that tells the starting shell
  not to become the server, then reads the pid file once more: a shell
  that wrote its pid before that is stopped by its pid; one that writes
  it after finds the file and ends without starting the server. The
  shell writes its pid, then looks for the file, so one of the two
  always happens.
- **The proof in a client repository.** A scratch copy (a clone) of the
  two-client client repository, its Tun inputs overridden with this
  worktree, with its second client's `flake.nix` and `modules` link
  removed, runs a loop of its own to verify and show; its top `bin/test`
  still runs the second's suite too (its own choice, which its next loop
  can drop, since verify now runs each), so that suite runs twice there.
  Nothing is pushed or changed in the client repository itself.
- **Estimate.** 4h / 6h / 10h: `workflow-planner` (6h52) and
  `checks-under-load` (14h41, mostly waiting and proof) were the last
  loops in the same runner; this one has more code than the first and
  less proof than the second, but five clients' runs and a scratch
  client's verify under a lock two other builders share.
- **The generated tests say which store.** That a client whose modules
  lie beside it runs on Postgres has to be read from its own run, and no
  summary said which store it was; the fuzzing test now prints one line,
  «The generated tests of NAME run on Postgres» (or «in memory»), before
  its summary.
- **A further client's directory by its truename.** Verify runs a further
  client's `tun check` in that client's directory, where `tun` names it
  `.`; the path then ends in a component `"."`, which hid the
  `clients/NAME/` it is in. `repository-modules` reads the directory by
  its truename (found by the proof below).
- **What the test of `start-server` leaves out.** It slows the starting
  shell before it writes its id, so the give-up finds no id and the shell
  ends on the given-up file; the other branch, an id written between the
  deadline and the given-up file, cannot be timed in a test, and is the
  same `stop-process` that stops a server that does not answer.

## Verify rounds

1. Passed (build, test, check), after 54 minutes for the verify lock; its
   tree lacked only gate B's message for a show of a further client
   alone.
2. Failed `test`: three suites under load (29 on 12 processors), each
   unrelated to the change and each passing alone right after (Log).
3. Passed, after 81 minutes for the lock.
4. Passed, with the generated tests saying which store they run on.
5. Passed, with the fix the proof in the client repository found
   (below), after 81 minutes for the lock.

## The proof in a client repository

A clone of the two-client client repository in a scratch folder, at its
`origin/main`, with one commit of its own that removes its second
client's `flake.nix` and `modules` link (the layout of
`docs/client-api.md`), its Tun inputs overridden with this worktree's
commit, ran a loop of its own (hands-on, its stage set to build by hand:
it proves the runner, and no gate of it is decided) with `tun loop
verify` under the machine's lock, without a tracker or a reviewer. Its
top's `bin/test` still runs the second client's suite as well, so that
suite runs twice there. Below, SECOND is its second client's name.

- Rounds 1 (at 8449be57) and 2 (at e66dfac1): `test` (the first
  client's suites and the second's), `check` (the first client's checks)
  and `test:SECOND` passed; `check:SECOND` failed in 7 to 8 s, its first
  preview's server stopping while it loaded the second client's tests.
  The same eight checks passed run from the repository's top (`tun check
  --dir clients/SECOND`). Run in the client's own directory, `tun check`
  names it `.`, and its path ended in a component `"."`, so
  `repository-modules` did not see `clients/NAME/` and the server's
  source registry had no modules. It now reads the directory by its
  truename; the preview test names the directory that way, failed before
  the fix and passes after.
- Round 3 (at 5951201a): Log.

## Clients

Each client's `bin/test`, from a clone of its `origin/main` in a scratch
folder, its Tun inputs (`tun`, and `dashboard` and `customers` at their
`modules/` directories) overridden with this worktree's commit, one at a
time under the verify lock, unchanged:

- at `bc86e7d1` (the change as verified in round 1, but for gate B's
  message, the store line and a further client's path, none of which a
  client's suite reaches): factory 773 checks, ferdig 812,
  nixploy-dashboard 1421 (tunworks `85e42b57`); kurs 352 (`a82a83d0`);
  the two-client client repository (`de467cbc`), its first client's
  suites (9387, 207, 65375, 390, 387, 373, 8856, 255, 109920, 91147,
  16264 and 27339 checks) and its second client's (145): every one exit
  0, no compiler warning, no failure;
- at `e66dfac1` (with the store line), the two-client client repository
  again: exit 0, no compiler warning, and its output says that the
  generated tests of each of its two clients run on Postgres: the second,
  whose modules lie beside it, among them (criterion 12).

What a client repository with several clients does differently on core
2.46.0:

- `tun loop verify` at the top runs, after the top's `bin/test` and `tun
  check`, `bin/test` and `tun check` in each `clients/NAME/`, named
  `test:NAME` and `check:NAME`; a top `bin/test` that also runs the
  second client's suite makes that suite run twice, so it can run only
  its own.
- The second client's checks need no hand-run `tun check --dir
  clients/NAME` and no hand-written log line; `tun loop show --client
  NAME` takes its pictures; the packets hold its results in
  `checks/NAME/` and `shots/NAME/`.
- `clients/NAME/flake.nix` and `clients/NAME/modules` can go; then `tun
  loop` run in `clients/NAME/` finds the top's loop, and `tun preview
  --dir clients/NAME` and `tun check --dir clients/NAME` (or `tun check`
  in that directory) find the top's `modules/`.
- The second client's generated tests run on Postgres when a module it
  enables needs it, and say so; `application-runs-queries-p` is a
  client's question for which store it is on.

## Pictures

Nothing a person sees in Tun's showcase changes. `tun loop show --path
/` after verify 5 took the showcase's graph page at 390 and 1280 px,
which looks as before. A further client's pictures are the client
repository's (the proof above).

## Actuals

```json
{"loop":"several-clients","title":"A repository with several clients: one verify round, show and the gate packets cover each, and generated tests choose Postgres by the modules a client loads","repository":"tun","mode":"reviewed","stage":"done","item":"sak_2qy4dngq8pfq4f3h","tags":["kind:tooling","core"],"like":["tun/workflow-planner","tun/checks-under-load","tun/client-modules"],"started":"2026-11-16 17:59","ended":"2026-11-17 03:27","minutes":{"total":568,"waiting_person":0,"waiting_reviewer":2,"working":566,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":240,"likely":360,"worst":600,"at":"brief"},"latest_estimate":{"best":240,"likely":360,"worst":600,"at":"brief"},"within_estimate":true,"ratio":1.58,"verify":{"rounds":5,"failed":1},"changes":{"A":0,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-16 17:59  started, reviewed
- 2026-11-16 18:00  estimated 4h 6h 10h at brief, like tun/workflow-planner tun/checks-under-load tun/client-modules
- 2026-11-16 18:04  gate A asked of a reviewer
- 2026-11-16 18:05  gate A: approve (reviewer)
  I'm reviewing gate A of the several-clients loop: whether the criteria cover the brief, whether each can be tested, and whether the spec change agrees with them.
  
  **The criteria cover the whole brief, and nothing beyond it:**
  - **Point 1 (verify, show and packets cover every client)**
    - One verify round runs every client's suite and browser checks, with each step named after its client (C2).
    - A failure in any client fails the round, and the log and tracker say which client failed (C3).
    - The verify lock is taken once for the whole round (C4).
    - A repository with one client behaves as before (C5).
    - `show --client` shows a named client (C6).
    - The gate packet names every client's results (C7).
  - **Point 2 (Postgres by the modules a client loads)**
    - The generated tests choose Postgres from the modules the application enables, wherever their files lie (C12).
    - The brief asked for "the right name" if `store-runs-queries-p` was wrong for clients. `application-runs-queries-p` is that name, and it has a sound reason: a client can't reach a store. `store-runs-queries-p` stays out of `TUN` (C13).
  - **Point 3 (a layout with no `flake.nix` or `modules` link)**
    - `tun loop` run in the second client's directory finds the top's loop (C8).
    - The second client's server finds the repository's `modules/` without a link (C9).
    - The first client's generated tests leave the second client's files out (C10).
    - The layout is documented (C11).
    - There is no `tun new` command for it. The brief explicitly allowed leaving it out with a reason, and the reason given (it would have to edit the root flake, and `tun add` would then need to understand that) is sound.
  - **The `start-server` fix:** it waits up to the server's own 180 s deadline instead of a fixed 5 s (C14), and stops the server it started when it gives up (C15). Each has a test.
  - **Proof against real clients:** every client of the installation passes its `bin/test`, and a scratch copy of the two-client repository shows one verify round covering both clients (C16).
  
  **Each criterion can be decided:** C1–C10 and C12–C15 by named tests with concrete fixtures and observable results (step names, log names, `failed` arrays, `flock -n`, a 6 s slowed fork). C11 is decided by review. C16 and C17 are decided by client runs and verify.
  
  **The spec change says the same as the criteria:**
  - `spec/loop.md` §6 has the client rule, step names, log files, lock, `show --client` and packet layout.
  - `spec/preview.md` §2 has the second client's source registry and the start deadline.
  - `spec/testing.md` §1 test 2 and §2 have the source exclusion and the Postgres choice. §4 and §5 already defer to §2's choice, so "the same choice holds for §4 and §5" is consistent.
  - `spec/store.md` §6 item 7 has the new predicate.
  - The docs (`client-api.md` "Several clients in one repository" and "Record policies", `docs/loop.md` §5 and §6) agree with all of it.
  
  **None of the Decisions needed to go back to the asker:**
  - **Which directories are clients.** The item said "those §1 already recognises", which requires a `flake.nix`. The builder narrowed this to `clients/*/` with or without a `flake.nix`. That follows directly from point 3, which wants the `flake.nix` gone, and from the layout the item itself describes.
  - **A module only the second client enables is checked as a module by neither client.** This isn't a regression (with the old link it was the same), and the docs say so. The asker may still want to know about it.
  
  **Non-blocking points to cover at gate B:**
  - **C6, show in the other order.** The tests should also cover showing the top again after the second client: `show/clients/` must survive it. The spec's wording ("replaces only the pictures of the client it shows") covers this, but the criterion's example only gives one order.
  - **C7, packet layout.**
    - The packet's top-level `shots/` shouldn't also copy `show/clients/`, or the second client's pictures appear twice.
    - `checks/CLIENT/` mustn't clash with any folder the top's own check results already contain.
  - **Test lists.** `spec/store.md`'s test list (around line 341) and `spec/testing.md` don't yet name the tests for C12 and C13, unlike `spec/loop.md` and `spec/preview.md`, which got entries.
- 2026-11-16 19:30  verify 1: passed build, test, check
- 2026-11-16 20:37  verify 2: failed test
- 2026-11-16 20:41  verify 2 failed three suites under load (load 29 on 12 processors in its test step): search's two-thousand-customers-are-searched-within-100-ms (the search's own 10 s deadline exceeded), safety's a-large-multipart-post-needs-a-person-the-page-admits (a socket I/O timeout), waiting's a-wait-outlasts-two-rechecks-in-real-time (15.69 s, not under 14 s, wall time). None touches this loop's change; each passed alone right after (search 32336, safety 193, waiting 54 checks) at loads 6 to 10. Verify 1 (same code but gate B's message) passed them all.
- 2026-11-16 22:17  verify 3: passed build, test, check
- 2026-11-16 22:18  shown (/)
- 2026-11-17 00:14  verify 4: passed build, test, check
- 2026-11-17 00:15  shown (/)
- 2026-11-17 01:08  the scratch copy of the two-client client repository (its second client's flake.nix and modules link removed) ran its loop's verify on this tree twice (at 8449be57, then at e66dfac1): test, check and test:SECOND passed, check:SECOND failed both times in 7 to 8 s, its server stopping before it loaded the second client's tests; the same checks passed 8 of 8 run from the repository's top (tun check --dir clients/SECOND). Cause: verify runs a further client's tun check in that client's directory, where tun names it ., whose path ends in a component ".", so repository-modules did not see clients/NAME/ and the server got no modules. Now it reads the directory by its truename; a test names the directory so and failed before the fix (a type error), passes after.
- 2026-11-17 02:44  verify 5: passed build, test, check
- 2026-11-17 02:45  shown (/)
- 2026-11-17 03:25  the scratch copy of the two-client client repository, round 3 of its loop's verify on this tree at 5951201a: one round, under one hold of the lock (taken after 95m47s), ran test (724 s, the first client's suites), check (1534 s, the first client's checks), test:SECOND (36 s) and check:SECOND (90 s, its 8 checks), every one ok; its summary names the last two «in clients/SECOND/». Then tun loop show --client SECOND --path / took the second client's home page at 390 and 1280 px into show/clients/SECOND/, logged «shown clients/SECOND (/)»; looked at: its today page, readable on a phone. (SECOND stands for the second client's name, which is the client repository's.)
- 2026-11-17 03:25  clients at bc86e7d1: factory 773, ferdig 812, nixploy-dashboard 1421 (tunworks 85e42b57), kurs 352 (a82a83d0), the two-client client repository's both clients (de467cbc; 12 suites of the first, 145 checks of the second): each bin/test exit 0, no compiler warning, unchanged; at e66dfac1 the two-client client repository again, exit 0, each of its clients' generated tests saying it runs on Postgres
- 2026-11-17 03:26  gate B asked of a reviewer
- 2026-11-17 03:27  gate B: approve (reviewer)
  I'm approving this gate. Every criterion has a test that would fail without the change or proof logged by hand, all three verify steps passed, and the code follows `AGENTS.md`. I found nothing that needs changing.
  
  **Criteria and their tests** (all in `diff.patch`)
  - **C1, C8 (finding the clients):** `a-repository-s-further-clients-are-in-its-clients-directory` covers the second client with and without a `flake.nix`/`modules` link. It also covers a repository of one client, a `clients/` folder with no `.asd`, Tun's own repository, and which loop `tun loop` finds when run in `clients/second/` (diff.patch:1154–1181).
  - **C2–C4 (the verify round):** `one-verify-round-runs-every-client-and-names-whose-step-failed` uses stand-in `bin/test` and `tun` scripts that record where they ran. It checks:
    - the four steps, each run in its own client's directory;
    - the exact `summary.txt` with `in clients/second/`;
    - the four log names;
    - the tracker's `steps` and `failed`;
    - the log lines for a failing test, a failing check and a missing `bin/test`;
    - `flock -n` failing inside every step, which shows the lock is held once around them all.
  - **C5–C7 (one client, show and the packet):** `a-show-of-a-named-client-has-a-folder-of-its-own` covers:
    - which client and folder a show picks, and refusing a name that is no client's (with the clients named), in a repository of one client and in Tun;
    - the clearing order top → second → top again, which gate A asked for;
    - packet paths `checks/second/` and `shots/second/`, with no duplicate `shots/clients/`;
    - the README, `verify.txt` and gate B's message with both links;
    - a repository of one client: summary, README and `checks/` unchanged.
  - **C9:** the preview test checks the registry order on a pinned Tun and on a worktree. It includes the `.`-ending path that the client-repository proof found. A repository's top, Tun's own `clients/`, and a directory with no client get no entry.
  - **C10:** the module-system test checks that `further.lisp` is left out, while `kept.lisp` (a component of a loaded system) and `notes.lisp` (no `.asd`) stay in.
  - **C12, C13:** the record-policy tests cover:
    - `application-runs-queries-p` in memory, on SQLite, on Postgres and with no application;
    - the public-interface check, and `store-runs-queries-p` staying out of `TUN`;
    - Postgres chosen only once a loaded, enabled module defines a record policy.
  - **C14, C15:** with the server's start slowed 6 s, the server is still waited for and runs. With the start slowed past a 1 s deadline, the start fails and neither the server nor its starting shell is left running. The "given-up" file closes the race in either order, and the code comment explains how.
  - **C11, C16, C17:** the docs and the spec sections agree. The client runs and the scratch two-client round 3 (four steps, one hold of the lock, `show --client` looked at) are in the Log. The core version is 2.46.0 in both places.
  
  **Brief:** all three points are met. Leaving out a `tun new` command for a further client is explained in `docs/client-api.md`. The `start-server` fix is in.
  
  **Code:** it's readable and has no debugging leftovers. Comments say why, not history. The one special case, the `/` test in `run-verify-step` for a missing `bin/test`, is explained in its docstring. The spec changed wherever the behaviour did.
  
  **Verification:** `verify.txt` round 5 shows build, test and check all `ok`. Tun's own screenshot (the showcase graph page) is unaffected, as expected. The second client's pictures belong to the client repository and are logged.
  
  **Non-blocking notes:**
  - C12 names "the test client's class". The test uses its own `store-choice-client`, which has the same property (enables only `customers`). It proves the same thing.
  - `needs-postgres-p` now skips an enabled module that isn't loaded (`find-module name` without erroring), where it used to error. That is reasonable and tested, but now the generated tests won't complain about it.
  - `spec/testing.md`'s test list doesn't name the new test-2 and Postgres-choice tests, although `spec/store.md` does name the Postgres-choice one.
- 2026-11-17 03:27  finished at tun 6ba559ed
