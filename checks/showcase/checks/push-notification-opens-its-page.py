"""The service worker shows every push as a notification, and a click on
one brings the app's window to its page on this server (spec/push.md 7)."""

import pathlib
import re
import sys
from urllib.parse import urlparse

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import _push  # noqa: E402

PUSH = """(data) => new Promise((done) => {
  self.dispatchEvent(new PushEvent('push', data === null ? {} : { data }));
  setTimeout(done, 300);
})"""

NOTIFICATIONS = """async () => (await self.registration.getNotifications())
  .map((n) => ({ title: n.title, body: n.body, tag: n.tag, url: n.data && n.data.url }))"""

CLOSE_ALL = """async () => {
  for (const n of await self.registration.getNotifications()) n.close();
}"""

CLICK = """async () => {
  const [n] = await self.registration.getNotifications();
  self.dispatchEvent(new NotificationEvent('notificationclick', { notification: n }));
}"""


def push(worker, data):
    """Show what a push with DATA (a text, or None for none) shows; the notifications after."""
    worker.evaluate(CLOSE_ALL)
    worker.evaluate(PUSH, data)
    return worker.evaluate(NOTIFICATIONS)


def run(t):
    page = t.desktop(permissions=["notifications"])
    _push.stand_in(page)
    page.sign_in("employee:anna")
    page.goto("/notifications")
    page.wait_for_function("navigator.serviceWorker.controller !== null")
    worker = next(w for w in page.context.service_workers if w.url.endswith("/sw.js"))

    shown = push(worker, '{"title":"A new item for you","body":"The export fails",'
                         '"url":"/items?from=notification","tag":"item:1"}')
    t.check(len(shown) == 1, f"one notification: {shown}")
    t.check(shown and shown[0]["title"] == "A new item for you", "with the message's title")
    t.check(shown and shown[0]["body"] == "The export fails", "its body")
    t.check(shown and shown[0]["tag"] == "item:1", "and its tag")

    with page.expect_navigation(url=re.compile(r"/items\?from=notification$")):
        worker.evaluate(CLICK)
    t.check(urlparse(page.url).path == "/items", f"a click brings the window to the page: {page.url}")

    for data, what in ((None, "without data"), ("not json {", "with data that is not JSON")):
        shown = push(worker, data)
        t.check(len(shown) == 1 and shown[0]["title"] == "showcase"
                and shown[0]["body"] == "You have a new notification",
                f"a push {what} shows the app's name with «You have a new notification»: {shown}")

    for url in ("https://other.example/", "//other.example/"):
        page.goto("/notifications")
        push(worker, '{"title":"A link out","url":"%s"}' % url)
        with page.expect_request(lambda r: r.is_navigation_request()
                                 and urlparse(r.url).path == "/"
                                 and urlparse(r.url).netloc == urlparse(t.url).netloc):
            worker.evaluate(CLICK)
        t.check("other.example" not in page.url, f"{url} opens / on this server: {page.url}")
