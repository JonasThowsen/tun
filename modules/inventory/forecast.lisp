;;;; modules/inventory/forecast.lisp -- the forecast (README §7), the
;;;; product-keyed shortages from it (§8), purchase suggestions (§9) and the
;;;; availability grid (§10).
;;;;
;;;; Inventory knows no order status (README §1): it asks two seams that
;;;; the orders module answers:
;;;;   ARTICLE-DEMAND       article_demand   (article date quantity) of the orders that count as demand
;;;;   PRODUCT-BOOKINGS-ON  bookings_on      units of a rental product booked on a date, and by which orders

(in-package #:tun.inventory)

(declaim (optimize (safety 3) (debug 2)))

(defgeneric article-demand (application &key include-unconfirmed from)
  (:method-combination traced-protocol)
  (:documentation "The demand the forecast subtracts: a list of (article-id date quantity),
from orders that are committed (and, with INCLUDE-UNCONFIRMED, not yet
started) and whose consumption is not applied.  DATE is the order's
event date; with FROM, only orders dated FROM or later (no forecast from
FROM looks further back, so history is not read).")
  (:method ((application inventory-module) &key include-unconfirmed from)
    (declare (ignore include-unconfirmed from))
    '()))

(defgeneric product-bookings-on (application product-id date)
  (:method-combination traced-protocol)
  (:documentation "Values the units of rental PRODUCT-ID that bookings block on DATE
(cleaning windows included, by orders' point semantics) and the ids of the
orders that hold them.")
  (:method ((application inventory-module) product-id date)
    (declare (ignore product-id date))
    (values 0 '())))

(register-extension-protocol 'article-demand "rule" :point "article_demand"
                             :description "The orders' demand on stock articles, by event date.")
(register-extension-protocol 'product-bookings-on "rule" :point "bookings_on"
                             :description "Units of a rental product booked on a date, and the orders.")

(defparameter +max-window-days+ 366)

(defun check-window (from to)
  (unless (and (date<= from to) (<= (round (- (parse-date to) (parse-date from)) 86400) +max-window-days+))
    (fail :invalid-input "Invalid period: the to date must be after the from date and at most ~d days later"
          +max-window-days+)))

(defun forecast-demand (from &key include-unconfirmed)
  "The ARTICLE-DEMAND a forecast from FROM uses: orders dated from the earlier
of FROM and today (demand before both is never targeted).  One request that
forecasts several articles asks once and passes it as FORECAST's DEMAND."
  (article-demand *application* :include-unconfirmed include-unconfirmed
                                :from (let ((today (local-today))) (if (date< from today) from today))))

(defun forecast (from to &key article-id include-unconfirmed (demand nil demand-p))
  "Per article, the balance day by day over FROM..TO (README §7): a list of
plists (:article :start :end :days ((date demand balance historical)...)
:status), articles by name.  Demand is targeted at its event date, or at
FROM when that date lies between today and FROM; days before today are
historical and subtract nothing.  DEMAND: the FORECAST-DEMAND for FROM
(and INCLUDE-UNCONFIRMED), when the caller already has it."
  (let ((today (local-today))
        (entries (if demand-p demand (forecast-demand from :include-unconfirmed include-unconfirmed)))
        (demand (make-hash-table :test 'equal)))
    (loop for (id date quantity) in entries
          for target = (cond ((and (date<= from date) (date<= date to)) date)
                             ((and (date< date from) (date<= today date)) from))
          when (and target (or (null article-id) (string= id article-id)))
            do (let ((days (or (gethash id demand) (setf (gethash id demand) (make-hash-table :test 'equal)))))
                 (incf (gethash target days 0) quantity)))
    (let ((articles (stable-sort (if article-id (list (find-article article-id)) (select 'article))
                                 #'string-lessp :key #'article-name)))
      (loop for article in articles
            for days = (gethash (entity-id article) demand)
            unless (and (not (article-active article)) (null days))
              collect (let ((balance (article-balance article)) (total 0) (shortage nil) (watch nil) (rows '()))
                        (loop for date = from then (date-add-days date 1)
                              while (date<= date to)
                              do (let ((need (if days (gethash date days 0) 0))
                                       (historical (date< date today)))
                                   (incf total need)
                                   (unless historical
                                     (decf balance need)
                                     (when (minusp balance) (setf shortage t))
                                     (when (< balance need) (setf watch t)))
                                   (push (list date need balance historical) rows)))
                        (list :article article :start (article-balance article) :end balance
                              :days (nreverse rows)
                              :status (cond ((zerop total) "none")
                                            (shortage "shortage")
                                            ((or (zerop balance) watch) "watch")
                                            (t "balanced"))))))))

(defun forecast-json (entry)
  (let ((article (getf entry :article)))
    (jobj "article_id" (entity-id article) "name" (article-name article) "unit" (article-unit article)
          "start_balance" (quantity-json (getf entry :start)) "end_balance" (quantity-json (getf entry :end))
          "days" (jarr (loop for (date need balance historical) in (getf entry :days)
                             collect (jobj "date" date "demand" (quantity-json need)
                                           "balance" (quantity-json balance) "historical" (json-bool historical))))
          "status" (getf entry :status))))

(defun purchase-suggestions (&optional (days 30))
  "README §9: for every article short within today..today+DAYS, what to
order, rounded up to whole packages, and by when (lead days before the
first shortage), sorted by that date then name.  JSON objects."
  (let* ((today (local-today))
         (rows (loop for entry in (forecast today (date-add-days today days))
                     when (string= (getf entry :status) "shortage")
                       collect (let* ((article (getf entry :article))
                                      (balances (mapcar #'third (getf entry :days)))
                                      (need (- (reduce #'min balances)))
                                      (minimum (article-min-level article))
                                      (need (if (and minimum (< (getf entry :end) minimum))
                                                (max need (- minimum (getf entry :end)))
                                                need))
                                      (first-short (first (find-if (lambda (d) (minusp (third d))) (getf entry :days))))
                                      (size (article-package-size article))
                                      (packages (and size (ceiling need size)))
                                      (order-by (date-add-days first-short (- (or (article-lead-days article) 0)))))
                                 (list order-by (article-name article)
                                       (jobj "article_id" (entity-id article) "name" (article-name article)
                                             "unit" (article-unit article)
                                             "shortage_quantity" (quantity-json need)
                                             "packages" (or packages :null)
                                             "order_quantity" (quantity-json (if size (* packages size) need))
                                             "supplier" (or (article-supplier article) (empty-supplier))
                                             "first_shortage_date" first-short
                                             "order_by" order-by))))))
    (mapcar #'third (stable-sort rows (lambda (a b) (or (string< (first a) (first b))
                                                        (and (string= (first a) (first b))
                                                             (string-lessp (second a) (second b)))))))))

;;; ------------------------------------------------------------------
;;; Operations

(define-operation inventory-forecast ((from :type date :required t :label "From date")
                                      (to :type date :required t :label "To date")
                                      (article-id :type (id article) :label "Article ID")
                                      (include-unconfirmed :type boolean :label "Include unconfirmed"
                                                           :description "Adds drafts, quotes sent and accepted orders as expected demand."))
    (:entity article :kind :read :title "Stock forecast"
     :description "The balance day by day: confirmed demand (and with include_unconfirmed the expected) subtracted on the event date; demand before the from date, but not before today, lands on from. Status none, balanced, watch or shortage.")
  (check-window from to)
  (when article-id (find-article article-id))
  (jobj "articles" (jarr (mapcar #'forecast-json
                                 (forecast from to :article-id article-id :include-unconfirmed include-unconfirmed)))))

(define-operation inventory-shortages ((before-date :type date :required t :label "Before date"))
    (:entity inventory-movement :kind :read :title "Shortage list"
     :description "Stock articles short in the forecast of confirmed orders from today up to and including the date: demand, balance and how much is short.")
  (let ((today (local-today))
        (items '()))
    (when (date<= today before-date)
      (dolist (entry (forecast today before-date))
        (when (string= (getf entry :status) "shortage")
          (let* ((article (getf entry :article))
                 (needed (reduce #'+ (getf entry :days) :key #'second))
                 (shortfall (- needed (article-balance article))))
            (when (plusp shortfall)
              (push (jobj "product_id" (article-key-product article) "article_id" (entity-id article)
                          "name" (article-name article) "needed" (quantity-json needed)
                          "on_hand" (quantity-json (article-balance article))
                          "shortfall" (quantity-json shortfall) "before_date" before-date)
                    items))))))
    (jobj "items" (jarr (sort items #'string< :key (lambda (i) (jget i "name")))))))

(define-operation inventory-purchase-suggestions ((days :type (integer :min 1 :max 366) :default 30
                                                       :label "Days"))
    (:entity article :kind :read :title "Purchase suggestions"
     :description "For each article short in the coming days: how much is short (at least up to the minimum), whole packages to order, the supplier and the last day to order (the lead time before the first shortage).")
  (jobj "items" (jarr (purchase-suggestions days))))

(define-operation inventory-availability-grid ((from :type date :required t :label "From date")
                                               (to :type date :required t :label "To date")
                                               (product-ids :type (list-of (id product) :min-items 1 :max-items 6)
                                                            :required t :label "Products"
                                                            :description "1–6 products."))
    (:entity article :kind :read :title "Availability overview"
     :description "Per product and date: the total, what is booked (cleaning days included), what is available (may be negative) and the orders that book it.")
  (check-window from to)
  (jobj "items"
        (jarr (loop for product-id in product-ids
                    for product = (find-product product-id)
                    collect (jobj "product_id" product-id "name" (product-name product)
                                  "days" (jarr (loop for date = from then (date-add-days date 1)
                                                     while (date<= date to)
                                                     collect (multiple-value-bind (booked orders)
                                                                 (product-bookings-on *application* product-id date)
                                                               (jobj "date" date
                                                                     "available" (- (product-units-owned product) booked)
                                                                     "total" (product-units-owned product)
                                                                     "booked" booked
                                                                     "order_ids" (jarr orders))))))))))
