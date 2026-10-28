;;;; modules/customers/customers.lisp -- the customers module.
;;;; It owns name, email, phone, notes and the completed-order counter;
;;;; clients extend the entity (see EXTEND-ENTITY) rather than this file.

(defpackage #:tun.customers
  (:use #:cl #:tun.core)
  (:local-nicknames (#:ui #:tun.ui))
  (:export #:customer #:customer-revision #:customer-name #:customer-email #:customer-phone
           #:customer-completed-orders #:customer-created-at #:customer-notes
           #:customers-create #:customers-get #:customers-list #:customers-set-consent #:customers-erase
           #:customer-marketing-consent #:customer-consent-source #:customer-consent-at
           #:customer-erased #:customer-erased-at #:customer-erasing #:marketing-allowed-p
           #:record-completed-order #:record-reopened-order))

(in-package #:tun.customers)

(declaim (optimize (safety 3) (debug 2)))

(define-module customers
  (:core ">= 2.0.0" "< 3.0")
  (:on-open repair-customer-receipts)
  (:documentation "Customers: name, email, phone, notes, completed orders."))

(define-entity customer (:label "Customer" :id-prefix "cus" :table "customers" :revisioned t)
  ((marketing-consent :type boolean :initform nil :label "Marketing consent")
   (consent-source :type (enum "manual" "email" "contact_form" "unsubscribe") :input nil
                   :label "Consent source")
   (consent-at :type timestamp :input nil :label "Consent changed")
   (erased :type boolean :input nil :initform nil :label "Erased")
   (erased-at :type timestamp :input nil :label "Erased at")
   (revision :type (integer :min 1) :input nil :initform 1 :label "Revision")
   (name :type (string :min 1 :max 120) :required t :label "Name"
         :description "The customer's name (1–120 characters, trimmed).")
   (email :type email :required t :label "Email"
          :description "An email address of the form name@domain.com (at most 160 characters).")
   (phone :type (string :max 40 :trim nil) :label "Phone"
          :description "Stored as given.")
   (notes :type (string :max 500) :label "Note"
          :description "Free text about the customer (at most 500 characters).")
   (completed-orders :type (integer :min 0) :input nil :initform 0 :label "Completed orders")
   (created-at :type timestamp :input nil :label "Created")))

(define-operation customers-create ((:draft customer))
    (:entity customer :kind :create
     :title "Create customer"
     :description "Registers a new customer. Returns the customer with its id and revision.")
  (when (customer-marketing-consent customer)
    (setf (customer-consent-source customer) "manual" (customer-consent-at customer) (now)))
  (insert customer))

(define-operation customers-get ((id :type (id customer) :required t :label "Customer ID"))
    (:entity customer :kind :read
     :title "Get customer"
     :description "Gets one customer by id.")
  (fetch! 'customer id))

(define-operation customers-list ((query :type (string :max 120) :label "Search in names and email")
                                  (limit :type (integer :min 1 :max 100) :default 20
                                         :label "Most results"))
    (:entity customer :kind :read
     :title "List customers"
     :description "Lists customers, oldest first, optionally matching a query in the name and the email (whatever the case).")
  ;; Without a query the store applies the limit; a query is matched here
  ;; (case-insensitive beyond ASCII, which SQL LIKE is not).
  (page (if query
            (remove-if-not (lambda (c) (or (contains-ci-p query (customer-name c))
                                           (contains-ci-p query (customer-email c))))
                           (select 'customer))
            (select 'customer :limit (1+ limit)))
        limit))

(defun record-completed-order (customer-id)
  "Increment the customer's completed-order counter (used by orders_complete)."
  (let ((customer (fetch! 'customer customer-id)))
    (incf (customer-completed-orders customer))
    (save customer)))

(defun record-reopened-order (customer-id)
  "Decrement the counter for an order reopened from completed (orders_reopen):
the count is the number of orders currently completed (README §3)."
  (let ((customer (fetch! 'customer customer-id)))
    (setf (customer-completed-orders customer) (max 0 (1- (customer-completed-orders customer))))
    (save customer)))

(tun.web:register-web-resource :path "/customers" :entity 'customer :title "Customers" :icon :users
                               :list-tool "customers_list" :create-tool "customers_create"
                               :get-tool "customers_get" :list-screen :customer-list)

;;; What clients may use (the module's other exports are for the modules
;;; that depend on it).
(publish '(customer customer-name customer-email customer-phone customer-completed-orders
           customers-create customers-get customers-list))

(defun marketing-allowed-p (customer)
  (and (customer-marketing-consent customer) (not (customer-erased customer))))

(defgeneric customer-erasing (application customer)
  (:method-combination traced-protocol)
  (:method ((application customers-module) customer) (declare (ignore customer)) nil))
(register-extension-protocol 'customer-erasing "before" :point "customer_erasing"
                            :description "Check erasure and anonymise dependent records in the same transaction.")

(define-operation customers-set-consent ((id :type (id customer) :required t)
                                         (marketing-consent :type boolean :required t)
                                         (source :type (enum "manual" "email" "contact_form" "unsubscribe") :required t))
    (:entity customer :kind :update :policy :employee :title "Change consent")
  (let ((customer (fetch! 'customer id)))
    (when (customer-erased customer) (fail :invalid-input "the customer is erased"))
    (setf (customer-marketing-consent customer) marketing-consent
          (customer-consent-source customer) source (customer-consent-at customer) (now))
    (audit-as :reason source)
    (save customer)))

(define-operation customers-erase ((id :type (id customer) :required t))
    (:entity customer :kind :update :policy :admin :confirm t :title "Erase customer data")
  (let* ((customer (fetch! 'customer id)) (suffix (subseq id (max 0 (- (length id) 8)))))
    (customer-erasing *application* customer)
    (redact-request-traces (list id (customer-name customer) (customer-email customer)
                                 (customer-phone customer) (customer-notes customer)))
    ;; The placeholder name is copy stored for people: the tenant's language.
    (setf (customer-name customer) (tr "Erased customer ~a" suffix)
          (customer-email customer) (format nil "~a@slettet.local" suffix)
          (customer-phone customer) nil (customer-notes customer) nil
          (customer-marketing-consent customer) nil
          (customer-erased customer) t (customer-erased-at customer) (now))
    (save customer)
    (redact-entity-receipts customer)
    customer))

(defun unsubscribe-form ()
  "The card that says what unsubscribing means, with its button."
  (ui:card ()
           (ui:stack (:gap :lg)
                     `(:p ,(tr "You will no longer get offers and news from us by email.") " "
                          ,(tr "You will still get messages about your bookings."))
                     `(:form (:@ :method "post")
                             ,(ui:button (:type "submit") (tr "Unsubscribe me"))))))

(defun public-unsubscribe-page (method parts form session)
  (declare (ignore form session))
  (let ((customer (with-transaction (:read)
                    (find-if (lambda (c) (constant-time-string= (string-upcase (or (first parts) "")) (link-token "avmeld" (entity-id c))))
                             (select 'customer)))))
    (unless (and customer (= (length parts) 1) (not (customer-erased customer)))
      (return-from public-unsubscribe-page
        (values 404 (tr "Page not found") `((:p ,(tr "Check the link in the email."))))))
    (if (eq method :post)
        (progn
          (call-customer-action (entity-id customer) "unsubscribe" "customer" (entity-id customer)
            (lambda ()
              (let ((current (fetch! 'customer (entity-id customer))))
                (when (or (customer-marketing-consent current) (not (equal (customer-consent-source current) "unsubscribe")))
                  (setf (customer-marketing-consent current) nil (customer-consent-source current) "unsubscribe"
                        (customer-consent-at current) (now)) (save current))))
            :reason "unsubscribe")
          (values 200 (tr "You are unsubscribed.") nil))
        (values 200 (tr "Unsubscribe me") (list (unsubscribe-form))))))
(tun.web:register-public-page "unsubscribe" #'public-unsubscribe-page)

(publish '(marketing-allowed-p customers-set-consent customer-marketing-consent customer-erased))
(defun repair-customer-receipts ()
  "At startup, redact receipts of erased customers that still hold their data
(README §5); keys remain deduplicated."
  (with-transaction (:write)
    (dolist (customer (select 'customer :where '(:= "erased" t)))
      (redact-entity-receipts customer))))

(seal-module "customers")
