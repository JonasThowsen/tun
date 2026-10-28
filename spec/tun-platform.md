# Tun platform contract: core, modules, clients, tenants

Status: v1, 2026-10-09. Language-neutral. Builds on `core.md`, the base
contract (MCP surface, policy, confirmation, idempotency, audit, workflows,
tenants, pressure, introspection). This document adds the one concept the
base contract leaves out: the **module**, a reusable domain package between
core and a client. Tun implements it in Common Lisp; tests and
acceptance checks verify it from the outside.

## 1. Vocabulary

- **Core** (kernel): registry, policy, confirmation, idempotency, audit, store,
  scheduler and workflows, messaging port, UI generator, introspection. Core
  owns no business entities except its system ones (`core.md` §3.10: audit, clock,
  accounting status, workflows, messages).
- **Module**: a package of business behaviour that more than one client can
  enable: entities, operations, rules, computed fields, workflows, message
  templates, screens, migrations, plus the extension points it publishes.
  Examples: `customers`, `catalog`, `inventory`, `orders`,
  `invoicing`, `messaging`, `staffing`, `calendar`.
- **Client**: one business's own code. It enables a set of modules, extends
  them through their published extension points, and adds entities,
  operations, workflows and screens of its own. A client is a separate flake
  that pins core and every module by git revision (`core.md` §6.1).
- **Tenant**: one deployed client: one process, one database, one pin set.

## 2. Module contract

1. **Identity**: a module has a name (`[a-z][a-z0-9_]*`), lives in its own
   directory (`modules/<name>/`), and is pinned by git
   revision like core. The core package and the modules may share a repository
   and a revision; a client pins each separately so one can move without the
   others.
2. **Dependencies**: a module declares the modules it depends on. Dependency
   cycles are refused at build time. A module may extend an entity of a module
   it depends on, never one it does not.
3. **Boundary**: the same rule as core and client (`core.md` §1.2): a module reaches
   other modules and core only through their public interfaces, and the public
   interface test (compiler, reader or loader) covers modules too. What a module
   exports to clients is its public interface; the rest is internal.
4. **Extension points**: a module publishes the same kinds as a client adds (`core.md` §1.1: field,
   rule, computed, before/after an operation, operation, workflow, template,
   screen) plus any named seam its domain needs (the orders module has, among others, discount,
   requirements, booking window). Every published point is listed by
   `introspect_extensions` and `registry_describe` with its owning module.
5. **Data**: a module owns its entities and their tables; another module or the
   client refers to them by public ids only. Client fields on a module's entity
   are stored apart from the module's columns (`ext`), so the module's migrations never see
   them.
6. **Migrations**: ordered, idempotent, namespaced per module
   (`<module>_<nnnn>_<name>`), run at start in dependency order, recorded per
   module. A migration one step back must be safe to run the previous revision
   against (rollback rule, §4).
7. **Hooks and rules across modules**: run in a deterministic order:
   dependency order of the modules, then the client, last. The order is
   reported by `explain` and `introspect_extensions`.
8. **Conflicts** are refused at startup, never resolved silently: two modules
   adding the same field or operation name, a client overriding a module's
   template that the module marked final, a rule attached to an entity that
   runs no rules.
9. **Registry**: `registry_describe` keeps `"source": "core" |
   "client"` and gains `"module": "core" | "<module>" | "client"` on every
   entity, field, operation, rule, workflow, template and screen, plus
   `modules` and `extension_points` lists.

## 3. Composition in a client

A client's manifest (data in its repository: the flake inputs plus a small
declaration) says which modules it enables and at which pins. Enabling a
module enables its dependencies. The harness reads the effective module set
through `introspect_runtime.modules` (name, revision, dependencies, enabled
by: client or dependency).

## 4. Pins, upgrades, rollback

- Build: a client builds from its own flake with the pinned core and
  modules; the committed lock is never modified by a check.
- Upgrade one pin (`core.md` §6.3): build at the old pins, run the
  module's acceptance `--phase before` on a fresh database, bump that one pin
  in a temporary copy, build, run `--phase after` on the same database. Core
  is one more pin.
- Rollback: re-pin one step back and restart on the same database; it must
  pass that module's `--phase before` again. A module whose migration cannot be rolled back one step says so in
  its README, and the upgrade command refuses `rollback` for it.
  A core from 1.23.1 on refuses to start on a database a higher core
  major has opened (`store.md` §2, item 10); an earlier one is not
  checked.
- Compatibility: a module's README states the core revision range it builds
  against. A client build fails, with the constraint named, when a pin is
  outside the range.

## 5. Evidence a module change ships

For every module a change introduces or changes:

- acceptance checks runnable against a tenant that enables only that module
  and its dependencies, with `--phase before|after|full` where an upgrade
  scenario exists;
- a second client that enables the module with a different extension,
  proving the module is not shaped like the first client;
- results for both clients at their committed pins, and one module upgrade
  and one rollback demonstrated;
- in the module's README: what is proven, by which run, and
  what is not.

## 6. What stays open

Deferred until a client needs it: module-level policy roles beyond
viewer/employee/admin, cross-tenant shared modules at runtime (none: tenants
are isolated processes), module marketplaces, and module-specific UI themes.
