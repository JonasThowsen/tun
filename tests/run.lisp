;;;; tests/run.lisp -- entry points used by scripts/test.lisp.  bin/test runs
;;;; each child suite of CORE in a process of its own, so every test of CORE
;;;; belongs to one of them.

(in-package #:tun.tests)

(defun run-core-tests (&optional (suite 'core))
  "Run SUITE, the whole core suite or one of its children; true when every
check passed."
  (let ((results (fiveam:run suite)))
    (fiveam:explain! results)
    (every (lambda (r) (typep r 'fiveam::test-passed)) results)))

(defun core-children ()
  "The names of the tests and suites placed directly in CORE, in the order
they were defined, each as (NAME . SUITE-P)."
  ;; A suite's bundle holds each child suite itself, and a test by its name.
  (let ((bundle (fiveam::tests (fiveam:get-test 'core))))
    (loop for name in (remove-duplicates (reverse (fiveam::%test-names bundle)) :from-end t)
          collect (cons name (typep (gethash name (fiveam::%tests bundle)) 'fiveam::test-suite)))))

(defun core-child-suites ()
  "The names of CORE's child suites, in lower case, as bin/test runs them."
  (loop for (name . suite-p) in (core-children)
        when suite-p
        collect (string-downcase name)))

(defun tests-outside-child-suites ()
  "The names of the tests placed directly in CORE, outside its child suites,
in lower case: bin/test would run them nowhere."
  (loop for (name . suite-p) in (core-children)
        unless suite-p
        collect (string-downcase name)))
