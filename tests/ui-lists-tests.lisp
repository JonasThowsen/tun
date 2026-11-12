;;;; tests/ui-lists-tests.lisp -- a table on a phone: every column kept in a
;;;; box that scrolls, one panel of dense rows, the lead of two lines, a row
;;;; that leads somewhere as one target pressed at once; the rows in the
;;;; page's first answer; a page title's long word hyphenated (spec/ui.md
;;;; 2.1, 6 table, 6 page-header, 8 «Lists», 10).

(in-package #:tun.tests)

(def-suite ui-lists :in core)
(in-suite ui-lists)

(defun table-declaration (property value &key selector media)
  "The declaration of PROPERTY with VALUE in the table's CSS, under a selector
holding SELECTOR and an at-rule holding MEDIA when they are given, or NIL."
  (find-if (lambda (d)
             (and (string= property (declaration-property d))
                  (string= value (declaration-value d))
                  (or (null selector) (search selector (selectors-text d)))
                  (or (null media) (some (lambda (m) (search media m)) (declaration-media d)))))
           (component-declarations "table")))

(defparameter +phone+ "@container tun-table (width < 36rem)"
  "The at-rule of a table on a phone.")

;;; ------------------------------------------------------------------
;;; No cards (criterion 1)

(test a-cell-holds-its-content-and-no-label
  (let ((html (order-table :row-href (lambda (row) (format nil "/ordre/~a" (first row))))))
    (is (not (search "tun-table-label" html)) "no column's name in a cell")
    (is (not (search "tun-icon" (subseq html (search "<tbody>" html))))
        "no chevron after the row's link")
    (is (search (concatenate 'string "<td><span class=\"tun-table-lead\">"
                             "<span class=\"tun-table-value\">"
                             "<a class=\"tun-table-row-link\" href=\"/ordre/10482\">10482</a>"
                             "</span></span></td>"
                             "<td><span class=\"tun-table-value\">Fjordkaffe AS</span></td>")
                html)
        "the lead holds the row's one link, the next cell its value alone")
    (is (search "<div class=\"tun-table\"><div class=\"tun-table-box\"><table>" html)
        "the rows stand in a box of their own")))

(test no-rule-makes-a-row-a-card
  (dolist (d (component-declarations "table"))
    (when (string= "display" (declaration-property d))
      (is (not (and (cl-ppcre:scan "(^|[ >,(])(table|thead|tbody|tfoot|tr|td|th)([ :.,)\\[]|$)"
                                   (selectors-text d))
                    (member (declaration-value d) '("block" "flex" "grid") :test #'string=)))
          "a part of the table is laid out as a card: ~a" (declaration-where d)))))

;;; ------------------------------------------------------------------
;;; The box that scrolls, the panel, the lead (criteria 2, 3, 5)

(test the-rows-scroll-in-their-own-box-with-edge-shadows
  (is (table-declaration "overflow-x" "auto" :selector ".tun-table-box"))
  (let ((background (find-if (lambda (d) (and (string= "background" (declaration-property d))
                                              (search ".tun-table-box" (selectors-text d))))
                             (component-declarations "table"))))
    (is (not (null background)))
    (when background
      (let ((value (declaration-value background)))
        (is (= 2 (count-matches "no-repeat local" value)) "two covers scroll with the rows")
        (is (= 2 (count-matches "no-repeat scroll" value)) "two shadows stay at the edges")
        (is (= 2 (count-matches "var\\(--card\\) 30%" value)) "the covers in the box's ground"))))
  (is (table-declaration "background-color" "var(--card)" :selector ".tun-table-box")))

(test a-phone-shows-one-panel
  (is (table-declaration "border" "1px solid var(--border)" :selector ".tun-table-box"
                                                            :media +phone+))
  (is (table-declaration "border-radius" "var(--radius-lg)" :selector ".tun-table-box"
                                                            :media +phone+))
  (is (table-declaration "box-shadow" "var(--shadow-panel)" :selector ".tun-table-box"
                                                            :media +phone+))
  (is (not (find-if (lambda (d) (and (string= "border" (declaration-property d))
                                     (search ".tun-table-box" (selectors-text d))
                                     (null (declaration-media d))))
                    (component-declarations "table")))
      "no edge from 36rem"))

(test the-lead-keeps-to-two-lines-and-half-the-box-on-a-phone
  (dolist (pair '(("-webkit-line-clamp" "2") ("line-clamp" "2") ("overflow" "hidden")
                  ("width" "max-content") ("max-width" "min(16rem, 50cqi)") ("white-space" "normal")
                  ("overflow-wrap" "anywhere")))
    (is (table-declaration (first pair) (second pair) :selector ".tun-table-lead"
                                                      :media +phone+)
        "the lead has ~a: ~a" (first pair) (second pair))))

;;; ------------------------------------------------------------------
;;; The old options (criterion 6)

(test the-old-options-are-taken
  (let ((html (tun.html:render-html
               (tun.ui:table (:caption "Ordre" :caption-hidden t :id "ordre"
                              :columns '(("Ordre" :width :min :sort "nr" :sorted :asc)
                                         ("Kunde" :wrap t) ("Dato" :narrow nil)
                                         ("Beløp" :align :end))
                              :rows '(("1" "Kari" "12.10.2026" "4,00"))
                              :row-href '("/ordre/1") :sort-href "/ordre?sort=~a&retning=~a"
                              :footer '("Sum" nil nil "4,00") :empty "Ingen."
                              :attributes '(:data-test "ja"))))))
    (is (search "<div class=\"tun-table\" id=\"ordre\" data-test=\"ja\">" html))
    (is (search "data-narrow=\"false\"" html))
    (is (search "<tfoot>" html)))
  (is (table-declaration "display" "none" :selector "[data-narrow='false']" :media +phone+)
      "a column a phone can do without is left out there")
  (signals error (tun.ui:table (:columns '(("Ordre" :phone :hidden)) :rows '()))
           "an option a column never took"))

;;; ------------------------------------------------------------------
;;; A row that leads somewhere (criteria 7, 8)

(test the-row-is-pressed-only-while-its-link-is-and-at-once
  (let ((pressed (remove-if-not (lambda (d) (search ":active" (selectors-text d)))
                                (component-declarations "table"))))
    (is (find-if (lambda (d) (and (search "tr[data-link]:has(.tun-table-row-link:active)"
                                          (selectors-text d))
                                  (string= "background-color" (declaration-property d))
                                  (string= "var(--pressed)" (declaration-value d))))
                 pressed))
    (is (find-if (lambda (d) (and (search "tr[data-link]:has(" (selectors-text d))
                                  (string= "transition-duration" (declaration-property d))
                                  (string= "0s" (declaration-value d))))
                 pressed))
    (is (not (find-if (lambda (d) (cl-ppcre:scan "tr(\\[data-link\\])?:active" (selectors-text d)))
                      pressed))
        "a row is not pressed by a control in it"))
  (is (table-declaration "background-color" "var(--accent)" :selector ":hover"
                                                             :media "(hover: hover)"))
  (is (table-declaration "box-shadow" "var(--focus-ring-inset)"
                         :selector ":focus-visible::after"))
  (is (table-declaration "padding-block" "calc(var(--spacing) * 3)" :selector "tr[data-link] td"
                                                                    :media "(pointer: coarse)")
      "a finger's row is 2.75rem high"))

;;; ------------------------------------------------------------------
;;; Empty, and the rows with the page (criteria 11, 12, 15)

(test the-empty-row-says-it-in-sight
  (is (table-declaration "position" "sticky" :selector ".tun-table-empty-text"))
  (is (table-declaration "max-width" "calc(100cqi - var(--spacing) * 4)"
                         :selector ".tun-table-empty-text")))

(test the-generated-list-has-its-rows-in-the-first-answer
  (with-test-server (port)
    (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
    (call-ok "customers_create" "employee:anna" "name" "Ola Hansen" "email" "ola@example.no")
    (multiple-value-bind (status page)
        (web-request port "/customers" :jar (web-login port "employee:anna"))
      (is (= 200 status))
      (is (search "Kari Nordmann" page))
      (is (search "Ola Hansen" page))
      (is (= 2 (count-matches "class=\"tun-table-lead\"" page)) "a row per customer")
      (is (not (cl-ppcre:scan "hx-trigger=\"[^\"]*(load|revealed)" page))
          "no part loads after the page")
      (is (not (search "tun-skeleton" page)) "no stand-in")
      (is (not (search "tun-pagination" page)) "and no second way to more"))))

;;; ------------------------------------------------------------------
;;; A page title's long word (criterion 14)

(test a-page-titles-long-word-is-hyphenated
  (let ((declarations (component-declarations "page-header")))
    (flet ((title-has (property value)
             (find-if (lambda (d) (and (search ".tun-page-header-title" (selectors-text d))
                                       (string= property (declaration-property d))
                                       (string= value (declaration-value d))))
                      declarations)))
      (is (title-has "hyphens" "auto"))
      (is (title-has "overflow-wrap" "anywhere") "breaking anywhere where no hyphen is"))))
