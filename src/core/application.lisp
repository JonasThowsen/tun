;;;; core/application.lisp -- the application object, clock and context.
;;;;
;;;; One application object per deployment.  A client subclasses
;;;; APPLICATION; every extensible generic function dispatches on it, so a
;;;; client's methods never collide with (or replace) core's methods, and the
;;;; same image can run core alone with a plain APPLICATION in tests.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; Clock: all server time comes from here.

(defclass clock () ())
(defgeneric clock-now (clock))
(defgeneric clock-now-ms (clock)
  (:documentation "Current time in milliseconds since the universal-time epoch.")
  (:method ((clock clock)) (* 1000 (clock-now clock))))

(defclass system-clock (clock) ())
(defmethod clock-now ((clock system-clock)) (get-universal-time))
(defmethod clock-now-ms ((clock system-clock))
  ;; Same source as GET-UNIVERSAL-TIME (the realtime clock), with milliseconds;
  ;; 2208988800 is the Unix epoch in universal time.
  (multiple-value-bind (seconds microseconds) (sb-ext:get-time-of-day)
    (+ (* 1000 (+ seconds 2208988800)) (floor microseconds 1000))))

(defparameter +test-clock-start+ "2026-03-01T09:00:00Z")

(defclass test-clock (clock)
  ((now :initarg :now :accessor test-clock-now :type (integer 0))
   (lock :initform (sb-thread:make-mutex :name "test clock") :reader test-clock-lock)))

(defmethod clock-now ((clock test-clock))
  (sb-thread:with-mutex ((test-clock-lock clock))
    (test-clock-now clock)))

(defun set-test-clock (clock time)
  (sb-thread:with-mutex ((test-clock-lock clock))
    (setf (test-clock-now clock) time)))

;;; Application

(defclass application ()
  ((stopping :initform nil :accessor application-stopping-p)
   (provider-calls :initform nil :accessor application-provider-calls)
   (provider-calls-lock :initform (sb-thread:make-mutex :name "provider calls") :reader application-provider-calls-lock)
   (workers :initform nil :accessor application-workers)
   (workers-lock :initform (sb-thread:make-mutex :name "application workers") :reader application-workers-lock)
   (name :initarg :name :initform "tun" :reader application-name)
   (store :initarg :store :initform nil :accessor application-store)
   (clock :initarg :clock :initform (make-instance 'system-clock) :accessor application-clock)
   (accounting :initarg :accounting :initform nil :accessor application-accounting
               :documentation "Adapter implementing the accounting port.")
   (message-transport :initarg :message-transport :initform nil
                      :accessor application-message-transport)
   (mail :initarg :mail :initform nil :accessor application-mail
         :documentation "The mail provider's adapter (spec/mail.md 1), made from the
client's (:mail ...) when the application opens unless given here.")
   (push-service :initarg :push-service :initform nil :accessor application-push-service
                 :documentation "The adapter push notifications are delivered through
(spec/push.md 5): Web Push over HTTPS, or one that sends nothing with the test
clock, when the application opens unless given here.")
   (debug-tools :initarg :debug-tools :initform nil :accessor application-debug-tools-p
                :documentation "--debug-tools: expose the debug_* tools (core.md §7.6).")
   (allow-eval :initarg :allow-eval :initform nil :accessor application-allow-eval-p
               :documentation "--allow-eval: expose the eval tool (core.md §8.2).")
   (repl-port :initarg :repl-port :initform nil :accessor application-repl-port)
   (identity :initarg :identity :initform :authenticated :reader application-identity
             :type (member :authenticated :claimed)
             :documentation "Where actors come from (spec/auth.md 1): credentials the tenant
issued, or, with --claimed-identity, also the X-Tun-Actor claim.")
   (public-url :initarg :public-url :initform nil :reader application-public-url
               :documentation "Where people reach the server, such as https://example.no,
from --public-url or PUBLIC_URL (spec/deploy.md 1); NIL when it was not given.")
   (log-requests :initarg :log-requests :initform nil :accessor application-log-requests-p
                 :documentation "Write a JSON line to standard output for every request
that ends (spec/errors.md 6): a server's default, never a test's.")
   (jobs-state :initform nil :accessor application-jobs-state
               :documentation "The process's own job state (TUN.JOBS): its process id and
the workers running each queue, which live in memory only.")
   (auth-state :initform nil :accessor application-auth-state
               :documentation "The process's own identity state (TUN.AUTH): the setup code
and the failed-login counts, which live in memory only.")
   (live-definitions :initform nil :accessor application-live-definitions)
   (live-patches :initform nil :accessor application-live-patches)
   (definition-sources :initform nil :accessor application-definition-sources)
   (definitions-lock :initform (sb-thread:make-mutex :name "live definitions") :reader application-definitions-lock)
   (started-us :initform (trace-clock-us) :reader application-started-us)
   (max-inflight :initform nil :accessor application-max-inflight)
   (inflight-cell :initform nil :accessor application-inflight-cell
                  :documentation "The HTTP layer's (count) cell of requests being processed."))
  (:documentation "A deployed tun system. Clients subclass it and specialize methods on the subclass."))

(defvar *application* nil "The application handling the current request.")

(defun test-mode-p (&optional (application *application*))
  (typep (application-clock application) 'test-clock))

(defun claimed-identity-p (&optional (application *application*))
  "True when APPLICATION takes the actor a request claims (--claimed-identity)."
  (eq (application-identity application) :claimed))

(defun absolute-url (path &optional (application *application*))
  "PATH, such as \"/saker/sak_1\", at APPLICATION's public URL: the whole link
a mail needs.  PATH itself when the server was given no public URL
(spec/deploy.md 1)."
  (let ((base (application-public-url application)))
    (if base (concatenate 'string base path) path)))

(defun now ()
  "Current server time (universal time) from the application's clock."
  (clock-now (application-clock *application*)))

(defun now-ms ()
  "Current server time in milliseconds (universal-time epoch); stored times stay whole seconds."
  (clock-now-ms (application-clock *application*)))

(defun now-string () (format-rfc3339 (now)))
(defun today () (date-of (now)))
(defun local-today ()
  "The clock instant's Norwegian local date (core.md §2.2: \"today\")."
  (local-date-of (now)))

(defun call-with-application (application function)
  (if (eq application *application*)
      (funcall function)
      (let ((*application* application)
            (*store* (application-store application))
            (*now-function* #'now)
            (*transaction-mode* nil))
        (funcall function))))

(defmacro with-application ((application) &body body)
  `(call-with-application ,application (lambda () ,@body)))

(defgeneric application-title (application)
  (:documentation "Human readable name of the deployment (used by the UI).")
  (:method ((application application)) (application-name application)))

(defgeneric application-after-request (application)
  (:documentation "Drain committed port work outside the sender transaction; slow ports must return immediately.")
  (:method (application) (declare (ignore application)) nil))

(defun normalize-message-text (text) (sb-unicode:normalize-string text :nfc))
(defun message-grapheme-count (text) (if (zerop (length text)) 0 (length (sb-unicode:graphemes text))))
(defun utf8-byte-count (text) (length (sb-ext:string-to-octets text :external-format :utf-8)))

(defun worker-running-p (lock) (not (null (sb-thread:mutex-owner lock))))
(defun call-with-worker-lock (lock function)
  "Run at most one worker for LOCK; a busy worker is never waited for."
  (when (sb-thread:grab-mutex lock :waitp nil)
    (unwind-protect (funcall function) (sb-thread:release-mutex lock))))
(defun start-worker (function name &optional (completion-wait 0))
  "Start committed work; optionally allow a bounded wait for quick completion."
  (let* ((app *application*)
         (thread (sb-thread:with-mutex ((application-workers-lock app))
                   (when (application-stopping-p app) (return-from start-worker nil))
                   (setf (application-workers app) (remove-if-not #'sb-thread:thread-alive-p (application-workers app)))
                   (let ((worker (sb-thread:make-thread function :name name)))
                     (push worker (application-workers app)) worker))))
    (when (plusp completion-wait)
      (sb-thread:join-thread thread :timeout completion-wait :default nil))
    thread))
(defun wait-for-workers (app)
  "Finish provider bookkeeping before closing the application's store."
  (let ((threads (sb-thread:with-mutex ((application-workers-lock app)) (copy-list (application-workers app)))))
    (dolist (thread threads) (sb-thread:join-thread thread))))
(defconstant +provider-call-limit+ 4)
(defun provider-call-capacity-p (&optional (app *application*))
  "Permit a claim only while this tenant has fewer than four live provider calls."
  (sb-thread:with-mutex ((application-provider-calls-lock app))
    (setf (application-provider-calls app) (remove-if-not #'sb-thread:thread-alive-p (application-provider-calls app)))
    (and (not (application-stopping-p app))
         (< (length (application-provider-calls app)) +provider-call-limit+))))
(defun stop-application-workers (app)
  "Stop new claims and let current bookkeeping finish; abandoned ports are never joined."
  (sb-thread:with-mutex ((application-workers-lock app))
    (setf (application-stopping-p app) t))
  (wait-for-workers app))
(defun call-with-time-limit (function seconds)
  "Bound provider calls and live abandoned threads per tenant; late answers are discarded."
  (let* ((app *application*) (timeout (gensym "PORT-TIMEOUT"))
         (deadline (+ (get-internal-real-time) (* seconds internal-time-units-per-second)))
         (thread (sb-thread:with-mutex ((application-provider-calls-lock app))
                   (setf (application-provider-calls app) (remove-if-not #'sb-thread:thread-alive-p (application-provider-calls app)))
                   (when (or (application-stopping-p app)
                             (>= (length (application-provider-calls app)) +provider-call-limit+))
                     (error 'deadline-exceeded))
                   (let ((call (sb-thread:make-thread
                                 (lambda () (handler-case (cons :ok (multiple-value-list (funcall function)))
                                              (serious-condition (condition) (cons :error condition))))
                                 :name "bounded provider call")))
                     (push call (application-provider-calls app)) call))))
    (loop
      (let ((remaining (/ (- deadline (get-internal-real-time)) internal-time-units-per-second)))
        (when (or (application-stopping-p app) (<= remaining 0)) (error 'deadline-exceeded))
        (let ((answer (sb-thread:join-thread thread :timeout (min remaining .05) :default timeout)))
          (unless (eq answer timeout)
            (when (>= (get-internal-real-time) deadline) (error 'deadline-exceeded))
            (if (eq (car answer) :error) (error (cdr answer))
                (return (values-list (cdr answer))))))))))
