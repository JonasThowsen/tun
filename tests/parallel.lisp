;;;; tests/parallel.lisp -- a client's suite in parallel (spec/testing.md 1,
;;;; «In parallel»): workers forked from the process that compiled it, each
;;;; running units of the suite (a test, a package's RUN-TESTS, or a share of
;;;; a split test), the longest first, each unit's output in a file of its
;;;; own and a failed one's printed at the end.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Split tests: the shares of a test that runs over a list

(defvar *test-share* nil
  "The share of a split test the current unit runs, as (INDEX . COUNT) from 0,
or NIL for the whole test.")

(defvar *split-tests* (make-hash-table :test 'eq)
  "The tests that may run as shares, by name: DEFINE-GENERATED-TESTS notes its
fuzzing and scenario tests here.")

(defparameter +most-shares+ 4
  "Into how many units a split test runs at most.")

(defun note-split-test (name)
  "Note the test NAME as one that may run as shares, each over SHARE-OF its
list. Returns NAME."
  (setf (gethash name *split-tests*) t)
  name)

(defun split-test-p (name)
  "True when the test NAME may run as shares."
  (values (gethash name *split-tests*)))

(defun share-of (items)
  "ITEMS, or, in a share (INDEX . COUNT) of a split test, those of them at
the positions INDEX, INDEX + COUNT, ... of the list: the shares together
take each item once."
  (if *test-share*
      (destructuring-bind (index . count) *test-share*
        (loop for item in items
              for position from 0
              when (= (mod position count) index)
              collect item))
      items))

(defun share-text ()
  "How a report names the current share, such as \"share 2 of 4\", or NIL."
  (and *test-share*
       (format nil "share ~d of ~d" (1+ (car *test-share*)) (cdr *test-share*))))

;;; ------------------------------------------------------------------
;;; How many workers

(defun available-memory-gb ()
  "The memory available for new work, MemAvailable of /proc/meminfo, in GB."
  (let ((line (find-if (lambda (line) (eql 0 (search "MemAvailable:" line)))
                       (ignore-errors (uiop:read-file-lines "/proc/meminfo")))))
    (if line
        (/ (or (parse-integer line :start (length "MemAvailable:") :junk-allowed t) 0)
           (* 1024.0 1024.0))
        0.0)))

(defun default-jobs (processors available-gb
                     &key (reserve-gb 4) (worker-gb 1.5) (most processors))
  "How many workers PROCESSORS and AVAILABLE-GB of memory allow: at most
MOST and PROCESSORS, each taking WORKER-GB with RESERVE-GB left over, at
least one."
  (max 1 (min most processors (floor (- available-gb reserve-gb) worker-gb))))

(defun jobs-from-environment (name)
  "The whole number the environment variable NAME holds, or NIL when it is
unset or empty; an error when it holds anything else."
  (let ((text (uiop:getenv name)))
    (unless (zerop (length text))
      (let ((number (parse-integer text :junk-allowed t)))
        (unless (and number (plusp number) (string= text (princ-to-string number)))
          (error "~a is ~s; it takes a whole number from 1" name text))
        number))))

(defun test-jobs ()
  "The workers a suite runs in: TUN_TEST_JOBS, else what the processors and
the available memory allow (spec/testing.md 1)."
  (or (jobs-from-environment "TUN_TEST_JOBS")
      (default-jobs (processor-count) (available-memory-gb))))

;;; ------------------------------------------------------------------
;;; Units

(defstruct (test-unit (:conc-name unit-)
                      (:constructor make-unit (suite label kind target &optional share)))
  "One piece of work of a run: a TEST of SUITE, with SHARE when it is a share
of a split test, or the RUN-TESTS of a package run WHOLE."
  (suite "" :type string)
  (label "" :type string)
  (kind :test :type (member :test :whole))
  target
  share)

(defun unit-name (unit)
  "The unit's name in the times and its log's: SUITE/LABEL, lower case, and
-share-I-of-N for a share."
  (string-downcase
   (format nil "~a/~a~@[-share-~d-of-~d~]" (unit-suite unit) (unit-label unit)
           (and (unit-share unit) (1+ (car (unit-share unit))))
           (and (unit-share unit) (cdr (unit-share unit))))))

(defun suite-children (suite)
  "The tests of the FiveAM suite named SUITE, those of its child suites
among them, in the order they were defined."
  ;; A suite's bundle holds each child suite itself, and a test by its name.
  (let ((bundle (fiveam::tests (fiveam:get-test suite))))
    (loop for name in (remove-duplicates (reverse (fiveam::%test-names bundle)) :from-end t)
          for test = (gethash name (fiveam::%tests bundle))
          if (typep test 'fiveam::test-suite)
          append (suite-children name)
          else
          collect name)))

(defun suite-p (name)
  "True when NAME names a FiveAM suite."
  (and (symbolp name) (typep (fiveam:get-test name nil) 'fiveam::test-suite)))

(defun package-suite (package-name)
  "The suite of the tests' package PACKAGE-NAME: the FiveAM suite named as
the package without TUN. and .TESTS, NOTES.TESTS's NOTES, or NIL when no
suite has that name there."
  (let* ((name (string-upcase package-name))
         (start (if (eql 0 (search "TUN." name)) (length "TUN.") 0))
         (end (if (and (> (length name) (length ".TESTS"))
                       (string= ".TESTS" name :start2 (- (length name) (length ".TESTS"))))
                  (- (length name) (length ".TESTS"))
                  (length name)))
         (symbol (and (< start end) (find-package name)
                      (find-symbol (subseq name start end) name))))
    (and (suite-p symbol) symbol)))

(defun suite-units (suite label jobs)
  "The units of the suite SUITE, named LABEL: one a test, and a split test's
shares, as many as JOBS and +MOST-SHARES+ allow."
  (loop for test in (suite-children suite)
        for shares = (if (split-test-p test) (min jobs +most-shares+) 1)
        append (if (= shares 1)
                   (list (make-unit label (symbol-name test) :test test))
                   (loop for index below shares
                         collect (make-unit label (symbol-name test) :test test
                                            (cons index shares))))))

(defun entry-units (entry jobs)
  "The units of ENTRY, a suite's name or a tests' package's name."
  (cond ((suite-p entry)
         (suite-units entry (symbol-name entry) jobs))
        ((symbolp entry)
         (error "run-tests-in-parallel: ~s is not a FiveAM suite" entry))
        ((package-suite entry)
         (suite-units (package-suite entry) (string-upcase entry) jobs))
        ((and (find-package (string-upcase entry))
              (find-symbol "RUN-TESTS" (string-upcase entry)))
         (list (make-unit (string-upcase entry) "RUN-TESTS" :whole (string-upcase entry))))
        (t (error "run-tests-in-parallel: ~a is neither a suite nor a package with RUN-TESTS"
                  entry))))

;;; ------------------------------------------------------------------
;;; The times of the last run

(defun read-times (file)
  "The seconds of each unit of the last run, by name, from FILE."
  (let ((times (make-hash-table :test 'equal)))
    (dolist (line (and (probe-file file) (uiop:read-file-lines file)) times)
      (let ((space (position #\Space line :from-end t)))
        (when space
          (let ((seconds (ignore-errors (let ((*read-eval* nil))
                                          (read-from-string line t nil :start (1+ space))))))
            (when (realp seconds)
              (setf (gethash (subseq line 0 space) times) seconds))))))))

(defun write-times (file times)
  "Write TIMES, seconds by name, to FILE, the longest first."
  (let ((rows '()))
    (maphash (lambda (name seconds) (push (cons name seconds) rows)) times)
    (ensure-directories-exist file)
    (with-open-file (out file :direction :output :if-exists :supersede)
      (loop for (name . seconds) in (sort rows #'> :key #'cdr)
            do (format out "~a ~,2f~%" name seconds)))))

(defun longest-first (units times)
  "UNITS in the order they are taken: those with no time first, in their
order, then the longest first by TIMES."
  (stable-sort (copy-list units) #'>
               :key (lambda (unit)
                      (multiple-value-bind (seconds known) (gethash (unit-name unit) times)
                        (if known seconds most-positive-fixnum)))))

;;; ------------------------------------------------------------------
;;; Running a unit

(defun run-unit (unit)
  "Run UNIT here and explain its results; true when every check passed."
  (handler-case
      (ecase (unit-kind unit)
        (:test (let ((*test-share* (unit-share unit)))
                 (fiveam:explain! (fiveam:run (unit-target unit)))))
        (:whole (and (uiop:symbol-call (unit-target unit) "RUN-TESTS") t)))
    (error (condition)
      (format t "~&~a did not run to its end: ~a~%" (unit-name unit) condition)
      nil)))

(defun log-file (directory unit &optional (type "log"))
  (merge-pathnames (make-pathname :name (substitute #\_ #\/ (unit-name unit)) :type type)
                   directory))

(defun redirect-output (file)
  "Send this process's standard output and error to FILE from here on, its
threads' and its programs' too; values a stream to FILE for this thread's
own output."
  (finish-output sb-sys:*stdout*)
  (finish-output sb-sys:*stderr*)
  (let ((fd (sb-posix:open (namestring file)
                           (logior sb-posix:o-wronly sb-posix:o-creat sb-posix:o-trunc) #o644)))
    (sb-posix:dup2 fd 1)
    (sb-posix:dup2 fd 2)
    (sb-posix:close fd))
  (sb-sys:make-fd-stream 1 :output t :buffering :line :external-format :utf-8))

(defun claim-unit (index directory)
  "Claim the unit at INDEX for this worker: true when no worker had it.
Creating its claim's file is the one step that only one process wins."
  (handler-case
      (progn (sb-posix:close (sb-posix:open (namestring (merge-pathnames (format nil "~d.claim" index)
                                                                         directory))
                                            (logior sb-posix:o-wronly sb-posix:o-creat
                                                    sb-posix:o-excl)
                                            #o644))
             t)
    (sb-posix:syscall-error () nil)))

(defun run-units (units directory)
  "In a worker: take the units of UNITS no worker has claimed, in their
order, until none is left; run each, its output to its log in DIRECTORY,
and write its result beside it, the result last, so a unit whose worker
ends while it runs has none."
  (loop for unit in units
        for index from 0
        when (claim-unit index directory)
        do (let* ((out (redirect-output (log-file directory unit)))
                  (watch (start-stopwatch))
                  (passed (let ((*standard-output* out) (*error-output* out)
                                (*trace-output* out) (fiveam:*test-dribble* out))
                            (prog1 (run-unit unit) (finish-output out))))
                  (seconds (stopwatch-seconds (stop-stopwatch watch))))
             (with-open-file (result (log-file directory unit "result")
                                     :direction :output :if-exists :supersede)
               (format result "~:[failed~;passed~] ~,3f~%" passed seconds)))))

(defun unit-result (unit directory)
  "What UNIT's worker wrote: (values passed seconds), or NIL and NIL when it
wrote nothing."
  (let ((file (log-file directory unit "result")))
    (if (probe-file file)
        (let ((words (uiop:split-string (string-trim '(#\Newline #\Space)
                                                     (uiop:read-file-string file))
                                        :separator " ")))
          (values (string= (first words) "passed")
                  (or (ignore-errors (let ((*read-eval* nil))
                                       (read-from-string (second words))))
                      0)))
        (values nil nil))))

(defun fork-worker (units directory)
  "Fork a worker that runs the units of UNITS no other has claimed, and
ends; its process id."
  (finish-output *standard-output*)
  (finish-output *error-output*)
  (finish-output sb-sys:*stdout*)
  (finish-output sb-sys:*stderr*)
  (let ((pid (sb-posix:fork)))
    (when (zerop pid)
      ;; The worker ends here, without unwinding into the parent's code,
      ;; whatever its units did.
      (unwind-protect (ignore-errors (run-units units directory))
        (sb-ext:exit :code 0 :abort t)))
    pid))

;;; ------------------------------------------------------------------
;;; The run

(defun run-in-this-process (entries)
  "Run each of ENTRIES here, one after another: a suite with RUN!, a
package's RUN-TESTS; true when every one passed."
  (let ((results (loop for entry in entries
                       collect (if (suite-p entry)
                                   (fiveam:run! entry)
                                   (uiop:symbol-call (string-upcase entry) "RUN-TESTS")))))
    (every #'identity results)))

(defun print-failure (unit directory reason)
  "Print UNIT's output, in full, and why it failed."
  (let ((log (log-file directory unit)))
    (format t "~&~%== FAIL ~a~@[: ~a~]~%" (unit-name unit) reason)
    (when (probe-file log)
      (write-string (uiop:read-file-string log)))
    (format t "~&== end of ~a (~a)~%" (unit-name unit) (namestring log))))

(defun run-tests-in-parallel (entries &key (jobs (test-jobs)) (directory #p".build/test/"))
  "Run ENTRIES, FiveAM suite names or the names of tests' packages, the
client's and its modules' (spec/testing.md 1, «In parallel»): with one job
here, one after another, as before; with more, in JOBS workers forked from
this process, each unit's output in DIRECTORY's units/, the times of the
run in DIRECTORY's times. Prints each failed unit's output and a line for
each suite and for the run; true when every unit passed."
  (if (or (<= jobs 1) (rest (sb-thread:list-all-threads)))
      (progn
        (when (> jobs 1)
          (format t "~&;; run-tests-in-parallel: this process runs threads (~{~a~^, ~}), ~
                     so it forks no workers and runs the tests here~%"
                  (mapcar #'sb-thread:thread-name (sb-thread:list-all-threads))))
        (run-in-this-process entries))
      (run-in-workers entries jobs (merge-pathnames directory (uiop:getcwd)))))

(defun print-summary (units failed seconds jobs)
  "A line for each suite of UNITS, its tests and those that FAILED, and one
for the run."
  (dolist (suite (remove-duplicates (mapcar #'unit-suite units) :test #'string= :from-end t))
    (let* ((own (remove suite units :key #'unit-suite :test-not #'string=))
           (tests (remove-duplicates own :key #'unit-label :test #'string=))
           (bad (remove-duplicates (remove-if-not (lambda (unit) (assoc unit failed)) own)
                                   :key #'unit-label :test #'string=)))
      (format t "~&~a: ~d test~:p, ~d failed~%" suite (length tests) (length bad))))
  (format t "~&~d unit~:p in ~,1f s on ~d workers~:[, ~d failed~;~*~]~%"
          (length units) seconds jobs (null failed) (length failed)))

(defun unclaimed-p (units directory)
  "True while a unit of UNITS has no claim in DIRECTORY."
  (loop for index below (length units)
        thereis (not (probe-file (merge-pathnames (format nil "~d.claim" index) directory)))))

(defun unit-failures (units directory)
  "The failures of UNITS by what their workers left in DIRECTORY, as
(UNIT . REASON) pairs: REASON NIL when a unit's checks failed, and a text
when its worker ended while it ran or no worker ran it."
  (loop for unit in units
        for index from 0
        for (passed seconds) = (multiple-value-list (unit-result unit directory))
        if (null seconds)
        collect (cons unit (if (probe-file (merge-pathnames (format nil "~d.claim" index)
                                                            directory))
                               "its worker ended while it ran"
                               "no worker ran it"))
        else if (not passed)
        collect (cons unit nil)))

(defun run-in-workers (entries jobs directory)
  "Run ENTRIES' units in JOBS workers forked from this process, each taking
the next unit no other has claimed, their output in DIRECTORY's units/; a
worker that ends while units are left is replaced. True when every unit
passed."
  (let* ((units-directory (merge-pathnames "units/" directory))
         (times-file (merge-pathnames "times" directory))
         (times (read-times times-file))
         (in-order (loop for entry in entries append (entry-units entry jobs)))
         (units (longest-first in-order times))
         (watch (start-stopwatch))
         (running 0)
         (forks 0))
    (uiop:delete-directory-tree units-directory
                                :validate (lambda (path) (search "/units/" (namestring path)))
                                :if-does-not-exist :ignore)
    (ensure-directories-exist units-directory)
    (format t "~&;; ~d unit~:p of ~{~a~^, ~} in ~d workers~%" (length units)
            (remove-duplicates (mapcar #'unit-suite units) :test #'string= :from-end t) jobs)
    (finish-output)
    (loop repeat (min jobs (length units))
          do (fork-worker units units-directory)
          (incf running) (incf forks))
    ;; A worker that ends early, as one whose test ends its process does,
    ;; is replaced while units are left, at most once a unit.
    (loop while (plusp running)
          do (sb-posix:waitpid -1 0)
          (decf running)
          (when (and (unclaimed-p units units-directory) (< forks (+ jobs (length units))))
            (fork-worker units units-directory)
            (incf running) (incf forks)))
    (let ((failed (unit-failures units units-directory)))
      ;; A line a unit, in the order of the suites, as FiveAM names each
      ;; test it runs; then the failed ones' output.
      (dolist (unit (sort (copy-list units) #'< :key (lambda (unit) (position unit in-order))))
        (let ((seconds (nth-value 1 (unit-result unit units-directory))))
          (when seconds
            (setf (gethash (unit-name unit) times) seconds))
          (format t "~&  ~:[ok  ~;FAIL~]  ~a/~a~@[ (share ~a)~]  ~,1fs~%"
                  (assoc unit failed) (unit-suite unit) (unit-label unit)
                  (and (unit-share unit)
                       (format nil "~d of ~d" (1+ (car (unit-share unit))) (cdr (unit-share unit))))
                  (or seconds 0))))
      (loop for (unit . reason) in failed
            do (print-failure unit units-directory reason))
      (write-times times-file times)
      (print-summary units failed (stopwatch-seconds watch) jobs)
      (finish-output)
      (null failed))))
