# Sources

Where to look when you are unsure how idiomatic Common Lisp does something.
Prefer reading one of these to guessing. Paths starting with `lib/` are in
the local tree that `bin/reference` builds. It is pinned to the same nixpkgs
as Tun's code, so library versions match what Tun runs.

Each entry says whether we may copy excerpts into the repository. When in
doubt, link and paraphrase.

## Reading set

Read these first. Together they cover the house style and the reasons for it.

1. **Google Common Lisp Style Guide** and **Google Common Lisp Effective
   Programming**. `lib/google-lisp-guides/lispguide.md` and
   `lispprogrammingguide.md`. CC-BY 3.0, so copying is allowed with
   attribution.
   - In the style guide, read Packages, CLOS, Special variables, Assertions
     and Conditions, Type Checking and Declarations, Macros, Data
     Representation, Structures and Classes, Iteration.
   - Its key rule on types: use `check-type` for an interface's contract, and
     `(declare (type ...))` only in internal code. What a declaration does
     depends on the safety policy.
   - In the Effective guide, read Optimization and Pitfalls.
2. **PAIP**, Peter Norvig, *Paradigms of Artificial Intelligence
   Programming*. `lib/paip/docs/chapterN.md`, with the code in
   `lib/paip/lisp/`. MIT, so copying is allowed.
   - Chapter 3, section 1: a guide to Lisp style.
   - Chapter 9: memoisation and compiling to closures.
   - Chapter 10: low-level efficiency, declarations and avoiding consing.
   - Chapter 13: CLOS. Chapter 24: packages, conditions, `loop`.
   - Chapter 25: troubleshooting.
3. **The SBCL manual.** `lib/sbcl-manual/`, read with
   `info -f reference/lib/sbcl-manual/sbcl.info`. Public domain.
   - Handling of Types: declarations are assertions under the default policy.
   - Compiler Policy, and Open Coding and Inline Expansion.
   - Efficiency, and Efficiency Hacks.
   - Package-Local Nicknames, and Timeouts and Deadlines.
   - Profiling: the deterministic and the statistical profiler.
4. **Practical Common Lisp**, Peter Seibel, at
   https://gigamonkeys.com/book/. Free to read online. Link only.
   - Chapters 8 and 24 on macros and defining macros.
   - Chapters 16 and 17 on generic functions and classes.
   - Chapter 19 on conditions and restarts.
   - Chapters 21 and 22 on packages and `loop`. Chapter 32 on optimisation.
5. **The Common Lisp Cookbook** at https://lispcookbook.github.io/cl-cookbook/.
   Its licence allows copying with the copyright notice. Read the pages on
   error handling, CLOS, macros, packages, types, performance, testing and
   debugging.
6. **Norvig and Pitman, "Tutorial on Good Lisp Programming Style"** (1993),
   at https://norvig.com/luv-slides.ps. Short. Link only.

For the language definition, use the HyperSpec in `lib/hyperspec/`. Its
licence allows only complete, unmodified, non-commercial copies, so read it
and never paste from it. For quotable text use the Common Lisp Community
Spec at https://cl-community-spec.github.io.

## Library source to learn from

These are worth reading as examples of how experienced authors write Lisp.
All are in `lib/`. Several are Tun dependencies.

| Library | Copy? | Read | Teaches |
|---|---|---|---|
| Alexandria | public domain, yes | `alexandria-1/macros.lisp`, `conditions.lisp`, `functions.lisp` | `with-gensyms`, `once-only`, small documented utilities, compiler macros |
| cl-ppcre | BSD, with notice | `api.lisp`, `specials.lisp`, `closures.lisp` | Compiler macros that precompile constant input, one shared optimisation policy, compiling to closures |
| Hunchentoot | BSD, with notice | `acceptor.lisp`, `taskmaster.lisp`, `conditions.lisp`, `easy-handlers.lisp` | A protocol of generic functions, strategy classes, a condition hierarchy, a defining macro. Closest to Tun's web layer. |
| Closer to MOP | MIT | `closer-mop-packages.lisp`, `closer-mop-shared.lisp` | Layering over the metaobject protocol |
| FiveAM | BSD, with notice | `src/check.lisp`, `src/test.lisp`, `src/run.lisp` | A macro that takes forms apart to explain failures, restarts while tests run |
| Parachute | zlib | `tester.lisp`, `result.lisp` | An extensible result and report protocol in CLOS |
| Ironclad | BSD, with notice | `src/common.lisp`, `src/macro-utils.lisp`, `src/digests/` | Typed, non-consing, fast code with `defstruct` and `deftype` |
| jzon | MIT | `src/jzon.lisp` | A modern single-file library: inline declarations, `dynamic-extent`, a condition hierarchy |
| Serapeum | MIT | `types.lisp`, `defining-types.lisp`, `control-flow.lisp` | Modern idioms such as the `->` ftype macro and exhaustiveness checks. Opinionated: read it, don't adopt it wholesale. |
| SBCL | public domain, keep the LOOP and PCL notices | `src/code/restart.lisp`, `src/code/target-error.lisp`, `src/pcl/combin.lisp`, `src/compiler/policies.lisp`, `contrib/sb-sprof/`, `contrib/sb-concurrency/queue.lisp` | How conditions, restarts and method combination are built; profiling; lock-free queues |

## Performance

Measure before you optimise. Then read, in this order:

1. **The SBCL manual's Efficiency and Profiling sections,** listed above.
2. **The Optimization section of Google's Effective Programming guide:**
   avoiding allocation, unsafe operations, `dynamic-extent`, `reduce` against
   `apply`.
3. **PAIP chapter 10.**
4. **The Cookbook's performance page:** `time`, the statistical profiler,
   `disassemble`, declarations, inlining, block compilation.
5. **CMUCL's "Advanced Compiler Use and Efficiency Hints"** at
   https://cmucl.org/docs/cmu-user/html/Advanced-Compiler-Use-and-Efficiency-Hints.html.
   SBCL inherited the same compiler. This is the deepest treatment of type
   inference and efficiency notes.

The tools are built in:

- `time` shows run time and bytes consed.
- `sb-sprof:with-profiling` profiles statistically, in `:cpu`, `:alloc` or
  `:time` mode.
- `sb-profile:profile` and `sb-profile:report` count calls and time per
  function.
- `disassemble` shows what the compiler made.
- Compiling a function under `(speed 3)` makes SBCL print efficiency notes
  for everything it could not optimise. That is the closest thing Lisp has to
  a performance linter.

## Tools in use

**Indentation:** `bin/indent FILE...` rewrites named files with the flake's
headless Emacs and `common-lisp-indent-function`; `bin/indent --check` checks
tracked Lisp and ASDF files without writing. In Emacs, the checkout's
`.dir-locals.el` loads the same Tun macro hints from `scripts/indent.el`. See
`../spec/tooling.md`.

**Lint:** `bin/lint` runs Mallet 0.9.2 (https://github.com/fukamachi/mallet,
MIT), pinned with `trivial-glob` in the flake. It reads source without loading
it. `.mallet.lisp` enables the default rules plus house-style line length,
exported docstrings and `::` checks. Findings are advisory, not a build gate.
See `lint-baseline.md` for counts per file; regenerate with
`bin/lint --baseline`. The complete JSON includes locations in `.build/lint.json`.

## Tools to add

1. **An agent REPL over MCP,** such as cl-mcp
   (https://github.com/cl-ai-project/cl-mcp, MIT). It evaluates code in
   separate child processes, checks parentheses, makes structural edits,
   expands macros and runs FiveAM. Use it on a development image only.
2. **lisp-critic,** in nixpkgs. Pattern-based style critiques, useful while
   learning. Not a gate.

## Designs borrowed from other platforms

Tun takes ideas, not code, from these. Read the design, then write it the
Lisp way.

- **Ash Framework** (Elixir), https://hexdocs.pm/ash, and **Ash
  Authentication**, https://hexdocs.pm/ash_authentication. MIT. One
  declaration of a resource gives its actions, policies and interfaces, as
  `define-entity` and `define-operation` do here; MCP calls run as the user
  who started them, as Tun's tokens do. `spec/auth.md` §3.5 follows Ash
  Authentication: strategies listed in one declaration, providers as
  presets of a generic OpenID Connect strategy (here, subclasses with
  default initargs), secrets read at run time, and an identity record
  (issuer and subject) linked to the account.
