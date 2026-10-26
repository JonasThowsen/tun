;;;; screens.lisp -- two screen overrides, methods on RENDER-SCREEN for this
;;;; application: the order page gains a section of hours per line and keeps
;;;; the generated page through CALL-NEXT-METHOD, and the customer list is
;;;; replaced by one with the client's Kundetype column. Data comes from the
;;;; same operations agents use, called as the logged-in actor.

(in-package #:test-client)

(defclass order-screen-feature () ()
  (:documentation "Order detail page with the hours on each line."))

(defun line-hours-row (line)
  "A row of the hours section for LINE, an order line as JSON."
  (jobj "Produkt" (jget (invoke 'products-get "id" (jget line "product_id")) "name")
        "Antall" (jget line "quantity")
        "Timer" (jget line "hours")))

(defmethod render-screen ((app order-screen-feature) (screen (eql :order-detail)) &key order)
  (list (section "Timer på ordren"
          (if (plusp (length (jget order "lines")))
              (json-table (map 'list #'line-hours-row (jget order "lines")))
              '(:p "Ordren har ingen linjer.")))
        (call-next-method)))

(defclass customer-list-feature () ()
  (:documentation "Customer list with the customer's kind."))

(defmethod render-screen ((app customer-list-feature) (screen (eql :customer-list)) &key items)
  (json-table (mapcar (lambda (c)
                        (jobj "Navn" (jget c "name")
                              "Kundetype" (jget c "kind")
                              "E-post" (jget c "email")
                              "Organisasjonsnummer" (jget c "org_number")
                              "ID" (jget c "id")))
                      items)))
