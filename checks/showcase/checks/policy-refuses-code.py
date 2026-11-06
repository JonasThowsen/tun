"""Code that gets into a page does not run: the browser refuses an inline
script and a string of code (eval, a timer's text), and says so; Tun's own
script still runs (spec/ui.md 4)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _policy  # noqa: E402

INJECT = """() => {
  const script = document.createElement('script');
  script.textContent = 'window.__inline = true';
  document.body.append(script);
  // Run from a timer, as the page's own code would: what Playwright
  // evaluates itself is let through.
  setTimeout(() => {
    try { window.__eval = String(eval('1 + 1')); } catch (error) { window.__eval = error.name; }
    setTimeout('window.__timer = true', 0);
  }, 0);
}"""


def run(t):
    page = t.desktop()
    _policy.record(page)
    page.sign_in("employee:anna")
    page.goto("/items")
    header = page.request.get(page.url).headers.get("content-security-policy", "")
    t.check("script-src 'self'" in header, f"the page has the policy: {header}")
    t.check(page.evaluate("typeof tunOnContent") == "function", "Tun's own script ran")

    page.evaluate(INJECT)
    page.wait_for_timeout(300)
    evaluated = page.evaluate("window.__eval")
    t.check(page.evaluate("window.__inline") is None, "an inline script written into the page did not run")
    t.check(evaluated == "EvalError", f"eval was refused: {evaluated}")
    t.check(page.evaluate("window.__timer") is None, "a timer's text did not run")
    found = _policy.violations(page)
    t.check(any(v.startswith("script-src") for v in found), f"the browser reported it: {found}")
