;;;; modules/invoicing/invoicing.lisp -- the invoicing module: invoices copied
;;;; from orders, sent through the kernel's accounting port.

(defpackage #:tun.invoicing
  (:use #:cl #:tun.core #:tun.customers #:tun.catalog #:tun.orders)
  (:export #:invoice #:invoice-order-id #:invoice-status #:invoice-customer #:invoice-lines
           #:invoice-subtotal-ore #:invoice-discount-ore #:invoice-total-ore #:invoice-external-ref
           #:invoice-created-at #:invoice-sent-at
           #:invoice-line #:find-invoice #:invoice-for-order #:create-invoice-from-order
           #:invoices-create-from-order #:invoices-get #:invoices-list #:invoices-send
           #:reconcile-send-intents))

(in-package #:tun.invoicing)

(declaim (optimize (safety 3) (debug 2)))

(define-module invoicing
  (:depends-on orders)
  (:core ">= 1.0" "< 2.0")
  ;; Sends whose outcome was never recorded are reconciled before any retry.
  (:on-open reconcile-send-intents)
  (:documentation "Invoicing: invoices from orders, sent through the accounting port."))

(define-entity invoice-line (:embedded t :json-name "invoice_line" :label "Fakturalinje")
  ((description :type (string :max 500) :input nil :label "Beskrivelse")
   (quantity :type integer :input nil :label "Antall")
   (unit-price-ore :type integer :input nil :label "Enhetspris (øre)")
   (line-total-ore :type integer :input nil :label "Linjesum (øre)")
   (line-effective-ore :type integer :input nil :label "Linjesum etter prisvalg (øre)")
   (line-adjustment-ore :type integer :input nil :label "Linjejustering (øre)")))

(define-entity invoice (:label "Faktura" :id-prefix "fak" :table "invoices"
                        :unique (("order_id")) :indexes (("status")))
  ((order-id :type (id order) :required t :label "Ordre")
   (status :type (enum "utkast" "sendt") :input nil :initform "utkast" :label "Status")
   (customer :type json :input nil :label "Kunde"
             :description "Kopi av kundens opplysninger da fakturaen ble laget.")
   (lines :type (list-of invoice-line) :input nil :label "Linjer")
   (subtotal-ore :type integer :input nil :label "Sum før rabatt (øre)")
   (discount-ore :type integer :input nil :label "Rabatt (øre)")
   (adjustment-ore :type integer :input nil :label "Justering (øre)")
   (total-ore :type integer :input nil :label "Totalt (øre)")
   (external-ref :type (string :max 200) :input nil :label "Ekstern referanse")
   (created-at :type timestamp :input nil :label "Opprettet")
   (sent-at :type timestamp :input nil :label "Sendt")))

(define-entity send-intent (:json-name "send_intent" :label "Sendeintensjon" :id-prefix "int"
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
  "Snapshot ORDER into a new utkast invoice. conflict when one exists."
  ;; Confirmed or later, not cancelled (README §3).
  (unless (member (order-status order) '("bekreftet" "hentet" "returnert" "send_faktura" "fullført") :test #'string=)
    (fail :invalid-transition "Ordren har status ~a; faktura krever en bekreftet ordre"
          (order-status order)))
  (when (invoice-for-order (entity-id order))
    (fail :conflict "Ordre ~a er allerede fakturert" (entity-id order)))
  (insert (make-instance 'invoice
                         :order-id (entity-id order)
                         :customer (customer-snapshot (order-customer order))
                         :lines (mapcar (lambda (line)
                                          (make-instance 'invoice-line
                                                         :description (product-name (find-product (order-line-product-id line)))
                                                         :quantity (order-line-quantity line)
                                                         :unit-price-ore (order-line-unit-price-ore line)
                                                         :line-total-ore (order-line-line-total-ore line)
                                                         :line-effective-ore (or (order-line-line-effective-ore line)
                                                                                 (order-line-line-total-ore line))
                                                         :line-adjustment-ore (- (or (order-line-line-effective-ore line)
                                                                                     (order-line-line-total-ore line))
                                                                                 (order-line-line-total-ore line))))
                                        (order-lines order))
                         :subtotal-ore (order-subtotal-ore order)
                         :discount-ore (order-discount-ore order)
                         :adjustment-ore (or (order-adjustment-ore order) (- (order-discount-ore order)))
                         :total-ore (order-total-ore order))))

(define-operation invoices-create-from-order ((order-id :type (id order) :required t :label "Ordre-ID"))
    (:entity invoice :kind :create :title "Lag faktura"
     :description "Lager et fakturautkast som kopi av en bekreftet eller fullført ordre. Ny faktura for samme ordre gir conflict.")
  (create-invoice-from-order (find-order order-id)))

(define-operation invoices-get ((id :type (id invoice) :required t :label "Faktura-ID"))
    (:entity invoice :kind :read :title "Hent faktura" :description "Henter én faktura.")
  (find-invoice id))

(define-operation invoices-list ((order-id :type (id order) :label "Ordre-ID")
                                 (status :type (enum "utkast" "sendt") :label "Status")
                                 (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:entity invoice :kind :read :title "Fakturaliste" :description "Lister fakturaer.")
  (let ((where (remove nil (list (and order-id `(:= "order_id" ,order-id))
                                 (and status `(:= "status" ,status))))))
    (page (select 'invoice :where (and where `(:and ,@where)) :limit (1+ limit)) limit)))

(defun send-summary ()
  (let ((invoice (find-invoice (input-value :id))))
    (format nil "Send faktura ~a (ordre ~a, totalt ~a kr) til regnskapssystemet og kunden."
            (entity-id invoice) (invoice-order-id invoice) (format-kroner (invoice-total-ore invoice)))))

(defvar *sending* (make-hash-table :test 'equal) "Invoice ids being sent by this process.")
(defvar *sending-lock* (sb-thread:make-mutex :name "invoices being sent"))

(defun claim-send (id)
  "Mark invoice ID as being sent; conflict if another call in this process is
sending it. Released when the send finishes or its transaction rolls back."
  (sb-thread:with-mutex (*sending-lock*)
    (when (gethash id *sending*)
      (fail :conflict "Fakturaen ~a er i ferd med å bli sendt" id))
    (setf (gethash id *sending*) t))
  (on-rollback (lambda () (release-send id))))

(defun release-send (id)
  (sb-thread:with-mutex (*sending-lock*) (remhash id *sending*)))

(defun finish-send (id intent-id)
  "Outside any transaction: call the accounting port for the committed intent,
then record the outcome and send the faktura message in a new transaction.
A failure leaves the intent pending; a later send resumes it."
  (unwind-protect
       (let* ((snapshot (with-transaction (:read)
                          (let ((invoice (find-invoice id)))
                            (tun.accounting:make-invoice-intent
                             :id intent-id :invoice-id id
                             :customer (invoice-customer invoice)
                             :lines (mapcar #'entity->json (invoice-lines invoice))
                             :total-ore (invoice-total-ore invoice)))))
              (ref (handler-case (with-request-state (:external-call)
                                   (with-step (:external :name "accounting.create_invoice" :source :core
                                               :detail (format nil "intent ~a" intent-id))
                                     (tun.accounting:create-invoice (application-accounting *application*) snapshot)))
                     (operation-error (e) (error e))
                     (deadline-exceeded (e) (error e))
                     (error (e)
                       (fail :unavailable "Regnskapssystemet svarte ikke (~a); fakturaen er ikke sendt, prøv igjen" e)))))
         (check-type ref string)
         (record-send-outcome id ref "invoices_send.completed"))
    (release-send id)))

(defun record-send-outcome (id ref audit-tool)
  "In a new transaction: the intent is done, the invoice sendt with REF, the
customer gets the faktura message. Idempotent: an invoice already sendt is
left as it is."
  (with-transaction (:write)
    (let ((invoice (find-invoice id))
          (intent (select-one 'send-intent :where `(:= "invoice_id" ,id))))
      (when intent
        (setf (send-intent-status intent) "done" (send-intent-external-ref intent) ref)
        (save intent))
      (when (string= (invoice-status invoice) "utkast")
        (setf (invoice-status invoice) "sendt"
              (invoice-external-ref invoice) ref
              (invoice-sent-at invoice) (now))
        (save invoice)
        (let ((order (find-order (invoice-order-id invoice))))
          (notify "faktura" :order order :customer (order-customer order)))
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

(define-operation invoices-send ((id :type (id invoice) :required t :label "Faktura-ID"))
    (:entity invoice :kind :transition :confirm t :destructive t :policy :admin :title "Send faktura"
     :summary send-summary
     :description "utkast → sendt. Lagrer en sendeintensjon (committet før regnskapskallet), kaller regnskapsporten utenfor transaksjonen, lagrer ekstern referanse og sender fakturameldingen. Krever bekreftelse og admin.")
  (let ((invoice (find-invoice id)))
    (unless (string= (invoice-status invoice) "utkast")
      (fail :invalid-transition "Fakturaen har status ~a og kan ikke sendes på nytt" (invoice-status invoice)))
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
