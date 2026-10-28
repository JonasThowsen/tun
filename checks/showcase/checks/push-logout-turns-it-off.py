"""Logging out turns this device's notifications off, in the browser and in
the tenant, whatever session they were tied to (spec/push.md 3)."""

import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _push  # noqa: E402


def run(t):
    page = t.desktop(permissions=["notifications"])
    _push.stand_in(page)
    page.sign_in("employee:anna")
    page.goto("/notifications")
    _push.state(page)
    page.get_by_role("switch", name="Notifications on this device").click()
    _push.wait_for_state(page, "on")
    endpoint = _push.endpoint(page)
    t.check(_push.tenant_has(page, endpoint) is True, "on to begin with")

    with page.expect_post("/push/unsubscribe") as post:
        page.get_by_role("button", name="Sign out").click()
    t.check(post.status == 200, f"the logout first deletes the subscription: {post.status}")
    page.wait_for_url(re.compile(r"/login"))
    t.check(_push.endpoint(page) is None, "and unsubscribes the browser")
    t.check(_push.stored_count(page, "check-push-unsubscribed") == 1, "once")

    page.sign_in("employee:anna")
    page.goto("/notifications")
    t.check(_push.state(page) == "off", "signed in again, the switch is off")
    t.check(_push.tenant_has(page, endpoint) is False, "and the tenant no longer has it")
