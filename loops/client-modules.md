# A module kept in a client's repository passes the checks and previews from the working tree

- loop: client-modules
- mode: reviewed
- stage: done
- base: 9eaab707e7eb2650a1f5313863b37eca21103041
- client: /home/jonas/coding/tun-erp-wt/module-layout
- client-base: 024eb4f6a4493f1262817d021376468d89d3f8e8
- item: sak_wqn3k1gzq3jrke7v
- estimate: 1h30m 2h30m 5h
- like: tun/client-checks tun/fuzz tun/sequences tun/page-smoke
- tags: kind:testing module:test-support
- verified: 7824a905e1e78a7c92c8202e79e0c9ab4fab42ab 423d8842869f76abbff5b4a47cd39840905914b6
- shown: 7824a905e1e78a7c92c8202e79e0c9ab4fab42ab 423d8842869f76abbff5b4a47cd39840905914b6

## Brief

Ferdig sak_wqn3k1gzq3jrke7v, made for Tun ERP's first component,
module-layout (sak_ww8v48fcjw07drxb), which
stopped at Tun d4cdbfa: a module kept in a client's repository at
`modules/company/` builds, opens and is a module in the registry, but the
client's generated test `generated-the-sources-use-only-tuns-public-interface`
reads its files as client code (`client-files-under`, tests/support.lisp)
and fails on `(:use #:tun.core)` and `in-package`; nothing checks such a
module as a module; and `tun preview` loads it from the dev shell's store
build, as old as the shell.

The orchestrator of the software factory, 2026-11-10, on Jonas's standing
approval of Tun changes for this work: «fix it in Tun, then finish
module-layout in tun-erp with the repository layout unchanged (client at
the root, modules in `modules/`)»; «a module may live in a client's
repository as `modules/NAME` (package `TUN.NAME`, system `tun-NAME`), and
Tun's generated tests, strict compile and preview treat it as a module»,
with the five points of module-layout's record: the client check leaves the
client's modules out, a generated test checks them as modules,
`module-violations` and the convention it relies on, preview from the
working tree («a builder must see the tree it verified»), and the spec.
«Include a test client fixture with a module of its own so Tun's suite
holds this from now on, and say in the spec how a second client in the
same repository is kept out of the first client's check if that is cheap.»

## Criteria

1. A client that keeps a module at `modules/NAME/` (a `flake.nix`,
   `tun-NAME.asd`, package `TUN.NAME`) and enables it passes
   `generated-the-sources-use-only-tuns-public-interface`: none of the
   module's files is read as the client's.
2. A new generated test, `generated-the-client-s-modules-use-only-public-interfaces`,
   checks each of the client's own modules by the module rules: a `::` into
   a Tun package in one of its files fails it, naming the file; a file
   under the module's `tests/` is not checked; and the test fails, naming
   both directories, when the module is loaded from anywhere but its
   directory in the client's tree.
3. A directory under the client's that holds a `flake.nix` and at least
   one `.asd`, none of whose systems is loaded (a second client, a module
   the client does not enable), is left out of the client's source check.
   A file a loaded system other than the client's own modules' has as a
   component is always checked as the client's, wherever it lies: a
   planted `::` in such a file, beside a `flake.nix` and an unused `.asd`,
   fails the check. A directory with a `flake.nix` and no `.asd` is not
   left out.
4. The generated fuzzing, record-policy and sequence tests take the tools
   of the client's own modules with the client's, and the translation test
   their texts.
5. `module-violations` finds a module's files as the source directory of
   its system `tun-NAME`, and says so when there is no such system. It
   leaves out the files under a module's `tests/`, for Tun's modules as
   for a client's (none of Tun's has a `tests/` today).
6. `tun preview`, from a client's dev shell and with `bin/tun preview
   --dir` on Tun's working tree, names the client's `modules/` in the
   source registry before anything else: the preview serves the working
   tree's module, uncommitted changes too.
7. A client from `tun new` builds every `modules/*/flake.nix` module of its
   own, pinned at its commit; its dev shell does not carry them from the
   store; its `bin/test` compiles them strictly from the working tree, so a
   compiler warning in a module file fails it, and runs each module's own
   tests (`tun-NAME/tests`, whose package `TUN.NAME.TESTS` exports
   `RUN-TESTS`) after the client's.
8. Tun's test client (`tests/client/`) keeps a module of its own,
   `logbook`, and enables it: Tun's `bin/test` runs the test client's
   generated tests over it, and a test of the test client sees a planted
   `::` in a copy of it fail the module check, naming the file.
9. `bin/test-cli` takes a new client through criterion 7's path: a module
   under `modules/` with tests of its own, built and tested (its tests
   run), a planted `::` and a planted warning
   each failing `bin/test`, and a preview showing a definition added to the
   module after the shell was entered as the module's.

10. A client's own module may not take the name of one of Tun's modules:
   `generated-the-client-s-modules-use-only-public-interfaces` fails for
   such a module, naming it and Tun's, and `buildModules` refuses two
   modules of one name, naming both sources, so a client that pins Tun's
   module of that name cannot build either.

## Decisions

- **The names are the contract.** A client's module is `modules/NAME/`
  with system `tun-NAME` and package `TUN.NAME`, the shape of Tun's own.
  Tun already depends on both names: `module-violations` finds a module by
  its system `tun-NAME`, and only a `TUN.*` package is `"source": "core"`
  and a module package to the interface check of its dependants. Writing
  that down (tun-platform.md §2.1) is cheaper and clearer than teaching the
  checks a second naming, and it lets such a module move into Tun's
  `modules/` unchanged. `module-violations` gets a clear error when the
  system is missing (criterion 5) rather than a search by location.
- **Which directories are left out of the client's check**: those of its
  own modules (a `flake.nix` and `tun-NAME.asd` with NAME a loaded
  module), and any with a `flake.nix` none of whose `.asd` systems is
  loaded. The second rule keeps a second client of the same repository
  out (Tun ERP's later `clients/service-trade`), at the cost of a
  directory listing. A loaded system in such a directory that is not a
  module stays the client's, so moving client code under a `flake.nix`
  does not escape the check.
- **A module's `tests/` is not its source**, as a client's `tests/` is
  not: the module check leaves it out, so a module can keep its own suite.
  It holds for Tun's modules as well; none has a `tests/`.
- **What the client loads is the client's.** The files that a loaded
  system, other than one of the client's own modules', has as components
  stay in the client's check wherever they are, so a directory cannot be
  made to look like a second client to hide them (gate A, reviewer). A
  directory is taken for another client only with a `flake.nix` and at
  least one `.asd`.
- **Tun's module names are reserved.** The client's `modules/` comes
  ahead of everything in the source registry, so a client module named
  `orders` would quietly stand in for Tun's in `bin/test` and the preview.
  The test support keeps the names of Tun's modules as a list, which a
  test of Tun's suite holds equal to `modules/`; the generated module test
  refuses a client module of one of those names, and `buildModules`
  refuses two modules of one name.
- **Loaded from its directory.** The module check reads the files of the
  module's directory in the client's tree and fails when the loaded
  system is somewhere else: a check of the store's copy would pass a
  working tree it never read.
- **The client's modules are the client's tools.** Tun fuzzes and
  policy-checks its own modules in its own suite; nobody would for a
  client's. The generated fuzzing, record-policy and sequence tests take
  their operations, and the translation test their texts, with the
  client's (criterion 4).
- **The dev shell leaves them to the working tree.** The template's flake
  passes the client's modules to `buildClient` only, not to
  `clientShell`, and `clientShell` adds `$PWD/modules//` to the source
  registry: with no store copy, every load in the shell (an editor,
  `bin/serve`) takes the working tree. `tests/run.lisp` still registers
  `modules/` first and compiles each `modules/*/tun-*.asd` system
  strictly, so a client whose flake gives its modules to the shell too is
  tested on its tree.
- **The test client's module** is `logbook` (a note per order, by the
  staff), small and with a name Tun is unlikely to take; it changes the
  test client's module list in its composition test.
- **Core version 2.19.0**: a minor version (the test support, the
  template, `clientShell` and the preview change; nothing is renamed).
  2.18.0 went to ui-graph while this loop was at gate B; the rebase took
  the next one.
- **Shown** in Tun ERP's module-layout worktree (`--client`), whose module
  company the preview loads from the working tree.

## Actuals

```json
{"loop":"client-modules","title":"A module kept in a client's repository passes the checks and previews from the working tree","repository":"tun","mode":"reviewed","stage":"done","item":"sak_wqn3k1gzq3jrke7v","tags":["kind:testing","module:test-support"],"like":["tun/client-checks","tun/fuzz","tun/sequences","tun/page-smoke"],"started":"2026-11-10 09:06","ended":"2026-11-10 10:44","minutes":{"total":98,"waiting_person":0,"waiting_reviewer":6,"working":92,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":90,"likely":150,"worst":300,"at":"brief"},"latest_estimate":{"best":90,"likely":150,"worst":300,"at":"brief"},"within_estimate":true,"ratio":0.65,"verify":{"rounds":4,"failed":0},"changes":{"A":1,"B":1,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-10 09:06  started, reviewed
- 2026-11-10 09:10  estimated 1h30m 2h30m 5h at brief, like tun/client-checks tun/fuzz tun/sequences tun/page-smoke
- 2026-11-10 09:10  gate A asked of a reviewer
- 2026-11-10 09:11  gate A: changes (reviewer)
  I'm asking for changes. The criteria cover the brief and the spec says what they say, but the second-client rule has a hole that undoes a promise the builder makes in **Decisions**, and one new risk has no criterion.
  
  **What is right**
  - **The brief is covered.** All five points from module-layout's record map to criteria:
    - the client check leaves its modules out: C1 and C3;
    - a generated test checks them as modules: C2;
    - `module-violations` and the naming convention: C5 and tun-platform.md §2.1;
    - preview from the working tree: C6;
    - the spec: the diff itself.
  - **The extras the brief asked for are covered too.** The test client fixture is C8, and how a second client is kept out is C3 plus testing.md test 2.
  - **C7 and C9 are in scope.** Strict compile is in the brief. The template's flake has to build `modules/*` or the layout can't ship.
  - **Each criterion can be decided by a test**, and the spec text matches the criteria:
    - testing.md tests 2 and 10, plus the paragraph on tests 4, 6, 7 and 8 (whose numbers are right);
    - preview.md §2.3;
    - cli.md §6 and the new step 6 of `bin/test-cli`;
    - tun-platform.md §2.1.
  - **C4 is a fair call to make without asking.** Fuzzing a client's own modules with the client's tools goes slightly against "treat it as a module". But no other suite would fuzz them, and the choice is written down.
  - **The naming contract is the cheaper, clearer choice.** Fixing `tun-NAME` and `TUN.NAME` matches what `module-violations` (tests/support.lisp:617) and the `TUN.*` source rule already assume.
  
  **Changes**
  
  1. **Client code can still escape the source check.** This contradicts **Decisions** ("moving client code under a `flake.nix` does not escape the check").
     - **The hole:** under C3 and testing.md lines 20–24, a directory is left out when it holds a `flake.nix` and `.asd` files none of whose systems is loaded. A directory with a `flake.nix`, an unused `dummy.asd`, and `.lisp` files that the client's own `.asd` lists as components meets that test, so the check skips those files even though the client loads them.
     - **A second, smaller case:** a directory with a `flake.nix` and no `.asd` at all meets "none of whose systems is loaded" with nothing to check.
     - **Fix:** add to C3, and to testing.md test 2, that a file which is a component of a loaded system of the client's always stays the client's. Also require at least one `.asd` before a directory is left out.
     - **Cost:** small. The client's ASDF component tree is already loaded. It is also checkable: a planted `::` in such a file must still fail test 2.
  
  2. **A client module with a Tun module's name has no check.** tun-platform.md (new text, end of §2.1) says "Its name, tools and paths must not be one of Tun's", but no criterion enforces it.
     - **Why it matters here:** cli.md, preview.md and the **Decisions** all register the client's `modules/` *ahead of* Tun's in the source registry.
     - **The risk:** a client module named, say, `orders` would quietly replace Tun's `tun-orders` in `bin/test` and the preview, while `nix build` might not.
     - **Fix:** add a criterion saying what refuses this and naming both directories, either the C2 generated test or the build. The spec line should then point to it.
  
  3. **Say whether Tun's own modules keep their `tests/` checked.** Today `module-violations` reads `**/*.lisp` under the module, `tests/` included (tests/support.lisp:623).
     - C2 and the decision "A module's `tests/` is not its source" drop `tests/` for client modules.
     - If the change goes through `module-violations`, Tun's own modules lose that coverage too, and nothing says so.
     - **Fix:** state in C5 (or C2) whether the exclusion applies to Tun's modules, so a test can hold it either way.
- 2026-11-10 09:13  gate A asked of a reviewer
- 2026-11-10 09:14  gate A asked of a reviewer
- 2026-11-10 09:15  gate A: approve (reviewer)
  Approve. All three changes from the last round are in the criteria and the spec, and nothing new turned up.
  
  **The previous round's changes are addressed**
  1. **The second-client hole is closed.** Criterion 3 now does three things:
     - A file that a loaded system (other than one of the client's own modules) has as a component is always checked as the client's, wherever it lies.
     - A directory is left out only if it holds a `flake.nix` *and* at least one `.asd`.
     - A directory with a `flake.nix` and no `.asd` stays in.
  
     It can be tested: a planted `::` beside a `flake.nix` and an unused `.asd` must still fail the check. testing.md test 2 says the same. The Decisions entry "What the client loads is the client's" matches it.
  2. **A client module can't take a Tun module's name.** This is the new criterion 10. The generated module test fails for such a module, naming both. `buildModules`, which exists at `flake.nix:175`, refuses two modules of one name. testing.md test 10 and the end of tun-platform.md §2.1 point to both. tun-platform.md also says "tools and paths" must not be Tun's. No criterion covers that, but the kernel already refuses duplicate tools and paths:
     - `src/core/operation.lisp:166` refuses a tool name defined twice;
     - `src/agent/http.lisp:1132` refuses an endpoint registered twice;
     - `src/web/ui.lisp:70` and `:243` refuse a page registered twice.
  
     So the sentence is true as written.
  3. **Tun's own modules and `tests/`.** Criterion 5 now says the `tests/` exclusion applies to Tun's modules as it does to a client's, and that none of Tun's has a `tests/` today. A test can hold that, and the Decisions entry says the same.
  
  **Still right from before**
  - **The brief is covered.** All five points of module-layout's record map to criteria:
    - the client check leaves its modules out: criteria 1 and 3;
    - a generated test checks them as modules: criterion 2;
    - `module-violations` and the naming convention: criterion 5 and tun-platform.md §2.1;
    - preview from the working tree: criterion 6;
    - the spec: the diff itself.
  - **The two extras the brief asked for are covered.** The test-client fixture is criterion 8. How a second client is kept out is criterion 3 and testing.md test 2.
  - **Each criterion can be decided by a test or a `bin/test-cli` step.**
  - **The spec text matches the criteria:** cli.md §6 and step 6, preview.md §2.3, testing.md tests 2 and 10 and the paragraph on tests 4, 6, 7 and 8, and tun-platform.md §2.1.
  - **No decision needed the asker.** The naming contract, reserving Tun's module names, and fuzzing a client's own modules with the client's tools are all written down and follow from the brief.
  
  **Not a reason to block:** criterion 10 sits between 5 and 6 in the list. The numbering is out of order but nothing depends on it.
- 2026-11-10 09:40  rebased: tun d1a4019 → fa659be, erp 024eb4f → 024eb4f
- 2026-11-10 09:40  bin/test-cli passed on the working tree (the new step: a module of the client's own in modules/notes, built, tested, a planted :: and a planted warning each failing bin/test, a preview showing a setting added after the shell was entered as module notes, source core)
- 2026-11-10 09:47  verify 1: passed build, test, check
- 2026-11-10 09:49  after verify 1: the template's tests/run.lisp loads and runs each module's own tests (tun-NAME/tests, TUN.NAME.TESTS:RUN-TESTS), which it named but did not load; criterion 7 and cli.md §6 say so, and bin/test-cli's module gains a test of its own
- 2026-11-10 09:57  bin/test-cli passed again with the module's own tests run (round 2 had found CL:*MODULES* taken in the template's run.lisp, now *OWN-MODULES*)
- 2026-11-10 10:03  verify 2: passed build, test, check
- 2026-11-10 10:04  shown (/settings)
- 2026-11-10 10:04  gate B asked of a reviewer
- 2026-11-10 10:06  gate B: changes (reviewer)
  I'm asking for changes: criteria 4 and 10 each have a part with no test that would fail without the change. Everything else is in order.
  
  **What is right**
  
  - **Verification passed.** Every step of `verify.txt` is ok (build, test, check). The log also records `bin/test-cli` passing its new step twice, the second time with the module's own tests running.
  - **Screenshots.** `/settings` was taken at both widths with no errors (`shots.json`). Tun ERP's `company.legal_name` appears there, which is the `company` module served from the working tree.
  - **The brief is done.**
    - The client check leaves the client's modules out (`client-files-under`, `tests/support.lisp`).
    - A generated test checks them as modules (`check-client-modules-use-only-public-interfaces`).
    - `module-violations` finds a module through its system `tun-NAME` and errors clearly when that system is missing (`module-directory`).
    - The preview loads modules from the working tree (`src/cli/preview.lisp:303`).
    - The spec is updated in `cli.md` §6, `preview.md` §2, `testing.md` tests 2 and 10, and `tun-platform.md` §2.1.
    - The test-client fixture (`logbook`) is there.
    - How a second client is kept out is now written down.
  - **Each of these criteria has a test that would fail without the change:**
    - 1 and 3: `a-client-s-check-leaves-out-its-modules-and-other-clients-but-not-what-it-loads` covers the gate-A hole: a loaded file beside a `flake.nix` and an unused `.asd`, and a `flake.nix` with no `.asd`.
    - 2: `a-client-s-own-module-is-checked-as-a-module` covers a `::` naming the file, `tests/` left out, and "is loaded from".
    - 5: `a-module-s-directory-is-its-system-s`.
    - 6: `a-previews-server-loads-the-client-s-own-modules-from-the-working-tree`, plus the `notes.later` check in `bin/test-cli`.
    - 7 and 9: the new `bin/test-cli` step covers the revision pin, the planted `::`, the planted warning, the module's own tests running, and the preview.
    - 8: `logbook`, the composition test, and `a-planted-qualifier-in-the-client-s-module-fails-its-check`.
    - 10, first half: the name check, plus `the-names-of-tuns-modules-are-its-modules-directories`, which keeps `+tun-module-names+` equal to `modules/`.
  - **The code is readable.** It follows the repository's rules, every new function has a docstring that cites the spec, and I found no leftover debugging or dead code. The core version bump is consistent across `flake.nix:87` and `src/core/module.lisp:20`.
  
  **Changes**
  
  1. **Criterion 4 has no test that would fail without the change.**
     - `client-tools` (`tests/generated.lisp:28`) and the owner loop in `check-translations` (`tests/generated.lisp:48`) are new behaviour.
     - Nothing asserts either of them. If `client-tools` went back to `(client-operations package)`, or `check-translations` went back to owner `"client"` only, the suite would still pass: `logbook` would just stop being fuzzed and translation-checked.
     - **What to add**, in the test client's suite next to the `logbook` tests:
       - a test that the tools the generated fuzzing, record-policy and sequence tests take for `test-client` include `logbook_add` and `logbook_list`;
       - a test that the translation check covers owner `logbook`. For example, factor out the owner list (`client` plus the client's module names), check that it contains `"logbook"`, and check that `known-texts` has `logbook`-owned texts so the loop isn't checking nothing.
  
  2. **The `buildModules` half of criterion 10 has no test.**
     - The duplicate-name `throw` (`flake.nix:178–183`) is never exercised.
     - `bin/test-cli` already evaluates Nix expressions without building (`nix eval --impure --expr`, `bin/test-cli:428`).
     - **What to add**, in step 6: evaluate `buildModules` on the client's `notes` module together with a second module of the same name (or `notes` renamed to a pinned module's name, such as `customers`). Check that the evaluation fails and that the message names both sources.
- 2026-11-10 10:18  gate B changes taken: a test that the generated tests take logbook's tools and texts (client-tools, client-text-owners), and bin/test-cli evaluates buildModules on two modules named notes and checks the refusal names both sources. bin/test-cli then failed once at the preview check (round 4: the preview's registry_describe did not show notes.later; its answer was not kept) and passed on the next run (round 5) unchanged but for keeping that answer and printing it on failure: intermittent, cause not found
- 2026-11-10 10:24  verify 3: passed build, test, check
- 2026-11-10 10:25  shown (/settings)
- 2026-11-10 10:25  gate B asked of a reviewer
- 2026-11-10 10:26  gate B: approve (reviewer)
  I approve this change. Both changes I asked for at the first gate B are in, and I found nothing new to block on.
  
  **My earlier changes are done**
  
  1. **Criterion 4 now has a test that would fail without the change.** The test is `the-generated-tests-take-the-client-s-module-with-the-client` (`tests/client/tests/interface-tests.lisp:812–820`).
     - It checks that the tools of `client-tools` (`tests/generated.lisp:873`) include `logbook_add` and `logbook_list`.
     - It checks that `client-text-owners` (`tests/generated.lisp:868`) includes `"logbook"`. That function is now the single owner list that `check-translations` loops over.
     - It checks that `known-texts` holds texts owned by `logbook`, so the translation loop really has something to check. The third element of each `known-texts` entry is the owner (`tests/i18n-support.lisp:104`).
     - If `client-tools` went back to `client-operations`, or the owner list went back to `"client"` only, this test would fail.
  2. **The `buildModules` half of criterion 10 is now tested** (`bin/test-cli:92–98`).
     - The step evaluates `buildModules` on two modules named `notes` with different sources (`./modules/notes` and `./tests`).
     - It fails if the evaluation succeeds, and it checks that the message names both `/nix/store/…notes` and `/nix/store/…tests`.
     - Because `.ordered` forces `checked`, the `throw` at `flake.nix:211–213` really runs.
  
  **Still right from the previous round**
  - Criteria 1–3 and 5–9 each have a test or a `bin/test-cli` step that would fail without the change. The first half of criterion 10 (the name check in the generated test) is tested too.
  - The spec is changed where the behaviour is: `cli.md` §6, `preview.md` §2.3, `testing.md` tests 2 and 10, and `tun-platform.md` §2.1.
  - The code is readable: docstrings cite the spec, and I found no debugging leftovers or dead code.
  - The core version is 2.18.0 in both `flake.nix` and `src/core/module.lisp`.
  
  **Verification**
  - Verify round 3 passed build, test and check.
  - The screenshots of `/settings` were taken at phone and desktop width. Tun ERP's `company` module is served there from the working tree.
  
  **Not blocking, but worth following up:** the log says `bin/test-cli` failed once at the preview check (`notes.later` was missing from `registry_describe`) and then passed unchanged. The failure output is now kept and printed, so the next failure can be diagnosed.
  - **One possible cause, unconfirmed:** ASDF compares file times to the whole second. Just before the preview, the earlier `bin/test` run compiles `notes.lisp`, and then `cp` and `sed` rewrite it. If all of that lands in the same second, the old compiled file can look up to date.
  - **What that would mean:** a timing problem in the test script, not a fault in criterion 6. Criterion 6's own Lisp test passes in `bin/test`.
  - **A cheap fix if it recurs:** add `sleep 1` or a `touch` in that step.
- 2026-11-10 10:27  rebased: tun fa659be → 9eaab70, erp 024eb4f → 024eb4f
- 2026-11-10 10:27  rebased onto ui-graph (core 2.18.0): this change is core 2.19.0; bin/test-cli waits a second before the preview step's edit, as the gate B reviewer suggested for the one intermittent failure (ASDF's one-second file times)
- 2026-11-10 10:34  bin/test-cli passed on core 2.19.0
- 2026-11-10 10:42  verify 4: passed build, test, check
- 2026-11-10 10:42  shown (/settings)
- 2026-11-10 10:42  gate B asked of a reviewer
- 2026-11-10 10:43  gate B: approve (reviewer)
  I approve: the only changes since the last approved gate B are the rebase onto ui-graph, the version bump and a one-second wait. All three are as the log says, and nothing new turned up.
  
  **What changed since the last approval**
  - **Version bump.** ui-graph took 2.18.0, so this change is now 2.19.0, and it is the same everywhere:
    - `coreVersion` in `flake.nix:87` and `+core-version+` in `src/core/module.lisp:20` both say 2.19.0;
    - the new module ranges all say `">= 2.19.0" "< 3.0"`: `tests/client/modules/logbook/flake.nix`, `logbook.lisp`, the `notes` module in `bin/test-cli`, and the example in `docs/client-api.md`.
    - Tun ERP's `company` module declares `">= 2.17.0" "< 3.0"`, which still includes 2.19.0.
  - **The intermittent preview failure.** `bin/test-cli` now waits one second before editing `notes.lisp` for the preview check (diff lines 116–124). That is the fix suggested last round for ASDF comparing file times only to the whole second, and a comment there explains why. The log records `bin/test-cli` passing on 2.19.0 after it.
  - **Nothing else changed.** The rest of the diff is what the last round approved:
    - criterion 4 is held by `the-generated-tests-take-the-client-s-module-with-the-client`;
    - the `buildModules` half of criterion 10 is held by the duplicate-`notes` evaluation in `bin/test-cli`;
    - criteria 1–3 and 5–9 have the same tests as before.
  
  **Still right**
  - **Verification.** Verify round 4 passed build, test and check.
  - **Screenshots.** `/settings` was taken at phone and desktop width. Both show `company.legal_name`, which comes from Tun ERP's `company` module, loaded from the working tree.
  - **The client is unchanged.** The report shows Tun ERP at its loop base, 024eb4f, and `modules/company` is already there. So the diff rightly has no client changes.
  - **The code.** I found no leftover debugging or dead code. The docstrings cite the spec, and the spec is changed where the behaviour is: `cli.md` §6, `preview.md` §2.3, `testing.md` §1 (tests 2 and 10) and `tun-platform.md` §2.1.
  
  **Not blocking:** step 6 in `spec/cli.md` doesn't mention two things `bin/test-cli` now does: running the module's own tests, and the `buildModules` refusal of two modules with one name. Both are specified elsewhere (§6 bullets, `tun-platform.md` §2.1), so the step list could name them too, but nothing depends on it.
- 2026-11-10 10:44  finished at tun f6a00d5, erp 024eb4f
