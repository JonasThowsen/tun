;;;; tests/ui-nits-tests.lisp -- five small things the first client found on
;;;; the component library: a summary list's long label, a search result
;;;; that shows why it was found, a section's live facts, a muted line in
;;;; the page's flow, and the specimen's theme switch (spec/ui.md 6, 6.4, 7,
;;;; 10).

(in-package #:tun.tests)

(def-suite ui-nits :in core)
(in-suite ui-nits)

;;; ------------------------------------------------------------------
;;; A summary list's label (criterion 1)

(test a-labels-column-is-fixed-and-a-long-label-breaks
  (let ((css (component-css-text 'tun.ui:summary-list)))
    (is (search "grid-template-columns: min(10rem, calc((100% - var(--spacing) * 4) / 2)) minmax(0, 1fr);"
                css)
        "10rem, or half the row after the gap, the same in every row")
    (is (search "column-gap: calc(var(--spacing) * 4);" css) "the gap the column reckons with")
    (is (cl-ppcre:scan "\\.tun-summary-list-key \\{[^}]*min-width: 0;[^}]*hyphens: auto;[^}]*overflow-wrap: break-word;"
                       css)
        "a label longer than its column breaks, with a hyphen where the language has one"))
  (let ((html (tun.html:render-html
               (tun.ui:summary-list (:attributes '(:lang "nb")
                                     :rows '(("Organisasjonsnummer" "912 345 678")))))))
    (is (search "<dl class=\"tun-summary-list\" lang=\"nb\">" html)
        "a list may carry its own language for the hyphens")))

;;; ------------------------------------------------------------------
;;; Why a result was found (criterion 2)

(defun results-html (query &rest items)
  (tun.html:render-html (tun.ui:search-results (:query query :items items))))

(test a-result-found-by-its-line-is-marked-there
  (let ((html (results-html "ex" '(:kind "customer" :label "Customer" :icon :users
                                    :title "Fjord Events" :meta ("hello@fjord.example")
                                    :href "/customers/c1"))))
    (is (search "Customer · hello@fjord.<mark>ex</mark>ample" html)
        "the word is marked in the meta line, as in a title"))
  (let ((html (results-html "nordvik" '(:kind "customer" :label "Customer" :icon :users
                                         :title "Nordvik Bakery Ltd"
                                         :meta ("post@nordvik.example")
                                         :href "/customers/c1"))))
    (is (search "<mark>Nordvik</mark> Bakery Ltd" html))
    (is (search "Customer · post@nordvik.example" html)
        "a result whose title is marked keeps its line unmarked"))
  (let ((html (results-html "41234567" '(:kind "customer" :label "Customer" :icon :users
                                          :title "Bjørn Åsen" :meta ("412 34 567")
                                          :href "/customers/c2"))))
    (is (search "Customer · <mark>412 34 567</mark>" html)
        "an identifier is marked over the characters it covers"))
  (let ((html (results-html "storgata" '(:kind "order" :label "Order" :icon :shopping-cart
                                          :title "Fjord Events" :matched "Storgata 12"
                                          :meta ("Confirmed") :href "/orders/o1"))))
    (is (search "Order · <mark>Storgata</mark> 12 · Confirmed" html)
        "what it was found by follows the kind's word, marked")))

(test identifiers-are-marked-only-as-the-rule-finds-them
  (is (equal '((0 . 10)) (search-mark-ranges (q "41234567") "412 34 567" :identifier t)))
  (is (equal '((0 . 3) (4 . 6)) (search-mark-ranges (q "412 34") "412 34 567" :identifier t))
      "by its words first")
  (is (equal '((1 . 5)) (search-mark-ranges (q "4123") "+41234567" :identifier t))
      "a number's start from three characters, the sign left out")
  (is (null (search-mark-ranges (q "41234567") "412 34 567")) "not without :identifier")
  (is (null (search-mark-ranges (q "234") "412 34 567" :identifier t)) "not inside it"))

(test the-excerpt-starts-at-the-word-of-the-match
  (is (string= "Storgata 12" (search-excerpt (q "storgata") "Storgata 12")))
  (let* ((long (format nil "~{~a~^ ~}" (loop repeat 20 collect "word")))
         (text (format nil "~a Exhibition hall ~a" long long))
         (excerpt (search-excerpt (q "exhib") text)))
    (is (string= "…Exhibition hall " (subseq excerpt 0 17)) "from the word, «…» before it")
    (is (= 82 (length excerpt)) "80 characters and the two «…»")
    (is (string= "…" (subseq excerpt 81)) "«…» after it when it is cut")
    (is (string= (concatenate 'string (subseq text 0 80) "…")
                 (search-excerpt (q "word") text))
        "no «…» before a match at the start")))

(test search-entity-says-what-a-result-was-found-by
  (with-test-app ()
    (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "post@nordmann.example"
             "phone" "412 34 567")
    (flet ((matched (text)
             (map 'list (lambda (item) (jget item "matched"))
                  (jget (call-ok "search" "employee:anna" "query" text
                                 "kinds" (jarr '("customer")))
                        "items"))))
      (is (equal '(:null) (matched "kari")) "none when its title shows the match")
      (is (equal '(:null) (matched "nordmann.ex")) "none when its meta shows it")
      (is (equal '(:null) (matched "41234567"))
          "none when its meta shows it as an identifier, written otherwise"))
    (let ((result (with-application (*app*)
                    (as-actor ("system" :write)
                              (first (search-entity (make-search-query "storgata")
                                                    'tun.customers:customer
                                                    :kind "customer" :title (constantly "Kari")
                                                    :texts (constantly '("Storgata 12"))
                                                    :meta (constantly '("Customer since 2021"))
                                                    :href (constantly "/customers/x")))))))
      (is (equal "Storgata 12" (and result (search-result-matched result)))
          "a text the line does not show is what it was found by"))))

(test a-result-made-as-in-2-31-is-shown-as-before
  (let ((result (make-search-result :kind "thing" :label "Thing" :icon :file :title "Kari"
                                    :meta '("kari@example.no") :href "/x" :score 10)))
    (is (null (search-result-matched result)))
    (is (equal '("kari@example.no") (search-result-meta result)))))

(test the-page-the-fragment-and-the-tool-agree-on-why
  (with-test-server (port)
    (let ((fjord (jget (call-ok "customers_create" "employee:anna" "name" "Fjord Events"
                                "email" "hello@fjord.example")
                       "id"))
          (product (jget (call-ok "products_create" "employee:anna" "name" "Telt" "kind" "rental"
                                  "unit" "stk" "unit_price_minor" 1000 "stock_tracked" nil
                                  "units_owned" 2)
                         "id")))
      (call-ok "orders_create" "employee:anna" "customer_id" fjord "event_date" "2026-12-12"
               "delivery_address" "Storgata 12, 0155 Oslo"
               "lines" (jarr (list (jobj "product_id" product "quantity" 1))))
      (let* ((jar (web-login port "employee:anna"))
             (items (coerce (jget (call-ok "search" "employee:anna" "query" "storgata") "items")
                            'list))
             (page (nth-value 1 (web-request port "/search?q=storgata" :jar jar)))
             (fragment (nth-value 1 (web-request port "/search?q=storgata" :jar jar
                                                 :headers '(("HX-Request" . "true")
                                                            ("HX-Request-Type" . "partial"))))))
        (is (equal '("order") (mapcar (lambda (item) (jget item "kind")) items)))
        (let ((order (first items)))
          (is (equal "Storgata 12, 0155 Oslo" (jget order "matched")))
          (dolist (key '("kind" "kind_label" "icon" "title" "meta" "href" "score" "id"))
            (is (not (null (jget order key))) "the item keeps ~a" key)))
        (dolist (html (list page fragment))
          (is (search "Order · <mark>Storgata</mark> 12, 0155 Oslo · " html)
              "the page and the fragment show it marked")))
      (let ((items (coerce (jget (call-ok "search" "employee:anna" "query" "fjord.ex") "items")
                           'list)))
        (is (eq :null (jget (first items) "matched")) "the meta shows it: no matched")))))

;;; ------------------------------------------------------------------
;;; A section's live facts (criterion 3)

(test a-sections-meta-is-a-row-of-live-facts-under-its-heading
  (let ((html (tun.html:render-html
               (tun.ui:section (:title "Linjer"
                                :meta (list "3 linjer" (tun.ui:badge (:variant :info) "Hos kunden"))
                                :actions (list (tun.ui:button () "Legg til")))
                 '(:p "…")))))
    (is (search "<h2 class=\"tun-section-title\">Linjer</h2><div class=\"tun-section-meta\">3 linjer<span class=\"tun-badge\""
                html)
        "under the heading, in the section's text")
    (is (before-p html "tun-section-meta" "tun-section-actions") "before the actions"))
  (is (search "<div class=\"tun-section-meta\">3 linjer</div>"
              (tun.html:render-html (tun.ui:section (:title "Linjer" :meta "3 linjer"))))
      "one fact alone")
  (is (not (search "tun-section-meta"
                   (tun.html:render-html (tun.ui:section (:title "Linjer" :meta '(nil)))))))
  (let ((css (component-css-text 'tun.ui:section))
        (header (component-css-text 'tun.ui:page-header)))
    (flet ((block-of (text name)
             (let ((start (search (format nil "& .~a {" name) text)))
               (subseq text (search "{" text :start2 start) (1+ (search "}" text :start2 start))))))
      (is (string= (block-of header "tun-page-header-meta") (block-of css "tun-section-meta"))
          "in the header's look"))))

;;; ------------------------------------------------------------------
;;; A muted line (criterion 4)

(test a-note-is-a-short-muted-line-in-the-flow
  (is (string= "<p class=\"tun-note\">Svaret går til Nordvik Bakeri AS.</p>"
               (tun.html:render-html (tun.ui:note () "Svaret går til Nordvik Bakeri AS."))))
  (let ((css (component-css-text 'tun.ui:note)))
    (is (search "color: var(--muted-foreground);" css) "the muted colour itself, nothing lighter")
    (is (search "font-size: var(--text-sm);" css))
    (is (search "margin: 0;" css) "no margin of its own")
    (is (search "overflow-wrap: break-word;" css)))
  (is (eq (find-symbol "NOTE" '#:tun.ui) 'tun.ui:note)))

;;; ------------------------------------------------------------------
;;; The specimen's theme switch (criterion 5)

(test the-specimens-theme-switch-follows-its-title
  (is (cl-ppcre:scan "\\.tun-specimen-header \\{[^}]*justify-content: flex-start;"
                     (tun.ui:stylesheet)))
  (let ((html (tun.ui:specimen-html :component (tun.ui:find-component 'tun.ui:note))))
    (is (before-p html "tun-specimen-title" "tun-specimen-themes"))))
