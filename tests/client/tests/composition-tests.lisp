;;;; tests/composition-tests.lisp -- a manifest that enables some modules:
;;;; only they and their dependencies are loaded and enabled, and the tools
;;;; of the modules left out are absent.

(in-package #:test-client.tests)

(def-suite composition :in client)
(in-suite composition)

(test only-the-manifest-and-its-dependencies-are-loaded
  (is (equal '("catalog" "customers" "inbox" "inventory" "messaging" "notifications" "orders"
               "reviews" "staffing")
             (sort (mapcar #'tun.core:module-name (tun.core:all-modules)) #'string<)))
  (with-client ()
    (let ((modules (coerce (jget (call-ok "introspect_runtime" "admin:ada") "modules") 'list)))
      (dolist (name '("customers" "catalog" "orders" "messaging"))
        (is (equal "client" (jget (find-by "name" name modules) "enabled_by")) "~a" name))
      (is (equal "orders" (jget (find-by "name" "inventory" modules) "enabled_by")))
      (is (equal "orders" (jget (find-by "name" "reviews" modules) "enabled_by"))))
    (let ((tools (mapcar #'tun.core:operation-tool (tun.core:visible-operations *app*))))
      (is (notany (lambda (tool) (or (search "invoices_" tool) (search "calendar_" tool))) tools))
      (is (member "messages_list" tools :test #'string=))
      (is (member "products_set_cleaning_days" tools :test #'string=)))))
