# One header per page with its actions beside the title on a phone, and the shell on the new grounds

- loop: ui-header
- mode: reviewed
- stage: ship
- base: 6d34699fad961f9a0cc9f8acbe3689c315349b82
- item: sak_79ne242sb9ep96dh
- estimate: 2h30m 4h 7h
- like: tun/ui-sheets tun/ui-look
- tags: kind:ui core module:ui
- verified: e0a4728438ad6ebb1d556b5a68845324d6de43e4
- shown: e0a4728438ad6ebb1d556b5a68845324d6de43e4

## Brief

Ferdig sak_79ne242sb9ep96dh, brought by the factory's orchestrator on
2026-11-11, the third loop of the work on Tun's component library after
`ui-look` (core 2.25.0) and `ui-sheets` (2.26.0). Jonas, 2026-11-11: he
has polished the admin UI of another application of his for two weeks and
wants the best of it carried into Tun's component library, «to make the UI
component Library of Tun superb». The source is the owner's rules for an
admin application, 2026-11; code does not carry over, rules, values,
component anatomy, behaviour and the tests that pin them do. His decisions
for Tun the same day: the option of a description under a title or a
section heading stays in Tun, but Tun's own pages stop using it (2B); Tun
keeps the device's own font.

This loop is the page's frame: `page-header`, `section`, `app-shell`,
`nav-list`, `breadcrumbs`, the record's facts, `tabs`, and the generated
screens that use them. The orchestrator's brief, in short:

1. **One header per page.** The title is the page's one `h1`; its actions
   sit beside it at the right edge, on a phone too (390, 360 and 320 px),
   never on a row of their own under the title; the filled button (the
   one next step) is last, at the right edge. When the actions do not fit
   beside the title on a phone, the secondary ones go into one «more»
   menu (the existing `dropdown-menu`, an icon-only button without a
   frame) and the filled one stays visible; a long title wraps or
   truncates beside them, the actions do not wrap. Without JavaScript the
   menu still works (the popover attributes).
2. **The shell on the new grounds.** The top bar and the menu on
   `--chrome` with the 1px `--chrome-border`, the page on `--background`;
   the current menu item without a change of weight or size; the
   installed app's theme colours (`:theme-color`, `:dark-theme-color` and
   the defaults the manifest and the meta tags carry) match the top bar's
   ground in light and dark, so the phone's status bar and the top bar
   are one surface, with a test comparing the defaults with the tokens.
3. **Section links instead of tabs for what is read together.** A new
   option or small component gives a long page a row of links to its
   sections: plain anchors to the sections' ids, working without
   JavaScript, the row scrolling sideways on a phone without wrapping,
   and where scripts run the link of the section in view marked (colour
   or underline, no weight change). `tabs` stays as it is for its
   clients, and moves to the right ground (`ui-look`'s report: «`tabs` on
   page ground» looked wrong).
4. **A record's facts by spacing**: label and value pairs set by spacing
   and the muted label colour, no lines or boxes between them, two
   columns from a width where they fit and one on a phone, the label
   above or beside the value as the owner's rules describe, the edges in
   line with the header and the sections.
5. **No description under a title in Tun's own pages** (2B): the
   `description` option of `page-header` and `section` stays and keeps
   working for clients, but every page Tun itself generates or ships
   stops passing it, and a test scans Tun's own sources for it. A
   description that carried what a person needs to act stays on the page
   in another honest form (an alert, an empty state's text), named in the
   report.
6. **From the last loop**: the flash after an account is created carries
   what the new person signs in with, so it must not leave by itself:
   `:toast nil`, with a test.
7. The specimen shows each of these, with before and after pictures at
   390 and 1280 px, light and dark, and a browser check that measures
   them.

Warnings from the owner's rules: header actions under the title on a
phone, a phone bottom tab bar and stat cards were tried there and dropped;
none is built. Not this loop: filters on lists (`ui-filters`), tables and
rows on a phone (`ui-lists`), search and date, time and money fields
(`ui-search`); `data-table`'s phone layout is not changed. The five clients
(factory, nixploy-dashboard, ferdig, kurs, tun-erp) pass `:description` and
header `:actions` today, which must keep rendering, and must compile and
pass unchanged.

Mode: reviewed. A core change, a minor version.

## Criteria

1. **The header's row.** `page-header` puts its title (the page's one
   `h1`) and its actions in one row, at every width: the actions' boxes
   and the title's box start on the same row (their tops within 1rem), the
   actions stand after the title at the right edge of the header (the
   last action's right edge equal to the header's, to 1px), and the
   actions never wrap onto a second line. A long title wraps beside them,
   and a word longer than the title's room breaks rather than pushing the
   actions out of the header.
   The filled actions (a `button` of the `:primary` variant, alone or as
   the one button of a form) come last, in the markup as on the screen,
   after the others in the order the page gave them. (`ui-header-tests`:
   the markup and the order; `ui-header.py`: at 390, 360 and 320 px and at
   1280 px on the specimen, a long title with three actions and a title
   of one long compound word, and on the showcase's `/items`)
2. **The «more» menu on a phone.** Below 40rem of the header's own width,
   when the actions with an estimate of their width do not fit beside the
   title on the narrowest phone (Decisions, «Fitting is reckoned on the
   server»), every action that is a `button` (a link or a button) or a form
   holding one button, other than the filled ones, is hidden from the row
   and is an item of one «More actions» («Flere handlinger») menu, a
   `dropdown-menu` whose button is an icon only (`:ellipsis`), without a
   frame, standing before the filled actions; each item has the action's
   words, its icon, its link or its form (a submit item posts the action's
   form) and its other attributes (`hx-*`, a confirm), and is destructive
   when the action was. When even then the row does not fit, a filled
   action with an icon shows its icon alone below 40rem, its words staying
   its name. From 40rem nothing is folded and the menu is not shown. An
   action of another kind (a `dropdown-menu`, any other markup) is never
   folded. Without JavaScript the menu opens and its items work (the
   popover attributes, a link, a form's submit). (`ui-header-tests`: which
   actions fold for which titles, the items' markup, both languages;
   `ui-header.py`: at 390, 360 and 320 px the menu's button and the filled
   action on the title's row, no other action shown, the menu opening
   with every folded action in it, and opening without JavaScript; at
   1280 px every action shown and no menu)
3. **The shell on the chrome.** The `app-shell`'s top bar, its phone menu
   and its sidebar stand on `--chrome` itself, not a tint of it, with a
   1px `--chrome-border` edge, and the page under them on `--background`.
   The current `nav-list` entry keeps its siblings' weight and size
   (`ui-look`'s checks stay green). The phone menu's dim is `--overlay`.
   (`ui-header-tests`: the CSS; `ui-header.py`: the top bar's computed
   ground at 390 px and the sidebar's at 1280 px, light and dark)
4. **The theme colours are the chrome.** Without `:theme-color` and
   `:dark-theme-color`, a web app's manifest and the two `theme-color`
   meta tags carry the light and dark values of `--chrome`, `#f6f6f7` and
   `#111113`; a client that names its own keeps them. A test reads the
   defaults and `--chrome`'s values from the stylesheet's tokens and finds
   them equal. On the showcase (a web app with the defaults), the top
   bar's computed ground equals the `theme-color` meta for the active
   scheme, light and dark. (`ui-header-tests`, `web-app-tests`;
   `ui-header.py`)
5. **Section links.** A new component, `section-links`, in the layout
   group: `(section-links (:label L :items ((:label TEXT :href "#ID")
   ...)))`, a `nav` named L holding a row of plain links to the sections'
   ids. The row does not wrap; where it is wider than its box it scrolls
   sideways inside it, and the page does not. Where scripts run, the link
   of the section in view (the last section whose top has passed the top
   of the content, else the first) has `aria-current="location"` and shows
   it by its colour and an underline, at its siblings' weight, size and
   padding; it moves as the page scrolls and when a link is followed.
   Without JavaScript the links work as links and none is marked. A
   generated record page with three sections or more starts with one.
   (`ui-header-tests`: the markup, the CSS; `ui-header.py`: at 390 px the
   row's height of one line with its content wider than its box, scrolling
   it, the page not scrolling sideways; scrolling to the third section
   marks its link, following a link marks it, the weights equal; without
   JavaScript none marked and a link moving the page)
6. **`tabs` on the page's ground.** The default (segmented) `tabs` has a
   1px `--border` frame on the ground it stands on instead of a grey fill,
   and its chosen tab a `--secondary` ground with the `--border` edge, so
   the chosen tab reads as chosen on the page, a card and the chrome, in
   light and dark (the chosen ground differs from the list's in both
   schemes). In the `:line` variant the tabs keep their width, side by
   side from the start, links too. Choosing still moves nothing.
   (`ui-header-tests`: the CSS; `ui-header.py`: the chosen tab's ground
   differs from the page's in light and dark at 390 px; the `:line` links'
   gaps equal; `ui-look.py` stays green)
7. **A record's facts by spacing.** `summary-list` has no line or box
   between its rows. Below 30rem of its own width each row is the label
   beside the value (the label at the start in `--muted-foreground`, the
   value after it), the action under the value; from 30rem the rows stand
   in two columns, each row its label above its value and the action
   beside the label. The list has no padding or edge of its own, so its
   left and right edges are its box's, in line with the header and the
   sections around it. (`ui-header-tests`: the CSS; `ui-header.py`: at 390
   px one column, every value right of its label; at 1280 px two columns;
   no row with a border; the list's left edge equal to the page header's)
8. **No description in Tun's own pages.** `page-header` and `section` keep
   `:description`, and a client's description still renders. No page Tun
   generates or ships passes one: a test reads every Lisp file under
   `src/` and `modules/` but the component library (`src/web/ui/`), and
   finds no call of `page-header`, `section`, `respond` or `guest-page`
   with `:description`, no call of `page-header*` or `section*` whose
   options are a literal plist holding it, and no page's fourth value with
   it, where the value after `:description` is anything but the variable
   `description` itself: passing on a description given from outside, as
   `respond` does with a client page's fourth value, is not a page of
   Tun's, and stays so a client's description renders. `guest-page`
   loses its `:description` key, which no page passes any more. Where a
   description carried what a person needs, it stays on the page in
   another form (Decisions, «Where the descriptions went»). The generated
   record page shows its status as a badge in the header's new `:meta`
   (live facts under the title: a badge, a count), not as a description.
   (`ui-header-tests`)
9. **The account's flash stays.** The flash after an account is created
   (with the way the person signs in, or the address an invitation went
   to) is `:toast nil`: in the page, not leaving by itself.
   (`ui-header-tests`: the markup after creating a person, both kinds)
10. **Evidence and the clients.** A new `tests/ui-header-tests.lisp` and
    `checks/showcase/checks/ui-header.py`, with no page error; the
    specimen gains examples (a long title with three actions, a header
    with `:meta`, `section-links` on a page of sections). The before and
    after pictures of `page-header`, `section`, `app-shell`, `nav-list`,
    `breadcrumbs`, `summary-list`, `tabs` and `section-links` at 390 and
    1280 px, light and dark, are in the Log's folders. Every existing test
    and check stays green, none weakened; a test that pinned an old value
    is changed and named in the Log. `spec/ui.md` §4.2, §6, §8 and §10 and
    `docs/client-api.md` say the above. Core 2.27.0 in
    `src/core/module.lisp` and `flake.nix`. No component's lambda list
    loses a key or refuses a value it took; the five clients build and
    pass their own `bin/test` against this tree, unchanged, each result in
    the Log.

## Decisions

- **Fitting is reckoned on the server.** Whether the actions fit beside
  the title is decided where the header is rendered, not measured in the
  browser, so the header looks the same with and without JavaScript and
  nothing moves after the page loads. The reckoning is for the narrowest
  phone, 320 px, whose content is 18rem wide: an icon button is 2.75rem
  (a finger's control), a button with words 1.25rem of padding, 1.375rem
  for an icon and 0.5rem a character, a form or a menu its button's,
  anything else 6rem, with 0.5rem between actions; the title keeps the
  room of its words at 0.75rem a character, at most 6rem. The actions fit
  when they and the title's room and 1rem between them come to 18rem or
  less. So the showcase's «Items» with «Search», «Filter» (icons) and «New
  item» keeps all three; «Ole Hansen Ltd» with «Edit» and «New order»
  folds «Edit» and keeps «New order»'s words; a long title with «Send to
  the customer» and two more folds them and shows the filled one's icon.
  The folding applies below 40rem of the header's own width (a container
  query), so a desktop is never folded. This is the place where the
  owner's rule («when they do not fit») is read as an estimate; measuring
  in the browser would fold after the first paint.
- **Filled last in the markup, not by CSS `order`.** The header puts the
  filled actions after the others in its markup, so the order a screen
  reader and Tab follow is the order on the screen.
- **The folded actions are in the page twice**: in the row, hidden below
  40rem, and as items of the menu, shown only there. A form action keeps
  its form in the row (hidden, it still posts), and its item is a submit
  button naming the form (`form=`); the header gives the form an id when
  it has none.
- **A filled action shows its icon alone only when it has to**, and only
  when it has an icon: one without keeps its words, and the title wraps
  narrower beside it.
- **`:meta`, live facts under the title**, is a new option of
  `page-header` and a new key of a page's fourth value: a row of nodes
  under the title's row, for a status badge or a count, which the owner's
  rules allow where they refuse a description. The generated record page
  moves its status badge there.
- **Where the descriptions went.** Each page and section description in
  Tun's own sources, and what became of it:
  - Restatements of the title, dropped: sign-in («Sign in to …»), the
    offline page («The page could not be fetched…»), the jobs overview
    (`modules/dashboard/jobs.lisp`, «The background jobs: what is
    waiting, running and failed, and the schedules.»), and the errors
    list's first sentence («Errors the code did not mean, grouped by
    cause…»).
  - What says what a list or a block holds, its limit or its order,
    becomes that list's caption (a `table`'s, which is its title) or the
    block's title (a `code-block`'s), with the same words: the errors
    page's «Occurrences» («The last 50, newest first. A request shows as
    long as the process has it in memory.») and «Backtrace» («Where the
    error happened, innermost first, the last time.»); the log list
    (`modules/dashboard/log.lisp`, «The last N requests the process has
    in memory, newest first. They are not stored…»), a request's
    «Steps» («In time order, each step's time against the whole
    request's; N more steps were not kept», the count only when steps
    were dropped) and its «Backtrace» («Where the error happened,
    innermost first.»); the jobs overview's «Queues» and «Processes»
    («… A process that is not alive has had its jobs taken over.»); the
    jobs list of one state (`/jobs/list`, «The last 100 jobs in the
    state, newest first.»); and the schedules page (`/jobs/schedules`,
    «The jobs queued by the clock, in local time, and the triggers…»,
    which the times in its table need).
  - What a person needs to act moves to where they act: the errors list's
    «A resolved error that happens again is open again.» into an info
    alert beside «Mark as resolved» on an open error's page; the first-run
    setup's «Tun has no administrator yet.» into the card that explains
    the page; «Accounts»' «People sign in with …, agents with tokens.»
    into the «New account» form's card, where an account is made; «My
    tokens»' sentence about tokens («… The token is shown only when it is
    made.») into the «New token for me» card; «Connect without a token»
    («Claude Code and other MCP clients that can do OAuth sign in as you
    through WorkOS, without a token.») into an info alert in its section;
    a public offer's «Your answer goes to …» into an info alert above the
    answer.
  - The generated record page's status badge goes to the new `:meta`.
  Cards and empty states keep their descriptions: the rule (2B) is about a
  header's and a section's.
- **Section links are a component of their own**, not an option of
  `tabs`: tabs show one part at a time, section links point into one page
  read as a whole, and the markup and the script differ. It is not sticky:
  a sticky row on a phone takes a strip of a small screen from the
  content; a client that wants it sticky can ask for a later loop.
  `aria-current="location"` is the ARIA value for a place within a page.
- **The facts keep `summary-list`'s call shape**: it is Tun's record's
  facts, so its look changes for every client that uses it, as `ui-look`'s
  did. The owner's rules put a hairline between the facts on a phone;
  this loop follows the brief, by spacing alone.
- **The top bar is the chrome itself**, not 95 % of it under a blur:
  the theme colour can only be one colour, and the status bar and the bar
  are one surface only when they are the same. `ui-look-tests`'
  `the-shell-stands-on-the-chrome` pinned the tint, and is changed to the
  solid ground.
- **The theme colours' defaults change** to `#f6f6f7` and `#111113`. A
  client that never named them gets the chrome in its installed app's
  bar; one that named `#ffffff` keeps it (none of the five changes).
  `:background-color`, the start screen, stays the page's `#ffffff`.
- **`tabs`' ground.** The segmented list's grey fill read as a box on the
  white page and, in the dark, put the chosen tab (the page's ground) below
  the list's; a frame on whatever ground it stands on and a chosen
  `--secondary` ground read the same on the page, a card and the chrome.
  The `:line` links' `li`s grew and spread the tabs over the row.
- **Not here**: a sticky row of section links, a phone bottom tab bar,
  stat cards, header actions under the title, the sections' own actions
  on a phone (they wrap as before), filters, lists, search.
- **Core version 2.27.0**: new component, new options, a changed look and
  new defaults; no call shape changes.

## Log

- 2026-11-11 23:39  started, reviewed
- 2026-11-11 23:45  estimated 2h30m 4h 7h at brief, like tun/ui-sheets tun/ui-look
- 2026-11-11 23:46  gate A asked of a reviewer
- 2026-11-11 23:47  gate A: changes (reviewer)
  I'm asking for changes. The criteria match the brief closely, but criterion 8 has two gaps against what was asked for Tun's own pages (brief item 5).
  
  **What is right**
  - Brief items 1–7 each have a criterion (1–2, 3–4, 5–6, 7, 8, 9, 10), and each one names a test or a browser check that could decide it. The out-of-scope items are left out: bottom tab bar, stat cards, filters, lists, search, and `data-table`'s phone layout. The clients-unchanged rule is in criterion 10.
  - The theme-colour defaults `#f6f6f7` / `#111113` are the real `--chrome` values (`src/web/ui/kit.lisp:309`).
  - The spec change says the same as the criteria: §6 `page-header`, `section-links`, `summary-list`, `tabs` and `app-shell`; the web-app colours; §8's header and record; the fourth value's `:meta`; and the test list. `docs/client-api.md` agrees with both.
  - None of the Decisions needs Jonas's answer. Reckoning the fit on the server reads the owner's «when they do not fit» as an estimate, says so openly, and gives the reason (nothing moves after the page loads). The theme-colour change is what brief item 2 asks for. Using spacing alone for the facts follows the brief rather than the owner's hairline, and the decision says so.
  
  **Changes**
  
  1. **The list of where the descriptions went is incomplete** (loop.md Decisions, «Where the descriptions went»). The brief says each description that carried what a person needs must stay in another form, «named in the report». The list skips these page and section descriptions that will be removed:
     - `modules/dashboard/errors.lisp:58`, the Errors page: «A resolved error that happens again is open again.» A person needs this to act.
     - `modules/dashboard/log.lisp:100`, the log list: «They are not stored: after a restart the list begins again, and errors are in "Errors".»
     - `modules/dashboard/log.lisp:165`, the log's «Where the error happened».
     - `modules/dashboard/jobs.lisp:153`: «The last 100 jobs in the state». This is a limit the list does not show.
     - `modules/dashboard/jobs.lisp:253`, Schedules: «…in local time…». Without it, the times in the table can't be read correctly.
  
     For each one, say whether it is dropped as a restatement or where it goes. The list's «the jobs page» should say which of the jobs pages it means (lines 125, 128, 132, 153 and 253 are all jobs pages).
  
  2. **Criterion 8's test would miss a page Tun ships.** The test only looks for calls of `page-header`, `section`, `respond` or `guest-page` with `:description`. But the offline page builds its header with `ui:page-header*` and a plist holding `:description` (`src/web/web-app.lisp:93–95`). The test would pass with that page unchanged. Add `page-header*` and `section*` (a literal plist with `:description`) to criterion 8, and to the matching test entry in `spec/ui.md` §10 (diff lines 214–216).
  
  **Not blocking**
  - Criterion 1 says a long title wraps beside the actions, but its check only uses a title of several words. Under the server's fit estimate, the title gets at most 7rem at 320 px. A single long Norwegian compound word would overflow that and push the actions off the right edge. Consider requiring that a title's word breaks too, and adding such a title to the check.
- 2026-11-11 23:49  gate A asked of a reviewer
- 2026-11-11 23:49  gate A: changes (reviewer)
  I'm asking for changes: one item in criterion 8 can't be met as written. Everything else checks out.
  
  **What is right**
  - **Both changes from the last round are made.**
    - The «Where the descriptions went» list now covers every page and section `:description` in `src/` (outside `src/web/ui/`) and in `modules/`. I checked it against the repository: `errors.lisp:58/111/117`, `jobs.lisp:125/128/132/153/253`, `log.lisp:100/160/165`, `web-app.lisp:95`, `access.lisp:91/268/401/405/425`, the public offer's «Your answer goes to …», and the record's status at `ui.lisp:1633`. Each one is either dropped as a restatement or given a named place. The jobs pages are named by file and route.
    - Criterion 8 and `spec/ui.md` §10 (diff lines 217–220) now include `page-header*` and `section*` called with a literal plist.
  - **The non-blocking point is taken up too.** Criterion 1, the §6 text and the `ui-header.py` entry now say that a title of one long word breaks, and the check uses such a title.
  - **The criteria still match brief items 1–7, and nothing out of scope came back.** Each criterion names a test or a check that could decide it. The spec and `docs/client-api.md` say the same as the criteria. No decision needs Jonas's answer.
  - **The descriptions that stay are allowed by the rule.** Those on cards and empty states (`ui.lisp:1441`, `ui.lisp:1530`, `messaging/web.lisp:82`, `inbox`, `notifications`) are covered by «Cards and empty states keep their descriptions».
  
  **Changes**
  
  1. **Criterion 8's scan would fail on the code that keeps client descriptions working.** As worded, the test finds no call of `respond` with `:description`, and no `page-header*` with a literal plist holding it. Two calls match:
     - `src/web/ui.lisp:232`: `(respond status title body :description description …)` passes a client page's fourth value on.
     - `src/web/ui.lisp:635`: `(ui:page-header* (list :title title :description description …))` is inside `respond`.
  
     Both have to stay, or criterion 8's own «a client's description still renders» breaks. (`access.lisp:43`, `guest-page` passing its parameter on, matches too. It can go, since no guest page will pass one.) So the test cannot pass without either breaking clients or adding an exception the spec doesn't mention.
  
     Say in criterion 8, and in `spec/ui.md` §10 (diff lines 217–220), what the scan flags: a `:description` whose value is a string or a form such as `(tr …)`, `(when …)` or a call, rather than a variable named `description` passed on. Or name the code that passes a description on (`respond`, and the fourth value's `destructuring-bind` in `ui.lisp`) as exempt.
- 2026-11-11 23:50  gate A asked of a reviewer
- 2026-11-11 23:50  gate A: approve (reviewer)
  I approve this spec. The one change asked for last round is made, I checked the scan rule against the code, and nothing else has changed for the worse.
  
  **What is right**
  - **Criterion 8's scan can now pass without breaking clients.** It flags a `:description` whose value is anything but the variable `description` passed on, and `spec/ui.md` §10 (diff lines 217–221) says the same thing. I checked every place in `src/` and `modules/` that passes `:description description`:
    - `src/web/ui.lisp:232` (`respond`) and `src/web/ui.lisp:635` (`page-header*` inside `respond`) are exempt. They pass a client page's description on, so a client's description still renders.
    - `src/web/access.lisp:43` (`guest-page`) is exempt, and its key goes anyway.
    - The other matches are not calls the scan covers: operation and field metadata, settings, and a `card` at `ui.lisp:1322`. The scan names only `page-header`, `section`, `respond`, `guest-page`, `page-header*` and `section*` with a literal plist, and a page's fourth value.
    - The offline page's `ui:page-header*` at `src/web/web-app.lisp:93` is caught, because its plist holds a string. So the test does decide the criterion.
  - **The criteria still cover brief items 1–7**, and they leave out what the owner's warnings and the brief's «not this loop» exclude:
    - left out: header actions under the title, a phone bottom tab bar, stat cards, filters, lists, search, and `data-table`'s phone layout;
    - kept: the five clients unchanged and passing.
  - **Every criterion names a test or a browser check that can decide it.** Criterion 1 now also pins a title of one long word.
  - **The spec and the docs match the criteria.** §6 covers `page-header` with its «more» menu and the fit estimate, `section-links`, `summary-list`, `tabs` and `app-shell`. The web-app section has the theme defaults `#f6f6f7` and `#111113`. §8 covers the header, no descriptions in Tun's pages, and the record with `:meta` and section links. §10 lists the tests and checks. `docs/client-api.md` says the same.
  - **No decision needs Jonas's answer:**
    - Reckoning the fit on the server is stated openly as a reading of «when they do not fit», with its reason.
    - Following the brief's spacing over the owner's hairline is stated.
    - The new theme defaults are what brief item 2 asks for.
    - Where each description went is listed in full, which brief item 5 requires.
  
  **Not blocking**
  - The exemption goes by the variable's name. A page of Tun's own that bound a local `description` to a string would slip past the scan. Nothing in the tree does this today. If a sharper test is cheap at gate B, it could limit the exemption to `respond`, `guest-page` and the fourth value's `destructuring-bind`.
- 2026-11-12 00:12  verify 1: passed build, test, check
- 2026-11-12 00:14  shown (/items, /ui/page-header, /ui/section-links, /ui/summary-list, /ui/tabs, /ui/app-shell, /access)
- 2026-11-12 00:24  verify 2: passed build, test, check
- 2026-11-12 00:25  shown (/items, /ui/page-header, /ui/section-links, /ui/summary-list, /ui/tabs, /ui/app-shell, /access)
- 2026-11-12 00:25  the title's room in the header's reckoning is at most 6rem, not the 7rem written at gate A: with 7rem «Ole Hansen Ltd» with «Edit» and «New order» would show «New order» as an icon at 320px, where 6rem leaves its words and the title still two lines; spec §6 and the Decisions say 6rem
- 2026-11-12 00:25  existing tests changed, none weakened: tests/ui-look-tests.lisp the-shell-stands-on-the-chrome pinned the top bar's 95% tint of the chrome, and now asks for no tint and the chrome itself on the top bar, the sidebar and the phone menu; tests/web-app-tests.lisp every-page-carries-the-head-tags pinned the dark theme colour's old default #0a0a0a, now #111113; tests/ui-data-tests.lisp the-shell-gives-a-board-the-height-the-page-leaves pinned the old phone rule of the header (flex-basis: auto under 40rem), now the title taking the room the actions leave and the actions not shrinking
- 2026-11-12 00:25  found while building: section-links' script first brought the marked link into view with scrollIntoView, which also scrolled the page back up to the row; it now scrolls only the row, and ui-header.py checks the page stays where it was scrolled. The «New account» card said «People sign in with , agents with tokens.» on a server with no identity provider (claimed identity), as the Accounts section's description did before; the sentence now shows only when there are providers
- 2026-11-12 00:26  pictures: the specimen before (base 6d34699) and after, every component at 390 and 1280 px, light and dark: ~/coding/tun-wt/ui-header-shots/before/ and after/ (bin/ui-shots); the open states (the «More actions» menu open at 390, 320 and 1280 px, the section links with a marked link), light and dark, in after/ as *-open-*.png and in the show folder
- 2026-11-12 00:35  the five clients' bin/test against this tree (base 6d34699, nix develop --override-input tun git+file of the worktree, verify-2's tree), unchanged: tunworks/apps/factory 583 passed; tunworks/apps/nixploy-dashboard 1421 passed; tunworks/apps/ferdig 812 passed; kurs 352 passed (its own fake-saxo note, as before); tun-erp 854, 68380, 344 and 244 passed; no compiler warning, none failed
- 2026-11-12 00:36  gate B asked of a reviewer
- 2026-11-12 00:37  gate B: changes (reviewer)
  I'm asking for one change: criterion 5 promises section links at the top of a generated record page, and no test or check shows it. Everything else meets its criterion, and all three steps of `verify.txt` passed (build, test, check).
  
  **What is right**
  - **Header row and «More actions» (criteria 1 and 2).**
    - `header-actions` (`src/web/ui/layout.lisp`, diff 1352–1385) puts the filled actions last in the markup. It folds only buttons and forms that hold one button. A folded form keeps its place and gets an id, and its menu item submits it through `form=`.
    - `ui-header.py` passed at 390, 360 and 320 px for the long title and the one-word title. The title's top equals the actions' top, the filled action's right edge is the header's, and the folded menu holds exactly «Preview» and «Withdraw».
    - At 1280 px every action shows and there is no menu. Without JavaScript the menu opens.
    - The screenshots match: the 320 px open menu, and the one-word title breaking beside «⋯ Edit».
    - `ui-header-tests` checks which actions fold, the items' link, form, `hx-*`, confirm and destructive markup, the Norwegian label, and that a `dropdown-menu` never folds.
  - **Chrome and theme colours (criteria 3 and 4).** The top bar is solid `--chrome` and the phone menu's dim is `--overlay`. The new defaults `#f6f6f7` and `#111113` are compared with the token values in a test. The browser check finds the bar's computed ground equal to the `theme-color` meta in light and dark.
  - **Section links, the component (criterion 5).**
    - The browser check covers: one line, scrolling in its own row, the page not moving sideways, a link marked on scroll and when followed, equal weights (500/14px), and none marked without JavaScript.
    - The `scrollIntoView` problem the builder found is fixed: `showInRow` scrolls only the row, and the check confirms the page stays put.
  - **Tabs and facts (criteria 6 and 7).** In both schemes the chosen tab's ground differs from the page's, and the line tabs' gaps are equal. The facts show one column with each label beside its value at 390 px, two columns at 1280 px, no borders, and their left edge in line with the header and sections.
  - **No descriptions in Tun's pages (criterion 8).** The scan follows the agreed rule, covers `page-header*`/`section*` with a literal plist and a page's fourth value, and handles backquoted code. Every description removed went where the Decisions say. On `/access` the «New account» sentence now shows only when there are identity providers, which fixes the empty «People sign in with , …».
  - **The account's flash (criterion 9).** Both kinds of account creation are tested for `data-placement="page"`.
  - **Clients and version (criterion 10).** Core is 2.27.0 in both files. The three tests changed for old values are named in the Log, and none is weaker. All five clients pass unchanged. The spec (§4.2, §6, §8, §10) and `docs/client-api.md` match the code.
  
  **Changes**
  
  1. **The record page's section links are untested** (criterion 5: «A generated record page with three sections or more starts with one»; spec §8, diff 709–710). `record-sections` (`src/web/ui.lisp`, diff 969–984) implements it, but:
     - `a-record-shows-its-status-in-the-headers-meta` (`tests/ui-header-tests.lisp`, diff 2171–2173) only checks `id="record-details"`.
     - No browser check or screenshot opens a record page.
  
     Removing the `section-links` branch would break no test. Please add assertions to that test (or a sibling) for:
     - a record with three or more sections: a `<nav class="tun-section-links"` before the first section, holding `href="#record-details"`;
     - a record with fewer than three sections: no section links.
  
  **Not blocking**
  - `dropdown-menu` items now also accept markup as `:icon`, not just a name (`src/web/ui/interaction.lisp:749`, diff 1172–1173). The header needs this for folded items, but §6 doesn't mention it. A short note there would keep the spec and the code in line.
- 2026-11-12 00:48  verify 3: passed build, test, check
- 2026-11-12 00:48  shown (/items, /ui/page-header, /ui/section-links, /ui/summary-list, /ui/tabs, /ui/app-shell, /access)
- 2026-11-12 00:48  gate B 1's changes: the generated record page's section links are tested both ways: record-sections with three sections starts with a section-links nav whose links lead to each section's id, with two none (a-record-of-three-sections-starts-with-links-to-them), and the order page checks the nav before its sections whenever it has three or more; spec §6 and dropdown-menu's docstring say an item's :icon is a name or an icon already made. The clients' runs were on verify-2's tree; since then only tests, the spec and a docstring changed
- 2026-11-12 00:48  gate B asked of a reviewer
- 2026-11-12 00:49  gate B: approve (reviewer)
  I approve this round. The one change asked for at gate B round 1 is made, and nothing has got worse since.
  
  **What is right**
  - **The record page's section links now have tests (criterion 5).**
    - `a-record-of-three-sections-starts-with-links-to-them` (`tests/ui-header-tests.lisp`, diff 2195–2209) renders `record-sections` with three sections. It checks that the `<nav class="tun-section-links" aria-label="On this page"` comes before the first `<section`, and that it links to `#record-1` and `#record-3`, whose ids the sections carry. With two sections it checks there is no nav.
    - That test would fail if the `(>= (length entries) 3)` branch in `src/web/ui.lisp` (diff 979–987) were removed, and also if it fired with fewer than three sections.
  - **The order page test now covers the links too.** `a-record-shows-its-status-in-the-headers-meta` (diff 2186–2193) checks the nav before `record-details` when the page has three or more sections, and no nav when it has fewer. Which branch runs depends on the fixture, but the unit test above covers both cases either way.
  - **The non-blocking point from round 1 is also done.** `spec/ui.md` §6 (diff 645) and `dropdown-menu`'s docstring (diff 1186) now say an item's `:icon` is a name or an icon already made.
  - **Verification passed.** All three steps of verify 3 passed: build, test and check. Every result in `checks/` passed, including all of `ui-header.json`:
    - the header row and the «More actions» menu at 390, 360 and 320 px, and without JavaScript;
    - every action and no menu at 1280 px;
    - the top bar and sidebar ground equal to the `theme-color` meta in light and dark;
    - the section links' row, its marking and the version without JavaScript;
    - the facts' layout and their line with the header;
    - the tabs' grounds.
  - **Everything round 1 found right still holds.** The only changes since verify 2 are tests, the spec and a docstring, as the Log says. So the five clients' runs on verify 2's tree still apply to this code.
