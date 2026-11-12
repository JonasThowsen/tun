"""A table in a browser: every column kept on a phone in a box that scrolls
sideways, one panel of dense rows, the lead of two lines, the page never
wider than the window; a row that leads somewhere as one target, pressed at
once, with its focus ring, and what is inside it working as itself; a sort
that keeps the address and the filters, the rows staying while a slow
answer comes; and the same without JavaScript (spec/ui.md 6, table)."""

import re
import time

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > innerWidth + 1"

# The specimen's Nth table: its box, its rows' cells, its lead and what
# the box shows.
TABLE = """(n) => {
  const root = document.querySelectorAll('.tun-specimen-preview .tun-table, main .tun-table')[n];
  const box = root.querySelector('.tun-table-box');
  const rect = (e) => { const r = e.getBoundingClientRect();
                        return {left: r.left, right: r.right, top: r.top, bottom: r.bottom,
                                width: r.width, height: r.height}; };
  const style = getComputedStyle(box);
  const rows = [...box.querySelectorAll('tbody tr')];
  // A cell's lines: the height its content spans over the line's height.
  const lines = (cell) => {
    const range = document.createRange();
    range.selectNodeContents(cell);
    const rects = [...range.getClientRects()].filter((r) => r.width > 0);
    const span = Math.max(...rects.map((r) => r.bottom)) - Math.min(...rects.map((r) => r.top));
    return Math.ceil(span / parseFloat(getComputedStyle(cell).lineHeight) - 0.5);
  };
  const lead = box.querySelector('tbody .tun-table-lead');
  return {
    box: rect(box), scrollWidth: box.scrollWidth, clientWidth: box.clientWidth,
    border: style.borderTopWidth, radius: style.borderTopLeftRadius, shadow: style.boxShadow,
    attachment: style.backgroundAttachment,
    rowDisplays: [...new Set(rows.map((r) => getComputedStyle(r).display))],
    headerDisplay: getComputedStyle(box.querySelector('thead tr')).display,
    headers: [...box.querySelectorAll('thead th')]
      .filter((th) => getComputedStyle(th).display !== 'none').length,
    heights: rows.map((r) => r.getBoundingClientRect().height),
    leadLines: rows.map((r) => {
      const l = r.querySelector('.tun-table-lead');
      return l ? Math.round(l.getBoundingClientRect().height
                            / parseFloat(getComputedStyle(l).lineHeight)) : 0; }),
    leadWidths: rows.map((r) => {
      const l = r.querySelector('.tun-table-lead');
      return l ? l.getBoundingClientRect().width : 0; }),
    lead: lead && rect(lead),
    leadLineHeight: lead && parseFloat(getComputedStyle(lead).lineHeight),
    otherLines: rows.flatMap((r) => [...r.querySelectorAll('td:not(:first-child):not(:has(.tun-dropdown-menu))')]
                             .filter((td) => td.textContent.trim()).map(lines)),
    secondLeft: rows[0] && rows[0].children[1] && rows[0].children[1].getBoundingClientRect().left,
  };
}"""

AMOUNTS = """() => {
  const root = document.querySelector('.tun-specimen-preview .tun-table');
  const column = [...root.querySelectorAll('thead th')].findIndex((th) => th.textContent === 'Amount');
  const cells = [...root.querySelectorAll('tbody tr')].map((tr) => tr.children[column]);
  const box = root.querySelector('.tun-table-box').getBoundingClientRect();
  return {rights: cells.map((td) => td.getBoundingClientRect().right),
          header: root.querySelectorAll('thead th')[column].getBoundingClientRect().right,
          numeric: [...new Set(cells.map((td) => getComputedStyle(td).fontVariantNumeric))],
          boxRight: box.right};
}"""

# The point near a row's right edge, inside what its box shows, and the
# link that point belongs to.
ROW_POINT = """(n) => {
  const row = document.querySelectorAll('main .tun-table tbody tr')[n];
  const box = row.closest('.tun-table-box').getBoundingClientRect();
  const r = row.getBoundingClientRect();
  const x = Math.min(r.right, box.right) - 6, y = r.top + r.height / 2;
  const hit = document.elementFromPoint(x, y);
  const link = row.querySelector('.tun-table-row-link');
  return {x, y, href: link.getAttribute('href'),
          covers: !!hit && hit.closest('a') === link};
}"""

EDGES = """() => {
  const r = (s) => document.querySelector(s).getBoundingClientRect();
  return {table: [r('main .tun-table-box').left, r('main .tun-table-box').right],
          toolbar: [r('#cards-toolbar').left, r('#cards-toolbar').right],
          header: [r('.tun-page-header').left, r('.tun-page-header').right]};
}"""

TITLES = "() => [...document.querySelectorAll('main .tun-table tbody .tun-table-lead')].map((e) => e.textContent.trim())"

# Every 100 ms after the next press: the rows, the table's height and the
# loading sign, until a later answer replaces the rows.
WATCH = """() => {
  window.tunListSeen = [];
  const look = () => {
    const box = document.querySelector('main .tun-table-box');
    window.tunListSeen.push({
      rows: document.querySelectorAll('main .tun-table tbody tr').length,
      height: box ? box.getBoundingClientRect().height : 0,
      bar: document.querySelector('[data-tun-loading]')?.hidden === false,
      search: location.search});
  };
  for (let ms = 100; ms <= 1400; ms += 100) setTimeout(look, ms);
}"""


def held(seconds):
    def handler(route):
        time.sleep(seconds)
        route.continue_()
    return handler


def near(a, b, slack=1):
    return abs(a - b) <= slack


def specimen_on_a_phone(t):
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.goto("/ui/table")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: the page does not scroll sideways")
        m = page.evaluate(TABLE, 0)
        t.check(m["rowDisplays"] == ["table-row"] and m["headerDisplay"] == "table-row",
                f"{width}px: the orders are rows, not cards: {m['rowDisplays']}")
        t.check(m["headers"] == 6, f"{width}px: every column stays: {m['headers']}")
        t.check(m["scrollWidth"] > m["clientWidth"],
                f"{width}px: six columns scroll in their own box ({m['scrollWidth']} > {m['clientWidth']})")
        t.check(m["attachment"].count("local") == 2 and m["attachment"].count("scroll") == 2,
                f"{width}px: two covers that scroll and two edge shadows: {m['attachment']}")
        t.check(m["border"] == "1px" and m["radius"] == "12px" and m["shadow"] != "none",
                f"{width}px: one panel: {m['border']} {m['radius']} {m['shadow']}")
        t.check(max(m["leadLines"]) <= 2 and max(m["otherLines"]) == 1,
                f"{width}px: the lead within two lines, the other cells on one: "
                f"{m['leadLines']} {set(m['otherLines'])}")
        t.check(m["lead"]["width"] <= min(256, m["box"]["width"] / 2) + 1,
                f"{width}px: the lead at most half the box: {m['lead']['width']:.0f} of {m['box']['width']:.0f}")
        t.check(m["secondLeft"] < m["box"]["right"] - 40,
                f"{width}px: the customer starts in sight ({m['secondLeft']:.0f}, box {m['box']['right']:.0f})")
        page.evaluate("() => { const b = document.querySelector('.tun-specimen-preview .tun-table-box'); b.scrollLeft = b.scrollWidth; }")
        a = page.evaluate(AMOUNTS)
        t.check(max(a["rights"]) <= a["boxRight"] + 1,
                f"{width}px: scrolling the box brings the amounts into sight: {a}")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: and the page still does not scroll")
        empty = page.evaluate("""() => {
          const root = document.querySelectorAll('.tun-specimen-preview .tun-table')[4];
          const r = (e) => e.getBoundingClientRect();
          const text = r(root.querySelector('.tun-table-empty-text'));
          const box = r(root.querySelector('.tun-table-box'));
          return text.left >= box.left - 1 && text.right <= box.right + 1 && text.width > 50; }""")
        t.check(empty, f"{width}px: an empty table says so in sight")


def specimen_on_a_desktop(t):
    for scheme in ("light", "dark"):
        page = t.desktop(scheme=scheme)
        page.goto("/ui/table")
        m = page.evaluate(TABLE, 0)
        t.check(m["scrollWidth"] <= m["clientWidth"] and m["headers"] == 6,
                f"1280px {scheme}: every column in sight: {m['scrollWidth']} {m['clientWidth']}")
        t.check(m["border"] == "0px", f"1280px {scheme}: no edge from 36rem: {m['border']}")
        a = page.evaluate(AMOUNTS)
        t.check(all(near(r, a["header"]) for r in a["rights"]),
                f"1280px {scheme}: the amounts' right edges in line with their header's: {a}")
        t.check(a["numeric"] == ["tabular-nums"], f"1280px {scheme}: tabular figures: {a['numeric']}")


def cards_on_a_phone(t):
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.sign_in("employee:anna")
        page.goto("/cards")
        t.check(not page.evaluate(WIDE_PAGE), f"/cards {width}px: the page does not scroll sideways")
        e = page.evaluate(EDGES)
        t.check(all(near(a, b) for a, b in zip(e["table"], e["toolbar"]))
                and all(near(a, b) for a, b in zip(e["table"], e["header"])),
                f"/cards {width}px: the table's edges are the toolbar's and the header's: {e}")
        m = page.evaluate(TABLE, 0)
        one_line = [h for h, lines in zip(m["heights"], m["leadLines"]) if lines == 1]
        t.check(one_line and all(44 <= h <= 46 for h in one_line),
                f"/cards {width}px: a row of one line is 44 to 46px: {sorted(set(one_line))}")
        if width == 390:
            t.check(sum(m["heights"][:8]) <= 448,
                    f"/cards 390px: eight rows measure {sum(m['heights'][:8]):.0f}px, at most 448")
        t.check(max(m["otherLines"]) == 1, f"/cards {width}px: the other cells on one line")
        t.check(max(m["leadLines"]) == 2,
                f"/cards {width}px: a long title wraps to two lines and no more: {m['leadLines'][:8]}")
        t.check(max(m["leadWidths"]) <= min(256, m["box"]["width"] / 2) + 1,
                f"/cards {width}px: every lead at most half the box: "
                f"{max(m['leadWidths']):.0f} of {m['box']['width']:.0f}")
        t.check(m["secondLeft"] < m["box"]["right"] - 40,
                f"/cards {width}px: beside «Urgent: the customer cannot sign in» the status starts "
                f"in sight ({m['secondLeft']:.0f}, box {m['box']['right']:.0f})")


def cards_on_a_desktop(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    m = page.evaluate(TABLE, 0)
    t.check(all(36 <= h <= 38 for h in m["heights"]),
            f"/cards 1280px: a row is 36 to 38px: {sorted(set(m['heights']))}")


def the_row_is_one_target(t):
    for name, page in (("390px", t.phone()), ("1280px", t.desktop())):
        page.sign_in("employee:anna")
        page.goto("/cards")
        p = page.evaluate(ROW_POINT, 2)
        t.check(p["covers"], f"{name}: the point at the row's right edge is its link")
        if page.touch:
            page.touchscreen.tap(p["x"], p["y"])
        else:
            page.mouse.click(p["x"], p["y"])
        page.wait_for_url(re.compile(re.escape(p["href"]) + "$"), timeout=10000)
        t.check(page.url.endswith(p["href"]), f"{name}: a tap there opens the row's page: {page.url}")

    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.locator("main .tun-table thead .tun-table-sort").last.focus()
    page.keyboard.press("Tab")
    focus = page.evaluate("""() => {
      const a = document.activeElement;
      return {row: a.matches('.tun-table-row-link'),
              ring: getComputedStyle(a, '::after').boxShadow}; }""")
    t.check(focus["row"] and "inset" in focus["ring"],
            f"Tab reaches the row's link and the row shows the inset ring: {focus}")

    # Pressed: the ground while the mouse is held on the row, at once.
    p = page.evaluate(ROW_POINT, 1)
    page.mouse.move(p["x"], p["y"])
    hover = page.evaluate("() => getComputedStyle(document.querySelectorAll('main .tun-table tbody tr')[1]).backgroundColor")
    page.mouse.down()
    pressed = page.evaluate("""() => { const s = getComputedStyle(document.querySelectorAll('main .tun-table tbody tr')[1]);
                                       return {ground: s.backgroundColor, duration: s.transitionDuration}; }""")
    page.mouse.move(5, 5)
    page.mouse.up()
    t.check(pressed["ground"] != hover and pressed["duration"] == "0s",
            f"a held row is pressed at once: {hover} then {pressed}")


def what_is_inside_works_as_itself(t):
    page = t.desktop()
    page.goto("/ui/table")
    row = "(() => document.querySelector('.tun-specimen-preview .tun-table tbody tr'))()"
    link = page.locator(".tun-specimen-preview .tun-table tbody tr").first.locator(".tun-link")
    link.hover()
    hover = page.evaluate(f"() => getComputedStyle({row}).backgroundColor")
    page.mouse.down()
    ground = page.evaluate(f"() => getComputedStyle({row}).backgroundColor")
    page.mouse.move(5, 5)
    page.mouse.up()
    t.check(ground == hover, f"pressing a link in a row leaves the row unpressed: {hover} {ground}")

    for name, page in (("390px", t.phone()), ("1280px", t.desktop())):
        page.goto("/ui/table")
        first = page.locator(".tun-specimen-preview .tun-table tbody tr").first
        first.locator(".tun-link").click()
        t.check(page.url.endswith("/ui/table#customer-10482"),
                f"{name}: a click on the customer follows its link, not the row's: {page.url}")
        first.locator("button[aria-label='More actions']").click()
        page.wait_for_timeout(300)
        opened = page.evaluate("""() => [...document.querySelectorAll('.tun-specimen-preview .tun-table [popover]')]
                                   .some((m) => m.matches(':popover-open'))""")
        t.check(opened and page.url.endswith("/ui/table#customer-10482"),
                f"{name}: the row's menu opens and the address stays: {page.url}")
        page.get_by_role("menuitem", name="Remind").first.click()
        t.check(page.url.endswith("/ui/table#remind-10482"),
                f"{name}: its «Remind» follows its own link: {page.url}")


def sorting_keeps_the_address(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards?q=&status=&status=new&estimate=&files=")
    page.locator("main .tun-table thead .tun-table-sort", has_text="Title").click()
    page.wait_for_url(re.compile(r"sort=title"), timeout=10000)
    t.check("status=new" in page.url and "direction=asc" in page.url,
            f"sorting keeps the filter in the address: {page.url}")
    titles = page.evaluate(TITLES)
    t.check(titles == sorted(titles, key=str.lower), f"the rows by title: {titles[:5]}")
    t.check(page.locator("#cards-toolbar input[type=hidden][name=sort][value=title]").count() == 1,
            "the toolbar keeps the sort")
    weights = page.evaluate("() => [...new Set([...document.querySelectorAll('main .tun-table thead th')].map((th) => getComputedStyle(th).fontWeight))]")
    t.check(len(weights) == 1, f"the sorted header at the others' weight: {weights}")

    page.route(re.compile(r".*/cards\?.*"), held(1.5))
    before = page.evaluate("() => document.querySelector('main .tun-table-box').getBoundingClientRect().height")
    rows = page.evaluate("() => document.querySelectorAll('main .tun-table tbody tr').length")
    page.evaluate(WATCH)
    page.locator("main .tun-table thead .tun-table-sort", has_text="Estimate").click()
    page.wait_for_url(re.compile(r"sort=estimate"), timeout=15000)
    page.wait_for_timeout(300)
    seen = page.evaluate("() => window.tunListSeen || []")
    waiting = [s for s in seen if "sort=estimate" not in s["search"]]
    t.check(waiting and all(s["rows"] == rows and near(s["height"], before) for s in waiting),
            f"while the sort's answer is held the rows stay, the height too: {waiting[:3]}")
    t.check(any(s["bar"] for s in waiting), "and the loading sign shows")
    t.check("status=new" in page.url, f"the sorted address keeps the filter: {page.url}")

    before = page.evaluate("() => document.querySelector('main .tun-table-box').getBoundingClientRect().height")
    rows = page.evaluate("() => document.querySelectorAll('main .tun-table tbody tr').length")
    page.evaluate(WATCH)
    page.locator("#cards-toolbar .tun-list-toolbar-toggle").first.click()
    page.wait_for_url(re.compile(r"files=true"), timeout=15000)
    page.wait_for_timeout(300)
    seen = page.evaluate("() => window.tunListSeen || []")
    waiting = [s for s in seen if "files=true" not in s["search"]]
    t.check(waiting and all(s["rows"] == rows and near(s["height"], before) for s in waiting),
            f"while a filter's answer is held the rows stay, the height too: {waiting[:3]}")
    t.check(any(s["bar"] for s in waiting), "and the loading sign shows")
    t.check("sort=estimate" in page.url, f"the filter keeps the sort: {page.url}")
    page.unroute(re.compile(r".*/cards\?.*"))


def without_javascript(t):
    page = t.phone(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/cards?q=&status=&status=new&estimate=&files=")
    page.locator("main .tun-table thead .tun-table-sort", has_text="Title").click()
    page.wait_for_url(re.compile(r"sort=title"), timeout=10000)
    t.check("status=new" in page.url, f"without JavaScript a sort link sorts: {page.url}")
    cell = page.locator("main .tun-table tbody tr").nth(1).locator("td").last
    href = page.locator("main .tun-table tbody tr").nth(1).locator(".tun-table-row-link").get_attribute("href")
    box = cell.bounding_box()
    page.touchscreen.tap(box["x"] + box["width"] / 2, box["y"] + box["height"] / 2)
    page.wait_for_url(re.compile(re.escape(href) + "$"), timeout=10000)
    t.check(page.url.endswith(href), f"without JavaScript a tap on the row's last cell opens it: {page.url}")


def run(t):
    specimen_on_a_phone(t)
    specimen_on_a_desktop(t)
    cards_on_a_phone(t)
    cards_on_a_desktop(t)
    the_row_is_one_target(t)
    what_is_inside_works_as_itself(t)
    sorting_keeps_the_address(t)
    without_javascript(t)
