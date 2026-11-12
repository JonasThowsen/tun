;;;; modules/orders/publish.lisp -- upsell suggestions (README §13.1), the
;;;; module's screens, what it publishes to clients, and its seal.

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(define-operation orders-suggest ((id :type (id order) :required t :label "Order ID"))
    (:entity order :kind :read :title "Suggestions for the order"
     :description "Upsell suggestions for the order from the client's rules (product and reason). Changes nothing.")
  (let ((order (find-order id)))
    (jobj "items" (jarr (loop for (product reason) in (order-suggestions *application* order)
                              collect (jobj "product_id" (entity-id product) "name" (product-name product)
                                            "reason" reason))))))

(defmethod search-records ((application orders-module) query actor)
  ;; spec/ui.md 6.4: an order by its customer's name and its id, as its
  ;; customer would score, less 15, so the customer comes before it.
  (declare (ignore actor))
  (append (when (search-query-wants-p query "order")
            (let ((names (make-hash-table :test 'equal)))
              (dolist (customer (select 'customer))
                (setf (gethash (entity-id customer) names) (customer-name customer)))
              (flet ((customer-of (order) (or (gethash (order-customer-id order) names) "")))
                (search-entity query 'order
                               :kind "order" :label (tr "Order") :icon :shopping-cart
                               :title #'customer-of
                               :identifiers (lambda (order) (list (entity-id order)))
                               :texts (lambda (order) (list (order-delivery-address order)))
                               :meta (lambda (order)
                                       (list (label "order" "status" (order-status order))
                                             (and (order-event-date order)
                                                  (date-text (order-event-date order)))))
                               :href (lambda (order) (format nil "/orders/~a" (entity-id order)))
                               :score (lambda (score) (- score 15))))))
          (call-next-method)))

(tun.web:register-web-resource :path "/orders" :entity 'order :title "Orders" :icon :shopping-cart
                               :list-tool "orders_list" :create-tool "orders_create" :get-tool "orders_get"
                               :list-screen :order-list :detail-screen :order-detail :detail-key :order)

;;; What clients may use (the module's other exports are for the modules
;;; that depend on it).
(publish '(order order-revision order-status order-customer-id order-event-date order-end-date
           order-delivery-address order-lines order-tags order-department order-subtotal-minor
           order-discount-minor order-total-minor order-requirements order-bookings
           order-line order-line-id order-line-product-id order-line-quantity
           order-line-unit-price-minor order-line-line-total-minor
           requirement-product-id requirement-quantity
           find-order order-customer order-final-p order-dateless-p order-logistics
           order-discount compute-order-requirements booking-window order-suggestions
           order-checklist-items
           orders-create orders-get orders-list orders-update orders-send-quote
           orders-accept orders-confirm orders-complete orders-cancel availability-check
           quotes-respond order-quote-summary quote-expired orders-reactivate order-logistics-object order-open-questions
           plan orders-correct-plan plans-list plans-get plan-impacts-list))

(seal-module "orders")
