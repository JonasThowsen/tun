# A client names the title a customer sees on public pages

- loop: public-page-title
- mode: reviewed
- stage: ship
- base: 8800b66573c7063111438d48f69ba1376899a06a
- item: sak_w2vc686s0zc4fx3d
- estimate: 40m 1h15m 2h30m
- like: tun/home-page tun/loading-sign
- tags: kind:ui core module:web
- verified: f090143941845f8a134309a5914afea604d0f318
- shown: f090143941845f8a134309a5914afea604d0f318

## Brief

Ferdig sak_w2vc686s0zc4fx3d, brought by the factory's orchestrator on
2026-11-11 from Tun ERP's builder:

> A page registered with `register-public-page` (a page a customer opens
> without signing in: a quote, an invoice, a pay page, an inquiry form) is
> framed by Tun's public shell, whose header shows `application-title`:
> the application's one name and its first letter as the logo. A client
> like Tun ERP serves many companies' customers, who must see the
> COMPANY's name there («Lindenhof Services»), not the application's
> («erp»). Today a client can only override `application-title`, which
> also feeds the staff header, the PWA name, sign-in and invitation
> texts, push notices and error alerts, so that is not usable. Wanted: a
> client or module decides the title (and so the logo letter, and the
> document title's suffix if the shell writes one) of public pages, per
> request, without touching what staff see.

Two shapes were suggested: a `:title` function given to
`register-public-page`, or a generic function `(public-page-title
APPLICATION)` defaulting to `application-title` that a module answers
for all its client's public pages. Whatever is chosen: the default is
today's behaviour exactly (existing clients and the UI specimen
unchanged); the text is escaped; an empty or NIL answer falls back to
`application-title`; a function that signals does not break the page
(fall back, and write the error to the server's error output); it
applies to every public page, the shell's own error and «link expired»
pages included; it does not leak across tenants. Spec, the export in
`TUN`, tests, the showcase (a public page whose title comes from a
function, and one without), a browser check at 390 and 1280 px. Mode:
reviewed. A core change, additive.

## Criteria

1. Without a `public-page-title` method of the client's or its
   modules', a public page shows exactly what it showed before: the
   shell's title is `application-title`, the mark its first letter, and
   the document's `<title>` «HEADING – application-title»; the specimen
   (`/ui`), which has no frame of the application's, is unchanged.
   (`tests/public-title-tests.lisp`, with a plain application and a
   public page of the tests')
2. `public-page-title` is a generic function in `TUN` of (APPLICATION
   PREFIX), PREFIX the public page's registered prefix (`"offer"`), with
   a docstring and registered for `introspect_extensions`; Tun's method,
   the least specific, answers `(application-title APPLICATION)`. A
   module's method on its mixin answers for its client's public pages; a
   client's method on its application class or a feature wins over the
   module's and reaches it with `call-next-method`. A method runs in a
   read transaction, the tenant's application bound and `*actor*` the
   request's (NIL for a customer), so a method that calls `select` or
   `setting-value-at-use` works. (`tests/public-title-tests.lisp`)
3. An answer «Lindenhof Services» is the shell's title (linking to the
   page as before), «L» its mark, and the document's `<title>` is
   «HEADING – Lindenhof Services»; surrounding whitespace is trimmed. An
   answer holding `<`, `&` and `"` is escaped in the title, the mark and
   `<title>`, and no element of its own appears.
   (`tests/public-title-tests.lisp`)
4. NIL, `""` or an answer of whitespace only gives `application-title`,
   with nothing written to the error output. A non-string answer (`42`)
   or a method that signals an error gives `application-title`, the page
   answers with its own status and body as without the method, and a
   line naming the prefix and the error is written to the server's error
   output. (`tests/public-title-tests.lisp`)
5. It applies to every answer of a public page: a 200, the page's own
   404 or 410 (a «link expired» page, as the orders module's offer
   answers), and the shell's 422 for an operation error the page does not
   catch. (`tests/public-title-tests.lisp`)
6. What staff see is unchanged by an answer: a staff page's shell title
   and `<title>` suffix, `/login`, and the web app manifest's `name`
   stay `application-title`. (`tests/public-title-tests.lisp`)
7. It does not leak across tenants and is not cached: two applications
   served at once, each with its own store, whose method answers from
   the store, show each its own answer on requests that alternate
   between them; a change to the store shows on the next request.
   (`tests/public-title-tests.lisp`)
8. `register-public-page` is exported in `TUN` too, so a client (the
   showcase) registers a public page through the public interface; its
   contract is in `spec/ui.md` §8 «Public pages» and
   `docs/client-api.md`. (`tests/public-title-tests.lisp`, the
   showcase's build through the interface check)
9. In the browser, in the showcase, whose method answers the setting
   `showcase.company_name` («Lindenhof Services») for its public page
   `/quote/…` and passes on for `/notice`: at 390 and 1280 px `/quote/q1`
   shows «Lindenhof Services» as the shell's title, «L» as the mark and
   in the tab's title, `/notice` shows the application's title, a staff
   page signed in shows the application's title, and nothing scrolls
   sideways at 390 px. (`checks/showcase/checks/public-page-title.py`)
10. `spec/ui.md` §8 «Public pages» and §10, and `docs/client-api.md`
   («Public pages», with a module's example) say this; the core version
   is the next free minor on main when pushed, 2.23.0 now, in
   `src/core/module.lisp` and `flake.nix`.

## Decisions

- **A generic function of (APPLICATION PREFIX), not a `:title` on
  `register-public-page`.** The public pages a customer of Tun ERP opens
  are mostly the modules': the orders module's offer, the inbox's
  feedback form, the customers module's unsubscribe page. A `:title` on
  each registration would make every module that registers a page know
  about a company's name, and a client could not change them. One seam
  answers for all of them, in the style of `home-path` and
  `staff-page-extras`: a module's mixin (Tun ERP's `company` module)
  answers once, a client's class wins over it. PREFIX lets a method
  answer for some pages only (the showcase's quote, not its notice),
  as `home-path`'s ACTOR does for some people; a method that does not
  care ignores it.
- **The default is `application-title` itself**, called through Tun's
  method, so a client that overrides `application-title` keeps today's
  public pages.
- **Asked once per answer, in the shell.** `dispatch-public-page` asks
  after the page's handler has answered, in a read transaction of its
  own (the handler opens its own transactions; there is no page
  transaction to share), with the request's application bound by
  `with-application`. Nothing is cached, so nothing can carry from one
  tenant or one request to the next.
- **Fallbacks.** NIL and blank text are «no answer» and fall back
  silently. A non-string answer or an error is a mistake in the client
  or a module: it falls back and is written to the error output, as
  `home-path`'s refusals are, and the customer's page is never broken by
  it. Only `error` is caught; a stack exhaustion goes to the request's
  500 as anywhere else.
- **Only the public shell.** The title goes to `page-frame` and
  `page-document` as a key of `respond`, used only by
  `dispatch-public-page`; the staff frame, `/login`, `/setup`, the
  manifest and every text that names the application keep
  `application-title`.
- **`register-public-page` in `TUN`.** The showcase, a client, needs a
  public page to show both cases, and a client such as Tun ERP may well
  register one of its own; today only modules can (through `TUN.WEB`).
  The fourth argument, a session the orders module keeps for an offer,
  is documented as one a client ignores.
- **A module mixin is in every application's class precedence once the
  module is loaded**, enabled or not (as `home-path` found). A module
  that answers should do so for applications that enable it; in a
  client's build only its pinned modules are loaded, so this matters
  only in Tun's own test image, where the tests' methods are guarded.
- **The showcase** declares a setting `showcase.company_name`
  (default «Lindenhof Services»), read with `setting-value-at-use` in
  its method, as a tenant's company name would be.
- **Core version** 2.23.0, the next free minor; additive.

## Log

- 2026-11-11 15:02  started, reviewed
- 2026-11-11 15:04  estimated 40m 1h15m 2h30m at brief, like tun/home-page tun/loading-sign
- 2026-11-11 15:04  gate A asked of a reviewer
- 2026-11-11 15:05  gate A: approve (reviewer)
  I'd approve this. Every part of the brief has a criterion that a test could decide, the spec change says the same as the criteria, and none of the decisions should have gone back to the asker.
  
  **The brief is fully covered:**
  - **Default unchanged** (title, mark, `<title>`, the `/ui` specimen): criterion 1.
  - **Title, mark and `<title>` suffix are set together:** criterion 3.
  - **Escaping:** criterion 3, which also requires that no extra element appears.
  - **Empty or NIL falls back:** criterion 4. It also treats whitespace-only answers as empty.
  - **A method that signals falls back and logs to the server's error output:** criterion 4. It treats a non-string answer the same way, and requires the page's status and body to stay as they would be without the method.
  - **Every public page:** criterion 5 covers the 200, the page's own 404 and 410, and the shell's 422. In the code (`src/web/ui.lisp:275-296`), those are the only answers the public shell frames. The «link expired» page is the offer's 410 in `modules/orders/public-offers.lisp:16`. So "every answer of a public page" really is all of them.
  - **No leak across tenants:** criterion 7, with two applications served at once, alternating requests and a store change.
  - **Staff see no change:** criterion 6 (staff shell, `/login`, the manifest).
  - **The export in `TUN`, the spec, the tests, the showcase with and without a title method, and a browser check at 390 and 1280 px:** criteria 2, 8, 9 and 10.
  
  **The criteria stay within the brief.** The only addition is exporting `register-public-page` (criterion 8). The showcase needs it: it is built only on `TUN`'s public interface (`checks/showcase/package.lisp`) and could not otherwise register the public page the brief asks for. It is additive and listed under Decisions.
  
  **Each criterion can be decided.** Each one names its test file or browser check and gives concrete, observable results: the strings, «L» as the mark, the status codes, an error-output line naming the prefix, and nothing scrolling sideways at 390 px.
  
  **The spec matches the criteria.** `spec/ui.md` §8 «Public pages» items 1–5 match criteria 1–6. The §10 entries list the new test file and the browser check. `docs/client-api.md` has both examples (a client's page and a module's method), and its `define-setting` form matches the existing examples there. What the spec says about the current code is accurate: the method takes 4 arguments, no transaction is open around the handler, the 422 for an uncaught operation error, duplicate prefixes are refused, and the title links to `/PREFIX/ID`.
  
  **The Decisions are the builder's to make.** The brief offered two shapes and left the choice open ("whatever is chosen"). Choosing the generic function, with PREFIX as an argument, follows how `home-path` already works and is explained. Asking for the title after the handler, in a read transaction of its own with nothing cached, is an implementation detail that criterion 7 tests.
  
  **Minor, no change needed:**
  - Exporting `register-public-page` makes its fourth `session` argument part of the public contract, though only the offer page uses it. The spec and docs say a client ignores it, which is enough for now.
  - The spec doesn't mention the `introspect_extensions` registration from criterion 2. `docs/client-api.md:197` already covers it for every published seam.
- 2026-11-11 15:18  verify 1: passed build, test, check
- 2026-11-11 15:18  shown (/quote/q1, /notice)
- 2026-11-11 15:18  gate B asked of a reviewer
- 2026-11-11 15:19  gate B: approve (reviewer)
  I approve this change. Every criterion has a test or check that would fail without it, the screenshots show it at both widths, and all three verify steps passed.
  
  **The criteria**
  - **1, today's behaviour without a method:** the default test expects `("erp" "e" "Quote – erp")` and that the title links to the page itself. Tun's own method answers `application-title`. The `/ui` specimen is served before public pages are dispatched (`src/web/ui.lisp:1854`), so it can't be affected.
  - **2, the generic function:** `public-page-title` has a docstring, is registered with `register-extension-protocol` and is exported through `src/public.lisp`, and a test checks all of this.
    - A client's method wins over a module's, and `call-next-method` reaches the module's answer (the `:wrap` case is tested).
    - The method runs inside the request's `with-application` and `*actor*` binding (`ui.lisp:1829-1832`), with a read transaction of its own, so `select` works. The `:read` test proves this.
  - **3, trimming and escaping:** the test sends `  <b>Berg & "Sønn"</b>  `. It expects escaped text in the title, the mark and `<title>`, and no `<b>` anywhere in the page.
  - **4, fallbacks:** NIL, `""` and whitespace-only answers fall back with nothing written to the error output. `42` and a method that signals both fall back, write a line naming the prefix and the error, and the page still answers 200 with its body. Only `error` is caught, as the Decisions say.
  - **5, every answer of a public page:** the 410, 404 and 422 (an operation error the page doesn't catch) are each tested over HTTP with the title, mark and `<title>`.
  - **6, staff unchanged:** a staff page, `/login` and the manifest's `name` are tested with a module answer active. In the code, `site-title` is passed only from `dispatch-public-page` (`ui.lisp:297-298`), and public pages are always `:guest t`, so the staff frame never sees it.
  - **7, no leak across tenants:** two servers run at once with alternating requests, and a store change shows on the next request. Nothing is cached.
  - **8, `register-public-page` exported:** it's exported, tested and documented. The showcase uses it through `TUN`.
  - **9, the browser check:** `checks/public-page-title.json` passed all 12 results at 390 and 1280 px, including the quote opened while signed in. The screenshots show «L / Lindenhof Services» on `/quote/q1` and «s / showcase» on `/notice` at both widths, with nothing scrolling sideways.
  - **10, spec, docs and version:** `spec/ui.md` §8 «Public pages» and its §10 test entries, plus `docs/client-api.md` «Public pages» with a module example, match the code. The version is 2.23.0 in both `src/core/module.lisp` and `flake.nix`.
  
  **The brief:** a module's method gives every public page of its client the company's name, and a client can narrow that by prefix. Staff pages and texts are untouched. A bad answer falls back to the application's title and never breaks the customer's page.
  
  **The code:** it's small and readable. `public-title` is one well-documented function, and the new `site-title` key on `respond`, `page-frame` and `page-document` is optional and documented. There's no leftover debugging or dead code. The showcase's Norwegian (`nb`) translations cover the new texts.
  
  **Not blocking:** the test's guarded method on `customers-module` depends on the global `*module-title*` being unset in other suites. It defaults to NIL and is only set with `with-global` or `let`, so that's fine.
