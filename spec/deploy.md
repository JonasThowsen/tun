# Deploying a client

Status: v1, 2026-10-12. How a client repository that `tun new` created
(`cli.md` §6) runs on a server. Tun builds the image and fills in what
every Tun server needs; [nixploy](https://github.com/JonasThowsen/nixploy)
deploys it to a Podman host over SSH, behind Caddy, with blue/green slots.

## 1. The server process

The server takes its port and database from flags or, as a container
needs, from the environment:

- `--port N`, else the `PORT` environment variable, else 8080. A `PORT`
  that is not a port number is refused at start (exit 2).
- `--db PATH|URL`, else `DATABASE_URL` (`store.md` §1).
- `--public-url URL`, else `PUBLIC_URL`: where people reach the server,
  such as `https://feedback.example.no`, with no path. A value that is not
  an `http` or `https` URL is refused at start (exit 2). When it is set:
  - links the server prints and sends use it: the setup line
    (`auth.md` §4), a provider's callback URL (`auth.md` §3.5), and the
    links a client or a module puts in mail, which it makes with
    `absolute-url` (`docs/client-api.md`), such as the messaging module's
    offer, feedback and unsubscribe links; without it `absolute-url`
    answers the path alone;
  - when it is `https`, every answer to a request that came over HTTPS
    carries `Strict-Transport-Security: max-age=31536000`, and a `GET` or
    `HEAD` that the proxy reports came over plain HTTP
    (`X-Forwarded-Proto: http`) is answered 301 to the same path and
    query at the public URL. Other methods, and requests without that
    header, such as the host's health checks, are answered as before.
- It listens on `127.0.0.1` unless `--address` says otherwise, so a host
  shares it only through a proxy on the same machine.
- `--trusted-proxy ADDRESS`, else `TRUSTED_PROXY`: the IP address the
  proxy in front of the server connects from, such as `127.0.0.1`. A
  value that is not an IPv4 or IPv6 address is refused at start (exit 2).
  A request from that address is counted against the client the proxy
  names in `X-Forwarded-For`, and a connection from any other address
  against its own (`core.md` §7.5). Without it, as in development, tests
  and previews, every peer is a client and `X-Forwarded-For` is not read.
- `GET /health` answers 200 once the application is open.
- It opens the database and applies pending migrations before it listens.
  Two processes may share a database while one slot replaces the other
  (`store.md` §2).

## 2. The image

`nix build .#docker` in the client builds an OCI image named after the
client, tag `latest`. Its entrypoint is the server of `nix build`, so the
image runs exactly the pinned kernel, modules and client, and any
arguments are the server's flags. It also holds CA certificates, a
writable `/tmp` and `HOME=/tmp`, and sets `LANG=C.UTF-8`. It has no shell
and no other programs. The server it starts is authenticated
(`auth.md` §1): the first start prints where to create the first
administrator, and `nixploy logs` shows it.

## 3. Targets

The client's flake has a `nixploy` output for nixploy's configuration
schema. Its targets are the attributes of `deploy.nix`, each a nixploy
target. Tun fills in, unless the target sets them:

| Field | Value |
|---|---|
| `image` | `"docker"` |
| `run.network` | `"host"`, so the server reaches a database on the host's loopback |
| `run.environment.PORT` | `"{port}"`, the slot nixploy starts |
| `run.environment.PUBLIC_URL` | `"https://"` and `web.domain`, when the target has one |
| `run.environment.TRUSTED_PROXY` | `"127.0.0.1"`, the address Caddy on the host connects from, when the target has `web.domain` |
| `web.healthPath` | `"/health"` |

A target names the rest: the host (`ip`, `user`, `identityFile`), the
domain and two free ports (`web.domain`, `web.slots`), and its secrets.

**Caddy and callers that hold connections.** nixploy writes the target's
route into Caddy, a reverse proxy to the slot on `127.0.0.1`, and nothing
in it limits connections per address. It need not: Caddy reads a
request's line and headers itself before it sends the request on, so a
caller who sends them slowly, or keeps connecting, holds Caddy's
connections and not the server's threads. Caddy ends `X-Forwarded-For`
with the address the request came from (and drops what the caller sent
there, unless told to trust other proxies), so its last entry is
Caddy's. What reaches the server through Caddy is counted by that
address (`core.md` §7.5); `TRUSTED_PROXY` tells the server that Caddy is
the peer to read it from. A CDN or another proxy in front of Caddy would
make its own addresses the clients, and every caller behind it would
share their counts, unless Caddy were told to trust it
(`trusted_proxies`), which the route nixploy writes does not do.
`tun new` writes a `deploy.nix` with no targets and an example of one.

The database URL is a secret: a SOPS-encrypted dotenv file with
`DATABASE_URL=postgresql://USER:PASSWORD@127.0.0.1/DATABASE`, named in
the target's `secrets`. The same file holds the settings a sign-in
strategy reads from the environment (`auth.md` §3.5), such as
`GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`, and those the mail provider
reads (`mail.md` §1), such as `RESEND_API_KEY` and `MAIL_FROM`, and those
the client's own settings read (`outbound.md` §3), such as
`TYPESAFE_API_KEY`. Creating
that database and role on the host, and
the DNS record for the domain, are the host's administration, outside Tun
and nixploy.

## 4. Backups and restore

A tenant's data is its Postgres database on the host: its records, its
audit, its accounts and their access tokens. The image holds none of it.
Backing the database up is the host's administration, like creating it
(§3); neither Tun nor nixploy does it.

On a NixOS host, dump the database every night:

```nix
services.postgresqlBackup = {
  enable = true;
  databases = [ "DATABASE" ];
  startAt = "*-*-* 02:15:00";
  compression = "gzip";
  # No owners or grants, so a dump loads into a database any role owns.
  pgdumpOptions = "--no-owner --no-privileges";
};
```

Each night this writes `/var/backup/postgresql/DATABASE.sql.gz`, plain
SQL readable only by the `postgres` user, and keeps the night before as
`DATABASE.prev.sql.gz`. `pgdumpOptions` replaces the module's default
`-C`, so the dump neither creates nor connects to a database of its own
name and loads into any database.

Dumps on the same disk as the database are not enough: a failed disk or a
lost machine takes them too, and only two nights are kept. Copy
`/var/backup/postgresql` off the machine after each dump, encrypted and
with a history, for example with `services.restic.backups` or
`services.borgbackup.jobs` naming that directory in `paths` and running
after `startAt`. The dumps hold customers' personal data, so the key to
the copies is kept apart from the machine. Where the copies go is the
host's choice.

Before a deploy that must be able to go back, such as a new core major,
take a dump of its own from the operator's machine. It needs no sudo on
the host, only the deploy user's ssh key and the `pg_dump` on the host's
path, and the secret is never shown:

```
sops -d secrets/TARGET.env | grep '^DATABASE_URL=' | cut -d= -f2- \
  | ssh USER@HOST 'read -r url; pg_dump --no-owner --no-privileges "$url"' \
  | gzip > TARGET-$(date +%F).sql.gz
```

The host reads `DATABASE_URL` from standard input, so it is in no file and
no shell history; it is in `pg_dump`'s arguments while the dump runs, where
other users of the host could see it. The dump lands on the operator's
machine, where the nightly rotation does not replace it, and it restores
as below.

To restore a dump, whether last night's, the one before or one fetched
from the copies, on a host where the tenant's role USER exists:

1. Create a fresh database owned by the tenant's role, and load the dump
   into it as that role, so every table belongs to the role:

   ```
   sudo -u postgres createdb --owner USER RESTORED
   gunzip -c DATABASE.sql.gz | psql -h 127.0.0.1 -U USER -d RESTORED -v ON_ERROR_STOP=1 --single-transaction
   ```

   psql asks for the role's password, the one in `DATABASE_URL`. A dump
   that does not load leaves RESTORED empty rather than half filled.
2. Point the target at it: change the database in the target's
   `DATABASE_URL` secret to RESTORED and deploy the target again. To keep
   the URL instead, stop the target's containers, rename the old database
   aside and RESTORED to its name (`ALTER DATABASE … RENAME TO …`), and
   deploy again.
3. The server opens RESTORED and applies pending migrations before it
   listens (§1), so a dump taken at an older revision is brought up to the
   running one. Setup stays closed: the administrator is in the restored
   data, so the server prints no setup link, and people sign in with the
   accounts and access tokens they had when the dump was taken.

Whatever was written after the dump is not in it. That includes
revocations: a token or account revoked or disabled since then is valid
again until an administrator revokes it again at `/access`.

## 5. Evidence

`bin/test-cli` (`cli.md` §7) builds the new client's image, loads it into
the local Podman, runs it as nixploy does (host network, `PORT` and
`DATABASE_URL` in the environment) against a Postgres server on the local
loopback, checks `/health`, takes it through setup to an access token and
an MCP call with it (`auth.md` §9), and checks that the account it made
through the server is in that database. It then dumps the database with
the options of §4, loads the dump into a new database owned by another
role that is not a superuser, runs the image on that database, and checks
that the account is there, that `/health` answers, that the token still
works and that the log has no setup line. Last, it checks that the
client's `nixploy` output evaluates with a target from `deploy.nix`, and
that a target with a domain gets `PUBLIC_URL` and `TRUSTED_PROXY`.
`tests/cli-tests.lisp` checks how the server reads `--trusted-proxy` and
`TRUSTED_PROXY`, and `tests/hostile-tests.lisp` what it counts by
address (`core.md` §7.5).
