# An accordion fades and rises as it opens, a generated record page confirms in the dialog, a Markdown table scrolls in its own box on a phone

- loop: ui-motion
- mode: reviewed
- stage: ship
- base: f2201238d04fb335d8a16eabb35b3fbfbc55b5ad
- item: sak_28fv8fkx6mk2baca
- estimate: 1h30m 2h30m 4h
- like: tun/ui-sheets tun/ui-nits
- tags: kind:ui core module:ui
- verified: 55929d85eccc8628f9eba0c45285bdab6770fadd
- shown: 55929d85eccc8628f9eba0c45285bdab6770fadd

## Brief

Ferdig sak_28fv8fkx6mk2baca (project «Tun»), brought by the factory's
orchestrator on 2026-11-14: three of Jonas's answers of 2026-11-14 that
change Tun's UI library, as one loop. The item, in Jonas's numbering:

> - 2B: an accordion's content fades in and rises when it opens (with the
>   duration tokens, nothing under reduced motion).
> - 3B: a destructive action on a generated record page asks in the
>   confirm dialog; the server's confirmation page stays for a browser
>   without scripts.
> - 8A: a table in rendered Markdown scrolls in its own box on a phone
>   instead of widening the page.

The orchestrator's brief, in short:

1. **The accordion** (`accordion`, `src/web/ui/interaction.lisp`): only
   `opacity` and `translate` move, never height or `transform`; the
   duration and easing are the motion tokens (§2.1); nothing moves under
   `prefers-reduced-motion: reduce`; closing happens at once; «choosing
   moves nothing» still holds for the summary row; it works without
   scripts (`<details>`). A browser check measures it: the animation's
   name and duration on open, none under reduced motion, the boxes
   around it do not jump.
2. **The generated record page's confirmation** (`confirmation-page` in
   `src/web/ui.lisp`): with scripts, the press opens Tun's confirm
   dialog and, on yes, the operation runs; the server's own confirmation
   (token, expiry, policy, idempotency) is not weakened or bypassed:
   decide and write in the spec how the dialog's yes obtains and posts
   the token, and test that a forged or expired token is still refused.
   Without scripts the server page stays exactly as it is. An operation
   drawn as a warning (those that end or remove something) gets the
   danger button and starts with focus on Cancel. Client pages that call
   the same generated path get the same behaviour with no change.
3. **The Markdown table** (`markdown`, `src/web/ui/markdown.lisp`, §6.2)
   scrolls in its own box on a phone instead of widening the page, as
   `table`'s box does (`loops/ui-lists.md`), keyboard reach of a
   scrolling box included; the showcase's `/markdown` gets a wide table
   so the check and the pictures show it at 390, 360 and 320 px.

Each of the three shows on the showcase (specimen or a page), has a test
and a browser check, is in `spec/ui.md` before gate A, and in
`docs/client-api.md` where a client would see a difference. The source of
the motion rules is the owner's rules for an admin application, 2026-11.

Mode: reviewed. A core change, a minor version (2.38.0).

## Criteria

1. **The accordion opens with motion, only opacity and translate.** In
   `accordion`'s CSS, an item's content (`.tun-accordion-content`) of an
   open item (`.tun-accordion-item[open] > .tun-accordion-content`) runs
   the keyframes `tun-accordion-open`, from `opacity: 0` and `translate:
   0 0.25rem` to where it stands, over `--duration` with `--ease` and
   `animation-fill-mode: backwards`, inside `@media
   (prefers-reduced-motion: no-preference)`. The CSS sets no
   `interpolate-size`, no `::details-content` rule, and no `transition`
   or keyframes of `block-size`, `height`, `transform` or `scale`; the
   keyframes name only `opacity` and `translate`. Closing has no
   animation or transition: the content is gone at once.
   (`ui-motion-tests`)
2. **Measured in a browser.** On the specimen's `/ui/accordion` at 390
   and 1280 px: right after a closed item's summary is clicked, its
   content's computed `animation-name` is `tun-accordion-open` and its
   `animation-duration` 0.2s, and its opacity, sampled every frame,
   rises from below 1 to 1 within 300 ms; the summary row's box is the
   same (to 0.5px) closed, opening and open; the next item's summary
   stands, from the first frame after the click, where it stands when
   the opening has ended (to 0.5px), so nothing around the content
   slides; clicking the summary again hides the content in the next
   frame. Under `prefers-reduced-motion: reduce` the content's
   `animation-name` is `none` and it is at full opacity in the first
   frame. With JavaScript off the item opens and closes on a click.
   (`ui-motion.py`)
3. **Without scripts, the confirmation page as it is.** A POST to a
   generated record's action (`/PATH/ID/TOOL`) whose operation asks for
   confirmation, without `HX-Request`, answers 200 with the same
   `confirm-panel` page as before (the question, the summary, the
   expiry, «Go back», the `confirmation_token` field), and the post with
   the token runs it and answers 303 to the record. `web-tests`'
   `orders-through-the-ui-with-confirmation` stays as it is.
   (`ui-motion-tests`, `web-tests`)
4. **With scripts, the server asks the page to ask.** The same POST sent
   by htmx (`HX-Request: true`, from the generated record page or any
   other page) changes nothing in the store and answers 200 with
   `HX-Retarget: [data-tun-confirm-dialog]`, `HX-Reswap: beforeend` and
   `HX-Push-Url: false`, and a fragment only (no document, no shell): a
   `form` with `hidden` and `data-tun-confirm-step`, posting to the same
   path, holding the `confirmation_token` the operation issued and a
   submit button marked with `confirm-attributes`: the question «TITLE?»
   (the operation's title), the sentence the operation's summary, the
   action TITLE, and `data-variant="destructive"` for an operation drawn
   as a warning (a tool ending in `_cancel`, `_erase`, `_delete` or
   `_revoke`), `primary` otherwise. A refusal of the first call (a
   viewer's 403, a record that does not exist, 404) answers with its
   error page as before, with no step. (`ui-motion-tests`)
5. **The token is still the server's.** The second post is the
   operation's own confirming call: with the step's token it runs once
   and answers 303 to the record (to htmx too: a boosted post gets the
   303); the same token again, a token made up, a token issued for
   another record or another tool, and a token after its expiry (the
   clock set past `expires_at`) are each refused with the record page
   and its `confirmation_invalid` error, nothing changed in the store,
   with and without `HX-Request`. (`ui-motion-tests`)
6. **The dialog asks, the yes posts the token.** On the showcase's
   generated `/meetings/ID` at 390 and 1280 px: pressing «Cancel the
   meeting» opens the page's confirm dialog over the record page, its
   address unchanged, with the title «Cancel the meeting?», the
   operation's summary as its sentence, the action «Cancel the meeting»
   in red words (`--destructive`) and the focus on «Cancel»; «Cancel»
   and Escape close it with no second POST, the meeting still planned,
   the address unchanged, no step left in the page and the focus back
   on the control that was pressed; pressing it again and the action posts once
   with the token, and the record page shows the meeting cancelled at
   `/meetings/ID`. «Mark as held», not a warning, asks with the primary
   action and the focus on it. With JavaScript off, «Cancel the meeting»
   shows the server's confirmation page with its token form, as before.
   At 390 px the two actions do not fit beside the title (spec §6
   `page-header`: their words, 18rem, and the title's room come to more
   than a 320 px phone's 18rem), so they fold into «More actions»: the
   check opens that menu and presses its item «Cancel the meeting», and
   the focus goes back to «More actions» after «Cancel» and after
   Escape; at 1280 px they are buttons, and the focus goes back to the
   button «Cancel the meeting». (`ui-motion.py`)
7. **The showcase's meetings have actions that confirm.** The module
   `meetings` gains a `status` (planned, held, cancelled; planned when
   made) and two record actions that ask for confirmation,
   `meetings_hold` («Mark as held») and `meetings_cancel` («Cancel the
   meeting», drawn as a warning), each from planned only, with a
   summary naming the meeting, in English and Norwegian. The default
   scenario's meetings are planned. (`ui-motion-tests`, the check)
8. **A Markdown table scrolls in its own box at every width.** A table
   of four or more columns stays a table where `markdown` is under 36rem
   wide too: its rows are table rows, its headings show, and its box
   (`.tun-markdown-table`, `overflow-x: auto`) scrolls sideways when the
   columns do not fit, never the page. A cell keeps its text on one line
   up to 16rem, and three quarters of the component's width, and wraps
   beyond it. The cards go: no cell holds its
   column's heading (`tun-markdown-table-label`) and no rule makes a
   row or a cell a block. The box has the edge shadows of `table`'s
   (two covers that scroll with the rows, `local`, and two shadows that
   do not, `scroll`). A table of up to three columns is as before: a
   table at every width, its long words broken, never scrolling.
   (`markdown-tests`, `ui-motion-tests`)
9. **Measured in a browser.** On the showcase's `/markdown` at 320, 360
   and 390 px: the page does not scroll sideways; the ten-column table's
   rows and headings are table rows, its box lies inside the comment and
   scrolls (`scrollWidth` above `clientWidth`), and scrolling it to its
   end brings the last column's end into the box; «Fjord Coffee Ltd» and
   «In progress» stand on one line, and the long note wraps within 16rem
   and three quarters of the comment's width; the three-column table fits
   without scrolling. A press of Tab from the element before the box
   puts the focus on the box (a box that scrolls is reached by the
   keyboard), and the arrow keys then scroll it. At 800 and 1280 px the
   page does not scroll sideways and the box scrolls where the columns
   do not fit, as before. `markdown-fits-a-phone.py` is changed with the
   spec: it pinned the cards. (`ui-motion.py`,
   `markdown-fits-a-phone.py`)
10. **The specimen and the pictures.** The specimen's `markdown` shows
    «A wide table, scrolling in its own box on a phone»; its `accordion`
    keeps its examples. Pictures before and after of `/ui/accordion`,
    `/ui/markdown` and `/ui/confirm-dialog` at 390 and 1280 px, light
    and dark, and of the open states (an accordion opening, the dialog
    over `/meetings/ID`, `/markdown` at 320, 360 and 390 px), in
    `~/coding/tun-wt/ui-motion-shots/`.
11. **The spec, the clients, the version.** `spec/ui.md` §2.1, §6
    (`accordion`, `confirm-dialog`), §6.2, §8 («A record») and §10, and
    `docs/client-api.md` say the above. Core 2.38.0 in
    `src/core/module.lisp` and `flake.nix`. No component's lambda list
    changes. Every existing test and check stays green, none weakened;
    one that pinned a removed behaviour is replaced and named in the
    Log. The five clients (`tunworks/apps/factory`,
    `tunworks/apps/ferdig`, `tunworks/apps/nixploy-dashboard`, `kurs`,
    `tun-erp`) build and pass their own `bin/test` against this tree,
    unchanged; each result is in the Log, and the report names any
    client check that pins what changed.

## Decisions

- **The accordion: keyframes on the content, not the size.** The open
  item's content runs a short rise and fade (`tun-accordion-open`); its
  room opens at once, so the page below moves once, in the frame of the
  click, and nothing slides. The slide of `block-size` through
  `::details-content` and `interpolate-size` goes: it laid the page out
  every frame, the kind of motion the owner's rule leaves out (`ui-sheets`
  left the question to Jonas; 2B answers it). Keyframes rather than a
  transition: an element shown by `<details>` has no earlier style to
  move from, and `@starting-style` works only where `::details-content`
  does; an animation that starts when `[open]` starts to match runs in
  every browser that has `<details>`. Under reduced motion the
  animation is not set at all (and the duration tokens are 0 besides).
  Closing has no motion, as decided. An item open in the page's markup
  fades in once as the page shows, which is how content appearing looks
  anyway; nothing runs a script.
- **0.25rem and `--duration`.** The rise of a menu, a list and a tooltip
  (0.25rem), over the duration of what opens in the page (`--duration`,
  200ms); `--duration-fast` is for the small floating layers.
- **How the dialog gets the token: the first post answers the
  confirmation, the page asks.** The record's action stays a form that
  posts, with no change to the generated page's markup, so a client's
  page that posts to the same path gets the same. The server tells an
  htmx request (`HX-Request`) from a browser without scripts: to htmx it
  answers the confirmation not with a page but with a small hidden form
  of the token, appended beside the shell's confirm dialog
  (`HX-Retarget`, `HX-Reswap`; `HX-Push-Url: false` keeps the address),
  and the confirm dialog's script asks with the texts the server wrote on
  it. A yes posts that form, which is exactly the second call the
  confirmation page makes today: the operation checks the token
  (single use, ten minutes, bound to the person, the tool and the input)
  as before, and nothing in the browser can run the operation without
  the server's token. Not chosen: the dialog's yes making both posts
  (two requests a person waits for after saying yes, and a summary the
  dialog could not show before the first); asking first in the
  browser with a question written into the page (the server's summary,
  «Cancel order 10 (status draft). Bookings … are released», would be
  lost, and a client's page would need markup of its own).
- **The question and the sentence.** The title is the operation's title
  as a question, «Cancel the meeting?», as the confirmation page's panel
  reads, and the sentence is the operation's summary, which names the
  record. The expiry line of the page is left out of the dialog: the
  dialog is answered at once, and a token answered after ten minutes is
  refused with the record page's error, as on the page.
- **Warning: the tools that end or remove something**, as the page and
  the record's menu already decide it (`destructive-tool-p`), not the
  operation's `:destructive` flag (which marks orders' «Confirm the
  order» too, which the page draws as a plain confirmation).
- **The step's focus.** The step's own button is hidden; the script
  remembers the control whose request brought the step (the submitter of
  htmx's request), and the focus goes back to it on «Cancel» (to the
  menu's button when it was a menu item, as for any confirmed control).
  One question at a time: a step that comes while the dialog asks (a
  double press) is dropped, and a step answered «Cancel» is removed, so
  neither token is posted.
- **The showcase's meetings get a status and two actions.** The
  showcase has no generated record with a confirming action (its
  customers' «Erase customer data» is an update, not a record action);
  the meetings module, the showcase's own, gains them. Checks create
  their own meeting to act on, so the scenario's meetings stay as other
  checks know them.
- **Markdown: the same box as `table`'s, no frame.** The cards go for
  four columns or more; the table keeps its columns and scrolls in its
  own box at every width, with `table`'s edge shadows. Its box has no
  edge: a Markdown text usually stands in a card (a comment), and a
  frame there would be a frame in a frame. A cell keeps its text on one
  line up to 16rem (the lead's cap in `table`), and three quarters of the
  text's width (decided while building: at 320 px a comment's card is
  about 15rem wide, and a cell wider than it is read only by scrolling
  inside it), so a short value never wraps and a long one wraps rather
  than making the table very wide.
  Tables of up to three columns keep breaking words to fit, as the
  spec says: they fit a phone, so nothing changes for them.
- **No `tabindex` on the box**, as `table` decided (`loops/ui-lists.md`):
  browsers make a box that scrolls and holds nothing focusable a stop of
  the keyboard themselves; a box that holds a link is reached through
  the link, which scrolls into view.
- **The cards' labels leave the markup**, with `+markdown-label-length+`:
  hidden from 36rem, they were only for the cards. The output of a wide
  table gets smaller. The tests that pinned them
  (`a-table-of-ten-columns-becomes-cards`, `a-card-s-heading-is-text-cut-at-80`)
  are replaced by tests of the table without them.
- **The showcase's `/markdown` already holds a ten-column table** (from
  the `markdown` loop); the check and the pictures use it at 320, 360
  and 390 px. Its «Note» column gets a cell long enough to wrap at 16rem.
- **Core version 2.38.0**: new behaviour of the generated pages, the
  accordion and `markdown`; no call shape changes.

## Clients

On this loop's tree (verify round 3's, unchanged since), each client's
`bin/test` with `--override-input tun` at the worktree (and tun-erp's
`customers` at its `modules/customers`), one at a time, from clones of
their `main` in a scratch folder, with no change to any of them: factory
and nixploy-dashboard (tunworks `508b78f`, 667 and 1421 checks), ferdig
(812) and kurs `c2579ae` (352) pass. tun-erp `1a49875` passes every
suite but one check of its own repository's text,
`the-parity-checks-find-each-planted-mistake` («item 81 names
order-files-comments, which is not a later key of the plan»), which reads
its `factory/plan.json` and loop records, not Tun, and so fails the same
with any Tun.

Client checks that pin what changed (browser checks, not run by
`bin/test`): ferdig's `checks/markdown-text.py` expects a Markdown
table of four or five columns as cards on a phone (`wideRow == "block"`
and the label «Sak», «Valg», «Kolonne» from
`.tun-markdown-table-label`); with 2.38.0 those tables are tables
scrolling in their box, so the check needs the new expectation when
ferdig takes this Tun. No client check goes through a generated record's
confirmation page (tun-erp's `checks/_stock.py` confirms on a page of
its own, which is unchanged).

## Log

- 2026-11-14 21:30  started, reviewed
- 2026-11-14 21:30  estimated 1h30m 2h30m 4h at brief, like tun/ui-sheets tun/ui-nits
- 2026-11-14 21:34  gate A asked of a reviewer
- 2026-11-14 21:36  gate A: changes (reviewer)
  I'm asking for changes. The spec mostly matches the brief, but criterion 6 contradicts the spec at phone width, and the client doc now puts a code example under the wrong sentence.
  
  **What is right**
  - **All three items are covered, and nothing beyond them.**
    - **Accordion (criteria 1–2):** only `opacity` and `translate` move. It uses `--duration` (200 ms in `kit.lisp:415`, so the check's "0.2s" holds) and `--ease`, and nothing moves under reduced motion. Closing is at once, the summary row stays put, and it works without JavaScript.
    - **Confirmation (criteria 3–7):** without scripts the page is unchanged. The spec now says how the dialog's yes gets the token and posts it back (§8 «A record's action that asks first»). Forged, reused, wrong-record, wrong-tool and expired tokens are each tested, with and without `HX-Request`. A warning gets the danger button with focus on «Cancel», and client pages need no change.
    - **Markdown table (criteria 8–9):** checked at 320, 360 and 390 px, including reaching the box by keyboard.
  - **The criteria can be decided by a test or a check.** They name selectors, headers, timings and tolerances.
  - **The design fits the code.**
    - `HX-Retarget: [data-tun-confirm-dialog]` with `beforeend` puts the step inside the wrapper `div` beside the `<dialog>` (`interaction.lisp:744`), which is what the spec says.
    - Staff pages are boosted (`ui.lisp:655`), so `HX-Request` is set.
    - The warning rule reuses `destructive-tool-p` (`ui.lisp:2173–2180`), which matches the four suffixes the criteria name.
    - The ten-column table on `/markdown` holds no link, so the "Tab reaches the box" check can work without a `tabindex`.
  - **The Decisions are the builder's to make.** Removing the `block-size`/`interpolate-size` slide is what answer 2B decided (`loops/ui-sheets.md:303` left it to Jonas). Adding a status and two actions to the showcase's meetings is showcase-only.
  
  **Changes**
  1. **Criterion 6 at 390 px contradicts the spec's own focus rule** (`loop.md:116–129` against `spec/ui.md` §6 «A step the server sends», diff.patch:64–71).
     - With two outline actions, «Mark as held» and «Cancel the meeting», beside a meeting's title, the page header will very likely fold them into «More actions» on a phone (`layout.lisp:384–386`). I haven't seen it at 390 px; that is my reading of the folding rule.
     - If they fold, then at 390 px «Cancel the meeting» is a menu item. The spec's rule then sends the focus back to the menu's button, not to «Cancel the meeting» as the criterion says.
     - Fix: say what the 390 px check does. It opens «More actions», presses the item, and expects the focus back on «More actions» after «Cancel» or Escape. Otherwise, state that the buttons stay unfolded at 390 px, and why.
  2. **`docs/client-api.md:340–353`: the code example now follows the wrong sentence.**
     - The new paragraph about generated record actions ends with a colon, so the `ui:confirm-attributes` / `hx-confirm` button example below reads as if it showed that paragraph.
     - Fix: put the record-action paragraph after the code block, or end the `hx-confirm` sentence with the colon again.
     - The same paragraph's "(§8, …)" should read "(`spec/ui.md` §8, …)", as the sentence before it does.
- 2026-11-14 21:36  gate A asked of a reviewer
- 2026-11-14 21:37  gate A: approve (reviewer)
  I approve gate A, round 2. Both changes asked for in round 1 are fixed, and nothing new needs changing.
  
  **Round 1's changes**
  1. **Criterion 6 at 390 px** (`loop.md:129–135`) now says what the check does. At 390 px the actions fold into «More actions». The check opens that menu and presses «Cancel the meeting». After «Cancel» and after Escape, the focus should be back on «More actions». At 1280 px it goes back to the button itself. This matches the spec's focus rule (`diff.patch:63–70`, "the button of its menu, when that has closed").
     - I checked the folding against `spec/ui.md:1318–1342`. «Cancel the meeting» needs about 11.6rem and «Mark as held» about 8.6rem with their icons. Together that is more than 18rem before the title's room, so they fold.
     - The fold only shows below 40rem of the header's width, so 390 px gets the menu and 1280 px gets the buttons, as the criterion says.
     - A folded item is a submit button naming its form. htmx still knows which control was pressed, which the focus rule depends on.
  2. **`docs/client-api.md:340–354`**: the `hx-confirm` sentence ends with the colon again. The code block follows it, and the new record-action paragraph comes after the block. That paragraph now cites "`spec/ui.md` §8".
  
  **Still right**
  - The criteria cover all three items (2B, 3B, 8A) and add nothing beyond the brief. Each can be decided by a test or a check: they name selectors, headers, durations and tolerances, and the widths 320, 360, 390 and 1280.
  - The spec change says the same as the criteria:
    - **Accordion:** §2.1 and §6 say the same as criteria 1–2.
    - **Confirmation:** §6 «A step the server sends» and §8 «A record's action that asks first» say the same as criteria 3–6. The headers, the token posted back, the refusals and the warning rule match.
    - **Markdown table:** §6.2 says the same as criterion 8. The removed cards are also dropped from the description of `markdown-fits-a-phone.py`.
    - The new test and check are listed in §10.
  - The Decisions are the builder's to make:
    - Removing the height slide is what answer 2B decided.
    - The token flow is what the brief asked the builder to decide and write into the spec.
    - The meetings' status and actions are showcase-only.
    - Using `destructive-tool-p` for the warning follows what the page already does.
- 2026-11-14 21:48  decided while building, after gate A: a step that comes while the dialog asks is dropped rather than taking the place of the one asked (spec §6 «A step the server sends», Decisions); a wide Markdown table's cell is capped at three quarters of the text's width as well as 16rem, since a 320 px comment's card is about 15rem wide, and criterion 9 measures short values on one line and the long note wrapping within the cap, and the last column's end in the box, rather than «Hansen Building and Construction Ltd» on one line (36 characters, over 16rem); the showcase's meetings are pinned by ui-motion.py, as the showcase's module is not loaded by Tun's suites
- 2026-11-14 21:48  existing tests and checks changed with the spec, none weakened: tests/markdown-tests.lisp a-table-of-ten-columns-becomes-cards becomes a-table-of-ten-columns-stays-a-table (the cells without labels), and a-card-s-heading-is-text-cut-at-80 goes with the cards' labels (ui-motion-tests pins the wide table's markup and CSS); checks/showcase/checks/markdown-fits-a-phone.py checks the ten columns as a table scrolling in its box at 320, 360 and 390 px instead of cards
- 2026-11-14 22:08  verify 2: failed test
- 2026-11-14 22:09  verify 2 failed on ui-look's panels-have-the-edge-and-the-panel-shadow, which listed markdown among the components with --shadow-panel for its rows as cards; markdown leaves that list with the cards (changed with the spec, not weakened: the box is pinned by ui-motion-tests). It also failed three timing tests under another builder's load (load 17 to 23): search's every-kind-of-two-thousand-records (postgres 113 to 146 ms) and generated-choice's the-names-add-little (postgres 119 ms), which this loop does not touch
- 2026-11-14 22:28  verify 3: failed test
- 2026-11-14 22:29  verify 3 failed only on timing under another builder's load (load average 25 to 59 during the round): search's two-thousand-records limits (postgres 124 to 259 ms), fuzz's a-day-past-the-last-date (deadline_exceeded) and markdown's costly-texts-take-time-in-proportion (table rows 0.158 s against 0.009 s); every check passed; the next round waits for the load to drop
- 2026-11-14 23:32  verify 4: failed test
- 2026-11-14 23:36  verify 4 (three suites at a time) failed only on search's every-kind-of-two-thousand-records-is-searched-within-the-limit (postgres 94 to 125 ms, load 36 to 40); every check passed. Run alone with Postgres at load 13 to 16 the search suite passed twice on this tree (failed once, «nordmann» 110 ms), and passed once on the base f2201238: the limit is a timing under another builder's load, and this loop does not touch the search
- 2026-11-15 00:01  verify 5: failed check
- 2026-11-15 00:01  verify 5 passed build and every suite, and failed one check: ui-fields stopped on a page load that took over 30 s (Page.goto /fields timed out, load about 20); it passed in rounds 2 to 4 on the same code, and this loop does not touch the fields
- 2026-11-15 00:37  verify 6: passed build, test, check
- 2026-11-15 00:38  shown (/ui/accordion, /ui/markdown, /markdown, /meetings)
- 2026-11-15 00:39  pictures: the specimen before (base f2201238) and after, accordion, markdown and confirm-dialog at 390 and 1280 px, light and dark, in ~/coding/tun-wt/ui-motion-shots/before/ and after/ (bin/ui-shots); the open states in after/open/ and in the show folder as phone-open-* and desktop-open-*: the confirm dialog over a meeting at 390 (through «More actions») and 1280 px, light and dark, settled, taken from the shown preview by a script of the builder's (Chromium, Playwright), since bin/tun loop show captures pages closed; an accordion opening at 390 px and /markdown and its wide table at 320, 360 and 390 px, from ui-motion.py in verify 6
- 2026-11-15 00:39  gate B asked of a reviewer
- 2026-11-15 00:40  gate B: changes (reviewer)
  I've read the whole packet (record, diff, check results and screenshots) and am writing up the verdict now.
  
  ## Gate B review: ui-motion
  
  I'm asking for changes. The feature works and looks right at both widths, but one line of the spec describes tests that don't exist, and criterion 5 is only partly tested.
  
  **What is right**
  - **Verification:** round 6 passed build, test and check (`verify.txt`). Every result in `checks/ui-motion.json` passed.
  - **Accordion (criteria 1–2):**
    - The open item's content runs the `tun-accordion-open` keyframes, with only `opacity` and `translate`. They are set only under `no-preference`.
    - The old height slide (`::details-content`, `interpolate-size`) is gone (`interaction.lisp`, diff 838–852).
    - The browser check measured, at 390 and 1280 px:
      - the animation's duration is 0.2s;
      - the opacity rises from 0.83 to 1 within the frames sampled;
      - the summary row and the next item's summary don't move (one position for the next item in every frame);
      - closing is at once.
    - Under reduced motion the animation is `none`. Without JavaScript an item still opens and closes.
  - **The confirmation (criteria 3–7):**
    - `confirmation-step` (`ui.lisp`, diff 735–759) sends the step only when the server asked for confirmation and the post came from htmx. A refusal still comes first in the `cond` and gets the record page, so a refused first post is unchanged.
    - The token check stays on the server. The script can only submit the form the server sent (`requestSubmit`).
    - The screenshots show it at both widths:
      - **Phone:** a bottom sheet with red «Cancel the meeting».
      - **Desktop:** a centred dialog in dark mode.
    - The check confirms:
      - focus starts on «Cancel» for the warning and on the action for «Mark as held»;
      - focus goes back to «More actions» (390 px) or to the button (1280 px);
      - «Cancel» and Escape send no second post and leave no step behind;
      - the yes posts once with the token;
      - without JavaScript the confirmation page is unchanged.
  - **Markdown (criteria 8–9):**
    - The cards' markup, CSS and tests are gone cleanly (`plain-text` and `+markdown-label-length+` were removed with them).
    - The `75cqi` cap works because the component still declares its container (`markdown.lisp:728`).
    - At 320, 360 and 390 px the check shows:
      - the page doesn't scroll sideways and the box does;
      - short values stay on one line and the note wraps at the cap;
      - scrolling to the end brings the last column into the box;
      - Tab reaches the box and the arrow keys scroll it.
    - The 320 px screenshot shows the edge shadow.
  - **Replaced tests:** the `ui-look-tests` and `markdown-tests` changes follow the new spec, weaken nothing, and are named in the Log.
  - **Version and docs:** 2.38.0 is in both places, and the `client-api.md` paragraph is accurate.
  
  **Changes**
  1. **`spec/ui.md` §10 describes tests that don't exist** (diff.patch:699). It says `tests/ui-motion-tests.lisp` covers "the showcase's meetings' status and actions". The file has no meetings test. The Log agrees that the meetings are checked only by `ui-motion.py`, because Tun's test suites don't load the showcase module.
     - Fix: drop that phrase from the `ui-motion-tests` entry, and list the meetings' actions under the `ui-motion.py` entry instead.
  2. **Criterion 5 says "with and without `HX-Request`", but most cases are tested only with it** (`tests/ui-motion-tests.lisp`, `the-token-is-still-the-server-s`, diff 1242–1260).
     - Only the made-up token is also tried without the header (line 1243).
     - Fix: also call `refused` with `'()` (no htmx headers) for the reused token, the other record, the other tool and the expired token. The helper already takes that argument, so each is one more line.
     - Also worth adding: criterion 4 names an `invalid_transition` refusal of the first post with `HX-Request`, but only the viewer's 403 is tested (diff 1263–1273). A second post of `orders_send_quote` on an accepted order, or similar, would cover it.
- 2026-11-15 00:42  gate B 1's changes: spec §10 no longer says ui-motion-tests covers the meetings (ui-motion.py's entry names them); the-token-is-still-the-server-s refuses the reused token, the other record's, the other tool's and the expired token without HX-Request too; the first post's refusal is tested for a record that does not exist (404) beside the viewer's 403, and criterion 4 and spec §8 name those two instead of an invalid_transition, since a confirming operation's first call issues its token before the operation's own state checks (core.md §3.6)
- 2026-11-15 01:02  verify 7: passed build, test, check
- 2026-11-15 01:03  shown (/ui/accordion, /ui/markdown, /markdown, /meetings)
- 2026-11-15 01:03  gate B asked of a reviewer
- 2026-11-15 01:04  gate B: approve (reviewer)
  I approve gate B, round 2. Both changes from round 1 are made, and nothing new needs changing. Verify round 7 passed build, test and check (`verify.txt`), and no result in `checks/ui-motion.json` failed.
  
  **Round 1's changes**
  1. **`spec/ui.md` §10** (diff.patch:688–714):
     - The `ui-motion-tests` entry no longer claims to cover the showcase's meetings.
     - The `ui-motion.py` entry now names them: their status and their two actions that ask first.
     - That entry also adds the address staying unchanged while the dialog asks, which criterion 6 requires.
  2. **Criterion 5, with and without `HX-Request`** (`tests/ui-motion-tests.lisp`, diff.patch:1245–1267): each refusal is now called twice, once with the htmx headers and once with none (`'()`). That covers:
     - the made-up token;
     - the token for another record;
     - the token for another tool;
     - the same token again;
     - the token after its expiry.
  
     Each call checks for 422, `confirmation_invalid` and the record page. The store is also checked to be unchanged.
  3. **A refused first post** (diff.patch:1270–1286): the test now covers the viewer's 403 and a record that does not exist (404). In both cases there is no `HX-Retarget` and no step in the body.
     - Criterion 4 and spec §8 (diff.patch:659–662) were changed to name these two refusals instead of `invalid_transition`.
     - The reason given is that a confirming operation issues its token before it checks the record's state (`core.md` §3.6), so a bad state is only refused at the second call. That holds, and the spec now says so instead of promising a test that couldn't exist.
  
  **Still right** (from round 1; this round's diff changes only the tests and the spec text above)
  - **Accordion:** only `opacity` and `translate` move, only under `no-preference`, and the old height slide is gone.
  - **Confirmation:** the token is still checked on the server. Without scripts the confirmation page is as before. The dialog's colour and focus are measured at 390 and 1280 px.
  - **Markdown:** the wide table scrolls in its own box at 320, 360 and 390 px, the screenshots show it, and Tab reaches the box.
  - **Version and docs:** 2.38.0 is in `src/core/module.lisp` and `flake.nix`, and `docs/client-api.md` describes the change.
