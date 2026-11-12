;;;; tests/ui-fields-tests.lisp -- the date, time and money fields, the
;;;; calendar, and a period as a list's filter: what a person types, read on
;;;; the server; the fields' markup and CSS; the generated forms and lists
;;;; that use them (spec/ui.md 6, 8, 10; spec/i18n.md 6.2).

(in-package #:tun.tests)

(def-suite ui-fields :in core)
(in-suite ui-fields)

;;; ------------------------------------------------------------------
;;; Reading a date (criterion 1)

(defparameter +months-en+ '("Jan" "Feb" "Mar" "Apr" "May" "Jun" "Jul" "Aug" "Sep" "Oct" "Nov" "Dec"))
(defparameter +months-en-whole+
  '("January" "February" "March" "April" "May" "June" "July" "August" "September" "October"
    "November" "December"))
(defparameter +months-nb-whole+
  '("januar" "februar" "mars" "april" "mai" "juni" "juli" "august" "september" "oktober"
    "november" "desember"))

(defun every-day (from-year to-year)
  "Every date from FROM-YEAR's first day to TO-YEAR's last, YYYY-MM-DD."
  (loop for day = (format nil "~d-01-01" from-year) then (date-add-days day 1)
        while (<= (parse-integer day :end 4) to-year)
        collect day))

(defun date-forms (date)
  "The forms of spec/i18n.md 6.2 a person may write DATE in, with its year."
  (destructuring-bind (y m d) (mapcar #'parse-integer (cl-ppcre:split "-" date))
    (let ((yy (mod y 100)))
      (list (format nil "~d.~d.~d" d m y) (format nil "~2,'0d.~2,'0d.~d" d m y)
            (format nil "~d/~d/~2,'0d" d m yy) (format nil "~d-~d-~d" d m y)
            (format nil "~d ~d ~d" d m y) (format nil "~d,~d,~d" d m y)
            (format nil "~d. ~d. ~d." d m y) (format nil "  ~d.~d.~d  " d m y)
            (format nil "~2,'0d~2,'0d~d" d m y) (format nil "~2,'0d~2,'0d~2,'0d" d m yy)
            (format nil "~d-~2,'0d-~2,'0d" y m d) (format nil "~d-~d-~d" y m d)
            (format nil "~d.~2,'0d.~2,'0d" y m d)
            (format nil "~d ~a ~d" d (nth (1- m) +months-en+) y)
            (format nil "~d ~a ~d" d (string-upcase (nth (1- m) +months-en-whole+)) y)
            (format nil "~a ~d, ~d" (nth (1- m) +months-en+) d y)
            (format nil "~d ~a. ~d" d (string-downcase (nth (1- m) +months-en+)) yy)))))

(defun date-forms-this-year (date)
  "The forms of DATE without a year, read in the year it is in."
  (destructuring-bind (m d) (mapcar #'parse-integer (rest (cl-ppcre:split "-" date)))
    (list (format nil "~d.~d." d m) (format nil "~d.~d" d m) (format nil "~2,'0d~2,'0d" d m)
          (format nil "~d/~d" d m) (format nil "~d ~a" d (nth (1- m) +months-en+))
          (format nil "~a ~d" (nth (1- m) +months-en-whole+) d))))

(test every-day-in-every-form-is-read-as-itself
  (let ((wrong '()) (count 0))
    (dolist (date (every-day 2024 2027))
      (let ((today (concatenate 'string (subseq date 0 4) "-06-15")))
        (dolist (form (append (date-forms date) (date-forms-this-year date)))
          (incf count)
          (let ((read (read-date-text form :today today)))
            (unless (equal read date) (push (list form read) wrong))))))
    (is (null wrong) "~d of ~d forms misread, such as ~s" (length wrong) count (first wrong))))

(test a-month-is-read-in-the-pages-language-too
  (with-language ("nb")
    (dolist (date (every-day 2026 2026))
      (destructuring-bind (y m d) (mapcar #'parse-integer (cl-ppcre:split "-" date))
        (dolist (form (list (format nil "~d. ~a ~d" d (nth (1- m) +months-nb-whole+) y)
                            (format nil "~d. ~a" d (subseq (nth (1- m) +months-nb-whole+) 0 3))
                            (format nil "~d ~a ~d" d (nth (1- m) +months-en-whole+) y)))
          (is (equal date (read-date-text form :today "2026-01-01")) "~s" form)))))
  (is (equal "2026-10-21" (with-language ("nb") (read-date-text "21. okt." :today "2026-01-01"))))
  (is (null (read-date-text "21 okt 2026" :today "2026-01-01"))
      "a Norwegian month is not English's"))

(test what-is-not-a-date-is-refused-with-a-message
  (dolist (text '("31.4.2026" "29.2.2027" "30.2.2028" "32.1.2026" "1.13.2026" "0.1.2026" "1.0.2026"
                  "1.2.026" "1.2.20261" "1.2.6" "1.2.1899" "1.2.2026.4" "12345" "1234567"
                  "123456789" "1" "12" "2026" "2026-13-01" "2026-02-30" "2026-2" "1.2.2026 10:00"
                  "1.2.2026 kl. 10" "1 Feb Mar 2026" "1 xyz 2026" "first of may" "1-2-3-4"
                  ".1.2.2026" "1..2.2026x" "1.2.2026T" "abc" "½.2.2026" "١.٢.٢٠٢٦" "1;2;2026"
                  "100.2.2026" "1.200.2026" "2026.1"))
    (multiple-value-bind (date message) (read-date-text text :today "2026-06-15")
      (is (null date) "~s read as ~a" text date)
      (is (and message (search "must be a date, such as 21 Oct 2026" (princ-to-string message)))
          "~s has the field's message" text)))
  (is (equal "må være en dato, som 21.10.2026"
             (with-language ("nb")
               (princ-to-string (nth-value 1 (read-date-text "31.4.2026"))))))
  (dolist (text '("" "   " nil))
    (multiple-value-bind (date message) (read-date-text text)
      (is (and (null date) (null message)) "an empty text is nothing given"))))

(test random-texts-are-read-without-an-error
  (let ((*random-state* (sb-ext:seed-random-state 20261112))
        (pieces #("1" "2" "12" "31" "29" "0" "00" "2026" "26" "1899" "9999" "10000" "." "/" "-"
                  "," " " "  " "Feb" "feb." "februar" "May" "okt" "x" "T" ":" "01022026")))
    (dotimes (n 10000)
      (let ((text (with-output-to-string (out)
                    (dotimes (i (random 7))
                      (write-string (aref pieces (random (length pieces))) out)))))
        (let ((read (handler-case (read-date-text text :today "2026-06-15")
                      (error (e) (format nil "error: ~a" e)))))
          (unless (or (null read) (valid-date-string-p read))
            (is nil "~s gave ~s" text read)
            (return)))))
    (pass)))

;;; ------------------------------------------------------------------
;;; Reading a time and an amount (criterion 2)

(test every-minute-in-every-form-is-read-as-itself
  (let ((wrong '()))
    (dotimes (hour 24)
      (dotimes (minute 60)
        (let ((time (format nil "~2,'0d:~2,'0d" hour minute)))
          (dolist (form (append (list (format nil "~d:~2,'0d" hour minute) time
                                      (format nil "~d.~2,'0d" hour minute)
                                      (format nil "~d,~2,'0d" hour minute)
                                      (format nil "~d ~2,'0d" hour minute)
                                      (format nil "~d~2,'0d" hour minute)
                                      (format nil "~2,'0d~2,'0d" hour minute)
                                      (format nil " ~d : ~2,'0d " hour minute))
                                (when (zerop minute)
                                  (list (format nil "~d" hour) (format nil "~2,'0d" hour)))))
            (unless (equal time (read-time-text form)) (push form wrong))))))
    (is (null wrong) "misread: ~s" (subseq wrong 0 (min 5 (length wrong))))))

(test what-is-not-a-time-is-refused-with-a-message
  (dolist (text '("24:00" "24" "25" "9:60" "9:5" "09:30:00" "9am" "9 pm" "12345" "930x" "kl. 9"
                  "-1" "1:2:3" "9::30" "a" "9.300" "١٢"))
    (multiple-value-bind (time message) (read-time-text text)
      (is (null time) "~s read as ~a" text time)
      (is (and message (search "must be a time of day, such as 09:30" (princ-to-string message)))
          "~s has the field's message" text)))
  (is (null (read-time-text ""))))

(test the-readers-are-in-tun
  (dolist (name '("READ-DATE-TEXT" "READ-TIME-TEXT" "READ-MONEY-TEXT" "PERIOD-TEXT"))
    (is (eq :external (nth-value 1 (find-symbol name "TUN"))) "~a" name))
  (is (= 125050 (read-money-text "1 250,50" :currency "NOK" :language "nb")))
  (is (= 125050 (read-money-text "1250.5" :currency "NOK" :language "nb")))
  (is (null (read-money-text "12,505" :currency "NOK" :language "nb"))
      "more decimals than the currency has"))

(test a-date-is-read-over-a-page-and-not-over-mcp
  (with-test-app ()
    (let ((customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari"
                                   "email" "kari@example.no")
                          "id")))
      (is (equal "invalid_input"
                 (nth-value 1 (call "orders_create" "employee:anna" "customer_id" customer
                                    "event_date" "12.11.2026" "lines" (jarr '()))))
          "over MCP a date is YYYY-MM-DD only")
      (let ((tun.core:*written-amounts* t))
        (multiple-value-bind (json code)
            (call "orders_create" "employee:anna" "customer_id" customer
                  "event_date" "31.11.2026" "lines" (jarr '()))
          (is (equal "invalid_input" code))
          (is (search "must be a date, such as 21 Oct 2026" (to-json-string json))))))))

;;; ------------------------------------------------------------------
;;; A period as the language writes it (criterion 8)

(test a-period-is-written-as-the-language-writes-it
  (flet ((both (from to) (list (period-text from to :today "2026-11-12")
                               (with-language ("nb") (period-text from to :today "2026-11-12")))))
    (is (equal '("1–14 Nov" "01.–14.11.") (both "2026-11-01" "2026-11-14")))
    (is (equal '("28 Oct – 3 Nov" "28.10.–03.11.") (both "2026-10-28" "2026-11-03")))
    (is (equal '("28 Dec 2026 – 3 Jan 2027" "28.12.2026–03.01.2027") (both "2026-12-28" "2027-01-03")))
    (is (equal '("From 1 Nov" "Fra 01.11.") (both "2026-11-01" nil)))
    (is (equal '("Until 14 Nov" "Til 14.11.") (both "" "2026-11-14")))
    (is (equal '("From 1 Nov 2025" "Fra 01.11.2025") (both "2025-11-01" nil)))
    (is (equal '("12 Nov" "12.11.") (both "2026-11-12" "2026-11-12")))
    (is (equal '("From 1.13" "Fra 1.13") (both "1.13" nil)) "what is not a date, as it is")
    (is (equal '(nil nil) (both nil "")))))

;;; ------------------------------------------------------------------
;;; The fields (criteria 3, 4, 6)

(defun render (node) (tun.html:render-html node))

(test the-date-field-writes-its-date-and-posts-what-is-typed
  (let ((html (render (tun.ui:date-input (:label "Delivery" :name "delivery" :id "d"
                                          :value "2026-11-21" :hint "The first day.")))))
    (is (html-has html "<div class=\"tun-date-input\" data-tun-date-input"
                  "class=\"tun-text-input tun-date-input-control\" type=\"text\" name=\"delivery\" value=\"21 Nov 2026\""
                  "inputmode=\"decimal\"" "autocomplete=\"off\"" "data-tun-date-value=\"2026-11-21\""
                  "aria-describedby=\"d-hint\"" "The first day. For example, 21 Oct 2026"))
    (is (html-has html "<button type=\"button\" class=\"tun-date-input-open\" popovertarget=\"d-calendar\" aria-label=\"Choose a date\" aria-haspopup=\"dialog\" aria-expanded=\"false\""))
    (is (html-has html "id=\"d-calendar\" popover=\"auto\" role=\"dialog\" aria-modal=\"true\" aria-labelledby=\"d-calendar-title\""
                  "role=\"grid\"" "<th scope=\"col\" abbr=\"Monday\">Mo</th>"
                  "<th scope=\"col\" abbr=\"Sunday\">Su</th>"
                  "aria-label=\"Previous month\"" "aria-label=\"Next month\""
                  "data-months=\"January|February|March" "data-day-label=\"{weekday} {day} {month} {year}\""
                  "data-format=\"en\"" "data-week-start=\"1\"")))
  (let ((html (render (tun.ui:date-input (:label "Return" :name "return" :id "r"
                                          :value "31.11.2026" :error "must be a date")))))
    (is (html-has html "value=\"31.11.2026\"" "aria-invalid=\"true\"" "aria-describedby=\"r-hint r-error\""))
    (is (not (search "data-tun-date-value" html)) "a text it cannot read names no date"))
  (let ((html (render (tun.ui:date-input (:label "Typed" :name "typed" :value "1.2.2026")))))
    (is (html-has html "value=\"1.2.2026\"" "data-tun-date-value=\"2026-02-01\"")
        "a date as typed stays as typed, and the calendar knows it"))
  (let ((html (render (tun.ui:date-input (:label "Born" :name "born" :autocomplete "bday" :disabled t)))))
    (is (html-has html "autocomplete=\"bday\"" "disabled"))))

(test the-calendar-speaks-norwegian-and-starts-on-monday
  (let ((html (with-language ("nb")
                ;; Tomorrow on: «I dag» is outside, whatever day the suite runs.
                (render (tun.ui:date-input (:label "Levering" :name "levering" :value "2026-11-21"
                                            :quick t
                                            :min (date-add-days (tun.core:page-today) 1)))))))
    (is (html-has html "value=\"21.11.2026\"" "For eksempel 21.10.2026" "aria-label=\"Velg en dato\""
                  "<th scope=\"col\" abbr=\"mandag\">ma</th>" "<th scope=\"col\" abbr=\"søndag\">sø</th>"
                  "data-months=\"januar|februar|mars|april|mai|juni|juli|august|september|oktober|november|desember\""
                  "data-day-label=\"{weekday} {day}. {month} {year}\"" "data-format=\"nb\""
                  "aria-label=\"Forrige måned\"" "aria-label=\"Neste måned\"" ">I dag<" ">I morgen<"))
    (is (cl-ppcre:scan "<th[^>]*>ma</th><th[^>]*>ti</th>" html) "Monday first")
    (is (cl-ppcre:scan "disabled data-tun-date-quick=\"[0-9-]+\"[^>]*>I dag" html)
        "a quick choice outside MIN is disabled, as the grid's days are")))

(test the-calendars-day-chosen-or-today-keeps-its-weight-and-size
  (let ((chosen (remove-if-not (lambda (d) (search "aria-" (selectors-text d)))
                               (component-declarations "date-input"))))
    (is (find-if (lambda (d) (and (search "aria-selected" (selectors-text d))
                                  (string= "background-color" (declaration-property d))))
                 chosen)
        "the chosen day has the ink fill")
    (is (find-if (lambda (d) (and (search "aria-current" (selectors-text d))
                                  (string= "border-color" (declaration-property d))))
                 chosen)
        "today a frame")
    (dolist (d chosen)
      (is (not (cl-ppcre:scan +box-properties+ (declaration-property d)))
          "~a" (declaration-where d)))))

(test the-calendar-opens-and-closes-as-what-opens-does
  (let ((declarations (opening-declarations "date-input" "tun-date-input-calendar")))
    (dolist (declaration declarations)
      (dolist (property (transition-names declaration))
        (is (member property (list* "opacity" "translate" +discrete-properties+) :test #'string=)
            "the calendar animates ~a" property))
      (is (not (member (declaration-property declaration)
                       '("scale" "transform" "rotate" "animation" "animation-name")
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
    (is (find-if (lambda (d) (some (lambda (m) (search "@starting-style" m)) (declaration-media d)))
                 declarations)
        "it starts from its closed state")
    (is (find-if (lambda (d) (and (string= "inset" (declaration-property d))
                                  (search "env(safe-area-inset-bottom)" (declaration-value d))))
                 declarations)
        "0.75rem from the sides and above the safe area on a phone"))
  (is (not (search "@keyframes" (tun.ui:component-css (tun.ui:find-component "date-input"))))))

(test the-calendar-script-follows-the-rules
  (let ((script (tun.ui:component-script (tun.ui:find-component "date-input"))))
    (is (not (search "setTimeout" script)))
    (is (not (search "pointerdown" script)))
    (is (not (search ":popover-open" script)))
    (dolist (key '("ArrowLeft" "ArrowRight" "ArrowUp" "ArrowDown" "PageUp" "PageDown" "Home" "End"
                   "Enter" "Tab"))
      (is (search key script) "~a" key))
    (is (search "dispatchEvent(new Event('change'" script))
    (is (not (cl-ppcre:scan "'(Today|Tomorrow|January|Monday)'" script)) "no copy in the script")))

(test the-time-field-is-five-characters-and-hints-its-form
  (let ((html (render (tun.ui:time-input (:label "Starts at" :name "starts" :id "t" :value "17:30")))))
    (is (html-has html "class=\"tun-time-input tun-text-input\" type=\"text\" name=\"starts\" value=\"17:30\""
                  "inputmode=\"decimal\"" "autocomplete=\"off\"" "data-width=\"5\""
                  "For example, 09:30")))
  (is (search "For eksempel 09:30"
              (with-language ("nb") (render (tun.ui:time-input (:label "Start" :name "start")))))))

(test the-money-field-writes-the-amount-and-the-currency-where-the-language-does
  (let ((html (render (tun.ui:money-input (:label "Deposit" :name "deposit" :id "m"
                                           :currency "EUR" :value 125050)))))
    (is (html-has html "class=\"tun-money-input tun-input-group\" data-width=\"10\""
                  "<span class=\"tun-input-group-addon\" aria-hidden=\"true\">€</span><input"
                  "value=\"1,250.50\"" "inputmode=\"decimal\"" "autocomplete=\"off\"")))
  (is (search "class=\"tun-input-group-addon\" aria-hidden=\"true\">NOK</span><input"
              (render (tun.ui:money-input (:label "Pris" :name "p" :currency "NOK" :value 5)))))
  (let ((html (with-language ("nb")
                (render (tun.ui:money-input (:label "Pris" :name "p" :currency "NOK" :value -125050))))))
    (is (search (format nil "value=\"−1~c250,50\"" #\No-break_space) html))
    (is (cl-ppcre:scan "<input [^>]*><span class=\"tun-input-group-addon\" aria-hidden=\"true\">kr</span></div>"
                       html)
        "after the amount in Norwegian"))
  (is (search "value=\"12.505\""
              (render (tun.ui:money-input (:label "Discount" :name "x" :currency "EUR" :value "12.505"))))
      "a text as it is")
  (is (search "text-align: end; font-variant-numeric: tabular-nums"
              (tun.ui:component-css (tun.ui:find-component "money-input")))))

;;; ------------------------------------------------------------------
;;; Generated forms (criterion 7)

(defun order-form-parts (port jar)
  (let* ((customer (jget (call-ok "customers_create" "employee:anna" "name" "Kari"
                                  "email" "kari@example.no")
                         "id"))
         (product (jget (call-ok "products_create" "employee:anna" "name" "Popcornmaskin"
                                 "kind" "rental" "unit" "stk" "unit_price_minor" 150000
                                 "stock_tracked" nil "units_owned" 3)
                        "id")))
    (values customer product (nth-value 1 (web-request port "/orders" :jar jar)))))

(defun post-order (port jar customer product date &rest more)
  (web-request port "/orders" :method :post :jar jar
               :parameters `(("customer_id" . ,customer) ("event_date" . ,date)
                             ("lines[0][product_id]" . ,product) ("lines[0][quantity]" . "1")
                             ,@more)))

(test a-generated-form-takes-a-date-and-an-amount-as-typed
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (customer product form) (order-form-parts port jar)
        (is (search "class=\"tun-text-input tun-date-input-control\" type=\"text\" name=\"event_date\"" form)
            "a date input is a date field")
        (is (not (search "type=\"date\"" form)) "not the browser's own")
        (is (search "tun-money-input" form) "an amount is a money field")
        (flet ((stored (date)
                 (multiple-value-bind (status body headers) (post-order port jar customer product date)
                   (declare (ignore body))
                   (is (= 303 status) "~a is taken" date)
                   (let ((id (subseq (location headers) (length "/orders/"))))
                     (jget (call-ok "orders_get" "viewer:vera" "id" id) "event_date")))))
          (is (equal "2026-11-12" (stored "12.11.2026")) "typed, read into YYYY-MM-DD")
          (is (equal "2026-11-12" (stored "2026-11-12")) "an ISO date as before")
          (is (equal "2026-11-12" (stored "12 Nov 2026"))))
        (multiple-value-bind (status body)
            (post-order port jar customer product "31.11.2026"
                        '("lines[0][discount_input_minor]" . "12.505"))
          (is (= 422 status))
          (is (search "value=\"31.11.2026\"" body) "a refused date comes back as typed")
          (is (search "must be a date, such as 21 Oct 2026" body) "with its error")
          (is (search "value=\"12.505\"" body) "and so does a refused amount"))))))

;;; ------------------------------------------------------------------
;;; A period in the list toolbar (criteria 8, 9)

(defparameter +period-filter+
  '(:kind :period :label "Period" :names ("from" "to")))

(test a-period-sends-two-keys-and-says-its-days
  (let* ((year (subseq (tun.core:page-today) 0 4))
         (html (toolbar-html :id "t" :filters (list (with-value +period-filter+
                                                                (list (format nil "~a-11-01" year)
                                                                      (format nil "~a-11-14" year)))
                                                    +status-filter+))))
    (is (search "Period: <span class=\"tun-list-toolbar-filter-value\">1–14 Nov</span>" html)
        "the button says the period")
    (is (html-has html (format nil "name=\"from\" value=\"1 Nov ~a\"" year)
                  (format nil "name=\"to\" value=\"14 Nov ~a\"" year)
                  "id=\"t-from-start\"" "id=\"t-from-end\"" ">From<" ">To<"))
    (is (html-has html "data-kind=\"period\"" "data-in-use=\"true\""
                  "href=\"/orders?from=&amp;to=&amp;status=\"")
        "its clear names both keys empty")
    (dolist (quick '("Today" "This week" "This month" "Last month"))
      (is (search (format nil ">~a</a>" quick) html) "~a" quick))
    (is (cl-ppcre:scan "class=\"tun-list-toolbar-quick-choice\" href=\"/orders\\?from=[0-9-]+&amp;to=[0-9-]+&amp;status=\" hx-boost=\"false\"" html)
        "a quick choice is a link with ISO days, the other filters kept")
    (is (search "data-from=\"" html) "and the days it writes in the fields")))

(test a-quick-choice-in-use-is-marked
  (let* ((today (tun.core:page-today))
         (html (toolbar-html :filters (list (with-value +period-filter+ (list today today))))))
    (is (cl-ppcre:scan "aria-current=\"true\"[^>]*>Today</a>" html)))
  (let ((html (toolbar-html :filters (list (append +period-filter+
                                                   '(:value ("2026-01-01" "2026-03-31")
                                                     :quick (("First quarter" "2026-01-01" "2026-03-31"))))))))
    (is (cl-ppcre:scan "aria-current=\"true\"[^>]*>First quarter</a>" html) "the page's own")))

(test a-period-shows-its-errors-and-speaks-norwegian
  ;; Days of this year, so the summary leaves the year out in any year.
  (let* ((year (subseq (tun.core:page-today) 0 4))
         (from (format nil "1.11.~a" year))
         (to (format nil "31.11.~a" year))
         (html (with-language ("nb")
                 (toolbar-html :filters (list (append (list :label "Periode" :value (list from to)
                                                            :errors '(nil "må være en dato"))
                                                      +period-filter+))))))
    (is (html-has html (format nil "Periode: <span class=\"tun-list-toolbar-filter-value\">01.11.–~a</span>" to)
                  ">I dag</a>" ">Denne uka</a>" ">Denne måneden</a>" ">Forrige måned</a>"
                  ">Fra<" ">Til<" (format nil "value=\"~a\"" to) "må være en dato"
                  "aria-invalid=\"true\""))))

(test a-period-is-a-row-of-the-filters-sheet
  (let ((html (toolbar-html :filters (list +status-filter+ +tags-filter+ +period-filter+))))
    (is (search "data-tun-list-toolbar-fold" html))
    (is (cl-ppcre:scan "<dialog[^>]*data-tun-list-toolbar-sheet.*data-kind=\"period\"" html)
        "inside the sheet, as the others")))

(test a-period-applies-on-a-change-never-per-key
  (let ((script (tun.ui:component-script (tun.ui:find-component "list-toolbar"))))
    (is (search "toolbarDate(input)" script))
    (is (search "form.tunSent === fields" script) "the same fields are not sent twice")
    (is (search "data-tun-list-toolbar-quick" script))
    (is (not (search "'input'" script)) "nothing is sent while a date is typed")))

(test the-generated-list-offers-a-pair-of-dates-as-a-period
  (with-test-server (port)
    (let ((jar (web-login port "employee:anna")))
      (multiple-value-bind (june july) (some-orders)
        (let ((page (nth-value 1 (web-request port "/orders" :jar jar))))
          (is (html-has page "data-kind=\"period\"" "name=\"from\"" "name=\"to\"" ">Period<")))
        (let ((typed (nth-value 1 (web-request port "/orders?from=1.7.2026&to=" :jar jar)))
              (iso (nth-value 1 (web-request port "/orders?from=2026-07-01&to=" :jar jar))))
          (dolist (page (list typed iso))
            (is (search july page))
            (is (not (search june page)) "the operation is given the period"))
          (is (search (period-text "2026-07-01" nil) typed) "the button says it")
          (is (search "name=\"from\" value=\"1.7.2026\"" typed) "the field holds what the address does"))
        (let ((page (nth-value 1 (web-request port "/orders?status=completed&from=2026-07-01" :jar jar))))
          (is (search "href=\"/orders?status=&amp;dateless=&amp;tag=&amp;from=&amp;to=\"" page)
              "«Reset» clears the period too"))
        (let ((page (nth-value 1 (web-request port "/orders?from=31.11.2026" :jar jar))))
          (is (search "tun-alert" page) "the list's refusal")
          (is (cl-ppcre:scan "name=\"from\" value=\"31.11.2026\"[^>]*aria-invalid=\"true\"" page)
              "and the error at the field"))))))
