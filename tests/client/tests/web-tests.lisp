;;;; tests/web-tests.lisp -- the client's screen overrides, and its fields
;;;; and rule in the generated forms.

(in-package #:test-client.tests)

(def-suite client-web :in client)
(in-suite client-web)

(test the-order-page-override-adds-a-section-and-keeps-the-generated-page
  (with-test-server (port :class 'test-client:nordvik)
    (let* ((jar (web-login port "viewer:besøkende"))
           (id (customer "Anders" "anders@example.no" "kind" "privat"))
           (lines (lines-of (list "product_id" (rental "Partytelt") "quantity" 1 "hours" 4)))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" id
                                 "event_date" "2026-06-20" "lines" lines)
                        "id")))
      (multiple-value-bind (status body) (web-request port (format nil "/orders/~a" order) :jar jar)
        (is (= 200 status))
        (is (search "viewer:besøkende" body) "a UTF-8 actor survives the cookie")
        (is (search "Timer på ordren" body) "the client's section")
        (is (search "Partytelt" body))
        (is (search "data-field=\"status\"" body) "the generated page is kept")))))

(test the-customer-list-override-replaces-the-generated-list
  (with-test-server (port :class 'test-client:nordvik)
    (let ((jar (web-login port "employee:anna")))
      (customer "Vestvik Bygg AS" "post@example.no" "kind" "bedrift" "org_number" "987654321")
      (multiple-value-bind (status body) (web-request port "/customers" :jar jar)
        (is (= 200 status))
        (is (search "Kundetype" body))
        (is (search "bedrift" body))
        (is (search "987654321" body))))))

(test the-generated-forms-include-the-client-fields-and-apply-its-rule
  (with-test-server (port :class 'test-client:nordvik)
    (let ((jar (web-login port "employee:anna"))
          (tent (rental "Telt"))
          (id (customer "Anders" "anders@example.no" "kind" "privat")))
      (is (search "name=\"lines[0][hours]\"" (nth-value 1 (web-request port "/orders" :jar jar))))
      (is (search "name=\"kind\"" (nth-value 1 (web-request port "/customers" :jar jar))))
      (multiple-value-bind (status body headers)
          (web-request port "/orders" :method :post :jar jar
                       :parameters `(("customer_id" . ,id) ("event_date" . "2026-06-20")
                                     ("lines[0][product_id]" . ,tent) ("lines[0][quantity]" . "1")
                                     ("lines[0][hours]" . "5")))
        (declare (ignore body))
        (is (= 303 status))
        (let ((order (call-ok "orders_get" "viewer:vera" "id" (subseq (location headers) 8))))
          (is (= 5 (jget (aref (jget order "lines") 0) "hours")))))
      (multiple-value-bind (status body)
          (web-request port "/customers" :method :post :jar jar
                       :parameters '(("name" . "Firma AS") ("email" . "post@example.no")
                                     ("kind" . "bedrift")))
        (is (= 422 status) "the client's rule applies to form input too")
        (is (search "org_number" body))))))

(defun product-field-names ()
  (mapcar #'tun.core:field-json-name (tun.core:entity-fields 'tun.catalog:product)))

(test the-generated-list-leaves-the-entity-definition-as-it-was
  ;; The generated list chooses its columns by sorting the entity's fields;
  ;; the sort must work on a copy, not on the cached field list, whose last
  ;; field here is the client's cleaning_days.
  (with-test-server (port :class 'test-client:nordvik)
    (let ((jar (web-login port "employee:anna"))
          (before (product-field-names)))
      (rental "Telt")
      (dotimes (i 2) (web-request port "/products" :jar jar))
      (is (equal before (product-field-names))))))
