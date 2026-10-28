;;;; tests/ui-tests.lisp -- the design system: components, the stylesheet
;;;; and script, and the specimen (spec/ui.md 10).

(in-package #:tun.tests)

(def-suite ui :in core)
(in-suite ui)

(defun component-label (component)
  (string-downcase (symbol-name (tun.ui:component-name component))))

;;; ------------------------------------------------------------------
;;; Every component

(test every-component-is-documented-and-has-examples
  (dolist (component (tun.ui:all-components))
    (let ((name (component-label component)))
      (is (plusp (length (tun.ui:component-doc component))) "~a has no :doc" name)
      (is (plusp (length (tun.ui:component-source component))) "~a has no :source" name)
      (is (plusp (length (tun.ui:component-group component))) "~a has no :group" name)
      (is (tun.ui:component-examples component) "~a has no examples" name))))

(test every-example-renders-with-only-allowed-markup
  (dolist (component (tun.ui:all-components))
    (loop for (title nil thunk) in (tun.ui:component-examples component)
          do (let ((markup (funcall thunk)))
               (is (string= (tun.html:render-html markup)
                            (tun.html:render-html (tun.html:untrusted markup)))
                   "~a, ~s: the renderer strips some of its markup from extension output"
                   (component-label component) title)))))

(test every-root-carries-its-class
  (dolist (component (tun.ui:all-components))
    (loop for (title nil thunk) in (tun.ui:component-examples component)
          do (is (search (format nil "class=\"~a" (tun.ui:root-class
                                                   (tun.ui:component-name component)))
                         (tun.html:render-html (funcall thunk)))
                 "~a, ~s: no element has the class ~a" (component-label component) title
                 (tun.ui:root-class (tun.ui:component-name component))))))

(test component-css-is-scoped
  (flet ((problem (css) (tun.ui:scoped-css-problem css "tun-x")))
    (is (null (problem ".tun-x { color: red; & .tun-x-part { color: blue; } }
                        @media (min-width: 40rem) { .tun-x[data-size='lg'] { padding: 0; } }
                        @keyframes tun-x-spin { to { rotate: 1turn; } }
                        .tun-x, .tun-x::after { content: '{'; }")))
    (is (search "dialog" (problem "dialog { color: red; }")))
    (is (problem ".tun-xy { color: red; }") "a longer class is another component")
    (is (problem ".tun-x { } .other { }"))
    (is (problem "@media (hover: hover) { .other { } }") "media queries are looked into")
    (is (problem "@import url(x.css);"))
    (is (problem "@keyframes spin { }"))
    (is (problem "/* .tun-x */ :root { --x: 1; }") "comments do not count")))

(test a-component-clause-takes-one-value
  (flet ((expand (css-clause)
           (macroexpand-1 `(tun.ui:define-component x ((&key))
                             (:group "Data") (:doc "D") (:source "S") ,css-clause
                             (:examples ("E" (x ())))
                             '(:div)))))
    (is (consp (expand '(:css ".tun-x { color: red; }"))))
    (signals error (expand '(:css ".tun-x[data-width=" narrow "] { }"))
             "a double quote inside the CSS ended the string")))

(test icons-and-labels
  (is (member :check (tun.ui:icon-names)))
  (signals error (tun.ui:icon (:name :no-such-icon)))
  (signals error (tun.ui:button (:size :icon) (tun.ui:icon (:name :x)))
           "a button that shows only an icon needs a label")
  (is (search "aria-hidden=\"true\"" (tun.html:render-html (tun.ui:icon (:name :x)))))
  (is (search "aria-label=\"Lukk\""
              (tun.html:render-html (tun.ui:icon (:name :x :label "Lukk")))))
  (is (equal (tun.html:render-html (tun.ui:button (:variant :outline) "Avbryt"))
             (tun.html:render-html (apply #'tun.ui:button* '((:variant :outline) "Avbryt"))))
      "the macro and the function make the same markup"))

;;; ------------------------------------------------------------------
;;; Every example in Norwegian and in the pseudo-language (spec/i18n.md 3.7)

(defun example-strings (source)
  "The string literals of SOURCE, an example's forms as the specimen shows
them, read with the Lisp reader (and nothing evaluated), backquoted forms
included."
  (let ((strings '()))
    (labels ((walk (form)
               (cond ((stringp form) (push form strings))
                     ((sb-int:comma-p form) (walk (sb-int:comma-expr form)))
                     ((consp form) (walk (car form)) (walk (cdr form))))))
      (let ((*read-eval* nil)
            (*package* (find-package '#:tun.ui)))
        (with-input-from-string (in source)
          (loop for form = (read in nil in)
                until (eq form in)
                do (walk form)))))
    strings))

(defun shown-parts (string)
  "What a component shows of STRING, a text it was given, besides the whole:
the text without the spaces around it, as a page's text is read, a
shortcut's keys (Ctrl+K), a name's initials (KN) and its first letter."
  (let ((words (cl-ppcre:split "\\s+" (string-trim '(#\Space #\Newline) string))))
    (append (list (string-trim '(#\Space #\Newline) string))
            (uiop:split-string string :separator "+")
            (when words
              (list (subseq (first words) 0 (min 1 (length (first words))))
                    (string-upcase
                     (format nil "~a~a" (subseq (first words) 0 (min 1 (length (first words))))
                             (let ((last (first (last words))))
                               (subseq last 0 (min 1 (length last)))))))))))

(defun example-allowed-texts (component source)
  "The texts an example of COMPONENT whose forms are SOURCE may show without
a lookup: its own strings and what a component shows of them, and for the
icon the icons' names, which its specimen shows."
  (let ((strings (example-strings source)))
    (append strings (mapcan #'shown-parts strings)
            (when (eq (tun.ui:component-name component) 'tun.ui:icon)
              (mapcar (lambda (name) (string-downcase (symbol-name name))) (tun.ui:icon-names))))))

(defun example-unlooked-up-texts (component source thunk)
  "The texts the example of COMPONENT with forms SOURCE and markup from THUNK
writes in the pseudo-language without looking them up."
  (unlooked-up-texts (with-language ("qps") (tun.html:render-html (funcall thunk)))
                     :allowed (example-allowed-texts component source)))

;; A component made for the test below: it writes one text without TR.  It
;; is the specimen's own kind (internal), so no other test lists it.
(tun.ui:define-component unlooked-up-notice ((&key name))
  (:internal t)
  (:examples ("A notice" (unlooked-up-notice (:name "Kari Nordmann"))))
  `(:p (:span ,name) (:span ,(tr "Close")) (:span "Saved")))

(test every-example-has-norwegian-for-its-component-copy
  (dolist (component (tun.ui:all-components))
    (loop for (title nil thunk) in (tun.ui:component-examples component)
          do (let ((missing '()))
               (let ((*missing-translation-hook*
                      (lambda (language source context)
                        (declare (ignore language))
                        (pushnew (list source context) missing :test #'equal))))
                 (with-language ("nb") (tun.html:render-html (funcall thunk))))
               (is (null missing) "~a, ~s: no Norwegian for ~s"
                   (component-label component) title missing)))))

(test every-example-looks-up-the-texts-it-writes
  (dolist (component (tun.ui:all-components))
    (loop for (title source thunk) in (tun.ui:component-examples component)
          do (let ((unlooked (example-unlooked-up-texts component source thunk)))
               (is (null unlooked) "~a, ~s writes texts it did not look up: ~s"
                   (component-label component) title unlooked)))))

(test a-text-written-without-a-lookup-is-found
  (let ((component (tun.ui:find-component "unlooked-up-notice")))
    (destructuring-bind (title source thunk &rest more)
        (first (tun.ui:component-examples component))
      (declare (ignore title more))
      (is (equal '("Saved") (example-unlooked-up-texts component source thunk))
          "the text without TR is found, the looked-up one and the example's own are not"))))

;;; ------------------------------------------------------------------
;;; htmx in extension output (spec/ui.md 5)

(test extension-output-keeps-htmx-that-cannot-run-code
  (flet ((shown (&rest attributes)
           (tun.html:render-html (tun.html:untrusted `(:form (:@ ,@attributes) "x")))))
    (let ((html (shown :hx-post "/saker/flytt" :hx-target "closest .tun-board"
                       :hx-swap "outerHTML" :hx-trigger "change" :data-hx-get "/saker"
                       :hx-target\:inherited "#saker")))
      (dolist (kept '("hx-post=\"/saker/flytt\"" "hx-target=\"closest .tun-board\""
                      "hx-swap=\"outerHTML\"" "hx-trigger=\"change\"" "data-hx-get=\"/saker\""
                      "hx-target:inherited=\"#saker\""))
        (is (search kept html) "~a is kept" kept)))
    (dolist (refused '((:hx-on\:click "alert(1)") (:data-hx-on\:click "alert(1)")
                       (:hx-on "click -> alert(1)") (:hx-on\:\:before\:request "alert(1)")
                       (:hx-headers "{\"X\": \"1\"}") (:hx-headers\:inherited "{}")
                       (:hx-config "action:/x") (:hx-status\:4xx "swap:none")
                       (:hx-target\:sneaky "#x") (:hx-get "javascript:alert(1)")
                       (:data-hx-post "javascript:alert(1)") (:hx-get\:inherited "javascript:x")
                       (:hx-post "//evil.example/x")))
      (is (string= "<form>x</form>" (apply #'shown refused)) "~a is left out" (first refused)))))

;;; ------------------------------------------------------------------
;;; The stylesheet, the script and the pages

(test the-stylesheet-and-script-are-served-by-their-hash
  (with-test-server (port)
    (multiple-value-bind (status body headers) (web-request port (tun.ui:stylesheet-path))
      (is (= 200 status))
      (is (eql 0 (search "@layer reset, tokens, base, components, client;" body)))
      (is (search ".tun-button" body))
      (is (string= "public, max-age=31536000, immutable" (cdr (assoc :cache-control headers))))
      (is (search "text/css" (cdr (assoc :content-type headers)))))
    (multiple-value-bind (status body headers) (web-request port (tun.ui:script-path))
      (is (= 200 status))
      (is (search "data-tun-theme" body))
      (is (search "text/javascript" (cdr (assoc :content-type headers)))))
    (multiple-value-bind (status body headers) (web-request port "/assets/tun-000000000000.css")
      (is (= 200 status) "an older page still gets the styles")
      (is (search ".tun-button" body))
      (is (string= "no-store" (cdr (assoc :cache-control headers)))))
    (is (= 404 (web-request port "/assets/other.css")))))

(test pages-have-the-viewport-and-the-assets
  (with-test-server (port)
    (let ((body (nth-value 1 (web-request port "/login"))))
      (is (search "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">" body))
      (is (search (tun.ui:stylesheet-path) body))
      (is (search (tun.ui:script-path) body)))))

(test the-specimen-shows-every-component
  (with-test-server (port)
    (multiple-value-bind (status body) (web-request port "/ui")
      (is (= 200 status))
      (is (search "name=\"viewport\"" body))
      (is (search "<html lang=\"en\">" body) "in the test app's language")
      (dolist (component (tun.ui:all-components))
        (is (search (format nil "id=\"~a\"" (component-label component)) body)
            "the specimen lacks ~a" (component-label component))))
    (is (= 200 (web-request port "/ui/button")))
    (is (= 404 (web-request port "/ui/specimen")) "the specimen's own styles are not a component")
    (is (= 404 (web-request port "/ui/no-such-component")))
    (is (= 404 (web-request port "/ui/button/more"))))
  (let ((html (with-language ("nb")
                (tun.ui:specimen-html :component (tun.ui:find-component "pagination")))))
    (is (search "<html lang=\"nb\">" html) "the page says the language its examples are in")
    (is (search "Sidenavigering" html) "and they are")
    (is (search "Source: " html) "while its own chrome stays English")))

(test the-specimen-is-written-as-standalone-files
  (let ((directory (uiop:ensure-directory-pathname
                    (merge-pathnames (format nil "tun-ui-~36r/" (random (expt 36 8)))
                                     (uiop:temporary-directory)))))
    (unwind-protect
         (let ((files (tun.ui:write-specimen directory)))
           (is (= (1+ (length (tun.ui:all-components))) (length files)))
           (let ((index (uiop:read-file-string (first files))))
             (is (search "<style>@layer reset" index) "the stylesheet is inline")
             (is (search "href=\"button.html\"" index) "links lead to the other files")
             (is (not (search "/assets/" index)))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))
