# A client's MCP protocol error is logged as a failing request

- loop: mcp-client-errors
- mode: hands-on
- stage: done
- base: 58ecabfacbc40fd151fba6e296d70145641207cc
- verified: 0b4c9f1c5ae10be12c2053b3a2a7cdb25eeb8ebf
- shown: 0b4c9f1c5ae10be12c2053b3a2a7cdb25eeb8ebf

## Brief

Ferdig sak_45f0z7dsjb5jtzyn, from nixploy-dashboard's log watch on
ferdig/production (findings chk_cnds8a8jh3m95grz, chk_2tmqn11qs8gpmpfx):
every time claude.ai's connector connects (actor admin:jonas), its first
call is `server/discover`, Tun answers JSON-RPC -32601, and the client goes
on with `initialize` and `tools/list`. The request's log line has outcome
`error` (level warn, code `method_not_found`), which the log watch reports
as failing requests. The agent run's diagnosis: handle-mcp
(src/agent/mcp.lisp) records every JSON-RPC error no operation recorded as
outcome `error`. Jonas answered «Du kan fikse det» (2026-11-02) and chose
that the change is made here as a loop.

`server/discover` is MCP 2026-07-28's discovery call. A client that speaks
both that revision and the older one sends it first, and a «method not
found» answer is how it learns the server is of the older kind and falls
back to `initialize` (modelcontextprotocol.io, Versioning and
Compatibility). Tun's answer is right; its record of it is not.

## Criteria

1. An `/mcp` request answered with a JSON-RPC error the client caused (a
   body that is not JSON (-32700), not a request (-32600), an unknown
   method such as `server/discover` (-32601), bad params or an unknown
   tool (-32602), no valid actor (-32000)) is retained with outcome
   `rejected` and its code, and its log line says `"outcome":"rejected"`.
2. A JSON-RPC error that is the server's (-32603, and every other code)
   keeps outcome `error`.
3. An error an operation recorded itself keeps the outcome it recorded.
4. spec/core.md §8.4 says which requests are `rejected`, these among them,
   as `/api` already does for its refusals.

## Decisions

- **Rejected for the client's errors, error for the server's,** the same
  line `/api` draws (`api-failure`: below 500 rejected), so a client
  probing or erring is a refusal on both transports, and the log watch
  sees no failing request. The codes are those JSON-RPC 2.0 reserves for
  the request's own faults, and Tun's -32000 for a missing actor.
- **No change to the answer:** -32601 stays, since it is what lets a
  client fall back. Serving MCP 2026-07-28 (`server/discover` and
  requests without `initialize`) is a feature of its own, not this fix.
- **Spec:** §8.4's list of rejected codes is wider than it says already
  (`unauthenticated`, a body the transport refuses, `/api`'s refusals);
  it is written out with the protocol errors added.
- Core 2.4.7; the card loop (card-link-fields, 2.4.6) goes first.

## Log

- 2026-11-02 12:25  started, hands-on
- 2026-11-02 12:25  gate A asked of the person
- 2026-11-02 12:26  gate A: approve (jonas): «Approve (Recommended)»
- 2026-11-02 13:02  rebased: tun 5eb2c13 → 58ecabf
- 2026-11-02 13:16  verify 1: passed build, test, check
- 2026-11-02 13:17  shown (/ui)
- 2026-11-02 13:17  gate B asked of the person
- 2026-11-02 13:23  gate B: approve (jonas): «Approve and push (Recommended)»
- 2026-11-02 13:24  gate C asked of the person
- 2026-11-02 13:24  gate C: approve (jonas): «Approve ferdig (Recommended)»: Tun 2.4.7 to ferdig (production via nixploy-dashboard); nixploy-dashboard not now
- 2026-11-02 13:27  deployed: ferdig 9baef05 (Tun 3ef265d, core 2.4.7) to production, dpl_bjnnkp5rj1mem68x succeeded; nixploy-dashboard left for later, per gate C
- 2026-11-02 13:27  finished at tun 3ef265d
