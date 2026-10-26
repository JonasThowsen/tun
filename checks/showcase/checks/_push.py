"""What the push checks share (spec/push.md 10): a stand-in for the
browser's push service, so no push service is contacted, and questions to
ask the page and the tenant.

A file whose name starts with _ is not a check (spec/preview.md 4)."""

# RFC 8291's receiver key and secret: a real point on P-256, as Tun checks.
P256DH = "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
AUTH = "BTBZMqHH6r4Tts7J_aSIgg"

# PushManager's subscribe and getSubscription answered from localStorage, with
# an endpoint at Google's push service that is never posted to; and a count of
# the times the page asks for permission.
STAND_IN = """
(() => {
  try {
    const stored = 'check-push';
    const count = (name) => localStorage.setItem(name, String(Number(localStorage.getItem(name) || 0) + 1));
    const encode = (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes)))
      .replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
    const decode = (text) => {
      const base64 = text.replace(/-/g, '+').replace(/_/g, '/');
      return Uint8Array.from(atob(base64 + '='.repeat((4 - (base64.length % 4)) % 4)),
                             (c) => c.charCodeAt(0)).buffer;
    };
    const subscription = (data) => ({
      endpoint: data.endpoint,
      options: { userVisibleOnly: true, applicationServerKey: decode(data.key) },
      toJSON: () => ({ endpoint: data.endpoint, keys: { p256dh: '%P256DH%', auth: '%AUTH%' } }),
      unsubscribe: () => {
        localStorage.removeItem(stored);
        count('check-push-unsubscribed');
        return Promise.resolve(true);
      },
    });
    if (window.PushManager) {
      PushManager.prototype.subscribe = function (options) {
        const data = { endpoint: 'https://fcm.googleapis.com/fcm/send/check-'
                                 + Math.random().toString(36).slice(2),
                       key: encode(options.applicationServerKey) };
        localStorage.setItem(stored, JSON.stringify(data));
        return Promise.resolve(subscription(data));
      };
      PushManager.prototype.getSubscription = function () {
        const data = localStorage.getItem(stored);
        return Promise.resolve(data ? subscription(JSON.parse(data)) : null);
      };
    }
    if (window.Notification) {
      const ask = Notification.requestPermission.bind(Notification);
      Notification.requestPermission = (...args) => {
        count('check-push-asked');
        return ask(...args);
      };
    }
  } catch (error) {
    // about:blank has no localStorage; the checks' own pages do.
  }
})();
""".replace("%P256DH%", P256DH).replace("%AUTH%", AUTH)


def stand_in(page):
    """Answer the page's push manager with the stand-in, on every page of its browser."""
    page.context.add_init_script(STAND_IN)


def state(page):
    """The switch's state once its script has decided: on, off, missing, blocked..."""
    page.wait_for_function("document.querySelector('[data-tun-push]')?.dataset.state")
    return page.evaluate("document.querySelector('[data-tun-push]').dataset.state")


def wait_for_state(page, wanted):
    page.wait_for_function(
        "(wanted) => document.querySelector('[data-tun-push]')?.dataset.state === wanted", arg=wanted)


def status(page):
    return page.evaluate("document.querySelector('.tun-push-switch-status').textContent")


def stored_count(page, name):
    return page.evaluate("(name) => Number(localStorage.getItem(name) || 0)", name)


def endpoint(page):
    """The endpoint of the browser's subscription, or None."""
    return page.evaluate("JSON.parse(localStorage.getItem('check-push') || 'null')?.endpoint ?? null")


def tenant_has(page, endpoint):
    """Whether the tenant has ENDPOINT for the signed-in person (push_check)."""
    return page.evaluate("""(endpoint) => fetch('/push/state', {
        method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ endpoint }) }).then((r) => r.json()).then((j) => j.on)""",
                         endpoint)
