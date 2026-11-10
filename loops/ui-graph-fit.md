# ui:graph reads on a phone for a 30-node plan

- loop: ui-graph-fit
- mode: reviewed
- stage: ship
- base: 2b4e5560416b5da5ecd7e36dce861bd0bcbc67db
- after: ui-graph
- item: sak_9kev1pd3ey6e1paw
- tags: kind:ui module:ui core
- estimate: 1h15m 2h15m 4h30m
- like: ui-graph price-chart
- verified: 1f87f05262501279d4607de3d4ff000ac35e23ca
- shown: 1f87f05262501279d4607de3d4ff000ac35e23ca

## Brief

From `ui:graph`'s first real use, brought by the factory's orchestrator
on 2026-11-10 (Ferdig sak_9kev1pd3ey6e1paw, under «Software factory»).
tunworks `apps/factory` draws a project's plan with it, and on Tun ERP's
real plan (30 components, 57 dependencies, ten layers) it falls short on
a phone and a normal desktop. The builder who used it (tunworks
`apps/factory/loops/factory-graph.md`, «Where `ui:graph` falls short on
the real plan»):

> 1. Too wide for any screen but a very wide one. Thirty components in
>    ten layers draw 2508 × 1140 px (12rem nodes, 4rem gaps). A phone's
>    box (about 358 px) shows 1.4 of the ten layers, a 1280 px desktop
>    beside the menu about 3.7. There is no other orientation […] and no
>    way to fit the drawing to its box.
> 2. A phone's first screen is blank. […] at 390 px the first ~600 px of
>    the box are empty […].
> 3. Titles are cut to about 18 characters. […] 29 of the 30 titles are
>    longer and end in «…». […] Two lines of title would fit most of them.
> 4. The second line is cut too. The state's word, a dot and the meta
>    share one line […]; the meta has no `title` of its own.
> 5. One badge fits a line, and nothing says more are hidden. […] A «+1»
>    in the line would tell.
> 6. Still open from Tun's own review of `ui-graph`: badges out of sight
>    keep their links in the tab order, and large graphs leave empty rows.

The orchestrator adds the review's other open notes (two nodes depending
on each other read as one double-headed arrow; §6.3 step 3 does not say
that reversed edges keep their own empty places), and what Jonas needs:
he reads the factory on his phone, and this graph is its headline view
(«a visual graph representation of the projects, where it is possible to
see where the agents are working and the ferdig issues connected to
them»). On a 390 px phone a 30-node plan must be readable and navigable
without hunting through empty space. The design is the builder's; the
client's API (`:id :title :meta :state :href :badges`, `:from :to`)
stays compatible; no script; useful without JavaScript; the table stays.
The factory's 30-component shape becomes a specimen example and a browser
check at 390 and 1280 px. Mode: reviewed, after `ui-graph`.

Jonas, at gate A, 2026-11-10 (Ferdig kom_2cszh0g0ryvwqf5m), answered «B»
to the orchestrator's question, whose option B read: «send it back once
more: the rail list on narrow boxes (phones) only; on a desktop keep the
drawing, compacted and scrolling sideways. The graph is the headline view
and should stay a graph where there is room to pan it.»

## Criteria

1. The calls a client makes are unchanged: every `ui:graph` call valid
   before is valid now, with the same options, and draws the same nodes,
   states and edges; every badge is in the table, and a node shows those
   that fit (criterion 6). (`tests/graph-tests.lisp`)
2. `graph` renders two forms of the same graph, and CSS shows one by the
   figure's own width: **the list** when the figure is narrower than
   40rem, as on a phone or in a narrow column, and **the drawing**
   (layers left to right, as before) from 40rem, as in a desktop's
   content, where it scrolls sideways in its own box when it is wider.
   The form not shown is `display: none`. (tests; `graph.py` and
   `graph-plan.py` at 390 px: the list, at 1280 px: the drawing)
3. **The list**: the nodes with edges stand in one column, in the order
   of the layers, each layer from its top, every node as wide as the box
   less a gutter (at most 40rem, at least 12rem; below that the list
   scrolls sideways in its own box), one after another with 0.5rem
   between them, so the first node is at the top of the list and there
   is no empty place in it. At 390 px the 30-component plan lists all 30
   nodes with no sideways scrolling of the page or the list, and the
   48-step graph's nodes are at least 12rem wide. (tests;
   `graph-plan.py`, `graph.py`)
4. In the gutter left of the list, a rail belongs to the node at its
   top and runs down its own lane to the lowest node it joins. A node
   has a solid rail for its edges to nodes below it: a dot and a line
   from its left side start it, and at each target a dot on the rail and
   a line to the target's left side end in an arrowhead pointing into
   it. A node has a dashed rail for the edges a cycle reversed, from
   nodes below it into it: the line to its left side ends in an
   arrowhead pointing into it, and at each source below a dot on the
   rail and a line from the source's left side. Rails whose lines would
   meet take different lanes, the shortest nearest the nodes; a rail
   into a node's upper part and one out of its lower part may share a
   lane. (tests of the
   lanes and ends; `graph-plan.py` at 390 px measures each arrowhead's
   tip at its node's left side and each dot's line at its node)
5. A node's title has up to two lines, cut with an ellipsis after the
   second. At 390 px (the list) at least 28 of the plan's 30 titles (20
   to 45 characters) show whole; at 1280 px (the drawing, whose nodes
   are now 14rem wide) at least 24; at both, every node's state word and
   META show whole. The state's word and META share the
   line under the title; META has its own `title`. (`graph-plan.py`)
6. A node shows the badges that fit the narrowest node's line (a list
   node's at 12rem: 10.25rem of badges), the same in both forms, as the
   server reckons them from their text, and «+N» for the N left out, whose `title`
   names them (en «2 more: …», nb «2 til: …»); the badges left out are
   not in the node at all, so no hidden link takes focus. The table
   holds every badge. The badge line is one line and clipped as a guard:
   a badge that wraps past it is out of sight whole, and one alone too
   wide ends in an ellipsis with its whole text in its `title`. (tests;
   `graph-plan.py` at 390 px and 1280 px: «+2» on `accounting-port`
   («1 question» shown; «Planner», «#40» left out), «+1» on
   `order-lifecycle` («Reviewer», «#42» shown; «#43» left out), no «+N» on
   `orders` («Builder 2», «#41»); every badge wholly inside its node but
   `setup-wizard`'s, too long for the line alone, which ends in an
   ellipsis with its whole text in its `title`)
7. In the drawing, an edge a cycle reversed runs 0.5rem below the middle
   of its nodes' sides, so two nodes that depend on each other show two
   lines. (tests; `graph.py` at 1280 px)
8. The drawing is compacted: each place takes the row nearest the
   topmost row of its neighbours (not their mean), and a row empty in
   every layer is taken out. At 1280 px the 30-component plan's drawing
   box opens on nodes: `module-layout`, the first layer's only node
   (`customers-update` stands in the layer before its successor, step
   2), stands in the drawing's first two rows, and the part of the box in view when it is scrolled
   to (its width by 600 px from its top) holds at least six nodes.
   (tests; `graph-plan.py`)
9. `spec/ui.md` §6.3 says all this, step 3 says the reversed edges keep
   their own empty places, and §10 the evidence; `docs/client-api.md`
   mentions the list; the specimen shows the 30-component plan; the core
   version is the next free one on main when this is pushed, 2.20.0 now,
   in `src/core/module.lisp` and `flake.nix`.

## Decisions

- **Jonas chose the forms** at gate A (B): the rail list on narrow boxes
  only; on a desktop the drawing, compacted and scrolling sideways. The
  graph is the headline view and stays a graph where there is room to
  pan it.
- **The breakpoint is 40rem of the figure's own width**, by a container
  query, not the window's: a phone (a 390 px screen gives about 22rem)
  and a narrow column get the list, a desktop's content column (59rem
  at 1280 px beside the menu) the drawing. A drawing in 40rem shows two
  layers and a part of the third; narrower, it is more panning than
  reading.
- **The list, not the drawing turned, for narrow boxes.** Tun ERP's plan
  has a layer of 11 places (six nodes and the empty places of long
  edges), so a drawing top to bottom is still 11 nodes wide. One column
  of full-width nodes in the order of the layers fits any width, starts
  at its first node and has no empty place; the dependencies are rails
  in a gutter, as a version-control graph draws branches. On Tun ERP's
  plan that is 13 lanes, about 85 px.
- **Both forms in the page, CSS choosing.** The server cannot know the
  box's width, so it renders both; the form not shown is `display:
  none`, neither seen nor read nor focused; the page's HTML holds the
  nodes twice.
- **Compacting the drawing.** With each place nearest its neighbours'
  mean row, a node feeding a wide fan stood in the fan's middle, and the
  plan's first layers in the middle of an 11-row drawing: the desktop
  box opened on blank space. Nearest the topmost neighbour, the layers
  lean to the top and the box opens on the first nodes; chains stay
  level, since a single neighbour is its own topmost. Rows empty across
  every layer are taken out besides.
- **Badges chosen on the server.** CSS cannot count what wrapped out of
  sight, so the server reckons each badge's width from its text: 0.45rem
  a character (0.6em of `--text-xs`, a generous average for the sans
  font badges use, the width of a monospace character), with its padding
  and its dot, keeps the badges that fit the line of the narrowest node,
  a list's at 12rem, with room for «+N», and leaves the rest out of the
  node; the same in both forms, so a wider node may have room to spare.
  A text of many wide letters can still be wider than reckoned; the CSS
  keeps the line one line high and clips it, so a badge that wraps past
  it is out of sight whole, and one alone too wide ends in an
  ellipsis.
- **Two-line titles and wider nodes in the drawing:** 14rem by 6.5rem,
  with 3rem between layers, not 12rem by 5.5rem with 4rem; two lines of
  14rem hold most titles of up to 45 characters.
- **Lanes by the rails' lines, not their rows** (at build): two rails
  that only meet at one node, one ending in its upper part and the next
  leaving from its lower part, can share a lane, so a chain is one
  straight lane; first counted by rows, a chain took a lane a link.
- **A gutter with many lanes** narrows the list's nodes; at 12rem they
  stop narrowing and the list scrolls sideways in its own box.
- **Core version**: the next free minor when pushed; `client-modules`
  took 2.19.0 on main first, so 2.20.0 unless another lands.

## Log

- 2026-11-10 10:49  started, reviewed
- 2026-11-10 10:51  estimated 1h15m 2h15m 4h30m at brief, like ui-graph price-chart
- 2026-11-10 10:52  gate A asked of a reviewer
- 2026-11-10 10:53  gate A: changes (reviewer)
  Reading the diff against the brief, I've got enough for the verdict; writing it up now.
  
  **Gate A review: ui-graph-fit**
  
  **What's right**
  
  - The brief's main problems each have a criterion that a check can decide:
    - too wide for the screen, and a blank first screen on a phone (2, 3);
    - titles cut (5);
    - META without its own `title` (5);
    - no «+N», and hidden badges' links in the tab order (6);
    - a double-headed arrow where two nodes depend on each other (7);
    - step 3 of the spec not mentioning reversed edges (8).
  - The asker's own requirements are covered: the API stays compatible (1), no script, the table stays, the 30-component specimen, and checks at 390 and 1280 px.
  - The brief leaves the design to the builder. A list with rails for narrow boxes, a container query rather than the window choosing the form, and `display: none` on the form not shown are all sound choices. They keep the page script-free and keep hidden links out of the tab order.
  - The §6.3 changes in `spec/ui.md` match criteria 2–7, and §10 names the new evidence.
  
  **Changes**
  
  1. **`spec/ui.md`, the list's rails: it contradicts itself about reversed rails.**
     - It first says "Each node with edges out has a rail for them, and a second, dashed, for those step 1 reversed", which puts the dashed rail on the source node. Criterion 4 says the same.
     - It then says "A reversed rail runs from its target, the upper node, to the lowest of its sources, and its arrowhead is at the target", which groups the rail by target instead.
     - A test cannot decide both. Pick one and say it in both places, with where the dot and the arrowheads go. For example: "the source's dashed rail runs from its highest reversed target down to the source, a dot at the source and an arrowhead at each target."
  
  2. **Criterion 6 and §10 `graph-plan.py`, "no badge cut": this conflicts with the specimen.**
     - `+erp-plan-badges+` gives `setup-wizard` the badge "Builder 3, the one on the long name". At 0.45rem a character that is about 16rem, wider than the line, and the spec says such a badge "ends in an ellipsis".
     - Say what the check really asserts. For example: "no badge clipped except the one too long for the line, which ends in an ellipsis with its whole text in its `title`".
  
  3. **Brief item 6, "large graphs leave empty rows", is dropped by a decision.**
     - The brief lists it among the open problems. "Rows in the drawing are as before" decides not to fix it, and that is the asker's call to make, not the builder's.
     - Either add a criterion (for example, the 48-step graph at 2600 px has no empty row) or record it as explicitly out of scope with the asker's agreement.
  
  4. **Brief items 3 and 4 are only checked on the list.**
     - The titles were cut in the drawing's 12rem nodes, which still show on wide screens. Criterion 5 measures titles only at 390 and 1280 px, where the plan is a list. Add the 2600 px drawing to the "≥ 28 of 30 titles whole" check.
     - Item 4 says the second line is cut, but criterion 5 only requires META to have a `title`. Add that the plan's state word and META show whole at 390 and 1280 px.
  
  5. **Criterion 1 says calls "draw the same … badges".**
     - Under criterion 6 they no longer do: a node shows only the badges that fit, plus «+N».
     - Change it to: the same nodes, states and edges, and every badge in the table.
  
  6. **The badge-width decision misdescribes the font.**
     - It says "the widest character of `--text-xs` (0.45rem, a monospace one)". `.tun-badge` uses the normal sans font (`src/web/ui/actions.lisp:587`): `--text-xs` with no mono font.
     - 0.45rem (0.6em) is a generous average, not the widest character; a "W" is about 0.9em. Reword it so the record says what the server actually reckons, and that the CSS clip catches text with many wide letters.
  
  **Notes (not blocking)**
  
  - `checks/showcase/checks/zz-shots.py` says it is temporary. It must not be in the diff at gate B.
  - Nothing limits the gutter's width as lanes grow. The 30-node plan's 13 lanes take about 85 px, but a larger graph on a 390 px phone could squeeze its nodes badly. It would be worth §6.3 saying what happens then, or `graph.py` checking the 48-step graph's list at 390 px for a minimum node width.
  - On a 1280 px desktop the factory's headline view will be the list, not a drawing. That is within the latitude the brief gives, but the asker should see it at gate B.
- 2026-11-10 10:54  gate A asked of a reviewer
- 2026-11-10 10:55  gate A: changes (reviewer)
  The revised criteria now answer the first round's points, but the spec change in the diff hasn't been updated to match them, so the verdict is changes.
  
  **What's right**
  
  - The criteria now cover the whole brief:
    - item 1 (too wide) and item 2 (blank first screen): criteria 2 and 3
    - item 3 (titles cut), in the list and now also in the drawing: criterion 5
    - item 4 (second line cut): criterion 5 now says the state word and META show whole at 390 and 1280 px
    - item 5 («+N») and item 6 (hidden badges' links in the tab order): criterion 6
    - item 6 (empty rows): now criterion 8, no longer dropped by a decision
    - the two arrows between nodes that depend on each other: criterion 7
    - §6.3 step 3: criterion 9
    - the asker's limits (same API, no script, the table stays, the specimen, checks at 390 and 1280 px): criteria 1 and 9
  - Criterion 1 no longer promises the same badges. Criterion 4 now says one thing about the dashed rail: it belongs to its upper node, the target. Criterion 6 now allows the one badge too long for the line, and that matches the specimen's "Builder 3, the one on the long name".
  - Every criterion can be decided by a test or a browser check.
  - Choosing the form by a container query is still sound, and so is leaving the form not shown as `display: none`. Showing the list on a 1280 px desktop is within the latitude the brief gives the builder.
  - Step 3's new text about reversed edges and the `docs/client-api.md` line say what criterion 9 asks.
  
  **Changes**
  
  The criteria were revised after round 1, but `spec/ui.md` was not. Criterion 9 makes the spec part of what this gate approves, and in several places it now says the opposite of the criteria:
  
  1. **Width of `data-fits`** (`spec/ui.md:866-868`). The spec says "from 8rem to 160rem" and "a drawing wider than 160rem has no `data-fits`". Criterion 2 and the last decision say 200rem. At 160rem the 30-component plan's drawing (about 167rem plus padding) could never show, and criterion 5's check of the drawing at 3200 px couldn't pass. The first decision still says "157rem" and "up to 160rem are 20 rules"; that should go too.
  2. **Size of the drawing's nodes** (`spec/ui.md:794`, `:875`). The spec still says nodes are 12rem wide and layers have 4rem between them. The decision and criterion 5 say 14rem by 6.5rem with 3rem between layers.
  3. **The dashed rail** (§6.3 «The list»). The spec still opens with "Each node with edges out has a rail for them, and a second, dashed, for those step 1 reversed". That gives the dashed rail to the source, against criterion 4 and against the spec's own next sentence. Say it as criterion 4 does: a dashed rail belongs to its upper node, the target, and a dot and a line join each source below.
  4. **The list's minimum width.** Criterion 3 says nodes are at least 12rem wide, and below that the list scrolls sideways in its own box. The spec only says "at most 40rem".
  5. **Empty rows** (§6.3 step 5, `spec/ui.md:851-856`). Criterion 8 removes a row that is empty in every layer, but step 5 is unchanged. Add that after the rows are moved up, a row empty in every layer is taken out.
  6. **The evidence in §10** (`spec/ui.md:1161-1175`):
     - The checks use 2600px, but criteria 2, 7 and 8 use 3200 px.
     - `graph-plan.py` still says "no badge cut". Make it criterion 6's wording: every badge wholly inside its node except the one too long for the line, which ends in an ellipsis with its whole text in its `title`.
     - It doesn't list the checks criterion 5 adds: at least 24 titles whole at 3200 px, and every state word and META whole at 390 and 1280 px.
     - It doesn't list criterion 3's check that the 48-step graph's nodes are at least 12rem wide at 390 px.
     - `graph.py`'s claim "at 390px and 1280px the same graphs are lists" may not hold under criterion 2: a small graph such as the pilot, if it fits 1280 px, shows as a drawing. Say what each graph is expected to show at 1280 px.
  
  **Note (not blocking)**
  
  - The core version, 2.20.0 in `src/core/module.lisp` and `flake.nix`, isn't in the diff yet. That's fine at gate A, but criterion 9 needs it by gate B.
- 2026-11-10 10:56  gate A asked of a reviewer
- 2026-11-10 10:57  gate A: changes (reviewer)
  Round 3 fixes everything the second review asked for, but three small gaps remain. One check can't be decided as written, and the spec disagrees with the criteria in two places.
  
  **What's right**
  
  - **Drawing width:** `spec/ui.md` now uses 200rem everywhere, and the first decision says 25 rules. At 3200 px a `:wide` page has no max width (`src/web/ui/layout.lisp:764`). So the plan's ten layers (about 167rem) and the 48-step graph's six (about 99rem) can both show as drawings there, as criteria 5, 7 and 8 need.
  - **Node size:** the spec now says 14rem by 6.5rem with 3rem between layers, as the decision does.
  - **Dashed rail:** the spec now gives it to the upper node, the target, with a dot and a line at each source below. That matches criterion 4 and no longer contradicts itself.
  - **List width:** the spec now has the 12rem minimum and the list's own sideways scroll.
  - **Empty rows:** step 5 now takes out a row no layer has a place in (criterion 8). Step 3 now says reversed edges share empty places only with each other.
  - **Evidence in §10:** every check now runs at 3200 px. The badge wording now matches criterion 6, and the title, state-word, META and 12rem checks are added. `graph.py` now says every graph on `/graph` is a list at 390 and 1280 px. That holds: the pilot has more than three layers, so it is wider than 59rem as a drawing.
  - **Brief coverage:** every item is now met, along with the asker's limits: the same API, no script, the table kept, the specimen, and checks at 390 and 1280 px. `docs/client-api.md` mentions the list.
  
  **Changes**
  
  1. **Criterion 6 and `spec/ui.md` §10, `graph-plan.py`: "«+2» on the node with three" is not unique.**
     - `+erp-plan-badges+` (`checks/showcase/graph.lisp`) gives three badges to two nodes: `order-lifecycle` ("Reviewer", "#42", "#43") and `accounting-port` ("1 question", "Planner", "#40").
     - I estimated widths with 0.45rem a character plus the badge's padding and gap (`src/web/ui/actions.lisp:575`). On that estimate, `order-lifecycle`'s three badges all fit a 14rem node and it would show no «+N». `accounting-port`'s would not fit.
     - Name the node (for example, «+2» on `accounting-port`). Also say what `order-lifecycle` shows: all three, or a «+N». That turns the case where all badges fit into a check too.
  
  2. **`spec/ui.md` §6.3, the node: "14rem wide in the drawing and wider in the list" contradicts the list's minimum.**
     - Criterion 3 and «The list» let a list node be as narrow as 12rem. At 390 px, after the page's and card's padding and a gutter of about 85 px, the plan's nodes come out at about 14rem, and the 48-step graph's are likely narrower.
     - Say "in the list as wide as «The list» says" instead of "wider".
  
  3. **`spec/ui.md` §6.3: "Under the drawing, a `<details>` … holds a `table`".**
     - The figure now holds two forms, and the drawing is `display: none` in every narrow box. Read as written, the table could sit inside the hidden drawing and be gone on a phone, against the brief's "the table stays".
     - Say the table is under whichever form shows, outside both. Say the same of «No data», which "stands in place of the drawing".
  
  **Notes (not blocking)**
  
  - `src/core/module.lisp` and `flake.nix` must reach 2.20.0 by gate B (criterion 9).
  - At gate B, the asker should see that the factory's headline view is a list on a 1280 px desktop.
- 2026-11-10 10:58  gate A asked of the person
- 2026-11-10 11:48  gate A: changes (jonas): «B»: the rail list on narrow boxes (phones) only; on a desktop keep the drawing, compacted and scrolling sideways (Ferdig kom_2cszh0g0ryvwqf5m)
- 2026-11-10 11:51  gate A asked of a reviewer
- 2026-11-10 11:52  gate A: changes (reviewer)
  Most of the spec now does what Jonas asked at gate A ("B"). Three small gaps remain, one of which brings back a problem from the brief, so the verdict is changes.
  
  **What's right**
  
  - **The forms follow Jonas's answer.** Narrow boxes get the list with rails, and from 40rem a box gets the drawing. The drawing is compacted and scrolls sideways in its own box. The choice is made by a container query, the form not shown is `display: none`, and there is no script. "Two forms" in §6.3 says the same as criterion 2, and the first decision records the choice as his.
  - **The old `data-fits` mechanism is gone.** Neither the spec nor the decisions mention it now, so the contradictions from the last rounds about 160rem and 200rem have nothing left to apply to.
  - **Spec and criteria agree on:**
    - the drawing's size: 14rem by 6.5rem nodes, 3rem between layers;
    - the list: 12rem to 40rem wide, scrolling in its own box;
    - the rails: the solid rail belongs to the source, the dashed rail to the upper target, and lanes go to the shortest rail first;
    - step 3: reversed edges share empty places only with each other;
    - step 5: rows lean to the topmost neighbour, and empty rows are taken out;
    - the table under both forms, outside them, and «No data» standing in for both.
  - **Every brief item has a criterion**, and so do the asker's limits: the same API, no script, the table kept, the 30-component specimen, and checks at 390 and 1280 px. The pilot's `review` ⇄ `fix` pair gives criterion 7 something to measure at 1280 px.
  - **§10 now matches the criteria**: «+2» on `accounting-port`, no «+N» on `order-lifecycle`, the long badge's ellipsis, 28 and 24 titles, 12rem nodes in the 48-step list, and six nodes in the first 600 px.
  
  **Changes**
  
  1. **The list's badges are counted for a wider line than the list may have** (`spec/ui.md` §6.3, «The badges a node shows», and the badge decision).
     - The server picks badges by "the drawing's node line", which is 14rem, "the same in both forms". But a list node may be as narrow as 12rem (criterion 3, «The list»).
     - So on a phone, a node with several badges, such as the pilot's `photos` or a graph with many lanes, can keep badges that do not fit. The CSS guard then cuts the last one mid-text with no «+N». That is brief item 5 again («nothing says more are hidden»), on the phone, which is the view the brief is about.
     - The decision says a clipped badge "then ends in an ellipsis"; the spec says only that "the line is clipped". Pick one.
     - Suggested fix: count the list's badges for the list's narrowest node (12rem). Or say plainly what a list node narrower than 14rem shows. Either way, make the spec and the decision say the same about the guard.
  
  2. **Brief item 4 is no longer checked on the desktop** (criterion 5).
     - The second line was cut in the drawing's nodes. Since Jonas's answer, the drawing is what a 1280 px desktop shows, but criterion 5 checks "every node's state word and META whole" only at 390 px.
     - Add it at 1280 px, in both criterion 5 and §10's `graph-plan.py`.
  
  3. **"The first layer's node" can't be decided as written** (criterion 8, §10 `graph-plan.py`).
     - The plan's first layer has two nodes, `module-layout` and `customers-update`, since neither depends on anything.
     - Say which one, or "both of the first layer's nodes stand in its first two rows".
  
  **Note (not blocking)**
  
  - `checks/showcase/checks/zz-shots.py` says it is temporary. It must be out of the diff by gate B, and `src/core/module.lisp` and `flake.nix` must be at 2.20.0 by then (criterion 9).
- 2026-11-10 11:53  gate A asked of a reviewer
- 2026-11-10 11:54  gate A: approve (reviewer)
  I'm approving gate A: the three changes asked for last round are done, and the spec now says what the criteria say.
  
  **Last round's changes**
  
  1. **Badges are now counted for the narrowest node.** `spec/ui.md` §6.3 («The badges a node shows») and criterion 6 now use the list's 12rem node, which leaves 10.25rem for badges, in both forms. So a phone no longer keeps a badge that does not fit, with no «+N». The spec («The guard») and the badge decision now agree on the guard: the line is one line high and clipped, and a badge alone too wide ends in an ellipsis.
  2. **State word and META are checked on the desktop too.** Criterion 5 says "at both" widths, and §10's `graph-plan.py` checks them at 1280 px.
  3. **Criterion 8's first node can now be decided.** It names `module-layout` as the first layer's only node. That matches step 2: `customers-update` has nothing it depends on, so it moves to the layer just before `customers`.
  
  **What's right**
  
  - **Jonas's answer («B») is followed.** Narrow boxes get the list with rails, and from 40rem the box gets the drawing, compacted and scrolling sideways. A container query chooses, the form not shown is `display: none`, and there is no script. The first decision records the choice as his.
  - **Every item in the brief has a criterion:**
    - width and the blank first screen: criteria 2, 3 and 8;
    - titles: criterion 5;
    - the second line, and META's own `title`: criterion 5;
    - «+N» and hidden badges' links in the tab order: criterion 6;
    - empty rows: criterion 8;
    - the double-headed arrow: criterion 7;
    - step 3 and reversed edges: criterion 9.
  - **The asker's limits are kept:** the same API, no script, the table kept and outside both forms, the 30-component specimen, and checks at 390 and 1280 px.
  - **The spec matches the criteria** on:
    - node size: 14rem by 6.5rem, with 3rem between layers;
    - the list: 12rem to 40rem wide, scrolling in its own box;
    - rail ownership and lanes;
    - step 3's reversed places;
    - step 5 leaning to the topmost neighbour and taking out empty rows;
    - §10's evidence.
  - **The checks can run as written.** On `/graph` every card spans the wide page, so at 1280 px each figure is over 40rem and is a drawing (criterion 2). The pilot's `review` ⇄ `fix` pair gives criterion 7 something to measure.
  - **The named badge cases are concrete.** `accounting-port` shows «+2», `order-lifecycle` «+1», `orders` no «+N», and `setup-wizard`'s 35-character badge ends in an ellipsis.
  
  **Notes (not blocking)**
  
  - **`order-lifecycle`'s «+1» is close to the line.** §6.3 says neither how wide «+N» counts nor whether the 0.25rem gaps between badges count. I estimated from the badge CSS (`src/web/ui/actions.lisp`), with the dot from `src/web/ui/graph.lisp`. Counting the gaps, «Reviewer» + «#42» + room for «+1» comes to about 10.35rem, just over 10.25rem. That would make it «+2», against criterion 6. It would help if the spec said how «+N» and the gaps are counted; the check will catch it at gate B either way.
  - **Before gate B:**
    - `checks/showcase/checks/zz-shots.py`, which says it is temporary, must be out of the diff.
    - `src/core/module.lisp` and `flake.nix` must be at 2.20.0 (criterion 9).
- 2026-11-10 12:11  verify 1: failed test
- 2026-11-10 12:11  verify 1 failed on markdown's timing test (costly-texts-take-time-in-proportion: fences 0.120 s against 0.012 s), which this loop does not touch; the machine runs other loops' suites; verified again
- 2026-11-10 12:19  verify 2: failed test
- 2026-11-10 12:20  verify 2 failed on the same markdown timing test (table rows 0.179 s against 0.016 s) under a load of 8; alone it passes twice; verify 3 runs at TUN_TEST_JOBS=4
- 2026-11-10 12:30  verify 3: passed build, test, check
- 2026-11-10 12:30  shown (/graph, /ui/graph)
- 2026-11-10 12:31  gate B asked of a reviewer
- 2026-11-10 12:32  gate B: approve (reviewer)
  I'm approving gate B. Each criterion is met, the checks and tests back it, and every verify step passed.
  
  **Verification**
  - Round 3 of `verify.txt` passed build, test and check.
  - Rounds 1 and 2 failed only on markdown's timing test under load. This loop doesn't touch markdown, and the log records it passing on its own. That is a fair reading.
  - `checks/graph.json` and `checks/graph-plan.json` pass every line, light and dark, at 390 and 1280 px, and also without the script.
  
  **Criteria against the evidence**
  1. **The client's calls are unchanged.** `ui:graph` takes the same options. The table still uses `graph-badges` on every badge. The one changed assertion in the old tests, the meta span gaining its `title`, is intended.
  2. **Two forms, chosen by the figure's width.** The figure is a container; `.tun-graph-scroll` is `display: none` by default, and `@container (min-width: 40rem)` switches to the drawing (`graph.lisp`, the CSS). The checks see a list at 390 px and a drawing at 1280 px for all three graphs, including without the script.
  3. **The list.** The CSS has `minmax(12rem, 40rem)`. The checks find all 30 nodes, 8 px between nodes, and no sideways scroll of the page or the list. The 48-step list's nodes are 202 px wide.
  4. **The rails.** Tests cover a chain sharing one lane, the shorter rail taking the nearer lane, and the dashed rail pointing into its upper node. `misplaced_rails` measures every arrowhead and dot in the browser, and finds none misplaced.
  5. **Titles and the second line.** 30 of 30 titles show whole at both widths, against the 28 and 24 asked. The state word and META show whole on every node. META now carries its own `title`.
  6. **Badges.** `shown-badge-count` is tested on exactly the four named cases. The browser check confirms them at both widths:
     - «+2» on `accounting-port`, titled «2 more: Planner, #40»;
     - «+1» on `order-lifecycle`, which was the borderline case at gate A;
     - no «+N» on `orders`;
     - the ellipsis on `setup-wizard`'s long badge.
     
     A test asserts that a left-out badge's link is absent from the node and present in the table. The nb text «2 til» comes from an entry already in `src/i18n/nb-ui.lisp` (the one `actions.lisp` also uses).
  7. **Reversed edges in the drawing.** `edge-y` puts a reversed edge 8 px below the middle. A test pins the path at y 60 against 52, and `misplaced_edges` checks the offset in the browser.
  8. **The compacted drawing.**
     - Rows now take the topmost neighbour (`reduce #'min`) and `dense-rows` takes out empty rows. Two new tests cover a fan's source and empty rows.
     - The browser check finds no empty row in the 48-step drawing.
     - `module-layout` stands in row 1, and 11 nodes are in the first 600 px.
  9. **Spec, docs, specimen and version.**
     - `spec/ui.md` §6.3 and §10 match the criteria, and step 3 now covers reversed edges.
     - `docs/client-api.md` mentions the list.
     - The specimen has the 30-component plan.
     - The version is 2.20.0 in both `src/core/module.lisp` and `flake.nix`.
     - The temporary `zz-shots.py` is gone from the diff.
  
  **Brief and screenshots**
  - **Phone:** the plan reads as one column from its first node, with no blank opening screen. Titles take two lines, and «+2» shows where badges are left out.
  - **Desktop:** the plan is a compacted drawing that scrolls sideways in its own box, as Jonas chose at gate A. It opens on the first layers.
  
  **Code**
  - It follows the repository's rules (`AGENTS.md`).
  - The new functions have docstrings that point to the spec.
  - The two check scripts now share their measuring code in `_graph.py`.
  - There is no leftover debugging and no dead code.
  - Hiding the form not shown with `display: none` keeps its duplicate links out of focus.
  - I checked for duplicate `id`s from rendering the nodes twice and found none: `graph-node-markup` emits no `id`.
  
  **Notes (not blocking)**
  - On the 1280 px desktop, the plan's card is as tall as its tallest layer, 11 rows. Below the first layers' nodes, about 700 px of the box is empty until you scroll sideways to the later layers. Criterion 8 is met, but Jonas should see this, since this graph is the factory's headline view.
  - On the phone, the 48-step list's gutter has many lanes. It reads as a dense grey band, though the nodes keep their 12rem minimum.
  - `rail-lanes` looks spans up with `(nth j spans)` inside a nested loop. Walking `spans` alongside `j` would read better and avoid the quadratic lookups. The test that renders the largest allowed graph within a second still passes.
