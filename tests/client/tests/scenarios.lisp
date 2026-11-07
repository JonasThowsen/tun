;;;; tests/scenarios.lisp -- the test client's scenario (spec/preview.md 3),
;;;; which the generated scenario test runs as it runs every client's.

(in-package #:test-client.tests)

(define-scenario default (:actors ("employee:anna" "admin:jonas"))
  "Nordvik med to kunder og et telt å leie ut."
  (customer "Kari Nordmann" "kari@example.no" "kind" "privat")
  (customer "Ola Nordmann" "ola@example.no" "kind" "privat")
  (rental "Partytelt"))
