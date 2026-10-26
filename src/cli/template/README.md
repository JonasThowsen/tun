# {{name}}

A client of Tun. `AGENTS.md` says how to work on it.

```
nix develop        the dev shell (or: direnv allow)
bin/test           compile strictly and run the tests
bin/serve          serve on http://127.0.0.1:8080 with a local Postgres
nix build          build the server, result/bin/{{name}}-server
nix build .#docker build the image nixploy deploys
tun list           the modules Tun offers
tun add MODULE     enable a module
tun update         move Tun and every module to the head of main
```

## Deploying

`deploy.nix` lists the servers {{name}} runs on, as nixploy targets; it
starts empty, with an example. A target needs a Podman host with Caddy, a
Postgres database on that host, a DNS record for its domain, and its
`DATABASE_URL` and WorkOS settings in a SOPS-encrypted secret: in the
WorkOS dashboard, a first-party OAuth application (Connect → OAuth
applications) whose redirect URI is `https://DOMAIN/auth/workos/callback`
gives `WORKOS_CLIENT_ID` and `WORKOS_CLIENT_SECRET`, and `WORKOS_DOMAIN`
is the environment's AuthKit domain. The database is all of
{{name}}'s data, so the host backs it up and copies the backups off the
machine (`$TUN_SOURCE/spec/deploy.md` §4 has the configuration and the
restore). Then:

```
nixploy deploy --target production --dry-run
nixploy deploy --target production
nixploy status --target production
```

## Accounts and agents

A new server has no accounts. At start it prints a one-time link for the
first administrator, which `bin/serve` shows in its output and
`nixploy logs --target production` shows on a server:

```
tun: no administrator yet; create one at /setup/CODE
```

Open it, choose a name and «Fortsett», and sign in through WorkOS; that
makes you the administrator. Then add people and agents at `/access`. A
person signs in through WorkOS with the email their account has.
Claude Code connects as you through WorkOS, once you have signed in in
the browser, with `claude mcp add --transport http {{name}}
https://DOMAIN/mcp` (in the WorkOS dashboard, turn on Client ID Metadata
Documents and Dynamic Client Registration, and add `https://DOMAIN/mcp`
as a Resource Indicator). Agents and scripts use access tokens:
everyone makes them for their own account there, and an admin makes them
for agent accounts. A token acts as its account, never as more, and is shown once;
Claude Code connects with it:

```
claude mcp add --transport http {{name}} https://DOMAIN/mcp \
  --header "Authorization: Bearer TOKEN"
```

Locally, `bin/serve --claimed-identity` needs no WorkOS: it lets any
request name its own actor, as `/login?actor=admin:you` or an `X-Tun-Actor` header. That is for
local work only; a deployed server never runs that way
(`$TUN_SOURCE/spec/auth.md`).
