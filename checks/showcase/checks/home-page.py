"""On a phone, / and a sign-in lead to the person's home page (spec/ui.md 8,
«Home»): the showcase names «Graph» for everyone, and sends an admin to
«Welcome» until they press «Done» there; a sign-in from a page returns to
that page, even while the admin's welcome is not done."""

import re
from urllib.parse import urlparse


def path(page):
    return urlparse(page.url).path


def heading(page):
    return page.locator("h1").first.text_content().strip()


def run(t):
    anna = t.phone()
    anna.sign_in("employee:anna")
    t.check(path(anna) == "/graph", f"an employee's sign-in lands on «Graph»: {anna.url}")
    anna.goto("/")
    t.check(path(anna) == "/graph" and heading(anna) in ("Graph", "Graf"),
            f"and / leads there: {anna.url}")

    admin = t.phone()
    admin.goto("/")
    t.check(path(admin) == "/login", f"/ without a sign-in is the login: {admin.url}")
    admin.get_by_role("link", name=re.compile("As an administrator|Som administrator")).tap()
    admin.wait_for_url(re.compile(r"/welcome"))
    t.check(path(admin) == "/welcome" and heading(admin) in ("Welcome", "Velkommen"),
            f"an admin's sign-in lands on «Welcome»: {admin.url}")
    admin.goto("/")
    t.check(path(admin) == "/welcome", f"and so does / until it is done: {admin.url}")

    other = t.phone()
    other.goto("/login?next=%2Fitems")
    other.get_by_role("link", name=re.compile("As an administrator|Som administrator")).tap()
    other.wait_for_url(re.compile(r"/items"))
    t.check(path(other) == "/items",
            f"a sign-in from a page returns to it, while «Welcome» is not done: {other.url}")

    admin.get_by_role("button", name=re.compile("^(Done|Ferdig)$")).tap()
    admin.wait_for_url(re.compile(r"/graph"))
    t.check(path(admin) == "/graph", f"after «Done», «Graph»: {admin.url}")
    admin.goto("/")
    t.check(path(admin) == "/graph", f"and / leads there from now on: {admin.url}")

