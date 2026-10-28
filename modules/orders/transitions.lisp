;;;; modules/orders/transitions.lisp -- the order status machine (README §2.2)
;;;; and its locks (§2.3).  Every transition takes an optional revision (a
;;;; stale one is conflict); every other (from, to) pair is
;;;; invalid_transition and nothing is stored.

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defun load-for-transition (id revision &key lock)
  "The order ID, checked against REVISION and, with LOCK, refused when locked."
  (let ((order (find-order id)))
    (check-revision order revision)
    (when lock (check-order-not-locked order))
    order))

(defun close-guard (order tool)
  "Completing, invoicing readiness and cancelling may be refused by a seam
(staffing: a running work session)."
  (order-closure-check *application* order tool))

(defun actor-admin-p () (eq :admin (actor-role *actor*)))

;;; ------------------------------------------------------------------
;;; Quote, acceptance, confirmation

(define-operation orders-send-quote ((id :type (id order) :required t :label "Order ID")
                                     (revision :type integer :label "Revision"))
    (:entity order :kind :transition :title "Send the quote"
     :description "draft or quote_sent → quote_sent. Creates the quote (revision 1) or issues it again (revision + 1, the same code), and sends it to the customer. Can be sent without a date.")
  ;; Allowed only from draft and quote_sent, never locked: any other status
  ;; is invalid_transition (the lock message is for what a locked order allows).
  (let ((order (load-for-transition id revision))
        (customer nil))
    (transition order '("draft" "quote_sent") "quote_sent")
    (setf customer (order-customer order))
    (when (blank-p (customer-email customer))
      (fail :invalid-transition "The customer has no email address; the quote cannot be sent"))
    (issue-quote order customer)
    (setf (order-accepted-snapshot-stale order) nil)
    (save order)
    ;; Through the kernel's messaging port: nothing is sent without messaging.
    (notify "quote" :order order :customer customer)
    order))

(defun accept-order (order)
  "quote_sent -> accepted, recording the answer on the quote."
  (transition order '("quote_sent") "accepted")
  (let ((quote (quote-for-order (entity-id order))))
    (when quote
      (when (quote-stale-p quote order) (setf (order-accepted-snapshot-stale order) t))
      (setf (order-quote-status quote) "accepted"
            (order-quote-responded-at quote) (now))
      (save quote)))
  order)

(define-operation orders-accept ((id :type (id order) :required t :label "Order ID")
                                 (revision :type integer :label "Revision"))
    (:entity order :kind :transition :title "Accept the quote"
     :description "quote_sent → accepted: the customer has accepted the quote (registered by an employee). The quote is marked accepted.")
  (let ((order (load-for-transition id revision)))
    (accept-order order)
    (save order)))

(defun confirm-summary ()
  (let* ((order (find-order (input-value :id)))
         (customer (order-customer order)))
    (tr "Confirm order ~a for ~a, event ~a, total ~a. Equipment is booked and consumables reserved."
        (entity-id order) (customer-name customer)
        (if (order-event-date order) (date-text (order-event-date order)) (tr "(no date)"))
        (money-text (order-total-minor order)))))

(define-operation orders-confirm ((id :type (id order) :required t :label "Order ID")
                                  (revision :type integer :label "Revision"))
    (:entity order :kind :transition :confirm t :destructive t :title "Confirm the order"
     :summary confirm-summary
     :description "accepted → confirmed. Needs an event date; books the rental equipment (unavailable when capacity is short), reserves consumables and schedules the customer's workflows. Needs confirmation.")
  (let ((order (load-for-transition id revision)))
    ;; The active plan is reserved (README §10.1); a catalog change reaches the order
    ;; through catalog_change, not through confirmation.
    (transition order '("accepted") "confirmed")
    (book-order order)
    (sync-reservations order)
    (setf (order-accepted-snapshot-stale order) nil)
    (save order)))

;;; ------------------------------------------------------------------
;;; Pickup, return, invoicing readiness

(defun check-requires-pickup (order)
  (unless (order-requires-pickup-p order)
    (fail :invalid-transition "pickup and return apply only to orders with rental products")))

(defun handover-record (at &rest keys-and-values)
  (apply #'jobj "at" (format-rfc3339 (or at (now))) (append keys-and-values (list "by" (actor-string *actor*)))))

(define-operation orders-register-pickup ((id :type (id order) :required t :label "Order ID")
                                          (condition :type (string :min 1 :max 500) :required t :label "Condition"
                                                     :description "The equipment's condition at pickup.")
                                          (at :type timestamp :label "Time" :description "Default: now.")
                                          (revision :type integer :label "Revision"))
    (:entity order :kind :transition :title "Register the pickup"
     :description "confirmed → picked_up: the rental equipment is picked up. Only orders with rental products. Releases the bookings and reservations and takes the active requirement plan's consumption from stock (insufficient_stock aborts).")
  (let ((order (load-for-transition id revision :lock t)))
    (when (string= (order-status order) "confirmed") (check-requires-pickup order))
    (transition order '("confirmed") "picked_up")
    ;; A new pickup starts a new rental: an earlier cycle's return is history.
    (setf (order-pickup order) (handover-record at "condition" condition)
          (order-return-record order) nil)
    ;; The machine is out: no booking, and no reservation either (only
    ;; confirmed reserves; README §10.1).  The consumables go with it:
    ;; the active plan is consumed now (README §10.2; insufficient_stock
    ;; aborts the pickup).
    (release-bookings order)
    (consume order)
    (sync-reservations order)
    (save order)))

(define-operation orders-register-return ((id :type (id order) :required t :label "Order ID")
                                          (condition :type (string :min 1 :max 500) :required t :label "Condition")
                                          (damages :type (string :max 2000) :label "Damages")
                                          (fee-minor :type (money :min 0 :max 9007199254740991) :label "Fee")
                                          (at :type timestamp :label "Time" :description "Default: now.")
                                          (revision :type integer :label "Revision"))
    (:entity order :kind :transition :title "Register the return"
     :description "picked_up → returned: the rental equipment is back, with its condition, any damages and a fee.")
  (let ((order (load-for-transition id revision :lock t)))
    (check-requires-pickup order)
    (transition order '("picked_up") "returned")
    (setf (order-return-record order)
          (handover-record at "condition" condition "damages" (or damages :null) "fee_minor" (or fee-minor 0)))
    (save order)))

(define-operation orders-ready-for-invoice ((id :type (id order) :required t :label "Order ID")
                                            (force :type boolean :label "Force (admin)"
                                                   :description "Invoice a rental before its return is registered; needs an admin and a reason.")
                                            (reason :type (string :max 500) :label "Reason")
                                            (revision :type integer :label "Revision"))
    (:entity order :kind :transition :title "Ready for invoicing"
     :description "confirmed or returned → ready_for_invoice (with force also from picked_up). A rental order needs a registered return, unless an admin forces it with a reason. Locks the order and releases the bookings.")
  (let ((order (load-for-transition id revision)))
    (when (and force (not (actor-admin-p)))
      (reject :forbidden "Only an admin can force invoicing"))
    ;; From picked_up only by force: without it the missing return is the refusal below.
    (transition order '("confirmed" "returned" "picked_up") "ready_for_invoice")
    (close-guard order "orders_ready_for_invoice")
    (when (and (order-requires-pickup-p order) (null (order-return-record order)))
      (cond ((not force)
             (fail :invalid-transition "cannot invoice before the return is registered; a rental order needs its return before the invoice"))
            ((blank-p reason)
             (fail :invalid-input "A reason is required to force invoicing before the return"))
            (t (audit-as :reason (trim reason)))))
    (release-bookings order)
    ;; Consumed at the first of pickup, invoicing readiness and completion (§10.2).
    (consume order)
    (sync-reservations order)
    (save order)))

;;; ------------------------------------------------------------------
;;; Completion and cancellation

(define-operation orders-complete ((id :type (id order) :required t :label "Order ID")
                                   (revision :type integer :label "Revision"))
    (:entity order :kind :transition :title "Complete the order"
     :description "confirmed or ready_for_invoice → completed. Takes the reserved consumption from stock (insufficient_stock aborts everything), adds one to the customer's completed orders and locks the order.")
  (let ((order (load-for-transition id revision)))
    (transition order '("confirmed" "ready_for_invoice") "completed")
    (close-guard order "orders_complete")
    ;; Completion's ledger effects, once, from the active plan (README
    ;; §10.2): consumed at the first of pickup, invoicing readiness and
    ;; completion, so from ready_for_invoice nothing more.
    (consume order)
    (sync-reservations order)
    (record-completed-order (order-customer-id order))
    (save order)))

(defun cancel-summary ()
  (let ((order (find-order (input-value :id))))
    (tr "Cancel order ~a (status ~a). Bookings and reservations are released, and planned workflows cancelled."
        (entity-id order) (status-text (order-status order)))))

(define-operation orders-cancel ((id :type (id order) :required t :label "Order ID")
                                 (revision :type integer :label "Revision"))
    (:entity order :kind :transition :confirm t :destructive t :title "Cancel the order"
     :summary cancel-summary
     :description "draft, quote_sent, accepted, confirmed or ready_for_invoice → cancelled. Releases bookings and reservations and cancels planned workflows. Needs confirmation.")
  (let ((order (load-for-transition id revision)))
    (transition order '("draft" "quote_sent" "accepted" "confirmed" "ready_for_invoice")
                "cancelled")
    (close-guard order "orders_cancel")
    (release-bookings order)
    ;; A consumed order's consumption is reversed (a later recount wins).
    (reverse-consumption order)
    (sync-reservations order)
    (tun.workflows:cancel-workflows id)
    (save order)))

;;; ------------------------------------------------------------------
;;; Reopening and reactivation

(defun reopen-summary ()
  (let ((order (find-order (input-value :id))))
    (tr "Reopen order ~a (status ~a) for editing: it becomes confirmed, the equipment is booked again and the checklist reset."
        (entity-id order) (status-text (order-status order)))))

(define-operation orders-reopen ((id :type (id order) :required t :label "Order ID")
                                 (revision :type integer :label "Revision"))
    (:entity order :kind :transition :confirm t :destructive t :policy :admin :title "Reopen the order"
     :summary reopen-summary
     :description "ready_for_invoice or completed → confirmed (admin). Unlocks, books the equipment again (unavailable if the capacity is gone), reserves the consumption again and resets the checklist. Consumption taken from stock is not put back. From completed, the customer's completed orders are counted down again.")
  (let* ((order (load-for-transition id revision))
         (was-completed (string= (order-status order) "completed")))
    (transition order '("ready_for_invoice" "completed") "confirmed")
    ;; Completion counts once per order: the next orders_complete counts it again.
    (when was-completed
      (record-reopened-order (order-customer-id order)))
    (book-order order)
    ;; Reserved again unless consumed (reopen from completed does not reverse it).
    (sync-reservations order)
    (reset-checklist order)
    (save order)))

(define-operation orders-reactivate ((id :type (id order) :required t :label "Order ID")
                                     (revision :type integer :label "Revision"))
    (:entity order :kind :transition :title "Resume as a draft"
     :description "cancelled, accepted or confirmed → draft. Releases bookings and reservations, cancels planned workflows, and a quote awaiting an answer is marked declined.")
  (let ((order (load-for-transition id revision)))
    (transition order '("cancelled" "accepted" "confirmed") "draft")
    (release-bookings order)
    ;; A consumed order is editable again: its consumption is reversed (§10.2).
    (reverse-consumption order)
    (sync-reservations order)
    (tun.workflows:cancel-workflows id)
    (let ((quote (quote-for-order id)))
      (when (and quote (string= (order-quote-status quote) "awaiting_response"))
        (setf (order-quote-status quote) "declined"
              (order-quote-responded-at quote) (now))
        (save quote)))
    (save order)))
