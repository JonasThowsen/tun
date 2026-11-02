;;;; tests/chart-tests.lisp -- a value over time: LINE-CHART and SPARKLINE
;;;; (spec/ui.md 6), their ticks and labels, and the markup they may use.

(in-package #:tun.tests)

(def-suite charts :in core)
(in-suite charts)

(defun days-of-prices (prices &key (from "2026-08-03"))
  "PRICES as a chart's points, one a day at noon UTC from FROM."
  (loop for price in prices
        for day from 0
        collect (cons (+ (parse-date from) (* day 86400) 43200) price)))

(defun chart-html (&rest options)
  (with-language ("en")
    (tun.html:render-html (tun.ui:line-chart* options))))

(defun tick-labels (html)
  "The y axis's labels in HTML, from the top."
  (let ((axis (subseq html (search "tun-line-chart-y" html)
                      (search "tun-line-chart-plot" html))))
    (mapcar (lambda (match) (subseq match 6 (- (length match) 7)))
            (cl-ppcre:all-matches-as-strings "<span>[^<]*</span>" axis))))

(defun x-labels (html)
  (let ((axis (subseq html (search "tun-line-chart-x" html)
                      (search "tun-line-chart-live" html))))
    (mapcar (lambda (match) (subseq match 6 (- (length match) 7)))
            (cl-ppcre:all-matches-as-strings "<span>[^<]*</span>" axis))))

;;; ------------------------------------------------------------------
;;; The y axis

(test ticks-are-multiples-of-a-round-step-around-every-value
  (is (equal '("460" "440" "420" "400")
             (tick-labels (chart-html :label "EQNR" :points (days-of-prices '(405.2 439.7 451))))))
  (is (equal '("1.0" "0.5" "0.0" "-0.5")
             (tick-labels (chart-html :label "x" :points (days-of-prices '(-0.3 0.9)))))
      "a step of 0.5, written with its one decimal")
  (is (equal '("1.25" "1.00" "0.75" "0.50" "0.25")
             (tick-labels (chart-html :label "x" :points (days-of-prices '(0.3 1.2)))))
      "a step of 0.25 has two")
  (dolist (prices '((1 2) (0.01 0.02) (99 101) (1000 1001) (5 5.5)))
    (let ((count (length (tick-labels (chart-html :label "x" :points (days-of-prices prices))))))
      (is (<= 3 count 5) "~a gives ~d ticks" prices count))))

(test equal-values-sit-between-two-steps
  (is (equal '("105" "95" "85")
             (tick-labels (chart-html :label "x" :points (days-of-prices '(95 95 95))))))
  (is (equal '("1" "0" "-1")
             (tick-labels (chart-html :label "x" :points (days-of-prices '(0 0))))))
  (is (equal '("-35" "-40" "-45")
             (tick-labels (chart-html :label "x" :points (days-of-prices '(-40)))))
      "a tenth of the absolute value, 4, rounded up to the step 5"))

;;; ------------------------------------------------------------------
;;; The x axis

(test the-x-axis-has-distinct-labels-of-the-right-kind
  (is (equal '("3 Aug" "5 Sep" "7 Oct" "9 Nov")
             (x-labels (chart-html :label "x" :points (days-of-prices
                                                       (make-list 99 :initial-element 1))))))
  (is (equal '("3 Aug" "4 Aug")
             (x-labels (chart-html :label "x" :points (days-of-prices '(1 2)))))
      "two days: not four labels where two read the same")
  (is (equal '("15 Dec 2026" "10 Jan 2027")
             (x-labels (chart-html :label "x"
                                   :points (days-of-prices (make-list 27 :initial-element 1)
                                                           :from "2026-12-15"))))
      "across a new year: the full date, two at most")
  (let ((hours (loop for hour from 9 to 15
                     collect (cons (+ (parse-date "2026-08-03") (* hour 3600)) hour))))
    (is (equal '("09:00" "11:00" "13:00" "15:00")
               (x-labels (chart-html :label "x" :points hours)))
        "one day: times of day"))
  (is (equal '("3 Aug") (x-labels (chart-html :label "x" :points (days-of-prices '(7)))))
      "one point: its day alone"))

;;; ------------------------------------------------------------------
;;; Values, edges and markup

(test values-are-written-with-the-digits-asked-for
  (let ((html (chart-html :label "EQNR" :points (days-of-prices '(281.4d0 290.25d0)) :digits 2)))
    (is (search "<span class=\"tun-line-chart-last\">290.25</span>" html) "the last value")
    (is (search "281.40" html) "in the table")
    (is (search "&quot;281.40&quot;" html) "for the tooltip"))
  (with-language ("nb")
    (is (search "281,40" (tun.html:render-html
                          (tun.ui:line-chart (:label "EQNR"
                                              :points (days-of-prices '(281.4d0))
                                              :digits 2)))))))

(test a-chart-draws-what-its-points-allow
  (let ((html (chart-html :label "Nothing" :points '())))
    (is (search "No data" html))
    (is (not (search "<table" html)) "no table")
    (is (not (search "<svg" html))))
  (let ((html (chart-html :label "One" :points (days-of-prices '(5)))))
    (is (not (search "tun-line-chart-stroke" html)) "one point has no line")
    (is (search "tun-line-chart-dot" html) "but its dot")
    (is (search "cx=\"50.00%\"" html) "in the middle"))
  (let ((html (chart-html :label "Many" :points (days-of-prices '(1 2 3)))))
    (is (search "preserveaspectratio=\"none\"" html))
    (is (search "role=\"img\" aria-label=\"Many\"" html))
    (is (search "aria-live=\"polite\"" html))
    (is (search "<details class=\"tun-line-chart-table\">" html) "closed by default"))
  (signals error (chart-html :label "x"
                             :points (days-of-prices (make-list 2001 :initial-element 1))))
  (signals error (chart-html :label "x" :points '((1 . "a"))))
  (signals error (chart-html :label "x" :points '(5))))

(test points-are-drawn-in-time-order
  (let* ((points (days-of-prices '(1 2 3)))
         (html (chart-html :label "x" :points (reverse points))))
    (is (search "M0.0,1000.0 L500.0,500.0 L1000.0,0.0" html))))

(test a-sparkline-reads-out-its-first-and-last-value
  (flet ((sparkline (&rest options)
           (with-language ("nb") (tun.html:render-html (tun.ui:sparkline* options)))))
    (let ((html (sparkline :label "EQNR.OL" :points (days-of-prices '(412.3d0 420 430)) :digits 2)))
      (is (search "role=\"img\"" html))
      (is (search "aria-label=\"EQNR.OL: 412,30 til 430,00\"" html)))
    (is (search "data-dot" (sparkline :label "x" :points (days-of-prices '(1)))) "one point")
    (let ((html (sparkline :label "x" :points '())))
      (is (search "aria-label=\"x: Ingen data\"" html))
      (is (not (search "<path" html))))))

(test extension-output-may-stretch-a-drawing-and-nothing-more
  (flet ((untrusted (node) (tun.html:render-html (tun.html:untrusted node))))
    (is (search "preserveaspectratio=\"none\""
                (untrusted '(:svg (:@ :preserveaspectratio "none") (:path (:@ :d "M0,0"))))))
    (is (not (search "style=" (untrusted '(:svg (:@ :style "color:red"))))))
    (is (not (search "<text" (untrusted '(:svg (:text "hi"))))))))
