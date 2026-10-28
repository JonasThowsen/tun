;;;; customers.lisp -- private and business customers, and loyalty: client
;;;; fields on a module's entity, a rule, a computed field and a seam.

(in-package #:test-client)

;;; Two fields on the customers module's customer, marked "source": "client".
(extend-entity customer (:name customer-kind-fields)
  ((kind :type (enum "privat" "bedrift") :required t :label "Kundetype"
         :description "privat eller bedrift.")
   (org-number :type (string :max 9 :pattern "^[0-9]{9}$" :pattern-message "må bestå av ni sifre")
               :label "Organisasjonsnummer"
               :description "Ni sifre. Påkrevd for bedriftskunder.")))

;;; A rule runs on every insert and update of the entity, whichever
;;; operation writes it.
(define-rule business-customers-need-org-number (customer c)
    (:field org-number :message "Bedriftskunder må ha et organisasjonsnummer på ni sifre")
  (or (not (equal (customer-kind c) "bedrift"))
      (and (stringp (customer-org-number c))
           (= 9 (length (customer-org-number c)))
           (every #'digit-char-p (customer-org-number c)))))

(declaim (ftype (function ((integer 0)) (values string &optional)) loyalty-tier-for))
(defun loyalty-tier-for (completed-orders)
  "The loyalty tier of a customer with COMPLETED-ORDERS completed orders."
  (cond ((>= completed-orders 5) "gull")
        ((>= completed-orders 2) "sølv")
        (t "bronse")))

(define-computed-field customer loyalty-tier (c)
    (:type (enum "bronse" "sølv" "gull") :label "Lojalitetsnivå")
  (loyalty-tier-for (customer-completed-orders c)))

(declaim (ftype (function (string) (values (integer 0 100) &optional)) tier-discount-percent))
(defun tier-discount-percent (tier)
  "The discount, in percent of the subtotal, that loyalty TIER gives."
  (cond ((string= tier "gull") 10)
        ((string= tier "sølv") 5)
        (t 0)))

(defclass loyalty-feature () ()
  (:documentation "Loyalty discount: 0 %, 5 % or 10 % of the subtotal by tier, rounded down."))

;;; The orders module asks for the discount through its ORDER-DISCOUNT seam.
(defmethod order-discount ((app loyalty-feature) order customer)
  (floor (* (order-subtotal-minor order) (tier-discount-percent (customer-loyalty-tier customer)))
         100))
