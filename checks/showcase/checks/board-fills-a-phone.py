"""On a phone, a board fills the screen under a one-row header, and its
columns' cards scroll inside them (spec/ui.md 6.1, 8)."""

MEASURE = """() => {
  const column = document.querySelector('.tun-board-column').getBoundingClientRect();
  const header = document.querySelector('.tun-page-header');
  const title = header.querySelector('.tun-page-header-title').getBoundingClientRect();
  const actions = header.querySelector('.tun-page-header-actions').getBoundingClientRect();
  return {top: column.top, bottom: column.bottom, below: innerHeight - column.bottom,
          pageScrolls: document.documentElement.scrollHeight > innerHeight,
          oneRow: Math.abs(title.top - actions.top) < 20 && actions.left > title.right};
}"""


def run(t):
    for width, height in ((390, 844), (375, 667)):
        page = t.phone(width, height)
        page.sign_in("employee:anna")
        page.goto("/items")
        m = page.evaluate(MEASURE)
        t.check(m["oneRow"], f"{width}x{height}: the title and its buttons share a row")
        t.check(m["bottom"] <= height - 40, f"{width}x{height}: a column's bottom edge shows ({m['bottom']:.0f})")
        t.check(m["below"] >= 40, f"{width}x{height}: with a strip of page under it ({m['below']:.0f}px)")
        t.check(not m["pageScrolls"], f"{width}x{height}: the page itself does not scroll")

    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/items")
    m = page.evaluate(MEASURE)
    cards = "document.querySelector('[data-tun-board-column=new] .tun-board-cards').scrollTop"
    page.touch.swipe((195, (m["top"] + m["bottom"]) / 2), (195, (m["top"] + m["bottom"]) / 2 - 150))
    page.wait_for_timeout(400)
    t.check(page.evaluate(cards) > 50, "a swipe on the cards scrolls the column")
    t.check(page.evaluate("scrollY") == 0, "and not the page")
