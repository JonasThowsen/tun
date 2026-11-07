# PUT, PATCH and DELETE to another system's JSON API

- loop: outbound-methods
- mode: hands-on
- stage: done
- base: 9627863ac7e751208c77fa9c2704fdf1153eeed8
- item: sak_904293mv3n9tjxw9
- verified: 8a3deb4a58ae876c2cf508c0e52f6eeda455730c
- shown: 8a3deb4a58ae876c2cf508c0e52f6eeda455730c

## Brief

Jonas, 2026-11-07, on Factory 1 (Ferdig sak_317zg468h4qapk2q, Hetzner hosts
and Cloudflare DNS from nixploy-dashboard), asked whether Tun's two missing
pieces should be built first: «Yes, build them first (Or at the same time,
while other things are running).» This is the first of them (Ferdig
sak_904293mv3n9tjxw9).

Tun's public calls to other systems are `http-json-get`, `http-json-post`
and `http-form-post` (spec/outbound.md). Hetzner Cloud's API removes a
server with DELETE and changes one with PUT; Cloudflare's DNS API changes
a record with PUT or PATCH and removes it with DELETE; Tailscale's removes
a device with DELETE. Tailscale's OAuth token endpoint takes a form POST
(`client_id`, `client_secret`), which `http-form-post` already makes.

## Criteria

1. `(http-json-put URL BODY &key headers (timeout 10))` sends a PUT with
   BODY as UTF-8 JSON, `Content-Type` and `Accept` as `application/json`,
   then HEADERS, and values the answer's JSON and its status for a status
   from 200 to 299.
2. `(http-json-patch URL BODY &key headers (timeout 10))` does the same
   with PATCH.
3. `(http-json-delete URL &key query headers (timeout 10))` sends a
   DELETE with no body and QUERY appended and percent-encoded as
   `http-json-get` does it; a 204 with no body values `:null` and 204.
4. For each of the three, a status outside 200 to 299, a body that is not
   JSON, no answer, no answer in time and a redirect are a
   `remote-failure` with the status, body, URL and message
   `http-json-post` gives them.
5. Each call is an `external` step in the trace named by its method and
   the URL without its query or user and password, such as
   `DELETE http://127.0.0.1:…/v1/check`, with the status as its detail;
   no header or body is in the trace.
6. A `User-Agent` in HEADERS is the one received, once; a header, or a
   DELETE's query, that is not a pair of strings is an error in the
   caller's code naming the function and showing no value.
7. `*http-json-handler*` answers for the three: given the JSON body for
   PUT and PATCH, and the URL with its query and NIL for DELETE. While it
   runs, `*http-json-method*` is `:put`, `:patch` or `:delete`, and
   `:get` and `:post` for the existing calls (`:post` for a form). A
   handler of three arguments, as every existing one is, works unchanged.
8. `http-json-put`, `http-json-patch`, `http-json-delete` and
   `*http-json-method*` are in the TUN package; spec/outbound.md and
   docs/client-api.md describe them. Core is 2.11.0 (2.9.0 when gated; renumbered on the rebase onto origin, where 2.9.0–2.10.0 were taken).

## Decisions

- **Three functions, one per method, not a `:method` argument.** The
  existing calls are one per kind of request; `http-json-delete` takes a
  query and no body, as a GET does, and PUT and PATCH take a body, as a
  POST does. All go through `json-call`, so the deadline, the limit of
  four calls, the trace and the failures are the same code.
- **The handler learns the method from `*http-json-method*`, not from a
  fourth argument.** Sixteen handlers in Tun's tests and more in ferdig,
  nixploy-dashboard and kurs take three arguments; a fourth would break
  every one. A fake of Hetzner needs the method, since GET and DELETE of
  `/v1/servers/42` are different requests.
- **No DELETE with a body.** RFC 9110 gives it no meaning, and Hetzner,
  Cloudflare and Tailscale take none.
- **No retries.** As for POST, a failure is the caller's; a PUT and a
  DELETE are idempotent by HTTP's rules, but whether a given system's are
  is not Tun's to assume.
- **PATCH sends `application/json`**, as Cloudflare's PATCH takes. A
  system that wants `application/merge-patch+json` is not served by this.
- **No Tailscale work here.** Its token endpoint is a form POST
  (verified in tailscale.com/kb/1215/oauth-clients: `client_id` and
  `client_secret` as form fields), which `http-form-post` covers.
- **Core 2.11.0** (2.9.0 when gated), a minor version: new public symbols, nothing changed for
  existing clients.

## Log

- 2026-11-07 11:15  started, hands-on
- 2026-11-07 11:16  gate A asked of the person
- 2026-11-07 12:17  gate A: approve (jonas): «ja»
- 2026-11-07 12:24  verify 1: passed build, test, check
- 2026-11-07 12:25  shown (/ui)
- 2026-11-07 12:25  gate B asked of the person
- 2026-11-07 13:20  gate B: approve (jonas): «ja»
- 2026-11-07 13:20  finished at tun 323bc7e
