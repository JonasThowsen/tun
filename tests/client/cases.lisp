;;;; cases.lisp -- switching over a closed set (spec/core.md 2.7), as
;;;; docs/client-api.md «Switching over a closed set» writes it: a module's
;;;; field, a member type of Tun's, and the client's own closed set of kinds.

(in-package #:test-client)

(defun order-status-variant (status)
  (ecase-of (order status) status         ; every status has its branch
    ("draft" :outline)
    (("quote_sent" "accepted") :info)
    (("confirmed" "picked_up" "returned" "ready_for_invoice") :warning)
    ("completed" :success)
    ("cancelled" :destructive)))

(defun refusal-heading (code)
  (case-of error-code code                 ; some kinds of refusal, and the rest
    (:not-found "Not found")
    (:forbidden "You do not have access to this")
    (otherwise "That did not work")))

(defstruct pickup place)
(defstruct shipment address)
(deftype delivery () '(or pickup shipment))

(defun delivery-text (delivery)
  (etypecase-of delivery delivery
    (pickup (format nil "Picked up at ~a" (pickup-place delivery)))
    (shipment (format nil "Sent to ~a" (shipment-address delivery)))))
