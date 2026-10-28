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
;;;; A transport adapts a wait to its connection through four specials:
;;;; *AWAIT-LIMIT* holds a wait to what the connection survives,
;;;; *AWAIT-HEARTBEAT* is called while it waits, so MCP can send progress,
;;;; *WAITING-LEAVES* are the counts a parked call leaves while it waits,
;;;; and *WAIT-CLIENT* is the client its wait counts for.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +await-max-seconds+ 600 "The longest any wait lasts.")
(defparameter +await-recheck-seconds+ 5
  "How often a waiting call looks again without being woken: what another
process on the same database commits reaches it within this.")
(defparameter +await-heartbeat-seconds+ 25 "How often *AWAIT-HEARTBEAT* is called.")
(defparameter *max-waiting* 256 "How many calls may wait at once in this process.")

(defparameter *max-waiting-per-client* 32
  "How many of the *MAX-WAITING* may wait at once for one client (core.md 7.5).")

(defvar *waiting* (list 0) "How many calls wait now, in a cell for SB-EXT:ATOMIC-INCF.")

(defvar *client-waits* (make-key-counts "client waits")
  "How many calls wait now for each client, by its *WAIT-CLIENT* key.")

(defvar *await-limit* +await-max-seconds+
  "The longest a wait lasts in this request: the transport lowers it to what
its connection survives.")

(defvar *await-heartbeat* nil
  "NIL, or a function of the seconds waited so far, called every
+AWAIT-HEARTBEAT-SECONDS+ while a call waits: MCP sends progress with it.")

(defvar *waiting-leaves* '()
  "What a call leaves while it waits, as its transport counts it: a list of
functions, each called with :LEAVE when the call starts waiting and with
:RETURN when it stops.  HTTP adds one for the requests in flight, so waits
do not use up --max-inflight, and one for its client's requests in
progress through the proxy (core.md 7.5).")

(defvar *wait-client* nil
  "The client a call that waits counts for, the key HTTP counts the caller
under (core.md 7.5); NIL for a call made inside the process, which only
*MAX-WAITING* bounds.")

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
the waiting, in the process and for its client, and out of what
*WAITING-LEAVES* count, with a deadline that lasts the wait and then a
whole one for the work after it.  Refused with unavailable, before it
waits, past *MAX-WAITING* or its client's *MAX-WAITING-PER-CLIENT*."
  (when (>= (sb-ext:atomic-incf (car *waiting*)) *max-waiting*)
    (sb-ext:atomic-decf (car *waiting*))
    (fail :unavailable "~d calls are already waiting; try again shortly" *max-waiting*))
  (let ((client *wait-client*))
    (when (and client (not (take-count *client-waits* client *max-waiting-per-client*)))
      (sb-ext:atomic-decf (car *waiting*))
      (fail :unavailable "~d calls are already waiting from the same address; try again shortly"
            *max-waiting-per-client*))
    (dolist (leave *waiting-leaves*)
      (funcall leave :leave))
    (move-deadline (+ (* 1000 seconds) *deadline-ms*))
    (unwind-protect (funcall function)
      (dolist (leave *waiting-leaves*)
        (funcall leave :return))
      (when client
        (give-back-count *client-waits* client))
      (sb-ext:atomic-decf (car *waiting*))
      (move-deadline *deadline-ms*))))

(defun waiting-count ()
  "How many calls wait now in this process."
  (car *waiting*))

(defun client-waiting-count (client)
  "How many calls wait now for CLIENT, a *WAIT-CLIENT* key."
  (key-count *client-waits* client))
