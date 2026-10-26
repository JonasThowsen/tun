;;;; core/deadline.lisp -- per-operation deadlines (core.md §7.1).
;;;;
;;;; Every top-level operation (and every workflow run) gets a deadline of
;;;; *DEADLINE-MS*.  Two mechanisms enforce it, deliberately:
;;;;
;;;; 1. Cooperative checks (the primary path).  CHECK-DEADLINE runs at every
;;;;    store access, before taking the write lock (which is acquired with a
;;;;    timeout), and inside the loops of anything that waits or computes for a
;;;;    long time (SLEEP-WITH-DEADLINE, the debug tools, the fake adapter's
;;;;    latency).  It signals DEADLINE-EXCEEDED from a known point, so the
;;;;    unwind is as safe as any other error: the transaction rolls back.
;;;;
;;;; 2. A watchdog thread (the backstop) for code that never reaches a check,
;;;;    e.g. a runaway loop in an extension.  Once an operation is past its
;;;;    deadline plus WATCHDOG-GRACE-MS, it interrupts the thread
;;;;    (SB-THREAD:INTERRUPT-THREAD) to signal DEADLINE-EXCEEDED there.  An
;;;;    asynchronous unwind can land anywhere in Lisp code; it never lands
;;;;    inside a foreign call into SQLite (WITHOUT-DEADLINE-INTERRUPTS marks
;;;;    those, and the interrupt re-arms instead), because unwinding through
;;;;    sqlite3_step would leave the connection unusable.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *deadline-ms* 10000 "Server-side deadline of every operation (--deadline-ms).")
(defparameter *watchdog-grace-ms* 500 "How long past the deadline before the watchdog interrupts.")

(define-condition deadline-exceeded (error) ()
  (:report "The operation ran past its deadline"))

(defvar *deadline* nil "Internal real time at which the current operation's deadline passes.")
(defvar *interruptible* t "NIL inside foreign calls the watchdog must not interrupt.")

(declaim (inline now-internal))
(defun now-internal () (get-internal-real-time))

(defun ms->internal (ms) (round (* ms internal-time-units-per-second) 1000))

(defun deadline-remaining-ms ()
  "Milliseconds until the current deadline (NIL when there is none)."
  (and *deadline* (max 0 (floor (* 1000 (- *deadline* (now-internal))) internal-time-units-per-second))))

(defun check-deadline ()
  (when (and *deadline* (> (now-internal) *deadline*))
    (error 'deadline-exceeded)))

(defun sleep-with-deadline (ms)
  "Sleep MS milliseconds in short slices, ending at the deadline."
  (let ((end (+ (now-internal) (ms->internal ms))))
    (loop for left = (- end (now-internal))
          while (plusp left)
          do (check-deadline)
             (sleep (min 0.05 (/ left internal-time-units-per-second))))
    (check-deadline)))

(defmacro without-deadline-interrupts (&body body)
  "Run BODY (a foreign call) where the watchdog must not unwind."
  `(let ((*interruptible* nil)) ,@body))

;;; ------------------------------------------------------------------
;;; Watchdog

(defvar *watched* (make-hash-table :test 'eq) "Thread -> watch entry.")
(defvar *watched-lock* (sb-thread:make-mutex :name "deadline watchdog"))
(defvar *watchdog* nil)

(defstruct watch deadline (fired nil))

(defun call-with-deadline (function &key (ms *deadline-ms*))
  "Run FUNCTION under a deadline of MS (unless one is already running)."
  (if *deadline*
      (funcall function)
      (let* ((*deadline* (+ (now-internal) (ms->internal ms)))
             (entry (make-watch :deadline *deadline*))
             (thread sb-thread:*current-thread*))
        (sb-thread:with-mutex (*watched-lock*) (setf (gethash thread *watched*) entry))
        (unwind-protect (funcall function)
          (sb-thread:with-mutex (*watched-lock*)
            (when (eq (gethash thread *watched*) entry) (remhash thread *watched*)))))))

(defmacro with-deadline ((&key (ms '*deadline-ms*)) &body body)
  `(call-with-deadline (lambda () ,@body) :ms ,ms))

(defun move-deadline (ms)
  "Move the running operation's deadline to MS milliseconds from now, for
the watchdog too: for an operation that waits longer than a deadline allows
(spec/waiting.md 1).  Nothing when no deadline runs."
  (when *deadline*
    (let ((new (+ (now-internal) (ms->internal ms))))
      (setf *deadline* new)
      (sb-thread:with-mutex (*watched-lock*)
        (let ((entry (gethash sb-thread:*current-thread* *watched*)))
          (when entry (setf (watch-deadline entry) new)))))))

(defun watchdog-interrupt (entry)
  "Runs inside the late thread."
  (cond ((not (eq (sb-thread:with-mutex (*watched-lock*) (gethash sb-thread:*current-thread* *watched*)) entry)))
        ((not *interruptible*) (setf (watch-fired entry) nil)) ; in a foreign call: re-arm
        (t (error 'deadline-exceeded))))

(defun watchdog-scan ()
  (let ((late '())
        (now (now-internal))
        (grace (ms->internal *watchdog-grace-ms*)))
    (sb-thread:with-mutex (*watched-lock*)
      (maphash (lambda (thread entry)
                 (when (and (not (watch-fired entry)) (> now (+ (watch-deadline entry) grace)))
                   (setf (watch-fired entry) t)
                   (push (cons thread entry) late)))
               *watched*))
    (loop for (thread . entry) in late
          do (ignore-errors
              (let ((entry entry))
                (sb-thread:interrupt-thread thread (lambda () (watchdog-interrupt entry))))))))

(defun start-deadline-watchdog ()
  (unless (and *watchdog* (sb-thread:thread-alive-p *watchdog*))
    (setf *watchdog*
          (sb-thread:make-thread (lambda () (loop (sleep 0.05) (ignore-errors (watchdog-scan))))
                                 :name "tun deadline watchdog")))
  *watchdog*)
