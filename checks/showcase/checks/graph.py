"""A project's steps and a graph of 48 steps, drawn by graph, at 390px and
on a desktop, light and dark: every edge leaves its source's side and its
arrowhead touches its target's, a reversed edge from the other sides and
dashed; no two nodes overlap; a node's stripe is its state's colour, an
agent's node is ringed and its dot shown; each badge is wholly inside its
node or wholly out of sight, and one too long for the line ends in an
ellipsis; the page does not scroll sideways
while a drawing wider than its box scrolls in it; the table opens with a row
per node, and the node and its badges are links; without the script the
graph is drawn the same (spec/ui.md 6.3)."""

GRAPHS = ("#pilot", "#large")

# Where the edges and nodes of a graph are on the screen, and the colours
# its tokens give in the page's scheme.
MEASURE = """(selector) => {
  const root = document.querySelector(selector);
  const box = (element) => {
    const b = element.getBoundingClientRect();
    return {left: b.left, right: b.right, top: b.top, bottom: b.bottom,
            middle: (b.top + b.bottom) / 2};
  };
  const nodes = {};
  for (const node of root.querySelectorAll('.tun-graph-node')) nodes[node.dataset.node] = box(node);
  const svg = root.querySelector('.tun-graph-edges');
  const matrix = svg.getScreenCTM();
  const screen = (x, y) => new DOMPoint(x, y).matrixTransform(matrix);
  const edges = [...root.querySelectorAll('.tun-graph-edge')].map((edge) => {
    const path = edge.querySelector('path');
    const start = screen(path.getPointAtLength(0).x, path.getPointAtLength(0).y);
    const [x, y] = edge.querySelector('polygon').getAttribute('points').split(' ')[0]
      .split(',').map(Number);
    const tip = screen(x, y);
    return {from: edge.dataset.from, to: edge.dataset.to, back: edge.hasAttribute('data-back'),
            start: {x: start.x, y: start.y}, tip: {x: tip.x, y: tip.y},
            stroke: getComputedStyle(path).stroke, width: getComputedStyle(path).strokeWidth,
            dashes: getComputedStyle(path).strokeDasharray};
  });
  const token = (name) => {
    const probe = document.createElement('span');
    probe.style.color = `var(${name})`;
    root.append(probe);
    const colour = getComputedStyle(probe).color;
    probe.remove();
    return colour;
  };
  const stripes = {};
  for (const node of root.querySelectorAll('.tun-graph-node')) {
    stripes[node.dataset.state] = getComputedStyle(node).borderLeftColor;
  }
  const live = root.querySelector('.tun-graph-node[data-live]');
  const dot = live && live.querySelector('.tun-graph-live').getBoundingClientRect();
  // A badge is shown whole, in its line, or not at all, below it.
  const cutBadges = [];
  for (const line of root.querySelectorAll('.tun-graph-node .tun-graph-badges')) {
    const clip = line.getBoundingClientRect();
    for (const badge of line.querySelectorAll('.tun-badge')) {
      const b = badge.getBoundingClientRect();
      const whole = b.left >= clip.left - 0.5 && b.right <= clip.right + 0.5
        && b.top >= clip.top - 0.5 && b.bottom <= clip.bottom + 0.5;
      const hidden = b.top >= clip.bottom - 0.5;
      if (!whole && !hidden) cutBadges.push(badge.title);
    }
  }
  const scroll = root.querySelector('.tun-graph-scroll');
  return {
    nodes, edges, stripes, cutBadges,
    tokens: {planned: token('--muted-foreground'), active: token('--info'),
             waiting: token('--warning'), done: token('--success'),
             failed: token('--destructive'), blocked: token('--destructive')},
    muted: token('--muted-foreground'),
    ring: live ? getComputedStyle(live).boxShadow : '',
    info: token('--info'),
    dot: dot ? {width: dot.width, height: dot.height} : null,
    scrolls: scroll.scrollWidth > scroll.clientWidth + 1,
    scrollFits: scroll.getBoundingClientRect().right <= innerWidth + 0.5,
    pageScrolls: document.documentElement.scrollWidth > innerWidth,
    tableOpen: root.querySelector('.tun-graph-table').open,
  };
}"""


def near(a, b):
    return abs(a - b) < 1.5


def overlapping(nodes):
    boxes = list(nodes.values())
    return [(a, b) for i, a in enumerate(boxes) for b in boxes[i + 1:]
            if a["left"] < b["right"] - 0.5 and b["left"] < a["right"] - 0.5
            and a["top"] < b["bottom"] - 0.5 and b["top"] < a["bottom"] - 0.5]


def misplaced_edges(m):
    """The edges whose ends are not at their nodes' sides."""
    wrong = []
    for e in m["edges"]:
        source, target = m["nodes"][e["from"]], m["nodes"][e["to"]]
        start_x = source["left"] if e["back"] else source["right"]
        tip_x = target["right"] if e["back"] else target["left"]
        if not (near(e["start"]["x"], start_x) and near(e["start"]["y"], source["middle"])
                and near(e["tip"]["x"], tip_x) and near(e["tip"]["y"], target["middle"])):
            wrong.append(e)
    return wrong


def look(t, page, name, wide_box_scrolls):
    for graph in GRAPHS:
        m = page.evaluate(MEASURE, graph)
        label = f"{name} {graph}"
        t.check(m["edges"] and not misplaced_edges(m),
                f"{label}: each edge runs from its source's side to its target's: "
                f"{misplaced_edges(m)[:2]}")
        t.check(not overlapping(m["nodes"]), f"{label}: no two nodes overlap")
        t.check(all(e["stroke"] == m["muted"] and e["width"] == "1.5px" for e in m["edges"]),
                f"{label}: edges 1.5px in --muted-foreground")
        t.check(all((e["dashes"] != "none") == e["back"] for e in m["edges"]),
                f"{label}: the reversed edges, and only they, are dashed")
        wrong = {state: colour for state, colour in m["stripes"].items()
                 if colour != m["tokens"][state]}
        t.check(not wrong, f"{label}: each stripe in its state's colour: {wrong}")
        t.check(m["dot"] and m["dot"]["width"] > 4 and m["info"] in m["ring"],
                f"{label}: an agent's node is ringed in --info, its dot shown: {m['ring']}")
        t.check(not m["pageScrolls"] and m["scrollFits"],
                f"{label}: the page does not scroll sideways")
        t.check(not m["tableOpen"], f"{label}: the table is closed")
        t.check(not m["cutBadges"], f"{label}: no badge cut: {m['cutBadges']}")
        if wide_box_scrolls or graph == "#large":
            t.check(m["scrolls"], f"{label}: the drawing scrolls in its own box")
    pilot = page.evaluate(MEASURE, "#pilot")
    t.check(any(e["back"] for e in pilot["edges"]), f"{name}: the pilot has a reversed edge")
    t.check(len(pilot["edges"]) == 14, f"{name}: the pilot's 14 edges: {len(pilot['edges'])}")
    long = page.evaluate("""() => {
      const text = document.querySelector('#pilot [data-node="docs"] .tun-graph-badge-text');
      return {cut: text.scrollWidth > text.clientWidth,
              ellipsis: getComputedStyle(text).textOverflow,
              title: text.closest('.tun-badge').title};
    }""")
    t.check(long["cut"] and long["ellipsis"] == "ellipsis"
            and long["title"] == "Claude i tunworks, the orchestrator's builder",
            f"{name}: a badge too long for the line ends in an ellipsis, whole in its title: {long}")
    many = page.evaluate("""() => {
      const line = document.querySelector('#pilot [data-node="photos"] .tun-graph-badges');
      const clip = line.getBoundingClientRect();
      return [...line.querySelectorAll('.tun-badge')]
        .filter((b) => b.getBoundingClientRect().top >= clip.bottom - 0.5).length;
    }""")
    t.check(many > 0, f"{name}: of six badges, those past the line are out of sight: {many}")


def run(t):
    for scheme in ("light", "dark"):
        phone = t.phone(width=390, scheme=scheme)
        phone.sign_in("employee:anna")
        phone.goto("/graph")
        look(t, phone, f"390px {scheme}", True)
        desktop = t.desktop(scheme=scheme)
        desktop.sign_in("employee:anna")
        desktop.goto("/graph")
        look(t, desktop, f"desktop {scheme}", False)

    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/graph")
    table = page.locator("#pilot .tun-graph-table")
    table.locator("summary").click()
    rows = table.locator("tbody tr")
    t.check(rows.count() == 13, f"the table has a row per node: {rows.count()}")
    t.check(rows.first.inner_text().startswith("Brief and estimate"),
            f"the first layer first: {rows.first.inner_text()!r}")
    t.check(rows.last.inner_text().startswith("Customer guide"),
            "the node with no edges last")
    review = next(text for text in rows.all_inner_texts()
                  if text.startswith("Review the calendar"))
    t.check("Booking calendar" in review and "Fix the double bookings" in review,
            f"a row names what its node depends on: {review!r}")

    node = page.locator('#pilot .tun-graph-node[data-node="demo"]')
    node.scroll_into_view_if_needed()
    box = node.bounding_box()
    page.mouse.click(box["x"] + box["width"] - 12, box["y"] + box["height"] - 12)
    page.wait_for_url("**/graph/demo")
    t.check(page.url.endswith("/graph/demo"), "a tap anywhere on a node follows its link")
    page.goto("/graph")
    page.locator('#pilot .tun-graph-node[data-node="calendar"] .tun-graph-badge-link').click()
    page.wait_for_url("**/graph")
    t.check(page.url.endswith("/graph"), "a badge's own link stays above the node's")

    off = t.desktop(javascript=False)
    off.sign_in("employee:anna")
    off.goto("/graph")
    look(t, off, "without the script", False)
    off.locator("#pilot .tun-graph-table summary").click()
    t.check(off.evaluate("document.querySelector('#pilot .tun-graph-table').open"),
            "without the script the table opens")
