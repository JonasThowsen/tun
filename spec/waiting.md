# Waiting for people

Status: v1, 2026-10-21. How an agent's call waits for something a person
does, such as answering a question in the UI, and gets it in the same
call; and how a client tells agents how to work with it.

A remote MCP server cannot push to an agent between calls. What reaches a
running agent is the answer to a call, so the call waits: `questions_wait`
returns when the question is answered, or when its time is up.

## 1. A waiting operation

```lisp
(define-operation questions-wait ((id :type (id question) :required t :label "Spørsmål")
                                  (seconds :type (integer :min 1 :max 600) :default 120
                                           :label "Sekunder"))
    (:kind :wait :entity question :policy :employee :title "Vent på svar"
     :description "Venter til spørsmålet er besvart, eller til tiden er ute.")
  (await (:seconds seconds :until #'question-answered-at)
    (fetch! 'question id)))
```

- An operation of `:kind :wait` reads and never writes. Policy and input
  are checked as for any operation; then its body runs outside a
  transaction, so it holds no database connection and no write lock
  while it waits. Its result, an entity or a JSON object, is shown as a
  read's is.
- `(await (:seconds S [:until PREDICATE]) FORM...)` evaluates FORM in a
  read transaction of its own, again and again, until PREDICATE holds for
  its value (the value itself being true, without `:until`) or S seconds
  have passed. It returns the last value, and as a second value whether
  PREDICATE held. An error in FORM ends the wait with that error.
- FORM runs again at once after every write that commits in this
  process, and at least every 5 seconds, which catches a write by
  another process on the same database (a blue/green switch, `store.md`
  §3).
- `await` is only for a `:wait` operation's body; anywhere else, inside a
  transaction or not, it is an error.
- A wait is at most 600 seconds, whatever S says. The transport may hold
  it to less (§2, §3); the caller calls again.
- The operation's deadline (`--deadline-ms`) holds for its work, not for
  its waiting: each FORM runs under it, and the work after `await` gets
  a whole one.
- While it waits, a call does not count against `--max-inflight`, nor
  against the requests its client may have in progress through the
  proxy (`core.md` §7.5). At most 256 calls wait at once in a process;
  one more is refused with `unavailable` before it waits.
- At most 32 of them wait for one client: over HTTP, the address the
  client is counted under (`core.md` §7.5), the one the trusted proxy
  names or else the peer's. One more for that client is refused the same
  way, with `unavailable` before it waits, «32 kall venter allerede fra
  samme adresse; prøv igjen om litt», while other clients' waits are
  taken. A call made inside the process, with no client, is held to the
  256 alone.
- A wait is retained as one request, with the time it took.

## 2. Over MCP

- A `tools/call` of a `:wait` tool whose client accepts
  `text/event-stream` (as the Streamable HTTP transport requires it to)
  is answered as JSON when it is done within 25 seconds. A longer one is
  answered as an SSE stream: the stream starts at the 25th second, and
  every 25 seconds it carries
  - a `notifications/progress` for the request's
    `params._meta.progressToken`, with `progress` the seconds waited and
    a message, when the request carried a token;
  - else an SSE comment line, which keeps the connection busy;
  and the JSON-RPC response is its last event. So neither a client's
  idle timeout (Claude Code's is 5 minutes) nor a proxy that drops a
  silent connection (Cloudflare's is 100 seconds) cuts the call.
- A client that accepts only JSON waits at most 90 seconds per call.

## 3. Over the HTTP API

A `:wait` tool on `POST /api/TOOL` (`api.md`) is a long poll: the answer
comes when the wait ends, as a plain JSON answer, and a wait is at most
90 seconds, so a proxy that drops a silent connection after 100 seconds
does not cut it. The caller calls again.

## 4. Instructions for agents

`(:instructions TEXT...)` in `define-application` adds TEXT, one or more
strings, to what MCP's `initialize` tells an agent about the server
(`instructions`), after Tun's own, each as a paragraph. A client says
there how its tools are meant to be used together: «Start med å si hvem
du er, still spørsmål med questions_ask, vent på svaret med
questions_wait, og avslutt saken når den er ferdig.»

## 5. Not yet

- Waking a waiter at once on another process's write (Postgres
  `LISTEN`/`NOTIFY`); until then within 5 seconds.
- Resuming a stream after a dropped connection (`Last-Event-ID`): the
  agent calls again.

## 6. Evidence

- `tests/waiting-tests.lisp`: a wait returns at the commit that satisfies
  it, and with its last value and NIL when its time is up; an error ends
  it; `await` outside a `:wait` body is an error; a wait holds no
  transaction and is not counted in flight while it waits; the cap on
  waiters; a wait longer than the deadline is not cut by it; over MCP a
  long wait becomes an SSE stream with progress for a token and comments
  without one, and a short one is plain JSON; over `/api` it is a long
  poll held to 90 seconds; the instructions reach `initialize`.
