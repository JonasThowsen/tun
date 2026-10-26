;;;; tests/package.lisp -- core test-suite (runs with no client loaded).

(defpackage #:tun.tests
  (:use #:cl #:tun.core #:tun.outbound #:fiveam #:tun.test-support)
  (:shadowing-import-from #:tun.core #:fail)
  ;; The suite's HTTP-POST posts to a test server; TUN.OUTBOUND's is Tun's own call.
  (:shadowing-import-from #:tun.test-support #:http-post)
  (:export #:run-core-tests))

(in-package #:tun.tests)

(def-suite core :description "tun core, without any client.")
