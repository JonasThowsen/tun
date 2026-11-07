;;;; tests/generated-tests.lisp -- the tests Tun generates for every client
;;;; (spec/testing.md 1), on the test client as on any other.

(in-package #:test-client.tests)

(def-suite generated :in client)
(in-suite generated)

(define-generated-tests "test-client" :package "TEST-CLIENT")
