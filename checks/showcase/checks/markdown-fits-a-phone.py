"""An agent's comment shown with markdown, at 320px, 390px and on a desktop:
the page never scrolls sideways, though the comment holds a table of ten
columns, a line with no spaces, a long code line and a long address; on a
phone the ten columns are cards, each value under its heading, and the
table of three stays a table; on a desktop the ten columns are a table in a
box of its own, which scrolls at 800px where they do not fit, and the code
block scrolls in its own (spec/ui.md 6.2)."""

COMMENT = "#comment"

MEASURE = """(selector) => {
  const root = document.querySelector(selector);
  const [narrow, wide] = root.querySelectorAll('.tun-markdown-table');
  const pre = root.querySelector('.tun-code-block-pre');
  const label = wide.querySelector('tbody tr td .tun-markdown-table-label');
  const value = label.nextElementSibling;
  const box = (element) => element.getBoundingClientRect();
  const inside = (element) => box(element).right <= box(root).right + 0.5
    && box(element).left >= box(root).left - 0.5;
  return {
    pageScrolls: document.documentElement.scrollWidth > innerWidth,
    rootWidth: box(root).width,
    narrowRow: getComputedStyle(narrow.querySelector('tbody tr')).display,
    narrowInside: inside(narrow),
    wideRow: getComputedStyle(wide.querySelector('tbody tr')).display,
    wideHeadings: getComputedStyle(wide.querySelector('thead')).display,
    labelShown: getComputedStyle(label).display !== 'none',
    labelText: label.textContent,
    labelAbove: box(label).bottom <= box(value).top + 0.5,
    wideInside: inside(wide),
    wideScrolls: wide.scrollWidth > wide.clientWidth,
    wideOverflow: getComputedStyle(wide).overflowX,
    codeInside: inside(pre),
    codeScrolls: pre.scrollWidth > pre.clientWidth,
    paragraphsInside: [...root.querySelectorAll(':scope > p')].every(inside),
    links: [...root.querySelectorAll('a')].map((a) => a.getAttribute('href')),
    text: root.textContent,
  };
}"""


def run(t):
    for width in (320, 390):
        phone = t.phone(width=width)
        phone.sign_in("employee:anna")
        phone.goto("/markdown")
        m = phone.evaluate(MEASURE, COMMENT)
        name = f"{width}px"
        t.check(not m["pageScrolls"], f"{name}: the page does not scroll sideways")
        t.check(m["paragraphsInside"],
                f"{name}: the line with no spaces and the long address break inside the comment")
        t.check(m["narrowRow"] == "table-row" and m["narrowInside"],
                f"{name}: three columns stay a table and fit: {m['narrowRow']}")
        t.check(m["wideRow"] == "block" and m["wideHeadings"] == "none",
                f"{name}: ten columns are cards: rows {m['wideRow']}, headings {m['wideHeadings']}")
        t.check(m["labelShown"] and m["labelText"] == "Order" and m["labelAbove"],
                f"{name}: each value has its heading above it: {m['labelText']!r}")
        t.check(m["wideInside"], f"{name}: the cards fit in the comment")
        t.check(m["codeInside"] and m["codeScrolls"],
                f"{name}: the code block scrolls in its own box")

    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/markdown")
    m = page.evaluate(MEASURE, COMMENT)
    t.check(not m["pageScrolls"], "desktop: the page does not scroll sideways")
    t.check(m["wideRow"] == "table-row" and m["wideHeadings"] == "table-header-group",
            f"desktop: ten columns are a table ({m['rootWidth']}px wide)")
    t.check(m["wideInside"] and m["wideOverflow"] == "auto",
            "desktop: in a box of its own that scrolls when it does not fit")
    t.check(m["codeInside"] and m["codeScrolls"], "desktop: the code block scrolls in its own box")

    # A tablet: wide enough for a table, too narrow for ten columns whose
    # words stay whole.
    tablet = t.desktop(width=800)
    tablet.sign_in("employee:anna")
    tablet.goto("/markdown")
    m = tablet.evaluate(MEASURE, COMMENT)
    t.check(not m["pageScrolls"], "800px: the page does not scroll sideways")
    t.check(m["wideRow"] == "table-row" and m["wideInside"] and m["wideScrolls"],
            f"800px: ten columns are a table scrolling in its own box ({m['rootWidth']}px wide)")
    t.check(m["links"] == ["/items/12", "https://example.com/docs/export_(v2)",
                           "https://example.com/status", "mailto:team@example.com",
                           "https://example.com/exports/2026/11/orders-for-every-customer-and-every-department-in-the-company.csv"],
            f"desktop: the links, and no javascript: one: {m['links']}")
    t.check("<script>alert('shown as written')</script>" in m["text"],
            "desktop: the HTML in the comment shows as written")
