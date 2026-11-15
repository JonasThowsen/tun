;;;; tests/timing-tests.lisp -- speed and time in tests (spec/tooling.md,
;;;; "Speed and time in tests"): only tests/timing.lisp reads a clock, a speed
;;;; is processor time, and a failure says what was measured, the limit and
;;;; the machine's load.

(in-package #:tun.tests)

(def-suite timing :in core)
(in-suite timing)

;;; ------------------------------------------------------------------
;;; The scan of the test sources

(defparameter +clock-readers+
  '("GET-INTERNAL-REAL-TIME" "GET-INTERNAL-RUN-TIME" "CLOCK-GETTIME" "GET-TIME-OF-DAY"
    "UNIX-GETTIMEOFDAY")
  "The functions that read a clock: only tests/timing.lisp calls them.")

(defparameter +time-comparing-operators+
  '("<" "<=" ">" ">=" "=" "/=" "IS" "IS-TRUE" "IS-FALSE")
  "A form headed by one of these compares or asserts what is inside it.")

(defun token-end (text start)
  "The index after the token that starts at START."
  (or (position-if (lambda (c) (or (member c '(#\( #\) #\" #\; #\' #\` #\,))
                                   (member c '(#\Space #\Tab #\Newline #\Return #\Page))))
                   text :start start)
      (length text)))

(defun token-name (token)
  "TOKEN's symbol name, upper case, without its package."
  (string-upcase (subseq token (1+ (or (position #\: token :from-end t) -1)))))

(defun clock-violations (text)
  "Where TEXT, Lisp source, reads a clock, or compares or asserts a
stopwatch's seconds: a list of (LINE . WHAT).  Strings, comments and
character literals are not code; each open form's head is kept, so a call
knows the forms it is inside."
  (let ((violations '()) (heads '()) (line 1) (i 0) (length (length text)))
    (flet ((skip-to (end)
             (incf line (count #\Newline text :start i :end end))
             (setf i end)))
      (loop while (< i length)
            do (let ((c (char text i))
                     (next (and (< (1+ i) length) (char text (1+ i)))))
                 (cond ((char= c #\Newline) (incf line) (incf i))
                       ((member c '(#\Space #\Tab #\Return #\Page #\' #\` #\, #\@)) (incf i))
                       ((char= c #\;) (skip-to (or (position #\Newline text :start i) length)))
                       ((member c '(#\" #\|)) (skip-to (tun.test-support::delimited-end text i)))
                       ((and (char= c #\#) (eql next #\|))
                        (skip-to (tun.test-support::block-comment-end text i)))
                       ((and (char= c #\#) (eql next #\\)) (skip-to (token-end text (+ i 3))))
                       ((and (char= c #\#) (eql next #\')) (incf i 2))
                       ((char= c #\() (push :head heads) (incf i))
                       ((char= c #\)) (pop heads) (incf i))
                       (t (let* ((end (max (1+ i) (token-end text i)))
                                 (name (token-name (subseq text i end))))
                            (when (eq (first heads) :head)
                              (setf (first heads) name))
                            (cond ((member name +clock-readers+ :test #'string=)
                                   (push (cons line (format nil "reads the clock with ~(~a~)" name))
                                         violations))
                                  ((and (string= name "STOPWATCH-SECONDS")
                                        (some (lambda (head)
                                                (and (stringp head)
                                                     (member head +time-comparing-operators+
                                                             :test #'string=)))
                                              (rest heads)))
                                   (push (cons line "compares a stopwatch's seconds")
                                         violations)))
                            (setf i end)))))))
    (nreverse violations)))

(defun test-source-files ()
  "Every Lisp source of Tun's test systems, but the helper that reads the clock."
  (let ((helper (asdf:system-relative-pathname "tun" "tests/timing.lisp")))
    (labels ((sources (component)
               (typecase component
                 (asdf:cl-source-file (list (asdf:component-pathname component)))
                 (asdf:parent-component (mapcan #'sources (asdf:component-children component)))
                 (t '()))))
      (remove helper
              (remove-duplicates
               (mapcan (lambda (name) (sources (asdf:find-system name)))
                       '("tun/tests" "tun-test-support" "test-client/tests"))
               :test #'equal)
              :test #'equal))))

(test only-the-timing-helper-reads-the-clock
  (let ((files (test-source-files)))
    (is (< 50 (length files)) "the test sources are found: ~d" (length files))
    (is (member "fuzzing" files :key #'pathname-name :test #'string=)
        "Tun's test-support is among them")
    (is (member "web-tests" files :key #'pathname-name :test #'string=)
        "and the test client's tests")
    (let ((violations (loop for file in files
                            append (loop for (line . what)
                                           in (clock-violations (uiop:read-file-string file))
                                         collect (format nil "~a:~d ~a"
                                                         (enough-namestring
                                                          file (asdf:system-source-directory "tun"))
                                                         line what)))))
      (is (null violations)
          "a test reads the clock only through tests/timing.lisp (spec/tooling.md, ~
           \"Speed and time in tests\"):~%~{  ~a~%~}" violations))))

(test the-scan-names-each-clock-read-and-each-stopwatch-compared
  (let ((planted (format nil "(defun a () (get-internal-real-time))~%~
                              (defun b () (sb-unix:clock-gettime 1))~%~
                              (defun c () (get-internal-run-time))~%~
                              (defun d () (sb-ext:get-time-of-day))~%~
                              (defun e () (sb-unix:unix-gettimeofday))~%~
                              (defun f (w) (is (< (stopwatch-seconds w) 2)))~%~
                              (defun g (w) (when (>= (+ 1 (stopwatch-seconds w)) 2) t))~%~
                              ;; get-internal-real-time in a comment~%~
                              (defun h (w) (format nil \"get-internal-real-time ~~a\" ~
                                                   (stopwatch-seconds w)))~%~
                              (defun i () #\\( (list 1))")))
    (is (equal '((1 . "reads the clock with get-internal-real-time")
                 (2 . "reads the clock with clock-gettime")
                 (3 . "reads the clock with get-internal-run-time")
                 (4 . "reads the clock with get-time-of-day")
                 (5 . "reads the clock with unix-gettimeofday")
                 (6 . "compares a stopwatch's seconds")
                 (7 . "compares a stopwatch's seconds"))
               (clock-violations planted))
        "~s" (clock-violations planted))))

;;; ------------------------------------------------------------------
;;; Processor time

(test a-speed-is-processor-time-not-waiting
  (let ((sleeping (measure-speed (lambda () (sleep 0.2)) :runs 1 :why "a sleep")))
    (is (< (tun.test-support::measurement-processor-ms sleeping) 20)
        "a body that sleeps costs no processor time: ~a" sleeping)
    (is (>= (tun.test-support::measurement-wall-ms sleeping) 200)
        "though it takes its wall time: ~,1f ms" (tun.test-support::measurement-wall-ms sleeping)))
  (let ((computing (measure-speed (lambda ()
                                    (let ((watch (start-stopwatch)) (x 0))
                                      (declare (type fixnum x))
                                      (loop until (stopwatch-past-p watch 0.1)
                                            do (setf x (logand (+ x 3) #xffff)))
                                      x))
                                  :runs 1 :why "a computation")))
    (is (< 5 (tun.test-support::measurement-processor-ms computing)
           (+ 5 (tun.test-support::measurement-wall-ms computing)))
        "a body that computes costs processor time, no more than its wall time: ~a ~,1f ms"
        computing (tun.test-support::measurement-wall-ms computing))))

(test a-speed-on-postgres-counts-the-server-s-work
  (when (postgres-available-p)
    (with-test-app (:db (scratch-postgres "timing_server"))
      (let ((measured (measure-speed (lambda ()
                                       (with-application (*app*)
                                         (with-transaction (:read)
                                           (raw-sql "SELECT count(*) FROM (SELECT md5(g::text)
                                                     FROM generate_series(1, 200000) g ORDER BY 1) s"))))
                                     :runs 3 :why "a sort on the server")))
        (is (> (tun.test-support::measurement-server-ms measured)
               (* 1/2 (tun.test-support::measurement-processor-ms measured)))
            "the server's processes did most of the work, and it is counted: ~a, of it Postgres ~,1f ms"
            measured (tun.test-support::measurement-server-ms measured))))))

;;; ------------------------------------------------------------------
;;; What a failure says

(test a-failure-names-the-time-the-limit-and-the-load
  (let ((text (tun.test-support::measurement-text
               (tun.test-support::limit-measurement
                (tun.test-support::make-measurement "a search" 9 123.4 20.5 400.0 nil) 90 nil 1))))
    (dolist (part '("a search: 123.4 ms of processor time (median of 9, Postgres 20.5 ms)"
                    "over its limit of 90 ms" "wall 400.0 ms" "load " " processors"))
      (is (search part text) "«~a» in «~a»" part text)))
  (let* ((before (tun.test-support::make-measurement "10 records" 9 30.0 nil 31.0 nil))
         (text (tun.test-support::measurement-text
                (tun.test-support::limit-measurement
                 (tun.test-support::make-measurement "2000 records" 9 90.0 nil 95.0 nil) 50 before 1))))
    (is (search "over its limit of 80.0 ms (1 × 30.0 ms + 50 ms)" text) "~a" text))
  (let ((text (tun.test-support::measurement-text
               (tun.test-support::limit-measurement
                (tun.test-support::make-measurement "remote" 9 1.0 nil 70.0 t) 50 nil 1))))
    (is (search "70.0 ms of wall time" text) "~a" text)
    (is (search "could not be read, so wall time decides" text) "~a" text))
  (let ((text (tun.test-support::seconds-text "stopped at the deadline" 1.62d0 1 1.5)))
    (is (search "stopped at the deadline: 1.62 s, not under 1.5 s (wall time; load " text)
        "~a" text)
    (is (search " processors)" text) "~a" text)))
