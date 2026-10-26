;;;; tests/scenarios.lisp -- the data a preview, a browser check or a test
;;;; starts from ($TUN_SOURCE/spec/preview.md 3). `tun preview` makes the
;;;; default scenario's records before it answers; `tun preview --scenario
;;;; NAME` another's; a test calls (run-scenario "NAME").

(in-package #:{{name}}.tests)

(define-scenario default (:actors ("admin:admin" "employee:anna"))
  "{{name}} uten data, med en administrator og en ansatt å logge inn som."
  ;; Make the records here through the client's operations, as the actor
  ;; who would make them, for example:
  ;; (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann")
  )
