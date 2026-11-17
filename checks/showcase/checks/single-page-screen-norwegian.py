"""The showcase's single-page screen on its Norwegian tenant
(spec/typescript.md 4): the server writes the page's language into its
<html lang>, and the screen's words, its own, are Norwegian, the
refusal's message the server's Norwegian."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _policy  # noqa: E402

SCENARIO = "norwegian"


def run(t):
    page = t.phone()
    _policy.record(page)
    page.sign_in("employee:anna")
    page.goto("/sign-off")
    page.wait_until("() => document.querySelector('#count').dataset.count !== undefined",
                    what="the count")
    t.check(page.evaluate("document.documentElement.lang") == "nb", "<html lang> is nb")
    count = page.evaluate("document.querySelector('#count').dataset.count")
    t.check(page.locator("#count").text_content().strip() == f"{count} signert så langt",
            f"the count in Norwegian: {page.locator('#count').text_content()!r}")
    t.check(page.locator("h1").text_content().strip() == "Signer", "the heading")
    t.check(page.locator("label[for=note]").text_content().strip() == "Notat", "the label")
    t.check(page.locator("button[type=submit]").text_content().strip() == "Signer", "the button")
    t.check(page.evaluate("document.title") == "Signer", "the title")

    page.locator("button[type=submit]").click()
    page.wait_until("() => !document.querySelector('#note-error').hidden",
                    what="the refusal at its field")
    message = page.locator("#note-error").text_content().strip()
    t.check(message == "må fylles ut", f"the server's Norwegian message: {message!r}")

    page.locator("#note").fill("Sjekket på norsk")
    page.locator("button[type=submit]").click()
    answer = page.wait_until(
        "() => { const t = document.querySelector('#answer').textContent;"
        " return t.startsWith('Signert av') ? t : null; }",
        what="the answer of the sign-off")
    t.check(answer == "Signert av employee:anna (claimed)", f"the answer in Norwegian: {answer!r}")
    t.check(_policy.violations(page) == [], "no violation of the policy")
    t.close_pages()
