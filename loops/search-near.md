# A misspelled word still finds, ranked below exact hits, in the search and in the choice

- loop: search-near
- mode: reviewed
- stage: done
- base: cf0de1df2dc69c8bb91f830e0df7ac7bdc7e4232
- item: sak_nbe1akjs60qsbze8
- estimate: 1h15m 2h 3h30m
- like: tun/search-reads
- verified: 2f51baf9709dd01040736b8fdc739d72630d1ecb
- shown: 2f51baf9709dd01040736b8fdc739d72630d1ecb

## Brief

Ferdig sak_nbe1akjs60qsbze8, brought by the factory's orchestrator on
2026-11-14. Jonas, 2026-11-14, answering question 11A on
sak_xvtp3eht3dcnrh2n: «add near matches in a small loop, always ranked
below exact hits». He was asked because the search's one rule (core
2.31.0, `search-match` in `src/core/search.lisp`) folds case, accents
and ø/æ/å («bjorn ase» finds «Bjørn Åsen») but a misspelled word finds
nothing («minglng» does not find «Mingling»), and a client application's
own search forgives typos today and would lose that if it moved onto
Tun's.

The orchestrator's brief, in short:

1. The one rule learns near matches: a query word that matches no word
   of a record exactly may match a word near it (one letter missing, one
   extra, one wrong, two neighbours swapped; perhaps two faults in a long
   word). The builder decides and states the exact rule (the length
   before a fault is forgiven, how many at what length, whether the first
   letter must be right, whole word or a word's start as one types):
   decidable by a test, cheap, predictable; a short word («AS», «Ola»)
   is never matched nearly.
2. Always ranked below exact hits: a record found only through a near
   match scores below every record found without one, in the search (per
   kind and overall) and in a choice. Several words still need every
   word found, each exactly or nearly.
3. Identifiers stay exact: a number, an order number, an e-mail, a
   phone, a registration number never match nearly; a query word with a
   digit is never matched nearly.
4. One rule everywhere: Ctrl K, `/search`, the MCP tool `search`,
   `search-entity`, `search-among`, `choice-matches`, `choice-answer`,
   `/choices/ENTITY`, and given options narrowed in the browser by the
   choice's script, which follows the server's rule, compared on a table
   of cases.
5. What the person sees: the mark (`search-excerpt`, the line's
   `matched`) covers the word nearly matched, whole. A quiet line over
   results found only nearly only if the spec's rules (§2.1) decide it;
   nothing that needs the owner's taste without asking.
6. Speed: the limits of 2.33.0 and 2.35.0 hold (90 ms for 3×2000 records
   on Postgres, measured alone, never loosened); near matching runs only
   for a word that found nothing exactly, or is as cheap; a new test of
   the worst case, a misspelled word against 3×2000 records, with a
   stated limit. The property test of 2.33.0 still says something true:
   for queries that match exactly, results and order unchanged.
7. Property tests: an exact hit never ranks below a near one; a word with
   a digit never matches nearly; folding and near matching commute where
   the spec says so; a near match is symmetric where it should be.

What stays: every function's call shape; the five clients compile and
pass unchanged (each at its `origin/main`); a client test asserting that
a misspelled query finds nothing is reported, not touched. The core
rises a minor (2.37.0, after `form-nits`' 2.36.0).

The source of the owner's rules for an admin application, 2026-11, has a
search rule of its own: near matches only for words of six letters or
more (raised from five to keep its search fast), exact matches before
near ones, the browser's rule held to the server's by shared fixtures.

## Criteria

1. **The rule's cases.** A table of cases, `tests/search-cases.json`
   (what was typed, an option's text, and «exact», «near» or «none»),
   holds at least 40 cases, among them: «minglng» and «minglni» find
   «Mingling» nearly; «mongleng» and «ningling» do not; «nordvk» finds
   «Nordvik Bakery Ltd» nearly; «bjorn ase» finds «Bjørn Åsen» exactly;
   «hanssen» finds «Hansen» and «hansen» «Hanssen»; «bergen» finds
   «Bergersen», «bergersen» not «Bergen»; one fault of each kind (a
   letter missing, extra, wrong, two swapped) at six and at eight
   letters, two faults at nine, two at eight not; a word of five letters
   with a fault («lunde» for «Lunda», «kunde» for «Kunda») and a word with
   a digit or sign («ab12345», «kari@exampel.no», «ola-nordman») not
   found nearly; a several-word query with one word exact and one near
   found nearly, and with one word nowhere not found. `search-match`
   with the text as a name answers each case: a score of 10 or more and
   NIL as second value for «exact», a score below 10 and T for «near»,
   NIL for «none». (test)
2. **Identifiers stay exact.** No identifier is found nearly: «1043»,
   «SO-1043», «kari@exampel.no» and «+47 912 34 568» do not find a record
   whose identifiers are «1042», «SO-1042», «kari@example.no» and
   `search-phone-forms` of «+47 912 34 567»; a property over random
   identifiers and random one-fault changes of them finds none. An email
   a contributor also gives as a text is found by the words of its
   letters as any text is: «exampel» finds a record whose text is
   «post@nordvik.example» nearly, while the typed email
   «post@nordvik.exampel» finds it neither as an identifier nor nearly.
   (test)
3. **Scores and the order.** A record found nearly scores 5 when every
   word is found in its names, 1 when one is only in its texts.
   `search-among` and `search-entity` answer every record found exactly
   before any found nearly, also when `:score` lowers the exact ones
   below the near ones (by 15, as the orders module, and by 200);
   `search-order` does the same over kinds, with results made with
   `:near`; `choice-matches` answers the rows found exactly first; the
   `search` tool's items carry `near`. (test)
4. **Properties.** Over thousands of random words and texts: a record
   found exactly never scores below or is ordered after one found nearly
   in the same `search-among`; a word holding a digit is never found
   nearly; a query dressed (upper case, accents, «aa» for «å») is found
   as its fold is, and a text as its fold is; two whole words of the same
   length band and first letter within its faults find each other both
   ways; the 2.33.0 property test still holds every record the plain
   (2.32.0) rule finds to the same score, marks and order, and a record
   it does not find is now either not found or found nearly. (test)
5. **The marks.** In a result found nearly, the word found nearly is
   marked whole: «minglng» marks «Mingling» in a title, `search-excerpt`
   and `search-matched-text` start from it and mark it in a long text and
   in MATCHED, and `search-results` with `:near` marks it in the title
   and the line; a result found exactly has no near mark. (test)
6. **Everywhere.** On the test application the customers module finds
   «Nordvik Bakery Ltd» by «nordvk» nearly and the orders module its
   order after it; `/search?q=nordvk`, its fragment and the tool agree;
   `/choices/customer?q=nordvk` (the generated choice) and `choice-answer`
   answer it; a query matching some customers exactly and another nearly
   answers the exact ones first. (test)
7. **The browser's rule is the server's.** The kit's script holds
   `tunSearchFold` and `tunSearchFinds`; a browser check evaluates
   `tunSearchFinds` on every case of `tests/search-cases.json` and
   answers what the table says, as the server does by criterion 1. The
   specimen's given options gain «Nordvika Marina»: typing «nordvika»
   shows «Nordvika Marina» then «Nordvik Bakery Ltd», «nordvk» shows
   both, found nearly, in the order given («Nordvik Bakery Ltd», then
   «Nordvika Marina»), and every case `ui-choice` checks still
   answers as before; an empty text shows them all in the order given.
   (browser check)
8. **The dialog.** On the showcase's search scenario, typing «nordvk» in
   the dialog shows «Nordvik Bakery Ltd» with «Nordvik» marked whole, and
   «catring» shows «Berg Catering» with «Catering» marked; the search
   scenario gains a customer «Hanssen Rigging» (its email,
   «post@rigging.no», holds no text an earlier check's query finds), and typing «hansen» shows «Hansen Plumbing»,
   found exactly, before «Hanssen Rigging», found nearly. Every earlier
   check of the search scenario passes unchanged. Pictures at 390 and
   1280 px, light and dark. (browser check)
9. **Speed.** The speed tests of 2.33.0 and 2.35.0 pass with their limits
   unchanged; a new query in the test of every kind, a misspelled word
   found nearly in 2000 customers and their 2000 orders («nordmnan»),
   and one found nearly in long texts («julebrod»), each answers with a
   median of nine under the same 90 ms, in memory and on Postgres; the
   medians before and after are in the Log. (test, Log)
10. The core is 2.37.0 (or the next free minor); `bin/test` and the
    browser checks are green; the five clients compile unchanged at their
    `origin/main`, and their suites pass but for any test that asserts a
    misspelled query finds nothing, which is not touched: each such test
    is named in the Log and the report, and is not a failure of this
    criterion. (verify, client runs)

## Decisions

- **Six letters, one fault to eight, two from nine.** A word of five
  letters or less with one fault forgiven finds too much («lunde»
  would find «Lunda», «Lunne», «Lund…»; «kunde» «kunne»), and the
  owner's own admin application raised its threshold from five to six
  letters for the same reason and for speed. Two faults only from nine
  letters, where a pair of faults still leaves seven letters right.
- **Faults are the optimal string alignment distance**: a letter missing,
  extra or wrong, or two neighbours swapped, each one fault, no
  substring edited twice. It is what a person means by «one typo», a
  test decides it with a table, and it is symmetric, unlike a trigram
  similarity with a threshold, which a person cannot predict.
- **The first letter must be right.** People rarely mistype the first
  letter, and it keeps near matching cheap: the rule's table of which
  characters start a word of the query already leaves a text without
  any of them unfolded, and only a word starting with the right letter
  is ever compared.
- **A word's start, not a part of a word.** The dialog and a choice ask
  as one types, so a word half typed with a fault must find
  («minglni»); against any part of a word, near matches would find
  nearly everything. A word of a text is a run of letters, so the letters
  of «kunde1@example.no» are «kunde», «example» and «no», and a digit
  never takes part in a near match.
- **Only letters typed.** A word typed with a digit or a sign is an
  identifier or part of one (a number, an email, «SO-1042», a phone);
  it is never found nearly. Identifiers given as identifiers are never
  tried nearly. A contributor that also gives an email as a text (the
  customers module does, so «nordvik» finds «post@nordvik.example»)
  lets its letters' words be found nearly as any text's, but a typed
  email or number never is.
- **Per record, not per search.** A word is tried nearly in a record
  that lacks it exactly, even when other records have it: a search
  answers the same for a record whatever else is stored, the browser's
  rule over one option's text is the server's, and «always ranked
  below exact hits» means they come after, not instead.
- **Scores 5 and 1, and an order that does not trust them.** A record
  found nearly scores 5 (every word in the names) or 1, below the exact
  rule's lowest, 10, so a contributor that sorts by score alone is
  right. But a contributor may lower scores (the orders module by 15, so
  an exact order can score −5), so the order itself puts every result
  found exactly first: `search-match` answers a second value, a result
  carries `near` (`make-search-result :near`), and `search-among`,
  `search-entity` and `search-order` sort by it before the score.
  `choice-matches` has no score function and sorts by score. Near
  matches are not ranked by their number of faults in this loop (a
  later loop; the spec's «Not yet»).
- **No quiet line.** The owner's rules (§2.1) ask for nothing that sets a
  weaker result apart, and the mark over the whole word it was found by
  says why it was found; the results found nearly come last. A line
  such as «Similar spellings» would need the owner's wording and taste:
  a question in the report, not built.
- **Marks.** A result found nearly marks, in each text, a word not found
  there exactly over the whole word of the text it is nearly in; a
  result found exactly is marked as before, so the marks of 2.32.0's
  property test do not change. `search-mark-ranges`, `search-excerpt`
  and `search-matched-text` take `:near`, and `search-results`' items
  `:near`, which the page takes from the tool's `near`.
- **The cost: in the same pass.** `search-match` tries a word nearly
  while it folds a text for the exact rule, when the word is long
  enough and not found in that text exactly, at each word start whose
  first letter is the word's and whose run of letters is not too short,
  with a small dynamic programme bounded by the word's length. No text is
  folded twice. A query none of whose words may be found nearly (short
  words, numbers) does exactly what it did.
- **The browser's rule.** The fold and the near rule move into the kit's
  script as `tunSearchFold` and `tunSearchFinds`, so a check can call
  them, and the choice's script uses them; the fold gains the letters
  the server folds that it lacked («ı», «þ») and decomposes as the
  server does (NFKD, removing only the non-spacing marks). Given options
  are shown exact first, then near, each in the order given: the script
  moves them in the list and puts them back in the order given when the
  text is emptied.
- **The specimen's given options** gain «Nordvika Marina», last, so a
  query («nordvika») finds a later option exactly and an earlier one
  nearly; none of the cases `ui-choice` checks changes.
- **Spec**: `spec/ui.md` §6.4 (the rule's near matches, the score, the
  order, the marks, the cost, the tool's `near`, `search-results`'
  `:near`), §6 (`choice-input`'s given options, `choice-matches`), §9,
  §10 and the status line; `docs/client-api.md` «The search».

## Clients

On this loop's tree rebased on 2.36.0 (committed as 6b5f333c), each
client's `bin/test` with `--override-input tun` at it (and `dashboard`,
and tun-erp's `customers`, at their `modules/` directories), one at a
time, from clones of their `origin/main` in a scratch folder: factory and
nixploy-dashboard and ferdig (tunworks `edbdc75`, 583, 1421 and 812
checks) and kurs `a82a83d` (352) pass, with no change to any of them.
tun-erp `1a49875` passes all four of its suites, its own search tests
among them, but for two checks of its suite `erp`
(`the-parity-checks-find-each-planted-mistake`,
`the-parity-map-holds-every-item-once-with-what-proves-it`): its
`factory/parity.md` names a plan key «order-files-comments» its plan
does not hold, a mistake in its own repository's documents that no Tun
change touches. No client has a test asserting that a misspelled query
finds nothing.

## Pictures

Before (`origin/main`, 2.35.0) in `~/coding/tun-wt/search-near-shots/before/`
(the specimen's search-results, search-dialog and choice-input at 390 and
1280 px, light and dark); after in `~/coding/tun-wt/search-near-shots/after/`
(the same, the specimen's new search-results example «catring», and from
`search-near.py` the dialog finding «Nordvik Bakery Ltd» by «nordvk»,
«hansen» finding Hansen Plumbing before Hanssen Rigging, and the given
options for «nordvika», each at 390 and 1280 px, light and dark). Before
this loop the dialog answered «nordvk» with «No results for «nordvk»».

## Actuals

```json
{"loop":"search-near","title":"A misspelled word still finds, ranked below exact hits, in the search and in the choice","repository":"tun","mode":"reviewed","stage":"done","item":"sak_nbe1akjs60qsbze8","tags":[],"like":["tun/search-reads"],"started":"2026-11-14 19:07","ended":"2026-11-14 21:03","minutes":{"total":116,"waiting_person":0,"waiting_reviewer":4,"working":112,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":75,"likely":120,"worst":210,"at":"brief"},"latest_estimate":{"best":75,"likely":120,"worst":210,"at":"brief"},"within_estimate":true,"ratio":0.97,"verify":{"rounds":3,"failed":2},"changes":{"A":1,"B":0,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-14 19:07  started, reviewed
- 2026-11-14 19:07  estimated 1h15m 2h 3h30m at brief, like tun/search-reads
- 2026-11-14 19:12  gate A asked of a reviewer
- 2026-11-14 19:14  gate A: changes (reviewer)
  I'm asking for changes at Gate A. Most of the spec is sound, but one criterion contradicts the rule the spec defines, so as written it can never pass.
  
  **What is right**
  - **The brief is covered.** Each of brief items 1–7 has a criterion:
    - The rule and its table of cases: criterion 1.
    - Identifiers stay exact: criterion 2.
    - Exact hits ranked first, even when a contributor lowers their scores: criterion 3.
    - The properties, including the 2.33.0 property test restated for near matches: criterion 4.
    - The whole word marked: criterion 5.
    - Every surface where the rule is used: criteria 6–8.
    - Speed, with the old limits kept: criterion 9.
  
    Nothing goes beyond the brief.
  - **The criteria can be tested.** I worked through the named cases by the stated rule (one fault up to eight letters, two from nine, first letter right, a word's start), and they come out as the table says:
    - «minglng» and «minglni» are each one fault from a start of «mingling».
    - «mongleng» is two faults from «mingling», and «ningling» has the wrong first letter.
    - «hansen» and «hanssen» find each other both ways.
    - «bergen» finds «Bergersen» by its start «berger», but «bergersen» is three faults from «bergen».
    - «catring» is one letter missing from «catering».
  - **The new specimen option breaks nothing.** I checked the existing `ui-choice` checks against «Nordvika Marina» (`checks/showcase/checks/ui-choice.py:353-363`), and none of their answers change.
  - **The builder's decisions are theirs to make.** The brief left the exact rule to the builder: the length, the faults, the first letter, a word's start. The six-letter threshold matches the owner's own admin application. Building no quiet line, and asking about it in the report instead, is what brief item 5 asks for.
  - **The spec text agrees with the criteria.** That covers the scores 5 and 1, ordering by `near` before the score, `:near` on results, `search-results` and the marks, the tool's `near`, the choice's given options, and moving the item from «Not yet» into the spec.
  
  **Changes**
  1. **Criterion 7 can never pass.** In `loop.md:125-126` it says «nordvk» shows «Nordvik Bakery Ltd» *alone*. Under the rule in `spec/ui.md` (diff lines 125–128: "the whole run or any start of it is within its faults"), «nordvk» is one fault from «nordvik», which is a start of «Nordvika». So «Nordvika Marina» is also found nearly. Either:
     - expect both options, in the order given («Nordvik Bakery Ltd» then «Nordvika Marina»), or
     - pick a query that really finds only one of them.
  2. **Emails stored as text can be found nearly.** Brief item 3 says an e-mail never matches nearly. Under Decisions («Only letters typed»), the letter-words of an email that a contributor also stores as text can be: «exampel» would find «post@nordvik.example». That is defensible, since the exact rule already finds those words, but:
     - the §6.4 «Which words» paragraph (diff lines 108–114) only says identifiers given *as identifiers* are never found nearly, and nowhere says that an email stored as text can be found by its words;
     - no criterion tests it either way.
  
     Add one sentence to the spec, and one case to criterion 1 or 2, so that this departure from the brief's wording is written down and tested rather than implied.
  3. **Criterion 10 contradicts the brief about client tests.** It says the five clients "pass unchanged". The brief says a client test asserting that a misspelled query finds nothing is to be *reported, not touched*. Add that such a test failing is reported in the Log and is not a failure of this criterion. Otherwise criterion 10 cannot be met when such a test exists.
  
  **A small formatting point:** two lines in `spec/ui.md` run past the file's line width: diff line 49 («(`tests/search-cases.json`). With SOURCE…») and diff line 111 («…which a fault would let find too much. Identifiers are never…»). Rewrap them while making the changes above.
- 2026-11-14 19:14  gate A asked of a reviewer
- 2026-11-14 19:15  gate A: approve (reviewer)
  I'm approving this gate. The second round of the spec fixes all three changes asked for at the first review, and I found nothing new that blocks it.
  
  **The first review's changes are fixed**
  1. **Criterion 7** now expects «nordvk» to show both options, found nearly, in the order given. That fits the rule: «nordvk» is one fault from «nordvik», which is a start of both «Nordvik» and «Nordvika». «nordvika» also works out: it finds «Nordvika Marina» exactly, and «Nordvik Bakery Ltd» nearly, one fault from «nordvik».
  2. **Emails stored as text** are now written into §6.4 «Which words» (diff lines 118–122). Criterion 2 tests both ways: «exampel» finds «post@nordvik.example» nearly, and the typed email «post@nordvik.exampel» is not found nearly.
  3. **Criterion 10** now says that a client test asserting a misspelled query finds nothing is named in the Log and the report, and does not count against the criterion. That is what the brief asks.
  4. **Line width:** the long line in «Which words» is rewrapped, and the `choice-input` paragraph is rewrapped within the width.
  
  **Checked again this round**
  - **Criterion 1's named cases** follow the stated rule. «hanssen» and «hansen» are one fault apart either way. «bergen» finds «Bergersen» through its start «berger», while «bergersen» is three faults from «bergen». «exampel» is one swap from «example», where a word starts after «.».
  - **The scores** fit the table's limits. A near match in the names scores 5, below the 10 that «exact» needs. An exact match in the names scores at least 25.
  - **«aa» for «å»** in criterion 4 matches the existing fold (`spec/ui.md:1877`).
  - **The new customer «Hanssen Rigging»** breaks none of the queries in `checks/showcase/checks/ui-search.py` («nord», «item», «e»/«ex», «zebra», «bjorn ase», «412 34», «nordvik»). None of them finds it exactly. The «nordvik» check on the search page only asserts the first title, so a result found nearly further down doesn't change it.
  - **Brief items 1–7** each still have a criterion, and nothing goes beyond the brief. The decisions are the ones the brief left to the builder. The «quiet line» is deferred as a question in the report, which is what brief item 5 asks for.
  - **The spec text agrees with the criteria**: the scores 5 and 1, `:near` on results and the tool's `near`, the ordering, the whole-word marks, the cost, and the «Not yet» list updated.
- 2026-11-14 19:34  before (2.35.0, the search suite alone with bin/with-postgres, load 4-8; medians of nine, the two new queries added to the test): memory kunde 1999 36, nordmann 39, julebord rigging 28, zebra 20, 912 19 20, nordmnan 32, julebrod 31 ms; Postgres 43, 43, 47, 36, 34, 43, 40 ms (the misspelled words found nothing)
- 2026-11-14 19:34  after (this tree, same run, load 3-4): memory kunde 1999 30, nordmann 36, julebord rigging 27, zebra 18, 912 19 22, nordmnan 44, julebrod 26 ms; Postgres 51, 51, 43, 35, 42, 56, 56 ms; every one under the 90 ms limit, the misspelled words now finding 2000 customers and orders, and long texts, nearly
- 2026-11-14 19:37  rebased: tun 97ade0c → cf0de1d
- 2026-11-14 19:52  verify 2: failed test
- 2026-11-14 20:08  verify 3: failed test
- 2026-11-14 20:08  verify 2 and 3 failed only on speed tests under another builder's load (load 7-12) in bin/test's parallel run: 2.33.0's every-kind test on Postgres for «kunde 1999» (109 ms; a query no near match runs for: «kunde» has five letters and «1999» digits), and 2.35.0's orders' list on Postgres (50.0 ms more against a limit of 50); round 3 passed the search suite, round 2 generated-choice. Every other suite and every browser check passed in both. Limits unchanged; waiting for a quieter machine
- 2026-11-14 21:00  verify 5: passed build, test, check
- 2026-11-14 21:00  shown (/search?q=nordvk, /search?q=hansen, /ui/choice-input)
- 2026-11-14 21:01  gate B asked of a reviewer
- 2026-11-14 21:02  gate B: approve (reviewer)
  I approve gate B of search-near. Every criterion has a test or browser check that would fail without the change, all three verify steps passed in round 5, and the code and spec agree.
  
  **Criteria**
  1. **The table of cases.** `tests/search-cases.json` holds 55 cases and covers each named one. That includes one fault of each kind at six and eight letters (riging, lunndi, hensen, hnasen; bergesen, nordviik, catexing, cateirng), two faults at nine (caterrnig, konfimasjno) and two at eight not found (cxterinh). `search-near-tests.lisp:404` holds `search-match` to the table's score limits and its second value.
  2. **Identifiers stay exact.** The named identifiers and phone are tested, plus 2000 random identifiers each with one fault (`:436-463`). The test checks both sides of the email case: «exampel» finds the email given as text, and the typed email does not.
  3. **Scores and order.**
     - Scores of 5 and 1 are tested.
     - `search-among` is tested with `:score` as identity, −15, −200, and a function that pushes near scores above exact ones.
     - `search-order` is tested over kinds with `:near`.
     - `choice-matches` and the tool's `near` are tested.
     - `search-entity` goes through `search-among` (`src/core/search.lisp:834`), so it is covered too.
  4. **Properties.** All four are there. The 2.33.0 property test now keeps the plain rule's records at the same score, marks and order, and lets a record the plain rule missed only be found nearly. The `search-among` comparison checks the exact results come first.
  5. **Marks.** The title, the excerpt, MATCHED and `search-results`' title and line are each tested, and a result found exactly has no near mark.
  6. **Everywhere.** The tool, the page and its fragment, and `/choices/customer` all answer the exact match first and «Nordvik Bakery Ltd» nearly, with its order after it.
  7. **The browser's rule.** The browser check runs `tunSearchFinds` on all 55 cases with no mismatch. The given options answer «nordvika» and «nordvk» in the order criterion 7 asks for, and show every option in the order given when opened again.
  8. **The dialog.** «nordvk», «catring» and «hansen» behave as the criterion says. The earlier `ui-search` checks still pass, and every check under `checks/` passes.
  9. **Speed.** The new queries «nordmnan» and «julebrod» are in the test of every kind under the unchanged 90 ms limit. The Log records medians before and after; the worst after is 56 ms, on Postgres.
  10. **Version and clients.** The core is 2.37.0 in both `flake.nix` and `module.lisp`. Client results are in the Log.
  
  **Screenshots.** At 390 and 1280 px:
  - «hansen» shows Hansen Plumbing before Hanssen Rigging, each marked.
  - «nordvk» marks the whole word «Nordvik».
  - «nordvika» in the given options shows Nordvika Marina before Nordvik Bakery Ltd.
  
  **Brief.** The change does what the brief asks, not only what the criteria say:
  - one rule, implemented once in Lisp and once in the kit's script, held together by the shared table;
  - an order that puts exact hits first even when a contributor lowers their scores;
  - near matching done in the same pass as the exact rule, and only for words that may be found nearly;
  - no quiet line built, with the question left for the report.
  
  **Code.**
  - **The fault count.** I checked `start-within-p`, which only fills cells near the diagonal and stops early once two rows are over the limit. That is sound, and the browser's unbanded version is equivalent.
  - **The given options.** `choiceNarrow` caches the options by list, which is safe because it only runs for given options, never asked ones.
  - **Readability.** There is no leftover debugging, and the spec is changed where the behaviour changed: §6, §6.4, §9 and «Not yet».
  
  **One thing for the report, not a blocker.** tun-erp fails two `erp` checks, so strictly it does not pass. The Log blames a plan key its own `factory/parity.md` names that its plan lacks, which is unrelated to search, and neither check is about a misspelled query. The Log doesn't say these checks were also run on tun-erp against 2.36.0 to confirm they already failed. The report should name both and say they come from tun-erp's own documents.
- 2026-11-14 21:03  finished at tun 3a08219e
