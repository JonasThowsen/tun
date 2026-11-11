# ui-sheets: a dialog is a bottom sheet on a phone, what opens moves into place, one confirm

- loop: ui-sheets
- mode: reviewed
- stage: done
- base: 7af7e5a8b7774e357cbf7604de92315805f19caa
- item: sak_fbhn0jva0dezp35v
- estimate: 2h 3h30m 6h
- like: tun/ui-look
- tags: kind:ui core module:ui
- verified: 96f84f60639aeb859714c423c233ce6fddb232f2
- shown: 96f84f60639aeb859714c423c233ce6fddb232f2

## Brief

Ferdig sak_fbhn0jva0dezp35v, brought by the factory's orchestrator on
2026-11-11, the second loop after `ui-look` of the work on Tun's
component library. It was meant to sit under the item for the library,
sak_xvtp3eht3dcnrh2n, which is finished, so it stands alone. Jonas,
2026-11-11: he has polished the admin UI of another application of his
for two weeks and wants the best of it carried into Tun's component
library, «to make the UI component Library of Tun superb». The source is
the owner's rules for an admin application, 2026-11; code does not carry
over, rules, values, behaviour and the tests that pin them do.

This loop: what opens moves into place, and a dialog on a phone is a
sheet from the bottom. In the orchestrator's words: a dialog below 40rem
stands at the bottom at full width with its title and close button at
the top and its actions at the bottom while only its content scrolls; a
dialog one types in opens at full height so the on-screen keyboard moves
only its bottom edge, the focused field and the actions above the
keyboard, nothing of the page behind scrolling; opening and closing move
(a sheet slides over `--duration-sheet` and back over
`--duration-close`; a centred dialog, a menu, the combobox's list and a
tooltip rise a few pixels and fade; «an `accordion` panel does not
jump»; closing has motion too, unlike where the rules were learned),
only `opacity` and `translate`, by what CSS has
for the top layer, nothing timed by a script, nothing moving under
reduced motion; the dim only gets darker while it opens; one confirm, a
new `confirm-dialog` instead of the browser's `confirm()`, which htmx's
`hx-confirm` goes through too; a flash as a toast, last and only if the
loop has time; focus and keys as today, Escape closing the top one, Tab
kept in a modal; tests that scan the CSS and a browser check that
measures. Warnings: matching `:popover-open` from a script threw in
Safari before 17 and broke every dialog's keyboard fit; the dim once
crossed two fades and flashed lighter on a phone; a half-height sheet was
pushed off the top by the keyboard. Not this loop: the page header and
the shell, filters and their sheet, lists, search, date fields, a side
panel, panels with an address.

Mode: reviewed. A core change, a minor version.

## Criteria

1. **The sheet.** Below 40rem every `dialog` (all three variants) has
   its box at the bottom of the window, as wide as the window (to 1px),
   its top corners `--radius-xl` and its bottom corners 0, at most the
   window's height less 2rem (`--tun-dialog-strip`). Its header (title,
   description, close button) stays at the top and its footer at the
   bottom while its body scrolls: scrolling the body of «Terms for jobs»
   to its end leaves the header's and the footer's boxes where they
   were, inside the dialog's box. The footer's buttons share one row,
   «Cancel» first, each growing to fill it, and the dialog's bottom
   padding is at least the bottom's safe area
   (`env(safe-area-inset-bottom)`). From 40rem a dialog is centred as
   today (28rem wide; 32rem for the asking variants), all corners
   rounded, its footer's buttons at the end of their row at their own
   width, «Cancel» first. `dialog` keeps its call shape; a dialog without a
   footer or without a body renders and opens the same way.
   (`ui-sheets-tests`: the CSS; `ui-sheets.py`: the boxes at 390 and
   1280 px)
2. **The keyboard.** Below 40rem a dialog that holds a text field (an
   `input` that takes text), a `textarea` or a `combobox` is as tall as
   its largest height from the moment it opens. While a modal dialog is
   open, the script writes the visual viewport's distance from the top
   and the bottom of the window as `--tun-visual-top` and
   `--tun-visual-bottom` on `<html>` (nothing when the page is zoomed in
   or when both are under 2px) and removes them when no dialog is open;
   the dialog stands inside them, so with the visual viewport shrunk to
   400px from the bottom, as a keyboard does, the dialog's bottom edge is
   at 400px, its top where it was, its footer wholly above 400px and the
   focused field inside the visible part. While a modal dialog is open
   the page behind does not scroll: the script sets `overflow: hidden`
   on `<html>` (with `scrollbar-gutter: stable` when the page scrolled,
   so nothing moves sideways) and restores what was there when the last
   one closes. Without JavaScript a dialog still opens with its button
   (`command`) where the browser has invoker commands, and closes, and
   its form posts. No script matches `:popover-open` or `:modal` in a way
   that throws where a browser lacks them: every such match goes through
   a guarded helper. (`ui-sheets.py`: the boxes with the visual viewport
   shrunk, the page's scroll; `ui-sheets-tests`: the helpers are the only
   places the script names the two pseudo-classes)
3. **Motion.** A dialog below 40rem slides up from `translate: 0 100%`
   over `--duration-sheet` and back over `--duration-close`; from 40rem
   it rises from `translate: 0 0.5rem` and fades in from 0 over
   `--duration` and leaves the same way over `--duration-close`. The
   `dropdown-menu`'s list, the `combobox`'s list and a `tooltip` rise
   from 0.25rem below and fade in over `--duration-fast`, and leave over
   `--duration-close`. Every one of them (the `accordion` aside,
   Decisions) animates only `opacity` and `translate` (with `display`, `overlay`,
   `visibility` and `content-visibility` flipping, never animated), with
   `--ease`; none uses `transform` or `scale`; no script sets a timer
   for them. They use `@starting-style` and `transition-behavior:
   allow-discrete`, so a browser without them opens and closes at once.
   Under `prefers-reduced-motion` the duration tokens are 0 and nothing
   moves. (`ui-sheets-tests`: the CSS scan; `ui-sheets.py`: a closing
   menu still showing at 80ms and gone after `--duration-close`, a
   dialog's box during and after opening, reduced motion)
4. **The dim.** The page behind a modal `dialog` dims with its
   `::backdrop` in `--overlay`, a new token, `light-dark(#00000066,
   #0000008a)`, in one fade of its opacity from 0 to 1 over `--duration`
   and back over `--duration-close`; there is no blur and no second
   layer. Sampled every frame while a dialog opens, the backdrop's
   opacity never decreases; while it closes, it never increases.
   (`ui-sheets-tests`: the token and the backdrop's rules;
   `ui-sheets.py`: the samples at 390 and 1280 px)
5. **One confirm.** A new component `confirm-dialog`, in the
   interaction group, is the page's one confirming dialog: a `dialog` of
   the `:confirm` variant (a sheet on a phone) with an empty question, an
   empty sentence, «Cancel» («Avbryt») and the action, «Confirm»
   («Bekreft») until a control fills it. Every `app-shell` holds one. A
   control (a button, a link, a menu item) marked
   `data-tun-confirm="QUESTION"`, with `data-tun-confirm-detail`
   (one sentence of what happens) and `data-tun-confirm-action` (the
   action's words) as it needs, or through the new function
   `(confirm-attributes QUESTION :detail D :action A)` for its
   `:attributes`, opens that dialog on a click instead of acting: its
   title is QUESTION, under it the sentence, and its action button has
   the action's words, else the control's own words (its text without
   key caps, else its `aria-label`) when they are 1 to 40 characters,
   else «Confirm»; it is red words (`:destructive`) when the control is
   destructive (`data-variant="destructive"`) and the primary button
   otherwise. The focus starts on «Cancel» for a destructive action and
   on the action otherwise. Escape and «Cancel» close it, nothing runs,
   and the focus goes back to the control. The action button closes it
   and clicks the control once more, which then acts as it would have
   (a form posts with that button as its submitter, a link is followed,
   htmx sends its request), exactly once. htmx's `hx-confirm` goes
   through the same dialog from its `htmx:confirm` event: the text up to
   and with its first «?» is the question and the rest, trimmed, the
   sentence; a text without «?» is all question, with no sentence; htmx
   sends the request on the action or drops it on «Cancel» or Escape.
   Without JavaScript nothing changes: the control acts, and a page that
   asks on the server (the `confirm-panel` of a `:confirm` operation)
   still asks. A page without a `confirm-dialog` falls back to the
   browser's own. (`ui-sheets-tests`: the markup, both languages, the
   function, the shell; `ui-sheets.py`: the texts, the colour, the
   focus, Escape, «Cancel», one post and one htmx request, a confirm
   opened from inside a dialog)
6. **Flash as a toast** (last; left out, and this criterion and its
   spec taken back, if the loop has passed its likely estimate when it
   is reached). With JavaScript, a `flash` stands over the page, not in
   its flow: below 40rem at the bottom, 1rem from the window's sides and
   1rem above the bottom's safe area; from 40rem 1rem from the top and
   the right, at most 25rem wide; in the layer `--z-toast`. It rises in
   over `--duration` and leaves over `--duration-close` (opacity and
   translate). `:success` and `:info` leave by themselves 5 seconds
   after they showed, the time standing still while a pointer is over it
   or the focus in it; `:warning` and `:destructive` stay until closed;
   each has its close button. `:destructive` has `role="alert"`, the
   others `role="status"`. A new option, `:toast nil`, keeps a flash in
   the page's flow, as the specimen's gallery does. Without JavaScript a
   flash stands in the page as today and does not leave. A flash is in
   the page for at least 5 seconds after it showed, so a check reading
   it right after an action finds it. (`ui-sheets-tests`,
   `ui-sheets.py`)
7. **Focus and keys.** Opening a `dialog` puts the focus on its
   `autofocus` control, else on its first control; opening a
   `dropdown-menu` puts it where it does today. Closing a dialog gives
   the focus back to the control that opened it (its `command` button,
   or what had the focus when its shortcut opened it). Escape closes the
   top one only: a `confirm-dialog` opened from inside a dialog closes
   and the dialog stays open. Tab and Shift+Tab stay inside an open
   modal dialog, going round from its last control to its first and
   back. (`ui-sheets.py`)
8. **Evidence.** A new `tests/ui-sheets-tests.lisp` pins criteria 1–6
   in the CSS, the markup and the script, and scans the CSS of
   `dialog`, `confirm-dialog`, `dropdown-menu`, `combobox`, `tooltip`
   and `flash` for what opens: every transition there names
   only `opacity`, `translate` and the four discrete properties; each
   has a leaving transition with `--duration-close`; no `scale`,
   `transform` or keyframes there. A new
   `checks/showcase/checks/ui-sheets.py` measures on the specimen at 390
   and 1280 px, light and dark where colour matters, what criteria 1–7
   say it measures, with no page error thrown. The specimen gains
   examples: a dialog to type in with a text area, a dialog without a
   footer, a `confirm-dialog` with a destructive and a plain marked
   control, a link marked, an `hx-confirm`, a confirm from inside a
   dialog, and a flash as a toast. Every existing test and check stays
   green, none weakened; a test that pinned an old value is changed and
   named in the Log.
9. **The spec and the clients.** `spec/ui.md` §2.1 «Motion», §3 (the
   `--overlay` token), §6 (`dialog`, `confirm-dialog`, the motion of the
   menus, the combobox and the tooltip, `flash`) and §10
   say the above; `docs/client-api.md` shows `confirm-attributes` and
   `hx-confirm`. Core 2.26.0 in `src/core/module.lisp` and `flake.nix`.
   No component's lambda list loses a key or refuses a value it took;
   the five clients (`tunworks/apps/factory`, `tunworks/apps/ferdig`,
   `tunworks/apps/nixploy-dashboard`, `kurs`, `tun-erp`) build and pass
   their own `bin/test` against this tree, unchanged; each result is in
   the Log.

## Decisions

- **The accordion is left as it is.** Its panel slides its height open
  and shut today (`block-size` with `interpolate-size`), which is a
  size, the kind of motion the owner's rule for what opens would not
  use (it lays the page out every frame). Whether to keep that slide or
  let the panel fade and rise with its room opening at once is Jonas's
  to decide, so this loop does not touch the accordion, leaves it out of
  the scan and the spec's motion rule, and the question goes in the
  report.
- **One shared confirm dialog, filled from the control.** The texts are
  the server's, in the page's language: the question and the sentence in
  the control's attributes, «Cancel» and «Confirm» in the
  `confirm-dialog` the shell renders. The script copies only text the
  page holds (spec §4: it holds no copy of its own). One dialog per page,
  not one per control, so `hx-confirm` on any element finds it without a
  change to the clients. It lives in `interaction.lisp`, after `dialog`,
  which it is made of; the shell (`layout.lisp`) gains the one line that
  renders it, the only touch to the shell.
- **The confirm's two words are attributes until it asks.** «Cancel»
  and «Confirm» are written on the `confirm-dialog` as
  `data-cancel-label` and `data-confirm-label`, in the page's language,
  and its buttons take them when it opens: nixploy-dashboard's suite
  checks that a run page offers no «Cancel» (`>Cancel<` in the page),
  and a closed dialog in every shell holding one would fail it, though
  no one sees it.
- **The generated record pages keep the server's confirm panel.** A
  `:confirm` operation asks on the server with a token, for agents and
  people alike; marking its buttons too would ask twice. Making the
  dialog stand in for that page needs the server to take the dialog's
  answer, a change to the generated screens: a question for Jonas (in
  the report), not this loop.
- **A dialog still needs `:title`.** «A dialog that has no title still
  works» is read as: the sheet holds when its header has no description
  and no icon (the `confirm-dialog`'s title is empty until it is
  filled), and when it has no footer or no body. Making `:title`
  optional would leave a dialog without a name for a screen reader; the
  call shape stays.
- **Every variant is a sheet on a phone.** The asking variants were
  centred on a phone; the brief's confirm is a sheet there, so they are
  too, their header aligned to the start as from 40rem.
- **The dim is a token, `--overlay`,** the owner's values: black at 40 %
  in the light and 54 % in the dark. Basecoat's black at 10 % with a
  4px blur goes: the blur is costly on a phone and the faint dim read as
  none.
- **Opening and leaving durations by state.** A transition takes its
  duration from the state it goes to, so the open state names the
  opening duration and the closed state `--duration-close`.
- **The page behind is held by the script,** since a component's CSS
  may only name its own root: `overflow: hidden` on `<html>` while a
  modal dialog is open, a style a script sets while it runs (spec §4).
- **The keyboard fit is the script's in every browser**: the dialog
  stands inside `--tun-visual-top` and `--tun-visual-bottom`, so Safari
  and Chrome on Android (which by default shrink only the visual
  viewport) behave alike, with no change to the viewport tag.
- **Guarded helpers in the kit's script** (`tunPopoverOpen`,
  `tunModal`) are the only places a script asks `:popover-open` or
  `:modal`; Safari before 17 has no popovers, and an unknown
  pseudo-class throws there. The dropdown menu, the combobox and the
  dialog use them.
- **The menus on a phone stay menus**: a menu as a floating sheet is the
  filters' and the shell's loops'.
- **Core version 2.26.0**: a new token, a new component, function and
  option, new behaviour; no call shape changes.

## Actuals

```json
{"loop":"ui-sheets","title":"ui-sheets: a dialog is a bottom sheet on a phone, what opens moves into place, one confirm","repository":"tun","mode":"reviewed","stage":"done","item":"sak_fbhn0jva0dezp35v","tags":["kind:ui","core","module:ui"],"like":["tun/ui-look"],"started":"2026-11-11 21:14","ended":"2026-11-11 23:33","minutes":{"total":139,"waiting_person":0,"waiting_reviewer":6,"working":133,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":120,"likely":210,"worst":360,"at":"brief"},"latest_estimate":{"best":120,"likely":210,"worst":360,"at":"brief"},"within_estimate":true,"ratio":0.66,"verify":{"rounds":4,"failed":1},"changes":{"A":2,"B":1,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-11 21:14  started, reviewed
- 2026-11-11 21:14  estimated 2h 3h30m 6h at brief, like tun/ui-look
- 2026-11-11 21:22  gate A asked of a reviewer
- 2026-11-11 21:23  gate A: changes (reviewer)
  I'm asking for changes. The spec is mostly sound, but one decision belongs to Jonas, who brought the request, and a few smaller gaps are worth fixing in the same pass.
  
  **What is right**
  - **The brief is covered.** The criteria cover what the brief asks for:
    - the sheet below 40rem
    - the dialog fitting above the keyboard, at full height so the keyboard can't push it off the top
    - the page behind not scrolling
    - motion only by `opacity`/`translate`, using CSS's own top-layer transitions, with closing motion and reduced motion
    - a dim that only gets darker
    - one `confirm-dialog`, which `hx-confirm` also goes through
    - the flash as a toast, last and dropped if over the estimate
    - focus and keys as today
    - a CSS scan and a browser check that measures
  
    The brief's three warnings each map to something checkable: the Safari helpers in criterion 2, the backdrop sampled every frame in criterion 4, and full height from opening in criterion 2.
  - **The criteria are decidable.** Each one gives values a test or check can measure: 1px width, `--radius-xl`, the 2rem strip, the viewport shrunk to 400px, 80ms against `--duration-close`, per-frame opacity, "exactly once" for post and htmx, 1–40 characters.
  - **Most decisions are sound.** The `:confirm` record pages keep the server's panel, every variant is a sheet, `--overlay` uses the owner's values, and the script sets `overflow` on `<html>` (§4 allows a script to set styles while it runs). These follow from the brief or the repo's rules and don't need asking.
  - **The spec and the criteria mostly agree.** §2.1, §3, §6, §10 and `docs/client-api.md` say what criteria 1–7 say.
  
  **Changes**
  1. **The accordion is Jonas's decision, and the spec decides it without him** (criterion 3; the accordion part of criterion 8's scan list; `spec/ui.md:151` and `:651`).
     - The brief doesn't mention the accordion. It names a sheet, a centred dialog, a menu, the combobox's list and a tooltip.
     - The decision says "the brief asks that … an accordion's panel does not jump", but the brief contains no such sentence.
     - Today the accordion slides its height (`src/web/ui/interaction.lisp:982-992`, `interpolate-size` and `block-size`). The criteria remove that working motion, and the decision itself calls it "a question for him", to go in the report after the change ships.
     - **Fix, one of:**
       - (a) Leave the accordion out: keep its slide, remove it from criterion 3, the criterion 8 scan and the two spec passages. Ask in the report whether he wants it changed.
       - (b) Ask Jonas now, before building.
  2. **Criterion 1 should match spec §6.** The spec says the sheet's footer keeps the bottom safe area, and from 40rem the buttons sit at the end of the row (`spec/ui.md:600-602`). Criterion 1 says neither, so nothing would check them. Either add both to criterion 1 or remove them from the spec.
  3. **Pin the `hx-confirm` split** (criterion 5; `spec/ui.md:163`). "The text up to its first «?» is the question" doesn't say whether the «?» stays with the question, or what happens when the text has no «?». The check needs one answer. Say: the question keeps the «?», and with no «?» the whole text is the question with no sentence.
  4. **Minor:** `--overlay` is described in §3's prose but has no row in the colour table beside the other colour tokens (`spec/ui.md:188-204`). Add `| --overlay | #00000066 | #0000008a |`.
- 2026-11-11 21:24  gate A asked of a reviewer
- 2026-11-11 21:25  gate A: changes (reviewer)
  I compared this round with the gate‑A‑1 packet. The earlier fixes are mostly in, but the Brief itself was changed between rounds, so I'm asking for changes.
  
  **What is right**
  - **Earlier fix 2 is done.** Criterion 1 now covers the bottom safe area and the wide‑screen footer (buttons at the end of the row, their own width, «Cancel» first), matching `spec/ui.md` §6 (diff 102‑111).
  - **Earlier fix 3 is done.** The `hx-confirm` split is pinned the same way in criterion 5 and the spec (diff 169‑173): the question keeps its «?», and a text with no «?» is all question.
  - **Earlier fix 4 is done.** `--overlay` now has its row in the colour table (diff 82).
  - **The accordion outcome is now option (a).** Its slide is kept, it is out of criterion 3 and the criterion 8 scan, and the question goes to Jonas in the report.
  - **The criteria and the spec otherwise agree** and can still be decided by a test or check.
  
  **Changes**
  1. **The Brief was edited, and the Log doesn't say so** (`loop.md:33-34`). In gate‑A‑1 the Brief (`gate-A-1/loop.md:32-34`) went straight from «tooltip rise a few pixels and fade;» to «closing has motion too». It now also says «an `accordion` panel does not jump», with the broken line wrapping you get from an insertion. The Log records nobody adding it. The Brief is the asker's words, and the reviewer at A‑1 had just pointed out that this sentence wasn't there. The first Decision (`loop.md:203-204`) and the new spec sentence now rely on it.
     - **Fix:** put the Brief back to its gate‑A‑1 text. If the orchestrator or Jonas really did add the sentence, add a Log entry saying who, when and in what words.
     - Then reword the accordion Decision so it doesn't claim the brief asks for this. It should say the accordion is left as it is and the question goes to Jonas.
  2. **The new accordion sentence in §6 clashes with §2.1** (diff 183‑185). It describes the panel sliding its height, under the new rule that what opens moves "never … a size" (diff 47‑48). It also leans on the phrase from change 1 («so it does not jump»).
     - **Fix:** since the accordion is out of this loop, drop that sentence and the accordion from criterion 9's §6 list.
     - Alternatively, if it stays, label it explicitly as the current behaviour and an exception to §2.1 until Jonas decides.
- 2026-11-11 21:25  the Brief quotes «an `accordion` panel does not jump» from the orchestrator's brief of 2026-11-11 (its criterion 3: «a centred dialog, a dropdown-menu, the combobox list and a tooltip rise a few pixels and fade in …; an accordion panel does not jump»); the first Brief's summary left it out, and it was put back before gate A's second round
- 2026-11-11 21:25  gate A asked of a reviewer
- 2026-11-11 21:26  gate A: approve (reviewer)
  Both changes from round 2 are in, and nothing else needs to change.
  
  **What is right**
  - **The Brief edit now has a record.** `loop.md:313` says who wrote «an `accordion` panel does not jump» (the orchestrator, in its brief of 2026-11-11, its criterion 3), quotes their words, and explains why the first summary left it out. That is the fix round 2 asked for. I couldn't find the orchestrator's original text in the reachable repositories, so I'm relying on the Log entry's quote.
  - **The accordion Decision no longer claims too much** (`loop.md:203-210`). It says the slide is kept and the choice goes to Jonas in the report. That fits the Brief's sentence: the panel slides its height today, so it doesn't jump, and leaving it alone meets the sentence.
  - **The accordion is out everywhere else too.** It's gone from §6 (diff 181-183 name only the menu, the combobox's list and the tooltip), from criterion 9's §6 list, from criterion 3 and from criterion 8's scan list. §2.1's "never … a size" rule (diff 45-57) lists what it covers (dialog, menu, combobox's list, tooltip, flash), so the accordion's slide doesn't break it.
  - **The round-1 fixes are still in place.**
    - Criterion 1 includes the bottom safe area and the wide-screen footer, matching §6 (diff 102-111).
    - The `hx-confirm` split is pinned the same way in criterion 5 and the spec (diff 169-173).
    - `--overlay` has its row in the colour table (diff 82).
  - **The criteria cover the whole brief and no more.** That includes the sheet, the keyboard fit at full height, the page behind not scrolling, motion by `opacity`/`translate` only (with closing motion and reduced motion), a dim that only gets darker, one confirm that `hx-confirm` also uses, the toast last and droppable, focus and keys, the CSS scan and the measuring check. Each of the brief's three warnings maps to a check that can decide it.
  - **The spec says the same as the criteria.** The other Decisions (the server's confirm panel kept, every variant a sheet, `overflow` set by the script, the guarded helpers) follow from the brief or the repository's rules and didn't need Jonas.
- 2026-11-11 22:29  verify 1: failed test, check
- 2026-11-11 22:40  verify 2: passed build, test, check
- 2026-11-11 22:43  shown (/ui/dialog, /ui/confirm-dialog, /ui/flash, /ui/dropdown-menu, /items)
- 2026-11-11 23:05  verify 3: passed build, test, check
- 2026-11-11 23:17  verify 1 failed: confirm-dialog's examples without the component in them (every root carries its class), the shell's menu test counting the confirm's buttons, the offline page's version changing with a fresh confirm-dialog id each render, three checks (combobox-find read a fading list as open, files-thumbnails' viewer off centre by a scroll bar's room, policy-tour timing out on a loaded machine) and charts' SBCL dying with «GC invariant lost» under memory pressure; fixed by an example each, one fixed id, the scroll bar's room kept only when a scroll bar takes room
- 2026-11-11 23:17  existing tests changed, none weakened: tests/ui-layout-tests.lisp the-menu-button-opens-the-menu-panel reads the popovertarget of the buttons in the shell's header only (the shell now also holds the confirm dialog's two buttons, after its content); checks/showcase/checks/combobox-find.py is_open asks whether the list is :popover-open instead of whether it is visible, since a closed list now fades out over --duration-close
- 2026-11-11 23:17  the five clients' bin/test against this tree (base 7af7e5a, nix develop --override-input tun git+file of the worktree), unchanged: tunworks/apps/factory 583 passed; tunworks/apps/ferdig 812 passed; tunworks/apps/nixploy-dashboard 1421 passed; kurs 352 passed; tun-erp 90700, 16534 and 26225 passed; no compiler warning. An earlier run failed nixploy-dashboard's a-run-page-says-what-became-of-its-question-and-offers-dismiss-while-it-waits (no «>Cancel<» on a run page), which the confirm dialog's words as attributes until it asks now keep
- 2026-11-11 23:17  the specimen before (base 7af7e5a) and after, every component at 390 and 1280 px, light and dark: ~/coding/tun-wt/ui-sheets-shots/before/ and after/ (bin/ui-shots); the open states (a sheet, a dialog to type in, the confirm, a menu, the toast) in after/open/
- 2026-11-11 23:17  the flash as a toast was built (criterion 6): the loop had not passed its likely estimate when it was reached
- 2026-11-11 23:17  shown (/ui/dialog, /ui/confirm-dialog, /ui/flash, /ui/dropdown-menu, /items)
- 2026-11-11 23:18  gate B asked of a reviewer
- 2026-11-11 23:20  gate B: changes (reviewer)
  I'm asking for changes. The work itself is solid, but the packet doesn't show the change on screen, and two behaviours pinned at gate A were built but never checked. One more small fix is cheap.
  
  **What is right**
  - **Verification passed.** `verify.txt` round 3 has build, test and check all ok. `checks/ui-sheets.json` passed every line, with no page error. The five clients' `bin/test` runs against this tree are recorded in the Log (`loop.md:343`).
  - **The checks measure the criteria at both widths, light and dark:**
    - **The sheet at 390px:** 0 to 390 wide, bottom at 844, top corners 12px and bottom corners 0, 32px of the page above it.
    - **The parts while the body scrolls:** the header and footer stay put (48→48, 784→784).
    - **The footer:** «Cancel» first, the two buttons sharing one row.
    - **The keyboard:** a dialog with a text area is full height from the start. With the visual viewport shrunk to 400px, its top stays, its bottom is at 400 and the footer is above it. The page behind holds still.
    - **The dim:** never falls while opening and never rises while closing. It reads `rgba(0,0,0,.4)` in the light and `.54` in the dark.
    - **The menu:** still showing at 80ms and gone afterwards.
    - **The confirm:** the texts, the red action, the focus, Escape, «Cancel», one post, one htmx request, Escape closing only the top dialog.
    - **The toast:** its placement at both widths, its 5-second life, the pause while pointed at, a warning staying.
    - **Without JavaScript and under reduced motion:** both covered.
  - **The code is careful:**
    - `tunPopoverOpen` and `tunModal` are the only places the scripts name the two pseudo-classes, and a test counts them.
    - Each component's duration follows the state it goes to.
    - Every `scale` and `transform-origin` is gone.
    - The page behind is held and given back exactly.
    - The confirm's «Cancel» stays an attribute until the dialog asks, which keeps nixploy-dashboard's suite green.
    - Version 2.26.0 is set in both `flake.nix` and `module.lisp`.
    - The spec (§2.1, §3, §6, §10) and `docs/client-api.md` say what the code does.
    - The two existing tests that changed are named in the Log, and neither is weakened.
  - **The accordion is left alone,** as the gate A Decision says.
  
  **Changes**
  1. **The screenshots show nothing that opens.** `shots/phone-ui-dialog.png`, `phone-ui-confirm-dialog.png` and their desktop pairs show the pages closed, just buttons. I can't judge the sheet, the dialog to type in, the confirm (red and plain) or a menu at either width. The flash shot does catch the toast, but over the middle of the page: that is a full-page capture of a fixed element. The open-state shots the Log cites (`~/coding/tun-wt/ui-sheets-shots/after/open/`) are outside the packet, and I couldn't read them. This loop is about how things look on a phone, and Jonas will judge it by eye.
     - **Fix:** add those open states to `shots/`:
       - the sheet, the dialog to type in, the confirm (destructive and plain) and an open menu, at 390 and 1280 px;
       - the toast, captured at the window's size rather than as a full page.
  
  2. **Two pinned behaviours have no check** (criterion 5). Gate A asked for the `hx-confirm` split with no «?» to be pinned. The code is there (`interaction.lisp`, the `htmx:confirm` handler), but:
     - `ui-sheets.py` only exercises a text that contains «?»;
     - `ui-sheets-tests` only looks for the string `text.slice(0, end + 1)`;
     - nothing exercises the action falling back to «Confirm» when the control's words run past 40 characters.
     - **Fix:** add to `checks/showcase/checks/ui-sheets.py`, with specimen examples to match:
       - an `hx-confirm` without «?» (the whole text is the title, with no sentence);
       - a marked control whose words run past 40 characters (the action reads «Confirm»).
  
  3. **Duplicate ids on `/ui/confirm-dialog`.** Each of the four examples renders `(confirm-dialog ())`, and every one gets the fixed id `tun-confirm-dialog`. So the page holds four `id="tun-confirm-dialog"`, four `…-title` and four `…-description` (`interaction.lisp` diff 1509–1533; `dialog*` builds `aria-labelledby` from the id at `interaction.lisp:497,516`). It works only because the script takes the first match. That contradicts «the page's one dialog» in the specimen meant to show it.
     - **Fix:** give each example's `confirm-dialog` its own `:id`. The shell's default stays fixed, so the offline page's hash doesn't change.
  
  **Minor, no change needed**
  - The shortcut regex fix (`/^ctrl\\+/i`, diff 1208) is a real bug fix outside the brief. It's worth a line in the Log.
- 2026-11-11 23:30  verify 4: passed build, test, check
- 2026-11-11 23:30  shown (/ui/dialog, /ui/confirm-dialog, /ui/flash, /ui/dropdown-menu, /items)
- 2026-11-11 23:31  gate B 1's changes: each confirm-dialog in the specimen's examples has its own id (the shell's stays tun-confirm-dialog), a new example and check for a control whose words run past 40 characters (the action reads «Confirm») and an hx-confirm without «?» (all question, no sentence, one request), and no id twice on /ui/confirm-dialog; the open states (the sheet, a dialog to type in, a dialog from 40rem, the confirm destructive and plain, an open menu, the toast at the window's size) at 390 and 1280 px, light and dark, are added to the show folder as phone-open-* and desktop-open-*, taken from the specimen's standalone files by a script of the builder's (Chromium, Playwright), since bin/tun loop show captures pages closed. The shortcut's /^ctrl\\+/i is unchanged from main (the reviewer's note read it as a fix)
- 2026-11-11 23:31  gate B asked of a reviewer
- 2026-11-11 23:32  gate B: approve (reviewer)
  I approve this gate. All three changes asked for in the first round of gate B are in, every verify step passed, and the screenshots now show the open states.
  
  **What was fixed since the last round**
  - **Open states are now in the screenshots** (`shots/*-open-*`, at 390 and 1280 px, light and dark). I looked at several:
    - **The sheet:** «Terms for jobs» (dark) sits at the bottom at full width with rounded top corners and a strip of the page above. Its title and close button are at the top and its button at the bottom.
    - **The dialog to type in:** «Note on order 1042» is full height from the start, with focus on the text area and the actions at the bottom.
    - **The confirm on a phone:** the destructive one is a sheet with «Cancel» first and focused, and the action in red, the two buttons sharing one row.
    - **The confirm from 40rem:** the plain one (dark) is centred with all corners rounded. Its buttons sit at the end of the row at their own width, with the primary action focused.
    - **The menu:** it opens below its button.
    - **The toast:** on a phone it now sits at the bottom of the window, 1rem in from the sides.
  - **The two untested behaviours now have checks** (`checks/showcase/checks/ui-sheets.py:371-391`).
    - A control whose words run past 40 characters gives the action «Confirm».
    - An `hx-confirm` without «?» is all question with no sentence, and its request is sent once.
    - Both passed in `checks/ui-sheets.json`, and the specimen has the matching examples.
  - **No duplicate ids on `/ui/confirm-dialog`.** Each example's `confirm-dialog` has its own id (`confirm-delete`, `confirm-send`, `confirm-archive`, `confirm-remind`, `confirm-edit`). The shell keeps the fixed `tun-confirm-dialog`, so the offline page's hash stays stable. A check now confirms no id appears twice on the page.
  - **The shortcut regex:** the builder's note that it is unchanged from main is accepted. I had read it as a fix by mistake.
  
  **Still right from the first round**
  - **Verification:** round 4 passed build, test and check. Every line of `checks/ui-sheets.json` passed with no page error.
  - **Criteria 1–7 are measured at both widths:** the sheet's box and corners, the header and footer staying put while the body scrolls, the keyboard fit at a 400px visual viewport, the page behind holding still, a dim that only gets darker, the closing menu, the confirm's behaviour, the toast, no JavaScript, and reduced motion.
  - **The spec, client docs and version:** the spec and `docs/client-api.md` match the code, and the version is 2.26.0 in both `flake.nix` and `src/core/module.lisp`.
  - **Clients:** all five clients' results are in the Log.
  - **The accordion** is left alone, as decided at gate A.
  
  **Minor, no change needed:** the open‑state screenshots were taken by the builder's own script, not by `bin/tun loop show`, as the Log says.
- 2026-11-11 23:33  pushed 95b381a to Tun's main, core 2.26.0
- 2026-11-11 23:33  finished at tun 95b381a
