;;;; tests/ui-filters-tests.lisp -- a list's toolbar: its one form, a button
;;;; per filter, a filter in use, «Reset», the «Filters» sheet, its CSS; a
;;;; repeated query key and what a page remembers of it; and the generated
;;;; list's toolbar (spec/ui.md 6 list-toolbar, 8 «Lists», 10).

(in-package #:tun.tests)

(def-suite ui-filters :in core)
(in-suite ui-filters)

(defparameter +status-filter+
  '(:name "status" :label "Status" :kind :one
    :choices (("draft" "Draft") ("confirmed" "Confirmed"))))

(defparameter +tags-filter+
  '(:name "tags" :label "Tags" :kind :several
    :choices (("rental" "Rental") ("music" "Music") ("food" "Food"))))

(defparameter +dateless-filter+
  '(:name "dateless" :label "Without a date" :kind :toggle))

(defun toolbar-html (&rest options)
  (tun.html:render-html (tun.ui:list-toolbar* (list* :action "/orders" options))))

(defun with-value (filter value)
  (append filter (list :value value)))

(defun html-has (html &rest needles)
  "True when HTML holds every one of NEEDLES."
  (every (lambda (needle) (search needle html)) needles))

;;; ------------------------------------------------------------------
;;; One form (criterion 1)

(test the-toolbar-is-one-get-form-naming-every-key
  (let ((html (toolbar-html :search '(:name "q" :label "Search orders" :value "bakery")
                            :filters (list +status-filter+ +tags-filter+ +dateless-filter+)
                            :keep '(("sort" "date")))))
    (is (html-has html "<form class=\"tun-list-toolbar\" id=\"tun-list-toolbar\" method=\"get\""
                  "action=\"/orders\"" "role=\"search\"" "hx-swap=\"innerMorph\""
                  "hx-push-url=\"true\""))
    (is (html-has html "type=\"search\" name=\"q\" value=\"bakery\""
                  "<label class=\"tun-list-toolbar-search-label\" for=\"tun-list-toolbar-search\">Search orders</label>"))
    (is (search "type=\"radio\" id=\"tun-list-toolbar-status-choice\" name=\"status\" value=\"\" checked"
                html)
        "a :one filter's «All» is empty and chosen while nothing is")
    (is (search ">All</span>" html))
    (is (cl-ppcre:scan "<input type=\"hidden\" name=\"tags\" value=\"\">.*name=\"tags\" value=\"rental\""
                       html)
        "a :several filter sends its key empty before its boxes")
    (is (cl-ppcre:scan "<input type=\"hidden\" name=\"dateless\" value=\"\"><label class=\"tun-list-toolbar-toggle\"><input class=\"tun-list-toolbar-toggle-input\" type=\"checkbox\" id=\"tun-list-toolbar-dateless-input\" name=\"dateless\" value=\"true\">"
                       html)
        "so does a toggle")
    (is (search "<input type=\"hidden\" name=\"sort\" value=\"date\">" html) "KEEP goes along")
    (is (search "data-tun-list-toolbar-apply" html) "«Apply» is in the markup; CSS shows it")
    (is (not (search "tun-list-toolbar-reset" html)) "nothing in use, no «Reset»")))

(test every-filter-has-a-button-and-its-choices-in-a-popover
  (let ((html (toolbar-html :filters (list +status-filter+ +tags-filter+))))
    (dolist (name '("status" "tags"))
      (is (search (format nil "<button type=\"button\" class=\"tun-list-toolbar-filter-button\" id=\"tun-list-toolbar-~a-button\" popovertarget=\"tun-list-toolbar-~:*~a-choices\" aria-expanded=\"false\"" name)
                  html))
      (is (search (format nil "<div class=\"tun-list-toolbar-choices\" id=\"tun-list-toolbar-~a-choices\" popover " name)
                  html)))
    (is (search "<legend" html) "the choices are a fieldset under the filter's label")
    (is (not (search "data-tun-list-toolbar-fold" html)) "two filters do not fold")
    (is (not (search "<dialog" html)))))

(test the-ids-are-fixed-so-a-morph-keeps-them
  (is (string= (toolbar-html :filters (list +status-filter+))
               (toolbar-html :filters (list +status-filter+)))
      "the same toolbar renders the same markup")
  (is (search "id=\"cards-status-button\"" (toolbar-html :id "cards" :filters (list +status-filter+)))))

;;; ------------------------------------------------------------------
;;; A filter in use, the clear and «Reset» (criterion 2)

(test a-filter-in-use-says-its-value-and-clears-from-its-button
  (let ((html (toolbar-html :search '(:name "q" :label "Search" :value "lim")
                            :filters (list (with-value +status-filter+ "confirmed")
                                           (with-value +tags-filter+ '("rental" "music"))
                                           (with-value +dateless-filter+ t)
                                           (with-value '(:name "team" :label "Team" :kind :several
                                                         :choices (("a" "Stage") ("b" "Sound")))
                                             '("b")))
                            :keep '(("sort" "date")))))
    (is (search "<span>Status: <span class=\"tun-list-toolbar-filter-value\">Confirmed</span></span>"
                html))
    (is (search "<span>Tags: <span class=\"tun-list-toolbar-filter-value\">2</span></span>" html)
        "two or more of several are counted")
    (is (search "<span>Team: <span class=\"tun-list-toolbar-filter-value\">Sound</span></span>" html)
        "one of several is named")
    (is (search "data-in-use=\"true\"" html))
    (is (search "type=\"checkbox\" id=\"tun-list-toolbar-dateless-input\" name=\"dateless\" value=\"true\" checked"
                html))
    (is (search "<a class=\"tun-list-toolbar-filter-clear\" href=\"/orders?q=lim&amp;status=&amp;tags=&amp;tags=rental&amp;tags=music&amp;dateless=&amp;dateless=true&amp;team=&amp;team=b&amp;sort=date\" hx-boost=\"false\" aria-label=\"Clear Status\""
                html)
        "the clear names every key, its own empty, the others as they are")
    (is (search "href=\"/orders?q=lim&amp;status=confirmed&amp;tags=&amp;dateless=&amp;dateless=true&amp;team=&amp;team=b&amp;sort=date\" hx-boost=\"false\" aria-label=\"Clear Tags\""
                html))
    (is (search "<a class=\"tun-list-toolbar-reset\" href=\"/orders?q=lim&amp;status=&amp;tags=&amp;dateless=&amp;team=&amp;sort=date\" hx-boost=\"false\" data-tun-list-toolbar-reset>Reset</a>"
                html)
        "«Reset» clears every filter and keeps the search and KEEP")))

(test reset-shows-from-two-filters-in-use
  (is (not (search "tun-list-toolbar-reset"
                   (toolbar-html :filters (list (with-value +status-filter+ "draft") +tags-filter+)))))
  (is (search "tun-list-toolbar-reset"
              (toolbar-html :filters (list (with-value +status-filter+ "draft")
                                           (with-value +dateless-filter+ t))))))

(test the-toolbar-speaks-norwegian
  (with-language ("nb")
    (let ((html (toolbar-html :filters (list (with-value +status-filter+ "draft")
                                             (with-value +tags-filter+ '("rental"))
                                             +dateless-filter+))))
      (is (html-has html ">Alle</span>" "aria-label=\"Fjern Status\"" ">Nullstill</a>"
                    ">Bruk</button>" "aria-label=\"Filtre, 2 i bruk\"" ">Filtre<")))))

;;; ------------------------------------------------------------------
;;; The «Filters» sheet (criterion 5)

(test three-filters-fold-into-a-sheet-inside-the-form
  (let ((html (toolbar-html :filters (list (with-value +status-filter+ "draft")
                                           +tags-filter+ +dateless-filter+))))
    (is (search "command=\"show-modal\" commandfor=\"tun-list-toolbar-sheet\"" html))
    (is (search "aria-label=\"Filters, 1 in use\"" html))
    (is (search "<span class=\"tun-list-toolbar-count\" aria-hidden=\"true\">1</span>" html))
    (is (cl-ppcre:scan "<dialog class=\"tun-dialog\" id=\"tun-list-toolbar-sheet\"[^>]*data-tun-list-toolbar-sheet"
                       html))
    (let ((form-end (search "</form>" html :from-end t)))
      (is (< (search "<dialog" html) (search "name=\"tags\"" html) form-end)
          "the sheet and its fields are inside the form")))
  (is (not (search "tun-list-toolbar-count"
                   (toolbar-html :filters (list +status-filter+ +tags-filter+ +dateless-filter+))))
      "no count while none is in use"))

;;; ------------------------------------------------------------------
;;; The CSS (criteria 2, 3, 5)

(defun toolbar-declarations ()
  (component-declarations "list-toolbar"))

(test a-filter-in-use-moves-nothing
  (dolist (declaration (toolbar-declarations))
    (when (cl-ppcre:scan "data-in-use|:checked" (selectors-text declaration))
      (is (not (cl-ppcre:scan +box-properties+ (declaration-property declaration)))
          "in use sets ~a" (declaration-where declaration)))))

(test the-choices-open-as-a-popover-moves
  (let ((declarations (opening-declarations "list-toolbar" "tun-list-toolbar-choices")))
    (dolist (declaration declarations)
      (dolist (property (transition-names declaration))
        (is (member property (list* "opacity" "translate" +discrete-properties+) :test #'string=)
            "the popover animates ~a" property))
      (is (not (member (declaration-property declaration) '("scale" "transform" "animation")
                       :test #'string=))))
    (flet ((duration-p (value &optional media)
             (find-if (lambda (d) (and (string= "transition-duration" (declaration-property d))
                                       (string= value (declaration-value d))
                                       (or (null media)
                                           (some (lambda (m) (search media m))
                                                 (declaration-media d)))))
                      declarations)))
      (is (duration-p "var(--duration-close)") "it leaves over --duration-close")
      (is (duration-p "var(--duration-fast)") "it opens over --duration-fast")
      (is (duration-p "var(--duration)" "max-width: 39.99rem") "a floating sheet on a phone"))
    (is (find-if (lambda (d) (and (string= "inset" (declaration-property d))
                                  (string= "auto calc(var(--spacing) * 3) calc(var(--spacing) * 3 + max(var(--tun-visual-bottom, 0px), env(safe-area-inset-bottom)))"
                                           (declaration-value d))))
                 declarations)
        "0.75rem from the window's sides and above the safe area, and a keyboard")))

(test the-toolbar-folds-below-40rem-of-its-own-width-and-only-with-scripts
  (let ((css (tun.ui:component-css (tun.ui:find-component "list-toolbar"))))
    (is (search "container: tun-list-toolbar / inline-size;" css))
    (is (search "@container tun-list-toolbar (max-width: 39.99rem) {
    @media (scripting: enabled) {" css)
        "the sheet hides the filters only where scripts run")
    (is (search "@media (scripting: enabled) { display: none; }" css) "«Apply» goes with scripts")))

(test the-toolbar-script-submits-a-choice-and-a-clear
  (let ((script (tun.ui:component-script (tun.ui:find-component "list-toolbar"))))
    (is (search "requestSubmit" script))
    (is (search "choices.hidePopover()" script) "one of several closes on the choice")
    (is (not (search "setTimeout" script)))
    (is (not (search "pointerdown" script)))
    (is (search "htmx_before_morph_attr" (tun.ui:script)) "an open dialog stays open in a morph")))

;;; ------------------------------------------------------------------
;;; A repeated key (criterion 1)

(test a-repeated-key-is-an-array-and-query-values-reads-both
  (let ((query (tun.web::query-object '(("q" . "lim") ("tags" . "") ("tags" . "rental")
                                        ("tags" . "music") ("status" . "")))))
    (is (equal "lim" (jget query "q")))
    (is (equalp #("" "rental" "music") (jget query "tags")))
    (is (equal '("rental" "music") (tun.web:query-values query "tags")))
    (is (equal '("lim") (tun.web:query-values query "q")))
    (is (null (tun.web:query-values query "status")))
    (is (null (tun.web:query-values query "missing")))))

(tun.web:define-page tags-page ("test-merker" :title "Merker" :navigation nil
                                              :remembers '("tags" "status"))
    (method path form query)
  (declare (ignore method path form))
  (values 200 "Merker" (list `(:p ,(format nil "tags ~{~a~^,~} status ~{~a~}"
                                           (tun.web:query-values query "tags")
                                           (tun.web:query-values query "status"))))))

(test a-page-remembers-a-repeated-key-and-a-clear-clears-it
  (with-test-server (port)
    (let ((anna (web-login port "employee:anna")))
      (multiple-value-bind (status body)
          (web-request port "/test-merker?tags=&tags=rental&tags=music&status=open" :jar anna)
        (is (= 200 status))
        (is (search "tags rental,music status open" body)))
      (is (equal "/test-merker?tags=rental&tags=music&status=open"
                 (nth-value 1 (filters-request port "/test-merker" anna)))
          "the kept values each in turn")
      (let ((clear (tun.web::pairs-query '(("tags" . "") ("status" . "open")))))
        (is (= 200 (filters-request port (format nil "/test-merker?~a" clear) anna))
            "a clear link names every key, so it is not sent back")
        (is (equal "/test-merker?status=open"
                   (nth-value 1 (filters-request port "/test-merker" anna)))
            "and what it cleared stays cleared"))
      (is (= 200 (filters-request port "/test-merker?tags=&status=" anna)) "«Reset»")
      (is (= 200 (filters-request port "/test-merker" anna)) "nothing kept"))))

;;; ------------------------------------------------------------------
;;; The generated list (criterion 6)

(defun some-orders ()
  "Two orders, a draft and one whose quote is sent; values their ids."
  (let* ((customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari"
                                  "email" "kari@example.no")
                         "id"))
         (product (jget (call-ok "products_create" "employee:anna" "name" "Popcornmaskin"
                                 "kind" "rental" "unit" "stk" "unit_price_minor" 150000
                                 "stock_tracked" nil "units_owned" 2)
                        "id"))
         (orders (loop for date in '("2026-06-20" "2026-07-04")
                       collect (jget (call-ok "orders_create" "employee:anna"
                                              "customer_id" customer "event_date" date
                                              "lines" (jarr (list (jobj "product_id" product
                                                                        "quantity" 1))))
                                     "id"))))
    (call-ok "orders_send_quote" "employee:anna" "id" (second orders))
    (values-list orders)))

(test the-generated-list-filters-by-its-operations-inputs
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (draft sent) (some-orders)
        (let ((page (nth-value 1 (web-request port "/orders" :jar jar))))
          (is (search "<form class=\"tun-list-toolbar\"" page))
          (is (html-has page "name=\"status\" value=\"quote_sent\"" "name=\"dateless\" value=\"true\""
                        "name=\"tag\" value=\"rental\""))
          (is (search "data-tun-list-toolbar-filter=\"customer_id\"" page)
              "a customer's id is a :choice filter (spec/ui.md 8, «Choosing a record»)")
          (is (not (search "tun-list-toolbar-department" page)) "nor other text")
          (is (not (search "name=\"limit\"" page)) "nor the limit")
          (is (and (search draft page) (search sent page))))
        (let ((page (nth-value 1 (web-request port "/orders?status=quote_sent&tag=&dateless="
                                              :jar jar))))
          (is (search sent page))
          (is (not (search draft page)) "the list is called with the address's values")
          (is (search "id=\"tun-list-toolbar-status-choice-" page))
          (is (cl-ppcre:scan "value=\"quote_sent\" checked" page)))
        (let ((page (nth-value 1 (web-request port "/orders?status=completed" :jar jar))))
          (is (search "Nothing matches" page) "a list filtered to nothing says so")
          (is (search "href=\"/orders?customer_id=&amp;status=&amp;dateless=&amp;tag=&amp;from=&amp;to=\"" page)
              "with «Reset» naming every key"))
        (let ((page (nth-value 1 (web-request port "/orders?status=bogus" :jar jar))))
          (is (search "<form class=\"tun-list-toolbar\"" page) "a refused value keeps the toolbar")
          (is (search "tun-alert" page) "and shows the operation's error"))))))

(test the-generated-list-searches-with-a-query-input
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
      (call-ok "customers_create" "employee:anna" "name" "Ola Hansen" "email" "ola@example.no")
      (let ((page (nth-value 1 (web-request port "/customers?query=kari" :jar jar))))
        (is (search "type=\"search\" name=\"query\" value=\"kari\"" page))
        (is (search "Kari Nordmann" page))
        (is (not (search "Ola Hansen" page)) "the search is the operation's query")
        (is (not (search "data-tun-list-toolbar-filter=" page)) "customers_list has no filters")))))

(defclass own-customer-list-feature () ()
  (:documentation "A client's feature with its own customer list, which does not
call the next method."))

(defmethod tun.web:render-screen ((app own-customer-list-feature) (screen (eql :customer-list))
                                  &key items &allow-other-keys)
  (tun.web:json-table (mapcar (lambda (customer) (jobj "Navn" (jget customer "name"))) items)))

(define-application own-customer-list-app (own-customer-list-feature))

(test a-clients-own-list-screen-shows-no-toolbar
  (with-test-server (port :class 'own-customer-list-app)
    (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann" "email" "kari@example.no")
    (call-ok "customers_create" "employee:anna" "name" "Ola Hansen" "email" "ola@example.no")
    (multiple-value-bind (status page)
        (web-request port "/customers?query=kari" :jar (web-login port "employee:anna"))
      (is (= 200 status))
      (is (search "Kari Nordmann" page) "the client's screen shows")
      (is (not (search "tun-list-toolbar" page)) "its own screen alone, no toolbar"))))
