;;;; modules/catalog/catalog.lisp -- the catalog module: products, i.e.
;;;; rental equipment (rental), consumables (consumable) and services (service),
;;;; their ownership by department, and (requirements.lisp) what they
;;;; require from stock.  A client's per-100-servings recipe on a product
;;;; (products_set_recipe) stays a client operation, sugar over this
;;;; module's recipes and requirements (README §10).
;;;;
;;;; The catalog knows no stock article and no order.  What it needs from
;;;; them it asks through seams that the modules depending on it answer:
;;;;   STOCK-ARTICLE-FOR     stock_article        the article a new stock-tracked product counts in (inventory)
;;;;   CATALOG-ARTICLE       article_reference    an article's name and unit, or NIL when there is none (inventory)
;;;;   PRODUCT-BOOKED-PEAK   booked_peak          the most units of a rental product booked on any date (orders)
;;;;   CATALOG-DEPARTMENTS   catalog_departments  the departments a product or article may belong to (staffing)
;;;;   PRODUCT-TRANSFERRED   product_transferred  records a product's change of department (inventory's transfers)
;;;;   CATALOG-CHANGED       catalog_changed      a catalog change was recorded (orders: catalog_change)

(defpackage #:tun.catalog
  (:use #:cl #:tun.core)
  (:export #:product #:product-revision #:product-name #:product-kind #:product-unit
           #:product-unit-price-minor #:product-stock-tracked #:product-units-owned #:product-created-at
           #:product-article-id #:product-department #:product-department-revision #:product-requirements #:product-manual-url
           #:products-create #:products-get #:products-list #:products-update #:products-transfer
           #:find-product #:rental-product-p #:consumable-product-p #:stock-tracked-consumable-p
           #:link-product-article
           #:stock-article-for #:catalog-article #:product-booked-peak #:catalog-departments
           #:product-transferred #:catalog-changed #:check-catalog-department #:check-transfer
           #:product-requirement #:product-requirement-id #:product-requirement-name #:product-requirement-target
           #:product-requirement-quantity #:product-requirement-basis #:product-requirement-picks
           #:product-requirement-rounding #:product-requirement-position
           #:recipe #:recipe-name #:recipe-lines #:recipe-active #:recipe-item #:recipe-item-article-id
           #:recipe-item-quantity #:choice-group #:choice-group-members #:catalog-change #:catalog-change-resource-type
           #:catalog-change-resource-id #:catalog-change-product-id
           #:record-catalog-change #:set-lite-recipe #:resolve-line #:check-line-choices #:quantity-value
           #:recipes-create #:recipes-update #:recipes-get #:recipes-list #:recipes-archive
           #:choice-groups-create #:choice-groups-update #:choice-groups-get #:choice-groups-list
           #:choice-groups-archive #:catalog-changes-list #:products-set-requirements))

(in-package #:tun.catalog)

(declaim (optimize (safety 3) (debug 2)))

(define-module catalog
  (:core ">= 2.0.0" "< 3.0")
  (:documentation "Catalog: products for rent, consumption and services, and what they require from stock."))

;;; The requirement declarations a product carries (README §7): embedded in
;;; the product, so a product and its requirements change together.
(define-entity product-requirement (:embedded t :json-name "product_requirement"
                                    :label "Requirement")
  ((id :type id :label "ID")
   (name :type (string :max 120) :label "Name")
   (target :type json :label "Target" :description "{kind: article|recipe|choice_group, id}")
   (quantity :type (decimal :scale 3) :label "Quantity")
   (basis :type (enum "per_line" "per_quantity" "per_serving" "per_day") :label "Calculated from")
   (picks :type integer :label "Number of choices")
   (rounding :type (enum "exact" "ceil_per_100") :initform "exact" :label "Rounding")
   (position :type integer :label "Place")))

(define-entity product (:label "Product" :id-prefix "prd" :table "products" :indexes (("kind") ("article_id"))
                        :revisioned t)
  ((revision :type (integer :min 1) :input nil :initform 1 :label "Revision")
   (name :type (string :min 1 :max 120) :required t :label "Name")
   (kind :type (enum "rental" "consumable" "service") :required t :label "Product type"
         :description "rental (equipment), consumable or service.")
   (unit :type (string :min 1 :max 20) :required t :label "Unit")
   (unit-price-minor :type (money :min 0) :required t :label "Unit price")
   (stock-tracked :type boolean :required t :label "Stock-tracked")
   (units-owned :type (integer :min 0 :max 100000) :initform 0 :label "Units owned"
                :description "How many units can be rented out at once (rental).")
   (manual-url :type (string :max 2000) :label "Digital manual")
   (created-at :type timestamp :input nil :label "Created")
   (article-id :type id :input nil :label "Stock article"
               :description "The stock article the product is counted in; several products may share one.")
   (department :type (string :max 100) :label "Department"
               :description "The department that owns the product; changed afterwards only with products_transfer.")
   (department-revision :type (integer :min 1) :input nil :initform 1 :label "Department revision")
   (requirements :type (list-of product-requirement :max-items 50) :input nil :initform '()
                 :label "Requirements"
                 :description "What the product requires from stock per line, quantity, serving or day; set with products_set_requirements.")
   (lite-requirement-id :type id :input nil :label "Own recipe requirement"
                        :description "The requirement products_set_recipe created for the product.")
   (lite-recipe-id :type id :input nil :label "Own recipe"
                   :description "The recipe products_set_recipe created for the product; only that recipe is updated afterwards.")))

(defun find-product (id) (fetch! 'product id))
(define-rule valid-manual-url (product item)
  (:field manual-url :message "The manual must have a valid http(s) address")
  (or (null (product-manual-url item)) (cl-ppcre:scan "^https?://[^\\s]+$" (product-manual-url item))))
(defun rental-product-p (product) (string= (product-kind product) "rental"))
(defun consumable-product-p (product) (string= (product-kind product) "consumable"))
(defun stock-tracked-consumable-p (product)
  (and (consumable-product-p product) (product-stock-tracked product)))

;;; ------------------------------------------------------------------
;;; Seams

(defgeneric stock-article-for (application product)
  (:method-combination traced-protocol)
  (:documentation "The id of the stock article a new stock-tracked PRODUCT counts in (a
module keeping stock creates it), or NIL when no module keeps stock.")
  (:method ((application catalog-module) product)
    (declare (ignore product))
    nil))

(defgeneric catalog-article (application article-id)
  (:method-combination traced-protocol)
  (:documentation "Values the name, unit and active flag of the stock article ARTICLE-ID,
or NIL when there is no such article.")
  (:method ((application catalog-module) article-id)
    (declare (ignore article-id))
    nil))

(defgeneric product-booked-peak (application product)
  (:method-combination traced-protocol)
  (:documentation "The most units of rental PRODUCT that bookings of calendar-active
orders block on any one date (cleaning windows included); 0 without orders.")
  (:method ((application catalog-module) product)
    (declare (ignore product))
    0))

(defgeneric catalog-departments (application)
  (:method-combination traced-protocol)
  (:documentation "The departments a product or a stock article may belong to.")
  (:method ((application catalog-module))
    '()))

(defgeneric product-transferred (application product from to note)
  (:method-combination traced-protocol)
  (:documentation "Record that PRODUCT moved from department FROM to TO with NOTE, in the
transfer's transaction (a module keeping transfer records answers).")
  (:method ((application catalog-module) product from to note)
    (declare (ignore product from to note))
    (fail :invalid-transition "No module keeps transfers between departments here")))

(defgeneric catalog-changed (application change)
  (:method-combination traced-protocol)
  (:documentation "Called after the catalog change CHANGE was recorded, in its transaction.")
  (:method ((application catalog-module) change)
    (declare (ignore change))
    nil))

(register-extension-protocol 'stock-article-for "after" :point "stock_article"
                             :description "The stock article a new stock-tracked product counts in.")
(register-extension-protocol 'catalog-article "rule" :point "article_reference"
                             :description "A stock article's name and unit, or none.")
(register-extension-protocol 'product-booked-peak "rule" :point "booked_peak"
                             :description "The most units of a rental product booked on one date.")
(register-extension-protocol 'catalog-departments "rule" :point "catalog_departments"
                             :description "The departments products and articles may belong to.")
(register-extension-protocol 'product-transferred "after" :point "product_transferred"
                             :description "Records a product's change of department.")
(register-extension-protocol 'catalog-changed "after" :point "catalog_changed"
                             :description "Reacts to a recorded catalog change (catalog_change).")

(defun check-catalog-department (department)
  "DEPARTMENT is one of the client's departments (or NIL)."
  (when (and department (not (member department (catalog-departments *application*) :test #'string=)))
    (fail :invalid-input "Unknown department ~a (valid: ~{~a~^, ~})"
          department (catalog-departments *application*))))

(defun link-product-article (product-id article-id)
  "Link the product PRODUCT-ID to the stock article ARTICLE-ID (a module keeping
stock adopting what an older core stored; nothing else)."
  (let ((product (find-product product-id)))
    (setf (product-article-id product) article-id)
    (save product)))

;;; ------------------------------------------------------------------
;;; Operations

(define-operation products-create ((:draft product))
    (:entity product :kind :create :title "Create product"
     :description "Registers a rental product, a consumable or a service. A stock-tracked product gets its own stock article.")
  (check-catalog-department (product-department product))
  (setf (entity-id product) (new-ordered-id (entity-id-prefix (class-of product))))
  (when (product-stock-tracked product)
    (setf (product-article-id product) (stock-article-for *application* product)))
  (insert product))

(define-operation products-get ((id :type (id product) :required t :label "Product ID"))
    (:entity product :kind :read :title "Get product" :description "Gets one product.")
  (find-product id))

(define-operation products-list ((query :type (string :max 120) :label "Search in names")
                                 (kind :type (enum "rental" "consumable" "service")
                                       :label "Product type")
                                 (limit :type (integer :min 1 :max 100) :default 20
                                        :label "Most results"))
    (:entity product :kind :read :title "Product list" :description "Lists and searches products.")
  (let ((where (and kind `(:= "kind" ,kind))))
    (page (if query
              (remove-if-not (lambda (p) (contains-ci-p query (product-name p))) (select 'product :where where))
              (select 'product :where where :limit (1+ limit)))
          limit)))

(define-operation products-update ((id :type (id product) :required t :label "Product ID")
                                   (revision :type integer :label "Revision")
                                   (:field product name)
                                   (:field product kind)
                                   (:field product unit)
                                   (:field product unit-price-minor)
                                   (:field product units-owned)
                                   (:field product manual-url)
                                   (article-id :type id :label "Stock article ID"
                                               :description "Links the product to a stock article (admin); null removes the link.")
                                   (department :type json :label "Department"
                                               :description "Cannot be changed here; use products_transfer."))
    (:entity product :kind :update :title "Change product"
     :description "Changes the name, kind, unit, price or units owned. An admin can link the product to a stock article. Units owned cannot be set below what active orders have booked, and a rental product with bookings cannot change its kind.")
  (let ((product (find-product id)))
    (when (input-provided-p :department)
      (fail :invalid-input "The department is changed with products_transfer"))
    (when (and revision (/= revision (product-revision product)))
      (fail :conflict "The product has changed (revision ~d, not ~d)"
            (product-revision product) revision))
    (when (or (input-provided-p :article-id) (input-null-p :article-id))
      (unless (eq :admin (actor-role *actor*))
        (reject :forbidden "Only an administrator can link the product to a stock article"))
      (when (and article-id (null (catalog-article *application* article-id)))
        (fail :not-found "Found no stock article with the id ~a" article-id))
      (setf (product-article-id product) article-id
            (product-stock-tracked product) (and article-id t)))
    (when (input-provided-p :name) (setf (product-name product) name))
    (when (input-provided-p :unit) (setf (product-unit product) unit))
    (when (input-provided-p :unit-price-minor)
      (setf (product-unit-price-minor product) unit-price-minor))
    (when (or (input-provided-p :manual-url) (input-null-p :manual-url)) (setf (product-manual-url product) manual-url))
    ;; The capacity guard (README §3): never below what active orders booked.
    (let ((new-kind (if (input-provided-p :kind) kind (product-kind product)))
          (new-units (if (input-provided-p :units-owned) units-owned (product-units-owned product))))
      (when (and (rental-product-p product)
                 (or (string/= new-kind "rental") (/= new-units (product-units-owned product))))
        (let ((peak (product-booked-peak *application* product)))
          (cond ((and (string/= new-kind "rental") (plusp peak))
                 (fail :invalid-input "Availability cannot be turned off while up to ~d are booked in active orders."
                       peak))
                ((and (string= new-kind "rental") (< new-units peak))
                 (fail :invalid-input "The units owned cannot be set to ~d; up to ~d are already booked in active orders."
                       new-units peak)))))
      (setf (product-kind product) new-kind
            (product-units-owned product) new-units))
    (save product)))

(define-operation products-transfer ((id :type (id product) :required t :label "Product ID")
                                     (department :type (string :max 100) :label "To department")
                                     (note :type (string :max 1000) :label "Reason")
                                     (department-revision :type integer
                                                          :label "Department revision"))
    (:entity product :kind :update :policy :admin :title "Transfer product"
     :description "Moves the ownership of the product to another department, with a reason; recorded as a transfer. Units are never moved.")
  (let ((product (find-product id)))
    (multiple-value-bind (from to) (check-transfer (product-department product) (product-department-revision product)
                                                   department note department-revision)
      (setf (product-department product) to)
      (incf (product-department-revision product))
      (product-transferred *application* product from to (trim note))
      (save product))))

(defun check-transfer (current current-revision department note department-revision)
  "Values the department a transfer moves from and to, after its checks (README §4)."
  (when (blank-p department)
    (fail :invalid-input "Choose the department to transfer the stock to"))
  (check-catalog-department department)
  (when (equal department current)
    (fail :invalid-input "Choose another department"))
  (when (blank-p note)
    (fail :invalid-input "Give the reason for the transfer"))
  (unless (eql department-revision current-revision)
    (fail :conflict "The department has changed since you loaded the page; reload the page"))
  (values current department))
