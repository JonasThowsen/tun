;;;; scripts/test.lisp -- compile strictly, then run one test-suite.
;;;; Usage: sbcl --script scripts/test.lisp core|CLIENT [SUITE]
;;;; core is the kernel and module suite, with no client loaded; CLIENT is a
;;;; client system, such as test-client, whose CLIENT/tests runs instead.
;;;; With SUITE, only that FiveAM suite of the core tests runs.
;;;; Any compiler warning or style warning in our code fails the run.

(load (merge-pathnames "setup.lisp" *load-truename*))
(in-package #:tun-build)

(defparameter *suite* (or (second sb-ext:*posix-argv*) "core"))

(load-quietly "alexandria" "bordeaux-threads" "cl-base64" "cl-ppcre" "closer-mop" "com.inuoe.jzon"
              "drakma" "fiveam" "hunchentoot" "ironclad" "sqlite" "cl-postgres" "swank" "usocket")

(defparameter *client*
  (if (string= *suite* "core") nil *suite*))

(defparameter *systems*
  (if *client*
      (list "tun" *client* (format nil "~a/tests" *client*))
      '("tun" "tun/tests")))

(let* ((start (get-internal-real-time))
       (warnings (compile-strictly *systems* :force t))
       (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
  (format t "~&;; compiled ~{~a~^, ~} in ~,2fs~%" *systems* seconds)
  (when warnings
    (format t "~&;; FAIL: ~d compiler warning~:p:~%~{;;   ~a~%~}" (length warnings) warnings)
    (exit-with 2)))

(defparameter *only* (third sb-ext:*posix-argv*))

(when *only*
  (let ((suite (find-symbol (string-upcase *only*) "TUN.TESTS")))
    (unless (and suite (fiveam:get-test suite))
      (format t "~&;; no core test suite named ~a~%" *only*)
      (exit-with 2))
    (exit-with (if (fiveam:run! suite) 0 1))))

(let* ((runner (if *client*
                   ;; A manifest suite (shop/minimal) has package SHOP-MINIMAL.TESTS.
                   (find-symbol "RUN-CLIENT-TESTS" (format nil "~:@(~a~).TESTS" (substitute #\- #\/ *client*)))
                   (find-symbol "RUN-CORE-TESTS" "TUN.TESTS")))
       (start (get-internal-real-time))
       (ok (funcall runner))
       (seconds (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
  (format t "~&;; ~a suite ~:[FAILED~;passed~] in ~,2fs~%" *suite* ok seconds)
  (exit-with (if ok 0 1)))
