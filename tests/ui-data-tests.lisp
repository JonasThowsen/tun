;;;; tests/ui-data-tests.lisp -- the data group of the design system: what
;;;; its components promise a screen reader and a phone (spec/ui.md 6).

(in-package #:tun.tests)

(def-suite ui-data :in core)
(in-suite ui-data)

(defun count-matches (regex string)
  (length (cl-ppcre:all-matches-as-strings regex string)))

(defun tag-with-p (html &rest attributes)
  "True when one start tag in HTML has every one of ATTRIBUTES, strings such as
aria-current=\"page\", in any order."
  (some (lambda (tag) (every (lambda (attribute) (search attribute tag)) attributes))
        (cl-ppcre:all-matches-as-strings "<[a-z]+ [^>]*>" html)))

(defun order-table (&rest options)
  (tun.html:render-html
   (tun.ui:table* (append options
                          (list :columns '("Ordre" "Kunde" ("Beløp" :align :end))
                                :rows '(("10482" "Fjordkaffe AS" "4 380,00 kr")
                                        ("10481" "Hansen Bygg AS" "128 950,00 kr")))))))

;;; ------------------------------------------------------------------
;;; Table

(test every-table-cell-carries-its-column-header-as-a-label
  (let ((html (order-table)))
    (is (= 3 (count-matches "<th scope=\"col\"" html)) "the headers are column headers")
    (dolist (header '("Ordre" "Kunde" "Beløp"))
      (is (= 2 (count-matches (format nil "<span class=\"tun-table-label\">~a</span>" header)
                              html))
          "each of the two rows labels its ~a cell" header))
    (is (search "<td data-align=\"end\"><span class=\"tun-table-label\">Beløp</span>" html)
        "an amount is aligned to the end, label and all")))

(test a-row-with-a-link-links-its-first-cell-only
  (let ((html (order-table :row-href (lambda (row) (format nil "/ordre/~a" (first row))))))
    (is (= 2 (count-matches "<tr data-link=\"true\">" html)))
    (is (= 2 (count-matches "class=\"tun-table-row-link\"" html)) "one link per row")
    (is (search "<a class=\"tun-table-row-link\" href=\"/ordre/10482\">10482" html)
        "the link's text is the first cell's"))
  (let ((html (order-table :row-href '("/ordre/10482" nil))))
    (is (= 1 (count-matches "class=\"tun-table-row-link\"" html))
        "a NIL in the list leaves its row without a link")))

(test a-table-refuses-rows-that-do-not-fit-its-columns
  (signals error (tun.ui:table (:columns '("Ordre" "Kunde") :rows '(("10482")))))
  (signals error (tun.ui:table (:columns '("Ordre") :rows '(("1") ("2"))
                                         :row-href '("/ordre/1")))
           "a list of links has one per row"))

(test an-empty-table-says-so-across-all-its-columns
  (let ((html (tun.html:render-html
               (tun.ui:table (:columns '("Faktura" "Kunde" "Forfall") :rows '()
                                       :empty "Ingen fakturaer.")))))
    (is (search "<tr class=\"tun-table-empty\"><td colspan=\"3\">Ingen fakturaer.</td>" html))
    (is (search "<th scope=\"col\">Faktura</th>" html) "the headers stay")))

(test a-hidden-caption-still-names-the-table
  (let ((html (order-table :caption "Ordre siste uke" :caption-hidden t)))
    (is (search "<caption data-hidden=\"true\">Ordre siste uke</caption>" html))))

;;; ------------------------------------------------------------------
;;; Pagination

(defun pagination-html (page pages)
  (tun.html:render-html (tun.ui:pagination (:page page :pages pages :href "/ordre?side=~d"))))

(test pagination-marks-the-current-page-and-only-it
  (let ((html (pagination-html 3 12)))
    (is (= 1 (count-matches "aria-current=\"page\"" html)))
    (is (tag-with-p html "href=\"/ordre?side=3\"" "data-variant=\"outline\""
                    "aria-label=\"Side 3\"" "aria-current=\"page\"")
        "the current page is the outlined link, named «Side 3»")
    (is (search "aria-label=\"Sidenavigering\"" html))
    (is (search "Side 3 av 12" html) "the phone's status line")))

(test pagination-shows-seven-places-with-gaps
  (flet ((pages (html)
           (mapcar #'parse-integer
                   (cl-ppcre:all-matches-as-strings "(?<=aria-label=\"Side )\\d+" html))))
    (is (equal '(1 2 3 4 5 12) (pages (pagination-html 3 12))))
    (is (equal '(1 6 7 8 24) (pages (pagination-html 7 24))))
    (is (equal '(1 20 21 22 23 24) (pages (pagination-html 22 24))))
    (is (= 2 (count-matches "tun-pagination-gap" (pagination-html 7 24))))
    (is (equal '(1 2 3 4 5) (pages (pagination-html 2 5))) "no gap when every page fits")))

(test pagination-disables-previous-on-the-first-page-and-next-on-the-last
  (let ((first (pagination-html 1 5))
        (last (pagination-html 5 5)))
    (is (tag-with-p first "aria-label=\"Forrige side\"" "aria-disabled=\"true\"")
        "Forrige on page 1 is disabled")
    (is (not (tag-with-p first "aria-label=\"Forrige side\"" "href="))
        "and leads nowhere")
    (is (tag-with-p last "aria-label=\"Neste side\"" "aria-disabled=\"true\""))
    (is (tag-with-p first "aria-label=\"Neste side\"" "href=\"/ordre?side=2\""))))

(test pagination-of-one-page-is-nothing
  (is (null (tun.ui:pagination (:page 1 :pages 1 :href "/?side=~d"))))
  (signals error (tun.ui:pagination (:page 4 :pages 3 :href "/?side=~d"))))

(test pagination-takes-a-function-for-the-address
  (let ((html (tun.html:render-html
               (tun.ui:pagination
                (:page 2 :pages 3 :href (lambda (page) (format nil "/kunder/side/~d" page)))))))
    (is (search "href=\"/kunder/side/3\"" html))))

;;; ------------------------------------------------------------------
;;; The other components

(test a-summary-list-action-names-what-it-changes
  (let ((html (tun.html:render-html
               (tun.ui:summary-list (:rows '(("E-post" "ole@example.no" :href "/endre")
                                             ("Org.nr." "912 345 678")))))))
    (is (search "<dt class=\"tun-summary-list-key\">E-post</dt>" html))
    (is (search (concatenate 'string "<a href=\"/endre\">Endre"
                             "<span class=\"tun-summary-list-hidden\"> E-post</span></a>")
                html))
    (is (= 1 (count-matches "tun-summary-list-action" html)) "only the row with a link")))

(test a-card-that-is-a-link-needs-a-title
  (signals error (tun.ui:card (:href "/oppdrag") "Innhold"))
  (let ((html (tun.html:render-html (tun.ui:card (:title "Oppdrag" :href "/oppdrag")))))
    (is (search "data-variant=\"link\"" html))
    (is (search (concatenate 'string "<h3 class=\"tun-card-title\">"
                             "<a class=\"tun-card-link\" href=\"/oppdrag\">Oppdrag</a>")
                html))))

(test a-stat-colours-its-change-by-its-sign-unless-told
  (flet ((tone (&rest options)
           (cl-ppcre:scan-to-strings "tun-stat-change\" data-variant=\"\\w+"
                                     (tun.html:render-html
                                      (tun.ui:stat* (list* :label "Omsetning" :value "1 kr"
                                                           options))))))
    (is (search "success" (tone :change "+12 %")))
    (is (search "destructive" (tone :change (format nil "~c3 %" (code-char #x2212))))
        "a minus sign counts as down")
    (is (search "destructive" (tone :change "-3 %")))
    (is (search "neutral" (tone :change "0 %")))
    (is (search "destructive" (tone :change "+8 %" :change-tone :destructive)))))

(test a-timeline-entry-has-a-machine-readable-time
  (let ((html (tun.html:render-html
               (tun.ui:timeline (:entries '((:time "I dag kl. 10.12"
                                             :datetime "2026-10-13T10:12+02:00"
                                             :actor "Kari" :text "sendte purring")))))))
    (is (tag-with-p html "<time " "datetime=\"2026-10-13T10:12+02:00\""))
    (is (search "<ol class=\"tun-timeline\">" html))))

(test a-code-block-copy-button-is-hidden-until-the-script-reveals-it
  (let* ((html (tun.html:render-html (tun.ui:code-block () "tun_live_abc")))
         (id (cl-ppcre:scan-to-strings "(?<=<code class=\"tun-code-block-code\" id=\")[^\"]+"
                                       html)))
    (is (stringp id))
    (is (tag-with-p html "aria-label=\"Kopier\"" " hidden"
                    (format nil "data-tun-copy=\"~a\"" id))
        "the button names what it does, starts hidden and points at the text")
    (is (tag-with-p html "aria-live=\"polite\"" (format nil "data-tun-copy-status=\"~a\"" id))
        "«Kopiert» is announced"))
  (is (not (search "data-tun-copy"
                   (tun.html:render-html (tun.ui:code-block (:copy nil) "nix develop ."))))))
;;; ------------------------------------------------------------------
;;; Board (spec/ui.md 6.1)

(defun items-board (&rest options)
  (tun.html:render-html
   (tun.ui:board* (append options
                          (list :label "Saker etter status"
                                :columns (list (list :key "ny" :title "Ny"
                                                     :cards (list (list :id "itm_1" :title "Eksporten feiler"
                                                                        :href "/saker/itm_1"
                                                                        :meta "Kari")
                                                                  (list :id "itm_2" :title "Lager")))
                                               (list :key "ferdig" :title "Ferdig" :count "20+"
                                                     :cards '())))))))

(test a-board-shows-its-columns-cards-and-counts
  (let ((html (items-board :action "/saker/flytt")))
    (is (tag-with-p html "class=\"tun-board\"" "role=\"region\"" "data-tun-board " "data-tun-fill"
                    "aria-label=\"Saker etter status\"" "data-tun-board"))
    (is (tag-with-p html "data-tun-board-column=\"ny\"" "aria-labelledby=\"tun-board-ny\""))
    (is (search "<h3 class=\"tun-board-column-title\" id=\"tun-board-ny\">Ny</h3>" html))
    (is (search "data-tun-board-count>2</span>" html) "the number of cards")
    (is (search "data-tun-board-count>20+</span>" html) "or the count the page gives")
    (is (search "<a class=\"tun-board-card-title\" href=\"/saker/itm_1\">Eksporten feiler</a>" html))
    (is (search "<span class=\"tun-board-card-title\">Lager</span>" html) "a card without a link")
    (is (search "<p class=\"tun-board-empty\">Ingen</p>" html))))

(test a-board-card-moves-by-a-plain-form
  (let ((html (items-board :action "/saker/flytt")))
    (is (tag-with-p html "<form" "id=\"tun-board-itm_1-form\"" "method=\"post\""
                    "action=\"/saker/flytt\"" "hx-post=\"/saker/flytt\""
                    "hx-target=\"closest .tun-board\"" "hx-swap=\"outerMorph\"")
        "the answer is morphed into the board, which keeps where its columns are scrolled")
    (is (search "<input type=\"hidden\" name=\"card\" value=\"itm_1\">" html))
    (is (tag-with-p html "type=\"submit\"" "form=\"tun-board-itm_1-form\"" "name=\"column\""
                    "value=\"ferdig\"" "data-tun-board-move=\"ferdig\"")
        "the menu moves it to the other column")
    (is (not (tag-with-p html "form=\"tun-board-itm_1-form\"" "value=\"ny\""))
        "not to the column it is in")
    (is (search "id=\"tun-board-itm_1-move-trigger\"" html)
        "its menu button's id is the same in every answer")
    (is (search "aria-label=\"Flytt «Eksporten feiler»\"" html))))

(test a-board-without-an-action-moves-nothing
  (let ((html (items-board :message (list (tun.ui:alert () "Ikke flyttet")))))
    (is (not (search "data-tun-board>" html)) "no dragging")
    (is (not (search "<form" html)))
    (is (not (search "tun-dropdown-menu" html)))
    (is (search "Ikke flyttet" html) "the message"))
  (signals error (tun.ui:board (:columns '())) "a board needs a label"))
;;; ------------------------------------------------------------------
;;; Sorting a table (spec/ui.md 6)

(test a-sortable-header-links-to-the-other-direction
  (let ((html (order-table :columns '(("Ordre" :sort "number" :sorted :asc) ("Kunde" :sort "customer")
                                      ("Beløp" :align :end))
                           :sort-href "/ordre?sort=~a&retning=~a")))
    (is (tag-with-p html "<th" "aria-sort=\"ascending\"") "the column the rows are sorted by")
    (is (search "href=\"/ordre?sort=number&amp;retning=desc\"" html)
        "sorted ascending, it leads to descending")
    (is (search "href=\"/ordre?sort=customer&amp;retning=asc\"" html) "another column, ascending")
    (is (= 1 (count-matches "aria-sort" html)) "only the sorted column says so")
    (is (= 2 (count-matches "class=\"tun-table-sort\"" html)) "a column without :sort is no link"))
  (is (search "href=\"/x/customer/desc\""
              (order-table :columns '("Ordre" ("Kunde" :sort "customer" :sorted :asc) "Beløp")
                           :sort-href (lambda (key direction) (format nil "/x/~a/~a" key direction))))
      "a function makes the link")
  (signals error (order-table :columns '(("Ordre" :sort "number") "Kunde" "Beløp"))
    "a sortable column needs :sort-href"))

(test long-board-columns-scroll-inside-and-fit-on-a-phone
  (let ((css (tun.ui:component-css (tun.ui:find-component "board"))))
    (is (search "overflow-y: auto" css))
    (is (search "max-height: var(--tun-fill-max-height, min(46rem, calc(100dvh - " css)
        "on a phone a column fits on the screen under the header")
    (is (search "@media (max-width: 40rem) { padding-block-end:" css)
        "with a strip of page under the board")
    (is (search "align-items: var(--tun-fill-align, start)" css))
    (is (search "max-height: var(--tun-fill-max-height, min(70dvh, 46rem))" css)
        "where the shell gives it a height, a board fills it"))
  (is (search "data-tun-fill"
              (tun.html:render-html
               (tun.ui:board (:label "Tavle" :columns (list (list :key "ny" :title "Ny"))))))))

(test the-shell-gives-a-board-the-height-the-page-leaves
  (let ((css (tun.ui:component-css (tun.ui:find-component "app-shell"))))
    (is (search ".tun-app-shell-content:has(> [data-tun-fill]" css))
    (is (search "min-height: calc(100dvh - var(--spacing) * 14 - 1px)" css))
    (is (search "--tun-fill-max-height: none" css))
    (is (search "min-height: 20rem" css)))
  (is (search "@media (max-width: 40rem) { flex-basis: auto; }"
              (tun.ui:component-css (tun.ui:find-component "page-header")))
      "on a phone a short title and its actions share a row"))

(test dragging-a-card-stops-the-columns-snapping-and-pages-them-by-touch
  (let ((board (tun.ui:find-component "board")))
    (is (search "&[data-tun-board-moving] .tun-board-columns { scroll-snap-type: none; }"
                (tun.ui:component-css board))
        "the script can scroll the columns while a card is dragged")
    (let ((script (tun.ui:component-script board)))
      (is (search "board.dataset.tunBoardMoving = ''" script))
      (is (search "delete board.dataset.tunBoardMoving" script) "and they snap again after")
      (is (search "page(box, sideways)" script) "a finger pages a column at a time")
      (is (search "Math.min(rect.right, window.innerWidth)" script)
          "counting the edge where the screen cuts the box off"))))
