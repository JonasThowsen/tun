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
           #:order-price-mode #:order-catalog-total-ore #:order-subtotal-ore #:order-discount-ore
           #:order-adjustment-ore #:order-total-ore #:order-requirements #:order-created-at #:record-order-request #:aggregate-order-communication
           #:order-bookings #:order-logistics #:order-pickup #:order-return-record
           #:order-line #:order-line-id #:order-line-product-id #:order-line-quantity
           #:order-line-unit-price-ore #:order-line-line-total-ore #:order-line-line-effective-ore
           #:order-line-notes
           #:requirement #:requirement-product-id #:requirement-quantity
           #:booking #:booking-order-id #:booking-product-id #:booking-quantity
           #:booking-from #:booking-to
           #:+final-statuses+ #:+locked-statuses+ #:+calendar-active-statuses+ #:status-label
           #:find-order #:order-customer #:order-final-p #:order-locked-p #:order-dateless-p
           #:order-period #:order-last-date #:order-requires-pickup-p #:touch-order #:check-order-not-locked
           #:+lock-message+ #:order-line-choices #:requirement-article-id
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
  (:core ">= 1.2.0" "< 2.0")
  (:on-open repair-quote-receipts)
  (:documentation "Orders: quotes, pricing, logistics, statuses, checklists, bookings and reservations."))

;;; Statuses (README §2.1) and their groups.
(defparameter +statuses+
  '("utkast" "tilbud_sendt" "akseptert" "bekreftet" "hentet" "returnert" "send_faktura" "fullført" "avbrutt"))
(defparameter +status-labels+
  '(("utkast" . "UTKAST") ("tilbud_sendt" . "TILBUD SENDT") ("akseptert" . "AKSEPTERT AV KUNDE")
    ("bekreftet" . "BEKREFTET") ("hentet" . "HENTET") ("returnert" . "RETURNERT")
    ("send_faktura" . "SEND FAKTURA") ("avbrutt" . "AVLYST") ("fullført" . "FERDIG")))
(defparameter +final-statuses+ '("fullført" "avbrutt")
  "Final statuses: orders_update refused (README §1.4).")
(defparameter +locked-statuses+ '("send_faktura" "fullført"))
(defparameter +not-started-statuses+ '("utkast" "tilbud_sendt" "akseptert"))
(defparameter +active-statuses+ '("bekreftet" "hentet" "returnert" "send_faktura"))
(defparameter +closed-statuses+ '("avbrutt" "fullført"))
(defparameter +calendar-active-statuses+ '("utkast" "tilbud_sendt" "akseptert" "bekreftet"))

(defparameter +lock-message+
  "Ordren er låst (send faktura eller fullført). Åpne ordren for redigering først.")

(defun status-label (status)
  (or (cdr (assoc status +status-labels+ :test #'string=)) status))
