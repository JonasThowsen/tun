# Few browser checks: page tests over HTTP, one generated width sweep, and browser checks only for what a browser alone decides

- loop: few-browser-checks
- mode: reviewed
- stage: verified
- base: e89b3f8ba4d02fd591e64de8c7f32dbdd2b9f17c
- item: sak_z4ggf27qjx57443v
- estimate: 3h 5h 9h
- like: tun/fast-checks tun/posted-sets
- tags: kind:tooling core
- verified: 1247327db00671792b327419ef28a4a95a9440b3

## Brief

Item sak_z4ggf27qjx57443v («few-browser-checks: page tests over HTTP, one
generated width sweep, and browser checks only for what a browser alone
decides»), made by the factory's orchestrator on 2026-11-18 after loop
`fast-checks`, whose proposal (b) the orchestrator decided be built.

The owner, 2026-11-17 (in `loops/fast-checks.md`): «we have to minimize or
basically almost remove the browser checks. 30 minutes is unacceptable …
one of the reasons we want to use Common Lisp is fast iteration.» The
measurements are in `loops/fast-checks.md`, «Measured»: of a client's
1155 browser-check assertions, 77 % are decided by the server's answer to
a GET or a POST and 5 % by asking for a fragment; 205 are the same «the
page does not scroll sideways» after each step; about 71 truly need a
browser (a chooser, popovers and sheets, finger-sized controls, what is on
the first screen, tables on a phone, the search dialog, the date picker,
files, scroll kept after a tap).

The orchestrator's brief, in short:

> 1. **Page tests over HTTP.** A small, documented reader, on top of
>    `with-test-server` and `web-request`, that a client's suite uses to
>    assert what a browser check asserted from the server's answer: a
>    page's parts by `data-part`, its headings and texts, its forms
>    (action, method, fields with their values and their refusal
>    messages), links, the status and the redirect, a fragment's answer to
>    an htmx request, in a given language and for a given actor, against a
>    scenario. Fast: no browser, no new server per test. Say in
>    `docs/client-api.md` how a check's step becomes a test, with an
>    example converted from a real showcase check.
> 2. **One generated browser check per client**: every page the page
>    sweep (`generated-every-page-answers-every-role`) reaches, per role,
>    at 390 and 1280 px, fails on sideways scroll, a console error, or a
>    policy violation, with a picture per page in the results. It joins
>    the parallel check runner that 2.50.0 made ready for a generated
>    check. Its time on the client with 102 checks is in the record.
> 3. **The rule**, in `docs/loop.md` («Criteria a browser shows become
>    browser checks» and wherever a check is required), `spec/preview.md`,
>    and `reference/`: a browser check only for what a browser alone
>    decides (script behaviour, touch, layout at a width, what is on the
>    first screen); everything the server's answer decides is a test in
>    the suite; one language suffices for a browser check when the other
>    language changes only text.
> 4. **The showcase's own checks** converted by that rule: the ones the
>    fast-checks record says could be HTTP tests (about 10) become tests;
>    the rest stay. Before and after: count and minutes of Tun's check step.
> 5. Note for the factory's playbook (step 7 of `building`): the sentence
>    the playbook should say instead, in the report.
>
> Every client passes unchanged on this tree with `bin/tun clients test`
> under one hold of the lock (their checks stay as they are; converting a
> client's checks is that client's own loop).

## Criteria

1. **A server for page tests.** `tun-test-support` has a package
   `tun.page-test`, used through a local nickname (`page`), whose
   `with-server` runs its body against an application of CLASS holding
   the records of SCENARIO, in memory or on the test Postgres server,
   served over HTTP by a server in the test's own process that takes
   claimed identity, with an actor for the body's requests and the
   tenant's language when given. The scenario is made once in a process
   for each class, scenario and database and copied for each `with-server`
   (a memory store's copy, or a Postgres template's), unless making it
   changed a global variable (`spec/preview.md` §4's comparison), when it
   is made again for each. No browser and no process is started. (test)
2. **Requests as a browser sends them.** `page:visit` GETs a path,
   `page:post` posts fields (a name given several values posts it once
   for each, multipart when asked), `page:submit` posts or gets a form of
   an answer as a browser sends it untouched (`testing.md` §5's rule:
   each named input, a checkbox or radio only when checked, each select's
   selected option, each text area, the button pressed or else the first
   named submit button, a file input empty), with the fields a test gives
   in place of the page's: the form a selector names, else the one the
   button pressed belongs to, else the first in the page's `<main>`, so
   never the frame's «Sign out» by mistake; and `page:follow` GETs where
   an answer redirects. Each takes the server's actor or another (none with NIL),
   `X-Tun-Actor` as the actor's claimed identity, keeps each actor's
   cookies, never follows a redirect itself, and sends htmx's headers
   when asked (`:htmx :partial` or `:full`, and `:target` as
   `HX-Target`), and further headers (`:headers`). (test)
3. **What an answer says.** Its status, where it redirects (the path of
   `Location`, or of `HX-Redirect` or `HX-Location`), any header, its
   content type, its body (text, or octets for anything else) and its
   JSON. (test)
4. **What a page shows.** Read from the answer's HTML, a page's or a
   fragment's: the elements a selector names (a type, `#id`, `.class`,
   `[attr]`, `[attr=value]` and `~=`, `^=`, `$=`, `*=`, joined by a space
   or `>`, several by `,`; anything else is refused, naming the
   selector); a part by its `data-part`; an element's text as a person
   reads it (white space collapsed; scripts, styles, templates and
   elements marked `hidden` left out), its attributes and its tag; the
   page's title, its headings, its links (text and `href`) and its alerts
   (`.tun-alert` and `role="alert"`). (test)
5. **What a form holds.** Each form of an answer, and the one
   `page:form` takes without a selector, as `page:submit` does (the first
   in the page's `<main>`, else the first): its action, its method,
   whether it posts multipart, its fields as a browser would send them
   untouched, each field's value or values, and each refused field's
   message (a control marked `aria-invalid="true"`, its message the
   element of its `aria-describedby` that is a field's error). (test)
6. **In a language.** `with-server`'s `:language` sets the tenant's
   language before the body runs; the showcase's page tests read a page
   in English and in Norwegian. (test)
7. **Fast.** A `with-server` on a scenario made before in the process
   costs tens of milliseconds, its requests a few each; the showcase's
   page tests run in seconds. Measured in the Log. (test, Log)
8. **One generated browser check.** `tun check` runs, besides the files
   of `checks/`, `generated-every-page-at-both-widths` from the default
   scenario, first: its server lists, before it serves, every page the
   page sweep (`testing.md` §5) gets a page for by a GET (status 200,
   `text/html`: the listed pages, the home path and the links it follows,
   not the fragments it asks for with htmx's headers nor the forms it
   posts), for each of the sweep's actors (the scenario's, the fuzz roles
   none of them has, and no one); the check opens each at 390×844 with
   touch and at 1280×800, signed in as that actor, and fails a page that
   answers 400 or more, scrolls sideways, has a JavaScript error or an
   error in its console, or a Content-Security-Policy violation. Each
   page and width is one result with a picture of the screen in the
   results. `tun check NAME` runs it by its name; `TUN_CHECK_IMAGE=0`
   runs the files only. (test, check run)
9. **Its time.** The generated check's time and what it visits, on the
   showcase and on the client with 102 checks, are in the Log; a failure
   it finds there is named, not mended in the client. (Log)
10. **The rule.** `docs/loop.md` (§2, where criteria become checks or
    tests, and §4), `spec/preview.md` §4, `spec/testing.md` §6 and
    `reference/style.md` («Tests») each say all four: a browser check
    only for what a browser alone decides (script behaviour, touch,
    layout at a width, what is on the first screen); everything the
    server's answer decides is a test in the suite; one language
    suffices for a browser check when the other changes only text; the
    generated check covers «the page does not scroll sideways» on every
    page it reaches. `reference/pitfalls.md` («Tests») gives the
    measurement behind it, and `docs/client-api.md` says how a check's
    step becomes a test, with an example converted from a showcase
    check. (review)
11. **The showcase by the rule.** The showcase's checks that the server
    decides become page tests in its suite, which `bin/test` now runs
    (the showcase a client system of the run); checks of which only part
    is the server's keep the browser's part. Before and after: the number
    of checks and the minutes of the check step, in the Log. (test, Log)
12. **Clients unchanged.** Every client passes its own `bin/test`
    unchanged on this tree, by `bin/tun clients test` under one hold of
    the lock; nothing new is exported from `tun.test-support`, so no
    client's names can clash. (Log)
13. **The playbook's sentence.** The record's Decisions and the final
    report give the sentence the factory's playbook (`building`, step 7,
    «browser checks in `checks/` at 390 px and 1280 px») should say
    instead, for the orchestrator to put there; this loop changes nothing
    in the factory. (review)
14. **Core 2.51.0** (`+core-version+`, `coreVersion`), or the next free;
    `bin/build` warning-free, `bin/test` and `bin/check` green. (verify)

## Decisions

- **A package of its own, `tun.page-test`, used by a nickname.** The
  reader's natural names (`status`, `text`, `form`, `links`) are the names
  clients' tests already give their own helpers: the clients' test
  packages define `page-body`, `page-path`, `html-text`, `page-answer`,
  `form-text` and more, and they `:use` `tun.test-support`, so a new
  export there of such a name would collide with a client's function
  (a redefinition, which fails its strict compile) now or later. A
  package that no client `:use`s cannot collide: a test writes
  `(page:visit "/items")` after `(:local-nicknames (#:page
  #:tun.page-test))` in its `defpackage`. Its names avoid `CL`'s, so no
  shadowing. It reaches Tun only through `tun.test-support`'s, `TUN`'s
  and the kernel's exported symbols.
- **Over HTTP, in the test's process.** The requests go to a Hunchentoot
  acceptor on a port of its own in the test's process, as
  `with-test-server` does, so a page's answer is exactly what a browser
  gets: its status, headers and redirects, its cookies, the
  dispatch of staff and public pages, htmx's headers. «No new server per
  test» is read as no server process and no browser: the acceptor is
  started for each `with-server` (milliseconds) because each test gets
  its own copy of the records, and an acceptor serves one application.
- **No HTML library.** Tun's renderer writes well-formed HTML whose
  attributes it always double-quotes and escapes (`tests/pages.lisp`
  reads them the same way), so a small reader builds the element tree:
  void elements, raw text in `script` and `style`, entities. A library
  would be a new dependency of every client's test build (Nix builds
  `tun-test-support` for them). The selector is a small subset of CSS,
  enough for what the clients' checks select (`[data-part=…]`, a tag, a
  class, an attribute, descendants); the rest is refused by name rather
  than misread.
- **The scenario's records once, copied.** As `tun check` does since
  2.50.0 and the fuzzer does in the suite: a memory store is copied
  (`copy-memory-store`), a Postgres template database copied with
  `CREATE DATABASE … TEMPLATE`. A scenario that sets a global variable
  is made again for each `with-server`, so what it set is what the
  test's server sees, as a check made per check does. In memory by
  default, as `with-test-app` is; `:database :postgres` where the
  record policies matter (`store.md` §6).
- **Actors by claimed identity.** The server takes claimed identity, as
  every test server and preview does; a request names its actor in
  `X-Tun-Actor`, as `/login?actor=…` in a check stands for. A request
  with no actor is one a person who is not signed in sends.
- **The generated check's pages come from the check's own server.** The
  sweep's paths hold record ids, which are those of the database the
  check's server runs on; so that server, given `--page-sweep FILE`,
  runs the sweep's GETs as each actor in its own process, on an acceptor
  of its own on the same application, after its scenario is in place
  and before it serves, and writes the paths each actor got a page for.
  Only GETs: posting the forms would change the records the later pages
  show. The sweep's bounds hold (two paths a shape, 150 an actor), so the
  check visits a page of each shape at most twice.
- **What the check reads on each page.** After the load, and after every
  htmx request the page began has ended (a page that loads a part with
  `hx-trigger="load"`), it reads the document's `scrollWidth` against the
  window's width, the JavaScript errors and console errors since the
  page was opened, and the violations the browser reported
  (`securitypolicyviolation`, as the policy checks record them). No
  fixed wait. The picture is the screen as a JPEG at quality 60, to keep
  a run's hundreds of pictures to megabytes; a failure's picture too.
- **First in the run.** The check is the longest of a run, so it is put
  first in the list, which the workers take in order: it runs beside the
  others rather than after them.
- **Which showcase checks are the server's.** By the rule, from the
  fast-checks record's ten: wholly the server's, so tests:
  `audited-download`, `pdf-download`, `pdf-document`,
  `login-returns-to-the-page`, `public-page-title` and
  `files-without-javascript`. Partly: `mail-preview` (the frame's
  sandbox, title, links and text are the server's; its text size and
  column width at a width are the browser's), `posted-sets` (a set
  posted without JavaScript is the server's; htmx building the post from
  ticked boxes is a script's, so one round with JavaScript stays) and
  `policy-tour` (the menu's pages are the generated check's now; the
  specimen and login, which the sweep leaves out, and a file's preview
  stay). `policy-refuses-code` stays: that the browser refuses code is
  the browser's; its header is one line of a test. «The page does not
  scroll sideways» in the converted checks is the generated check's.
- **The showcase in `bin/test`.** Its page tests are the showcase's own
  suite (`showcase/tests`), so `scripts/client-systems` lists it and
  `scripts/setup.lisp` registers its directory, as for a client under
  `clients/`.
- **From the build** (after gate A):
  - **The browser's own look for `/favicon.ico` is not a page's error.**
    The showcase's single-page screen names no icon, so Chromium asks
    for `/favicon.ico`, which answers 404, and logs «Failed to load
    resource» in the console: the generated check's first run failed
    `/sign-off` at 390 px on it. Every browser does the same for any page
    without an icon, and nothing of the page fails; the check leaves out
    a console error about `/favicon.ico` alone, and keeps every other.
    Whether Tun should answer `/favicon.ico` with the web app's icon is
    left for a later loop (report).
  - **A path is sent as it is written.** Drakma reads a URL's query and
    encodes it again, so `/login?next=%2Fitems` reached the server as
    `next=%252Fitems`, which a sign-in's return refused; the reader asks
    Drakma to send the URI as given (`:preserve-uri`). The sweep's own
    crawl (`tests/pages.lisp`, unchanged here) sends paths the old way;
    its GETs of a path whose query holds a `%` reach the server encoded
    twice (report).
  - **A file goes as a browser sends it.** A field's value that is a
    pathname is a file, named by its file name and typed by its
    extension, as a browser types it, sent multipart with its length
    (Hunchentoot refuses a chunked request, which Drakma sends for a file
    otherwise).
  - **`page:read-html`**, for HTML that is not an answer's body, such as
    a mail's preview in a frame's `srcdoc`, which the converted
    `mail-preview` reads.
  - **Which packages tell a scenario that sets a variable:** its own
    (found by asking each package for the scenario), the client's when
    `tun check` loaded it, and the class's with those named after it
    (`SHOWCASE`, `SHOWCASE.TESTS`), unless the class is Tun's own
    (`TUN.CORE:APPLICATION`): Tun's packages hold the kernel's caches,
    which any scenario changes, and Tun's isolated variables are always
    compared.
  - **The core suite's tests package uses the nickname**, as a client's
    would; the reader's tests are a child suite `page-test` of `core`,
    and its sweep is tested there too (`the-sweep-lists-each-actor-s-whole-pages`).
- **The playbook's sentence** (criterion 13), for step 7 of `building`
  in place of «browser checks in `checks/` at 390 px and 1280 px»: «page
  tests over HTTP (`tun.page-test`, Tun's `spec/testing.md` §6) for
  everything the server's answer decides: texts, parts, links, forms and
  their refusals, statuses, redirects, fragments, downloads, the other
  language; and a browser check in `checks/` only for what a browser
  alone decides (what a script does, touch, layout at 390 or 1280 px,
  what is on the first screen), in one language when the other changes
  only text, never for sideways scrolling, which Tun's generated check
  sees on every page.»
- **Estimate.** 3h / 5h / 9h, the orchestrator's, like `tun/fast-checks`
  (the runner this joins) and `tun/posted-sets` (a showcase check and a
  form's post).

## Log

- 2026-11-18 12:29  started, reviewed
- 2026-11-18 12:37  estimated 3h 5h 9h at brief, like tun/fast-checks tun/posted-sets
- 2026-11-18 12:42  gate A asked of a reviewer
- 2026-11-18 12:43  gate A: changes (reviewer)
  I'm asking for changes. The criteria and the spec change get most of the brief right, but four things need fixing before this goes on.
  
  **What is right**
  - Brief item 1 (page tests over HTTP) is covered by criteria 1–7. Each one can be decided by a test, and `spec/testing.md` §6 says the same as each.
  - Brief item 2 (the generated check) is covered by criteria 8–9. `spec/preview.md` §4, «The generated check», matches them: same actors, both widths, same failures, one picture a page, `TUN_CHECK_IMAGE=0`.
  - Brief items 3 and 4 and the clients' line are covered by criteria 10–12.
  - None of the decisions should have gone to the asker:
    - **A separate package (`tun.page-test`) used by a nickname:** the reason is sound and concrete. Clients' test packages `:use` `tun.test-support` and define names like `page-body`, so new exports there could collide.
    - **Starting a test server for each `with-server`:** the brief says «no new server per test», and the decision reads that as no server process and no browser. That is a fair reading of the asker's goal, which is speed, and criterion 7 measures it.
  
  **Changes**
  
  1. **Brief item 5 has no criterion.** The brief asks for «the sentence the playbook should say instead, in the report» (step 7 of `building`). No criterion or decision mentions it. Add one, decided at review or in the report.
  
  2. **`page:submit` picks the wrong form when only `:button` is given.** In `spec/testing.md` §6 (diff line 293), FORM defaults to «the answer's first form», and nothing says BUTTON picks a form. Staff pages render the shell's logout form (`src/web/ui/layout.lisp:975`) in the header, ahead of the content. So the example in `docs/client-api.md` (diff line 76), `(page:submit document :button "Make the PDF")`, would send the logout form or fail. Say that when BUTTON is given without FORM, the form is the one that button belongs to: inside it, or naming it with `form="ID"`, as §5 counts. Without that, the example has to pass `:form`.
  
  3. **`page:submit` cannot send `HX-Target` or extra headers.** Criterion 2 says each request «sends htmx's headers when asked (`:htmx :partial` or `:full`, and `HX-Target`)». But the spec's `page:submit` takes only `form fields button actor htmx`, with no `target` and no `headers` (diff line 293). Add them, or narrow the criterion.
  
  4. **Criterion 10 claims more than the docs say.** It says every file it names says all four points of the rule:
     - `spec/testing.md` (diff 263–268) only points to `preview.md`. It doesn't say that one language suffices, or that the generated check covers sideways scrolling.
     - `reference/style.md` (diff 157–164) doesn't mention the generated check.
  
     Because the criterion is decided at review, it would fail at gate B as written. Either add the missing points, or reword the criterion to say what each file says.
  
  **Minor (fix while there)**
  - `docs/client-api.md` (diff lines 11–13) lists the generated check's failures as sideways scrolling, a console error or a policy violation. Criterion 8 and `preview.md` also fail a page on status 400 or more and on a JavaScript error.
  - `page:links` returns «its text and its target» (criterion 4, diff line 327). «Target» can be read as the HTML `target` attribute; the docs example uses it as the `href`, so say `href`.
- 2026-11-18 12:45  gate A asked of a reviewer
- 2026-11-18 12:45  gate A: changes (reviewer)
  I'm asking for one change. The previous round's four requests and both minor points are fixed, but the default of `page:form` repeats the bug that was just fixed for `page:submit`.
  
  **What is right**
  - **The playbook sentence:** criterion 13 now covers brief item 5. The sentence itself is under Decisions and the criterion says it goes in the report. The loop changes nothing in the factory.
  - **Which form `page:submit` sends:** criterion 2 and `spec/testing.md` §6 (diff 300–311) agree. It is the form FORM names, else the one BUTTON belongs to (inside it, or by `form="ID"`), else the first form in `<main>`, else the answer's first. I confirmed that `src/web/ui/layout.lisp:975` puts the logout form in the shell ahead of `<main>` (line 1481). So the `pdf-document` example in `docs/client-api.md` (diff 77) now sends the right form.
  - **Headers:** `page:submit` takes `target` and `headers` (diff 300–301), as criterion 2 says.
  - **The rule (criterion 10):** `spec/testing.md` §6 (diff 265–272) and `reference/style.md` (diff 164–166) now say all four points, as do `docs/loop.md` §2 and `spec/preview.md` §4. `docs/loop.md` §4 points back to §2, which is enough.
  - **The minor points:** `docs/client-api.md` (diff 11–14) lists the 400-or-more and JavaScript failures, and `page:links` gives `(TEXT . HREF)`.
  - **The rest:** the criteria still cover the whole brief and nothing more, each can be decided by a test, a check run, the Log or review, and no decision belongs to the asker.
  
  **Change**
  
  1. **`page:form` with no selector reads the frame's logout form on a staff page.** `spec/testing.md` §6 (diff 341) says `page:form` is «by default the first form», and criterion 5 doesn't say which form either. On any staff page the first form is the shell's «Sign out» form (`layout.lisp:975`, before `<main>`). So the conversion table's row in `docs/client-api.md` (diff 48), `(page:form-error (page:form answer) "email")`, reads the wrong form and returns NIL. A test that asserts no refusal would then pass without checking anything. Give `page:form`'s default the same order as `page:submit`'s (the first form in `<main>`, else the answer's first form), and say so in criterion 5 and at diff 341.
- 2026-11-18 12:45  gate A asked of a reviewer
- 2026-11-18 12:46  gate A: approve (reviewer)
  I approve. The one change asked for last round is made, and nothing new turned up when I re-read the rest.
  
  **What is right**
  
  - **The previous change:** `page:form`'s default form is now fixed. Criterion 5 says `page:form` with no selector takes the form the same way `page:submit` does: the first form inside `<main>`, else the first. `spec/testing.md` §6 says the same (diff 341–343). So the table row in `docs/client-api.md` (diff 48), `(page:form-error (page:form answer) "email")`, now reads the page's own form, not the «Sign out» form above `<main>`.
  - **Brief against criteria:**
    - Items 1–5 and the "clients unchanged" line are covered by criteria 1–7, 8–9, 10, 11, 13 and 12.
    - Criterion 14, the core version and a green build and checks, is the loop's usual housekeeping, not scope creep.
    - Nothing is beyond the brief. Criterion 13 has the loop change nothing in the factory, so the playbook sentence goes to the orchestrator.
  - **Each criterion can be decided:**
    - 1–6, 8, 11: by a test or a check run.
    - 7, 9, 11, 12: by measurements in the Log.
    - 10, 13: at review, against named files and sections. All of those sections are in the diff, and each says all four points of the rule: `docs/loop.md` §2 says them and §4 points back to §2, then `spec/preview.md` §4, `spec/testing.md` §6 (diff 265–272) and `reference/style.md` (diff 158–166).
  - **The spec says the same as the criteria:**
    - **Requests:** how `page:submit` picks its form and builds the request, and which headers each request takes (`htmx`, `target`, `headers`, `X-Tun-Actor`), match criterion 2 (diff 295–316).
    - **Reading an answer:** the answer readers, the selector subset and refusal, what text leaves out, links as `(TEXT . HREF)`, and alerts match criteria 3–4 (diff 317–340).
    - **The generated check** (diff 212–238) matches criterion 8: which pages, which actors, both widths, the five failures, one JPEG per page and width, run first, run by name, and left out under `TUN_CHECK_IMAGE=0`.
  - **Decisions:** none of them is the asker's to make.
    - Reading «no new server per test» as no server process and no browser is fair to the asker's aim, which is speed, and criterion 7 measures it.
    - Which showcase checks become tests is the brief's own rule applied to the fast-checks record's ten.
    - Using GETs only for the sweep, and the JPEG quality, are technical choices with their reasons stated.
  - **The converted `pdf-document` example** (diff 72–86) is consistent with the spec. The button picks the document form, `page:follow` follows the 303, and `page:body` gives octets for the PDF.
- 2026-11-18 13:35  verify 1: passed build, test, check
