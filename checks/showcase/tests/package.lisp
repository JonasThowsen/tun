;;;; tests/package.lisp -- the showcase's scenarios and its page tests.

(defpackage #:showcase.tests
  (:use #:cl #:fiveam #:tun.test-support)
  (:local-nicknames (#:page #:tun.page-test))
  (:export #:run-client-tests))

(in-package #:showcase.tests)

(defun run-client-tests ()
  "Run the showcase's page tests, explain their results, and return true
when every one passed."
  (run! 'showcase))
