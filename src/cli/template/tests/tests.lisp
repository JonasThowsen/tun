;;;; tests/tests.lisp -- what every client checks: it uses only Tun's public
;;;; interface, its application opens on Postgres, which runs every query
;;;; once, with the modules it enables, every scenario makes its records, and
;;;; every text of its own has a translation into each language it offers.

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

(test every-text-has-a-translation-into-each-language-offered
  (with-test-app (:class {{name}}:*application-class*)
    (dolist (language (tun.core:application-languages *app*))
      (let ((missing (untranslated-texts language :owner "client")))
        (is (null missing) "~d texts lack ~a, such as ~{~s~^, ~}" (length missing) language
            (subseq missing 0 (min 5 (length missing))))))
    (dolist (language tun.core:+languages+)
      (let ((unused (unused-translations language :owner "client")))
        (is (null unused) "~a entries no text uses: ~{~s~^, ~}" language unused)))))

(test every-scenario-makes-its-records
  (dolist (name (scenario-names))
    (with-test-app (:class {{name}}:*application-class* :db (scratch-postgres "{{name}}"))
      (finishes (run-scenario name)))))
