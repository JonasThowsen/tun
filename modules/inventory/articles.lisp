;;;; modules/inventory/articles.lisp -- the article tools (README §2), the
;;;; recount (telling, §3.1) and department transfers (§11).

(in-package #:tun.inventory)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +order-url-pattern+ "^https?://[^@\\s/:?#]+(:\\d+)?([/?#]\\S*)?$"
  "An http or https URL with no user or password (README §2.1).")

(defun check-supplier (value existing)
  "The supplier object for VALUE (merged over EXISTING): name, contact,
article_no and order_url, each a string or null; order_url a plain http(s) URL."
  (unless (hash-table-p value)
    (fail :invalid-input "Leverandøren må være et objekt med name, contact, article_no og order_url"))
  (let ((merged (if (hash-table-p existing) (json-copy existing) (empty-supplier))))
    (dolist (key (jkeys value))
      (unless (member key '("name" "contact" "article_no" "order_url") :test #'string=)
        (fail :invalid-input "Leverandøren har ikke feltet ~a" key))
      (let ((v (jget value key)))
        (unless (or (json-null-p v) (and (stringp v) (<= (length v) (if (string= key "order_url") 2000 200))))
          (fail :invalid-input (if (string= key "order_url")
                                   "Bestillingslenken må være en http- eller https-adresse uten brukernavn eller passord"
                                   "Leverandørfeltet ~a må være en tekst på høyst 200 tegn")
                key))
        (when (and (string= key "order_url") (stringp v) (not (cl-ppcre:scan +order-url-pattern+ v)))
          (fail :invalid-input "Bestillingslenken må være en http- eller https-adresse uten brukernavn eller passord"))
        (setf (gethash key merged) (if (and (stringp v) (blank-p v)) :null v))))
    merged))

(defun apply-article-fields (article &key name sku unit package-size min-level max-level cost-price-ore
                                          supplier lead-days)
  "Set the given (non-NIL) fields of ARTICLE after their checks (create and update)."
  (when name
    (setf (article-name article) name))
  (when unit
    (setf (article-unit article) unit))
  (when sku
    (when (find-if (lambda (other) (not (equal (entity-id other) (entity-id article))))
                   (select 'article :where `(:= "sku" ,sku)))
      (fail :conflict "Varenummeret ~a er allerede i bruk" sku))
    (setf (article-sku article) sku))
  (when package-size
    (unless (plusp package-size) (fail :invalid-input "Pakningsstørrelsen må være større enn 0"))
    (setf (article-package-size article) package-size))
  (when min-level
    (when (minusp min-level) (fail :invalid-input "Nivået kan ikke være negativt"))
    (setf (article-min-level article) min-level))
  (when max-level
    (when (minusp max-level) (fail :invalid-input "Nivået kan ikke være negativt"))
    (setf (article-max-level article) max-level))
  (when cost-price-ore (setf (article-cost-price-ore article) cost-price-ore))
  (when lead-days (setf (article-lead-days article) lead-days))
  (when supplier
    (setf (article-supplier article) (check-supplier supplier (article-supplier article))))
  article)

;;; ------------------------------------------------------------------
;;; Operations

(define-operation articles-create ((name :type (string :max 120) :label "Navn")
                                   (sku :type (string :max 60) :label "Varenummer")
                                   (unit :type (string :max 20) :label "Enhet")
                                   (package-size :type (decimal :scale 3) :label "Pakningsstørrelse"
                                                 :description "Innkjøpspakningen i artikkelens enhet (> 0).")
                                   (min-level :type (decimal :scale 3) :label "Minimum")
                                   (max-level :type (decimal :scale 3) :label "Maksimum")
                                   (cost-price-ore :type (integer :min 0) :label "Innkjøpspris (øre)")
                                   (supplier :type json :label "Leverandør"
                                             :description "{name, contact, article_no, order_url}")
                                   (lead-days :type (integer :min 0 :max 3650) :label "Leveringstid (dager)")
                                   (department :type (string :max 100) :label "Avdeling")
                                   (opening-balance :type (decimal :scale 3) :default 0 :label "Startbeholdning"))
    (:entity article :kind :create :policy :admin :title "Opprett lagerartikkel"
     :description "En lagerartikkel (den talte varen) med enhet, pakningsstørrelse, nivåer, leverandør og leveringstid. Startbeholdningen skrives som én aapning-bevegelse i samme transaksjon (også 0).")
  (when (or (null name) (null unit))
    (fail :invalid-input "Navn og enhet må fylles ut"))
  (check-catalog-department department)
  (when (minusp opening-balance)
    (fail :invalid-input "Startbeholdningen kan ikke være negativ"))
  (let ((article (apply-article-fields (make-instance 'article :supplier (empty-supplier) :department department
                                                              :created-at (now))
                                       :name name :sku sku :unit unit :package-size package-size
                                       :min-level min-level :max-level max-level
                                       :cost-price-ore cost-price-ore :supplier supplier :lead-days lead-days)))
    (insert article)
    (ledger-row (lock-article (entity-id article)) "aapning" opening-balance :balance opening-balance
                :reason "Åpningsbeholdning")
    (find-article (entity-id article))))

(define-operation articles-get ((id :type (id article) :required t :label "Artikkel-ID"))
    (:entity article :kind :read :title "Hent lagerartikkel" :description "Én lagerartikkel med beholdning.")
  (find-article id))

(define-operation articles-list ((query :type (string :max 120) :label "Søk i navn")
                                 (department :type (string :max 100) :label "Avdeling")
                                 (active :type boolean :label "Aktive" :description "Standard true; false viser de arkiverte.")
                                 (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:entity article :kind :read :title "Lagerartikler"
     :description "Lagerartikler etter navn; søket er en del av navnet uten hensyn til store og små bokstaver (% og _ er vanlige tegn).")
  (let* ((active (if (or (input-provided-p :active) (input-null-p :active)) (and active t) t))
         (where `(:and (:= "active" ,active) ,@(and department `((:= "department" ,department)))))
         (rows (remove-if-not (lambda (a) (or (null query) (contains-ci-p query (article-name a))))
                              (select 'article :where where))))
    (page (stable-sort rows #'string-lessp :key #'article-name) limit)))

(define-operation articles-update ((id :type (id article) :required t :label "Artikkel-ID")
                                   (revision :type integer :label "Revisjon")
                                   (name :type (string :max 120) :label "Navn")
                                   (sku :type (string :max 60) :label "Varenummer")
                                   (unit :type (string :max 20) :label "Enhet")
                                   (package-size :type (decimal :scale 3) :label "Pakningsstørrelse")
                                   (min-level :type (decimal :scale 3) :label "Minimum")
                                   (max-level :type (decimal :scale 3) :label "Maksimum")
                                   (cost-price-ore :type (integer :min 0) :label "Innkjøpspris (øre)")
                                   (supplier :type json :label "Leverandør")
                                   (lead-days :type (integer :min 0 :max 3650) :label "Leveringstid (dager)")
                                   (active :type boolean :label "Aktiv")
                                   (balance :type json :label "Beholdning" :description "Kan ikke settes; den følger lagerboken.")
                                   (department :type json :label "Avdeling" :description "Kan ikke endres her; bruk articles_transfer."))
    (:entity article :kind :update :policy :admin :title "Endre lagerartikkel"
     :description "Endrer alt unntatt beholdning, bevegelsesrevisjon og avdeling. active true aktiverer en arkivert artikkel igjen.")
  (when (input-provided-p :balance)
    (fail :invalid-input "Beholdningen endres bare gjennom lagerbevegelser"))
  (when (input-provided-p :department)
    (fail :invalid-input "Avdelingen endres med articles_transfer"))
  (let ((article (lock-article id)))
    (when (and revision (/= revision (article-revision article)))
      (fail :conflict "Lagerartikkelen er endret (revisjon ~d, ikke ~d)" (article-revision article) revision))
    (apply-article-fields article :name name :sku sku :unit unit :package-size package-size
                                  :min-level min-level :max-level max-level :cost-price-ore cost-price-ore
                                  :supplier supplier :lead-days lead-days)
    (when (input-provided-p :active)
      (setf (article-active article) active))
    (incf (article-revision article))
    (save article)))

(define-operation articles-archive ((id :type (id article) :required t :label "Artikkel-ID"))
    (:entity article :kind :update :policy :admin :title "Arkiver lagerartikkel"
     :description "Arkiverer artikkelen (active false); lagerboken beholdes, og forbruk kan fortsatt føres og reverseres.")
  (let ((article (lock-article id)))
    (setf (article-active article) nil)
    (incf (article-revision article))
    (save article)))

(define-operation articles-recount ((article-id :type (id article) :required t :label "Artikkel-ID")
                                   (quantity :type (decimal :scale 3) :required t :label "Talt mengde")
                                   (reason :type (string :max 500) :label "Begrunnelse"))
    (:entity inventory-movement :kind :create :policy :admin :title "Varetelling"
     :description "Skriver en telling: beholdningen blir det talte antallet. Krever begrunnelse; artikkelen må være aktiv.")
  (let ((article (lock-article article-id)))
    (require-active article)
    (when (blank-p reason)
      (fail :invalid-input "Oppgi årsaken til lagerkorrigeringen"))
    (when (minusp quantity)
      (fail :invalid-input "Talt mengde kan ikke være negativ"))
    (ledger-row article "telling" quantity :balance quantity :reason (trim reason))))

(define-operation articles-transfer ((id :type (id article) :required t :label "Artikkel-ID")
                                     (department :type (string :max 100) :label "Til avdeling")
                                     (note :type (string :max 1000) :label "Begrunnelse")
                                     (department-revision :type integer :label "Avdelingsrevisjon"))
    (:entity article :kind :update :policy :admin :title "Overfør lagerartikkel"
     :description "Flytter eierskapet til artikkelen til en annen avdeling, med begrunnelse; føres som en overføring. Beholdningen flyttes aldri.")
  (let ((article (lock-article id)))
    (multiple-value-bind (from to) (check-transfer (article-department article) (article-department-revision article)
                                                   department note department-revision)
      (setf (article-department article) to)
      (incf (article-department-revision article))
      (insert (make-instance 'transfer :target-type "article" :target-id id :from-department from
                                       :to-department to :note (trim note) :by (actor-string *actor*) :at (now)))
      (save article))))

(define-operation transfers-list ((target-type :type (enum "article" "product") :required t :label "Type")
                                  (target-id :type id :required t :label "Gjelder")
                                  (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:entity transfer :kind :read :title "Overføringer"
     :description "Overføringene av en artikkel eller et produkt mellom avdelinger, nyeste først.")
  (page (select 'transfer :where `(:and (:= "target_type" ,target-type) (:= "target_id" ,target-id))
                          :order-by '(("seq" :desc)) :limit (1+ limit))
        limit))
