"""Run browser checks against a running preview (spec/preview.md 4).

Usage: tun-check-python tun_check.py OUT URL CHECK.py...

Each CHECK.py defines run(t). It is run in Chromium, through Playwright,
against the preview at URL. OUT/NAME.json gets its results, and
OUT/NAME-N.png a screenshot for each check that failed. Exit status: 0
when every check passed, 1 when one failed, 2 for a usage error.

`tun check` starts the preview and calls this; a check does not import it.
What a check gets:

    t.phone(), t.desktop()     a page at 390x844 with touch, or 1280x800
                               with a mouse, each with its own cookies;
                               both take another width and height, and
                               permissions (["notifications"]) and
                               user_agent for the page's browser
    page.sign_in(actor)        sign in as "employee:anna" (claimed identity)
    page.goto(path)
    page.card(title), page.column(key)
                               a board's card and column, as locators
    page.visible_width(css)    how many pixels of the element are on screen
    page.touch                 a finger: hold, move_to, stay, lift, swipe
    page.expect_post(path)     with page.expect_post("/x") as post: ...;
                               then post.body and post.status
    t.check(condition, text)   record one check; carry on when it fails

Anything else on a page is Playwright's (page.evaluate, page.locator, ...).
"""

import importlib.util
import json
import pathlib
import sys
import time
import traceback
from contextlib import contextmanager
from urllib.parse import urlparse

from playwright.sync_api import sync_playwright

# Loading a check would leave __pycache__ beside it, in the client's checks/.
sys.dont_write_bytecode = True


class Touch:
    """One finger on a page, through the DevTools protocol's touch events,
    which scroll and drag as a finger does; Playwright's own taps do not
    move."""

    def __init__(self, page):
        self.page = page
        self.cdp = page.context.new_cdp_session(page)
        self.x = self.y = 0

    def _send(self, kind):
        points = [] if kind == "touchEnd" else [{"x": self.x, "y": self.y}]
        self.cdp.send("Input.dispatchTouchEvent", {"type": kind, "touchPoints": points})

    def _point(self, target):
        if isinstance(target, tuple):
            return target
        box = target.bounding_box()
        # Left of the middle: a card's right side holds its menu button.
        return box["x"] + min(40, box["width"] / 2), box["y"] + box["height"] / 2

    def hold(self, target, seconds=0.45):
        """Put the finger on TARGET, a locator or (x, y), and keep it still."""
        self.x, self.y = self._point(target)
        self._send("touchStart")
        time.sleep(seconds)
        return self

    def move_to(self, x, y, steps=6, every=0.02):
        """Move the finger to (x, y) in STEPS moves."""
        x0, y0 = self.x, self.y
        for i in range(1, steps + 1):
            self.x, self.y = x0 + (x - x0) * i / steps, y0 + (y - y0) * i / steps
            self._send("touchMove")
            time.sleep(every)
        return self

    def stay(self, seconds):
        """Keep the finger where it is, as a held finger does: still, with a
        move now and then."""
        end = time.time() + seconds
        while time.time() < end:
            self._send("touchMove")
            time.sleep(0.1)
        return self

    def lift(self):
        self._send("touchEnd")
        return self

    def swipe(self, start, end, steps=9):
        """A quick swipe from START to END, each (x, y): a finger that does
        not hold first."""
        self.x, self.y = start
        self._send("touchStart")
        self.move_to(*end, steps=steps, every=0.016)
        return self.lift()


class Post:
    body = ""
    status = None


class Page:
    """A Playwright page with Tun's helpers. Anything else is the page's."""

    def __init__(self, run, page, touch):
        self._run = run
        self._page = page
        self.errors = []
        page.on("pageerror", lambda error: self.errors.append(str(error)))
        self.touch = Touch(page) if touch else None

    def __getattr__(self, name):
        return getattr(self._page, name)

    def goto(self, path):
        self._run.page = self
        return self._page.goto(self._run.url + path)

    def sign_in(self, actor):
        return self.goto(f"/login?actor={actor}")

    def card(self, title):
        """The card titled TITLE exactly, not the copy that follows a drag."""
        return (self._page.locator("[data-tun-board-card]:not([data-tun-board-ghost])")
                .filter(has=self._page.get_by_text(title, exact=True)).first)

    def column(self, key):
        return self._page.locator(f"[data-tun-board-column='{key}']")

    def visible_width(self, selector):
        return self._page.evaluate(
            """(selector) => {
                 const r = document.querySelector(selector)?.getBoundingClientRect();
                 return r ? Math.round(Math.max(0, Math.min(r.right, innerWidth) - Math.max(r.left, 0))) : 0;
               }""", selector)

    @contextmanager
    def expect_post(self, path):
        post = Post()
        with self._page.expect_response(
                lambda r: r.request.method == "POST" and urlparse(r.url).path == path) as info:
            yield post
        response = info.value
        post.status = response.status
        post.body = response.request.post_data or ""


class Run:
    """What a check's run(t) gets: its pages and its record of checks."""

    def __init__(self, browser, url, out, name):
        self.browser, self.url, self.out, self.name = browser, url, out, name
        self.results = []
        self.pages = []
        self.page = None

    def _new_page(self, touch, permissions=None, **options):
        context = self.browser.new_context(**options)
        if permissions:
            context.grant_permissions(permissions, origin=self.url)
        wrapped = Page(self, context.new_page(), touch)
        self.pages.append(wrapped)
        self.page = wrapped
        return wrapped

    def phone(self, width=390, height=844, permissions=None, user_agent=None):
        return self._new_page(True, permissions, viewport={"width": width, "height": height},
                              has_touch=True, is_mobile=True, device_scale_factor=2,
                              **({"user_agent": user_agent} if user_agent else {}))

    def desktop(self, width=1280, height=800, permissions=None, user_agent=None):
        return self._new_page(False, permissions, viewport={"width": width, "height": height},
                              **({"user_agent": user_agent} if user_agent else {}))

    def check(self, condition, text):
        result = {"text": text, "ok": bool(condition), "screenshot": None}
        if not condition and self.page is not None:
            shot = self.out / f"{self.name}-{len(self.results) + 1}.png"
            try:
                self.page.screenshot(path=str(shot))
                result["screenshot"] = str(shot)
            except Exception:
                pass
        self.results.append(result)
        return bool(condition)


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem.replace("-", "_"), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_check(browser, url, out, path):
    name = path.stem
    run = Run(browser, url, out, name)
    error = None
    description = ""
    try:
        module = load(path)
        description = (module.__doc__ or "").strip().splitlines()[0] if module.__doc__ else ""
        module.run(run)
    except Exception:
        error = traceback.format_exc()
        run.check(False, "the check ran to its end")
    for page in run.pages:
        if page.errors:
            run.page = page
            run.check(False, f"no JavaScript errors: {page.errors}")
        page.context.close()
    if not run.results:
        run.check(False, "the check checks something")
    report = {"name": name, "description": description,
              "passed": all(r["ok"] for r in run.results),
              "results": run.results, "error": error}
    (out / f"{name}.json").write_text(json.dumps(report, ensure_ascii=False, indent=1))
    return report["passed"]


def main(argv):
    if len(argv) < 4:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        return 2
    out, url, checks = pathlib.Path(argv[1]), argv[2].rstrip("/"), [pathlib.Path(a) for a in argv[3:]]
    out.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as playwright:
        # The whole browser, headless: Playwright's default headless shell
        # refuses notifications, which the push checks need.
        browser = playwright.chromium.launch(channel="chromium")
        passed = [run_check(browser, url, out, path) for path in checks]
        browser.close()
    return 0 if all(passed) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
