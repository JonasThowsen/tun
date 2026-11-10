;;;; tests/run.lisp -- what bin/test runs: compile the client, its own modules
;;;; and its and their tests, failing on any compiler warning in them, then run
;;;; the client's suite and each module's.

(setf *read-eval* nil)
(load (or (sb-ext:posix-getenv "ASDF") (error "Run inside `nix develop` (ASDF is not set)")))

;;; The client's own modules, one directory each under modules/
;;; ($TUN_SOURCE/spec/tun-platform.md 2.1), from the working tree before any
;;; copy elsewhere, and compiled as strictly as the client.
(asdf:initialize-source-registry
 `(:source-registry (:tree ,(merge-pathnames "modules/" (uiop:getcwd))) :inherit-configuration))

(defparameter *own-modules*
  (mapcar #'pathname-name (directory (merge-pathnames "modules/*/tun-*.asd" (uiop:getcwd))))
  "The systems of the client's own modules, tun-NAME.")

(defparameter *module-tests*
  (loop for module in *own-modules*
        for tests = (format nil "~a/tests" module)
        when (asdf:find-system tests nil) collect tests)
  "The modules' own tests, tun-NAME/tests, where a module's .asd defines them.")

(defparameter *systems* (append *own-modules* *module-tests* '("{{name}}" "{{name}}/tests")))

;;; Tun, its modules and the test libraries come compiled from the Nix
;;; store. Load them first, quietly: their warnings are not the client's.
(let ((*compile-verbose* nil) (*load-verbose* nil))
  (handler-bind ((warning #'muffle-warning))
    (dolist (system *systems*)
      (dolist (dependency (asdf:system-depends-on (asdf:find-system system)))
        (unless (member dependency *systems* :test #'equal)
          (asdf:load-system dependency))))))

;;; Compile the client's own systems afresh, so every warning shows.
(let ((warnings '())
      (*compile-verbose* nil)
      (*compile-print* nil))
  (handler-bind ((warning (lambda (warning)
                            ;; Compiling a file and then loading it redefines its
                            ;; macros; that is not a defect in the code.
                            (unless (typep warning 'sb-kernel:redefinition-with-defmacro)
                              (push (princ-to-string warning) warnings))
                            (muffle-warning warning))))
    (with-compilation-unit (:override t)
      (asdf:load-system (car (last *systems*)) :force *systems*)
      ;; The modules' tests, which the client does not depend on.
      (dolist (tests *module-tests*)
        (asdf:load-system tests :force (list tests)))))
  (when warnings
    (format t "~&;; FAIL: ~d compiler warning~:p:~%~{;;   ~a~%~}"
            (length warnings) (reverse warnings))
    (uiop:quit 2)))

;;; The client's suite, then each module's: the package TUN.NAME.TESTS of
;;; tun-NAME/tests exports RUN-TESTS, true when every test passed.
(let ((results (cons (uiop:symbol-call "{{package}}.TESTS" "RUN-TESTS")
                     (loop for tests in *module-tests*
                           for module = (subseq tests 0 (position #\/ tests))
                           collect (uiop:symbol-call
                                    (format nil "TUN.~:@(~a~).TESTS" (subseq module (length "tun-")))
                                    "RUN-TESTS")))))
  (uiop:quit (if (every #'identity results) 0 1)))
