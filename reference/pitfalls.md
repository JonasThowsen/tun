# Common Lisp pitfalls this codebase has hit

Each item below cost a bug, a review finding or a slow afternoon in Tun. They
are written as rules with the reason, so you can apply them without
repeating the history.

## Data and JSON

- **`NIL` is false, the empty list and "nothing" at once.** JSON has `false`,
  `[]` and `null` as three values. Tun's encoder encodes `NIL` as `false`,
  wants arrays as vectors, and uses `:null` for JSON null. Build arrays with
  `jarr`, so an empty list becomes `[]`. Build objects with `jobj`. A plain
  `NIL` where an array belongs encodes `false`, and only a test notices.
- **A posted name is a text or an array, by how many a browser sent.** A
  page's FORM and QUERY keep a name given once as its text and a name
  given more than once (a group of `ui:checkboxes`, a `:several`
  filter) as an array of its texts, in order; a name not given is
  absent. `jget` of a set therefore gives NIL, a string or a vector, and
  code that expects one of them loses or refuses the others. Read a set
  with `(query-values form NAME)`, a list of its values that are not
  empty, whatever was ticked. Until core 2.47.0 a posted form kept only
  the last value of a repeated name.
- **Most data crossing the MCP boundary is dynamically typed.** Inputs and
  results are hash tables. Nothing checks their shape at compile time.
  Validate at the boundary with the declared parameter types, then work with
  entity objects inside.

## CLOS and method combination

- **Long-form `define-method-combination` groups default to
  most-specific-first.** Tun's `operation` combination declares
  `:order :most-specific-last` for both `:before` and `:after` groups, so
  modules run before the client in both phases. Code compiled cleanly with
  the wrong order. Only a test caught it. When you write a method
  combination, state the order of every group explicitly and test it.
- **A second `defmethod` with the same specialisers replaces the first.**
  SBCL warns about the redefinition. `bin/build` turns that warning into a
  failure, which is one reason the build is strict.

## Packages

- **SBCL does not enforce a package lock while that package is `*package*`.**
  A file that starts with `(in-package #:tun.core)` can redefine kernel
  functions. The interface check refuses `in-package` into a package the
  client does not own for this reason.
- **A missing export shows up as an undefined-function warning**, not an
  error at the call site. Read every warning. The strict build exists so
  that none is ignored.

## Threads and special variables

- **New threads do not inherit dynamic bindings.** A special variable bound
  with `let` in the parent is at its global value in a thread the parent
  starts. Capture what the thread needs in a lexical variable and rebind it
  inside the thread function. `start-worker` in `src/core/application.lisp`
  captures `*application*` before creating the thread.
- **An unhandled condition in any thread ends a `--non-interactive` process.**
  `src/runtime.lisp` installs an `sb-ext:*invoke-debugger-hook*` that aborts
  only the thread that hit the condition. Requests and workflow runs also
  catch `serious-condition` themselves, so one failure never takes the
  tenant down.
- **Asynchronous interrupts can land between any two instructions.** The
  deadline watchdog uses `sb-thread:interrupt-thread`. Use `unwind-protect`
  for every cleanup. Use `sb-sys:without-interrupts` around sections that
  must not be split, such as recording a commit. Never unwind through a
  foreign call: the watchdog re-arms instead of interrupting inside SQLite.

## Build and load

- **Compile and load in separate processes.** Loading a second system in an
  image where ASDF already loaded the first can make ASDF reload it, with
  macro-redefinition style warnings. `bin/build` and `bin/test` run the
  kernel and each client in their own process.
- **A file compiled against a definition in another file is not compiled
  again unless ASDF knows it depends on that file.** `:serial t`, or a
  `:depends-on` between the components, says so; then a changed set
  recompiles every `ecase-of` over it, in the same system and in the
  systems that depend on it. Without it, the old expansion is loaded and
  only the load-time comparison of `ecase-of` notices (`spec/core.md`
  §2.7). Give every system `:serial t` unless it has a reason not to.
- **`ecase` and `case` compare with `eql`, so they never match a
  string.** An enum field's value is a string: switch over it with
  `ecase-of (ENTITY FIELD)`, which compares with `equal`, never with
  `case`.
- **Unbalanced parentheses surface only at the next full compile.** Let the
  editor or `bin/build` check the form before moving on.
- **`function-lambda-expression` returns nothing for compiled code.** Source
  text is not in the image. Use `sb-introspect:find-definition-source` for
  `file:line` and read the file.

## Libraries

- **Hunchentoot decodes header bytes as Latin-1** and form posts as Latin-1
  unless the external format is set. Tun re-decodes headers as UTF-8 and
  sets UTF-8 for posts. Test with `æ`, `ø` and `å`.
- **Hunchentoot and Chunga read request lines and headers without limit**,
  and jzon parses very long numbers in quadratic time. Every input bound in
  Tun is explicit.
- **cl-sqlite keeps 16 prepared statements per connection by default.** A
  write transaction uses about 25 distinct statements, so most were parsed
  again on every use. Tun raises the cache to 256. Defaults like this show up
  only under a profiler, so profile before assuming the language is slow.
- **cl-postgres sends NIL as `false`, not NULL.** NULL is `:null`, both ways.
  The Postgres adapter turns NIL into `:null` going in and back coming out.
- **One failed statement aborts the whole Postgres transaction**, where
  SQLite fails only the statement. Code that catches a `conflict` and goes on
  needs the failing write in its own savepoint; the adapter does this for
  entities with unique fields.
- **cl-postgres signals every server notice as a Lisp warning**, such as
  "already exists, skipping". The adapter sets `client_min_messages` to
  `WARNING` on each connection.
- **A socket read inside `sb-sys:without-interrupts` makes SBCL warn**, and
  nothing can interrupt it. The Postgres adapter protects its commit with
  `*interruptible*` (the watchdog waits), not by blocking all interrupts,
  and closes a connection whose statement was cut off halfway.

## Tests

- **A test timed with the wall clock fails on a busy machine.** Other
  builders' suites share the machine, and a search that takes 40 ms alone
  took 260 ms at a load of 60. Measure a speed with `is-fast`, which
  counts processor time (this process's and the Postgres server's), and
  time a deadline or a timeout with `is-within-seconds`; only
  `tests/timing.lisp` reads a clock, and a test checks that
  (`spec/tooling.md`, «Speed and time in tests»).

## Single-page screens and TypeScript

- **A session cookie goes with a request from another origin on the same
  site.** `SameSite=Lax` keeps a cross-site POST from carrying it, but a
  page on another port of the same host, such as another tenant, is the
  same site. That is why `/api` takes a session only with the session's
  proof, which only the screen's own page can read
  (`spec/typescript.md` §5), and never the cookie alone.
- **A link in the staff shell is boosted by htmx.** htmx would fetch a
  single-page screen's document and swap its body into the shell, where
  its module scripts never run. The screen answers an htmx request with
  `HX-Redirect`, so the browser loads it whole.
- **`tsc` does not rewrite import paths.** Code the browser loads
  without a bundler imports `./api.js`, not `./api`; with
  `"moduleResolution": "bundler"` that name finds `api.ts` when it is
  type-checked.
- **`exactOptionalPropertyTypes` refuses `undefined` where a DOM type
  says `?: T | null`.** `fetch`'s `signal: options?.signal` does not
  type-check under it; `options?.signal ?? null` does. A screen's
  project may well turn the option on, so the generated module is
  checked with it.
- **A result is a JSON object.** MCP's `structuredContent` is one and
  `result->json` takes a record or an object, so `:returns` declares a
  record, a page or an object, and a list or a value only as a key's.

## Sandboxing

- **Code in the same image cannot be sandboxed.** Package locks, the reader
  check and the integrity snapshot stop accidents and make review possible.
  A determined author can still call `sb-ext:unlock-package`. Treat client
  code as trusted code that has been reviewed, not as untrusted input.
