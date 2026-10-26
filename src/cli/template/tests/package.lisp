;;;; tests/package.lisp -- the client's test-suite.

(defpackage #:{{name}}.tests
  (:use #:cl #:fiveam #:tun.test-support)
  (:export #:run-tests))

(in-package #:{{name}}.tests)

(def-suite {{name}} :description "{{name}}'s tests.")

(defun run-tests ()
  "Run the suite, explain its results, and return true when every test passed."
  (run! '{{name}}))
