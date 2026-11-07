# A client in a subdirectory of a larger repository

- loop: client-subdir
- mode: hands-on
- stage: done
- base: 64947260be8ad3f58c3c4523f43e48634ca3c762
- item: sak_rzxz10fq0q0ag96p
- verified: 52992522844654f354b82863ab24ccedd6c35585
- shown: 52992522844654f354b82863ab24ccedd6c35585

## Brief

Ferdig sak_rzxz10fq0q0ag96p, for Factory 5 (sak_kqdwrzrn7c0cfvws): the
private monorepo tunworks (~/coding/tunworks) holds the software factory's
applications, ferdig and nixploy-dashboard among them, under `apps/X`, each
still its own Tun client with its own flake and deployment. Jonas,
2026-11-03: «separate apps and deployments, but inside a monorepo for better
organization»; 2026-11-04: «you should basically just start creating the
monorepo for this software factory», and he authorised the loops it needs.

Reading the code found what breaks for a client at `apps/X`:
`tun loop` takes the git repository's top as its own (`repository-top`,
src/cli/loop.lisp), so records land in the monorepo's root `loops/`, two
applications' open loops refuse each other, verify runs the root's
`bin/test`, and trees and diffs take the whole repository; `tun new` always
runs `git init`, nesting a repository; `tun preview` marks a client dirty
for any uncommitted change anywhere in the repository. `tun update`, `add`,
`check` and `preview` already take `--dir`.

## Criteria

1. In a repository with clients at `apps/a` and `apps/b` (each a
   `flake.nix` and an `.asd`), `tun loop start` in `apps/a`, or with
   `--dir apps/a/src`, writes `apps/a/loops/NAME.md`; `tun loop status` in
   `apps/a` finds it, in `apps/b` does not.
2. With an open loop in each of `apps/a` and `apps/b`, `tun loop status`
   without NAME in each finds its own, and does not refuse for several.
3. `tun loop verify` in `apps/a` runs `apps/a/bin/test`, and its logs are
   under `apps/a/.build/loop/NAME/`.
4. A file committed in `apps/b`, or at the repository's root, after
   `apps/a`'s loop passed verify leaves its tree as verified: `gate B` on
   the shown tree goes on, and the packet's `diff.patch` holds `apps/a`'s
   changed files only, with paths from `apps/a` (`b/pages.lisp`, not
   `b/apps/a/pages.lisp`).
5. A commit holding `apps/a`'s shown tree passes `gate C`, also when it
   holds changes elsewhere in the repository too.
6. In Tun's repository, `checks/showcase/` (a client of its own) has
   Tun's top: a loop started there is Tun's, as today.
7. A loop in a client at the top of its own repository runs as before:
   the existing loop tests pass unchanged.
8. `tun new` into a directory inside a git repository runs no
   `git init`: the new directory has no `.git`, and its files are known
   to the enclosing repository (`git ls-files`).
9. A preview's revision is `-dirty` when the client's directory has an
   uncommitted change, and clean when only another directory of the
   repository has one.
10. A client made by `tun new` builds the same image (the same
    derivation for `.#docker`) after a commit that changes none of its
    own files, such as one to `deploy.nix` or to another application of a
    monorepo; its nixploy targets carry the commit as
    `run.environment.TUN_CLIENT_REVISION`, and `introspect_runtime`
    reports it as `client_revision` (spec/deploy.md §2, §3).
11. A client whose flake still passes `revision = self.rev` to
    `buildClient` and fills in targets with `deployTarget` builds and
    deploys as before.

## Decisions

- The loop's top is found by walking up from the directory to the
  repository's top and taking the first directory with a `flake.nix` and
  an `.asd` at its top, the same test `tun` uses for a client elsewhere
  (`client-name`). In Tun's repository the top is always Tun's, since its
  showcase and test client are clients too and a loop there is Tun's.
- A loop's tree is the tree of its top (`git write-tree --prefix`), and a
  commit's tree is the commit's tree at that directory. At the repository's
  top that is the same tree as today. Both sides of a diff are computed the
  same way, so the diff needs no pathspec (a `.` pathspec filters every
  path of a subtree out) and paths are from the top.
- A base from before the directory was in the repository is the empty
  tree, so a loop started right after an application moved in by
  `git subtree add` still works from its next commit.
- The template's `revision = self.rev` gave every application in a
  monorepo a new image on any commit anywhere in it. Jonas at gate A,
  2026-11-07: «ja, but include the revision = self.rev». The commit
  leaves the build: the image depends only on the client's files, kernel
  and modules, and the commit reaches the server at start as
  `TUN_CLIENT_REVISION` in the target's environment (`deployTargets`),
  which `introspect_runtime` already reads before the built-in value.
  The server's launcher keeps a value given at start over the built-in
  one. Nix cannot see which commit last touched a directory, so the
  revision a target reports is the commit it was deployed from, as
  today; only the image stops changing with it.
- Existing clients (ferdig, nixploy-dashboard, kurs) keep their flakes
  and build as before; each moves to `deployTargets` when it moves into
  tunworks or by hand. `tun update` does not rewrite a client's
  `flake.nix`.
- Not changed: ferdig's `bin/loop-tracker` names its project after the
  main checkout's directory; in tunworks that is `tunworks`, so each
  application sets `FERDIG_PROJECT`. That is ferdig's side.
- A core minor version: Tun's flake library gains `deployTargets`, which
  a client's flake uses (the rest is in the `tun` command only).

## Log

- 2026-11-04 18:39  started, hands-on
- 2026-11-04 18:41  gate A asked of the person
- 2026-11-04 18:41  gate A asked of jonas in Ferdig, question kom_3k1j70xes5mgdaa4 on sak_rzxz10fq0q0ag96p
- 2026-11-04 19:29  while waiting at gate A: the change drafted in the worktree, uncommitted; bin/build has 0 warnings and the loop, cli and preview suites pass (bin/test --only); verify waits for the approval
- 2026-11-07 13:22  gate A: changes (jonas): «ja, but include the revision = self.rev»
- 2026-11-07 13:23  rebased: tun 0a0bec3 → 14c0124
- 2026-11-07 13:24  gate A asked of the person
- 2026-11-07 13:25  gate A asked again of jonas in Ferdig, question kom_nt40d6ptds4xy4m7 on sak_rzxz10fq0q0ag96p, with the revision included
- 2026-11-07 13:59  while waiting at gate A: the revision drafted (deployTargets, the launcher keeps a TUN_CLIENT_REVISION given at start, the template, core 2.9.0); bin/build 0 warnings, bin/test-cli passes with the new revision step; uncommitted
- 2026-11-07 19:54  gate A: approve (jonas): «ja»
- 2026-11-07 19:54  rebased: tun 14c0124 → 6494726
- 2026-11-07 20:02  verify 1: failed check
- 2026-11-07 20:09  verify 2: passed build, test, check
- 2026-11-07 20:14  bin/test-cli passes on the verified commit (the new revision step included); verify round 1 failed only push-notification-opens-its-page (a 30 s Playwright timeout under load), round 2 passed unchanged
- 2026-11-07 20:15  shown (/)
- 2026-11-07 20:15  gate B asked of the person
- 2026-11-07 20:15  gate B asked of jonas in Ferdig, question kom_t95d8wb8aazqrzkj on sak_rzxz10fq0q0ag96p
- 2026-11-07 22:18  gate B: approve (jonas): «ja»
- 2026-11-07 22:18  finished at tun d660ec4
