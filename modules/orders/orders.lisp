;;;; modules/orders/orders.lisp -- the order aggregate: entities, seams,
;;;; pricing modes (README §3), logistics (§4), bookings and availability
;;;; (§5), and the create/read/update operations (§1).

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Entities

(define-entity order-line (:embedded t :json-name "order_line" :label "Order line")
  ((id :type id :label "ID"
       :description "The line's id: in orders_update a line with the same id (or the same product in the same place) keeps its identity, and the checklist follows it.")
   (product-id :type (id product) :required t :label "Product")
   (quantity :type (integer :min 1 :max 100000) :required t :label "Quantity")
   (price-mode :type (enum "automatic" "percent_discount" "fixed_discount" "manual_total")
               :initform "automatic" :label "Price mode"
               :description "automatic (the default), percent_discount, fixed_discount or manual_total.")
   (discount-percent :type (decimal :scale 2) :label "Discount in percent"
                     :description "0–100, at most two decimals (price mode percent_discount).")
   (discount-input-minor :type money :label "Discount amount" :description "Price mode fixed_discount.")
   (manual-total-minor :type money :label "Manual line total" :description "Price mode manual_total.")
   (price-reason :type (string :max 500) :label "Reason for the price")
   (notes :type (string :max 1000) :label "Note")
   (choices :type json :label "Choices"
            :description "{requirement id: [recipe id, …]}: the picks for the product's choice-group requirements, in order.")
   (choices-at :type timestamp :input nil :label "Chosen"
               :description "When the choices last changed (stock warnings: no receipt since the pick).")
   (unit-price-minor :type money :input nil :label "Unit price")
   (line-total-minor :type money :input nil :label "Line total by the catalog")
   (line-effective-minor :type money :input nil :label "Line total")
   (line-adjustment-minor :type money :input nil :label "Line adjustment")))

(define-entity requirement (:embedded t :json-name "requirement" :label "Need")
  ((product-id :type id :input nil :label "Product"
               :description "The article's product, or the article without one (README §8.3).")
   (quantity :type (decimal :scale 3) :input nil :label "Required quantity")
   (article-id :type id :input nil :label "Stock article")))

(define-entity order (:label "Order" :id-prefix "ord" :table "orders"
                      :indexes (("customer_id") ("status") ("event_date")) :revisioned t)
  ((source :type json :input nil :label "Source")
   (open-questions :type (list-of (string :max 2000)) :input nil :initform nil
                   :label "Open questions")
   (revision :type (integer :min 1) :input nil :initform 1 :label "Revision")
   (status :type (enum "draft" "quote_sent" "accepted" "confirmed" "picked_up" "returned"
                       "ready_for_invoice" "completed" "cancelled")
           :input nil :initform "draft" :label "Status")
   (customer-id :type (id customer) :required t :label "Customer")
   (event-date :type date :label "Event date")
   (end-date :type date :label "End date" :description "The last day; empty means one day.")
   (delivery-address :type (string :max 300) :label "Delivery address")
   (lines :type (list-of order-line :max-items 100) :initform nil :label "Lines")
   (tags :type (list-of (enum "rental" "entertainment") :max-items 2) :initform '() :label "Tags")
   (department :type (string :max 100) :label "Department")
   (price-mode :type (enum "automatic" "percent_discount" "fixed_discount" "manual_total")
               :initform "automatic" :label "Price mode of the order"
               :description "automatic (the customer's discount), percent_discount or fixed_discount.")
   (discount-percent :type (decimal :scale 2) :label "Order discount in percent")
   (discount-input-minor :type money :label "Order discount")
   (price-reason :type (string :max 500) :label "Reason for the price")
   (logistics :type json :label "Logistics"
              :description "{delivery:{not_agreed,method,earliest,latest}, return:{…}, site_address}.")
   (catalog-total-minor :type money :input nil :initform 0 :label "Catalog total")
   (subtotal-minor :type money :input nil :initform 0 :label "Subtotal")
   (discount-minor :type money :input nil :initform 0 :label "Discount")
   (adjustment-minor :type money :input nil :initform 0 :label "Adjustment")
   (total-minor :type money :input nil :initform 0 :label "Total")
   (requirements :type (list-of requirement) :input nil :label "Consumables needed")
   (pickup :type json :input nil :label "Pickup")
   (return-record :type json :input nil :json-name "return" :label "Return")
   (accepted-snapshot-stale :type boolean :input nil :initform nil :label "The accepted quote was out of date")
   (created-at :type timestamp :input nil :label "Created")))

(define-entity booking (:json-name "booking" :label "Booking" :id-prefix "bkg" :table "bookings"
                        :internal t :indexes (("product_id" "from_date") ("order_id")))
  ((order-id :type id :input nil)
   (product-id :type (id product) :input nil)
   (quantity :type (integer :min 1) :input nil)
   (from :type date :input nil :json-name "from_date")
   (to :type date :input nil :json-name "to_date")))

;;; The quote (README §6): one per order, a stable id across re-issues.
(define-entity order-quote (:json-name "quote" :label "Quote" :id-prefix "qte" :table "quotes"
                            :unique (("order_id")) :indexes (("access_code")))
  ((order-id :type (id order) :input nil :label "Order")
   (revision :type (integer :min 1) :input nil :initform 1 :label "Revision")
   (status :type (enum "awaiting_response" "accepted" "declined" "expired") :input nil :initform "awaiting_response"
           :label "Status")
   (offered-at :type timestamp :input nil :label "Sent")
   (expires-at :type timestamp :input nil :label "Expires")
   (responded-at :type timestamp :input nil :label "Answered")
   (snapshot :type json :input nil :label "Content when the quote was sent")
   (basis :type json :input nil :label "The order when the quote was sent"
          :description "The total, dates, address and every line field; when they change, the quote is out of date (stale).")
   (access-code :type (string :max 10) :input nil :label "Access code")))

;;; The checklist (README §7): automatic items from requirements, manual items.
(define-entity checklist-item (:json-name "checklist_item" :label "Checklist item" :id-prefix "chk"
                               :table "checklist_items" :indexes (("order_id")))
  ((order-id :type (id order) :input nil :label "Order")
   (order-line-id :type id :input nil :label "Order line")
   (origin :type (enum "automatic" "manual") :input nil :initform "manual" :label "Origin")
   (source-key :type (string :max 200) :input nil :label "Source")
   (description :type (string :max 500) :input nil :label "Description")
   (category :type (string :max 200) :input nil :label "Category")
   (computed-quantity :type (decimal :scale 3) :input nil :label "Computed quantity")
   (done-quantity :type (decimal :scale 3) :input nil :label "Packed quantity")
   (done :type boolean :input nil :initform nil :label "Done")))

;;; ------------------------------------------------------------------
;;; Seams (published extension points)

(defgeneric order-discount (application order customer)
  (:method-combination traced-protocol)
  (:documentation "The automatic discount, in minor units, of ORDER's subtotal for
CUSTOMER (price mode automatic). Called when an order is created or updated, after
lines are priced. Must return an integer between 0 and the subtotal.")
  (:method ((application orders-module) order customer)
    (declare (ignore order customer))
    0))

(defgeneric compute-order-requirements (application order)
  (:method-combination traced-protocol)
  (:documentation "Consumables ORDER needs, as a list of (product-id . quantity).
Duplicates are summed. Reserved on confirm, consumed on complete.")
  (:method ((application orders-module) order)
    (declare (ignore order))
    '()))

(defgeneric booking-window (application product event-date end-date)
  (:method-combination traced-protocol)
  (:documentation "Values FROM and TO (dates, inclusive) during which one booking
of rental PRODUCT for an order on EVENT-DATE..END-DATE blocks the unit
(END-DATE is EVENT-DATE for a single-day order; README §5.2).  FROM must
not be after EVENT-DATE nor TO before END-DATE.")
  (:method ((application orders-module) product event-date end-date)
    (declare (ignore product))
    (values event-date end-date)))

(defgeneric order-suggestions (application order)
  (:method-combination traced-protocol)
  (:documentation "Upsell suggestions for ORDER: a list of (product reason), where
PRODUCT is a product entity. Never mutates.")
  (:method ((application orders-module) order)
    (declare (ignore order))
    '()))

(defgeneric order-checklist-items (application order)
  (:method-combination traced-protocol)
  (:documentation "Extra automatic checklist items for ORDER, by rule: a list of
plists (:key KEY :description TEXT :category TEXT :quantity N), each keyed
client:<KEY>. They synchronise like the requirement items.")
  (:method ((application orders-module) order)
    (declare (ignore order))
    '()))

(defgeneric order-departments (application)
  (:method-combination traced-protocol)
  (:documentation "The departments an order may name (none unless a module or the
client declares some).")
  (:method ((application orders-module))
    '()))

(defgeneric order-department-changed (application order previous)
  (:method-combination traced-protocol)
  (:documentation "Called inside the transaction of orders_create (when ORDER names a
department; PREVIOUS is NIL) and of orders_update (when the department
changed from PREVIOUS), after the order is stored.  A refusal (an
operation error) fails the whole save.")
  (:method ((application orders-module) order previous)
    (declare (ignore order previous))
    nil))

(defgeneric order-closure-check (application order tool)
  (:method-combination traced-protocol)
  (:documentation "Called before ORDER is completed, made ready for invoicing or
cancelled (TOOL names which); a method refuses by signalling an operation
error (a running work session: conflict).")
  (:method ((application orders-module) order tool)
    (declare (ignore order tool))
    nil))

(register-extension-protocol 'order-discount "before" :point "discount"
                             :description "The automatic discount of an order's subtotal (price mode automatic).")
(register-extension-protocol 'compute-order-requirements "before" :point "requirements"
                             :description "Consumables an order needs, per line.")
(register-extension-protocol 'booking-window "before" :point "booking_window"
                             :description "Dates one booking of a rental unit blocks it.")
(register-extension-protocol 'order-suggestions "before" :point "suggestions"
                             :description "Upsell suggestions for an order (orders_suggest).")
(register-extension-protocol 'order-checklist-items "before" :point "checklist_items"
                             :description "Extra automatic checklist items, keyed client:<key>.")
(register-extension-protocol 'order-departments "rule" :point "departments"
                             :description "The departments an order may name.")
(register-extension-protocol 'order-department-changed "after" :point "department_changed"
                             :description "Reacts inside the save when an order's department is set or changes.")
(register-extension-protocol 'order-closure-check "rule" :point "closure_guard"
                             :description "May refuse completing, invoicing readiness or cancelling an order.")

;;; ------------------------------------------------------------------
;;; Basic predicates

(defun find-order (id) (fetch! 'order id))
(defun order-customer (order) (fetch! 'customer (order-customer-id order)))
(defun order-final-p (order) (member (order-status order) +final-statuses+ :test #'string=))
(defun order-locked-p (order) (and (member (order-status order) +locked-statuses+ :test #'string=) t))
(defun order-dateless-p (order) (null (order-event-date order)))

(defun order-last-date (order)
  "end_date ?? event_date (NIL for a dateless order)."
  (and (order-event-date order) (or (order-end-date order) (order-event-date order))))

(defun order-period (order)
  "Values first and last date of ORDER, or NIL for a dateless order."
  (if (order-event-date order)
      (values (order-event-date order) (order-last-date order))
      nil))

(defun order-requires-pickup-p (order)
  "True when any line's product is rental (it must be picked up and returned)."
  (some (lambda (line)
          (let ((product (fetch 'product (order-line-product-id line))))
            (and product (rental-product-p product))))
        (order-lines order)))

(defun check-order-not-locked (order)
  (when (order-locked-p order)
    (refuse-locked-order)))

(defun check-revision (order revision)
  (when (and revision (/= revision (order-revision order)))
    (fail :conflict "The order has changed (revision ~d, not ~d)" (order-revision order) revision)))

(defun touch-order (order)
  "Store ORDER again: every change to an order, its quote, checklist,
assignments or department counts as a revision (README §1.2)."
  (save order))

;;; ------------------------------------------------------------------
;;; Pricing (README §3)

(defconstant +max-amount-minor+ 9007199254740991
  "Largest amount stored or returned: exact in JSON numbers and SQLite integers.")

(defun check-amount (amount what)
  "AMOUNT, refused when it is larger than an amount may be; WHAT, a text,
names it in the refusal."
  (when (> (abs amount) +max-amount-minor+)
    (fail :invalid-input "~a is too large (over ~d minor units)" what +max-amount-minor+))
  amount)

(defun apply-price-mode (amount mode percent fixed manual &key (allow-manual t))
  "AMOUNT after price MODE: automatic keeps it, percent_discount takes PERCENT
off (rounded down), fixed_discount takes FIXED minor units off, both floored
at 0; manual_total is MANUAL."
  (cond ((or (null mode) (string= mode "automatic")) amount)
        ((string= mode "percent_discount")
         (cond ((null percent) (fail :invalid-input "Discount percent must be filled in"))
               ((not (<= 0 percent 100)) (fail :invalid-input "Discount percent must be between 0 and 100"))
               (t (max 0 (- amount (floor (* amount percent) 100))))))
        ((string= mode "fixed_discount")
         (cond ((null fixed) (fail :invalid-input "Discount amount must be filled in"))
               ((minusp fixed) (fail :invalid-input "Discount amount cannot be negative"))
               (t (max 0 (- amount fixed)))))
        ((and (string= mode "manual_total") allow-manual)
         (cond ((null manual) (fail :invalid-input "Manual total must be filled in"))
               ((minusp manual) (fail :invalid-input "Manual total cannot be negative"))
               (t (check-amount manual (deferred-tr "The manual total")))))
        (t (fail :invalid-input "That price mode is not allowed here"))))

(defun clear-other-mode-inputs (mode setters)
  "Inputs that belong to another price mode are stored as null."
  (loop for (owner . clear) in setters
        unless (equal owner mode) do (funcall clear)))

(defun price-lines (order)
  "Give every line an id, the product's current price, and its effective sum."
  (dolist (line (order-lines order))
    (clear-other-mode-inputs (order-line-price-mode line)
                             (list (cons "percent_discount" (lambda () (setf (order-line-discount-percent line) nil)))
                                   (cons "fixed_discount" (lambda () (setf (order-line-discount-input-minor line) nil)))
                                   (cons "manual_total" (lambda () (setf (order-line-manual-total-minor line) nil))))))
  (dolist (line (order-lines order))
    (let* ((product (find-product (order-line-product-id line)))
           (total (check-amount (* (order-line-quantity line) (product-unit-price-minor product)) (deferred-tr "The line total")))
           (effective (apply-price-mode total (order-line-price-mode line) (order-line-discount-percent line)
                                        (order-line-discount-input-minor line) (order-line-manual-total-minor line))))
      (unless (order-line-id line) (setf (order-line-id line) (new-id "lin")))
      (unless (order-line-price-mode line) (setf (order-line-price-mode line) "automatic"))
      (setf (order-line-unit-price-minor line) (product-unit-price-minor product)
            (order-line-line-total-minor line) total
            (order-line-line-effective-minor line) effective
            (order-line-line-adjustment-minor line) (- effective total)))))

(defun aggregate-requirements (pairs)
  (let ((table (make-hash-table :test 'equal)) (order '()))
    (loop for (product-id . quantity) in pairs
          do (check-type product-id string)
             (check-type quantity (integer 0))
             (unless (nth-value 1 (gethash product-id table)) (push product-id order))
             (incf (gethash product-id table 0) quantity))
    (loop for product-id in (reverse order)
          for quantity = (gethash product-id table)
          when (plusp quantity)
            collect (make-instance 'requirement :product-id product-id :quantity quantity))))

(defun reprice (order)
  "Recompute the catalog total, subtotal (Σ effective line sums), the order
adjustment (the discount seam in automatic mode, else the explicit mode),
the total and the requirements.  Prices are always derived here."
  (let* ((customer (order-customer order))
         (catalog (check-amount (reduce #'+ (order-lines order) :key #'order-line-line-total-minor)
                                (deferred-tr "The total")))
         (subtotal (check-amount (reduce #'+ (order-lines order) :key #'order-line-line-effective-minor)
                                 (deferred-tr "The total")))
         (mode (or (order-price-mode order) "automatic")))
    (clear-other-mode-inputs mode
                             (list (cons "percent_discount" (lambda () (setf (order-discount-percent order) nil)))
                                   (cons "fixed_discount" (lambda () (setf (order-discount-input-minor order) nil)))))
    (setf (order-price-mode order) mode
          (order-catalog-total-minor order) catalog
          (order-subtotal-minor order) subtotal)
    (if (string= mode "automatic")
        (let ((discount (order-discount *application* order customer)))
          (unless (and (integerp discount) (<= 0 discount subtotal))
            (extension-error "ORDER-DISCOUNT returned ~s for subtotal ~d" discount subtotal))
          (setf (order-discount-minor order) discount
                (order-total-minor order) (- subtotal discount)))
        (let ((total (apply-price-mode subtotal mode (order-discount-percent order) (order-discount-input-minor order)
                                       nil :allow-manual nil)))
          (setf (order-discount-minor order) 0
                (order-total-minor order) total)))
    (setf (order-adjustment-minor order) (- (order-total-minor order) (order-subtotal-minor order))
          (order-requirements order) (requirements-of (resolve-order order)))
    order))

;;; ------------------------------------------------------------------
;;; Logistics (README §4)

(defparameter +delivery-methods+ '("we_deliver" "customer_collects"))
(defparameter +return-methods+ '("we_collect" "customer_returns"))
(defparameter +address-methods+ '("we_deliver" "we_collect") "Methods that need the site address.")

(defun local-time-string-p (value)
  (and (stringp value) (cl-ppcre:scan "^([01][0-9]|2[0-3]):[0-5][0-9]$" value) t))

(defun default-side ()
  (jobj "not_agreed" t "method" :null "earliest" :null "latest" :null))

(defun default-logistics (address)
  (jobj "delivery" (default-side) "return" (default-side) "site_address" (or address :null)))

(defun side-agreed-p (side) (and side (not (eq t (jget side "not_agreed")))))
(defun side-value (side key)
  (let ((v (and side (jget side key))))
    (if (or (null v) (json-null-p v)) nil v)))

(defun parse-side (value name methods)
  "One side of a logistics input as a normalised object; malformed input is invalid_input."
  (cond ((or (null value) (json-null-p value)) (default-side))
        ((not (hash-table-p value)) (fail :invalid-input "logistics.~a must be an object" name))
        (t
         (dolist (key (jkeys value))
           (unless (member key '("not_agreed" "method" "earliest" "latest") :test #'string=)
             (fail :invalid-input "logistics.~a.~a is not a known field" name key)))
         (let ((not-agreed (jget value "not_agreed"))
               (method (jget value "method"))
               (earliest (jget value "earliest"))
               (latest (jget value "latest")))
           (unless (or (null not-agreed) (eq not-agreed t) (json-null-p not-agreed))
             (fail :invalid-input "logistics.~a.not_agreed must be true or false" name))
           (when (json-null-p method) (setf method nil))
           (when (json-null-p earliest) (setf earliest nil))
           (when (json-null-p latest) (setf latest nil))
           (when (and method (not (and (stringp method) (member method methods :test #'string=))))
             (fail :invalid-input "logistics.~a.method must be one of: ~{~a~^, ~}" name methods))
           (dolist (time (list earliest latest))
             (when (and time (not (local-time-string-p time)))
               (fail :invalid-input "Enter a valid time of day")))
           (if (eq not-agreed t)
               (default-side)
               (jobj "not_agreed" nil "method" (or method :null)
                     "earliest" (or earliest :null) "latest" (or latest :null)))))))

(defun normalise-logistics (raw event-date end-date stored-address)
  "The logistics object for RAW (the input), normalised then validated (first
failure wins, README §4): agreed sides keep method and times, an address is
kept only when an agreed side needs it, and trimmed.  RAW replaces the whole
object; a missing side is not agreed; a missing site_address keeps
STORED-ADDRESS."
  (unless (hash-table-p raw) (fail :invalid-input "logistics must be an object"))
  (dolist (key (jkeys raw))
    (unless (member key '("delivery" "return" "site_address") :test #'string=)
      (fail :invalid-input "logistics.~a is not a known field" key)))
  (let* ((delivery (parse-side (jget raw "delivery") "delivery" +delivery-methods+))
         (return (parse-side (jget raw "return") "return" +return-methods+))
         (address-raw (multiple-value-bind (value present) (jget raw "site_address")
                        (if present value (or stored-address :null))))
         (address (and (stringp address-raw) (trim address-raw)))
         (needs-address (or (and (side-agreed-p delivery) (member (side-value delivery "method") +address-methods+ :test #'string=))
                            (and (side-agreed-p return) (member (side-value return "method") +address-methods+ :test #'string=)))))
    (when (and address-raw (not (json-null-p address-raw)) (not (stringp address-raw)))
      (fail :invalid-input "logistics.site_address must be a text"))
    (when (and address (> (length address) 300))
      (fail :invalid-input "The address cannot be longer than 300 characters"))
    (unless needs-address (setf address nil))
    (when (and address (zerop (length address))) (setf address nil))
    (flet ((agreed (side) (side-agreed-p side))
           (v (side key) (side-value side key)))
      (cond ((and (agreed delivery) (null (v delivery "method"))) (fail :invalid-input "Choose a delivery method"))
            ((and (agreed return) (null (v return "method"))) (fail :invalid-input "Choose a return method"))
            ((and (agreed delivery) (or (null (v delivery "earliest")) (null (v delivery "latest"))))
             (fail :invalid-input "Set a time window for the delivery"))
            ((and (agreed return) (or (null (v return "earliest")) (null (v return "latest"))))
             (fail :invalid-input "Set a time window for the return"))
            ((and (agreed delivery) (string< (v delivery "latest") (v delivery "earliest")))
             (fail :invalid-input "The latest delivery time cannot be before the earliest"))
            ((and (agreed return) (string< (v return "latest") (v return "earliest")))
             (fail :invalid-input "The latest return time cannot be before the earliest"))
            ((and (agreed delivery) (agreed return)
                  (or (null end-date) (equal end-date event-date))
                  (string< (v return "earliest") (v delivery "latest")))
             (fail :invalid-input "The return cannot start before the delivery is done on the same day"))
            ((and needs-address (null address))
             (fail :invalid-input "Address must be filled in when we deliver to or collect from the customer"))))
    (jobj "delivery" delivery "return" return "site_address" (or address :null))))

(defun order-logistics-object (order)
  "ORDER's logistics, with site_address the stored delivery address."
  (let ((stored (order-logistics order)))
    (if (hash-table-p stored)
        (let ((copy (jobj "delivery" (or (jget stored "delivery") (default-side))
                          "return" (or (jget stored "return") (default-side)))))
          (setf (gethash "site_address" copy) (or (order-delivery-address order) :null))
          copy)
        (default-logistics (order-delivery-address order)))))

(defun apply-logistics-input (order raw)
  "Set ORDER's logistics (and so its site address) from the input RAW."
  (let ((logistics (normalise-logistics raw (order-event-date order) (order-end-date order)
                                       (order-delivery-address order))))
    (setf (order-delivery-address order) (let ((a (jget logistics "site_address"))) (if (json-null-p a) nil a))
          (order-logistics order) logistics)))

(defun sync-logistics (order)
  "Keep the stored logistics object's site address equal to the delivery address."
  (setf (order-logistics order) (order-logistics-object order)))

(defun logistics-settled-p (logistics)
  "Both sides agreed with a method and both times, and the address there when a side needs it."
  (let ((delivery (jget logistics "delivery")) (return (jget logistics "return")))
    (flet ((complete-p (side)
             (and (side-agreed-p side) (side-value side "method")
                  (side-value side "earliest") (side-value side "latest"))))
      (and (complete-p delivery) (complete-p return)
           (or (not (or (member (side-value delivery "method") +address-methods+ :test #'string=)
                        (member (side-value return "method") +address-methods+ :test #'string=)))
               (let ((address (jget logistics "site_address")))
                 (and (stringp address) (not (blank-p address)))))))))

(defun logistics-method-label (method)
  "The logistics METHOD as a person reads it, in the current language."
  (cond ((equal method "we_deliver") (tr "We deliver"))
        ((equal method "customer_collects") (tr "Customer collects"))
        ((equal method "we_collect") (tr "We collect"))
        ((equal method "customer_returns") (tr "Customer returns"))
        (t (tr "Agreed"))))

(defun side-summary (side)
  "One side of the logistics in a few words (README §4), in the current language."
  (if (not (side-agreed-p side))
      (tr "Not agreed")
      (let ((label (logistics-method-label (side-value side "method")))
            (earliest (side-value side "earliest"))
            (latest (side-value side "latest")))
        (cond ((and earliest latest (string= earliest latest)) (tr "~a at ~a" label earliest))
              ((and earliest latest) (format nil "~a ~a-~a" label earliest latest))
              (t label)))))

(defun logistics-summary (logistics)
  (jobj "delivery" (side-summary (jget logistics "delivery"))
        "return" (side-summary (jget logistics "return"))))

;;; ------------------------------------------------------------------
;;; Validation of the order's own fields

(defparameter +first-order-date+ "1970-01-01")
(defparameter +last-order-date+ "2999-12-31")
(defparameter +max-order-days+ 731 "Most days end_date may lie after event_date (README §1.3).")

(defun check-order-dates (order)
  "ORDER's dates (README §1.3): within 1970..2999, the end not before the
start and at most 731 days after it; checked before anything computes with
them, so an extreme date is invalid_input, never an error later."
  (dolist (date (list (order-event-date order) (order-end-date order)))
    (when (and date (or (date< date +first-order-date+) (date< +last-order-date+ date)))
      (fail :invalid-input "The date ~a must lie between ~a and ~a" date +first-order-date+ +last-order-date+)))
  (when (and (order-end-date order) (null (order-event-date order)))
    (fail :invalid-input "An end date needs a start date"))
  (when (and (order-end-date order) (date< (order-end-date order) (order-event-date order)))
    (fail :invalid-input "The end date cannot be before the start date"))
  (when (and (order-end-date order)
             (< +max-order-days+ (round (- (parse-date (order-end-date order)) (parse-date (order-event-date order)))
                                        86400)))
    (fail :invalid-input "The end date can be at most ~d days after the start date" +max-order-days+)))

(defun check-order-fields (order)
  (check-order-dates order)
  (let ((tags (order-tags order)))
    (unless (= (length tags) (length (remove-duplicates tags :test #'string=)))
      (fail :invalid-input "Each tag can be used only once")))
  (let ((department (order-department order)))
    (when (and department (not (member department (order-departments *application*) :test #'string=)))
      (fail :invalid-input "Unknown department ~a (valid: ~{~a~^, ~})" department (order-departments *application*)))))

(defun prepare-order (order)
  "Everything a save of ORDER derives and checks (create, update; explain runs
the same): the customer exists, own fields valid, lines priced, totals,
discount and requirements computed, logistics in step with the address."
  (order-customer order)
  (check-order-fields order)
  (sync-logistics order)
  (price-lines order)
  (check-choices order)
  (reprice order)
  order)

;;; ------------------------------------------------------------------
;;; Output: derived fields and defaults for rows an older core stored

(defmethod entity->json ((line order-line))
  (let ((json (call-next-method)))
    (remhash "choices_at" json)
    (when (json-null-p (jget json "choices"))
      (setf (gethash "choices" json) (jobj)))
    (when (json-null-p (jget json "line_effective_minor"))
      (setf (gethash "line_effective_minor" json) (or (order-line-line-total-minor line) :null)
            (gethash "line_adjustment_minor" json) 0))
    json))

(defun add-stock-warnings (json)
  "The live view of orders_create and orders_update: the stock warnings of
the order JSON shows, computed after the commit (README §12.3)."
  (let ((order (and (stringp (jget json "id")) (fetch 'order (jget json "id")))))
    (when order
      (setf (gethash "stock_warnings" json) (jarr (stock-warnings order))))
    json))

(defmethod entity->json ((order order))
  (let ((json (call-next-method)))
    ;; Stock warnings on the order an operation shows (orders_get here;
    ;; orders_create and _update add them after their commit, as their live
    ;; view), not on every order of a list (README §12.3).
    (when (and (entity-id order) (equal (current-operation-tool) "orders_get"))
      (setf (gethash "stock_warnings" json) (jarr (stock-warnings order))))
    (setf (gethash "logistics" json) (order-logistics-object order)
          (gethash "site_address" json) (or (order-delivery-address order) :null))
    (when (json-null-p (jget json "catalog_total_minor"))
      (setf (gethash "catalog_total_minor" json)
            (reduce #'+ (order-lines order) :key (lambda (l) (or (order-line-line-total-minor l) 0)))))
    (when (json-null-p (jget json "adjustment_minor"))
      (setf (gethash "adjustment_minor" json) (- (or (order-total-minor order) 0) (or (order-subtotal-minor order) 0))))
    (when (json-null-p (jget json "price_mode")) (setf (gethash "price_mode" json) "automatic"))
    json))

(define-computed-field order bookings (order) (:type json :label "Bookings")
  (jarr (mapcar (lambda (b) (jobj "product_id" (booking-product-id b) "quantity" (booking-quantity b)
                                  "from" (booking-from b) "to" (booking-to b)))
                (order-booking-rows (entity-id order)))))

(define-computed-field order requires-pickup (order) (:type boolean :label "Needs pickup and return")
  (order-requires-pickup-p order))

(define-computed-field order locked (order) (:type boolean :label "Locked")
  (order-locked-p order))

(define-computed-field order dateless (order) (:type boolean :label "Without a date")
  (order-dateless-p order))

(define-computed-field order logistics-settled (order) (:type boolean :label "Logistics agreed")
  (logistics-settled-p (order-logistics-object order)))

(define-computed-field order logistics-summary (order) (:type json :label "Logistics")
  (logistics-summary (order-logistics-object order)))

(define-computed-field order quote (order) (:type json :label "Quote")
  (let ((quote (and (entity-id order) (quote-for-order (entity-id order)))))
    (if quote
        (jobj "id" (entity-id quote) "revision" (order-quote-revision quote)
              "status" (quote-status quote) "expires_at" (format-rfc3339 (order-quote-expires-at quote)))
        :null)))

(define-computed-field order packed (order) (:type boolean :label "Packed")
  (order-packed-p order))

(defun order-booking-rows (order-id)
  (select 'booking :where `(:= "order_id" ,order-id) :order-by '(("product_id" :asc))))

;;; ------------------------------------------------------------------
;;; Availability and bookings

(defun blocking-bookings (product-id date &key exclude-order)
  (remove-if (lambda (b) (equal (booking-order-id b) exclude-order))
             (select 'booking :where `(:and (:= "product_id" ,product-id)
                                            (:<= "from_date" ,date)
                                            (:>= "to_date" ,date)))))

(defun availability (product date &key exclude-order)
  "Values units-owned, blocked, available and the blocking bookings."
  (let* ((blocking (blocking-bookings (entity-id product) date :exclude-order exclude-order))
         (blocked (reduce #'+ blocking :key #'booking-quantity))
         (owned (product-units-owned product)))
    (values owned blocked (- owned blocked) blocking)))

(defun peak-blocked (product-id first last &key exclude-order)
  "Values the most units of PRODUCT-ID that bookings (other than
EXCLUDE-ORDER's) block on any one date of FIRST..LAST, and the first date
with that peak: what a booking over those dates must fit beside (README
§5.2: every date of a multi-day order, point semantics on each)."
  (let ((bookings (remove-if (lambda (b) (equal (booking-order-id b) exclude-order))
                             (select 'booking :where `(:and (:= "product_id" ,product-id)
                                                            (:<= "from_date" ,last)
                                                            (:>= "to_date" ,first)))))
        (peak 0) (peak-date first))
    (when bookings
      (loop for date = first then (date-add-days date 1)
            while (date<= date last)
            do (let ((blocked (loop for b in bookings
                                    when (and (date<= (booking-from b) date) (date<= date (booking-to b)))
                                      sum (booking-quantity b))))
                 (when (> blocked peak)
                   (setf peak blocked peak-date date)))))
    (values peak peak-date)))

(defun period-availability (product first last &key exclude-order)
  "Values units-owned, blocked and available over FIRST..LAST (the worst
date), and that date."
  (multiple-value-bind (blocked date) (peak-blocked (entity-id product) first last :exclude-order exclude-order)
    (let ((owned (product-units-owned product)))
      (values owned blocked (- owned blocked) date))))

(defun order-booking-window (product order)
  "Values FROM and TO of a booking of PRODUCT for ORDER: the client's window
around event_date..(end_date ?? event_date), checked."
  (let ((first (order-event-date order))
        (last (order-last-date order)))
    (multiple-value-bind (from to) (booking-window *application* product first last)
      (unless (and (valid-date-string-p from) (valid-date-string-p to) (date<= from first) (date<= last to))
        (extension-error "BOOKING-WINDOW returned ~s..~s for ~a..~a" from to first last))
      (values from to))))

(defun rental-demand (order)
  "Alist product-id -> quantity over ORDER's rental lines."
  (let ((demand '()))
    (dolist (line (order-lines order) (nreverse demand))
      (let ((product (find-product (order-line-product-id line))))
        (when (rental-product-p product)
          (let ((cell (assoc (entity-id product) demand :test #'string=)))
            (if cell
                (incf (cdr cell) (order-line-quantity line))
                (push (cons (entity-id product) (order-line-quantity line)) demand))))))))

(defun book-order (order &key (code :unavailable))
  "Replace ORDER's bookings for its dates (event_date..end_date), checking
capacity on every one of them (CODE, unavailable by default, when a unit is
taken on any)."
  (let ((first (or (order-event-date order)
                   (fail :invalid-input "The order has no event date (event_date)")))
        (last (order-last-date order))
        (planned '()))
    (loop for (product-id . quantity) in (rental-demand order)
          for product = (find-product product-id)
          do (multiple-value-bind (owned blocked available date)
                 (period-availability product first last :exclude-order (entity-id order))
               (declare (ignore owned blocked))
               (when (> quantity available)
                 (fail code "~a: only ~d free on ~a (cleaning days included), the order needs ~d"
                       (product-name product) (max available 0) date quantity)))
             (multiple-value-bind (from to) (order-booking-window product order)
               (push (make-instance 'booking :order-id (entity-id order) :product-id product-id
                                             :quantity quantity :from from :to to)
                     planned)))
    (release-bookings order)
    (mapc #'insert (nreverse planned))
    order))

(defun release-bookings (order)
  (mapc #'delete-entity (order-booking-rows (entity-id order))))

;;; ------------------------------------------------------------------
;;; Updating an order (orders_update; explain runs the same)

(defun updated-order (input)
  "Values: the order orders_update would store for INPUT (not yet saved), its
department before the change, and its requirement snapshot before the change
on the current catalog."
  (flet ((given (key) (input-provided-p key input))
         (cleared (key) (input-null-p key input))
         (value (key) (input-value key input)))
    (let* ((order (find-order (value :id)))
           (previous-department (order-department order))
           (before (resolve-order order)))
      (when (string= (order-status order) "ready_for_invoice")
        (refuse-locked-order))
      (when (order-final-p order)
        (fail :invalid-transition "The order is ~a and cannot be changed"
              (status-text (order-status order))))
      (check-revision order (value :revision))
      (macrolet ((update (key accessor &optional (cleared-value nil))
                   `(cond ((given ,key) (setf (,accessor order) (value ,key)))
                          ((cleared ,key) (setf (,accessor order) ,cleared-value)))))
        (update :event-date order-event-date)
        (update :end-date order-end-date)
        (update :delivery-address order-delivery-address)
        (when (given :lines)
          (let ((old (order-lines order)))
            (setf (order-lines order) (keep-line-identities old (value :lines)))
            (stamp-choices (order-lines order) old)))
        (update :tags order-tags '())
        (update :department order-department)
        (update :price-mode order-price-mode "automatic")
        (update :discount-percent order-discount-percent)
        (update :discount-input-minor order-discount-input-minor)
        (update :price-reason order-price-reason))
      (when (and (null (order-event-date order))
                 (not (member (order-status order) '("draft" "quote_sent") :test #'string=)))
        (fail :invalid-input "The order is ~a and must have an event date"
              (status-text (order-status order))))
      (check-order-dates order)
      (when (given :logistics)
        (apply-logistics-input order (value :logistics)))
      (prepare-order order)
      (values order previous-department before))))

;;; ------------------------------------------------------------------
;;; explain (core.md §8.2, README §16): the same functions as the operations,
;;; nothing stored

(defun planned-bookings (order)
  "The bookings confirming ORDER would make: one per rental product, over
the client's booking window (no capacity check)."
  (if (null (order-event-date order))
      '()
      (loop for (product-id . quantity) in (rental-demand order)
            collect (multiple-value-bind (from to) (order-booking-window (find-product product-id) order)
                      (jobj "product_id" product-id "quantity" quantity "from" from "to" to)))))

(defun line-availability (order)
  "Per rental product: what confirming ORDER finds (book-order's check)."
  (let ((date (order-event-date order)))
    (loop for (product-id . quantity) in (rental-demand order)
          for product = (find-product product-id)
          collect (if (null date)
                      (jobj "product_id" product-id "product_name" (product-name product)
                            "quantity" quantity "date" :null "ok" nil)
                      (multiple-value-bind (owned blocked available)
                          (period-availability product date (order-last-date order) :exclude-order (entity-id order))
                        (multiple-value-bind (from to) (order-booking-window product order)
                          (jobj "product_id" product-id "product_name" (product-name product)
                                "date" date "quantity" quantity "units_owned" owned "blocked" blocked
                                "available" available "ok" (json-bool (>= available quantity))
                                "window" (jobj "from" from "to" to))))))))

(defun requirements-json (order)
  (jarr (mapcar (lambda (r) (jobj "product_id" (requirement-product-id r) "article_id" (requirement-article-id r)
                                  "quantity" (quantity-json (requirement-quantity r))))
                (order-requirements order))))

(defun order-would (order bookings)
  (jobj "catalog_total_minor" (order-catalog-total-minor order)
        "subtotal_minor" (order-subtotal-minor order)
        "discount_minor" (order-discount-minor order)
        "adjustment_minor" (order-adjustment-minor order)
        "total_minor" (order-total-minor order)
        "requirements" (requirements-json order)
        "bookings" (jarr bookings)))

(defmethod explain-would ((name (eql 'orders-create)) input)
  ;; orders_create books nothing: bookings exist only from confirmation (README §16).
  (order-would (prepare-new-order (input-draft input)) '()))

(defmethod explain-would ((name (eql 'orders-update)) input)
  (let ((order (updated-order input)))
    (if (string= (order-status order) "confirmed")
        ;; A confirmed order is booked again: the same capacity check runs.
        (let ((availability (line-availability order)))
          (let ((would (order-would order (planned-bookings order))))
            (setf (gethash "availability" would) (jarr availability))
            would))
        (order-would order (let ((*request-record* nil)) (planned-bookings order))))))

(defmethod explain-would ((name (eql 'orders-confirm)) input)
  (let ((order (find-order (input-value :id input))))
    (transition order '("accepted") "confirmed")
    ;; Same order as orders_confirm: book (capacity per line), then requirements.
    (let ((availability (line-availability order)))
      (setf (order-requirements order) (requirements-of (resolve-order order)))
      (jobj "availability" (jarr availability)
            "requirements" (requirements-json order)))))

;;; ------------------------------------------------------------------
;;; Status machine

(defun transition (order from to)
  (unless (member (order-status order) from :test #'string=)
    (fail :invalid-transition "The order is ~a and cannot become ~a"
          (status-text (order-status order)) (status-text to)))
  (setf (order-status order) to)
  order)

;;; ------------------------------------------------------------------
;;; Create, read, update

(defun keep-line-identities (old new)
  "Give each NEW line the id of the OLD line it continues: the one with the
same id, else the one at the same position with the same product.  Other
lines get fresh ids; an id that names no line of the order is invalid_input."
  (dolist (line new)
    (when (and (order-line-id line) (not (find (order-line-id line) old :key #'order-line-id :test #'equal)))
      (fail :invalid-input "The line ~a is not on the order" (order-line-id line))))
  (let ((claimed '()))
    (loop for line in new
          for i from 0
          for previous = (or (and (order-line-id line)
                                  (find (order-line-id line) old :key #'order-line-id :test #'equal))
                             (let ((at (nth i old)))
                               (and at (equal (order-line-product-id at) (order-line-product-id line))
                                    (not (find (order-line-id at) new :key #'order-line-id :test #'equal))
                                    at)))
          do (setf (order-line-id line)
                   (if (and previous (not (member (order-line-id previous) claimed :test #'string=)))
                       (progn (push (order-line-id previous) claimed) (order-line-id previous))
                       nil)))
    new))

(defun prepare-new-order (order)
  "Everything orders_create does before it stores ORDER (explain runs the same)."
  (dolist (line (order-lines order)) (setf (order-line-id line) nil))
  (check-order-dates order)
  (stamp-choices (order-lines order) '())
  (let ((raw (order-logistics order)))
    (setf (order-logistics order) nil)
    (when raw (apply-logistics-input order raw)))
  (prepare-order order))

(define-operation orders-create ((:draft order) (lines :type (list-of order-line :min-items 1 :max-items 100) :required t :label "Lines"))
    (:entity order :kind :create :title "Create an order" :live-view add-stock-warnings
     :description "Creates an order draft (a quote) for a customer, with or without a date. The lines are priced at the product's price now; price modes per line and for the order (automatic, percent_discount, fixed_discount, and manual_total on a line). Logistics: delivery and return, each with a method and a time window.")
  (persist-new-order order))

(defun persist-new-order (draft)
  (let ((order (insert (prepare-new-order draft))))
    ;; Plan revision 1, active at once (README §9.2, rule 3).
    (decide-plan order (jobj "type" "order_create" "id" (entity-id order)) (actor-string *actor*) 1)
    (store-derived order)
    (when (order-department order)
      (order-department-changed *application* order nil))
    (sync-checklist order)
    order))

(define-operation orders-get ((id :type (id order) :required t :label "Order ID"))
    (:entity order :kind :read :title "Get an order" :description "Gets one order.")
  (find-order id))

(define-operation orders-create-request ((customer-id :type (id customer) :required t)
                                        (lines :type (list-of order-line :max-items 100))
                                        (department :type (string :max 100)))
    (:entity order :kind :create :policy :employee :title "Create a request draft")
  (persist-new-order (make-instance 'order :customer-id customer-id :lines lines :department department)))

(defun orders-matching (&key customer-id status dateless dateless-given department tag from to)
  "Orders matching the filters, oldest first.  from/to select orders whose
period [event_date, end_date ?? event_date] overlaps [FROM, TO]."
  (let* ((where (remove nil (list (and customer-id `(:= "customer_id" ,customer-id))
                                  (and status `(:= "status" ,status))
                                  (and department `(:= "department" ,department))
                                  (and dateless-given (if dateless '(:null "event_date") '(:not-null "event_date")))
                                  (and (or from to) '(:not-null "event_date"))
                                  (and to `(:<= "event_date" ,to)))))
         (orders (select 'order :where (and where `(:and ,@where)))))
    (remove-if-not (lambda (o)
                     (and (or (null tag) (member tag (order-tags o) :test #'string=))
                          (or (null from) (date<= from (order-last-date o)))))
                   orders)))

(define-operation orders-list ((customer-id :type (id customer) :label "Customer ID")
                               (status :type (enum "draft" "quote_sent" "accepted" "confirmed"
                                                   "picked_up" "returned" "ready_for_invoice"
                                                   "completed" "cancelled")
                                       :label "Status")
                               (dateless :type boolean :label "Without a date"
                                         :description "true: only requests without a date; false: only orders with one.")
                               (department :type (string :max 100) :label "Department")
                               (tag :type (enum "rental" "entertainment") :label "Tag")
                               (from :type date :label "From date") (to :type date :label "To date")
                               (limit :type (integer :min 1 :max 100) :default 20 :label "Most results"))
    (:entity order :kind :read :title "Order list"
     :description "Lists orders, oldest first. Filters: customer, status, without a date, department, tag, and period (from/to overlaps the order's days).")
  (if (or (input-provided-p :dateless) (input-null-p :dateless) department tag from to)
      (page (orders-matching :customer-id customer-id :status status
                             :dateless dateless :dateless-given (input-provided-p :dateless)
                             :department department :tag tag :from from :to to)
            limit)
      (let ((where (remove nil (list (and customer-id `(:= "customer_id" ,customer-id))
                                     (and status `(:= "status" ,status))))))
        (page (select 'order :where (and where `(:and ,@where)) :limit (1+ limit)) limit))))

(define-operation orders-summary ()
    (:entity order :kind :read :title "Order overview"
     :description "Counts of orders: in all, not started, active, awaiting an answer to a quote, without a date, with and without agreed logistics, and closed.")
  (let ((orders (select 'order)))
    (flet ((count-if* (predicate) (count-if predicate orders))
           (in (statuses) (lambda (o) (member (order-status o) statuses :test #'string=))))
      (jobj "total" (length orders)
            "not_started" (count-if* (in +not-started-statuses+))
            "active" (count-if* (in +active-statuses+))
            ;; Quotes sent and waiting for the customer's answer.
            "awaiting_quote" (count-if (lambda (o)
                                         (and (string= (order-status o) "quote_sent")
                                              (let ((q (quote-for-order (entity-id o))))
                                                (and q (string= (quote-status q) "awaiting_response")))))
                                       orders)
            "dateless" (count-if* #'order-dateless-p)
            "logistics_settled" (count-if (lambda (o) (logistics-settled-p (order-logistics-object o))) orders)
            ;; Orders with a side (delivery or return) not agreed yet.
            "logistics_not_agreed" (count-if (lambda (o)
                                               (let ((l (order-logistics-object o)))
                                                 (or (not (side-agreed-p (jget l "delivery")))
                                                     (not (side-agreed-p (jget l "return"))))))
                                             orders)
            "closed" (count-if* (in +closed-statuses+))
            "today" (local-today)))))

(define-operation orders-update ((id :type (id order) :required t :label "Order ID")
                                 (revision :type integer :required t :label "Revision"
                                           :description "The revision you are changing; a wrong one is conflict.")
                                 (:field order event-date)
                                 (:field order end-date)
                                 (:field order delivery-address)
                                 (lines :type (list-of order-line :min-items 1 :max-items 100) :label "Lines")
                                 (:field order tags)
                                 (:field order department)
                                 (:field order price-mode)
                                 (:field order discount-percent)
                                 (:field order discount-input-minor)
                                 (:field order price-reason)
                                 (:field order logistics))
    (:entity order :kind :update :title "Change an order" :live-view add-stock-warnings
     :description "Changes the dates, address, lines, tags, department, price mode or logistics of an order that is neither closed nor locked. A confirmed order's availability is checked again and its reservations adjusted. A sent quote goes out of date.")
  (multiple-value-bind (order previous-department before) (updated-order *input*)
    ;; The order's own edit: rules 1-3 and 7 of README §9.2 (rule 2 refuses
    ;; a changed snapshot once consumption is applied; a neutral edit keeps
    ;; everything).
    (let ((next (1+ (order-revision order))))
      (decide-plan order (jobj "type" "order_update" "id" (format nil "~a:~d" id next)) (actor-string *actor*) next
                   :before before))
    (when (string= (order-status order) "confirmed")
      (book-order order))
    (sync-reservations order)
    (save order)
    (unless (equal previous-department (order-department order))
      (order-department-changed *application* order previous-department))
    (sync-checklist order)
    order))

(define-operation availability-check ((product-id :type (id product) :required t :label "Product ID")
                                      (date :type date :required t :label "Date")
                                      (quantity :type (integer :min 1 :max 100000) :default 1 :label "Quantity"))
    (:entity order :kind :read :title "Check availability"
     :description "Whether rental equipment is free on a date, with the bookings that block it (cleaning days included).")
  (let ((product (find-product product-id)))
    (multiple-value-bind (owned blocked available blocking) (availability product date)
      (jobj "product_id" product-id "date" date "quantity" quantity
            "units_owned" owned "blocked" blocked "available" available
            "ok" (json-bool (>= available quantity))
            "conflicts" (jarr (mapcar (lambda (b)
                                        (let ((o (fetch 'order (booking-order-id b))))
                                          (jobj "order_id" (booking-order-id b)
                                                "event_date" (if o (order-event-date o) :null)
                                                "from" (booking-from b) "to" (booking-to b))))
                                      blocking))))))

(defgeneric aggregate-order-communication (application order)
  (:method-combination traced-protocol)
  (:method ((application orders-module) order)
    (declare (ignore order))
    (jobj "outbound" 0 "inbound" 0 "failed" 0 "last_outbound_at" :null "last_inbound_at" :null)))
(register-extension-protocol 'aggregate-order-communication "before" :point "communication"
                            :description "Aggregate communication through the public message and inbox interfaces.")
(define-computed-field order communication (order) (:type json :label "Communication")
  (aggregate-order-communication *application* order))

(defun record-order-request (order-id request-id questions &optional delivery)
  "Store inbox provenance and open questions without changing the order revision."
  (let ((order (find-order order-id)))
    (setf (order-source order) (jobj "type" "inquiry" "id" request-id)
          (order-open-questions order) (coerce questions 'list))
    (when delivery
      (let ((logistics (order-logistics-object order)))
        (setf (gethash "method" (gethash "delivery" logistics)) delivery)
        (setf (order-logistics order) logistics)))
    (save order)))
