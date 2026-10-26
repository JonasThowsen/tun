# Varsler på telefonen fra en installert app

- loop: web-push
- mode: autonomous
- stage: ship
- base: b7a392cdc7c9a04b02339d58cca4ac2b06a4b308
- verified: 9c5ad6bba4dc600e386cca43e92770675fca013c
- shown: 9c5ad6bba4dc600e386cca43e92770675fca013c

## Brief

Requested by Jonas on 2026-10-26, through an agent working on a client
(core):

> Web Push notifications for an installed app (core). Tun clients are already PWAs.
> - A person turns on notifications per device from a user gesture. A ui component for it is fine, e.g. in the account menu or on a page the client chooses. That stores a push subscription per account and device. They can turn it off. A 404 or 410 from the push service deletes the subscription.
> - A client API such as `(notify-push ACCOUNT :title … :body … :url … :tag …)` sends to all of that account's devices. Run it as an outbound job with retries, like mail.
> - The service worker shows the notification and opens or focuses `url` on click.
> - VAPID keys: ideally Tun generates the keypair itself on first need and keeps it in the tenant's store as a secret setting, so no one handles a credential by hand. Your call.
> - Payload: either RFC 8291 aes128gcm encryption (test against the RFC's vectors), or a contentless push where the service worker fetches what to show. Your call.
> - It has to work on iOS home-screen apps (16.4+), Android Chrome and desktop.

Jonas's condition: the parts in Tun know nothing of the client that asked.

## Criteria

The contract is `spec/push.md`; each criterion names the section.

1. Encryption (§6.1): encrypting RFC 8291 §5's plaintext with its keys
   and salt gives Appendix A's intermediate values (ecdh_secret, PRK_key,
   IKM, PRK, CEK, NONCE) and exactly §5's body; the receiver's private key
   decrypts a body Tun makes with a fresh key and salt back to the
   notification. (`tests/push-tests.lisp`)
2. VAPID (§6.2, §6.3): the token's header is `{"typ":"JWT","alg":"ES256"}`
   and its claims `aud` (the endpoint's origin), `exp` (now + 12 h) and
   `sub` (the public URL when it is `https`, absent otherwise); its
   signature verifies with the key in `k`; ironclad verifies RFC 7515
   A.3's ES256 signature; the key comes from `push.hemmelighet`, is the
   same for the same secret and another after `settings_set`, and the
   setting reads `"***"` in `settings_list`. (`tests/push-tests.lisp`)
3. Subscriptions (§3, §8): `push_subscribe` stores endpoint, p256dh,
   auth, device, session and the current key for the caller; the same
   endpoint from another account moves to it; `invalid_input` for an
   endpoint that is `http`, on another port, with a user and password,
   at an IP address (`https://10.0.0.1/x`, `https://[::1]/x`), at
   `localhost`, at a tailnet host (`https://box.tail1234.ts.net/x`), at
   a host that only looks like a push service
   (`https://fcm.googleapis.com.evil.example/x`), and for a p256dh that
   is not a P-256 point and an auth that is not 16 octets; endpoints at
   `fcm.googleapis.com`, `web.push.apple.com`,
   `updates.push.services.mozilla.com` and `wns2-par02p.notify.windows.com`
   are taken; an 11th subscription deletes the one stored longest ago,
   and an endpoint moved from another account counts as stored now, so
   it stays; without `(:web-app ...)` `push_subscribe` is
   `invalid_input`; `auth` reads `"***"` in `introspect_request`;
   `push_unsubscribe` deletes the caller's and answers `not_found` for
   another's; `push_check` answers `on` only for the caller's endpoint
   made with the current key; `push_devices` lists the caller's without
   endpoint or keys; `auth` reads `"***"`; `POST /logout` deletes the
   subscriptions made or last checked in that session and no others;
   a subscription made in session S1, which then expires, is checked
   with `POST /push/state` in a new session S2, and logging out of S2
   deletes it; disabling the account deletes its subscriptions;
   `push_test` sends to the caller's devices and a second call within a
   minute is `conflict`. (`tests/push-tests.lisp`)
4. Sending (§4): `notify-push` in a write enqueues one `send_push` job
   per subscription of NAME made with the current key and returns the
   count; after a rollback there is none; a disabled account gets 0;
   without `(:web-app ...)` it returns 0 and queues nothing; a
   subscription made with an older key is deleted; a missing title, a
   URL not starting with `/`, the URLs `//example.com/x` and
   `/\example.com/x`, an over-long field and a notification over 3993
   octets are `invalid_input`. (`tests/push-tests.lisp`)
5. Delivery (§5): through a fake push service, a 201 succeeds with
   `TTL: 86400`, `Content-Encoding: aes128gcm`,
   `Content-Type: application/octet-stream` and `Authorization: vapid
   t=…, k=…`, and a body the device's key decrypts to the notification's
   JSON; 404 and 410 delete the subscription and cancel the job; 429, 500
   and no answer retry after 30 s, 2, 10, 30 min, 1 h, 3 h and fail after
   the seventh attempt; 400, 403 and 413 fail at once; a deleted
   subscription cancels the job, and so does one whose stored endpoint
   is not at a push service's host, which is deleted; the `:push` queue
   runs two at once by default. (`tests/push-tests.lisp`)
6. The real adapter (§5): `web-push-service` posts the body and headers
   over real HTTP to a fake push service in the test process and answers
   its status; the trace step is `external`, named with the endpoint's
   scheme and host only. (`tests/push-tests.lisp`)
7. Paths (§2.3): `GET /push/key` answers the key without a login and 404
   without `(:web-app ...)`; the POSTs answer 401 without a login and 403
   from another origin; a client's page cannot take `push` or
   `push/x`.
   (`tests/push-tests.lisp`)
8. The worker (§7), in Chromium on the showcase: a push with a payload
   shows a notification with its title, body and tag; a push without data
   and one whose data is not JSON each show the application's title with
   «Du har et nytt varsel»; a click on the notification brings the open
   window to its URL; a click on one whose URL is
   `https://other.example/` or `//other.example/` brings it to `/`.
   (`checks/showcase/checks/push-notification-opens-its-page.py`)
9. The switch (§2.1), in Chromium on the showcase's «Varsler» page, with
   notifications allowed and the browser's push service stood in by the
   check: on stores the subscription (`push_check` on the server
   answers `on` for the browser's endpoint) and shows «Varsler er på for
   denne enheten.» and «Send et prøvevarsel»; a reload shows it on; off
   deletes it and shows the description; loading the page never calls
   `Notification.requestPermission`.
   (`checks/showcase/checks/push-switch-on-and-off.py`)
10. Where push is missing (§2.2), in Chromium: a blocked permission shows
    «Varsler er blokkert …» with the switch off and disabled; a browser
    without `PushManager` shows «Denne nettleseren kan ikke vise
    varsler.»; an iPhone's user agent in a tab without `PushManager`
    shows «Varsler virker bare i appen. Legg den på Hjem-skjermen først …»;
    the same user agent in standalone display without `PushManager` (a
    Home Screen app before iOS 16.4) shows «Denne enheten kan ikke vise
    varsler fra appen. Det krever iOS 16.4 eller nyere.»; when
    `/push/key` answers 404, as without `(:web-app ...)`, it shows
    «Varsler er ikke tilgjengelige her.»; an iPad presenting as a Mac
    (a Mac's user agent with touch) in a tab without `PushManager`
    shows «Varsler virker bare i appen …»; an iPhone's user agent in
    standalone display with `PushManager` and `Notification` (iOS 16.4
    or newer) shows the switch, off and enabled; and where several
    apply, §2.2's order decides: a 404 key over missing push, missing
    push over a blocked permission.
    (`checks/showcase/checks/push-switch-where-push-is-missing.py`)
11. Logging out (§3), in Chromium on the showcase: with the switch on,
    «Logg ut» in the shell posts the browser's endpoint to
    `/push/unsubscribe` and unsubscribes the browser before the logout
    goes on, so after signing in again `push_check` answers `on: false`.
    The preview's sign-in is claimed, so that subscription is tied to no
    session: the case of one tied to an expired session, which the
    server's deletion alone would miss.
    (`checks/showcase/checks/push-logout-turns-it-off.py`)
12. The `:push` queue runs two at once without `(:queues ...)`, and the
    application's `(:queues (:push 1))` overrides it (`jobs.md` §6).
    (`tests/push-tests.lisp`)
13. The showcase is an installable app with a «Varsler» page holding the
    switch, shown by `tun loop show` at phone and desktop widths.

## Decisions

- **RFC 8291 encryption, not a contentless push.** A contentless push
  makes the worker fetch what to show, which needs a signed-in fetch
  from the worker; on iOS a push that does not end in a notification
  quickly costs the app its permission. Encrypting is a few dozen lines
  on ironclad (ECDH, AES-GCM, HMAC) with HKDF written out, and is tested
  against the RFC's own vectors.
- **The VAPID key is derived from a secret setting, `push.hemmelighet`,**
  rather than a stored key pair. Every secret setting Tun declares
  already gets a random value at a tenant's first start and is masked
  everywhere, so nothing new is needed in settings; the same secret gives
  the same key in every process; an admin who changes it rotates the key.
  Each subscription keeps the key it was made with, so a rotation shows
  the switch off and old subscriptions are dropped rather than failing
  at the push service.
- **A component, not a change to the app shell.** `ui:push-switch` goes
  on whatever page a client chooses; the account area of every staff
  page is left as it is. It is hidden until the script knows what the
  device can do, since push cannot work without JavaScript.
- **Permission only from the person's tap,** `requestPermission` called
  first in the click handler (Safari requires it inside the gesture),
  with the key fetched beforehand so nothing is awaited before it.
- **The device decides what it can do, by feature detection;** the user
  agent is read only to tell an iPhone in a Safari tab what to do, since
  there push is missing until the app is on the Home Screen.
- **Subscriptions are keyed by the account's name** (the actor's name),
  as `account-address` is, so a claimed actor in a preview can try it on
  a phone.
- **Disabling an account deletes its subscriptions** (the reviewer's
  optional point, taken): a disabled person's devices do not come back
  to life when the account is enabled. `accounts_update` calls a
  generic function of `tun.auth` with a method from the push code, so
  auth does not depend on push.
- **Logging out deletes the subscriptions made or last checked in that
  session,** so a shared or handed-on device stops showing the person's
  notifications. The components' script also catches a logout on a page
  of an installable client: it posts the browser's endpoint to
  `/push/unsubscribe` and unsubscribes the browser, at most 2 s, then
  logs out. Of the two fixes the reviewer offered this one is chosen
  because it closes the gap on the device that logs out, whatever
  session the subscription was tied to, and needs no request on every
  page; the server-side deletion still covers a browser without
  JavaScript. An expired session keeps them: the person did not leave
  the device. So that a later logout still finds them, `push_check`
  (`POST /push/state`, asked whenever a page with the switch loads) ties
  the subscription to the session it is asked in. That makes it a write
  with an audit entry per check; it is asked only where a client put the
  switch, typically one settings page, and saves only when the session
  changed.
- **An allowlist of push-service hosts, not a block list of private
  addresses.** The browser's push service is one of a handful (FCM,
  Apple, Mozilla, Windows), so an allowlist names exactly where Tun may
  post, and needs no DNS lookups that could change between check and
  call (the allowlisted names are the services' own domains, which no
  subscriber controls). A block list would still let a viewer make Tun
  post to any public host. The cost: a browser on a new push service is
  refused until Tun adds its host, which the spec lists. Checked at
  subscribe and again at delivery, so a host removed from the list stops
  being posted to.
- **`push_test` once a minute per account,** recorded as `tested_at` on
  the account's subscriptions (as `accounts_invite` records
  `invited_at`); sooner is `conflict`.
- **The `:push` queue runs two at once** by default, each attempt cut
  off at 10 s: a slow push service holds up the queue for at most 10 s
  per attempt, and two leave room for mail and other calls within the
  tenant's four at once. Tun declaring a default for its own queue is
  new, in `jobs.md` §6; `(:queues ...)` overrides it, and every other
  queue stays at 1.
- **URLs:** `notify-push` refuses a URL whose second character is `/` or
  `\`; the worker resolves the URL against its origin and opens `/` for
  any other origin, so a notification never leads off the server.
- **A click with no window open is not checked in a browser.** The
  check clicks by dispatching `notificationclick` in the worker, which
  carries no user activation, and Chromium refuses `clients.openWindow`
  without one (tried: nothing opens). The branch is one call,
  `clients.openWindow(url)`, after the two that are checked.
- **Secret inputs are masked in request records generally:** an
  operation parameter can be declared `:secret t` (or reuse a secret
  field), and `recorded-input` shows `"***"` for it, as it already did for
  `settings_set`'s secret values (`core.md` §8.2, gate B's review).
- **A moved endpoint is a new record:** `push_subscribe` deletes the
  stored one and inserts anew, so the limit of 10, ordered by
  `created_at` and then insertion, never deletes the device just turned on.
- **`sub` only for an `https` public URL,** since the claim must be an
  `https:` or `mailto:` URI.
- **One job per device, `send_push`, in a `:push` queue, outside a
  transaction,** with mail's delays and seven attempts. No record per
  notification: the jobs are the record (`jobs_get`), and a push has no
  provider id or idempotency key to keep. 404/410 delete; 429, 5xx and no
  answer retry; other answers fail at once so a refused message does not
  retry for hours.
- **The port** is `deliver-push` on a push-service adapter. The real one
  posts through a new internal `tun.outbound:http-post`, which shares
  `http-json-post`'s limits, deadline and trace; `http-json-post` is
  rebuilt on it. The trace names only the endpoint's host, since its path
  addresses the device. A test-clock application gets an adapter that
  sends nothing; tests use a fake that records and answers.
- **`url` is a path on the server,** so a notification cannot send a
  person to another site; the worker takes anything else as `/`.
- **`push_test`** sends a notification to one's own devices, so a person
  (and a preview on a phone) can see that it works without the client
  writing anything.
- **The check runner uses Chromium's full browser, headless**
  (`channel="chromium"`): Playwright's default headless shell refuses
  notifications. Every check runs on it; `bin/check` shows the old ones
  still pass. The check stands in for the push service by replacing
  `PushManager.prototype.subscribe` in the page; no push service is
  contacted.
- **Not now** (spec §9): `pushsubscriptionchange`, `Topic`/`Urgency`,
  actions and badges, a page of one's other devices.
- **Core 1.19.0**, raised at Build. Shipped after board-order, which took 1.18.0.

## Log

- 2026-10-26 16:36  started, autonomous
- 2026-10-26 16:40  gate A asked of a reviewer
- 2026-10-26 16:45  gate A: changes (reviewer): off-site URLs (//host, /\host) must be refused and tested, worker falls back to /; a subscription found in a new session must move to it so logout deletes it; refuse endpoints on IP literals, localhost and private/loopback/link-local hosts, and limit push_test; fix §2.1 refs, ui.md §4.2 wording, sub only for https, the 3993 rationale, uncovered §2.2 rows and a non-JSON push in criterion 8
- 2026-10-26 16:48  gate A asked of a reviewer
- 2026-10-26 16:52  gate A: changes (reviewer): earlier points met; this_device is not in §8; criterion 10 must check an iPhone home-screen app shows the switch and an iPad tab shows the hint, and §2.2 must say which row wins; jobs.md §6 must allow a per-queue default (:push 2)
- 2026-10-26 16:54  gate A asked of the person
- 2026-10-26 17:00  gate A: approve (jonas): «Approve» (asked: approve the spec and criteria so building can start?)
- 2026-10-26 17:29  verify 1: passed build, test, check
- 2026-10-26 17:36  verify 2: passed build, test, check
- 2026-10-26 17:36  Built: spec/preview.md also names user_agent on t.phone()/t.desktop(), which the iOS checks need; the loop screenshots (tun_shots.py) use the same full Chromium as the checks
- 2026-10-26 17:36  shown (/varsler, /ui/push-switch)
- 2026-10-26 17:43  verify 3: passed build, test, check
- 2026-10-26 17:43  shown (/varsler, /ui/push-switch)
- 2026-10-26 17:44  gate B asked of a reviewer
- 2026-10-26 19:41  gate B: changes (reviewer): criterion 7 untested (a client page at push must be an extension-error); notify-push and push_subscribe must do nothing without (:web-app ...) as §1 says; bare-string errors in crypto.lisp; auth kept verbatim in request records; the 10-device limit can drop the subscription just saved (order by created_at)
- 2026-10-26 20:23  verify 4: passed build, test, check
- 2026-10-26 20:23  shown (/varsler, /ui/push-switch)
- 2026-10-26 20:23  gate B asked of a reviewer
- 2026-10-26 20:30  gate B: approve (reviewer): the five earlier points met and tested (push 217/217); criteria 1-13 hold; security re-checked; merge with board-order intact; verify 4 green
