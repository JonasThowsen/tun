# The look and states of Tun's components: grounds, edges, focus, pressed, chosen, buttons, badges

- loop: ui-look
- mode: reviewed
- stage: ship
- base: 31baa9989256c38e4f073a6692d2f20e6947ba24
- item: sak_s77vyp4103cr54ze
- estimate: 1h30m 2h30m 5h
- like: ui-graph loading-sign ui-graph-fit
- tags: kind:ui core module:ui
- verified: f05fe923a3b081db8549dad180b065def49cb4a2
- shown: f05fe923a3b081db8549dad180b065def49cb4a2

## Brief

Ferdig sak_s77vyp4103cr54ze, under «Software factory», brought by the
factory's orchestrator on 2026-11-11. Jonas, 2026-11-11: he has
polished the admin UI of another application of his for two weeks and
wants the best of it carried into Tun's component library, «to make the
UI component Library of Tun superb». The source is the owner's rules for
an admin application, 2026-11-10 and 2026-11-11.

This loop is the first of several: the look and the states of the
existing components (tokens, edges, radii, type, focus, pressed, chosen,
buttons, badges). Later loops, not this one: dialogs as bottom sheets
with opening motion, the page header and the shell, filters, lists on a
phone, search, date fields.

What must hold, from the orchestrator: every component keeps its call
shape, so the five clients compile and render unchanged; the token names
stay shadcn's, and tokens may be added. Grounds (page, panel, chrome),
one 1px edge and a stronger one, two radii, text sizes and a muted text
at 72 % of the text colour, an ink primary button and an accent for
focus, on and selection, a two-layer focus ring, a light panel shadow and
no frame in a frame, motion tokens, a pressed state on every tappable
thing and hover only under `(hover: hover)`, choosing that moves
nothing (pinned by a test and a browser check), the destructive button as
red words without a fill, frameless icon-only buttons decided by their
attributes, 44px targets on a coarse pointer, and one soft badge in five
tones. Warnings from where the rules were learned: bold on the chosen
item moved its neighbours and was fixed four times; `:has()` could not
tell an icon-only button since text nodes are invisible to selectors; a
grey page with white boxes and 2px edges read as heavy and was dropped;
hover outside `(hover: hover)` sticks on phones.

Mode: reviewed. A core change, a minor version.

## Criteria

1. **Grounds.** The tokens hold three grounds: `--background` (page)
   `#ffffff` / `#19191c`; `--card` and `--popover` (panels) `#ffffff` /
   `#19191c`; new `--chrome` `#f6f6f7` / `#111113` with `--chrome-border`
   `#0000000f` / `#ffffff12`; and new `--input-background` `#ffffff` /
   `#141417`. The `app-shell`'s top bar, phone menu and desktop sidebar
   stand on `--chrome` with `--chrome-border` as their edge; the shell's
   layout does not change. (`ui-look-tests`: token values and the shell's
   CSS; `ui-look.py`: the sidebar's computed ground is the chrome's.)
2. **Edges and radii.** `--border` is `#0000001f` / `#ffffff24`;
   `--border-strong` the text colour at 26 % / 30 %. Every edge width in
   the stylesheet is 1px or 0, but three marks (the checkbox's tick, a
   graph node's tone stripe, the confirm panel's «!»). `--radius-md` is
   0.5rem (controls), `--radius-lg`, `--radius-xl` and `--radius` 0.75rem
   (panels), `--radius-full` for pills, `--radius-sm` 0.375rem for a part
   inside a padded control; every `border-radius` in the stylesheet is
   one of these tokens, 0 or `inherit`. `--input`, the edge of a field, a
   box to tick and a switch's track, is the text colour at 50 % / 40 %
   (`color-mix(in oklab, var(--foreground) 50%, transparent)` and 40 %),
   and the test computes it at 3:1 or more on the page, the panels, the
   chrome and a field's ground, in both schemes (but see Decisions: the
   asker is asked). In the specimen at 390 and 1280
   px, light and dark, no element with an edge on all four sides has a
   square corner, but the joined sides of a button group's parts.
   (`ui-look-tests`, `ui-look.py`)
3. **Text.** `--foreground` `#171717` / `#ededed`; the body's text, and
   the running text of `card`, `dialog`, `summary-list`, `timeline`,
   `tabs`' panel, `accordion`'s content and `confirm-panel`'s body, is
   0.875rem on 1.375rem (`--text-running`); controls 0.875rem on 1.25rem
   (`--text-sm`); meta 0.75rem on 1rem (`--text-xs`); fields 1rem on a
   coarse pointer (`--control-font-size`, unchanged). `--muted-foreground`
   is `color-mix(in oklab, var(--foreground) 72%, transparent)`, and the
   test computes its contrast, at least 6.5:1 (above AA's 4.5:1), on the
   page, the panel, the chrome, a field's ground and `--muted`, in both
   schemes. No rule in the stylesheet sets `text-transform: uppercase` or
   a positive `letter-spacing` (the specimen's group headings and the
   `dropdown-menu`'s shortcut hint lose theirs), which covers the
   `nav-list` heading the shell's «System» group is written in; in the
   browser, that heading on a staff page has `text-transform: none` and
   `letter-spacing` normal. (`ui-look-tests`, `ui-look.py`)
4. **Accent and focus.** `--primary` stays ink (`#171717` / `#ededed`).
   New `--highlight` `#005ff2` / `#47a8ff` (with `--highlight-foreground`
   and `--highlight-soft`) is `--ring`, the fill of a checked checkbox
   and radio and of a switch that is on, and the ground of selected text.
   Every rule that uses `var(--ring)` or `var(--highlight…)` (or a focus
   ring token) is one of: a focus rule (`:focus`, `:focus-visible`), a
   checked or on state (`:checked`), the text selection (`::selection`),
   or a drop target (a board's column a card is dragged over, a file
   field something is dragged over); the test reads every declaration
   for it. The attachments' tiles turn `--border-strong` under a
   pointer, not `--ring`. `--focus-ring` is `0 0 0 2px var(--background),
   0 0 0 4px var(--ring)`, and the chrome sets it with `var(--chrome)` as
   the gap; every `:focus-visible` rule that sets a box-shadow sets
   `var(--focus-ring)`, or `var(--focus-ring-inset)` (`inset 0 0 0 2px
   var(--ring)`) for a row or a line of tabs that fills its box. A
   focused button in the specimen has that computed shadow. The accent
   is at least 4.5:1 on the page and 3:1 on the chrome, in both schemes,
   computed. A link in running text (no class) keeps the base rule
   `:focus-visible { outline: 2px solid var(--ring); outline-offset: 2px;
   }`, the same shape drawn by the browser. (`ui-look-tests`,
   `ui-look.py`)
5. **Panel shadow.** `--shadow-panel` is `0 1px 2px light-dark(rgb(0 0
   0 / 0.04), transparent), 0 2px 8px light-dark(rgb(0 0 0 / 0.03),
   transparent)`: the given shadow in the light, none in the dark. `card`,
   `stat`, a `table`'s and a `markdown` table's rows as cards on a phone,
   `flash`, `confirm-panel`, a `board`'s card and a `graph`'s node use it;
   `card` and `stat` have a real 1px edge (`--border`) instead of a ring
   of shadow. New `--soft` (the text colour at 5 %) is the ground for a
   group inside a panel. The frames in frames in the components' own
   markup are listed under Decisions. (`ui-look-tests`)
6. **Motion tokens.** `--ease` `cubic-bezier(0.16, 1, 0.3, 1)`,
   `--duration-fast` 150ms, `--duration` 200ms, new `--duration-sheet`
   280ms and `--duration-close` 160ms; all four are 0ms under
   `prefers-reduced-motion: reduce`. Every `transition` and
   `transition-duration` in the stylesheet names a duration token, or 0s
   for a pressed state (and the base's reduced-motion rule).
   (`ui-look-tests`)
7. **Pressed.** New `--pressed`: the text colour at 8 % / 10 %. An
   `:active` rule gives a pressed look, a tint or a ground, at once, to:
   `button` (every variant: `--pressed` laid over its ground; `:primary`
   a lighter fill), `card` with `:href`, a `table` row with a link and
   its sortable header, a `nav-list` entry, a `tabs` tab, a
   `dropdown-menu` item, a `combobox` option, an `accordion`'s summary,
   and so `pagination`'s links (buttons); and to the links that had only
   a hover: `link`, `breadcrumbs`' links, `summary-list`'s action,
   `error-summary`'s and `form-actions`' links, `flash`'s close button,
   a `board` card with a link, a `graph` node with a link and the
   `attachments`' tiles. Those of the first list whose element has a
   transition set `transition-duration: 0s` in it. A scan pins it for
   what comes next: every component whose CSS has a `:hover` rule has an
   `:active` rule, but `tooltip`, which shows on hover and has no tap of
   its own. Every `:hover` in the stylesheet is inside `@media (hover:
   hover)` (the attachments' tiles were not). (`ui-look-tests`: the
   named rules, the scan and the hover scan)
8. **Choosing moves nothing.** No rule in any component's CSS whose
   selector holds a chosen state (`[aria-selected='true']`,
   `[aria-current…]`, `[aria-pressed='true']`, `[aria-checked…]`,
   `[aria-expanded='true']`, `[aria-sort…]`, `:checked`), outside a
   `:not()` and not on `::before` or `::after`, sets `font-weight`,
   `font`, `font-size`, `letter-spacing`, `padding…`, `margin…`, `width`,
   `height`, `min-…`/`max-…` sizes, `border-width` or a `border…`
   shorthand with a width; a test reads every component's CSS for it (the
   `nav-list`'s current entry and the specimen's current link lose their
   heavier weight). In the browser, on `/ui/tabs` at 390 and 1280 px,
   pressing each tab in turn leaves the box of every tab of its list
   where it was (to 0.5px), and the chosen tab, the current `nav-list`
   entry and `pagination`'s current page have the computed font weight of
   their siblings. (`ui-look-tests`, `ui-look.py`)
9. **Buttons.** The variants keep their names. `:destructive` has
   `--background` as its ground, `--border` as its edge and
   `--destructive` as its colour: no rule sets a red or tinted fill on it,
   and the confirm panel's destructive submit no longer fills itself red.
   An icon-only button (`data-size` starting with `icon`) of
   `:outline` has a transparent edge and a transparent ground at rest, by
   a selector on `data-size` and `data-variant` (no `:has()`). When
   `aria-pressed`, `aria-current` or `aria-expanded` is true, and as a
   part of a `button-group`, it has its visible edge (`--border` or
   `--border-strong`) and its ground again. `:ghost` already has neither
   at rest; `:primary` keeps its fill. On a coarse pointer, every button on `/ui/button` is a
   target of at least 44×44px: its box with the invisible area of the
   sizes `:xs`, `:sm`, `:icon-xs` and `:icon-sm`. (`ui-look-tests`,
   `ui-look.py`: the computed ground and colour of «Delete», the
   frameless «Edit» and the framed «2», the targets on a phone)
10. **Badge.** `badge` is a fully round pill with no edge, a tinted ground
   and text: `:neutral` (the new default) `--foreground` on `--muted`,
   and `:info`, `:success`, `:warning`, `:destructive` as `--TONE` on
   `--TONE-soft`; `:primary`, `:secondary` and `:outline` render the
   neutral tone. The status tokens are hex values, and the test computes,
   in both schemes, 4.5:1 or more for each tone's text on its ground,
   for `--TONE` on the page, and for `--TONE-foreground` on `--TONE`. Its `:doc` and spec §6 name the five
   meanings. The `graph`'s badges keep working. (`ui-look-tests`,
   `ui-actions-tests`)
11. **The spec.** `spec/ui.md` §1 says the look is Tun's own after its
   owner's rules of 2026-11; a new §2.1 «The look» states criteria 1–9 as
   rules; §3 lists the new tokens and their values; §6 the button's and
   the badge's rules; §10 the evidence. `docs/client-api.md` lists no
   tokens or variants, so it is unchanged. The core version is 2.25.0 in
   `src/core/module.lisp` and `flake.nix`.
12. **Clients unchanged.** No `define-component` in the diff changes
   its lambda list or refuses a value it took before (the badge's default
   changes from `:primary` to `:neutral`, both taken, and the markup's
   `data-variant` of a badge without one is `neutral`). The five clients
   (`tunworks/apps/factory`, `tunworks/apps/ferdig`,
   `tunworks/apps/nixploy-dashboard`, `kurs`, `tun-erp`) build and pass
   their own `bin/test` against this tree, unchanged, with `--override-input
   tun` to the loop's commit; each result is in the Log.
13. **Evidence.** A new `tests/ui-look-tests.lisp` pins criteria 1–10 as
   above; `checks/showcase/checks/ui-look.py` checks them in a browser
   on the specimen. Every existing test and check stays green, none
   weakened; a test that pinned an old value is changed to the new one
   and named in the Log.

## Decisions

- **The accent is a new token, `--highlight`, not shadcn's `--accent`.**
  In shadcn's themes `--accent` is the quiet ground under a pointer, and
  Tun's menus, combobox and nav list use it so; making it blue would turn
  every hover blue and break a shadcn theme laid over Tun. `--accent`
  stays the hover ground, now a tint of the text colour so it shows on
  the chrome too; `--ring` is `--highlight`.
- **A field's edge stays at 3:1, not the panels' 12 %.** Spec §2 holds
  Tun to WCAG 2.2 AA, and 1.4.11 asks 3:1 for what identifies a control:
  the edge of a text box, a box to tick and a switch's track is all there
  is of them. So `--input` (shadcn's name for exactly that edge) is the
  text colour at 50 % / 40 %, about 3.2:1 on the page and the chrome, and
  the one-edge rule of 1px and 12 % holds for buttons, panels and
  dividers. Still 1px, as the brief asks. This bends the brief, so it is
  the asker's to decide: asked on the item, 2026-11-11 (question
  `kom_aya5hm22rm0cf80b`: A, 12 % as the panels, or B, 3:1). Until he
  answers, the loop builds B, which keeps today's strength of these
  edges; A is a change of the one token `--input` and its test's floor,
  and the answer is recorded in the Log.
- **Hex values for the status colours.** The test computes contrast from
  the token values; oklch values would need a colour conversion in the
  test. The tones are the owner's, with destructive's text and soft
  ground chosen so text meets 4.5:1 on its tint (`#d8001b` on `#ffeeef`,
  4.8:1). The badges then need no mix towards the text colour.
- **`--radius-sm` is the control's radius less 2px**, for a part inside a
  padded control or menu, so their corners stay concentric; the brief's
  two radii are the control's and the panel's. `--radius-lg` and
  `--radius-xl` both become the panel's 0.75rem, so each component's
  choice between them stops mattering.
- **Pressed and hover as a tint over the ground** (`background-image` of
  `--accent` or `--pressed`), so a button keeps its own ground under the
  tint and every variant answers alike; the primary's fill turns lighter
  instead, as a tint of ink would not show.
- **Hover and pressed keep a frameless icon button frameless**: only its
  ground shows, as the owner's rule says; chosen (`aria-pressed`,
  `aria-current`, `aria-expanded`) it keeps its frame, which is how a
  current page in `pagination` (outline, `:icon`) still shows.
- **The current `nav-list` entry** is a panel of the page's ground in its
  frame on the chrome, instead of a heavier weight on a grey fill: on the
  chrome a grey fill would be near the hover's, and the frame shows on
  any ground.
- **The segmented `tabs`' chosen tab** has the edge in both schemes now
  (it was transparent in the light): on a white tab over a grey list the
  edge is what makes it read as chosen in either.
- **Running text** is a new token, `--text-running`, so `--text-sm`'s
  line height stays the controls' 1.25rem. `alert` keeps the controls'
  size: its icon is centred on a 1.25rem line.
- **`--shadow-panel` uses `light-dark()` on its colours**, so the one
  token is the given shadow in the light and nothing in the dark.
- **Card and stat get a real 1px edge** instead of a ring of shadow: a
  border survives forced colours, where box shadows are dropped. The
  floating layers (dialog, menu, combobox list, chart tooltip) keep their
  ring, now `--border`, beside their large shadow.
- **The confirm panel's red fill goes.** It was the one solid red
  button, after GOV.UK's warning button; the brief says the destructive
  button is never a red fill, and the panel's submit is that button.
- **Loops keep an even easing.** The new `--ease` is an expo-out for
  changes of state; the progress bar, the loading sign and the graph's
  pulse run forever and would lurch on it, so they use `ease-in-out`
  with a comment.
- **Frames in frames in a component's own markup:** none found that is
  plainly one. Checked: `card` (header, content and footer unframed),
  `alert`, `flash`, `confirm-panel` (its icon on a soft round ground),
  `code-block` (a divider under its header), `dialog` (its icon on a
  soft ground), `file-input` (the browser's file button in the dashed
  zone is a control, not a frame), `table` and `markdown` (rows are
  cards only where the table has no frame), `board` (cards on a soft
  column), `timeline`, `attachments`, `graph`. `--soft` is there for the
  next loops' groups.
- **Strips of tabs in the shell** do not exist yet (the shell is the next
  loops'); `tabs` in a page stays on the page's ground.
- **Not in this loop, needing the next ones:** the dialog's opening
  motion as a sheet (`--duration-sheet` and `--duration-close` are
  defined for it), the page header, the theme colours of an installed
  app (spec §4.2, still `#ffffff` / `#0a0a0a`, which the shell's chrome
  loop should match to `--chrome`), filters, lists, search, dates.
- **Core version 2.25.0**, the next minor after 2.24.0 (taken on main by
  another loop while this one ran): new tokens, a new badge default and
  a changed look; no call shape changes.

## Log

- 2026-11-11 19:03  started, reviewed
- 2026-11-11 19:04  estimated 1h30m 2h30m 5h at brief, like ui-graph loading-sign ui-graph-fit
- 2026-11-11 19:21  gate A asked of a reviewer
- 2026-11-11 19:22  gate A: changes (reviewer)
  I'm asking for changes. The criteria cover most of the brief and nearly all of them can be decided by a test or a check. But criterion 9 contradicts the spec and Decisions, one of the brief's limits isn't a criterion, and the spec makes some promises nothing tests.
  
  **What's right**
  - Criteria 1–10 match the brief's list one for one: three grounds, one edge and a stronger one, two radii, the text sizes, muted text at 72 %, an ink primary button, the accent, the two-layer focus ring, the panel shadow, motion tokens, pressed states, hover only under `(hover: hover)`, choosing that moves nothing (pinned by a test and a browser check), the destructive button as red words, frameless icon-only buttons decided by attributes without `:has()`, 44px targets, and one badge in five tones.
  - Each criterion names a test or check that could decide it.
  - Later loops' work is kept out.
  - I checked a sample of the colour values by hand and the claims hold:
    - The accent: about 5.4:1 on white and about 6.9:1 on `#19191c`.
    - The badge tones: destructive about 4.75:1, warning about 5.1:1, success about 4.75:1, info about 4.9:1.
    - Muted text: about 7.1:1 on the page and about 6.8:1 on `--muted`.
    - The chart's new 4.8:1 against `#19191c`.
  - Most of Decisions are reasonable choices to leave to the builder:
    - `--highlight` instead of reusing shadcn's `--accent`.
    - Hex values for the status colours.
    - `--radius-sm`.
    - The confirm panel losing its red fill, which the brief requires.
  
  **Changes**
  
  1. **Criterion 9 says the opposite of the spec and Decisions.** It says an icon-only `:outline` button "has a transparent edge and ground at rest … keeps them when `aria-pressed`, `aria-current` or `aria-expanded` is true, and keeps them in a `button-group`". Read plainly, "them" is the transparent edge and ground. But the Decisions entry ("chosen … it keeps its frame") and the new paragraph in `spec/ui.md` §6 (diff lines 187–191: "keeps its frame … in a `button-group` the parts keep the group's frame") say a chosen button and a grouped button keep their **frame**. The same criterion's browser check also expects a "framed «2»" in pagination. Reword criterion 9 so it says a chosen or grouped icon-only outline button keeps its edge, and the test then pins the same thing as the spec.
  
  2. **The brief's first limit has no criterion.** The brief says "every component keeps its call shape, so the five clients compile and render unchanged". Only "the variants keep their names" (criterion 9) and "existing tests stay green" (criterion 12) come near it. Neither checks the five clients, and verify doesn't build them (`spec/loop.md` §verify). Add a criterion that no component's arguments or accepted values change, and that the five clients build and their checks pass against the new core. The Log should record each client's result.
  
  3. **The `--input` decision belongs to the asker, and the criteria don't pin it.**
     - **It's the asker's call.** The brief asks for "one 1px edge and a stronger one". The owner also warned that heavy edges read as heavy. The builder makes the field, checkbox and switch edges 50 % / 40 % of the text colour, much heavier than `--border-strong` (26 % / 30 %), and the Decisions entry says "the orchestrator is told". The WCAG 1.4.11 reasoning is sound, but this changes how every form looks, against the asker's explicit look rule. In reviewed mode it should be put to the asker at this gate, not just reported.
     - **No criterion tests it.** Neither the value nor the claimed 3:1 on the page and the chrome is in any criterion, yet `spec/ui.md` §2.1 and the §3 table state both (diff lines 42–44 and 131). Add both to criterion 2 or 3 for `ui-look-tests`.
  
  4. **The spec promises things no criterion tests.** Either add them to the criteria or take them out of the spec:
     - Diff line 58 says muted text is "at least 6.7:1 on every ground", but criterion 3 only tests 4.5:1.
     - Diff lines 72–73 say "a link in running text has the browser's outline … 2px of the accent, 2px off". No criterion covers it.
     - Diff line 137 says `--STATUS` is at least 4.5:1 "on the page". Criterion 10 only tests it on its soft ground.
     - Diff lines 79–81 say "every control and row a person taps answers while it is pressed", but criterion 7 tests a fixed list. Either limit the spec's sentence to that list or add the rest: checkbox, radio, switch, `select` and the combobox trigger.
     - Diff line 61 names "the menu's «System» heading", while criterion 3 names "the menu's shortcut". Make them name the same thing.
  
  5. **A small one.** The new opening of `spec/ui.md` (diff line 11) cites "§2 «The look»", but criterion 11 and the heading are §2.1. That same rewrap leaves a stray short line ("Tun page looks and", diff line 12).
- 2026-11-11 19:53  gate A asked of a reviewer
- 2026-11-11 19:54  gate A: changes (reviewer)
  I'm asking for changes. The second round fixed almost everything the first review raised, but two of the brief's rules are still not covered in full. I checked the current component CSS to confirm both.
  
  **What's right**
  
  - **Criterion 9** now says plainly that a chosen or grouped icon-only `:outline` button gets its edge and ground back. That matches spec §6 (diff lines 189–195) and the Decisions entry.
  - **Criterion 12** covers the brief's first limit. No component's arguments or accepted values may change, and the five clients must build and pass `bin/test` against this tree, with each result in the Log.
  - **The `--input` choice** is now put to the asker (`kom_aya5hm22rm0cf80b`). Its value and the 3:1 floor are in criterion 2, and the Decision says that answer A changes one token and one test floor. Building B until the asker answers is reasonable.
  - **The spec's earlier untested promises** now line up with the criteria:
    - muted text at 6.5:1, in criterion 3 and spec line 62;
    - the outline on a link in running text, in criterion 4;
    - `--STATUS` on the page, in criterion 10;
    - the pressed list, limited to the named controls, with checkbox, radio, switch and field excluded and the reason given (spec lines 82–87);
    - the «System» heading, in criterion 3.
  - The stray short line is gone. The new §3 table matches criteria 1–7. Later loops' work stays out.
  
  **Changes**
  
  1. **Some tappable things have no pressed state.** The brief asks for "a pressed state on every tappable thing". Criterion 7 and spec §2.1 «Pressed» (diff lines 82–89) list only some of them. These are all links, but get nothing on press:
     - the attachments' tiles: `<a class="tun-attachments-image|file">`, `src/web/ui/files.lisp:357,364`;
     - a `board` card with a link, `src/web/ui/board.lisp:280`;
     - a `graph` node with a link, `src/web/ui/graph.lisp:462`.
  
     Criterion 7 itself names the attachment tiles, but only to say their hover is wrapped. Either add these three to criterion 7 and to the spec's list, or write a scan into the criterion: every selector with a `:hover` has a matching `:active`, except the named field controls. The scan would catch the next one too.
  
  2. **The accent appears on hover.** Criterion 4 and §2.1 «Ink and the accent» say `--highlight` is only for focus, for what is on, and for what is selected, and that `--ring` is `--highlight`. But `src/web/ui/files.lisp:400` (`&:hover { border-color: var(--ring); }`) would turn an attachment tile's edge blue under a pointer. The test as written ("no other rule uses it") may not catch this, because the rule names `--ring`, not `--highlight`. Make criterion 4 say that every use of `var(--ring)` or `var(--highlight…)` is one of:
     - a focus rule;
     - a checked or on state;
     - the text selection;
     - a drop target (`board.lisp:209`, and `files.lisp:50` if that is the file field's drag-over).
  
     Name the tile's hover as one that changes to `--border-strong`, the edge §2.1 gives "under a pointer".
  
  3. **A small one.** Diff line 23 (spec §1) still points to "§2 «The look»". The heading is §2.1, so make it "§2.1".
- 2026-11-11 19:56  gate A asked of a reviewer
- 2026-11-11 19:57  gate A: approve (reviewer)
  The three changes the last round asked for are all made, and I found nothing new that blocks the spec.
  
  **The last round's changes**
  - **Pressed on every tappable thing.** Criterion 7 now names the attachments' tiles and the `board` and `graph` cards that are links. It also adds a scan: every component's CSS with a `:hover` rule must have an `:active` rule, except `tooltip`. Spec §2.1 «Pressed» (diff lines 83–95) lists the same things, gives the same exception, and says why the checkbox, radio, switch and field answer with the browser's own state.
  - **The accent only where it belongs.** Criterion 4 now limits every use of `var(--ring)`, `var(--highlight…)` and the focus-ring tokens to four places: focus, a checked or on state, `::selection` and a drop target. It also says the attachment tile's edge under a pointer becomes `--border-strong`. §2.1 «Ink and the accent» (diff lines 65–70) says the same, drop target included.
  - **The section numbers.** Both references in §1 now point to §2.1 (diff lines 13 and 23).
  
  **Spec against the criteria**
  - The §3 table (diff lines 126–142) matches the values in criteria 1–7. The radius, focus and motion entries match criteria 2, 4 and 6.
  - The status list (diff lines 147–152) matches criterion 10: each tone's text 4.5:1 on its own ground and on the page, and its foreground on its fill.
  - §6's button and badge paragraphs match criteria 9 and 10. A chosen or grouped icon-only outline button gets its frame back, decided by `data-size` and `data-variant`, never by `:has()`.
  - §10 names both new test files and what each one pins.
  - §2.1's six grounds, `--input`, the edge limits and the text rules match criteria 1–3. The criteria still keep the brief's scope and no more. Criterion 12 covers the five clients, and the `--input` choice is still put to the asker, recorded as question `kom_aya5hm22rm0cf80b`.
  - **Contrast.** I checked the `--input` claim by hand. At 50 % in light and 40 % in dark, composited over the page, the chrome and a field's ground, it comes to about 3.3–3.5:1 in both schemes. Muted text on the dark grounds is about 7.7–8.3:1. Both are above the floors the criteria set.
  
  **Small things, none blocking; worth fixing at gate B**
  - §2.1 «Hover» (diff line 98) calls `--accent` "the text colour at 5 %", but the §3 table gives it as `#0000000d` / `#ffffff0f`. That is black or white at about 5–6 %, not the text colour. The wording should match the value the test pins.
  - §6 (diff line 196) says the frameless rule covers `:outline` and `:ghost`. Criterion 9 says `:ghost` already has no frame or ground at rest. That is consistent, but "keeps its frame" doesn't apply to `:ghost`.
  - Criterion 9's browser check mentions a "framed «2»", but doesn't say which page it is on. The §10 check list (diff lines 238–248) doesn't mention it at all.
- 2026-11-11 20:07  verify 1: failed check
- 2026-11-11 20:13  rebased: tun a4e458c → 31baa99
- 2026-11-11 20:25  verify 2: failed test
- 2026-11-11 20:31  the five clients' bin/test against this tree (base 31baa99, nix develop --override-input tun git+file of the worktree), unchanged: tunworks/apps/factory 583 passed; tunworks/apps/ferdig 812 passed; tunworks/apps/nixploy-dashboard 1404 passed; kurs 352 passed; tun-erp 16534 and 26225 passed; no compiler warning in any
- 2026-11-11 20:32  verify 2 failed on two timing tests (hostile: small bodies that trickle, files: sizes bounded per call, deadline_exceeded) while the five clients' suites ran on the same machine; neither touches the UI
- 2026-11-11 20:32  verify 2 failed on two timing tests (hostile: small bodies that trickle; files: sizes bounded per call, deadline_exceeded) while the five clients' suites ran on the same machine; neither touches the UI
- 2026-11-11 20:38  verify 4: failed test, check
- 2026-11-11 20:48  verify 5: passed build, test, check
- 2026-11-11 20:52  shown (/items, /graph, /ui/button, /ui/badge, /ui/tabs, /ui/nav-list, /ui/switch)
- 2026-11-11 20:53  the specimen before (base a4e458c) and after, every component at 390 and 1280 px, light and dark: ~/coding/tun-wt/ui-look-shots/before/ and after/ (bin/ui-shots); no existing test was changed: none pinned a value this loop changes
- 2026-11-11 20:53  gate B asked of a reviewer
- 2026-11-11 20:54  gate B: changes (reviewer)
  I'm asking for changes, but only small ones. The change does what the brief asks, and the screenshots and browser checks show it working. The gaps are in the tests: criteria 3 and 5 each say `ui-look-tests` pins a list of components, and the test pins only part of each list.
  
  **What's right**
  - **Verification passed.** All three steps of `verify.txt` passed in round 5. `checks/ui-look.json` passed all 26 of its results at 390 and 1280 px, light and dark:
    - no square corners on a box with an edge;
    - choosing a tab moves nothing, and every tab has weight 500;
    - the current nav-list entry and the current page have their siblings' weight;
    - every button on a phone is a 44px target;
    - «Delete» is red words on the page's ground;
    - «Edit» has no frame or ground at rest, and the current «2» keeps its frame;
    - a focused button shows the white gap and the `rgb(0,95,242)` ring;
    - the sidebar's ground is `#f6f6f7` / `#111113`;
    - the «System» heading is not in capitals.
  - **The screenshots match the brief.**
    - `desktop-items.png`: a grey sidebar, a white page, an ink primary button, the current nav entry as a framed white panel at normal weight, and light 1px edges.
    - `desktop-ui-button.png`: «Delete» has no fill, the icon-only buttons have no frame, and the chosen buttons have their frame.
    - `phone-ui-badge.png`: five soft tones with no edge, and the older variant names render neutral.
  - **The code is tidy.**
    - The tokens in `kit.lisp` match the §3 table and the test.
    - The destructive and confirm-panel red fills are gone, and `ui-look-tests` checks for both.
    - Icon-only buttons are told apart by `data-size`/`data-variant`, with no `:has()`.
    - The attachments' hover is now inside `(hover: hover)` and uses `--border-strong`, not `--ring`.
    - Loops use `ease-in-out`, with a comment saying why.
    - There is no leftover debugging.
    - The spec's §1, §2.1, §3, §6 and §10 change with the behaviour, and the version is 2.25.0 in both places.
  - **The clients pass.** The Log records the five clients' `bin/test` results against this tree (criterion 12).
  - **The new tests are solid.** The CSS scans (edges, radii, capitals, hover, transitions, the accent's uses, choosing moves nothing) read every declaration. The scan for a chosen state has its own test proving it catches a heavier tab and skips `:not()` and marks.
  
  **Changes**
  1. **Criterion 3's running text is only partly pinned.** The criterion lists seven components that use `--text-running`. In `tests/ui-look-tests.lisp:192`, `running-text-is-the-pages` checks only `card`, `dialog`, `summary-list` and `timeline`. It never checks `tabs` (its panel), `accordion` (its content) or `confirm-panel` (its body), which this diff changes in `interaction.lisp` and `feedback.lisp`. Add those three names to the list.
  2. **Criterion 5's panel shadow is only partly pinned.** The criterion names eight components that use `--shadow-panel`. `panels-have-the-edge-and-the-panel-shadow` (`tests/ui-look-tests.lisp:494`) checks only `card` and `stat`. Also check `table`, `markdown`, `flash`, `confirm-panel`, `board` and `graph` for `var(--shadow-panel)`. The board card's value is `0 0 0 1px var(--border), var(--shadow-panel)`, so match with `search`, not `string=`.
  
  **Not blocking, worth doing while there**
  - **Grouped icon buttons rely on rule order.** In a `button-group`, the rule that gives an icon-only outline button its frame back (`actions.lisp`, the `& > .tun-button[data-size^='icon'][data-variant='outline']` rule) has the same specificity as the rule that takes the frame away. It wins only because it comes later in the stylesheet. Nothing in a browser checks a grouped icon button, so a reordering would break it silently. A line in `ui-look.py` on `/ui/button-group` would catch that.
  - **Two comments in `kit.lisp` disagree with the spec.** The `--muted-foreground` comment says "6.7:1" where spec §2.1 and the test say 6.5. The `--highlight` comment leaves out drop targets.
  - **The `--input` question is still open.** The asker hasn't answered question `kom_aya5hm22rm0cf80b` (option A, 12 % like the panels, or B, 3:1). The loop builds B in the meantime. The answer should be in the Log before gate C.
- 2026-11-11 21:04  verify 6: passed build, test, check
- 2026-11-11 21:05  shown (/items, /graph, /ui/button, /ui/button-group, /ui/badge, /ui/tabs, /ui/nav-list, /ui/switch)
- 2026-11-11 21:05  gate B asked of a reviewer
- 2026-11-11 21:06  gate B: approve (reviewer)
  I approve this round. Both changes asked for at the last gate B are made, verify round 6 passed every step, and nothing new blocks.
  
  **Last round's changes**
  1. **Running text (criterion 3).** `running-text-is-the-pages` now checks all seven components the criterion names: `card`, `dialog`, `summary-list`, `timeline`, `tabs`, `accordion` and `confirm-panel` (`tests/ui-look-tests.lisp`, diff line 1937).
  2. **Panel shadow (criterion 5).** `panels-have-the-edge-and-the-panel-shadow` still checks `card` and `stat` for the 1px edge and the shadow. It now also checks `table`, `markdown`, `flash`, `confirm-panel`, `board` and `graph` for `var(--shadow-panel)`. It uses `search`, so the board card's combined value still matches (diff lines 2245–2248).
  
  **The non-blocking notes are also done**
  - **Grouped icon buttons.** `ui-look.py` now checks that an icon-only outline button in a `button-group` keeps its edge and ground, on `/ui/button-group` (diff lines 156–165). That check passed: edge `rgba(0,0,0,0.12)` on white for three buttons. A reordering of the stylesheet would now be caught.
  - **The two comments in `kit.lisp`.** The `--muted-foreground` comment now says 6.5:1, as the spec and the test do (diff line 1436). The `--highlight` comment now names drop targets (diff line 1457).
  
  **Verification**
  - `verify.txt` round 6: build, test and check all passed.
  - `checks/ui-look.json` passed all 27 of its results at 390 and 1280 px, light and dark.
  - The specimen's shots were taken again with `/ui/button-group` added.
  - The five clients' results are still in the Log (criterion 12).
  
  **One thing for gate C, not blocking here.** The asker hasn't answered question `kom_aya5hm22rm0cf80b` about `--input` (A, 12 % like the panels, or B, 3:1). The loop still builds B. The answer should be in the Log before deploy. If it's A, the token `--input` and the floor in `a-fields-edge-is-3-to-1` change.
  
  **A small note.** Criterion 1 says the sidebar's ground is the chrome's. The browser check reads `.tun-app-shell-header`, which at desktop width is the sidebar and has `var(--chrome)` as its ground (layout.lisp, diff line 1696), so the check does test that.
