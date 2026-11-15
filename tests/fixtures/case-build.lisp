;;;; tests/fixtures/case-build.lisp -- build systems as bin/build does,
;;;; incrementally and counting every warning, for the test that a changed
;;;; set stops the build (spec/core.md 2.7): sbcl --load this DIRECTORY
;;;; SYSTEM.  It loads Tun as compiled, then builds SYSTEM, found in
;;;; DIRECTORY, with what it depends on, as COMPILE-STRICTLY does (one load,
;;;; so no system is loaded twice), prints each warning on a line of its own
;;;; starting "warning: ", and exits 2 when there was one, else 0.

(load (merge-pathnames "../../scripts/setup.lisp" *load-truename*))
(in-package #:tun-build)

(load-quietly "tun")

(destructuring-bind (directory system) (rest sb-ext:*posix-argv*)
  (push (uiop:ensure-directory-pathname directory) asdf:*central-registry*)
  (let ((warnings (compile-strictly (list system))))
    (dolist (warning warnings)
      (format t "warning: ~a~%" (substitute #\Space #\Newline warning)))
    (exit-with (if warnings 2 0))))
