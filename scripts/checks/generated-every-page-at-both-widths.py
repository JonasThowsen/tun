"""Every page the page sweep reaches, as each of its actors, at 390 and
1280 px: none answers 400 or more, scrolls sideways, has a JavaScript
error or an error in its console, or a violation of its policy
(spec/preview.md 4, «The generated check»).

Tun makes this check for every client; `tun check` runs it first. Its
server writes the pages the sweep's GETs got, as each actor, to the file
TUN_PAGE_SWEEP names, before it serves."""

import json
import os
import pathlib

# Added to every document before the page's own scripts: what the browser
# reports against the page's policy, and the htmx requests begun and ended.
WATCH = """
window.__tunViolations = [];
document.addEventListener('securitypolicyviolation', (event) => {
  window.__tunViolations.push(`${event.effectiveDirective} ${event.blockedURI || 'inline'}`);
});
window.__tunHtmx = {begun: 0, ended: 0};
document.addEventListener('htmx:before:request', () => { window.__tunHtmx.begun += 1; }, true);
document.addEventListener('htmx:finally:request', () => { window.__tunHtmx.ended += 1; }, true);
"""

# Every htmx request the page began, such as a part it loads once it is
# shown, has been answered.
SETTLED = "() => !window.__tunHtmx || window.__tunHtmx.ended >= window.__tunHtmx.begun"

READ = """() => ({width: document.documentElement.scrollWidth, window: window.innerWidth,
                 violations: window.__tunViolations || []})"""


def swept():
    """The sweep's actors and their pages, as its server wrote them."""
    sweep = pathlib.Path(os.environ["TUN_PAGE_SWEEP"])
    return json.loads(sweep.read_text(encoding="utf-8"))["actors"]


def browser_own(message):
    """True for the browser's own look for /favicon.ico, which it makes for a
    page that names no icon, such as a single-page screen: not the page's
    error."""
    url = (message.location or {}).get("url") or ""
    return url.split("?")[0].endswith("/favicon.ico")


def console_text(message):
    """A console message's text, with the address it is about when it names one."""
    url = (message.location or {}).get("url")
    return f"{message.text} ({url})" if url else message.text


def watched(page):
    """PAGE, recording its console's errors and what WATCH sees."""
    page.add_init_script(WATCH)
    page.console_errors = []
    page.on("console", lambda message: page.console_errors.append(console_text(message))
            if message.type == "error" and not browser_own(message) else None)
    return page


def problems_of(page, response):
    """What is wrong with the page PAGE shows, which RESPONSE answered."""
    found = []
    if response is not None and response.status >= 400:
        found.append(f"answered {response.status}")
    page.wait_until(SETTLED, what="the page's htmx requests to be answered")
    seen = page.evaluate(READ)
    if seen["width"] > seen["window"]:
        found.append(f"scrolls sideways ({seen['width']} px in {seen['window']})")
    if seen["violations"]:
        found.append(f"policy violations: {seen['violations']}")
    if page.errors:
        found.append(f"JavaScript errors: {page.errors}")
    if page.console_errors:
        found.append(f"console errors: {page.console_errors}")
    # Each page's errors are its own result's, not the next page's.
    page.errors.clear()
    page.console_errors.clear()
    return found


def opened(page, path):
    """Open PATH in PAGE and say what is wrong with it: a page the browser
    could not load at all, such as an error answered with no body, is that."""
    try:
        response = page.goto(path)
    except Exception as error:  # Playwright's, for a navigation that failed
        # Chromium shows its own error page instead, a navigation of its own
        # that would cut the next page's short: it is waited for first.
        page.wait_for_url(lambda url: url.startswith("chrome-error:"))
        page.errors.clear()
        page.console_errors.clear()
        return [f"did not load: {str(error).splitlines()[0]}"]
    return problems_of(page, response)


def run(t):
    actors = swept()
    for entry in actors:
        actor, paths = entry["actor"], entry["paths"]
        who = actor or "no one"
        for width, page in ((390, watched(t.phone())), (1280, watched(t.desktop()))):
            if actor:
                page.sign_in(actor)
                page.errors.clear()
                page.console_errors.clear()
            for path in paths:
                found = opened(page, path)
                said = f": {'; '.join(found)}" if found else ""
                t.check(not found, f"{width} px, {who}: {path}{said}", picture=page)
        t.close_pages()
    t.check(True, f"{sum(len(entry['paths']) for entry in actors)} pages of "
                  f"{len(actors)} actors, each at 390 and 1280 px")
