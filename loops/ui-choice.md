# Choosing one record among many by typing: a form field and a list filter that send an id

- loop: ui-choice
- mode: reviewed
- stage: done
- base: 5cc7d9b9cad0d685df6e3c870abf5d08c523163f
- item: sak_3a9y1xn7rf5kz47g
- estimate: 3h 5h 9h
- like: tun/ui-fields
- tags: kind:ui core module:ui
- verified: a51448decb875725bb3f553dd1de0ddc7a33f6cd
- shown: a51448decb875725bb3f553dd1de0ddc7a33f6cd

## Brief

Ferdig sak_3a9y1xn7rf5kz47g, brought by the factory's orchestrator on
2026-11-12, a loop of the work on Tun's component library after
`ui-look` (core 2.25.0) through `search-reads` (2.33.0). Jonas,
2026-11-11: he wants the best of another application's admin UI carried
into Tun's component library, «to make the UI component Library of Tun
superb»; the source is the owner's rules for an admin application,
2026-11 (its select and combobox: anatomy, sizes, opening upward when
there is no room, the clear button, the order of near matches; what opens
on a phone).

The item: «Found when Tun ERP's lists moved onto list-toolbar (core
2.32.0): a filter over records (the orders' «Customer») is a list of up
to 100 radios in the «Filters» sheet, and a form's «Customer» is a
select with every customer. Tun's combobox finds one of its texts and
sends the typed text, not an id (spec/ui.md §9 lists «a combobox whose
values differ from the texts it shows, or that asks the server» as left
out). Wanted: one control that finds a record by typing and sends its
id, with its options given or asked from the server, as a form field and
as a list-toolbar filter kind; works without JavaScript. Also noted by
the same client, smaller: Tun publishes no URL encoder for an address
with query pairs; no muted text inside a table cell.»

The orchestrator's brief, in short: (1) a choice that sends a value
other than its text, cleared with a clear button, a value not among the
options refused by a server-side reader that checks a submitted id the
same way whether scripts ran or not; new options on `combobox` or a new
component, by what keeps one way of doing a thing; (2) options given, or
asked from an address the client names as one types (htmx, its own
`delay`, an overtaken answer never painting over a newer one, as the
search dialog does), answered under the actor's authority with the
smallest helper, on `search-among`/`search-match` so the one rule finds
what the search finds («bjorn ase»), and what the server answers when
there are more matches than shown; (3) without JavaScript the field
still works (a plain `select` for given options; for asked ones a «Find»
step or another honest fallback), tested with scripts off; (4) on a
phone a floating sheet with the text field above the keyboard
(`--tun-visual-bottom`) at 320, 360 and 390 px; on a wide screen under
the field, upward when there is no room; arrows, Enter, Escape,
Home/End; `role=combobox` and its states; the active option at the
others' weight; pressed; motion by tokens; the scans of `ui-look` and
`ui-sheets` pass; (5) a `list-toolbar` filter kind (`:choice`) showing
the chosen record's text, its state under the same query name a `:one`
filter would use, inside the «Filters» sheet without a sheet over a
sheet that traps focus; `:one` stays; (6) generated pages use it for a
reference input and a list's id input where the referenced entity has a
label and its list operation can be searched, or, if large, left out
and said so; (7) a published function that writes an address with
encoded query pairs, documented in `docs/client-api.md`, and nothing for
muted text in a table cell unless the spec has the means. Shown on the
specimen (given, asked against a specimen address; chosen, empty, error,
disabled) and on the showcase (`/cards` gets a `:choice` filter over
customers, a card's form a customer field, hundreds of seeded
customers). Browser checks measure the typing delay, an overtaken
answer, Enter, the id posted, clear, the phone's sheet above a simulated
keyboard and scripts off. A minor core version; the five clients compile
and pass unchanged.

## Criteria

1. **A field that posts an id.** A new component `choice-input` (forms
   group) takes `:label :name :value :options :source :find :placeholder
   :hint :error :required :optional :disabled :label-hidden :id`;
   OPTIONS are `(VALUE TEXT)` pairs. It renders a `field` holding a
   `select` named NAME with the field's id, its empty first option
   «Choose» («Velg») or PLACEHOLDER, then OPTIONS, VALUE selected; a
   button (`aria-haspopup="dialog"`, `aria-expanded="false"`,
   `aria-labelledby` naming LABEL and the chosen text) showing the chosen
   option's text or the placeholder; a clear button «Clear LABEL»
   («Fjern LABEL») that is shown when VALUE is among OPTIONS and
   `hidden` otherwise (both tested); a popover (`popover="auto"`, `role="dialog"` named
   LABEL) with a text field (`role="combobox"`, `aria-controls` the list,
   `aria-autocomplete="list"`, `aria-expanded="true"`, `autocomplete="off"`,
   a `form` naming no form) and the list. `combobox`'s calls render as
   before. (`ui-choice-tests`, both languages; the specimen's examples
   render in English, Norwegian and the pseudo-language)
2. **The list.** A new component `choice-options` renders a `ul`
   (`role="listbox"`, `data-tun-choice-query` the text) of an `li`
   (`role="option"`, `aria-selected="false"`, `data-value`) per option,
   the chosen one with a check mark; with MORE above 0 a last line that is
   no option, «N more. Type to narrow them.» («N til. Skriv for å snevre
   inn.»), and with no options «No match» («Ingen treff»).
   (`ui-choice-tests`)
3. **Matching by the one rule.** `(choice-matches TEXT ROWS &key value
   text names texts identifiers keep limit)` in `TUN` answers `(VALUE
   TEXT)` pairs and the count of further matches: for a blank text every
   kept row in ROWS' order; else the rows `search-match` matches, best
   score first and in ROWS' order among equals; at most LIMIT (20).
   «bjorn ase» finds «Bjørn Åsen», «ase» finds it by a word's start, an
   email given as an identifier finds by its start only when the text
   holds a digit, as the search does. (`ui-choice-tests`)
4. **Answering an asked choice.** `(choice-answer QUERY ROWS ...)` in
   `TUN` answers an htmx request for part of a page with `choice-options`
   alone for QUERY's `q` (its first LIMIT and the rest as «more»), and any
   other request with a page «Choices» («Valg») holding it; a showcase
   page answering with it reads only what the signed-in person may (its
   `define-page` policy refuses a viewer when it is `:employee`).
   (`ui-choice-tests`)
5. **Reading what is posted.** `(read-choice TEXT OPTIONS)` in `TUN`,
   OPTIONS pairs or a function of a value: the value, NIL and its text for
   one of them, NIL alone for empty or NIL, NIL and «must be one of the
   choices» («må være et av valgene») for another, the same for a value
   posted by the script's select and by the select without it.
   `(choice-find FORM NAME)` gives NAME-find's text when FORM's
   `tun-find` is NAME, else NIL. (`ui-choice-tests`)
6. **Typing asks after the pause, and the latest answer wins.** On the
   showcase's «New item» form with 400 customers, typing «bjorn» in the
   choice's text field sends no request before 150 ms after the last key
   and one after it, and the list then holds «Bjørn Åsen» first; an
   answer for earlier keys held back until after a newer one never
   replaces it; the list asks once, for an empty text, when it first
   opens, showing 20 options and the «more» line counting the rest of the
   customers. (`ui-choice.py`)
7. **The keys and the posted id.** ↓ and ↑ move `aria-selected="true"`
   and the field's `aria-activedescendant` over the options, going round;
   Home and End reach the first and last while one is active; Enter
   chooses the active option: the button shows its text, the popover
   closes, the focus is on the button, and the form posts the option's
   id under NAME; Escape closes without choosing, the focus back on the
   button; a click chooses. An Enter typed while the answer for what the
   field holds has not come (an answer held back by the check) chooses
   nothing until it comes, and then chooses its first option, not one of
   the earlier answer's. The clear button empties the value (the form
   posts NAME empty) and shows the placeholder. The active option has
   the font weight, size and padding of the others. (`ui-choice.py`)
8. **Where it opens.** At 1280 px the popover's top is within 8px under
   the field's bottom and its left at the field's; a field near the
   window's bottom opens it above (its bottom within 8px over the
   field's top) with the text field as its last part; opening moves only
   `opacity` and `translate` over `--duration-fast`, closing over
   `--duration-close`. At 390, 360 and 320 px it is a floating sheet
   inside the window, 0.75rem (12px) from its sides, over a dim, and with
   the visual viewport shrunk to 60 % as a keyboard does, the sheet's
   bottom, its text field and its list stand above the keyboard's top.
   (`ui-choice.py`; `ui-look-tests` and `ui-sheets-tests`' scans include
   the new CSS and stay green; `ui-choice-tests` pins the sheet's CSS on
   `--tun-visual-bottom`)
9. **Given options narrow in the browser by the rule's fold.** On the
   specimen's given-options field, typing «bjorn ase» leaves «Bjørn
   Åsen» alone, «ase» leaves it too, «aasen» finds it, «hansen kari»
   finds «Kari Hansen», the options kept in the order given; a word in
   no option shows «No match»; ↓ and Enter choose an option, and the
   select's value is that option's id. (`ui-choice.py`)
10. **A `:choice` filter.** `list-toolbar` takes a filter `(:kind :choice
   :name :label :choices :value [:source] [:all] [:find])`: its button
   says «LABEL: TEXT» in use with its clear; its submissions, clear and
   «Reset» name `NAME=VALUE` exactly as a `:one` filter of the same key
   does, so the toolbar's hrefs for a `:choice` and a `:one` filter of
   the same name and value are equal; its value is a `select` named NAME
   with «All». On the showcase's `/cards`, choosing a customer in the
   filter changes the address to `customer=<id>` and the list to that
   customer's cards without loading the page, the popover closing with
   the focus on its button; `/cards?customer=<id>` written by hand shows
   the button in use. (`ui-choice-tests`, `ui-choice.py`)
11. **In the «Filters» sheet.** At 390 px on `/cards` (three filters or
    more, so folded) the `:choice` filter's row holds its text field and
    list in place; typing narrows it, a choice applies at once with the
    sheet still open, no popover opens (no element is `:popover-open`),
    Tab stays inside the sheet and Escape closes the sheet with the focus
    on «Filters». (`ui-choice.py`)
12. **Without JavaScript.** With scripts off, the given-options field is
    a `select` that posts the chosen id; the asked field shows the select,
    a «Find» field and button: typing «bjorn» and pressing «Find» shows
    the form again, nothing saved, the select holding the matches, and
    choosing one and saving posts its id; on `/cards`, the `:choice`
    filter's popover opens with its select and «Find» field, and «Apply»
    filters by the chosen customer. (`ui-choice.py`)
13. **The specimen.** `/ui/choice-input` shows a given-options field, an
    asked one, a chosen one, an empty one, one with an error and a
    disabled one; `/ui/choice-input/options?q=TEXT` answers made-up
    customers as `choice-answer` does, and the asked example lists them
    in the browser. (`ui-choice-tests`, `ui-choice.py`)
14. **An address with a query.** `(query-address PATH PAIRS)` in `TUN`
    writes PATH with the pairs percent-encoded as UTF-8, a list value
    repeating the key, NIL left out, an empty text kept, joined with `&`
    when PATH has a query and PATH alone without pairs; documented in
    `docs/client-api.md`. (`ui-choice-tests`)
15. **No muted text in a table cell.** The spec has no means for it
    (`note` is a line in the page's flow, not in a cell), and this loop
    adds none: `table`'s options are unchanged and §9 says a quieter fact
    is a column of its own. (`ui-choice-tests`: `table`'s lambda list as
    before)
16. **Unchanged elsewhere.** The core version is 2.34.0 (or the next
    free); `bin/test` is green, `combobox`'s tests and checks unchanged;
    the five clients compile and pass unchanged.

## Decisions

- **A new component, not options on `combobox`.** `combobox` is a text
  field whose answer is the text typed (with `:strict` a known text);
  what is chosen here is a value the person never sees, its field a
  button showing a text, its list a popover with its own text field, and
  its fallback a `select`. Putting both under one name would give one
  component two markups, two fallbacks and two answers chosen by the
  shape of its options. So: `combobox` for a text, `choice-input` for a
  record's id (its doc and `combobox`'s say so), `select` and `radios`
  for a short list. It is named as the fields that read what is posted
  are (`date-input`, `money-input`).
- **A `select` carries the value.** One named element posts it, with or
  without scripts: the `select` is the field without JavaScript, and the
  script hides it (`hidden`, which still posts) and sets it, adding an
  `option` for an asked choice it does not hold. No hidden twin to keep
  in step, no name posted twice; `read-choice` reads both the same.
- **The list is a popover with its own text field**, the source's select
  with a search: the button shows what is chosen, so the field never
  holds half a name, and a phone's sheet can hold the text field above
  the keyboard. The text field has a `form` naming no form, so it never
  posts (htmx asks with its own `q` alone, as it does for any GET from an
  element that is not a form).
- **Given options narrow in the browser by the rule's fold and words**;
  the server's ranking is for asked ones. A few dozen options need no
  ranking; the fold is the rule's, so «bjorn» finds «Bjørn» both ways.
- **More than shown:** the first 20 by the rule, then one line that is no
  option, «N more. Type to narrow them.». Twenty fill a sheet on a phone;
  the count tells the person typing helps.
- **Without JavaScript, the asked choice has a «Find» step**: a text
  field and a button that posts the form as a find (`tun-find`), which
  the page answers by showing the form again with the matches in the
  select. Honest: nothing is guessed from a name. The toolbar's GET form
  needs no button: «Apply» sends the find text with the rest.
- **In the «Filters» sheet the filter's list is in place**, as a `:one`
  filter's radios are: no popover or sheet over the sheet, so the
  dialog's own focus, Tab and Escape hold and nothing traps the focus
  twice. The list scrolls in a box of 15rem.
- **The phone's sheet stands above the keyboard** by the same
  `--tun-visual-bottom` the dialog uses: the dialog's script writes it
  while a modal dialog **or a popover marked `data-tun-keyboard`** is
  open. The toolbar's popovers of a `:choice` and a period carry the
  mark too, so a period's typed dates gain it.
- **Generated pages are left out (item 6)**: asking a list operation
  finds by that operation's own `query` (the customers module's by a part
  of the name or the email), so «bjorn ase» would not find «Bjørn Åsen»;
  doing it right means a rule-based search per list operation, or reading
  every record for each key, which is its own loop. §9 says so; the
  generated pages stay as they are. Items 1–5 and 7 are built whole.
- **`query-address`** is the encoder Tun's own links use
  (`hunchentoot:url-encode` as UTF-8, behind `pairs-query`), published in
  `TUN`; `pairs-query` writes through it.
- **Muted text in a table cell: nothing.** The spec has no means for it;
  `note` is a line in the page's flow.
- **The specimen asks a real address**, `/ui/choice-input/options`, a
  fixed list of made-up customers, public as the specimen is, holding no
  data.
- **`read-choice` answers as the other readers do** (decided while
  building): the second value is always the message, the text a third,
  `(values VALUE NIL TEXT)`, so a page's `(multiple-value-bind (value
  problem) ...)` reads it as it reads `read-date-text`; with the text
  second, the showcase itself took a customer's name for an error.
- **The find step's field leaves the form by a `form` attribute, not
  `disabled`** (decided while building): a disabled control in a `field`
  greys its label (`field`'s own rule), so a working choice looked
  disabled. Tun's htmx extension keeps that attribute, and the script's
  `data-tun-ready`, through a morph.
- **The phone's checks run on the specimen.** The showcase's «New item»
  holds a `file-input` wider than a 320 px window (its control is 327 px
  in a 296 px column), which widens the layout viewport; that is not this
  loop's, and is reported. The choice's sheet is measured at 320, 360 and
  390 px on the specimen's asked example, which asks a real address, and
  at 390 px in the showcase's pictures.
- **The showcase**: a card gets an optional customer; `/cards` gets a
  `:choice` filter «Customer» asking `/cards/customers` once a card is for
  a customer (or the address names one), as a list offers a filter that
  can find something; so the default scenario's `/cards`, whose cards
  have no customer, keeps the three filters `ui-filters`' check measures
  (with a fourth its 1280 px row is full and, as specified, the search
  narrows when one is put into use), and «New item»
  a customer field asking the same; a scenario `choices` adds 400
  customers and gives some cards one. The default scenario keeps its
  four customers, so other checks see what they saw.

## Clients

On the tree verified in round 4 (as the snapshot commit 1e49ddcc), each
client's `bin/test` with `--override-input tun` at it, one at a time,
from clones in a scratch folder: factory (583 checks), nixploy-dashboard
(1421), ferdig (812), kurs (352) and tun-erp at its main `40a7559` (all
of its suites) pass, with no change to any of them.

Verify rounds 2 and 3 failed only on `search-tests`' timing test of
2000 records of each kind on Postgres (103 ms and 95 ms against its 90
ms limit, at a load average of 16 with another builder's suite and
preview running); run alone the suite passed with medians of 35–40 ms,
and round 4 passed whole. This loop changes no code the test runs.

## Actuals

```json
{"loop":"ui-choice","title":"Choosing one record among many by typing: a form field and a list filter that send an id","repository":"tun","mode":"reviewed","stage":"done","item":"sak_3a9y1xn7rf5kz47g","tags":["kind:ui","core","module:ui"],"like":["tun/ui-fields"],"started":"2026-11-12 16:03","ended":"2026-11-12 17:50","minutes":{"total":107,"waiting_person":0,"waiting_reviewer":3,"working":104,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":180,"likely":300,"worst":540,"at":"brief"},"latest_estimate":{"best":180,"likely":300,"worst":540,"at":"brief"},"within_estimate":false,"ratio":0.36,"verify":{"rounds":4,"failed":3},"changes":{"A":1,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-12 16:03  started, reviewed
- 2026-11-12 16:03  estimated 3h 5h 9h at brief, like tun/ui-fields
- 2026-11-12 16:07  gate A asked of a reviewer
- 2026-11-12 16:08  gate A: changes (reviewer)
  I'm asking for changes at Gate A. Most of the spec is right, but one behaviour the brief asks for has no criterion that would test it.
  
  **What is right**
  - **Brief coverage:** every item in the orchestrator's brief, (1) to (7), has a criterion. So do the specimen, the showcase and the list of browser checks:
    - the id is posted and a wrong value is refused the same way with or without scripts (criteria 1, 5, 7)
    - choices asked from the server, with the 150 ms pause, a late answer never replacing a newer one, the reader's own authority, `search-match`, «bjorn ase» and the «more» line (2, 3, 4, 6)
    - scripts off, with the «Find» step (11)
    - the phone sheet at 320, 360 and 390 px above a simulated keyboard, opening upward, the keys and the motion tokens (7, 8)
    - the `:choice` filter: same address as a `:one` filter, and in the «Filters» sheet no second sheet that traps focus (9, 10)
    - generated pages left out and said so in §9, which the brief allows ("or, if large, left out and said so")
    - `query-address` with its docs, and nothing for muted text in a table cell (13, 14)
    - a minor version, with the five clients unchanged (15)
  - **Testability:** each criterion names its test or check and gives values it can measure (8px, 150 ms, 60 % viewport, equal hrefs, `:popover-open`).
  - **Spec matches criteria and existing rules:** the `spec/ui.md` change agrees with the criteria. I checked a few claims against the existing spec:
    - An email counts by its start only when the text holds a digit; that matches §6.4 at `spec/ui.md:1872-1878`.
    - The phone sheet rising over `--duration` matches the filter popover's sheet (`spec/ui.md:1058`).
    - "Near matches … (as in the search)" in §9 matches the search's own left-out entry (`spec/ui.md:2357`).
  - **Decisions:** none of them is really the asker's. A new component instead of more options on `combobox` is the call the brief explicitly hands over ("by what keeps one way of doing a thing"). The rest are implementation choices.
  
  **Changes**
  1. **Narrowing given options in the browser is untested.** The brief's item (2) is "options given, *or* asked". Decision 4 and the spec (`diff.patch:91-95`) say given options narrow in the browser, using the search rule's folding re-implemented in the script, so «bjorn» finds «Bjørn». Every typing criterion uses an asked field:
     - criterion 6 is the showcase's asked field
     - criterion 10 is `/cards`, also asked
     - criterion 12 only *shows* a given-options field
  
     So the browser's copy of the fold could drift from the server's and no check would notice. Add a criterion, checked in `ui-choice.py`: on the specimen's given-options field, typing «bjorn ase» (and «ase») leaves «Bjørn Åsen», in the order given; a word not in any option shows «No match»; ↓ and Enter choose and post the option's id.
  2. **Criterion 1 and the spec disagree about the clear button.** Criterion 1 renders «Clear LABEL» unconditionally. The spec (`diff.patch:114`) shows it only "while an option is chosen", and criterion 7 has it hidden after clearing. State the condition in criterion 1 (present when VALUE is among OPTIONS; absent or hidden otherwise) and test both cases.
  3. **Enter before the answer arrives is in the spec but untested.** The spec (`diff.patch:130-132`) says an Enter typed before the answer for the current text arrives waits for it, then chooses its first option. That is exactly the race the brief wants the browser checks to measure ("Enter", "an overtaken answer"). Add it to criterion 7, or take the sentence out of the spec.
- 2026-11-12 16:08  gate A asked of a reviewer
- 2026-11-12 16:09  gate A: approve (reviewer)
  The three changes asked for at the first review are made, and nothing new needs changing. I approve.
  
  **The three earlier changes**
  1. **Typing in a field whose options come with the page is now tested.** New criterion 9 checks the specimen's field with «bjorn ase», «ase», «aasen» and «hansen kari», the order the options were given in, «No match», and that ↓ then Enter sets the select to the option's id. «aasen» finding «Åsen» is right by §6.4 (`spec/ui.md:1854-1860`): a run of «a» is one «a». The spec text for these fields (`diff.patch:91-96`) says the same.
  2. **The clear button now has its condition.** Criterion 1 says it is shown when VALUE is among OPTIONS and hidden otherwise, and tests both. This matches the spec's "while an option is chosen" (`diff.patch:113-118`) and "a VALUE not among OPTIONS is shown as nothing chosen" (`diff.patch:99-100`).
  3. **Pressing Enter before the answer arrives is now tested.** Criterion 7 checks it with an answer held back on purpose: Enter chooses nothing until the answer comes, then chooses its first option, never one from the earlier answer. This matches the spec at `diff.patch:130-132`.
  
  **The rest**
  - Every part of the brief, items (1) to (7), is still covered, as are the specimen, the showcase and the browser checks. Nothing goes beyond what the brief asks.
  - Leaving out generated pages is allowed by the brief and is stated in §9 (`diff.patch:308-313`).
  - Each criterion can be decided by its named test or check.
  - The `spec/ui.md` and `docs/client-api.md` changes agree with the criteria.
  - None of the decisions should have gone back to the asker. The brief itself leaves the choice between new options on `combobox` and a new component to the builder.
- 2026-11-12 16:50  verify 1: failed check
- 2026-11-12 17:06  verify 2: failed test
- 2026-11-12 17:20  verify 3: failed test
- 2026-11-12 17:34  verify 4: passed build, test, check
- 2026-11-12 17:35  shown (/items/new, /cards, /ui/choice-input)
- 2026-11-12 17:48  gate B asked of a reviewer
- 2026-11-12 17:49  gate B: approve (reviewer)
  I approve this gate. All 16 criteria are met with evidence, verify round 4 passed whole, and the code follows the repository's rules.
  
  **Verification**
  - `verify.txt`: build, test and check all pass in round 4.
  - Rounds 2 and 3 failed only on `search-tests`' timing limit, on a machine under heavy load. This loop doesn't change the code that test runs, and the suite passed when run alone.
  - The five clients compile and pass unchanged (`loop.md:287-291`).
  
  **Criteria against the checks** (`checks/ui-choice.json`, every result `ok`)
  - **6 (pause and latest answer):**
    - Exactly one request, 151 ms after the last key; «Bjørn Åsen» comes first.
    - A held-back answer for «anna», answered late, never replaces the newer list.
    - A failing answer shows its message.
    - Opening asks once and shows 20 options with «385 more. Type to narrow them.»
  - **7 (keys and posted id):**
    - ↓/↑ go round, and Home/End work; `aria-activedescendant` follows the active option.
    - Enter chooses: the list closes, the focus goes to the button, and the saved card is for Anna Bakke.
    - Escape and a click behave as specified.
    - The clear button empties the value, and the form posts `customer` empty.
    - The active option has the same weight, size, padding and height as the others.
    - An Enter typed before the answer chooses nothing until the held answer arrives, then chooses «Bjørn Åsen».
  - **8 (where it opens):**
    - At 1280 px the list's top is 4 px under the field, at the same left edge.
    - Near the window's bottom it opens above, 4 px over the field, with the text field last.
    - Open uses 0.15 s and close 0.16 s; the transition properties are opacity, translate and the discrete display/overlay ones.
    - At 390, 360 and 320 px it is a sheet 12 px from each side, over the dim. With the visual viewport at 60 %, the sheet's bottom is 494 and the field and list end at or above it, all above the keyboard's top at 506. `--tun-visual-bottom` is 338px.
  - **9 (given options):** «bjorn ase», «ase», «aasen» and «hansen kari» each give the expected options, in the order given. «zebra» shows «No match». ↓ ↓ Enter sets the select to `cus_2`.
  - **10 and 11 (the filter):**
    - Choosing sets `customer=<id>` without loading the page, and the button says «Customer: Bjørn Åsen».
    - `/cards?customer=<id>` written by hand shows the button in use.
    - In the «Filters» sheet: the field is in place and the list box is at most 15rem. A choice applies with the sheet still open and no popover open. Tab stays inside, and Escape closes it with the focus on «Filters».
    - The unit tests check that a `:choice` and a `:one` filter of the same name and value give equal addresses, including when cleared.
  - **12 (scripts off):** the select posts the id. «Find» shows the form again with «1 found» and saves nothing. The toolbar's «Apply» filters by the chosen customer.
  - **1–5, 13–15** are covered by `tests/ui-choice-tests.lisp`:
    - the markup and ARIA, and the clear button shown or hidden, in English and Norwegian
    - `choice-matches` («bjorn ase», a word's start, an email's start only with a digit, ties keeping the rows' order, LIMIT, KEEP)
    - `read-choice` and `choice-find`
    - `choice-answer`'s fragment, its page, and the 403 for a viewer
    - the specimen's options address
    - `query-address`
    - the unchanged `table`
    
    The pseudo-language rendering is covered by the existing all-examples test in `tests/ui-tests.lisp:78`.
  - **16:** the version is 2.34.0 in both `flake.nix` and `src/core/module.lisp`, and `combobox`'s tests are unchanged.
  
  **Screenshots** cover the field, the open list, the cards filter and the «Filters» sheet at 390 and 1280 px, light and dark. They match the criteria: the sheet sits above the dim, the active option has a ground and a frame at the same size as the others, and the filter button says «Customer: Bjørn Åsen».
  
  **The brief**
  - All seven points are delivered: a new component sending an id, given or asked options, scripts off, the phone sheet, the `:choice` filter, `query-address`, and no muted cell.
  - Generated pages are left out, and §9 says so with the reason (`spec/ui.md` diff 1265-1270). The brief allows this.
  - The showcase has 400+ customers, a customer field on a card's form and a filter on `/cards`.
  
  **The code**
  - `spec/ui.md` describes every new behaviour, and `docs/client-api.md` documents the published functions.
  - Comments explain what the code does and why. The tests label sections by criterion number, which the existing test files also do.
  - There is no leftover debugging.
  - The morph rule in `src/web/ui/kit.lisp` that keeps `data-tun-ready` and the find field's `form` attribute is explained and needed.
  
  **Small things, not blocking**
  - `src/web/ui.lisp:2009-2024` (`specimen-choices`) repeats `choice-answer`'s work with an unexplained `:limit 8` instead of calling it. A comment or a call to `choice-answer` would be clearer.
  - The specimen's «A find step without scripts» example looks like a plain empty field when scripts run (`desktop-ui-choice-input.png`). It only shows its find step with scripts off.
- 2026-11-12 17:50  finished at tun b17306f9
