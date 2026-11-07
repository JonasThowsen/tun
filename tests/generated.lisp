;;;; tests/generated.lisp -- the tests Tun generates for every client
;;;; (spec/testing.md 1): one form in the client's suite defines them, so a
;;;; check Tun adds reaches every client with its next Tun.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *isolated-variables* '(tun:*program-handler* tun:*http-json-handler*)
  "Tun's variables through which a scenario or a test installs what answers
for another system for every thread. Each generated test, and each scenario
the scenario test runs, sees them NIL, and what it sets reaches neither the
next scenario nor the next test (spec/testing.md 1, Isolation).")

(defun call-with-variables-unset (variables function)
  "Call FUNCTION with each of VARIABLES, special variables, bound to NIL, so
what FUNCTION sets them to ends with it."
  (progv variables (make-list (length variables))
    (funcall function)))

;;; The checks. Each makes its FiveAM assertions in the generated test that
;;; calls it.

(defun check-package-uses-only-cl-and-tun (package)
  (fiveam:is (equal '("COMMON-LISP" "TUN")
                    (sort (mapcar #'package-name (package-use-list package)) #'string<))))

(defun check-sources-use-only-tuns-public-interface (system package)
  (let ((violations (client-violations system package)))
    (fiveam:is (null violations) "~{~a~^~%~}" violations)))

(defun check-application-opens-with-its-modules (class system)
  "Open CLASS on a fresh Postgres database, which runs every record policy
and query, and check that it enables the modules it names and no others."
  (with-test-app (:class class :db (scratch-postgres system))
    (let ((enabled (loop for module across (jget (call-ok "introspect_runtime" "admin:a")
                                                 "modules")
                         when (equal (jget module "enabled_by") "client")
                           collect (jget module "name"))))
      (fiveam:is (equal (sort (copy-list (application-declared-modules *app*)) #'string<)
                        (sort enabled #'string<))))))

(defun check-translations (class)
  "Check that every text of the client has a translation into each language
CLASS offers, and that no entry of its catalogues is unused."
  (with-test-app (:class class)
    (dolist (language (application-languages *app*))
      (let ((missing (untranslated-texts language :owner "client")))
        (fiveam:is (null missing) "~d texts lack ~a, such as ~{~s~^, ~}" (length missing) language
                   (subseq missing 0 (min 5 (length missing))))))
    (dolist (language +languages+)
      (let ((unused (unused-translations language :owner "client")))
        (fiveam:is (null unused) "~a entries no text uses: ~{~s~^, ~}" language unused)))))

(defun check-every-scenario-makes-its-records (class system packages variables)
  "Run each scenario defined in PACKAGES, package names, on a fresh Postgres
database of its own, with VARIABLES unset around it."
  (dolist (scenario (package-scenarios packages))
    (with-test-app (:class class :db (scratch-postgres system))
      (call-with-variables-unset variables
                                 (lambda () (fiveam:finishes (run-scenario scenario)))))))

;;; The form

(defun application-class-variable (package)
  "The symbol *APPLICATION-CLASS* of PACKAGE, whose value is the client's
application class."
  (unless (find-package package)
    (error "define-generated-tests: there is no package ~a" package))
  (or (find-symbol "*APPLICATION-CLASS*" package)
      (error "define-generated-tests: the package ~a has no *APPLICATION-CLASS*" package)))

(defun isolated-variables (variables)
  "Tun's variables to isolate and then VARIABLES, those the client names."
  (dolist (variable variables)
    (unless (and (symbolp variable) (boundp variable))
      (error "define-generated-tests: ~s in :isolate is not a global variable" variable)))
  (append *isolated-variables* variables))

(defmacro define-generated-tests (name &key package isolate)
  "Define in the current FiveAM suite the tests Tun generates for the client
whose system is NAME, a string, and whose package is PACKAGE, a string
(spec/testing.md 1). The application class is the value of
*APPLICATION-CLASS* in PACKAGE. Each test is named for what it checks,
prefixed GENERATED-, in the current package. The scenario test runs the
scenarios defined in PACKAGE and in the current package. Around each test,
and around each scenario that test runs, *ISOLATED-VARIABLES* and the
variables ISOLATE names are bound to NIL."
  (check-type name string)
  (check-type package string)
  (let ((class (application-class-variable package))
        (variables (isolated-variables isolate))
        (scenario-packages (remove-duplicates (list (package-name (find-package package))
                                                    (package-name *package*))
                                              :test #'string=)))
    (flet ((generated-test (subject check)
             `(fiveam:test ,(intern (concatenate 'string "GENERATED-" subject))
                (call-with-variables-unset ',variables (lambda () ,check)))))
      `(progn
         ,(generated-test "THE-PACKAGE-USES-ONLY-CL-AND-TUN"
                          `(check-package-uses-only-cl-and-tun ,package))
         ,(generated-test "THE-SOURCES-USE-ONLY-TUNS-PUBLIC-INTERFACE"
                          `(check-sources-use-only-tuns-public-interface ,name ,package))
         ,(generated-test "THE-APPLICATION-OPENS-WITH-THE-MODULES-IT-ENABLES"
                          `(check-application-opens-with-its-modules ,class ,name))
         ,(generated-test "EVERY-TEXT-HAS-A-TRANSLATION-INTO-EACH-LANGUAGE-OFFERED"
                          `(check-translations ,class))
         ,(generated-test "EVERY-SCENARIO-MAKES-ITS-RECORDS"
                          `(check-every-scenario-makes-its-records
                            ,class ,name ',scenario-packages ',variables))))))
