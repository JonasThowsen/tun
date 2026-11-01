# An MCP protocol error is logged instead of failing to log

- loop: mcp-error-codes
- mode: hands-on
- stage: ship
- base: 038c0f51b2efea5e0935f00401b2bc403b051b27
- after: combobox-over
- verified: fc55bbb635452b7b1b4d03ed02e82d2d359f4c0b
- shown: fc55bbb635452b7b1b4d03ed02e82d2d359f4c0b

## Brief

A finding from a client's log watch, worked by an agent run: the client's
server wrote «;; tun errors: could not log req_…: The value
"method_not_found" is not of type SYMBOL when binding SYMBOL» after an MCP
client called a method Tun does not have. The agent found the cause in Tun
and asked; Jonas, 2026-11-01: «seems like an issue was found in tun that
you need to fix».

The cause: `handle-mcp` records a JSON-RPC error's code with
`rpc-code-name`, which gives a string («method_not_found»), while the log
line's `code-text` (src/platform/errors.lisp) takes the keyword every
operation's error has (:method-not-found) and fails on a string, so the
request's log line is lost.

## Criteria

1. A request that ends in a JSON-RPC error (bad JSON, an unknown method, a
   missing actor, invalid parameters) has its log line, with `code` as
   before: `parse_error`, `method_not_found`, `invalid_params`,
   `invalid_actor`, `internal_error`, and `jsonrpc_N` for any other code.
2. The trace (introspect_recent, introspect_request) shows the same codes
   as before.
3. A test calls each kind and reads the log line.

## Decisions

- **Keywords, as the agent proposed:** `rpc-code-name` gives
  `:method-not-found` and the like, the form every other error code has,
  so the log line, the trace and the fault fingerprint read them alike;
  no change to `code-text`. An unknown code is `:jsonrpc-N` (its JSON name
  `jsonrpc_N`, the minus sign of a negative code becoming the underscore).
- A bug fix with no change to the spec: the contract already has these
  codes.

## Log

- 2026-11-01 18:58  started, hands-on
- 2026-11-01 18:58  gate A asked of the person
- 2026-11-01 18:58  gate A: approve (jonas): «Approve (Recommended)»
- 2026-11-01 19:24  verify 1: passed build, test, check
- 2026-11-01 19:25  shown (/ui)
- 2026-11-01 19:25  gate B asked of the person
- 2026-11-01 19:26  gate B: approve (jonas): «Approve and push (Recommended)»
