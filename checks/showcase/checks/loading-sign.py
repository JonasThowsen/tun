"""A staff page shows that it is working when a link or a form has not been
answered after 300 ms, and the sign goes when the page is swapped in, when
the request fails and after Back; a fast page and a part that loads by
itself never show it (spec/ui.md 4.1, «The loading sign»)."""

import re
import time

BAR = "[data-tun-loading]"
STATUS = "[data-tun-loading-status]"

# Records, in the window, each time the bar is shown, with the time since
# the last press, and what the live region said; htmx swaps the body, not
# the document, so the record lasts across pages.
WATCH = """() => {
  window.tunSeen = [];
  window.tunSaid = [];
  window.tunPressed = performance.now();
  document.addEventListener('pointerdown', () => { window.tunPressed = performance.now(); }, true);
  document.addEventListener('submit', () => { window.tunPressed = performance.now(); }, true);
  new MutationObserver((records) => {
    for (const record of records) {
      const target = record.target;
      if (target.matches?.('[data-tun-loading]') && !target.hidden)
        window.tunSeen.push(Math.round(performance.now() - window.tunPressed));
      if (target.closest?.('[data-tun-loading-status]') || target.matches?.('[data-tun-loading-status]'))
        window.tunSaid.push(document.querySelector('[data-tun-loading-status]')?.textContent);
    }
  }).observe(document.documentElement,
             { subtree: true, attributes: true, attributeFilter: ['hidden'],
               childList: true, characterData: true });
}"""


def shown(page):
    return page.evaluate(f"document.querySelector('{BAR}')?.hidden === false")


def said(page):
    return page.evaluate(f"document.querySelector('{STATUS}')?.textContent ?? ''")


def seen(page):
    return page.evaluate("window.tunSeen.length")


def run(t):
    page = t.phone()
    page.sign_in("employee:anna")
    page.goto("/wait?ms=0")
    page.wait_for_selector("#wait-part")
    page.evaluate(WATCH)
    t.check(not shown(page) and said(page) == "", "no sign on a page that has loaded")
    t.check(page.locator(BAR).get_attribute("aria-hidden") == "true"
            and page.locator(STATUS).get_attribute("role") == "status",
            "the bar is hidden from a screen reader, which hears the status region")

    page.get_by_role("link", name="A fast page").tap()
    page.wait_for_selector("#wait-part")
    time.sleep(0.5)
    t.check(seen(page) == 0, "a fast page never shows the sign")
    page.wait_for_timeout(1000)
    t.check(page.locator("#wait-part").count() == 1 and seen(page) == 0,
            "and the part that loads by itself (1 s) does not either")

    page.get_by_role("link", name="A slow page").tap()
    time.sleep(0.15)
    t.check(not shown(page), "150 ms after the press of a slow link: no sign yet")
    page.wait_for_selector(BAR, state="visible", timeout=2000)
    t.check(shown(page) and said(page) in ("Loading…", "Laster…"),
            f"then the bar shows and the region says so: {said(page)!r}")
    box = page.evaluate(f"(({{top, height, width}}) => ({{top, height, width}}))"
                        f"(document.querySelector('{BAR}').getBoundingClientRect())")
    t.check(box["top"] == 0 and box["height"] == 3 and abs(box["width"] - 390) <= 1,
            f"a 3px bar across the top of the phone's window: {box}")
    first = page.evaluate("window.tunSeen[0]")
    t.check(300 <= first < 700, f"after the delay: {first} ms after the press")
    page.wait_for_url(re.compile(r"ms=1500"))
    page.wait_for_selector("text=This page waited 1500 ms.")
    t.check(not shown(page) and said(page) == "", "the sign is gone once the page is swapped in")
    t.check(page.evaluate("window.tunSaid.filter((text) => text).length") == 1,
            "the region said it once for that wait")

    page.get_by_role("button", name="Send a slow form").tap()
    page.wait_for_selector(BAR, state="visible", timeout=2000)
    t.check(True, "a slow form shows the sign")
    page.wait_for_url(re.compile(r"sent=1"))
    page.wait_for_selector("#wait-part")
    t.check(not shown(page), "and it goes when the page after it is shown")

    # A request that fails on the network.
    page.route("**/wait?ms=1500", lambda route: (time.sleep(0.8), route.abort()))
    before = seen(page)
    page.get_by_role("link", name="A slow page").tap()
    page.wait_for_timeout(1500)
    t.check(seen(page) > before and not shown(page),
            "a request that fails shows the sign, then clears it")
    page.unroute("**/wait?ms=1500")

    # A request cancelled: htmx:abort on the form that asked.
    page.goto("/wait?ms=0")
    page.evaluate(WATCH)
    page.get_by_role("button", name="Send a slow form").tap()
    page.wait_for_selector(BAR, state="visible", timeout=2000)
    page.evaluate("document.querySelector('form[action=\"/wait?ms=1500\"]')"
                  ".dispatchEvent(new CustomEvent('htmx:abort'))")
    page.wait_for_timeout(200)
    t.check(not shown(page) and said(page) == "" and "sent=1" not in page.url,
            f"a request cancelled with htmx:abort clears the sign at once: {page.url}")

    # A slow link, then a fast one: htmx cancels neither, so the sign
    # stays while the slow request is under way and goes when it ends.
    page.get_by_role("link", name="A slow page").tap()
    page.wait_for_selector(BAR, state="visible", timeout=2000)
    page.get_by_role("link", name="A fast page").tap()
    page.wait_for_timeout(300)
    t.check(shown(page) and page.locator("text=This page waited 0 ms.").count() == 1,
            "a fast page swapped in after the bar showed keeps it while the slow one is under way")
    page.wait_for_timeout(1500)
    t.check(not shown(page) and said(page) == "",
            f"and goes when it has ended: {page.url}")

    # An error page, after 0.8 s.
    def refuse(route):
        time.sleep(0.8)
        route.fulfill(status=500, content_type="text/html",
                      body="<!doctype html><title>Error</title><body><h1>Error</h1></body>")
    page.route("**/wait?ms=1500", refuse)
    before = seen(page)
    page.get_by_role("link", name="A slow page").tap()
    page.wait_for_selector("h1:text('Error')", timeout=3000)
    t.check(seen(page) > before and not shown(page),
            "an error answer shows the sign, then clears it when the error page is in")
    page.unroute("**/wait?ms=1500")

    # Back to a boosted page while a slow page loads.
    page.goto("/wait?ms=0")
    page.wait_for_selector("#wait-part")
    page.evaluate(WATCH)
    page.evaluate("document.addEventListener('htmx:before:history:restore', "
                  "() => { window.tunRestored = location.href; })")
    page.get_by_role("link", name="A fast page").tap()
    page.wait_for_selector("#wait-part")
    page.get_by_role("link", name="A slow page").tap()
    page.wait_for_selector(BAR, state="visible", timeout=2000)
    page.go_back()
    page.wait_for_timeout(300)
    restored = page.evaluate("window.tunRestored")
    t.check(restored and restored.endswith("/wait?ms=0") and page.url.endswith("/wait?ms=0"),
            f"Back restores the boosted page through htmx: {restored}, {page.url}")
    t.check(shown(page), "and the bar stays on it while the slow request is under way")
    page.wait_for_timeout(2000)
    t.check(not shown(page) and said(page) == "",
            f"and once the slow request has ended there is no sign: {page.url}")

    desktop = t.desktop(scheme="dark")
    desktop.sign_in("employee:anna")
    desktop.goto("/wait?ms=0")
    desktop.wait_for_selector("#wait-part")
    desktop.evaluate(WATCH)
    preloads = []
    desktop.on("request", lambda request: preloads.append(request.url)
               if request.headers.get("tun-preload") == "true" else None)
    slow = desktop.get_by_role("link", name="A slow page")
    box = slow.bounding_box()
    desktop.mouse.move(box["x"] + 5, box["y"] + 5)
    desktop.mouse.move(box["x"] + 10, box["y"] + 8)
    desktop.wait_for_timeout(2000)
    t.check(any("ms=1500" in url for url in preloads) and seen(desktop) == 0,
            f"a preload of the slow page never shows the sign: {preloads}")
    desktop.mouse.move(0, 400)
    # The slow page is preloaded now, so its link answers at once; the
    # slow form is not.
    desktop.get_by_role("button", name="Send a slow form").click()
    desktop.wait_for_selector(BAR, state="visible", timeout=2000)
    colour = desktop.evaluate(
        f"getComputedStyle(document.querySelector('{BAR}')).backgroundImage")
    t.check("gradient" in colour, f"in the dark, on a desktop, the bar shows: {colour[:60]}")
    desktop.wait_for_url(re.compile(r"sent=1"))

    still = t.phone()
    still._page.emulate_media(reduced_motion="reduce")
    still.sign_in("employee:anna")
    still.goto("/wait?ms=0")
    still.get_by_role("link", name="A slow page").tap()
    still.wait_for_selector(BAR, state="visible", timeout=2000)
    animation = still.evaluate(
        f"getComputedStyle(document.querySelector('{BAR}')).animationName")
    t.check(animation == "none", f"under reduced motion the bar stands still: {animation}")
    still.wait_for_selector("text=This page waited 1500 ms.")

    plain = t.phone(javascript=False)
    plain.sign_in("employee:anna")
    plain.goto("/wait?ms=0")
    t.check(plain.locator(BAR).is_hidden(), "without JavaScript the bar stays hidden")
