;;;; modules/inventory/stock.lisp -- the product-keyed inventory tools on the
;;;; article ledger (README §4): each keeps its product-keyed input and output
;;;; and acts on the product's article; each also takes article_id in place
;;;; of product_id (which the schema keeps required).

(in-package #:tun.inventory)

(declaim (optimize (safety 3) (debug 2)))

(defun article-ref (product-id article-id &key (need-stock t))
  "Values the article a product-keyed tool acts on and the product named:
PRODUCT-ID's article, or ARTICLE-ID's.  A product without an article is
invalid_input when NEED-STOCK, else the article is NIL."
  (cond (product-id
         (let ((product (find-product product-id)))
           (cond ((product-article-id product)
                  (values (find-article (product-article-id product)) product))
                 (need-stock (fail :invalid-input "Produktet ~a er ikke lagerført" (product-name product)))
                 (t (values nil product)))))
        (article-id (values (find-article article-id) nil))
        (t (fail :invalid-input "Mangler påkrevd felt: input.product_id"))))

(define-operation inventory-receive ((product-id :type (id product) :schema-required t :label "Produkt-ID")
                                     (article-id :type (id article) :label "Artikkel-ID"
                                                 :description "I stedet for product_id.")
                                     (quantity :type (integer :min 1 :max 1000000) :required t :label "Antall")
                                     (reason :type (string :max 500) :label "Begrunnelse"))
    (:entity inventory-movement :kind :create :title "Varemottak"
     :description "Registrerer mottak av varer på lager (mottak) på produktets lagerartikkel, eller på article_id.")
  (let* ((article (lock-article (entity-id (article-ref product-id article-id)))))
    (require-active article)
    (ledger-row article "mottak" quantity :balance (+ (article-balance article) quantity) :reason reason)))

(define-operation inventory-adjust ((product-id :type (id product) :schema-required t :label "Produkt-ID")
                                    (article-id :type (id article) :label "Artikkel-ID"
                                                :description "I stedet for product_id.")
                                    (delta :type (integer :min -1000000 :max 1000000) :required t
                                           :label "Endring (+/-)")
                                    (reason :type (string :min 1 :max 500) :required t :label "Begrunnelse"))
    (:entity inventory-movement :kind :create :policy :admin :title "Lagerjustering"
     :description "Justerer beholdningen med en begrunnelse. Feiler med insufficient_stock om beholdningen ville blitt negativ.")
  (when (zerop delta) (fail :invalid-input "Justeringen kan ikke være 0"))
  (let* ((article (lock-article (entity-id (article-ref product-id article-id))))
         (balance (+ (article-balance article) delta)))
    (require-active article)
    (when (minusp balance)
      (insufficient article (- delta)))
    (ledger-row article "justering" delta :balance balance :reason reason)))

(define-operation inventory-balance ((product-id :type (id product) :schema-required t :label "Produkt-ID")
                                     (article-id :type (id article) :label "Artikkel-ID"
                                                 :description "I stedet for product_id."))
    (:entity inventory-movement :kind :read :title "Lagerbeholdning"
     :description "Beholdning, reservert og tilgjengelig (tilgjengelig kan bli negativ), for produktets lagerartikkel eller article_id.")
  (multiple-value-bind (article product) (article-ref product-id article-id :need-stock nil)
    (if (null article)
        (jobj "product_id" (entity-id product) "article_id" :null "on_hand" 0 "reserved" 0 "available" 0)
        (let ((reserved (reserved-quantity (entity-id article))))
          (jobj "product_id" (if product (entity-id product) (or (article-product-id article) :null))
                "article_id" (entity-id article)
                "on_hand" (quantity-json (article-balance article))
                "reserved" (quantity-json reserved)
                "available" (quantity-json (- (article-balance article) reserved)))))))

(define-operation inventory-movements ((product-id :type (id product) :schema-required t :label "Produkt-ID")
                                       (article-id :type (id article) :label "Artikkel-ID"
                                                   :description "I stedet for product_id.")
                                       (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:entity inventory-movement :kind :read :title "Lagerbevegelser"
     :description "Lagerbokens rader for produktets lagerartikkel (eller article_id), høyeste revisjon først.")
  (let ((article (article-ref product-id article-id :need-stock nil)))
    (jobj "items" (jarr (and article
                             (mapcar #'entity->json
                                     (select 'inventory-movement :where `(:= "article_id" ,(entity-id article))
                                                                 :order-by '(("revision" :desc))
                                                                 :limit limit)))))))
