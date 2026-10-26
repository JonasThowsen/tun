;;;; modules/inventory/inventory.lisp -- the inventory module: stock articles
;;;; and their ledger (README §2, §3), reservations, and the catalog seams
;;;; the module answers.
;;;;
;;;; An article is the counted physical commodity.  Its balance is a ledger
;;;; projection: every balance-changing movement (aapning, mottak, justering,
;;;; telling, forbruk) locks the article, increments its movement_revision,
;;;; writes balance_after and inserts the row carrying that revision, in one
;;;; write transaction.  Ledger order is revision, not time.  Products link
;;;; to an article (several may share one); the product-keyed inventory tools
;;;; act on the product's article (README §4).
;;;;
;;;; Reservations and consumption are keyed by an opaque order id: inventory
;;;; never reads orders (README §1); the orders module tells it what an
;;;; order reserves and consumes, and answers the demand seam the forecast
;;;; asks.

(defpackage #:tun.inventory
  (:use #:cl #:tun.core #:tun.catalog)
  (:export #:article #:article-name #:article-unit #:article-balance #:article-movement-revision
           #:article-product-id #:article-active #:article-package-size #:article-min-level
           #:article-supplier #:article-lead-days #:article-department
           #:find-article #:article-key-product
           #:inventory-movement #:movement-product-id #:movement-article-id #:movement-kind #:movement-quantity
           #:movement-revision #:movement-balance-after #:movement-reason #:movement-order-id #:movement-at
           #:received-since-p
           #:on-hand #:reserved-quantity
           #:set-order-reservations #:release-order-reservations
           #:order-reservations #:sync-consumption #:consumption-applied-p
           #:article-demand #:product-bookings-on #:forecast #:forecast-demand #:purchase-suggestions
           #:inventory-forecast #:inventory-purchase-suggestions #:inventory-availability-grid
           #:transfer
           #:articles-create #:articles-get #:articles-list #:articles-update #:articles-archive
           #:articles-recount #:articles-transfer #:transfers-list
           #:inventory-receive #:inventory-adjust #:inventory-balance #:inventory-movements
           #:inventory-shortages))

(in-package #:tun.inventory)

(declaim (optimize (safety 3) (debug 2)))

(define-module inventory
  (:depends-on catalog)
  (:core ">= 1.0" "< 2.0")
  (:on-open adopt-older-stock)
  (:documentation "Inventory: stock articles, the ledger, reservations, consumption and the forecast."))

;;; ------------------------------------------------------------------
;;; Entities

;;; The per-product balance of an older core.  Written by older cores only;
;;; read once, when an older database is adopted (ADOPT-OLDER-STOCK, README §14).
(define-entity stock-level (:json-name "stock_level" :label "Lagerstatus" :id-prefix "stk"
                            :table "stock_levels" :internal t :unique (("product_id")))
  ((product-id :type (id product) :input nil)
   (on-hand :type integer :input nil :initform 0)
   (revision :type (integer :min 0) :input nil :initform 0
             :description "Movement revision: incremented by every movement of the product.")))

(defun article-rollback-finding (article)
  "An older core reads stock from its per-product stock levels.  An article
adopted from one and untouched since still agrees with it; any other holds
stock the older core would not see."
  (let ((level (and (article-product-id article)
                    (select-one 'stock-level :where `(:= "product_id" ,(article-product-id article))))))
    (unless (and level
                 (eql (stock-level-on-hand level) (article-balance article))
                 (eql (stock-level-revision level) (article-movement-revision article)))
      "stock kept on an article, which the older core does not read")))

(defun product-link-rollback-finding (product)
  "An older core reads a stock-tracked product's stock from its own stock
level.  A product linked to the article made for it (adopted from that
level, or made by products_create) reads the same; one linked to another
article, or unlinked from its own, does not (README §14)."
  (let* ((id (entity-id product))
         (linked (product-article-id product))
         (own (select-one 'article :where `(:= "product_id" ,id))))
    (cond ((and (null linked) own)
           "unlinked from the stock article made for it, which the older core still reads")
          ((and linked (not (and own (equal linked (entity-id own)))))
           "stock counted on an article not made for the product, which the older core does not read"))))

(add-rollback-check 'product 'product-link-rollback-finding :older-lacks 'article)

(define-entity article (:label "Lagerartikkel" :id-prefix "art" :table "articles"
                        :indexes (("product_id") ("department")) :rollback-check article-rollback-finding)
  ((revision :type (integer :min 1) :input nil :initform 1 :label "Revisjon")
   (name :type (string :min 1 :max 120) :input nil :label "Navn")
   (sku :type (string :max 60) :input nil :label "Varenummer")
   (unit :type (string :min 1 :max 20) :input nil :label "Enhet")
   (package-size :type (decimal :scale 3) :input nil :label "Pakningsstørrelse")
   (balance :type (decimal :scale 3) :input nil :initform 0 :label "Beholdning"
            :description "Projeksjon av lagerboken; ingen verktøy setter den direkte.")
   (movement-revision :type integer :input nil :initform 0 :label "Bevegelsesrevisjon")
   (min-level :type (decimal :scale 3) :input nil :label "Minimum")
   (max-level :type (decimal :scale 3) :input nil :label "Maksimum")
   (cost-price-ore :type (integer :min 0) :input nil :label "Innkjøpspris (øre)")
   (supplier :type json :input nil :label "Leverandør" :description "{name, contact, article_no, order_url}")
   (lead-days :type (integer :min 0) :input nil :initform 0 :label "Leveringstid (dager)")
   (department :type (string :max 100) :input nil :label "Avdeling")
   (department-revision :type (integer :min 1) :input nil :initform 1 :label "Avdelingsrevisjon")
   (active :type boolean :input nil :initform t :label "Aktiv")
   (product-id :type (id product) :input nil :label "Produkt"
               :description "The product the article was made for (by products_create), if any.")
   (created-at :type timestamp :input nil :label "Opprettet")))

(define-entity inventory-movement (:json-name "inventory_movement" :label "Lagerbevegelse"
                                   :id-prefix "mov" :table "inventory_movements"
                                   :indexes (("product_id" "revision") ("article_id" "revision") ("order_id")))
  ((product-id :type (id product) :input nil :label "Produkt")
   (kind :type (enum "aapning" "mottak" "justering" "telling" "forbruk" "reservasjon" "frigivelse")
         :input nil :label "Type")
   (quantity :type (decimal :scale 3) :input nil :label "Mengde")
   (revision :type integer :input nil :label "Revisjon")
   (balance-after :type (decimal :scale 3) :input nil :label "Beholdning etter")
   (reason :type (string :max 500) :input nil :label "Begrunnelse")
   (order-id :type id :input nil :label "Ordre")
   (at :type timestamp :input nil :label "Tidspunkt")
   (article-id :type (id article) :input nil :label "Lagerartikkel")
   (balance-updated :type boolean :input nil :initform t :label "Beholdning oppdatert"
                    :description "false for a forbruk row recreated after a later telling: the count wins.")
   (by :type (string :max 200) :input nil :label "Utført av")))

;; Accessor aliases with ledger vocabulary.
(defun movement-product-id (m) (inventory-movement-product-id m))
(defun movement-article-id (m) (inventory-movement-article-id m))
(defun movement-kind (m) (inventory-movement-kind m))
(defun movement-quantity (m) (inventory-movement-quantity m))
(defun movement-revision (m) (inventory-movement-revision m))
(defun movement-balance-after (m) (inventory-movement-balance-after m))
(defun movement-reason (m) (inventory-movement-reason m))
(defun movement-order-id (m) (inventory-movement-order-id m))
(defun movement-at (m) (inventory-movement-at m))

(defun received-since-p (article-id since)
  "Whether ARTICLE-ID has a mottak after timestamp SINCE (the ledger is this
module's own table: other modules ask, tun-platform.md §2.5)."
  (and (select-one 'inventory-movement :where `(:and (:= "article_id" ,article-id) (:= "kind" "mottak")
                                                     (:> "at" ,since)))
       t))

(define-entity reservation (:json-name "reservation" :label "Reservasjon" :id-prefix "res"
                            :table "reservations" :internal t
                            :indexes (("order_id") ("article_id")))
  ((order-id :type id :input nil)
   (product-id :type (id product) :input nil
               :description "An older core's key; reservations are by article.")
   (quantity :type (decimal :scale 3) :input nil)
   (needed-on :type date :input nil :description "Date the reserved goods are needed.")
   (article-id :type (id article) :input nil)))

(defun transfer-rollback-finding (transfer)
  (declare (ignore transfer))
  "department transfer, which the older core cannot show")

(define-entity transfer (:label "Overføring" :id-prefix "ovf" :table "transfers"
                         :indexes (("target_id")) :rollback-check transfer-rollback-finding)
  ((target-type :type (enum "article" "product") :input nil :label "Type")
   (target-id :type id :input nil :label "Gjelder")
   (from-department :type (string :max 100) :input nil :label "Fra avdeling")
   (to-department :type (string :max 100) :input nil :label "Til avdeling")
   (note :type (string :max 1000) :input nil :label "Merknad")
   (by :type (string :max 200) :input nil :label "Utført av")
   (at :type timestamp :input nil :label "Tidspunkt")))

;;; ------------------------------------------------------------------
;;; Articles and the ledger

(defun find-article (id)
  (or (and (stringp id) (fetch 'article id))
      (fail :not-found "Fant ingen lagerartikkel med id ~a" id)))

(defun article-key-product (article)
  "The id a product-keyed view shows for ARTICLE: its product's, or its own."
  (or (article-product-id article) (entity-id article)))

(defun lock-article (id)
  "ARTICLE ID, locked for the rest of the write transaction and read again under the lock."
  (lock-row 'article id)
  (find-article id))

(defun require-active (article)
  (unless (article-active article)
    (fail :invalid-input "Lagerartikkelen er arkivert")))

(defconstant +max-balance+ (expt 10 12)
  "The largest balance an article may reach: up to it every balance is exact
at three decimals (README §3.3).")

(defun check-balance-bound (balance)
  (when (> balance +max-balance+)
    (fail :invalid-input "Beholdningen kan være høyst ~d" +max-balance+)))

(defun ledger-row (article kind quantity &key (balance (article-balance article)) reason order-id
                                              (balance-updated t))
  "Append one row of KIND to locked ARTICLE's ledger: the movement revision
counts it, and BALANCE becomes the article's balance when BALANCE-UPDATED.
A balance above 10^12 is invalid_input (README §3.3)."
  (when balance-updated (check-balance-bound balance))
  (incf (article-movement-revision article))
  (when balance-updated
    (setf (article-balance article) balance))
  (save article)
  (insert (make-instance 'inventory-movement
                         :article-id (entity-id article) :product-id (article-product-id article)
                         :kind kind :quantity quantity :revision (article-movement-revision article)
                         :balance-after (article-balance article) :reason reason :order-id order-id
                         :balance-updated balance-updated :by (actor-string *actor*) :at (now))))

(defun insufficient (article needed)
  (fail :insufficient-stock "Ikke nok ~a på lager: ~a på lager, trenger ~a"
        (article-name article) (format-quantity (article-balance article)) (format-quantity needed)))

(defun on-hand (product-id)
  "The balance of PRODUCT-ID's article (0 without one)."
  (let* ((product (fetch 'product product-id))
         (article (and product (product-article-id product) (fetch 'article (product-article-id product)))))
    (if article (article-balance article) 0)))

;;; ------------------------------------------------------------------
;;; Reservations (keyed by an opaque order id)

(defun order-reservations (order-id)
  (select 'reservation :where `(:= "order_id" ,order-id)))

(defun reserved-quantity (article-id)
  (reduce #'+ (select 'reservation :where `(:= "article_id" ,article-id)) :key #'reservation-quantity))

(defun set-order-reservations (order-id requirements needed-on)
  "Make ORDER-ID's reservations equal REQUIREMENTS, a list of (article-id . quantity)."
  (release-order-reservations order-id)
  (loop for (article-id . quantity) in requirements
        when (plusp quantity)
          do (insert (make-instance 'reservation :order-id order-id :article-id article-id
                                                 :product-id (article-product-id (find-article article-id))
                                                 :quantity quantity :needed-on needed-on))))

(defun release-order-reservations (order-id)
  (mapc #'delete-entity (order-reservations order-id))
  t)

;;; ------------------------------------------------------------------
;;; The catalog's seams

(defmethod stock-article-for ((application inventory-module) product)
  ;; A product-created article writes no aapning row: its revisions start
  ;; at 1 on the first receipt (README §4).
  (or (call-next-method)
      (entity-id (insert (make-instance 'article :name (product-name product) :unit (product-unit product)
                                                 :product-id (entity-id product) :supplier (empty-supplier)
                                                 :created-at (now))))))

(defmethod catalog-article ((application inventory-module) article-id)
  (let ((article (and (stringp article-id) (fetch 'article article-id))))
    (if article
        (values (article-name article) (article-unit article) (article-active article))
        (call-next-method))))

(defmethod product-transferred ((application inventory-module) product from to note)
  (insert (make-instance 'transfer :target-type "product" :target-id (entity-id product)
                                   :from-department from :to-department to :note note
                                   :by (actor-string *actor*) :at (now))))

(defun empty-supplier ()
  (jobj "name" :null "contact" :null "article_no" :null "order_url" :null))

;;; ------------------------------------------------------------------
;;; Adopting what an older core stored (at start)

(defun adopt-older-stock ()
  "An older core kept each stock-tracked product's balance in its
stock level.  Give every stock-tracked product without an article one, with
that balance and movement count, and key its movements and reservations by
the article.  Idempotent: adopted products have their article."
  (with-transaction (:write)
    (dolist (product (select 'product :where '(:and (:= "stock_tracked" t) (:null "article_id"))))
      (let* ((id (entity-id product))
             (level (select-one 'stock-level :where `(:= "product_id" ,id)))
             (article (insert (make-instance 'article :name (product-name product) :unit (product-unit product)
                                                      :product-id id :supplier (empty-supplier)
                                                      :balance (if level (stock-level-on-hand level) 0)
                                                      :movement-revision (if level (stock-level-revision level) 0)
                                                      :created-at (now)))))
        (link-product-article id (entity-id article))
        (dolist (m (select 'inventory-movement :where `(:and (:= "product_id" ,id) (:null "article_id"))))
          (setf (inventory-movement-article-id m) (entity-id article))
          (unless (inventory-movement-by m) (setf (inventory-movement-by m) "system:migration"))
          (save m))
        (dolist (r (select 'reservation :where `(:and (:= "product_id" ,id) (:null "article_id"))))
          (setf (reservation-article-id r) (entity-id article))
          (save r))))))
