# Working on tun

Read `README.md` first, then `docs/architecture.md` (how the platform works)
and `docs/client-api.md` (how a client extends it). Before writing Lisp, read
`reference/style.md` and `reference/pitfalls.md`.

- The platform is this repository: `tun.asd` and `src/` (kernel) and
  `modules/`. Clients live in their own repositories (`tun new`); `clients/`
  only holds ones you add locally, and `tests/client/` is the test client
  the kernel's suite runs the client surface on. `spec/` is the contract:
  change the spec before changing behaviour, and run the suites before
  claiming anything is done.
- A request to change what Tun does runs the feature loop
  (`docs/loop.md`): fixed stages, gates a person or a reviewer approves,
  and `bin/tun loop status` to find where an open loop is.
- Work inside `nix develop .`. `bin/build` must stay warning-free and
  `bin/test` must stay green. The suites run from committed state.
- People edit their own checkout and meet agents through git
  (`docs/emacs.md`). On a shared machine, work on your own branch or worktree,
  and start your own image rather than using one someone else is connected
  to: `lisp start`, then `lisp eval` and its debugger (`docs/lisp.md`).
- A client reaches core and modules only through their public interface; the
  build gate refuses anything else. Modules declare their dependencies and
  the kernel range they build against; clients pin every module by revision.
- Write code a reader can follow: follow `reference/style.md`, copy the
  nearest good example in this repository, and when unsure how idiomatic
  Lisp does something, read the sources listed in `reference/sources.md`
  rather than guessing.
- Comments explain what the code does and why. They do not narrate review
  rounds, finding numbers or history; that belongs in commit messages.
- Code identifiers in English, stored values and keys included. Copy is
  written in English and translated in catalogues, Norwegian (bokmål)
  among them, keeping `æ`, `ø` and `å` (`spec/i18n.md`).
- No production deployments, credentials, publishing, pushes to remotes, or
  external infrastructure changes without explicit authorization. Every
  external system sits behind a port with a fake adapter.
