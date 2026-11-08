# A deployed client reports the commit nixploy deployed, not «unknown»

- loop: deploy-revision
- mode: hands-on
- stage: build
- base: fac67a3716221af6f4d8483956b86398e693eb16
- item: sak_27f0jw32b2d1ce3v

## Brief

Found after ferdig's first production deploy from tunworks (Ferdig
sak_27f0jw32b2d1ce3v; the move is sak_rmkwcrdh8kwjgz2c; deploy
dpl_x70m7dzvdw2a0921, 2026-11-08): the deploy succeeded, and
`introspect_runtime` shows core fac67a3 (2.13.0) but `client_revision`
«unknown».

The cause, read in nixploy's source (`ocaml/lib/source.ml`): nixploy
builds a target from a copy of the repository's tracked files without
`.git`, for a pushed commit and for a working tree alike. A flake
evaluated there has no `self.rev` or `self.dirtyRev`, so 2.13.0's
`deployTargets { revision = self.rev or self.dirtyRev or "unknown"; … }`
gives «unknown». nixploy knows the commit it deploys and replaces
`{revision}` in `run.environment` with it (`configuration.ml`
`rendered_environment`, covered by its `core_test.ml`).

The change: every target gets `TUN_CLIENT_REVISION = "{revision}"` from
`deployTarget`, and `deployTargets` takes `{ targets }`, ignoring a
`revision` passed in the 2.13.0 form. spec/deploy.md §3 says where the
commit comes from and what it means for a deploy from a changed working
tree; the template and docs/architecture.md follow.

## Criteria

1. A target from `deploy.nix` evaluates with `run.environment.TUN_CLIENT_REVISION = "{revision}"`, with the tree committed or changed.
2. A target that sets `TUN_CLIENT_REVISION` itself keeps its value.
3. `deployTargets { targets = …; }` and the 2.13.0 form `{ revision = …; targets = …; }` give the same configuration.
4. `deployTarget` alone, as clients made before `deployTargets` use it, fills in `"{revision}"` too.
5. A commit of `deploy.nix` alone still builds the same image (`.#docker`'s derivation).
6. A server started with `TUN_CLIENT_REVISION` reports it as `client_revision` (unchanged, `bin/test-cli`).
7. A client made by `tun new` uses the new form, and `bin/test-cli` passes end to end.
8. Core 2.13.1; spec/deploy.md §3, docs/architecture.md and the template say the same.

## Decisions

- The commit comes from nixploy's `{revision}`, not from the flake: the flake can't see it where nixploy builds, and nixploy already names the commit it deploys.
- `-dirty` goes: nixploy names `HEAD` for a deploy from a changed working tree, and the spec says so rather than promising a marker nobody sets. nixploy-dashboard only deploys clean checkouts of pushed commits.
- `deployTargets` ignores a passed `revision` instead of refusing it, so ferdig's and nixploy-dashboard's 2.13.0 flakes evaluate unchanged until they move to the short form.
- `deployTarget` fills it in too, so older clients (passing the commit to `buildClient`) report the deployed commit as well.
- Patch version 2.13.1: a fix of 2.13.0's promise, no new interface.

## Log

- 2026-11-08 00:36  started, hands-on
- 2026-11-08 00:38  gate A asked of the person
- 2026-11-08 10:22  gate A: approve (jonas): «ja»
