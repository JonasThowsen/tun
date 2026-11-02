# A client that hangs up during a wait is logged as an internal error

- loop: client-gone
- mode: hands-on
- stage: done
- base: f30a03cda461376b0b873aaff52a9693354ec3cc
- after: mcp-add-scope
- item: sak_n6yvgdknycbb3b5n
- verified: 7b957e3f213a386a2958e79a1bd34aacda456aee
- shown: 7b957e3f213a386a2958e79a1bd34aacda456aee

## Brief

Ferdig sak_n6yvgdknycbb3b5n, filed 2026-11-01 from nixploy-dashboard's log
watch on ferdig/production (sak_3th7ad0854x3y6aj) and the diagnosis of
agent runs run_m0syxs3cvsxnbqrm and run_k2dxrwbfsczgrf2v: «A questions_wait
over MCP (an operation of :kind :wait, answered as SSE) ran 279 s; the
client, through the local reverse proxy, hung up before it ended. Writing to
the socket then failed («Couldn't write to … Broken pipe»): the heartbeat in
call streaming (src/agent/http.lisp, write-event) writes from inside the
await, so SB-INT:BROKEN-PIPE went through the operation and was recorded as
internal_error (a fault, err_fysqssajs2xbb8e3), the tools/call handler
(src/agent/mcp.lisp) then failed again sending its -32603, and the HTTP
layer logged BROKEN-PIPE as well.» Wanted: «a stream error on the client's
socket during a wait (or while writing any answer) is the client having
gone: the request ends with an outcome such as «disconnected» (not a fault,
no error group, a warn-level log line at most), the operation's wait stops,
and nothing is written after.» On 2026-11-02 Jonas asked to «fix the items
in ferdig that regard tun».

## Criteria

1. A `:wait` tool called over MCP and answered as an SSE stream, whose
   client hangs up while it waits: the first beat written after that
   fails, the wait stops, and the request is retained with outcome
   `error` and code `disconnected`; `errors_list` shows no error for it,
   and its JSON log line has level `warn`.
2. Nothing more is written to that connection: the tools/call handler
   sends no JSON-RPC error, and Hunchentoot logs nothing for it.
3. The same when the write that fails is the stream's last event, the
   response.
4. A client that hangs up before a plain answer is written (a JSON answer
   or a page) gets no line at level `error` from Hunchentoot, and the
   request keeps its outcome.
5. Tests over real HTTP, with the beat made short: a waiting call whose
   client closes its socket once the stream has started ends as in 1 and
   2; a hang-up while a plain answer is written ends as in 4.

## Decisions

- **Outcome `error`, code `disconnected`,** rather than a fourth outcome:
  spec/core.md §8.4 keeps its three outcomes, and errors.md §2 already
  says which error codes are faults; `disconnected` is listed among the
  answers that are not, and `warn` follows from that (errors.md §6).
- **A condition of Tun's own,** signalled where the stream is written
  (call streaming) and passed through the operation and the tools/call
  handler unchanged, so neither turns it into `internal_error`.
- **Hunchentoot's own lines:** Hunchentoot catches and logs the failing
  connection inside its own handlers, outside Tun's, both for a plain
  answer it writes after the request has ended and for the end of a
  stream. Tun's acceptor leaves out of its log a message whose argument is
  the socket failing (a system stream error, the end of input, or
  usocket's connection aborted or reset). Tun's own handlers catch every
  other error before Hunchentoot sees it, so nothing else is hidden.
- **The proxy's idle timeout** (the item's optional check) is nixploy's
  and the host's, not Tun's; the 25 s beat already stays under every
  timeout spec/waiting.md names. Left out.

## Log

- 2026-11-02 07:52  started, hands-on
- 2026-11-02 07:54  gate A asked of the person
- 2026-11-02 07:56  gate A: approve (jonas): «Approve (Recommended)»
- 2026-11-02 10:00  rebased: tun 43b7afb → f30a03c
- 2026-11-02 10:14  verify 1: passed build, test, check
- 2026-11-02 10:14  shown (/ui)
- 2026-11-02 10:14  gate B asked of the person
- 2026-11-02 10:16  gate B: approve (jonas): «Approve and push (Recommended)»
- 2026-11-02 10:16  gate C asked of the person
- 2026-11-02 10:16  gate C: approve (jonas): «Approve both (Recommended)»: Tun 2.4.5 to ferdig (production via nixploy-dashboard) and nixploy-dashboard (Jonas deploys netcup)
- 2026-11-02 10:20  Tun 2abaad6 (core 2.4.5) in ferdig 244a7db, deployed to production through nixploy-dashboard (dpl_yz58yczr2d4vq70j, succeeded in 68 s); in nixploy-dashboard 8013eb7, ~/nixos f903da8, for Jonas to deploy to netcup
- 2026-11-02 10:20  finished at tun 2abaad6
