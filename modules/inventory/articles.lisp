;;;; modules/inventory/articles.lisp -- the article tools (README §2), the
;;;; recount (§3.1) and department transfers (§11).

(in-package #:tun.inventory)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +order-url-pattern+ "^https?://[^@\\s/:?#]+(:\\d+)?([/?#]\\S*)?$"
  "An http or https URL with no user or password (README §2.1).")

(defun refuse-order-url ()
  "Refuse a supplier's order_url that is not a plain http(s) URL (README §2.1)."
  (fail :invalid-input
        "The order link must be an http or https address without a user name or password"))

(defun check-supplier (value existing)
  "The supplier object for VALUE (merged over EXISTING): name, contact,
article_no and order_url, each a string or null; order_url a plain http(s) URL."
  (unless (hash-table-p value)
    (fail :invalid-input "The supplier must be an object with name, contact, article_no and order_url"))
  (let ((merged (if (hash-table-p existing) (json-copy existing) (empty-supplier))))
    (dolist (key (jkeys value))
      (unless (member key '("name" "contact" "article_no" "order_url") :test #'string=)
        (fail :invalid-input "The supplier has no field ~a" key))
      (let ((v (jget value key)))
        (unless (or (json-null-p v) (and (stringp v) (<= (length v) (if (string= key "order_url") 2000 200))))
          (if (string= key "order_url")
              (refuse-order-url)
              (fail :invalid-input "The supplier field ~a must be text of at most 200 characters" key)))
        (when (and (string= key "order_url") (stringp v) (not (cl-ppcre:scan +order-url-pattern+ v)))
          (refuse-order-url))
        (setf (gethash key merged) (if (and (stringp v) (blank-p v)) :null v))))
    merged))

(defun apply-article-fields (article &key name sku unit package-size min-level max-level cost-price-minor
                                          supplier lead-days)
  "Set the given (non-NIL) fields of ARTICLE after their checks (create and update)."
  (when name
    (setf (article-name article) name))
  (when unit
    (setf (article-unit article) unit))
  (when sku
    (when (find-if (lambda (other) (not (equal (entity-id other) (entity-id article))))
                   (select 'article :where `(:= "sku" ,sku)))
      (fail :conflict "The SKU ~a is already in use" sku))
    (setf (article-sku article) sku))
  (when package-size
    (unless (plusp package-size) (fail :invalid-input "The package size must be more than 0"))
    (setf (article-package-size article) package-size))
  (when min-level
    (when (minusp min-level) (fail :invalid-input "The level cannot be negative"))
    (setf (article-min-level article) min-level))
  (when max-level
    (when (minusp max-level) (fail :invalid-input "The level cannot be negative"))
    (setf (article-max-level article) max-level))
  (when cost-price-minor (setf (article-cost-price-minor article) cost-price-minor))
  (when lead-days (setf (article-lead-days article) lead-days))
  (when supplier
    (setf (article-supplier article) (check-supplier supplier (article-supplier article))))
  article)

;;; ------------------------------------------------------------------
;;; Operations

(define-operation articles-create ((name :type (string :max 120) :label "Name")
                                   (sku :type (string :max 60) :label "SKU")
                                   (unit :type (string :max 20) :label "Unit")
                                   (package-size :type (decimal :scale 3) :label "Package size"
                                                 :description "The purchase package in the article's unit (> 0).")
                                   (min-level :type (decimal :scale 3) :label "Minimum")
                                   (max-level :type (decimal :scale 3) :label "Maximum")
                                   (cost-price-minor :type (money :min 0) :label "Cost price")
                                   (supplier :type json :label "Supplier"
                                             :description "{name, contact, article_no, order_url}")
                                   (lead-days :type (integer :min 0 :max 3650) :label "Lead time (days)")
                                   (department :type (string :max 100) :label "Department")
                                   (opening-balance :type (decimal :scale 3) :default 0
                                                    :label "Starting balance"))
    (:entity article :kind :create :policy :admin :title "Create stock article"
     :description "A stock article (the counted commodity) with its unit, package size, levels, supplier and lead time. The starting balance is written as one opening movement in the same transaction (0 too).")
  (when (or (null name) (null unit))
    (fail :invalid-input "Name and unit must be filled in"))
  (check-catalog-department department)
  (when (minusp opening-balance)
    (fail :invalid-input "The starting balance cannot be negative"))
  (let ((article (apply-article-fields (make-instance 'article :supplier (empty-supplier) :department department
                                                              :created-at (now))
                                       :name name :sku sku :unit unit :package-size package-size
                                       :min-level min-level :max-level max-level
                                       :cost-price-minor cost-price-minor :supplier supplier :lead-days lead-days)))
    (insert article)
    (ledger-row (lock-article (entity-id article)) "opening" opening-balance :balance opening-balance
                :reason (tr "Opening balance"))
    (find-article (entity-id article))))

(define-operation articles-get ((id :type (id article) :required t :label "Article ID"))
    (:entity article :kind :read :title "Get stock article"
     :description "One stock article with its balance.")
  (find-article id))

(define-operation articles-list ((query :type (string :max 120) :label "Search in names")
                                 (department :type (string :max 100) :label "Department")
                                 (active :type boolean :label "Only active"
                                         :description "true by default; false shows the archived ones.")
                                 (limit :type (integer :min 1 :max 100) :default 20 :label "Most results"))
    (:entity article :kind :read :title "Stock articles"
     :description "Stock articles by name; the query is a part of the name, matched without regard to case (% and _ are ordinary characters).")
  (let* ((active (if (or (input-provided-p :active) (input-null-p :active)) (and active t) t))
         (where `(:and (:= "active" ,active) ,@(and department `((:= "department" ,department)))))
         (rows (remove-if-not (lambda (a) (or (null query) (contains-ci-p query (article-name a))))
                              (select 'article :where where))))
    (page (stable-sort rows #'string-lessp :key #'article-name) limit)))

(define-operation articles-update ((id :type (id article) :required t :label "Article ID")
                                   (revision :type integer :label "Revision")
                                   (name :type (string :max 120) :label "Name")
                                   (sku :type (string :max 60) :label "SKU")
                                   (unit :type (string :max 20) :label "Unit")
                                   (package-size :type (decimal :scale 3) :label "Package size")
                                   (min-level :type (decimal :scale 3) :label "Minimum")
                                   (max-level :type (decimal :scale 3) :label "Maximum")
                                   (cost-price-minor :type (money :min 0) :label "Cost price")
                                   (supplier :type json :label "Supplier")
                                   (lead-days :type (integer :min 0 :max 3650) :label "Lead time (days)")
                                   (active :type boolean :label "Active")
                                   (balance :type json :label "Balance"
                                            :description "Cannot be set; it follows the ledger.")
                                   (department :type json :label "Department"
                                               :description "Cannot be changed here; use articles_transfer."))
    (:entity article :kind :update :policy :admin :title "Change stock article"
     :description "Changes everything but the balance, the movement revision and the department. active true makes an archived article active again.")
  (when (input-provided-p :balance)
    (fail :invalid-input "The balance changes only through stock movements"))
  (when (input-provided-p :department)
    (fail :invalid-input "The department is changed with articles_transfer"))
  (let ((article (lock-article id)))
    (when (and revision (/= revision (article-revision article)))
      (fail :conflict "The stock article has changed (revision ~d, not ~d)"
            (article-revision article) revision))
    (apply-article-fields article :name name :sku sku :unit unit :package-size package-size
                                  :min-level min-level :max-level max-level :cost-price-minor cost-price-minor
                                  :supplier supplier :lead-days lead-days)
    (when (input-provided-p :active)
      (setf (article-active article) active))
    (incf (article-revision article))
    (save article)))

(define-operation articles-archive ((id :type (id article) :required t :label "Article ID"))
    (:entity article :kind :update :policy :admin :title "Archive stock article"
     :description "Archives the article (active false); the ledger is kept, and consumption can still be recorded and reversed.")
  (let ((article (lock-article id)))
    (setf (article-active article) nil)
    (incf (article-revision article))
    (save article)))

(define-operation articles-recount ((article-id :type (id article) :required t :label "Article ID")
                                   (quantity :type (decimal :scale 3) :required t
                                             :label "Counted quantity")
                                   (reason :type (string :max 500) :label "Reason"))
    (:entity inventory-movement :kind :create :policy :admin :title "Stock count"
     :description "Writes a recount: the balance becomes the counted quantity. Needs a reason; the article must be active.")
  (let ((article (lock-article article-id)))
    (require-active article)
    (when (blank-p reason)
      (fail :invalid-input "Give the reason for the stock correction"))
    (when (minusp quantity)
      (fail :invalid-input "The counted quantity cannot be negative"))
    (ledger-row article "recount" quantity :balance quantity :reason (trim reason))))

(define-operation articles-transfer ((id :type (id article) :required t :label "Article ID")
                                     (department :type (string :max 100) :label "To department")
                                     (note :type (string :max 1000) :label "Reason")
                                     (department-revision :type integer
                                                          :label "Department revision"))
    (:entity article :kind :update :policy :admin :title "Transfer stock article"
     :description "Moves the ownership of the article to another department, with a reason; recorded as a transfer. The balance is never moved.")
  (let ((article (lock-article id)))
    (multiple-value-bind (from to) (check-transfer (article-department article) (article-department-revision article)
                                                   department note department-revision)
      (setf (article-department article) to)
      (incf (article-department-revision article))
      (insert (make-instance 'transfer :target-type "article" :target-id id :from-department from
                                       :to-department to :note (trim note) :by (actor-string *actor*) :at (now)))
      (save article))))

(define-operation transfers-list ((target-type :type (enum "article" "product") :required t
                                                :label "Type")
                                  (target-id :type id :required t :label "Subject")
                                  (limit :type (integer :min 1 :max 100) :default 20
                                         :label "Most results"))
    (:entity transfer :kind :read :title "Transfers"
     :description "The transfers of an article or a product between departments, newest first.")
  (page (select 'transfer :where `(:and (:= "target_type" ,target-type) (:= "target_id" ,target-id))
                          :order-by '(("seq" :desc)) :limit (1+ limit))
        limit))
