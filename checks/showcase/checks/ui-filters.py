"""A list's toolbar in a browser: the search and a button per filter on one
row, a choice applied at once into the address without loading the page,
Back a choice back, the «Filters» sheet and the floating popover on a
phone, nothing wider than the window, and the form without JavaScript
(spec/ui.md 6, list-toolbar; 8, «Lists»)."""

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > innerWidth + 1"

ROW = """() => {
  const box = (e) => { const r = e.getBoundingClientRect();
                       return {top: r.top, bottom: r.bottom, left: r.left, right: r.right,
                               width: r.width, height: r.height}; };
  const toolbar = document.querySelector('#cards-toolbar');
  const parts = [...toolbar.querySelectorAll(
    '.tun-list-toolbar-search, .tun-list-toolbar-filter-control, .tun-list-toolbar-toggle, [data-tun-list-toolbar-fold]')]
    .filter((e) => e.getBoundingClientRect().width > 0);
  const table = document.querySelector('.tun-table, .tun-empty-state');
  return {parts: parts.map(box), toolbar: box(toolbar.querySelector('.tun-list-toolbar-row')),
          list: table ? box(table).top : null,
          rows: document.querySelectorAll('.tun-table tbody tr').length,
          weights: [...new Set([...toolbar.querySelectorAll('.tun-list-toolbar-filter-button, .tun-list-toolbar-toggle')]
                               .map((e) => getComputedStyle(e).fontWeight))]};
}"""

POPOVER = """(id) => {
  const p = document.getElementById(id);
  const r = p.getBoundingClientRect();
  const s = getComputedStyle(p);
  let open = false;
  try { open = p.matches(':popover-open'); } catch (e) {}
  return {open, top: r.top, bottom: r.bottom, left: r.left, right: r.right, width: r.width,
          radius: s.borderTopLeftRadius, radiusEnd: s.borderBottomRightRadius,
          property: s.transitionProperty, duration: s.transitionDuration,
          dim: getComputedStyle(p, '::backdrop').backgroundColor,
          focus: document.activeElement && (document.activeElement.id || document.activeElement.className)};
}"""

FOCUS = "() => document.activeElement && (document.activeElement.id || document.activeElement.getAttribute('aria-label') || document.activeElement.textContent.trim())"


def rows(page):
    return page.evaluate("() => document.querySelectorAll('.tun-table tbody tr').length")


def wait_for(page, search, count):
    """Wait until the address holds SEARCH and the list COUNT rows."""
    page.wait_for_function(
        "([search, count]) => location.search.includes(search)"
        " && document.querySelectorAll('.tun-table tbody tr').length === count",
        arg=[search, count], timeout=10000)


def desktop(t):
    for scheme in ("light", "dark"):
        page = t.desktop(scheme=scheme)
        page.sign_in("employee:anna")
        page.goto("/cards")
        m = page.evaluate(ROW)
        tops = [p["top"] for p in m["parts"]]
        t.check(len(tops) == 4 and max(tops) - min(tops) <= 1,
                f"1280px {scheme}: the search and the three filters on one row: {tops}")
        t.check(not page.evaluate(WIDE_PAGE), f"1280px {scheme}: the page does not scroll sideways")

    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/graph")
    page.goto("/cards")
    page.evaluate("() => { window.tunFiltersMark = 1; }")
    before = page.evaluate(ROW)
    total = before["rows"]

    # One of several: under its button, rising in; the choice closes it.
    page.locator("#cards-toolbar-estimate-button").click()
    page.wait_for_timeout(300)
    p = page.evaluate(POPOVER, "cards-toolbar-estimate-choices")
    button = page.evaluate("() => document.querySelector('#cards-toolbar-estimate .tun-list-toolbar-filter-control').getBoundingClientRect().toJSON()")
    t.check(p["open"] and p["top"] >= button["bottom"] - 0.5 and p["top"] - button["bottom"] <= 12
            and abs(p["left"] - button["left"]) <= 1 and p["right"] <= 1280,
            f"1280px: the choices open under their button: {p} {button}")
    t.check("opacity" in p["property"] and "translate" in p["property"]
            and "transform" not in p["property"] and p["duration"].startswith("0.15s"),
            f"1280px: it fades and rises over --duration-fast: {p['property']} {p['duration']}")
    t.check(p["focus"] == "cards-toolbar-estimate-choice",
            f"1280px: the focus is on its chosen choice, «All»: {p['focus']}")
    page.keyboard.press("Escape")
    page.wait_for_timeout(250)
    t.check(not page.evaluate(POPOVER, "cards-toolbar-estimate-choices")["open"]
            and page.evaluate(FOCUS) == "cards-toolbar-estimate-button",
            "1280px: Escape closes it, the focus back on its button")
    page.locator("#cards-toolbar-estimate-button").click()
    page.wait_for_timeout(250)
    page.locator("#cards-toolbar-estimate-choices label", has_text="With an estimate").click()
    wait_for(page, "estimate=with", 1)
    after = page.evaluate(ROW)
    t.check(page.evaluate("() => window.tunFiltersMark") == 1,
            "1280px: the choice changes the list without loading the page")
    t.check(not page.evaluate(POPOVER, "cards-toolbar-estimate-choices")["open"]
            and page.evaluate(FOCUS) == "cards-toolbar-estimate-button",
            f"1280px: one of several closes on the choice, the focus on its button: {page.evaluate(FOCUS)}")
    t.check(page.locator("#cards-toolbar-estimate-button").inner_text().strip() == "Estimate: With an estimate",
            f"1280px: its button says it: {page.locator('#cards-toolbar-estimate-button').inner_text()!r}")
    t.check(abs(after["toolbar"]["height"] - before["toolbar"]["height"]) <= 1
            and abs(after["list"] - before["list"]) <= 1 and after["weights"] == before["weights"],
            f"1280px: in use moves nothing below, at the same weight: {before['toolbar']['height']}→"
            f"{after['toolbar']['height']}, list {before['list']}→{after['list']}, {after['weights']}")
    t.check(rows(page) == 1 and total > 20, f"1280px: the list is filtered: {total} → {rows(page)}")
    edges = lambda m: [m["parts"][0]["right"], m["parts"][1]["left"], m["parts"][2]["left"]]
    t.check(all(abs(a - b) <= 1 for a, b in zip(edges(before), edges(after))),
            f"1280px: the search and the buttons up to the chosen one stay put: {edges(before)} → {edges(after)}")

    # Several of several: stays open, the focus on the box just ticked.
    page.locator("#cards-toolbar-estimate a.tun-list-toolbar-filter-clear").first.click()
    wait_for(page, "estimate=&", total)
    page.locator("#cards-toolbar-status-button").click()
    page.wait_for_timeout(250)
    page.locator("#cards-toolbar-status-choices label", has_text="Planned").click()
    wait_for(page, "status=planned", 3)
    p = page.evaluate(POPOVER, "cards-toolbar-status-choices")
    focused = page.evaluate("() => document.activeElement.value")
    t.check(p["open"] and focused == "planned",
            f"1280px: several of several stays open, the focus on the box ticked: {p['open']} {focused}")
    page.locator("#cards-toolbar-status-choices label", has_text="Done").click()
    wait_for(page, "status=done", 4)
    t.check(page.evaluate(POPOVER, "cards-toolbar-status-choices")["open"]
            and page.locator("#cards-toolbar-status-button").inner_text().strip() == "Status: 2",
            "1280px: a second tick, still open, its button counting two")
    m = page.evaluate(ROW)
    t.check(abs(m["parts"][0]["right"] - before["parts"][0]["right"]) <= 1
            and abs(m["parts"][1]["left"] - before["parts"][1]["left"]) <= 1,
            f"1280px: with it in use the search and its button stay put: {m['parts'][0]['right']}, {m['parts'][1]['left']}")
    page.keyboard.press("Escape")
    t.check(page.evaluate("() => window.tunFiltersMark") == 1, "1280px: still the same page")

    # Back goes a choice back, then off the list.
    page.go_back()
    wait_for(page, "status=planned", 3)
    t.check("status=done" not in page.evaluate("() => location.search"),
            f"Back returns to the state before: {page.evaluate('() => location.search')}")
    page.go_back()
    wait_for(page, "estimate=&", total)
    page.go_back()
    wait_for(page, "estimate=with", 1)
    t.check(rows(page) == 1, "and again, each choice a step")
    page.go_back()
    page.go_back()
    page.wait_for_function("() => location.pathname === '/graph'", timeout=10000)
    t.check(True, "and from the first state Back leaves the list")

    # Three in use: still one row, the toolbar and the list where they were.
    page.goto("/cards?q=&status=&status=planned&estimate=with&files=&files=true")
    m = page.evaluate(ROW)
    reset = page.evaluate("() => document.querySelector('#cards-toolbar .tun-list-toolbar-reset').getBoundingClientRect().toJSON()")
    filters = page.evaluate("() => { const f = document.querySelector('#cards-toolbar .tun-list-toolbar-filters'); return [f.scrollWidth, f.clientWidth]; }")
    tops = [p["top"] for p in m["parts"]]
    t.check(len(tops) == 4 and max(tops) - min(tops) <= 1
            and abs((reset["top"] + reset["bottom"]) / 2 - (m["parts"][0]["top"] + m["parts"][0]["bottom"]) / 2) <= 1,
            f"1280px: three filters in use and «Reset» on the search's row: {tops}, reset {reset['top']}")
    t.check(abs(m["toolbar"]["height"] - before["toolbar"]["height"]) <= 1 and abs(m["list"] - before["list"]) <= 1,
            f"1280px: the toolbar's height and the list's top as with none in use: {m['toolbar']['height']}, {m['list']}")
    t.check(filters[0] <= filters[1] + 1 and not page.evaluate(WIDE_PAGE),
            f"1280px: the filters fit their box, the page does not scroll sideways: {filters}")

    # The toggle and «Reset».
    page.goto("/cards?status=&status=planned")
    page.locator("#cards-toolbar-files .tun-list-toolbar-toggle").click()
    wait_for(page, "files=true", 1)
    t.check(page.locator("#cards-toolbar .tun-list-toolbar-reset").count() == 1,
            "a toggle applies at once, and two in use show «Reset»")
    page.locator("#cards-toolbar .tun-list-toolbar-reset").click()
    wait_for(page, "status=&", total)
    t.check("files=true" not in page.evaluate("() => location.search"), "«Reset» clears them")


def phone(t):
    for width in (390, 360, 320):
        for scheme in (("light", "dark") if width == 390 else ("light",)):
            page = t.phone(width=width, scheme=scheme)
            page.sign_in("employee:anna")
            page.goto("/cards")
            m = page.evaluate(ROW)
            t.check(len(m["parts"]) == 2, f"{width}px: the search and «Filters» alone: {len(m['parts'])}")
            t.check(not page.evaluate(WIDE_PAGE), f"{width}px {scheme}: the page does not scroll sideways")
            fold = page.locator("#cards-toolbar [data-tun-list-toolbar-fold]")
            fold.click()
            page.wait_for_timeout(500)
            box = page.evaluate("""() => { const d = document.querySelector('#cards-toolbar-sheet');
              const r = d.getBoundingClientRect(); const s = getComputedStyle(d);
              return {open: d.open, top: r.top, bottom: r.bottom, left: r.left, width: r.width,
                      tl: s.borderTopLeftRadius, bl: s.borderBottomLeftRadius,
                      dim: getComputedStyle(d, '::backdrop').backgroundColor,
                      dimOpacity: getComputedStyle(d, '::backdrop').opacity,
                      held: document.documentElement.style.overflow,
                      rows: [...d.querySelectorAll('.tun-list-toolbar-filter-heading, .tun-list-toolbar-toggle')]
                        .filter((e) => e.getBoundingClientRect().width > 0).length,
                      inside: [...d.querySelectorAll('*')].every((e) => e.getBoundingClientRect().right <= innerWidth + 0.5)}; }""")
            t.check(box["open"] and abs(box["bottom"] - 844) < 1 and abs(box["left"]) < 1
                    and abs(box["width"] - width) < 1 and box["tl"] == "12px" and box["bl"] == "0px"
                    and box["top"] >= 31.5,
                    f"{width}px {scheme}: «Filters» opens a sheet at the bottom: {box}")
            t.check(box["dim"] == ("rgba(0, 0, 0, 0.4)" if scheme == "light" else "rgba(0, 0, 0, 0.54)")
                    and box["dimOpacity"] == "1" and box["held"] == "hidden",
                    f"{width}px {scheme}: over the dim, the page held: {box}")
            t.check(box["rows"] == 3 and box["inside"], f"{width}px: a row per filter, inside the window: {box}")
            if width == 390 and scheme == "light":
                page.evaluate("() => { window.tunFiltersMark = 1; }")
                page.locator("#cards-toolbar-sheet label", has_text="Planned").click()
                wait_for(page, "status=planned", 3)
                still = page.evaluate("() => document.querySelector('#cards-toolbar-sheet').open")
                t.check(still and page.evaluate("() => document.activeElement.value") == "planned"
                        and page.evaluate("() => window.tunFiltersMark") == 1,
                        f"390px: a choice in the sheet applies at once, the sheet open, the focus kept: {still}")
                page.keyboard.press("Escape")
                page.wait_for_timeout(400)
                t.check(not page.evaluate("() => document.querySelector('#cards-toolbar-sheet').open")
                        and "Filters" in (page.evaluate(FOCUS) or "")
                        and page.evaluate("() => document.documentElement.style.overflow") != "hidden",
                        f"390px: Escape closes it, the focus back on «Filters»: {page.evaluate(FOCUS)}")
                t.check(fold.inner_text().replace("\n", " ").strip() == "Filters 1",
                        f"390px: «Filters» counts what is in use: {fold.inner_text()!r}")

    # One or two filters: a floating popover inside the window.
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.goto("/ui/list-toolbar")
        page.locator("#invoices-toolbar-state-button").click()
        page.wait_for_timeout(450)
        p = page.evaluate(POPOVER, "invoices-toolbar-state-choices")
        t.check(p["open"] and p["left"] >= 11.5 and p["right"] <= width - 11.5 and p["bottom"] <= 844 - 11.5
                and p["top"] >= 0 and p["radius"] == "12px" and p["radiusEnd"] == "12px",
                f"{width}px: a filter's popover is a floating sheet inside the window: {p}")
        t.check(p["dim"] == "rgba(0, 0, 0, 0.4)", f"{width}px: over the dim: {p['dim']}")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: the specimen does not scroll sideways")


def generated(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/customers")
    total = rows(page)
    page.locator(".tun-list-toolbar input[type=search]").fill("berg")
    page.locator(".tun-list-toolbar input[type=search]").press("Enter")
    wait_for(page, "query=berg", 1)
    t.check(total == 4, f"/customers, a generated list, searches with its operation's query: {total} → 1")


def without_javascript(t):
    page = t.phone(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/cards")
    shown = page.evaluate("""() => [...document.querySelectorAll('#cards-toolbar .tun-list-toolbar-filter-control, #cards-toolbar .tun-list-toolbar-toggle, #cards-toolbar [data-tun-list-toolbar-apply]')]
      .filter((e) => e.getBoundingClientRect().width > 0).length""")
    t.check(shown == 4, f"without JavaScript, 390px: the three filters and «Apply» show: {shown}")
    page.locator("#cards-toolbar-estimate-button").click()
    page.wait_for_timeout(300)
    page.locator("#cards-toolbar-estimate-choices label", has_text="With an estimate").click()
    with page.expect_navigation():
        page.locator("#cards-toolbar [data-tun-list-toolbar-apply]").click()
    t.check("estimate=with" in page.url and page.locator(".tun-table tbody tr").count() == 1,
            f"and «Apply» filters the list: {page.url}")


def run(t):
    desktop(t)
    phone(t)
    generated(t)
    without_javascript(t)
