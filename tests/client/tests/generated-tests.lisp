;;;; tests/generated-tests.lisp -- the tests Tun generates for every client
;;;; (spec/testing.md 1), on the test client as on any other.

(in-package #:test-client.tests)

(def-suite generated :in client)
(in-suite generated)

(define-generated-tests "test-client" :package "TEST-CLIENT" :cases t)

(test the-fuzzing-and-scenario-tests-run-as-shares
  ;; spec/testing.md 1, «In parallel»: a worker runs a share of each.
  (dolist (name '("GENERATED-EVERY-TOOL-WITHSTANDS-FUZZING" "GENERATED-EVERY-SCENARIO-MAKES-ITS-RECORDS"))
    (is (split-test-p (find-symbol name "TEST-CLIENT.TESTS")) "~a runs as shares" name))
  (is (not (split-test-p (find-symbol "GENERATED-THE-PACKAGE-USES-ONLY-CL-AND-TUN"
                                      "TEST-CLIENT.TESTS")))))
