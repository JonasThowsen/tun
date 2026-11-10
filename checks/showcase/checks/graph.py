"""The graphs on /graph, light and dark: at 1280px each is a drawing, every
edge leaving its source's side and its arrowhead touching its target's, a
reversed edge from the other sides, 0.5rem below their middles, and dashed;
no row of the 48-step drawing empty across every layer; at 390px each is a
list, its rails' arrowheads and dots at their nodes, the 48-step one's
nodes at least 12rem wide. At both, no two nodes overlap, a node's stripe is
its state's colour, an agent's node is ringed and its dot shown, no badge is
cut, the page does not scroll sideways; the table opens with a row per
node, and a node and its badges are links; without the script the forms are
chosen and drawn the same (spec/ui.md 6.3)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _graph  # noqa: E402

GRAPHS = ("#pilot", "#plan", "#large")
ROW = 104 + 16  # a row of the drawing, in px


def empty_rows(m):
    """The drawing's rows that neither a node nor an edge's empty place is
    in: a node's row from its top, an empty place's from the y an edge
    passes it at, the middle of its row (or below it, reversed)."""
    rows = {round((node["top"] - m["holder"]["top"]) / ROW) for node in m["nodes"].values()}
    for edge in m["edges"]:
        offset = _graph.BACK_OFFSET if edge["back"] else 0
        rows |= {int((y - offset - 52) // ROW) for y in edge["ys"]
                 if (y - offset - 52) % ROW == 0}
    return sorted(set(range(max(rows) + 1)) - rows)


def run(t):
    for scheme in ("light", "dark"):
        phone = t.phone(width=390, scheme=scheme)
        phone.sign_in("employee:anna")
        phone.goto("/graph")
        desktop = t.desktop(scheme=scheme)
        desktop.sign_in("employee:anna")
        desktop.goto("/graph")
        for graph in GRAPHS:
            m = phone.evaluate(_graph.MEASURE, graph)
            t.check(m["form"] == "list", f"390px {scheme} {graph}: a list, not a drawing")
            _graph.look(t, m, f"390px {scheme} {graph}")
            m = desktop.evaluate(_graph.MEASURE, graph)
            t.check(m["form"] == "drawing", f"1280px {scheme} {graph}: a drawing")
            _graph.look(t, m, f"1280px {scheme} {graph}")
        large = phone.evaluate(_graph.MEASURE, "#large")
        narrowest = min(node["width"] for node in large["nodes"].values())
        t.check(narrowest >= 192 - 0.5,
                f"390px {scheme}: the 48-step list's nodes are at least 12rem wide: {narrowest}")
        large = desktop.evaluate(_graph.MEASURE, "#large")
        t.check(not empty_rows(large),
                f"1280px {scheme}: no row of the 48-step drawing is empty: {empty_rows(large)}")
        pilot = desktop.evaluate(_graph.MEASURE, "#pilot")
        t.check(any(e["back"] for e in pilot["edges"]), f"{scheme}: the pilot has a reversed edge")
        t.check(len(pilot["edges"]) == 14, f"{scheme}: the pilot's 14 edges: {len(pilot['edges'])}")
        t.check(any(r["back"] for r in phone.evaluate(_graph.MEASURE, "#pilot")["rails"]),
                f"{scheme}: the pilot's list has a reversed rail")

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

    node = page.locator('#pilot .tun-graph-canvas .tun-graph-node[data-node="demo"]')
    node.scroll_into_view_if_needed()
    box = node.bounding_box()
    page.mouse.click(box["x"] + box["width"] - 12, box["y"] + box["height"] - 12)
    page.wait_for_url("**/graph/demo")
    t.check(page.url.endswith("/graph/demo"), "a tap anywhere on a node follows its link")
    page.goto("/graph")
    page.locator('#pilot .tun-graph-canvas [data-node="calendar"] .tun-graph-badge-link').click()
    page.wait_for_url("**/graph")
    t.check(page.url.endswith("/graph"), "a badge's own link stays above the node's")

    for name, off in (("1280px", t.desktop(javascript=False)),
                      ("390px", t.phone(width=390, javascript=False))):
        off.sign_in("employee:anna")
        off.goto("/graph")
        m = off.evaluate(_graph.MEASURE, "#pilot")
        t.check(m["form"] == ("drawing" if name == "1280px" else "list"),
                f"without the script at {name}: the {m['form']}")
        _graph.look(t, m, f"without the script at {name}")
        off.locator("#pilot .tun-graph-table summary").click()
        t.check(off.evaluate("document.querySelector('#pilot .tun-graph-table').open"),
                f"without the script at {name}: the table opens")
