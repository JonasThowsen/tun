# Generated pages find a record by typing, and a file field that fits a 320 px phone

- loop: generated-choice
- mode: reviewed
- stage: done
- base: 4c5f137d4b07a67ff85a3b55ea5173fe8ecc06cd
- item: sak_639q2yc1sgsr8qpt
- estimate: 2h 3h30m 6h
- like: tun/ui-choice
- tags: kind:ui core module:ui
- verified: 14b6d5e5d8d41b375c74be8fdf27c6ab4af92fef
- shown: 14b6d5e5d8d41b375c74be8fdf27c6ab4af92fef

## Brief

Ferdig sak_639q2yc1sgsr8qpt, brought by the factory's orchestrator on
2026-11-12, after loop `ui-choice` (core 2.34.0), part of the work on
Tun's component library Jonas asked for on 2026-11-11 («to make the UI
component Library of Tun superb»). The item: «A generated form's
reference field and a generated list's id filter offer a select of the
first 100 records, so record 101 cannot be chosen. They move onto
`choice-input` and the `:choice` filter of core 2.34.0, asking an address
the kernel answers with `choice-matches` over the resource's records
under the actor's authority. Also: `file-input`'s control is wider than
its column at 320 px and widens the page.»

The orchestrator's brief, in short: (1) generated pages find a record by
typing: a reference field and a list's id filter on `choice-input` and
`:choice`, answered by a kernel address (or one per resource) with
`choice-answer`/`choice-matches` over the resource's records, by the
search's rule («bjorn ase» finds «Bjørn Åsen»), under the actor's
authority (the permission and record policies of reading the resource's
list; 403 for an actor who may not read it; never a record a policy
hides); a record's text is what generated pages show as its label, the
spec saying which fields are names and which identifiers and how a module
overrides it if the design has a place; it reads only the fields it needs
(`select :fields`) and stays fast (2000 records under a stated limit on
Postgres); the page holds only the chosen record and a find step's
matches; without JavaScript the select and the «Find» step do the job; a
posted id is checked with `read-choice`; a hand-written address of a
generated list filtered by an id still reads the same; a resource with
few records may keep a plain select, by a stated and tested rule. (2)
`file-input` at 320 px: on the showcase's «New item» the control is 327
px in a 296 px column; fix it in the component, pinned by a browser check
at 320, 360 and 390 px. (3) Two notes from `ui-choice`'s gate B, if
small: `specimen-choices` repeats `choice-answer`'s work; the specimen's
find-step example looks like an empty field where scripts run. Every
component's call shape stays; the five clients compile and pass
unchanged; core 2.35.0.

## Criteria

1. **The address.** `/choices/ENTITY?q=TEXT` (ENTITY the entity's JSON
   name) answers an htmx request for part of a page with
   `choice-options` alone: `/choices/customer?q=bjorn ase` lists «Bjørn
   Åsen» first; `q=` empty lists the first 20 customers in the order of
   their names and «N more. Type to narrow them.» for the rest; any other
   request gets a page «Choices». `/choices/account` answers an employee
   403 (`accounts_list` is for admins) and an admin 200; `/choices`,
   `/choices/no_such_entity`, `/choices/memo` (an entity of the tests
   that has no list operation), `/choices/customer/x` and a POST answer
   404. (`generated-choice-tests`)
2. **Under the record policies.** On Postgres, for an entity of the
   tests with a `name`, a record policy that gives an employee her own
   records, and a list operation: the choices an employee gets from its
   `/choices/…`, those a generated field of hers offers and those
   `read-choice` takes for her are her own records only (another's id is
   refused), and a viewer, whose role has no clause, gets none.
   (`generated-choice-tests`)
3. **One read of two fields.** Answering `/choices/customer` reads the
   customers once, through `select` with `:fields ("name")`, and calls
   no operation. (`generated-choice-tests`, counting the store's reads)
4. **Fast.** With 2000 customers, the median of nine answers of
   `/choices/customer` for «kunde 19» and for an empty text, on the
   server, is under 100 ms, in memory and on Postgres; and the names
   add less than 50 ms to the pages that show them: the medians of nine
   answers of the orders' list (ten orders) and of an order's page, with
   2000 customers, are each within 50 ms of the same pages' with the ten
   orders' customers alone. (`generated-choice-tests`)
5. **A record's text.** A record is shown and chosen by its `name`, else
   its id; an order for the 105th customer shows that customer's name in
   the orders' table and on the order's page (before, only the first
   100 had theirs). A record the person may not choose is shown by its
   id: on Postgres, the test entity's record of another employee, in
   the cell of a reference as the generated pages write it, shows its
   id, never its name; an account to an employee (whom `accounts_list`
   does not admit) shows its id, to an admin its name.
   (`generated-choice-tests`)
6. **Few: with the page.** With at most 30 customers an employee may
   choose, the orders' form's «Customer» field is a `choice-input`
   holding every customer as an option, with no `hx-get`; a line's
   «Product» field is one too. With 31 it carries
   `hx-get="/choices/customer"` and its select holds only the empty
   option; shown again after a refusal of another input (no lines), it
   holds the empty option and the posted customer alone, by name. The
   orders' list's `customer_id` filter the same: with at most 30
   customers its select holds every customer and its text field has no
   `hx-get`; with 31 its text field carries `hx-get="/choices/customer"`
   and its select holds «All» alone. (`generated-choice-tests`)
7. **The find step.** With 31 customers or more, posting the orders'
   form with `tun-find=customer_id` and `customer_id-find=bjorn` answers
   200 with the form again, its select holding the empty option and
   «Bjørn Åsen» alone (the one match) and «1 found», and makes no order.
   (`generated-choice-tests`)
8. **A posted id is checked.** Posting an id that is none of the
   choices (one that does not exist) answers 422 with «must be one of
   the choices» at the customer field and in the error summary, the
   operation not called (no order made); a line's product id the same;
   one of the choices makes the order. (`generated-choice-tests`)
9. **The list's filter.** The orders' list has a `:choice` filter named
   `customer_id`; `/orders?customer_id=ID` lists only that customer's
   orders and its button names the customer; «Reset» names
   `customer_id=`; the toolbar's address of it equals a `:one` filter's
   of the same key and value. An id in the address that is none of the
   person's choices (one that does not exist) is passed to the list
   operation as given (the list says «Nothing matches») and the
   filter's button shows that id. (`generated-choice-tests`; the
   existing `ui-filters-tests` change where they said an id is not
   offered)
10. **Where there is nothing to choose from.** An input whose entity has
    no list operation, or whose list operation's policy does not admit
    the person, is a text field as before and no filter; `:choices`
    given to `operation-form` (Access's agents) stay a `select`.
    (`generated-choice-tests`)
11. **In the browser.** On the showcase's generated «Meetings» (a new
    resource of the showcase's, each meeting for a customer), with 405
    customers: the form's «Customer» field asks as one types, «bjorn ase»
    lists «Bjørn Åsen» first, Enter chooses him and «Create meeting»
    saves a meeting for him; the list's «Customer» filter chosen changes
    the address to `customer=<id>` and the list without loading the
    page; with JavaScript off, «Find» lists the matches in the select and
    saving posts the chosen id, and the filter's «Find» and «Apply»
    filter the list. With the default scenario's four customers the
    field holds all four, and typing «fjord» leaves «Fjord Events» alone
    with no request sent. (`generated-choice.py`; `generated-choice-few.py`
    for the four)
12. **`file-input` at a phone's width.** On «New item» at 320, 360 and
    390 px the page does not scroll sideways and the file control's box
    and its zone end inside the field's column. (`generated-choice.py`)
13. **The specimen.** `/ui/choice-input/options` is answered by
    `choice-answer`: the list alone to htmx, a page «Choices» to any
    other request, eight shown and the rest counted; the find-step
    example shows a chosen customer, not the placeholder, where scripts
    run. (`ui-choice-tests` as before and `generated-choice-tests`;
    `generated-choice.py`)
14. **Unchanged elsewhere.** Core 2.35.0 in `src/core/module.lisp` and
    `flake.nix`; `bin/test` green, the checks of `ui-choice`, `ui-filters`,
    `ui-look` and `ui-sheets` green; every component's call shape as
    before; the five clients compile and pass unchanged.

## Decisions

- **One kernel address, `/choices/ENTITY`, not one per resource.** The
  entity an id names need not have generated pages of its own, while it
  always has (or lacks) a list operation; so the address is the
  entity's, a kernel page (`define-page`, `:viewer`, out of the menu, as
  `/search` is). `/choices` is a new kernel route: none of the five
  clients, nor any module, has a page or resource under it.
- **The list operation's policy, not the operation.** «The same
  permission as reading the list» is the operation's policy; the
  records are those the entity's record policies give the person
  (`select`). The operation itself is not called: its own `query` is not
  the search's rule and its page is at most 100, which is the problem.
  The operation is found as the generated pages already find it (a read
  tool of the entity ending in `_list`).
- **A record's text is its `name`, else its id; its id is its identifier.**
  That is what the generated pages already called a record; it is read
  with `:fields ("name")`. No email or other field: the request names
  the label, and more fields would be a per-entity choice. Tun has no
  seam for a module to give another text (the generated form has no
  per-entity hook), so the spec says how a module does it today (its own
  page and address) and §9 lists the seam.
- **Labels from the same read.** Tables and record pages named a
  referenced record by reading the list operation's first 100; they now
  read the records' names as the choice does, so the 101st customer is
  named everywhere once it can be chosen. One read of two columns per
  referenced entity and request.
- **At most 30 with the page.** `choice-input`'s spec puts given options
  at «a few dozen at most»; 30 fill one and a half sheets on a phone,
  narrow at once in the browser, and keep the page small. Beyond, the
  field asks. Both are a `choice-input`, so a form looks the same either
  way; without JavaScript both are a `select`, the asked one with its
  «Find» step. So the four-customer showcase and small tenants keep a
  plain select without scripts, as the brief allows.
- **A posted id is checked before the operation.** The generated form
  checks every choice's id with `read-choice` against the person's
  choices and, on a refusal, shows the form again with an error of the
  operation's own shape (`invalid_input`, the field's path), so the
  summary and the field show it as any other refusal, and the operation
  is not called. A row's id is checked the same way.
- **The address of a list filtered by an id.** Before, a generated list
  did not offer an id and did not pass one from its address to the
  operation, so `/orders?customer_id=cus_12` listed every order. Now the
  key is the input's name, as an agent passes it and as a `:one` filter
  of that key would be named, and the list is called with it as given,
  so an address written by hand, by an agent or by the filter read the
  same. The brief's «a select of the first 100» was the form's; the list
  had no id filter.
- **The showcase gets a generated resource with a reference**, «Meetings»
  (title, customer, day), since its only generated list (customers)
  refers to nothing. Its list operation filters by customer, so its
  toolbar has the `:choice` filter. The `choices` scenario (405
  customers) gives some meetings to Bjørn Åsen; the default scenario's
  four customers show the field with every option.
- **`file-input`**: its zone is a grid whose one column took the
  control's own width (a file input's intrinsic width is the browser's
  button and «No file chosen»); the column becomes `minmax(0, 1fr)` and
  the control `width: 100%`, `min-width: 0`, so it narrows with the
  column.
- **The specimen's notes.** `/ui/choice-input/options` now calls
  `choice-answer` (with `:limit 8`, said in a comment: the specimen's 24
  customers then show the «more» line), so a request for a whole page
  gets a page. The find-step example gets a chosen customer, so where
  scripts run it reads as a chosen field; its title says the step shows
  without scripts.
- **Spec**: `spec/ui.md` §8 («Lists», «Forms», the new «Choosing a
  record»), §7, §9, §10 and its history; `spec/files.md` §6.1;
  `docs/client-api.md` (the generated pages' choice and `/choices`).
  Tests that said a generated list offers no id (`ui-filters-tests`)
  change with the spec.
- **The meetings are a module of the showcase's own** (decided while
  building): only a module registers a resource (`register-web-resource`
  is not in `TUN`), so the showcase keeps one in
  `checks/showcase/modules/meetings/`, as the test client keeps
  `logbook`, and enables it beside customers. Its menu gains «Meetings»,
  which puts «Access» below a 1280×800 window's bottom, so
  `preload-on-intent.py`, which presses the mouse at a link's box,
  scrolls the link into view first (what it checks is unchanged: the
  press still comes before the pointer rests).
- **Two checks** (decided while building): a check runs on one scenario,
  so the four customers' field is `generated-choice-few.py` on the
  default scenario, beside `generated-choice.py` on `choices`.
- **The refusal's message** (decided while building): the refusal of an
  id that is none of the choices is an `invalid_input` document whose
  message, «Choose one of the choices.» («Velg et av valgene.»), the
  summary does not show (it shows the fields' errors).
- **Other tests that change with the spec**: `ui-fields-tests`' «Reset»
  of the orders' list names `customer_id` too.
- **Measured** (alone, load about 5): `/choices/customer` with 2000
  customers answers in 7–9 ms (median of nine, over the loopback, in
  memory and on Postgres), so the test's 100 ms has wide room; the
  orders' list and an order's page took 11 and 6 ms with ten customers
  and 17 and 13 ms with 2000 in memory, 34 and 11 ms and 34 and 13 ms on
  Postgres.
- **Verify round 1** failed on two things: `ui-fields-tests`' «Reset»
  (above), and `preload-on-intent.py` (above); and on `search-tests`'
  Postgres timing test of every kind (111 ms against 90 ms, under
  another builder's load), which this loop does not touch. Round 2
  passed whole.

## Clients

On the tree verified in round 2, committed as 3d4f7173, each client's
`bin/test` with `--override-input tun` at it, one at a time, from clones
in a scratch folder: factory (583 checks), nixploy-dashboard (1421),
ferdig (812), kurs (352) and tun-erp at its main `19f8551` (all four of
its suites) pass, with no change to any of them. None of their pages
changes look: of their generated resources only tun-erp's customers
(from the customers module) exist, and a customer refers to no record,
nor does `customers_list` take an id.

## Pictures

Before (`origin/main`, 2.34.0) in `~/coding/tun-wt/generated-choice-shots/before/`
(the specimen's choice-input, choice-options, file-input and
list-toolbar at 390 and 1280 px, and «New item» at 320 and 390 px from
`generated-choice.py` run without the file field's fix); after in
`~/coding/tun-wt/generated-choice-shots/after/` (the same, the
meetings' list, form, field, chosen field and filter at 390 and 1280 px,
light and dark, the four customers' field, and the shown pages).

## Actuals

```json
{"loop":"generated-choice","title":"Generated pages find a record by typing, and a file field that fits a 320 px phone","repository":"tun","mode":"reviewed","stage":"done","item":"sak_639q2yc1sgsr8qpt","tags":["kind:ui","core","module:ui"],"like":["tun/ui-choice"],"started":"2026-11-12 17:56","ended":"2026-11-12 19:10","minutes":{"total":74,"waiting_person":0,"waiting_reviewer":3,"working":71,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":120,"likely":210,"worst":360,"at":"brief"},"latest_estimate":{"best":120,"likely":210,"worst":360,"at":"brief"},"within_estimate":false,"ratio":0.35,"verify":{"rounds":2,"failed":1},"changes":{"A":2,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-12 17:56  started, reviewed
- 2026-11-12 17:57  estimated 2h 3h30m 6h at brief, like tun/ui-choice
- 2026-11-12 18:02  gate A asked of a reviewer
- 2026-11-12 18:03  gate A: changes (reviewer)
  I've read the whole packet and checked the store spec. Here is my review.
  
  ## Gate A review: generated-choice
  
  **What's right.** The criteria cover every part of the brief:
  - **The `/choices` address:** criterion 1 covers the address, the search's rule and the 403.
  - **Record policies:** criterion 2 covers what a person may see and post.
  - **Speed:** criteria 3 and 4 cover reading only the names and the time with 2000 records.
  - **Find step and checked ids:** criteria 7 and 8 cover the «Find» step without JavaScript and the `read-choice` check.
  - **The list's filter:** criterion 9 covers the id filter and its address.
  - **Few records:** criterion 6 states and tests the rule of 30.
  - **`file-input` and the specimen:** criteria 12 and 13 cover the 320/360/390 px fix and both specimen notes.
  - **Nothing else changes:** criterion 14 covers core 2.35.0, the five clients and the components' call shapes.
  
  A check or test can decide each criterion. The `spec/ui.md` §8 «Choosing a record» text matches the criteria. None of the decisions needed the asker:
  - **One kernel address** instead of one per resource fits the brief, which allows either.
  - **The list operation's policy** without calling the operation is what the brief says.
  - **Name, else id** is what the generated pages already show.
  - **Filtering `/orders?customer_id=`:** before, the list ignored the id. Now it filters by it, which is what anyone writing that address meant. The decision says so openly.
  - **The showcase's «Meetings»** is fine: the showcase isn't one of the five clients.
  
  **Changes:**
  
  1. **Names in tables and record pages ignore the record policies in the spec, and nothing bounds their cost.** The decision «Labels from the same read» names referenced records by reading every record's name, not the list operation's first 100.
     - The spec (`spec/ui.md` §8, «Choosing a record», item 2, diff lines 127–139) doesn't say whose records those are. It needs to say that a record the person may not choose (hidden by a policy, or the list operation's policy refuses them) shows its id, never its name. The brief says «never a record a policy hides», and that applies to the names in tables too.
     - Criterion 5 should test this with `fuzz-memo`, or with a hidden customer on an order.
     - Every orders page now reads all customers, not 100. Add the orders' list and an order's page, with 2000 customers, to criterion 4's 100 ms limit. Otherwise the brief's «stays fast» holds for `/choices` but not for the pages that use it.
  
  2. **One 404 in the spec has no test.** Item 4 of «Choosing a record» (diff lines 153–154) says an entity without a list operation gets 404. Criterion 1 only tests `no_such_entity`. Add an existing entity with no list operation to criterion 1's 404 cases.
  
  3. **«The page holds only the chosen record» isn't tested once a record is chosen.** Criterion 6 only checks a new form at 31 customers (just the empty option).
     - Add to criterion 8, or to criterion 6: at 31 customers, a form shown again after a refusal elsewhere in it (a missing required field, say) has a select holding only the empty option and the posted customer, named.
     - Add to criterion 7: its select holds only the matches.
  
  4. **Minor, same fix as above:** item 6 (diff lines 173–174) says an id in the address that isn't one of the person's choices goes to the operation unchanged, and the filter's button shows the id. Add that case to criterion 9, so the spec's sentence is tested and it's clear the button doesn't leak a hidden record's name.
- 2026-11-12 18:05  gate A asked of a reviewer
- 2026-11-12 18:05  gate A: changes (reviewer)
  Second round on gate A. All four of the first reviewer's points are fixed, and one small gap is left: the "30 or fewer" rule isn't tested for the list's filter.
  
  **Fixed since the first round:**
  1. **Names follow the record policies.** `spec/ui.md` §8 «Choosing a record» item 2 (diff lines 127–136) now says a record the person may not choose is shown by its id, never its name. Criterion 5 tests this on Postgres for the test entity and for `account` (employee sees the id, admin sees the name). Criterion 4 now limits what the names cost the orders' list and an order's page: each must stay within 50 ms with 2000 customers.
  2. **The 404 for an entity with no list operation.** Criterion 1 now includes `/choices/memo`. `memo` exists in `tests/record-policy-tests.lisp:15` with only a create operation and a query, so that case can be tested.
  3. **The page holds only the chosen record.** Criterion 6 covers a form shown again after a refusal: only the empty option and the posted customer. Criterion 7 covers the find step: only the one match.
  4. **An unknown id in the address.** Criterion 9 now says it goes to the operation as given and the button shows the id.
  
  **The rest checks out:**
  - The criteria cover all three parts of the brief, and every one can be decided by a test or check.
  - What the criteria name exists: `select :fields` (`src/core/search.lisp:655`), `read-choice` (`search.lisp:709`), `choice-answer` with `:limit` (`src/web/ui.lisp:2012`), `accounts_list` for admins, and `account`'s `name`.
  - The `spec/files.md` addition matches criterion 12.
  - The §9 entry for the missing seam replaces the old one, which this change makes untrue.
  - None of the decisions needed the asker.
  
  **Change:**
  
  1. **The "30 or fewer" rule isn't tested for the list's filter.** Item 3 of «Choosing a record» (diff lines 146–152) says "the field *and the filter* hold all of them with the page". Every filter criterion leaves this branch out:
     - criterion 9 doesn't say how many customers there are;
     - criterion 11 tests the filter only with 405 customers;
     - criterion 6 covers only the form's fields.
  
     The brief asks that a resource with few records keep a plain select "by a stated and tested rule", and as written the filter's half of that rule could go untested.
  
     Add to criterion 6, or to criterion 9: with at most 30 customers, the orders' list's `customer_id` filter holds every customer as an option with no `hx-get`, and with 31 it carries `hx-get="/choices/customer"`.
- 2026-11-12 18:06  gate A asked of a reviewer
- 2026-11-12 18:06  gate A: approve (reviewer)
  # Gate A review, round 3: generated-choice
  
  The one change asked for in round 2 is made, and I found nothing else that needs changing.
  
  **The round 2 change.** That round asked that the "at most 30" rule be tested for the list's filter, not only the form's field. Criterion 6 (`loop.md:87-97`) now tests the filter both ways:
  - With at most 30 customers, the `customer_id` filter's select holds every customer and its text field has no `hx-get`.
  - With 31 customers, it carries `hx-get="/choices/customer"` and its select holds «All» alone.
  
  Both halves of `spec/ui.md` §8 «Choosing a record» item 3 ("the field and the filter hold all of them with the page") now have a test. That meets the brief's «by a stated and tested rule».
  
  **Criteria against the brief.** I re-read the brief against the current criteria, and every part of it is covered:
  - **(1) Generated pages find a record by typing:**
    - The address, its search rule, the 403 and the 404s: criterion 1. The 404s now include `memo`, an existing entity with no list operation.
    - Record policies for the address, the field, `read-choice`, and the names a cell shows: criteria 2 and 5.
    - Reading only the `name` field, one read: criterion 3.
    - Speed, on both `/choices` and the pages that show names: criterion 4.
    - The page holding only the chosen record and the matches: criteria 6 and 7.
    - The «Find» step without JavaScript: criteria 7 and 11.
    - The `read-choice` check of a posted id: criterion 8.
    - A hand-written filtered address: criterion 9.
  - **(2) `file-input` at 320, 360 and 390 px:** criterion 12.
  - **(3) Both notes on the specimen:** criterion 13.
  - **Call shapes, the five clients, core 2.35.0:** criterion 14.
  
  Each criterion is concrete enough for a test or a browser check to decide: it names the addresses, statuses, counts, texts and limits.
  
  **The spec says the same as the criteria:**
  - `spec/ui.md` §8 «Choosing a record» items 1–6 match criteria 1–10: the limit of 20, the rule of 30, the 403 and 404s, «must be one of the choices» with status 422, an id passed to the operation as given, and the filter's button showing an id rather than a name.
  - The §8 «Lists» and «Forms» changes, the replaced §9 entry, and the history entries for `generated-choice-tests` and `generated-choice.py` agree with the criteria.
  - `spec/files.md` matches criterion 12.
  - `docs/client-api.md` summarises the same behaviour.
  
  **Decisions.** None of them should have gone to the asker. The brief allowed either one kernel address or one per resource. It asked for a stated threshold for few records, which is the 30. «Name, else id» is what the generated pages already show, and the missing seam for a module to give another text is recorded in §9. The id filter that a generated list used to ignore is now applied, and the decision says so openly.
  
  **Not blocking.** A few lines in the «Lists» paragraph (`diff.patch:91-98`) are longer than the paragraph's usual wrap. That's style only.
- 2026-11-12 18:38  verify 1: failed test, check
- 2026-11-12 18:54  verify 2: passed build, test, check
- 2026-11-12 18:55  shown (/meetings, /items/new, /ui/choice-input)
- 2026-11-12 19:08  gate B asked of a reviewer
- 2026-11-12 19:10  gate B: approve (reviewer)
  I've read the whole packet. Every criterion is met and tested, `verify.txt` passed (build, test, check), and nothing needs changing.
  
  **Criteria against the tests and checks** (all in `tests/generated-choice-tests.lisp` unless named; each would fail without the change):
  1. **The address.** `diff.patch:1289-1319` covers it. «bjorn ase» finds «Bjørn Åsen» as the only match. An empty text gives 20 options and «11 more», in name order. A non-htmx request gets a page with an `<h1>`. The employee gets 403 on `/choices/account` and the admin 200. All four 404 paths (including `memo`), the POST and the sign-in redirect are tested.
  2. **Record policies, on Postgres.** `:1324-1377` covers it. The `choice-note` entity has a record policy per author, and the test checks `/choices`, the form field, `read-choice` and the name shown in a cell. Kari sees only her own records, Ola's id is refused, and Vera (the viewer) gets no options.
  3. **One read.** `:1382-1394` checks one read of the customers, with `:fields ("name")`. The code (`diff.patch:874-886`) uses `select` and calls no operation. The test doesn't assert "no operation called", but the code plainly calls none.
  4. **Fast.** `:1399-1444` tests both limits (100 ms for `/choices`, 50 ms added to the pages), in memory and on Postgres.
  5. **A record's text.** `:1449-1472` shows the 105th customer by name in the orders' table and on the order's page. An account shows its id to an employee and its name to an admin.
  6. **The rule of 30.** `:1477-1530` tests the form, a line's «Product» field and the filter, at 30 and at 31. A form shown again after a refusal holds the empty option and the posted customer alone.
  7. **The find step.** Answers 200 with «1 found», 2 options, no error summary and no order made.
  8. **A posted id is checked.** `:1532-1557` covers the customer and a line's product: 422, «must be one of the choices», the summary links to the field, no order made, and a valid id gives 303.
  9. **The list's filter.** `:1562-1584` covers the filtered list, the button's name, «Reset» naming `customer_id=`, and `cus_nope` passed as given with its id on the button. The changes to `ui-filters-tests` and `ui-fields-tests` follow from the spec.
  10. **Nothing to choose from.** `:1589-1612`: `memo` and `account` stay text fields for an employee, the employee gets no filter and the admin gets `:choice`, and Access's `:choices` stay a `select`.
  11. **In the browser.** `checks/generated-choice.json` passes every step: asking as one types, the 20 + «385 more», Enter, saving, the filter changing the address without a page load, and without JavaScript the «Find», saving and «Apply». `generated-choice-few.json` covers the four customers with no request sent.
  12. **`file-input`.** The boxes at 320, 360 and 390 px all end inside the column, and the page doesn't scroll sideways. The 320 px screenshot confirms it.
  13. **The specimen.** `:1617-1628` and the browser check cover it.
  14. **Unchanged elsewhere.** Core is 2.35.0 in both places, and `loop.md` records that the five clients pass unchanged.
  
  **Screenshots.** At 390 px (the sheet) and 1280 px (the popover), the field and the filter look right in light and dark. Names show in the table, and the file zone fits at 320 px.
  
  **The brief.** All three parts are done:
  - Records under 30 come with the page, and beyond that the field asks the server.
  - An address written by hand now filters the list.
  - The file field is fixed in the component itself.
  - Both specimen notes are handled: `specimen-choices` now uses `choice-answer`, and the find-step example shows a chosen customer.
  
  **The code.**
  - `*reference-labels*` is fully replaced; nothing in the repository still refers to it.
  - Every new piece of copy has a Norwegian translation («Valg», «må være et av valgene», «Velg et av valgene.»).
  - Comments explain why the code does what it does, and there's no debugging left behind.
  - The spec is updated where the behaviour lives (`spec/ui.md` §8 «Choosing a record», §7, §9, history; `spec/files.md`).
  - Blank optional ids pass the posted-id check, because `read-choice` returns NIL for an empty value.
  
  **Not blocking:**
  - `spec/files.md` (`diff.patch:584-586`) says the browser's text is «cut at its end». Chrome actually cuts it in the middle («No fi…hosen» in the 320 px shot). The wording could say only that it is shortened.
  - The test for criterion 3 could also assert that no operation is called.
- 2026-11-12 19:10  finished at tun cdb0d325
