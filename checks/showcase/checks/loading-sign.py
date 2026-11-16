"""A staff page shows that it is working when a link or a form has not been
answered after 300 ms, and the sign goes when the page is swapped in, when
the request fails and after Back; a fast page and a part that loads by
itself never show it (spec/ui.md 4.1, «The loading sign»).

The 300 ms are the page's own timer, so the check holds the page's clock
and moves it on itself; a slow answer is one the check holds until it lets
it go, so a busy machine changes neither."""

import datetime
import re

BAR = "[data-tun-loading]"
STATUS = "[data-tun-loading-status]"

# A time for the page's clock, which the check holds and moves on.
PAGE_TIME = datetime.datetime(2026, 11, 2, 9, 0)

# Records, in the window, how many times the bar is shown, what the live
# region said, and how many swaps htmx has made; htmx swaps the body, not
# the document, so the record lasts across pages.
WATCH = """() => {
  window.tunSeen = 0;
  window.tunSaid = [];
  window.tunSwaps = 0;
  document.addEventListener('htmx:after:swap', () => { window.tunSwaps += 1; });
  new MutationObserver((records) => {
    for (const record of records) {
      const target = record.target;
      if (target.matches?.('[data-tun-loading]') && !target.hidden) window.tunSeen += 1;
      if (target.closest?.('[data-tun-loading-status]') || target.matches?.('[data-tun-loading-status]'))
        window.tunSaid.push(document.querySelector('[data-tun-loading-status]')?.textContent);
    }
  }).observe(document.documentElement,
             { subtree: true, attributes: true, attributeFilter: ['hidden'],
               childList: true, characterData: true });
}"""

SHOWN = f"() => document.querySelector('{BAR}')?.hidden === false"
GONE = f"() => document.querySelector('{BAR}')?.hidden !== false"


def shown(page):
    return page.evaluate(SHOWN)


def said(page):
    return page.evaluate(f"document.querySelector('{STATUS}')?.textContent ?? ''")


def seen(page):
    return page.evaluate("window.tunSeen")


def swaps(page):
    return page.evaluate("window.tunSwaps")


def wait_swapped(page, before, what):
    """Wait until htmx has swapped in more than BEFORE times: the answer to
    the step's own request is in, and the kit's htmx:after:swap listener,
    which runs in the same event, has had its say."""
    page.wait_until("(before) => window.tunSwaps > before", before, what=what)


class Held:
    """The requests to PATTERN, held until let go: a slow answer whose end
    the check decides."""

    def __init__(self, page, pattern):
        self.page, self.pattern, self.routes = page, pattern, []
        page.route(pattern, lambda route: self.routes.append(route))

    def wait(self):
        self.page.poll_until(lambda: self.routes, what=f"a request to {self.pattern} to be held")

    def go(self):
        for route in self.routes:
            route.continue_()
        self.routes.clear()
        self.page.unroute(self.pattern)


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

    # The page's clock, held: no timer of the page fires until the check
    # moves it on, so its 300 ms are exact however busy the machine is.
    page.clock.install(time=PAGE_TIME)
    page.clock.pause_at(PAGE_TIME + datetime.timedelta(hours=1))
    # The page already says «waited 0 ms», so the check counts the fast
    # page's swap. The swap may wait on a timer of the page's, which runs
    # only when the check moves the held clock: a millisecond at a time,
    # until it is in, however long the machine takes to answer.
    before = swaps(page)
    moved = [0]

    def swapped():
        page.clock.run_for(1)
        moved[0] += 1
        return swaps(page) > before

    # The part's request comes only from the swapped-in page.
    with page.expect_response(re.compile(r"/wait/part\?ms=1000$")):
        with page.expect_response(re.compile(r"/wait\?ms=0$")):
            page.get_by_role("link", name="A fast page").tap()
        page.poll_until(swapped, what="the fast page swapped in")
        t.check(moved[0] < 299, f"the fast page swapped in {moved[0]} ms after the tap")
        page.clock.run_for(max(0, 299 - moved[0]))  # the answer came before the sign's time
    page.clock.run_for(1000)
    page.wait_for_selector("#wait-part")
    page.clock.run_for(1000)
    t.check(seen(page) == 0, "a fast page never shows the sign")
    t.check(page.locator("#wait-part").count() == 1 and seen(page) == 0,
            "and the part that loads by itself (1 s) does not either")

    slow = Held(page, "**/wait?ms=1500")
    page.get_by_role("link", name="A slow page").tap()
    slow.wait()
    page.clock.run_for(299)
    t.check(not shown(page), "299 ms after the press of a slow link: no sign yet")
    page.clock.run_for(1)
    t.check(shown(page) and said(page) in ("Loading…", "Laster…"),
            f"at 300 ms the bar shows and the region says so: {said(page)!r}")
    box = page.evaluate(f"(({{top, height, width}}) => ({{top, height, width}}))"
                        f"(document.querySelector('{BAR}').getBoundingClientRect())")
    t.check(box["top"] == 0 and box["height"] == 3 and abs(box["width"] - 390) <= 1,
            f"a 3px bar across the top of the phone's window: {box}")
    page.clock.resume()
    slow.go()
    page.wait_for_url(re.compile(r"ms=1500"))
    page.wait_for_selector("text=This page waited 1500 ms.")
    page.wait_until(GONE, what="the sign gone")
    t.check(not shown(page) and said(page) == "", "the sign is gone once the page is swapped in")
    t.check(page.evaluate("window.tunSaid.filter((text) => text).length") == 1,
            "the region said it once for that wait")

    page.get_by_role("button", name="Send a slow form").tap()
    page.wait_for_selector(BAR, state="visible")
    t.check(True, "a slow form shows the sign")
    page.wait_for_url(re.compile(r"sent=1"))
    page.wait_for_selector("#wait-part")
    page.wait_until(GONE, what="the sign gone")
    t.check(not shown(page), "and it goes when the page after it is shown")

    # A request that fails on the network, once the sign shows.
    failing = Held(page, "**/wait?ms=1500")
    before = seen(page)
    page.get_by_role("link", name="A slow page").tap()
    failing.wait()
    page.wait_for_selector(BAR, state="visible")
    failing.routes.pop().abort()
    failing.go()
    page.wait_until(GONE, what="the sign cleared after the failed request")
    t.check(seen(page) > before and not shown(page),
            "a request that fails shows the sign, then clears it")

    # A request cancelled: htmx:abort on the form that asked.
    page.goto("/wait?ms=0")
    page.evaluate(WATCH)
    page.get_by_role("button", name="Send a slow form").tap()
    page.wait_for_selector(BAR, state="visible")
    page.evaluate("document.querySelector('form[action=\"/wait?ms=1500\"]')"
                  ".dispatchEvent(new CustomEvent('htmx:abort'))")
    page.wait_until(GONE, what="the sign cleared after htmx:abort")
    t.check(not shown(page) and said(page) == "" and "sent=1" not in page.url,
            f"a request cancelled with htmx:abort clears the sign at once: {page.url}")

    # A slow link, then a fast one: htmx cancels neither, so the sign
    # stays while the slow request is under way and goes when it ends.
    slow = Held(page, "**/wait?ms=1500")
    with page.expect_htmx():                # until both requests have ended
        page.get_by_role("link", name="A slow page").tap()
        slow.wait()
        page.wait_for_selector(BAR, state="visible")
        # The page already says «waited 0 ms»: wait for the fast page's own
        # swap, since htmx brings it with a hidden bar until after:swap.
        before = swaps(page)
        page.get_by_role("link", name="A fast page").tap()
        wait_swapped(page, before, "the fast page swapped in")
        t.check(shown(page) and page.locator("text=This page waited 0 ms.").count() == 1,
                "a fast page swapped in after the bar showed keeps it while the slow one is under way")
        slow.go()
    page.wait_until(GONE, what="the sign gone once the slow request ended")
    t.check(not shown(page) and said(page) == "",
            f"and goes when it has ended: {page.url}")

    # An error page, once the sign shows.
    refused = Held(page, "**/wait?ms=1500")
    before = seen(page)
    with page.expect_htmx():
        page.get_by_role("link", name="A slow page").tap()
        refused.wait()
        page.wait_for_selector(BAR, state="visible")
        refused.routes.pop().fulfill(status=500, content_type="text/html",
                                     body="<!doctype html><title>Error</title><body><h1>Error</h1></body>")
        refused.go()
    page.wait_for_selector("h1:text('Error')")
    page.wait_until(GONE, what="the sign gone once the error page is in")
    t.check(seen(page) > before and not shown(page),
            f"an error answer shows the sign, then clears it when the error page is in: "
            f"shown {before} → {seen(page)} times, now {shown(page)}")

    # Back to a boosted page while a slow page loads.
    page.goto("/wait?ms=0")
    page.wait_for_selector("#wait-part")
    page.evaluate(WATCH)
    page.evaluate("document.addEventListener('htmx:before:history:restore', "
                  "() => { window.tunRestored = location.href; })")
    with page.expect_htmx():                # the fast page's history entry is in
        page.get_by_role("link", name="A fast page").tap()
    page.wait_for_selector("#wait-part")
    slow = Held(page, "**/wait?ms=1500")
    page.get_by_role("link", name="A slow page").tap()
    slow.wait()
    page.wait_for_selector(BAR, state="visible")
    before = swaps(page)
    page.go_back()
    restored = page.wait_until("() => window.tunRestored", what="htmx to restore the page Back went to")
    page.wait_until("() => location.href.endsWith('/wait?ms=0')", what="the address restored")
    wait_swapped(page, before, "the page Back went to swapped in")
    t.check(restored and restored.endswith("/wait?ms=0") and page.url.endswith("/wait?ms=0"),
            f"Back restores the boosted page through htmx: {restored}, {page.url}")
    t.check(shown(page), "and the bar stays on it while the slow request is under way")
    slow.go()
    page.wait_until(GONE, what="the sign gone once the slow request ended")
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
    with desktop.expect_response(lambda response: "ms=1500" in response.url
                                 and response.request.headers.get("tun-preload") == "true"):
        desktop.mouse.move(box["x"] + 5, box["y"] + 5)
        desktop.mouse.move(box["x"] + 10, box["y"] + 8)
    t.check(any("ms=1500" in url for url in preloads) and seen(desktop) == 0,
            f"a preload of the slow page never shows the sign: {preloads}")
    desktop.mouse.move(0, 400)
    # The slow page is preloaded now, so its link answers at once; the
    # slow form is not.
    desktop.get_by_role("button", name="Send a slow form").click()
    desktop.wait_for_selector(BAR, state="visible")
    colour = desktop.evaluate(
        f"getComputedStyle(document.querySelector('{BAR}')).backgroundImage")
    t.check("gradient" in colour, f"in the dark, on a desktop, the bar shows: {colour[:60]}")
    desktop.wait_for_url(re.compile(r"sent=1"))

    still = t.phone()
    still._page.emulate_media(reduced_motion="reduce")
    still.sign_in("employee:anna")
    still.goto("/wait?ms=0")
    still.get_by_role("link", name="A slow page").tap()
    still.wait_for_selector(BAR, state="visible")
    animation = still.evaluate(
        f"getComputedStyle(document.querySelector('{BAR}')).animationName")
    t.check(animation == "none", f"under reduced motion the bar stands still: {animation}")
    still.wait_for_selector("text=This page waited 1500 ms.")

    plain = t.phone(javascript=False)
    plain.sign_in("employee:anna")
    plain.goto("/wait?ms=0")
    t.check(plain.locator(BAR).is_hidden(), "without JavaScript the bar stays hidden")
