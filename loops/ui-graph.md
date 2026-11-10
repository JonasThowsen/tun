# ui:graph: a visual graph of nodes and edges, where agents work and the issues tied to them

- loop: ui-graph
- mode: reviewed
- stage: done
- base: fa659be3d11a357d9cb2bdffa943fde4adca81d2
- item: sak_8xph0h22zbjd2mmp
- tags: kind:ui module:ui core
- estimate: 50m 1h15m 2h30m
- like: price-chart markdown
- verified: b5b036f7854fdbbb244c5ba56da80ea19f526e6e
- shown: b5b036f7854fdbbb244c5ba56da80ea19f526e6e

## Brief

Ferdig item sak_8xph0h22zbjd2mmp, «Factory 4: a visual graph of Tun's
modules and their dependencies» (Jonas, 2026-11-01), part of «Software
factory»: see the modules a business needs and what each pulls in, as a
graph one can click through; «add a `ui:graph` (or similar) in Tun when
the list is not enough».

Jonas, 2026-11-10, about the factory's dashboard, brought by the
factory's orchestrator:

> a visual graph representation of the projects, where it is possible to
> see where the agents are working and the ferdig issues connected to
> them.

The orchestrator's needs for the component (tunworks `apps/factory`, a
Tun client built in parallel, will use it): nodes with a title, an
optional second line, a state in the tokens' tones (planned, active,
waiting on a person, done, failed or blocked), an optional link, and a
few small badges, one kind reading as «someone is working here now» and
one as a count or an issue reference; directed edges (a dependency, from
→ to) drawn so the direction is clear; a layered layout computed on the
server, with no client library and nothing fetched, that places nodes
without edges, survives cycles and keeps 30–60 nodes readable; at 390 px
and on a desktop, light and dark, and without JavaScript; the same
information as a table for screen readers; documented in the specimen,
`spec/ui.md` and `docs/client-api.md`, with tests of the layout and a
browser check at both widths. A kernel change: the core version is
raised. Mode: reviewed.

## Criteria

1. `(ui:graph (:label L :nodes NODES :edges EDGES))` renders a figure
   captioned L. Each node, `(:id ID :title TITLE [:meta TEXT] [:state S]
   [:href H] [:badges BADGES])`, is a box of one fixed size: TITLE on one
   line, cut with an ellipsis and whole in the box's `title` attribute;
   the state's word, then META, on a second line; the badges on a third.
   With H the whole box is a link, and a badge's own link stays above
   it. (`tests/graph-tests.lisp`; `graph.py`)
2. S is `:planned` (the default), `:active`, `:waiting`, `:done`,
   `:failed` or `:blocked`. Each has a catalogued word on the node (en
   «Waiting», nb «Venter», and so on) and a tone, shown as a 3px stripe
   at the box's start and a dot by the word: planned
   `--muted-foreground`, active `--info`, waiting `--warning` on
   `--warning-soft`, done `--success`, failed and blocked
   `--destructive` on `--destructive-soft`. (tests; `graph.py` reads the
   stripe's colour in light and dark)
3. A badge is `(:text T [:kind K] [:tone TONE] [:href H])`. TONE is
   `:neutral` (the default), `:info`, `:success`, `:warning` or
   `:destructive`, drawn as the `badge` variants. K `:agent` is someone
   working there now: a dot that pulses (still when motion is reduced),
   the tone `:info` unless given, a screen reader hearing «T, working
   now» (nb «arbeider nå»), and its node ringed in `--info`. K `:ref` is
   a count or an issue reference, in tabular figures. With H the badge
   is a link. Without K a badge is a plain label. Badges that do not
   fit the node's line are left out of the box whole; a first badge
   wider than the line alone ends in an ellipsis, its whole text in its
   `title`; all are in the table. (tests; `graph.py` finds each badge
   wholly inside its node or wholly out of sight, on a node with a long
   badge and one with many)
4. The layout, computed on the server (tests of the layout function):
   - every edge goes from a lower layer to a higher one, but for the
     edges a cycle needs reversed, which are marked;
   - a chain lies on one row;
   - a node with no edges is not in the layers but in a row under the
     drawing that wraps to its width;
   - a node with no edge into it stands in the layer just before its
     earliest successor;
   - an edge across several layers passes through empty places in the
     layers between, so no edge runs under a node, and no two nodes or
     such places share a place;
   - two pairs of edges given crossed come out uncrossed;
   - the same input gives the same layout.
5. Each distinct edge (repeats and an edge from a node to itself left
   out) is drawn behind the nodes, in `--muted-foreground` at 1.5px,
   ending in an arrowhead that points into its target. An edge forward
   runs from its source's right side to its target's left side, the
   arrowhead pointing right. An edge a cycle reverses, whose target is in
   an earlier layer, is dashed and runs from its source's left side to
   its target's right side, the arrowhead pointing left. (tests;
   `graph.py` measures each edge's ends against its nodes' sides at 390
   px and 1280 px, the reversed edges included)
6. More than 150 nodes, 300 edges or 8 badges on a node, a repeated or
   missing id, an edge naming a node that is not there, or a state, kind
   or tone not listed is an error in the caller's code. The largest
   graph allowed, edges all across, renders within a second. (tests)
7. At 390 px the page does not scroll sideways and the drawing scrolls
   sideways in its own box; at 1280 px a drawing wider than its box
   scrolls in it the same way; nodes do not overlap. (`graph.py`)
8. A `<details>`, closed by default, «Show as a table», holds a table
   with a row per node: its title (linked to H), its state's word, the
   titles of the nodes it depends on (its edges' sources), and its
   badges. The rows follow the layers, from the first, each layer from
   its top; then the nodes with no edges, in the order NODES gives them. The drawing's SVG and its empty places are `aria-hidden`.
   The component has no script, so without JavaScript it is drawn the
   same and the `<details>` opens. With no nodes: «No data» and no
   table. (tests; `graph.py` without JavaScript)
9. The specimen (`/ui/graph`) shows a project's work with an agent and
   issues, Tun's modules and their dependencies, and a cycle with nodes
   that have no edges. The showcase's `/graph` shows a project of a
   dozen nodes and a graph of 48, taken by `graph.py` at 390 px and
   1280 px, light and dark.
10. `spec/ui.md` (§6, §6.3, §10) and `docs/client-api.md` describe it;
    the core version is 2.18.0 in `src/core/module.lisp` and
    `flake.nix`.

## Decisions

- **A graph of nodes and edges, not of projects.** The component knows
  nodes, states, badges and edges; the dashboard maps its projects,
  steps, agents and Ferdig items onto them, and Factory 4's module
  graph is the same component with modules for nodes.
- **An edge's direction.** `(:from A :to B)` means B depends on A, or
  comes after it: A stands to the left, the arrow points into B, and
  the table says B «depends on» A. That reads for work (a step after
  the one before) and for modules (an edge from a module to the one
  that requires it).
- **The layout** is a layered drawing in the way of Sugiyama: cycles
  broken by a depth-first search in the nodes' order, reversing each
  edge back to a node still being searched; layers by the longest path
  from a source, a source then moved up to just before its earliest
  successor; an empty place per layer crossed by a long edge, shared by
  the long edges from one node; the order within each layer by the
  barycentre of the neighbours, four sweeps down and up, keeping the
  order with the fewest crossings; then the rows, increasing down each
  layer and nearest, in the least squares, the mean of the neighbours'
  rows (pool-adjacent-violators), swept down and up. Simple,
  deterministic and within a second for the bounds; no library and
  nothing fetched.
- **Changed at build, after gate A.** The spec first placed each node at
  its sources' mean row or pushed it below the one above; on Tun's
  module graph in the specimen that only ever pushed down and left the
  drawing tall and empty above. The least-squares rows centre a layer on
  its neighbours, and sharing a node's long edges' empty places took the
  module graph from a page and a half to about one screen. `spec/ui.md`
  §6.3 steps 3 and 5 say so, and the criteria are unchanged.
- **Left to right at every width.** On a phone the drawing scrolls
  sideways in its own box, which the brief allows. Turning it top to
  bottom would put the widest layer across the screen, and that layer,
  often a handful of independent steps, is usually wider than the graph
  is deep.
- **Nodes without edges in a row of their own,** wrapping under the
  drawing: in the first layer they would make it as tall as their
  number, and on a phone they now fit the screen.
- **Placed without `style`** (spec/ui.md §4). Every node is the same
  size and the gaps fixed; a layer is a column of places, a node or an
  empty one; the SVG of the edges lies over the columns with a viewBox
  in the same CSS pixels, so the lines meet the boxes. The sizes are
  one set of Lisp constants that write both the CSS and the drawing.
- **Arrowheads are polygons.** SVG markers are not in the renderer's
  allowlist, and polygons need nothing added to it.
- **No script.** Links navigate and the box scrolls on its own; nothing
  needs JavaScript.
- **Fixed node size.** A title is one line with an ellipsis, its whole
  text in `title` and the table. Badges that do not fit the line are
  hidden whole; a single badge too long for it, such as a long agent's
  name, ends in an ellipsis with its text in `title` (from gate B).
- **Two nodes that depend on each other** draw a solid and a dashed edge
  on one line, which reads as an arrow with a head at each end. Offsetting
  them would need a second route through every layer; the double head says
  what is meant.
- **No labels or states on edges, and no self-edges.** The brief needs
  neither; a node's own dependency on itself says nothing in a drawing.
- **Core 2.18.0**: a new public component in `TUN.UI`.
- **Shown in the showcase** (`/graph`): the factory's app is being built
  at the same time and takes this once it is pushed.

## Actuals

```json
{"loop":"ui-graph","title":"ui:graph: a visual graph of nodes and edges, where agents work and the issues tied to them","repository":"tun","mode":"reviewed","stage":"done","item":"sak_8xph0h22zbjd2mmp","tags":["kind:ui","module:ui","core"],"like":["price-chart","markdown"],"started":"2026-11-10 08:49","ended":"2026-11-10 09:46","minutes":{"total":57,"waiting_person":0,"waiting_reviewer":6,"working":51,"drafted":null,"person_at_gates":null,"agent":null},"estimate":{"best":120,"likely":210,"worst":420,"at":"brief"},"latest_estimate":{"best":50,"likely":75,"worst":150,"at":"build"},"within_estimate":false,"ratio":0.27,"verify":{"rounds":3,"failed":0},"changes":{"A":1,"B":1,"C":0},"interventions":0,"cost":{"tokens_in":null,"tokens_out":null,"usd":null,"agent_minutes":null}}
```

## Log

- 2026-11-10 08:49  started, reviewed
- 2026-11-10 08:52  estimated 2h 3h30m 7h at brief, like price-chart markdown combobox-over
- 2026-11-10 08:53  gate A asked of a reviewer
- 2026-11-10 08:54  gate A: changes (reviewer)
  My verdict is **changes**: the spec covers the brief well, but one criterion describes drawing a cycle's reversed edge differently from the spec, and it needs fixing before gate B.
  
  **What is right**
  
  - **The brief is covered, and nothing beyond it.** The criteria include everything the brief asks for:
    - nodes with a title, a second line, the six states, a link and badges;
    - an `:agent` badge for "working here now" and a `:ref` badge for counts and issue references;
    - directed edges with arrowheads;
    - a layered layout on the server with no library, that handles nodes without edges and cycles;
    - 390 px and desktop, light and dark, no JavaScript, and a table for screen readers;
    - the specimen, `spec/ui.md`, `docs/client-api.md`, layout tests, a browser check at both widths, and the core version bump.
  
    Nothing in the criteria goes beyond the brief.
  - **Each criterion can be checked**, and each names its test or check.
  - **The spec's references hold:**
    - The tokens it names exist in `src/web/ui/kit.lisp` (`--info`, `--warning-soft`, `--destructive-soft`).
    - The tones match `badge`'s variants.
    - `/ui/NAME` is how the specimen already shows one component (§7).
    - `checks/showcase/checks/` is where the other checks live.
    - The core version is 2.17.0 today, so 2.18.0 is the right next step.
  - **Spec and criteria agree** on the node box, the states and their words, the badges, the bounds, the five layout steps, the table and "No data".
  - **The decisions are reasonable for a builder to make:**
    - The component knows nodes rather than projects.
    - Left to right at every width, scrolling in its own box on a phone, which the brief allows.
    - No `style` attributes, polygon arrowheads, no script.
    - The edge direction (`:from A :to B` means B depends on A) answers the brief's "a dependency, from → to". It is written down in the decisions, §6.3 and `client-api.md`, so the factory's client can follow it.
  
  **Changes**
  
  1. **A reversed edge is described two ways.**
     - Criterion 5 says every distinct edge, reversed ones included, runs "from its source's right side to its target's left side" and graph.py measures that.
     - `spec/ui.md:852–857` says a reversed edge's arrowhead "points into its target, from the right". Its target is in an earlier layer, so the edge ends at the target's *right* side.
     - The two disagree. If graph.py checks criterion 5 as written, every reversed edge either fails or gets drawn back across both its nodes.
     - Fix: state the reversed case the same way in criterion 5 and §6.3. For example: "a reversed edge runs from its source's left side to its target's right side, dashed, its arrowhead pointing left into the target". Name that case in graph.py's measurement too.
  
  2. **Small: where nodes without edges go in the table.**
     - §6.3 (`spec/ui.md:862`) orders the table's rows "in the order of the layers". But nodes without edges are not in any layer (`spec/ui.md:841`), so their place in the table is undefined.
     - Criterion 8 doesn't give an order at all.
     - Fix: say they come after the layered nodes, in their given order, in both places, so a test can decide it.
- 2026-11-10 08:54  gate A asked of a reviewer
- 2026-11-10 08:55  gate A: approve (reviewer)
  The reviewer's two requested changes from the first round are both fixed, and nothing new needs changing. I approve.
  
  **The first round's changes**
  
  1. **A reversed edge is now described the same way everywhere.**
     - Criterion 5 and §6.3's drawing bullet both say it is dashed and runs from its source's left side to its target's right side, with the arrowhead pointing left.
     - Its target is in an earlier layer, so that is the right geometry.
     - Criterion 5 now says `graph.py` measures the reversed edges too, and the §10 entry for `graph.py` says it checks every edge's ends.
  2. **The table's order is now defined.** Criterion 8 and §6.3 agree: rows follow the layers, starting from the first and going down each layer, then the nodes with no edges, in the order NODES gives them. A test can decide this.
  
  **What is right**
  
  - **The brief is covered, and nothing beyond it.**
    - **Nodes:** title, an optional second line, the six states in the tokens' tones, an optional link, and badges. The `:agent` badge reads as "working here now" (pulse, ring, and the screen-reader text "T, working now"). The `:ref` badge is a count or issue reference, in tabular figures.
    - **Edges:** directed, with an arrowhead into the target.
    - **Layout:** layered, on the server, with no library and nothing fetched. It handles nodes without edges and cycles, and the bounds give 30–60 nodes plenty of room.
    - **Widths and modes:** 390 px and desktop, light and dark, no script, and a table for screen readers.
    - **Documentation and tests:** the specimen and showcase, `spec/ui.md` §6, §6.3 and §10, `docs/client-api.md`, layout tests, a browser check at both widths, and core 2.18.0.
  - **Each criterion can be decided** by a named test or by `graph.py`.
  - **The criteria and the spec agree** on:
    - the node box and its three lines;
    - the state words in English and Norwegian, and their tones;
    - the badge kinds and tones;
    - the bounds and errors;
    - the five layout steps;
    - nodes without edges in a row of their own;
    - the edge drawing;
    - scrolling in the drawing's own box;
    - the table, `aria-hidden` and "No data".
  - **None of the decisions needed the asker.**
    - The meaning of an edge (`:from A :to B` means B depends on A) answers the brief's "a dependency, from → to". It is written in the decisions, §6.3 and `client-api.md`, so the factory client being built alongside can follow it.
    - Left to right at every width, scrolling sideways on a phone, is allowed by the brief.
    - No `style` attributes, polygon arrowheads and no script are implementation choices that fit the rules in §4 and §5.
  
  **A note for gate B, not a reason to hold this gate**
  
  - Criterion 8 says the `<details>` opens without JavaScript, but §6.3 only says the graph is drawn the same.
  - A native `<details>` opens without a script, so the two don't conflict. `graph.py` should still check that it opens, as §10 already says it will.
- 2026-11-10 09:20  verify 1: passed build, test, check
- 2026-11-10 09:20  shown (/graph, /ui/graph)
- 2026-11-10 09:20  gate B asked of a reviewer
- 2026-11-10 09:22  gate B: changes (reviewer)
  Two things to fix found. Writing the verdict now.
  
  ## Gate B review: ui-graph
  
  **What is right**
  
  - **Verification passed.** All three steps in `verify.txt` passed (build, test, check). Every browser check in `checks/` passed, `graph.json` included (light and dark, 390 px, desktop, and without JavaScript).
  - **Criteria 1, 2, 4, 5, 7, 8 and 10 are met**, each with a test or check that would fail without the change:
    - **Layout (criterion 4):** `tests/graph-tests.lisp` covers each bullet: layers, a chain on one row, loose nodes, a source next to its successor, long edges through empty places, nothing sharing a place, crossed edges uncrossed, cycles reversed and marked, and the same layout every time.
    - **Edge geometry (criterion 5):** pinned to exact path and polygon coordinates in the tests. `graph.py` measures every edge's ends against its nodes' sides at both widths, reversed edges included.
    - **Table (criterion 8):** the row order, the "depends on" column, `aria-hidden` and «No data» are all tested. `graph.py` opens the `<details>` without JavaScript.
    - **Version (criterion 10):** 2.18.0 in both `src/core/module.lisp` and `flake.nix`.
  - **The brief is covered.** The screenshots at both widths show the factory picture the brief asks for:
    - nodes in their state tones;
    - the ringed agent node with its pulsing badge;
    - `#12` and «1 question» refs;
    - directed arrows and the cycle;
    - loose nodes in their own row;
    - the drawing scrolling in its own box on a phone while the page does not.
  
    The specimen also shows the module graph from Factory 4.
  - **Reduced motion works.** The pulse stops under reduced motion through the kit's global rule (`kit.lisp:411`), so the comment in `graph.lisp` is accurate.
  - **The code is readable.** The layout is a set of small pure functions with docstrings that point at the matching §6.3 steps. The CSS and the drawing take their sizes from one set of constants. There is no leftover debugging, and the spec and docs were changed where the behaviour is. The nb catalogue keeps æ/ø/å.
  
  **Changes**
  
  1. **Criterion 3, "badges that do not fit … never cut", is unchecked, and one case breaks it.**
     - `.tun-graph-badges` (`src/web/ui/graph.lisp`, the `& .tun-graph-badges` rule) wraps badges to a second line and hides it. That hides whole badges only when there are several.
     - A single badge wider than the node's line is clipped on the right. `.tun-badge` is `flex-shrink: 0; white-space: nowrap`, so nothing stops it.
     - This will happen in real use. The factory puts agent names in `:agent` badges, and a long one ("Claude i tun, orchestrator") overflows a 12rem node.
     - Neither the tests nor `graph.py` check how badges overflow.
     - **Fix:**
       - Decide what an over-long badge does, for example an ellipsis inside the badge with its whole text in `title` (it is still in the table). Say it in §6.3 and criterion 3.
       - Add a node with too many badges and a long one to `/graph`.
       - Make `graph.py` assert that each badge either lies wholly inside its node's box or is wholly out of sight.
  
  2. **Criterion 6, "a kind not listed is an error", is not met for `:label`.**
     - `+graph-badge-kinds+` (`src/web/ui/graph.lisp`, near the top) accepts `:label`.
     - §6.3, criterion 3 and `docs/client-api.md` list only `:agent` and `:ref`.
     - So `(:text "x" :kind :label)` renders silently instead of signalling an error.
     - **Fix:** either refuse `:label` (no kind is the plain badge) and add it to the error test, or list `:label` in §6.3, `client-api.md` and the criterion.
  
  **Notes, not reasons to hold**
  
  - **Two-node cycles look solid.** In a two-node cycle (review ↔ fix), the solid forward edge and the dashed reversed edge lie on the same line. It reads as a double-headed arrow, which is right, but the dashing can't be seen.
  - **Hidden badge links can still take focus.** Badge links hidden by the overflow are still reachable with Tab. Focusing one can scroll the badge line into a half-shown state. Worth handling alongside change 1.
  - **Large graphs are tall.** The 48-node graph and the module graph in the specimen leave a lot of empty space above and between rows. They are readable, but taller than they need to be.
- 2026-11-10 09:25  estimated 50m 1h15m 2h30m at build, like price-chart markdown
- 2026-11-10 09:33  verify 2: passed build, test, check
- 2026-11-10 09:34  shown (/graph, /ui/graph)
- 2026-11-10 09:34  gate B asked of a reviewer
- 2026-11-10 09:35  gate B: approve (reviewer)
  **Gate B, round 2 of ui-graph: approved.** Both changes asked for in round 1 are fixed, every step of verify passed, and every criterion has a test or check that would fail without the change.
  
  **Round 1's changes are fixed**
  
  1. **Badges that overflow.**
     - **The rule:** §6.3 and criterion 3 now say what happens: badges that don't fit the line are left out of the box whole, and a lone first badge that is too wide ends in an ellipsis with its whole text in `title`.
     - **The CSS:** the badge line in `src/web/ui/graph.lisp` (the `& .tun-graph-badges` rule) is one fixed-height line that wraps and is clipped. Badges can now shrink, and the text inside them ends in an ellipsis.
     - **The showcase:** `/graph` now has a node with a long agent badge («Claude i tunworks, the orchestrator's builder») and one with six badges («Product photos»).
     - **The check:** `graph.py` asserts that every badge lies wholly inside its line or wholly below it («no badge cut: []»). It also checks the ellipsis and the `title`, and that 3 of the 6 badges are out of sight. Both checks run at 390 px and on a desktop, light and dark, and without the script. The screenshots show the result: «Claude i tunworks,…», and «Kari · Ola» with the rest hidden.
  2. **The `:label` kind.** `+graph-badge-kinds+` is now `(:agent :ref)` only, and the error test has a case for `:kind :label`.
  
  **Criteria**
  
  - **Layout (criterion 4):** `tests/graph-tests.lisp` covers each bullet. Every edge goes to a later layer, also on 60 random nodes. A chain lies on one row. Nodes with no edges stand apart. A node with no edge into it moves to just before its earliest successor. Long edges pass through empty places, and no two nodes share a place. Crossed edges come out uncrossed. A cycle's reversed edge is marked. The same input gives the same layout.
  - **Drawing and edges (criteria 1, 2, 3 and 5):** the markup tests pin the exact path and arrowhead points, forward and reversed. `graph.py` measures every edge's ends against its nodes' sides at both widths. It also checks the dashes, the stroke and the stripe colours in light and dark, and the agent's ring.
  - **Bounds and speed (criterion 6):** each kind of error is tested, and so is the largest graph rendering within a second.
  - **Scrolling and overlap (criterion 7):** checked by `graph.py`.
  - **Table (criterion 8):** the order, «Depends on», «No data» and Norwegian are tested. `graph.py` opens the table without JavaScript.
  - **Documentation and version (criteria 9 and 10):** the specimen has its three examples and the showcase its two graphs, `spec/ui.md` and `docs/client-api.md` are updated, and the version is 2.18.0 in both `src/core/module.lisp` and `flake.nix`.
  - **Verification:** `verify.txt` passed build, test and check, and no browser check in `checks/` has a failure.
  
  **The brief**
  
  The pilot and the specimen show what the factory needs, at both widths:
  - nodes in their state tones;
  - a ringed node with a pulsing agent badge;
  - `#12` and «1 question» references;
  - directed arrows, and the review ↔ fix cycle as a double-headed edge;
  - nodes with no edges in their own row;
  - Factory 4's graph of modules.
  
  On a phone the drawing scrolls in its own box and the page does not.
  
  **The code**
  
  - It follows `AGENTS.md`: there is no `style` attribute and no script, the copy is catalogued and the nb translations keep æ/ø/å, and the comments say what and why.
  - The layout is made of small pure functions, each pointing at its step in §6.3.
  - The CSS and the drawing take their sizes from one set of constants.
  - There is no debugging left in and no dead code.
  
  **Notes, not reasons to hold**
  
  - **Hidden badge links can still be focused.** Clipping stops the line from scrolling, but Tab can still land on a link nobody can see, and its focus ring is invisible. The table has the same links, so a follow-up could take them out of the tab order.
  - **§10 is behind.** `spec/ui.md` §10's entry for `graph.py` doesn't mention the new badge checks, although the check's own docstring does.
  - **Large graphs are tall.** The 48-step graph and the module graph still leave empty rows. On a phone the pilot shows mostly empty space around «Brief and estimate». They are readable, but a later loop could make them more compact.
- 2026-11-10 09:36  rebased: tun d1a4019 → fa659be
- 2026-11-10 09:44  verify 3: passed build, test, check
- 2026-11-10 09:45  shown (/graph, /ui/graph)
- 2026-11-10 09:45  gate B asked of a reviewer
- 2026-11-10 09:46  gate B: approve (reviewer)
  I approve gate B for ui-graph. The rebase onto fa659be left the graph code as the reviewer approved it in round 2, and verify round 3 passed.
  
  **What is right**
  
  - **Verification:** all three steps in `verify.txt` passed (build, test, check). No result in `checks/` failed. `graph.json` ran at 390 px and on a desktop, in light and dark, and once without JavaScript.
  - **Each criterion has a test or check that would fail without the change:**
    - **Node box, states and words (criteria 1–2):** the markup tests check the title, state word, meta and `data-live`, and the six words in English and Norwegian. `graph.py` reads each state's stripe colour in light and dark.
    - **Badges (criterion 3):** `graph.py` checks that no badge is cut. It also checks the long agent badge's ellipsis and `title`, and that three of the six badges on «Product photos» are out of sight. The error test now covers `:kind :label`.
    - **Layout (criterion 4):** `tests/graph-tests.lisp` covers every bullet, and runs the layer and no-shared-place checks on a random graph of 60 nodes and 90 edges.
    - **Edges (criterion 5):** the tests pin the exact path and arrowhead points, forward and reversed. `graph.py` measures every edge's ends against its nodes' sides, reversed edges included.
    - **Bounds and speed (criterion 6):** each error is tested, and so is 150 nodes with 300 edges rendering within a second.
    - **Table (criterion 8):** the order, «Depends on», «No data», the closed `<details>`, and opening it without JavaScript are all checked.
    - **Version (criterion 10):** 2.18.0 in both `src/core/module.lisp` and `flake.nix`.
  - **Screenshots:** the desktop shot shows what the brief asks for:
    - nodes in their tones;
    - the ringed «Booking calendar» with its pulsing agent badge and `#12`;
    - «1 question»;
    - arrows into their targets;
    - the node with no edges in its own row.
  
    At 390 px the drawing scrolls in its own box and the page does not.
  - **Code:**
    - The layout is small pure functions, each pointing at its step in §6.3, and one set of constants writes both the CSS and the SVG.
    - There is no `style` attribute and no script.
    - The new copy is catalogued, and the nb words keep æ/ø/å.
    - There is no debugging left in and no dead code.
  - **The spec:** the earlier note that §10 was behind is fixed. Its `graph.py` entry now names the badge checks, the ellipsis included.
  
  **Notes, not reasons to hold**
  
  - **A gap in §6.3 step 3.** `edge-chain` in `src/web/ui/graph.lisp` keeps a cycle's reversed edges out of the forward edges' shared empty places, so a dashed line never runs along a solid one. §6.3 step 3 only says "the edges from one node share their empty place". Adding a clause for this would make the spec match the code.
  - **For gate C.** `shots/report.md` says the preview ran from `bc284f7-dirty`, and `spec/ui.md` was modified and uncommitted in the worktree when I started. Before deploying, confirm that the committed tree is the one shown here.
  - **Still open from round 2.** Badge links that are clipped out of sight can still take focus. Large graphs, the 48-step one especially, leave a lot of empty rows. Both are fine for a later loop.
- 2026-11-10 09:46  finished at tun bf1331a
