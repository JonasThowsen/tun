"""A page that remembers its query: the project tab chosen on /saker is
there again after another page, through the menu's boosted link, in the
address, and on another browser of the same account; «Alle» clears it
(spec/ui.md 8)."""

import re

CURRENT = "document.querySelector('.tun-tabs [aria-current]')?.textContent.trim()"


def menu(page, name):
    page.locator(".tun-nav-list").get_by_role("link", name=name, exact=True).click()


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/saker")
    page.get_by_role("link", name="Nettside", exact=True).click()
    page.wait_for_url(re.compile(r"/saker\?p=1$"))

    menu(page, "Tilgang")
    page.wait_for_url(re.compile(r"/access"))
    menu(page, "Saker")
    page.wait_for_url(re.compile(r"/saker\?p=1$"))
    t.check(page.url.endswith("/saker?p=1"), f"the menu's «Saker» lands on the kept tab: {page.url}")
    t.check(page.evaluate(CURRENT) == "Nettside", "and shows it chosen")
    page.go_back()
    page.wait_for_url(re.compile(r"/access"))
    t.check("/access" in page.url, f"Back returns to the page before: {page.url}")

    other = t.desktop()
    other.sign_in("employee:anna")
    other.goto("/saker")
    other.wait_for_url(re.compile(r"/saker\?p=1$"))
    t.check(other.url.endswith("/saker?p=1"), "another browser of the same account has it too")

    stranger = t.desktop()
    stranger.sign_in("employee:bo")
    stranger.goto("/saker")
    t.check(stranger.url.endswith("/saker"), f"another account does not: {stranger.url}")

    page.goto("/saker?p=1")
    page.get_by_role("link", name="Alle", exact=True).click()
    page.wait_for_url(re.compile(r"/saker\?p=$"))
    menu(page, "Tilgang")
    page.wait_for_url(re.compile(r"/access"))
    menu(page, "Saker")
    page.wait_for_url(re.compile(r"/saker"))
    page.wait_for_load_state()
    t.check(page.url.endswith("/saker"), f"«Alle» is kept as cleared: {page.url}")
    t.check(page.evaluate(CURRENT) == "Alle", "and «Alle» is chosen")
