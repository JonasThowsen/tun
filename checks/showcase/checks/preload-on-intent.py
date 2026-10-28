"""A boosted link loads its page when a pointer rests on it or a finger
or button presses it, and the click then shows that page without asking
again; a preload is used once, within ten seconds, a post drops them, a
page that remembers its query saves nothing for one, and links marked
off are left alone (spec/ui.md 4.1)."""

import re
import time
from urllib.parse import urlparse


class Requests:
    """The GET requests a page makes for whole pages, as (path, preload)."""

    def __init__(self, page):
        self.seen = []
        page.on("request", self._note)

    def _note(self, request):
        if request.method == "GET" and request.resource_type in ("document", "fetch", "xhr"):
            url = urlparse(request.url)
            path = url.path + (f"?{url.query}" if url.query else "")
            self.seen.append((path, request.headers.get("tun-preload") == "true", request.headers))

    def clear(self):
        self.seen.clear()

    def to(self, path, preload=None):
        return [seen for seen in self.seen
                if seen[0] == path and (preload is None or seen[1] == preload)]


def menu(page, name):
    return page.locator(".tun-nav-list").get_by_role("link", name=name, exact=True)


def follow(page, link, path):
    """Follow LINK as a script would, without moving the pointer, and wait
    for PATH."""
    link.evaluate("link => link.click()")
    page.wait_for_url(re.compile(re.escape(path) + "$"))
    page.wait_for_load_state()


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/access")
    title = page.title()
    page.goto("/items")
    seen = Requests(page)
    access = menu(page, "Access")

    # 1. A pointer that rests loads; one that passes does not.
    box = access.bounding_box()
    page.mouse.move(box["x"] + 10, box["y"] + box["height"] / 2)
    page.wait_for_timeout(40)
    page.mouse.move(700, 500)
    page.wait_for_timeout(300)
    t.check(not seen.to("/access"), "a pointer passing over «Access» loads nothing")
    access.hover()
    page.wait_for_timeout(400)
    preloads = seen.to("/access", preload=True)
    t.check(len(preloads) == 1, f"one resting on it loads it in the background ({len(preloads)})")
    headers = preloads[0][2] if preloads else {}
    t.check(headers.get("tun-assets") and headers.get("hx-request-type") == "full"
            and headers.get("hx-boosted") == "true",
            "with the click's own headers, Tun-Assets among them")

    # 3. The click shows it without asking again.
    seen.clear()
    access.click()
    page.wait_for_url(re.compile(r"/access$"))
    page.wait_for_load_state()
    t.check(not seen.to("/access"), f"the click asks the server nothing: {seen.to('/access')}")
    # htmx sets the title after it pushes the address.
    page.wait_for_function("title => document.title === title", arg=title, timeout=2000)
    t.check(page.title() == title, f"with the title it has without preloading: {page.title()}")

    # 4. Used once: following «Items» and «Access» again by script asks again.
    follow(page, menu(page, "Items"), "/items")
    seen.clear()
    follow(page, menu(page, "Access"), "/access")
    t.check(seen.to("/access", preload=False), "a preload is used once; the next visit asks")

    # 4. A post drops the preloads.
    follow(page, menu(page, "Items"), "/items")
    menu(page, "Access").hover()
    page.wait_for_timeout(400)
    page.mouse.move(700, 500)
    page.evaluate("""() => htmx.ajax('POST', '/items/move',
                     {source: document.body, swap: 'none', values: {card: 'none', column: 'new'}})""")
    page.wait_for_timeout(400)
    seen.clear()
    follow(page, menu(page, "Access"), "/access")
    t.check(seen.to("/access", preload=False), "after a post, the click asks the server")

    # 4. Ten seconds old is too old.
    follow(page, menu(page, "Items"), "/items")
    menu(page, "Access").hover()
    page.wait_for_timeout(400)
    page.mouse.move(700, 500)
    time.sleep(10.2)
    seen.clear()
    follow(page, menu(page, "Access"), "/access")
    t.check(seen.to("/access", preload=False), "a preload ten seconds old is not used")

    # 2. A mouse button pressed loads at once, before the pointer has rested.
    follow(page, menu(page, "Items"), "/items")
    seen.clear()
    box = menu(page, "Access").bounding_box()
    page.mouse.move(box["x"] + 10, box["y"] + box["height"] / 2)
    page.mouse.down()
    page.wait_for_timeout(50)
    t.check(seen.to("/access", preload=True), "a mouse button pressed on a link loads it at once")
    page.mouse.up()
    page.wait_for_url(re.compile(r"/access$"))

    # 5. A page that remembers its query saves nothing for a preload, and
    # saves for the click after it.
    page.goto("/items?p=")
    website = page.get_by_role("link", name="Website", exact=True)
    website.hover()
    page.wait_for_timeout(400)
    page.mouse.move(700, 500)
    follow(page, menu(page, "Access"), "/access")
    follow(page, menu(page, "Items"), "/items")
    t.check(page.url.endswith("/items"), f"hovering «Website» left the saved tab as it was: {page.url}")
    website = page.get_by_role("link", name="Website", exact=True)
    website.hover()
    page.wait_for_timeout(400)
    website.click()
    page.wait_for_url(re.compile(r"/items\?p=1$"))
    follow(page, menu(page, "Access"), "/access")
    follow(page, menu(page, "Items"), "/items?p=1")
    t.check(page.url.endswith("/items?p=1"), f"clicking it after the hover saved it: {page.url}")
    page.get_by_role("link", name="All", exact=True).click()
    page.wait_for_url(re.compile(r"/items\?p=$"))

    # 6. Links that are not preloaded.
    card = page.evaluate("document.querySelector('[data-tun-board-card] a[href]').getAttribute('href')")
    page.goto(card)
    seen.clear()
    for name in ("Back to the items", "Access in a new tab", "Access"):
        page.locator("main").get_by_role("link", name=name, exact=True).hover()
        page.wait_for_timeout(300)
    page.mouse.move(700, 600)
    t.check(not seen.seen, f"links marked off, inside a part marked off, or with a target load nothing: {[s[0] for s in seen.seen]}")

    # 2. A touch on a phone loads at once.
    phone = t.phone()
    phone.sign_in("employee:anna")
    phone.goto("/items")
    seen = Requests(phone)
    link = phone.get_by_role("link", name="Website", exact=True)
    phone.touch.hold(link, seconds=0.05)
    phone.wait_for_timeout(100)
    t.check(seen.to("/items?p=1", preload=True), "a touch on a link loads it at once")
    phone.touch.move_to(10, 700).lift()
