;;;; tests/run.lisp -- entry point used by scripts/test.lisp.

(in-package #:tun.tests)

(defun run-core-tests ()
  "Run the core suite; true when every check passed."
  (let ((results (fiveam:run 'core)))
    (fiveam:explain! results)
    (every (lambda (r) (typep r 'fiveam::test-passed)) results)))
