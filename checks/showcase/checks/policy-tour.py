"""The login page, the specimen and a file's preview before it is sent work
under the page's Content-Security-Policy: the browser reports no
violation (spec/ui.md 4). Every page the page sweep reaches is the
generated check's, which records violations on each; the login page and
the specimen are left out of the sweep, and a preview from a blob: URL
is a script's."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _files  # noqa: E402
import _policy  # noqa: E402


def run(t):
    guest = t.desktop()
    _policy.record(guest)
    guest.goto("/login")
    t.check(guest.locator("h1").count() > 0, "the login page shows")
    t.check(_policy.violations(guest) == [], f"no violation on the login page: {_policy.violations(guest)}")

    page = t.desktop()
    _policy.record(page)
    page.sign_in("employee:anna")
    for path in ["/ui", "/ui/card"]:
        page.goto(path)
        page.wait_for_load_state("networkidle")
        found = _policy.violations(page)
        t.check(found == [], f"no violation on {path}: {found}")

    # A picture previewed from a blob: URL.
    _files.card_page(page, "Notification by email")
    page.locator(".tun-card input[type=file][name=files]").set_input_files(_files.path("photo.jpg"))
    preview = page.locator(".tun-file-input-item img.tun-file-input-preview")
    preview.wait_for()
    t.check(preview.evaluate("(img) => img.complete && img.naturalWidth > 0"),
            "the chosen picture's preview is shown")
    found = _policy.violations(page)
    t.check(found == [], f"no violation on a card with a preview: {found}")
