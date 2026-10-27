# Tre mangler fra herdingen lukkes

- loop: hardening
- mode: autonomous
- stage: ship
- base: e2f758832363eb2cbf5f8141b9c6f4bfd4b1e3b3
- verified: cbd998b09656e75875b351ede21f1fdbea5df507
- shown: cbd998b09656e75875b351ede21f1fdbea5df507

## Brief

Three follow-ups left open by the hardening of core 1.20.0 and 1.21.0
(request bounds, the memory budget in `spec/core.md` §7.5, and files),
which Jonas asked for on 2026-10-27: «let's do the three first».

1. **Connection-thread exhaustion.** Hunchentoot runs up to 1024
   connection threads, and callers that keep reconnecting, each held up
   to the 30 s header deadline, can keep them all busy. A per-IP limit is
   the fix. Tun runs behind Caddy in production (`spec/deploy.md`, the
   template under `src/cli/template/`), so decide where it belongs: in
   Tun, counting connections per client address with the forwarded
   address trusted only from the proxy, in the generated Caddy
   configuration, or both. It must work for a tenant deployed with the
   template, and in development without a proxy. Test what lives in Tun
   with many connections from one address while another address is still
   served.
2. **The preview port race.** Two checkouts starting a preview or
   `bin/check` at the same moment can choose the same port: `choose-port`
   tests only that nothing listens on the HTTP port, and the database
   starts on that port's socket directory before the server binds. Claim
   the port atomically before using it, released when the preview stops
   or its process dies. Test two concurrent starts getting different
   ports, and a stale claim being reclaimed.
3. **`define-job` accepts a `(files …)` parameter it cannot use.**
   Enqueueing such a job fails inside the operation with «shots[0]: har
   ukjente felt: bytes». Refuse a files parameter, and any other type a
   job cannot carry, when the job is defined, as a stored files field is
   refused, with a clear message.

## Criteria

Connections per address (`spec/core.md` §7.5, `spec/deploy.md` §1, §3,
`spec/waiting.md` §1):

1. A server without `--trusted-proxy` holds 64 connections from one
   address (127.0.0.2) in their headers; the 65th from that address is
   answered `503` with `Retry-After: 1` and `Connection: close` at once,
   before it sends anything, and closed; a 65th that has already sent a
   whole request line and headers, `X-Forwarded-For: 203.0.113.9` among
   them, still reads the 503 (the header is ignored without a trusted
   proxy); meanwhile `/health` from another address (127.0.0.3) answers
   200; once one of the 64 ends, the first address is served again
   (`tests/hostile-tests.lisp`). A refused connection whose request had
   already arrived reads the 503 and then a clean end, not a reset
   (`a-refused-connection-drops-what-it-was-sent-before-it-closes`).
2. `X-Forwarded-For` is read from the trusted proxy only: on a server
   with `--trusted-proxy 127.0.0.1`, 17 requests whose bodies are still
   coming, sent at once from 127.0.0.2 with `X-Forwarded-For:
   203.0.113.7`, are all held, none answered 503, as they count as
   127.0.0.2's connections and not as that client's requests
   (`tests/hostile-tests.lisp`).
3. With `--trusted-proxy 127.0.0.1`, 16 requests for the client
   203.0.113.7 whose bodies are still coming are held; the 17th for that
   client, sent through the proxy, is answered 503 with `Retry-After: 1`
   at once, body unread; requests for 203.0.113.8, and one whose
   `X-Forwarded-For` lists 203.0.113.7 before another address, are
   answered 200; 70 connections from the proxy's own address are open
   at once, none of them having sent anything, and a request on the 70th
   is answered 200; once the 16 end, 203.0.113.7 is served again
   (`tests/hostile-tests.lisp`).
4. Through the proxy, requests without `X-Forwarded-For` count as the
   proxy's own address: with 16 of them held, the 17th without the
   header is answered 503, while one for 203.0.113.8 is answered 200
   (`tests/hostile-tests.lisp`).
5. Through the proxy, 20 calls of a `:wait` tool for the client
   203.0.113.7 waiting at once do not shut that client out: while they
   wait, an ordinary call for 203.0.113.7 is answered 200, and each wait
   is answered when it ends (`tests/hostile-tests.lisp`).
6. Through the proxy, with 32 calls of a `:wait` tool waiting for the
   client 203.0.113.7, a 33rd for that client is refused at once with
   `unavailable` and «32 kall venter allerede fra samme adresse; prøv
   igjen om litt», while a wait for 203.0.113.8 is taken and waits
   (`tests/hostile-tests.lisp`).
7. The address counted: an IPv4 address as itself, IPv6 addresses by
   their first 64 bits (`2001:db8:1:2::5` and `2001:db8:1:2:ffff::1`
   together, `2001:db8:1:3::1` apart), `::ffff:203.0.113.7` as
   `203.0.113.7`; through the proxy, a last `X-Forwarded-For` entry that
   is not an IP address counts as the proxy's own
   (`tests/hostile-tests.lisp`).
8. `--trusted-proxy`, else `TRUSTED_PROXY`, takes an IPv4 or IPv6
   address; another value is refused (the server exits 2)
   (`tests/cli-tests.lisp`). A nixploy target with `web.domain` gets
   `run.environment.TRUSTED_PROXY = "127.0.0.1"` (`bin/test-cli`).
9. The memory budget still holds with the limit in place: a thousand
   connections in their headers come from 20 addresses
   (`a-thousand-connections-in-their-headers-fit-the-budget`), and the
   requests at every limit at once from several addresses, so the
   per-address bound does not stand in for the limits they reach
   (`hostile-callers-at-every-limit-at-once-keep-the-server-up`).

The preview's port (`spec/preview.md` §2, «The port»):

10. Eight starts choosing a port at the same moment each claim a
    different one (`tests/preview-tests.lisp`).
11. A claim whose process has ended is taken over by the next start; one
    held by a running process, or one that cannot be read as a process
    id, is skipped, and `--port` naming it is refused with exit 1,
    naming the process or the file (`tests/preview-tests.lisp`).
12. Handing a claim to the server replaces its file by a rename under
    the lock: the claim then names the new process, and no other file is
    left in `ports/` but the lock (`tests/preview-tests.lisp`).
13. A restart of a running preview takes over its claim before the old
    server stops: the claim names the restarting process, and a start
    choosing a port meanwhile does not get that port
    (`tests/preview-tests.lisp`).
14. No claim is left behind: `tun preview stop` removes the preview's
    claim; a start that fails after claiming (`--port` where something
    already listens) leaves none; and a start whose server exits before
    it answers /health, of a client that does not load, exits 1 and
    leaves no claim and no preview file (`tests/preview-tests.lisp`).

Jobs (`spec/jobs.md` §2):

15. `define-job` with an argument `(files)`, `(files :max 3)`,
    `(list-of files)` or `(list-of ENTITY)` for an embedded entity is
    refused when it is expanded, with a message naming the job and the
    argument and what to pass instead (`tests/jobs-tests.lisp`).
16. A `(:field ENTITY NAME)` argument is checked when an application
    opens: a job defined before its entity, whose field is a list of an
    embedded entity, loads, and keeps an application from opening with
    a message naming the job, the argument and the entity; so does a
    `(:field ...)` argument naming an entity, or a field of it, that does
    not exist; the same job order with a field of a type a job carries
    opens and runs (`tests/jobs-tests.lisp`).
17. A job with an argument of each other type (string, email, integer,
    decimal, boolean, enum, date, timestamp, id, json, a list of
    strings) is defined, enqueued and run with its argument read back as
    given (`tests/jobs-tests.lisp`).

18. The core version is 1.23.0 (`src/core/module.lisp`, `flake.nix`,
    `spec/cli.md`).

## Decisions

- **The per-address limit lives in Tun; nothing goes into Caddy.**
  nixploy writes a tenant's Caddy route through Caddy's admin API, one
  `reverse_proxy` to the slot, outside this repository, and a target
  has no field for more; stock Caddy has no per-address connection
  limit at all (its rate-limit module is third-party and counts requests
  over time, not connections held). It is also not needed there: Caddy
  reads a request's line and headers itself, in cheap goroutines, before
  it sends anything on, so behind Caddy a slow or reconnecting caller
  holds Caddy's connections, not Tun's threads. What reaches Tun through
  Caddy is a request in progress, which Tun counts by the client address
  Caddy forwards. In development and previews there is no proxy, and Tun
  counts connections by their peer. Both are in Tun, behind one rule:
  the trusted proxy's connections are counted by request and forwarded
  address, everyone else's by connection and peer.
- **The proxy is named, never guessed.** `--trusted-proxy` /
  `TRUSTED_PROXY` names it, and the template's targets get
  `TRUSTED_PROXY=127.0.0.1` from Tun's `deployTarget` when they have a
  domain, beside `PUBLIC_URL`, so a tenant made with the template needs
  no change to its `deploy.nix`. Inferring a proxy from a loopback peer
  or from `PUBLIC_URL` would trust anyone on the machine in development,
  where every peer is loopback, and previews have a `PUBLIC_URL` too.
- **The last entry of `X-Forwarded-For`** is the client: the one the
  trusted proxy wrote. Caddy drops a caller's own by default, and a proxy
  that appends instead still writes its entry last.
- **64 connections, 16 proxied requests.** Through the proxy a request
  is work, not an idle connection (Caddy keeps those), and a quarter of
  the 64 answered at once (`--max-inflight`) keeps one client from
  taking the capacity. Is 16 enough for an office behind one address?
  A page, a form post or a tool call is answered in milliseconds, so
  dozens of people produce a few requests in progress at a time. What
  lasts are transfers: an upload counts while its body comes and a
  download while its file is sent, for their whole duration, and those
  are what 16 must hold. Uploads over 256 KiB are already limited to four
  at once for the whole server, so the remainder is downloads and small
  bodies on slow links; 16 at once from one office is far past what an
  SMB's staff reach, and a 503 with `Retry-After: 1` is a retry, not an
  error page. Waits are the exception that would not fit, as an agent or
  a page can hold one for up to 600 s, so they leave the count while
  they wait (next). A direct connection may be idle between requests,
  and on a developer's machine the browser, `bin/test`, `bin/check` and
  a load suite share 127.0.0.1 (the pressure suite runs 32 workers and
  probes), so it gets 64. They are parameters
  (`*connections-per-address*`, `*requests-per-address*`) that tests can
  set, not flags: no tenant has needed another value.
- **A waiting call leaves its client's count while it waits,** as it
  leaves `--max-inflight` (decided at gate A). Waits are bounded by
  `*max-waiting*`, 256 in a process, and holding many is what agents and
  an office behind one address legitimately do; counting them would let
  16 waits shut the address out. It comes back to the count when the
  wait ends, over the bound or not, so a finished wait is never refused
  its answer. A wait on a direct connection keeps its connection, which
  counts as before.
- **Counted in the connection's thread.** The connection is counted and
  released inside Hunchentoot's `process-connection`, in one
  `unwind-protect`, so no path (a failed thread start, Hunchentoot's own
  503 when its queue is full) can leave a count behind. A refused
  connection costs a thread that ends at once; checking in the acceptor
  thread instead would need the release on paths Hunchentoot owns.
- **The 503 is written before the request is read** for a refused
  connection, as the 408 and 431 are: there is no request yet to answer
  as `/api` or `/mcp` would. Closing a socket with bytes unread makes
  the kernel send a reset, and the caller may lose the 503 (gate A), so
  what has already arrived, up to the 32 KiB header budget, is read and
  dropped with `listen`, never blocking, and then the connection is
  closed. Waiting for more, as the 2 s drain after a refused body does,
  would let refused connections hold threads again, which is what the
  limit is for; a caller whose bytes arrive after the close may still
  see a reset, and retries. Through the proxy there is a request, so it
  is answered as `call-bounded` sheds.
- **At most 32 waits per client** (Jonas at gate A: «a per-client wait
  bound»). Waits leave the per-client request count, so without a bound
  of their own one client could hold all 256 waiting places
  (`*max-waiting*`) and every other client's wait would be refused. 32 is
  an eighth of the 256: eight clients at their bound fill the process,
  and an office or an agent host that needs more than 32 waits at once
  from one address is past what a tenant of this size has. The key is
  the one the connection or request is counted under (forwarded address
  through the proxy, peer otherwise), handed by the HTTP layer to the
  wait as `*in-flight-cell*` is today; a call inside the process has no
  client and meets the 256 alone. Past it the call gets what a call past
  the 256 gets, `unavailable` before it waits, with a message that says
  the address has 32 waiting.
- **The pressure suite's P6 must come from several addresses**
  (`core.md` §7.8, gate A). It runs 256 workers straight at the server
  from 127.0.0.1; under the new bound 192 of them would be refused per
  address before `--max-inflight` is reached, so P6 would measure the
  wrong limit (its 503s still pass, but the recovery reads could meet
  idle connections the workers left open). §7.8 now says P6 spreads its
  workers over 127.0.0.2 to 127.0.0.9, 32 each. The suite lives in the
  `tun-acceptance` repository, outside this one, so binding its
  workers' sockets to those addresses is a change there; `tun loop
  verify` runs it only when `TUN_PRESSURE` names it, which it does not
  in this worktree. P1 to P5 and P7 use at most 32 workers and probes,
  under 64.
- **IPv6 by /64**, the smallest network commonly given to one
  subscriber or site: counting single addresses would let one holder of
  a /64 use 2^64 of them. Someone with a /56 or a /48 has many /64s, so
  this bounds a network, not a holder; grouping wider would put
  unrelated customers of one provider together.
- **A CDN in front of Caddy is not supported by the count**, and
  `deploy.md` says so: its addresses would be the clients unless Caddy
  trusted it, which nixploy's route does not configure.
- **Previews pass no trusted proxy.** Their visitors come through
  `tailscale serve` on 127.0.0.1 and share its 64 connections, plenty for
  the people looking at a preview and its checks.
- **`X-Forwarded-Proto` is left as it is**, read from any peer: it only
  chooses HSTS and the redirect to HTTPS on a server that listens on
  loopback, and is outside this brief.
- **A port is claimed by a file under a lock.** `choose-port` and the
  claim run while `tun` holds `flock` on `ports/lock`; the claim is
  `ports/PORT` with the holder's process id, handed from `tun` to the
  preview's server once it runs, so it lives as long as the server.
  `O_EXCL` alone cannot take over a stale claim safely (two takers can
  each remove the other's new claim); the lock makes choosing and
  taking over one step. `flock`, not `fcntl`: its lock belongs to the
  open file, so it excludes between threads as between processes, and
  the test's concurrent starts are threads. A reused process id would
  hold a port until that process ends; the next port is taken then.
- **Every claim is written to a file of its own and renamed into
  place,** the first claim and the hand-over to the server alike, under
  the lock (gate A): a `tun` killed while writing leaves a stray
  temporary file, never half a claim. A claim that cannot be read as a
  process id is held, not stale: `tun` cannot tell its holder, and
  taking it over could put two previews on one port. It is only skipped,
  and `--port` names the file.
- **A restart takes over its own claim** from the server it replaces,
  under the lock and before stopping it, so `tun preview` again keeps
  its port: releasing the claim with the old server first would let
  another start take the port in between.
- **Claims are per user,** in `$XDG_STATE_HOME`, like the previews'
  files and the database's socket directory. A shared directory would
  need a world-writable place and someone to clear another user's stale
  claims. Previews by two users are kept apart once one listens
  (`port-free-p`), and the spec states that two users starting at the
  same moment can still meet.
- **What a job cannot carry is decided from the designator** when
  `define-job` expands: `files` anywhere in the type, and a `list-of`
  an entity, since `jobs.md` §2 says a job takes ids and values, never
  records (a list of embedded records with a field that is not input
  fails just as files do; one without works by chance). The macro reads
  no other definition (`reference/style.md`), so a `(:field ...)`
  argument, whose type is another definition's, is checked when an
  application opens, with the other checks of definitions
  (`check-entity-registry`, `check-operation-methods`): a job may still
  be loaded before its entity, as today, and a wrong one keeps every
  application from opening, before any job could be enqueued. The
  messages are in English, as `define-job`'s other compile-time errors
  are: they are for the developer.
- **`define-job` binds a `(:field ENTITY NAME)` argument by NAME.** Its
  expansion bound every argument by the spec's first element, which for
  `(:field ...)` is the keyword `:field`, so such a job never compiled;
  the spec has always said arguments are declared as an operation's
  are. Criterion 16 needs it, so the build fixes it rather than leaving
  the form refused.
- **Core 1.23.0**, a minor version: a new flag and new refusals.

## Log

- 2026-10-27 19:26  started, autonomous
- 2026-10-27 19:35  gate A asked of a reviewer
- 2026-10-27 20:17  gate A: changes (reviewer): waiting calls (up to 600 s) count against the 16-per-client limit and can shut an address out; the load-time check for (:field …) breaks or skips today's lazy order; the claim hand-off to the server must be atomic and an unreadable claim counts as held; test cleanup after the server started
- 2026-10-27 20:20  gate A asked of a reviewer
- 2026-10-27 20:27  gate A: changes (reviewer): the direct 503 closes with request bytes unread (a reset, not the 503); P6 in §7.8 changes meaning under the per-address limit; criterion 3 and the (:field …) missing-entity case
- 2026-10-27 20:27  Jonas, asked about the review: «Changes, incl. a per-client wait bound» — fix the three points and bound waiting calls per client (e.g. 32) so one client cannot take all 256 waiting slots; «then build»
- 2026-10-27 20:29  gate A asked of the person
- 2026-10-27 20:30  gate A asked of the person
- 2026-10-27 20:31  gate A: approve (jonas): «Changes, incl. a per-client wait bound» … «then build» (the fixes and the wait bound are in)
- 2026-10-27 21:05  verify 1: passed build, test, check
- 2026-10-27 21:17  verify 2: passed build, test, check
- 2026-10-27 21:18  shown (/)
- 2026-10-27 21:38  verify 3: passed build, test, check
- 2026-10-27 21:39  rebased: tun 12ab0ec → e2f7588
- 2026-10-27 21:50  verify 4: passed build, test, check
- 2026-10-27 21:50  shown (/)
- 2026-10-27 21:51  bin/test-cli passed (third run; the first lost port 4208 to another worktree's test-cli on old preview code, the second failed on its own check that the previews' directory is empty, which now allows ports/lock)
- 2026-10-27 21:51  pressure P6 once against this worktree with tun-acceptance b55dfbd (workers from 127.0.0.2-9): passed, 0 failures, 25 203 shed 503, recovery reads at most 8 ms
- 2026-10-27 21:51  gate B asked of a reviewer
- 2026-10-27 22:02  gate B: approve (reviewer): criteria 1-18 met and probed: caps, proxy, waits, port claims, job refusals hold; legitimate bursts served
