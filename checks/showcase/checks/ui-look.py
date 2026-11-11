"""The look of the components in a browser, on the specimen: no square
corners on a box with an edge, choosing a tab moves nothing, chosen items
keep their weight, 44px targets on a phone, the destructive and icon-only
buttons, the focus ring and the chrome (spec/ui.md 2.1, 6)."""

# Every element of the examples with an edge on all four sides, and the
# corners it has square: a button group's parts are measured as the group,
# their outer corners only.
SQUARE_CORNERS = """() => {
  const found = [];
  const edged = (style) => ['Top', 'Right', 'Bottom', 'Left'].every((side) =>
    parseFloat(style[`border${side}Width`]) > 0 && style[`border${side}Style`] !== 'none'
    && !/rgba\\(.*, 0\\)$/.test(style[`border${side}Color`]));
  const corners = {TopLeft: 'start-start', TopRight: 'start-end', BottomLeft: 'end-start',
                   BottomRight: 'end-end'};
  for (const element of document.querySelectorAll('.tun-specimen-preview *')) {
    const box = element.getBoundingClientRect();
    if (box.width === 0 || box.height === 0) continue;
    const style = getComputedStyle(element);
    if (!edged(style)) continue;
    const group = element.parentElement.closest('.tun-button-group');
    const inGroup = group && element.parentElement === group;
    const parts = inGroup ? [...group.children].filter((part) => part.matches('.tun-button, span, label, output')) : [];
    const vertical = inGroup && group.dataset.orientation === 'vertical';
    for (const [corner, name] of Object.entries(corners)) {
      if (inGroup) {
        const top = corner.startsWith('Top'), left = corner.endsWith('Left');
        const first = element === parts[0], last = element === parts[parts.length - 1];
        const outer = vertical ? (top ? first : last) : (left ? first : last);
        if (!outer) continue;
      }
      if (parseFloat(style[`border${corner}Radius`]) === 0)
        found.push(`${element.className || element.tagName} ${name}`);
    }
  }
  return found;
}"""

WIDE_PAGE = "() => document.scrollingElement.scrollWidth > innerWidth + 1"

# Each tab's box within its list, which may scroll sideways to show the
# tab chosen.
TAB_BOXES = """(list) => [...list.querySelectorAll('[role=tab]')].map((tab) => {
  const box = tab.getBoundingClientRect(), inside = list.getBoundingClientRect();
  return [box.left - inside.left + list.scrollLeft, box.top - inside.top + list.scrollTop,
          box.width, box.height];
})"""

WEIGHTS = """(selector) => [...document.querySelectorAll(selector)].map((element) =>
  getComputedStyle(element).fontWeight)"""

# Each button's target: its box, and the invisible area of its ::before
# where it has one.
TARGETS = """() => [...document.querySelectorAll('.tun-specimen-preview .tun-button')]
  .filter((button) => button.getBoundingClientRect().width > 0)
  .map((button) => {
    const box = button.getBoundingClientRect();
    const area = getComputedStyle(button, '::before');
    let [width, height] = [box.width, box.height];
    if (area.content !== 'none' && area.position === 'absolute') {
      width = Math.max(width, box.width - parseFloat(area.left) - parseFloat(area.right));
      height = Math.max(height, box.height - parseFloat(area.top) - parseFloat(area.bottom));
    }
    return {name: button.getAttribute('aria-label') || button.textContent.trim(),
            size: button.dataset.size, width, height};
  })"""

BUTTONS = """() => {
  const style = (selector) => {
    const element = document.querySelector(selector);
    const computed = getComputedStyle(element);
    return {background: computed.backgroundColor, border: computed.borderTopColor,
            color: computed.color, image: computed.backgroundImage};
  };
  return {page: getComputedStyle(document.body).backgroundColor,
          text: getComputedStyle(document.body).color,
          destructive: style('.tun-specimen-preview .tun-button[data-variant=destructive]'),
          edit: style('.tun-specimen-preview .tun-button[aria-label=Edit]'),
          current: style('.tun-specimen-preview .tun-button[aria-current=page][data-size=icon]')};
}"""

FOCUSED = """() => {
  const element = document.activeElement;
  return element && element.matches('.tun-button')
    ? {name: element.textContent.trim(), shadow: getComputedStyle(element).boxShadow} : null;
}"""

TRANSPARENT = "rgba(0, 0, 0, 0)"


def rgb(text):
    return tuple(int(part) for part in text[text.index("(") + 1:text.index(")")].split(",")[:3])


def run(t):
    for width, scheme in ((390, "light"), (390, "dark"), (1280, "light"), (1280, "dark")):
        page = t.phone(width, 844, scheme=scheme) if width < 600 else t.desktop(scheme=scheme)
        page.goto("/ui")
        square = page.evaluate(SQUARE_CORNERS)
        t.check(not square, f"{width}px {scheme}: no box with an edge has a square corner: {square[:6]}")
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px {scheme}: the specimen does not scroll sideways")

    for width in (390, 1280):
        page = t.phone() if width < 600 else t.desktop()
        page.goto("/ui/tabs")
        lists = page.locator(".tun-specimen-preview [role=tablist]")
        moved = []
        for n in range(lists.count()):
            tablist = lists.nth(n)
            before = tablist.evaluate(TAB_BOXES)
            tabs = tablist.locator("[role=tab]")
            for i in range(tabs.count()):
                tabs.nth(i).click()
                after = tablist.evaluate(TAB_BOXES)
                if any(abs(a - b) > 0.5 for old, new in zip(before, after) for a, b in zip(old, new)):
                    moved.append((n, i))
        t.check(lists.count() > 0 and not moved,
                f"{width}px: choosing each tab leaves every tab where it was (moved: {moved})")
        weights = page.evaluate(WEIGHTS, ".tun-specimen-preview .tun-tabs-tab")
        t.check(len(set(weights)) == 1, f"{width}px: every tab, chosen or not, has one weight: {set(weights)}")

    page = t.desktop()
    page.goto("/ui/nav-list")
    weights = page.evaluate(WEIGHTS, ".tun-specimen-preview .tun-nav-list-link")
    current = page.locator(".tun-specimen-preview .tun-nav-list-link[aria-current]").count()
    t.check(current > 0 and len(set(weights)) == 1,
            f"the current nav-list entry has its siblings' weight: {set(weights)}")
    page.goto("/ui/pagination")
    weights = page.evaluate(WEIGHTS, ".tun-specimen-preview .tun-pagination-page .tun-button")
    t.check(len(set(weights)) == 1, f"the current page has its siblings' weight: {set(weights)}")

    page = t.phone()
    page.goto("/ui/button")
    small = [b for b in page.evaluate(TARGETS) if b["width"] < 43.5 or b["height"] < 43.5]
    t.check(not small, f"on a phone every button is a target of 44px each way: {small[:4]}")

    for scheme in ("light", "dark"):
        page = t.desktop(scheme=scheme)
        page.goto("/ui/button")
        m = page.evaluate(BUTTONS)
        red = rgb(m["destructive"]["color"])
        t.check(m["destructive"]["background"] == m["page"] and red[0] > red[1] + 80 and red[0] > red[2] + 60,
                f"{scheme}: «Delete» is red words on the page's ground: {m['destructive']}")
        t.check(m["edit"]["border"] == TRANSPARENT and m["edit"]["background"] == TRANSPARENT
                and m["edit"]["image"] == "none",
                f"{scheme}: the icon-only outline «Edit» has no frame or ground at rest: {m['edit']}")
        t.check(m["current"]["border"] != TRANSPARENT,
                f"{scheme}: the current «2» keeps its frame: {m['current']}")

    # In a group the parts share one frame: an icon-only outline part keeps
    # its edge and ground.
    page = t.desktop()
    page.goto("/ui/button-group")
    grouped = page.evaluate("""() => [...document.querySelectorAll(
        '.tun-specimen-preview .tun-button-group > .tun-button[data-variant=outline][data-size^=icon]')]
      .map((button) => [getComputedStyle(button).borderTopColor,
                        getComputedStyle(button).backgroundColor])""")
    t.check(grouped and all(edge != TRANSPARENT and ground != TRANSPARENT for edge, ground in grouped),
            f"an icon-only outline button in a group keeps its frame and ground: {grouped[:3]}")

    page = t.desktop()
    page.goto("/ui/button")
    page.locator(".tun-specimen-preview").first.click(position={"x": 2, "y": 2})
    focused = None
    for _ in range(4):
        page.keyboard.press("Tab")
        page.wait_for_timeout(400)  # the ring eases in over --duration-fast
        focused = page.evaluate(FOCUSED)
        if focused:
            break
    shadow = focused and focused["shadow"]
    t.check(bool(shadow) and "0px 0px 0px 2px" in shadow and "rgb(0, 95, 242) 0px 0px 0px 4px" in shadow,
            f"a focused button has the gap and the accent's ring: {shadow}")

    for scheme, chrome in (("light", (246, 246, 247)), ("dark", (17, 17, 19))):
        page = t.desktop(scheme=scheme)
        page.sign_in("admin:jonas")
        page.goto("/items")
        ground = page.evaluate("() => getComputedStyle(document.querySelector('.tun-app-shell-header')).backgroundColor")
        t.check(rgb(ground) == chrome, f"{scheme}: the sidebar stands on the chrome: {ground}")
        headings = page.evaluate("""() => [...document.querySelectorAll('.tun-nav-list-heading')].map((h) => {
          const style = getComputedStyle(h);
          return [h.textContent.trim(), style.textTransform, style.letterSpacing];
        })""")
        t.check(headings and all(h[1] == "none" and h[2] == "normal" for h in headings),
                f"{scheme}: the menu's headings are not in capitals: {headings}")
