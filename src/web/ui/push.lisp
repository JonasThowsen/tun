;;;; web/ui/push.lisp -- the switch that turns notifications on for this
;;;; device (spec/push.md 2), and the logout that turns them off.
;;;;
;;;; The markup is a switch and a line of status, hidden until the script
;;;; knows what the device can do: push cannot work without JavaScript.
;;;; The script asks Tun's paths under /push/ and the browser's push
;;;; manager; permission is asked only from the person's tap.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(define-component push-switch ((&key (label "Varsler på denne enheten")
                                     (description "Få varsel her når noe trenger deg.")
                                     id attributes))
  (:group "Skjema")
  (:doc "Slår varsler på eller av for enheten personen bruker nå, med en linje under som sier
hvordan det står til. Den vises først når skriptet vet hva enheten kan: på en iPhone i Safari
står det at appen må legges på Hjem-skjermen, der varsler er blokkert, står det hvor de slås på.
Spør om lov bare når personen slår bryteren på. Når varsler er på, kan personen sende et
prøvevarsel til seg selv. Krever at klienten kan installeres som app, (:web-app ...).")
  (:source "Basecoat switch (Vega); asking for permission only from a user's tap, as WebKit and
web.dev recommend for Web Push")
  (:css "
.tun-push-switch {
  display: grid;
  gap: calc(var(--spacing) * 2);
  max-width: 40rem;
  & .tun-push-switch-status {
    color: var(--muted-foreground);
    font-size: var(--text-sm);
    line-height: var(--text-sm--line-height);
    max-width: 65ch;
  }
  &[data-state='blocked'] .tun-push-switch-status,
  &[data-state='failed'] .tun-push-switch-status { color: var(--foreground); }
  & [data-tun-push-test] { justify-self: start; }
}")
  (:script "
// Notifications on this device (spec/push.md 2.1, 2.2).
const pushText = {
  on: 'Varsler er på for denne enheten.',
  unavailable: 'Varsler er ikke tilgjengelige her.',
  homeScreen: 'Varsler virker bare i appen. Legg den på Hjem-skjermen først: trykk Del, '
    + 'så «Legg til på Hjem-skjerm», og åpne den derfra.',
  oldIos: 'Denne enheten kan ikke vise varsler fra appen. Det krever iOS 16.4 eller nyere.',
  unsupported: 'Denne nettleseren kan ikke vise varsler.',
  blocked: 'Varsler er blokkert for denne appen. Slå dem på i innstillingene for nettleseren '
    + 'eller telefonen, og last inn siden på nytt.',
  failed: 'Kunne ikke slå på varsler. Prøv igjen.',
  sent: (count) => `Prøvevarselet er sendt til ${count} ${count === 1 ? 'enhet' : 'enheter'}.`,
  wait: 'Et prøvevarsel ble sendt for under ett minutt siden. Vent litt før du sender et nytt.',
  notSent: 'Kunne ikke sende prøvevarselet. Prøv igjen.',
};

// An iPhone or iPad: iPadOS presents itself as a Mac with a touch screen.
const pushAppleTouch = () => /iPhone|iPad|iPod/.test(navigator.userAgent)
  || (/Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints > 1);
const pushHomeScreenApp = () => window.matchMedia('(display-mode: standalone)').matches
  || navigator.standalone === true;
const pushAvailable = () => 'serviceWorker' in navigator && 'PushManager' in window
  && 'Notification' in window;

const pushKeyBytes = (text) => {
  const base64 = text.replace(/-/g, '+').replace(/_/g, '/');
  const binary = atob(base64 + '='.repeat((4 - (base64.length % 4)) % 4));
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
};

// Whether SUBSCRIPTION was made with KEY; a browser that does not say is trusted.
const pushSameKey = (subscription, key) => {
  const own = subscription.options && subscription.options.applicationServerKey;
  if (!own) return true;
  const bytes = new Uint8Array(own);
  return bytes.length === key.length && bytes.every((byte, i) => byte === key[i]);
};

const pushPost = async (path, fields) => {
  const answer = await fetch(path, {
    method: 'POST', credentials: 'same-origin',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams(fields || {}),
  });
  const json = await answer.json().catch(() => ({}));
  if (!answer.ok) throw Object.assign(new Error(`${path} answered ${answer.status}`),
                                      { status: answer.status });
  return json;
};

const setUpPushSwitch = async (root) => {
  const input = root.querySelector('.tun-switch-input');
  const status = root.querySelector('.tun-push-switch-status');
  const test = root.querySelector('[data-tun-push-test]');
  const show = (state, text) => {
    root.dataset.state = state;
    input.checked = state === 'on';
    input.disabled = !['on', 'off', 'failed'].includes(state);
    status.textContent = text || (state === 'on' ? pushText.on : root.dataset.tunPushDescription);
    test.hidden = state !== 'on';
    root.hidden = false;
  };
  // §2.2's order: no key, then no push, then blocked, then the switch.
  const answer = await fetch('/push/key', { credentials: 'same-origin' }).catch(() => null);
  if (!answer || !answer.ok) return show('unavailable', pushText.unavailable);
  const key = pushKeyBytes((await answer.json()).key);
  if (!pushAvailable()) {
    if (!pushAppleTouch()) return show('missing', pushText.unsupported);
    return show('missing', pushHomeScreenApp() ? pushText.oldIos : pushText.homeScreen);
  }
  if (Notification.permission === 'denied') return show('blocked', pushText.blocked);
  const registration = await navigator.serviceWorker.ready;
  const subscription = await registration.pushManager.getSubscription();
  const on = subscription && pushSameKey(subscription, key)
    && (await pushPost('/push/state', { endpoint: subscription.endpoint })).on;
  show(on ? 'on' : 'off');

  const turnOn = async (asked) => {
    input.disabled = true;
    try {
      const permission = await asked;
      if (permission === 'denied') return show('blocked', pushText.blocked);
      if (permission !== 'granted') return show('off');
      // One the tenant does not have, or made with an older key, is replaced.
      const old = await registration.pushManager.getSubscription();
      if (old) await old.unsubscribe();
      const made = (await registration.pushManager.subscribe({
        userVisibleOnly: true, applicationServerKey: key,
      })).toJSON();
      await pushPost('/push/subscription',
                     { endpoint: made.endpoint, p256dh: made.keys.p256dh, auth: made.keys.auth });
      show('on');
    } catch (error) {
      show('failed', pushText.failed);
    }
  };
  const turnOff = async () => {
    input.disabled = true;
    try {
      const current = await registration.pushManager.getSubscription();
      if (current) {
        await pushPost('/push/unsubscribe', { endpoint: current.endpoint }).catch(() => {});
        await current.unsubscribe();
      }
    } finally {
      show('off');
    }
  };
  input.addEventListener('change', () => {
    // Asked at once, inside the tap: Safari allows the question nowhere else.
    if (input.checked) turnOn(Notification.requestPermission());
    else turnOff();
  });
  test.addEventListener('click', async () => {
    try {
      status.textContent = pushText.sent((await pushPost('/push/test')).devices);
    } catch (error) {
      status.textContent = error.status === 409 ? pushText.wait : pushText.notSent;
    }
  });
};

tunOnContent((root) => {
  for (const element of root.querySelectorAll('[data-tun-push]:not([data-tun-push-ready])')) {
    element.dataset.tunPushReady = '';
    setUpPushSwitch(element).catch(() => {
      element.hidden = true;
    });
  }
});

// Logging out stops this device's notifications (spec/push.md 3): the
// browser's subscription is deleted on the server and at the push service
// before the logout goes on, within 2 seconds.  Caught before htmx sees
// the submit, then submitted again.
window.addEventListener('submit', (event) => {
  const form = event.target;
  if (!(form instanceof HTMLFormElement) || 'tunPushLeft' in form.dataset) return;
  if (new URL(form.action, window.location.href).pathname !== '/logout') return;
  if (!pushAvailable() || !document.querySelector('link[rel=manifest]')) return;
  event.preventDefault();
  event.stopImmediatePropagation();
  form.dataset.tunPushLeft = '';
  const leave = (async () => {
    const registration = await navigator.serviceWorker.getRegistration();
    const subscription = registration && await registration.pushManager.getSubscription();
    if (!subscription) return;
    await pushPost('/push/unsubscribe', { endpoint: subscription.endpoint }).catch(() => {});
    await subscription.unsubscribe();
  })();
  Promise.race([leave.catch(() => {}), new Promise((done) => setTimeout(done, 2000))])
    .then(() => form.requestSubmit());
}, true);")
  (:examples
   (("For denne enheten" :layout :stack)
    (push-switch ()))
   (("Med egen tekst" :layout :stack)
    (push-switch (:label "Varsle meg om nye saker"
                         :description "Du får varsel når en sak blir gitt til deg."))))
  (let* ((id (or id (element-id "tun-push")))
         (status-id (format nil "~a-status" id)))
    `(:div ,(attrs (list :class "tun-push-switch" :id id :hidden t :data-tun-push t
                         :data-tun-push-description description)
                   attributes)
           ,(switch (:label label :id (format nil "~a-input" id)
                            :disabled t
                            :attributes (list :aria-describedby status-id)))
           (:p (:@ :class "tun-push-switch-status" :id ,status-id :aria-live "polite")
               ,description)
           ,(button (:variant :outline :size :sm :icon :bell
                              :attributes (list :data-tun-push-test t :hidden t))
              "Send et prøvevarsel"))))
