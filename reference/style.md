# Tun Common Lisp style

How Common Lisp is written in this repository. It follows the community
conventions in the Google Common Lisp Style Guide and Norvig and Pitman's
"Tutorial on Good Lisp Programming Style" (see `sources.md`), narrowed to the
choices Tun has made. When this guide and those sources disagree, this guide
wins inside Tun.

The first rule is the one the others serve: **write for the next reader.**
That reader is often an agent with no history and sometimes a person learning
Lisp. Code that is obvious beats code that is clever.

## Layout

- **Lines stay under 100 columns.** Break long forms at argument
  boundaries, not in the middle of an argument.
- **Indent the way Emacs and SLIME indent.** Body forms of `defun`, `let`,
  `when` and similar get two spaces. Arguments of a function call line up
  under the first argument, or start on the next line indented one step.
- **One definition per top-level form, each on its own lines.** A
  one-line `defun` is fine only when it fits easily and needs no docstring,
  such as a trivial accessor alias.
- **Closing parentheses gather at the end of the last line.** Never put
  them on lines of their own.
- **A blank line separates top-level forms.** Two blank lines, or a `;;;`
  heading, separate sections of a file.

## Comments and docstrings

| Semicolons | Use |
|---|---|
| `;;;;` | File header: the first lines of the file, saying what it holds. |
| `;;;` | A section heading or a comment about the following top-level forms. |
| `;;` | A comment inside a definition, on its own line, indented with the code. |
| `;` | A short note at the end of a line. |

- **Every exported function, generic function, macro, class and condition
  has a docstring.** The first sentence says what it does or returns. Later
  sentences state the contract: what the arguments must be, what it signals.
- **Comments explain why, not what.** A comment saying what the next line
  does is noise if the line is clear. Rewrite the line instead.
- **No history in comments.** Review rounds, finding numbers and "until the
  slice 2 review" belong in commit messages. A comment describes the code as
  it is.
- **Refer to the spec by section only when the code implements a rule from
  it.** For example, `; core.md §3.6: a confirm tool without a token`. The
  reader can then find the rule.

## Naming

- **Lowercase words joined by hyphens,** spelled out: `order-total`, not
  `ord-tot`. Identifiers are English. Labels and messages are Norwegian.
- **Predicates end in `-p`,** as in `blank-p` and `marketing-allowed-p`.
  Common Lisp's own one-word predicates, such as `evenp`, drop the hyphen.
  Tun's names keep it throughout.
- **Special variables have earmuffs,** `*deadline-ms*`. **Constants have
  plus signs,** `+provider-call-limit+`.
- **Defining macros start with `define-`.** Macros that bind a context and
  clean up start with `with-`. **`make-`** constructs, **`find-`** returns
  an object or `nil`, **`fetch!`** signals when the object is missing.
- **Accessors are named `class-slot`,** for example `customer-email`.
- **Operation names match their MCP tool names** in Lisp spelling:
  `customers-create` is the tool `customers_create`.

## Packages and systems

- **One package per module,** `tun.<module>`, defined in that module's first
  file. A defpackage names symbols as uninterned symbols, `#:customer`.
- **`:use` only `#:cl` and the packages the platform defines,** usually
  `#:tun.core`. Reach a library through its own prefix or a package-local
  nickname, never through `:use`.
- **Export deliberately.** The `:export` list is the module's interface for
  modules that depend on it. What clients may use is what the module
  publishes into `TUN`.
- **Never `::` across packages** in kernel, module or client code. If you
  need an internal symbol, the interface is missing something: add it.
- **ASDF systems are data.** A `.asd` has `defsystem` forms with data
  options only. Build logic lives in `scripts/` or the flake.

## Definitions

- **Use Tun's defining forms where they apply.** An entity is a
  `define-entity`, a tool is a `define-operation`, a timed task is a
  `define-workflow`. They give validation, persistence, audit and MCP for
  free.
- **Write `defgeneric` before its methods,** with a docstring that states the
  contract every method must keep. A seam's docstring says what the default
  returns.
- **Classes declare `:initarg`, `:accessor` and, where it helps, `:type` and
  `:documentation` for every slot.**
- **Use `defstruct` only for small internal records** on a hot path, where
  the speed of slot access matters and redefinition in a live image does not.
  Struct redefinition does not update existing instances, so prefer classes
  for anything a live patch may change.

## Functions and control flow

- **Small functions with one job.** If a function needs a comment to
  separate its parts, the parts want to be functions.
- **Choose the iteration form by intent.**
  - `dolist` and `dotimes` for side effects;
  - `mapcar`, `remove-if` and `reduce` for transforming a sequence;
  - `loop` when collecting, summing or iterating several things together.
- **Prefer `cond` to nested `if`.** Use `when` and `unless` for one-armed
  conditionals, and `if` only when both branches are short.
- **`let` by default, `let*` only when a binding uses an earlier one.**
- **Return secondary results as multiple values,** as `gethash` does, rather
  than consing a list.
- **Keep side effects at the edges.** Compute in pure functions. Store,
  send and log in the operation body or the workflow.

## Errors and conditions

- **A domain refusal is `fail` with an error code** and a Norwegian message
  for the user. `fail` is declared with the error-code type, so a misspelled
  code is a compile-time warning.
- **Kernel conditions are `define-condition` subclasses** with readers for
  everything a handler needs. Never signal a bare string with `error` from
  kernel code.
- **Handle at boundaries.** Requests, workflow runs and threads catch
  conditions. Inner code lets them propagate. Use `handler-case` to unwind,
  and `handler-bind` to observe or decorate a condition without unwinding.
- **Offer a restart when a caller can choose how to recover.** A restart lets
  an operator at the REPL, or a calling layer, decide between retrying,
  skipping and aborting. Tun does not use restarts yet. Migrations and
  imports are the natural first places.
- **Every acquired resource is released in `unwind-protect`,** or through a
  `with-` macro that uses it.
- **Do not use `ignore-errors`** except for a probe whose failure is a valid
  answer, such as reading a source location. Comment why.
- **Use `check-type` in exported functions** whose argument types are part of
  their contract.

## Macros

- **Write a macro only when a function cannot do the job:** new binding
  forms, new defining forms, or code that must not evaluate its arguments.
- **Expand to ordinary Lisp.** `define-entity` expands to `defclass`, so the
  compiler checks it like hand-written code.
- **Keep the macro thin.** Put the logic in functions the expansion calls, or
  in functions the macro calls at expansion time. They are easier to test
  and to redefine.
- **Read no other definition while expanding.** A defining macro may look
  at its own arguments, never at another entity, operation or query: name
  the other definition by its symbol and look it up when the code runs
  (`define-query`'s `{order}`). Code compiled against another definition
  goes stale silently when that definition changes, and a chain of such
  macros is what makes a framework slow to compile.
- **Expand small.** One definition, a registration and a call into
  ordinary functions. A large expansion per entity costs compile time on
  every build, for every client.
- **Avoid capture and double evaluation.** Use gensyms for internal
  bindings, `alexandria:with-gensyms`, and `alexandria:once-only` for
  arguments used more than once.
- **Test what a macro expands to** when the expansion is part of the
  contract, using `macroexpand-1`.

## Types and performance

- **Correct first, then measured, then fast.** Tun compiles with
  `(declaim (optimize (safety 3) (debug 2)))` at the top of each file, which
  checks every slot type and keeps backtraces useful.
- **Profile before optimising.** Use `sb-sprof` or the request traces in
  `introspect_request`. Tun's biggest speedups came from I/O and library
  settings, such as fsync batching and the statement cache, not from
  declarations.
- **On a measured hot path, declare locally.** Put
  `(declare (optimize (speed 3) (safety 1)))` and argument types inside the
  hot function only, and read SBCL's optimisation notes.
- **`check-type` guards an interface; `declare` is for internals.** A type
  declaration is an assertion under Tun's safety policy, but under
  `(safety 0)` it becomes a promise the compiler trusts. Contracts that
  callers must meet use `check-type`, which always checks.
- **Money is integer øre.** Never floats. Quantities that need fractions use
  the `decimal` field type, which is exact, or rationals in computation.
- **Avoid consing in loops that run per request:** prefer `loop ... sum` to
  building a list and reducing it.

## Data

- **Entities are CLOS objects.** JSON hash tables exist only at the MCP and
  HTTP boundary. Convert at the edge.
- **Build JSON with `jobj` and `jarr`.** See `pitfalls.md` for why `nil`
  is not an empty array.
- **Property lists for keyword options,** hash tables with an explicit
  `:test` for lookups, alists only for short fixed tables.
- **Time is universal time inside the image** and RFC 3339 at the boundary.
  Norwegian local time comes from `summer-time-p` in `src/core/util.lisp`.

## Concurrency

- **Shared state lives on the application object,** guarded by an
  `sb-thread` mutex with `with-mutex`. No other global mutable state.
- **Rebind what a thread needs.** Dynamic bindings do not cross into new
  threads. See `pitfalls.md`.

## Tests

- **FiveAM.** One file per subject, named for the subject:
  `store-tests.lisp`, `orders-tests.lisp`.
- **A test name is a sentence about behaviour:**
  `a-viewer-cannot-create-a-customer`, not `test-17` and not a review
  number.
- **Test through operations,** the way a client or the MCP surface would.
  Use `with-test-app` for a fresh application.
- **Every bug gets a test that fails before the fix.**

## Before you call it done

1. `bin/build` has no warnings and `bin/test` is green.
2. Every new exported definition has a docstring.
3. No line is over 100 columns, and no comment narrates history.
4. A reader who knows Lisp, but not this change, can follow it without you.
