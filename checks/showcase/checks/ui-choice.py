"""Choosing one record among many by typing, on the showcase with 405
customers and on the specimen: asking after the pause, an overtaken answer
dropped, the keys, Enter before the answer, the id posted, the clear, where
the list opens and how it moves, the phone's sheet above a keyboard, the
given options narrowed by the search's fold, the cards' :choice filter in
the address and in the «Filters» sheet, and the field and the filter
without JavaScript (spec/ui.md 6, choice-input, list-toolbar)."""

import re
import time

SCENARIO = "choices"

# Wider than the window: a page wider than its device's width widens the
# layout viewport too, so innerWidth would grow with it.
WIDE_PAGE = "() => document.scrollingElement.scrollWidth > document.documentElement.clientWidth + 1"

# The state of the choice whose root holds the element SELECTOR.
STATE = """(selector) => {
  const root = document.querySelector(selector).closest('[data-tun-choice]');
  const field = root.querySelector('[data-tun-choice-field]');
  const list = root.querySelector('[data-tun-choice-list] [role=listbox]');
  const options = [...list.querySelectorAll('[role=option]')].filter((o) => !o.hidden);
  const popover = field.closest('[popover]');
  let open = false;
  try { open = popover.matches(':popover-open'); } catch (e) {}
  const active = options.find((o) => o.getAttribute('aria-selected') === 'true');
  const select = root.querySelector('[data-tun-choice-select]');
  const text = root.querySelector('[data-tun-choice-text]');
  const clear = root.querySelector('[data-tun-choice-clear]');
  const none = list.querySelector('.tun-choice-options-none');
  return {open, value: field.value, answered: list.getAttribute('data-tun-choice-query'),
          texts: options.map((o) => o.querySelector('.tun-choice-options-text').textContent),
          values: options.map((o) => o.dataset.value),
          active: active ? options.indexOf(active) : -1,
          activedescendant: field.getAttribute('aria-activedescendant'),
          activeId: active ? active.id : null,
          more: list.querySelector('.tun-choice-options-more')?.textContent ?? null,
          none: none && !none.hidden ? none.textContent : null,
          chosen: select.value, shown: text ? text.textContent : null,
          clear: clear ? !clear.hidden : null,
          focus: document.activeElement?.id ?? null,
          ready: root.hasAttribute('data-tun-ready')};
}"""

BOX = """(selector) => {
  const r = document.querySelector(selector).getBoundingClientRect();
  return {top: r.top, bottom: r.bottom, left: r.left, right: r.right, width: r.width,
          height: r.height};
}"""

OPTION_STYLES = """(selector) => {
  const root = document.querySelector(selector).closest('[data-tun-choice]');
  return [...root.querySelectorAll('[data-tun-choice-list] [role=option]')]
    .filter((o) => !o.hidden).map((o) => {
      const s = getComputedStyle(o);
      return {selected: o.getAttribute('aria-selected'), ground: s.backgroundColor,
              ring: s.boxShadow, weight: s.fontWeight, size: s.fontSize, padding: s.padding,
              height: o.getBoundingClientRect().height};
    });
}"""

MOTION = """(id) => {
  const p = document.getElementById(id);
  const s = getComputedStyle(p);
  return {property: s.transitionProperty, duration: s.transitionDuration,
          dim: getComputedStyle(p, '::backdrop').backgroundColor};
}"""

# A keyboard over the lower part of the window: the visual viewport shrinks
# to HEIGHT, as Safari and Chrome on Android report it (as ui-sheets does).
KEYBOARD = """(height) => {
  if (height === null) delete window.visualViewport.height;
  else Object.defineProperty(window.visualViewport, 'height', {configurable: true, get: () => height});
  window.visualViewport.dispatchEvent(new Event('resize'));
  return document.documentElement.style.getPropertyValue('--tun-visual-bottom');
}"""

UNREGISTER = """async () => {
  for (const registration of await navigator.serviceWorker.getRegistrations())
    await registration.unregister();
}"""

FORM = "#card-customer-trigger"
FIELD = "#card-customer-search"
TOOLBAR_BUTTON = "#cards-toolbar-customer-button"
TOOLBAR_FIELD = "#cards-toolbar-customer-search"
CUSTOMERS = 405


def state(page, selector=FIELD):
    return page.evaluate(STATE, selector)


def wait_answered(page, text, selector=FIELD, timeout=4000):
    page.wait_for_function(
        """([selector, text]) => document.querySelector(selector).closest('[data-tun-choice]')
             .querySelector('[data-tun-choice-list] [role=listbox]')
             ?.getAttribute('data-tun-choice-query') === text""",
        arg=[selector, text], timeout=timeout)


def open_form(t, make=None, **options):
    page = (make or t.desktop)(**options)
    page.sign_in("employee:anna")
    page.goto("/items/new")
    page.evaluate(UNREGISTER)
    page.goto("/items/new")
    page.wait_for_function("() => document.querySelector('[data-tun-choice][data-tun-ready]')")
    return page


def asking(t):
    page = open_form(t)
    asked = []
    page.on("request", lambda request: asked.append((time.monotonic(), request.url))
            if "/cards/customers" in request.url else None)
    page.locator(FORM).click()
    wait_answered(page, "")
    s = state(page)
    t.check(s["open"] and s["focus"] == "card-customer-search",
            f"the button opens the list with the focus in its text field: {s['open']} {s['focus']}")
    t.check(len(s["texts"]) == 20 and s["more"] == f"{CUSTOMERS - 20} more. Type to narrow them.",
            f"it asks once for an empty text: 20 options and the rest counted: {len(s['texts'])} {s['more']}")
    t.check(len(asked) == 1, f"one request on opening: {[u for _, u in asked]}")
    asked.clear()
    # The page's own clock: when each key's input came, and each request.
    page.evaluate("""() => {
      window.tunInputs = []; window.tunAsks = [];
      document.addEventListener('input', () => tunInputs.push(performance.now()), true);
      document.addEventListener('htmx:before:request', () => tunAsks.push(performance.now()), true);
    }""")
    page.keyboard.type("bjorn", delay=40)
    last_key = time.monotonic()
    wait_answered(page, "bjorn")
    took = (time.monotonic() - last_key) * 1000
    clock = page.evaluate("() => ({inputs: tunInputs, asks: tunAsks})")
    gaps = [round(ask - clock["inputs"][-1]) for ask in clock["asks"]]
    t.check(len(asked) == 1 and "q=bjorn" in asked[0][1] and len(gaps) == 1 and gaps[0] >= 145,
            f"one request, no sooner than 150 ms after the last key: {gaps} {[u for _, u in asked]}")
    s = state(page)
    t.check(s["texts"][:1] == ["Bjørn Åsen"] and took < 1500,
            f"«bjorn» lists «Bjørn Åsen» first, {took:.0f} ms after the last key: {s['texts'][:3]}")
    t.check(s["active"] == 0 and s["activedescendant"] == s["activeId"],
            f"and makes it active: {s['active']} {s['activedescendant']}")


def overtaken(t):
    page = open_form(t)
    held = []
    page.route(re.compile(r".*/cards/customers\?q=anna$"), lambda route: held.append(route))
    page.locator(FORM).click()
    wait_answered(page, "")
    page.keyboard.type("anna")
    page.wait_for_timeout(500)
    t.check(len(held) == 1, f"the answer for «anna» is held: {len(held)}")
    page.keyboard.type(" berg")
    wait_answered(page, "anna berg")
    later = state(page)["texts"]
    stale = ('<ul class="tun-choice-options" role="listbox" data-tun-choice-query="anna">'
             '<li class="tun-choice-options-option" role="option" aria-selected="false" '
             'data-value="cus_stale"><span class="tun-choice-options-text">Stale</span></li></ul>')
    try:
        held[0].fulfill(status=200, content_type="text/html", body=stale)
        answered = "answered late"
    except Exception as error:
        answered = f"cancelled by htmx ({type(error).__name__})"
    page.wait_for_timeout(600)
    s = state(page)
    t.check(s["answered"] == "anna berg" and s["texts"] == later and "Stale" not in s["texts"],
            f"the earlier answer ({answered}) never replaces the later one: {s['texts']}")
    page.unroute(re.compile(r".*/cards/customers\?q=anna$"))

    page.route(re.compile(r".*/cards/customers\?q=broken$"),
               lambda route: route.fulfill(status=500, content_type="text/html",
                                           body="<!doctype html><p>Server error</p>"))
    page.fill(FIELD, "")
    page.keyboard.type("broken")
    page.wait_for_timeout(800)
    s = state(page)
    t.check(s["none"] == "The choices could not be loaded. Try again.",
            f"a failed answer says so: {s['none']}")


def keys(t):
    page = open_form(t)
    page.locator(FORM).click()
    wait_answered(page, "")
    page.keyboard.type("anna")
    wait_answered(page, "anna")
    s = state(page)
    count = len(s["texts"])
    t.check(count == 20 and s["active"] == 0, f"«anna» finds 20, the first active: {count} {s['active']}")
    page.keyboard.press("ArrowDown")
    page.keyboard.press("ArrowDown")
    s = state(page)
    t.check(s["active"] == 2 and s["activedescendant"] == s["activeId"],
            f"↓ ↓ makes the third active: {s['active']} {s['activedescendant']}")
    styles = page.evaluate(OPTION_STYLES, FIELD)
    active = [o for o in styles if o["selected"] == "true"]
    others = [o for o in styles if o["selected"] != "true"]
    t.check(len(active) == 1 and active[0]["ground"] != others[0]["ground"]
            and "inset" in active[0]["ring"],
            f"the active option has its ground and frame: {active} {others[:1]}")
    t.check(all(o[k] == others[0][k] for o in styles for k in ("weight", "size", "padding", "height")),
            f"at the others' weight, size, padding and height: {styles[:3]}")
    page.keyboard.press("End")
    t.check(state(page)["active"] == count - 1, "End goes to the last")
    page.keyboard.press("Home")
    t.check(state(page)["active"] == 0, "Home to the first")
    page.keyboard.press("ArrowUp")
    t.check(state(page)["active"] == count - 1, "↑ from the first goes round to the last")
    page.keyboard.press("ArrowDown")
    page.keyboard.press("ArrowDown")
    s = state(page)
    name, value = s["texts"][1], s["values"][1]
    page.keyboard.press("Enter")
    page.wait_for_timeout(300)
    s = state(page)
    t.check(not s["open"] and s["shown"] == name and s["chosen"] == value
            and s["focus"] == "card-customer-trigger" and s["clear"],
            f"Enter chooses it: the button shows {name}, the list closes, the focus on the button: {s}")
    page.locator(FORM).click()
    page.wait_for_timeout(300)
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    s = state(page)
    t.check(not s["open"] and s["chosen"] == value and s["focus"] == "card-customer-trigger",
            f"Escape closes without choosing, the focus back on the button: {s['focus']}")

    # The form posts the id.
    page.fill("input[name=title]", "A card for a customer")
    page.locator("form button[type=submit]:has-text('Report the item')").click()
    page.wait_for_url(re.compile(r"/items/crd_"), timeout=5000)
    shown = page.locator(".tun-summary-list").inner_text()
    t.check(name in shown, f"the posted form carried the id, and the card is for {name}: {shown}")

    # The clear empties it.
    page = open_form(t)
    page.locator(FORM).click()
    wait_answered(page, "")
    page.locator(f"{FIELD} ~ [data-tun-choice-list] [role=option]").first.click()
    page.wait_for_timeout(300)
    chosen = state(page)
    page.locator("[data-tun-choice-clear]").click()
    page.wait_for_timeout(200)
    s = state(page)
    t.check(chosen["chosen"].startswith("cus_") and s["chosen"] == "" and s["shown"] == "Choose"
            and not s["clear"] and s["focus"] == "card-customer-trigger",
            f"a click chooses ({chosen['shown']}), and the clear empties it: {s}")
    with page.expect_post("/items/new") as post:
        page.locator("form button[type=submit]:has-text('Report the item')").click()
    t.check('name="customer"\r\n\r\n\r\n' in post.body,
            "the form posts the customer empty")


def enter_before_the_answer(t):
    page = open_form(t)
    held = []
    page.route(re.compile(r".*/cards/customers\?q=bjorn(%20|\+)ase$"),
               lambda route: held.append(route))
    page.locator(FORM).click()
    wait_answered(page, "")
    page.keyboard.type("bjorn ase")
    page.keyboard.press("Enter")
    page.wait_for_timeout(500)
    s = state(page)
    t.check(len(held) == 1 and s["open"] and s["chosen"] == "",
            f"an Enter before the answer chooses nothing yet: {len(held)} {s['open']} {s['chosen']}")
    held[0].continue_()
    page.wait_for_timeout(800)
    s = state(page)
    t.check(not s["open"] and s["shown"] == "Bjørn Åsen",
            f"and then its first option, not the earlier answer's: {s['shown']}")


def placement(t):
    page = open_form(t)
    page.locator(FORM).click()
    wait_answered(page, "")
    page.wait_for_timeout(300)
    field = page.evaluate(BOX, FORM)
    box = page.evaluate(BOX, "#card-customer-popover")
    t.check(0 <= box["top"] - field["bottom"] <= 8 and abs(box["left"] - field["left"]) < 1,
            f"1280px: the list stands under the field: {field} {box}")
    motion = page.evaluate(MOTION, "card-customer-popover")
    t.check("opacity" in motion["property"] and "translate" in motion["property"]
            and "transform" not in motion["property"] and motion["duration"].startswith("0.15s"),
            f"it opens by opacity and translate over --duration-fast: {motion}")
    page.keyboard.press("Escape")
    page.wait_for_timeout(50)
    motion = page.evaluate(MOTION, "card-customer-popover")
    t.check(motion["duration"].startswith("0.16s"), f"and leaves over --duration-close: {motion}")

    page = open_form(t, height=420)
    field = page.evaluate(BOX, FORM)
    page.locator(FORM).click()
    wait_answered(page, "")
    page.wait_for_timeout(300)
    box = page.evaluate(BOX, "#card-customer-popover")
    search = page.evaluate(BOX, FIELD)
    listed = page.evaluate(BOX, "#card-customer-list-box")
    t.check(0 <= field["top"] - box["bottom"] <= 8 and search["top"] > listed["top"],
            f"near the window's bottom it opens above, the text field last: {field} {box} {search}")


def phone(t):
    # On the specimen, whose asked example asks a real address: the
    # showcase's «New item» holds a file field wider than a 320px window.
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.goto("/ui/choice-input")
        page.wait_for_function("() => document.querySelector('[data-tun-choice][data-tun-ready]')")
        page.locator("#specimen-asked-trigger").tap()
        wait_answered(page, "", "#specimen-asked-search")
        page.wait_for_timeout(400)
        box = page.evaluate(BOX, "#specimen-asked-popover")
        dim = page.evaluate(MOTION, "specimen-asked-popover")["dim"]
        t.check(abs(box["left"] - 12) < 1 and abs(box["right"] - (width - 12)) < 1
                and box["bottom"] <= 844 - 12 and box["top"] >= 0,
                f"{width}px: a floating sheet inside the window, 12px from its sides: {box}")
        t.check(dim not in ("rgba(0, 0, 0, 0)", "transparent"), f"{width}px: over the dim: {dim}")
        t.check(page.evaluate("() => document.activeElement.id") == "specimen-asked-search",
                f"{width}px: the focus in its text field")
        top = round(844 * 0.6)
        inset = page.evaluate(KEYBOARD, top)
        page.wait_for_timeout(200)
        shrunk = page.evaluate(BOX, "#specimen-asked-popover")
        search = page.evaluate(BOX, "#specimen-asked-search")
        listed = page.evaluate(BOX, "#specimen-asked-list-box")
        t.check(inset == f"{844 - top}px" and shrunk["bottom"] <= top and search["bottom"] <= top
                and listed["bottom"] <= top and shrunk["top"] >= 0,
                f"{width}px: above a keyboard the sheet, its text field and its list stay in sight: "
                f"{inset} {shrunk} {search} {listed}")
        page.keyboard.type("bjorn")
        wait_answered(page, "bjorn", "#specimen-asked-search")
        page.locator("#specimen-asked-list-box [role=option]").first.tap()
        page.wait_for_timeout(400)
        s = state(page, "#specimen-asked-search")
        t.check(s["shown"] == "Bjørn Åsen" and not s["open"], f"{width}px: a tap chooses: {s['shown']}")
        page.evaluate(KEYBOARD, None)
        t.check(not page.evaluate(WIDE_PAGE), f"{width}px: the page does not scroll sideways")


def given(t):
    page = t.desktop()
    page.goto("/ui/choice-input")
    page.wait_for_function("() => document.querySelector('#specimen-given-trigger')")
    page.locator("#specimen-given-trigger").click()
    page.wait_for_timeout(300)
    field = "#specimen-given-search"
    all_texts = state(page, field)["texts"]
    for text, expected in (("bjorn ase", ["Bjørn Åsen"]), ("ase", ["Bjørn Åsen"]),
                           ("aasen", ["Bjørn Åsen"]), ("hansen kari", ["Kari Hansen"]),
                           ("hansen", ["Hansen Plumbing", "Kari Hansen"])):
        page.fill(field, "")
        page.keyboard.type(text)
        texts = state(page, field)["texts"]
        t.check(texts == expected, f"given options: «{text}» leaves {expected}: {texts}")
    page.fill(field, "")
    page.keyboard.type("zebra")
    s = state(page, field)
    t.check(not s["texts"] and s["none"] == "No match", f"«zebra» shows «No match»: {s['none']}")
    page.fill(field, "")
    page.keyboard.type("ø")
    page.fill(field, "")
    page.keyboard.press("Backspace")
    s = state(page, field)
    t.check(s["texts"] == all_texts, f"an empty text shows them all, in the order given: {s['texts']}")
    page.keyboard.press("ArrowDown")
    page.keyboard.press("ArrowDown")
    page.keyboard.press("Enter")
    page.wait_for_timeout(300)
    s = state(page, field)
    t.check(s["chosen"] == "cus_2" and s["shown"] == "Hansen Plumbing",
            f"↓ ↓ Enter chooses the second, its id the select's value: {s['chosen']} {s['shown']}")

    # The specimen's asked example asks a real address.
    page.locator("#specimen-asked-trigger").click()
    wait_answered(page, "", "#specimen-asked-search")
    page.keyboard.type("bjorn ase")
    wait_answered(page, "bjorn ase", "#specimen-asked-search")
    t.check(state(page, "#specimen-asked-search")["texts"] == ["Bjørn Åsen"],
            "the specimen's asked example finds its made-up customers")
    page.keyboard.press("Escape")
    for width, make in ((390, t.phone), (1280, t.desktop)):
        p = make()
        p.goto("/ui/choice-input")
        p.wait_for_timeout(300)
        t.check(not p.evaluate(WIDE_PAGE), f"{width}px: the specimen does not scroll sideways")


def toolbar(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.evaluate(UNREGISTER)
    page.goto("/cards")
    page.evaluate("() => { window.tunChoiceMark = 1; }")
    page.locator(TOOLBAR_BUTTON).click()
    wait_answered(page, "", TOOLBAR_FIELD)
    s = state(page, TOOLBAR_FIELD)
    t.check(s["open"] and s["focus"] == "cards-toolbar-customer-search",
            f"the filter's button opens its list, the focus in its field: {s['open']} {s['focus']}")
    page.keyboard.type("bjorn")
    wait_answered(page, "bjorn", TOOLBAR_FIELD)
    chosen = state(page, TOOLBAR_FIELD)["values"][0]
    page.keyboard.press("Enter")
    page.wait_for_url(re.compile(r"customer=cus_"), timeout=5000)
    page.wait_for_timeout(600)
    titles = page.locator(".tun-table tbody tr td:first-child").all_inner_texts()
    focus = page.evaluate("() => document.activeElement?.id")
    button = page.locator(TOOLBAR_BUTTON).inner_text()
    t.check(f"customer={chosen}" in page.url and sorted(titles) == ["Lights for the summer party",
                                                                   "Sound for the summer party"],
            f"Enter puts the id in the address and the list shows that customer's cards: {page.url} {titles}")
    t.check(page.evaluate("() => window.tunChoiceMark === 1"), "without loading the page")
    t.check(focus == "cards-toolbar-customer-button" and "Customer: Bjørn Åsen" in button,
            f"the popover closes, the focus on its button, which says the customer: {focus} {button}")

    page.goto(f"/cards?customer={chosen}")
    button = page.locator(TOOLBAR_BUTTON).inner_text()
    t.check("Customer: Bjørn Åsen" in button, f"an address written for a :one filter reads the same: {button}")


def sheet(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.evaluate(UNREGISTER)
    page.goto("/cards")
    page.locator("[data-tun-list-toolbar-fold]").tap()
    page.wait_for_timeout(500)
    field = page.locator(TOOLBAR_FIELD)
    t.check(field.is_visible(), "390px: the «Filters» sheet holds the customer's text field in place")
    field.tap()
    page.keyboard.type("nordvik")
    wait_answered(page, "nordvik", TOOLBAR_FIELD)
    list_box = page.evaluate(BOX, "#cards-toolbar-customer-list-box")
    t.check(list_box["height"] <= 15 * 16 + 1, f"its list scrolls in a box of at most 15rem: {list_box}")
    page.locator(f"{TOOLBAR_FIELD} ~ [data-tun-choice-list] [role=option]").first.tap()
    page.wait_for_url(re.compile(r"customer=cus_"), timeout=5000)
    page.wait_for_timeout(600)
    opened = page.evaluate("""() => ({
      sheet: document.querySelector('#cards-toolbar-sheet').open,
      popovers: [...document.querySelectorAll('[popover]')].filter((p) => {
        try { return p.matches(':popover-open'); } catch (e) { return false; } }).length})""")
    titles = page.locator(".tun-table tbody tr td:first-child").all_inner_texts()
    t.check(opened["sheet"] and opened["popovers"] == 0 and titles == ["Bread van signage"],
            f"a choice applies at once, the sheet open, no popover over it: {opened} {titles}")
    inside = []
    for _ in range(12):
        page.keyboard.press("Tab")
        inside.append(page.evaluate(
            "() => !!document.activeElement.closest('#cards-toolbar-sheet')"))
    t.check(all(inside), f"Tab stays inside the sheet: {inside}")
    page.keyboard.press("Escape")
    page.wait_for_timeout(500)
    closed = page.evaluate("""() => ({sheet: document.querySelector('#cards-toolbar-sheet').open,
      fold: document.activeElement.hasAttribute('data-tun-list-toolbar-fold')})""")
    t.check(not closed["sheet"] and closed["fold"], f"Escape closes it, the focus on «Filters»: {closed}")
    for width in (390, 360, 320):
        p = t.phone(width=width)
        p.sign_in("employee:anna")
        p.goto("/cards")
        t.check(not p.evaluate(WIDE_PAGE), f"{width}px: /cards does not scroll sideways")


def without_javascript(t):
    page = t.desktop(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/items/new")
    select = page.locator("select#card-customer")
    t.check(select.is_visible() and not page.locator(FORM).is_visible(),
            "without JavaScript the field is a select")
    page.fill("#card-customer-find", "bjorn")
    page.locator("button[name=tun-find]").click()
    page.wait_for_load_state()
    labels = page.locator("select#card-customer option").all_inner_texts()
    found = page.locator(".tun-choice-input-found").inner_text()
    t.check("Bjørn Åsen" in labels and found == "1 found" and "/items/new" in page.url,
            f"«Find» shows the form again with the matches in the select: {labels} {found}")
    t.check(page.locator(".tun-alert, .tun-error-summary").count() == 0, "nothing was saved or refused")
    select.select_option(label="Bjørn Åsen")
    page.fill("input[name=title]", "Found without scripts")
    page.locator("button[type=submit]:has-text('Report the item')").click()
    page.wait_for_url(re.compile(r"/items/crd_"), timeout=5000)
    t.check("Bjørn Åsen" in page.locator(".tun-summary-list").inner_text(),
            "and saving posts the chosen customer's id")

    page = t.desktop(javascript=False)
    page.goto("/ui/choice-input")
    values = page.locator("select#specimen-given option").evaluate_all(
        "(options) => options.map((o) => o.value)")
    t.check(page.locator("select#specimen-given").is_visible() and values[:2] == ["", "cus_1"],
            f"the given options are a select of their ids: {values[:3]}")

    page = t.phone(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.locator(TOOLBAR_BUTTON).click()
    page.wait_for_timeout(300)
    t.check(page.locator("#cards-toolbar-customer-choice").is_visible()
            and page.locator("#cards-toolbar-customer-find").is_visible(),
            "the filter's popover opens with its select and its «Find» field")
    page.fill("#cards-toolbar-customer-find", "nordvik")
    page.locator("[data-tun-list-toolbar-apply]").click()
    page.wait_for_url(re.compile(r"customer-find=nordvik"), timeout=5000)
    page.locator(TOOLBAR_BUTTON).click()
    page.locator("#cards-toolbar-customer-choice").select_option(label="Nordvik Bakery Ltd")
    page.locator("[data-tun-list-toolbar-apply]").click()
    page.wait_for_url(re.compile(r"customer=cus_"), timeout=5000)
    titles = page.locator(".tun-table tbody tr td:first-child").all_inner_texts()
    t.check(titles == ["Bread van signage"], f"«Apply» filters by the chosen customer: {titles}")


def pictures(t):
    """The field closed and open with a customer active, at 390 and 1280 px,
    light and dark, and the cards' filter in use."""
    for scheme in ("light", "dark"):
        for width, make in ((390, t.phone), (1280, t.desktop)):
            page = open_form(t, make=make, scheme=scheme)
            page.screenshot(path=str(t.out / f"ui-choice-form-{width}-{scheme}.png"))
            page.locator(FORM).click()
            wait_answered(page, "")
            page.keyboard.type("an")
            wait_answered(page, "an")
            page.keyboard.press("ArrowDown")
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"ui-choice-open-{width}-{scheme}.png"))
            page.fill(FIELD, "")
            page.keyboard.type("bjorn")
            wait_answered(page, "bjorn")
            chosen = state(page)["values"][0]
            page.goto("/cards?customer=" + chosen)
            page.wait_for_timeout(400)
            page.screenshot(path=str(t.out / f"ui-choice-cards-{width}-{scheme}.png"))
            if width == 390:
                page.locator("[data-tun-list-toolbar-fold]").tap()
                page.wait_for_timeout(500)
                page.locator(TOOLBAR_FIELD).tap()
                page.keyboard.type("nord")
                wait_answered(page, "nord", TOOLBAR_FIELD)
                page.wait_for_timeout(300)
                page.screenshot(path=str(t.out / f"ui-choice-sheet-{width}-{scheme}.png"))
            else:
                page.locator(TOOLBAR_BUTTON).click()
                wait_answered(page, "", TOOLBAR_FIELD)
                page.wait_for_timeout(300)
                page.screenshot(path=str(t.out / f"ui-choice-filter-{width}-{scheme}.png"))
            t.check(True, f"{width}px {scheme}: pictures of the field and the filter")


def run(t):
    asking(t)
    overtaken(t)
    keys(t)
    enter_before_the_answer(t)
    placement(t)
    phone(t)
    given(t)
    toolbar(t)
    sheet(t)
    without_javascript(t)
    pictures(t)
