;;;; tests/page-test-tests.lisp -- the reader of page tests over HTTP
;;;; (spec/testing.md 6): the element tree and its selectors, a page's text,
;;;; links and forms, and the server whose requests go as a browser sends
;;;; them.

(in-package #:tun.tests)
(def-suite page-test :in core)
(in-suite page-test)

;;; ------------------------------------------------------------------
;;; Reading a page

(defparameter +read-page+
  "<!doctype html><html lang=\"en\"><head><title>Orders – app</title>
<script>if (a < b && c > d) { show(\"<p>\"); }</script><style>p > b { color: red }</style></head>
<body><header><form class=\"tun-app-shell-logout\" method=\"post\" action=\"/logout\">
<button type=\"submit\">Sign out</button></form></header>
<main id=\"main-content\"><h1>Orders</h1><h2 class=\"sub\">Open</h2>
<p data-part=\"total\" class=\"tun-total big\">Total: <strong>1&nbsp;250,00</strong> kr</p>
<ul data-part=\"rows\"><li data-key=\"a1\">One</li><li hidden>Gone</li>
<li data-key=\"b2\">Two &amp; three</li></ul>
<template><p>Not shown</p></template>
<a href=\"/orders?status=open&amp;page=2\">Next <span>page</span></a><a>No target</a>
<div class=\"tun-alert\" role=\"alert\">Something needs correcting</div><p role=\"alert\">Also</p>
<input name=\"outside\" form=\"order\" value=\"from outside\">
<form id=\"order\" method=\"post\" action=\"/orders\" enctype=\"multipart/form-data\">
<input type=\"hidden\" name=\"id\" value=\"o1\">
<input name=\"title\" value=\"Tent &quot;big&quot;\">
<input type=\"checkbox\" name=\"days\" value=\"mon\" checked>
<input type=\"checkbox\" name=\"days\" value=\"tue\">
<input type=\"checkbox\" name=\"days\" value=\"wed\" checked>
<input type=\"checkbox\" name=\"agree\" checked>
<input type=\"radio\" name=\"size\" value=\"s\">
<input type=\"radio\" name=\"size\" value=\"m\" checked>
<select name=\"kind\"><option value=\"a\">A</option>
<option value=\"b\" selected>B</option></select>
<select name=\"first\"><option>Plain</option><option>Other</option></select>
<select name=\"many\" multiple><option value=\"x\" selected>X</option>
<option value=\"y\">Y</option><option value=\"z\" selected>Z</option></select>
<textarea name=\"note\">
Line one
Line two</textarea>
<input type=\"file\" name=\"files\"><input name=\"off\" value=\"no\" disabled>
<div class=\"tun-field\" data-invalid=\"true\"><label for=\"email\">Email</label>
<p class=\"tun-field-hint\" id=\"email-hint\">Where we write</p>
<p class=\"tun-field-error\" id=\"email-error\">Email must be an address</p>
<input name=\"email\" id=\"email\" value=\"nope\" aria-invalid=\"true\"
 aria-describedby=\"email-hint email-error\"></div>
<button type=\"button\">Preview</button><button type=\"submit\">Plain</button>
<button type=\"submit\" name=\"go\" value=\"save\">Save</button>
<button type=\"submit\" name=\"go\" value=\"close\" formaction=\"/orders/close\">
Save and close</button>
</form>
<form method=\"get\" action=\"/orders\"><input name=\"q\" value=\"tent\">
<button>Search</button></form>
</main></body></html>"
  "A page as Tun's renderer writes it, with what each reader reads.")

(defun read-page () (page:read-html +read-page+))

(test the-reader-finds-elements-by-a-small-set-of-selectors
  (let ((page (read-page)))
    (is (equal '("h1") (mapcar #'page:tag (page:elements page "h1"))))
    (is (equal "Open" (page:text (page:element page "h2.sub"))))
    (is (equal "Open" (page:text (page:element page ".sub"))))
    (is (equal "main" (page:tag (page:element page "#main-content"))))
    (is (= 2 (length (page:elements page "li[data-key]"))) "an attribute that is there")
    (is (equal "Two & three" (page:text (page:element page "li[data-key=b2]"))) "a value, bare")
    (is (equal "Two & three" (page:text (page:element page "li[data-key='b2']"))) "quoted")
    (is (equal "Total: 1 250,00 kr" (page:text (page:element page "p[class~=big]")))
        "a word of it")
    (is (= 1 (length (page:elements page "a[href^='/orders?']"))) "its start")
    (is (= 1 (length (page:elements page "a[href$=\"page=2\"]"))) "its end")
    (is (= 1 (length (page:elements page "a[href*=status]"))) "inside it")
    (is (= 3 (length (page:elements page "main li"))) "a descendant")
    (is (= 2 (length (page:elements page "ul > li[data-key]"))) "a child")
    (is (null (page:elements page "main > li")) "not a child of main")
    (is (equal '("h1" "h2") (mapcar #'page:tag (page:elements page "h2, h1")))
        "several, in document order")
    (is (= 2 (length (page:elements (page:element page "ul") "li[data-key]"))) "inside an element")
    (dolist (selector '("a:hover" "li + li" "ul ~ p" "[data-key|=a]" "" "main >" "> li" "h1,,h2"))
      (let ((refusal (handler-case (progn (page:elements page selector) nil)
                       (error (condition) (princ-to-string condition)))))
        (is (and refusal (search (format nil "~s" selector) refusal))
            "~s is refused, naming it: ~a" selector refusal)))))

(test the-reader-reads-a-page-as-a-person-does
  (let ((page (read-page)))
    (is (equal "Orders – app" (page:title page)))
    (is (equal '("Orders" "Open") (page:headings page)))
    (is (equal "Total: 1 250,00 kr" (page:text (page:part page "total")))
        "inline elements run on; a space that does not break stays")
    (is (equal "One Two & three" (page:text (page:part page "rows")))
        "the edges of a block are a space; a hidden element is not read")
    (is (equal 1 (length (page:parts page "total"))))
    (let ((text (page:text page)))
      (is (not (search "show(" text)) "no script")
      (is (not (search "color" text)) "no style")
      (is (not (search "Not shown" text)) "no template")
      (is (search "Next page" text)))
    (is (equal '(("Next page" . "/orders?status=open&page=2")) (page:links page))
        "each link with an href, its text and its href")
    (is (equal '("Something needs correcting" "Also") (page:alerts page)))
    (is (equal "main-content" (page:attribute (page:element page "main") "id")))
    (is (eq t (page:attribute (page:element page "li[hidden]") "hidden")) "one without a value")
    (is (null (page:attribute (page:element page "main") "class")))))

(test a-form-holds-what-a-browser-sends-of-it-untouched
  (let* ((page (read-page))
         (form (page:form page)))
    (is (equal "/orders" (page:form-action form)) "the first form in <main>, not the frame's")
    (is (equal "post" (page:form-method form)))
    (is (page:form-multipart-p form))
    (is (equal '(("outside" . "from outside") ("id" . "o1") ("title" . "Tent \"big\"")
                 ("days" . "mon") ("days" . "wed") ("agree" . "on") ("size" . "m") ("kind" . "b")
                 ("first" . "Plain") ("many" . "x") ("many" . "z") ("note" . "Line one
Line two")
                 ("email" . "nope") ("go" . "save"))
               (page:form-fields form))
        "a control naming the form, ticked boxes, selects, the text area's text, ~
         the first named button")
    (is (equal '("mon" "wed") (page:form-values form "days")))
    (is (equal "b" (page:form-value form "kind")))
    (is (null (page:form-value form "off")) "a disabled control sends nothing")
    (is (null (page:form-value form "files")) "nor a file input left empty")
    (is (equal '(("email" . "Email must be an address")) (page:form-errors form)))
    (is (equal "Email must be an address" (page:form-error form "email")))
    (is (null (page:form-error form "title")))
    (is (equal "get" (page:form-method (page:form page "form[method=get]"))))
    (is (equal '("/logout" "/orders" "/orders") (mapcar #'page:form-action (page:forms page))))
    (is (= 2 (length (page:elements form "select[name=kind] option")))
        "a form is read as an element is")))

(test fields-a-test-gives-take-the-place-of-the-page-s
  (is (equal '(("id" . "o1") ("days" . "tue") ("days" . "thu") ("note" . "x") ("new" . "1"))
             (tun.page-test::replace-fields
              '(("id" . "o1") ("days" . "mon") ("note" . "n") ("days" . "wed"))
              '(("days" "tue" "thu") ("note" . "x") ("new" . 1)))))
  (is (equal '(("id" . "o1"))
             (tun.page-test::replace-fields '(("id" . "o1") ("days" . "mon")) '(("days"))))
      "a name with no values sends none, as boxes left unticked"))

;;; ------------------------------------------------------------------
;;; The server

(defvar *page-test-request* nil "What the echo page saw last.")

(defun page-test-echo-page (method path form query)
  "A staff page that answers what it got: the method, the actor, htmx's
headers, the form; on a post of go=away, 303 to /page-test-echo?done=1."
  (declare (ignore path query))
  (let ((seen (list :method method
                    :actor (and *actor* (actor-string *actor*))
                    :htmx (tun.web:htmx-request-p)
                    :target (hunchentoot:header-in* :hx-target)
                    :extra (hunchentoot:header-in* :x-page-test)
                    :form form)))
    (setf (sb-ext:symbol-global-value '*page-test-request*) seen)
    (cond ((and (eq method :post) (equal (jget form "go") "away"))
           (values 303 "/page-test-echo?done=1"))
          ((tun.web:htmx-request-p)
           (values 200 :fragment (list '(:p (:@ :data-part "fragment") "Part"))))
          (t (values 200 "Echo"
                     (list `(:p (:@ :data-part "who") ,(or (getf seen :actor) "no one"))
                           '(:a (:@ :href "/page-test-echo?again=1") "Again")
                           '(:button (:@ :hx-get "/page-test-echo?part=1" :hx-target "#here")
                             "Part")
                           `(:form (:@ :method "post" :action "/page-test-echo")
                                   (:input (:@ :name "title" :value "Kept"))
                                   (:input (:@ :type "checkbox" :name "days" :value "mon"
                                               :checked t))
                                   (:button (:@ :type "submit" :name "go" :value "stay") "Stay")
                                   (:button (:@ :type "submit" :name "go" :value "away")
                                            "Away"))))))))

(defmacro with-echo-page (() &body body)
  "Run BODY with the echo page at /page-test-echo."
  `(unwind-protect
        (progn (tun.web:register-staff-page "page-test-echo" 'page-test-echo-page
                                            :policy :employee :navigation nil)
               ,@body)
     (remhash "page-test-echo" tun.web::*staff-pages*)))

(defun echo-seen (key)
  (getf (sb-ext:symbol-global-value '*page-test-request*) key))

(test the-server-s-requests-go-as-a-browser-sends-them
  (with-echo-page ()
    (page:with-server (:actor "employee:anna")
      (let ((page (page:visit "/page-test-echo")))
        (is (= 200 (page:status page)))
        (is (equal "employee:anna" (page:text (page:part page "who"))) "as the server's actor")
        (is (equal "admin:ada"
                   (page:text (page:part (page:visit "/page-test-echo" :actor "admin:ada") "who")))
            "or another")
        (let ((away (page:visit "/page-test-echo" :actor nil)))
          (is (= 303 (page:status away)) "no one is sent to the login")
          (is (equal "/login?next=%2Fpage-test-echo" (page:location away)))
          (is (= 200 (page:status (page:follow away :actor nil))) "the login page, to no one"))
        (let ((stay (page:submit page :fields '(("days" "mon" "tue")))))
          (is (= 200 (page:status stay)))
          (is (eq :post (echo-seen :method)))
          (is (equal "Kept" (jget (echo-seen :form) "title")) "the page's own values")
          (is (equalp #("mon" "tue") (jget (echo-seen :form) "days")) "and the test's, a set")
          (is (equal "stay" (jget (echo-seen :form) "go")) "the first named button"))
        (let ((away (page:submit page :button "Away")))
          (is (= 303 (page:status away)) "the button pressed")
          (is (equal "/page-test-echo?done=1" (page:location away)))
          (is (equal "/page-test-echo?done=1" (tun.page-test::answer-path (page:follow away)))))
        (let ((part (page:visit "/page-test-echo" :htmx :partial :target "#here"
                                :headers '(("X-Page-Test" . "1")))))
          (is (echo-seen :htmx) "htmx's headers")
          (is (equal "#here" (echo-seen :target)))
          (is (equal "1" (echo-seen :extra)) "and others")
          (is (equal "Part" (page:text (page:part part "fragment"))) "a fragment, read as a page"))
        (let ((posted (page:post "/page-test-echo" '(("go" . "stay") ("days" "tue" "wed")))))
          (is (= 200 (page:status posted)))
          (is (equalp #("tue" "wed") (jget (echo-seen :form) "days"))))))))

(test an-answer-says-its-status-headers-and-body
  (page:with-server (:actor "admin:ada")
    (let ((page (page:visit "/settings")))
      (is (equal "text/html" (page:content-type page)))
      (is (stringp (page:body page)))
      (is (search "default-src" (page:header page "Content-Security-Policy"))
          "a header by its name")
      (is (equal (page:header page "content-security-policy")
                 (page:header page :content-security-policy))))
    (let ((asked (page:visit "/settings?x=%2Fa%3Fb")))
      (is (= 200 (page:status asked)) "a path's escapes go as they are written"))
    (let ((health (page:visit "/health")))
      (is (equal "text/plain" (page:content-type health)) "a type without its parameters")
      (is (equal "ok" (page:body health)) "a text's body as text"))))

(test with-server-sets-the-tenant-s-language
  (page:with-server (:actor "admin:ada" :language "nb")
    (let ((page (page:visit "/settings")))
      (is (equal "nb" (page:attribute (page:element page "html") "lang")))
      (is (equal "Innstillinger" (first (page:headings page)))))))

(defvar *page-test-scenario-runs* (list 0)
  "How many times the scenarios below were made, counted in place, so that
counting is not a variable the scenario sets.")
(defvar *page-test-setting* nil "What the scenario page-test-sets sets.")

(defun page-test-scenario-runs () (car *page-test-scenario-runs*))

(define-scenario page-test-records (:actors ("admin:ada"))
  "The tenant's language set to Norwegian, a record."
  (incf (car *page-test-scenario-runs*))
  (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "nb"))

(define-scenario page-test-sets (:actors ("admin:ada"))
  "The same, and a variable set."
  (incf (car *page-test-scenario-runs*))
  (setf (sb-ext:symbol-global-value '*page-test-setting*) (list (random 1000)))
  (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "nb"))

(defun scenario-shown-p ()
  "Whether the page shows the scenario's record: the tenant's language."
  (equal "nb" (page:attribute (page:element (page:visit "/settings") "html") "lang")))

(test a-scenario-is-made-once-and-copied-unless-it-sets-a-variable
  (setf (car *page-test-scenario-runs*) 0)
  (clrhash tun.page-test::*templates*)
  (dotimes (i 3)
    (page:with-server (:scenario 'page-test-records :actor "admin:ada")
      (is (scenario-shown-p) "each server holds the scenario's records")
      (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "en")))
  (is (= 1 (page-test-scenario-runs)) "made once, copied for each, each copy its own")
  (setf (car *page-test-scenario-runs*) 0)
  (dotimes (i 2)
    (page:with-server (:scenario 'page-test-sets :actor "admin:ada")
      (is (scenario-shown-p))))
  (is (= 3 (page-test-scenario-runs))
      "one that sets a variable is made again for each server, after the first look"))

(test on-postgres-the-scenario-is-a-template-copied-for-each-server
  (if (not (postgres-available-p))
      (skip "no test Postgres (TUN_TEST_POSTGRES)")
      (progn
        (setf (car *page-test-scenario-runs*) 0)
        (clrhash tun.page-test::*templates*)
        (dotimes (i 3)
          (page:with-server (:scenario 'page-test-records :database :postgres :actor "admin:ada")
            (is (typep (application-store *app*) 'tun.store.postgres:postgres-store))
            (is (scenario-shown-p) "each copy holds the scenario's records")
            (call-ok "settings_set" "admin:ada" "key" "locale.language" "value" "en")
            (is (not (scenario-shown-p)) "and is changed in itself")))
        (is (= 1 (page-test-scenario-runs))
            "made once into a template, which each server copied while no one held it")
        (setf (car *page-test-scenario-runs*) 0)
        (dotimes (i 2)
          (page:with-server (:scenario 'page-test-sets :database :postgres :actor "admin:ada")
            (is (scenario-shown-p))))
        (is (= 3 (page-test-scenario-runs)) "one that sets a variable, made for each"))))

(test a-page-test-costs-milliseconds
  (page:with-server (:scenario 'page-test-records :actor "admin:ada")
    (page:visit "/settings"))
  (is-fast (:why "a server on a scenario made before, and a page of it" :limit-ms 400 :runs 5)
           (page:with-server (:scenario 'page-test-records :actor "admin:ada")
             (page:visit "/settings"))))

;;; ------------------------------------------------------------------
;;; The pages the generated browser check opens (spec/preview.md 4)

(test the-sweep-lists-each-actor-s-whole-pages
  (with-echo-page ()
    (with-test-app (:identity :claimed)
      (let* ((swept (tun.test-support::swept-pages *app* nil))
             (employee (cdr (assoc "employee:fuzz" swept :test #'equal)))
             (viewer (cdr (assoc "viewer:fuzz" swept :test #'equal))))
        (is (equal '("admin:fuzz" "employee:fuzz" "viewer:fuzz" nil) (mapcar #'car swept))
            "the sweep's actors, and no one")
        (is (member "/page-test-echo" employee :test #'equal) "a page its policy admits")
        (is (member "/page-test-echo?again=1" employee :test #'equal) "and one it links to")
        (is (not (member "/page-test-echo?part=1" employee :test #'equal))
            "not a fragment htmx asks for")
        (is (not (member "/page-test-echo" viewer :test #'equal)) "not a page it is refused")
        (is (not (member "/page-test-echo" (cdr (assoc nil swept)) :test #'equal))
            "nor to no one, who is sent to the login")
        (is (= (length employee) (length (remove-duplicates employee :test #'equal)))
            "each once")))))
