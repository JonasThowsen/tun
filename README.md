# tun

A *tun* is the yard of a Norwegian farm: separate buildings (låve, stabbur,
smie) grouped around one shared yard. No two farms have the same set of
buildings, but they all share the yard.

`tun` is that for small and medium-sized businesses: a composable platform of
modules (the buildings) around a shared core (the yard), with one data model,
one agent layer, and one link to the company's accounting system. Each client
gets the modules they need, extended to fit, and can add more later.

> Status: platform under construction, in Common Lisp.

## Why

Most SMBs run a patchwork of SaaS tools that don't talk to each other, and
their vendors were built before the AI boom. The hypothesis `tun` exists to
test:

> A custom, composable business platform with AI and MCP built into every
> operation, connected to the client's accounting system, can be delivered at
> a price SMBs can afford, because the platform does most of the work and each
> client only pays for their own extensions.

`tun` grows out of an earlier ERP built for one rental business (Elixir/Ash).
It does not port that code; it carries over what proved itself there (domain
contracts with ports and adapters, a careful agent layer, credential
isolation) and fixes its main structural lesson: being agent-accessible is a
property of every operation by construction, not a parallel layer someone has
to remember to write.

## Why Common Lisp

Tun was chosen after building the same platform in several languages against
one contract and one acceptance suite. Common Lisp needed the smallest kernel
and client change per feature. A fresh agent could build a client feature
from the docs alone and diagnose a planted bug down to the exact expression.
A live fix could be applied to a running tenant with no lost requests.

The language is the reason to expect that lead to hold. Macros make "one
definition, every surface" a few defining forms rather than a framework. The
image is live and introspectable, and code reloads without a restart. The
hot paths can be made fast where it counts. Coalton offers static types
inside Lisp, but is not ready for Tun yet (see `reference/coalton.md`). The
price is writing some plumbing ourselves.

## What exists

- **A kernel:** registry, policy, confirmation, idempotency, audit, store,
  scheduler and durable workflows, typed settings, link tokens,
  introspection with request traces, a Swank REPL and a read-only `eval`.
- **Twelve modules:** customers, catalog, inventory, reviews, orders,
  invoicing, staffing, calendar, warehouse, inbox, notifications, messaging.
- **Two clients for Tun's own checks:** the test client in `tests/client/`,
  a small rental business that exercises the main extension points, and
  the showcase in `checks/showcase/`, which `bin/check` drives in a browser.
  A real client lives in its own repository: a flake pinning the kernel and
  every module by revision.
- **The `tun` command:** `tun list` describes every module from its own
  code, `tun new` creates a client repository pinned at one Tun revision,
  `tun add` enables another module in one, and `tun update` moves it to a
  newer revision (`spec/cli.md`). The client
  builds an OCI image and carries a nixploy configuration for its servers
  (`spec/deploy.md`).
- **Generated HTML screens,** public customer pages and the MCP server.
- **Fake adapters** for accounting, mail delivery and inbound mail behind
  their ports. No external service is called.
- **Tests:** the kernel and module suite, the test client's suite, and
  browser checks on the showcase.

## Where to read

| To | Read |
|---|---|
| Understand the platform | `docs/architecture.md` |
| Extend it as a client | `docs/client-api.md` |
| Write Common Lisp the way this codebase does | `reference/README.md` |
| Know what behaviour is promised | `spec/README.md` |
| Work on it from Emacs | `docs/emacs.md` |

## Layout

```
tun.asd, flake.nix   the kernel's ASDF systems and the Nix flake
tun-cli.asd          the tun command (src/cli/), and the files of a new client
tun-test-support.asd test helpers for the kernel's suite and every client's
src/                 kernel: core, store, platform, agent (MCP, HTTP), web, ports, adapters
modules/<name>/      the business modules, one ASDF system and flake each
clients/<name>/      clients you add locally, separate flakes pinning core and modules (none are committed)
tests/               the kernel and module suite; tests/client/ is the test client
checks/showcase/     the client Tun's browser checks drive
spec/                behaviour contracts
reference/           Common Lisp style, idioms, pitfalls and sources
docs/, bin/, scripts/
```

## Running

Inside `nix develop .`:

```
bin/build          compile everything, zero warnings allowed
bin/test           kernel and module suite, boundary checks, the test client, any clients/
bin/serve          start a client on a port: bin/serve --client NAME --port N --db PATH|URL
bin/repl           an image with Tun loaded, for Emacs and SLY (docs/emacs.md)
bin/check          Tun's browser checks, on the showcase client, in Chromium
bin/with-postgres  run a command against a throwaway Postgres (spec/store.md)
bin/tun            the tun command from this checkout: list, new, add, update (spec/cli.md)
lisp               an image for an agent, with SLY's debugger as a command (docs/lisp.md)
bin/test-cli       tun new, build, test, image, restore, serve, tun add and tun update, with Nix
bin/drift          the code a running server has loaded, against this checkout
```

## Conventions

- Code identifiers in English. Norwegian in labels, descriptions and
  user-facing copy. Preserve `æ`, `ø` and `å`.
- A client extends through published extension points only. The build
  refuses a client that reaches into internals.
- Behaviour that matters is in `spec/` first and in a test or check second.
  Work is done only when it passes from committed state.

## Next

The foundation comes first:

1. **Make the codebase a reference.** Go through the kernel file by file:
   readable formatting, comments that explain the code rather than its review
   history, tests grouped by subject.
2. **A first deployed client.** A client from `tun new` builds its image
   and has a nixploy configuration; next, one runs on a server with its own
   Postgres database and domain.
3. **The change model.** Git is the source of truth, and a live load is a
   delivery path for a commit, never a second history.
4. **The interview** as an agent skill that writes the brief `tun new` reads.
5. **Brief to tenant:** a fresh agent turns a customer's brief into a running
   preview tenant.

## Licence

MIT. See `LICENSE`.

## Contributing

Issues and pull requests are welcome. Read `AGENTS.md` first: it holds the
working rules for people and agents alike, and `bin/build` and `bin/test`
must pass.
