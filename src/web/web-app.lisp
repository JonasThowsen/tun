;;;; web/web-app.lisp -- installing the client as an app (spec/ui.md 4.2):
;;;; the manifest, the icons, the tags in every page's head, the offline page
;;;; and the service worker, from the client's (:web-app ...).
;;;;
;;;; The service worker keeps the design system's assets and the offline
;;;; page, nothing else: a page a signed-in person sees, and every answer
;;;; of /api and /mcp, goes to the network and is never stored.  It also
;;;; shows the notifications pushed to the device and opens their page
;;;; (spec/push.md 7).

(in-package #:tun.web)

(declaim (optimize (safety 3) (debug 2)))

(defun web-app ()
  "The running application's (:web-app ...), as APPLICATION-WEB-APP gives
it, or NIL."
  (application-web-app *web-app*))

(defun web-app-short-name (web-app)
  (or (getf web-app :short-name) (application-title *web-app*)))

;;; ------------------------------------------------------------------
;;; The icons

(defun web-app-icon (web-app file)
  (find file (getf web-app :icons) :key (lambda (icon) (getf icon :file)) :test #'string=))

(defun icon-path (icon)
  "Where ICON is served: /assets/NAME-HASH.EXT."
  (let* ((file (getf icon :file))
         (dot (position #\. file :from-end t)))
    (format nil "/assets/~a-~a~a" (subseq file 0 dot) (getf icon :hash) (subseq file dot))))

(defun serve-icon (path)
  "The web app's icon at PATH, or NIL.  The current one is cached for good;
an older hash gets today's icon, uncached, as SERVE-ASSET does."
  (let ((web-app (web-app)))
    (cl-ppcre:register-groups-bind (name hash extension)
        ("^/assets/([a-z0-9-]+)-([0-9a-f]{12})\\.(svg|png)$" path)
      (let ((icon (and web-app (web-app-icon web-app (format nil "~a.~a" name extension)))))
        (when icon
          (setf (hunchentoot:content-type*) (getf icon :type)
                (hunchentoot:header-out "Cache-Control") (if (string= hash (getf icon :hash))
                                                             "public, max-age=31536000, immutable"
                                                             "no-store"))
          (getf icon :octets))))))

;;; ------------------------------------------------------------------
;;; The manifest and the head

(defun manifest-json (web-app)
  (flet ((icon (file sizes &optional purpose)
           (let ((icon (web-app-icon web-app file)))
             (apply #'jobj "src" (icon-path icon) "type" (getf icon :type) "sizes" sizes
                    (and purpose (list "purpose" purpose))))))
    (jobj "id" "/" "start_url" "/" "scope" "/"
          "name" (application-title *web-app*) "short_name" (web-app-short-name web-app)
          "display" "standalone" "lang" "no"
          "theme_color" (getf web-app :theme-color)
          "background_color" (getf web-app :background-color)
          "icons" (jarr (list (icon "icon.svg" "any")
                              (icon "icon-192.png" "192x192")
                              (icon "icon-512.png" "512x512")
                              (icon "icon-maskable-512.png" "512x512" "maskable"))))))

(defun web-app-head ()
  "The tags in a page's head that let a browser install the client as an
app, or NIL without (:web-app ...)."
  (let ((web-app (web-app)))
    (when web-app
      (flet ((href (file) (icon-path (web-app-icon web-app file))))
        `((:link (:@ :rel "manifest" :href "/manifest.webmanifest"))
          (:meta (:@ :name "theme-color" :media "(prefers-color-scheme: light)"
                     :content ,(getf web-app :theme-color)))
          (:meta (:@ :name "theme-color" :media "(prefers-color-scheme: dark)"
                     :content ,(getf web-app :dark-theme-color)))
          (:link (:@ :rel "icon" :type "image/svg+xml" :href ,(href "icon.svg")))
          (:link (:@ :rel "icon" :type "image/png" :sizes "192x192" :href ,(href "icon-192.png")))
          (:link (:@ :rel "apple-touch-icon" :sizes "180x180" :href ,(href "apple-touch-icon.png")))
          (:meta (:@ :name "apple-mobile-web-app-title" :content ,(web-app-short-name web-app)))
          (:meta (:@ :name "mobile-web-app-capable" :content "yes")))))))

;;; ------------------------------------------------------------------
;;; The offline page and the service worker

(defun offline-html ()
  "The page the service worker shows when the network fails: for someone
not logged in, whoever asks, since the worker keeps it."
  (let ((*actor* nil))
    (render-html
     (page-document "Du er frakoblet"
                    (page-frame (list (ui:page-header*
                                       (list :title "Du er frakoblet"
                                             :description "Siden kunne ikke hentes. Prøv igjen når du er på nett."))
                                      ;; An empty href is the address the page is shown at.
                                      (ui:cluster ()
                                        (ui:button (:href "" :icon :refresh-cw) "Prøv igjen")))
                                :guest t :width :narrow)))))

(defparameter +service-worker+ "'use strict';
// Tun's service worker (spec/ui.md 4.2).  It keeps this version's
// stylesheet, scripts and offline page, answers those assets from its
// cache, and shows the offline page when a page cannot be fetched.  It
// stores nothing else: pages, /api and /mcp carry signed-in data.  It
// shows the notifications pushed to this device (spec/push.md 7).
const version = ~s;
const offline = '/offline';
const kept = ~a;
const title = ~a;
const icon = ~a;

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(version)
    .then((cache) => cache.addAll(kept.map((path) => new Request(path, { cache: 'reload' }))))
    .then(() => self.skipWaiting()));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys()
    .then((names) => Promise.all(names
      .filter((name) => name.startsWith('tun-') && name !== version)
      .map((name) => caches.delete(name))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (url.pathname === '/api' || url.pathname.startsWith('/api/')
      || url.pathname === '/mcp' || url.pathname.startsWith('/mcp/')) return;
  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(() => caches.match(offline)));
  } else if (url.pathname !== offline && kept.includes(url.pathname)) {
    event.respondWith(caches.match(request).then((answer) => answer || fetch(request)));
  }
});

// Every push shows a notification: iOS takes the permission back from an
// app that is woken by a push and shows nothing.
self.addEventListener('push', (event) => {
  let message = null;
  try {
    message = event.data ? event.data.json() : null;
  } catch (error) {
    message = null;
  }
  if (!message || typeof message.title !== 'string')
    message = { title, body: 'Du har et nytt varsel', url: '/' };
  const options = { body: typeof message.body === 'string' ? message.body : '', icon,
                    data: { url: message.url } };
  if (typeof message.tag === 'string') {
    options.tag = message.tag;
    options.renotify = true;
  }
  event.waitUntil(self.registration.showNotification(message.title, options));
});

// The page a notification opens: its URL on this server, else the start page.
const notificationUrl = (url) => {
  const start = new URL('/', self.location.origin).href;
  try {
    const target = new URL(typeof url === 'string' ? url : '/', self.location.origin);
    return target.origin === self.location.origin ? target.href : start;
  } catch (error) {
    return start;
  }
};

// A click brings forward the app's window showing the page, else sends one
// of its windows there, else opens a window.  Focusing is allowed only
// while the click lasts, so a refusal must not stop the rest.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const url = notificationUrl(event.notification.data && event.notification.data.url);
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true })
    .then(async (windows) => {
      const showing = windows.find((client) => client.url === url);
      if (showing) return showing.focus().catch(() => showing);
      const other = windows[0];
      if (!other) return self.clients.openWindow(url);
      await other.focus().catch(() => other);
      return other.navigate(url).catch(() => self.clients.openWindow(url));
    }));
});
"
  "The service worker, given its cache's name, the paths it keeps as a JSON
array, and the application's title and icon as JSON strings.")

(defparameter +removing-service-worker+ "'use strict';
// This Tun is not installed as an app (spec/ui.md 4.2).  A worker an earlier
// version registered is replaced by this one, which deletes Tun's caches
// and unregisters itself.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil(caches.keys()
    .then((names) => Promise.all(names
      .filter((name) => name.startsWith('tun-'))
      .map((name) => caches.delete(name))))
    .then(() => self.registration.unregister()));
});
"
  "The service worker without (:web-app ...).")

(defun service-worker-script ()
  "The service worker for the running application.  Its cache is named
after the versions of what it keeps, so a deploy that changes any of them
installs a new worker, which deletes the older cache."
  (if (web-app)
      (let ((kept (list "/offline" (ui:stylesheet-path) (ui:script-path) (ui:htmx-path))))
        (format nil +service-worker+
                (format nil "tun-~a" (subseq (sha256-hex (format nil "~{~a~^ ~}~%~a" kept (offline-html)))
                                             0 12))
                (to-json-string (jarr kept))
                (to-json-string (application-title *web-app*))
                (to-json-string (icon-path (web-app-icon (web-app) "icon-192.png")))))
      +removing-service-worker+))

;;; ------------------------------------------------------------------
;;; Serving them

(defun web-app-path-p (path)
  "True for Tun's paths for installing the client as an app, which no
client page takes (CHECK-HTTP-ROUTE-CONFLICTS)."
  (member path '("/manifest.webmanifest" "/sw.js" "/offline") :test #'string=))

(defun serve-web-app (path)
  "PATH, one WEB-APP-PATH-P is true for, answered; NIL (not found) for the manifest
and the offline page without (:web-app ...)."
  (flet ((answer (type text)
           (setf (hunchentoot:content-type*) type
                 (hunchentoot:header-out "Cache-Control") "no-cache")
           (sb-ext:string-to-octets text :external-format :utf-8)))
    (let ((web-app (web-app)))
      (cond ((string= path "/sw.js")
             (answer "text/javascript; charset=utf-8" (service-worker-script)))
            ((null web-app) nil)
            ((string= path "/manifest.webmanifest")
             (answer "application/manifest+json; charset=utf-8"
                     (to-json-string (manifest-json web-app))))
            (t (answer "text/html; charset=utf-8" (offline-html)))))))
