"""A single-page screen of the showcase's own (spec/typescript.md 4, 5, 6):
its Svelte component as Nix built it. On a phone and wide it loads under
the page's policy with no violation, signs off through a session-only
operation called on /api with its session's proof, through its generated
module, and shows the answer with its icon, an asset of its own; shows a
refusal's message at its field and a call that got no answer; all without
a page load. In light and dark its colours are the pages' tokens', and a
theme the person chose on the pages holds. Signed out, its address leads
to the sign-in."""

import pathlib
import re
import sys
from urllib.parse import urlparse

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _policy  # noqa: E402

# The count the screen read, in its words' language or any other.
COUNT = "document.querySelector('#count').dataset.count"

# The pages' --background and --primary (spec/ui.md 3), as a browser
# computes them, by scheme.
COLOURS = {"light": ("rgb(255, 255, 255)", "rgb(23, 23, 23)"),
           "dark": ("rgb(25, 25, 28)", "rgb(237, 237, 237)")}


def signed_count(page):
    count = page.evaluate(f"() => {COUNT}")
    return int(count) if count is not None else None


def built_page(t, page, what):
    """What Vite built and the server answered keeps to the page's policy
    (spec/typescript.md 4): no inline script or style, the tokens linked."""
    html = page.request.get(page.url).text()
    t.check(re.search(r"<script(?![^>]*\ssrc=)[^>]*>", html) is None,
            f"{what}: no inline script in the screen's index.html")
    t.check("<style" not in html, f"{what}: no inline style in it")
    t.check(page.evaluate("document.querySelectorAll('style').length") == 0,
            f"{what}: and none put in the page while it runs")
    sheets = page.evaluate("[...document.styleSheets].map((s) => new URL(s.href).pathname)")
    t.check("/assets/tokens.css" in sheets
            and any(re.fullmatch(r"/sign-off/assets/[\w-]+\.css", s) for s in sheets),
            f"{what}: the tokens and the screen's own style sheet: {sheets}")


def colours(t, page, scheme, what):
    """The screen's ground and its button are the pages' tokens' colours."""
    ground, button = page.evaluate(
        "() => [getComputedStyle(document.body).backgroundColor,"
        " getComputedStyle(document.querySelector('button[type=submit]')).backgroundColor]")
    t.check((ground, button) == COLOURS[scheme],
            f"{what}: {scheme}, the pages' ground and ink: {ground}, {button}")


def sign_off(t, page, what):
    _policy.record(page)
    calls = []
    page.on("request", lambda request: calls.append(request)
            if urlparse(request.url).path.startswith("/api/") else None)
    page.sign_in("employee:anna")
    page.goto("/sign-off")
    page.wait_until(f"() => {COUNT} !== undefined", what=f"{what}: the count")
    before = signed_count(page)
    t.check(before is not None,
            f"{what}: the screen read the sign-offs: {page.evaluate(f'() => {COUNT}')}")
    t.check(page.locator("#count").text_content().strip() == f"{before} signed off so far",
            f"{what}: in English: {page.locator('#count').text_content()!r}")
    t.check(page.evaluate("document.documentElement.lang") == "en", f"{what}: <html lang>")
    built_page(t, page, what)
    colours(t, page, "light", what)
    policy = page.request.get(page.url).headers.get("content-security-policy", "")
    t.check("script-src 'self'" in policy and "default-src 'self'" in policy,
            f"{what}: the screen has the page's policy: {policy}")
    proof = page.evaluate("document.querySelector('meta[name=\"tun-api-proof\"]')?.content")
    t.check(isinstance(proof, str) and re.fullmatch("[0-9a-f]{64}", proof) is not None,
            f"{what}: the page carries its session's proof: {proof}")
    page.evaluate("window.__sameDocument = true")

    page.locator("button[type=submit]").click()
    page.wait_until("() => !document.querySelector('#note-error').hidden",
                    what=f"{what}: the refusal at its field")
    message = page.locator("#note-error").text_content().strip()
    t.check(message in ("must be filled in", "må fylles ut"),
            f"{what}: the field's own message, under the field: {message!r}")
    t.check(page.locator("#note").get_attribute("aria-invalid") == "true",
            f"{what}: the field is marked")

    page.locator("#note").fill(f"Checked {what}")
    page.locator("button[type=submit]").click()
    answer = page.wait_until(
        "() => { const t = document.querySelector('#answer').textContent;"
        " return t.startsWith('Signed off by') ? t : null; }",
        what=f"{what}: the answer of the sign-off")
    t.check(answer == "Signed off by employee:anna (claimed)",
            f"{what}: signed off as the person on the page: {answer!r}")
    t.check(page.locator("#note-error").is_hidden(), f"{what}: the refusal is gone")
    icon = page.wait_until(
        "() => { const i = document.querySelector('#signed');"
        " return i && i.complete && i.naturalWidth > 0 ? new URL(i.src).pathname : null; }",
        what=f"{what}: the answer's icon")
    t.check(re.fullmatch(r"/sign-off/assets/signed-[\w-]+\.svg", icon) is not None,
            f"{what}: the icon, a file of the screen's, not a data: URL: {icon}")
    page.wait_until(f"(n) => Number({COUNT}) === n", before + 1,
                    what=f"{what}: the count after it")
    made = [call for call in calls if urlparse(call.url).path == "/api/sign_offs_create"]
    t.check(len(made) == 2, f"{what}: two calls of sign_offs_create: {len(made)}")
    t.check(all(call.method == "POST" and call.headers.get("tun-api-proof") == proof
                and call.headers.get("content-type") == "application/json" for call in made),
            f"{what}: each a JSON POST carrying the proof")

    page.route("**/api/sign_offs_create", lambda route: route.abort())
    page.locator("#note").fill("Never sent")
    page.locator("button[type=submit]").click()
    failed = page.wait_until(
        "() => { const t = document.querySelector('#answer').textContent;"
        " return t.startsWith('No answer') ? t : null; }",
        what=f"{what}: the call that got no answer")
    t.check(failed == "No answer came. Try again.", f"{what}: said so: {failed!r}")
    page.unroute("**/api/sign_offs_create")

    t.check(page.evaluate("window.__sameDocument === true"), f"{what}: never a page load")
    t.check(_policy.violations(page) == [], f"{what}: no violation of the policy")
    t.check(page.evaluate("document.documentElement.scrollWidth <= window.innerWidth"),
            f"{what}: the screen does not scroll sideways")


def dark(t, page, what):
    """In a browser set to dark, the screen is dark."""
    _policy.record(page)
    page.sign_in("employee:anna")
    page.goto("/sign-off")
    page.wait_until(f"() => {COUNT} !== undefined", what=f"{what}: the count")
    colours(t, page, "dark", what)
    t.check(_policy.violations(page) == [], f"{what}: no violation of the policy")


def chosen_theme(t, page):
    """A person who chose dark on the pages, in a light browser."""
    page.sign_in("employee:anna")
    page.goto("/sign-off")
    page.wait_until(f"() => {COUNT} !== undefined", what="the count")
    colours(t, page, "light", "before a choice")
    page.evaluate("localStorage.setItem('tun-theme', 'dark')")
    page.reload()
    page.wait_until("() => document.documentElement.dataset.theme === 'dark'",
                    what="the chosen theme on <html>")
    colours(t, page, "dark", "the theme chosen on the pages")
    page.evaluate("localStorage.removeItem('tun-theme')")


def run(t):
    sign_off(t, t.phone(), "on a phone")
    sign_off(t, t.desktop(), "wide")
    dark(t, t.phone(scheme="dark"), "on a dark phone")
    dark(t, t.desktop(scheme="dark"), "wide and dark")
    chosen_theme(t, t.phone())
    t.close_pages()
    page = t.phone()
    page.goto("/sign-off")
    t.check(urlparse(page.url).path == "/login", f"signed out, to the sign-in: {page.url}")
