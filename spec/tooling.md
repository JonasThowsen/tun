# Development tooling

Run the tools inside `nix develop .`. Their versions come from the flake;
they do not change the application's behaviour. Only the editor REPL loads
the application.

## Indentation

`bin/indent FILE...` indents the named Common Lisp files with headless Emacs
and `common-lisp-indent-function`. Arguments are relative to the caller's
working directory. Rewriting requires explicit files. `--` ends option
parsing, including for names starting with a hyphen.

`bin/indent --check [FILE...]` prints the names of files that would change
without writing them. With no files, check the repository's tracked `.lisp`
and `.asd` files. Exit codes are 0 for no changes, 1 for indentation
differences and 2 for an invalid invocation or an unreadable or malformed
file. Repeated indentation produces identical bytes. Preserve UTF-8 text,
comments and string contents; only indentation changes.

Use the same indentation hints in batch mode and an editor by loading
`scripts/indent.el`. The checkout's `.dir-locals.el` does that for Emacs and
switches its Lisp buffers to `common-lisp-indent-function`; loading the
file changes no other buffer. Defining forms distinguish their header arguments from
their bodies, including package-qualified names. Context macros with a
binding list indent their bodies by two spaces; contexts without a binding
list do so from their first argument. Do not evaluate file-local settings
or source forms while indenting.

The command-line interface is the test boundary: representative defining
forms, check-mode reporting and immutability, repeatability, and failure
handling. `bin/test` runs the focused tooling checks as well as checking
shell syntax. Existing source files are formatted individually in the
readability pass, not as part of installing the tools.

## Editor REPL

The dev shell adds this checkout's systems to ASDF's source registry
through `CL_SOURCE_REGISTRY`: the root, and the trees `modules/` and
`clients/`. Any SBCL started in the shell can then load them with
`asdf:load-system`. That includes the one an editor starts itself, when the
editor takes the shell from `.envrc` through direnv. Such an image compiles
into ASDF's default cache, never into `bin/build`'s `.build/fasl/`.

`bin/repl [--port N] [SYSTEM]` is for an image started from a terminal or
on another machine. It starts SBCL with this checkout's ASDF systems
and a Slynk server, so SLY in Emacs can connect to it. SYSTEM defaults to
`tun/tests`, the kernel, every module and their tests; a client system such
as `test-client` loads that client instead. The port defaults to 4010.

Slynk listens on 127.0.0.1 only. It has no authentication and gives full
access to the process, so a remote editor reaches it through an SSH tunnel.
When the port cannot be bound, say so on standard error and exit 1.

Compile into `.build/repl-debug-fasl/`, never into `bin/build`'s
`.build/fasl/`: a file compiled first by the REPL would otherwise be
skipped by the next incremental strict build, and its warnings would go
unseen. Compiler warnings in the REPL are shown but do not stop it.

On a terminal, the process keeps SBCL's own REPL in the foreground. Without
one, it stays up until it is stopped. The Slynk version is the one the dev
shell provides, which reports the same version as SLY on MELPA. The
editor setup is in `docs/emacs.md`.

`bin/test` checks the CLI: a connection gets Slynk's connection info back
over the wire protocol, and a port already in use fails with exit 1.

An image `bin/repl` starts compiles with at least `(debug 3)`, through
`sb-ext:restrict-compiler-policy`, so its debugger shows every local of a
function, the ones the rest of it does not read too, and can restart its
frames. Everything of the checkout it loads is compiled under that policy:
its directory of compiled files is its own, so no file compiled before
under another policy is loaded.

## Agent REPL

`lisp`, from [slynk-cli](https://github.com/JonasThowsen/slynk-cli), gives
an agent what SLY gives a person: a running image to evaluate in, a
debugger that waits at an error, frames to look into and restart, a form
compiled on its own, and the way to a definition. It is a command, so it
works from any agent harness that runs commands. Its contract is the
README of the revision `flake.lock` pins; the flake puts that `lisp` on
the dev shell's PATH.

`.slynk-cli.sexp` at the root configures it for Tun: `lisp start` runs
`sbcl` without init files, loads `scripts/setup.lisp`, so the image has
this checkout's systems as `bin/build` has them, and loads `tun/tests` by
default, or the system it is given, such as a client. The image compiles
with `(debug 3)` into `.slynk-cli/fasl/` and keeps its records in
`.slynk-cli/`, which keeps itself out of git.

`bin/test` checks `lisp` on Tun in a state directory of its own, so an
agent's image of the checkout is left alone: an image of `tun/core`
starts, compiles under that policy into that directory, pauses at an
error in Tun's own code with the file and line of the frame under `src/`,
and stops. Each behaviour of the command is checked in `slynk-cli` itself.

## Lint

`bin/lint [MALLET-ARGUMENTS...]` runs the pinned Mallet release with
`.mallet.lisp` from this repository. With no arguments, inspect kernel,
modules, clients, tests, build scripts and `tun.asd`. Explicit paths are
relative to the caller's working directory. Mallet reads source without
loading the application or executing source forms.

Use the default rule set plus the house style's line length, exported
docstrings and package-boundary checks. Configuration is data, not code.
Lint findings are advisory: `bin/test` checks the lint CLI on small fixtures
but does not lint the existing tree as a gate. Pass through Mallet's exit
status and output formats so a caller can distinguish findings from errors.

Record findings per file in `reference/lint-baseline.md`, with sorted rule
counts, the pinned tool version and the parent Git revision. Regenerate it
through `bin/lint --baseline`; this writes the baseline report and
`.build/lint.json`, not source files. For a selected input set, use
`bin/lint --baseline REPORT FILE...`; REPORT is relative to the caller.
Successful report generation exits 0 even when lint reports findings.
Do not suppress existing findings globally just to get an empty report.

## Running the tests

`bin/test` is the gate every change passes (`AGENTS.md`). It is fast enough
to run after every change:

- It checks the shell scripts' syntax, then compiles Tun, its tests and
  every client system of the run once, strictly: a warning fails the run,
  as before.
- Then it runs, at once in separate processes, every child suite of `core`,
  each client's suite (`scripts/client-systems`) and the tooling checks
  (indentation, lint, the editor REPL, `lisp`). A suite's process loads
  what was compiled; it compiles nothing. The tooling checks compile only
  into directories of their own. At most `TUN_TEST_JOBS` run at once, by
  default the machine's processor count.
- The longest go first, by the times of the last run, kept in
  `.build/test/times`; a suite with no time yet goes first.
- Every test of `core` is in a child suite, so each runs in exactly one
  process; the run fails, naming the test, when one is not.
- Each prints one line as it ends: `ok` or `FAIL`, its name and its time.
  Every one runs, whatever another's result. At the end, each failed one's
  output is printed in full, and the run exits 1; otherwise 0. The
  outputs are kept in `.build/test/NAME.log`.
- The core suites share one throwaway Postgres server, which takes 300
  connections; each test makes its own databases on it. A test holds every
  port it uses until it is done, and none relies on a port staying unused.
- `TUN_TEST_SUITES="core test-client"` limits the run as before, and
  `bin/test --only SUITE` runs one core suite in this process.
- On a machine of 12 processors the whole run takes under 2.5 minutes.
