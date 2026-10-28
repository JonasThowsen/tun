"""A page that remembers its query: the project tab chosen on /items is
there again after another page, through the menu's boosted link, in the
address, and on another browser of the same account; «All» clears it
(spec/ui.md 8)."""

import re

CURRENT = "document.querySelector('.tun-tabs [aria-current]')?.textContent.trim()"


def menu(page, name):
    page.locator(".tun-nav-list").get_by_role("link", name=name, exact=True).click()


def run(t):
    page = t.desktop()
    page.sign_in("employee:anna")
    page.goto("/items")
    page.get_by_role("link", name="Website", exact=True).click()
    page.wait_for_url(re.compile(r"/items\?p=1$"))

    menu(page, "Access")
    page.wait_for_url(re.compile(r"/access"))
    menu(page, "Items")
    page.wait_for_url(re.compile(r"/items\?p=1$"))
    t.check(page.url.endswith("/items?p=1"), f"the menu's «Items» lands on the kept tab: {page.url}")
    t.check(page.evaluate(CURRENT) == "Website", "and shows it chosen")
    page.go_back()
    page.wait_for_url(re.compile(r"/access"))
    t.check("/access" in page.url, f"Back returns to the page before: {page.url}")

    other = t.desktop()
    other.sign_in("employee:anna")
    other.goto("/items")
    other.wait_for_url(re.compile(r"/items\?p=1$"))
    t.check(other.url.endswith("/items?p=1"), "another browser of the same account has it too")

    stranger = t.desktop()
    stranger.sign_in("employee:bo")
    stranger.goto("/items")
    t.check(stranger.url.endswith("/items"), f"another account does not: {stranger.url}")

    page.goto("/items?p=1")
    page.get_by_role("link", name="All", exact=True).click()
    page.wait_for_url(re.compile(r"/items\?p=$"))
    menu(page, "Access")
    page.wait_for_url(re.compile(r"/access"))
    menu(page, "Items")
    page.wait_for_url(re.compile(r"/items"))
    page.wait_for_load_state()
    t.check(page.url.endswith("/items"), f"«All» is kept as cleared: {page.url}")
    t.check(page.evaluate(CURRENT) == "All", "and «All» is chosen")
