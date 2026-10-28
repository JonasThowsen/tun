;;;; tests/module-system-tests.lisp -- the module contract (tun-platform.md 2,
;;;; core.md §1.3): identity, dependencies, boundary, ordering,
;;;; conflicts, migrations per module, registry attribution.

(in-package #:tun.tests)

(def-suite module-system :in core)
(in-suite module-system)

(defparameter +slice2-modules+
  '(("customers") ("catalog") ("inventory" "catalog") ("reviews")
    ("orders" "customers" "catalog" "inventory" "reviews")
    ("invoicing" "orders") ("messaging" "orders" "customers" "notifications" "inbox") ("staffing" "orders")
    ("calendar" "orders" "staffing") ("warehouse" "staffing")
    ("notifications" "customers" "orders" "staffing") ("inbox" "customers" "orders" "notifications")
    ("dashboard"))
  "Each module and what it depends on (core.md §1.3, each module's README), and the
developer's dashboard (modules/dashboard/README.md).")

(test the-ten-modules-are-loaded-with-the-declared-dependencies
  (is (= (length +slice2-modules+) (length (all-modules))))
  (dolist (entry +slice2-modules+)
    (let ((module (find-module (first entry))))
      (is (not (null module)) "module ~a is loaded" (first entry))
      (when module
        (is (equal (sort (copy-list (rest entry)) #'string<)
                   (sort (copy-list (module-depends-on module)) #'string<))
            "~a depends on ~a" (first entry) (rest entry))
        (is (module-sealed-p module))
        (is (every (lambda (c) (version-satisfies-p +core-version+ c)) (module-core-range module)))))))

(test modules-load-in-dependency-order
  (let ((names (mapcar #'module-name (all-modules))))
    (dolist (module (all-modules))
      (dolist (dependency (module-depends-on module))
        (is (< (position dependency names :test #'string=) (position (module-name module) names :test #'string=))
            "~a loads before ~a" dependency (module-name module))))))

(defun module-flake-text (name)
  (file-text (merge-pathnames "flake.nix" (asdf:system-source-directory (format nil "tun-~a" name)))))

(test each-module-declares-the-same-dependencies-everywhere
  ;; The Lisp declaration (define-module), the ASDF system and the module's
  ;; flake (which the client build reads) must agree.
  (dolist (module (all-modules))
    (let* ((name (module-name module))
           (system (asdf:find-system (format nil "tun-~a" name)))
           (asd-deps (remove "tun" (mapcar (lambda (d) (if (stringp d) d (string-downcase (princ-to-string d))))
                                           (asdf:system-depends-on system))
                             :test #'string=))
           (flake (module-flake-text name)))
      (is (equal (sort (mapcar (lambda (d) (format nil "tun-~a" d)) (module-depends-on module)) #'string<)
                 (sort (copy-list asd-deps) #'string<))
          "~a: .asd depends on ~a" name asd-deps)
      (is (search (format nil "name = \"~a\";" name) flake) "~a: flake names the module" name)
      (is (search (format nil "dependsOn = [~{ \"~a\"~} ];" (module-depends-on module)) flake)
          "~a: flake dependsOn matches" name)
      (is (search (format nil "core = [~{ \"~a\"~} ];" (module-core-range module)) flake)
          "~a: flake core range matches ~s" name (module-core-range module)))))

(test the-core-flake-states-the-core-version
  (is (search (format nil "coreVersion = \"~a\";" +core-version+)
              (file-text (merge-pathnames "flake.nix" (asdf:system-source-directory "tun"))))))

(test every-module-uses-only-public-interfaces
  (dolist (module (all-modules))
    (let ((violations (module-violations (module-name module))))
      (is (null violations) "~{~a~^~%~}" violations))))

(test the-module-check-catches-undeclared-and-internal-reaches
  (let ((public (append +kernel-public-packages+ '("TUN.CUSTOMERS" "TUN.CATALOG" "TUN.INVENTORY"))))
    (flet ((check (text)
             (public-interface-violations text :package "TUN.ORDERS" :public-packages public)))
      ;; orders does not depend on messaging or staffing
      (is (check "(tun.messaging:send-message \"quote\")"))
      (is (check "(defpackage #:x (:use #:tun.invoicing))"))
      ;; an internal symbol of a dependency, or any ::
      (is (check "(tun.inventory::stock-row \"p\")"))
      (is (check "(tun.core::run-guarded nil nil nil)"))
      ;; the dependency's external symbols are fine
      (is (null (check "(tun.inventory:on-hand \"p\")")))
      (is (null (check "(tun.web:register-web-resource :path \"/x\")"))))))

(defmacro with-scratch-modules (&body body)
  "Run BODY, then forget any module registered in it and restore APPLICATION."
  (let ((saved (gensym)))
    `(let ((,saved (copy-list tun.core::*loaded-modules*)))
       (unwind-protect (progn ,@body)
         (setf tun.core::*loaded-modules* ,saved)
         (tun.core::install-module-mixins)))))

(defclass zz-a-module () ())
(defclass zz-b-module () ())

(test module-registration-refuses-bad-declarations
  (with-scratch-modules
    (signals extension-error (register-module "zz_a" :depends-on '("no_such_module") :packages '()
                                                     :mixin 'zz-a-module))
    (signals extension-error (register-module "zz_a" :depends-on '("zz_a") :packages '() :mixin 'zz-a-module))
    (signals extension-error (register-module "Bad-Name" :packages '() :mixin 'zz-a-module))
    ;; The constraint is named in the refusal.
    (let ((e (handler-case (register-module "zz_a" :core-range '(">= 9.0") :packages '() :mixin 'zz-a-module)
               (extension-error (e) e))))
      (is (typep e 'extension-error))
      (is (search ">= 9.0" (princ-to-string e))))
    ;; A cycle: zz_a, then zz_b depending on zz_a, then zz_a re-declared on zz_b.
    (register-module "zz_a" :packages '() :mixin 'zz-a-module)
    (register-module "zz_b" :depends-on '("zz_a") :packages '() :mixin 'zz-b-module)
    (let ((e (handler-case (register-module "zz_a" :depends-on '("zz_b") :packages '() :mixin 'zz-a-module)
               (extension-error (e) e))))
      (is (typep e 'extension-error))
      (is (search "cycle" (princ-to-string e))))))

(test application-inherits-the-modules-most-dependent-first
  ;; So :before and :after methods run in dependency order (least specific
  ;; first), and a client's features, more specific still, run last.
  (let* ((cpl (closer-mop:class-precedence-list (find-class 'application)))
         (positions (mapcar (lambda (m) (position (find-class (module-mixin m)) cpl)) (all-modules))))
    (is (every #'integerp positions))
    (dolist (module (all-modules))
      (dolist (dependency (module-depends-on module))
        (is (< (position (find-class (module-mixin module)) cpl)
               (position (find-class (module-mixin (find-module dependency))) cpl))
            "~a is more specific than ~a" (module-name module) dependency)))))

(define-application zz-partial-app ()
  (:modules orders))

(test enabled-by-names-the-client-or-the-dependent-module
  (with-test-app ()
    (let ((app (make-instance 'zz-partial-app)))
      (let ((enabled (mapcar (lambda (e) (cons (module-name (first e)) (second e))) (enabled-modules app))))
        (is (equal "client" (cdr (assoc "orders" enabled :test #'string=))))
        (is (equal "orders" (cdr (assoc "inventory" enabled :test #'string=))))
        (is (equal "orders" (cdr (assoc "customers" enabled :test #'string=))))
        (is (null (assoc "messaging" enabled :test #'string=))))
      ;; In this image every module is loaded, so this client would run with
      ;; modules it does not enable: refused at start.
      (signals extension-error (check-enabled-modules app)))))

(test conflicts-are-refused-not-resolved
  ;; A client may not replace a template a module marked final.
  (unwind-protect
       (progn
         (tun.core::register-message-template "zz_final" 'zz-final-template :label "x" :source :core
                                                                            :module "orders" :final t)
         (signals extension-error
           (tun.core::register-message-template "zz_final" 'zz-client-template :label "y" :source :client
                                                                               :module "client")))
    (setf tun.core::*message-templates*
          (remove "zz_final" tun.core::*message-templates* :key #'message-template-name :test #'string=)))
  ;; A rule on an entity that runs no rules (an embedded order line).
  (signals extension-error (tun.core::register-rule 'tun.orders:order-line 'zz-rule (lambda (x) x)))
  ;; Two definitions of one tool name.
  (signals extension-error
    (tun.core::register-operation (make-instance 'operation :name 'zz-other-orders-get :tool "orders_get"
                                                            :kind :read :policy :viewer :parameters '()))))

(test template-override-retains-name-increments-version-and-marks-owner
  (let ((tun.core::*message-templates* (copy-list tun.core::*message-templates*)))
    (tun.core::register-message-template "unit_override" 'unit-default :source :core :module "messaging"
       :subject "Default" :text "Default")
    (tun.core::register-message-template "unit_override" 'unit-client :source :client :module "client"
       :subject "Client" :text "Client")
    (let ((description (tun.core:message-template-description (tun.core:find-message-template "unit_override"))))
      (is (equal "unit_override" (jget description "name")))
      (is (= 2 (jget description "version")))
      (is (equal "client" (jget description "module")))
      (is (equal "Client" (jget description "text"))))))

(test registry-names-the-owning-module-of-every-item
  (with-test-app ()
    (let* ((registry (call-ok "registry_describe" "viewer:v"))
           (entities (coerce (jget registry "entities") 'list))
           (operations (coerce (jget registry "operations") 'list)))
      (flet ((module-of (name list) (jget (find-by "name" name list) "module")))
        (is (string= "customers" (module-of "customer" entities)))
        (is (string= "orders" (module-of "order" entities)))
        (is (string= "core" (module-of "workflow" entities)))
        (is (string= "messaging" (module-of "message" entities)))
        (is (string= "orders" (module-of "orders_confirm" operations)))
        (is (string= "invoicing" (module-of "invoices_send" operations)))
        (is (string= "core" (module-of "registry_describe" operations)))
        ;; source stays core/client (core.md §1.3), module is the owner.
        (is (string= "core" (jget (find-by "name" "orders_confirm" operations) "source"))))
      (is (every (lambda (e) (and (jget e "module")
                                  (every (lambda (f) (jget f "module")) (coerce (jget e "fields") 'list))))
                 entities))
      (is (every (lambda (o) (jget o "module")) operations))
      (is (= (length +slice2-modules+) (length (jget registry "modules"))))
      (let ((points (mapcar (lambda (p) (jget p "name")) (coerce (jget registry "extension_points") 'list))))
        (dolist (point '("discount" "requirements" "booking_window" "screen"))
          (is (member point points :test #'string=) "extension point ~a" point))))))

(test introspect-runtime-lists-the-modules
  (with-test-app ()
    (let* ((runtime (call-ok "introspect_runtime" "admin:a"))
           (modules (coerce (jget runtime "modules") 'list)))
      (is (equal (mapcar #'module-name (all-modules)) (mapcar (lambda (m) (jget m "name")) modules)))
      (let ((orders (find-by "name" "orders" modules)))
        (is (equalp #("customers" "catalog" "inventory" "reviews") (jget orders "depends_on")))
        (is (string= "client" (jget orders "enabled_by")))
        (is (stringp (jget orders "revision")))))))

(test migrations-are-recorded-per-module
  (let ((db (scratch-path "migrations")))
    (with-test-app (:db db)
      (multiple-value-bind (tables migrations)
          (with-application (*app*) (store-describe-schema *store*))
        (declare (ignore tables))
        (let ((ids (map 'list (lambda (m) (jget m "id")) migrations)))
          (is (find-if (lambda (id) (string-prefix-p "customers_0001_create_customers" id)) ids))
          (is (find-if (lambda (id) (string-prefix-p "orders_" id)) ids))
          (is (find-if (lambda (id) (string-prefix-p "core_" id)) ids))
          ;; Per module, numbered from 1 without gaps.
          (dolist (module (cons "core" (mapcar #'module-name (all-modules))))
            (let ((own (remove-if-not (lambda (id) (string-prefix-p (format nil "~a_" module) id)) ids)))
              (loop for id in own
                    for n from 1
                    do (is (string-prefix-p (format nil "~a_~4,'0d_" module n) id))))))))
    ;; Restarting migrates nothing again (idempotent).
    (with-test-app (:db db)
      (multiple-value-bind (tables migrations) (with-application (*app*) (store-describe-schema *store*))
        (declare (ignore tables))
        (is (= (length migrations)
               (length (remove-duplicates (map 'list (lambda (m) (jget m "id")) migrations) :test #'string=))))))))
