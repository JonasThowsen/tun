;;;; tests/ui-motion-tests.lisp -- an accordion's content rises and fades as
;;;; it opens, a generated record's action that asks first asks in the
;;;; confirm dialog with the server's token, and a Markdown table of four
;;;; columns or more scrolls in its own box at every width (spec/ui.md 2.1,
;;;; 6, 6.2, 8, 10).

(in-package #:tun.tests)

(def-suite ui-motion :in core)
(in-suite ui-motion)

;;; ------------------------------------------------------------------
;;; The accordion (criterion 1)

(test an-accordion-s-content-rises-and-fades-by-opacity-and-translate
  (let ((css (component-css-text 'tun.ui:accordion)))
    (is (cl-ppcre:scan "@media \\(prefers-reduced-motion: no-preference\\) \\{\\s*& \\.tun-accordion-item\\[open\\] > \\.tun-accordion-content \\{\\s*animation: tun-accordion-open var\\(--duration\\) var\\(--ease\\) backwards;"
                       css)
        "an open item's content runs the keyframes over --duration, only without reduced motion")
    (let ((keyframes (cl-ppcre:scan-to-strings "@keyframes tun-accordion-open \\{[^}]*\\}" css)))
      (is (equal "@keyframes tun-accordion-open {
  from { opacity: 0; translate: 0 var(--spacing); }" keyframes)
          "from below and transparent, by opacity and translate alone: ~s" keyframes))
    (dolist (gone '("interpolate-size" "::details-content" "block-size" "transform" "scale"
                    "allow-discrete"))
      (is (not (search gone css)) "no size or transform moves: ~a" gone))
    (is (not (cl-ppcre:scan "[\\s;{]height:" css)) "no height but the summary's least")
    (is (= 1 (count-matches "@keyframes" css)) "one animation, the opening; closing has none")
    (is (cl-ppcre:scan "&:active \\{ background-color: var\\(--pressed\\); transition-duration: 0s; \\}" css)
        "the summary is still pressed at once")))

(test an-accordion-is-still-details-and-summary
  (let ((html (tun.html:render-html
               (tun.ui:accordion (:items '((:title "Delivery" :content "Two days" :open t)
                                           (:title "Returns" :content "30 days")))))))
    (is (search "<details class=\"tun-accordion-item\" open>" html))
    (is (search "<summary class=\"tun-accordion-trigger\">" html))
    (is (search "<div class=\"tun-accordion-content\">Two days</div>" html))))

;;; ------------------------------------------------------------------
;;; A Markdown table (criterion 8)

(test a-wide-markdown-table-is-a-table-at-every-width
  (let* ((header (format nil "|~{ K~d |~}" (loop for i from 1 to 10 collect i)))
         (delimiter (format nil "|~{~a~}" (loop repeat 10 collect "---|")))
         (row (format nil "|~{ v~d |~}" (loop for i from 1 to 12 collect i)))
         (html (md (md-lines (format nil "| **Fet** ~a" (subseq header 5)) delimiter row
                             "| a | | c |"))))
    (is (search "<div class=\"tun-markdown-table\" data-wide=\"true\"><table><thead><tr><th scope=\"col\"><strong>Fet</strong></th><th scope=\"col\">K2</th>"
                html)
        "the headings stand on top, with their marks")
    (is (search "<tr><td><span class=\"tun-markdown-table-value\">v1</span></td><td><span class=\"tun-markdown-table-value\">v2</span></td>"
                html)
        "a cell holds its value alone")
    (is (search "<tr><td><span class=\"tun-markdown-table-value\">a</span></td><td><span class=\"tun-markdown-table-value\"></span></td><td><span class=\"tun-markdown-table-value\">c</span></td></tr>"
                html)
        "an empty cell stays a cell")
    (is (not (search "tun-markdown-table-label" html)) "no cell holds its column's heading")
    (is (not (search "v11" html)) "cells past the headings are left out")))

(test a-wide-markdown-table-scrolls-in-its-own-box
  (let ((css (component-css-text 'tun.ui:markdown)))
    (is (not (search "@container" css)) "no layout of its own for a narrow box: no cards")
    (is (not (cl-ppcre:scan ":is\\(table, tbody, tr, td\\)|& tr \\{|& thead \\{" css))
        "no rule for a row, a cell or the headings' row as a card")
    (is (not (search "tun-markdown-table-label" css)))
    (is (cl-ppcre:scan "& \\.tun-markdown-table \\{\\s*overflow-x: auto;" css) "the box scrolls")
    (is (= 2 (count-matches "no-repeat local" css)) "two covers scroll with the rows")
    (is (= 2 (count-matches "no-repeat scroll" css)) "two shadows stay at the box's edges")
    (is (cl-ppcre:scan "\\[data-wide\\] \\{\\s*overflow-wrap: break-word;\\s*& td > \\.tun-markdown-table-value \\{\\s*display: block;\\s*width: max-content;\\s*max-width: min\\(16rem, 75cqi\\);"
                       css)
        "a cell keeps its own width up to 16rem, its words whole")))

;;; ------------------------------------------------------------------
;;; A record's action that asks first (criteria 3-5)

(defparameter +htmx-post+ '(("HX-Request" . "true") ("HX-Request-Type" . "full"))
  "The headers of a form htmx posts for a boosted page.")

(defun order-on-the-pages (port jar)
  "A new order, sent and accepted through the pages, ready to confirm or cancel."
  (let* ((customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari"
                                  "email" "kari@example.no")
                         "id"))
         (product (jget (call-ok "products_create" "employee:anna" "name" "Popcornmaskin"
                                 "kind" "rental" "unit" "stk" "unit_price_minor" 150000
                                 "stock_tracked" nil "units_owned" 5)
                        "id"))
         (path (location (nth-value 2 (web-request
                                       port "/orders" :method :post :jar jar
                                       :parameters `(("customer_id" . ,customer)
                                                     ("event_date" . "2026-06-20")
                                                     ("lines[0][product_id]" . ,product)
                                                     ("lines[0][quantity]" . "1"))))))
         (id (subseq path (length "/orders/"))))
    (web-request port (format nil "/orders/~a/orders_send_quote" id) :method :post :jar jar)
    (web-request port (format nil "/orders/~a/orders_accept" id) :method :post :jar jar)
    id))

(defun status-of-order (id)
  (jget (call-ok "orders_get" "viewer:vera" "id" id) "status"))

(defun step-token (body)
  "The confirmation token a step or a confirmation page carries."
  (let ((start (search "name=\"confirmation_token\" value=\"" body)))
    (and start (subseq body (+ start 33) (position #\" body :start (+ start 33))))))

(defun answer-header (name headers)
  (cdr (assoc name headers :test #'string-equal)))

(test without-scripts-the-confirmation-page-is-as-it-was
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (id (order-on-the-pages port jar)))
      (multiple-value-bind (status body headers)
          (web-request port (format nil "/orders/~a/orders_confirm" id) :method :post :jar jar)
        (is (= 200 status))
        (is (search "<!doctype html>" body) "a whole page")
        (is (search "tun-confirm-panel" body))
        (is (search "Confirm the order?" body))
        (is (search "Go back" body))
        (is (search "The confirmation expires" body))
        (is (stringp (step-token body)))
        (is (not (search "data-tun-confirm-step" body)))
        (is (null (answer-header "HX-Retarget" headers)))
        (is (string= "accepted" (status-of-order id)) "nothing changed")
        (multiple-value-bind (status body headers)
            (web-request port (format nil "/orders/~a/orders_confirm" id) :method :post :jar jar
                         :parameters `(("confirmation_token" . ,(step-token body))))
          (declare (ignore body))
          (is (= 303 status))
          (is (string= (format nil "/orders/~a" id) (location headers)))
          (is (string= "confirmed" (status-of-order id))))))))

(test with-scripts-the-server-asks-the-page-to-ask
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (id (order-on-the-pages port jar))
           (path (format nil "/orders/~a/orders_confirm" id)))
      (multiple-value-bind (status body headers)
          (web-request port path :method :post :jar jar :headers +htmx-post+)
        (is (= 200 status))
        (is (string= "[data-tun-confirm-dialog]" (answer-header "HX-Retarget" headers)))
        (is (string= "beforeend" (answer-header "HX-Reswap" headers)))
        (is (string= "false" (answer-header "HX-Push-Url" headers)) "the address stays")
        (is (eql 0 (search "<form" body)) "a fragment only: ~a" (subseq body 0 (min 80 (length body))))
        (is (not (search "<html" body)))
        (is (not (search "tun-app-shell" body)) "no shell")
        (is (search (format nil "<form method=\"post\" hidden data-tun-confirm-step action=\"~a\">" path)
                    body)
            "a hidden form that posts to the same path")
        (is (stringp (step-token body)) "with the operation's token")
        (is (search "data-tun-confirm=\"Confirm the order?\"" body) "the question is the title")
        (is (search (format nil "data-tun-confirm-detail=\"Confirm order ~a for Kari" id) body)
            "the sentence is the operation's summary")
        (is (search "data-tun-confirm-action=\"Confirm the order\"" body))
        (is (search "data-variant=\"primary\"" body) "not a warning")
        (is (string= "accepted" (status-of-order id)) "asking changes nothing")
        ;; The yes posts the step's form, as htmx boosts it.
        (multiple-value-bind (status body headers)
            (web-request port path :method :post :jar jar :headers +htmx-post+
                         :parameters `(("confirmation_token" . ,(step-token body))))
          (declare (ignore body))
          (is (= 303 status) "the record, as for a boosted post")
          (is (string= (format nil "/orders/~a" id) (location headers)))
          (is (string= "confirmed" (status-of-order id)) "it ran once"))))))

(test a-warning-asks-with-the-destructive-button
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (id (order-on-the-pages port jar))
           (body (nth-value 1 (web-request port (format nil "/orders/~a/orders_cancel" id)
                                           :method :post :jar jar :headers +htmx-post+))))
      (is (search "data-tun-confirm=\"Cancel the order?\"" body))
      (is (search "data-variant=\"destructive\"" body) "it ends the order")
      (is (string= "accepted" (status-of-order id))))))

(test the-token-is-still-the-server-s
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (id (order-on-the-pages port jar))
           (other (order-on-the-pages port jar)))
      (flet ((ask (order tool)
               (step-token (nth-value 1 (web-request port (format nil "/orders/~a/~a" order tool)
                                                     :method :post :jar jar :headers +htmx-post+))))
             (refused (order tool token why &optional (headers +htmx-post+))
               (multiple-value-bind (status body)
                   (web-request port (format nil "/orders/~a/~a" order tool) :method :post :jar jar
                                :headers headers
                                :parameters `(("confirmation_token" . ,token)))
                 (is (= 422 status) "~a: ~d" why status)
                 (is (search "data-code=\"confirmation_invalid\"" body) "~a: the record's error" why)
                 (is (search "tun-app-shell" body) "~a: the record page" why))))
        (refused id "orders_cancel" "made-up-token-0123456789" "a token made up")
        (refused id "orders_cancel" "made-up-token-0123456789" "a token made up, no scripts" '())
        (let ((token (ask id "orders_cancel")))
          (refused other "orders_cancel" token "a token for another record")
          (refused other "orders_cancel" token "a token for another record, no scripts" '())
          (refused id "orders_confirm" token "a token for another tool")
          (refused id "orders_confirm" token "a token for another tool, no scripts" '())
          (is (string= "accepted" (status-of-order id)))
          (is (string= "accepted" (status-of-order other)))
          (is (= 303 (web-request port (format nil "/orders/~a/orders_cancel" id) :method :post
                                  :jar jar :headers +htmx-post+
                                  :parameters `(("confirmation_token" . ,token))))
              "the step's own token runs it")
          (is (string= "cancelled" (status-of-order id)))
          (refused id "orders_cancel" token "the same token again")
          (refused id "orders_cancel" token "the same token again, no scripts" '()))
        (let* ((token (ask other "orders_confirm"))
               (expires (jget (call-ok "orders_confirm" "employee:anna" "id" other) "expires_at")))
          ;; A minute after a token issued later than the step's expires.
          (call-ok "clock_set" "admin:a" "now"
                   (tun.core:format-rfc3339 (+ 60 (tun.core:parse-rfc3339 expires))))
          (refused other "orders_confirm" token "a token after its expiry")
          (refused other "orders_confirm" token "a token after its expiry, no scripts" '())
          (is (string= "accepted" (status-of-order other)) "nothing changed"))))))

(test a-refused-first-post-is-the-record-page-as-before
  (with-test-server (port)
    (let* ((jar (web-login port "employee:anna"))
           (id (order-on-the-pages port jar)))
      (multiple-value-bind (status body headers)
          (web-request port (format nil "/orders/~a/orders_confirm" id) :method :post
                       :jar (web-login port "viewer:vera") :headers +htmx-post+)
        (is (= 403 status))
        (is (search "data-code=\"forbidden\"" body))
        (is (null (answer-header "HX-Retarget" headers)) "no step for a refusal"))
      (multiple-value-bind (status body headers)
          (web-request port "/orders/ord_none/orders_confirm" :method :post :jar jar
                       :headers +htmx-post+)
        (is (= 404 status) "no such order: ~d" status)
        (is (not (search "data-tun-confirm-step" body)))
        (is (null (answer-header "HX-Retarget" headers))))
      (is (string= "accepted" (status-of-order id))))))
