;;;; modules/invoicing/invoicing.lisp -- the invoicing module: invoices copied
;;;; from orders, sent through the kernel's accounting port.

(defpackage #:tun.invoicing
  (:use #:cl #:tun.core #:tun.customers #:tun.catalog #:tun.orders)
  (:export #:invoice #:invoice-order-id #:invoice-status #:invoice-customer #:invoice-lines
           #:invoice-subtotal-minor #:invoice-discount-minor #:invoice-total-minor
           #:invoice-external-ref
           #:invoice-created-at #:invoice-sent-at
           #:invoice-line #:find-invoice #:invoice-for-order #:create-invoice-from-order
           #:invoices-create-from-order #:invoices-get #:invoices-list #:invoices-send
           #:reconcile-send-intents))

(in-package #:tun.invoicing)

(declaim (optimize (safety 3) (debug 2)))

(define-module invoicing
  (:depends-on orders)
  (:core ">= 2.0.0" "< 3.0")
  ;; Sends whose outcome was never recorded are reconciled before any retry.
  (:on-open reconcile-send-intents)
  (:documentation "Invoicing: invoices from orders, sent through the accounting port."))

(define-entity invoice-line (:embedded t :json-name "invoice_line" :label "Invoice line")
  ((description :type (string :max 500) :input nil :label "Description")
   (quantity :type integer :input nil :label "Quantity")
   (unit-price-minor :type money :input nil :label "Unit price")
   (line-total-minor :type money :input nil :label "Line total")
   (line-effective-minor :type money :input nil :label "Line total after price mode")
   (line-adjustment-minor :type money :input nil :label "Line adjustment")))

(define-entity invoice (:label "Invoice" :id-prefix "fak" :table "invoices"
                        :unique (("order_id")) :indexes (("status")))
  ((order-id :type (id order) :required t :label "Order")
   (status :type (enum "draft" "sent") :input nil :initform "draft" :label "Status")
   (customer :type json :input nil :label "Customer"
             :description "A copy of the customer's details when the invoice was made.")
   (lines :type (list-of invoice-line) :input nil :label "Lines")
   (subtotal-minor :type money :input nil :label "Subtotal before discount")
   (discount-minor :type money :input nil :label "Discount")
   (adjustment-minor :type money :input nil :label "Adjustment")
   (total-minor :type money :input nil :label "Total")
   (external-ref :type (string :max 200) :input nil :label "External reference")
   (created-at :type timestamp :input nil :label "Created")
   (sent-at :type timestamp :input nil :label "Sent")))

(define-entity send-intent (:json-name "send_intent" :label "Send intent" :id-prefix "int"
                            :table "invoice_send_intents" :internal t :unique (("invoice_id")))
  ((invoice-id :type id :input nil)
   (intent-id :type (string :max 200) :input nil)
   (status :type (enum "pending" "done") :input nil :initform "pending")
   (external-ref :type (string :max 200) :input nil)
   (created-at :type timestamp :input nil)))

(defun find-invoice (id) (fetch! 'invoice id))

(defun invoice-for-order (order-id)
  (select-one 'invoice :where `(:= "order_id" ,order-id)))

(defun customer-snapshot (customer)
  "Who the invoice is for: core's name and email plus the client's own input
fields (its customer classification, e.g. kind and org_number).  Core's
free-text fields (phone, notes) stay off invoices and the accounting port."
  (let ((object (jobj)))
    (dolist (field (entity-input-fields (class-of customer)) object)
      (when (or (member (field-json-name field) '("name" "email") :test #'string=)
                (eq (field-source field) :client))
        (setf (gethash (field-json-name field) object)
              (type->json (field-type field) (field-value customer field)))))))

(defun create-invoice-from-order (order)
  "Snapshot ORDER into a new draft invoice. conflict when one exists."
  ;; Confirmed or later, not cancelled (README §3).
  (unless (member (order-status order) '("confirmed" "picked_up" "returned" "ready_for_invoice" "completed") :test #'string=)
    (fail :invalid-transition "The order is ~a; an invoice needs a confirmed order"
          (label "order" "status" (order-status order))))
  (when (invoice-for-order (entity-id order))
    (fail :conflict "Order ~a has already been invoiced" (entity-id order)))
  (insert (make-instance 'invoice
                         :order-id (entity-id order)
                         :customer (customer-snapshot (order-customer order))
                         :lines (mapcar (lambda (line)
                                          (make-instance 'invoice-line
                                                         :description (product-name (find-product (order-line-product-id line)))
                                                         :quantity (order-line-quantity line)
                                                         :unit-price-minor (order-line-unit-price-minor line)
                                                         :line-total-minor (order-line-line-total-minor line)
                                                         :line-effective-minor (or (order-line-line-effective-minor line)
                                                                                 (order-line-line-total-minor line))
                                                         :line-adjustment-minor (- (or (order-line-line-effective-minor line)
                                                                                     (order-line-line-total-minor line))
                                                                                 (order-line-line-total-minor line))))
                                        (order-lines order))
                         :subtotal-minor (order-subtotal-minor order)
                         :discount-minor (order-discount-minor order)
                         :adjustment-minor (or (order-adjustment-minor order) (- (order-discount-minor order)))
                         :total-minor (order-total-minor order))))

(define-operation invoices-create-from-order ((order-id :type (id order) :required t :label "Order ID"))
    (:entity invoice :kind :create :title "Create an invoice"
             :description "Makes a draft invoice, a copy of a confirmed or completed order. A second
invoice for the same order is conflict.")
  (create-invoice-from-order (find-order order-id)))

(define-operation invoices-get ((id :type (id invoice) :required t :label "Invoice ID"))
    (:entity invoice :kind :read :title "Get an invoice" :description "Gets one invoice.")
  (find-invoice id))

(define-operation invoices-list ((order-id :type (id order) :label "Order ID")
                                 (status :type (enum "draft" "sent") :label "Status")
                                 (limit :type (integer :min 1 :max 100) :default 20 :label "Limit"))
    (:entity invoice :kind :read :title "List invoices" :description "Lists invoices.")
  (let ((where (remove nil (list (and order-id `(:= "order_id" ,order-id))
                                 (and status `(:= "status" ,status))))))
    (page (select 'invoice :where (and where `(:and ,@where)) :limit (1+ limit)) limit)))

(defun send-summary ()
  (let ((invoice (find-invoice (input-value :id))))
    (tr "Send invoice ~a (order ~a, total ~a) to the accounting system and the customer."
        (entity-id invoice) (invoice-order-id invoice) (money-text (invoice-total-minor invoice)))))

(defvar *sending* (make-hash-table :test 'equal) "Invoice ids being sent by this process.")
(defvar *sending-lock* (sb-thread:make-mutex :name "invoices being sent"))

(defun claim-send (id)
  "Mark invoice ID as being sent; conflict if another call in this process is
sending it. Released when the send finishes or its transaction rolls back."
  (sb-thread:with-mutex (*sending-lock*)
    (when (gethash id *sending*)
      (fail :conflict "The invoice ~a is being sent" id))
    (setf (gethash id *sending*) t))
  (on-rollback (lambda () (release-send id))))

(defun release-send (id)
  (sb-thread:with-mutex (*sending-lock*) (remhash id *sending*)))

(defun accounting-unavailable (condition)
  "Refuse the send: the accounting port failed with CONDITION."
  (fail :unavailable
        "The accounting system did not answer (~a); the invoice was not sent, try again"
        condition))

(defun finish-send (id intent-id)
  "Outside any transaction: call the accounting port for the committed intent,
then record the outcome and send the invoice message in a new transaction.
A failure leaves the intent pending; a later send resumes it."
  (unwind-protect
       (let* ((snapshot (with-transaction (:read)
                          (let ((invoice (find-invoice id)))
                            (tun.accounting:make-invoice-intent
                             :id intent-id :invoice-id id
                             :customer (invoice-customer invoice)
                             :lines (mapcar #'entity->json (invoice-lines invoice))
                             :total-minor (invoice-total-minor invoice)))))
              (ref (handler-case (with-request-state (:external-call)
                                   (with-step (:external :name "accounting.create_invoice" :source :core
                                               :detail (format nil "intent ~a" intent-id))
                                     (tun.accounting:create-invoice (application-accounting *application*) snapshot)))
                     (operation-error (e) (error e))
                     (deadline-exceeded (e) (error e))
                     (error (e) (accounting-unavailable e)))))
         (check-type ref string)
         (record-send-outcome id ref "invoices_send.completed"))
    (release-send id)))

(defun record-send-outcome (id ref audit-tool)
  "In a new transaction: the intent is done, the invoice sent with REF, the
customer gets the invoice message. Idempotent: an invoice already sent is
left as it is."
  (with-transaction (:write)
    (let ((invoice (find-invoice id))
          (intent (select-one 'send-intent :where `(:= "invoice_id" ,id))))
      (when intent
        (setf (send-intent-status intent) "done" (send-intent-external-ref intent) ref)
        (save intent))
      (when (string= (invoice-status invoice) "draft")
        (setf (invoice-status invoice) "sent"
              (invoice-external-ref invoice) ref
              (invoice-sent-at invoice) (now))
        (save invoice)
        (let ((order (find-order (invoice-order-id invoice))))
          (notify "invoice" :order order :customer (order-customer order)))
        (write-system-audit audit-tool "ok" :entity-type "invoice" :entity-id id))
      invoice)))

(defun reconcile-send-intents ()
  "At start-up: every intent without a recorded outcome is looked up in the
accounting system (port LOOKUP-INVOICE) before any retry. If the provider has
it, the send is completed from its reference; if not, the intent stays
pending and the next invoices_send creates it. Returns how many completed."
  (let ((pending (with-transaction (:read) (select 'send-intent :where '(:= "status" "pending"))))
        (completed 0))
    (dolist (intent pending completed)
      (let ((ref (with-step (:external :name "accounting.lookup_invoice" :source :core
                             :detail (format nil "intent ~a" (send-intent-intent-id intent)))
                   (tun.accounting:lookup-invoice (application-accounting *application*)
                                                  (send-intent-intent-id intent)))))
        (when ref
          (record-send-outcome (send-intent-invoice-id intent) ref "invoices_send.reconciled")
          (incf completed))))))

(define-operation invoices-send ((id :type (id invoice) :required t :label "Invoice ID"))
    (:entity invoice :kind :transition :confirm t :destructive t :policy :admin :title "Send an invoice"
     :summary send-summary
             :description "draft → sent. Stores a send intent (committed before the accounting
call), calls the accounting port outside the transaction, stores the external reference and sends
the invoice message. Needs a confirmation and admin.")
  (let ((invoice (find-invoice id)))
    (unless (string= (invoice-status invoice) "draft")
      (fail :invalid-transition "The invoice is ~a and cannot be sent again"
            (label "invoice" "status" (invoice-status invoice))))
    (claim-send id)
    ;; 1. Persist the send intent; its id is stable per invoice, so a resumed
    ;;    send reuses it and the provider can de-duplicate.
    (let ((intent (or (select-one 'send-intent :where `(:= "invoice_id" ,id))
                      (insert (make-instance 'send-intent :invoice-id id :intent-id (format nil "send-~a" id))))))
      ;; 2-3. After this transaction commits: the port call, then the outcome.
      (complete-after-commit invoice
                             (let ((intent-id (send-intent-intent-id intent)))
                               (lambda () (finish-send id intent-id)))))))

(publish '(invoice invoice-for-order invoices-create-from-order invoices-get invoices-list
           invoices-send))

(seal-module "invoicing")
