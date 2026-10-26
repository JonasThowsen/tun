# Working on {{name}}

{{name}} is a client of Tun, a Common Lisp platform for small businesses.
The kernel and the modules come from Tun, pinned in `flake.lock`. This
repository holds only {{name}}'s own code.

- Work inside the dev shell: `nix develop`, or direnv through `.envrc`. It
  has SBCL with the pinned kernel and modules, Postgres, `tun`, `nixploy`
  and `sops`.
- `bin/test` must stay green, with no compiler warnings. `bin/serve` runs
  the working tree on http://127.0.0.1:8080 with a Postgres server of its
  own under `.data/`. `nix build` builds the server as it is deployed, and
  `nix build .#docker` its image. `deploy.nix` names the servers it is
  deployed to with nixploy (`$TUN_SOURCE/spec/deploy.md`).
- To show a change running, `tun preview` starts the working tree in the
  background with a fresh database, the records of its default scenario
  (`tests/scenarios.lisp`) and anyone's sign-in, at a link on the tailnet
  the person you work for can open on their phone; `tun preview stop NAME`
  ends it. Browser checks in `checks/*.py` drive such previews in
  Chromium, touch included: run them with `tun check`. A change to a page
  gets a check of what it promises (`$TUN_SOURCE/spec/preview.md`).
- A request to change what {{name}} does runs the feature loop
  (`$TUN_SOURCE/docs/loop.md`): fixed stages from the request to the
  deploy, gates the person you work for or a reviewer approves, and
  `tun loop status` to find where an open loop is.
- A running server knows who calls it from an account's credentials
  (`$TUN_SOURCE/spec/auth.md`): an agent reaches MCP with an access token
  from `/access`, and acts as that token's account. Ask the person you
  work for to make one; never use `--claimed-identity` outside your own
  machine.
- The client uses only Common Lisp and Tun's public interface: the `TUN`
  package, and the components in `TUN.UI` (as `ui:`) for its pages.
  `bin/test` checks this. Never use `::` into a Tun package.
- Before writing Lisp, read Tun's guides at the pinned revision:
  `$TUN_SOURCE/docs/client-api.md` (what a client can define),
  `$TUN_SOURCE/reference/style.md` and `$TUN_SOURCE/reference/pitfalls.md`.
- `tun list` shows the modules Tun offers at the pinned revision, and
  `tun list MODULE` what one of them defines. `tun add MODULE` adds a
  module and its dependencies, pinned at the same revision. `tun update`
  moves Tun and every module to one newer revision; run `bin/test` before
  committing `flake.lock`. Never move one Tun input alone with `nix flake
  update`.
- Code identifiers in English; Norwegian in labels, descriptions and copy.
- No deployments, credentials, publishing or pushes without explicit
  authorization.
