"""A preload serves only the next request: a click preloads its link once
at most, every request, a GET too, drops the other preloads, and a page
that remembers its query is never shown as it was before a change made
in between; the request a preload's redirect leads to is marked a
preload too (spec/ui.md 4.1)."""

import re
from urllib.parse import urlparse


def path_of(url):
    url = urlparse(url)
    return url.path + (f"?{url.query}" if url.query else "")


def menu(page, name):
    return page.locator(".tun-nav-list").get_by_role("link", name=name, exact=True)


def visit(page, name, path):
    """Click NAME in the menu with the mouse, as a quick hand does, and wait
    for PATH."""
    menu(page, name).click()
    page.wait_for_url(re.compile(re.escape(path) + "$"))
    page.wait_for_load_state()
    page.wait_for_timeout(250)


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/saker?p=1")
    seen = []
    page.on("request", lambda request: seen.append(request))

    # 2. A quick click preloads its link once at most.
    visit(page, "Tilgang", "/access")
    seen.clear()
    visit(page, "Saker", "/saker?p=1")
    preloads = [r for r in seen if path_of(r.url) == "/saker" and r.headers.get("tun-preload") == "true"]
    t.check(len(preloads) <= 1, f"one click on «Saker» preloads it once at most ({len(preloads)})")

    # 1. The tracker's case: the tab cleared in between is not undone by a preload.
    page.get_by_role("link", name="Alle", exact=True).click()
    page.wait_for_url(re.compile(r"/saker\?p=$"))
    page.wait_for_timeout(250)
    visit(page, "Tilgang", "/access")
    visit(page, "Saker", "/saker")
    t.check(page.url.endswith("/saker"), f"after «Alle», «Saker» in the menu shows them all: {page.url}")
    current = page.evaluate("document.querySelector('.tun-tabs [aria-current]')?.textContent.trim()")
    t.check(current == "Alle", f"with «Alle» chosen ({current})")

    # 3. A GET drops the other preloads: «Tilgang» preloaded, then «Saker»
    # followed, then «Tilgang» asks the server.
    menu(page, "Tilgang").hover()
    page.wait_for_timeout(300)
    page.mouse.move(700, 500)
    menu(page, "Saker").evaluate("link => link.click()")
    page.wait_for_url(re.compile(r"/saker$"))
    page.wait_for_load_state()
    page.wait_for_timeout(250)
    seen.clear()
    menu(page, "Tilgang").evaluate("link => link.click()")
    page.wait_for_url(re.compile(r"/access$"))
    page.wait_for_load_state()
    asked = [r for r in seen if path_of(r.url) == "/access" and r.headers.get("tun-preload") != "true"]
    t.check(asked, "a GET in between drops the preload, so the next click asks")

    # 4. The request a preload's redirect leads to is marked too.
    page.goto("/saker?p=1")
    page.wait_for_timeout(250)
    visit(page, "Tilgang", "/access")
    seen.clear()
    menu(page, "Saker").hover()
    page.wait_for_timeout(500)
    hops = [r for r in seen if r.redirected_from is not None and path_of(r.url) == "/saker?p=1"]
    t.check(hops, "a preload of the bare /saker is sent on to the kept tab")
    t.check(hops and all(r.all_headers().get("tun-preload") == "true" for r in hops),
            f"and that request carries Tun-Preload too: {[r.all_headers().get('tun-preload') for r in hops]}")
