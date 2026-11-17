# A typed TypeScript client generated from the registry, for a screen that is better as a single-page application

- loop: typescript-client
- mode: reviewed
- stage: done
- base: 3cc8b09c81cd015a04f92c76730b6c61c43fee59
- item: sak_bd087aramz0j0apw
- estimate: 4h 7h 12h
- like: tun/workflow-planner tun/erase-audit-download tun/pdf tun/several-clients
- tags: kind:feature core security
- verified: f442e53d8883275771eb2a4c8c5d38c71b6afd2f
- shown: f442e53d8883275771eb2a4c8c5d38c71b6afd2f

## Brief

Ferdig sak_bd087aramz0j0apw, filed by the owner on 2026-11-14:

> «There are definitely cases where a SPA frontend is the best
> alternative, and that opens up the typescript world. I think having
> that as an option, where having something like ash_typescript to
> create a typesafe API from the backend to a typescript frontend would
> be possible.»

The item adds what is meant: an option, not a new default; a TypeScript
client as a third projection of the registry beside MCP and `/api`, so
backend and front end cannot drift; server-rendered pages stay the rule.
To settle first: does every operation declare its output precisely
enough to generate from?

The orchestrator's brief, 2026-11-17, adds the owner's decision of
2026-11-16 that the first such screen is real: a client's screen for
answering what waits for a person, in Svelte, where a signed-in person
sees the top item of a queue, answers it with one tap or sends it to the
back, and the next comes up at once, on a phone first, built in the
client's own repository in the next loop on what this loop publishes.
«Build what that screen needs, and nothing a later screen might need.»
It lists eight parts: (1) `tun typescript`, generated, deterministic, a
changed operation breaking the front end's type check; (2) outputs,
settled by reading the registry, exact where declared, `unknown`-like
where not; (3) refusals as values with the API's kinds, network failure
its own case; (4) the screen served behind its page's policy with a
content security policy that holds, calling `/api` in the person's
session, safe against a forged request from another site, the refusal
tests written first; (5) design tokens as a CSS file; (6) Node,
TypeScript, Svelte and a bundler pinned in the flake, a client's `nix
build` building its screen, and a client without a screen paying
nothing; (7) one example screen in Svelte in the showcase with its
browser checks; (8) the docs. «If the spec shows this is two loops, say
so in the brief before gate A and build the first whole: the generator,
the typed refusals, the session path with its security tests, and the
type-check proof; leaving the Svelte example, the tokens file and the Nix
build of a screen for a second loop.» Mode reviewed, push to main
allowed, no deploy; core 2.47.0, which main took meanwhile for another loop (posted-sets), so this one is 2.48.0.

**This is two loops.** This loop builds parts 1 to 4 and 8 whole: the
outputs operations declare, the generator and `tun typescript`, refusals
as values, a single-page screen served behind its page's policy, the
session path on `/api` with its security tests, the type-check proof
with `tsc`, and the docs. It leaves for a second loop parts 5, 6 and 7:
the design tokens' CSS file, building a screen inside a client's Nix
build (Node, a bundler, the npm dependencies locked and fetched by Nix,
`bin/test` type-checking the screen), and the example screen in Svelte.
Why, under Decisions.

## Criteria

Declared outputs (`spec/core.md` §3.11):

1. **A declaration.** `define-operation` takes `:returns` as an entity,
   `(:page E)` or `(:object (key X [:optional t]) …)`, whose keys' X may
   also be `(:list X)` or `(:value TYPE)`; any other form, a list or a
   value as the whole result (a result is a JSON object), or a key given
   twice, is refused when the definition is compiled. `registry_describe` gives each
   operation's `returns`, the output's JSON Schema, or null when it
   declares none. (test)
2. **Checked under the test clock.** A call through `call-tool` whose
   result does not match its declaration is an internal error naming
   the tool and the first place it differs (`items[0].status`); a
   matching one answers as before; a confirmation request is not
   checked; on the real clock nothing is checked. (test)

The module (`spec/typescript.md` §2, §3):

3. **Deterministic.** The module for a registry is the same bytes when
   generated twice; functions and record types come in the order of
   their names; its first line says it is generated and how to write it
   again. (test)
4. **What it holds.** One function per operation but the test-only,
   debug-only and eval-only ones, session-only ones included; two tools
   whose function names would meet stop it, naming both. (test)
5. **Inputs.** Each row of §3.2's table; a required property `name: T`,
   another `name?: T | null`; `request_key` and `confirmation_token`
   where the schema lists them; an input with nothing required is an
   optional argument. (test)
6. **Outputs.** Each form of criterion 1 typed exactly; a record's
   interface with required fields `T`, others `T | null`, a secret
   `string`, computed fields among them; an undeclared output
   `Undeclared`. (test)
7. **Answers, run.** The fixture's module, compiled by `tsc` and run
   in Node against a stand-in `fetch` and `document`, sends `POST
   /api/TOOL` on its own origin with `credentials: "same-origin"`,
   `Content-Type: application/json`, the input as its body and
   `Tun-Api-Proof` from the page's meta tag, and answers: `ok` with the
   body; `confirm` with `confirmation_token`, `expires_at` and `summary`
   for a confirm operation's request for confirmation; `refused` with
   the code, the status, the message, `fields` mapping each path to its
   message, two messages of one field joined by a space, and `details`
   holding the error document's other keys; `failed` `network`, status
   0, when `fetch` rejects (an aborted `signal` among them); `failed`
   `answer` with the status for an answer that is not JSON or holds no
   error document. `RefusalCode` is exactly the operations' error codes
   and the transport's four. (test)
8. **The type check.** `tsc --strict --noEmit` accepts the fixture's
   screen against its module; after the fixture changes an operation the
   screen calls (a parameter renamed; a value taken out of an enum; a
   key taken out of a declared output), the module written again makes
   `tsc` fail, naming the screen's file. (test)
9. **The command.** `bin/tun typescript FOLDER --dir checks/showcase`
   writes `FOLDER/api.ts`, byte for byte the showcase screen's committed
   `src/api.ts`; `tsc` compiles the screen's committed sources to its
   committed `dist/` files byte for byte, so neither can be stale. No
   FOLDER, two, an unknown option, or a DIR that holds no client is a
   usage error, exit 2, writing nothing. (test)

`/api` in the person's session (`spec/typescript.md` §5), the refusal
tests written first and seen to fail on main's behaviour:

10. **Admitted.** A POST with a live session's cookie, its proof in
    `Tun-Api-Proof`, `Sec-Fetch-Site: same-origin` (or, without it, the
    server's own `Origin`) and a JSON body (`Content-Type`'s media type,
    compared without its parameters and its case, is
    `application/json`: `application/json; charset=utf-8` is admitted)
    runs as the person:
    `accounts_whoami` says the person and `session`, a session-only
    operation runs, an `invalid_input`'s messages are in the tenant's
    language (Norwegian on a Norwegian tenant), a mutation's audit entry
    names the session. (test)
11. **Refused and audited.** Each of these is 403 `forbidden`, the body
    unread, no record of the tool's entity made (a refused
    `accounts_create` makes no account), the request kept as a rejected
    request of kind `api`, and one audit entry:
    the person's actor, the tool, `rejected`, `forbidden`, the session's
    `ses_…`: no proof; another session's proof; `Sec-Fetch-Site:
    cross-site`; `same-site` (another origin on the same host);
    `none`; neither `Sec-Fetch-Site` nor `Origin`; another site's
    `Origin` with the cookie; a body sent as `text/plain`; no
    `Content-Type`. (tests)
12. **Nothing weaker.** A token call with a session cookie beside it acts
    as the token's account, and a session-only operation stays refused
    for it; a token call with another site's `Origin` is 403 as before;
    no token and no session is 401; an expired session with a right
    proof is 401; a refused session call does not move the session's
    last use. (tests)
13. **Claimed identity.** Under `--claimed-identity` a call with the
    `tun_actor` cookie and its proof runs as that actor with credential
    `claimed`; without the proof it is refused; `X-Tun-Actor` names the
    caller as before. (test)

A single-page screen (`spec/typescript.md` §4):

14. **Its policy.** `define-single-page` serves `/PREFIX`: signed out, a
    GET goes to `/login?next=/PREFIX`; a role its policy refuses gets
    403; signed in, `index.html` with the session's proof in a meta tag
    right after `<head>`, `text/html`, `no-store`, and the page's
    `Content-Security-Policy`, exactly; its entry is in the menu for an
    admitted role and not for another. (test)
15. **Its files.** A file of an allowed extension under the folder, with
    its type, `nosniff` and `no-cache`; a path out of the folder (`..`,
    a link out of it), a part starting with `.`, an unknown extension
    and a missing file are 404; a missing `index.html` is 404 with a
    line naming the folder; POST is 405 with `Allow: GET`; an htmx
    request gets 200 with `HX-Redirect` to the same path; a preload
    (`Tun-Preload: true`) gets 204 with `Tun-Preload: declined`. (test)
16. **In a browser.** The showcase's screen, whose code calls through
    its generated module compiled by `tsc` (criterion 9), at 390 and
    1280 px: loads under the page's policy with no violation reported; a
    tap calls a session-only operation through `/api` with the proof and
    shows its `ok` answer; a submission with a field left empty shows the
    `refused` answer's message at that field; a call the check makes
    fail on the way (Playwright aborts the request) shows the `failed`
    `network` answer; signed out, the screen's address leads to the
    sign-in. (browser check)

The rest:

17. **The docs.** `spec/typescript.md`, `spec/core.md` §3.11,
    `spec/api.md`, `spec/auth.md`, `spec/cli.md` §5.1, `spec/ui.md` §8,
    `docs/client-api.md` («A single-page screen»: when, and how a client
    adds one, start to finish as far as this loop goes; what a client
    without one pays), `reference/pitfalls.md`. (by hand, gate B)
18. **Clients unchanged.** Core 2.48.0 in `+core-version+` and the
    flake; Tun's dev shell has `tsc` and no client's shell or build
    does; every client of the installation passes its `bin/test`
    unchanged on this tree. (test for the version; the clients' runs
    logged)

## Decisions

### Two loops

The second half is not smaller work done thin: a screen built inside a
client's Nix build needs Node, a bundler, Svelte and the screen's npm
dependencies fetched by a fixed-output derivation and pinned by hash,
`buildClient` taught to build a screen into the client's source before
the Lisp build, and a client's `bin/test` to type-check it; the
showcase's Svelte screen needs that build to exist in Tun's own flake
first; the design tokens need a generator from the UI library's token
source and a drift test. Each is a day's risk of its own (the PDF loop
that added one outside program to the flake and the servers took 2h19
with no npm at all). The first half is what the security of the whole
rests on, and what any screen, Svelte or not, calls through. So this
loop builds the first half whole, with a small screen in plain
JavaScript in the showcase to prove the session path in a real browser,
and the second loop builds the Svelte screen, the tokens and the Nix
build on it. Until then a client can generate its module and type-check
and build its screen with its own tools; the docs say so.

### Outputs: what the registry declared

Read from `src/core/operation.lisp`: `define-operation` takes no output
declaration at all. `:entity` and `:kind` suggest a result (a create
usually answers its record) but bind nothing: the body returns any
record or JSON object, and lists answer `page`'s `{items, returned,
has_more}` by convention. Only `define-query` declares `:returns`, and a
query is a function a client's code calls, not a tool. So no operation's
output can be typed exactly from what is there, and guessing from
`:entity` and `:kind` would give types that are sometimes wrong, which
is worse than none. Outputs become exact only where an operation says
`:returns`; the grammar covers what Tun's results are (a record, a page
of records, a list, an object, a value), and it is checked against the
real results under the test clock, so a declaration cannot lie in any
path the suites, previews or checks run. It is not checked on the real
clock, where a wrong declaration should not fail a person's call. No
existing operation of the kernel or the modules gets a declaration in
this loop; the test fixture and the showcase's screen declare theirs.
`(:list X)` and `(:value TYPE)` are only the values of an object's keys,
found while building: a result is always a JSON object (MCP's
`structuredContent` is one, and `result->json` takes a record or an
object), so a declaration of a list as the whole result could never
hold.

### The session path

- **What proves the page made the call.** The cookie does not: a
  request from another site carries it too (`SameSite=Lax` keeps a
  cross-site POST from carrying it, but not a request from another
  origin on the same site, such as another tenant on another port of
  the same host, which `spec/auth.md` §3.3 already names). The proof is a
  value derived from the session cookie, SHA-256 of `tun-api-proof:` and
  the cookie, put in the screen's `index.html` (never cached) and sent
  back as `Tun-Api-Proof`. Another origin cannot read it (the browser
  does not let it read the answer, and Tun sends no CORS headers), and
  cannot send a header of its own without a preflight, which Tun never
  answers. It is computed, never stored, and does not reveal the cookie;
  a new session has a new one. A double-submit cookie would need a
  second cookie readable by script; a stored token per session a schema
  change; the derived value needs neither.
- **Two more checks behind it**, so one mistake does not open it:
  `Sec-Fetch-Site: same-origin` (or the server's own `Origin` from a
  browser without it, as the pages' rule, `cross-origin-post-p`, already
  judges a post) and a JSON body, which a plain form can never send.
  Both are what every modern browser's `fetch` from the page sends.
- **Audited as the person.** A refused session call is written in
  `audit_list` as the person's rejected call of the tool, with the
  session's credential, so a forged request is visible where an admin
  looks. Looking up the session for it does not touch its last use: a
  forged request must not keep a session alive.
- **Token callers unchanged.** The token is read first and decides
  alone, as before; the session is looked at only when there is no
  token, where today's answer was 401. `/mcp` takes no session.
- **Messages in the person's language.** A session call's error
  document is written in the language of the person's pages, so the
  screen shows a field's message as a form would; a token call's stays
  source text (`spec/i18n.md` §7).
- **Claimed identity** (previews, browser checks) takes the `tun_actor`
  cookie as the session, with the proof of its value, so the browser
  check exercises the same path; it has no security of its own, as
  before.

### The module

- `tun typescript FOLDER` names what it writes, as `tun list` and `tun
  preview` name what they do; it writes `FOLDER/api.ts`, so the
  screen's code imports `./api`. It loads the client as `tun preview`
  does, so it needs nothing but the client's dev shell.
- Every operation a person in a session may call is in it: the policy
  is decided on the server at each call, and a bundler drops what the
  screen does not import. Test-only, debug-only and eval-only tools are
  not, whatever the generating process runs with, so the module does
  not depend on flags.
- Inputs come from `operation-input-schema`, the schema `tools/list` and
  `/api` validate with, through a JSON Schema to TypeScript writer; the
  outputs from the declaration through the same writer, so one mapping
  holds for both.
- A call answers a tagged union and never throws: a screen switches on
  `kind`, and a refusal's `fields` is a map from the field's path to its
  message, ready to show at the field. Data keeps the API's snake_case.
- The type check runs `tsc` from nixpkgs (`pkgs.typescript`, 5.9.3),
  and the runtime's test `node` (`pkgs.nodejs`, 24), in Tun's dev shell
  only: Tun's suite needs them; a client's shell and build stay without
  Node.

### Exact outputs, counted

The showcase's module has 74 functions (the kernel's operations, the
customers and meetings modules', and the showcase's own); 2 of them come
out with an exact output, `sign_offs_create` and `sign_offs_list`, the
two its screen calls. None of the kernel's or the modules' operations
declares one, so in any client's module every one of theirs is
`Undeclared` until a loop declares it where a screen needs it.

### The screen

- `define-single-page` makes a staff page, so its policy, the sign-in
  and its menu entry are the pages' own code; it answers files instead
  of a page. A menu link is boosted by htmx, which would swap a document
  into the shell, so an htmx request is answered with `HX-Redirect` to a
  full load, and a preload is declined.
- The folder is named by an ASDF system and a path in it, found where
  the system was loaded from: the working tree, a preview, the store.
- The showcase's screen is a small TypeScript screen without a
  framework or a bundler: its `src/screen.ts` and its generated
  `src/api.ts`, compiled by `tsc` (one ES module each) into `dist/`
  beside its `index.html`. The generated and the compiled files are
  committed, since the showcase has no build of its own until the second
  loop, and a test writes both again and compares them byte for byte, so
  they are never stale. The browser check then runs the module's real
  `fetch`, proof and answers; the runtime's every branch is also run in
  Node against a stand-in `fetch` (criterion 7), where a branch a
  browser rarely meets (a non-JSON answer, two messages of one field) is
  easy to make. Node comes with `tsc` in Tun's dev shell.

## Evidence

Each criterion and what decides it:

1. `a-returns-declaration-is-checked-when-compiled`,
   `the-registry-describes-what-an-operation-returns`
   (`tests/typescript-tests.lisp`).
2. `a-result-that-breaks-its-declaration-fails-under-the-test-clock`:
   a wrong enum value at `items[0].status`, a key left out, a list that is
   not one; a confirmation request passes; on the real clock nothing is
   checked.
3. `the-module-is-the-same-bytes-each-time`; across processes,
   criterion 9's test (the committed module was written by an earlier
   process).
4. `the-module-holds-what-a-session-may-call`,
   `two-tools-whose-functions-would-meet-stop-the-module`.
5. `json-schema-becomes-typescript` (every row of §3.2),
   `the-module-types-inputs-from-their-schema`.
6. `the-module-types-declared-outputs-exactly`.
7. `the-module-answers-every-kind-of-answer-in-node` (the module and
   `tests/typescript/runtime.ts` compiled by `tsc`, run by `node` against
   a stand-in `fetch`), `the-refusal-codes-are-the-api-s`.
8. `tsc-takes-the-screen-and-refuses-it-once-an-operation-changed`
   (`tests/typescript/screen.ts`; `tsc` exits 2 naming `screen.ts` for
   each of the three changes, and 0 once each is undone).
9. `tun-typescript-writes-the-showcase-screen-s-committed-module`
   (`bin/tun typescript` on the showcase, compared byte for byte with
   `screen/src/api.ts`; `tsc` of the screen compared with
   `screen/public/dist/`), `tun-typescript-refuses-a-wrong-command-line`.
10.–13. `tests/session-api-tests.lisp`:
   `a-session-call-from-the-page-runs-as-the-person`,
   `a-session-call-another-site-sends-is-refused-and-audited` (nine
   cases), `a-refused-session-call-does-not-keep-the-session-alive`,
   `a-token-call-is-as-before-beside-a-session`,
   `claimed-identity-takes-the-actor-cookie-with-its-proof`; written
   first and seen to fail on main (Log, 03:50).
14.–15. `a-single-page-screen-is-behind-its-page-s-policy`,
   `a-single-page-screen-is-in-the-menu-of-those-its-policy-admits`,
   `a-single-page-screen-answers-its-files-and-nothing-else`,
   `a-screen-s-file-must-be-in-its-folder` (a link out of the folder),
   `a-screen-without-its-index-says-where-it-looked`.
16. `checks/showcase/checks/single-page-screen.py`, at 390 and 1280 px.
17. By hand at gate B.
18. `+core-version+` and `coreVersion` 2.48.0 (the core test that
    compares them); `flake.nix`'s diff adds `typescript` and `nodejs`
    to Tun's own dev shell only, and leaves `clientShell`, `buildClient`
    and `cli` as they were; the clients' runs under «Clients».

## Verify rounds

1. 853fb43c: build, test (217 s) and check (704 s) passed, after 49m42s
   waiting for the verify lock behind other builders' rounds.
2. 2fddd60a, after rebasing on main's 3cc8b09c (loop posted-sets, which
   took core 2.47.0: this loop is 2.48.0; one conflict, the showcase's
   Norwegian catalogue, both sides kept; the showcase's module written
   again, 74 operations with main's two new ones): build, test (192 s)
   and check (739 s) passed, after 53m45s waiting for the lock.

No round failed.

## Pictures

`~/coding/tun-wt/typescript-client-shots/`: `tun loop show`'s
`phone-sign-off.png` and `desktop-sign-off.png`, and the screen's three
states on a phone and wide, taken from the same preview:
`phone-1-open.png`, `phone-2-refused-at-the-field.png`,
`phone-3-signed-off.png` and the `wide-` three. The refusal is the
field's own message under it, «must be filled in»; the answer «Signed
off by employee:anna (claimed)», claimed being the preview's identity.
This is a new screen, not a change to how Tun looks, so there are no
before and after pictures.

## Clients

Each client's `bin/test`, from a clone in a scratch folder, its Tun
inputs (`tun`, and `dashboard` and `customers` at their `modules/`
directories) overridden with this worktree's commit 2fddd60a (the tree
verify round 2 passed), one at a time under `flock` on the verify lock,
unchanged: factory 1093 checks, ferdig 812, nixploy-dashboard 1421
(tunworks `ee844de`); kurs 352 (`c2579ae`); the two-client client
repository (`178416a`), its first client's suites (9578, 219, 72140,
390, 539, 373, 8856, 255, 127042, 91150, 16264 and 28157 checks) and its
second client's (160): every one exit 0, no compiler warning, no
failure. The lock waits were 69, 136, 94, 89 and 92 minutes.

A first run against 853fb43c lost four of its five clients to a quoting
mistake in the script that ran them (a module input's URL with `&`
unquoted in a `bash -c` string: exit 127 before `bin/test` began); only
kurs ran then, 352 checks, exit 0. The second run above is the one that
counts.

What a client sees differently on 2.48.0: nothing unless it uses it. An
operation without `:returns` answers as before; `registry_describe` has
a new key per operation, `returns` (null); `/api` without a token and
with a session's cookie but no proof is now 403 and audited where it was
401; a client's shell and build have no Node and no new step.

## Actuals

```json
{"loop":"typescript-client","title":"A typed TypeScript client generated from the registry, for a screen that is better as a single-page application","repository":"tun","mode":"reviewed","stage":"done","item":"sak_bd087aramz0j0apw","tags":["kind:feature","core","security"],"like":["tun/workflow-planner","tun/erase-audit-download","tun/pdf","tun/several-clients"],"started":"2026-11-17 03:33","ended":"2026-11-17 18:37","minutes":{"total":904,"waiting_person":0,"waiting_reviewer":2,"working":902,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":240,"likely":420,"worst":720,"at":"brief"},"latest_estimate":{"best":240,"likely":420,"worst":720,"at":"brief"},"within_estimate":false,"ratio":2.15,"verify":{"rounds":2,"failed":0},"changes":{"A":1,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-17 03:33  started, reviewed
- 2026-11-17 03:37  estimated 4h 7h 12h at brief, like tun/workflow-planner tun/erase-audit-download tun/pdf tun/several-clients
- 2026-11-17 03:43  gate A asked of a reviewer
- 2026-11-17 03:44  gate A: changes (reviewer)
  The split into two loops is fine. Three things need changing before gate A passes, and one of them is a real gap: the generated module's runtime code is never run.
  
  **What is right**
  
  - **The split.** The orchestrator's brief allowed two loops if the spec showed it, and asked for that to be said before gate A. It is said. The first half is parts 1–4 and 8, which is the set the brief named: the generator, typed refusals, the session path with its security tests, and the type-check proof. Parts 5–7 are deferred, and `spec/typescript.md` §6 says so.
  - **Outputs.** Brief part 2 asked to read the registry first. The "Outputs" decision does that: today nothing declares an output. Making outputs exact only where an operation says `:returns`, and never guessing from `:entity`/`:kind`, is right. Checking declarations under the test clock and not the real one is a reasonable engineering choice, not one the asker had to make.
  - **The session path.** Criteria 10–13 and `spec/typescript.md` §5 agree with each other. The proof is SHA-256 of `tun-api-proof:` and the cookie. It is backed by a same-origin check and a JSON-only body. Token calls are unchanged, a refused call is audited as the person, and the audit lookup does not count as a use of the session. The refusal cases in criterion 11 cover the attacks that matter, including another origin on the same host, which `spec/auth.md` §3.3 already names.
  - **The spec changes match the criteria.** That covers `core.md` §3.11 against criteria 1–2, `typescript.md` §2–3 against criteria 3–9, §4 against criteria 14–15, and the `api.md`, `auth.md`, `cli.md` §5.1 and `ui.md` §8 changes.
  - **"A client without a screen pays nothing"** is in criterion 18 and in `docs/client-api.md`.
  
  **Changes**
  
  1. **The module's runtime code is never run by any test or check.**
     - Criteria 3–9 only compare the module's text or run `tsc --noEmit` on it.
     - Criterion 16's browser check runs a screen written by hand in plain JavaScript. Per Decisions › The screen, it "calls `/api` exactly as the module does", but nothing shows that.
     - So no test exercises the `fetch`, the `Tun-Api-Proof` header read from the meta tag, the parsing into `ok`/`refused`/`confirm`/`failed`, `failed` with `network`, or joining several messages of one field (criterion 7).
     - Brief part 3 is exactly "refusals as values … network failure its own case". The next loop builds the Svelte screen on this module, so a broken runtime would only show up there.
     - The reason given for the hand-written screen doesn't hold. `tsc` is in Tun's dev shell (Decisions › The module), and it can emit a single ES module with no bundler. `docs/client-api.md` (diff line 89) already tells clients to commit their built folder.
     - **Change:** make the showcase's screen call through the generated module, compiled by `tsc` and committed, with a test that the committed output is current. Extend criterion 16 so the browser check shows:
       - an `ok` answer;
       - a `refused` answer whose `fields` message is shown at its field;
       - a `failed`/`network` answer (for example, a call aborted with its `signal`).
  
     Then state how criterion 7's "fields joins several messages" is decided, since a text test of the generated source does not decide it.
  2. **Criterion 11's "nothing done (no record made)" conflicts with `spec/typescript.md` §5.2.** The spec says a refused call is "retained as a rejected request of kind `api`". **Change:** say no record of the tool's entity is made and the request is kept as rejected, so a test can decide it without guessing.
  3. **The Content-Type rule is unclear** (`spec/typescript.md` §5.2 item 3, and the `text/plain` case in criterion 11). Is `application/json; charset=utf-8` admitted? **Change:** say whether the media type is compared without its parameters, and add one case for it to criterion 10 or 11.
  
  **Minor, not blocking**
  
  - Criterion 15's "a preload is declined" should name the answer (its status) so a test can decide it.
  - Criterion 9 leaves out the spec's "a DIR that holds no client" usage error.
- 2026-11-17 03:46  gate A asked of a reviewer
- 2026-11-17 03:46  gate A: approve (reviewer)
  I'm approving gate A. The second round fixes all three changes from the first review and both minor points. The criteria now cover what the brief asks for this loop, and nothing more.
  
  **The earlier changes are fixed**
  - **The module's code now runs.**
    - Criterion 7 compiles the fixture's module with `tsc` and runs it in Node against a stand-in `fetch` and `document`. It names every kind of answer: `ok`, `confirm`, `refused` (with `fields`, two messages of one field joined by a space, and `details`), `failed` `network` (an aborted `signal` among them), and `failed` `answer`.
    - Criterion 16 makes the showcase screen call through its generated module. The browser check must show an `ok` answer, a refusal's message at its field, and a `failed` `network` answer from a request Playwright aborts.
    - Criterion 9 has a test that the committed `src/api.ts` and `dist/` files match what the command and `tsc` write again, byte for byte, so neither can be stale.
  - **Criterion 11** now says no record of the tool's entity is made and the request is kept as a rejected request of kind `api`. This matches `spec/typescript.md` §5.2 (diff line 548ff).
  - **The Content-Type rule** compares the media type without its parameters or case, in both criterion 10 and §5.2 item 3. `application/json; charset=utf-8` is a named admitted case, and `text/plain` and a missing Content-Type are named refused cases.
  - **The minor points:** a preload now gets 204 with `Tun-Preload: declined` (criterion 15, §4), and criterion 9 includes "a DIR that holds no client".
  
  **What is right**
  - **Brief coverage.** Parts 1–4 and 8 are covered:
    - generated and deterministic, with the type check breaking on a changed operation: criteria 3, 8, 9;
    - outputs read from the registry, exact where declared and `Undeclared` elsewhere: criteria 1, 2, 6;
    - refusals as values with the API's codes, and network failure as its own case: criterion 7;
    - the screen behind its page's policy, with a content security policy that holds: criteria 14–16;
    - the session path, its forged-request refusals and the tests written first: criteria 10–13;
    - the docs: criterion 17.
  - **The split.** Parts 5–7 are deferred in `spec/typescript.md` §6, as the brief allowed.
  - **"A client without a screen pays nothing"** is in criterion 18 and `docs/client-api.md`.
  - **Every criterion can be decided** by a test or a check, except criterion 17, the docs, which is reviewed by hand at gate B.
  - **`RefusalCode` is complete.** I checked it against the source: the API's 503 overload answer uses `unavailable` (`src/agent/http.lisp:179`), and the token's errors are `unauthenticated` (`http.lisp:631-641`). Both are in §3.4's list, so the "exactly" in criterion 7 holds.
  - **The spec says the same as the criteria.** I compared §2–§5 of `spec/typescript.md`, `core.md` §3.11, and the `api.md`, `auth.md`, `cli.md` §5.1 and `ui.md` §8 changes against criteria 1–16.
  - **The design choices are the builder's to make**, not the asker's: the proof, the two checks behind it, checking declarations only under the test clock, and not declaring outputs on existing operations.
  
  **Not blocking:** §7's list of evidence for `tests/api-tests.lisp` (diff line 606ff) leaves out three cases that criteria 10 and 13 require: a missing Content-Type, the `charset` case, and claimed identity. The criteria decide what gets tested, so this only matters for keeping the spec's evidence list complete. It can be fixed at gate B.
- 2026-11-17 03:50  tests first: tests/session-api-tests.lisp on main's behaviour (bin/test --only session-api, kept in .build/loop/typescript-client/session-tests-on-main.log): 67 checks, 38 failed: every admitted session call answered 401 (criteria 10, 13), every forged one 401 and not audited where 403 and an audit entry are asked (11), the last-use test likewise; a-token-call-is-as-before-beside-a-session passed whole (12), as it must before and after
- 2026-11-17 05:29  verify 1: passed build, test, check
- 2026-11-17 05:29  shown (/sign-off)
- 2026-11-17 10:13  rebased: tun 945d834 → 3cc8b09
- 2026-11-17 11:25  verify 2: passed build, test, check
- 2026-11-17 11:26  shown (/sign-off)
- 2026-11-17 18:34  clients at 2fddd60a, each bin/test from a scratch clone under flock on the verify lock: factory 1093, ferdig 812, nixploy-dashboard 1421 (tunworks ee844de), kurs 352 (c2579ae), the two-client client repository (178416a) both clients: exit 0, no compiler warning, unchanged
- 2026-11-17 18:35  gate B asked of a reviewer
- 2026-11-17 18:36  gate B: approve (reviewer)
  I'm approving gate B. Every criterion has a test or a check that would fail without the change, the code does what the spec says, and all three verify steps passed. I found nothing that needs changing; two small notes are at the end.
  
  **Criteria and how they are decided**
  - **Declared outputs (1–2).** `check-output-form` (`src/core/outputs.lisp:269`) refuses a list or a value as the whole result, a key given twice, an unknown option and a type that doesn't exist, all when the definition is compiled. `call-tool` checks a result only when `test-mode-p` holds (`src/core/execution.lisp:691ff`), and lets a confirmation request through unchecked. The test makes the result wrong on purpose and gets an error naming the tool and `items[0].status`, and shows the real clock checks nothing.
  - **The module (3–9).** Covered by tests on the text, every row of §3.2 and every output form. `tsc` refuses the fixture screen, naming `screen.ts`, after each of the three operation changes, and accepts it once each is undone. A Node test runs the compiled module against a stand-in `fetch` and covers every kind of answer: `ok`, `confirm`, `refused` (two messages of one field joined, `details`), `failed` `network` (an aborted signal among them) and `failed` `answer`. `bin/tun typescript` on the showcase is compared byte for byte with the committed `src/api.ts`, and `tsc` with the committed `dist/`. The usage errors exit 2 and write nothing. This fixes the main gap from the first gate A review: the module's own code now runs.
  - **The session path (10–13).** `serve-session-call` (`src/agent/http.lisp:2954ff` in the diff) only looks at the session when there is no bearer token and no `X-Tun-Actor`, so token callers are unchanged. The proof is compared in constant time. The Origin/Sec-Fetch-Site check and the media-type check (parameters and case ignored) match §5.2. Refused calls are audited with `touch nil`, so a forged request does not keep a session alive. The tests cover all nine forged cases (403, no account made, one audit entry each, kept as a rejected request of kind `api`), the charset case, Norwegian messages, token-with-cookie, expiry and claimed identity. The log shows them written first and failing on main (38 of 67 checks).
  - **The screen (14–15).** It is the staff page's own code. Containment uses `probe-file` and a prefix compare on the folder's real path, and the symlink test proves a link out of the folder is not followed. `index.html` is not served directly, so it is never answered without the proof. The policy is compared with `/access`'s. htmx gets `HX-Redirect`, a preload gets 204, POST gets 405.
  - **In a browser (16).** `checks/single-page-screen.json` passed at both widths. It shows the policy with no violation, the proof in the meta tag, the field's own refusal message, the `ok` answer from a session-only operation, a 64-hex proof and JSON content type on both calls, `No answer came` when Playwright aborts the request, no page load, and the sign-in when signed out. The screenshots at 390 and 1280 px show the screen laid out cleanly.
  - **Docs (17).** I read them by hand: `spec/typescript.md`, `core.md` §3.11, `api.md`, `auth.md`, `cli.md` §5.1, `ui.md` §8, `docs/client-api.md` «A single-page screen» (from start to finish, including what a client without a screen pays) and `pitfalls.md`. They say what the code does. The gap gate A noted in §7's evidence list (missing Content-Type, charset, claimed identity) is now filled.
  - **Clients (18).** Core is 2.48.0 in both `+core-version+` and `flake.nix`. `typescript` and `nodejs` are added to Tun's dev shell only. Every client's `bin/test` passed unchanged at 2fddd60a.
  
  **Brief.** This loop builds parts 1–4 and 8 whole, as the agreed split says, and leaves Svelte, the tokens and the Nix build for the second loop. `spec/typescript.md` §6 and the docs say so.
  
  **Code.** It follows `AGENTS.md`: the spec changed with the behaviour, there is no leftover debugging, the comments explain why, and the one special case (the htmx redirect) is explained.
  
  **Verification.** Build, test and check all passed in round 2.
  
  **Not blocking**
  - The Evidence section of `loop.md`, item 18 (line 376), still says "2.47.0"; the code and the criterion say 2.48.0.
  - The showcase screen's own words ("Sign off", "No answer came. Try again.") are English only. That's acceptable for a test screen, but the docs could say how a real screen gets the person's language.
- 2026-11-17 18:37  finished at tun 684ebe78
