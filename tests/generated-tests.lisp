;;;; tests/generated-tests.lisp -- the tests Tun generates for every client
;;;; (spec/testing.md 1), run on a probe client: a package made for the
;;;; test, with scenarios of its own and its generated tests in a suite no
;;;; run reaches. Each test runs one of the probe's generated tests and
;;;; reads its results. The test client (tests/client/) runs them all.

(in-package #:tun.tests)

(def-suite generated :in core)
(in-suite generated)

(defparameter +probe-package+ "TUN-PROBE-CLIENT"
  "The probe client's package.")

(defparameter +other-package+ "TUN-PROBE-OTHER"
  "A package beside the probe's, as another system loaded in the image is.")

(defvar *seen* '()
  "What each probe scenario saw when it began, newest first: its package,
its name, and the values of *PROGRAM-HANDLER*, *HTTP-JSON-HANDLER* and the
probe's own *SETTING*.")

(defun probe-symbol (name)
  (intern name +probe-package+))

(defun note-what-the-scenario-sees (package name)
  (push (list package name *program-handler* *http-json-handler*
              (symbol-value (probe-symbol "*SETTING*")))
        *seen*))

(defun define-probe-scenario (package name &rest body)
  "Define in PACKAGE the scenario NAME, which notes what it sees and then
runs BODY."
  (let ((*package* (find-package package)))
    (eval `(define-scenario ,(intern name) ()
             (note-what-the-scenario-sees ,package ,name)
             ,@body))))

(defun make-probe-client ()
  "Make the probe: its package, whose *APPLICATION-CLASS* is APPLICATION
and whose *SETTING* is a variable it isolates; its scenarios, the first of
which installs handlers; another package's scenarios; and its generated
tests."
  (let ((probe (make-package +probe-package+ :use '())))
    (make-package +other-package+ :use '())
    (dolist (variable '("*APPLICATION-CLASS*" "*SETTING*"))
      (proclaim `(special ,(intern variable probe))))
    (setf (symbol-value (probe-symbol "*APPLICATION-CLASS*")) 'application
          (symbol-value (probe-symbol "*SETTING*")) :configured)
    (define-probe-scenario +probe-package+ "DEFAULT")
    (define-probe-scenario +probe-package+ "INSTALLS-HANDLERS"
      `(setf *program-handler* (lambda (&rest arguments) arguments)
             *http-json-handler* (lambda (&rest arguments) arguments)
             ,(probe-symbol "*SETTING*") :installed))
    (define-probe-scenario +probe-package+ "LOOKS")
    (define-probe-scenario +other-package+ "DEFAULT")
    (define-probe-scenario +other-package+ "LOOKS")
    ;; A suite of the probe's own, which no suite holds and no run reaches.
    (let ((*package* probe)
          (fiveam::*suite* (make-instance 'fiveam::test-suite :name 'probe-suite)))
      (eval `(define-generated-tests "probe" :package ,+probe-package+
               :isolate (,(probe-symbol "*SETTING*")))))))

(defun remove-probe-client ()
  "Remove what MAKE-PROBE-CLIENT made: the probe's generated tests, both
packages' scenarios and the packages."
  (dolist (name (fiveam:test-names))
    (when (eq (symbol-package name) (find-package +probe-package+))
      (fiveam:rem-test name)))
  (let ((scenarios tun.test-support::*scenarios*))
    (loop for key being the hash-keys of scenarios
          when (member (car key) (list +probe-package+ +other-package+) :test #'string=)
            do (remhash key scenarios)))
  (dolist (name (list +probe-package+ +other-package+))
    (when (find-package name)
      (delete-package name))))

(defmacro with-probe-client (() &body body)
  `(unwind-protect
        (let ((*seen* '()))
          (make-probe-client)
          ,@body)
     (remove-probe-client)))

(defun run-probe-test (subject)
  "Run the probe's generated test GENERATED-SUBJECT; values whether it passed
and what explaining its results printed."
  (let ((results (let ((fiveam:*test-dribble* (make-broadcast-stream)))
                   (fiveam:run (probe-symbol (concatenate 'string "GENERATED-" subject))))))
    (values (fiveam:results-status results)
            (with-output-to-string (fiveam:*test-dribble*)
              (fiveam:explain! results)))))

(test define-generated-tests-names-each-test-for-its-check
  (with-probe-client ()
    (is (equal '("GENERATED-EVERY-SCENARIO-MAKES-ITS-RECORDS"
                 "GENERATED-EVERY-TEXT-HAS-A-TRANSLATION-INTO-EACH-LANGUAGE-OFFERED"
                 "GENERATED-EVERY-TOOL-KEEPS-TO-THE-RECORD-POLICIES"
                 "GENERATED-EVERY-TOOL-WITHSTANDS-FUZZING"
                 "GENERATED-THE-APPLICATION-OPENS-WITH-THE-MODULES-IT-ENABLES"
                 "GENERATED-THE-PACKAGE-USES-ONLY-CL-AND-TUN"
                 "GENERATED-THE-SOURCES-USE-ONLY-TUNS-PUBLIC-INTERFACE"
                 "GENERATED-TOOLS-CALLED-IN-SEQUENCE-KEEP-THE-INVARIANTS")
               (sort (loop for name in (fiveam:test-names)
                           when (eq (symbol-package name) (find-package +probe-package+))
                             collect (symbol-name name))
                     #'string<)))))

(test a-failing-generated-test-says-which-check-found-it
  (with-probe-client ()
    ;; The probe's package uses no package at all, not CL and TUN.
    (multiple-value-bind (passed explained) (run-probe-test "THE-PACKAGE-USES-ONLY-CL-AND-TUN")
      (is (not passed))
      (is (search "GENERATED-THE-PACKAGE-USES-ONLY-CL-AND-TUN" explained) "~a" explained))))

(test define-generated-tests-refuses-what-it-cannot-check
  (signals error (macroexpand-1 '(define-generated-tests "probe" :package "NO-SUCH-PACKAGE")))
  (signals error (macroexpand-1 '(define-generated-tests "tun" :package "COMMON-LISP"))
    "a package with no *APPLICATION-CLASS*")
  (with-probe-client ()
    (signals error (macroexpand-1 `(define-generated-tests "probe" :package ,+probe-package+
                                     :isolate (no-such-variable))))))

(test the-scenario-test-runs-only-the-clients-scenarios
  (with-probe-client ()
    (is (eq t (run-probe-test "EVERY-SCENARIO-MAKES-ITS-RECORDS")))
    (is (equal `((,+probe-package+ "DEFAULT") (,+probe-package+ "INSTALLS-HANDLERS")
                 (,+probe-package+ "LOOKS"))
               (mapcar (lambda (seen) (subseq seen 0 2)) (reverse *seen*)))
        "the other package's default and looks are not run")
    (flet ((package-of-default (package)
             (tun.test-support::scenario-package (find-scenario "default" :package package))))
      (is (string= +probe-package+ (package-of-default +probe-package+)))
      (is (string= +other-package+ (package-of-default +other-package+))))
    (signals error (find-scenario "default") "two packages define default")))

(test what-a-scenario-installs-reaches-neither-the-next-scenario-nor-the-next-test
  (with-probe-client ()
    (is (eq t (run-probe-test "EVERY-SCENARIO-MAKES-ITS-RECORDS")))
    (is (equal '(nil nil nil) (nthcdr 2 (find "LOOKS" *seen* :key #'second :test #'string=)))
        "the scenario after the one that installs handlers sees none")
    ;; The setf reached only the binding around the scenario: the values
    ;; outside it are what they were.
    (is (null *program-handler*))
    (is (null *http-json-handler*))
    (is (eq :configured (symbol-value (probe-symbol "*SETTING*"))))
    (setf *seen* '())
    (is (eq t (run-probe-test "EVERY-SCENARIO-MAKES-ITS-RECORDS")))
    (is (every (lambda (seen) (equal '(nil nil nil) (nthcdr 2 seen))) *seen*)
        "the next generated test sees none: ~s" *seen*)))

(test a-generated-test-runs-with-the-handlers-unset
  ;; A handler a client's own test left installed for every thread does not
  ;; reach a generated test.
  (with-probe-client ()
    (unwind-protect
         (progn
           (setf *program-handler* (lambda (&rest arguments) arguments))
           (is (eq t (run-probe-test "EVERY-SCENARIO-MAKES-ITS-RECORDS")))
           (is (= 3 (length *seen*)))
           (is (every (lambda (seen) (null (third seen))) *seen*)))
      (setf *program-handler* nil))))
