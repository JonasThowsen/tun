;;;; scripts/build.lisp -- compile one part of the tree with warnings counted,
;;;; without running anything.  Incremental unless --force.
;;;; Usage: sbcl --load scripts/build.lisp core|CLIENT [--force]
;;;; core is the kernel with its tests; CLIENT is a client system, such as
;;;; test-client, with CLIENT/tests when it has one.  (bin/build compiles
;;;; each part in a process of its own, like bin/test: ASDF reloads core when
;;;; a client is loaded in a second operate session of the same image, which
;;;; would report spurious redefinitions, and two clients cannot share an
;;;; image.)

(load (merge-pathnames "setup.lisp" *load-truename*))
(in-package #:tun-build)

(load-quietly "alexandria" "bordeaux-threads" "cl-base64" "cl-ppcre" "closer-mop" "com.inuoe.jzon"
              "drakma" "fiveam" "hunchentoot" "ironclad" "sqlite" "cl-postgres" "swank" "usocket")

(defun part-systems (part)
  "The systems bin/build compiles for PART: core, or a client system."
  (if (string= part "core")
      '("tun" "tun/tests")
      (let ((tests (format nil "~a/tests" part)))
        (list* "tun" part (and (asdf:find-system tests nil) (list tests))))))

(let* ((part (or (second sb-ext:*posix-argv*) "core"))
       (force (and (member "--force" sb-ext:*posix-argv* :test #'string=) t))
       (systems (part-systems part))
       (start (get-internal-real-time))
       (warnings (compile-strictly systems :force force))
       (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
  (format t "~&;; ~a: built in ~,2fs, ~d warning~:p~%~{;;   ~a~%~}" part seconds (length warnings) warnings)
  (exit-with (if warnings 2 0)))
