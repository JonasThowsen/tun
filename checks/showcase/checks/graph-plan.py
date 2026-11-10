"""The shape of a real plan of 30 components (Tun ERP's) on /graph, light and
dark. At 390px it is a list of all 30 nodes that starts at its first node
with 0.5rem between them, neither the page nor the list scrolling sideways;
each rail's arrowheads and dots at their nodes; at least 28 titles whole in
two lines, every state word and META whole. At 1280px it is a drawing that
scrolls sideways in its own box and opens on nodes: the first layer's node
in its first two rows, at least six nodes in the box's first 600px, at
least 24 titles whole, every state word and META whole. At both, «+2» on
accounting-port, «+1» on order-lifecycle, none on orders, and every badge
inside its node but setup-wizard's, too long for its line, which ends in an
ellipsis with its whole text in its title (spec/ui.md 6.3)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _graph  # noqa: E402

PLAN = "#plan"
ROW = 104 + 16  # a row of the drawing, in px


def badges(t, m, label):
    text = m["nodeText"]
    t.check(text["accounting-port"]["more"] == "+2"
            and text["accounting-port"]["badges"] == ["1 question"]
            and text["accounting-port"]["moreTitle"] == "2 more: Planner, #40",
            f"{label}: «+2» on accounting-port: {text['accounting-port']}")
    t.check(text["order-lifecycle"]["more"] == "+1"
            and text["order-lifecycle"]["badges"] == ["Reviewer", "#42"],
            f"{label}: «+1» on order-lifecycle: {text['order-lifecycle']}")
    t.check(text["orders"]["more"] is None and text["orders"]["badges"] == ["Builder 2", "#41"],
            f"{label}: no «+N» on orders: {text['orders']}")
    long = text["setup-wizard"]["longBadge"]
    t.check(long and long["ellipsis"] == "ellipsis"
            and long["title"] == "Builder 3, the one on the long name",
            f"{label}: a badge too long for the line ends in an ellipsis: {long}")
    lines = [key for key, value in text.items() if not value["lineWhole"]]
    t.check(not lines, f"{label}: every state word and META whole: {lines}")


def run(t):
    for scheme in ("light", "dark"):
        phone = t.phone(width=390, scheme=scheme)
        phone.sign_in("employee:anna")
        phone.goto("/graph")
        m = phone.evaluate(_graph.MEASURE, PLAN)
        label = f"390px {scheme}"
        t.check(m["form"] == "list", f"{label}: a list")
        t.check(len(m["order"]) == 30, f"{label}: all 30 nodes: {len(m['order'])}")
        t.check(not m["boxScrolls"], f"{label}: the list does not scroll sideways")
        _graph.look(t, m, label)
        whole = [key for key, value in m["nodeText"].items() if value["titleWhole"]]
        t.check(len(whole) >= 28 and all(v["titleLines"] <= 2 for v in m["nodeText"].values()),
                f"{label}: at least 28 titles whole, in up to two lines: {len(whole)}")
        badges(t, m, label)

        desktop = t.desktop(scheme=scheme)
        desktop.sign_in("employee:anna")
        desktop.goto("/graph")
        desktop.locator(PLAN).scroll_into_view_if_needed()
        m = desktop.evaluate(_graph.MEASURE, PLAN)
        label = f"1280px {scheme}"
        t.check(m["form"] == "drawing", f"{label}: a drawing")
        t.check(m["boxScrolls"], f"{label}: the drawing scrolls sideways in its own box")
        _graph.look(t, m, label)
        whole = [key for key, value in m["nodeText"].items() if value["titleWhole"]]
        t.check(len(whole) >= 24, f"{label}: at least 24 titles whole: {len(whole)}")
        badges(t, m, label)
        first_row = round((m["nodes"]["module-layout"]["top"] - m["holder"]["top"]) / ROW)
        t.check(first_row <= 1,
                f"{label}: the first layer's node in the first two rows: {first_row}")
        view = m["box"]
        in_view = [key for key, node in m["nodes"].items()
                   if node["left"] < view["right"] and node["right"] > view["left"]
                   and node["top"] < view["top"] + 600 and node["bottom"] > view["top"]]
        t.check(len(in_view) >= 6,
                f"{label}: at least six nodes in the box's first 600px: {len(in_view)}")
