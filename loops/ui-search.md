# One search for the whole application, opened with Ctrl K

- loop: ui-search
- mode: reviewed
- stage: done
- base: af2003dcf2f75e5e1214d34812fdcb6f0ebfb997
- item: sak_jtrmh62tdgnxwjgq
- estimate: 2h 3h 5h
- like: tun/ui-fields tun/ui-filters
- tags: kind:ui module:search
- verified: d0a41e303f031e4efe8e151b716b853da5ecb079
- shown: d0a41e303f031e4efe8e151b716b853da5ecb079

## Brief

The seventh and last loop of the UI library work (Ferdig item
sak_jtrmh62tdgnxwjgq, under sak_xvtp3eht3dcnrh2n). Jonas, 2026-11-11: he
has polished the admin UI of another application of his for two weeks
and wants the best of it carried into Tun's component library, «to make
the UI component Library of Tun superb»; rules, values, anatomy and
behaviour carry over, not code. The source is the owner's rules for an
admin application, 2026-11: its one search, opened with Ctrl K, and the
one rule every search there matches by.

His rule for this loop, as the orchestrator gave it: **one search for the
whole application, on Ctrl K, with one rule for what matches.** Today Tun
has the parts and not the thing: `dialog` takes a `:shortcut`, `button`
shows a shortcut's caps, the specimen has a «Search from anywhere»
example, the `combobox` finds, and each client that wants a search builds
its own through `staff-page-extras`. This loop gives a seam for what can
be found, one rule implemented once, the dialog in every shell of an
application that has something to find, a page that works without
JavaScript, and the same search as an agent's tool.

The orchestrator's brief for the rule: «One rule for what matches,
written in the spec and implemented once as a function contributors call
(not re-invented per module): case and diacritics folded, every word of
the query must match … (decide from the inventory's rule; say it in one
sentence), numbers such as an order number match exactly or by prefix,
ranking by where it matched (title before meta).» And for agents: «the
same search is a tool over MCP (`search` with `query`, optional `kinds`,
`limit`)».

Out of scope: moving the clients' own searches onto the seam (reported),
full text of long texts, search history, filters inside the search.

## Criteria

1. `search-records` is a generic function in `TUN` with the
   `traced-protocol` combination, listed by `introspect_extensions`,
   whose own least specific method answers no results; a module's method on
   its mixin and a client's on its class both contribute when each
   appends `(call-next-method)`, the client's results first among equal
   scores. (test)
2. `search-match` folds case, marks, «ø æ œ ß ł đ» and a run of «a» on
   both sides; a record matches only when every word of the query is in
   one of its texts in any order, or the whole query is an identifier or,
   holding a digit, its start from three characters, compared without
   spaces and «+ - . # ( ) /»; it scores 100, 90, 80, 60, 45, 25 and 10 as `spec/ui.md` §6.4
   says. A property test: random records are found by their own words
   folded, reordered, cased and accented, and by each word's start, and
   never with a word that is in none of their texts. (test)
3. The title's marks cover the stored characters each word matched,
   «kafe» marking «kafé» and «bjorn» «Bjørn», as `<mark>` nodes. (test)
4. A result whose href is a page or a record the actor's role cannot
   open is dropped and written to the server's error output, and one
   whose href is a client's own staff page the
   actor's role opens is kept: an employee and an admin searching the
   same text get different results; on Postgres an entity's record
   policy decides which records each finds. (test)
5. Results come best score first, then by kind in the contributors'
   order, then in each contributor's order; at most five of a kind and
   twenty in all. (test)
6. The customers module finds customers (name; email and phone as
   identifiers; meta their email and phone) and the orders module orders
   (by their customer's name, their delivery address and their id,
   scoring as their customer would less 15), with no code in a client; an
   application without a contributor has no search button, row, dialog
   or shortcut, and `/search` answers 404. (test)
7. 2000 customers are searched within 100 ms on the server, in memory,
   and on Postgres when the test server is there. (test)
8. With a contributor, every staff page's `app-shell`, for an admin, an
   employee and a viewer alike, holds the top bar's «Search» link to
   `/search`, the sidebar's row with the Ctrl K caps and
   `aria-keyshortcuts`, and the search dialog with `:shortcut "Ctrl+K"`
   last in the shell, after a page's own dialog on Ctrl K. (test)
9. `/search?q=` is a GET form and the results as a list of links, each
   with the kind's icon, the title with its marks and a meta line that
   starts with the kind's word, «No results for «…»» when there are none
   and nothing under two characters; an htmx request for part of it
   answers the list alone; the `search` tool answers the same results as
   data; one test shows the page, the fragment and the tool agreeing for
   one query. (test)
9a. The `search` tool's `kinds` keeps only the results of the kinds it
    names (the customers and orders modules skip reading a kind left
    out), and its
    `limit` cuts the list after the order and the five of a kind; a
    `limit` outside 1 to 20, or a `query` under two characters, is
    refused as invalid input. (test)
10. The CSS: the marked row changes its ground and frame, never its
    weight, size, padding or edge; `<mark>` takes its colours from the
    tokens, not the accent; `:size :large` is a fixed box from 40rem; the results scroll
    in their own box. The earlier scans of `ui-look` and `ui-sheets` hold
    for the new parts. (test)
11. A browser check on the showcase (cards and customers found): Ctrl K
    and ⌘ K open the dialog with the focus in the field, «⌘» on a Mac,
    and what was typed before selected when it opens again; at
    1280 px the dialog's box is the same with no results, with «No
    results» and with the most the showcase finds (its two kinds, five
    of each); typing shows results within 1.5 s of the
    last key with the match in a `<mark>`; ↓ and ↑ move the mark at the
    others' weight and size; Enter opens the marked row; an Enter typed
    at once after the keys opens the first row of the latest answer; a
    slow earlier answer never replaces a later one; a failed answer says
    so; Escape closes it with the focus back on the opener; on `/items`
    Ctrl K opens the page's own dialog; at 390 px the top bar's button
    opens it as tall as it may be and above a keyboard; without
    JavaScript the button leads to `/search` and its form lists the
    results; the server's time for the showcase's searches is measured.
    (check)
12. The specimen shows `search-results` and `search-dialog`; pictures at
    390 and 1280 px, light and dark, of the shell closed, open with
    results and the marked row, and empty. (pictures)
13. Every earlier test and check stays green, and the five clients
    compile and pass unchanged. (verify, client runs)

## Decisions

- **The rule is the owner's: every word as a part of a word, not only
  its start.** The source finds «floss super» in «… Super Floss» and a
  word inside another; the start of a word ranks higher (45 against 25),
  so a word's start comes first in the order.
- **Near matches for a word typed wrong are not in this loop; whether
  they come next is Jonas's question.** The rule this loop was given
  names its parts: case and diacritics folded, every word of the query
  found, numbers exact or by their start, ranked by where they matched,
  one function every contributor calls. The source's owner built it in
  that order too: «one matching rule everywhere first, then ranking and
  typo tolerance on top» (2026-11-06), and its trigram near matches came
  after, as a layer that only adds hits below every exact one. So this
  loop builds the exact rule, which near matches would extend without
  changing (a near hit scores below 10, the lowest exact score), §9
  names them, and the question goes to Jonas in the loop's report, not
  decided here.
- **The tool's `kinds` and `limit` are the agent's, not filters of the
  search.** The brief asks for the tool with them: an agent that wants
  only customers asks for them, and a `limit` keeps its answer short.
  A person's search, the page and the dialog, asks for every kind and
  shows the twenty; nothing in the dialog or on the page chooses kinds,
  which is the filter left out of scope. `search-query-kinds` lets a
  contributor skip reading an entity no one asked for.
- **A run of «a» is one «a»** as in the source, so «aasen» finds «Åsen»;
  the cost is that «sab» finds «Saab».
- **Identifiers are whole, or a start from three characters when what
  was typed holds a digit**, compared without spaces and signs: one
  place for an order's number, an email, a phone written «412 34 567».
  Words of one or two characters therefore never match an identifier, as
  the source's short words skip contact fields, and the start of an
  email never ranks a customer above one whose name it is: the source
  scores only whole emails.
- **The seam answers results, appended through `call-next-method`**,
  in the `traced-protocol` combination the domain seams use, so each
  contributor is a step of the request's trace. An `append` combination
  would make forgetting the call impossible, but would not be traced;
  the docstring and the client API say to append, and the test pins a
  module's and a client's both kept.
- **Tun drops what the actor cannot open**, by the result's href, as the
  home page does (`home-page-opens-p`), and a record page only when the
  actor may call the resource's get tool. Record policies are the
  store's, applied because contributors read in the actor's
  transaction. A second check of each record would cost a read per
  result.
- **No index.** Tun's store has no text search: `select` has no
  pattern, `define-query` runs only on Postgres and the memory store runs
  the tests. `search-entity` reads a kind's records once per search and
  matches in Lisp, which is what `customers_list` does for its query; the
  test measures 2000 customers. A Postgres trigram index is §9.
- **One list, labelled by kind, not groups.** The source's hits form one
  list best first, each row's icon and meta line saying its kind; groups
  would put a weaker customer before a better order.
- **The debounce is htmx's own**: `hx-trigger="input changed
  delay:150ms"` and `hx-sync="this:replace"`. The script only guards
  what htmx does not: an answer for an older query is not swapped in
  (htmx 4 does not always cancel a slow earlier request, Ferdig
  sak_y3s3wajkhf6t67yx), a failed answer shows the error, the arrows,
  and Enter waiting for the latest answer. Under two characters the
  server answers an empty list; htmx's trigger filters run JavaScript
  from markup, which Tun's extension refuses.
- **The page's own Ctrl K dialog wins.** The search's dialog is last in
  the shell, and the shortcut opens the first dialog in the page that
  takes the key: a client that built its own (through
  `staff-page-extras` or in a page, as the showcase's `/items` has) keeps
  it, and the search keeps its button and row. None of the five clients
  has a contributor and its own Ctrl K dialog at once.
- **The button and the row are links to `/search`**, turned into opening
  the dialog on a click where scripts run, so without JavaScript they
  lead to the page; the dialog's form is a GET to the same page.
- **The dialog keeps a title**, «Search», as every dialog has, for its
  name and its close button; the field's label is hidden, the title
  naming the same.
- **The mark and the marked row keep §2.1's accent rule.** The source
  tints a match with its accent and rings the marked row in it; Tun's
  accent is only for focus, what is on, a text selection and a drop
  (`ui-look`'s test holds every component to it). So a match is tinted
  with the text colour at 14 %, and the marked row, which is chosen, has
  the pointer's ground and the chosen frame, 1px of `--border-strong`.
- **`:size :large` is a new option of `dialog`** rather than a second
  dialog: the sheet, the keyboard, the motion and the focus stay the
  dialog's own.
- **The search page is `:viewer` and up**, as read tools are; what a
  viewer finds is what they may open. Every role a staff page admits
  opens it, so the shell needs no second check of the role.
- **Spec**: `spec/ui.md` §6.4 (new), §6 (`dialog`'s size, the set), §8
  (the frame), §9, §10; `docs/client-api.md` «The search».

## Actuals

```json
{"loop":"ui-search","title":"One search for the whole application, opened with Ctrl K","repository":"tun","mode":"reviewed","stage":"done","item":"sak_jtrmh62tdgnxwjgq","tags":["kind:ui","module:search"],"like":["tun/ui-fields","tun/ui-filters"],"started":"2026-11-12 06:23","ended":"2026-11-12 08:46","minutes":{"total":143,"waiting_person":0,"waiting_reviewer":5,"working":138,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":120,"likely":180,"worst":300,"at":"brief"},"latest_estimate":{"best":120,"likely":180,"worst":300,"at":"brief"},"within_estimate":true,"ratio":0.79,"verify":{"rounds":7,"failed":4},"changes":{"A":1,"B":1,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-12 06:23  started, reviewed
- 2026-11-12 06:32  estimated 2h 3h 5h at brief, like tun/ui-fields tun/ui-filters
- 2026-11-12 06:32  gate A asked of a reviewer
- 2026-11-12 06:33  gate A: changes (reviewer)
  I've read the packet: `loop.md`, `diff.patch`, and for comparison `home-page-opens-p` and §8 in the repository. My verdict is changes. Most of the spec is sound, but three things need settling before it is built.
  
  **What is right**
  
  - The brief's six parts each have a criterion: the seam, one rule implemented once, the dialog in every shell, the page without JavaScript, the agent's tool, and the specimen. Nothing out of scope has crept in, apart from item 2 below.
  - Each criterion can be decided by a test, a check or a picture. The scores, folds, limits (five of a kind, twenty in all), timings (100 ms, 1.5 s) and sizes are concrete.
  - §6.4 says the same as criteria 1–12. That covers the seam and its `traced-protocol` combination, the client's results first, the fold, identifiers from three characters, the order, the marks, the `/search` page, the fragment, the tool, the dialog's size, the keys, the page's own Ctrl K dialog winning, and the behaviour without JavaScript. §10's evidence matches the criteria. The client API's text and example agree with §6.4.
  - The other decisions are fine for the builder to make: one list, no index, htmx's debounce, `:size :large` on `dialog`, `:viewer` and up, and the button and row as links.
  
  **Changes**
  
  1. **The access rule leaves out the client's own pages.** In `spec/ui.md` §6.4, "Only what ACTOR may open" (diff.patch:127–132), a result is kept only for "a staff page of a module the application enables", a resource's list, or a resource's record. The rule it says it copies, `home-page-opens-p` (`src/web/ui.lisp:1892`, described in §8 at `spec/ui.md:1935`), also covers a client's own `define-page` pages and the kernel's. As written, a client result that links to its own staff page would be dropped. The client API's own example, `href "/items/~a"`, may be exactly that case. Say "a staff page (`define-page`, the client's, a module's or the kernel's) whose policy admits ACTOR", as §8 does. Criterion 4 should also test a client page result being kept.
  
  2. **The tool's `kinds` and `limit`, and `search-query-kinds`, are not in any criterion** (diff.patch:116, 197–198). The brief puts "filters inside the search" out of scope, and choosing kinds is such a filter. Either remove `kinds` and `search-query-kinds`, or keep them only as an internal optimisation, add a criterion with a test, and say in Decisions why they don't count as the excluded filter. Either way, `limit` needs a test or should go.
  
  3. **Leaving out near matches is the asker's decision.** The brief asks for "the one rule every search there matches by", and the rules are meant to carry over. The first decision says the source's rule includes near matches for a mistyped word (trigrams) and drops them, deferring them to §9. That is a cut to the rule the asker named, not a detail of how to build it, and the brief's out-of-scope list doesn't include it. Ask Jonas before building, or add it to the criteria.
  
  4. **Small: criterion 8 drops a condition the spec has.** It says every staff page's `app-shell` holds the search. §6.4 (diff.patch:136) adds "for a person whose role opens `/search` (`:viewer` and up)". Add that condition to criterion 8, so the test also checks that a role below viewer has no button, row or dialog.
- 2026-11-12 06:34  gate A asked of a reviewer
- 2026-11-12 06:35  gate A: approve (reviewer)
  The four changes asked for at the first gate A review have been dealt with, and nothing else blocks the spec. I approve.
  
  **The earlier changes**
  
  1. **Your own pages in search results.** §6.4's "Only what ACTOR may open" (diff.patch:128–134) now covers every staff page whose policy lets the actor in: your own, the kernel's and the modules'. That matches §8's `home-page-opens-p`. Criterion 4 now tests that a result pointing at your own staff page is kept, and §10 lists that test.
  2. **The tool's `kinds` and `limit`.** The earlier review was wrong to call these out of scope. Your brief asks for them by name ("`search` with `query`, optional `kinds`, `limit`"). They are now pinned by criterion 9a, with tests for the inputs the tool refuses. The decision explains why they are not the excluded "filters inside the search": a person's search never chooses kinds.
  3. **Near matches for mistyped words.** The decision now argues this well. The rule in your brief lists its parts (folding, every word, numbers exact or by their start, ranking), and none of them is near matches. The source's owner also built near matches after the exact rule, as a layer that only adds hits ranked below every exact one. The design leaves room for that layer without changing anything (a near hit would score under 10, the lowest exact score). §9 names it, and the question goes to Jonas in the loop's report. Deferring it this way is reasonable, and it is not a silent cut.
  4. **Who sees the search.** Criterion 8 now names admin, employee and viewer. §6.4 says `/search` is open to `:viewer` and up, which is every role a staff page lets in. So there is no lower role to test, and the criterion and the spec agree.
  
  **The rest**
  
  - Each part of the brief has a criterion:
    - the place where modules and clients add what can be found (1)
    - the one rule, implemented once (2, 3)
    - access (4)
    - ordering (5)
    - the customers and orders modules (6)
    - speed (7)
    - the search in every shell (8)
    - the page without JavaScript and the tool (9, 9a)
    - CSS (10)
    - browser behaviour (11)
    - specimen (12)
    - regressions (13)
  
    Nothing on the out-of-scope list has come in.
  - Every criterion can be decided by a test, a check or a picture: the scores, folds, limits, timings and sizes are all concrete.
  - §6.4, the `dialog` size note in §6, §8, §9, §10 and `docs/client-api.md` agree with the criteria.
  - The other decisions are reasonable for the builder to make alone. Each is grounded in the source or in how Tun already works.
  
  **Small points, not blocking (worth tidying at gate B)**
  
  - The orchestrator asked for the rule to be "said in one sentence". §6.4 gives it as bullets with no one-sentence summary. A single opening sentence under **The rule** (diff.patch:145) would honour that.
  - Three things §6.4 promises have no criterion:
    - orders scoring as their customer less 15
    - a dropped result being written to the server's error output
    - text typed earlier being selected when the dialog reopens
  
    They are easy to add to the tests in criteria 6, 4 and 11.
  - Criterion 9a says "a contributor is not asked for a kind left out". But §6.4 has contributors *choose* to skip kinds via `search-query-kinds`, so Tun does not stop asking them. The test can only show that the built-in modules skip. The criterion's wording should match the spec.
  - `spec/ui.md`'s header (diff.patch:59) leaves "How every Tun page" as a short orphan line, so the paragraph wants re-wrapping.
- 2026-11-12 07:06  verify 1: failed test
- 2026-11-12 07:23  verify 2: failed test
- 2026-11-12 07:35  verify 3: passed build, test, check
- 2026-11-12 08:02  verify 4: failed check
- 2026-11-12 08:15  verify 5: failed check
- 2026-11-12 08:28  verify 6: passed build, test, check
- 2026-11-12 08:28  shown (/cards, /search?q=bjorn, /customers)
- 2026-11-12 08:28  gate B asked of a reviewer
- 2026-11-12 08:30  gate B: changes (reviewer)
  Gate B verdict: changes. The search works, but two things the criteria require are missing.
  
  ## What is right
  
  - **Verification:** round 6 passed build, test and check. `checks/ui-search.json` passed every step.
  - **The rule is written once** (`src/core/search.lisp`). `search-fold`, `identifier-score`, `names-score` and `search-match` follow §6.4's scores (100, 90, 80, 60, 45, 25, 10). The property test runs 2000 random records with folded, reordered, cased and accented words and their starts, and also checks that a word in none of a record's texts finds nothing. §6.4 now opens with the one-sentence rule that gate A asked for.
  - **Criteria 1, 3, 4, 5, 7, 9 and 9a have real tests** in `tests/search-tests.lisp`:
    - (1) the `traced-protocol` combination and `introspect_extensions`, with the client's results first and the module's also kept;
    - (3) the marks on the stored characters, including «aasen» marking «Åsen»;
    - (4) the drop is written to the error output, a client's own page is kept, admin, employee and viewer get different results, and the record policy is checked on Postgres;
    - (5) the order, five of a kind and twenty in all;
    - (7) 2000 customers within 100 ms;
    - (9) the page, the fragment and the tool agree;
    - (9a) `kinds` and `limit`, the inputs the tool refuses, and the modules skipping a kind left out.
  - **The browser check covers all of criterion 11:**
    - Ctrl K and ⌘ K, and the text typed before is selected when the dialog opens again;
    - a fixed 640×576 box with no results, «No results» and the most found;
    - results in about 170 ms;
    - the marked row at the others' weight, size, padding and height;
    - an Enter typed at once opens the latest answer's first row;
    - a held slow answer never replaces the later one;
    - a 500 and a dropped connection both show the error;
    - Escape returns the focus to the opener;
    - on `/items` Ctrl K opens the page's own dialog;
    - a full-height sheet at 390, 360 and 320 px that stays above a keyboard;
    - without JavaScript the button leads to `/search` and its form lists the results;
    - the server times are measured at 5–8 ms.
  - **The screenshots** show the sidebar's row with its caps at 1280 px, the top bar's icon button at 390 px, and `/search?q=bjorn` at both widths, with «Bjørn» marked and the meta line starting «Customer ·».
  - **The code is clean.** There is no debugging output. The script keeps to what htmx does not do. The spec, `docs/client-api.md` and both modules' READMEs are updated, and the core version is bumped in both places.
  
  ## Changes
  
  1. **Criterion 12 is not met: there is no picture of the search open.** The criterion asks for pictures at 390 and 1280 px, light and dark, of the shell closed, open with results and the marked row, and empty.
     - The packet's `shots/` has only light, closed pages and `/search`. There are no dark pictures, no open dialog and no empty dialog. Every entry in `checks/ui-search.json` has `"screenshot": null`.
     - The specimen shots in the worktree (`.build/ui/shots/search-dialog-{390,1280}-{light,dark}.png`) show only the closed «Search» button, because the example's dialog is never opened.
     - **To fix:** have `ui-search.py` take screenshots, or add specimen examples that render the dialog open. The pictures needed are open with results and the marked row, and open with «No results», at 390 and 1280 px, light and dark, and they should be in the packet.
  
  2. **Criterion 6 is only half tested.** It says an application without a contributor has "no search button, row, dialog or shortcut". `the-default-finds-nothing-and-an-application-without-contributors-has-none` (`tests/search-tests.lisp`, about line 2255 of `diff.patch`) only checks `search-contributors-p` and the 404. No test renders a staff page of `search-plain-app` and checks that `data-tun-search-open`, `tun-app-shell-search-row` and `id="tun-search"` are absent, so a shell that always drew the search would still pass. **To fix:** add that request, or a render of `app-shell` with `:search nil`.
  
  3. **Small, but visible in the specimen:** the «⌘» in `search-dialog`'s `:doc` (`src/web/ui/search.lisp`, about line 1833 of `diff.patch`) shows as a missing-glyph box in the specimen's body font, at both widths. **To fix:** write "Cmd K on a Mac" in the doc text, as `dialog`'s doc already does, or render it as a `kbd`.
  
  **Not blocking:** the orders module also searches `order-delivery-address` (`modules/orders/publish.lisp`, about line 597 of `diff.patch`). Its README says so, but criterion 6 and §6.4 list only the customer's name and the id. Either add the address to §6.4's example or drop it.
- 2026-11-12 08:44  verify 7: passed build, test, check
- 2026-11-12 08:44  shown (/cards, /search?q=bjorn, /customers)
- 2026-11-12 08:44  gate B asked of a reviewer
- 2026-11-12 08:45  gate B: approve (reviewer)
  I approve this at gate B. The three changes asked for at the last review are fixed, verify round 7 passed, and nothing new blocks it.
  
  **The three earlier changes**
  
  1. **Pictures of the search (criterion 12):** fixed. `pictures()` in `checks/showcase/checks/ui-search.py` (diff.patch:428–454) saves 12 pictures: the shell closed, open with results, and open with «No results», at 390 and 1280 px, light and dark. All are in `checks/`. I looked at four of them:
     - With results, at 1280 px dark and 390 px light: «Export to accounting» shows «Ex» marked, the marked row («Café Øst») has its ground and frame, and each meta line starts with «Card ·» or «Customer ·».
     - With no results, at 1280 px light and 390 px dark: the fixed 640×576 box on a wide screen, the full-height sheet on a phone, and «No results for «zebra»».
  2. **No search where nothing can be found (criterion 6):** fixed. The test `the-default-finds-nothing-…` (diff.patch:2298–2320) now draws `app-shell` once with a search and once without. It checks that each marker is absent without one and present with one: the button's `data-tun-search-open`, the sidebar row, `id="tun-search"`, the dialog's shortcut and `aria-keyshortcuts`. It also checks that `shell-search-path` is nil for the plain application, alongside the 404. A shell that always drew the search would now fail it.
  3. **The «⌘» box in the doc text:** fixed. `search-dialog`'s doc now says «Cmd K on a Mac» (diff.patch:1876).
     - The orders module's search by delivery address, raised last time as a minor point, is now in §6.4 (diff.patch:738), matching the code and the module's README.
  
  **Still right**
  
  - **Verification:** round 7 passed build, test and check, and every step of `checks/ui-search.json` passed. The timings are about 170–180 ms from the last key to results, and about 5 ms on the server.
  - **Criteria 1–5, 7, 8, 9 and 9a:** each has a test in `tests/search-tests.lisp` that would fail without the change, as the last review found.
  - **Criteria 10 and 11:** the CSS and the browser check are unchanged and still pass.
  - **The code:** no debugging output is left. The spec, `docs/client-api.md`, both modules' READMEs and the version bump all agree.
  
  **Not blocking**
  
  - `modules/orders/publish.lisp:615`: the comment says an order is found «by its customer's name and its id». The code also matches the delivery address (line 627), so the comment should say that too.
  - Criterion 11 asks for the box to stay the same «with the most the showcase finds (its two kinds, five of each)». The browser check measures it with «item», which finds five cards and no customers. The size can't actually grow, because the CSS test pins a fixed height and makes only the results scroll. Still, a query that fills both kinds would test that wording literally.
- 2026-11-12 08:46  finished at tun 2094a439
