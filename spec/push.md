# Push notifications

Status: v1, built 2026-10-26, core 1.19.0. How a client
that is installed as an app (`ui.md` §4.2) notifies people on their
phones and computers: a person turns notifications on for a device, the
client's code sends a notification to a person, and the service worker
shows it and opens the page it is about. It is Web Push: the push
service of the person's browser (Apple's, Google's, Mozilla's) carries
the message, encrypted for the device (RFC 8291), from a server that
proves who it is with a key of its own (VAPID, RFC 8292).

## 1. What a client does

```lisp
(define-application tracker-application ()
  (:web-app :short-name "Saker" :icons "icons/"))

;; On a page the client chooses, such as the person's own settings:
(ui:push-switch ())

;; In an operation, a job or a workflow: a write.
(notify-push "kari" :title "Ny sak til deg"
                    :body "Eksporten feiler for Fjord AS"
                    :url "/saker/itm_12"
                    :tag "sak:itm_12")
```

Nothing else: no key to make, no setting to fill in, no provider to
name. Push is part of `(:web-app ...)`: without it the switch says
notifications are not available (§2.2), `push_subscribe` refuses with
`invalid_input`, and `notify-push` returns 0 and sends nothing, since the
worker such a client serves removes itself and shows no notification.
A subscription stored while the client had `(:web-app ...)` is kept, and
used again if the option comes back.

## 2. Turning notifications on

### 2.1 The switch

`(ui:push-switch (&key label description id))`, in `TUN.UI`, is a
`switch` (`ui.md` §6) for this device, with a line of status under it.

- LABEL defaults to «Varsler på denne enheten», DESCRIPTION to «Få
  varsel her når noe trenger deg.»
- It is hidden until the components' script has found out what this
  device can do, so a browser without JavaScript shows nothing.
- **On** asks the browser for permission, from the person's own tap or
  click, and only then: never when the page loads. Granted, it
  subscribes the browser to its push service with Tun's public key
  (`userVisibleOnly: true`) and stores the subscription (§3). It then
  shows «Varsler er på for denne enheten.» and a button «Send et
  prøvevarsel» (`push_test`, §8).
- **Off** deletes the subscription from the tenant and unsubscribes the
  browser. It then shows the description again.
- A page loaded later shows the switch on exactly when the browser has a
  subscription made with the current key and the tenant has it for the
  signed-in person (`push_check`, §8). Asking also ties the subscription
  to the session the person is in now (§3), so logging out of that
  session turns it off.
- A subscription the browser holds but the tenant does not (after
  logging out, §3, or after the key changed, §6.3) is replaced by a new
  one when the person turns the switch on.
- A failure to subscribe or store says «Kunne ikke slå på varsler. Prøv
  igjen.» and leaves the switch off.

### 2.2 What each device shows

The switch shows the first of these that applies, in this order:

1. `/push/key` answers 404, as it does without `(:web-app ...)`:
   «Varsler er ikke tilgjengelige her.»
2. Push is missing: the browser lacks a service worker, `PushManager`
   or `Notification`. Push is detected, never assumed from the user
   agent. What the person is told depends on the device:
   - an iPhone or iPad in a tab (Safari's, or another browser's on it):
     «Varsler virker bare i appen. Legg den på Hjem-skjermen først:
     trykk Del, så «Legg til på Hjem-skjerm», og åpne den derfra.»
   - an iPhone or iPad in the Home Screen app, which has no push before
     iOS 16.4: «Denne enheten kan ikke vise varsler fra appen. Det
     krever iOS 16.4 eller nyere.»
   - any other: «Denne nettleseren kan ikke vise varsler.»
3. The person blocked notifications for the app
   (`Notification.permission` is `denied`): «Varsler er blokkert for
   denne appen. Slå dem på i innstillingene for nettleseren eller
   telefonen, og last inn siden på nytt.» The switch is off and cannot
   be turned on.
4. Otherwise, the switch (§2.1).

An iPhone or iPad is told apart by its user agent, or by a Mac's user
agent with a touch screen (`maxTouchPoints` above 1), which is how
iPadOS presents itself. The Home Screen app is told from a tab by
`display-mode: standalone`, or `navigator.standalone` on iOS.

So the devices the request names see:

| Device | What the person sees |
|---|---|
| iPhone or iPad, iOS 16.4 or newer, the app opened from the Home Screen | the switch; on asks iOS for permission |
| iPhone or iPad in a tab | step 2's «Varsler virker bare i appen …» |
| iPhone or iPad, the Home Screen app before iOS 16.4 | step 2's «… Det krever iOS 16.4 eller nyere.» |
| Android, Chrome, in a tab or installed | the switch |
| A computer: Chrome, Edge, Firefox, or Safari 16.1 or newer on macOS 13 or newer | the switch |

### 2.3 Tun's paths

All under `/push/`, which a client's page cannot take (`ui.md` §4.2, as
`/login`). A POST from another origin is refused as every POST is
(`auth.md` §3.3). Each answers JSON.

| Path | Login | Does |
|---|---|---|
| `GET /push/key` | no | `{"key": KEY}`, the public key in base64url (§6.2), with `Cache-Control: no-cache`; 404 without `(:web-app ...)`. |
| `POST /push/subscription` | yes | `push_subscribe` with the form's `endpoint`, `p256dh` and `auth`, and the device's name made from the user agent: `{"on": true}`. |
| `POST /push/unsubscribe` | yes | `push_unsubscribe` with the form's `endpoint`: `{"on": false}`. |
| `POST /push/state` | yes | `push_check` with the form's `endpoint`: `{"on": BOOL}`. |
| `POST /push/test` | yes | `push_test`: `{"devices": N}`. |

Without a signed-in person a POST answers 401 with the error document
(`api.md` §3). A refusal of the tool answers its error document with the
status its code has on `/api`.

## 3. Subscriptions

A subscription is a record of the internal entity `push_subscription`
(id prefix `psh`), one per device and account:

| Field | Meaning |
|---|---|
| `account` | The account's name, the actor's name of the person who turned it on. |
| `endpoint` | The push service's URL for this browser: `https`, at most 1000 characters. Unique. |
| `p256dh` | The browser's P-256 public key, uncompressed (65 octets), in base64url. |
| `auth` | The browser's 16-octet authentication secret, in base64url. A secret field (`auth.md` §7). |
| `server_key` | Tun's public key (§6.2) when it was made. |
| `session` | The session it was made or last checked in (`ses_…`), or null when it came another way. |
| `device` | A name for the device, such as «iPhone» or «Chrome på Mac», at most 80 characters. |
| `created_at` | When it was stored. |
| `tested_at` | When `push_test` last sent to the account's devices, or null. |

- `push_subscribe` with an endpoint already stored replaces that record:
  the same browser after another person signed in on it belongs to that
  person now.
- **Push services only.** An endpoint must be an `https` URL on the
  default port at a host of a known push service: `fcm.googleapis.com`
  (Chrome, Edge on Android, Samsung Internet, Opera), a host ending in
  `.push.apple.com` (Safari, every browser on iOS),
  `updates.push.services.mozilla.com` or a host ending in
  `.push.services.mozilla.com` (Firefox), or a host ending in
  `.notify.windows.com` (Edge on Windows). Any other endpoint, an IP
  address, `localhost`, a user or password in the URL included, is
  `invalid_input`, so Tun never posts to a host a person chose. The
  endpoint is parsed once, when it is subscribed, into its host and
  path; what is stored, and later posted to, is the URL rebuilt from
  them, so the host that was checked is the host connected to. A stored
  endpoint is checked again at delivery (§5).
- A `p256dh` that is not a point on P-256, or an `auth` that is not 16
  octets, is `invalid_input`.
- An account keeps at most 10. Storing an 11th deletes the one stored
  longest ago: `push_subscribe` sets `created_at` anew, also for an
  endpoint that moves from another account, so the device just turned on
  is never the one deleted.
- **Logging out** stops notifications on the device, in two ways:
  - On the server, `POST /logout` deletes the subscriptions made or last
    checked in that session. A subscription made in a session that has
    since expired is tied to the new one as soon as a page with the
    switch is opened in it (§2.1, `push_check`).
  - In the browser, the components' script catches the submit of a
    form to `/logout` on a page that links a manifest. When the
    browser holds a push subscription, it first posts its endpoint to
    `/push/unsubscribe`, then unsubscribes it from the push service,
    then lets the logout go on. It waits at most 2 seconds for both, so
    logging out never hangs. This covers a subscription tied to a
    session that has expired, whose record the logout would not find.
    Without JavaScript only the first way applies.
- **Disabling an account** (`accounts_update`) deletes its
  subscriptions, so its devices do not get notifications again if it is
  enabled later.
- The push service's 404 or 410 deletes the subscription (§5).

## 4. Sending

`(notify-push NAME &key title body url tag)`, in the TUN package, is
called inside a write, as `send-mail` is (`mail.md` §2).

- NAME is an account's name, as for `account-address` (`auth.md` §2).
- TITLE, 1 to 120 characters, is required. BODY is at most 1000
  characters. TAG, at most 64 characters, makes a later notification
  with the same tag replace this one on the device instead of adding
  another.
- URL is the page the notification opens: a path on this server, at
  most 1000 characters, `/` when absent. It starts with `/`, and its
  second character is neither `/` nor `\`, which a browser would read
  as another host (`//example.com/x`).
- The notification as JSON, `{"title", "body", "url", "tag"}` with the
  absent ones left out, is at most 3993 octets in UTF-8. A push service
  must take a body of 4096 octets (RFC 8291 §4), and the body is the
  86-octet header, then the JSON, the delimiter (1 octet) and the
  record's tag (16 octets) (§6.1).
- A bad argument, a notification too long among them, signals an error,
  so the operation fails `invalid_input` and nothing is written.
- It enqueues one `send_push` job (§5) for each of NAME's subscriptions
  made with the current key, and returns how many. The jobs are part of
  the caller's transaction: when it rolls back, nothing is sent.
- It returns 0 and enqueues nothing when NAME has no subscriptions, as
  a disabled account has none (§3). A name with no account, such as a
  claimed actor in a preview, is sent to as any other.
- A subscription of NAME made with an older key is deleted then: no push
  service would take a message for it (§6.3).

## 5. Delivery

Each notification to a device is delivered by a job, `send_push`, in the
`:push` queue, outside any transaction (`jobs.md` §4.2). The queue runs
two jobs at once unless the application says otherwise (`(:queues (:push
N))`), and every attempt is cut off after 10 seconds, so a push service
that is slow holds up the others for at most that long. Two leave room
for mail and other calls within the tenant's four at once
(`outbound.md` §1). Its
arguments are the subscription's id and the notification's fields.

- An attempt reads the subscription, encrypts the notification for it
  with a new key and salt (§6.1), signs a new VAPID token (§6.2), and
  posts it to the endpoint through the application's push service (the
  port below), within 10 seconds.

| The push service answers | The subscription | The job |
|---|---|---|
| 200 to 299 | kept | `succeeded` |
| 404 or 410 | deleted | `cancelled`, «Enheten tar ikke lenger imot varsler» |
| 429, 500 to 599, nothing within 10 seconds, no connection | kept | retried after 30 s, 2, 10 and 30 minutes, 1 hour, then 3 hours; `failed` after the seventh attempt |
| anything else, such as 400, 401, 403 or 413 | kept | `failed` at once, with the status and the answer's first 200 characters |

- A subscription that no longer exists when its job runs cancels the
  job. One whose endpoint is no longer on a push service's host (§3) is
  deleted and cancels it.
- Each delay gets up to a tenth more at random; in test mode it is exact
  (`jobs.md` §2). The job keeps every attempt's error (`jobs_get`).
- The message asks the push service to keep it for a day (`TTL: 86400`)
  while the device is offline.
- A job that runs again after a crash (`jobs.md` §7) may show the
  notification twice; its tag, when it has one, makes the second replace
  the first.

**The port.** A push service is an adapter with one generic function,
`(deliver-push SERVICE ENDPOINT HEADERS BODY)`, that answers the status
and the answer's text, or NIL for no answer.

- `web-push-service`, the adapter a server uses, posts over HTTPS with
  the certificate verified, through the machinery of
  `http-json-post` (`outbound.md`): the same four calls at once, shared
  with mail and every other call, the operation's deadline, and an
  `external` step in the trace. The step names only the endpoint's
  scheme and host, as `POST https://web.push.apple.com/…`: the rest of
  an endpoint is the device's address.
- An application opened with the test clock, as a test opens one, gets
  `log-push-service`, which sends nothing and answers 201, unless it is
  given another. Tests give a fake that records what it is sent and
  answers what the test chooses.

## 6. The message

### 6.1 Encryption (RFC 8291, RFC 8188)

The body is the notification's JSON in one `aes128gcm` record, encrypted
for the subscription's `p256dh` and `auth`:

- a new P-256 key pair (the sender's) and a 16-octet random salt for each
  attempt;
- `ecdh_secret`, the x coordinate of ECDH between the sender's private
  key and `p256dh`;
- `IKM = HKDF(salt=auth, ikm=ecdh_secret, info="WebPush: info" 0x00
  p256dh sender_public, L=32)`;
- `CEK = HKDF(salt, IKM, "Content-Encoding: aes128gcm" 0x00, 16)` and
  `NONCE = HKDF(salt, IKM, "Content-Encoding: nonce" 0x00, 12)`, HKDF
  with SHA-256 (RFC 5869);
- the record is the JSON, then the delimiter 0x02, without padding,
  encrypted with AES-128-GCM under CEK and NONCE, its 16-octet tag
  after it;
- the body is the header, salt (16), record size 4096 (4 octets, big
  endian), 65 (1 octet) and the sender's public key (65 octets), 86
  octets in all, then the record.

The request's headers are `Content-Encoding: aes128gcm`,
`Content-Type: application/octet-stream`, `TTL: 86400` and
`Authorization` (§6.2).

### 6.2 VAPID (RFC 8292)

- `Authorization: vapid t=TOKEN, k=KEY`. KEY is Tun's public key,
  uncompressed (65 octets), in base64url: the `applicationServerKey` the
  browser subscribed with.
- TOKEN is a JWT signed with ES256 (ECDSA on P-256 with SHA-256, the
  signature R and S, 32 octets each): header `{"typ":"JWT","alg":"ES256"}`;
  claims `aud`, the endpoint's scheme, host and port, as
  `https://fcm.googleapis.com`; `exp`, 12 hours from now; and `sub`, the
  server's public URL (`deploy.md` §1) when it is an `https` URL, and no
  `sub` otherwise. Apple's push service refuses a token without `sub`,
  so a deployed tenant has an `https` `PUBLIC_URL`.

### 6.3 The key

- Tun's key pair is derived from the secret setting `push.hemmelighet`,
  which, like every secret setting Tun declares, gets a random value
  when a tenant first starts (`core.md` §5.3) and is kept in the
  tenant's store, masked in every listing. Nobody makes or copies a key.
- The private key is `1 + (HMAC-SHA-256(key=SECRET, "tun web push vapid")
  mod (n − 1))`: the HMAC's key is the secret's UTF-8 octets, its
  message those of the ASCII text, its result read as a big-endian
  integer, and n is the order of P-256. The public key is that times
  the curve's generator. The same secret always gives the
  same key, so every process of a tenant signs with the same one.
- An administrator who changes the setting (`settings_set`) changes the
  key. Every device then has to turn notifications on again: the switch
  shows off on each (§2.1), and `notify-push` deletes the old
  subscriptions it finds (§4).

## 7. The service worker

With `(:web-app ...)`, `/sw.js` (`ui.md` §4.2) also:

- **shows a notification for every push**, as iOS requires: the title,
  body and tag of the message's JSON, the app's 192-pixel icon, and its
  URL kept with it. A push without data, or with data that is not such
  JSON, shows the application's title with «Du har et nytt varsel», for
  `/`. A notification with a tag replaces the device's earlier one with
  that tag and alerts again.
- **opens the page on a click**: it closes the notification, then
  brings forward a window of the app that shows the URL, else one of the
  app's windows, which it sends to the URL, else opens a new window at
  the URL. It resolves the URL against its own origin, and takes `/`
  when the result is on another origin, as `https://example.com/` and
  `//example.com/` are, or when the URL is not a string.

The worker without `(:web-app ...)` (`ui.md` §4.2) has neither.

## 8. Tools

They are ordinary operations, for any signed-in account (viewer and
up): policy, validation, idempotency and audit apply. Each acts on the
caller's own subscriptions only.

| Tool | Does |
|---|---|
| `push_subscribe` | Stores a subscription for the caller (§3): `endpoint`, `p256dh`, `auth`, optional `device`. `auth` is secret: a request's record shows `"***"` (`core.md` §8.2). Refused without `(:web-app ...)`. |
| `push_unsubscribe` | Deletes the caller's subscription with `endpoint`; one that is not the caller's is `not_found`. |
| `push_check` | Whether `endpoint` is the caller's and made with the current key: `{"on": BOOL}`. When it is, and the call comes in a session, the subscription is tied to that session (§3). |
| `push_devices` | The caller's subscriptions: id, device and `created_at`, never the endpoint or keys. |
| `push_test` | Sends «Varsler er på» to each of the caller's devices, opening `/`: how many. At most once a minute per account; sooner is `conflict`. |

## 9. Not yet

- `pushsubscriptionchange`: a browser that renews its subscription on
  its own (Firefox may) is subscribed again only when the person turns
  the switch on.
- `Topic` and `Urgency`, so a push service replaces an undelivered
  message or holds back a less urgent one.
- Actions on a notification, images, and a badge count on the icon.
- A page where a person sees and turns off their other devices, and an
  administrator's view of everyone's.

## 10. Evidence

- `tests/push-tests.lisp`:
  - the encryption of RFC 8291 §5 with its keys and salt: the
    intermediate values of its Appendix A and the exact body, and that
    the receiver's key decrypts what Tun sends;
  - VAPID: the token's header and claims, its signature verified with
    the public key in `k`, and ironclad's ES256 against RFC 7515 A.3;
    the key from the setting, the same each time and another after
    `settings_set`;
  - without `(:web-app ...)`, no subscription and nothing sent;
  - `auth` masked in `introspect_request`;
  - a client's page cannot take `/push`;
  - the tools: subscribing, moving an endpoint to another account,
    refusals (hosts that are not push services among them), the limit of
    10, unsubscribing, `push_check` and the session it ties, logging
    out, disabling an account, `push_test`'s limit;
  - the limit of 10 by when each was stored, a moved endpoint kept;
  - `notify-push`: one job per device in the caller's write and none
    after a rollback, the count, a disabled account, older keys, bad
    arguments and the size limit;
  - delivery through a fake push service: each row of §5's table, the
    headers, and a body the device's key decrypts to the notification;
    the `:push` queue's two at once, and the application's own number
    over it;
  - `web-push-service` over real HTTP against a fake push service in the
    test process, and the trace step without the endpoint's path;
  - the paths of §2.3, their logins, and 404 without `(:web-app ...)`.
- Browser checks in `checks/showcase/checks/`, on the showcase's
  «Varsler» page, in Chromium with notifications allowed and the
  browser's push service stood in by the check:
  - `push-switch-on-and-off`: on stores the subscription and shows
    «Send et prøvevarsel», a reload shows it on, off deletes it, and
    loading the page never asks for permission;
  - `push-logout-turns-it-off`: logging out of the shell deletes the
    subscription and unsubscribes the browser;
  - `push-switch-where-push-is-missing`: §2.2's order and texts: a
    404 key, a browser without push, an iPhone in a tab, an iPad
    presenting as a Mac in a tab, an iPhone's Home Screen app without
    push, a blocked permission, and an iPhone's Home Screen app with
    push, which shows the switch;
  - `push-notification-opens-its-page`: a push to the worker shows the
    notification with its title, body and tag, one without data or with
    data that is not JSON shows «Du har et nytt varsel», a click brings
    the app's window to the URL, and a URL on another origin opens `/`.
