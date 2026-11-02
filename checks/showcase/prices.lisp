;;;; prices.lisp -- /prices: a share's price over three months as a line
;;;; chart, and a watchlist whose rows each have a sparkline (spec/ui.md 6),
;;;; with made-up prices that are the same every time.

(in-package #:showcase)

(defun made-up-prices (count start &key (interval 86400) (seed 1) (from "2026-08-03"))
  "COUNT prices from START, INTERVAL seconds apart from FROM at 07:00 UTC,
moved by a fixed pseudo-random walk from SEED."
  (let ((price start)
        (from (+ (parse-date from) (* 7 3600))))
    (loop for i below count
          collect (cons (+ from (* i interval)) (/ (round price 1/100) 100d0))
          do (setf seed (mod (+ (* seed 1103515245) 12345) 2147483648)
                   price (* price (+ 1 (/ (- (mod seed 1000) 480) 40000d0)))))))

(defparameter +watchlist+
  '(("EQNR.OL" 412.3d0 1) ("DNB.OL" 228.6d0 2) ("AAPL" 228.1d0 3) ("NHY.OL" 71.84d0 4)
    ("ORK.OL" 76.5d0 5 "2026-11-20"))
  "The shares on the watchlist: ticker, first price, the walk's seed and the
first day, 3 August 2026 unless given; ORK.OL's three months cross a new
year.")

(defun watchlist-prices (ticker)
  (destructuring-bind (start seed &optional (from "2026-08-03"))
      (rest (assoc ticker +watchlist+ :test #'string=))
    (made-up-prices 63 start :seed seed :from from)))

(defun watchlist-table ()
  (ui:table (:caption (tr "Watchlist") :caption-hidden t
             :columns (list (tr "Share")
                            (list (tr "Three months") :align :end)
                            (list (tr "Last") :align :end))
             :rows (loop for (ticker) in +watchlist+
                         for points = (watchlist-prices ticker)
                         collect (list ticker
                                       (ui:sparkline (:label ticker :points points :digits 2))
                                       (number-text (cdr (first (last points))) :digits 2)))
             :row-href (loop for (ticker) in +watchlist+
                             collect (format nil "/prices/~a" ticker)))))

(defun share-chart (ticker)
  (ui:line-chart (:id "price" :label ticker :digits 2 :points (watchlist-prices ticker))))

(define-page prices-page ("prices" :title "Prices" :icon :trending-up :policy :employee
                                   :width :wide)
    (method path form query)
  (declare (ignore form query))
  (let ((ticker (or (first path) "EQNR.OL")))
    (if (or (eq method :post) (rest path)
            (not (assoc ticker +watchlist+ :test #'string=)))
        (values 404 (tr "Prices") (list (ui:alert (:variant :warning
                                                   :title (tr "Page not found")))))
        (values 200 (tr "Prices")
                (list (ui:stack (:gap :lg)
                        (ui:card (:title ticker) (share-chart ticker))
                        (ui:card (:title (tr "Watchlist")) (watchlist-table))))))))
