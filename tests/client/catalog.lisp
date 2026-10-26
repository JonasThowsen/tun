;;;; catalog.lisp -- cleaning days on rental products: a client field, the
;;;; client's own operation that sets it, and the booking-window seam.

(in-package #:test-client)

(extend-entity product (:name product-rental-fields)
  ((cleaning-days :type (integer :min 0 :max 60) :initform 1 :label "Rengjøringsdager"
                  :description "Dager før og etter et arrangement enheten er blokkert.")))

(define-operation products-set-cleaning-days
    ((product-id :type (id product) :required t :label "Produkt-ID")
     (days :type (integer :min 0 :max 60) :required t :label "Dager"))
    (:entity product :kind :update :title "Sett rengjøringsdager"
     :description "Setter hvor mange dager før og etter et arrangement enheten er blokkert.")
  ;; SAVE through TUN stores the client's own fields of a module record and
  ;; refuses a change to the module's.
  (let ((product (find-product product-id)))
    (setf (product-cleaning-days product) days)
    (save product)))

(defclass cleaning-feature () ()
  (:documentation "A booking blocks the unit for its cleaning days before and after the event."))

(defmethod booking-window ((app cleaning-feature) product event-date end-date)
  (let ((days (or (product-cleaning-days product) 1)))
    (values (date-add-days event-date (- days)) (date-add-days end-date days))))
