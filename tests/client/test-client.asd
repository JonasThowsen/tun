;;;; test-client.asd -- the test client: a small rental business, Nordvik
;;;; Utleie, built only from the public TUN package. The kernel suite cannot
;;;; load client code (tests/module-tests.lisp checks that), so bin/test runs
;;;; this client's suite in a process of its own: the interface check on real
;;;; client files, each kind of extension point, the hooks in explain and in
;;;; request traces, the screens and a manifest that enables some modules only.

(defsystem "test-client"
  :description "Nordvik Utleie, the client Tun's own suite tests the client surface on."
  :version "0.1.0"
  :depends-on ("tun" "tun-customers" "tun-catalog" "tun-orders" "tun-messaging")
  :serial t
  :components ((:file "package")
               (:file "customers")
               (:file "catalog")
               (:file "orders")
               (:file "workflows")
               (:file "screens")
               (:file "application")))

(defsystem "test-client/tests"
  :description "The test client's suite: the client surface of the kernel and the modules."
  :depends-on ("test-client" "tun-test-support" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "interface-tests")
                             (:file "extension-tests")
                             (:file "introspection-tests")
                             (:file "web-tests")
                             (:file "composition-tests")))))
