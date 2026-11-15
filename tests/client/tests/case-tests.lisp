;;;; tests/case-tests.lisp -- switching over a closed set as a client does
;;;; (spec/core.md 2.7): the examples of docs/client-api.md, the client's own
;;;; computed field, and the cases guard it turns on (spec/testing.md 1,
;;;; test 11).

(in-package #:test-client.tests)

(def-suite cases :in client)
(in-suite cases)

(test the-docs-examples-run-their-branches
  (is (equal '(:outline :info :info :warning :warning :warning :warning :success :destructive)
             (mapcar #'test-client:order-status-variant
                     '("draft" "quote_sent" "accepted" "confirmed" "picked_up" "returned"
                       "ready_for_invoice" "completed" "cancelled"))))
  (signals tun:case-not-handled (test-client:order-status-variant "shipped"))
  (is (equal '("Not found" "You do not have access to this" "That did not work")
             (mapcar #'test-client:refusal-heading '(:not-found :forbidden :conflict))))
  (is (equal "Picked up at the depot"
             (test-client:delivery-text (test-client:make-pickup :place "the depot"))))
  (is (equal "Sent to Storgata 1"
             (test-client:delivery-text (test-client:make-shipment :address "Storgata 1"))))
  (signals tun:case-not-handled (test-client:delivery-text "a letter")))

(test a-tier-outside-the-set-has-no-discount
  (is (eql 0 (test-client:tier-discount-percent "platina"))))

(defparameter +base-tier-discount+
  ";;;; customers.lisp, as it was before the client switched with ecase-of.
(in-package #:test-client)

(defun tier-discount-percent (tier)
  \"The discount, in percent of the subtotal, that loyalty TIER gives.\"
  (cond ((string= tier \"gull\") 10)
        ((string= tier \"sølv\") 5)
        (t 0)))
"
  "The test client's TIER-DISCOUNT-PERCENT before this client used ECASE-OF.")

(test the-guard-found-the-client-s-cond-over-its-tiers
  (let ((findings (plain-case-findings-in-text +base-tier-discount+ :source "customers.lisp")))
    (is (= 1 (length findings)) "~{~a~^~%~}" findings)
    (is (search "customers.lisp:4 (defun tier-discount-percent): a cond comparing tier with \"gull\", \"sølv\", values of (customer loyalty-tier)"
                (first findings))
        "~a" (first findings))))

(test the-guard-is-a-generated-test-only-when-the-client-turns-it-on
  (flet ((names-in (form)
           (let ((names '()))
             (tun.test-support::walk-symbols (macroexpand-1 form)
                                             (lambda (s) (push (symbol-name s) names)))
             names)))
    (is (member "GENERATED-CASES-OVER-DECLARED-SETS-NAME-THEIR-SET"
                (names-in '(define-generated-tests "test-client" :package "TEST-CLIENT" :cases t))
                :test #'string=))
    (is (not (member "GENERATED-CASES-OVER-DECLARED-SETS-NAME-THEIR-SET"
                     (names-in '(define-generated-tests "test-client" :package "TEST-CLIENT"))
                     :test #'string=))))
  (is (fiveam:get-test 'generated-cases-over-declared-sets-name-their-set)
      "the test client turns it on"))
