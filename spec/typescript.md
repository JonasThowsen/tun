# A typed TypeScript client and single-page screens

Status: v1, 2026-11-17. How a client gives one screen a front end of its
own, a single-page application written in TypeScript, when that screen
is better so than as a server-rendered page: what the screen is served
as, how it calls the application's operations under the signed-in
person's session, and the TypeScript module `tun typescript` generates
from the registry so the screen's code and the operations cannot drift
apart. Server-rendered pages stay the rule (`ui.md` §8); a single-page
screen is chosen for one screen at a time, when a person's work on it
is a quick run of taps that a page load after each would slow down.

The owner, 2026-11-14: «There are definitely cases where a SPA frontend
is the best alternative, and that opens up the typescript world. I think
having that as an option […] to create a typesafe API from the backend
to a typescript frontend would be possible.»

## 1. Outputs an operation declares

An operation may declare what its result is (`core.md` §3.11). The
generated module types a declared output exactly, and an undeclared one
as an object of unknown values (§3.3). Before this, no operation
declared its output: a `define-query` declares `:returns`, but a query
is a function a client's code calls, not a tool.

## 2. `tun typescript FOLDER [--dir DIR]`

Writes `FOLDER/api.ts` for the client in DIR (default `.`), creating
FOLDER when it does not exist. FOLDER is relative to the current
directory. The command loads the client as `tun preview` does (on the
Tun its dev shell provides; in Tun's own repository, on the working
tree, `preview.md` §2) and writes the module the registry of its
application gives. It prints the path and how many operations the module
has, and how many of them have an exact output.

- **Generated, never edited.** The module's first line says so and
  names the command that writes it again. The same registry gives the
  same bytes: nothing in it depends on the time, the machine or the
  database. Functions and record types come in the order of their
  names, a type's properties in the order its schema lists them.
- **What it holds.** One function for each operation a person signed in
  on a page may call: every operation of the application but the
  test-only, debug-only and eval-only ones, whatever flags the command's
  process runs with. Session-only operations are among them (`core.md`
  §3.3): the screen calls in a session. Whether the person's role may
  call one is the operation's policy, decided on the server at each
  call; the module offers them all.
- **A changed operation breaks the screen's type check.** A parameter
  renamed, removed, made required or given another type, a value
  removed from an enum, an operation removed, or a declared output
  changed changes the module, and `tsc` then refuses the screen's code
  that still uses the old shape.
- **Usage errors** (exit 2): no FOLDER, more than one, an unknown
  option, a DIR that holds no client. A client that fails to load is a
  failed step (exit 1), with the loading's last lines.

## 3. The module

The module is plain TypeScript for `tsc --strict` with the DOM library,
written for ES2022 modules: no `enum`, no `namespace`, no default
export, every type exported with `export type` or `export interface`,
so a bundler that compiles one file at a time takes it.

### 3.1 Names

- A tool `customers_list` is the function `customersList`; its input
  type is `CustomersListInput`, its output type `CustomersListOutput`.
- A record of the entity `customer` is the interface `Customer`
  (PascalCase of the entity's JSON name); one whose name is one of the
  module's own types (`Answer`, `Page`, …) has `Record` after it,
  `AnswerRecord`.
- Two names that would be the same (`a_b1` and `a_b_1` are both
  `aB1`) stop the command with both tools named (exit 1).

### 3.2 Inputs

Each input type is the operation's JSON Schema, the one `tools/list`
and `/api` validate with (`core.md` §3.4), written in TypeScript:

| JSON Schema | TypeScript |
|---|---|
| `"type": "string"` | `string` |
| with `"enum"` | a union of the values, `"open" \| "closed"` |
| `"integer"`, `"number"` | `number` |
| `"boolean"` | `boolean` |
| `"array"` with `"items"` | `T[]` |
| `"object"` with `"properties"` | `{ name: T; other?: U \| null }` |
| `"object"` without properties | `{ [key: string]: unknown }` |
| `"anyOf"` | a union |
| `{"type": "null"}` | `null` |
| `{}`, or anything else | `unknown` |

A property in `required` is `name: T`; any other is `name?: T | null`,
since the API takes null as «not given». A mutating operation's input
has `request_key?`, a confirm operation's `confirmation_token?`, as the
schema lists them. An operation with no required property takes its
input as an optional argument.

### 3.3 Outputs

- A declared output (`core.md` §3.11) is typed from it: a record is its
  entity's interface, `(:page E)` is `Page<E>` (`{ items: E[]; returned:
  number; has_more: boolean }`), `(:object …)` an object type with its
  keys, a key's `(:list X)` `X[]` and a key's `(:value TYPE)` the field
  type's.
- A record's interface has every field `entity->json` gives, stored and
  computed, the client's extensions among them: a required field, a
  stored record's `id`, a boolean and a list are `T`, any other `T |
  null`; a secret field is `string` (it reads `"***"`).
- An undeclared output is `Undeclared`, `{ [key: string]: unknown }`:
  the screen must check a value before it uses it. The module's comment
  on such a function says to declare `:returns` to make it exact.

### 3.4 What a call answers

Each function returns `Promise<Answer<Output>>`, a confirm operation's
`Promise<Answer<Output> | Confirm>`. A call never throws for a refusal
or a failure: each is a value the screen switches on by `kind`.

```ts
export type Answer<T> =
  | { kind: "ok"; value: T }
  | { kind: "refused"; refusal: Refusal }
  | { kind: "failed"; failure: Failure };

export type Confirm = { kind: "confirm"; confirmation: Confirmation };

export interface Refusal {
  code: RefusalCode;      // the error document's code
  status: number;         // the HTTP status
  message: string;        // the message, in the page's language (§5.3)
  fields: { [field: string]: string };   // invalid_input: each field's message
  details: { [key: string]: unknown };   // the error document's other keys
}

export interface Failure {
  reason: "network" | "answer";  // no answer, or one that is not the API's
  status: number;                // 0 for "network"
  message: string;
}
```

- `ok`: a 200 whose body is not a request for confirmation; `value` is
  the body.
- `confirm`: a 200 with `"confirmation_required": true` from a confirm
  operation; `confirmation` holds `confirmation_token`, `expires_at` and
  `summary`. The screen confirms by calling the same function again
  with the input and `confirmation_token`.
- `refused`: an answer with the API's error document (`api.md` §3).
  `RefusalCode` is exactly the codes the API answers: the operations'
  (`forbidden`, `invalid_input`, `not_found`, `conflict`,
  `invalid_transition`, `unavailable`, `insufficient_stock`,
  `confirmation_invalid`, `idempotency_conflict`, `deadline_exceeded`,
  `read_only`) and the transport's (`unauthenticated`, `unknown_tool`,
  `invalid_json`, `internal_error`). `fields` maps each field's path, as
  the error document names it (`title`, `lines[0].quantity`), to its
  message; a field with several messages has them joined by a space, as
  a form shows them under the field. It is empty for other refusals.
- `failed`: `network` when no answer came (the fetch rejected, or the
  call was aborted); `answer` when the answer is not JSON or holds no
  error document, such as a proxy's error page.

A call takes an optional second argument `{ signal?: AbortSignal }`.

### 3.5 The call

A call is one `fetch` of `POST /api/TOOL` on the page's own origin,
`credentials: "same-origin"`, with `Content-Type: application/json`, the
input as its body, and `Tun-Api-Proof` set from the page's `<meta
name="tun-api-proof">` (§5). The module holds no token and reads none:
the browser sends the person's session cookie.

## 4. A single-page screen

```lisp
(define-single-page queue ("queue" :title "Queue" :icon :list-checks :policy :employee)
  :files ("my-client" "screens/queue/dist/"))
```

- The screen is served at `/PREFIX` and the paths under it, from the
  folder FILES names: a path relative to the directory of an ASDF
  system, found where the system was loaded from, so it is the same in
  the working tree, a preview and a deployed server. The folder holds
  the screen's built files, `index.html` among them.
- It is a staff page (`ui.md` §8) with that prefix, title, icon,
  `:navigation` and `:group`: its entry is in the menu for those its
  policy admits. Its policy decides who gets any of its files: someone
  not signed in is sent to sign in and back (`auth.md` §3.4), a person
  whose role it does not admit gets the page «This page is not for
  you», 403.
- `GET /PREFIX` and `GET /PREFIX/` answer `index.html` with the proof
  (§5.1) put in its `<head>`, `Content-Type: text/html;
  charset=utf-8` and `Cache-Control: no-store`.
- `GET /PREFIX/PATH` answers the file PATH in the folder when every
  part of PATH is letters, digits, `.`, `_` and `-` not starting with
  `.`, the file is in the folder (a link out of it is not followed), and
  its extension is one of `js`, `mjs`, `css`, `svg`, `png`, `jpg`,
  `jpeg`, `webp`, `gif`, `ico`, `woff`, `woff2`, `json`, `txt`, with
  that type, `Cache-Control: no-cache` and `X-Content-Type-Options:
  nosniff`. Anything else is 404, as an unknown page is.
- Another method than GET is 405 with `Allow: GET`. A request htmx makes
  (a menu entry's link) is answered 200 with `HX-Redirect` to the same
  path, so the browser loads the screen as a document; a preload
  (`Tun-Preload: true`, `ui.md` §4.1) is declined, 204 with
  `Tun-Preload: declined`.
- **The browser's policy is the page's** (`ui.md` §4), on every answer:
  `default-src 'self'; script-src 'self'; style-src 'self';
  style-src-attr 'unsafe-inline'; img-src 'self' blob:; object-src
  'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'self'
  ORIGINS`. For a screen that means: its script and its style sheets are
  files of its folder (`<script type="module" src="…">`, `<link
  rel="stylesheet">`), never an inline `<script>` or `<style>` and never
  `eval`; it calls only its own origin (`connect-src` is `default-src`);
  it shows images of its own and `blob:`; no other site frames it. A
  `style` attribute, and a style set from a script, are allowed.
- If the folder has no `index.html`, `/PREFIX` is 404 and the server's
  error output says which folder it looked in.

## 5. Calling `/api` in the person's session

`/api` takes the session of a person signed in on a page, besides an
access token (`api.md` §2). A request from the browser carries the
session cookie whatever page sent it, so what proves that the
application's own page made a call is not the cookie, which a request
another site makes carries too, but what only that page can know and
send.

### 5.1 The proof

- The proof of a session is the lowercase hex SHA-256 of
  `tun-api-proof:` followed by the session cookie's value (`auth.md`
  §3.3). Under claimed identity (`auth.md` §1) it is that of the
  `tun_actor` cookie's value. It is computed, never stored, and cannot
  be turned back into the cookie.
- A single-page screen's `index.html` carries it as `<meta
  name="tun-api-proof" content="PROOF">`, put right after `<head>`, in
  an answer that is never cached (§4). The page of another origin cannot
  read it, because the browser does not let it read another origin's
  answer, and Tun sends no CORS headers.
- The generated module sends it as the header `Tun-Api-Proof`. A
  request from another site that sets a header of its own is preflighted
  by the browser first, and Tun answers no preflight, so it is never
  sent.

### 5.2 Which call is admitted

A `POST /api/TOOL` without `Authorization: Bearer` that carries the
session cookie of a live session (under claimed identity, without
`X-Tun-Actor` and with a `tun_actor` cookie naming an actor) is a
session call. It is admitted only when all of these hold:

1. `Tun-Api-Proof` is the session's proof, compared in constant time;
2. `Sec-Fetch-Site` is `same-origin`, or, from a browser that sends no
   `Sec-Fetch-Site`, `Origin` is the server's own `scheme://host:port`;
3. `Content-Type`'s media type is `application/json`, compared without
   its parameters and its case (`application/json; charset=utf-8` is
   one).

Any other session call is refused before its body is read, and nothing
of the tool runs: 403, the error document with code `forbidden`, the
request kept as a rejected request of kind `api` (`introspect_recent`),
and audited as the person (`audit_list`: their actor, the
tool the path names, outcome `rejected`, `error_code` `forbidden`, the
session's credential `ses_…`). A request with another site's `Origin`
is refused 403 as before (`api.md` §2), and audited the same way when it
carries a live session's cookie. Looking up the session for the audit
does not count as its use (`auth.md` §3.3).

### 5.3 An admitted call

It runs as the person, with the session's credential: `(credential-kind)`
is `:session` (`:claimed` under claimed identity), so a session-only
operation runs (`core.md` §3.3), and the audit names the session. Its
error document's messages are written in the language the person's
pages are (`i18n.md` §2), as a form shows them; a token call's stay
source text. Everything else is a token call's: policy and record
policies, validation, idempotency by `request_key`, confirmation,
answers and their statuses (`api.md` §3), the request record.

### 5.4 What does not change

- A call with `Authorization: Bearer` is decided by the token alone, as
  before, whatever cookie comes with it: the same actor, the same
  refusals, the same Origin check, never a session's actor or a
  session-only operation.
- A call with neither a token nor a session is 401 as before.
- `X-Tun-Actor` under claimed identity names the caller as before.
- `/mcp` takes no session.

### 5.5 Not yet

- Files over the session path: a session call is not a known caller
  for a body over 256 KB (`core.md` §7.5), so a tool that takes files is
  called from a page's form, not from a screen.

## 6. Not yet, for a later loop

- Building a screen inside the client's Nix build (Node, a bundler and
  the screen's npm dependencies pinned and fetched by Nix), `bin/test`
  type-checking it, and the example screen in Svelte in the showcase.
- Tun's design tokens as a CSS file a screen imports.

## 7. Evidence

- `tests/typescript-tests.lisp`: the module for a fixture registry,
  byte for byte the same twice; the names, the input types and every row
  of §3.2's table; a declared output of each form and an undeclared one;
  the refusal codes against the operations' error codes and the API's;
  two tools whose names would meet; `tsc --strict --noEmit` accepting the
  fixture's screen against the module, and refusing it, naming the
  screen's file, after an operation it calls changed (a parameter
  renamed, a value taken out of an enum, an output's key taken out); the
  module compiled and run in Node against a stand-in `fetch`, for every
  kind of answer of §3.4; `tun typescript` on the showcase writing its
  screen's committed `api.ts`, and `tsc` its committed `dist/`, byte
  for byte; the command's usage errors.
- `tests/session-api-tests.lisp`, written first and seen to fail before
  §5 was built: a session call admitted with its proof, as the person, with
  the session's credential, a session-only operation run, and messages
  in the tenant's language; refused and audited, nothing done, for a
  cross-site request with the cookie, a same-site one from another
  origin, a missing or wrong proof (another session's), a wrong
  `Sec-Fetch-Site`, no `Sec-Fetch-Site` and no `Origin`, a body that is
  not JSON or has no `Content-Type` (and `application/json;
  charset=utf-8` admitted); claimed identity's `tun_actor` cookie with
  and without its proof; an expired session 401; a token call unchanged with a
  session cookie beside it and with another site's `Origin`; the
  session's last use not moved by a refused call.
- `tests/session-api-tests.lisp` too: a single-page screen signed out,
  with a role its policy refuses and signed in, and its menu entry; the proof in its `index.html`; the
  headers of each answer; a file, a path out of the folder, an unknown
  extension, a missing `index.html`; htmx and preload; 405.
- `checks/showcase/checks/single-page-screen.py`: in a browser at 390
  and 1280 px, the showcase's screen, calling through its generated
  module, loads under the page's policy with no violation, calls a
  session-only operation through `/api` with the proof and shows its
  answer, shows a refusal at its field and a call that got no answer,
  and is refused signed out.
