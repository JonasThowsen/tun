# The tun command

Status: v1, 2026-10-12. `tun` is how a person or an agent finds the modules
Tun offers, starts a client repository from them, adds a module to a
client later, and moves a client to a newer Tun. The module contract is `tun-platform.md`; this document is the
command's contract and the shape of the client it creates. `tun preview`
and `tun check`, which run a client's working tree and its browser
checks, are in `preview.md`; `tun loop`, the feature loop, is in
`loop.md`.

## 1. Where it runs

| Where | Command | Tun revision it describes |
|---|---|---|
| Any machine with Nix and access to the repository | `nix run git+ssh://git@github.com/JonasThowsen/tun -- COMMAND` | the head of `main` |
| Tun's dev shell | `bin/tun COMMAND` | this checkout's working tree |
| A client's dev shell | `tun COMMAND` | the revision the client pins |

The program loads the kernel and every module of its revision, so what it
reports is read from the modules' own definitions. There is no catalog file
to keep in step with them.

Results go to standard output. Errors go to standard error as one line that
starts with `tun: `. Exit status: 0 on success, 1 when a step fails (such as
`nix flake lock`), 2 for a usage error, including an unknown module or an
invalid name. A usage error changes nothing on disk.

## 2. `tun list [--json] [MODULE...]`

Lists every module of the revision. Without MODULE, one entry per module:
its name, its description and the modules it depends on. With MODULE
names, the details of those modules: dependencies, core range, entities
(name and label), operations, screens, settings, workflows, message
templates and extension points.

`--json` prints one object, always with every module in full detail, so an
agent needs one call:

```json
{"core_version": "1.23.0", "revision": "…",
 "modules": [{"name": "orders", "system": "tun-orders", "description": "…",
              "depends_on": ["customers", "…"], "core_range": [">= 1.2.0", "< 2.0"],
              "entities": [{"name": "order", "label": "Ordre"}],
              "operations": ["orders_create", "…"], "screens": ["…"],
              "settings": ["…"], "workflows": ["…"], "message_templates": ["…"],
              "extension_points": ["…"]}]}
```

`revision` is the commit the program was built from, or `unknown`. A
MODULE that does not exist is a usage error naming the modules that do.

## 3. `tun new NAME [MODULE...] [--dir DIR] [--tun-url URL] [--rev REV]`

Creates a client repository in DIR (default `./NAME`), which must not exist
or must be empty.

- **NAME** matches `[a-z][a-z0-9-]*`, is at most 40 characters, and is
  neither `tun` nor starts with `tun-`, the names of Tun's own systems. It
  names the client's ASDF system, its package (upcased), its application
  class and its server program (`NAME-server`).
- **Modules** are the ones named plus every module they depend on. With no
  module, the client runs on the kernel alone.
- **URL** is where the client's flake fetches Tun, default
  `git+ssh://git@github.com/JonasThowsen/tun`, or the `TUN_URL` environment
  variable. The repository is private, so SSH access to it is what a
  machine that builds the client needs.
- **Pins.** The flake has one input for the kernel (`URL?ref=main`) and one
  per module (`URL?ref=main&dir=modules/M`), so each can move on its own
  later (`tun-platform.md` §4). `tun new` locks all of them at one revision:
  REV when given, else the revision the program was built from when that is
  a commit, else the head of `main`. The flake's `nixploy` input
  (`deploy.md`) is locked at the head of its repository.

It writes the files of §6, runs `git init` and `git add` (Nix reads only
files git knows about), and locks the flake. It makes no commit. Afterwards,
in DIR, `nix build` builds the server and `bin/test` passes.

## 4. `tun add MODULE... [--dir DIR]`

Adds modules to the client in DIR (default: the current directory). Each
named module and every dependency the client lacks is added to:

1. the flake's inputs, after the last `inputs.<name>.url` line of
   `flake.nix`;
2. the `:depends-on` list that starts with `"tun"` in the `.asd` at the top
   of DIR: the named modules only;
3. the `(:modules …)` option of `define-application` in a `.lisp` file at
   the top of DIR: the named modules only.

Each new input is locked at the revision the client's `tun` input is
locked to, so the kernel and every module stay at one revision. Existing
pins do not move. When the client already has every module named, `tun
add` says so and changes nothing. When one of the three places is not
found, or locking fails, the client is left as it was and `tun add` says
what went wrong.

## 5. `tun update [--rev REV] [--dir DIR]`

Moves the client in DIR (default: the current directory) to one Tun
revision: REV when given, else the head of `main`. Its Tun inputs are the
`tun` input and every input in the same repository, which is every module
input `tun new` and `tun add` write. `nix flake update` is not the way to
do this: `nix flake update tun` moves the kernel alone, and a plain `nix
flake update` fetches each input separately, so a push in between could
leave them at different commits.

1. **The revision.** With `--rev`, REV, a full commit hash of Tun's
   repository. Without it, the head of the ref in the `tun` input's URL
   (`ref=main`, as `tun new` writes it), read once with `git ls-remote`.
   A `tun` input that is not a `git+` URL needs `--rev`.
2. **The lock.** Each Tun input is locked at that revision in `flake.lock`,
   in one `nix flake lock` with an `--override-input` per input. `flake.nix`
   does not change: its URLs keep `ref=main`, so `tun add` and the next
   `tun update` still follow `main`. Other inputs, such as `nixploy`, keep
   their pins.
3. **The result.** For each Tun input that moved, the revision it was
   locked at and the one it is locked at now, and a reminder to run `bin/test` before
   committing `flake.lock`. When every Tun input is already locked at the
   revision, `tun update` says so and changes nothing.

When the client has no `flake.nix` with a `tun` input or no `flake.lock`
that pins it, when the head cannot be read, or when locking fails or
leaves an input at another revision, `flake.lock` is left as it was and
`tun update` says what went wrong (exit 1). A REV that is not a full
commit hash is a usage error.

## 6. The client `tun new` creates

```
NAME/
  flake.nix            Tun, module and nixploy inputs; server, image, app,
                       nixploy configuration and dev shell
  flake.lock
  deploy.nix           nixploy targets, none at first (deploy.md)
  NAME.asd             systems NAME and NAME/tests
  package.lisp         (defpackage #:NAME (:use #:cl #:tun) …)
  application.lisp     define-application with (:modules …)
  tests/package.lisp   the suite
  tests/scenarios.lisp the default scenario a preview starts from (preview.md 3)
  tests/tests.lisp     the public-interface check; the application opens;
                       every scenario makes its records
  tests/run.lisp       what bin/test runs
  bin/test             compile strictly, run the suite
  bin/serve            serve from the working tree with a local Postgres
  .envrc               use flake
  .gitignore           .direnv/, .data/, result
  AGENTS.md            how to work in the repository, for agents and people
  README.md
```

- `nix build` builds `NAME-server` with Tun's `buildClient` from the pinned
  kernel and modules. `nix run . -- --port N` serves it, with the database
  from `--db` or `DATABASE_URL` (`store.md` §1, `deploy.md` §1).
- `nix develop` (or direnv through `.envrc`) gives SBCL with the pinned
  kernel, the pinned modules, Tun's test support, FiveAM and Slynk, plus
  Postgres and `tun` at the pinned revision. `TUN_SOURCE` names the pinned
  Tun source, so its documentation is at `$TUN_SOURCE/docs`. The client's
  own systems join ASDF's source registry, so `M-x sly` in an editor that
  takes the shell from `.envrc` can load them. The shell also has
  `nixploy`, `sops` for a target's secrets, `tun-with-postgres`, and
  `tun-check-python`, which `tun check` runs browser checks with
  (`preview.md` §4).
- `nix build .#docker` builds the image, and the `nixploy` output deploys
  it to the targets in `deploy.nix` (`deploy.md`).
- `bin/test` compiles the client and its tests and fails on any compiler
  warning (loading a compiled file redefines its macros, which is not
  one), then runs the suite with a throwaway Postgres server
  (`tun-with-postgres`, Tun's `bin/with-postgres`; `TUN_TEST_POSTGRES`
  names it). The generated suite checks that the client's package uses
  only `CL` and `TUN`, that its sources use only Tun's public interface,
  that the application opens on a fresh Postgres database, which runs
  every record policy and query (`store.md` §6, §5), and enables the
  modules it names, and that every scenario makes its records
  (`preview.md` §3).
- `bin/serve [--port N]` serves the working tree on `127.0.0.1:N` (default
  8080) against a Postgres server of the client's own under
  `.data/postgres`, reachable only through a socket in that directory. The
  first run creates it; later runs keep its data. When `bin/serve` ends, by
  an interrupt or a TERM signal too, it stops the Postgres server it
  started.

## 7. Evidence

`bin/test` runs `tests/cli-tests.lisp` in the core suite: the catalog, name
checks, the files of a new client, the edits of §4, which inputs `tun
update` moves and where it reads the head, refusals that change nothing,
and exit statuses. It also checks the shell syntax of the
templates' scripts.

`bin/test-cli` runs the whole path, which builds with Nix and takes
minutes. It commits the working tree to a temporary clone of Tun and,
with the clone's own Nix-built `tun`:

1. runs `tun new` with two modules, and checks that every input is locked
   at the clone's revision;
2. builds the client and runs its `bin/test`; adds a macro, a query and
   an entity with a record policy and checks that `bin/test` passes, then names a
   missing column in each in turn and checks that `bin/test` fails naming
   the policy's entity and role, or the query, and the column
   (`store.md` §6.6, §5.7); then builds its image and
   runs it as nixploy would, and again on a restored dump of its database
   (`deploy.md` §5);
3. runs `bin/serve`, checks `/health` and that the server uses its own
   Postgres, stops it, and checks that its Postgres server stopped too;
4. runs `tun add` with a module that brings a dependency, checks the
   three edits and the pins, and that a second `tun add` changes nothing;
5. builds and tests again;
6. makes a second commit in the clone, runs `tun update`, and checks that
   every Tun input is locked at the new commit, that `nixploy` did not
   move, and that a second `tun update` changes nothing;
7. builds and tests again.
