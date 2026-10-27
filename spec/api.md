# The HTTP API

Status: v1, 2026-10-21. How a system that is not an agent, such as
another company's ERP with a «Meld fra» button, calls a tenant's tools
with one HTTP request. MCP (`/mcp`, `core.md` §3) is for agents;
this is the same tools without JSON-RPC.

## 1. A call

```
curl -X POST https://tracker.example.no/api/items_create \
  -H 'Authorization: Bearer tun_…' \
  -H 'Content-Type: application/json' \
  -d '{"title": "Eksporten feiler", "request_key": "erp-4711"}'
```

- `POST /api/TOOL` calls the tool TOOL, a name `tools/list` lists. The
  body is the tool's arguments, a JSON object; an empty body is `{}`.
- The call goes through the same execution path as a `tools/call`:
  the tool's policy and record policies, validation, rules,
  confirmation, idempotency by `request_key`, receipts and audit. A
  system that may send the same report twice (a retry after a timeout)
  sends the same `request_key`, and gets the first answer again.
- A tool that needs confirmation answers its `confirmation_token`; the
  caller confirms with a second call carrying it, as on MCP.
- A tool that takes files, such as `attachments_add`, takes each as
  base64 in the body, which may then be up to 16 MiB (`files.md` §4).

## 2. Who calls

- The caller is an account's access token (`auth.md` §3.2), sent as
  `Authorization: Bearer tun_…`: normally an `agent` account the admin
  made for that system, with the role its tools need. An AuthKit access
  token works as on `/mcp` (`auth.md` §5.1). A session cookie does not:
  a browser does not call the API.
- With claimed identity (`auth.md` §1), `X-Tun-Actor` names the caller,
  as on `/mcp`.
- The token belongs on the calling system's server. A button in another
  system's page posts to that system, which calls the API.
- A request with an `Origin` other than the server's own is refused with
  403, as on `/mcp`. The API sends no CORS headers.

## 3. Answers

The answer is JSON. Every answer carries `X-Tun-Request-Id`, the handle
for `introspect_request`.

| Status | When | Body |
|---|---|---|
| 200 | The tool ran. | Its result, as `structuredContent` on MCP. |
| 400 | The body is not a JSON object. | `{"error": {"code": "invalid_json", "message": …}}` |
| 401 | No token, or a token that is unknown, expired, revoked or its account disabled. With `WWW-Authenticate`, as `/mcp`'s. | `{"error": {"code": "unauthenticated", …}}` |
| 403 | The tool's policy refused the caller (`forbidden`), another origin, or an AuthKit identity no one has linked. | The error document. |
| 404 | No tool TOOL (`unknown_tool`), or a record the call names does not exist (`not_found`). | The error document. |
| 405 | Any method but POST. With `Allow: POST`. | Empty. |
| 409 | `conflict`, `idempotency_conflict`, `invalid_transition`, `unavailable`, `insufficient_stock`. | The error document. |
| 422 | Any other operation error, such as `invalid_input` with its `fields`. | The error document. |
| 503 | AuthKit could not be reached to check a token, or the server is at its limit of requests (`Retry-After: 1`). | The error document. |

The error document is the one an operation error has everywhere,
`{"error": {"code", "message", …}}`.

## 4. Records

Each call is retained as one request, in `introspect_recent`, the log
line (`errors.md`) and faults. A call that reaches its tool is that
tool's record, as a `tools/call` is; one refused before any tool ran (no
token, another origin, bad JSON, an unknown tool) is a request of kind
`api`, as MCP's are of kind `mcp`.

## 5. Not yet

- Webhooks: a tenant calling another system when something happens.
- Tokens limited to some tools.

## 6. Evidence

- `tests/api-tests.lisp`: a call answers the result; a second call with
  the same `request_key` answers the same result and makes one record;
  the error statuses above; a token's role meets the tool's policy;
  without a token 401 and the challenge; another origin 403; GET 405;
  a call is retained as its tool's record, a refusal with kind `api`.
