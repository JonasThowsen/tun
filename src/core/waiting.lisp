;;;; core/waiting.lisp -- operations that wait for a change (spec/waiting.md).
;;;;
;;;; An agent's call can wait for something a person does, such as answering
;;;; a question, and get it in the same call.  AWAIT runs a form in a read
;;;; transaction of its own, again after every commit (NOTE-COMMIT wakes it)
;;;; and at least every few seconds, until its value is what the caller
;;;; waits for or the time is up.  Between tries it holds no transaction.
;;;; Only the body of a :WAIT operation, which runs outside a transaction,
;;;; may wait.
;;;;
;;;; A transport adapts a wait to its connection through three specials:
;;;; *AWAIT-LIMIT* holds a wait to what the connection survives,
;;;; *AWAIT-HEARTBEAT* is called while it waits, so MCP can send progress,
;;;; and *IN-FLIGHT-CELL* is the request count a parked call leaves.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +await-max-seconds+ 600 "The longest any wait lasts.")
(defparameter +await-recheck-seconds+ 5
  "How often a waiting call looks again without being woken: what another
process on the same database commits reaches it within this.")
(defparameter +await-heartbeat-seconds+ 25 "How often *AWAIT-HEARTBEAT* is called.")
(defparameter *max-waiting* 256 "How many calls may wait at once in this process.")

(defvar *waiting* (list 0) "How many calls wait now, in a cell for SB-EXT:ATOMIC-INCF.")

(defvar *await-limit* +await-max-seconds+
  "The longest a wait lasts in this request: the transport lowers it to what
its connection survives.")

(defvar *await-heartbeat* nil
  "NIL, or a function of the seconds waited so far, called every
+AWAIT-HEARTBEAT-SECONDS+ while a call waits: MCP sends progress with it.")

(defvar *in-flight-cell* nil
  "The cell counting the HTTP requests in flight, while one is being
handled: a waiting call leaves the count, so waits do not use up
--max-inflight.")

(defmacro await ((&key seconds (until '#'identity)) &body form)
  "Evaluate FORM in a read transaction of its own until UNTIL, a function of
its value, holds (the value itself being true, without UNTIL) or SECONDS
have passed; again after every commit, and at least every
+AWAIT-RECHECK-SECONDS+.  Values the last value and whether UNTIL held.  Only
in the body of a :WAIT operation (spec/waiting.md 1)."
  `(call-awaiting (lambda () ,@form) ,seconds ,until))

(defun call-awaiting (probe seconds until)
  (unless (and *operation* (eq (operation-kind *operation*) :wait) (null *transaction-mode*))
    (error "AWAIT waits only in the body of an operation of :kind :wait, outside a transaction"))
  (check-type seconds (real 0))
  (let ((seconds (min seconds *await-limit* +await-max-seconds+))
        (start (get-internal-real-time)))
    (labels ((waited ()
               (/ (- (get-internal-real-time) start) internal-time-units-per-second))
             (look ()
               ;; The commit count is read before the look, so a commit
               ;; between the look and the wait wakes the wait at once.
               (let* ((seen (store-commits *store*))
                      (value (with-transaction (:read) (funcall probe))))
                 (values value (and (funcall until value) t) seen))))
      (multiple-value-bind (value done seen) (look)
        (if (or done (>= (waited) seconds))
            (values value done)
            (call-parked
             seconds
             (lambda ()
               (let ((heartbeat-at +await-heartbeat-seconds+))
                 (loop
                   (wait-for-commit *store* seen (min +await-recheck-seconds+
                                                      (- seconds (waited))))
                   (when (and *await-heartbeat* (>= (waited) heartbeat-at))
                     (funcall *await-heartbeat* (floor (waited)))
                     (incf heartbeat-at +await-heartbeat-seconds+))
                   (multiple-value-setq (value done seen) (look))
                   (when (or done (>= (waited) seconds))
                     (return (values value done))))))))))))

(defun call-parked (seconds function)
  "Run FUNCTION, a wait of at most SECONDS, as a parked call: counted among
the waiting, not the requests in flight, and with a deadline that lasts the
wait and then a whole one for the work after it."
  (when (>= (sb-ext:atomic-incf (car *waiting*)) *max-waiting*)
    (sb-ext:atomic-decf (car *waiting*))
    (fail :unavailable "~d kall venter allerede; prøv igjen om litt" *max-waiting*))
  (when *in-flight-cell*
    (sb-ext:atomic-decf (car *in-flight-cell*)))
  (move-deadline (+ (* 1000 seconds) *deadline-ms*))
  (unwind-protect (funcall function)
    (when *in-flight-cell*
      (sb-ext:atomic-incf (car *in-flight-cell*)))
    (sb-ext:atomic-decf (car *waiting*))
    (move-deadline *deadline-ms*)))

(defun waiting-count ()
  "How many calls wait now in this process."
  (car *waiting*))
