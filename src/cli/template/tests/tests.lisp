;;;; tests/tests.lisp -- what every client checks: it uses only Tun's public
;;;; interface, its application opens on Postgres, which runs every query
;;;; once, with the modules it enables, and every scenario makes its records.

(in-package #:{{name}}.tests)

(in-suite {{name}})

(test the-package-uses-only-cl-and-tun
  (is (equal '("COMMON-LISP" "TUN")
             (sort (mapcar #'package-name (package-use-list "{{package}}")) #'string<))))

(test the-sources-use-only-tuns-public-interface
  (let ((violations (client-violations "{{name}}" "{{package}}")))
    (is (null violations) "~{~a~^~%~}" violations)))

(test the-application-opens-with-the-modules-it-enables
  (with-test-app (:class {{name}}:*application-class* :db (scratch-postgres "{{name}}"))
    (let ((enabled (loop for module across (tun.core:jget (call-ok "introspect_runtime" "admin:a")
                                                          "modules")
                         when (equal (tun.core:jget module "enabled_by") "client")
                           collect (tun.core:jget module "name"))))
      (is (equal (sort (copy-list (tun.core:application-declared-modules *app*)) #'string<)
                 (sort enabled #'string<))))))

(test every-scenario-makes-its-records
  (dolist (name (scenario-names))
    (with-test-app (:class {{name}}:*application-class* :db (scratch-postgres "{{name}}"))
      (finishes (run-scenario name)))))
