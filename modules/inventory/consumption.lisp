;;;; modules/inventory/consumption.lisp -- consumption of stock by orders
;;;; (README §6), as one synchronising command per order:
;;;;   {order_id, order_revision, effective_date, lines [(article, quantity)]}.
;;;; The newest applied command per order is remembered; an older one, or the
;;;; same revision with an earlier date, is a no-op; the same revision and
;;;; date with another payload is a conflict.  Otherwise the order's consumption
;;;; rows are replaced wholesale: every row is reversed (unless a recount came
;;;; after it: the count wins) and deleted, and new rows are written, which do
;;;; not deduct from an article recounted since the old row.
;;;;
;;;; "Consumption applied" for an order: at least one consumption row with its
;;;; order_id exists (README §6.1).  Orders are opaque ids here.

(in-package #:tun.inventory)

(declaim (optimize (safety 3) (debug 2)))

(define-entity consumption-command (:json-name "consumption_command" :label "Consumption command" :id-prefix "fbk"
                                    :table "consumption_commands" :internal t :unique (("order_id")))
  ((order-id :type id :input nil)
   (order-revision :type integer :input nil)
   (effective-date :type date :input nil)
   (fingerprint :type (string :max 64) :input nil)))

(defun order-consumption-rows (order-id)
  (select 'inventory-movement :where `(:and (:= "order_id" ,order-id) (:= "kind" "consumption"))))

(defun consumption-applied-p (order-id)
  (and (select-one 'inventory-movement :where `(:and (:= "order_id" ,order-id) (:= "kind" "consumption"))) t))

(defun later-recount-p (article-id revision)
  "True when ARTICLE-ID has a recount after ledger REVISION."
  (find-if (lambda (m) (> (inventory-movement-revision m) revision))
           (select 'inventory-movement :where `(:and (:= "article_id" ,article-id) (:= "kind" "recount")))))

(defun counted-since-recount-p (article-id)
  "True when ARTICLE-ID's latest recount is still what its balance rests on:
there is one, and no receipt, adjustment or opening with a higher revision
(README §6.4).  A consumption row a recount made not deduct stays recounted while
this holds: the sync that replaces it writes a row that does not deduct."
  (let ((recount (reduce #'max (select 'inventory-movement :where `(:and (:= "article_id" ,article-id)
                                                                         (:= "kind" "recount")))
                         :key #'inventory-movement-revision :initial-value 0)))
    (and (plusp recount)
         (not (select-one 'inventory-movement
                          :where `(:and (:= "article_id" ,article-id) (:in "kind" ("receipt" "adjustment" "opening"))
                                        (:> "revision" ,recount)))))))

(defun command-key< (revision-a date-a revision-b date-b)
  (or (< revision-a revision-b) (and (= revision-a revision-b) (string< date-a date-b))))

(defun sync-consumption (order-id order-revision effective-date expected)
  "Make ORDER-ID's consumption rows match EXPECTED, a list of (article-id .
quantity), as the command at ORDER-REVISION and EFFECTIVE-DATE (README §6).
insufficient_stock (a deducting row needs more than the balance) aborts the
caller's transaction, leaving the prior consumption intact."
  (let* ((totals (let ((table '()))
                   (loop for (article-id . quantity) in expected
                         do (let ((cell (assoc article-id table :test #'string=)))
                              (if cell (incf (cdr cell) quantity) (push (cons article-id quantity) table))))
                   (sort (remove-if-not #'plusp table :key #'cdr) #'string< :key #'car)))
         (fingerprint (canonical-json-hash (jarr (mapcar (lambda (e) (jarr (list (car e) (quantity-json (cdr e)))))
                                                         totals))))
         (last (select-one 'consumption-command :where `(:= "order_id" ,order-id))))
    ;; The no-op and conflict rules.
    (when (and last (consumption-command-order-revision last))
      (let ((last-revision (consumption-command-order-revision last))
            (last-date (consumption-command-effective-date last)))
        (when (command-key< order-revision effective-date last-revision last-date)
          (return-from sync-consumption nil))
        (when (and (= order-revision last-revision) (string= effective-date last-date))
          (if (string= fingerprint (consumption-command-fingerprint last))
              (return-from sync-consumption nil)
              (fail :conflict "Stock consumption is already recorded for this version")))))
    (let* ((rows (sort (order-consumption-rows order-id) #'string< :key #'inventory-movement-article-id))
           (recounted '()))
      ;; Lock every affected article in id order.
      (dolist (id (sort (remove-duplicates (append (mapcar #'inventory-movement-article-id rows) (mapcar #'car totals))
                                           :test #'string=)
                        #'string<))
        (lock-row 'article id))
      ;; Reverse and delete the order's rows; a later recount wins, and a row
      ;; a recount already made not deduct stays recounted (README §6.4).
      (dolist (row rows)
        (let* ((article (find-article (inventory-movement-article-id row)))
               (later (later-recount-p (entity-id article) (inventory-movement-revision row))))
          (when (or later
                    (and (not (inventory-movement-balance-updated row))
                         (counted-since-recount-p (entity-id article))))
            (pushnew (entity-id article) recounted :test #'string=))
          (when (and (inventory-movement-balance-updated row) (not later))
            (setf (article-balance article) (+ (article-balance article) (inventory-movement-quantity row)))
            (save article))
          (delete-entity row)))
      ;; New rows, in article-id order.
      (loop for (article-id . quantity) in totals
            for article = (find-article article-id)
            do (if (member article-id recounted :test #'string=)
                   (ledger-row article "consumption" quantity :balance-updated nil
                                                              :order-id order-id
                                                              :reason (tr "Reserved for order (balance adjusted by hand)"))
                   (progn
                     (when (> quantity (article-balance article))
                       (insufficient article quantity))
                     (ledger-row article "consumption" quantity :balance (- (article-balance article) quantity)
                                                            :order-id order-id :reason (tr "Reserved for order")))))
      ;; What was given back stays within the bound (README §3.3).
      (dolist (row rows)
        (check-balance-bound (article-balance (find-article (inventory-movement-article-id row)))))
      (if last
          (progn (setf (consumption-command-order-revision last) order-revision
                       (consumption-command-effective-date last) effective-date
                       (consumption-command-fingerprint last) fingerprint)
                 (save last))
          (insert (make-instance 'consumption-command :order-id order-id :order-revision order-revision
                                                      :effective-date effective-date :fingerprint fingerprint)))
      t)))
