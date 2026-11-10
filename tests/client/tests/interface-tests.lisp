;;;; tests/interface-tests.lisp -- a client may use only Tun's public
;;;; interface: the external symbols of TUN, and TUN.UI for its pages. The
;;;; generated tests check the test client with it; these check the check.

(in-package #:test-client.tests)

(def-suite interface :in client)
(in-suite interface)

(test the-check-reads-every-client-source
  (is (<= 7 (length (client-source-files "test-client")))))

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

;;; The client's own module, logbook, kept in its modules/ (tun-platform.md
;;; 2.1): checked as a module, not as the client's (testing.md 1, tests 2
;;; and 10).

(test the-client-s-module-is-checked-as-a-module-not-as-the-client
  (is (equal '("logbook") (client-module-names "test-client")))
  (is (notany (lambda (file) (search "/modules/logbook/" (namestring file)))
              (client-source-files "test-client")))
  (is (null (client-module-violations "test-client")))
  (is (member "logbook_add" (mapcar #'tun.core:operation-tool (tun.core:all-operations)) :test #'string=)))

(test the-generated-tests-take-the-client-s-module-with-the-client
  ;; The fuzzing, record-policy and sequence tests call the module's tools,
  ;; and the translation test checks its texts (testing.md 1).
  (let ((tools (mapcar #'tun.core:operation-tool (client-tools "test-client" "TEST-CLIENT"))))
    (is (member "logbook_add" tools :test #'string=))
    (is (member "logbook_list" tools :test #'string=)))
  (is (member "logbook" (client-text-owners "test-client") :test #'string=))
  (is (find "logbook" (known-texts) :key #'third :test #'equal)
      "the module writes texts for the translation test to check"))

(test a-planted-qualifier-in-the-client-s-module-fails-its-check
  ;; A copy of the client with logbook.lisp reaching into the kernel: the
  ;; module check names the file, from the client's directory.
  (let* ((client (asdf:system-source-directory "test-client"))
         (copy (merge-pathnames (format nil ".build/test-db/planted-~a/" (tun.core:new-id "p"))
                                (asdf:system-source-directory "tun"))))
    (dolist (file (directory (merge-pathnames "modules/logbook/*.*" client)))
      (let ((target (merge-pathnames (enough-namestring file client) copy)))
        (ensure-directories-exist target)
        (uiop:copy-file file target)))
    (with-open-file (out (merge-pathnames "modules/logbook/logbook.lisp" copy)
                         :direction :output :if-exists :append)
      (format out "~%(defun planted () (tun.core::run-guarded nil nil nil))~%"))
    (let ((violations (client-module-violations-under copy)))
      (is (find-if (lambda (v) (search "modules/logbook/logbook.lisp: uses a :: qualifier" v)) violations)
          "~s" violations)
      (is (find-if (lambda (v) (search "is loaded from" v)) violations)
          "a copy is not where the module was loaded from"))))
