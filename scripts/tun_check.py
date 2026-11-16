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
                               both take another width and height,
                               permissions (["notifications"]) and
                               user_agent for the page's browser, and
                               javascript=False for a browser without it
    page.sign_in(actor)        sign in as "employee:anna" (claimed identity)
    page.goto(path)
    page.card(title), page.column(key)
                               a board's card and column, as locators
    page.visible_width(css)    how many pixels of the element are on screen
    page.touch                 a finger: hold, move_to, stay, lift, swipe
    page.expect_post(path)     with page.expect_post("/x") as post: ...;
                               then post.body and post.status
    t.check(condition, text)   record one check; carry on when it fails
    t.close_pages()            close the pages opened so far (their errors recorded)

A check reads no clock (spec/preview.md 4). It waits for what it reads:
    page.wait_until(function, arg=None, what="...")
                               until the page's "(arg) => ..." is true; its value
    with page.expect_htmx(): ...
                               then every htmx request begun is answered and swapped
    page.poll_until(predicate, what="...")
                               until the check's own Python function is true
    page.touch.hold_to_drag(card)
                               a finger held until the board's drag begins
its speed is what the server spent:
    speed = page.server_speed(path, headers=None, runs=9)
    t.check_fast(speed, limit_ms, text)
and motion is read held still:
    page.hold_motion(), page.release_motion()
    page.animations(selector)  each running animation and transition
    page.seek_motion(selector, ms)
                               them at MS (None: the end), to read that moment
A page's own timers run on page.clock, Playwright's, which a check holds
and advances. Every wait has the page's one deadline, PAGE_TIMEOUT_MS.

Anything else on a page is Playwright's (page.evaluate, page.locator, ...).
page.wait_for_function takes a function, "() => ...": a bare expression is
evaluated as a string in the page, and the page's policy refuses that
(spec/ui.md 4).
"""

import importlib.util
import json
import os
import pathlib
import statistics
import sys
import time
import traceback
from contextlib import contextmanager
from urllib.parse import urlparse

from playwright.sync_api import TimeoutError as PlaywrightTimeout
from playwright.sync_api import sync_playwright

# Loading a check would leave __pycache__ beside it, in the client's checks/.
sys.dont_write_bytecode = True


PAGE_TIMEOUT_MS = 120_000
"""How long a navigation, or any wait, may take: the one deadline."""


class Waited(Exception):
    """A wait that passed the deadline. Its text says what was waited for and
    what was seen last; the check fails with it."""


BOARD_DRAGGING = "() => document.querySelector('[data-tun-board-moving]') !== null"


class Touch:
    """One finger on a page, through the DevTools protocol's touch events,
    which scroll and drag as a finger does; Playwright's own taps do not
    move."""

    def __init__(self, page, cdp):
        self.page = page
        self.cdp = cdp
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

    def hold_to_drag(self, target):
        """Put the finger on TARGET, a board's card, and keep it still until
        the board begins to drag it: its hold is the page's timer, which a
        busy machine runs late."""
        self.x, self.y = self._point(target)
        self._send("touchStart")
        self.page.wait_until(BOARD_DRAGGING, what="the board to begin dragging the held card")
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
        end = time.monotonic() + seconds
        while time.monotonic() < end:
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


class Speed:
    """What the server says it spent on a request (its Server-Timing), the
    medians of RUNS: ms, its processor time, or its wall time when it could
    not tell that (wall_only); db_ms, the database server's share; wall_ms."""

    def __init__(self, path, timings):
        self.path, self.runs = path, len(timings)
        self.wall_only = any("cpu" not in each for each in timings)
        self.wall_ms = statistics.median(each.get("total", 0.0) for each in timings)
        self.db_ms = None if self.wall_only else statistics.median(each.get("db", 0.0) for each in timings)
        self.ms = self.wall_ms if self.wall_only else statistics.median(each["cpu"] for each in timings)

    def __str__(self):
        kind = "wall time (the server could not tell its processor time)" if self.wall_only \
            else f"the server's processor time (median of {self.runs}, Postgres {self.db_ms:.1f} ms)"
        return f"{self.path}: {self.ms:.1f} ms of {kind}; wall {self.wall_ms:.1f} ms; {machine()}"


def machine():
    """The machine's load, for a failure that depends on time."""
    return f"load {os.getloadavg()[0]:.2f} on {os.cpu_count()} processors"


# The server's own timing for PATH, RUNS times after one to warm up
# (spec/core.md 7.7): Server-Timing's names and milliseconds, for each.
SERVER_SPEED = """async ([path, headers, runs]) => {
  const ask = async () => {
    const answer = await fetch(path, {headers});
    await answer.text();
    const timing = {};
    for (const part of (answer.headers.get('Server-Timing') || '').split(',')) {
      const [name, duration] = part.trim().split(';dur=');
      if (duration !== undefined) timing[name] = parseFloat(duration);
    }
    return timing;
  };
  await ask();
  const timings = [];
  for (let i = 0; i < runs; i += 1) timings.push(await ask());
  return timings;
}"""

# Counts the htmx requests begun and ended on this document, once.
HTMX_WATCH = """() => {
  if (!window.tunHtmx) {
    const seen = window.tunHtmx = {begun: 0, ended: 0};
    document.addEventListener('htmx:before:request', () => { seen.begun += 1; }, true);
    document.addEventListener('htmx:finally:request', () => { seen.ended += 1; }, true);
  }
  return window.tunHtmx.begun;
}"""

HTMX_ENDED = """(begun) => window.tunHtmx && window.tunHtmx.begun > begun
                               && window.tunHtmx.ended >= window.tunHtmx.begun"""

# The animations of the element SELECTOR, or of the whole document when it
# is null (a dialog's ::backdrop among them).
ANIMATIONS_OF = """(selector, subtree) => {
  if (selector === null) return document.getAnimations();
  const element = document.querySelector(selector);
  return element ? element.getAnimations({subtree}) : null;
}"""

ANIMATIONS = """([selector, subtree]) => {
  const animations = (""" + ANIMATIONS_OF + """)(selector, subtree);
  if (!animations) return null;
  return animations.map((animation) => {
    const timing = animation.effect.getTiming();
    const transition = animation.transitionProperty !== undefined;
    return {kind: transition ? 'transition' : 'animation',
            name: transition ? animation.transitionProperty : animation.animationName,
            duration_ms: animation.effect.getComputedTiming().duration,
            delay_ms: timing.delay, easing: timing.easing,
            keyframes: animation.effect.getKeyframes().map((frame) => ({...frame})),
            current_ms: animation.currentTime, state: animation.playState};
  });
}"""

SEEK = """([selector, ms, subtree]) => {
  const animations = (""" + ANIMATIONS_OF + """)(selector, subtree) || [];
  for (const animation of animations) {
    animation.pause();
    // An animation that runs for ever has no end to finish at.
    try { if (ms === null) animation.finish(); else animation.currentTime = ms; } catch (e) {}
  }
  return animations.length;
}"""


class Page:
    """A Playwright page with Tun's helpers. Anything else is the page's."""

    def __init__(self, run, page, touch):
        self._run = run
        self._page = page
        self.errors = []
        page.on("pageerror", lambda error: self.errors.append(str(error)))
        self._cdp = None
        self.touch = Touch(self, self.cdp()) if touch else None

    def cdp(self):
        """The page's DevTools protocol session."""
        if self._cdp is None:
            self._cdp = self._page.context.new_cdp_session(self._page)
        return self._cdp

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

    def wait_until(self, function, arg=None, what=None):
        """Wait until FUNCTION, "(arg) => ...", gives a true value in the page,
        and return that value. Past the deadline the check fails, saying what
        was waited for (WHAT) and what the function last gave."""
        try:
            return self._page.wait_for_function(function, arg=arg, timeout=PAGE_TIMEOUT_MS).json_value()
        except PlaywrightTimeout:
            try:
                last = self._page.evaluate(function, arg)
            except Exception as error:
                last = f"nothing: {error}"
            raise Waited(f"waited {PAGE_TIMEOUT_MS // 1000} s for {what or function}; "
                         f"it last gave {last!r} ({machine()})") from None

    def poll_until(self, predicate, what):
        """Wait until PREDICATE, a Python function of nothing, gives a true
        value, asking it between the page's events: for what only the check
        sees, such as a request a route holds. Its value; past the deadline
        the check fails, saying WHAT was waited for."""
        end = time.monotonic() + PAGE_TIMEOUT_MS / 1000
        while True:
            value = predicate()
            if value:
                return value
            if time.monotonic() > end:
                raise Waited(f"waited {PAGE_TIMEOUT_MS // 1000} s for {what} ({machine()})")
            self._page.wait_for_timeout(50)

    @contextmanager
    def expect_htmx(self):
        """After the block, wait until every htmx request it began has been
        answered, swapped and settled (htmx:finally:request comes after the
        swap); at least one must begin."""
        begun = self._page.evaluate(HTMX_WATCH)
        yield
        self.wait_until(HTMX_ENDED, begun, what="the answer to the htmx request the step began")

    def server_speed(self, path, headers=None, runs=9):
        """What the server says it spent on PATH (spec/core.md 7.7): a Speed,
        the medians of RUNS requests after one to warm up, one at a time."""
        timings = self._page.evaluate(SERVER_SPEED, [path, headers or {}, runs])
        if not timings or any(not each for each in timings):
            raise RuntimeError(f"{path} was answered without Server-Timing (spec/core.md 7.7)")
        return Speed(path, timings)

    def hold_motion(self):
        """Hold every animation and transition of the page at its start, until
        release_motion: what is read meanwhile does not depend on the clock."""
        self.cdp().send("Animation.enable")
        self.cdp().send("Animation.setPlaybackRate", {"playbackRate": 0})

    def release_motion(self):
        self.cdp().send("Animation.setPlaybackRate", {"playbackRate": 1})

    def animations(self, selector, subtree=False):
        """The running animations and transitions of the element SELECTOR (and
        of its descendants with SUBTREE), or of the whole page with None, each
        a dict: kind, name, duration_ms, delay_ms, easing, keyframes,
        current_ms, state; None when there is no such element."""
        return self._page.evaluate(ANIMATIONS, [selector, subtree])

    def seek_motion(self, selector, ms, subtree=False):
        """Put the element's animations and transitions at MS, paused, or at
        their end with None, so the style and boxes read next are that
        moment's; how many there were."""
        return self._page.evaluate(SEEK, [selector, ms, subtree])

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
        # A check is not a speed test (spec/tooling.md, "Speed and time in
        # tests"): a page a loaded machine serves slowly is waited for, one
        # that never loads still fails.  A check's own timeouts stay.
        context.set_default_navigation_timeout(PAGE_TIMEOUT_MS)
        context.set_default_timeout(PAGE_TIMEOUT_MS)
        if permissions:
            context.grant_permissions(permissions, origin=self.url)
        wrapped = Page(self, context.new_page(), touch)
        self.pages.append(wrapped)
        self.page = wrapped
        return wrapped

    def phone(self, width=390, height=844, permissions=None, user_agent=None, javascript=True,
              scheme="light"):
        return self._new_page(True, permissions, viewport={"width": width, "height": height},
                              has_touch=True, is_mobile=True, device_scale_factor=2,
                              java_script_enabled=javascript, color_scheme=scheme,
                              **({"user_agent": user_agent} if user_agent else {}))

    def desktop(self, width=1280, height=800, permissions=None, user_agent=None, javascript=True,
                scheme="light"):
        return self._new_page(False, permissions, viewport={"width": width, "height": height},
                              java_script_enabled=javascript, color_scheme=scheme,
                              **({"user_agent": user_agent} if user_agent else {}))

    def close_pages(self):
        """Close every page opened so far, each after its JavaScript errors
        are recorded: a check of many pages frees their connections, which
        the server counts per address, before it opens more."""
        for page in self.pages:
            if page.errors:
                self.page = page
                self.check(False, f"no JavaScript errors: {page.errors}")
            page.context.close()
        self.pages = []
        self.page = None

    def check_fast(self, speed, limit_ms, text):
        """Record whether SPEED, from page.server_speed, is under LIMIT_MS."""
        ok = speed.ms < limit_ms
        return self.check(ok, f"{text}: {speed}; {'under' if ok else 'over'} its limit of {limit_ms} ms")

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
    except (Waited, AssertionError) as stopped:
        # A wait past its deadline, or a check's own assert: its message is
        # the failure, not a traceback.
        run.check(False, str(stopped))
    except Exception:
        error = traceback.format_exc()
        run.check(False, "the check ran to its end")
    run.close_pages()
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
