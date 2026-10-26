;;;; tests/run.lisp -- what bin/test runs: compile the client and its tests,
;;;; failing on any compiler warning in them, then run the suite.

(setf *read-eval* nil)
(load (or (sb-ext:posix-getenv "ASDF") (error "Run inside `nix develop` (ASDF is not set)")))

(defparameter *systems* '("{{name}}" "{{name}}/tests"))

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
      (asdf:load-system (car (last *systems*)) :force *systems*)))
  (when warnings
    (format t "~&;; FAIL: ~d compiler warning~:p:~%~{;;   ~a~%~}"
            (length warnings) (reverse warnings))
    (uiop:quit 2)))

(uiop:quit (if (uiop:symbol-call "{{package}}.TESTS" "RUN-TESTS") 0 1))
