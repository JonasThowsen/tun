# Every table shows dense rows on a phone and keeps its columns; a row that leads somewhere answers the press

- loop: ui-lists
- mode: reviewed
- stage: ship
- base: 99cd40e880d06a15b0c67957fd25dae0c2124e97
- item: sak_1ysmxc6qqxdm6hr6
- estimate: 1h30m 2h15m 4h
- like: tun/ui-filters tun/ui-header
- tags: kind:ui core module:ui
- verified: 6a39ed1637bfc799b07ec681b30bb096dc0eeb18
- shown: 6a39ed1637bfc799b07ec681b30bb096dc0eeb18

## Brief

Ferdig sak_1ysmxc6qqxdm6hr6, brought by the factory's orchestrator on
2026-11-12, the fifth loop of the work on Tun's component library after
`ui-look` (core 2.25.0), `ui-sheets` (2.26.0), `ui-header` (2.27.0) and
`ui-filters` (2.28.0). Jonas, 2026-11-11: he has polished the admin UI of
another application of his for two weeks and wants the best of it
carried into Tun's component library, «to make the UI component Library
of Tun superb». The source is the owner's rules for an admin
application, 2026-11; code does not carry over, rules, values, component
anatomy, behaviour and the tests that pin them do.

Today `table` turns each row into a card on a phone, its label and value
stacked per cell, so eight records fill about three screens. Jonas
decided on 2026-11-11, for the choice «every Tun table shows dense rows on
a phone, cards go»: rows as in his admin application, for every Tun
table, with no option to keep cards. The orchestrator's brief, in short:

1. **Dense rows on a phone, columns kept**, below the table's own width
   where its columns fit (a container query): either the leading column
   on a first line with the status or amount at the right and the rest on
   a muted second line, or the table scrolling sideways in its own box;
   take what the source settled on and say which. No page-level
   horizontal scroll at 390, 360 and 320 px; the rows' edges in line
   with the header and the toolbar; numbers right-aligned and tabular; a
   long name truncated or wrapped to at most two lines; eight rows of the
   showcase's list in one phone screen, the height pinned.
2. **Every table**: the card layout's CSS and markup go; `table`'s call
   shape stays and options that only made sense for cards are accepted;
   a sensible default so every client's call renders a good row
   unchanged, with a column option where the default is not enough.
3. **A row that leads somewhere**: the whole row is the target, without
   JavaScript and for the keyboard (one link per row, the focus ring on
   the row), pressed at once on touch, hover only under `(hover: hover)`,
   links and buttons inside the row working without triggering it.
4. **The first rows with the page**, «load more» or pagination one way
   per list below the rows, the rows staying with the loading sign while
   a filter or sort request runs; sorting by a header keeps the address
   as the state, works without scripts, and marks the sorted column
   without a change of weight.
5. **Empty and filtered-empty** keep ui-filters' one empty state.
6. The specimen shows a table with several kinds of column (text, badge,
   money, date, an action) at 390 and 1280 px, light and dark, before and
   after, and the showcase's `/cards`, `/customers` and `/items` on a
   phone; a browser check measures the widths, the heights, the edges,
   the row's link, pressed and focus, an inner link and the sort.
7. A small one from the header loop's pictures: a page title of one very
   long word breaks mid-word without a hyphen; `hyphens: auto` with
   `overflow-wrap: anywhere` as the fallback.

Out of scope: search on Ctrl K and the date, time and money fields
(`ui-search`), moving clients onto `list-toolbar`. The five clients
(factory, nixploy-dashboard, ferdig, kurs, tun-erp) must compile and pass
unchanged and are not touched; the report says which of their browser
checks pin the cards and which tables want a column option.

Mode: reviewed. A core change, a minor version.

## Criteria

1. **No cards.** A `table`'s cell holds its content, marked as its value
   (`tun-table-value`), and nothing else: no column label is written
   into it, no chevron is added to the row's link, and the stylesheet has
   no rule that makes a row, a cell or the table body a block or a flex
   box on a narrow screen. The first cell's value stands in one part
   (`tun-table-lead`) and the empty row's text in one
   (`tun-table-empty-text`). (`ui-lists-tests`)
2. **The columns stay, in a box that scrolls.** At 390, 360 and 320 px on
   the specimen's `/ui/table` and the showcase's `/cards`, the page does
   not scroll sideways; every table's header row and data rows are table
   rows (`display: table-row`) with every column but those given
   `:narrow nil`; where the columns do not fit (the specimen's list of
   six columns) the table's box scrolls sideways (its `scrollWidth` above
   its `clientWidth`) and scrolling it brings the amount column into
   sight; at 1280 px every column of that list is in sight without
   scrolling. The box has edge shadows: its background holds the two
   covers that scroll with the rows (`local`) and the two shadows that do
   not (`scroll`). (`ui-lists.py`, `ui-lists-tests`)
3. **One panel on a phone.** Below 36rem of the table's own width its box
   has a 1px edge in `--border`, `--radius-lg` corners, `--shadow-panel`
   and the `--card` ground; at 390 px on `/cards` the box's left and
   right edges are within 1px of the toolbar's and of the page header's.
   From 36rem the box has no edge, as before. (`ui-lists.py`, CSS in
   `ui-lists-tests`; `ui-look-tests`' panel test stays green)
4. **Dense rows.** At 390 px on a phone (coarse pointer) every cell but
   the first stays on one line; a row that leads somewhere is 44 to 46px
   high when its lead is one line; eight rows of `/cards` measure at most
   448px together, about half of an 844px screen (the cards they replace
   measured more than 900px); at 1280 px with a mouse a row
   is 36 to 38px high. In the specimen's list every amount cell's right
   edge is within 1px of the others' and of its header's, and the
   amounts' `font-variant-numeric` is `tabular-nums`. (`ui-lists.py`)
5. **The lead.** Below 36rem the first column's text wraps to at most
   two lines (its height at most two line heights), the rest cut with
   «…», and its width is at most half of the table's box and 16rem, on
   the specimen and on `/cards`, whose «Urgent: the customer cannot sign
   in» wraps; that row keeps the
   second column's left edge inside the box at 320 px. (`ui-lists.py`,
   CSS in `ui-lists-tests`)
6. **The old options.** `:narrow nil` still leaves its column out below
   36rem (its header and cells `display: none`) and keeps it from 36rem;
   every option `table` and its columns took before is accepted; a column
   option it never took is still refused. (`ui-lists-tests`;
   `combobox-find.py` stays green)
7. **A row that leads somewhere is one target.** Each row with a link
   has exactly one link (`tun-table-row-link`), in its first cell, the
   first cell's text; at 390 and 1280 px a point near the row's right
   edge (`elementFromPoint`) belongs to that link, and a tap there opens
   the row's page; without JavaScript a tap on the row's last cell opens
   it too. Tabbing reaches the row's link, and the focused row shows the
   inset ring (`--focus-ring-inset`, a box-shadow on the link's box over
   the row). (`ui-lists.py`, `ui-lists-tests`)
8. **Pressed, hover.** The row's ground while its link is pressed is
   `--pressed` with no transition into it (`transition-duration: 0s`,
   measured in the browser from a held pointer); pressing a link or a
   button inside the row leaves the row's ground as it was; the row's
   hover rule is inside `(hover: hover)`. (`ui-lists.py`; the CSS in
   `ui-lists-tests`; `ui-look-tests` stays green)
9. **What is inside works as itself.** In the specimen's list, whose
   customer cells are links to the customer and whose last column is a
   row's «More actions» `dropdown-menu`: a click on a customer's link
   follows that link and not the row's; a click on the menu's button
   opens the menu, the address unchanged, and a click on its «Remind»
   item follows the item's link and not the row's. (`ui-lists.py`)
10. **Sorting keeps the address.** The showcase's `/cards` sorts by its
    «Title» and «Estimate» headers: a header's link holds the toolbar's
    filters and the sort, the toolbar keeps the sort as hidden fields;
    following it with JavaScript changes the address to one holding the
    sort and the filters and the rows to the sorted order; without
    JavaScript the same link sorts. While a sort's answer, and then a
    filter's (the toolbar's «With files» toggle), is held back by 1.5 s,
    the rows stay in the page with the table's height unchanged and the
    loading sign shows, and the answer then replaces them. The sorted
    header has the font weight of the others. (`ui-lists.py`)
11. **The rows with the page.** The generated list's page (the test
    client's `/customers`) and a `table` in a client's page hold their
    rows in the page's first answer, with no element that loads a part
    after it (`hx-trigger="load"` or `revealed`) and no skeleton.
    (`ui-lists-tests`)
12. **Empty.** A table of no rows says its EMPTY text in one row across
    its columns, the text inside the box's visible part at 320 px; a
    generated list filtered to nothing keeps ui-filters' «Nothing
    matches» with «Reset» under the toolbar. (`ui-lists.py`;
    `ui-filters-tests` stays green)
13. **The specimen** has a table with a text, a badge, a date, a money
    and an action column and a link on each row, shown at 390 and 1280
    px, light and dark, before and after, with `/cards`, `/customers` and
    `/items` at 390 px. (the pictures)
14. **A page title's long word** is hyphenated: `page-header`'s title has
    `hyphens: auto` and keeps `overflow-wrap: anywhere`. (`ui-lists-tests`;
    `ui-header.py` stays green)
15. **One way to more.** `spec/ui.md` §6 says a page that shows a list a
    part at a time gives one way to the rest under the rows
    (`pagination` or one «load more» link); `pagination`'s place is the
    page's, as before; the generated list shows its first 100 records
    and does not page (§8, and §9 «Not yet»). (the spec; `ui-lists-tests`
    for the generated list's one answer)
16. **The clients.** Factory, nixploy-dashboard, ferdig, kurs and
    tun-erp compile and pass their own `bin/test` against this tree with
    no change in their repositories; the final report names, per client,
    the browser checks in its `checks/` that pin the cards on a phone
    (selectors, labels, heights) and what each needs, and the tables
    that read badly on a phone by default with the column order or
    `:narrow nil` that would fix them. (the clients' runs; the report)

## Decisions

- **The rows scroll sideways in their own box; no second line.** The
  source settled on that: every column stays on a phone, the table
  scrolls sideways in its own region with a soft shadow at an edge with
  more beyond it, the columns that matter first and the cells closer
  together, and a list of related records that must read in one screen
  is a list of link rows, not a table. Jonas's choice was «rows as in his
  admin application». A two-line row would need Tun to guess what goes
  where for every client's table; scrolling keeps each column where its
  header is, so every client's call renders unchanged.
- **No sticky first column.** A sticky cell is positioned, so it becomes
  the box of the row's link's cover, which would then cover only the
  first cell: the row would stop being one target. The source does not
  stick it either; the lead's width is capped instead, so the next
  columns start in sight.
- **One panel on a phone, as before no frame from 36rem.** The cards were
  panels on a phone (§2.1), and the source frames its tables; one panel
  holding the rows gives the scrolling box its edge and lines up with the
  toolbar. The wide look does not change, since no one asked for it.
- **Phone: 36rem of the table's own width**, the cards' threshold, so
  `:narrow nil` hides the same columns at the same widths as before.
- **No new column option.** The default, every column in its order with
  the first leading, renders every existing call well; a page that wants
  a phone to see a column first puts it earlier, and `:narrow nil` leaves
  out what a phone can do without. `:narrow` keeps its meaning (it was
  the one option made for the cards).
- **The lead: two lines, then «…»** (`line-clamp`), at most half the box
  and 16rem: the source's names wrap to two lines rather than push the
  other columns out («never a table whose one long name pushes the other
  columns off a phone»). Up to that it keeps its own width
  (`width: max-content`): left to the table, a lead was squeezed to its
  longest word, «10482» broken in two and «The expo…», while the other
  columns kept theirs; scrolling the box is the better answer.
- **Eight rows pinned at 448px, not 368px.** 368px holds only for eight
  leads of one line; `/cards`' first eight titles include ones longer
  than half the box, which wrap to two lines (380px measured in the
  last round, 440px while the table still squeezed its lead), so the
  pin is 448px, about half of
  an 844px screen, with a row of one line held at 44 to 46px. The full text is still the link's text for a screen
  reader.
- **The pressed row is the row whose link is pressed**
  (`:has(.tun-table-row-link:active)`), not any `:active` row: pressing a
  button inside a row made the whole row look pressed.
- **The edge shadows are background layers** of the scrolling box, as in
  the source: no script, light and dark through the tokens, and nothing
  shows on a box that does not scroll.
- **No `tabindex` on the box.** Browsers now make a scrolling box without
  a focusable child focusable themselves, and a stop on every table, also
  where it does not scroll, would add a tab stop to every client's page.
- **A cell's value keeps its mark** (`tun-table-value`, a span with no
  style of its own): tun-erp's overview tests read a table's values by
  it, and kurs's watchlist check selects by it, so dropping it would
  fail a client's suite that must pass unchanged. Only the label beside
  it, which was the cards', goes.
- **The test that pinned the cards' labels** (`ui-data-tests`'
  `every-table-cell-carries-its-column-header-as-a-label`) pinned the
  behaviour this loop removes; it is replaced by tests of the cells
  without labels, not weakened.
- **The generated list does not page.** It shows the first 100 records
  of its operation, as before; paging it means a cursor in its address
  and in every list operation, a loop of its own, so §9 names it. The
  rule for one way to more is §6's, for a page that pages.
- **Sorting is shown on `/cards`**, the showcase's list with a toolbar,
  so the check can see a sort keep the filters. The generated list does
  not sort; it was not asked for.
- **No dimming of the rows while loading.** The source dims kept rows;
  Tun's loading sign is the one sign (§4.1), and htmx keeps the rows until
  the answer is swapped in.
- **The clients** (criterion 16), against this branch with their
  repositories untouched: factory, nixploy-dashboard, ferdig, kurs and
  tun-erp compile and pass their `bin/test`. Their browser checks that
  pin the cards on a phone: kurs's `checks/watchlist.py` reads «a card's
  columns» from `.tun-table-label` (it reads the headers now, `thead
  th`); tun-erp's `checks/_rental.py` wants the rental grid's header row
  hidden on a phone («each item is a card»; it now shows, the grid
  scrolling in its box). Pictures of their lists at 390 px are in
  `.build/loop/ui-lists/pictures/clients/` of this worktree; tables
  whose phone row
  wants a column moved first or `:narrow nil` are named in the loop's
  report to the orchestrator.
- **The pictures** (criterion 13) are in this worktree's
  `.build/loop/ui-lists/pictures/`: `before/` and `after/` hold the
  specimen's `table` and `page-header` at 390 and 1280 px, light and
  dark (`bin/ui-shots`, before on `origin/main`), and `showcase/` in each
  the showcase's `/cards`, `/customers` and `/items` at 390 px and
  `/cards` at 1280 px, light and dark.
- **Markdown's tables stay as they are** (`markdown`, §6.2): they are
  text in a comment, not a list of records, and have their own spec.
- **Core 2.29.0**: the table's look on a phone for every client; no call
  shape changes.

## Log

- 2026-11-12 02:46  started, reviewed
- 2026-11-12 02:46  estimated 1h30m 2h15m 4h at brief, like tun/ui-filters tun/ui-header
- 2026-11-12 02:51  gate A asked of a reviewer
- 2026-11-12 02:52  gate A: changes (reviewer)
  I'm asking for changes at gate A. The main approach is sound, but brief point 4 has a rule in the spec with no criterion and no implementation behind it. Two other parts of the brief aren't fully covered by the criteria either.
  
  **What's right**
  - **Scroll instead of a two-line row:** the brief left this choice to the builder ("take what the source settled on and say which"). The Decision names the choice and gives the reason, so it didn't need to go back to the asker.
  - **Coverage:** criteria 1–8 and 11–14 cover brief points 1, 2, 3, 5, 6 and 7. Each one names measurable values (px heights, `display`, `elementFromPoint`, `transition-duration`, `hyphens`) and the check or test that will decide it.
  - **No new column option:** the brief says a column option only "where the default is not enough". With every column kept, the Decision argues that case doesn't come up, and `:narrow` keeps its meaning.
  - **Spec matches criteria:** the spec change (`spec/ui.md` §2.1, §6 `table`, `page-header`, §8, the tests list) agrees with the criteria. `:wrap` and the toolbar's `:keep` already exist (`src/web/ui/data.lisp:26`, `spec/ui.md:782`), so the spec isn't adding options. The 36rem threshold, `:narrow nil` and the replaced card-label test are handled honestly.
  
  **Changes**
  1. **"Load more" or pagination, one way per list below the rows (brief point 4), has no criterion.** The spec states it as a rule (`spec/ui.md:760-762`: "A list with more rows than it shows has one way to the rest, under the rows"). But the generated list is specified as showing "its first 100 records" (`spec/ui.md:1522`) and gives no way to the rest. Its code caps at 100 (`src/web/ui.lisp:1701`), and there is no «load more» link anywhere in Tun. As written, the spec's own generated list breaks the new rule.
     - **Option A:** add a criterion that a generated list with more than 100 records shows `pagination` (or one «load more» link) below the rows, and that following it shows the next rows.
     - **Option B:** if paging the generated list is out of scope, say so under Decisions and change the rule at §6 so it doesn't promise what the generated list doesn't do.
  2. **Buttons inside a row (brief point 3: "links and buttons inside the row working without triggering it").** Criterion 9 only tests a click on a link («Remind»). Criterion 8 covers pressing a button, but not what clicking it does. Add a button to the specimen's row, and to criterion 9 a click on it that runs the button and doesn't follow the row's link.
  3. **Rows kept while a filter request runs (brief point 4: "while a filter or sort request runs").** Criterion 10 checks only a slow sort. Either add a slow filter request (rows stay, height unchanged, loading sign shows), or name the existing ui-filters check that already proves it.
  4. **The brief's conditions on the five client apps (factory, nixploy-dashboard, ferdig, kurs, tun-erp).** The brief says they "must compile and pass unchanged and are not touched", and that the report names which of their browser checks pin the cards and which tables want a column option. No criterion holds any of this. Add one: the five clients compile and their tests pass with no change in their repositories, and the report lists the card-pinning checks and the tables.
- 2026-11-12 02:53  gate A asked of a reviewer
- 2026-11-12 02:54  gate A: approve (reviewer)
  I approve this gate. All four changes from the first gate A review are made, and the criteria now cover the whole brief.
  
  **The earlier changes**
  1. **«Load more» or pagination.** The builder chose the second option. The §6 rule now applies only to "a page that shows a list a part at a time" (diff.patch:85-86). §8 says the generated list shows its first 100 records and does not page yet (diff.patch:119-120), and §9 «Not yet» names it (diff.patch:130). There is a Decision for it and criterion 15 holds it. The spec no longer promises something its own generated list doesn't do.
  2. **Buttons inside a row.** Criterion 9 now clicks the «More actions» `dropdown-menu` button. The menu opens and the address stays the same. A click on the item then follows the item's own link, not the row's.
  3. **Rows kept while a filter runs.** Criterion 10 now holds back the «With files» filter's answer by 1.5 s, as well as the sort's.
  4. **The five clients.** Criterion 16 covers them: they must compile and pass their own `bin/test` with no change to their repositories. The report must name the checks that pin the cards and the tables that need a column order or `:narrow nil`.
  
  **The rest**
  - **Brief to criteria:** each point of the brief maps to a criterion.
  
    | Brief point | Criteria |
    |---|---|
    | 1 | 2–5 |
    | 2 | 1, 6 |
    | 3 | 7–9 |
    | 4 | 10, 11, 15 |
    | 5 | 12 |
    | 6 | 13 and the check in the tests list |
    | 7 | 14 |
  
    Nothing outside the brief is added.
  - **Testable:** every criterion names something a check or test can measure (px heights, `display`, `elementFromPoint`, `scrollWidth`, `transition-duration`, `font-variant-numeric`, `hyphens`) and names the test or check that decides it.
  - **Spec matches criteria:** the spec's numbers agree with the criteria.
    - 36rem threshold, 2.25rem rows (36px), 2.75rem on a coarse pointer (44px).
    - The panel on `--card`, the lead capped at half the box and 16rem.
    - The pressed row only while its link is pressed, hover only where a pointer hovers.
    - The sorted header at the others' weight, the empty row in sight.
    - The §2.1 panels line now says "a table on a phone".
  - **Decisions:** the brief left the choice between scrolling and a second line to the builder ("take what the source settled on and say which"). Jonas's own decision, no cards for any table, is kept. Not adding a column option and not sticking the first column are reasoned choices within the brief. None of them should have gone back to the asker.
  
  **Two things to settle when the check is written (gate B), not reasons to block now**
  - **Criterion 7:** "a point near the row's right edge" belongs to the row's link. That can't be true in the specimen's list:
    - its last cell is the menu button, which criterion 9 says must not follow the row;
    - at 390 px that list scrolls, so the row's right edge is outside the box.
  
    The check should test a row whose right edge is in sight (on `/cards`, or the box's visible right edge) and say which one.
  - **Criteria 4 and 5:** criterion 4 says a row that leads somewhere is 44–46px, but a lead wrapped to two lines (criterion 5's «Hansen Building…») can be taller. The check should measure the height on rows whose lead is one line, and the 368px total on `/cards` as written.
- 2026-11-12 03:19  verify 1: passed build, test, check
- 2026-11-12 03:19  shown (/ui/table, /cards, /customers, /items)
- 2026-11-12 03:42  verify 2: passed build, test, check
- 2026-11-12 03:57  shown (/ui/table, /cards, /customers, /items)
- 2026-11-12 03:57  gate B asked of a reviewer
- 2026-11-12 03:58  gate B: changes (reviewer)
  I'm asking for changes at gate B. The change does what the brief asks and all verify steps passed. The problems are in the record and the evidence, not the behaviour, and each fix is small.
  
  **What's right**
  - **Verification:** build, test and check all passed in round 2. All results in `checks/ui-lists.json` pass.
  - **Brief:** the screenshots show the cards are gone.
    - **Phone, `/cards`:** dense rows in one panel whose edges line up with the toolbar and the header (16/374 at 390 px). Rows are 44.5–45 px, eight of them take 380 px, and a long title wraps to two lines.
    - **Phone, specimen:** the six columns scroll in their own box with the edge shadow.
    - **Desktop:** looks as before.
  - **Code (`src/web/ui/data.lisp`):**
    - The card CSS and the label/chevron markup are removed, and `tun-table-value` stays for the clients.
    - The pressed rule now applies only while the row's own link is pressed (`:has(.tun-table-row-link:active)`), and `textarea` is added to the controls that stay above the row's link.
    - The empty text is sticky so it stays in sight in a scrolling box.
  - **Tests:** they pin each CSS rule and would fail without the change. The new check covers the row as one target, pressing it, the focus ring, the inner link and menu, sorting with filters, rows held during a slow sort or filter, and the no-JavaScript paths. The card-label test is replaced, not weakened.
  - **Clients and version:** `:narrow nil` keeps its meaning, the call shape is unchanged, and core goes to 2.29.0.
  
  **Changes**
  1. **The spec contradicts the criterion (`spec/ui.md`, tests list, diff.patch:609).** It says "eight rows of `/cards` at most 368px high", but criterion 4 and the check (`ui-lists.py:184`) use 448. Make it 448. The Decision «Eight rows pinned at 448px» also says "440px measured", but the check measured 380. Correct that number or drop it.
  2. **The browser check for criterion 5 doesn't test a long lead.** `specimen_on_a_phone` measures the lead and `secondLeft` on the specimen's first table. Its lead is the order number «10482» (42 px, one line), so these checks pass whether or not the clamp exists. «Hansen Building and Construction Ltd» is now in the second column, not the lead, so the criterion's Hansen row is never measured as a lead.
     - **Fix:** in `cards_on_a_phone`, which has leads that wrap («Urgent: the customer cannot sign in»), check that `leadLines` ≤ 2 and the lead's width ≤ min(256, half the box). Also check that the second column's left edge is inside the box at 320 px.
     - **Alternatively:** give the specimen a row whose lead is long.
  3. **Criterion 13's pictures are missing from the packet.** It asks for the specimen at 390 and 1280 px, light and dark, before and after. `shots/` has only light "after" pictures. I couldn't open the folder the Decisions name (`~/coding/tun-wt/ui-lists-shots/`); it's outside what I can access. Add the dark and "before" pictures where a reviewer can see them, or point to where they are.
- 2026-11-12 04:09  verify 3: passed build, test, check
- 2026-11-12 04:09  shown (/ui/table, /cards, /customers, /items)
- 2026-11-12 04:09  gate B asked of a reviewer
- 2026-11-12 04:10  gate B: approve (reviewer)
  I approve gate B. The last review asked for three changes, and all three are made. The build, test and check steps all passed in verify round 3, and every result in `checks/ui-lists.json` passes.
  
  **The three earlier changes**
  1. **The spec now says 448px, as criterion 4 does.** The spec's tests list (diff.patch:620) and the check (`ui-lists.py`, diff.patch:187) both use 448. The Decision now says "380px measured in the last round, 440px while the table still squeezed its lead". It no longer claims 440 was the current measurement.
  2. **The check now tests a long lead on `/cards`, which has titles that wrap.**
     - At 390, 360 and 320 px it requires `max(leadLines) == 2`, and it measured `[2, 1, 2, 1, 1, 2, 1, 2]` at 360 and 320.
     - It checks each lead's width against half the box (179 of 358, 164 of 328, 144 of 288). The 16rem (256px) cap isn't measured separately, but at these widths half the box is the tighter limit.
     - It checks that the column next to «Urgent: the customer cannot sign in» starts inside the box at 320 px (177 against a right edge of 304).
     - Without the clamp these checks would fail.
  3. **Criterion 13's pictures are all present** in `.build/loop/ui-lists/pictures/` of the worktree.
     - `before/` and `after/` each hold the specimen's `table` and `page-header` at 390 and 1280 px, light and dark.
     - The showcase's `/cards`, `/customers` and `/items` are there at 390 px, and `/cards` at 1280 px, light and dark.
     - The clients' pictures and reports are under `clients/`.
     - I looked at three of them, `before/showcase/cards-390-light` against the current `phone-cards`, and `after/table-390-dark`:
       - before, eight cards needed about two screens;
       - after, `/cards` shows dense rows in one panel lined up with the toolbar;
       - in dark, the specimen's long description shows two lines and then «…», the six-column list scrolls behind an edge shadow, and the empty row is in sight.
  
  **The rest is unchanged from the last review and still holds**
  - **Criteria 7–10:** the row is one target at both widths, it also works without JavaScript, and the focus ring is inset. The pressed state applies only while the row's own link is pressed. The customer link and the «More actions» menu inside a row work as themselves. Sorting keeps the filters in the address, and the rows stay with the loading sign while a slow sort or filter answers.
  - **The added lines** have no leftover debugging or TODOs.
