"""The application's one search on the showcase, whose cards and customers
it finds: Ctrl K and the shell's links open it, a fixed box on a wide
screen, results as one types with the match marked, the arrows and Enter,
an Enter typed before the latest answer, an answer overtaken by a newer
one, a failed answer, Escape, a page's own Ctrl K dialog, the phone's
sheet above a keyboard, and the page without JavaScript (spec/ui.md 6.4)."""

import re
import statistics
import time

SCENARIO = "search"

DIALOG = "dialog#tun-search"
FIELD = "#tun-search-field"

BOX = """(selector) => {
  const box = document.querySelector(selector).getBoundingClientRect();
  return {top: box.top, bottom: box.bottom, left: box.left, right: box.right,
          width: box.width, height: box.height};
}"""

STATE = """() => {
  const dialog = document.querySelector('dialog#tun-search');
  const field = document.querySelector('#tun-search-field');
  const rows = [...dialog.querySelectorAll('[role=option]')];
  const marked = rows.find((row) => row.getAttribute('aria-selected') === 'true');
  return {open: dialog.open, focused: document.activeElement === field, value: field.value,
          selected: [field.selectionStart, field.selectionEnd],
          shown: dialog.querySelector('[data-tun-search-query]')?.getAttribute('data-tun-search-query'),
          titles: rows.map((row) => row.querySelector('.tun-search-results-title').textContent),
          marks: [...dialog.querySelectorAll('.tun-search-results-title mark')].map((m) => m.textContent),
          marked: marked ? rows.indexOf(marked) : -1,
          active: field.getAttribute('aria-activedescendant'),
          empty: dialog.querySelector('.tun-search-results-empty')?.textContent ?? null};
}"""

ROW_STYLES = """() => [...document.querySelectorAll('dialog#tun-search [role=option]')].map((row) => {
  const style = getComputedStyle(row);
  const title = getComputedStyle(row.querySelector('.tun-search-results-title'));
  return {selected: row.getAttribute('aria-selected'), ground: style.backgroundColor,
          ring: style.boxShadow, padding: style.padding, height: row.getBoundingClientRect().height,
          weight: title.fontWeight, size: title.fontSize};
})"""

# A keyboard over the lower part of the window: the visual viewport shrinks
# to HEIGHT, as Safari and Chrome on Android report it (as ui-sheets does).
KEYBOARD = """(height) => {
  if (height === null) delete window.visualViewport.height;
  else Object.defineProperty(window.visualViewport, 'height', {configurable: true, get: () => height});
  window.visualViewport.dispatchEvent(new Event('resize'));
  return document.documentElement.style.getPropertyValue('--tun-visual-bottom');
}"""

MAC = "Object.defineProperty(Navigator.prototype, 'platform', {get: () => 'MacIntel'});"

# The server's time for the dialog's fragment, from the browser: the
# median of five, after one to warm up.
TIMING = """async (texts) => {
  const out = {};
  for (const text of texts) {
    const ask = async () => {
      const start = performance.now();
      await (await fetch('/search?q=' + encodeURIComponent(text),
                         {headers: {'HX-Request': 'true', 'HX-Request-Type': 'partial'}})).text();
      return performance.now() - start;
    };
    await ask();
    const times = [];
    for (let i = 0; i < 5; i += 1) times.push(await ask());
    times.sort((a, b) => a - b);
    out[text] = times[2];
  }
  return out;
}"""


def state(page):
    return page.evaluate(STATE)


def wait_shown(page, text, timeout=3000):
    """Wait until the dialog shows the answer for TEXT; the time it took, in ms."""
    start = time.monotonic()
    page.wait_for_function(
        """(text) => document.querySelector('dialog#tun-search [data-tun-search-query]')
                       ?.getAttribute('data-tun-search-query') === text""", arg=text, timeout=timeout)
    return (time.monotonic() - start) * 1000


def opens(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    t.check(page.locator(".tun-app-shell-search-row").is_visible(),
            "1280px: the sidebar's row shows")
    t.check(not page.locator(".tun-app-shell-bar > [data-tun-search-open]").is_visible(),
            "and the top bar's button does not")
    keys = page.locator(".tun-app-shell-search-row kbd kbd").all_text_contents()
    t.check(keys == ["Ctrl", "K"], f"the row shows Ctrl K: {keys}")
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    s = state(page)
    t.check(s["open"] and s["focused"], f"Ctrl K opens the search with the focus in its field: {s}")
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    t.check(not state(page)["open"], "Escape closes it")

    page.locator(".tun-app-shell-search-row").click()
    page.wait_for_timeout(300)
    t.check(state(page)["open"] and state(page)["focused"], "the row opens it, the focus in the field")
    t.check("/search" not in page.url, f"and the page stays: {page.url}")
    page.keyboard.type("nord")
    wait_shown(page, "nord")
    page.keyboard.press("Escape")
    page.wait_for_timeout(300)
    back = page.evaluate("() => document.activeElement.classList.contains('tun-app-shell-search-row')")
    t.check(back, "Escape gives the focus back to the row")
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    s = state(page)
    t.check(s["value"] == "nord" and s["selected"] == [0, 4],
            f"opened again, what was typed is there and chosen: {s['value']} {s['selected']}")

    page = t.desktop()
    page.add_init_script(MAC)
    page.sign_in("employee:anna")
    page.goto("/cards")
    keys = page.locator(".tun-app-shell-search-row kbd kbd").all_text_contents()
    t.check(keys == ["⌘", "K"], f"a Mac reads ⌘ K: {keys}")
    page.keyboard.press("Meta+k")
    page.wait_for_timeout(300)
    t.check(state(page)["open"], "and ⌘ K opens it")

    # A page's own dialog on Ctrl K opens on it instead (/items has one).
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/items")
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    own = page.locator("dialog#search[open]").count()
    t.check(own == 1 and not state(page)["open"],
            "on /items Ctrl K opens the page's own search, not the shell's")
    t.check(page.locator(".tun-app-shell-search-row").is_visible(), "which keeps its row")


def results(t):
    for scheme in ("light", "dark"):
        page = t.desktop(scheme=scheme)
        page.sign_in("employee:anna")
        page.goto("/cards")
        page.keyboard.press("Control+k")
        page.wait_for_timeout(400)
        closed_box = page.evaluate(BOX, DIALOG)
        field_box = page.evaluate(BOX, FIELD)
        page.keyboard.type("item")
        took = wait_shown(page, "item")
        s = state(page)
        t.check(took < 1500, f"{scheme}: results within 1.5 s of the last key: {took:.0f} ms")
        t.check(len(s["titles"]) == 5 and all(m.lower() == "item" for m in s["marks"]),
                f"{scheme}: five cards, «Item» marked in each: {s['titles']} {s['marks']}")
        many_box = page.evaluate(BOX, DIALOG)
        page.fill(FIELD, "")
        page.keyboard.type("e")
        page.wait_for_timeout(600)
        t.check(not state(page)["titles"], "one character asks for nothing")
        page.keyboard.type("x")
        wait_shown(page, "ex")
        ten = state(page)
        page.fill(FIELD, "")
        page.keyboard.type("zebra")
        wait_shown(page, "zebra")
        s = state(page)
        t.check(s["empty"] == "No results for «zebra»", f"{scheme}: says so when nothing: {s['empty']}")
        none_box = page.evaluate(BOX, DIALOG)
        t.check(all(abs(box[k] - closed_box[k]) < 0.5 for box in (many_box, none_box)
                    for k in ("top", "left", "width", "height")),
                f"{scheme}: the dialog's box stays as results come and go: {closed_box} {many_box} {none_box}")
        t.check(abs(page.evaluate(BOX, FIELD)["top"] - field_box["top"]) < 0.5, "and the field never moves")
        t.check(abs(closed_box["width"] - 640) < 1 and abs(closed_box["height"] - 576) < 1,
                f"{scheme}: 40rem by 36rem: {closed_box}")
        t.check(len(ten["titles"]) >= 6, f"«ex» finds cards and customers: {ten['titles']}")

    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    page.keyboard.type("bjorn ase")
    wait_shown(page, "bjorn ase")
    s = state(page)
    t.check(s["titles"][:1] == ["Bjørn Åsen"] and s["marks"][:2] == ["Bjørn", "Åse"],
            f"«bjorn ase» finds and marks «Bjørn Åsen»: {s['titles']} {s['marks']}")
    page.fill(FIELD, "")
    page.keyboard.type("412 34")
    wait_shown(page, "412 34")
    t.check(state(page)["titles"][:1] == ["Bjørn Åsen"], "the start of a phone number finds it")
    meta = page.locator("dialog#tun-search .tun-search-results-meta").first.text_content()
    t.check(meta.startswith("Customer · "), f"its line starts with its kind: {meta}")


def keys(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    page.keyboard.type("item")
    wait_shown(page, "item")
    s = state(page)
    t.check(s["marked"] == 0 and s["active"] == "tun-search-result-0",
            f"the first row is marked when results come: {s['marked']} {s['active']}")
    page.keyboard.press("ArrowDown")
    page.keyboard.press("ArrowDown")
    s = state(page)
    t.check(s["marked"] == 2 and s["active"] == "tun-search-result-2", f"↓ ↓ marks the third: {s}")
    styles = page.evaluate(ROW_STYLES)
    marked = [r for r in styles if r["selected"] == "true"]
    others = [r for r in styles if r["selected"] != "true"]
    t.check(len(marked) == 1 and marked[0]["ground"] != others[0]["ground"]
            and "inset" in marked[0]["ring"],
            f"the marked row has its ground and frame: {marked} {others[:1]}")
    t.check(all(r[k] == others[0][k] for r in styles for k in ("weight", "size", "padding", "height")),
            f"at the others' weight, size, padding and height: {styles}")
    page.keyboard.press("ArrowUp")
    page.keyboard.press("ArrowUp")
    page.keyboard.press("ArrowUp")
    t.check(state(page)["marked"] == 4, "↑ from the first goes round to the last")
    title = state(page)["titles"][4]
    page.keyboard.press("Enter")
    page.wait_for_url(re.compile(r"/items/crd_"), timeout=5000)
    page.wait_for_timeout(300)
    heading = page.locator("main h1").first.text_content()
    t.check(heading.strip() == title, f"Enter opens the marked row: {title} → {heading}")
    t.check(not page.evaluate("() => document.querySelector('dialog#tun-search').open"),
            "the search is closed on the new page")
    scrolls = page.evaluate("() => getComputedStyle(document.documentElement).overflow")
    t.check(scrolls != "hidden", f"and the page scrolls again: {scrolls}")

    # An Enter typed before the answer for the last keys waits for it.
    page.goto("/cards")
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    page.keyboard.type("item")
    wait_shown(page, "item")
    page.keyboard.type(" 2", delay=20)
    page.keyboard.press("Enter")
    page.wait_for_url(re.compile(r"/items/crd_"), timeout=5000)
    page.wait_for_timeout(300)
    heading = page.locator("main h1").first.text_content().strip()
    t.check(heading == "Item 2", f"an Enter at once opens the latest answer's first row: {heading}")


def overtaken_and_failed(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    # Requests a service worker passes on are not always routed: without
    # it, the page's own requests are what the check holds and fails.
    page.evaluate("""async () => {
      for (const registration of await navigator.serviceWorker.getRegistrations())
        await registration.unregister();
    }""")
    page.goto("/cards")
    held = []
    failed = []
    asked = []
    page.on("requestfailed", lambda request: failed.append(request.url))
    page.on("request", lambda request: asked.append(request.url) if "/search" in request.url else None)

    def hold(route):
        held.append(route)

    page.route(re.compile(r".*/search\?q=ite$"), hold)
    page.keyboard.press("Control+k")
    page.wait_for_timeout(300)
    page.keyboard.type("ite")
    page.wait_for_timeout(500)
    t.check(len(held) == 1, f"the answer for «ite» is held: {len(held)} {asked}")
    page.keyboard.type("m 1")
    wait_shown(page, "item 1")
    later = state(page)["titles"]
    stale = ('<div class="tun-search-results" data-tun-search-query="ite"><ul class="tun-search-results-list"'
             ' role="listbox"><li role="none"><a class="tun-search-results-row" href="/cards" id="tun-search-result-0"'
             ' role="option" aria-selected="true"><span class="tun-search-results-text">'
             '<span class="tun-search-results-title">Stale</span></span></a></li></ul></div>')
    try:
        held[0].fulfill(status=200, content_type="text/html", body=stale)
        answered = "answered late"
    except Exception as error:
        answered = f"cancelled by htmx ({type(error).__name__})"
    page.wait_for_timeout(600)
    s = state(page)
    t.check(s["shown"] == "item 1" and s["titles"] == later and "Stale" not in s["titles"],
            f"the slow earlier answer ({answered}; failed requests {len(failed)}) never replaces the later one: {s['titles']}")
    page.unroute(re.compile(r".*/search\?q=ite$"))

    page.route(re.compile(r".*/search\?q=broken$"),
               lambda route: route.fulfill(status=500, content_type="text/html",
                                           body="<!doctype html><p>Server error</p>"))
    page.fill(FIELD, "")
    page.keyboard.type("broken")
    page.wait_for_timeout(800)
    s = state(page)
    t.check(s["empty"] == "The search failed. Try again." and "Server error" not in page.content(),
            f"a failed answer says so, and nothing of the error page shows: {s['empty']}")
    page.route(re.compile(r".*/search\?q=gone$"), lambda route: route.abort("failed"))
    page.fill(FIELD, "")
    page.keyboard.type("gone")
    page.wait_for_timeout(800)
    t.check(state(page)["empty"] == "The search failed. Try again.", "so does no answer at all")


def phone(t):
    for width in (390, 360, 320):
        page = t.phone(width=width)
        page.sign_in("employee:anna")
        page.goto("/cards")
        button = page.locator(".tun-app-shell-bar > [data-tun-search-open]")
        t.check(button.is_visible(), f"{width}px: the top bar's «Search» shows")
        t.check(not page.locator(".tun-app-shell-search-row").is_visible(), "the row does not")
        b = button.bounding_box()
        t.check(b["width"] >= 44 and b["height"] >= 44 and b["x"] + b["width"] <= width,
                f"{width}px: a target of 44px, inside the bar: {b}")
        t.check(page.evaluate("() => document.documentElement.scrollWidth") <= width,
                f"{width}px: the page does not scroll sideways")
        button.tap()
        page.wait_for_timeout(600)
        box = page.evaluate(BOX, DIALOG)
        t.check(abs(box["height"] - (844 - 32)) < 1 and abs(box["bottom"] - 844) < 1,
                f"{width}px: it opens as tall as it may be: {box}")
        if width != 390:
            continue
        t.check(state(page)["focused"], "the focus in the field")
        page.keyboard.type("item")
        wait_shown(page, "item")
        inset = page.evaluate(KEYBOARD, 400)
        page.wait_for_timeout(150)
        shrunk = page.evaluate(BOX, DIALOG)
        field = page.evaluate(BOX, FIELD)
        results_box = page.evaluate(BOX, "#tun-search-results")
        t.check(inset == "444px" and abs(shrunk["bottom"] - 400) < 1 and field["bottom"] <= 400
                and results_box["bottom"] <= 400.5,
                f"above a keyboard the field and the results stay in sight: {inset} {shrunk} {field} {results_box}")
        page.evaluate(KEYBOARD, None)
        page.locator("dialog#tun-search [role=option]").first.tap()
        page.wait_for_url(re.compile(r"/items/crd_"), timeout=5000)
        t.check(True, "a tap on a row opens it")


def without_javascript(t):
    page = t.phone(javascript=False)
    page.sign_in("employee:anna")
    page.goto("/cards")
    page.locator(".tun-app-shell-bar > [data-tun-search-open]").click()
    page.wait_for_url(re.compile(r"/search"), timeout=5000)
    t.check(page.locator("main form[role=search] input[name=q]").count() == 1,
            f"without JavaScript the button leads to the search page: {page.url}")
    page.fill("main form[role=search] input[name=q]", "nordvik")
    page.locator("main form[role=search] button[type=submit]").click()
    page.wait_for_url(re.compile(r"q=nordvik"), timeout=5000)
    titles = page.locator("main .tun-search-results-title").all_text_contents()
    t.check(titles[:1] == ["Nordvik Bakery Ltd"], f"and its form lists the results: {titles}")
    t.check(page.locator("main .tun-search-results-title mark").first.text_content() == "Nordvik",
            "with the match marked")


def timing(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/cards")
    times = page.evaluate(TIMING, ["it", "item", "nordvik", "bjorn", "412 34"])
    worst = max(times.values())
    t.check(worst < 100, "the showcase's searches answer within 100 ms: "
            + ", ".join(f"«{k}» {v:.0f} ms" for k, v in times.items()))


def pictures(t):
    """The shell closed, the search open with results and the marked row,
    and open with nothing found, at 390 and 1280 px, light and dark."""
    for scheme in ("light", "dark"):
        for width, make in ((390, t.phone), (1280, t.desktop)):
            page = make(scheme=scheme)
            page.sign_in("employee:anna")
            page.goto("/cards")
            page.wait_for_timeout(400)
            page.screenshot(path=str(t.out / f"ui-search-closed-{width}-{scheme}.png"))
            if width == 390:
                page.locator(".tun-app-shell-bar > [data-tun-search-open]").click()
            else:
                page.keyboard.press("Control+k")
            page.wait_for_timeout(500)
            page.keyboard.type("ex")
            wait_shown(page, "ex")
            page.keyboard.press("ArrowDown")
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"ui-search-results-{width}-{scheme}.png"))
            page.fill(FIELD, "")
            page.keyboard.type("zebra")
            wait_shown(page, "zebra")
            page.wait_for_timeout(300)
            page.screenshot(path=str(t.out / f"ui-search-empty-{width}-{scheme}.png"))
            t.check(state(page)["empty"] == "No results for «zebra»",
                    f"{width}px {scheme}: pictures of the search closed, with results and empty")


def run(t):
    opens(t)
    results(t)
    keys(t)
    overtaken_and_failed(t)
    phone(t)
    without_javascript(t)
    timing(t)
    pictures(t)
