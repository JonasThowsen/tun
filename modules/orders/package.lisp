;;;; modules/orders/package.lisp -- the orders module: the order aggregate
;;;; (lines, pricing modes, logistics, statuses and locks), quotes, checklists,
;;;; bookings of rental equipment and consumable reservations.
;;;;
;;;; Seams a client (or a dependent module) may specialize on its application
;;;; class (published extension points, each with one purpose):
;;;;   ORDER-DISCOUNT              discount          the automatic discount of an order's subtotal (default 0)
;;;;   COMPUTE-ORDER-REQUIREMENTS  requirements      consumables an order needs (default none)
;;;;   BOOKING-WINDOW              booking_window    dates one booking blocks a unit (default the event date)
;;;;   ORDER-SUGGESTIONS           suggestions       upsell suggestions for an order (default none)
;;;;   ORDER-CHECKLIST-ITEMS       checklist_items   extra automatic checklist items (default none)
;;;;   ORDER-DEPARTMENTS           departments       the departments an order may name (default none)
;;;;   ORDER-DEPARTMENT-CHANGED    department_changed  reacts when an order's department is set or changes
;;;;   ORDER-CLOSURE-CHECK         closure_guard     may refuse completing, invoicing or cancelling an order

(defpackage #:tun.orders
  (:use #:cl #:tun.core #:tun.customers #:tun.catalog)
  (:local-nicknames (#:ui #:tun.ui))
  (:export #:order #:order-revision #:order-status #:order-customer-id #:order-event-date
           #:order-end-date #:order-delivery-address #:order-lines #:order-tags #:order-department #:order-open-questions
           #:order-price-mode #:order-catalog-total-minor #:order-subtotal-minor
           #:order-discount-minor
           #:order-adjustment-minor #:order-total-minor #:order-requirements #:order-created-at #:record-order-request #:aggregate-order-communication
           #:order-bookings #:order-logistics #:order-pickup #:order-return-record
           #:order-line #:order-line-id #:order-line-product-id #:order-line-quantity
           #:order-line-unit-price-minor #:order-line-line-total-minor
           #:order-line-line-effective-minor
           #:order-line-notes #:logistics-method-label
           #:requirement #:requirement-product-id #:requirement-quantity
           #:booking #:booking-order-id #:booking-product-id #:booking-quantity
           #:booking-from #:booking-to
           #:+final-statuses+ #:+locked-statuses+ #:+calendar-active-statuses+ #:status-label
           #:find-order #:order-customer #:order-final-p #:order-locked-p #:order-dateless-p
           #:order-period #:order-last-date #:order-requires-pickup-p #:touch-order #:check-order-not-locked
           #:refuse-locked-order #:order-line-choices #:requirement-article-id
           #:logistics-settled-p #:logistics-summary #:side-summary #:order-logistics-object
           #:order-discount #:compute-order-requirements #:booking-window #:order-suggestions
           #:order-checklist-items #:order-departments #:order-department-changed #:order-closure-check
           #:checklist-item #:checklist-item-order-id #:checklist-item-order-line-id #:checklist-item-origin
           #:checklist-item-source-key #:checklist-item-description #:checklist-item-category
           #:checklist-item-computed-quantity #:checklist-item-done-quantity #:checklist-item-done
           #:planned-item #:order-packed-p
           #:order-quote #:quote-for-order #:mask-quote-credentials #:order-quote-summary #:quote-expired
           #:orders-create #:orders-get #:orders-list #:orders-update #:orders-summary #:orders-send-quote
           #:orders-accept #:orders-confirm #:orders-complete #:orders-cancel
           #:orders-register-pickup #:orders-register-return #:orders-ready-for-invoice
           #:orders-reopen #:orders-reactivate #:orders-suggest
           #:quotes-get #:quotes-preview #:quotes-respond
           #:checklists-list #:checklists-sync #:checklists-mark #:checklists-add-manual #:checklists-delete
           #:availability-check
           #:plan #:plan-order-id #:plan-revision #:plan-status #:plan-lines #:plan-impact
           #:active-plan #:effective-plan-lines #:plan-totals #:consumption-applied-p
           #:orders-correct-plan #:plans-list #:plans-get #:plan-impacts-list))

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(define-module orders
  (:depends-on customers catalog inventory reviews)
  (:core ">= 2.0.0" "< 3.0")
  (:on-open repair-quote-receipts)
  (:documentation "Orders: quotes, pricing, logistics, statuses, checklists, bookings and reservations."))

;;; Statuses (README §2.1) and their groups.
(defparameter +statuses+
  '("draft" "quote_sent" "accepted" "confirmed" "picked_up" "returned" "ready_for_invoice" "completed" "cancelled"))
(defparameter +final-statuses+ '("completed" "cancelled")
  "Final statuses: orders_update refused (README §1.4).")
(defparameter +locked-statuses+ '("ready_for_invoice" "completed"))
(defparameter +not-started-statuses+ '("draft" "quote_sent" "accepted"))
(defparameter +active-statuses+ '("confirmed" "picked_up" "returned" "ready_for_invoice"))
(defparameter +closed-statuses+ '("cancelled" "completed"))
(defparameter +calendar-active-statuses+ '("draft" "quote_sent" "accepted" "confirmed"))

(defun refuse-locked-order ()
  "Refuse a change to a locked order with the lock message (README §2.3)."
  (fail :conflict "The order is locked (ready for invoice or completed). Reopen the order for editing first."))

(defun status-label (status)
  "The order STATUS as the calendar shows it, in capitals (README §2.1), in
the current language; an unknown status as it is."
  (cond ((string= status "draft") (tr "DRAFT"))
        ((string= status "quote_sent") (tr "QUOTE SENT"))
        ((string= status "accepted") (tr "ACCEPTED BY CUSTOMER"))
        ((string= status "confirmed") (tr "CONFIRMED"))
        ((string= status "picked_up") (tr "PICKED UP"))
        ((string= status "returned") (tr "RETURNED"))
        ((string= status "ready_for_invoice") (tr "SEND INVOICE"))
        ((string= status "cancelled") (tr "CANCELLED"))
        ((string= status "completed") (tr "COMPLETED"))
        (t status)))

(defun status-text (status)
  "The order STATUS as a message's argument: its label (spec/i18n.md 3.1)."
  (label "order" "status" status))
