;;;; tests/ui-choice-tests.lisp -- choosing one record among many by typing:
;;;; choice-input, choice-options, matching and answering by the search's
;;;; rule, reading what is posted, a list's :choice filter, the specimen's
;;;; options and query-address (spec/ui.md 6, 7, 8, 10).

(in-package #:tun.tests)

(def-suite ui-choice :in core)
(in-suite ui-choice)

(defun choice-html (&rest options)
  (tun.html:render-html (tun.ui:choice-input* options)))

(defparameter +choice-customers+
  '(("cus_1" "Nordvik Bakery Ltd") ("cus_2" "Hansen Plumbing") ("cus_4" "Bjørn Åsen")
    ("cus_5" "Kari Hansen")))

;;; ------------------------------------------------------------------
;;; The field (criterion 1)

(test a-choice-is-a-select-and-a-button-that-opens-its-list
  (let ((html (choice-html :label "Customer" :name "customer_id" :id "c" :value "cus_4"
                           :options +choice-customers+)))
    (is (search "<select class=\"tun-choice-input-select\" name=\"customer_id\" data-tun-choice-select id=\"c\"" html)
        "one select posts the value under NAME, with the field's id")
    (is (search "<option value=\"\">Choose</option>" html) "nothing chosen is its empty first option")
    (is (search "<option value=\"cus_4\" selected>Bjørn Åsen</option>" html) "VALUE is selected")
    (is (search "<label class=\"tun-field-label\" for=\"c\">Customer" html))
    (is (html-has html "<button type=\"button\" class=\"tun-choice-input-trigger\" id=\"c-trigger\""
                  "popovertarget=\"c-popover\" aria-haspopup=\"dialog\" aria-expanded=\"false\""
                  "aria-labelledby=\"c-name c-text\""
                  "<span id=\"c-name\" hidden>Customer</span>"
                  "<span class=\"tun-choice-input-text\" id=\"c-text\" data-tun-choice-text>Bjørn Åsen</span>"))
    (is (search "<button type=\"button\" class=\"tun-choice-input-clear\" aria-label=\"Clear Customer\" data-tun-choice-clear>"
                html)
        "the clear button shows while an option is chosen")
    (is (html-has html "class=\"tun-choice-input-popover\" id=\"c-popover\" popover=\"auto\" role=\"dialog\" aria-label=\"Customer\""
                  "data-tun-keyboard"))
    (is (html-has html "<input class=\"tun-text-input\" type=\"text\" id=\"c-search\" form=\"c-search-alone\""
                  "autocomplete=\"off\"" "role=\"combobox\"" "aria-expanded=\"true\""
                  "aria-autocomplete=\"list\"" "aria-controls=\"c-list\"" "data-tun-choice-field"))
    (is (not (search "hx-get" html)) "given options ask nothing")
    (is (search "<ul class=\"tun-choice-options\" id=\"c-list\" role=\"listbox\" data-tun-choice-query=\"\">"
                html)
        "given options are the list's whole answer for no text")
    (is (not (search "tun-choice-input-find" html)) "no find step without a source")))

(test the-clear-is-hidden-and-the-placeholder-shown-while-nothing-is-chosen
  (dolist (value '(nil "cus_99"))
    (let ((html (choice-html :label "Customer" :name "customer_id" :id "c" :value value
                             :placeholder "Find a customer" :options +choice-customers+)))
      (is (search "aria-label=\"Clear Customer\" hidden data-tun-choice-clear" html)
          "~s: hidden" value)
      (is (search "data-empty data-tun-choice-text>Find a customer</span>" html)
          "~s: the placeholder, muted" value)
      (is (search "<option value=\"\">Find a customer</option>" html)))))

(test an-error-a-hint-and-disabled-are-a-selects
  (let ((html (choice-html :label "Customer" :name "customer_id" :id "c" :hint "Type the name."
                           :error "Choose a customer" :options +choice-customers+)))
    (is (search "aria-describedby=\"c-hint c-error\" aria-invalid=\"true\"" html)
        "on the select")
    (is (cl-ppcre:scan "class=\"tun-choice-input-trigger\"[^>]*aria-describedby=\"c-hint c-error\" aria-invalid=\"true\""
                       html)
        "and on the button"))
  (let ((html (choice-html :label "Warehouse" :name "w" :id "w" :value "oslo" :disabled t
                           :options '(("oslo" "Oslo")))))
    (is (search "name=\"w\" disabled" html))
    (is (cl-ppcre:scan "class=\"tun-choice-input-trigger\" id=\"w-trigger\" disabled" html))
    (is (search "aria-label=\"Clear Warehouse\" hidden" html) "a disabled choice has no clear")))

(test an-asked-choice-asks-its-source-and-has-a-find-step
  (let ((html (choice-html :label "Customer" :name "customer_id" :id "c" :value "cus_4"
                           :source "/cards/customers" :options '(("cus_4" "Bjørn Åsen")))))
    (is (html-has html "name=\"q\" hx-get=\"/cards/customers\""
                  "hx-trigger=\"input changed delay:150ms, tun-choice-ask\""
                  "hx-target=\"#c-list-box\"" "hx-swap=\"innerHTML\"" "hx-sync=\"this:replace\""))
    (is (search "<ul class=\"tun-choice-options\" id=\"c-list\" role=\"listbox\">" html)
        "a list it has not asked for yet carries no query")
    (is (html-has html "<label class=\"tun-choice-input-find-label\" for=\"c-find\">Find</label>"
                  "type=\"search\" id=\"c-find\" name=\"customer_id-find\""
                  "data-tun-choice-off"
                  "name=\"tun-find\" value=\"customer_id\" formnovalidate"))
    (is (not (search "tun-choice-input-found" html)) "nothing found before a find step"))
  (let ((html (choice-html :label "Customer" :name "customer_id" :id "c" :source "/x"
                           :find "hansen" :options '(("cus_2" "Hansen Plumbing")
                                                     ("cus_5" "Kari Hansen")))))
    (is (search "value=\"hansen\"" html) "the text found stays in its field")
    (is (search ">2 found</p>" html))
    (is (search "<option value=\"cus_5\">Kari Hansen</option>" html) "the select holds the matches"))
  (is (search "Nothing matches «zebra»"
              (choice-html :label "Customer" :name "c" :source "/x" :find "zebra" :options '()))))

(test a-choice-reads-in-norwegian
  (tun.core:with-language ("nb")
    (let ((html (choice-html :label "Kunde" :name "kunde" :id "k" :source "/x" :find "z"
                             :options '())))
      (is (html-has html "<option value=\"\">Velg</option>" "aria-label=\"Fjern Kunde\""
                    ">Finn</label>" "Ingen treff på «z»"
                    "data-tun-choice-failed=\"Valgene kunne ikke hentes. Prøv igjen.\"")))))

(test combobox-renders-as-before
  (let ((html (tun.html:render-html
               (tun.ui:combobox (:label "Customer" :name "customer" :id "cb"
                                 :options '("Kari Nordmann" "Fjord Coffee Ltd"))))))
    (is (search "<input class=\"tun-text-input tun-combobox-input\" type=\"text\" name=\"customer\"" html))
    (is (search "<datalist id=\"cb-choices\">" html))
    (is (not (search "data-tun-choice" html)))))

;;; ------------------------------------------------------------------
;;; The list (criterion 2)

(test the-list-marks-the-chosen-option-and-says-how-many-more
  (let ((html (tun.html:render-html
               (tun.ui:choice-options (:query "nord" :value "cus_1" :more 1980
                                       :options '(("cus_1" "Nordvik Bakery Ltd")
                                                  ("cus_11" "Ola Nordmann")))))))
    (is (search "<ul class=\"tun-choice-options\" role=\"listbox\" data-tun-choice-query=\"nord\">" html))
    (is (search "<li class=\"tun-choice-options-option\" role=\"option\" aria-selected=\"false\" data-value=\"cus_1\" data-chosen=\"true\"><span class=\"tun-choice-options-text\">Nordvik Bakery Ltd</span>"
                html))
    (is (search "data-value=\"cus_11\"><span" html) "the others are not chosen")
    (is (search "<li class=\"tun-choice-options-more\" role=\"presentation\">1980 more. Type to narrow them.</li>"
                html))
    (is (search "<li class=\"tun-choice-options-none\" role=\"presentation\" hidden>No match</li>" html)))
  (let ((html (tun.html:render-html (tun.ui:choice-options (:query "zebra" :options '())))))
    (is (search "<li class=\"tun-choice-options-none\" role=\"presentation\">No match</li>" html))
    (is (not (search "tun-choice-options-more" html))))
  (tun.core:with-language ("nb")
    (is (search "til. Skriv for å snevre inn."
                (tun.html:render-html
                 (tun.ui:choice-options (:options '(("a" "A")) :more 1980)))))))

(test the-active-option-changes-its-ground-not-its-size
  (let ((css (component-css-text 'tun.ui:choice-options)))
    (is (cl-ppcre:scan "&\\[aria-selected='true'\\] \\{\\s*background-color: var\\(--accent\\);\\s*box-shadow: inset 0 0 0 1px var\\(--border-strong\\);\\s*\\}"
                       css))
    (is (search "&:active { background-color: var(--pressed); transition-duration: 0s; }" css))
    (is (search "min-height: var(--control-height);" css) "2.25rem, 2.75rem on a touch screen")))

(test the-phones-sheet-stands-above-the-keyboard
  (let ((css (component-css-text 'tun.ui:choice-input)))
    (is (search "@media (max-width: 39.99rem)" css))
    (is (search "+ max(var(--tun-visual-bottom, 0px), env(safe-area-inset-bottom)));" css)
        "its bottom above what a keyboard covers")
    (is (search "height: min(24rem, calc(100dvh - var(--tun-visual-top, 0px)" css)
        "as high from the start as it will be")
    (is (search "&[data-above] { flex-direction: column-reverse; }" css)
        "above the field, its text field last"))
  (let ((script (tun.ui:component-script (tun.ui:find-component 'tun.ui:dialog))))
    (is (search "[data-tun-keyboard]" script)
        "the dialog's script writes the keyboard's room while such a popover is open"))
  (is (search "+ max(var(--tun-visual-bottom, 0px), env(safe-area-inset-bottom)));"
              (component-css-text 'tun.ui:list-toolbar))
      "and a filter's floating sheet"))

;;; ------------------------------------------------------------------
;;; Matching by the one rule (criterion 3)

(defparameter +choice-rows+
  '((:id "c1" :name "Anna Berg" :email "anna@berg.example")
    (:id "c2" :name "Bjørn Åsen" :email "bjorn@asen.example")
    (:id "c3" :name "Åse Holm" :email "ase@holm.example")
    (:id "c4" :name "Kari Hansen" :email "kari@hansen.example")
    (:id "c5" :name "Hansen Plumbing" :email "post@41234567.example"))
  "Rows in the order a page wants them, by name.")

(defun choice-texts (text &rest keys)
  (mapcar #'second (apply #'choice-matches text +choice-rows+
                          :text (lambda (row) (getf row :name)) keys)))

(test a-blank-text-matches-every-row-in-its-order
  (is (equal '("Anna Berg" "Bjørn Åsen" "Åse Holm" "Kari Hansen" "Hansen Plumbing")
             (choice-texts "")))
  (is (equal (choice-texts "") (choice-texts "   ")))
  (multiple-value-bind (options more)
      (choice-matches nil +choice-rows+ :text (lambda (row) (getf row :name)) :limit 2)
    (is (equal '(("c1" "Anna Berg") ("c2" "Bjørn Åsen")) options) "the row's id is its value")
    (is (= 3 more) "and the rest are counted"))
  (is (equal '("Bjørn Åsen" "Åse Holm" "Kari Hansen" "Hansen Plumbing")
             (choice-texts "" :keep (lambda (row) (not (equal (getf row :id) "c1")))))
      "KEEP says which are offered"))

(test a-choice-finds-what-the-search-finds
  (is (equal '("Bjørn Åsen") (choice-texts "bjorn ase")) "every word, folded, in any order")
  (is (equal '("Bjørn Åsen") (choice-texts "ASEN bjørn")))
  (is (equal '("Åse Holm" "Bjørn Åsen") (choice-texts "ase"))
      "the name that starts with it first, then the one with a word that does")
  (is (equal '("Hansen Plumbing" "Kari Hansen") (choice-texts "hansen"))
      "a name that starts with it before one with a word that does")
  (is (equal '("Kari Hansen") (choice-texts "hansen kari")))
  (is (equal '("Hansen Plumbing") (choice-texts "hansen" :limit 1)) "LIMIT")
  (is (null (choice-texts "zebra")))
  (flet ((by-email (text)
           (mapcar #'second (choice-matches text +choice-rows+
                                            :text (lambda (row) (getf row :name))
                                            :identifiers (lambda (row) (list (getf row :email)))))))
    (is (equal '("Kari Hansen") (by-email "kari@hansen.example")) "an identifier whole")
    (is (null (by-email "kari@han")) "not an email's start without a digit")
    (is (equal '("Hansen Plumbing") (by-email "post@4123")) "with a digit, its start"))
  (is (equal '(("x2" "Bjørn Åsen"))
             (choice-matches "bjorn" +choice-rows+ :text (lambda (row) (getf row :name))
                             :value (lambda (row)
                                      (concatenate 'string "x" (subseq (getf row :id) 1)))))
      "VALUE gives the option's value"))

(test equal-scores-keep-the-rows-order
  (let ((rows (loop for name in '("Ole Dahl" "Ole Berg" "Ole Aas")
                    collect (list :id name :name name))))
    (is (equal '("Ole Dahl" "Ole Berg" "Ole Aas")
               (mapcar #'second (choice-matches "ole" rows
                                                :text (lambda (row) (getf row :name))))))))

;;; ------------------------------------------------------------------
;;; Reading what is posted (criterion 5)

(test read-choice-takes-only-one-of-the-options
  (is (equal '("cus_4" nil "Bjørn Åsen")
             (multiple-value-list (read-choice "cus_4" +choice-customers+)))
      "the value, no message, and its text")
  (is (equal '(nil) (multiple-value-list (read-choice "" +choice-customers+))) "nothing chosen")
  (is (equal '(nil) (multiple-value-list (read-choice nil +choice-customers+))))
  (multiple-value-bind (value problem) (read-choice "cus_99" +choice-customers+)
    (is (null value))
    (is (equal "must be one of the choices" (princ-to-string problem)))
    (tun.core:with-language ("nb")
      (is (equal "må være et av valgene" (princ-to-string problem)))))
  (flet ((name-of (id) (cdr (assoc id '(("cus_7" . "Café Øst")) :test #'equal))))
    (is (equal '("cus_7" nil "Café Øst") (multiple-value-list (read-choice "cus_7" #'name-of)))
        "an asked choice reads the record")
    (is (null (read-choice "cus_8" #'name-of)))
    (is (not (null (nth-value 1 (read-choice "cus_8" #'name-of)))))))

(test choice-find-is-the-text-of-a-find-step
  (is (equal "bjorn" (tun.web:choice-find (jobj "tun-find" "customer" "customer-find" " bjorn ")
                                  "customer")))
  (is (equal "" (tun.web:choice-find (jobj "tun-find" "customer") "customer"))
      "found with nothing typed")
  (is (null (tun.web:choice-find (jobj "customer-find" "bjorn") "customer"))
      "a text left in the find field does not make a save a find")
  (is (null (tun.web:choice-find (jobj "tun-find" "other" "customer-find" "x") "customer"))))

;;; ------------------------------------------------------------------
;;; Answering an asked choice (criterion 4) and the specimen's (13)

(tun.web:define-page choice-answer-test-page ("choice-answer-test" :policy :employee
                                                                   :navigation nil)
    (method path form query)
  (declare (ignore method path form))
  (tun.web:choice-answer query +choice-rows+ :text (lambda (row) (getf row :name)) :limit 2))

(test choice-answer-answers-the-fragment-to-htmx-and-a-page-to-the-rest
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (htmx '(("HX-Request" . "true") ("HX-Request-Type" . "partial")))
           (fragment (nth-value 1 (web-request port "/choice-answer-test"
                                               :parameters '(("q" . "bjorn ase"))
                                               :jar jar :headers htmx)))
           (all (nth-value 1 (web-request port "/choice-answer-test?q=" :jar jar
                                                                       :headers htmx)))
           (page (nth-value 1 (web-request port "/choice-answer-test?q=ase" :jar jar))))
      (is (search "<ul class=\"tun-choice-options\" role=\"listbox\" aria-label=\"Choices\" data-tun-choice-query=\"bjorn ase\">"
                  fragment))
      (is (search "data-value=\"c2\"><span class=\"tun-choice-options-text\">Bjørn Åsen</span>"
                  fragment))
      (is (not (search "<h1" fragment)) "the list alone")
      (is (search "3 more. Type to narrow them." all) "two shown, the rest counted")
      (is (search "<h1" page) "a page to any other request")
      (is (search "Åse Holm" page))
      (is (= 403 (web-request port "/choice-answer-test?q=a" :jar (web-login port "viewer:vera")))
          "under the page's policy"))))

(test the-specimen-answers-its-asked-choices
  (with-test-server (port)
    (multiple-value-bind (status html) (web-request port "/ui/choice-input/options"
                                              :parameters '(("q" . "bjorn ase")))
      (is (= 200 status))
      (is (search "data-tun-choice-query=\"bjorn ase\"" html))
      (is (search ">Bjørn Åsen</span>" html)))
    (is (search "more. Type to narrow them."
                (nth-value 1 (web-request port "/ui/choice-input/options?q="))))
    (is (= 200 (web-request port "/ui/choice-input")))))

;;; ------------------------------------------------------------------
;;; A list's :choice filter (criteria 10, 11)

(defparameter +customer-filter+
  '(:name "customer" :label "Customer" :kind :choice :source "/orders/customers"
    :choices (("cus_4" "Bjørn Åsen"))))

(test a-choice-filter-says-its-record-and-is-addressed-as-a-one-filter
  (let* ((choice (with-value +customer-filter+ "cus_4"))
         (one (list :name "customer" :label "Customer" :kind :one
                    :choices '(("cus_4" "Bjørn Åsen")) :value "cus_4"))
         (html (toolbar-html :id "t" :search '(:name "q" :label "Search")
                             :filters (list choice +status-filter+))))
    (is (search "<span>Customer: <span class=\"tun-list-toolbar-filter-value\">Bjørn Åsen</span></span>"
                html))
    (is (search "aria-label=\"Clear Customer\"" html))
    (dolist (needle '("data-kind=\"choice\" data-in-use=\"true\" data-tun-list-toolbar-filter=\"customer\" data-tun-choice"
                      "<select name=\"customer\" id=\"t-customer-choice\""
                      "data-tun-choice-select"
                      "<option value=\"\">All</option>"
                      "<option value=\"cus_4\" selected>Bjørn Åsen</option>"
                      "id=\"t-customer-search\"" "hx-get=\"/orders/customers\""
                      "aria-controls=\"t-customer-list\"" "data-tun-keyboard"
                      "name=\"customer-find\""))
      (is (search needle html) "~a" needle))
    (is (equal (tun.ui::toolbar-href "/orders" nil (list choice) nil)
               (tun.ui::toolbar-href "/orders" nil (list one) nil))
        "its address is a :one filter's")
    (is (equal "/orders?customer=cus_4" (tun.ui::toolbar-href "/orders" nil (list choice) nil)))
    (is (equal "/orders?customer=" (tun.ui::toolbar-href "/orders" nil (list choice) nil
                                                        :cleared :all))
        "cleared, it is named empty")))

(test a-choice-filter-in-the-sheet-and-without-a-source
  (let ((html (toolbar-html :id "t" :filters (list (list :name "customer" :label "Customer"
                                                         :kind :choice :all "Every customer"
                                                         :choices +choice-customers+)
                                                   +status-filter+ +tags-filter+))))
    (is (search "data-tun-list-toolbar-fold" html) "three filters fold on a phone")
    (is (search "<option value=\"\">Every customer</option>" html))
    (is (not (search "customer-find" html)) "every choice comes with the page: nothing to find")
    (is (search "data-tun-choice-query=\"\"" html) "the list's whole answer")))

;;; ------------------------------------------------------------------
;;; An address with a query (criterion 14), no muted cell (15)

(test query-address-encodes-its-pairs
  (is (equal "/orders?q=kari%20nord&status=&tag=a&tag=b"
             (tun.web:query-address "/orders" '(("q" . "kari nord") ("status" . "") ("tag" "a" "b")))))
  (is (equal "/orders" (tun.web:query-address "/orders" '(("q")))) "NIL leaves its pair out")
  (is (equal "/orders" (tun.web:query-address "/orders" '())))
  (is (equal "/orders?a=1&b=%C3%A6%26%3D%3F"
             (tun.web:query-address "/orders?a=1" '(("b" . "æ&=?"))))
      "after & when it has a query")
  (is (equal "/orders?b=2" (tun.web:query-address "/orders?" '(("b" . 2)))) "a number written out")
  (is (equal "/s?n%C3%B8kkel=v" (tun.web:query-address "/s" '(("nøkkel" . "v"))))))

(test a-table-takes-no-option-for-muted-text
  (signals error (tun.ui:table* '(:columns ("A") :rows (("a")) :muted t)))
  (signals error (tun.ui:table* '(:columns ("A") :rows (("a")) :muted-columns (0)))))
