"""The generated check (spec/preview.md 4, «The generated check») sees what
is wrong with a page: a page that answers 404 or does not load, one made
wider than the window, an error in its console, a JavaScript error and
code the page's policy refuses each fail it, a page with none of these
passes, and only a console error about /favicon.ico is the browser's
own."""

import importlib.util
import pathlib

GENERATED = (pathlib.Path(__file__).resolve().parents[3]
             / "scripts" / "checks" / "generated-every-page-at-both-widths.py")

BREAK = """(what) => {
  if (what === 'wide') {
    const wide = document.createElement('div');
    wide.style.width = '3000px';
    wide.style.height = '10px';
    document.body.append(wide);
  }
  if (what === 'console') console.error('a planted console error');
  if (what === 'script') setTimeout(() => { throw new Error('a planted error'); }, 0);
  if (what === 'policy') {
    const script = document.createElement('script');
    script.textContent = 'window.__planted = true';
    document.body.append(script);
  }
}"""


def generated():
    spec = importlib.util.spec_from_file_location("generated_check", GENERATED)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Message:
    """A console message as Playwright gives it, about URL."""

    def __init__(self, url):
        self.text = "Failed to load resource: the server responded with a status of 404"
        self.type = "error"
        self.location = {"url": url}


def run(t):
    check = generated()
    page = check.watched(t.desktop())
    page.sign_in("employee:anna")
    page.errors.clear()
    page.console_errors.clear()

    found = check.opened(page, "/items")
    t.check(found == [], f"a page with nothing wrong passes: {found}")

    # A public page's own «not found», a page with a body.
    found = check.opened(page, "/quote/none")
    t.check(any(text.startswith("answered 404") for text in found), f"a 404 fails: {found}")

    found = check.opened(page, "/no-such-page")
    t.check(any(text.startswith(("answered 404", "did not load")) for text in found),
            f"a page that does not load fails, and the check goes on: {found}")

    for what, says in (("wide", "scrolls sideways"), ("console", "console errors"),
                       ("script", "JavaScript errors"), ("policy", "policy violations")):
        response = page.goto("/items")
        page.evaluate(BREAK, what)
        if what == "script":
            page.poll_until(lambda: page.errors, what="the planted error")
        if what == "policy":
            page.wait_until("() => window.__tunViolations.length > 0", what="the refused script")
        found = check.problems_of(page, response)
        t.check(any(text.startswith(says) for text in found), f"{what}: the check says {says}: {found}")

    t.check(check.browser_own(Message("http://127.0.0.1:1/favicon.ico")),
            "a console error about /favicon.ico is the browser's own")
    t.check(not check.browser_own(Message("http://127.0.0.1:1/assets/app.js")),
            "about anything else it is the page's")
