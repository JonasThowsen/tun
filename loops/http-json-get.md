# Read another system's JSON API with a GET (http-json-get)

- loop: http-json-get
- mode: reviewed
- stage: done
- base: ba2113321e3de26dde3ebeef65aac714ff7c4662
- verified: f4866aeab03a53646b1673928ea85f9bd43f8a23
- shown: f4866aeab03a53646b1673928ea85f9bd43f8a23

## Brief

Jonas, in this session (2026-11-02), wants a dashboard for trading stocks
on Oslo Børs and in the US, built as a Tun client, with prices from Yahoo
Finance (what yfinance reads): «I am open to both Oslo børs and US
stocks», «You can start on the Tun work right away, i would like to get
somethjng working quickly, so chart can also be built.»

Price services are read with a GET, and Tun calls other systems only
with `http-json-post` (spec/outbound.md §1). Some services also ask a
client to name itself in its `User-Agent`, which drakma writes as its own
and would send twice beside one in the headers. Charts are the loop after
this one (`price-chart`).

Yahoo Finance (what yfinance reads) answers 429 to any request without a
browser's `User-Agent`; that is its bot check, and Tun does not pretend
to be a browser to get past it. Which price service the client uses is
Jonas's choice, after this loop.

## Criteria

1. `(http-json-get URL :query ALIST :headers ALIST :timeout N)` sends a
   GET to URL with `Accept: application/json` and no body, and values
   the answer's JSON and its status for a status from 200 to 299.
2. QUERY's names and values are percent-encoded as UTF-8 and appended
   to URL after `?`, or after `&` when URL has a query already: `^GSPC`
   arrives as `%5EGSPC`, `Bodø` as `Bod%C3%B8`. Without QUERY, or with
   an empty one, URL is sent as it is, with no `?` added. A URL's
   `#fragment` is not sent, and the query goes before it. A name or a
   value that is not a string is an error in the caller's code.
3. A status outside 200 to 299, a body that is not JSON, no answer, no
   answer in time and a redirect are each a `remote-failure`, with the
   status, body and message `http-json-post` gives them; its URL
   (`remote-failure-url`) is the URL as sent, with the query.
4. The call is an `external` step in the trace named `GET` and the URL
   without its query or its user and password, with the status as its
   detail.
5. A `User-Agent` in HEADERS, matched without regard to case
   (`user-agent` too), is the one the other system receives, once, for
   `http-json-get` and for `http-json-post`.
6. `*http-json-handler*` answers for a GET too: it is called with the
   URL with its query, NIL for the body, and the headers.
7. `http-json-get` is in the TUN package for clients, and
   spec/outbound.md and docs/client-api.md describe it.

## Decisions

- **A function of its own, not a `:method` on `http-json-post`.** A GET
  has no body, and `(http-json-post url nil)` would read as posting
  `false`. The two share everything else: checks, deadline, the
  four-call limit, the trace and the failures.
- **`:query` as an alist.** Tickers such as `^GSPC` and names with `ø`
  must be encoded, and a client that builds the query with `format`
  gets that wrong. The encoder moves from `tun.auth` (oidc.lisp) to
  `tun.outbound`, so there is one, and OIDC uses it from there.
- **NIL for the body in the handler** keeps `*http-json-handler*`'s
  signature, so existing tests and clients are unchanged. A handler that
  serves both tells them apart by the URL, as a real system does; a POST
  of JSON `false` is the one ambiguity, and no API takes that as a body.
- **The trace name keeps dropping the query.** A price query may hold
  nothing secret, but other APIs put a key there (`?key=`), so the rule
  stays one rule.
- **No default `User-Agent`.** drakma's own stays the default. A client
  that must name itself sets its own, such as `kurs/1.0 (address)`.
- **The URL is sent as written** (drakma's `:preserve-uri`), for POST
  too. Without it drakma escapes a query's `%` again, so `%5E` arrives
  as `%255E`; the first test run caught it. Sent as written, a URL
  loses its fragment and gets `/` for an empty path in one place for
  every method, since drakma would otherwise send `https://host?q=1` as
  `/` and a POST's `#fragment` in its request line (gate B).
- Core 2.5.0: a new function clients can call.

## Log

- 2026-11-02 15:40  started, reviewed
- 2026-11-02 15:40  gate A asked of a reviewer
- 2026-11-02 15:43  gate A: changes (reviewer): User-Agent matched without regard to case in criterion 5; say remote-failure-url is the URL as sent with its query; an empty or NIL :query leaves the URL unchanged; the spec's Status line names every section changed
- 2026-11-02 15:43  gate A asked of a reviewer
- 2026-11-02 15:45  gate A: approve (reviewer): Earlier findings fixed; criteria testable and match the spec; decisions are not the asker's. Small points for build: §2 names user and password too, which User-Agent wins of two, a URL ending in a bare ?
- 2026-11-02 16:23  verify 2: passed build, test, check
- 2026-11-02 16:24  shown (/ui)
- 2026-11-02 16:24  gate B asked of a reviewer
- 2026-11-02 16:27  gate B: changes (reviewer): Under :preserve-uri a URL with no path loses its query (drakma's trivial-uri-path) and POST sends a #fragment; fix in one shared place, test the root URL, and say in spec §1 that the URL is sent as written
- 2026-11-02 16:41  verify 3: passed build, test, check
- 2026-11-02 16:42  shown (/ui)
- 2026-11-02 16:42  gate B asked of a reviewer
- 2026-11-02 16:44  gate B: approve (reviewer): Earlier findings fixed; each criterion tested; verify round 3 green
- 2026-11-02 16:44  finished at tun 87a359c
