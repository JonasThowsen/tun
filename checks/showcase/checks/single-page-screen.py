"""A single-page screen of the showcase's own (spec/typescript.md 4, 5): on
a phone and wide it loads under the page's policy with no violation, signs
off through a session-only operation called on /api with its session's
proof, through its generated module, and shows the answer; shows a
refusal's message at its field and a call that got no answer; all without
a page load. Signed out, its address leads to the sign-in."""

import pathlib
import re
import sys
from urllib.parse import urlparse

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _policy  # noqa: E402

COUNT = "document.querySelector('#count').textContent"
SIGNED = r"^(\d+) signed off so far$"


def signed_count(page):
    match = re.match(SIGNED, page.evaluate(f"() => {COUNT}").strip())
    return int(match.group(1)) if match else None


def sign_off(t, page, what):
    _policy.record(page)
    calls = []
    page.on("request", lambda request: calls.append(request)
            if urlparse(request.url).path.startswith("/api/") else None)
    page.sign_in("employee:anna")
    page.goto("/sign-off")
    page.wait_until(f"() => /signed off so far/.test({COUNT})", what=f"{what}: the count")
    before = signed_count(page)
    t.check(before is not None,
            f"{what}: the screen read the sign-offs: {page.evaluate(f'() => {COUNT}')}")
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
    page.wait_until(f"(n) => {COUNT}.startsWith(n + ' ')", before + 1,
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


def run(t):
    sign_off(t, t.phone(), "on a phone")
    sign_off(t, t.desktop(), "wide")
    t.close_pages()
    page = t.phone()
    page.goto("/sign-off")
    t.check(urlparse(page.url).path == "/login", f"signed out, to the sign-in: {page.url}")
