# Five small faults the first client found on the new UI library (core 2.31.0)

- loop: ui-nits
- mode: reviewed
- stage: done
- base: b0ba1dd26db2439ab488882ab3882d92a4115223
- item: sak_60ga5rkmmj8f1ejk
- estimate: 50m 1h15m 2h30m
- like: tun/ui-header
- tags: kind:ui core module:ui
- verified: 5fb014d894da32157032a84aec54055aecd6f397
- shown: 5fb014d894da32157032a84aec54055aecd6f397

## Brief

Ferdig sak_60ga5rkmmj8f1ejk, brought by the factory's orchestrator on
2026-11-12. It follows the seven loops of the work on Tun's component
library (core 2.25.0 to 2.31.0) after Jonas's request of 2026-11-11, «to
make the UI component Library of Tun superb». The first client to move
onto core 2.31.0 found five small faults. The item, in its words:

1. `summary-list` on a phone: a long one-word label («Organisasjonsnummer»)
   runs into its value. Seen at 390 px: the label's box is narrower than
   the word and the word paints over the value beside it.
2. Search results: a record that matched only in its second line shows no
   mark there, so one cannot see why it was found. In the showcase,
   typing «ex» finds five customers because their e-mail ends in
   «.example», and nothing in the row shows why.
3. A section's live fact (a count, «3 lines»; a state, «The units are
   with the customer.») has no place of its own; a client put it as a
   badge among the section's actions. `page-header` has `:meta` for this.
4. A client had no component for a muted line of text («Your answer goes
   to COMPANY.» under a pair of buttons, «The first 100 found; search to
   narrow them.» under a table) and used a class name Tun does not style.
5. The specimen's toast covers its theme switcher on a wide screen.

The orchestrator's brief adds: each its own criterion; the page, the
fragment and the MCP tool `search` still agree, the tool's result may gain
a field but lose none, and contributors written against 2.31.0 compile and
work unchanged; the test that forbids `:description` in Tun's own pages
stays as it is; for 4, add the smallest component only if nothing existing
fits; raise the core by a minor; the five clients compile and pass
unchanged. A small loop, not to be widened.

## Criteria

1. At 320, 360 and 390 px, on the specimen's `summary-list` examples and
   on a card's page of the showcase in Norwegian, no label's text (its
   line boxes) reaches into its value's box; a long label stands on one
   line when its words fit its column in the browser's font and breaks
   when they do not, and the column is 10rem at 390 px on the card's page.
   (The check's Chromium has none of a phone's fonts: its sans is a wide
   fallback in which «Organisasjonsnummer» is wider than 10rem, so the
   check decides by the word's own width there, not by a fixed width.)
   The CSS gives the label a column of
   `min(10rem, (100% - gap) / 2)` with `hyphens: auto` and
   `overflow-wrap: break-word`.
2. A search result whose title has no mark shows its match in the line
   under the title: the typed words marked in its META the same way as
   in the title, an identifier in META marked over the characters it
   covers; when no META text holds a mark, the result carries MATCHED
   (the first of its names, texts and identifiers holding one, from the start of the word
   holding its mark, at most 80 characters, as §6.4 says), shown after the kind's word,
   marked. A result whose title is marked has its line unmarked as
   before. The `search` tool's items gain `matched` (a text or null) and
   keep every field they had; the page, the fragment and the tool agree;
   `make-search-result` and `search-entity` called as in 2.31.0 compile
   and work. In the showcase, typing «ex» marks «ex» in each found
   customer's line.
3. `section` takes `:meta`, one node or a list: a row under the heading,
   in the section's text and so before its actions, in the header's
   look (`--text-sm`, `--muted-foreground`, wrapping, a gap of 0.5rem);
   no row without it. The specimen shows it and a card's page of the
   showcase uses it. The test forbidding `:description` in Tun's own
   pages is unchanged.
4. `note` is a `<p class="tun-note">` in `--text-sm` and
   `--muted-foreground`, its words wrapping and a long word broken; the
   spec says what it is for and which existing component is for each
   neighbouring case; the specimen shows it under a pair of buttons and
   under a table, and the muted colour's contrast stays the rule §2.1
   sets (the token's contrast test).
5. At 1280 px on the specimen, the toast's box and the theme switch's box
   do not overlap, and pressing «Dark» while the toast shows makes the
   page dark.
6. The core is 2.32.0; `bin/test` and the browser checks are green; the
   five clients compile and pass unchanged.

## Decisions

- **The label's column** is a fixed track, `min(10rem, (100% - gap) / 2)`,
  the same in every row so the values still line up (a column sized by
  its content would be a row's own and break the line of values).
  «Organisasjonsnummer» measures about 152 px (9.5rem) in Chromium's
  default sans at 0.875rem, so 10rem holds it from 360 px, where half the
  row is 156 px; at 320 px half the row is 136 px and it breaks, with a
  hyphen where the language has one. Before, the label had 2/5 of the row
  (137 px at 390 px) with nothing to break a word, and its text painted
  over the value. `overflow-wrap: break-word` rather than `anywhere`, so a
  long word does not change the column's own size; the column is fixed
  anyway. The specimen's example is in Norwegian through the list's own
  `lang`, so hyphenation is the language's.
- **Why it was found.** Marking META needs no change to a contributor:
  the renderer marks it from the query. Only a match in a text that is
  not shown (an order's delivery address, a note) needs the result to
  carry it, so `search-result` gains a slot `matched`, worked out by
  `search-entity` for the at most five results it keeps (cheap), passed by
  `make-search-result`'s new `:matched` (NIL by default), and sent by the
  tool as `matched`, null otherwise. It is an excerpt of at most 80
  characters so a long note does not fill the tool's answer; the line cuts
  it with «…» on a phone as it cuts META. Identifiers are marked by the
  characters their key covers, so «41234567» marks «412 34 567». The
  title keeps the words-only marks of 2.31.0.
- **A section's `:meta`** stands inside the section's text block, under
  the heading, so the actions keep their place beside the heading; the
  header puts its row under the title's whole row, but the section's
  actions are small and wrap, and the heading is what the facts belong
  to.
- **`note`.** §6 has hints (a field's, tied to it), a table's caption
  (above it, naming what it holds), an empty state's text, a stat's note
  and a card's description (inside those components); none is a line in
  the page's flow. So the smallest component: one `<p>`, no variants, in
  `layout.lisp` beside `section`. Named by what it is, not by its colour.
  The colour is `--muted-foreground` itself, whose contrast (at least
  6.5:1) `ui-look`'s test computes; nothing lighter.
- **The theme switch** moves to the start of the specimen's top bar,
  after the title, rather than moving the toast: the specimen shows the
  flash where a page would have it.
- **The tests define no entity of their own.** A first version of
  `tests/ui-nits-tests.lisp` defined a small entity for `search-entity`;
  with it, the markdown suite's timing test (four times the text in about
  four times the time) failed in every parallel run of the suites (4 of
  4) and passed alone, and without it the suites passed. The test now
  uses the customers module's entity, as `search-tests.lisp` does.
- **Not done:** no change to the generated record pages' labels, to
  `page-header`, or to the search rule's scores.

## Clients

On the tree verified in round 4 (snapshot 6acdbbcc), each client's
`bin/test` with `--override-input tun` at it, one at a time: factory
(583 checks), nixploy-dashboard (1421), ferdig (812), kurs (352) and
tun-erp at 8eaa0d2 (16324 and 26105) all pass, with no change to any of
them.

## Actuals

```json
{"loop":"ui-nits","title":"Five small faults the first client found on the new UI library (core 2.31.0)","repository":"tun","mode":"reviewed","stage":"done","item":"sak_60ga5rkmmj8f1ejk","tags":["kind:ui","core","module:ui"],"like":["tun/ui-header"],"started":"2026-11-12 10:24","ended":"2026-11-12 11:59","minutes":{"total":95,"waiting_person":0,"waiting_reviewer":2,"working":93,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":50,"likely":75,"worst":150,"at":"brief"},"latest_estimate":{"best":50,"likely":75,"worst":150,"at":"brief"},"within_estimate":true,"ratio":1.27,"verify":{"rounds":4,"failed":3},"changes":{"A":0,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-12 10:24  started, reviewed
- 2026-11-12 10:26  estimated 50m 1h15m 2h30m at brief, like tun/ui-header
- 2026-11-12 10:27  gate A asked of a reviewer
- 2026-11-12 10:28  gate A: approve (reviewer)
  I reviewed the spec at Gate A and I approve it. The two nits below are worth fixing during the build but don't need another round.
  
  **What's right**
  
  - **Coverage:** each of the five faults has its own criterion (1–5), and criterion 6 covers what the orchestrator asked for: core 2.32.0, `bin/test` and the browser checks green, and the five clients unchanged. Nothing beyond the brief is promised. **Not done** rules out the generated record pages, `page-header` and the search scores.
  - **Brief constraints:**
    - The `:description` test is explicitly left unchanged (criterion 3).
    - The tool gains `matched` and keeps every field it had.
    - `make-search-result` takes `:matched` with NIL as the default, so contributors written against 2.31.0 compile and work unchanged.
    - The page, the fragment and the tool are required to agree.
    - `note` is argued for under "only if nothing existing fits". The **Decisions** entry and `spec/ui.md` (lines 1075–1087) go through hint, caption, empty-state, stat note, card description and `:meta`, and give each its own place.
  - **Testable:** every criterion names something a check can measure:
    - for 1, the label's line boxes against the value's box at 320, 360 and 390 px, and the word on one line;
    - for 2, «ex» marked in each customer's line;
    - for 3 and 4, the order in the markup and the tokens used;
    - for 5, the two boxes not overlapping, and «Dark» working while the toast shows.
  
    The new entries in the spec's test list (diff lines 179–197) map onto all five.
  - **Spec matches criteria:**
    - the summary-list label column (§6, diff 90–100);
    - a section's `:meta` (diff 60–67, in the header's tokens and before the actions);
    - `note` (diff 69–81, citing §2.1's 6.5:1, which is at `spec/ui.md:118`);
    - «Why it was found» and the tool's `matched` (diff 109–148);
    - the theme switch (diff 155–159);
    - the §8 rule (diff 168–171).
  
    `docs/client-api.md` says the same for clients.
  - **Decisions:** none of them needs the asker. Moving the theme switch rather than the toast affects only the specimen. The fixed label column is what keeps the values lined up. The 80-character excerpt and the name `note` are reasonable defaults that fit the brief's "smallest" and "not to be widened".
  
  **Nits to fix while building (not blocking)**
  
  1. **The column's formula is ambiguous.** Criterion 1 and `spec/ui.md:1140` say "half the row less the gap", which can be read as `50% - gap`. **Decisions** means `(100% - gap) / 2`. The spec should say it that way so the CSS test has one answer.
  2. **The excerpt's wording differs.** Criterion 2 says MATCHED is "cut to 80 characters around it". §6.4 (diff 119–121) says it starts at the beginning of the word holding the first mark. The criterion defers to §6.4, so §6.4 governs, but "around" should become "from the word holding it".
  
  **A risk at build time:** «Organisasjonsnummer» fitting on one line at 360 px rests on a measured 152 px against 156 px of room. If the check's Chromium uses a wider default sans (DejaVu, for example), criterion 1 will fail at 360 px. The builder should measure the word in the font the check actually runs with.
- 2026-11-12 10:48  verify 1: failed test
- 2026-11-12 11:02  verify 2: failed test
- 2026-11-12 11:16  verify 3: failed test
- 2026-11-12 11:44  verify 4: passed build, test, check
- 2026-11-12 11:45  shown (/ui/summary-list, /ui/section, /ui/note, /search?q=ex, /ui/flash)
- 2026-11-12 11:58  gate B asked of a reviewer
- 2026-11-12 11:59  gate B: approve (reviewer)
  I approve this change. All five faults are fixed, every criterion has a test or browser check that would fail without the change, and all four steps of verify round 4 passed (build, test, check).
  
  **Criteria**
  
  1. **Long label in a summary list.** The label's column is now `min(10rem, calc((100% - gap) / 2))` with `hyphens: auto` and `overflow-wrap: break-word` (`src/web/ui/data.lisp:682-696`). The browser check measures the label's own text, not its box, at 320, 360 and 390 px, on the specimen and on a card's page in Norwegian. No label reaches its value anywhere. On the card's page at 390 px the column is exactly 160 px (10rem), and «Registreringsnummer» (159.6 px) stays on one line. It breaks at 360 and 320, which is what criterion 1 asks for. The phone screenshot shows «Organisasjonsnum-mer» hyphenated by the list's own `lang="nb"`, not painted over its value.
  2. **Why a search result was found.**
     - **Code:** The new identifier marking (`src/core/search.lisp:505-519`) strips the same characters as `search-identifier-key` and copies `identifier-score`'s whole-or-start rule, so a mark appears exactly where the search found something. `matched` is NIL by default and checked as `(or null string)`. The tool sends `null` when it is empty, and the fragment reads it back.
     - **Tests:** They cover:
       - a line marked only when the title has no mark;
       - an identifier marked across its spaces (`412 34 567`);
       - the 80-character excerpt with «…» on either side;
       - a result built without `:matched`;
       - the tool keeping all of its old fields;
       - the page and the fragment showing the same «Order · <mark>Storgata</mark> 12…».
     - **Browser and screenshot:** Typing «ex» marks «ex» in all five customers' lines.
  3. **A section's `:meta`.** It renders inside the section's text block, before the actions. A test checks that its CSS block is identical to the page header's meta block. A list holding only `nil` gives no row. The specimen shows it, and the showcase's new card page uses it, checked at all three widths. The test forbidding `:description` is untouched.
  4. **`note`.** It is one `<p class="tun-note">` in `--muted-foreground` and `--text-sm`. The spec (`spec/ui.md` §6) explains why a hint, caption, empty state, meta or flash don't fit this case. The specimen shows it under a pair of buttons and under a table, and the screenshot matches. It uses the muted token itself, so the existing contrast rule still applies.
  5. **The toast covering the theme switch.** The switch now follows the specimen's title. At 1280 px the measured boxes are far apart: the switch spans x 168–354 and the toast x 864–1264. Pressing «Dark» while the toast shows turns the page dark. The desktop screenshot agrees.
  6. **Version and clients.** The core is 2.32.0 in both `flake.nix` and `module.lisp`. The record says the five clients compile and pass with no change to any of them.
  
  **Brief**
  
  - Every field the search tool had is still there, and only `matched` is added.
  - Contributors written against 2.31.0 work unchanged, because `:matched` defaults to NIL.
  - Nothing beyond the five faults was widened. «Not done» rules out changes to the generated record pages, `page-header` and the search scores, and the diff touches none of them.
  - Gate A's two nits were fixed. The spec now writes the column as `(100% - gap) / 2`, and the criterion now says the excerpt starts "from the start of the word holding its mark".
  
  **Code**
  
  There is no leftover debugging or dead code. The spec, `docs/client-api.md` and the spec's list of tests change where the behaviour does. The decision to have the new tests reuse the customers module's entity, instead of defining their own, comes with its reason recorded.
- 2026-11-12 11:59  finished at tun 15502387
