;;;; scripts/test.lisp -- compile the test-suites strictly, or run one of them
;;;; (spec/tooling.md, "Running the tests").
;;;; Usage: sbcl --load scripts/test.lisp ACTION ...
;;;;   compile core     compile Tun and its tests, check that every test of
;;;;                    the suite core is in one of its child suites, and
;;;;                    list those in .build/test/core-suites
;;;;   compile CLIENT   after compile core: compile a client system, such as
;;;;                    test-client, and CLIENT/tests
;;;;   run core SUITE   load what was compiled and run SUITE, a child of core
;;;;   run CLIENT       load what was compiled and run CLIENT/tests
;;;;   only SUITE       compile core, then run its suite SUITE in this process
;;;; bin/test compiles first, then runs each suite in a process of its own;
;;;; bin/test --only SUITE is the last form.  A compile fails on any compiler
;;;; warning or style warning in our code, and a run compiles nothing.

(load (merge-pathnames "setup.lisp" *load-truename*))
(in-package #:tun-build)

(load-quietly "alexandria" "bordeaux-threads" "cl-base64" "cl-ppcre" "closer-mop" "com.inuoe.jzon"
              "drakma" "fiveam" "hunchentoot" "ironclad" "sqlite" "cl-postgres" "swank" "usocket")

(defparameter *core-systems* '("tun" "tun/tests"))

(defun client-systems (client)
  "The systems of CLIENT's suite, in load order."
  (list "tun" client (format nil "~a/tests" client)))

;;; What one compile leaves for bin/test and for the compiles after it, in
;;; .build/test/: core-suites, the suites to run, and compiled, the systems
;;; of ours this run has compiled.

(defun test-file (name)
  (merge-pathnames (concatenate 'string ".build/test/" name) *root*))

(defun write-lines (name lines &key append)
  "Write LINES to the file NAME in .build/test/, after what it holds when APPEND."
  (let ((file (test-file name)))
    (ensure-directories-exist file)
    (with-open-file (out file :direction :output :if-does-not-exist :create
                         :if-exists (if append :append :supersede))
      (format out "~{~a~%~}" lines))))

(defun compiled-systems ()
  "The systems of ours this run has compiled so far."
  (let ((file (test-file "compiled")))
    (and (probe-file file) (uiop:read-file-lines file))))

;;; Compiling

(defun compile-or-exit (systems &key except)
  "Compile SYSTEMS strictly, every system of ours forced but those in EXCEPT;
exit 2 on a warning."
  (let* ((start (get-internal-real-time))
         (warnings (compile-strictly systems :force t :except except))
         (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
    (format t "~&;; compiled ~{~a~^, ~} in ~,2fs~%" systems seconds)
    (when warnings
      (format t "~&;; FAIL: ~d compiler warning~:p:~%~{;;   ~a~%~}" (length warnings) warnings)
      (exit-with 2))))

(defun core-tests-call (name &rest arguments)
  "Call the function NAME of the core tests' package, which is loaded only now."
  (apply (find-symbol name "TUN.TESTS") arguments))

(defun check-core-suites ()
  "Exit 2 naming every test placed directly in the suite core: no process
of bin/test would run it."
  (let ((strays (core-tests-call "TESTS-OUTSIDE-CHILD-SUITES")))
    (when strays
      (format t "~&;; FAIL: ~d test~:p in the suite core, outside its child suites:~%~
                 ~{;;   ~a~%~};; Put each in a child suite, (def-suite NAME :in core).~%"
              (length strays) strays)
      (exit-with 2))))

(defun compile-core ()
  (compile-or-exit *core-systems*)
  (check-core-suites)
  (write-lines "core-suites" (core-tests-call "CORE-CHILD-SUITES"))
  (write-lines "compiled" (our-systems)))

(defun compile-client (client)
  "Compile CLIENT and its tests.  The kernel and the modules, which compile
core compiled, are loaded as they are, and so is a part of the client that
another client of this run shares and compiled first."
  (let ((before (compiled-systems)))
    (compile-or-exit (client-systems client) :except before)
    (write-lines "compiled" (set-difference (our-systems) before :test #'string=) :append t)))

;;; Running

(defvar *compiling-refused* nil
  "True while a suite's process loads what bin/test compiled before it.")

(defmethod asdf:perform :before ((operation asdf:compile-op) (file asdf:cl-source-file))
  (when *compiling-refused*
    (error "~a is not compiled: a suite loads what bin/test compiled, and compiles nothing"
           (asdf:component-pathname file))))

(defun load-compiled (systems)
  "Load SYSTEMS from the files bin/test compiled; an error when one would
have to be compiled first."
  (let ((*compiling-refused* t))
    (asdf:load-system (car (last systems)))))

(defun core-suite (name)
  "The child suite of core named NAME, or exit 2."
  (let ((suite (find-symbol (string-upcase name) "TUN.TESTS")))
    (unless (and suite (fiveam:get-test suite))
      (format t "~&;; no core test suite named ~a~%" name)
      (exit-with 2))
    suite))

(defun client-runner (client)
  "The function that runs CLIENT's suite."
  ;; A manifest suite (shop-minimal) has package SHOP-MINIMAL.TESTS.
  (find-symbol "RUN-CLIENT-TESTS" (format nil "~:@(~a~).TESTS" (substitute #\- #\/ client))))

(defun run-and-exit (name runner)
  "Call RUNNER, which runs the suite NAME and is true when it passed; exit 0
when it did, else 1."
  (let* ((start (get-internal-real-time))
         (ok (funcall runner))
         (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
    (format t "~&;; ~a suite ~:[FAILED~;passed~] in ~,2fs~%" name ok seconds)
    (exit-with (if ok 0 1))))

(defun usage ()
  (format *error-output* "~&usage: sbcl --load scripts/test.lisp ~
                          compile core|CLIENT, run core SUITE, run CLIENT or only SUITE~%")
  (exit-with 2))

(destructuring-bind (&optional action target name &rest more) (rest sb-ext:*posix-argv*)
  (cond (more (usage))
        ((and (equal action "compile") (equal target "core"))
         (compile-core))
        ((and (equal action "compile") target)
         (compile-client target))
        ((and (equal action "run") (equal target "core") name)
         (load-compiled *core-systems*)
         (let ((suite (core-suite name)))
           (run-and-exit name (lambda () (core-tests-call "RUN-CORE-TESTS" suite)))))
        ((and (equal action "run") target (not (equal target "core")))
         (load-compiled (client-systems target))
         (run-and-exit target (client-runner target)))
        ((and (equal action "only") target)
         (compile-or-exit *core-systems*)
         (let ((suite (core-suite target)))
           (run-and-exit target (lambda () (fiveam:run! suite)))))
        (t (usage))))
(exit-with 0)
