# A form's alert names fields by their labels, Enter saves without scripts, and a module shapes its records' choice

- loop: form-nits
- mode: reviewed
- stage: ship
- base: 97ade0c28aa74ef2e1155c7c593b058646539fae
- item: sak_j38933ycc05qwa47
- estimate: 1h30m 2h30m 5h
- like: tun/generated-choice
- tags: kind:ui core module:ui
- verified: 6a97ae3b04762d089037148d9eadec841eb0d490
- shown: 6a97ae3b04762d089037148d9eadec841eb0d490

## Brief

Ferdig sak_j38933ycc05qwa47, brought by the factory's orchestrator on
2026-11-12 after loops `ui-choice` (core 2.34.0) and `generated-choice`
(2.35.0): «Three things the first clients of core 2.34.0 and 2.35.0
found. (1) `error-alert` names a field by its path («starts_on must be a
date…»); it should name it by the label the form shows. (2) Without
scripts, Enter in a text field of a form with an asked choice runs the
«Find» step instead of saving. (3) A module cannot say what names a
record in `/choices/ENTITY`, which more fields find it, or which records
stay out (an erased customer).»

The orchestrator's brief, in short: (1) the alert (and `error-summary`
where it has the same fault) names each field by the label the form
shows, in the page's language, each line linking to its field where the
page has it; generated forms know the labels, a hand-written page says
the least it can, a page that says nothing renders as today; a path with
no known label never worse than today; rows («Line 3: Unit price …»);
and «must be a valid identifier» on an empty required reference is no
sentence for a person: a generated form says «Choose a customer»-like
words there, if that fits how the kernel words refusals. (2) Enter saves
without scripts in a form with an asked `choice-input`, fixed in the
component, the find field's Enter may still find; a browser check with
JavaScript off on a hand-written and a generated form. (3) A module
says, for its entity, the text that names a record, which more names and
identifiers find it, and which records stay out though they can be read,
a chosen record kept out since still named on a record's page; by Tun's
ways for a seam or a declaration, in the spec and `docs/client-api.md`;
one `select :fields`, the speed tests of `generated-choice` green with
room. (4) `spec/files.md`'s «cut at its end» (Chrome cuts in the
middle); `generated-choice`'s criterion 3 test may assert that no
operation is called. Every call shape stays; the five clients compile
and pass unchanged; core 2.36.0.

## Criteria

1. **The alert names fields by their labels.** `(error-alert JSON
   :fields FIELDS)`, FIELDS nodes the components made, writes each field
   error of JSON as a list item holding a link `#ID` to the control
   posted under the error's path, its text «LABEL MESSAGE» (a message
   that is a sentence of its own alone): LABEL the label of that
   control's `field` without «(optional)» for a `text-input`, `select`,
   `choice-input`, `date-input`, `money-input`, `textarea`, `checkbox`
   and `input-group`, and the legend for `radios` and `checkboxes`; in
   English and in Norwegian («Tittel må fylles ut»). (`form-nits-tests`)
2. **Rows.** An error at `lines[2].unit_price` or `lines.2.unit_price`
   names the control `lines[2][unit_price]`: «Line 3: Unit price …»
   when it stands in a `fieldset` with the legend «Line 3», else «Row 3:
   Unit price …» («Rad 3: …»). The generated form's summary names a
   row's field «Order line 1: Quantity …» (was «Quantity in order line
   1 …»). (`form-nits-tests`)
3. **As before where nothing is known.** An error whose path no control
   in FIELDS is posted under, and every error of an alert without
   FIELDS, is written as in 2.35.0: «PATH MESSAGE» with no link; an
   alert without FIELDS renders exactly the markup 2.35.0's did (the
   destructive `alert` of the code's title and `data-code`, a `ul` of
   those texts, or the message). (`form-nits-tests`, the 2.35.0 markup
   built in the test as 2.35.0's `error-alert` built it)
4. **A blank choice.** The kernel refuses an id input given as `""` or
   blanks with «must be filled in» («må fylles ut»), not «must be a valid
   identifier», an optional one as a required one (refused as before,
   in other words; null or left out is still no value and accepted), as
   an operation's input and as an entity draft's field; a generated form's required record choice and enum
   choice left empty say «Customer must be chosen» («Kunde må velges»)
   in the summary and «Must be chosen» at the field. (`form-nits-tests`)
5. **In the browser.** On the showcase's «New item», posted with no
   title and «Reported on» «32.13.2026», the alert says «Title must be
   filled in» and «Reported on must be a date …» (Norwegian «Tittel må
   fylles ut», «Rapportert …»), each a link: with JavaScript, pressing it
   puts the focus in its field; without, the address's fragment becomes
   the field's id. At 390 px the alert does not widen the page.
   (`form-nits.py`)
6. **Enter saves without scripts.** An asked `choice-input` (with
   SOURCE) renders, right before its «Find» button, a submit button with
   no name, visually hidden, `tabindex="-1"`, `aria-hidden="true"` and
   `data-tun-choice-off`; one with given options renders none.
   (`form-nits-tests`) With JavaScript off, Enter in the title of «New
   item» and of the generated «Meetings» form (405 customers, a customer
   chosen by «Find») saves the item and the meeting, and «Find» still
   lists the matches; with JavaScript on, Enter in the title of «New
   item» saves it too. (`form-nits.py`)
7. **A module shapes its records' choice.** `record-choice` is a
   generic function in `TUN` whose default answers NIL. With the
   customers module's method, on Postgres and in memory:
   `/choices/customer?q=` a customer's email finds it, and so does its
   phone written without its country code; an erased customer is
   neither offered (not by `/choices/customer` for an empty text nor
   among a form's options with 30 or fewer) nor accepted when posted
   («must be one of the choices», by the orders' generated create
   form, the one kind of generated form that posts it), while an order
   made for it before it was erased shows its name in the orders'
   list and on the order's page. A method more specific than the
   module's that answers `(list* :text F
   (call-next-method))` changes the text and keeps the email, the phone
   and the erased customer out. (`form-nits-tests`)
8. **Still one read, still fast.** `/choices/customer` reads the
   customers once, through `select` with `:fields ("name" "email"
   "phone" "erased")`, and calls no operation; `generated-choice-tests`'
   speed tests pass with their limits unchanged. (`generated-choice-tests`)
9. **Unchanged elsewhere.** Core 2.36.0 in `src/core/module.lisp` and
   `flake.nix`; `spec/files.md` says the browser shortens the file
   control's text as it does (Chromium in the middle); `bin/test` green,
   the checks of `ui-choice`, `generated-choice`, `ui-look` and
   `ui-sheets` green; every component's and `error-alert`'s call shape as
   before; the five clients compile and pass unchanged.

## Decisions

- **The alert learns the labels from the fields themselves**: `:fields`,
  the form's field nodes, which the page already builds, rather than an
  option of labels by path. The labels then are the very ones the form
  shows, in its language, and so are the controls' ids, which the links
  need and which a page does not otherwise know (the components number
  them). A page passes one list it already has; one that passes nothing
  renders as before. The walk reads only Tun's own markup: a control's
  `name` and `id`, the `label` whose `for` is that id, a `fieldset`'s
  `legend`.
- **A row's field** is named «LEGEND: LABEL» after the fieldset the
  control stands in (the generated form's «Order line 1»), else «Row
  N: LABEL», N the path's index plus one. The generated summary used «LABEL
  in order line N»; it takes the same wording, so a form reads alike
  generated or not.
- **«must be chosen» on the web side, «must be filled in» in the
  kernel.** The kernel words a refusal as a fragment after the field
  («must be filled in»); it does not know the field is chosen from a list.
  An id given as blank text was refused and stays refused, required or
  not; only its words change, to «must be filled in» (for every caller;
  an agent reads it as well). Reading blank as no value, as blank text
  is, would change what an agent's `""` means on an update (clear, or
  leave), which is not this loop's to decide; an optional id with no
  value is null or left out, as it was. Where the form knows the field is a choice (the generated form:
  a record's `choice-input`, an enum's `select` or `radios`), it words the
  operation's «must be filled in» as «must be chosen», at the field and
  in the summary: «Customer must be chosen», «Kunde må velges», the
  field's label in it as the brief asks, in the kernel's form of a
  fragment after the label. A full sentence «Choose a customer» would need
  an article per entity in English and a gender in Norwegian. A
  hand-written page's alert keeps the operation's words, which are the
  ones its own field shows.
- **`error-summary` keeps its shape**: it is given its lines as `(ID
  MESSAGE)` and has no paths; the generated form's summary already named
  fields by their labels. Its fault was only the row's wording (above).
- **Enter**: a browser presses the form's first submit button, so the
  asked choice puts a nameless submit button right before its «Find»,
  clipped out of sight rather than `display: none` (gate A's reviewer:
  older Safari does not press a default button that is not rendered).
  It is taken out of the form with the find step where scripts run, so with JavaScript nothing changes. Enter in the find field saves
  too: the brief allows either, and HTML has no way to let one field's
  Enter press another button without a script.
- **A seam, not a declaration**: `record-choice (APPLICATION ENTITY)`,
  like `search-records`: the module that makes the entity is not always
  the one that decides (Tun's customers module's customer is named
  otherwise by a client), a declaration on `define-entity` could not be
  changed by another module or the client, and the functions it holds
  (a display name, `search-phone-forms`) are code. It answers a property
  list of what it changes, so a more specific method adds its keys before
  `(call-next-method)`'s and keeps the rest; EQL-specialised on the entity,
  a module answers for its own entity only. Its keys are `search-entity`'s
  (`:fields`, `:names`, `:texts`, `:identifiers`, `:keep`) and `:text`
  and `:order-by`.
- **A kept-out record**: not offered, not found, not counted by the rule
  of 30, and refused when a generated form posts it (an erased customer
  cannot be chosen again by a crafted post); still named wherever a page
  names it, from the same read. The generated pages have no form that
  edits a record: `handle-resource` posts only the create tool, and a
  record's actions are buttons without inputs. So a kept-out record is
  never the current value of a generated form, and the edit form the
  reviewer of gate A feared cannot be refused there. A client's own edit
  page checks with its own `read-choice` options, and the spec says to
  give the record's current value among them; nothing is taken from it.
- **Tun's customers module shapes its customer** as its search does
  (email, phone in its forms, no erased customer). So the showcase and
  every client with the module get it; tun-erp's `/choices/customer`
  then keeps erased customers out and finds by email with nothing
  written. `generated-choice`'s test of one read changes with the spec:
  the fields read are the module's four.
- **The showcase**: «New item» gets an optional «Reported on» date field
  (the card's `reported_on`), so its alert shows a path that is not its
  label in both languages, and passes its fields to `error-alert`. The
  erased customer is a test's (on the orders' pages), not the
  scenario's: the scenarios stay as other checks know them.
- **Verify round 1** failed on one check: `generated-choice.py` pressed
  «Create meeting» by `button[type=submit]:not([name=tun-find])`, which
  now also finds the choice's default button; it names the form's own
  button by leaving that one out too (what it checks is unchanged).
- **Spec**: `spec/ui.md` §2.1 (an alert's links pressed), §6
  `choice-input` («Enter saves»), §8 «Forms», «Choosing a record» 2, 4
  and 5, «A client's pages» 4, §9, §10 and the history; `spec/files.md`
  §6.1; `docs/client-api.md` (`error-alert`'s `:fields`,
  `record-choice`).

## Clients

On the tree verified in round 2 and shown, each client's `bin/test` with
`--override-input tun` at it (and tun-erp's `customers` at its
`modules/customers`), one at a time, from clones of their `origin/main`
in a scratch folder: factory and nixploy-dashboard (tunworks `16cf6ad`,
583 and 1421 checks), kurs `a82a83d` (352) and tun-erp `13b84c1` (all
of its suites) pass, with no change to any of them. ferdig `011de00`
fails 2 of 760 checks of `generated-every-page-answers-every-role` (a
viewer's link to `/sok` from `/access` answers 403; an admin's link to
`/kunder/…/personer/jonas` answers 404), and fails the same two with
Tun at this loop's base, `97ade0c2`: they are not this loop's.

## Pictures

Before (`origin/main`, 2.35.0) in `~/coding/tun-wt/form-nits-shots/before/`
(the specimen's alert, error summary, choice-input and text-input at
390 and 1280 px, light and dark); after in
`~/coding/tun-wt/form-nits-shots/after/` (the same, and «New item»'s
alert naming its fields at 390 and 1280 px, light and dark, in English
and Norwegian, from `form-nits.py`).

## Log

- 2026-11-12 19:13  started, reviewed
- 2026-11-12 19:13  estimated 1h30m 2h30m 5h at brief, like tun/generated-choice
- 2026-11-12 19:26  gate A asked of a reviewer
- 2026-11-12 19:27  gate A: changes (reviewer)
  I'm asking for changes. Most of the spec is sound, but one markup error and two gaps need fixing before this goes on.
  
  **What's right**
  - **Coverage of the brief.** Criteria 1–3 cover the alert: labels, legends, links, rows, and the 2.35.0 fallback. Criterion 4 covers the blank choice and 6 covers Enter without scripts. Criteria 7–8 cover the choice seam, kept to one `select` with no operation called. Criterion 9 covers `files.md`, 2.36.0 and the five clients unchanged. Each one names a test or check that could decide it.
  - **The `record-choice` seam.** It copies the existing `search-records` method on `customers-module` in `modules/customers/customers.lisp:188-206`: the same fields, `:keep` and identifiers. A client specialising on its application class beats the module's method, as the spec says. Choosing a seam over a declaration is argued well enough to be the builder's call.
  - **Enter.** «New item» really does have an asked `choice-input` (`checks/showcase/pages.lisp:150`), so criterion 6's no-script check hits the real fault. The cost to a form whose submit button has a name or `formaction` is stated in §6.
  - **Spec wording.** Writing «must be chosen» in the web layer and «must be filled in» in the kernel matches how the kernel words refusals, and §8 says the same.
  
  **Changes**
  
  1. **Broken code fence: `spec/ui.md:2354`** (diff line 240). The line reads ``` `timestamp-text`, `date-text`,``` with text after the closing fence. A closing fence must stand alone on its line, so everything up to the next fence renders as code. That swallows the rest of «A client's pages» 4. Put the closing ``` on its own line and the `timestamp-text` sentence after it.
  
  2. **Criterion 4 doesn't cover an optional id given as blank.** The criterion says the kernel *refuses* an id given as `""` or blanks with «must be filled in», with no exception for optional inputs. The spec (`spec/ui.md:2173`) and the Decisions say instead "as it refuses a missing one" / "is missing, as blank text is". A missing optional input isn't refused, and the kernel already reads a blank optional string as no value (`src/core/types.lisp:130-131`). The two texts give different answers for an optional `(id …)` posted as `""`: refused «must be filled in», or accepted as no value. The second is a contract change for agents too, and for an update it raises whether blank means "clear" or "absent". State which one, in the criterion and in the spec, and test it.
  
  3. **An edit form with an erased customer can no longer be saved.** This is the asker's call, so ask. Criterion 7 and the spec (`spec/ui.md` «Choosing a record» 5, diff line 204) refuse a kept-out id when posted. The spec also says the form still shows it as the chosen value. So editing a meeting whose customer has since been erased re-posts that id and gets «must be one of the choices». The person can't save any other change without picking a different customer. The brief only asks that a kept-out record not be *offered*, and that one already chosen stays named. The Decisions call refusing it the "safer reading", but that reading has this cost in tun-erp, and the asker didn't choose it.
     - I recommend accepting a kept-out id when it is the record's current value and refusing it only when newly chosen. That still blocks a crafted post.
     - Either way, add the case to criterion 7 and a test for it.
- 2026-11-12 19:28  gate A asked of a reviewer
- 2026-11-12 19:29  gate A: approve (reviewer)
  I approve the spec. Both earlier changes are fixed, and the third, which I had said needed the asker's decision, turns out not to.
  
  **Earlier review, checked against the code**
  - **Code fence (`spec/ui.md`, diff line 240):** fixed. The closing fence stands alone, and the `timestamp-text` sentence follows it.
  - **A blank id given to an optional input:** criterion 4 and §8 «Forms» now say the same thing. A blank id is refused whether the input is required or not, only reworded to «must be filled in». Null or leaving the input out is still accepted. This matches the code: the id type at `src/core/types.lisp:402-405` already refuses `""` whether or not the input is required. The text-field rule the earlier review cited (`:130-131`) is a different code path. So nothing changes for an agent except the wording.
  - **An erased customer on an edit form:** I checked the builder's argument and it holds.
    - Generated pages post only the create tool (`handle-resource`, `src/web/ui.lisp:1903-1922`), so a kept-out record is never the current value of a generated form.
    - `read-choice` (`src/core/search.lisp:709`) checks only against the options the caller gives it. A client's own edit page decides what it accepts.
    - The spec now tells such a page to include the record's current value among its options.
    
    The cost the earlier review feared can't happen in Tun's pages, so the asker doesn't need to be asked.
  
  **Coverage of the brief**
  - **Part 1 (the alert):** criteria 1–3 and 5 cover labels, legends, links, both languages, rows, «as before» with no labels known, and the 390 px width. Criterion 4 covers the empty required choice, «Customer must be chosen». Rewording that in the web layer rather than the kernel fits how the kernel words refusals, as the brief asked.
  - **Part 2 (Enter):** criterion 6 covers the component's markup and Enter with JavaScript off on a hand-written and a generated form. «Find» still finds.
  - **Part 3 (a module shapes its choice):** criteria 7–8 cover text, email, phone, the erased customer (not offered, not accepted, still named), a more specific method winning, one `select :fields` with no operation called, and the speed limits unchanged.
  - **Part 4:** criterion 9 covers `files.md`, 2.36.0, the five clients and unchanged call shapes. The «no operation is called» assertion is in criterion 8 and in §10.
  
  Each criterion names a test or a check that could decide it. The spec, `docs/client-api.md` and the criteria agree. Choosing a seam over a declaration, and the «Order line 1: Quantity» wording, are reasonable calls for the builder.
  
  **Notes, not blocking**
  - **«Refused as before» isn't quite true for whitespace-only ids.** Criterion 4 and `spec/ui.md` (diff lines 120-125) refuse «blanks alone» too, which today pass as an id (`types.lisp:403` checks only length). The new behaviour is better, but at gate B the spec sentence should say it's new for blanks.
  - **Safari is a risk for criterion 6.** The no-script Enter fix relies on a `hidden` default button. Chromium presses it, and that's all the check runs. Older Safari versions have been known not to submit through a `display:none` default button. If that matters, hide it visually off-screen instead.
- 2026-11-12 19:56  verify 1: failed check
- 2026-11-12 20:11  verify 2: passed build, test, check
- 2026-11-12 20:12  shown (/items/new, /meetings, /ui/choice-input)
- 2026-11-12 20:13  gate B asked of a reviewer
- 2026-11-12 20:14  gate B: approve (reviewer)
  I approve this change. Every criterion has a test or check that would fail without it, the code is clean and verification passed.
  
  **Verification**
  - `verify.txt` round 2 passed build, test and check. Round 1 failed on one check in `generated-choice.py`: its selector also matched the new hidden default button. The fix only narrows that selector (`SAVE`, diff 180), so what the check tests is unchanged.
  - No result in `checks/` failed. That includes `ui-choice`, `generated-choice`, `ui-look` and `ui-sheets`.
  
  **Criteria**
  - **1–3, the alert.** `error-alert` gains `&key fields`, so the call shape is unchanged.
    - The walk over the fields (`form-controls`, `form-field-labels`, `src/web/ui.lisp` diff 846–909) reads only the markup Tun's components make. It drops «(optional)» and uses the legend for radios and checkboxes.
    - `form-nits-tests` covers every component kind the criterion lists, both path forms of a row, «Line 3» versus «Row 3»/«Rad 3», and Norwegian.
    - The "as before" test compares the output with the 2.35.0 markup, rebuilt in the test as 2.35.0's `error-alert` built it.
  - **2, the generated summary.** It now says «Order line 1: Quantity», and the test asserts the old wording is gone.
  - **4, a blank id.**
    - In `types.lisp` (diff 720), a blank id is refused with «must be filled in», whether the input is required or not. Null or leaving the input out is still accepted. All of this is tested.
    - The generated form's «must be chosen» covers both a record's choice and an enum (`generated-form-errors`), and is tested in Norwegian too.
    - The spec now says that blanks alone are newly refused, as gate A's note asked.
  - **5, in the browser.**
    - The links work with JavaScript (focus goes to the field) and without (the address's fragment becomes the field's id), and the alert does not widen the page at 390 px.
    - The screenshots at 390 and 1280 px, light and dark, in English and Norwegian, show linked lines named by their labels.
    - The criterion guessed the Norwegian label as «Rapportert …». The showcase's existing translation is «Meldt», and the check asserts that. This is not a gap.
  - **6, Enter.**
    - The hidden default button is hidden with the visually-hidden CSS, not `display: none`, which settles gate A's concern about older Safari.
    - Its attributes are checked in the unit test.
    - The browser check covers Enter with JavaScript off on «New item» and on the generated «Meetings» form, «Find» still finding on both, and Enter with JavaScript on.
  - **7–8, `record-choice`.**
    - It is a traced generic function exported from `TUN` whose default answers NIL.
    - The customers module's method is EQL-specialised on its entity and appends `(call-next-method)`.
    - Tests run on memory and Postgres. They cover email, a phone without its country code, and an erased customer: not offered, not among the 30 or fewer options, refused when posted, and still named in the orders' list and on the order's page.
    - A more specific method keeps the module's keys.
    - The one-read test now asserts the four fields and that no operation is called.
  - **9, versions and spec.** Core is 2.36.0 in both places, and the `files.md` wording is fixed. The customers module's core floor rises to 2.36.0, which it needs because it calls `record-choice`.
  
  **Code**
  - It is readable, with no debugging left over. Comments say what and why, without history.
  - The spec, `docs/client-api.md` and the deferred list in §10 move with the behaviour.
  - `offered-choice-text` and `record-choice-text` keep "accepted when posted" apart from "named on a page", which is the right line to draw.
