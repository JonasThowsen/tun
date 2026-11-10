;;;; tests/generated.lisp -- the tests Tun generates for every client
;;;; (spec/testing.md 1): one form in the client's suite defines them, so a
;;;; check Tun adds reaches every client with its next Tun.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

;;; The checks. Each makes its FiveAM assertions in the generated test that
;;; calls it.

(defun check-package-uses-only-cl-and-tun (package)
  (fiveam:is (equal '("COMMON-LISP" "TUN")
                    (sort (mapcar #'package-name (package-use-list package)) #'string<))))

(defun check-sources-use-only-tuns-public-interface (system package)
  (let ((violations (client-violations system package)))
    (fiveam:is (null violations) "~{~a~^~%~}" violations)))

(defun check-client-modules-use-only-public-interfaces (system)
  "Check each of the client SYSTEM's own modules as Tun's suite checks Tun's:
loaded from its directory in the client's tree, and its sources reaching
the kernel and its dependencies only through their public interfaces
(testing.md 1, test 10)."
  (let ((violations (client-module-violations system)))
    (fiveam:is (null violations) "~{~a~^~%~}" violations)))

(defun client-text-owners (system)
  "The owners whose texts the translation test checks for the client SYSTEM:
the client and each of its own modules (testing.md 1)."
  (cons "client" (client-module-names system)))

(defun client-tools (system package)
  "The operations of the client SYSTEM whose package is PACKAGE, and those of
its own modules (testing.md 1): what the fuzzing, record-policy and
sequence tests call."
  (let ((modules (client-module-names system)))
    (append (client-operations package)
            (remove-if-not (lambda (operation) (member (operation-module operation) modules :test #'string=))
                           (all-operations)))))

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

(defun check-translations (class system)
  "Check that every text of the client SYSTEM and of its own modules has a
translation into each language CLASS offers, and that no entry of their
catalogues is unused."
  (with-test-app (:class class)
    (dolist (owner (client-text-owners system))
      (dolist (language (application-languages *app*))
        (let ((missing (untranslated-texts language :owner owner)))
          (fiveam:is (null missing) "~d texts of ~a lack ~a, such as ~{~s~^, ~}" (length missing) owner language
                     (subseq missing 0 (min 5 (length missing))))))
      (dolist (language +languages+)
        (let ((unused (unused-translations language :owner owner)))
          (fiveam:is (null unused) "~a entries of ~a no text uses: ~{~s~^, ~}" language owner unused))))))

(defun default-scenario (packages)
  "The scenario named default defined in PACKAGES, package names, or NIL."
  (find "default" (package-scenarios packages) :key #'scenario-name :test #'string=))

(defun needs-postgres-p (system package)
  "True when the client SYSTEM whose package is PACKAGE, or one of its own
modules, defines a query or an entity with a record policy, which only
Postgres runs (spec/store.md 5, 6)."
  (let ((packages (cons (find-package package)
                        (loop for name in (client-module-names system)
                              append (mapcar #'find-package (module-packages (find-module name t)))))))
    (flet ((own-p (name) (member (symbol-package name) packages)))
      (or (some (lambda (query) (own-p (query-name query))) (all-queries))
          (some (lambda (class) (and (own-p (class-name class)) (entity-record-policy class)))
                (all-entity-classes))))))

(defun check-every-tool-of-the-client-withstands-fuzzing (class system package packages variables)
  "Fuzz every tool of the client SYSTEM defines in PACKAGE on CLASS, with
the default scenario of PACKAGES when there is one and VARIABLES, the
client's own, unset around each tool's run (spec/testing.md 2): in memory,
or on Postgres when the client needs it."
  (check-every-tool-withstands-fuzzing (client-tools system package) system
                                       :class class :scenario (default-scenario packages)
                                       :variables variables
                                       :database (if (needs-postgres-p system package)
                                                     :postgres
                                                     :memory)))

(defun check-every-tool-of-the-client-keeps-to-the-record-policies (class system package packages
                                                                    variables)
  "Check that every tool of the client SYSTEM defines in PACKAGE on CLASS
keeps to the record policies (spec/testing.md 3), from the default scenario
of PACKAGES when there is one, with VARIABLES, the client's own, unset."
  (check-every-tool-keeps-to-the-record-policies (client-tools system package) system
                                                 :class class
                                                 :scenario (default-scenario packages)
                                                 :variables variables))

(defun check-the-client-s-tools-called-in-sequence (class system package packages variables)
  "Call the tools of the client SYSTEM defines in PACKAGE on CLASS in
sequence (spec/testing.md 4), from the default scenario of PACKAGES when
there is one, with VARIABLES, the client's own, unset: in memory, or on
Postgres when the client needs it."
  (check-tools-called-in-sequence (client-tools system package) system
                                  :class class :scenario (default-scenario packages)
                                  :variables variables
                                  :database (if (needs-postgres-p system package) :postgres :memory)))

(defun check-every-page-of-the-client (class system package packages variables)
  "Open every page of the client SYSTEM on CLASS as each role (spec/testing.md
5), from the default scenario of PACKAGES when there is one, with VARIABLES,
the client's own, unset: in memory, or on Postgres when the client defined
in PACKAGE needs it."
  (check-every-page-answers-every-role system
                                       :class class :scenario (default-scenario packages)
                                       :variables variables
                                       :database (if (needs-postgres-p system package) :postgres :memory)))

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
scenarios defined in PACKAGE and in the current package, and the fuzzing
and record-policy tests start each tool from the one of them named
default, and so do the sequence test and the page test.  Around each test,
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
         ,(generated-test "THE-CLIENT-S-MODULES-USE-ONLY-PUBLIC-INTERFACES"
                          `(check-client-modules-use-only-public-interfaces ,name))
         ,(generated-test "THE-APPLICATION-OPENS-WITH-THE-MODULES-IT-ENABLES"
                          `(check-application-opens-with-its-modules ,class ,name))
         ,(generated-test "EVERY-TEXT-HAS-A-TRANSLATION-INTO-EACH-LANGUAGE-OFFERED"
                          `(check-translations ,class ,name))
         ,(generated-test "EVERY-SCENARIO-MAKES-ITS-RECORDS"
                          `(check-every-scenario-makes-its-records
                            ,class ,name ',scenario-packages ',variables))
         ,(generated-test "EVERY-TOOL-WITHSTANDS-FUZZING"
                          `(check-every-tool-of-the-client-withstands-fuzzing
                            ,class ,name ,package ',scenario-packages ',isolate))
         ,(generated-test "EVERY-TOOL-KEEPS-TO-THE-RECORD-POLICIES"
                          `(check-every-tool-of-the-client-keeps-to-the-record-policies
                            ,class ,name ,package ',scenario-packages ',isolate))
         ,(generated-test "TOOLS-CALLED-IN-SEQUENCE-KEEP-THE-INVARIANTS"
                          `(check-the-client-s-tools-called-in-sequence
                            ,class ,name ,package ',scenario-packages ',isolate))
         ,(generated-test "EVERY-PAGE-ANSWERS-EVERY-ROLE"
                          `(check-every-page-of-the-client
                            ,class ,name ,package ',scenario-packages ',isolate))))))
