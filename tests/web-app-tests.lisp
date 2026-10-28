;;;; tests/web-app-tests.lisp -- installing the client as an app
;;;; (spec/ui.md 4.2): the options, the icons, the manifest, the head, the
;;;; offline page and the service worker.

(in-package #:tun.tests)

(def-suite web-app :in core)
(in-suite web-app)

(define-application installable-app ()
  (:web-app :short-name "Prøve" :theme-color "#fafafa" :icons "fixtures/web-app-icons/")
  (:default-initargs :name "Prøveappen"))

(defparameter *web-app-icons*
  (asdf:system-relative-pathname "tun" "tests/fixtures/web-app-icons/"))

(defun web-octets (port path)
  "Values the status, the body's octets and the headers of GET PATH."
  (multiple-value-bind (octets status headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d~a" port path)
                           :redirect nil :force-binary t)
    (values status octets headers)))

(defun fixture-icon (file)
  "The octets of the fixture icon FILE."
  (with-open-file (in (merge-pathnames file *web-app-icons*) :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence octets in)
      octets)))

(defun header (name headers)
  (cdr (assoc name headers)))

(defun kept-paths (script)
  "The paths the service worker SCRIPT keeps, from its `const kept`."
  (cl-ppcre:register-groups-bind (array) ("const kept = (\\[[^\\]]*\\]);" script)
    (coerce (parse-json array) 'list)))

(defun icons-directory-with (file octets)
  "A fresh copy of the fixture icons with FILE replaced by OCTETS, or
removed when OCTETS is NIL."
  (let ((directory (uiop:ensure-directory-pathname
                    (merge-pathnames (format nil "tun-icons-~a" (random-token-string 8))
                                     (uiop:temporary-directory)))))
    (ensure-directories-exist directory)
    (dolist (source (uiop:directory-files *web-app-icons*))
      (uiop:copy-file source (merge-pathnames (file-namestring source) directory)))
    (let ((target (merge-pathnames file directory)))
      (if octets
          (with-open-file (out target :direction :output :element-type '(unsigned-byte 8)
                                      :if-exists :supersede)
            (write-sequence octets out))
          (delete-file target)))
    directory))

(test the-options-are-checked-when-the-form-is-compiled
  (dolist (options '((:short-name "x")
                     (:icons "icons/" :theme-color "red")
                     (:icons "icons/" :dark-theme-color "#12345")
                     (:icons "icons/" :short-name "Altfor langt navn")
                     (:icons "icons/" :colour "#fff")
                     (:icons)))
    (signals error (macroexpand-1 `(define-application broken-web-app () (:web-app ,@options)))
      "~s is refused" options))
  ;; INSTALLABLE-APP above shows a directory relative to this file is found.
  (signals error (macroexpand-1 '(define-application iconless-web-app () (:web-app :icons "x/")))
    "a directory without the icons"))

(test the-icons-are-checked-when-the-form-is-compiled
  (let ((svg (sb-ext:string-to-octets "<svg/>" :external-format :utf-8)))
    (let ((icons (tun.core::web-app-icons *web-app-icons*)))
      (is (equal '("icon.svg" "icon-192.png" "icon-512.png" "icon-maskable-512.png"
                   "apple-touch-icon.png")
                 (mapcar (lambda (icon) (getf icon :file)) icons)))
      (is (every (lambda (icon) (= 12 (length (getf icon :hash)))) icons)))
    (flet ((refused (file octets pattern)
             (let ((directory (icons-directory-with file octets)))
               (unwind-protect
                    (let ((message (handler-case
                                       (progn (tun.core::web-app-icons directory) "no error")
                                     (error (e) (princ-to-string e)))))
                      (is (search pattern message) "~a: ~a" file message))
                 (uiop:delete-directory-tree directory :validate t)))))
      (refused "icon-192.png" nil "missing")
      (refused "apple-touch-icon.png"
               (fixture-icon "icon-192.png")
               "192x192, not a 180x180 PNG")
      (refused "icon-512.png" svg "not a PNG")
      (refused "icon.svg" (fixture-icon "icon-192.png")
               "not an SVG"))))

(test the-manifest-and-icons-are-served-without-a-login
  (with-test-server (port :class 'installable-app)
    (multiple-value-bind (status body headers) (web-request port "/manifest.webmanifest")
      (is (= 200 status))
      (is (search "application/manifest+json" (header :content-type headers)))
      (is (string= "no-cache" (header :cache-control headers)))
      (let ((manifest (parse-json body)))
        (is (equal '("/" "/" "/" "Prøveappen" "Prøve" "standalone" "en" "#fafafa" "#ffffff")
                   (mapcar (lambda (key) (jget manifest key))
                           '("id" "start_url" "scope" "name" "short_name" "display" "lang"
                             "theme_color" "background_color"))))
        (let ((icons (coerce (jget manifest "icons") 'list)))
          (is (equal '(("image/svg+xml" "any" nil) ("image/png" "192x192" nil)
                       ("image/png" "512x512" nil) ("image/png" "512x512" "maskable"))
                     (mapcar (lambda (icon) (list (jget icon "type") (jget icon "sizes")
                                                  (jget icon "purpose")))
                             icons)))
          (dolist (icon icons)
            (multiple-value-bind (status octets headers) (web-octets port (jget icon "src"))
              (is (= 200 status) "~a" (jget icon "src"))
              (is (string= (jget icon "type") (header :content-type headers)))
              (is (string= "public, max-age=31536000, immutable" (header :cache-control headers)))
              (is (plusp (length octets)))))
          (let ((maskable (jget (fourth icons) "src")))
            (is (cl-ppcre:scan "^/assets/icon-maskable-512-[0-9a-f]{12}\\.png$" maskable))
            (is (equalp (fixture-icon "icon-maskable-512.png")
                        (nth-value 1 (web-octets port maskable))))))))
    (multiple-value-bind (status octets headers) (web-octets port "/assets/icon-192-000000000000.png")
      (is (= 200 status) "an older page still gets the icon")
      (is (plusp (length octets)))
      (is (string= "no-store" (header :cache-control headers))))
    (is (= 404 (web-request port "/assets/icon-1024-000000000000.png")))))

(test every-page-carries-the-head-tags
  (with-test-server (port :class 'installable-app)
    (dolist (body (list (nth-value 1 (web-request port "/login"))
                        (nth-value 1 (web-request port "/settings" :jar (web-login port "admin:root")))))
      (is (search "<link rel=\"manifest\" href=\"/manifest.webmanifest\">" body))
      (is (search "<meta name=\"theme-color\" media=\"(prefers-color-scheme: light)\" content=\"#fafafa\">" body))
      (is (search "<meta name=\"theme-color\" media=\"(prefers-color-scheme: dark)\" content=\"#0a0a0a\">" body))
      (is (cl-ppcre:scan "<link rel=\"icon\" type=\"image/svg\\+xml\" href=\"/assets/icon-[0-9a-f]{12}\\.svg\">" body))
      (is (cl-ppcre:scan "<link rel=\"icon\" type=\"image/png\" sizes=\"192x192\" href=\"/assets/icon-192-[0-9a-f]{12}\\.png\">" body))
      (is (cl-ppcre:scan "<link rel=\"apple-touch-icon\" sizes=\"180x180\" href=\"/assets/apple-touch-icon-[0-9a-f]{12}\\.png\">" body))
      (is (search "<meta name=\"apple-mobile-web-app-title\" content=\"Prøve\">" body))
      (is (search "<meta name=\"mobile-web-app-capable\" content=\"yes\">" body)))
    (is (search "navigator.serviceWorker.register('/sw.js'"
                (nth-value 1 (web-request port (tun.ui:script-path))))
        "the components' script registers the worker")))

(test the-offline-page-holds-nothing-about-who-is-signed-in
  (with-test-server (port :class 'installable-app)
    (multiple-value-bind (status body headers)
        (web-request port "/offline" :jar (web-login port "employee:anna"))
      (is (= 200 status))
      (is (search "text/html" (header :content-type headers)))
      (is (search "You are offline" body))
      (is (search "Try again" body))
      (is (search "href=\"\"" body) "«Try again» loads the address again")
      (is (search "rel=\"manifest\"" body))
      (is (not (search "anna" body)))
      (is (not (search "Sign out" body))))))

;; spec/i18n.md 2.1, 3.6: the manifest's lang, the offline page and the
;; worker's text for a push without data follow the tenant's language.
(test the-web-app-speaks-the-tenants-language
  (with-test-server (port :class 'installable-app)
    (flet ((manifest-lang ()
             (jget (parse-json (sb-ext:octets-to-string
                                (nth-value 1 (web-octets port "/manifest.webmanifest"))
                                :external-format :utf-8))
                   "lang"))
           (worker () (nth-value 1 (web-request port "/sw.js"))))
      (let ((english (worker)))
        (is (equal "en" (manifest-lang)))
        (is (search "const unnamed = \"You have a new notification\";" english))
        (is (search "body: unnamed" english))
        (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "nb")
        (is (equal "nb" (manifest-lang)))
        (let ((norwegian (worker)))
          (is (search "const unnamed = \"Du har et nytt varsel\";" norwegian))
          (is (not (search "You have a new notification" norwegian)))
          (is (string/= (subseq english 0 (search "const offline" english))
                        (subseq norwegian 0 (search "const offline" norwegian)))
              "a new cache, since the offline page it keeps changed"))
        (is (search "Du er frakoblet" (nth-value 1 (web-request port "/offline"))))))))

(test the-service-worker-keeps-the-assets-and-the-offline-page
  (with-test-server (port :class 'installable-app)
    (multiple-value-bind (status script headers) (web-request port "/sw.js")
      (is (= 200 status))
      (is (search "text/javascript" (header :content-type headers)))
      (is (string= "no-cache" (header :cache-control headers)))
      (is (equal (list "/offline" (tun.ui:stylesheet-path) (tun.ui:script-path) (tun.ui:htmx-path))
                 (kept-paths script)))
      (is (cl-ppcre:scan "const version = \"tun-[0-9a-f]{12}\";" script))
      (is (search "request.mode === 'navigate'" script))
      (is (not (search "cache.put" script)) "it stores no answer")
      (is (string= script (nth-value 1 (web-request port "/sw.js"))) "the same version twice"))))

(test without-the-option-nothing-is-installed
  (with-test-server (port)
    (is (= 404 (web-request port "/manifest.webmanifest")))
    (is (= 404 (web-request port "/offline")))
    (is (not (search "rel=\"manifest\"" (nth-value 1 (web-request port "/login")))))
    (multiple-value-bind (status script) (web-request port "/sw.js")
      (is (= 200 status))
      (is (search "self.registration.unregister()" script) "an earlier worker removes itself")
      (is (null (kept-paths script))))))

(test a-clients-page-cannot-take-the-paths
  (dolist (path '("offline" "sw.js" "manifest.webmanifest"))
    (let ((tun.web::*public-pages* (make-hash-table :test 'equal)))
      (let ((*package* (find-package "TUN.CUSTOMERS")))
        (tun.web:register-public-page path 'identity))
      (signals extension-error (with-test-app () nil)))))
