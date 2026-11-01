# A server waits for its database at start instead of exiting

- loop: database-wait
- mode: hands-on
- stage: ship
- base: f40c1e58df3a7753f58f8eddfa668da0797368ef
- after: mcp-error-codes
- verified: 1b0eb3cec76ebbda27e552f5eb3d29c0f96eacb2
- shown: 1b0eb3cec76ebbda27e552f5eb3d29c0f96eacb2

## Brief

An agent run of nixploy-dashboard on a finding in ferdig's production logs,
2026-11-01: the shared host's Postgres restarted at 18:45 UTC, and ferdig
crashed three times on its way back up with an unhandled
DATABASE-SOCKET-ERROR from tun.runtime:main (open-for-serving handles only
newer-database and database-refused), exit 70; the fourth start came up.
The agent proposed that Tun's start wait for the database with backoff.
Jonas chose «File them, fix startup first (Recommended)».

## Criteria

1. A server started while its Postgres database refuses connections,
   cannot be reached, or is starting up or shutting down (SQLSTATE 57P03)
   waits: it writes one line on standard error per try, naming the host
   and not the password, and tries again after 1, 2, 4, 8, 16 and 29
   seconds; when the database answers, it opens and serves as before.
2. Still unreachable after a minute, it exits 1 with a line saying so,
   instead of an unhandled error (exit 70).
3. Refusals that are not about reaching the database (wrong password, a
   newer core, a database core 2.0 cannot take) are not waited for and
   end as they do now.
4. Tests: a fake connect that fails twice then works opens the
   application; one that never works exits 1 after the tries (with the
   waits made instant in the test); a wrong password is not retried.

## Decisions

- **A condition of Tun's own,** `database-unreachable`, signalled by the
  Postgres store when it cannot connect, so the runtime does not know
  cl-postgres.
- **A minute, then exit 1:** long enough for a restart of Postgres on the
  same host; the supervisor restarts the server after that, so a longer
  outage is still recovered, now with a clear line instead of a backtrace.

## Log

- 2026-11-01 20:51  started, hands-on
- 2026-11-01 20:51  gate A asked of the person
- 2026-11-01 20:52  gate A: approve (jonas): «Approve (Recommended)»
- 2026-11-01 21:19  verify 1: failed test
- 2026-11-01 21:39  verify 2: passed build, test, check
- 2026-11-01 21:40  shown (/ui)
- 2026-11-01 21:40  gate B asked of the person
- 2026-11-01 21:47  gate B: approve (jonas): «Approve and push (Recommended)»
