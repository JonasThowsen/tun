;;;; tests/tests.lisp -- the tests Tun generates for every client
;;;; ($TUN_SOURCE/spec/testing.md 1): it uses only Tun's public interface,
;;;; its application opens on Postgres with the modules it enables, every
;;;; text of its own has a translation into each language it offers, and
;;;; every scenario makes its records. A new Tun brings new ones. Name in
;;;; :isolate (VARIABLE...) a variable of the client's own through which a
;;;; scenario installs what answers for another system.

(in-package #:{{name}}.tests)

(in-suite {{name}})

(define-generated-tests "{{name}}" :package "{{package}}")
