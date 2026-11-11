"""The page's frame in a browser: the header's title and actions on one
row with the «More actions» menu on a phone, the shell and the theme
colour on the chrome, section links, the record's facts by spacing and
tabs on the page's ground (spec/ui.md 4.2, 6, 8)."""

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > innerWidth + 1"

# The Nth page header of the specimen's examples: its title's box, the
# boxes of the actions that show, their names, and the header's box.
HEADER = """(n) => {
  const header = document.querySelectorAll('.tun-specimen-preview .tun-page-header')[n];
  const box = (element) => {
    const r = element.getBoundingClientRect();
    return {left: r.left, right: r.right, top: r.top, bottom: r.bottom, width: r.width};
  };
  const shown = (element) => element.getBoundingClientRect().width > 0;
  const actions = header.querySelector('.tun-page-header-actions');
  const items = [...actions.querySelectorAll(':scope > *, :scope > .tun-page-header-more > *')]
    .filter((element) => !element.matches('.tun-page-header-more') && shown(element));
  const name = (element) => {
    const button = element.matches('.tun-button') ? element : element.querySelector('.tun-button');
    return (button.getAttribute('aria-label') || button.textContent).trim();
  };
  return {title: box(header.querySelector('.tun-page-header-title')), header: box(header),
          actions: items.map(box), names: items.map(name)};
}"""

def one_row(m):
    return (bool(m["actions"])
            and all(abs(a["top"] - m["actions"][0]["top"]) <= 1 for a in m["actions"])
            and all(a["top"] - m["title"]["top"] < 16 and a["left"] >= m["title"]["right"] - 1
                    for a in m["actions"])
            and all(a["left"] >= b["right"] - 1 for a, b in zip(m["actions"][1:], m["actions"])))


def at_right_edge(m):
    return abs(m["actions"][-1]["right"] - m["header"]["right"]) <= 1


def rgb(text):
    return tuple(int(part) for part in text[text.index("(") + 1:text.index(")")].split(",")[:3])


def hex_rgb(text):
    text = text.lstrip("#")
    return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))


# The top bar's ground and the theme-color meta that holds for the
# scheme the page shows.
THEME = """() => {
  const scheme = matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  const meta = document.querySelector(
    `meta[name=theme-color][media='(prefers-color-scheme: ${scheme})']`);
  return {bar: getComputedStyle(document.querySelector('.tun-app-shell-header')).backgroundColor,
          meta: meta && meta.content, scheme};
}"""

SECTION_LINKS = """() => {
  const nav = document.querySelector('.tun-specimen-preview .tun-section-links');
  const list = nav.querySelector('ul');
  const links = [...list.querySelectorAll('a')];
  return {height: list.getBoundingClientRect().height,
          linkHeight: links[0].getBoundingClientRect().height,
          scrollWidth: list.scrollWidth, clientWidth: list.clientWidth,
          current: links.filter((a) => a.getAttribute('aria-current')).map((a) => a.textContent),
          weights: [...new Set(links.map((a) => getComputedStyle(a).fontWeight))],
          sizes: [...new Set(links.map((a) => getComputedStyle(a).fontSize))],
          textLeft: links[0].getBoundingClientRect().left
            + parseFloat(getComputedStyle(links[0]).paddingLeft),
          navLeft: nav.getBoundingClientRect().left};
}"""

FACTS = """() => {
  const list = document.querySelector('.tun-specimen-preview .tun-summary-list');
  const rows = [...list.querySelectorAll('.tun-summary-list-row')];
  return {lefts: [...new Set(rows.map((row) => Math.round(row.getBoundingClientRect().left)))],
          beside: rows.every((row) => row.querySelector('dd').getBoundingClientRect().left
                                      > row.querySelector('dt').getBoundingClientRect().right),
          above: rows.every((row) => row.querySelector('dd').getBoundingClientRect().top
                                     >= row.querySelector('dt').getBoundingClientRect().bottom - 1),
          edges: rows.some((row) => {
            const style = getComputedStyle(row);
            return ['Top', 'Bottom'].some((side) => parseFloat(style[`border${side}Width`]) > 0);
          })};
}"""

SHELL_EDGES = """() => {
  const preview = document.querySelector('.tun-specimen-preview .tun-app-shell');
  const left = (selector) => Math.round(preview.querySelector(selector).getBoundingClientRect().left);
  return [left('.tun-page-header'), left('.tun-section'), left('.tun-summary-list')];
}"""

TABS = """() => {
  const chosen = document.querySelector('.tun-specimen-preview [role=tab][aria-selected=true]');
  const list = chosen.closest('.tun-tabs-list');
  const links = [...document.querySelectorAll('.tun-specimen-preview nav.tun-tabs[data-variant=line] .tun-tabs-tab')]
    .map((tab) => tab.getBoundingClientRect());
  const gaps = links.slice(1).map((box, i) => Math.round(box.left - links[i].right));
  return {chosen: getComputedStyle(chosen).backgroundColor,
          list: getComputedStyle(list).backgroundColor,
          page: getComputedStyle(document.body).backgroundColor, gaps};
}"""


def headers_on_a_phone(t):
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.goto("/ui/page-header")
        for n, label in ((2, "a long title"), (3, "a title of one long word")):
            m = page.evaluate(HEADER, n)
            t.check(one_row(m), f"{width}px, {label}: the title and the actions on one row: {m}")
            t.check(at_right_edge(m), f"{width}px, {label}: the last action at the right edge")
            t.check(m["title"]["right"] <= m["header"]["right"] and m["title"]["width"] > 40,
                    f"{width}px, {label}: the title keeps its room ({m['title']['width']:.0f}px)")
        m = page.evaluate(HEADER, 2)
        t.check(m["names"] == ["More actions", "Send to the customer"],
                f"{width}px: «More actions» and the filled action, nothing else: {m['names']}")
        page.locator(".tun-specimen-preview .tun-page-header").nth(2) \
            .locator("[aria-label='More actions']").click()
        page.wait_for_timeout(300)
        items = page.evaluate("""() => [...document.querySelectorAll(
          '.tun-page-header-more [popover]')].filter((menu) => menu.matches(':popover-open'))
          .flatMap((menu) => [...menu.querySelectorAll('[role=menuitem]')]
                              .map((item) => item.textContent.trim()))""")
        t.check(items == ["Preview", "Withdraw"], f"{width}px: the menu holds the folded: {items}")
        m = page.evaluate(HEADER, 0)
        t.check(m["names"] == ["More actions", "New order"] and one_row(m) and at_right_edge(m),
                f"{width}px: «Ole Hansen Ltd» folds «Edit» and keeps «New order»: {m['names']}")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: the page does not scroll sideways")

    plain = t.phone(javascript=False)
    plain.goto("/ui/page-header")
    plain.locator(".tun-specimen-preview .tun-page-header").nth(2) \
        .locator("[aria-label='More actions']").click()
    plain.wait_for_timeout(300)
    opened = plain.evaluate("""() => [...document.querySelectorAll('.tun-page-header-more [popover]')]
      .some((menu) => menu.matches(':popover-open') && menu.getBoundingClientRect().height > 0)""")
    t.check(opened, "without JavaScript the menu opens")


def headers_on_a_desktop(t):
    page = t.desktop()
    page.goto("/ui/page-header")
    m = page.evaluate(HEADER, 2)
    t.check(m["names"] == ["Preview", "Withdraw", "Send to the customer"],
            f"1280px: every action shows, the filled last, no menu: {m['names']}")
    t.check(one_row(m) and at_right_edge(m), "1280px: on the title's row at the right edge")


def items_on_a_phone(t):
    for width in (390, 320):
        page = t.phone(width=width)
        page.sign_in("employee:anna")
        page.goto("/items")
        names = page.evaluate("""() => [...document.querySelectorAll(
          '.tun-page-header-actions > *')].filter((e) => e.getBoundingClientRect().width > 0)
          .map((e) => (e.getAttribute('aria-label') || e.textContent).trim())""")
        t.check(names == ["Search", "Filter", "New item"],
                f"{width}px: /items keeps its three actions: {names}")


def chrome(t):
    for scheme in ("light", "dark"):
        page = t.phone(scheme=scheme)
        page.sign_in("employee:anna")
        page.goto("/items")
        m = page.evaluate(THEME)
        t.check(m["meta"] and rgb(m["bar"]) == hex_rgb(m["meta"]),
                f"{scheme}: the top bar's ground is the theme colour: {m}")
        page = t.desktop(scheme=scheme)
        page.sign_in("employee:anna")
        page.goto("/items")
        ground = page.evaluate(
            "() => getComputedStyle(document.querySelector('.tun-app-shell-header')).backgroundColor")
        chrome_colour = (246, 246, 247) if scheme == "light" else (17, 17, 19)
        t.check(rgb(ground) == chrome_colour, f"{scheme}: the sidebar is the chrome: {ground}")


def section_links(t):
    page = t.phone()
    page.goto("/ui/section-links")
    m = page.evaluate(SECTION_LINKS)
    t.check(m["height"] < m["linkHeight"] * 1.5 + 10, f"the row is one line ({m['height']:.0f}px)")
    t.check(m["scrollWidth"] > m["clientWidth"], "it is wider than its box at 390px")
    t.check(abs(m["textLeft"] - m["navLeft"]) <= 1,
            f"the first link's words at the row's edge ({m['textLeft']:.0f}, {m['navLeft']:.0f})")
    page.evaluate("() => document.querySelector('.tun-specimen-preview .tun-section-links ul').scrollLeft = 200")
    t.check(page.evaluate("() => document.querySelector('.tun-specimen-preview .tun-section-links ul').scrollLeft") > 0,
            "the row scrolls sideways in its box")
    t.check(not page.evaluate(WIDE_PAGE), "and the page does not")
    t.check(page.evaluate(SECTION_LINKS)["current"] == ["Details"], "at first «Details» is marked")
    # Room below the specimen, so its third section can reach the top.
    page.evaluate("() => { document.body.style.paddingBottom = '2000px'; }")
    page.evaluate("() => scrollTo(0, document.getElementById('order-delivery').getBoundingClientRect().top + scrollY)")
    target = page.evaluate("() => scrollY")
    page.wait_for_timeout(200)
    m = page.evaluate(SECTION_LINKS)
    t.check(m["current"] == ["Delivery"], f"scrolled to «Delivery», its link is marked: {m['current']}")
    t.check(abs(page.evaluate("() => scrollY") - target) < 1,
            "marking it scrolls the row, never the page")
    t.check(len(m["weights"]) == 1 and len(m["sizes"]) == 1,
            f"at the others' weight and size: {m['weights']} {m['sizes']}")
    page.evaluate("() => { document.body.style.paddingBottom = ''; }")
    page.locator(".tun-specimen-preview .tun-section-links a", has_text="History").click()
    page.wait_for_timeout(300)
    t.check(page.evaluate(SECTION_LINKS)["current"] == ["History"], "a followed link is marked")

    plain = t.phone(javascript=False)
    plain.goto("/ui/section-links")
    t.check(plain.evaluate(SECTION_LINKS)["current"] == [], "without JavaScript none is marked")
    plain.locator(".tun-specimen-preview .tun-section-links a", has_text="Invoices").click()
    plain.wait_for_timeout(300)
    t.check(plain.evaluate("() => scrollY") > 100, "and a link moves the page")


def facts(t):
    page = t.phone()
    page.goto("/ui/summary-list")
    m = page.evaluate(FACTS)
    t.check(len(m["lefts"]) == 1 and m["beside"], f"390px: one column, the label beside: {m}")
    t.check(not m["edges"], "390px: no line between the facts")
    page = t.desktop()
    page.goto("/ui/summary-list")
    m = page.evaluate(FACTS)
    t.check(len(m["lefts"]) == 2 and m["above"], f"1280px: two columns, the label above: {m}")
    t.check(not m["edges"], "1280px: no line between the facts")
    for name, page in (("390px", t.phone()), ("1280px", t.desktop())):
        page.goto("/ui/app-shell")
        lefts = page.evaluate(SHELL_EDGES)
        t.check(len(set(lefts)) == 1, f"{name}: the header, a section and the facts line up: {lefts}")


def tabs(t):
    for scheme in ("light", "dark"):
        page = t.phone(scheme=scheme)
        page.goto("/ui/tabs")
        m = page.evaluate(TABS)
        t.check(m["chosen"] != m["page"] and m["chosen"] != m["list"],
                f"{scheme}: the chosen tab's ground is unlike the page's and the strip's: {m}")
        t.check(m["gaps"] and max(m["gaps"]) - min(m["gaps"]) <= 1,
                f"{scheme}: line tabs side by side, evenly: {m['gaps']}")


def run(t):
    headers_on_a_phone(t)
    headers_on_a_desktop(t)
    items_on_a_phone(t)
    chrome(t)
    section_links(t)
    facts(t)
    tabs(t)
