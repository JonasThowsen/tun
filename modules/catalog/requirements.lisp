;;;; modules/catalog/requirements.lisp -- what products require from stock
;;;; (README §6-§11): recipes, choice groups, requirement declarations, the
;;;; resolver, order-line choices, and catalog changes (§11).
;;;;
;;;; The catalog resolves; it does not plan.  RESOLVE-LINE turns one order
;;;; line (its product, quantity, servings, choices, and the order's days)
;;;; into entries (article, quantity, source); the orders module aggregates
;;;; them into requirement plans.  Every write to a requirement, recipe or
;;;; choice group records a catalog change and calls the catalog_changed seam.

(in-package #:tun.catalog)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Entities

(define-entity recipe-item (:embedded t :json-name "recipe_item" :label "Recipe line")
  ((id :type id :label "ID")
   (article-id :type id :label "Stock article")
   (quantity :type (decimal :scale 3) :label "Quantity per use")
   (position :type integer :label "Place")))

(define-entity recipe (:label "Recipe" :id-prefix "opp" :table "recipes")
  ((revision :type (integer :min 1) :input nil :initform 1 :label "Revision")
   (name :type (string :min 1 :max 120) :input nil :label "Name")
   (description :type (string :max 2000) :input nil :label "Description")
   (active :type boolean :input nil :initform t :label "Active")
   (lines :type (list-of recipe-item :max-items 100) :input nil :initform '() :label "Lines")))

(define-entity choice-group (:json-name "choice_group" :label "Choice group" :id-prefix "vgr"
                             :table "choice_groups")
  ((revision :type (integer :min 1) :input nil :initform 1 :label "Revision")
   (name :type (string :min 1 :max 120) :input nil :label "Name")
   (active :type boolean :input nil :initform t :label "Active")
   (members :type (list-of id :max-items 100) :input nil :initform '() :label "Recipes")))

(define-entity catalog-change (:json-name "catalog_change" :label "Catalog change" :id-prefix "kat"
                               :table "catalog_changes")
  ((resource-type :type (enum "requirement" "recipe" "choice_group") :input nil :label "Resource")
   (resource-id :type id :input nil :label "Resource ID")
   (operation :type (enum "created" "updated" "deleted") :input nil :label "Operation")
   (changed-fields :type (list-of (string :max 60)) :input nil :initform '()
                   :label "Changed fields")
   (at :type timestamp :input nil :label "Time")
   (by :type (string :max 200) :input nil :label "Done by")
   (product-id :type id :input nil :label "Product"
               :description "For a requirement: the product that carries it (catalog impact reaches its orders).")))

(defvar *record-catalog-changes* t
  "NIL while an older database's catalog is adopted at start: a migration,
not a change anyone made, so nothing is recorded and no plan is touched.")

(defun record-catalog-change (resource-type resource-id operation &optional changed-fields product-id)
  "Record one catalog change (README §11) and tell the modules that react."
  (unless *record-catalog-changes*
    (return-from record-catalog-change nil))
  (let ((change (insert (make-instance 'catalog-change :resource-type resource-type :resource-id resource-id
                                                       :operation operation :product-id product-id
                                                       :changed-fields (sort (copy-list changed-fields) #'string<)
                                                       :at (now) :by (actor-string *actor*)))))
    (catalog-changed *application* change)
    change))

;;; ------------------------------------------------------------------
;;; Quantities: decimals with at most three fractional digits (README §5)

(defconstant +max-declared-quantity+ (expt 10 9)
  "Largest requirement or recipe quantity (README §5).")

(defun quantity-value (value message &key (positive t) (max +max-declared-quantity+))
  "VALUE (JSON) as a rational quantity; invalid_input with MESSAGE, a TEXT
(DEFERRED-TR), when it is missing, not a number, negative or (POSITIVE)
zero, and when above MAX."
  (when (or (null value) (json-null-p value) (eq value t) (not (realp value)))
    (fail :invalid-input "~a" message))
  (when (and (floatp value) (> (abs value) (* 10 max)))
    (fail :invalid-input "The quantity can be at most ~d" max))
  (let ((q (json-number->rational value)))
    (unless (integerp (* q 1000))
      (fail :invalid-input "Quantities can have at most three decimals"))
    (when (or (minusp q) (and positive (zerop q)))
      (fail :invalid-input "~a" message))
    (when (> q max)
      (fail :invalid-input "The quantity can be at most ~d" max))
    q))

;;; ------------------------------------------------------------------
;;; Recipes and choice groups

(defun find-recipe (id)
  (or (and (stringp id) (fetch 'recipe id)) (fail :not-found "Found no recipe with the id ~a" id)))

(defun find-choice-group (id)
  (or (and (stringp id) (fetch 'choice-group id)) (fail :not-found "Found no choice group with the id ~a" id)))

(defun check-article (id)
  (unless (and (stringp id) (catalog-article *application* id))
    (fail :not-found "Found no stock article with the id ~a" id)))

(defun recipe-items (lines previous)
  "Recipe lines from the JSON LINES ([{id?, article_id, quantity}]), keeping
the ids of PREVIOUS lines they name."
  (unless (json-array-p lines) (fail :invalid-input "The lines must be a list"))
  (loop for line across lines
        for position from 0
        collect (progn
                  (unless (hash-table-p line) (fail :invalid-input "A recipe line must be an object"))
                  (let ((id (jget line "id")) (article-id (jget line "article_id")))
                    (check-article article-id)
                    (when (and (stringp id) (not (find id previous :key #'recipe-item-id :test #'equal)))
                      (fail :invalid-input "Unknown recipe line ~a" id))
                    (make-instance 'recipe-item :id (if (stringp id) id (new-id "rln")) :article-id article-id
                                                :quantity (quantity-value
                                                           (jget line "quantity")
                                                           (deferred-tr "The quantity must be more than 0"))
                                                :position position)))))

(defun recipe-items-json (items)
  (to-json-string (jarr (mapcar #'entity->storage-json items))))

(defun new-recipe (name description lines)
  (let ((recipe (insert (make-instance 'recipe :name name :description description
                                               :lines (recipe-items (or lines (jarr '())) '())))))
    (record-catalog-change "recipe" (entity-id recipe) "created")
    recipe))

(defun update-recipe (recipe &key (name nil name-p) (description nil description-p) (lines nil lines-p)
                                  (active nil active-p))
  "Apply the given changes to RECIPE; a change bumps its revision and is a catalog change."
  (let ((changed '()))
    (when (and name-p name (string/= name (recipe-name recipe)))
      (setf (recipe-name recipe) name) (push "name" changed))
    (when (and description-p (not (equal description (recipe-description recipe))))
      (setf (recipe-description recipe) description) (push "description" changed))
    (when (and lines-p lines)
      (let ((before (recipe-items-json (recipe-lines recipe)))
            (items (recipe-items lines (recipe-lines recipe))))
        (unless (string= before (recipe-items-json items))
          (setf (recipe-lines recipe) items) (push "lines" changed))))
    (when (and active-p (not (eq (and active t) (recipe-active recipe))))
      (setf (recipe-active recipe) (and active t)) (push "active" changed))
    (when changed
      (incf (recipe-revision recipe))
      (save recipe)
      (record-catalog-change "recipe" (entity-id recipe) "updated" changed))
    recipe))

(defun group-members (members)
  (unless (json-array-p members) (fail :invalid-input "The members must be a list of recipe ids"))
  (let ((list (coerce members 'list)))
    (unless (= (length list) (length (remove-duplicates list :test #'equal)))
      (fail :invalid-input "A recipe can be in a choice group only once"))
    (mapc #'find-recipe list)
    list))

(defun update-choice-group (group &key (name nil name-p) (members nil members-p) (active nil active-p))
  (let ((changed '()))
    (when (and name-p name (string/= name (choice-group-name group)))
      (setf (choice-group-name group) name) (push "name" changed))
    (when (and members-p members)
      (let ((list (group-members members)))
        (unless (equal list (choice-group-members group))
          (setf (choice-group-members group) list) (push "members" changed))))
    (when (and active-p (not (eq (and active t) (choice-group-active group))))
      (setf (choice-group-active group) (and active t)) (push "active" changed))
    (when changed
      (incf (choice-group-revision group))
      (save group)
      (record-catalog-change "choice_group" (entity-id group) "updated" changed))
    group))

;;; ------------------------------------------------------------------
;;; Requirement declarations (README §7)

(defparameter +bases+ '("per_line" "per_quantity" "per_serving" "per_day"))

(defun requirement-target-kind (requirement) (jget (product-requirement-target requirement) "kind"))
(defun requirement-target-id (requirement) (jget (product-requirement-target requirement) "id"))

(defun checked-requirement (json position)
  "A requirement declaration from JSON, checked in the order of README §7.2."
  (unless (hash-table-p json) (fail :invalid-input "A requirement must be an object"))
  (dolist (key (jkeys json))
    (unless (member key '("id" "name" "target" "quantity" "basis" "picks" "rounding" "position") :test #'string=)
      (fail :invalid-input "The requirement has no field ~a" key)))
  (flet ((value (key) (let ((v (jget json key))) (if (json-null-p v) nil v))))
    (let ((target (or (value "target") (jobj))))
      (unless (hash-table-p target) (fail :invalid-input "The requirement's target must be an object with kind and id"))
      (when (or (null (value "quantity")) (null (value "basis")))
        (fail :invalid-input "Fill in the quantity and what the requirement is calculated from"))
      (let ((quantity (quantity-value (value "quantity")
                                      (deferred-tr "Fill in the quantity and what the requirement is calculated from")))
            (basis (value "basis"))
            (kind (jget target "kind"))
            (id (jget target "id"))
            (picks (value "picks"))
            (rounding (or (value "rounding") "exact"))
            (name (value "name")))
        (unless (member basis +bases+ :test #'equal)
          (fail :invalid-input "Unknown basis ~a; use ~{~a~^, ~}" basis +bases+))
        (unless (member kind '("article" "recipe" "choice_group") :test #'equal)
          (fail :invalid-input "The requirement must be for a stock article, a recipe or a choice group"))
        (unless (and (stringp id) (plusp (length id)))
          (cond ((string= kind "article")
                 (fail :invalid-input "Choose a stock article for this requirement"))
                ((string= kind "recipe")
                 (fail :invalid-input "Choose a recipe for this requirement"))
                (t (fail :invalid-input "Choose a choice group for this requirement"))))
        (cond ((string= kind "article") (check-article id))
              ((string= kind "recipe") (find-recipe id))
              (t (find-choice-group id)))
        (cond ((string= kind "choice_group")
               (unless (and (integerp picks) (>= picks 1))
                 (fail :invalid-input "The number of choices must be at least 1"))
               (unless (string= basis "per_serving")
                 (fail :invalid-input "A choice group requirement must be calculated per serving")))
              (picks
               (fail :invalid-input "A number of choices is allowed only on a choice group requirement")))
        (unless (member rounding '("exact" "ceil_per_100") :test #'equal)
          (fail :invalid-input "The rounding must be exact or ceil_per_100"))
        (unless (or (null name) (and (stringp name) (<= (length name) 120)))
          (fail :invalid-input "The name can be at most 120 characters"))
        (make-instance 'product-requirement :id (value "id")
                                            :name (and name (not (blank-p name)) (trim name))
                                            :target (jobj "kind" kind "id" id) :quantity quantity :basis basis
                                            :picks picks :rounding rounding :position position)))))

(defun requirement-changes (old new)
  "The fields of requirement NEW that differ from OLD."
  (let ((changed '()))
    (flet ((differ (name a b) (unless (equal a b) (push name changed))))
      (differ "name" (product-requirement-name old) (product-requirement-name new))
      (differ "target" (to-json-string (product-requirement-target old) :canonical t)
              (to-json-string (product-requirement-target new) :canonical t))
      (differ "quantity" (product-requirement-quantity old) (product-requirement-quantity new))
      (differ "basis" (product-requirement-basis old) (product-requirement-basis new))
      (differ "picks" (product-requirement-picks old) (product-requirement-picks new))
      (differ "rounding" (product-requirement-rounding old) (product-requirement-rounding new))
      (differ "position" (product-requirement-position old) (product-requirement-position new)))
    changed))

(defun check-active-target (requirement)
  "A new or retargeted REQUIREMENT's target is active: what was archived is
not taken into use again (an existing requirement on it stays, and is
still resolved, consumed and forecast)."
  (let ((kind (requirement-target-kind requirement))
        (id (requirement-target-id requirement)))
    (cond ((string= kind "article")
           (unless (nth-value 2 (catalog-article *application* id))
             (fail :invalid-input "The stock article is archived")))
          ((string= kind "recipe")
           (unless (recipe-active (find-recipe id))
             (fail :invalid-input "The recipe is archived")))
          (t
           (unless (choice-group-active (find-choice-group id))
             (fail :invalid-input "The choice group is archived"))))))

(defun set-product-requirements (product requirements)
  "Replace PRODUCT's requirements by REQUIREMENTS (checked declarations, ids
of existing ones kept): each created, updated or deleted requirement is a
catalog change.  Saves PRODUCT."
  (let ((old (product-requirements product)))
    (dolist (r requirements)
      (let ((id (product-requirement-id r)))
        (cond ((null id)
               (check-active-target r)
               (setf (product-requirement-id r) (new-id "krv"))
               (record-catalog-change "requirement" (product-requirement-id r) "created" '() (entity-id product)))
              (t
               (let ((previous (find id old :key #'product-requirement-id :test #'equal)))
                 (unless previous (fail :invalid-input "Unknown requirement ~a for this product" id))
                 (setf old (remove previous old))
                 (let ((changed (requirement-changes previous r)))
                   (when (member "target" changed :test #'string=)
                     (check-active-target r))
                   (when changed (record-catalog-change "requirement" id "updated" changed (entity-id product)))))))))
    (dolist (gone old)
      (record-catalog-change "requirement" (product-requirement-id gone) "deleted" '() (entity-id product)))
    (setf (product-requirements product) requirements)
    (save product)))

(defun recipe-components (recipe)
  "RECIPE's lines as (article-id . per-100-servings), the per-100-servings shape (README §10)."
  (mapcar (lambda (item) (cons (recipe-item-article-id item) (* 100 (recipe-item-quantity item))))
          (recipe-lines recipe)))

(defun recipe-used-elsewhere-p (recipe-id product-id)
  "Whether a product other than PRODUCT-ID requires RECIPE-ID, directly or as a
member of a choice group it requires."
  (let ((groups (loop for group in (select 'choice-group)
                      when (member recipe-id (choice-group-members group) :test #'equal)
                        collect (entity-id group))))
    (some (lambda (other)
            (and (string/= (entity-id other) product-id)
                 (some (lambda (r)
                         (let ((kind (requirement-target-kind r)) (id (requirement-target-id r)))
                           (or (and (equal kind "recipe") (equal id recipe-id))
                               (and (equal kind "choice_group") (member id groups :test #'equal)))))
                       (product-requirements other))))
          (select 'product))))

(defun own-lite-requirement (product previous)
  "PRODUCT's own per-100-servings requirement (README §10), if it still
targets the recipe created with it: the one recorded on PRODUCT.  A product
given that requirement by an older core has nothing recorded; then it is the
per_serving ceil_per_100 requirement of quantity 1 on a recipe whose lines
are exactly PREVIOUS, the components of the recipe this call replaces."
  (let ((recorded (product-lite-requirement-id product)))
    (find-if (lambda (r)
               (and (equal "recipe" (requirement-target-kind r))
                    (if recorded
                        (and (equal recorded (product-requirement-id r))
                             (equal (product-lite-recipe-id product) (requirement-target-id r)))
                        (let ((recipe (fetch 'recipe (requirement-target-id r))))
                          (and previous recipe
                               (string= (product-requirement-rounding r) "ceil_per_100")
                               (equal "per_serving" (product-requirement-basis r))
                               (eql 1 (product-requirement-quantity r))
                               (equal previous (recipe-components recipe)))))))
             (product-requirements product))))

(defun set-lite-recipe (product components &key (adopting nil) (previous nil))
  "A client's products_set_recipe as sugar (README §10): COMPONENTS, a
list of (article-id . per-100-servings), become the lines (quantity per_100
/ 100) of PRODUCT's own recipe, which one per_serving requirement with
rounding ceil_per_100 targets.  The recipe and requirement this created are
recorded on PRODUCT; only that recipe is ever updated, and only while it is
active and no other product requires it.  Otherwise a new recipe named
after PRODUCT is created (the own requirement, if PRODUCT still has it, is
retargeted to it): a recipe shared with another product is never rewritten.
PREVIOUS: the components of the recipe being replaced (see
OWN-LITE-REQUIREMENT).  Saves PRODUCT.  ADOPTING: an older core's recipe
taken over at start, which records no catalog change (the numbers the older
core planned with are unchanged)."
  (let* ((*record-catalog-changes* (not adopting))
         (own (own-lite-requirement product previous))
         (recipe (and own (fetch 'recipe (requirement-target-id own))))
         (lines (jarr (loop for (article-id . per-100) in components
                            collect (jobj "article_id" article-id "quantity" (/ per-100 100))))))
    (cond ((and recipe (recipe-active recipe)
                (not (recipe-used-elsewhere-p (entity-id recipe) (entity-id product))))
           (update-recipe recipe :lines lines))
          (t
           (setf recipe (new-recipe (product-name product) nil lines))
           (cond (own
                  (setf (product-requirement-target own) (jobj "kind" "recipe" "id" (entity-id recipe)))
                  (record-catalog-change "requirement" (product-requirement-id own) "updated" '("target")
                                         (entity-id product)))
                 (t
                  (setf own (make-instance 'product-requirement
                                           :id (new-id "krv") :name (product-name product)
                                           :target (jobj "kind" "recipe" "id" (entity-id recipe))
                                           :quantity 1 :basis "per_serving" :rounding "ceil_per_100"
                                           :position (length (product-requirements product))))
                  (record-catalog-change "requirement" (product-requirement-id own) "created" '() (entity-id product))
                  (setf (product-requirements product) (append (product-requirements product) (list own)))))))
    (setf (product-lite-requirement-id product) (product-requirement-id own)
          (product-lite-recipe-id product) (entity-id recipe))
    (save product)))

;;; ------------------------------------------------------------------
;;; The resolver (README §8)

(defun source-key (&rest parts)
  (format nil "krav:~{~a~^:~}" (remove nil parts)))

(defun resolve-line (product-id &key (quantity 1) servings choices (days 1))
  "Entries (article-id quantity source) one order line of PRODUCT-ID needs:
QUANTITY units, SERVINGS (NIL counts as 0), CHOICES (an object requirement
id -> recipe ids, in placement order) and DAYS (inclusive days of the order;
1 for single-day and dateless).  SOURCE is a JSON object (requirement,
recipe, pick, position, source_key)."
  (let ((product (fetch 'product product-id))
        (servings (or servings 0))
        (entries '()))
    (labels ((emit (r recipe pick position item article-id q)
               (let ((q (if (string= (product-requirement-rounding r) "ceil_per_100") (ceiling q) q)))
                 (push (list article-id q
                             (jobj "requirement_id" (product-requirement-id r)
                                   "requirement_name" (or (product-requirement-name r) :null)
                                   "recipe_id" (if recipe (entity-id recipe) :null)
                                   "pick_name" (or pick :null)
                                   "position" (or position :null)
                                   "source_key" (source-key (product-requirement-id r)
                                                            (and recipe (entity-id recipe)) position
                                                            (and item (recipe-item-id item)) article-id)))
                       entries)))
             (multiplier (basis)
               (cond ((string= basis "per_line") 1)
                     ((string= basis "per_quantity") quantity)
                     ((string= basis "per_serving") servings)
                     (t days))))
      (when product
        (dolist (r (sort (copy-list (product-requirements product)) #'< :key #'product-requirement-position))
          (let ((n (* (product-requirement-quantity r) (multiplier (product-requirement-basis r))))
                (kind (requirement-target-kind r))
                (target (requirement-target-id r)))
            (cond ((string= kind "article")
                   (emit r nil nil nil nil target n))
                  ((string= kind "recipe")
                   (let ((recipe (fetch 'recipe target)))
                     (when recipe
                       (dolist (item (recipe-lines recipe))
                         (emit r recipe nil nil item (recipe-item-article-id item) (* (recipe-item-quantity item) n))))))
                  (t
                   (let ((picks (coerce (or (jget choices (product-requirement-id r)) #()) 'list))
                         (k (product-requirement-picks r))
                         (group (fetch 'choice-group target)))
                     (when (and picks k (plusp k) (zerop (mod servings k)) group)
                       (let ((base (* (/ servings k) (product-requirement-quantity r))))
                         (loop for recipe-id in picks
                               for position from 1
                               for recipe = (fetch 'recipe recipe-id)
                               when (and recipe (member recipe-id (choice-group-members group) :test #'equal))
                                 do (dolist (item (recipe-lines recipe))
                                      (emit r recipe (recipe-name recipe) position item (recipe-item-article-id item)
                                            (* (recipe-item-quantity item) base)))))))))))))
    (nreverse entries)))

(defun check-line-choices (product-id quantity servings choices)
  "The choices of one order line (README §9): a line with a choice-group
requirement has quantity 1, exactly picks active members per group, and
servings divisible by picks.  Missing choices count as zero picks."
  (let* ((product (find-product product-id))
         (groups (remove-if-not (lambda (r) (equal "choice_group" (requirement-target-kind r)))
                                (product-requirements product))))
    (when (hash-table-p choices)
      (dolist (key (jkeys choices))
        (unless (find key groups :key #'product-requirement-id :test #'equal)
          (fail :invalid-input "The choice ~a does not belong to a choice group requirement of the product"
                key))))
    (when groups
      (unless (eql quantity 1)
        (fail :invalid-input "An order line with a choice group requirement must have quantity 1. Add one line per unit."))
      (dolist (r groups)
        (let ((name (or (product-requirement-name r) (deferred-tr "Choice group requirement")))
              (picks (coerce (or (jget choices (product-requirement-id r)) #()) 'list))
              (k (product-requirement-picks r))
              (group (fetch 'choice-group (requirement-target-id r))))
          (unless (= (length picks) k)
            (fail :invalid-input "~a needs ~d choices (~d chosen)" name k (length picks)))
          (unless (zerop (mod (or servings 0) k))
            (fail :invalid-input "The servings must be shared evenly between ~d choices" k))
          (unless (every (lambda (id)
                           (let ((recipe (fetch 'recipe id)))
                             (and recipe (recipe-active recipe) group (choice-group-active group)
                                  (member id (choice-group-members group) :test #'equal))))
                         picks)
            (fail :invalid-input "~a holds choices that are not valid" name)))))))

;;; ------------------------------------------------------------------
;;; Operations

(define-operation products-set-requirements ((product-id :type (id product) :schema-required t
                                                         :label "Product ID")
                                             (service-id :type (id product) :label "Service ID"
                                                         :description "Instead of product_id, for a service.")
                                             (requirements :type (list-of json :max-items 50) :required t
                                                           :label "Requirements"
                                                           :description "[{id?, name?, target:{kind,id}, quantity, basis, picks?, rounding?}]; replaces the list."))
    (:entity product :kind :update :policy :admin :title "Set requirements"
     :description "Replaces the product's (or the service's) requirements: a stock article, a recipe or a choice group, calculated per line, quantity, serving or day. Each requirement created, changed or deleted is a catalog change.")
  (let ((product (find-product (or product-id service-id
                                   (fail :invalid-input "Missing required field: input.product_id")))))
    (set-product-requirements product (loop for r in requirements for i from 0 collect (checked-requirement r i)))))

(define-operation recipes-create ((name :type (string :max 120) :required t :label "Name")
                                  (description :type (string :max 2000) :label "Description")
                                  (lines :type json :label "Lines" :description "[{article_id, quantity}]"))
    (:entity recipe :kind :create :policy :admin :title "Create recipe"
     :description "A recipe: stock articles and the quantity of each per use. A catalog change.")
  (new-recipe name description (or lines (jarr '()))))

(define-operation recipes-update ((id :type (id recipe) :required t :label "Recipe ID")
                                  (name :type (string :max 120) :label "Name")
                                  (description :type (string :max 2000) :label "Description")
                                  (lines :type json :label "Lines"
                                         :description "[{id?, article_id, quantity}]")
                                  (active :type boolean :label "Active"))
    (:entity recipe :kind :update :policy :admin :title "Change recipe"
     :description "Changes the name, description, lines or active; a change is a catalog change.")
  (let ((recipe (find-recipe id)))
    (apply #'update-recipe recipe
           (append (and (input-provided-p :name) (list :name name))
                   (and (or (input-provided-p :description) (input-null-p :description)) (list :description description))
                   (and (input-provided-p :lines) (list :lines lines))
                   (and (input-provided-p :active) (list :active active))))))

(define-operation recipes-get ((id :type (id recipe) :required t :label "Recipe ID"))
    (:entity recipe :kind :read :title "Get recipe" :description "One recipe.")
  (find-recipe id))

(define-operation recipes-list ((query :type (string :max 120) :label "Search in names")
                                (active :type boolean :label "Active")
                                (limit :type (integer :min 1 :max 100) :default 20 :label "Most results"))
    (:entity recipe :kind :read :title "Recipes" :description "Recipes, oldest first.")
  (let ((rows (remove-if-not (lambda (r) (and (or (null query) (contains-ci-p query (recipe-name r)))
                                              (or (not (input-provided-p :active)) (eq (and active t) (recipe-active r)))))
                             (select 'recipe))))
    (page rows limit)))

(define-operation recipes-archive ((id :type (id recipe) :required t :label "Recipe ID"))
    (:entity recipe :kind :update :policy :admin :title "Archive recipe"
     :description "The recipe can no longer be chosen; a catalog change.")
  (update-recipe (find-recipe id) :active nil))

(define-operation choice-groups-create ((name :type (string :max 120) :required t :label "Name")
                                        (members :type json :label "Recipes"
                                                 :description "Recipe ids, in order."))
    (:entity choice-group :kind :create :policy :admin :title "Create choice group"
     :description "A group of recipes the customer chooses among (flavours). A catalog change.")
  (let ((group (insert (make-instance 'choice-group :name name :members (group-members (or members (jarr '())))))))
    (record-catalog-change "choice_group" (entity-id group) "created")
    group))

(define-operation choice-groups-update ((id :type (id choice-group) :required t
                                            :label "Choice group ID")
                                        (name :type (string :max 120) :label "Name")
                                        (members :type json :label "Recipes")
                                        (active :type boolean :label "Active"))
    (:entity choice-group :kind :update :policy :admin :title "Change choice group"
     :description "Changes the name, members or active; a change is a catalog change.")
  (apply #'update-choice-group (find-choice-group id)
         (append (and (input-provided-p :name) (list :name name))
                 (and (input-provided-p :members) (list :members members))
                 (and (input-provided-p :active) (list :active active)))))

(define-operation choice-groups-get ((id :type (id choice-group) :required t
                                         :label "Choice group ID"))
    (:entity choice-group :kind :read :title "Get choice group" :description "One choice group.")
  (find-choice-group id))

(define-operation choice-groups-list ((active :type boolean :label "Active")
                                      (limit :type (integer :min 1 :max 100) :default 20
                                             :label "Most results"))
    (:entity choice-group :kind :read :title "Choice groups"
     :description "Choice groups, oldest first.")
  (page (remove-if-not (lambda (g) (or (not (input-provided-p :active)) (eq (and active t) (choice-group-active g))))
                       (select 'choice-group))
        limit))

(define-operation choice-groups-archive ((id :type (id choice-group) :required t
                                             :label "Choice group ID"))
    (:entity choice-group :kind :update :policy :admin :title "Archive choice group"
     :description "The choice group is no longer active; a catalog change.")
  (update-choice-group (find-choice-group id) :active nil))

(define-operation catalog-changes-list ((limit :type (integer :min 1 :max 100) :default 20
                                                :label "Most results"))
    (:entity catalog-change :kind :read :title "Catalog changes"
     :description "The catalog changes (requirements, recipes, choice groups), newest first.")
  (page (select 'catalog-change :order-by '(("seq" :desc)) :limit (1+ limit)) limit))
