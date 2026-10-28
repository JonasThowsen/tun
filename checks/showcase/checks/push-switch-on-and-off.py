"""On a computer with notifications allowed, the switch on «Notifications» turns
this device's notifications on and off, and loading the page asks for
nothing (spec/push.md 2.1)."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _push  # noqa: E402


def run(t):
    page = t.desktop(permissions=["notifications"])
    _push.stand_in(page)
    page.sign_in("employee:anna")
    page.goto("/notifications")
    switch = page.get_by_role("switch", name="Notifications on this device")
    t.check(_push.state(page) == "off", "the switch starts off")
    t.check(switch.is_visible() and switch.is_enabled(), "and can be turned on")
    t.check(_push.status(page) == "Get notified here when something needs you.", "with its description")
    t.check(_push.stored_count(page, "check-push-asked") == 0, "loading the page asks nothing")

    switch.click()
    _push.wait_for_state(page, "on")
    t.check(switch.is_checked(), "on after a click")
    t.check(_push.stored_count(page, "check-push-asked") == 1, "the click asked once")
    t.check(page.get_by_text("Notifications are on for this device.").is_visible(), "it says so")
    t.check(page.get_by_role("button", name="Send a test notification").is_visible(),
            "and offers a test notification")
    endpoint = _push.endpoint(page)
    t.check(endpoint and endpoint.startswith("https://fcm.googleapis.com/"),
            f"the browser holds a subscription: {endpoint}")
    t.check(_push.tenant_has(page, endpoint) is True, "the tenant has it for Anna")

    page.reload()
    t.check(_push.state(page) == "on", "a reload shows it on")
    t.check(switch.is_checked(), "checked")
    t.check(_push.stored_count(page, "check-push-asked") == 1, "the reload asked nothing")

    switch.click()
    _push.wait_for_state(page, "off")
    t.check(not switch.is_checked(), "off after another click")
    t.check(_push.status(page) == "Get notified here when something needs you.", "the description again")
    t.check(not page.get_by_role("button", name="Send a test notification").is_visible(),
            "no test notification while off")
    t.check(_push.endpoint(page) is None, "the browser is unsubscribed")
    t.check(_push.tenant_has(page, endpoint) is False, "the tenant has deleted it")
