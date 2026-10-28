# spec

The behaviour Tun promises. Change a contract here before changing the
behaviour, and run the suites before calling work done.

| File | Contract |
|---|---|
| `core.md` | The base contract: core and clients, conventions and local time, the MCP surface with policy, confirmation, idempotency and audit, workflows, ports and settings, tenants and the rollback preflight, runtime properties, introspection. |
| `tun-platform.md` | Modules: identity, dependencies, boundary, extension points, migrations, pins, upgrade and rollback. |
| `store.md` | The store adapters (memory, SQLite, Postgres): selection, shared transaction and ordering rules, two processes on one database. |
| `cli.md` | The `tun` command: listing modules, creating a client repository, adding a module, moving a client to a newer Tun, and the shape of the client it creates. |
| `deploy.md` | Deploying a client: the server's port and database, the image, nixploy targets, backups and restore. |
| `api.md` | The HTTP API: `POST /api/TOOL` with a bearer token, for systems that are not agents. |
| `waiting.md` | Waiting for people: `:kind :wait` operations and `await`, long calls over MCP (SSE with progress) and the API, instructions for agents. |
| `outbound.md` | Calling other systems: `http-json-post` with its failures, trace and test stub, and settings read from the environment. |
| `auth.md` | Identity and access: accounts, sign-in through identity providers such as WorkOS, access tokens, sessions, the first administrator, MCP authentication. |
| `mail.md` | Sending mail: the provider (Resend), the queue in the sender's transaction, delivery with retries, the admin tools. |
| `push.md` | Push notifications to an installed app: turning them on per device, `notify-push`, delivery with retries, Web Push encryption and VAPID, the service worker. |
| `jobs.md` | Background jobs with retries, unique jobs, queues, crash recovery, schedules in the tenant's time zone, and triggers that run a job for each record meeting a condition. |
| `errors.md` | Errors and logs: faults grouped by cause and kept in the store, a mail when a new one appears, a JSON log line per request, and the dashboard's «Feil» and «Logg». |
| `files.md` | Files attached to records: which entities take them, the types decided by their bytes, metadata taken out, the `files` type and the attachment tools, request size, storage in Postgres, who may fetch a file, and the form control and thumbnails. |
| `i18n.md` | Languages, money and time per tenant: copy in English with catalogues per language, English identifiers and core 2.0's migration, currencies and minor units, time zones, formats. |
| `ui.md` | The design system: tokens, components, generated screens, a client's own pages, installing as an app. |
| `tooling.md` | Development tooling: indentation, the editor REPL, the agent REPL and lint. |
| `feedback.md` | Draft, not built: reporting from any page of a client into the supplier's tracker, the first link between Tun systems. |
| `preview.md` | Previews and checks: `tun preview` (a working tree at a tailnet link, fresh data, anyone's sign-in), scenarios, and browser checks run by `tun check`. |
| `loop.md` | The feature loop: a request taken to a deploy through fixed stages, with gates a person or a reviewer approves; its record in `loops/`, and `tun loop`. |
| `fleet.md` | Idea, not planned: one Tun system that knows every tenant, for agents debugging them. |

## Modules

Each business module's contract is the `## Contract` part of its
`modules/NAME/README.md`: its entities, states, rules, operations, workflows
and seams. Code comments cite them as `orders README §3`, and this
directory's documents as `core.md §3.6`.

## Running

From the repository root, inside `nix develop .`:

```
bin/test                          the kernel and module suite, the test client, any clients/
bin/with-postgres COMMAND...      COMMAND against a throwaway Postgres (store.md 5)
bin/check                         Tun's own browser checks, on the showcase client (preview.md 4)
bin/test-cli                      the tun command end to end: new, build, test, image, serve, preview, check, add
```
