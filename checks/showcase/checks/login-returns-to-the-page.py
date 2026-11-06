"""On a phone, someone not signed in who opens a page sees the login page
at once, not a page that only links to it, and after signing in is on the
page they opened (spec/auth.md 3.4)."""

import re
from urllib.parse import urlparse


def run(t):
    page = t.phone()
    page.goto("/items?view=list")
    t.check(urlparse(page.url).path == "/login", f"the page goes to the login: {page.url}")
    t.check(page.locator("h1").first.text_content().strip() in ("Sign in", "Logg inn"),
            "the login page itself")
    t.check(page.get_by_text(re.compile("not signed in|ikke innlogget")).count() == 0,
            "with no notice in between")

    page.get_by_role("link", name=re.compile("As an administrator|Som administrator")).tap()
    page.wait_for_url(re.compile(r"/items"))
    t.check(urlparse(page.url).path == "/items" and "view=list" in page.url,
            f"after signing in, the page that was opened, with its query: {page.url}")

    page.goto("/")
    t.check(urlparse(page.url).path != "/login", f"signed in, / is the home page: {page.url}")
