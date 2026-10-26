;;;; tests/interface-tests.lisp -- a client may use only Tun's public
;;;; interface: the external symbols of TUN, and TUN.UI for its pages.

(in-package #:test-client.tests)

(def-suite interface :in client)
(in-suite interface)

(test the-client-package-uses-only-cl-and-tun
  (is (equal '("COMMON-LISP" "TUN")
             (sort (mapcar #'package-name (package-use-list "TEST-CLIENT")) #'string<))))

(test the-client-sources-use-only-the-public-interface
  (is (<= 7 (length (client-source-files "test-client"))) "found the client sources")
  (let ((violations (client-violations "test-client" "TEST-CLIENT")))
    (is (null violations) "~{~a~^~%~}" violations)))

(test the-check-catches-internals
  ;; A double-colon reference, an exported symbol that is not public, and a
  ;; symbol of TUN that does not exist are all reported.
  (flet ((violations (text) (public-interface-violations text :package "TEST-CLIENT")))
    (is (find-if (lambda (v) (search "::" v)) (violations "(tun.core::run-operation 'x)")))
    (is (find-if (lambda (v) (search "RUN-OPERATION" v))
                 (violations "(tun.core:run-operation 'x)")))
    (is (find-if (lambda (v) (search "cannot be read" v)) (violations "(tun:no-such-thing)")))
    (is (null (violations "(defmethod tun:order-discount ((app t) order customer) 0)")))))

(test kernel-and-module-packages-are-locked
  (is (sb-ext:package-locked-p "TUN.CORE"))
  (is (sb-ext:package-locked-p "TUN.ORDERS"))
  (signals error (eval (read-from-string "(defun tun.orders::find-order (id) id)"))))
