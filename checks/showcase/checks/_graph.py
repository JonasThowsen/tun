"""What the graph checks measure of a `graph` in the page (spec/ui.md 6.3):
its drawing, its list, and which of them shows."""

# Where a graph's nodes, edges, rails and badges are on the screen, in the
# form that shows, and the colours its tokens give in the page's scheme.
MEASURE = """(selector) => {
  const root = document.querySelector(selector);
  const rect = (element) => {
    const b = element.getBoundingClientRect();
    return {left: b.left, right: b.right, top: b.top, bottom: b.bottom,
            width: b.width, height: b.height, middle: (b.top + b.bottom) / 2};
  };
  const shown = (element) => element && getComputedStyle(element).display !== 'none';
  const drawingBox = root.querySelector('.tun-graph-scroll');
  const listBox = root.querySelector('.tun-graph-list');
  const form = shown(drawingBox) ? 'drawing' : shown(listBox) ? 'list' : 'none';
  const holder = form === 'drawing' ? root.querySelector('.tun-graph-canvas')
                                    : root.querySelector('.tun-graph-list-nodes');
  const box = form === 'drawing' ? drawingBox : listBox;
  const nodeElements = [...holder.querySelectorAll('.tun-graph-node')];
  const nodes = {};
  for (const node of nodeElements) nodes[node.dataset.node] = rect(node);
  const order = nodeElements.map((node) => node.dataset.node);
  const svg = holder.closest(form === 'drawing' ? '.tun-graph-canvas' : '.tun-graph-list')
    .querySelector(form === 'drawing' ? '.tun-graph-edges' : '.tun-graph-rails');
  const matrix = svg.getScreenCTM();
  const screen = (x, y) => {
    const p = new DOMPoint(x, y).matrixTransform(matrix);
    return {x: p.x, y: p.y};
  };
  const edges = [...svg.querySelectorAll('.tun-graph-edge')].map((edge) => {
    const path = edge.querySelector('path');
    const start = path.getPointAtLength(0);
    const [x, y] = edge.querySelector('polygon').getAttribute('points').split(' ')[0]
      .split(',').map(Number);
    const ys = path.getAttribute('d').match(/-?[0-9.]+/g).map(Number)
      .filter((value, i) => i % 2 === 1);
    return {from: edge.dataset.from, to: edge.dataset.to, back: edge.hasAttribute('data-back'),
            start: screen(start.x, start.y), tip: screen(x, y), ys,
            stroke: getComputedStyle(path).stroke, width: getComputedStyle(path).strokeWidth,
            dashes: getComputedStyle(path).strokeDasharray};
  });
  const rails = [...svg.querySelectorAll('.tun-graph-rail')].map((rail) => ({
    node: rail.dataset.node, back: rail.hasAttribute('data-back'),
    dashes: getComputedStyle(rail.querySelector('path')).strokeDasharray,
    tips: [...rail.querySelectorAll('polygon')].map((polygon) => {
      const [x, y] = polygon.getAttribute('points').split(' ')[0].split(',').map(Number);
      return {node: polygon.dataset.node, ...screen(x, y)};
    }),
    dots: [...rail.querySelectorAll('circle')].map((circle) => ({
      node: circle.dataset.node,
      ...screen(Number(circle.getAttribute('cx')), Number(circle.getAttribute('cy')))})),
  }));
  const token = (name) => {
    const probe = document.createElement('span');
    probe.style.color = `var(${name})`;
    root.append(probe);
    const colour = getComputedStyle(probe).color;
    probe.remove();
    return colour;
  };
  const stripes = {};
  for (const node of nodeElements) {
    stripes[node.dataset.state] = getComputedStyle(node).borderLeftColor;
  }
  // A ringed node whose agent's badge shows; on another, «+N» holds it.
  const live = [...holder.querySelectorAll('.tun-graph-node[data-live]')]
    .find((node) => node.querySelector('.tun-graph-live'));
  const dot = live && live.querySelector('.tun-graph-live').getBoundingClientRect();
  // A badge is shown whole, in its line, or not at all, below it; one too
  // long for the line alone ends in an ellipsis.
  const cutBadges = [];
  for (const line of holder.querySelectorAll('.tun-graph-badges')) {
    const clip = line.getBoundingClientRect();
    const badges = [...line.querySelectorAll('.tun-badge')];
    for (const badge of badges) {
      const b = badge.getBoundingClientRect();
      const whole = b.left >= clip.left - 0.5 && b.right <= clip.right + 0.5
        && b.top >= clip.top - 0.5 && b.bottom <= clip.bottom + 0.5;
      const hidden = b.top >= clip.bottom - 0.5;
      const text = badge.querySelector('.tun-graph-badge-text');
      const ellipsis = badges.length === 1 && text && text.scrollWidth > text.clientWidth
        && getComputedStyle(text).textOverflow === 'ellipsis';
      if (!whole && !hidden && !ellipsis) cutBadges.push(badge.title);
    }
  }
  const nodeText = {};
  for (const node of nodeElements) {
    const title = node.querySelector('.tun-graph-title');
    const line = node.querySelector('.tun-graph-line');
    const more = node.querySelector('.tun-badge[data-kind="more"]');
    const longBadge = [...node.querySelectorAll('.tun-graph-badge-text')]
      .find((text) => text.scrollWidth > text.clientWidth);
    nodeText[node.dataset.node] = {
      titleWhole: title.scrollHeight <= title.clientHeight + 1,
      titleLines: Math.round(title.clientHeight / parseFloat(getComputedStyle(title).lineHeight)),
      lineWhole: line.scrollWidth <= line.clientWidth + 1,
      more: more ? more.querySelector('[aria-hidden]').textContent : null,
      moreTitle: more ? more.title : null,
      badges: [...node.querySelectorAll('.tun-badge:not([data-kind="more"])')].map((b) => b.title),
      longBadge: longBadge ? {title: longBadge.closest('.tun-badge').title,
                              ellipsis: getComputedStyle(longBadge).textOverflow} : null,
    };
  }
  return {
    form, nodes, order, edges, rails, stripes, cutBadges, nodeText,
    box: rect(box), holder: rect(holder),
    boxScrolls: box.scrollWidth > box.clientWidth + 1,
    tokens: {planned: token('--muted-foreground'), active: token('--info'),
             waiting: token('--warning'), done: token('--success'),
             failed: token('--destructive'), blocked: token('--destructive')},
    muted: token('--muted-foreground'),
    ring: live ? getComputedStyle(live).boxShadow : '',
    info: token('--info'),
    dot: dot ? {width: dot.width, height: dot.height} : null,
    pageScrolls: document.documentElement.scrollWidth > innerWidth,
    tableOpen: root.querySelector('.tun-graph-table').open,
  };
}"""

BACK_OFFSET = 8  # px below the middle a reversed edge runs in the drawing


def near(a, b, within=1.5):
    return abs(a - b) < within


def overlapping(nodes):
    boxes = list(nodes.values())
    return [(a, b) for i, a in enumerate(boxes) for b in boxes[i + 1:]
            if a["left"] < b["right"] - 0.5 and b["left"] < a["right"] - 0.5
            and a["top"] < b["bottom"] - 0.5 and b["top"] < a["bottom"] - 0.5]


def misplaced_edges(m):
    """The drawing's edges whose ends are not at their nodes' sides."""
    wrong = []
    for e in m["edges"]:
        source, target = m["nodes"][e["from"]], m["nodes"][e["to"]]
        start_x = source["left"] if e["back"] else source["right"]
        tip_x = target["right"] if e["back"] else target["left"]
        offset = BACK_OFFSET if e["back"] else 0
        if not (near(e["start"]["x"], start_x) and near(e["start"]["y"], source["middle"] + offset)
                and near(e["tip"]["x"], tip_x) and near(e["tip"]["y"], target["middle"] + offset)):
            wrong.append(e)
    return wrong


def misplaced_rails(m):
    """The list's arrowheads and dots that are not at their nodes: a tip at
    the node's left side within its upper half, a dot left of it within its
    height."""
    wrong = []
    for rail in m["rails"]:
        for tip in rail["tips"]:
            node = m["nodes"][tip["node"]]
            if not (near(tip["x"], node["left"]) and node["top"] < tip["y"] < node["middle"]):
                wrong.append(("tip", rail["node"], tip))
        for dot in rail["dots"]:
            node = m["nodes"][dot["node"]]
            if not (dot["x"] < node["left"] and node["top"] < dot["y"] < node["bottom"]):
                wrong.append(("dot", rail["node"], dot))
    return wrong


def list_gaps(m):
    """The space above the list's first node, and between each two."""
    tops = [m["nodes"][node] for node in m["order"]]
    return ([tops[0]["top"] - m["holder"]["top"]]
            + [b["top"] - a["bottom"] for a, b in zip(tops, tops[1:])])


def look(t, m, label):
    """The checks that hold for either form, in either scheme."""
    t.check(not overlapping(m["nodes"]), f"{label}: no two nodes overlap")
    wrong = {state: colour for state, colour in m["stripes"].items()
             if colour != m["tokens"][state]}
    t.check(not wrong, f"{label}: each stripe in its state's colour: {wrong}")
    t.check(m["dot"] and m["dot"]["width"] > 4 and m["info"] in m["ring"],
            f"{label}: an agent's node is ringed in --info, its dot shown: {m['ring']}")
    t.check(not m["cutBadges"], f"{label}: no badge cut: {m['cutBadges']}")
    t.check(not m["pageScrolls"], f"{label}: the page does not scroll sideways")
    t.check(not m["tableOpen"], f"{label}: the table is closed")
    if m["form"] == "drawing":
        t.check(m["edges"] and not misplaced_edges(m),
                f"{label}: each edge runs from its source's side to its target's: "
                f"{misplaced_edges(m)[:2]}")
        t.check(all(e["stroke"] == m["muted"] and e["width"] == "1.5px" for e in m["edges"]),
                f"{label}: edges 1.5px in --muted-foreground")
        t.check(all((e["dashes"] != "none") == e["back"] for e in m["edges"]),
                f"{label}: the reversed edges, and only they, are dashed")
    else:
        t.check(m["rails"] and not misplaced_rails(m),
                f"{label}: each rail's arrowheads and dots at their nodes: "
                f"{misplaced_rails(m)[:2]}")
        t.check(all((r["dashes"] != "none") == r["back"] for r in m["rails"]),
                f"{label}: the reversed rails, and only they, are dashed")
        gaps = list_gaps(m)
        t.check(all(gap <= 8.5 for gap in gaps),
                f"{label}: the list starts at its first node, 0.5rem between nodes: {max(gaps)}")
