;;;; tests/parallel-tests.lisp -- a client's suite in parallel (spec/testing.md
;;;; 1, «In parallel»): the verdicts of tests run in forked workers are those
;;;; of the same tests run one after another, a worker that ends fails its
;;;; unit, a split test's shares take each item once, and a package without a
;;;; suite of its name runs its RUN-TESTS whole.

(in-package #:tun.tests)

(def-suite parallel :in core)

;;; ------------------------------------------------------------------
;;; Samples to run: suites and packages of their own, outside CORE, which
;;; bin/test runs only through the tests below.

(defvar *sample-directory* nil
  "Where the samples write what they did, for the tests to read.")

(defparameter +split-items+ '(a b c d e f g)
  "What the sample split test runs over.")

(defun note-sample (name text)
  "Write TEXT to the sample file NAME."
  (with-open-file (out (merge-pathnames name *sample-directory*) :direction :output
                       :if-exists :supersede)
    (write-string text out)))

(def-suite parallel-sample :description "A sample suite for run-tests-in-parallel.")
(in-suite parallel-sample)

(test sample-passes
  (is (= 2 (+ 1 1))))

(test sample-fails
  (is (= 3 (+ 1 1)) "one and one make three"))

(test sample-errs
  (error "a sample error"))

(test sample-split
  (let ((items (share-of +split-items+)))
    (note-sample (format nil "split-~a" (if *test-share* (car *test-share*) "whole"))
                 (format nil "~{~a~^ ~}" items))
    (is (consp items))))

(note-split-test 'sample-split)

(def-suite parallel-crash :description "A sample suite whose test ends its process.")
(in-suite parallel-crash)

(test sample-ends-its-process
  (sb-ext:exit :code 3 :abort t))

(test sample-after-the-end
  (is (= 4 (* 2 2))))

(defpackage #:parallel-whole.tests
  (:use #:cl)
  (:export #:run-tests))

(defun parallel-whole.tests:run-tests ()
  "A package's RUN-TESTS, with no suite of the package's name."
  (note-sample "whole" "ran")
  t)

(defpackage #:parallel-not-a-suite.tests
  (:use #:cl)
  (:export #:run-tests #:parallel-not-a-suite))

(defun parallel-not-a-suite.tests:parallel-not-a-suite ()
  "A symbol of the package's name that is no suite.")

(defun parallel-not-a-suite.tests:run-tests ()
  "A package's RUN-TESTS beside a symbol of its name that is no suite."
  (note-sample "not-a-suite" "ran")
  t)

;;; ------------------------------------------------------------------
;;; Running them

(in-suite parallel)

(defun fork-possible-p ()
  "True when this process runs no thread but its main one, so the runner
forks workers rather than running the tests here."
  (null (rest (sb-thread:list-all-threads))))

(defun run-sample (entries jobs)
  "Run ENTRIES in JOBS workers in a fresh directory; values whether they
passed, what the run printed and the directory."
  (let* ((directory (uiop:ensure-directory-pathname
                     (merge-pathnames (format nil ".build/test-parallel/~a/" (new-id "run"))
                                      (asdf:system-source-directory "tun"))))
         (*sample-directory* directory))
    (ensure-directories-exist directory)
    (let* (passed
           (output (with-output-to-string (*standard-output*)
                     (let ((fiveam:*test-dribble* *standard-output*))
                       (setf passed (run-tests-in-parallel entries :jobs jobs
                                                           :directory directory))))))
      (values passed output directory))))

(defun sample-text (directory name)
  (let ((file (merge-pathnames name directory)))
    (and (probe-file file) (uiop:read-file-string file))))

(test the-workers-give-the-verdicts-of-one-after-another
  (unless (fork-possible-p)
    (skip "this process runs threads, so the runner would not fork"))
  (when (fork-possible-p)
    (multiple-value-bind (passed output directory) (run-sample '(parallel-sample) 3)
      (is (null passed) "a failing and an erring test fail the run")
      (dolist (text '("FAIL parallel-sample/sample-fails" "one and one make three"
                      "FAIL parallel-sample/sample-errs" "a sample error"
                      "PARALLEL-SAMPLE: 4 tests, 2 failed" "on 3 workers"))
        (is (search text output) "the run says ~s:~%~a" text output))
      (is (not (search "FAIL parallel-sample/sample-passes" output)))
      (is (search "ok    PARALLEL-SAMPLE/SAMPLE-PASSES" output) "a line names each test: ~a" output)
      (is (search "PARALLEL-SAMPLE/SAMPLE-SPLIT (share 3 of 3)" output))
      (is (not (search "FAIL parallel-sample/sample-split" output)))
      ;; Three shares of the split test, together over each item once.
      (let ((shares (loop for index below 3 collect (sample-text directory (format nil "split-~d" index)))))
        (is (every #'stringp shares) "every share ran: ~s" shares)
        (is (equal (sort (mapcar #'string-downcase
                                 (loop for share in shares
                                       append (uiop:split-string share :separator " ")))
                         #'string<)
                   (sort (mapcar (lambda (item) (string-downcase (symbol-name item))) +split-items+)
                         #'string<))))
      (let ((times (uiop:read-file-string (merge-pathnames "times" directory))))
        (dolist (name '("parallel-sample/sample-passes" "parallel-sample/sample-fails"
                        "parallel-sample/sample-split-share-1-of-3"))
          (is (search name times) "the times name ~a: ~a" name times)))
      (is (probe-file (merge-pathnames "units/parallel-sample_sample-fails.log" directory))))))

(test one-job-runs-the-suites-here-as-before
  (multiple-value-bind (passed output directory) (run-sample '(parallel-sample) 1)
    (is (null passed))
    (is (search "one and one make three" output) "FiveAM explains the failure: ~a" output)
    (is (not (search "units in" output)) "nothing forked: ~a" output)
    (is (string= "a b c d e f g" (string-downcase (or (sample-text directory "split-whole") "")))
        "the split test runs whole")))

(test a-worker-that-ends-fails-its-unit
  (unless (fork-possible-p)
    (skip "this process runs threads, so the runner would not fork"))
  (when (fork-possible-p)
    (multiple-value-bind (passed output) (run-sample '(parallel-crash) 2)
      (is (null passed))
      (is (search "FAIL parallel-crash/sample-ends-its-process: its worker ended while it ran"
                  output)
          "the run names the unit: ~a" output)
      (is (not (search "FAIL parallel-crash/sample-after-the-end" output)))
      (is (search "PARALLEL-CRASH: 2 tests, 1 failed" output) "~a" output))))

(test a-package-without-a-suite-of-its-name-runs-whole
  (dolist (jobs (if (fork-possible-p) '(1 2) '(1)))
    (multiple-value-bind (passed output directory)
        (run-sample '("PARALLEL-WHOLE.TESTS" "parallel-not-a-suite.tests") jobs)
      (is (eq t passed) "~d job~:p: ~a" jobs output)
      (is (equal "ran" (sample-text directory "whole")))
      (is (equal "ran" (sample-text directory "not-a-suite")))
      (when (> jobs 1)
        (is (search "PARALLEL-WHOLE.TESTS: 1 test, 0 failed" output) "~a" output)))))

(test a-package-s-suite-is-named-as-the-package
  (is (null (tun.test-support::package-suite "PARALLEL-NOT-A-SUITE.TESTS"))
      "a function of the package's name is no suite")
  (is (null (tun.test-support::package-suite "TUN.TESTS")) "nothing is left of the name")
  (is (null (tun.test-support::package-suite "NO-SUCH-PACKAGE.TESTS"))))

(test units-go-longest-first
  (let ((units (list (tun.test-support::make-unit "S" "A" :test 'a)
                     (tun.test-support::make-unit "S" "B" :test 'b)
                     (tun.test-support::make-unit "S" "C" :test 'c)
                     (tun.test-support::make-unit "S" "D" :test 'd)))
        (times (make-hash-table :test 'equal)))
    (setf (gethash "s/a" times) 1.0 (gethash "s/b" times) 9.0 (gethash "s/c" times) 0.1)
    (is (equal '("D" "B" "A" "C")
               (mapcar #'tun.test-support::unit-label
                       (tun.test-support::longest-first units times)))
        "no time first, then the longest")))

(test the-workers-are-as-many-as-processors-and-memory-allow
  (is (= 12 (default-jobs 12 31)))
  (is (= 4 (default-jobs 12 10)) "10 GB less 4 over 1.5")
  (is (= 1 (default-jobs 12 3)) "at least one")
  (is (= 2 (default-jobs 2 31)))
  (let ((before (uiop:getenv "TUN_TEST_JOBS")))
    (unwind-protect
         (progn (sb-posix:setenv "TUN_TEST_JOBS" "3" 1)
                (is (= 3 (test-jobs)))
                (sb-posix:setenv "TUN_TEST_JOBS" "many" 1)
                (signals error (test-jobs)))
      (if before (sb-posix:setenv "TUN_TEST_JOBS" before 1) (sb-posix:unsetenv "TUN_TEST_JOBS")))))

(test a-share-takes-every-nth-item
  (is (equal '(a b c d e f g) (share-of +split-items+)))
  (is (equal '(b e) (let ((*test-share* '(1 . 3))) (share-of '(a b c d e f)))))
  (is (equal "share 2 of 3" (let ((*test-share* '(1 . 3))) (share-text))))
  (is (null (share-text))))

(test the-fuzzer-s-summary-names-its-share
  (let ((report (tun.test-support::make-fuzz-report 1 8)))
    (is (search "(share 2 of 4)" (let ((*test-share* '(1 . 4))) (fuzz-summary report "x"))))
    (is (not (search "share" (fuzz-summary report "x"))))))
