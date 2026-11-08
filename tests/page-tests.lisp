;;;; tests/page-tests.lisp -- every page for every role (spec/testing.md 5):
;;;; Tun's own pages opened as a client's are, and probe pages whose planted
;;;; defects show that the page test finds each kind of failure.

(in-package #:tun.tests)

(def-suite pages :in core)
(in-suite pages)

(test tun-pages-answer-every-role
  (check-every-page-answers-every-role
   "Tun's pages" :scenario (find-scenario "fuzz-records" :package "TUN.TESTS")))

;;; ------------------------------------------------------------------
;;; Probe pages, and the defects a test plants in them (*PLANTED-DEFECTS*,
;;; tests/fuzz-tests.lisp)

(defvar *probe-outbound-answer* nil
  "What the probe page's call to another system got, the last time it made
one.")

(defun planted-p (defect) (member defect *planted-defects*))

(defun probe-fault (what)
  (error "The probe page failed: ~a" what))

(defun probe-customers ()
  "The customers the actor may see, by name: an order that does not depend
on their ids."
  (sort (coerce (jget (tun.web:web-call "customers_list" (jobj "limit" 10)) "items") 'list)
        #'string< :key (lambda (customer) (jget customer "name"))))

(defun probe-index ()
  "The probe's index: links of each kind the page test follows, and forms of
each kind it posts."
  `((:p (:a (:@ :href "/probe-pages/deep") "Deep"))
    (:div (:@ :hx-get "/probe-pages/fragment" :hx-trigger "load") "Fragment")
    (:p (:a (:@ :href "/probe-pages/moved") "Moved"))
    (:p (:a (:@ :href "/uitleg") "Uitleg"))
    (:p (:a (:@ :href "/probe-pages/odd/a b|{c}") "A path a browser encodes"))
    (:p (:a (:@ :href "/logout") "Log out") (:a (:@ :href "https://elsewhere.example/") "Away")
        (:a (:@ :href "#top") "Top") (:a (:@ :href "/ui") "Specimen"))
    (:ul ,@(loop for n from 1 to 5
                 collect `(:li (:a (:@ :href ,(format nil "/probe-pages/shape/~d" n)) ,n))))
    (:ul ,@(mapcar (lambda (customer)
                     `(:li (:a (:@ :href ,(format nil "/probe-pages/customer/~a"
                                                  (jget customer "id")))
                               ,(jget customer "name"))))
                   (probe-customers)))
    ,@(when (planted-p :broken-link) '((:p (:a (:@ :href "/probe-pages/missing") "Missing"))))
    ,@(when (planted-p :forbidden-link) '((:p (:a (:@ :href "/probe-admin") "Admin"))))
    ,@(when (planted-p :connect) '((:p (:a (:@ :href "/probe-pages/connect") "Connect"))))
    (:form (:@ :method "post" :action "/probe-pages/save" :id "probe-form")
           (:input (:@ :name "title" :value "Probe"))
           (:button (:@ :type "submit" :name "save" :value "1") "Save"))
    (:form (:@ :method "post" :action "/probe-pages/save" :id "probe-form-again")
           (:input (:@ :name "title" :value "Again"))
           (:button (:@ :type "submit" :name "save" :value "2") "Save"))
    (:form (:@ :method "post" :action "/probe-pages/after-save")
           (:button (:@ :type "submit") "Save and go on"))
    (:form (:@ :method "post" :action "/probe-pages/away") (:button (:@ :type "submit") "Away"))
    (:form (:@ :method "post" :action "/probe-pages/call") (:button (:@ :type "submit") "Call"))
    (:form (:@ :method "post" :action "https://elsewhere.example/hook")
           (:button (:@ :type "submit") "Elsewhere"))
    (:form (:@ :method "post" :action "/logout") (:button (:@ :type "submit") "Log out"))))

(defun probe-get (path)
  "The probe's answer to a GET of PATH, under /probe-pages."
  (cond
    ((null path)
     (if (and (planted-p :menu-403) (eq (actor-role *actor*) :employee))
         (values 403 "Probe pages" (list '(:p "Refused, though the policy admits you")))
         (values 200 "Probe pages" (probe-index))))
    ((equal path '("deep"))
     (when (or (planted-p :deep-500)
               (and (planted-p :role-500) (eq (actor-role *actor*) :viewer)))
       (probe-fault "deep"))
     (values 200 "Deep" (list '(:p "Deep"))))
    ((equal path '("fragment"))
     (when (and (planted-p :fragment-500) (tun.web:htmx-request-p))
       (probe-fault "fragment"))
     (values 200 :fragment (list '(:p "A part"))))
    ((equal path '("moved")) (values 303 "/probe-pages/target"))
    ((equal path '("target"))
     (when (planted-p :redirect-500) (probe-fault "target"))
     (values 200 "Target" (list '(:p "Target"))))
    ((equal path '("after"))
     (when (planted-p :post-redirect-500) (probe-fault "after a post"))
     (values 200 "After" (list '(:p "After"))))
    ((equal path '("connect"))
     ;; Straight to another host, past *HTTP-JSON-HANDLER*: 192.0.2.1 is an
     ;; address for documentation, which no host has.
     (drakma:http-request "http://192.0.2.1:9/pages" :connection-timeout 1)
     (values 200 "Connected" (list '(:p "Connected"))))
    ((and (member (first path) '("shape" "customer" "odd") :test #'string=) (rest path))
     (values 200 "One" (list `(:p ,(second path)))))
    (t (values 404 "Not found" (list '(:p "Not found"))))))

(defun probe-post (path)
  "The probe's answer to a post to PATH, under /probe-pages."
  (cond ((equal path '("save"))
         (when (planted-p :post-500) (probe-fault "save"))
         (values 303 "/probe-pages"))
        ((equal path '("after-save")) (values 303 "/probe-pages/after"))
        ((equal path '("away")) (values 303 "https://elsewhere.example/"))
        ((equal path '("call"))
         (setf *probe-outbound-answer*
               (handler-case (list :answered (tun:http-json-post "https://elsewhere.example/hook"
                                                                 (jobj "probe" t)))
                 (error (e) (list :refused (princ-to-string e)))))
         (values 200 "Called" (list '(:p "Called"))))
        (t (values 404 "Not found" (list '(:p "Not found"))))))

(tun.web:define-page probe-pages-page ("probe-pages" :title "Probe pages" :policy :viewer)
    (method path form query)
  (if (eq method :post) (probe-post path) (probe-get path)))

(tun.web:define-page probe-admin-page ("probe-admin" :title "Probe admin" :policy :admin
                                                     :navigation nil)
    (method path form query)
  (values 200 "Probe admin" (list '(:p "For admins"))))

(tun.web:define-page probe-uitleg-page ("uitleg" :title "Uitleg" :policy :viewer :navigation nil)
    (method path form query)
  (values 200 "Uitleg" (list '(:p "A page whose name starts as /ui's"))))

(tun.web:define-page probe-never-page ("probe-never" :title "Never" :navigation nil)
    (method path form query)
  (values 404 "Not here" (list '(:p "This page lives only under its prefix"))))

(tun.web:register-public-page
 "probe-public"
 (lambda (method path form session)
   (declare (ignore method path form session))
   (when (planted-p :public-500) (probe-fault "public"))
   (values 200 "Probe" (list '(:p "For anyone")))))

(defun probe-pages (&rest defects)
  "Open the probe pages with DEFECTS planted, as an employee, a viewer and
no actor, from fuzz-records; the report.  The defects are planted for
every thread: the test server's threads run the pages."
  (let ((before (sb-ext:symbol-global-value '*planted-defects*)))
    (setf (sb-ext:symbol-global-value '*planted-defects*) defects
          *probe-outbound-answer* nil)
    (unwind-protect
         (open-every-page :scenario (find-scenario "fuzz-records" :package "TUN.TESTS")
                          :actors '("viewer:fuzz")
                          :within '("probe-pages" "probe-admin" "uitleg" "probe-never"
                                    "probe-public"))
      (setf (sb-ext:symbol-global-value '*planted-defects*) before))))

(defun failures-at (report path &key actor)
  "The failures REPORT has at PATH, for ACTOR when it is given."
  (remove-if-not (lambda (failure)
                   (and (string= (page-failure-path failure) path)
                        (or (null actor) (string= (page-failure-actor failure) actor))))
                 (page-report-failures report)))

(defun tally-of (report actor)
  (find actor (page-report-tallies report) :key #'actor-tally-actor :test #'string=))

;;; ------------------------------------------------------------------
;;; What the page test finds

(test probe-pages-without-defects-pass
  (let ((report (probe-pages)))
    (is (null (page-report-failures report)) "~{~a~^~%~}"
        (mapcar #'page-failure-text (page-report-failures report)))
    (let ((paths (actor-tally-paths (tally-of report "employee:anna"))))
      (dolist (path '("/probe-pages/deep" "/probe-pages/fragment" "/probe-pages/moved"
                      "/probe-pages/target" "/uitleg" "/probe-pages/odd/a b|{c}"))
        (is (member path paths :test #'string=) "~a is opened" path))
      (dolist (path '("/logout" "/ui" "/login"))
        (is (not (member path paths :test #'string=)) "~a is left out" path)))
    (is (equal '("/probe-pages/save" "/probe-pages/after-save" "/probe-pages/away"
                 "/probe-pages/call")
               (actor-tally-forms (tally-of report "employee:anna")))
        "each form posted once, but those to another site and to /logout")
    (is (eq :refused (first *probe-outbound-answer*))
        "a post's call to another system is answered as unreachable in the server's thread: ~s"
        *probe-outbound-answer*)
    (is (search "Answered no actor with a page: /probe-never" (pages-summary report "probes"))
        "~a" (pages-summary report "probes"))))

(test a-page-failing-for-one-role-is-found
  (let ((report (probe-pages :role-500)))
    (let ((failures (failures-at report "/probe-pages/deep")))
      (is (= 1 (length failures)))
      (is (string= "viewer:fuzz" (page-failure-actor (first failures))))
      (is (eql 500 (page-failure-status (first failures))))
      (is (string= "/probe-pages" (page-failure-from (first failures)))
          "it names the page that led there")
      (is (search "The probe page failed: deep" (or (page-failure-fault (first failures)) ""))
          "the first line of the recorded fault: ~a" (page-failure-fault (first failures))))))

(test a-fragment-failing-only-for-htmx-is-found
  (let ((report (probe-pages :fragment-500)))
    (dolist (actor '("employee:anna" "viewer:fuzz"))
      (let ((failure (first (failures-at report "/probe-pages/fragment" :actor actor))))
        (is (eql 500 (and failure (page-failure-status failure)))
            "~a: requested as htmx requests it" actor)))))

(test a-redirect-to-a-failing-page-is-found
  (let ((failure (first (failures-at (probe-pages :redirect-500) "/probe-pages/target"
                                     :actor "employee:anna"))))
    (is (eql 500 (page-failure-status failure)))
    (is (string= "/probe-pages/moved" (page-failure-from failure)))))

(test a-link-its-reader-cannot-follow-is-found
  (let ((report (probe-pages :broken-link :forbidden-link)))
    (is (eql 404 (page-failure-status (first (failures-at report "/probe-pages/missing"
                                                          :actor "employee:anna")))))
    (is (eql 403 (page-failure-status (first (failures-at report "/probe-admin"
                                                          :actor "employee:anna"))))
        "a link to a page its actor may not open")
    (is (notany (lambda (failure) (eq :listed (page-failure-from failure)))
                (failures-at report "/probe-admin" :actor "employee:anna"))
        "a listed page's own refusal is not a failure")))

(test a-menu-page-refusing-a-role-it-admits-is-found
  (let ((failures (failures-at (probe-pages :menu-403) "/probe-pages" :actor "employee:anna")))
    (let ((listed (find :listed failures :key #'page-failure-from)))
      (is (eql 403 (and listed (page-failure-status listed))))
      (is (search "admits" (page-failure-problem listed))))
    (is (find-if #'stringp failures :key #'page-failure-from)
        "and the menu's link to it, on the pages that show the menu"))
  (is (null (failures-at (probe-pages) "/probe-never"))
      "a page outside the menu may answer 404 at its bare prefix"))

(test a-page-answering-whom-its-policy-refuses-is-found
  ;; Tun refuses a page to a role its policy does not admit before the page
  ;; runs, and refuses to start when another page shadows it, so no probe
  ;; page can answer otherwise: the expectations are checked themselves.
  (flet ((problem (page actor status &optional location)
           (funcall (tun.test-support::listed-expectation page actor) status location)))
    (let ((admin-page '(:kind :staff :path "/x" :policy :admin :navigation t))
          (outside '(:kind :staff :path "/y" :policy :employee :navigation nil)))
      (is (search "not 403" (problem admin-page "employee:kari" 200)))
      (is (null (problem admin-page "employee:kari" 403)))
      (is (search "a refusal" (problem admin-page "admin:kari" 403)))
      (is (null (problem outside "employee:kari" 404)) "outside the menu, any status below 500")
      (is (search "login" (problem admin-page nil 200)))
      (is (search "login" (problem admin-page nil 303 "/elsewhere")))
      (is (null (problem admin-page nil 303 "/login?next=%2Fx")))
      (is (null (problem admin-page nil 303 "http://127.0.0.1:4000/login?next=%2Fx")))
      (is (null (problem '(:kind :resource :path "/r") nil 303 "/login")))
      (is (search "login" (problem '(:kind :resource :path "/r") nil 200))))))

(test a-public-page-failing-with-no-actor-is-found
  (let ((failures (failures-at (probe-pages :public-500) "/probe-public" :actor "no actor")))
    (is (= 1 (length failures)))
    (is (eql 500 (page-failure-status (first failures))))))

(test a-failing-post-and-its-redirect-are-found
  (let ((report (probe-pages :post-500 :post-redirect-500)))
    (let ((post (first (failures-at report "/probe-pages/save" :actor "employee:anna"))))
      (is (equal "POST" (page-failure-method post)))
      (is (string= "/probe-pages" (page-failure-from post))))
    (let ((after (first (failures-at report "/probe-pages/after" :actor "employee:anna"))))
      (is (equal "GET" (page-failure-method after)))
      (is (string= "/probe-pages/after-save" (page-failure-from after))))))

(test a-page-reaching-another-host-fails
  (let ((report (probe-pages :connect)))
    (is (find "CONNECT" (page-report-failures report) :key #'page-failure-method :test #'string=)
        "~{~a~^~%~}" (mapcar #'page-failure-text (page-report-failures report)))
    (is (null (take-connection-attempts)) "the attempt is reported once, in the report")))

(test the-bounds-hold
  (let ((report (probe-pages)))
    (let ((paths (actor-tally-paths (tally-of report "employee:anna"))))
      (is (= 2 (count-if (lambda (path) (search "/probe-pages/shape/" path)) paths))
          "two paths of one shape"))
    (is (= 3 (actor-tally-left-out (tally-of report "employee:anna")))
        "three of the shape left out"))
  ;; The five listed pages are opened whatever the bound, and two more.
  (let ((report (let ((*paths-per-actor* 7)) (probe-pages))))
    (is (= 7 (actor-tally-opened (tally-of report "employee:anna"))))
    (is (search "left out by the bound" (pages-summary report "probes")))))

(defun ids-by-first-meeting (paths)
  "PATHS with each id in them replaced by the order it was first met in."
  (let ((ids (make-hash-table :test 'equal)))
    (mapcar (lambda (path)
              (cl-ppcre:regex-replace-all
               "[a-z]+_[0-9A-Za-z]+" path
               (lambda (id) (format nil "#~d" (or (gethash id ids)
                                                  (setf (gethash id ids) (hash-table-count ids)))))
               :simple-calls t))
            paths)))

(test two-runs-open-the-same-paths
  (flet ((opened ()
           (ids-by-first-meeting (actor-tally-paths (tally-of (probe-pages) "employee:anna")))))
    (let ((first (opened)))
      (is (some (lambda (path) (search "/probe-pages/customer/#" path)) first)
          "records' pages among them: ~s" first)
      (is (equal first (opened))))))

;;; ------------------------------------------------------------------
;;; Reading a page

(test a-form-is-read-as-a-browser-sends-it
  (let ((forms (tun.test-support::page-forms
                "<form method=\"post\" action=\"/x\" id=\"f\">
<input name=\"title\" value=\"A &amp; B\"><input type=\"checkbox\" name=\"on\" checked>
<input type=\"checkbox\" name=\"off\" value=\"1\"><input type=\"radio\" name=\"r\" value=\"a\">
<input type=\"radio\" name=\"r\" value=\"b\" checked><input type=\"file\" name=\"f\">
<select name=\"s1\"><option value=\"1\">One</option>
<option value=\"2\" selected>Two</option></select>
<select name=\"s2\"><option>First</option><option>Second</option></select>
<textarea name=\"t\">
Line</textarea><input name=\"gone\" value=\"x\" disabled>
<button type=\"button\" name=\"plain\">No</button><button name=\"go\" value=\"1\">Go</button>
<button name=\"other\" value=\"2\">Other</button></form>
<button form=\"f\" name=\"column\" value=\"done\">Done</button>
<form method=\"get\" action=\"/search\"><input name=\"q\"></form>
<form method=\"post\" enctype=\"multipart/form-data\"></form>")))
    (is (= 2 (length forms)) "a GET form is not posted")
    (let ((form (first forms)))
      (is (string= "/x" (tun.test-support::page-form-action form)))
      (is (equal '(("go" . "1") ("title" . "A & B") ("on" . "on") ("r" . "b") ("s1" . "2")
                   ("s2" . "First") ("t" . "Line"))
                 (tun.test-support::page-form-fields form))
          "~s" (tun.test-support::page-form-fields form)))
    (is (tun.test-support::page-form-multipart (second forms)))
    (is (string= "" (tun.test-support::page-form-action (second forms))))))

(test a-control-outside-its-form-counts
  (let ((form (first (tun.test-support::page-forms
                      "<form method=\"post\" action=\"/move\" id=\"m\">
<input type=\"hidden\" name=\"id\" value=\"7\"></form>
<button form=\"m\" name=\"column\" value=\"done\">Done</button>"))))
    (is (equal '(("column" . "done") ("id" . "7")) (tun.test-support::page-form-fields form)))))

(test links-are-read-as-htmx-requests-them
  (is (equal '(("/a" . nil) ("/b" . "partial") ("/c" . "full") ("/d" . "full") ("/e" . "partial"))
             (tun.test-support::page-links
              "<a href=\"/a\">a</a><div hx-get=\"/b\"></div>
<div hx-get=\"/c\" hx-target=\"body\"></div>
<div hx-get=\"/d\" hx-select=\"#x\"></div><span data-hx-get=\"/e\"></span>"))))

(test paths-on-the-site-and-their-shapes
  (let ((origin "http://127.0.0.1:4000"))
    (is (string= "/saker/12?q=1" (tun.test-support::site-path "/saker/12?q=1#top" "/" origin)))
    (is (string= "/saker" (tun.test-support::site-path "http://127.0.0.1:4000/saker" "/" origin)))
    (is (string= "/saker/ny" (tun.test-support::site-path "ny" "/saker/12" origin)))
    (is (string= "/saker?side=2" (tun.test-support::site-path "?side=2" "/saker" origin)))
    (dolist (url '("#top" "https://example.com/" "//example.com/x" "mailto:a@b.no" "/login"
                   "/logout" "/auth/google" "/setup/x" "/assets/a.css" "/ui" "/ui/button"))
      (is (null (tun.test-support::site-path url "/" origin)) "~a is left out" url))
    (is (string= "/uitleg" (tun.test-support::site-path "/uitleg" "/" origin))))
  (is (string= "/saker/:id/:id?page&q"
               (tun.test-support::path-shape "/saker/12/itm_ABC?q=a&page=2")))
  (is (string= "/saker/ny" (tun.test-support::path-shape "/saker/ny"))))

(test a-path-is-sent-as-a-browser-sends-it
  (is (string= "/s%C3%B8k/a%20b%7C%7Bc%7D?q=%C3%A6&x=1"
               (tun.test-support::browser-encoded "/søk/a b|{c}?q=æ&x=1"))))

(test a-request-that-cannot-be-sent-is-a-failure
  ;; A port that is no number makes an address the HTTP client cannot read.
  (let ((crawl (tun.test-support::make-page-crawl nil "no-port" nil nil nil)))
    (multiple-value-bind (status html location fault)
        (tun.test-support::crawl-request crawl :get "/saker")
      (is (eq :unsent status))
      (is (null html))
      (is (null location))
      (is (stringp fault) "it says why"))))

(test a-file-is-fetched-and-not-read
  (with-test-server (port)
    (multiple-value-bind (status html)
        (tun.test-support::page-request port "employee:anna" :get (tun.ui:stylesheet-path))
      (is (eql 200 status))
      (is (null html) "an answer that is not text/html is not read"))))
