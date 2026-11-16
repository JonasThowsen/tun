;;;; tests/timing.lisp -- the one place a test reads a clock (spec/tooling.md,
;;;; "Speed and time in tests").  A speed is how much work something is,
;;;; measured in processor time, so another process's load does not decide
;;;; it: IS-FAST.  When something happens (a deadline, a timeout, an answer
;;;; that must not wait) is wall time: IS-WITHIN-SECONDS.  A wait that gives
;;;; up, or a report's seconds, takes a stopwatch.

(in-package #:tun.test-support)

;;; ------------------------------------------------------------------
;;; Clocks

(defun clock-nanoseconds (clock)
  (multiple-value-bind (seconds nanoseconds) (sb-unix:clock-gettime clock)
    (+ (* seconds 1000000000) nanoseconds)))

(defun wall-nanoseconds ()
  (clock-nanoseconds sb-unix:clock-monotonic))

(defun wall-ticks ()
  "The wall clock the kernel's deadlines and timeouts read, so a stopwatch
agrees with them to the tick."
  (get-internal-real-time))

(defun own-nanoseconds ()
  "The processor time of this process so far, every thread of it."
  (clock-nanoseconds sb-unix:clock-process-cputime-id))

(defun children-nanoseconds ()
  "The processor time of the programs this process ran and waited for, such
as Typst making a PDF, as the kernel counts them for ended children."
  (multiple-value-bind (ok user-us system-us) (sb-unix:unix-getrusage sb-unix:rusage_children)
    (if ok (* 1000 (+ user-us system-us)) 0)))

(defun process-nanoseconds ()
  "The processor time of this process so far, every thread of it, and of the
programs it ran and waited for."
  (+ (own-nanoseconds) (children-nanoseconds)))

(defun load-average ()
  "The machine's load average over the last minute, as /proc/loadavg says."
  (let ((text (ignore-errors (uiop:read-file-string "/proc/loadavg"))))
    (or (and text (first (uiop:split-string text :separator " "))) "unknown")))

(defvar *processor-count* nil)

(defun processor-count ()
  (or *processor-count*
      (setf *processor-count*
            (max 1 (count-if (lambda (line) (uiop:string-prefix-p "processor" line))
                             (or (ignore-errors (uiop:read-file-lines "/proc/cpuinfo")) '()))))))

(defun machine-text ()
  (format nil "load ~a on ~d processor~:p" (load-average) (processor-count)))

;;; ------------------------------------------------------------------
;;; A stopwatch, for waits and reports

(defstruct (stopwatch (:constructor start-stopwatch ()))
  "Wall time since it was started, or until it was stopped.  For a wait that
gives up and a report's seconds; an assertion on time is IS-FAST or
IS-WITHIN-SECONDS, which also takes a stopwatch stopped where an assertion
cannot be made, as in another thread."
  (start (wall-ticks) :type integer :read-only t)
  (end nil :type (or null integer)))

(defun stop-stopwatch (watch)
  "Stop WATCH: its seconds stay those until now.  Values WATCH."
  (setf (stopwatch-end watch) (wall-ticks))
  watch)

(defun lap-stopwatch (watch)
  "A stopwatch started when WATCH was and stopped now: the time of a lap,
such as a line a program wrote."
  (stop-stopwatch (copy-stopwatch watch)))

(defun stopwatch-seconds (watch)
  "The seconds WATCH has run, for a report."
  (/ (- (or (stopwatch-end watch) (wall-ticks)) (stopwatch-start watch))
     (float internal-time-units-per-second 1d0)))

(defun stopwatch-past-p (watch seconds)
  "True once WATCH has run SECONDS or more: when a wait gives up."
  (>= (stopwatch-seconds watch) seconds))

;;; ------------------------------------------------------------------
;;; The Postgres server's share of the work

(defun store-postgres-url ()
  "The URL of the test application's database when its store is Postgres."
  (let ((store (and *app* (application-store *app*))))
    (and (typep store 'tun.store.postgres:postgres-store)
         (tun.store.postgres:postgres-store-url store))))

(defun open-monitor (url)
  "A connection of its own to the database URL names, to find the server
processes that serve it."
  (destructuring-bind (&key database user password host port)
      (tun.store.postgres:parse-postgres-url url)
    (cl-postgres:open-database database user password host port)))

(defun server-pids (monitor)
  "The server processes serving MONITOR's database, but MONITOR's own."
  (mapcar #'first
          (cl-postgres:exec-query
           monitor "SELECT pid FROM pg_stat_activity
                    WHERE datname = current_database() AND pid <> pg_backend_pid()"
           'cl-postgres:list-row-reader)))

(defun pid-nanoseconds (pid)
  "The processor time of process PID so far, or NIL when it cannot be read
\(gone, or on another machine)."
  (with-open-file (in (format nil "/proc/~d/schedstat" pid) :if-does-not-exist nil)
    (and in (ignore-errors (parse-integer (read-line in) :junk-allowed t)))))

(defun server-times (monitor)
  "Each serving process's processor time, as (pid . nanoseconds), and
whether any could be read at all."
  (let* ((pids (server-pids monitor))
         (times (loop for pid in pids
                      for ns = (pid-nanoseconds pid)
                      when ns collect (cons pid ns))))
    (values times (or (null pids) (not (null times))))))

;;; ------------------------------------------------------------------
;;; A speed

(defstruct (measurement (:constructor make-measurement
                            (why runs processor-ms server-ms wall-ms wall-only)))
  "What RUNS runs of something measured: the median processor time, the
median of the Postgres server's share of it, the median wall time, and
whether only wall time could be measured."
  why runs processor-ms server-ms wall-ms wall-only
  (limit-ms nil) (over nil) (factor 1) (added-ms 0))

(defmethod print-object ((measured measurement) stream)
  (print-unreadable-object (measured stream :type t)
    (format stream "~a: ~,1f ms" (measurement-why measured) (measurement-measured-ms measured))))

(defun measurement-measured-ms (measured)
  "What decides MEASURED's verdict: processor time, or wall time when only
that could be measured."
  (if (measurement-wall-only measured)
      (measurement-wall-ms measured)
      (measurement-processor-ms measured)))

(defun median (numbers)
  (let ((sorted (sort (copy-list numbers) #'<)))
    (nth (floor (length sorted) 2) sorted)))

(defun measure-run (function monitor)
  "One run of FUNCTION: values its processor milliseconds (this process's
and, with MONITOR, those of the server processes serving its database),
the server's share of them, its wall milliseconds, whether the server's
could not be read, and FUNCTION's value."
  (multiple-value-bind (before readable) (if monitor (server-times monitor) (values '() t))
    (let* ((wall (wall-nanoseconds))
           (processor (process-nanoseconds))
           (value (funcall function))
           (processor-ns (- (process-nanoseconds) processor))
           (wall-ns (- (wall-nanoseconds) wall))
           (server-ns (if monitor
                          ;; A process that started during the run counts whole.
                          (loop for (pid . ns) in (server-times monitor)
                                sum (- ns (or (cdr (assoc pid before)) 0)))
                          0)))
      (values (/ (+ processor-ns server-ns) 1d6) (/ server-ns 1d6) (/ wall-ns 1d6) (not readable)
              value))))

(defun measure-speed (function &key (why "") (runs 9))
  "Run FUNCTION RUNS times and measure it (spec/tooling.md, \"Speed and
time in tests\"); values the measurement, and FUNCTION's value of the last run.
Asserts nothing: IS-FAST does, and takes a measurement from here as its OVER."
  (let ((url (store-postgres-url))
        (monitor nil))
    (unwind-protect
         (let ((processor '()) (server '()) (wall '()) (wall-only nil) (value nil))
           (when url (setf monitor (open-monitor url)))
           (loop repeat runs
                 do (multiple-value-bind (processor-ms server-ms wall-ms unreadable last)
                        (measure-run function monitor)
                      (push processor-ms processor)
                      (push server-ms server)
                      (push wall-ms wall)
                      (when unreadable (setf wall-only t))
                      (setf value last)))
           (values (make-measurement why runs (median processor) (and url (median server))
                                     (median wall) wall-only)
                   value))
      (when monitor (cl-postgres:close-database monitor)))))

(defun measurement-limit-text (measured)
  (if (measurement-over measured)
      (format nil "~,1f ms (~a × ~,1f ms + ~a ms)" (measurement-limit-ms measured)
              (measurement-factor measured) (measurement-measured-ms (measurement-over measured))
              (measurement-added-ms measured))
      (format nil "~a ms" (measurement-limit-ms measured))))

(defun measurement-text (measured)
  "MEASURED and its limit in a line: what, the time measured, the limit, the
wall time and the machine's load."
  (format nil "~a: ~,1f ms of ~:[processor~;wall~] time (median of ~d~@[, Postgres ~,1f ms~]), ~
               ~:[over~;under~] its limit of ~a; wall ~,1f ms; ~a~
               ~:[~;; the Postgres server's processes could not be read, so wall time decides~]"
          (measurement-why measured) (measurement-measured-ms measured)
          (measurement-wall-only measured) (measurement-runs measured)
          (and (not (measurement-wall-only measured)) (measurement-server-ms measured))
          (measurement-within-p measured) (measurement-limit-text measured)
          (measurement-wall-ms measured) (machine-text) (measurement-wall-only measured)))

(defun measurement-within-p (measured)
  (< (measurement-measured-ms measured) (measurement-limit-ms measured)))

(defun limit-measurement (measured limit-ms over factor)
  "MEASURED with its limit: LIMIT-MS, or FACTOR times OVER's plus LIMIT-MS."
  (setf (measurement-over measured) over
        (measurement-factor measured) factor
        (measurement-added-ms measured) limit-ms
        (measurement-limit-ms measured) (if over
                                             (+ (* factor (measurement-measured-ms over)) limit-ms)
                                             limit-ms))
  measured)

(defun measurement-milliseconds (measured)
  "What decides MEASURED's verdict, in milliseconds: its median processor
time, or wall time when only that could be measured.  For a test that
plants a slowdown, never for a limit compared outside IS-FAST."
  (measurement-measured-ms measured))

(defun over-limit-p (measured &key (limit-ms 0) over (factor 1))
  "Whether IS-FAST would fail MEASURED, a measurement from MEASURE-SPEED,
with these limits: for a test that plants a slowdown to see it fail."
  (not (measurement-within-p (limit-measurement measured limit-ms over factor))))

(defun check-speed (measured limit-ms over factor)
  (limit-measurement measured limit-ms over factor)
  (format t "~&;; speed ~a~%" (measurement-text measured))
  (fiveam:is (measurement-within-p measured) "~a" (measurement-text measured))
  measured)

(defmacro is-fast ((&key (why "") (limit-ms 0) over (factor 1) (runs 9)) &body body)
  "Assert that BODY is fast enough (spec/tooling.md, \"Speed and time in
tests\"): the median processor time of RUNS runs of it is under LIMIT-MS,
or, with OVER, a measurement from MEASURE-SPEED, under FACTOR times OVER's plus
LIMIT-MS.  Values the measurement and BODY's value of the last run."
  (let ((value (gensym "VALUE")) (measured (gensym "MEASURED")))
    `(multiple-value-bind (,measured ,value) (measure-speed (lambda () ,@body) :why ,why :runs ,runs)
       (values (check-speed ,measured ,limit-ms ,over ,factor) ,value))))

;;; ------------------------------------------------------------------
;;; When something happens

(defun seconds-text (why seconds over under)
  (format nil "~a: ~,2f s~@[, not at least ~a s~]~@[, not under ~a s~] (wall time; ~a)"
          why seconds (and over (< seconds over) over) (and under (>= seconds under) under)
          (machine-text)))

(defun check-seconds (watch why over under)
  (let ((seconds (stopwatch-seconds watch)))
    (fiveam:is (and (or (null over) (>= seconds over)) (or (null under) (< seconds under)))
               "~a" (seconds-text why seconds over under))))

(defmacro with-deadline-lifted (() &body body)
  "Run BODY with the operation's deadline (*DEADLINE-MS*, read by the
server's threads too) at ten minutes: for a test about something else than
time, such as a refusal or a large file, which a loaded machine would
otherwise stop at the deadline (spec/tooling.md, \"Speed and time in
tests\")."
  (let ((saved (gensym "SAVED")))
    `(let ((,saved *deadline-ms*))
       (unwind-protect (progn (setf *deadline-ms* (* 10 60 1000)) ,@body)
         (setf *deadline-ms* ,saved)))))

(defmacro is-within-seconds ((&key (why "") over under watch) &body body)
  "Run BODY once and assert that its wall time is at least OVER and under
UNDER seconds, either left out (spec/tooling.md, \"Speed and time in
tests\"): for when a mechanism acts, a deadline or a timeout, never a
speed.  With WATCH, a stopwatch, assert its seconds instead, after BODY.
Values BODY's values."
  (let ((started (gensym "STARTED")))
    `(let ((,started (start-stopwatch)))
       (multiple-value-prog1 (progn ,@body)
         (check-seconds (or ,watch ,started) ,why ,over ,under)))))
