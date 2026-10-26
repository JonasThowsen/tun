"""Where push cannot work, the switch says why, in spec/push.md 2.2's
order: no key, then no push (an iPhone or iPad in a tab, a Home Screen app
before iOS 16.4, any other browser), then a blocked permission; an iPhone's
Home Screen app with push shows the switch."""

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _push  # noqa: E402

IPHONE = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 "
          "(KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1")
IPAD_AS_MAC = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
               "(KHTML, like Gecko) Version/17.4 Safari/605.1.15")

NO_PUSH = "delete window.PushManager;"
HOME_SCREEN = "Object.defineProperty(Navigator.prototype, 'standalone', { get: () => true });"
TOUCH = "Object.defineProperty(Navigator.prototype, 'maxTouchPoints', { get: () => 5 });"
BLOCKED = "Object.defineProperty(Notification, 'permission', { get: () => 'denied' });"

TEXTS = {
    "unavailable": "Varsler er ikke tilgjengelige her.",
    "home screen": "Varsler virker bare i appen. Legg den på Hjem-skjermen først",
    "old ios": "Denne enheten kan ikke vise varsler fra appen. Det krever iOS 16.4 eller nyere.",
    "unsupported": "Denne nettleseren kan ikke vise varsler.",
    "blocked": "Varsler er blokkert for denne appen.",
}


def open_switch(t, *scripts, phone=False, user_agent=None, no_key=False):
    """The «Varsler» page in a browser changed by SCRIPTS, run before the page's own."""
    page = (t.phone if phone else t.desktop)(user_agent=user_agent)
    _push.stand_in(page)
    for script in scripts:
        page.context.add_init_script(script)
    if no_key:
        page.route("**/push/key", lambda route: route.fulfill(status=404, body="{}"))
    page.sign_in("employee:anna")
    page.goto("/varsler")
    _push.state(page)
    return page


def says(t, page, text, what):
    status = _push.status(page)
    t.check(status.startswith(TEXTS[text]), f"{what}: «{status}»")
    switch = page.get_by_role("switch", name="Varsler på denne enheten")
    t.check(not switch.is_checked() and not switch.is_enabled(), f"{what}: the switch is off and disabled")


def run(t):
    says(t, open_switch(t, no_key=True), "unavailable", "without a key, as without (:web-app ...)")
    says(t, open_switch(t, NO_PUSH), "unsupported", "a browser without PushManager")
    says(t, open_switch(t, NO_PUSH, phone=True, user_agent=IPHONE), "home screen",
         "an iPhone in a Safari tab")
    says(t, open_switch(t, NO_PUSH, TOUCH, phone=True, user_agent=IPAD_AS_MAC), "home screen",
         "an iPad presenting as a Mac, in a tab")
    says(t, open_switch(t, NO_PUSH, HOME_SCREEN, phone=True, user_agent=IPHONE), "old ios",
         "an iPhone's Home Screen app before iOS 16.4")
    says(t, open_switch(t, BLOCKED), "blocked", "a blocked permission")

    says(t, open_switch(t, NO_PUSH, no_key=True), "unavailable", "no key goes before no push")
    says(t, open_switch(t, NO_PUSH, BLOCKED), "unsupported", "no push goes before blocked")

    page = open_switch(t, HOME_SCREEN, phone=True, user_agent=IPHONE)
    switch = page.get_by_role("switch", name="Varsler på denne enheten")
    t.check(_push.state(page) == "off", "an iPhone's Home Screen app with push shows the switch")
    t.check(not switch.is_checked() and switch.is_enabled(), "off, and it can be turned on")
