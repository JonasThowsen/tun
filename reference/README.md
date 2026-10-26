# reference

Common Lisp knowledge for anyone writing code in Tun, agent or person. How
Tun itself is designed is in `../docs/`. This folder is about the language:
how we write it, what bites, and where to learn more.

| File | What it holds |
|---|---|
| `style.md` | The house style. Follow it. |
| `pitfalls.md` | Mistakes this codebase has made, as rules with reasons. |
| `sources.md` | Books, guides and library sources worth reading, with licences and what to read in each. |
| `coalton.md` | Why Tun does not use Coalton yet, and the experiment that would change that. |
| `lib/` | Pinned local copies of those sources. Not committed: run `bin/reference` to build it. |

## How an agent picks up idioms

An agent writes the way the code around it is written, more than the way any
guide says. So the order of influence is:

1. **The nearest example in this repository.** That is why the codebase has
   to be the best reference of all. Code that is merely acceptable gets
   copied too.
2. **The short rules in context:** `../AGENTS.md`, `style.md` and
   `pitfalls.md`. Short, concrete rules with a reason are followed. Long
   essays are skimmed.
3. **Real sources on disk to search when unsure.** `lib/` holds Alexandria,
   cl-ppcre, Hunchentoot, SBCL's own source and others, at the versions Tun
   runs. A grep there beats a guess from memory.
4. **Mechanical checks.** The strict build fails on every warning. A linter
   and an indentation check are the next tools to add, as listed in
   `sources.md`.
5. **Review against the checklist** at the end of `style.md`.

## Learning Common Lisp with Tun

A path for a person who knows programming but not Lisp:

1. **Practical Common Lisp, chapters 1 to 10,** for syntax, functions,
   macros and the REPL. Then chapters 16, 17 and 19 on generic functions,
   classes and conditions.
2. **Read Tun's customers module,** `modules/customers/customers.lisp`. It is
   short and uses the defining forms: `define-module`, `define-entity`,
   `define-operation`.
3. **Read how those forms work:** `src/core/entity.lisp` for the metaclass,
   `src/core/operation.lisp` for the method combination. Read PAIP chapter
   13 and the Google guide's CLOS section alongside.
4. **Read a client,** the test client in `tests/client/`. It is about 250
   lines and uses most extension points.
5. **Change something small and watch it live.** Start the image from
   Emacs with SLY as `../docs/emacs.md` describes, and redefine a
   function. Then do it again properly: in the file, with a test, through
   the build.
6. **Then the style sources,** Google's guide and PAIP chapter 3, with this
   codebase in front of you.
