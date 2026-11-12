# A list's filters: one button per filter beside the search, a «Filters» sheet on a phone, the state in the address

- loop: ui-filters
- mode: reviewed
- stage: ship
- base: 415a002c3bb89e8c04e600a7bc49f22f61baaa05
- item: sak_41rk2e2c4svqxmw0
- estimate: 2h20m 3h30m 6h
- like: tun/ui-sheets tun/ui-header
- tags: kind:ui core module:ui
- verified: 366021b3de9d8898323cbdb17a7bd26b4776cb98
- shown: 366021b3de9d8898323cbdb17a7bd26b4776cb98

## Brief

Ferdig sak_41rk2e2c4svqxmw0, brought by the factory's orchestrator on
2026-11-12, the fourth loop of the work on Tun's component library after
`ui-look` (core 2.25.0), `ui-sheets` (2.26.0) and `ui-header` (2.27.0).
Jonas, 2026-11-11: he has polished the admin UI of another application of
his for two weeks and wants the best of it carried into Tun's component
library, «to make the UI component Library of Tun superb». The source is
the owner's rules for an admin application, 2026-11; code does not carry
over, rules, values, component anatomy, behaviour and the tests that pin
them do.

This loop gives a list one toolbar. The orchestrator's brief, in short:

1. **One toolbar per list**: a new component holding the list's one
   search field and its filters, one GET form whose fields are the
   filters, so the state lives in the address: a link, a reload and Back
   keep it, and the page works with JavaScript off (with a visible
   «Apply», or native controls that submit), usable and tested so.
2. **One button per filter**, named by the filter («Status»), beside the
   search; pressing it opens the filter's choices under it, a popover in
   the top layer moved into place as `ui-sheets` does (opacity and
   translate, `--duration-fast` in, `--duration-close` out). Kinds: one
   of several, several of several, on/off (a single toggle button, no
   popover), and a date range if the set has the fields for it (else left
   to `ui-search`, which builds the date fields, and said so). A filter in
   use shows its value in the button («Status: Open», a count when
   several) without a change of weight or size, and is cleared from the
   button; «Reset», underlined words, once two or more are in use.
3. **Applied at once** where scripts run: choosing submits the form,
   through htmx in a boosted shell, so only the list changes and the focus
   and the open popover behave (decide and pin whether the popover stays
   open for several of several and closes for one of several), with the
   loading sign; no «Apply» then. The address is updated (push or
   replace, decided); Back returns to the previous state or leaves the
   list, never to a half state.
4. **On a phone** (the toolbar's own width below 40rem, a container
   query): the search stays; more than two filters fold into one
   «Filters» button showing how many are in use, opening a sheet from the
   bottom (the dialog as a sheet from `ui-sheets`: `--overlay`,
   `--duration-sheet`, title «Filters» and a close button pinned, the page
   held, focus back to the button, Escape and the dim close it), one row
   per filter with its choices inline under it, applied at once with the
   list behind updating; the fields stay inside the list's one form. With
   one or two filters they stay buttons, their popovers on a phone
   floating sheets (0.75rem gutters, full radius) or anchored popovers,
   pinned by a check that the popover never leaves the window at 320 px.
5. **Generated list pages** (spec §8) use the toolbar for the filters
   they already offer, with no change to the address keys clients and
   tests rely on; the clients' own hand-built filter forms keep working
   unchanged, and the report says what each would change to move onto
   the toolbar.
6. The specimen shows the toolbar with each kind, in use and not; before
   and after pictures (390 and 1280 px, light and dark) of a generated
   list page in the showcase, and open-state pictures of a popover and of
   the «Filters» sheet. A browser check measures: one row at 1280 px;
   nothing overflowing at 390, 360 and 320 px; choosing changes the
   address and the list without a full page load; Back returns the
   previous state; without JavaScript the form still filters; the sheet's
   boxes, dim and focus as in `ui-sheets`' check; no shift of the toolbar
   when a filter goes into use beyond the button's own width (the row
   below does not move vertically).

Rules: every script through `tunOnContent` and `data-tun-*` delegation,
`tunPopoverOpen` and `tunModal` instead of the pseudo-classes, no
`setTimeout` for motion, act on click, not on pointerdown. Warnings from
the owner's rules: filters went through three shapes there (all behind
one «Filters» button; one button per filter; phones folding more than two
into a sheet); the first two are not rebuilt as such, the third is this
loop. Dense toolbars on phones were the recurring trap there. Not this
loop: a table's rows on a phone and the pressed row (`ui-lists`), search
on Ctrl K and the date, time and money fields (`ui-search`). The five
clients (factory, nixploy-dashboard, ferdig, kurs, tun-erp) must compile
and pass unchanged and are not touched.

Mode: reviewed. A core change, a minor version.

## Criteria

1. **One toolbar, one form.** A new component `list-toolbar`, in the data
   group: `(list-toolbar (:action PATH :search (:name N :label L :value V)
   :filters (FILTER...) :keep ((KEY VALUE)...) :id ID))` renders one
   `<form method="get" action=PATH role="search">` holding the search
   field (`type="search"`, labelled, its value), every filter's fields,
   and the KEEP pairs as hidden fields (such as the list's sort). A
   FILTER is `(:name :label :kind :choices :value [:all])`, KIND `:one`
   (one of several), `:several` (several of several) or `:toggle` (on or
   off); CHOICES are `(VALUE LABEL)` pairs, as `radios` take them. Every
   submission names every filter's key: a `:one` filter has an «All»
   («Alle», or ALL) choice of value empty, and a `:several` and a
   `:toggle` filter an empty hidden value before their own, so a page
   that `:remembers` a key sees it cleared rather than missing. A key
   given more than once reaches a `define-page`'s QUERY as a JSON array
   of its values in order (a key given once stays a string, as today), a
   `:remembers` page keeps and restores such a key's values, and a new
   function `(query-values QUERY KEY)` in `TUN` gives a key's non-empty
   values as a list. (`ui-filters-tests`: the markup, both languages,
   the hidden values, QUERY with a repeated key, `query-values`, a page
   remembering a repeated key)
2. **One button per filter, beside the search.** From 40rem of the
   toolbar's own width the search field and one button per `:one` and
   `:several` filter stand on one row that never wraps (the search keeping
   24rem while there is room, narrowing to 12rem first when the row is
   full, then the filters scrolling in their own box), each button named by the filter's
   label; at 1280 px the search's box and every button's box have their
   tops within 1px of each other. A `:toggle` filter is one button with
   no popover, pressed (its box checked) when on. A filter in use shows
   its value in its button: «Status: Open» for one choice, «Tags: 2» for
   two or more of a `:several` filter, and a clear button (an ×, «Clear
   Status» to a screen reader) joined to it, a link to the address
   with that filter cleared; with two or more filters in use, «Reset»
   («Nullstill») stands after them as underlined words, a link to the
   address with every filter cleared and the search and KEEP kept. These
   links name every filter's key, a cleared one empty
   (`/orders?q=…&status=&tags=&tags=rental&dateless=`), as the form's own
   submissions do, so on a page that `:remembers` them they clear rather
   than lead back to what was kept. Choosing moves nothing: a
   button in use has the weight, the font size, the height and the edge
   width of one not in use, and shows its state by its edge (`--border-
   strong`) and its words; on the showcase, putting a filter into use
   leaves the row's height and the top of the list under it where they
   were, to 1px. (`ui-filters-tests`, with a clear and a «Reset» followed
   on a `:remembers` page; `ui-look-tests`' scans stay green;
   `ui-filters.py`)
3. **The choices open under the button.** Pressing a `:one` or
   `:several` filter's button opens its choices (radios, or checkboxes)
   in a popover (`popover="auto"`: one open at a time, Escape and a
   press outside close it, focus back to the button), in the top layer,
   under the button, or above it when there is more room there, and
   always inside the window. It rises from 0.25rem below and fades in
   over `--duration-fast` and sinks and fades over `--duration-close`,
   animating only `opacity` and `translate`. Below 40rem of the window's
   width the popover is a floating sheet: at the bottom of the window,
   0.75rem from its sides and 0.75rem above the bottom's safe area, every
   corner `--radius-xl`, headed by the filter's label and a close button,
   over the `--overlay` dim, rising from below over `--duration`. At 320,
   360 and 390 px the open popover's box is wholly inside the window.
   (`ui-sheets-tests`' CSS scan takes the popover in; `ui-filters.py`:
   the boxes at 1280 and 320 px, the transition's properties and
   durations)
4. **Applied at once, with the address.** Where scripts run, choosing a
   value (a radio, a checkbox, the toggle) or clearing one submits the
   form at once and there is no «Apply» button; in a boosted shell the
   form is sent by htmx, which morphs the page in place (`hx-swap`
   `innerMorph` of the body) and pushes the new address, so the page is
   not loaded again (the window's own state survives), the loading sign
   shows as for any request, a `:several` filter's popover stays open
   with the focus on the box just ticked, and a `:one` filter's popover
   closes after the choice with the focus on its button. Each choice is
   one entry in the history: Back returns to the address and the list of
   the state before it, and from the first state leaves the list. Without
   JavaScript the popovers open with their buttons (the Popover API), an
   «Apply» («Bruk») submit button shows, and submitting filters the list
   to the chosen values. (`ui-filters.py`: the address, the list, a
   marker on `window` surviving, the popover and the focus, Back twice,
   without JavaScript)
5. **The «Filters» sheet on a phone.** Below 40rem of the toolbar's own
   width the search field fills its row. With three or more filters
   they are not shown in the bar but behind one «Filters» («Filtre»)
   button after the search, which shows how many filters are in use
   when any are («Filters 2» to a screen reader: «Filters, 2 in use»).
   It opens a `dialog` that is a sheet as `ui-sheets` makes it (at the
   bottom at the window's width, top corners `--radius-xl`, under the
   2rem strip, the `--overlay` dim fading in, sliding up over
   `--duration-sheet`), titled «Filters» with its close button pinned at
   the top, holding one row per filter: its label and value, and under
   it its choices inline, not in a popover. The dialog is inside the
   toolbar's form, so its fields are the form's: choosing applies at
   once as in 4, the list behind changes and the sheet stays open with
   the focus on the choice. Escape, the close button and a press on the
   dim close it, the focus goes back to «Filters», and the page behind
   does not scroll while it is open. With one or two filters there is no
   «Filters» button: their buttons stand on one row under the search,
   which scrolls sideways in its own box rather than wrap. Without
   JavaScript nothing folds, whatever the browser: every filter keeps its
   button on that row, its popover opening with the Popover API, and
   «Apply» submits, so no filter hangs on invoker commands. At 390, 360
   and 320 px no part of the toolbar, its sheet or its popovers is wider
   than the window, and the page does not scroll sideways. (`ui-filters.py`
   on the showcase and the specimen; without JavaScript at 390 px on
   `/cards`, the three buttons shown, a popover opened and «Apply»
   filtering the list)
6. **Generated list pages.** The generated list of a resource gets a
   `list-toolbar` above its table built from its list operation's inputs:
   an input named `query` or `q` of text is the search, an enum input a
   `:one` filter, a list of an enum a `:several` filter, a boolean a
   `:toggle`; other inputs (ids, dates, numbers, other text, `limit`) are
   not offered. The address keys are the inputs' names as an agent
   passes them (`/orders?status=draft&tag=rental&dateless=true`), and
   the list is called with the values the address gives. A list
   operation with none of those inputs gets no toolbar, as today. The
   toolbar is part of the generated screen, so a client's `render-screen`
   method for the list that does not call the next method shows its own
   screen alone, as today. A filtered list with no records says «Nothing
   matches» («Ingen treff») with «Reset», the link of criterion 2. (`ui-filters-tests` on the
   test client's orders and customers)
7. **The specimen and the showcase.** `/ui/list-toolbar` shows the
   toolbar with no filter in use, with each kind in use, with two filters
   and with three or more. The showcase enables the `customers` module,
   so it has a generated list (`/customers`, with its search), and gains
   `/cards`, a page of its cards with a toolbar of a search and three
   filters of every kind (status several, estimate one, files on or off)
   that filters on the server. Before and after pictures of `/customers`
   and the specimen at 390 and 1280 px, light and dark, and open-state
   pictures of a popover and of the «Filters» sheet. A new
   `checks/showcase/checks/ui-filters.py` measures what criteria 2–5 say,
   with no page error thrown; `ui-look`, `ui-sheets` and `ui-header`'s
   tests and checks stay green, none weakened.
8. **The spec and the clients.** `spec/ui.md` §6 (`list-toolbar`), §8
   (lists, the query's repeated keys) and §10, `docs/client-api.md`
   (`list-toolbar`, `query-values`) say the above; core 2.28.0. No
   component's call shape changes; the five clients build and pass their
   own `bin/test` against this tree, unchanged, each result in the Log.
   The Log names each client's hand-built filter forms and searches and
   what moving each onto `list-toolbar` would change (address keys,
   markup its tests and checks pin, what the toolbar lacks for it).

## Decisions

- **One component, `list-toolbar`, in the data group** (a new file,
  `src/web/ui/toolbar.lisp`): a toolbar belongs to a list, and the
  `ui-lists` loop will stand beside it. A filter is data in its options,
  not a component of its own, so the toolbar can lay its filters out as
  buttons or as the sheet's rows from the same fields.
- **The fields are rendered once.** On a wide toolbar the sheet's
  `dialog` is laid open in the row (`display: contents` while it is not
  open, its header hidden), so each filter's button and popover stand in
  the row; on a narrow one it is a closed dialog until «Filters» opens
  it. The dialog is a child of the form, so its fields are the form's in
  the top layer as in the row: no field is copied, and nothing is moved
  by a script. In the sheet a filter's popover is shown in its row
  (`display: block` in the flow, its button hidden and a heading shown).
- **Morph, push.** The toolbar's form carries `hx-swap="innerMorph"` and
  `hx-push-url="true"`; the shell's boost sends it to the body. The
  request is then htmx's «full» one, so a page answers it with the whole
  page and a page that `:remembers` keeps it, and the morph keeps the
  open popover, the open sheet and the focus where the markup is the
  same. Every element of the toolbar has a fixed id (from `:id`,
  «tun-list-toolbar» when omitted, and the filter's name), so the morph
  matches them; two toolbars on one page need an `:id` each. Tun's
  htmx extension keeps an open dialog's `open` attribute through a morph
  (its `htmx_before_morph_attr` hook), which the server's markup lacks. Push, not
  replace: each choice is a state a person may want back, and Back then
  goes one choice back, never to a half state; every entry is a whole
  address the server renders.
- **A popover of one of several closes on the choice, of several stays
  open**, as the owner's rules have it: one choice is done when made, and
  ticking several is one task.
- **The clear and «Reset» are links** to the address with the filter (or
  every filter) cleared, naming every key, so they work without
  JavaScript and on a `:remembers` page; with it the script empties the
  filter's fields and submits, so they too go through the morph.
- **Without JavaScript nothing folds.** Under `(scripting: none)` the
  narrow toolbar keeps a button per filter on its sideways-scrolling row
  and shows «Apply»: the sheet would need invoker commands, which not
  every browser has.
- **On a phone, popovers are floating sheets** (with one or two
  filters): the owner's rules do so, a sheet never leaves the window, and
  a thumb reaches it. Anchored where it fits from 40rem of the window.
- **No date range here.** The set's date field is the browser's own
  `<input type="date">`, which fires a change for each part typed (a year
  0002 on the way to 2026), so applying at once would send a request per
  digit. `ui-search` builds the date fields, and the date range filter on
  them, and the generated orders list's `from` and `to` wait for it.
- **Every key in every submission.** A radio «All» of empty value, and an
  empty hidden value before a `:several` filter's boxes and a toggle's
  box, because an unticked box sends nothing, and a `:remembers` page
  sent none of its keys sends the person back to what they kept: a
  person could not clear the last tick. The cost is `tags=&tags=rental`
  in the address; `query-values` drops the empty one.
- **Repeated keys as an array.** A `define-page`'s QUERY held only the
  last of a repeated key, so a `:several` filter could not be read by a
  client's page. A key given once stays a string, so no client's page
  reads anything new unless it is given a key twice.
- **The generated list gets filters from its operation's inputs**: it
  offers no filters today, and its list operation's inputs are «the
  filters it already offers» (`orders_list`'s description names them),
  under the names agents pass. The address keys of the clients' own pages
  are theirs and do not change.
- **The showcase enables `customers`**: a client cannot register a
  generated resource, and the showcase had none to picture. `customers`
  needs no other module; its list offers a search. The orders module,
  whose list has a status, a tag and a toggle, needs four more modules;
  the test client's orders pin its toolbar in the Lisp tests instead,
  and `/cards` shows every kind with a server on the showcase.
- **No «Filters» dialog of its own kind.** The sheet is the `dialog`
  component (`ui-sheets`' sheet, dim, focus, hold and Escape), which the
  toolbar renders inside its form.
- **Core 2.28.0**: a new component, a new function, QUERY's repeated
  keys and the generated list's toolbar; no call shape changes.

## Log

- 2026-11-12 00:58  started, reviewed
- 2026-11-12 01:01  estimated 2h20m 3h30m 6h at brief, like tun/ui-sheets tun/ui-header
- 2026-11-12 01:02  gate A asked of a reviewer
- 2026-11-12 01:03  gate A: changes (reviewer)
  I've read the brief, the criteria, the decisions and the diff, and checked `spec/ui.md` §8 for how `:remembers` works today. The criteria cover most of the brief and each can be checked. Three things need changing before gate B.
  
  **What's right**
  - Brief items 1–4 and 6 each map to a criterion that names its test or check (`ui-filters-tests`, `ui-filters.py`): one GET form, one button per filter, the popover's motion and tokens, applied at once with push, the «Filters» sheet from three filters, the 320/360/390 px overflow checks, the no-shift measure, and the pictures.
  - The brief asked for some choices to be made and pinned, and they are: push rather than replace, a `:one` popover closes while a `:several` one stays open, and no date range (the brief allows leaving it to `ui-search` if it says so, and it does).
  - The spec changes in `spec/ui.md` §6, §8 and §10 and in `docs/client-api.md` match the criteria, apart from the two points below.
  - Sending every filter's key in every submission (`tags=&tags=rental`) and reading a repeated key as an array are well reasoned. A key given once stays a string, so no client's page reads anything new.
  
  **Changes**
  
  1. **Without JavaScript, the clear (×) and «Reset» links break on a `:remembers` page.** Criterion 2 makes them links to "the address without that filter" and "the address with the search and KEEP alone" (spec `spec/ui.md` §6, diff lines 102–105; «Nothing matches» … «Reset» in §8, diff lines 161–162).
     - §8 item 7 (`spec/ui.md:1552–1558`) answers a GET with none of the remembered keys with a 303 to the saved values. It already says "A link that clears a page's filters names one of its keys (`/saker?prosjekt=`)".
     - Example: a person who arrived through that 303 is at `/saker?status=open`. The status clear link is `/saker`, which redirects straight back to `status=open`. «Reset» fails the same way.
     - With JavaScript it works, because the script empties the fields and submits the whole form. Without it, it doesn't, and the brief requires the page to work with JavaScript off.
     - Change criterion 2, criterion 6 and the spec so these links name every filter's key, with the cleared ones empty (`?q=…&status=&tag=`), as the toolbar's own submissions do. Add a test of a clear and a Reset on a `:remembers` page to `ui-filters-tests`.
  
  2. **Without JavaScript on a phone, the criteria and the spec disagree.**
     - The spec (diff lines 138–140) says the «Filters» sheet opens without JavaScript only "where the browser has invoker commands". Criteria 4 and 5 say nothing about a narrow toolbar without JavaScript.
     - The brief requires the page to work with JavaScript off, "usable and tested so". As written, three or more filters on a phone could be unreachable without JavaScript in some browsers, and nothing would catch it.
     - Add to criterion 4 or 5 what happens below 40rem without JavaScript: the sheet opens through `commandfor`, or the filters stay reachable some other way. Add that case to the no-JavaScript step of `ui-filters.py`, and make the spec say the same.
  
  3. **One part of the brief has no criterion.** Brief item 5 asks that "the report says what each [client's hand-built filter form] would change to move onto the toolbar". Criterion 8 only requires that the five clients build and pass. Add it, for example: "the Log names each client's hand-built filter forms and what moving each onto `list-toolbar` would change."
  
  **Not a blocker:** the generated list has no filters or search today; I found no search in `src/web/ui.lisp`. So turning the list operation's inputs into filters (criterion 6) is the builder's reading of "the filters they already offer". It's reasonable and stated under Decisions, and it adds filters to every client's generated lists. Criterion 8, which needs the five clients to pass unchanged, protects them. Mention it to the asker in the gate's answer.
- 2026-11-12 01:04  gate A asked of a reviewer
- 2026-11-12 01:04  gate A: changes (reviewer)
  I'm asking for changes again. This is the second time gate A has been asked, and none of the three changes from the first review (Log, 01:03) were made. The record has no entry between that answer and the new request at 01:04. The criteria, the spec text and the `docs/client-api.md` text are word for word what was reviewed before. I checked the working tree's `loops/ui-filters.md` and `spec/ui.md` as well, and they match the packet.
  
  **What's right** (same as the first review)
  - Brief items 1–4 and 6 each have a criterion that names its test or check, and each could be decided by one.
  - The choices the brief asked to be made are made and pinned: push rather than replace, a `:one` popover closes on the choice while a `:several` one stays open, and the date range is left to `ui-search`, with the reason given.
  - Sending every key in every submission and reading a repeated key as an array are sound. A key given once stays a string, so no client's page reads anything new.
  
  **Changes** (all still open from the first review)
  
  1. **The clear (×) and «Reset» links break without JavaScript on a page that remembers its filters.**
     - Criterion 2 and `spec/ui.md` §6 (diff lines 102–105; working tree `spec/ui.md:766`) make them links to "the address without that filter" and "the address with the search and KEEP alone". §8's «Nothing matches» … «Reset» (diff lines 161–162) says the same.
     - On a `:remembers` page, a GET with none of the remembered keys is answered with a 303 to the saved values. So the clear link `/saker` sends the person straight back to `?status=open`, and «Reset» fails the same way.
     - Make these links name every filter's key, with the cleared ones empty (`?q=…&status=&tag=`), in criterion 2, criterion 6 and the spec.
     - Add a test to `ui-filters-tests` of a clear link and a «Reset» on a `:remembers` page.
  
  2. **The «Filters» sheet without JavaScript on a phone is unpinned, and the spec hedges.**
     - The spec (diff lines 138–140; `spec/ui.md:802`) opens the sheet without JavaScript only "where the browser has invoker commands". Criteria 4 and 5 say nothing about a narrow toolbar without JavaScript.
     - The brief requires the page to work with JavaScript off, "usable and tested so". As written, three or more filters on a phone can be unreachable in some browsers, and no check would catch it.
     - State in criterion 4 or 5 how the filters are reached below 40rem without JavaScript. Add that case to the no-JavaScript step of `ui-filters.py`, and make the spec say the same.
  
  3. **Brief item 5's report has no criterion.**
     - The brief asks that "the report says what each [client's hand-built filter form] would change to move onto the toolbar". Criterion 8 only requires the five clients to build and pass.
     - Add, for example: "the Log names each client's hand-built filter forms and what moving each onto `list-toolbar` would change."
  
  **Not a blocker** (repeated for the asker): today the generated list has no filters and no search. Criterion 6 builds them from the list operation's inputs, which is the builder's reading of "the filters they already offer", and it adds filters to every client's generated lists. The asker should hear this in the gate's answer.
- 2026-11-12 01:05  gate A's second request went out before the edits for the first round's changes were saved (the builder's script that made them stopped on a text it did not find); the third request carries them: clear and «Reset» links naming every key (criterion 2, 6, spec §6, a test on a :remembers page), nothing folding without JavaScript (criterion 5, spec §6, the check), and the Log's account of each client's forms (criterion 8)
- 2026-11-12 01:05  gate A asked of a reviewer
- 2026-11-12 01:05  gate A: approve (reviewer)
  **Gate A, third round. I'm approving.** All three changes from the first review are now in the criteria and the spec.
  
  **The three earlier changes**
  1. **The clear (×) and «Reset» links now name every filter's key.**
     - Criterion 2 makes both links name every key, with a cleared one left empty (`/orders?q=…&status=&tags=&tags=rental&dateless=`).
     - It adds a test in `ui-filters-tests` that follows a clear link and a «Reset» on a page that remembers its filters (`:remembers`).
     - Criterion 6's «Nothing matches» uses the same «Reset» link.
     - The spec says the same in §6 (diff lines 101–108) and in the tests' list in §10 (diff lines 201–202).
  2. **Phones without JavaScript are now covered.**
     - Criterion 5 says that without JavaScript nothing folds into the «Filters» button, in any browser. Every filter keeps its button on the sideways-scrolling row, its popover opens through the browser's Popover API, and «Apply» submits.
     - The check pins this at 390 px on `/cards`: all three buttons shown, a popover opened, and «Apply» filtering the list.
     - The spec no longer depends on whether the browser supports invoker commands. §6 says the same as the criterion (diff lines 141–144), and so does `ui-filters.py`'s entry in §10 (diff lines 219–220).
  3. **Brief item 5's report now has a criterion.** Criterion 8 requires the Log to name each client's hand-built filter forms and searches. For each, it must say what moving onto `list-toolbar` would change: the address keys, the markup the client's tests and checks pin, and what the toolbar lacks for it.
  
  **The rest still holds**
  - Every part of the brief maps to a criterion that names a test or a check that could decide it.
  - The choices the brief asked to be made are made and pinned:
    - the address is pushed, not replaced
    - a «one of several» popover closes on the choice; a «several of several» one stays open
    - the date range is left to `ui-search`, and the reason is given
  - Sending every key in every submission, and reading a repeated key as an array, leaves a key given once as a string. So no client's page reads anything new.
  - `docs/client-api.md` matches §6 and §8.
  
  **Not blocking: two small wording gaps the builder could close at gate B**
  - **Popover placement.** Criterion 3 puts the popover "under the button where the window has room, else above it". `spec/ui.md` §6 (diff line 112) says "above it when there is more room there". These differ when neither side has room. Pick one wording for both, so `ui-filters.py` checks one rule.
  - **The page behind the sheet.** Criterion 5 says the page behind does not scroll while the «Filters» sheet is open. §6's phone part (diff lines 130–140) only gets there by pointing to the `dialog` sheet. One added phrase would make it explicit.
  
  **For the asker (repeated from the earlier reviews):** generated list pages have no filters or search today. Criterion 6 builds them from each list operation's inputs, which is the builder's reading of "the filters they already offer". That adds filters to every client's generated lists. Criterion 8 protects the clients, since all five must pass unchanged, but the asker should hear about it in this gate's answer.
- 2026-11-12 01:36  verify 1: failed test
- 2026-11-12 01:47  verify 2: passed build, test, check
- 2026-11-12 01:48  shown (/ui/list-toolbar, /cards, /cards?q=&status=&status=planned&estimate=with&files=, /customers)
- 2026-11-12 01:50  verify 1 failed on two suites that time real waits under the parallel run (files: a-file-is-read-and-sent-a-part-at-a-time, a request record not yet there; waiting: a-wait-outlasts-two-rechecks-in-real-time, woken at 11.00 s); each passed alone with bin/test --only, and round 2 passed unchanged
- 2026-11-12 01:50  the showcase enables the customers module, whose Norwegian catalogue says «Siden finnes ikke» and «Kontroller lenken i e-posten.»; the showcase's own catalogue said «Fant ikke siden» and «Sjekk lenken i e-posten.» for the same texts, which Tun refuses to load, so the showcase now takes the module's words (no check reads them)
- 2026-11-12 01:50  criterion 6's «a client's render-screen method that does not call the next method shows its own screen alone» is pinned outside the core suite, which runs without a client: tun-erp's crm module renders /customers that way (crm/pages.lisp, render-screen :customer-list) and its suite and its _crm check run unchanged against this tree; the core suite pins the toolbar living in the generated screen (render-screen's :toolbar), the orders list's filters and the customers list's search
- 2026-11-12 01:50  an open dialog is kept open through a morph by a hook of Tun's htmx extension (htmx_before_morph_attr), since htmx 4 asks extensions, not DOM listeners, before it changes an attribute in a morph; the clear and «Reset» links carry hx-boost=false, since a boosted link and the script's submit would push the same state twice
- 2026-11-12 01:50  the specimen before (base 415a002) and after, every component at 390 and 1280 px, light and dark: ~/coding/tun-wt/ui-filters-shots/before/ and after/ (bin/ui-shots; list-toolbar is new); the generated list /customers before (base Tun with the showcase's customers module) and after in before/open/ and after/open/; open states (the «Filters» sheet at 390, a floating popover at 390, a popover at 1280, /cards in use) in after/open/; all of them also in the show folder as before-* and after-open-*
- 2026-11-12 02:01  the five clients' bin/test against this tree (commit c73672c, the verified tree; nix develop --override-input tun git+file of the worktree, on clones in the builder's scratch folder, one at a time), unchanged: tunworks/apps/factory 583 passed; tunworks/apps/nixploy-dashboard 1421 passed; tunworks/apps/ferdig 812 passed; kurs 352 passed; tun-erp 854, 72294, 344, 244, 304, 8852, 243, 109900, 90700, 16534 and 26225 passed; no compiler warning, no failure. tun-erp's suite covers its /customers screen (the crm module's render-screen); its browser checks (_crm.py) were not run
- 2026-11-12 02:01  the clients' own filter forms and searches, read-only, and what moving each onto list-toolbar would change: ferdig: /saker filters in a dialog «Filtrer saker» (selects prosjekt, status, kind, urgency, customer_id, waiting; radios visning) applied with «Bruk», cleared by «Nullstill» to /saker?visning=…, remembered (:remembers); moving gives one button per filter with the same keys (each a :one filter with «Alle»), visning stays outside the toolbar or as a :one filter, sort and retning as :keep, and its tests (project-tests.lisp 260-279, 341-349) and checks (filters-kept.py, waiting-filter.py) that pin dialog#filter, «Nullstill filtrene», the count badge and «Bruk» are rewritten; /sok's live search stays its own; factory and nixploy-dashboard: no list filters from the address, nothing to move; kurs: /watchlist «Find a share» looks a share up rather than filtering a list, and its checks press «Søk»; it may stay as it is, or become a toolbar with a search alone (which has no submit button with scripts, so checks/watchlist.py would press Enter); tun-erp: about ten hand-built GET forms (/orders, /invoices, /work, /staff, /outbox, /stock, /catalogue, /rental, /crm, /stock/shortages) of selects with an «All…» empty option and a «Filter» or «Show» button, and a link row on /inquiries; their keys carry over as :one filters, q as the search, but the dates (from, to on /orders, /work, /rental, /reports) wait for ui-search's date range, defaults that are not «All» (catalogue status=active, rental days, shortages days) need the page to give the value, and the checks that select form[data-part=…] select[name=…] and press button[type=submit] would choose in the popover instead; /inquiries' links «New / Taken / Undated / All» would become a :one state filter and a toggle, which also fixes «All» naming no key under :remembers
- 2026-11-12 02:01  gate B asked of a reviewer
- 2026-11-12 02:03  gate B: changes (reviewer)
  I'm asking for changes. Most of the change works and is well tested; two things need fixing before deploy.
  
  **What's right**
  - **Verification:** both rounds are explained. Round 1 failed on two timing-sensitive suites under the parallel run; each passed alone, and round 2 passed build, test and check unchanged. All 57 results in `checks/ui-filters.json` pass, and the five clients pass their own `bin/test` against this tree.
  - **Criteria 1–5 are met and measured in a browser:**
    - At 1280 px the search and the three filters stand on one row, their tops all at 108.
    - A choice changes the address and the list without loading the page: the marker on `window` survives.
    - A «one of several» popover closes with the focus on its button; a «several of several» one stays open with the focus on the box just ticked.
    - Back goes one choice back each time, then off the list.
    - The «Filters» sheet's box, dim and page hold are right at 390, 360 and 320 px, in light and dark.
    - The floating popover stays inside the window at 320 px.
    - Without JavaScript, the three filters and «Apply» show at 390 px, and «Apply» filters the list.
  - **The clear and «Reset» links** name every key (pinned at `tests/ui-filters-tests.lisp:1809–1816`), and a clear on a page that remembers its filters is tested.
  - **The rules from the brief are kept:** no `setTimeout`, no `pointerdown`, events delegated through `data-tun-*`, and `tunPopoverOpen` is used. The sheet is the existing `dialog`, whose invoker-command fallback in `interaction.lisp:227` covers browsers without `commandfor`. The morph hook in `kit.lisp` only touches a dialog's `open`, and only `list-toolbar` uses `innerMorph`.
  - **The screenshots** show both widths: in use, the open popover, the open sheet, the specimen's floating popover, and `/customers`.
  
  **Changes**
  
  1. **Putting a filter into use moves the buttons beside it, which the brief rules out.**
     - The brief says: «no shift of the toolbar when a filter goes into use beyond the button's own width»; criterion 2 says «Choosing moves nothing».
     - The search can grow to fill the row and shrink back (`toolbar.lisp`, diff line 1238: `flex: 1 1 12rem; max-width: 24rem`). As a button widens to show its value, and as «Reset» appears, the search gives up the room, so every button between the search and the chosen one slides left.
     - The screenshots show it. With one filter in use (`after-open-cards-popover-1280-dark.png`), the search ends at x≈680 and «Status» starts at 688. With two in use (`desktop-cards-q-status-…png`), the search ends at ≈550 and «Status» starts at 558: a 130 px jump for a button the person may press next.
     - `ui-filters.py` only measures the row's height and the list's top, so it can't catch this.
     - Fix: give the search a width that doesn't depend on its neighbours (for example `flex: 0 1 24rem`, with no growing), so a filter widens only itself and what comes after it.
     - Add to the desktop step of `ui-filters.py` (around diff line 125) a check that the search's right edge and every filter button's left edge before the chosen one stay put to 1 px.
  
  2. **One part of criterion 6 has no test in the core suite, though `spec/ui.md` §10 says it does.**
     - Criterion 6 requires that a client's `render-screen` method that doesn't call the next method shows its own screen alone, with no toolbar. §10 (diff line 637) lists «a client's screen method without it» under `tests/ui-filters-tests.lisp`, but that file has no such test.
     - The Log (01:50) says the core suite «runs without a client». But the suite already uses the test client's orders and customers, and the test client has exactly this override: `tests/client/screens.lisp:28`, `customer-list-feature` on `:customer-list`, which never calls the next method.
     - Add a test to `ui-filters-tests` that turns that feature on and checks `/customers?query=…` shows the client's table with no `tun-list-toolbar`. Otherwise §10 promises something nothing checks.
  
  **Not blocking**
  - `ui-filters.py` checks that Escape closes the sheet, but not the close button or a press on the dim. The `dialog` component's own checks cover those.
  - For the asker: the generated lists now get filters from their list operation's inputs, so every client's generated lists gain a toolbar. All five clients still pass unchanged.
- 2026-11-12 02:06  gate B 1's changes: the search keeps its width from 40rem (flex: 0 1 24rem, no growing), so a filter put into use widens only its own button and what follows it; ui-filters.py now measures the search's right edge and every button's left edge up to the chosen one staying put to 1px, after a choice of one and after two of several; a new test, a-clients-own-list-screen-shows-no-toolbar, runs an application whose feature renders /customers itself without calling the next method and finds the client's table and no toolbar, so criterion 6 is pinned in the core suite too (this replaces the earlier entry that said it was pinned only by tun-erp); the open-state pictures are taken again
- 2026-11-12 02:15  verify 3: passed build, test, check
- 2026-11-12 02:16  shown (/ui/list-toolbar, /cards, /cards?q=&status=&status=planned&estimate=with&files=, /customers)
- 2026-11-12 02:16  the five clients' runs above were on c73672c; this round changes only the toolbar's CSS (the search's width), Tun's own test and its check, and no client uses list-toolbar, so they were not run again
- 2026-11-12 02:16  gate B asked of a reviewer
- 2026-11-12 02:17  gate B: changes (reviewer)
  Gate B round 2: I've confirmed both of round 1's fixes and the new checks. The fix to the search width causes a new problem, which shows in the in-use screenshot at 1280 px.
  
  **What's right**
  - **Verification:** round 3 passed build, test and check. No result in `checks/ui-filters.json` failed.
  - **Round 1's first change is fixed:** the search no longer grows (`toolbar.lisp`, diff line 1247: `flex: 0 1 24rem`). `ui-filters.py` now checks that the search's right edge and the buttons' left edges stay put, after one «one of several» choice and after two «several of several» ticks (diff lines 130–132 and 150–153). Both pass with the same edges before and after: `[680, 688, 790]`.
  - **Round 1's second change is fixed:** `a-clients-own-list-screen-shows-no-toolbar` (diff lines 2010–2028) runs an application whose `render-screen` doesn't call the next method. It finds the client's table and no `tun-list-toolbar`, so criterion 6 and §10 now agree.
  - Everything else round 1 found right still holds. Only the CSS, the check and one test changed since the clients' runs, and no client uses `list-toolbar`.
  
  **Changes**
  
  1. **With two filters in use at 1280 px, the filters drop to a second row and push the list down.** The brief and criterion 2 rule this out.
     - The brief asks for «one row at 1280 px» and «the row below does not move vertically». Criterion 2 asks that putting a filter into use leave «the row's height and the top of the list under it where they were, to 1px».
     - `shots/desktop-cards-q-status-status-planned-estimate-with-files.png` shows the state the loop itself showed (`/cards?…status=planned&estimate=with…`). The search stands alone on the first row (top 108). «Status: Planned ×», «Estimate: With an estimate ×», «With files» and «Reset» wrap onto a second row (top ≈152). The table header falls from ≈180 to ≈224.
     - This comes from the round-1 fix. The search now keeps all 24rem, which leaves the filters about 550 px. They can wrap (`toolbar.lisp`, diff line 1250: `flex-wrap: wrap`), so they wrap instead of the search giving up room.
     - The check missed it because its in-use states are narrow: one «Estimate» choice alone, then «Status: 2» alone.
     - **Fix:** keep the filters on one row at 1280 px with two or more in use. For example, don't let the filters group wrap from 40rem, and let the search shrink (with a sensible minimum) only when the row would otherwise overflow. While there is room, the search and the buttons before the chosen one still don't move.
     - **Add to the desktop step of `ui-filters.py`:** with `status=planned`, `estimate=with` and `files=true` in use at 1280 px, the search and every button and «Reset» have their tops within 1px, and the toolbar's height and the list's top are as with none in use.
  
  **Not blocking**
  - The close button and a press on the dim are still left to the `dialog` component's own checks.
  - For the asker: every client's generated lists now get a toolbar built from their list operation's inputs. All five clients still pass unchanged.
- 2026-11-12 02:19  gate B 2's change: from 40rem the toolbar's row never wraps; the search keeps 24rem while there is room and shrinks first when the row is full (flex-shrink 1000 against the filters' 1, to at least 12rem), then the filters scroll in their own box; with three filters in use and «Reset» at 1280 px on /cards everything stands on the search's row, the toolbar's height and the list's top as with none in use, the filters fitting their box, now measured in ui-filters.py; spec §6 «The row» and criterion 2 say so; the pictures (after/open/cards-1280-three-*.png, the specimen's list-toolbar) are taken again
- 2026-11-12 02:28  verify 4: failed test
- 2026-11-12 02:29  verify 4 failed on group-commit's gc-queued-writers-share-one-commit-and-wait-for-it (a writer's timing under the parallel run, in the store, which this loop does not touch); it passed alone with bin/test --only group-commit; verify again unchanged
- 2026-11-12 02:39  verify 5: passed build, test, check
- 2026-11-12 02:39  shown (/ui/list-toolbar, /cards, /cards?q=&status=&status=planned&estimate=with&files=&files=true, /customers)
- 2026-11-12 02:39  gate B asked of a reviewer
- 2026-11-12 02:40  gate B: approve (reviewer)
  I'm approving at gate B round 3. Round 2's one change is fixed, every verify step passed, and nothing new needs changing.
  
  **Round 2's change: two or more filters in use at 1280 px dropped to a second row. Now fixed.**
  - **The row can't wrap from 40rem any more.** The search keeps 24rem while there is room. When the row is full it gives up its space first, down to 12rem, and only then do the filters scroll in their own box (`toolbar.lisp`, diff lines 1265–1272: `flex-wrap: nowrap`, search `flex: 0 1000 24rem; min-width: 12rem`, filters `flex: 0 1 auto`). It shrinks 1000 times as readily as the filters, so it takes nearly all of the shrinking until it reaches 12rem. The comment explains why.
  - **The state that broke before now holds.** `desktop-cards-q-status-…-files-true.png` and `after-open-cards-1280-three-light.png` show `/cards` with all three filters in use and «Reset»: everything is on the search's row, and the table header stays at ≈180 as with no filter in use.
  - **The check now covers it** (`ui-filters.py`, diff lines 172–184):
    - every top is at 108 and «Reset» is centred on the search's row;
    - the toolbar's height (36) and the list's top (160) are the same as with no filter in use;
    - the filters fit their box (634 wide, nothing hidden) and the page doesn't scroll sideways.
  - **Round 1's fix still holds.** After one «one of several» choice and after two «several of several» ticks, the search's right edge and the buttons' left edges stay put: `[680, 688, 790] → [680, 688, 790]`.
  - **The spec and criterion 2 say the same.** §6 «The row» (diff lines 543–548) gives the same order as criterion 2: the search keeps 24rem, narrows to 12rem when the row is full, then the filters scroll. This is the fix the round-2 review asked for. When the row is full, the buttons before the chosen one can slide left as the search narrows. That's the trade-off accepted at round 2 so the row never wraps, and the spec says so.
  
  **The rest still holds from rounds 1 and 2**
  - **Verification:** verify 5 passed build, test and check. Verify 4 failed on one timing-sensitive store test this loop doesn't touch; it passed alone and then again unchanged. All 61 results in `checks/ui-filters.json` pass.
  - **Phones:** the «Filters» sheet's box, dim, page hold and focus are right at 390, 360 and 320 px. A filter's popover is a floating sheet inside the window at all three widths. Without JavaScript at 390 px, the three filters and «Apply» show, and «Apply» filters the list.
  - **Screenshots:** the phone shot shows the search, «Filters 3» and «Reset» on `/cards`. The specimen shows each kind in use and «Reset».
  - **Criterion 6 is pinned in the core suite:** `a-clients-own-list-screen-shows-no-toolbar` finds the client's own table and no toolbar.
  - **The clients:** this round changed only the toolbar's CSS, the check and the pictures. No client uses `list-toolbar`, so the five clients' passing runs on c73672c still stand.
  
  **Not blocking**
  - The close button and a press on the dim are still left to the `dialog` component's own checks; `ui-filters.py` only checks Escape.
  - For the asker: every client's generated lists now get a toolbar built from their list operation's inputs. All five clients still pass unchanged.
