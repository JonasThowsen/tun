;;;; modules/orders/stock.lisp -- what orders tell the inventory forecast and
;;;; the catalog's capacity guard (README §12.1, §12.2), and the stock
;;;; warnings on an order (§12.3).

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +committed-statuses+ '("bekreftet" "hentet" "returnert" "send_faktura" "fullført")
  "Orders whose demand the forecast counts by default (README §2.1, §12.1).")

;;; ------------------------------------------------------------------
;;; Seams answered for inventory and catalog

(defmethod tun.inventory:article-demand ((application orders-module) &key include-unconfirmed from)
  ;; Committed orders (and with INCLUDE-UNCONFIRMED the not-started ones)
  ;; with a date (FROM or later), whose consumption is not applied: their
  ;; active plan.  FROM keeps the completed history out of the query.
  (append (call-next-method)
          (loop for order in (select 'order :where `(:and (:in "status" ,(if include-unconfirmed
                                                                             (append +committed-statuses+ +not-started-statuses+)
                                                                             +committed-statuses+))
                                                          (:not-null "event_date")
                                                          ,@(and from `((:>= "event_date" ,from)))))
                unless (consumption-applied-p order)
                  append (loop for (article-id . quantity) in (plan-totals (effective-plan-lines order))
                               collect (list article-id (order-event-date order) quantity)))))

(defmethod tun.inventory:product-bookings-on ((application orders-module) product-id date)
  (let ((blocking (blocking-bookings product-id date)))
    (values (reduce #'+ blocking :key #'booking-quantity)
            (remove-duplicates (mapcar #'booking-order-id blocking) :test #'string= :from-end t))))

(defmethod product-booked-peak ((application orders-module) product)
  ;; The most units booked on one date by calendar-active orders (only
  ;; bekreftet ones hold bookings among them), cleaning windows included.
  (let* ((bookings (remove-if-not (lambda (b)
                                    (let ((order (fetch 'order (booking-order-id b))))
                                      (and order (member (order-status order) +calendar-active-statuses+
                                                         :test #'string=))))
                                  (select 'booking :where `(:= "product_id" ,(entity-id product)))))
         (peak 0))
    (dolist (b bookings (max peak (call-next-method)))
      (loop for date = (booking-from b) then (date-add-days date 1)
            while (date<= date (booking-to b))
            do (setf peak (max peak (loop for other in bookings
                                          when (and (date<= (booking-from other) date) (date<= date (booking-to other)))
                                            sum (booking-quantity other))))))))

;;; ------------------------------------------------------------------
;;; Stock warnings (README §12.3)

(defun stock-warnings (order)
  "shortage: an article whose balance on the event date, the balance minus the
committed demand targeted in [today, event_date], is negative counting this
order (even when it is not committed); not_in_stock: a choice-group
pick whose recipe has an article with no stock and no receipt since the
pick.  Warnings never block.  The demand is asked for once, and no per-day
series is built: the cost does not grow with the distance to the event
(README §12.3)."
  (let ((warnings '())
        (today (local-today))
        (date (order-event-date order))
        (active (and (entity-id order) (active-plan (entity-id order)))))
    (when (and date active (date<= today date) (plan-line-list active))
      (let* ((totals (plan-totals (plan-line-list active)))
             (own (if (member (order-status order) +committed-statuses+ :test #'string=) '() totals))
             (committed (make-hash-table :test 'equal)))
        (loop for (article-id demand-date quantity) in (tun.inventory:forecast-demand today)
              when (and (assoc article-id totals :test #'string=) (date<= today demand-date) (date<= demand-date date))
                do (incf (gethash article-id committed 0) quantity))
        (loop for (article-id . nil) in totals
              for article = (tun.inventory:find-article article-id)
              for balance = (- (tun.inventory:article-balance article)
                               (gethash article-id committed 0)
                               (or (cdr (assoc article-id own :test #'string=)) 0))
              when (minusp balance)
                do (push (jobj "kind" "shortage" "article_id" article-id
                               "name" (tun.inventory:article-name article)
                               "quantity" (quantity-json (- balance)) "date" date)
                         warnings))))
    (let ((seen '()))
      (dolist (line (order-lines order))
        (let ((since (order-line-choices-at line)))
          (dolist (key (if (hash-table-p (order-line-choices line)) (jkeys (order-line-choices line)) '()))
            (loop for recipe-id across (jget (order-line-choices line) key)
                  for recipe = (fetch 'recipe recipe-id)
                  when recipe
                    do (dolist (item (recipe-lines recipe))
                         (let ((article (tun.inventory:find-article (recipe-item-article-id item))))
                           (unless (or (member (entity-id article) seen :test #'string=)
                                       (plusp (tun.inventory:article-balance article))
                                       (and since (tun.inventory:received-since-p (entity-id article) since)))
                             (push (entity-id article) seen)
                             (push (jobj "kind" "not_in_stock" "article_id" (entity-id article)
                                         "name" (tun.inventory:article-name article)
                                         "quantity" (quantity-json (tun.inventory:article-balance article))
                                         "date" (or date :null))
                                   warnings)))))))))
    (nreverse warnings)))
