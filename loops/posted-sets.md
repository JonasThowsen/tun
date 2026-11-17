# A posted form keeps a repeated name, and a public page hands a file to the browser

- loop: posted-sets
- mode: reviewed
- stage: ship
- base: 945d834a6ef05fae87bd00f81a3aa68a79181c27
- item: sak_fyatfdaafm4k68p7
- estimate: 2h 3h30m 7h
- like: tun/erase-audit-download tun/workflow-planner tun/several-clients
- tags: kind:fault core
- verified: 5d9f216cfb50477a1b9e705e27270e1437cf74ae
- shown: 5d9f216cfb50477a1b9e705e27270e1437cf74ae

## Brief

Two Ferdig items in the project «Tun», brought together by the factory's
orchestrator on 2026-11-17 because both are in the same dispatch code
(`src/web/ui.lisp`, `dispatch-staff-page` and `dispatch-public-page`).

sak_fyatfdaafm4k68p7, a fault, as filed:

> A staff page's posted form keeps one value per name:
> `dispatch-staff-page` (src/web/ui.lisp) sets each posted pair with one
> `setf`, so the last value wins. Only the page's query (`query-object`)
> keeps a name given more than once as an array. `ui:checkboxes` posts one
> name several times, so a form with several boxes ticked saves only the
> last one, silently. A client's test saw it: two boxes ticked, the first
> lost. Client forms built on `ui:checkboxes` for choosing several people
> are affected today.
>
> Wanted: a posted form keeps a repeated name as an array, as the query
> does (one value stays a string or becomes an array by a rule the docs
> state and `ui:checkboxes` relies on); the same for a public page's form;
> a test posts a `ui:checkboxes` form with none, one and three boxes
> ticked and reads none, one and three; `reference/pitfalls.md` says what a
> handler receives. Every client passes unchanged, or the record names the
> form whose saved value changes because it was losing ticks.

sak_ymaa72jhybwdk6d9, as filed (its last paragraph, about `ecase-of`
over a set of strings, is not in this loop):

> Core 2.44.0 lets a staff page return `(values 200 :download
> (make-download …))`, sent after the page's policy has admitted a
> signed-in person. A public page cannot: `dispatch-public-page`
> (src/web/ui.lisp) passes the handler's values straight to `respond` and
> has no download branch, and `/files/ID` serves signed-in callers only.
> So a client cannot hand someone who holds a link token (a customer
> reading a document sent to them) the document's stored file.
>
> Wanted: a public page's handler may return a download, decided by the
> page's own token, with the same allowed types and headers as a staff
> page's (spec/files.md §5.5); nothing else about `/files/ID` changes.
> Refusal tests first: a token of another purpose or another record never
> reaches the file; a page that returns no download answers as today.

The orchestrator's brief adds: one stated rule for what a handler
receives, and a name given once stays what handlers get today; the
failing tests first, a `ui:checkboxes` form posted with none, one and
three ticked reading none, one and three, and a showcase form with a
browser check that ticks two and sees two saved; `reference/pitfalls.md`
and `docs/client-api.md` say what a handler receives; look for other
places a client meets the same loss (htmx posts, the form helpers that
read a list). For the download: the same allowed types, headers and
refusal of a type not allowed, decided by nothing but the page's own
handler; security first, as tests seen failing before the code: a page
that returns no download answers exactly as today (byte for byte on an
existing page); a download's headers are §5.5's; a HEAD or a GET with a
wrong token returns what the handler returns for it (a 404), never a
file; nothing about `/files/ID` changes. The docs show the pattern for a
page with a link token handing over a stored file and say what the
handler itself must check. Keep the change small and local to the page
dispatch (another loop works in `src/web/` at the same time); no page of
the showcase changes its look. Every client passes on the tree; a client
test that now sees a form save more is the fault mended, and is named
here, with no client changed.

## Criteria

A posted form (`spec/ui.md` §8, «A client's pages» 2 and «Public pages»
1):

1. **A staff page keeps a repeated name.** A form of `ui:checkboxes`
   (name `days`, five choices), rendered with none, one and three boxes
   ticked and posted as a browser posts it, gives the page's FORM no
   `days`, the text `"mon"`, and the array `["mon","wed","fri"]` in the
   order posted, and `(query-values form "days")` NIL, `("mon")` and
   `("mon" "wed" "fri")`: urlencoded, as `multipart/form-data`, and as an
   htmx post. (test, seen failing before the code)
2. **So does a public page.** The same three posts to a public page,
   urlencoded and as an htmx post, give its FORM the same (a multipart
   post to a public page is refused before it, as it is today: no
   session). (test, seen failing before the code)
3. **A name posted once is what it was.** A form whose names are each
   posted once gives the page the same JSON object as before: every name
   its text, an empty text kept as `""`; a name with files is still the
   array of `{filename, upload}` (`files.md` §6.2). (test)
4. **The showcase saves every tick.** A page out of the menu, «Visit
   days», has a `ui:checkboxes` of the five weekdays that saves through
   an operation; at 390 px with and without JavaScript, and at 1280 px,
   ticking two and saving shows those two saved and ticked when the page
   is opened again; three show three; none shows none. No other page of
   the showcase changes. (`checks/showcase/checks/posted-sets.py`)
5. **Said where a page's author reads.** `spec/ui.md` §8,
   `docs/client-api.md` («Pages», «Public pages»), `reference/pitfalls.md`
   and `ui:checkboxes`'s doc say what a handler receives for a name given
   once and given several times, and to read a set with `query-values`.

A download from a public page (`spec/files.md` §5.5, `spec/ui.md` §8,
«Public pages»):

6. **The same answer as a staff page's.** A public page that returns
   `(values 200 :download (make-download OCTETS :filename NAME
   :content-type TYPE))` answers 200 with exactly the octets and §5.5's
   headers: the type (`; charset=utf-8` for the text types and JSON),
   `Content-Length`, `Content-Disposition: attachment; filename="…";
   filename*=UTF-8''…`, `X-Content-Type-Options: nosniff`, the file's
   `Content-Security-Policy`, `Cross-Origin-Resource-Policy:
   same-origin`, `Referrer-Policy: no-referrer`, `Cache-Control:
   no-store`; `text/html`, `image/svg+xml` and a type with a header in it
   are sent as `application/octet-stream`, named `….bin`; a preload is
   declined (204) and htmx's POST refused (400), as on a staff page.
   (test, seen failing before the code)
7. **Decided by the handler alone.** The documented pattern's page, a
   link token of a purpose for one record handing over a stored file of
   that record (`/shared-test/ID/TOKEN/FILE-ID`): the right token and its
   record's file answer the file; a token that is no token, a token of
   another purpose for the same record, a token of another record, the
   right token with another record's file, and the right token for a
   record the module no longer lets be read each answer the handler's
   404 page, with no `Content-Disposition` and none of the
   file's bytes; a HEAD with a wrong token answers that 404 and with the
   right one 200 with the headers and no body. (test, seen failing before
   the code)
8. **Nothing else changes.** A public page that returns no download
   answers as before: its status, its headers (no `Content-Disposition`,
   the page's own `Content-Security-Policy`, `no-referrer`) and its body
   (test), and the showcase's `/quote/q1`, `/quote/x` and `/notice` answer
   byte for byte as on the base, numbered element ids aside (compared and
   written under «Verify rounds»). `/files/ID` still answers only a
   signed-in caller: after the public page's download it sends someone
   without a session to the login, and the public page sets no cookie.
   (test)
9. **Said with the pattern.** `spec/files.md` §5.5 («Who gets it»),
   `spec/ui.md` §8 («Public pages») and `docs/client-api.md` («Public
   pages») say that a public page's download is the handler's decision
   alone, what the handler must check (the token's purpose, its record,
   and that the file is that record's), and show the pattern with code.

Kept:

10. **Clients.** Every client of Tun (factory, nixploy-dashboard, ferdig,
    kurs, and the two-client repository) compiles and passes its
    `bin/test` unchanged against this tree; «Clients» below names each
    form of theirs that was losing ticks and each test that now sees a
    form save more.
11. **The build.** Core 2.47.0 (`+core-version+`, `coreVersion`), or the
    next free when main has taken it; `bin/build` warning-free, `bin/test`
    and `bin/check` green.

## Decisions

### What a page's FORM holds

- **The query's rule, the same function.** A posted form is read as the
  query already is (`query-object`): a name posted once is its text, a
  name posted more than once an array of its texts in the order posted,
  a name not posted absent. Both dispatchers call it on the post's pairs
  in place of one `setf` a pair, so the two can never differ.
- **A name given once stays a text.** A post does not say which names
  can repeat, and an always-array for some names would change what every
  existing form's single fields give. So a page that reads a name a
  browser may send several times (`checkboxes`, several `select`s of one
  name) reads it with `(query-values form NAME)`, which gives a list for
  either shape and drops empty texts; `jget` of such a name gives a text
  or an array. `query-values` is already published and documented for
  the query; its doc now says the form too. No new symbol.
- **Empty texts stay.** As in the query, a posted `""` is kept, alone or
  in an array: a page that tells «left empty» from «not posted» still
  can; `query-values` drops them.
- **Files are as before.** A name with files is the array of
  `{filename, upload}` that `add-posted-files` puts there after the text
  parts, as `files.md` §6.2 says.
- **Where else a client meets the loss.** Generated forms and record
  actions read the post's pairs (`posted-all`) and keep every value: no
  change. An htmx post reaches the same two dispatchers, so it is mended
  with them (criterion 1 posts one). `/push/…` (Tun's own script, one
  value a name) builds its JSON the old way; nothing of a client posts
  there, so it is left. `choice-find` reads one name, `tun-find`, which
  only one button of a form posts. The client forms named in «Clients»
  already read a text or an array; they were losing ticks before they
  reached the page.

### A download from a public page

- **The staff page's branch, nothing more.** `dispatch-public-page`
  answers `(values … :download DOWNLOAD)` with `send-download`, the same
  function a staff page's goes through: the same type list, name
  cleaning, headers, preload and htmx answers. Every other answer goes to
  `respond` exactly as before.
- **Who gets it is the handler's word.** A public page has no session or
  policy; the handler is the only check, as it already is for what a
  public page shows. So the docs say what it must check: the token is one
  of this purpose (a link to read a document, not one to answer it), for
  this record, the record still readable this way, and the file asked
  for is that record's. The pattern uses the kernel's `link-token`, an
  HMAC of the purpose and the record's id (the inbox module's feedback
  link is made so), compared in constant time, so a token of another
  purpose or record never matches; it takes the file from
  `(attachments-of record)`, so a file of another record is never
  reached, and answers everything else as its wrong link (404).
- **HEAD.** A HEAD reaches the handler as `:head` today; a handler that
  answers only `:get` answers it as its 404, and the pattern answers HEAD
  as GET, so a HEAD tells nothing a GET would not. Hunchentoot sends no
  body to a HEAD.
- **The pattern is a module's.** A public page that reads the store opens
  its own transaction, which only a module can (`ui.md` §8, «Public
  pages» 1); the file is read with `file-octets` under a system actor, as
  the handler, not the visitor, decides. A plain client puts such a page
  in a module of its own, as the public pages that read records already
  are.
- **`/files/ID` is untouched**, and a public download sets no cookie, so
  a link token never becomes a session.

### The rest

- **The showcase's page is out of the menu** (`:navigation nil`), so no
  page of the showcase changes its look; its entity, `visit-plan`, holds
  one record's days, set by `visit_days_set`.
- **The core version** goes to 2.47.0, or the next when the other loop in
  `src/web/` lands first: what a page's FORM holds changes.

## Tests first

Each new test and the check were run against the base's
`src/web/ui.lisp` (the dispatch as it was) before the change, and seen
failing:

- `posted-forms` (`tests/posted-form-tests.lisp`): 15 of 102 checks
  failed. Three boxes ticked gave the staff page and the public page
  `"fri"` alone, urlencoded, multipart and through htmx; repeated empty
  texts and a repeated name beside a file kept one value. None and one
  ticked, and names posted once, passed, as they should: they are what
  stays.
- `downloads` (`tests/download-tests.lisp`): the public page's made file
  and the pattern's stored file answered 500 (`values-list` of a
  download handed to the page frame), so every header and byte check
  failed; the refusals answered 404 before as after, as a wrong link
  must.
- `posted-sets.py`: at 390 px, two ticked saved `['wed']` and three
  `['fri']`; none saved none.

With the change all pass: `posted-forms` 102 checks, `downloads` 310,
and the check's 30 steps; the suites `ui-forms`, `public-title`,
`push`, `i18n`, `queries`, `communication`, `web-app`, `safety`,
`files`, `pages` and `ui`, run alone before the round, pass.

## Verify rounds

1. Green: build, test (206 s), check (703 s, every check). The round
   waited 54 minutes for the verify lock, held by other builders' rounds.
2. After gate B's first round, which asked for the four clients still
   running and for the tree they ran on (no file outside `loops/`
   changed): green, build, test (192 s), check (810 s). It waited 25
   minutes for the lock, while this loop's own client runs held it.

Byte for byte (criterion 8): the showcase previewed on the base
(`945d834a`) and on this tree side by side, `/quote/q1`, `/quote/x`,
`/notice` and `/quote/q1/extra` fetched with GET and with HEAD from each:
the bodies are identical byte for byte (numbered element ids too), and
the headers are the same but for `Date`, `Server-Timing` and
`X-Tun-Request-Id`, which differ on every request.

## Pictures

`tun loop show --path /visit-days --actor employee:anna`, in
`.build/loop/posted-sets/show/`: the page at 390 and 1280 px with
nothing saved (the scenario saves no days), looked at. Taken from the
same preview after saving Monday and Wednesday, at 390 and 1280 px,
light and dark, in `~/coding/tun-wt/posted-sets-shots/after/`
(`visit-days-two-saved-*.png`): both boxes ticked and «Saved: Monday,
Wednesday.» under the button; the menu has no «Visit days», as the page
is out of it. No other page of the showcase changed; the change to
public pages shows on no page.

## Clients

Each client's `bin/test`, from a clone in a scratch folder
(`~/coding/tun-wt/posted-sets-clients/src/`: tunworks at `ee844de`, kurs
at `c2579ae`, the two-client repository at `b14a910`), its Tun inputs
(`tun`, and `dashboard` and `customers` at their `modules/`
directories) overridden with this worktree's commit `89c92632`, under
the machine's verify lock, unchanged. That commit's tree is the tree
verified and shown (`5d9f216c`, in rounds 1 and 2) apart from `loops/`:
`git ls-tree -r` of the two differs only there, and no file outside
`loops/` has changed since.

- factory: 1093 checks; nixploy-dashboard: 1421; ferdig: 812; kurs: 352;
  the two-client repository: its first client's suites (9554, 219,
  65108, 390, 539, 373, 8856, 255, 127042, 91150, 16264 and 27996
  checks) and its second client's (145). Every one exit 0, no failure,
  no compiler warning. The factory's run waited 59 minutes for the lock;
  the other four ran one after another under one hold of it, taken after
  78 minutes.

Forms of the clients that were losing ticks, found by reading them: the
two-client repository's agenda event form (`ui:checkboxes` «For», name
`people`) and its work order form (`ui:checkboxes` «People», name
`assignees`). Each already reads a text or an array (`form-list`,
`form-assignees`), so each now saves every box ticked, with no change of
its own. No client test sees a form save more than before: the tests
that post those forms post one person (`clients/…/tests/skills.lisp`,
`modules/agenda/tests/tests.lisp`), and the others call the operations
with arrays. The client's work-arounds for this fault, one box a name
(the work order's lines, `line-N`; the outbox's files, `attachment-N`)
and ferdig's projects (one box each, by its own comment for this
reason), keep working; each may go back to `ui:checkboxes` and
`query-values` when it takes 2.47.0. factory, kurs and
nixploy-dashboard have no `ui:checkboxes` in a posted form.

## Log

- 2026-11-17 03:39  started, reviewed
- 2026-11-17 03:40  estimated 2h 3h30m 7h at brief, like tun/erase-audit-download tun/workflow-planner tun/several-clients
- 2026-11-17 03:51  gate A asked of a reviewer
- 2026-11-17 03:53  gate A: approve (reviewer)
  I approve the spec at gate A: the criteria cover both requests and the orchestrator's additions, each can be decided by a test or a check, and the spec text agrees with them.
  
  **What's right**
  
  - **Brief to criteria.**
    - **Repeated names:** criteria 1–3 cover a staff page and a public page; the urlencoded, multipart and htmx posts; none, one and three ticked; and names posted once (empty texts and files included) staying as today.
    - **Showcase:** criterion 4 adds the form, kept out of the menu so no page changes its look, with its browser check at both widths, with and without JavaScript.
    - **Docs:** criterion 5 covers `spec/ui.md`, `docs/client-api.md`, `reference/pitfalls.md` and the doc of `ui:checkboxes`.
    - **Public download:** criteria 6–9 cover the same types and headers as §5.5, refusal of a type not allowed, and every wrong-token case for GET and HEAD. A page without a download must answer byte for byte as before on `/quote/q1`, `/quote/x` and `/notice`. `/files/ID` is untouched and no cookie is set. The pattern is written out with what the handler must check.
    - **Clients:** criterion 10 names the client forms and tests that change.
    - Nothing was added beyond the brief.
  - **Decisions belong to the builder.** "A name given once stays a text" is what the orchestrator asked for ("a name given once stays what handlers get today"). Using `query-object` and `query-values` again means no new symbol. The places checked for the same loss (`posted-all`, htmx, `/push/…`, `choice-find`) answer the brief's "look for other places". Nothing here needed asking.
  - **Claims checked against the tree:**
    - Criterion 2's "a multipart post to a public page is refused before it": `upload-admission` returns `:no-session` when there is no actor (`src/web/files.lisp:27`).
    - `send-download` gives the 204 for a preload and the 400 for htmx's POST (`src/web/files.lisp:246-255`). So the public branch gets criterion 6 without new code.
    - `attachments-of` reads again as `*actor*`, so taking the file from the record's own attachments is a real check.
    - `link-token` and `constant-time-string=` are exported from `tun.core` (`src/core/package.lisp:211`), so a client's own module may use them (`spec/testing.md` test 10).
  - **The spec says the same as the criteria.** `spec/ui.md` §8 «A client's pages» 2, «Public pages» 1 and «Public pages» 6, and the new «From a public page» part of `spec/files.md` §5.5, match criteria 1–3 and 6–9. That includes `:head` now being listed as a METHOD, which it already was in practice.
  
  **Small points for gate B (none blocks this gate)**
  
  - `reference/pitfalls.md:20` says "Until core 2.47.0", but criterion 11 allows "the next free" version. Make it match the version that actually ships.
  - In `docs/client-api.md:847`, the pattern is headed "In a module:", but its symbols (`with-transaction`, `link-token`, `constant-time-string=`) aren't in the `TUN` package. Saying "in a client's own module" would stop a client from pasting it into their main package.
  - An htmx GET of a public download gets `HX-Redirect`, as on a staff page. No criterion mentions it; that's fine, since criterion 6 says "as on a staff page".
- 2026-11-17 05:11  verify 1: passed build, test, check
- 2026-11-17 05:12  shown (/visit-days)
- 2026-11-17 07:27  gate B asked of a reviewer
- 2026-11-17 07:28  gate B: changes (reviewer)
  I'm requesting changes. The code, tests, docs and verify round all hold up, but criterion 10 (every client passes) hasn't been checked yet for four of the five clients.
  
  **What's right**
  
  - **The fix is small and local.** `posted-form` (`src/web/ui.lisp:171`) sends the posted pairs through the same `query-object` the query already uses, and both dispatchers call it. So staff and public pages can't read a form differently. Files still arrive as before: they come from `tun.http:*posted-files*`, not from `post-parameters*`, so `add-posted-files` still puts its array over them.
  - **The public download is one branch.** `src/web/ui.lisp:499` sends it through the same `send-download` a staff page uses. Every other answer goes to `respond` unchanged.
  - **Criteria 1–3 have tests.** `tests/posted-form-tests.lisp` renders a real `ui:checkboxes`, reads back what a browser would post, and posts none, one and three ticked:
    - to a staff page urlencoded, multipart and through htmx;
    - to a public page urlencoded and through htmx.
  
    Names posted once, empty texts and the array of files are covered too. The record says 15 of its checks failed against the base dispatch, which fits.
  - **Criteria 6–8 have tests.** `tests/download-tests.lisp` covers:
    - the made file: exact bytes, every §5.5 header, the three types sent as octets, the 204 preload and the 400 for htmx;
    - every wrong-link case, for both GET and HEAD, plus a post, and HEAD with the right link;
    - a record the module no longer hands out;
    - `/files/ID` still sending to the login, with no `Set-Cookie`;
    - a page with no download answering as before.
  
    The byte-for-byte comparison of `/quote/q1`, `/quote/x` and `/notice` is written down under «Verify rounds».
  - **Criterion 4 passes.** `checks/posted-sets.json` passed all 30 steps at 390 px with and without JavaScript and at 1280 px, ticking two, three, none and two again. The page is out of the menu: the desktop screenshot's menu has no «Visit days».
  - **Criteria 5 and 9 are met.** `spec/ui.md` §8, `spec/files.md` §5.5, `docs/client-api.md`, `reference/pitfalls.md` and the doc of `ui:checkboxes` all state the rule. They give the pattern with what the handler must check.
  - **Both gate A points were taken up.** The client-api pattern now says it goes in a client's own module, and the pitfalls note's "Until core 2.47.0" matches the version shipped.
  - **`verify.txt` is all green:** build, test and check.
  - **Nothing left over** that I could see: no debugging, no dead code. The one `cond` with a fallback in `visits.lisp:138` has a comment saying why.
  
  **To change**
  
  1. **Criterion 10 is unmet for four clients** (`loop.md:292-296`). Only the factory's `bin/test` has a result. nixploy-dashboard, ferdig, kurs and the two-client repository are still "queued".
     - The two-client repository is the one this change affects most. Its agenda event form (`people`) and its work order form (`assignees`) are the two forms the record says will now save more. Whether any of its tests sees a different saved value is what the brief asked to have named.
     - Run all four against the shown tree. Record each result under «Clients», and name any test that now sees a form save more.
  2. **Say which tree the client run used.** «Clients» says it used commit `89c92632`, while `verified:` and `shown:` read `5d9f216c`. If `5d9f216c` is the tree of `89c92632`, add a line saying so. Otherwise run the clients again on the shown tree.
  
  **Minor, no change needed:** the packet's screenshots show only the empty state at both widths. The two-saved pictures are outside the packet, but the browser check covers that state at both widths.
- 2026-11-17 08:10  verify 2: passed build, test, check
- 2026-11-17 08:11  shown (/visit-days)
- 2026-11-17 08:11  gate B asked of a reviewer
- 2026-11-17 08:12  gate B: approve (reviewer)
  I approve gate B. The two things the first gate-B review asked for are now in the record, and the change itself holds up.
  
  **What's right**
  
  - **The earlier changes were made.**
    - **All five clients ran.** «Clients» (`loop.md:285-318`) now gives results for all five: factory, nixploy-dashboard, ferdig, kurs and the two-client repository with both its clients. Each exited 0 with no compiler warning.
    - **The forms that were losing ticks are named:** the agenda event form (`people`) and the work order form (`assignees`). The record says no client test sees a form save more, and gives the reason: their tests post one person.
    - **The tree is stated.** `loop.md:292-295` says commit `89c92632` has the same tree as `5d9f216c` (verified and shown), apart from `loops/`. I could only read files here, so I couldn't run `git ls-tree` to confirm that. Gate C should compare the trees anyway.
  - **The fix is small and in the dispatch.** `posted-form` (`src/web/ui.lisp:171`) sends the posted pairs through the same `query-object` the query already uses, and both dispatchers call it, so a staff page and a public page can't read a form differently.
    - Files still end up as their array: on a staff page, `add-posted-files` runs after `posted-form` and puts the array over them.
    - The public download is one branch (`ui.lisp:499`) through `send-download`. Every other answer goes to `respond` exactly as before.
  - **Each criterion has a test or check that fails without the change.**
    - **Criteria 1–3:** `tests/posted-form-tests.lisp` renders a real `ui:checkboxes`, takes the fields a browser would post, and posts none, one and three ticked. It does this to a staff page urlencoded, as multipart and through htmx, and to a public page urlencoded and through htmx. Names posted once, empty texts and a file's array are covered too.
    - **Criteria 6–8:** `tests/download-tests.lisp` covers:
      - exact bytes and every §5.5 header;
      - `text/html`, SVG and a type with a header injected sent as `.bin` octets;
      - the 204 for a preload and the 400 for htmx's POST;
      - eight wrong-link cases, each by GET and by HEAD, plus a POST and a record the module no longer hands out;
      - HEAD with the right link;
      - `/files/ID` still sending someone without a session to the login, with no `Set-Cookie`;
      - a page without a download answering as before.
  
      The byte-for-byte comparison of `/quote/q1`, `/quote/x` and `/notice` is written down under «Verify rounds».
    - The record says 15 of the 102 form checks, and the public downloads (which answered 500), failed against the base dispatch. That fits the code.
  - **Criterion 4 passes.** `checks/posted-sets.json` passed all 30 steps at 390 px with and without JavaScript, and at 1280 px. No other check in `checks/` failed. Both screenshots show the page laid out cleanly, and the desktop menu has no «Visit days».
  - **Criteria 5 and 9 are met.** `spec/ui.md` §8, `spec/files.md` §5.5 «From a public page», `docs/client-api.md`, `reference/pitfalls.md` and the doc of `ui:checkboxes` all state the rule and show the link-token pattern. The pattern lists what the handler must check: the token's purpose, its record, that the record is still readable this way, and that the file is that record's.
  - **The code is clean.** I found no debugging, no dead code and no unexplained special case. The one fallback `cond` (`checks/showcase/visits.lisp:137`) has a comment saying why.
  - **The build is green.** `verify.txt` round 2 passed build, test and check, and the version is 2.47.0 in both `+core-version+` and `flake.nix`.
  
  **Minor, no change needed:** the screenshots in the packet show only the state with nothing saved. The browser check covers two, three and none saved at both widths.
