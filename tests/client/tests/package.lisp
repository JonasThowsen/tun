;;;; tests/package.lisp -- the test client's suite. The tests are not client
;;;; code, so they may look at kernel internals to verify behaviour.

(defpackage #:test-client.tests
  (:use #:cl #:fiveam #:tun.test-support)
  (:import-from #:tun.core #:jobj #:jarr #:jget)
  (:export #:run-client-tests))

(in-package #:test-client.tests)

(def-suite client :description "The test client on top of Tun.")

(defmacro with-client ((&rest args) &body body)
  "Run BODY with *APP* bound to a fresh test-client application."
  `(with-test-app (:class 'test-client:nordvik ,@args) ,@body))

(defun run-client-tests ()
  "Run the suite, explain its results, and return true when every test passed."
  (run! 'client))

(defun customer (name email &rest fields)
  "The id of a new customer, created as an employee."
  (jget (apply #'call-ok "customers_create" "employee:anna" "name" name "email" email fields) "id"))

(defun product (&rest fields)
  "The id of a new product, created as an employee."
  (jget (apply #'call-ok "products_create" "employee:anna" fields) "id"))

(defun rental (name &key (cleaning-days 1))
  "The id of a new rental product, one unit owned."
  (product "name" name "kind" "rental" "unit" "stk" "unit_price_minor" 100000
           "stock_tracked" nil "units_owned" 1 "cleaning_days" cleaning-days))

(defun lines-of (&rest lines)
  "A JSON array of order lines, each a plist of its fields."
  (jarr (mapcar (lambda (line) (apply #'jobj line)) lines)))
