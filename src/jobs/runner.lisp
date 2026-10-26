;;;; jobs/runner.lisp -- running due jobs (spec/jobs.md 4, 6, 7).
;;;;
;;;; A job is claimed in a write transaction of its own: marked running by
;;;; this process, its attempt counted.  The attempt then runs as system:job
;;;; in a request of its own, and what it came to is recorded: with the
;;;; body's own writes for a job in a transaction, after the body for one
;;;; outside.  Writers are serialised (spec/store.md 2), so two processes
;;;; never claim the same job.
;;;;
;;;; Each process has a row in job_processes naming the presence lock it
;;;; holds while it runs (spec/store.md 3).  The running jobs of a process
;;;; whose lock is free, because it died or closed, are recovered by
;;;; whichever process notices.

(in-package #:tun.jobs)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Processes (spec/jobs.md 7)

(define-entity job-process (:label "Jobbprosess" :id-prefix "jpr" :table "job_processes"
                                   :internal t)
  ((started-at :type timestamp :input nil :label "Startet")
   (lock-key :type integer :input nil :label "Lås"
             :description "The presence lock the process holds while it runs (spec/store.md 3).")))

(defparameter +rescue-seconds+ 10 "How often a process looks for the jobs of processes that are gone.")
(defparameter +prune-seconds+ 3600 "How often a process deletes jobs kept long enough.")

(defclass jobs-state ()
  ((process-id :initarg :process-id :reader jobs-state-process-id)
   (last-rescue :initform (get-internal-real-time) :accessor jobs-state-last-rescue
                :documentation "Internal real time this process last looked for lost jobs.")
   (last-prune :initform (get-internal-real-time) :accessor jobs-state-last-prune
               :documentation "Internal real time this process last deleted old jobs.")
   (running :initform (make-hash-table :test 'eq) :reader jobs-state-running
            :documentation "Queue keyword -> how many workers run it.")
   (waking :initform nil :accessor jobs-state-waking-p
           :documentation "True in a server, whose scheduler runs: a job due now starts when
its write commits.  An application a test opens runs its jobs when told.")
   (lock :initform (sb-thread:make-mutex :name "job workers") :reader jobs-state-lock))
  (:documentation "What a process knows about its own part in running jobs."))

(defun process-id ()
  "The id of this process's row in job_processes."
  (jobs-state-process-id (application-jobs-state *application*)))

(defun claim-presence-key (store)
  "A presence key this process now holds on STORE.  Keys are random, from a
random state of this process's own, so two processes started from one image
do not pick alike; one another holds is passed over."
  (let ((random (make-random-state t)))
    (loop for key = (random (expt 2 31) random)
          when (store-claim-presence store key) return key)))

(defun open-job-process (app)
  "Register APP's process as one that runs jobs, holding its presence lock,
recover the jobs of every process that is gone, and enqueue what the
schedules missed while no process ran.  Runs when the application opens;
refuses to when a schedule names a job it cannot enqueue."
  (check-schedules)
  (with-application (app)
    (let* ((key (claim-presence-key (application-store app)))
           (process (with-transaction (:write)
                      (insert (make-instance 'job-process :started-at (now) :lock-key key)))))
      (setf (application-jobs-state app)
            (make-instance 'jobs-state :process-id (entity-id process)))
      (rescue-orphaned-jobs)
      (tend-schedules))))

(defun close-job-process (app)
  "Remove APP's process row.  Closing the store then releases its presence
lock, so another process recovers at once any job it left running.  Runs
when the application closes, after its workers have stopped."
  (when (application-jobs-state app)
    (with-application (app)
      (with-transaction (:write)
        (let ((process (fetch 'job-process (process-id))))
          (when process (delete-entity process)))))))

(defun lost-job (job)
  "Record that JOB's process stopped during its attempt: retrying, or failed
when its kind says :after-crash :fail or it has no attempts left."
  (let ((definition (find-job-definition (job-kind job))))
    (note-failure job "Prosessen stoppet under forsøket; utfallet er ukjent")
    (if (and definition (eq (job-definition-after-crash definition) :retry)
             (< (job-attempts job) (job-max-attempts job)))
        (setf (job-state job) "retrying"
              (job-due-at job) (now))
        (setf (job-state job) "failed"
              (job-finished-at job) (now)
              (job-note job) "Prosessen stoppet under forsøket; sjekk utfallet før jobben kjøres igjen"))
    (save job)))

(defun rescue-orphaned-jobs ()
  "Recover the running jobs of every process that is gone: one whose presence
lock no process holds, or that has no row (spec/jobs.md 7).  Returns how
many jobs it recovered."
  (with-transaction (:write)
    (let ((own (process-id))
          (alive '()))
      (dolist (process (select 'job-process))
        (cond ((equal (entity-id process) own) (push own alive))
              ((store-present-p *store* (job-process-lock-key process))
               (push (entity-id process) alive))
              (t (delete-entity process))))
      (let ((lost (remove-if (lambda (job) (member (job-claimed-by job) alive :test #'equal))
                             (select 'job :where '(:= "state" "running")))))
        (mapc #'lost-job lost)
        (length lost)))))

;;; ------------------------------------------------------------------
;;; Claiming

(defun due-job-condition (queue &optional except)
  "Due jobs, of QUEUE when given, of no queue named in EXCEPT."
  `(:and (:in "state" ("queued" "retrying"))
         (:<= "due_at" ,(now))
         ,@(when queue `((:= "queue" ,queue)))
         ,@(mapcar (lambda (other) `(:/= "queue" ,other)) except)))

(defun claim (job)
  "Mark JOB running in this process, its attempt counted."
  (setf (job-state job) "running"
        (job-claimed-by job) (process-id)
        (job-started-at job) (now))
  (incf (job-attempts job))
  (save job))

(defun claim-job (&optional queue except)
  "The next due job, of QUEUE (a queue name) when given and of no queue named
in EXCEPT, claimed by this process; NIL when none is due.  Lowest priority
number first, then the earliest due, then the oldest."
  (with-transaction (:write)
    (let ((job (select-one 'job :where (due-job-condition queue except)
                                :order-by '(("priority" :asc) ("due_at" :asc) ("seq" :asc)))))
      (when job (claim job)))))

;;; ------------------------------------------------------------------
;;; Retrying (spec/jobs.md 2)

(defun default-backoff (attempt max-attempts)
  "Oban's backoff: 15 seconds plus 2 to the power of the attempt, the attempt
scaled to twenty when a kind has more attempts than that."
  (let ((scaled (if (<= max-attempts 20) attempt (round (* 20 attempt) max-attempts))))
    (+ 15 (expt 2 scaled))))

(defun with-jitter (seconds)
  "SECONDS and up to a tenth more at random, so jobs that failed together do
not retry together.  Exact in test mode."
  (if (test-mode-p)
      seconds
      (+ seconds (random (1+ (floor seconds 10))))))

(defun backoff-seconds (definition attempt)
  "Seconds before the next attempt of a job of DEFINITION whose ATTEMPT-th
attempt failed: its :backoff list, whose last element repeats, else the
default, each with jitter; or what its :backoff function answers."
  (let ((backoff (job-definition-backoff definition)))
    (cond ((null backoff)
           (with-jitter (default-backoff attempt (job-definition-max-attempts definition))))
          ((listp backoff)
           (with-jitter (nth (min (1- attempt) (1- (length backoff))) backoff)))
          (t (funcall backoff attempt)))))

(defun note-failure (job text)
  "Add TEXT, what went wrong in JOB's current attempt, to its errors, keeping
the last ten."
  (let ((text (subseq text 0 (min 2000 (length text))))
        (earlier (coerce (or (job-errors job) #()) 'list)))
    (setf (job-last-error job) text
          (job-errors job) (jarr (last (append earlier
                                               (list (jobj "attempt" (job-attempts job)
                                                           "at" (format-rfc3339 (now))
                                                           "error" text
                                                           "request_id" (or *request-id* :null))))
                                       10)))))

(defun record-outcome (job outcome detail)
  "Store what JOB's attempt came to (spec/jobs.md 4.3): OUTCOME is
:succeeded, :failed with DETAIL the error's text, :given-up with the reason
FAIL-JOB gave, :cancelled with the reason, or :snoozed with the seconds.  Only a job this process still runs is
changed: one recovered from it meanwhile is another's."
  (let ((current (fetch 'job (entity-id job))))
    (when (and current (equal (job-state current) "running")
               (equal (job-claimed-by current) (process-id)))
      (ecase outcome
        (:succeeded
         (setf (job-state current) "succeeded"
               (job-finished-at current) (now)
               (job-last-error current) nil))
        (:failed
         (note-failure current detail)
         (let* ((definition (find-job-definition (job-kind current)))
                (delay (and definition (< (job-attempts current) (job-max-attempts current))
                            (backoff-seconds definition (job-attempts current)))))
           (if delay
               (setf (job-state current) "retrying"
                     (job-due-at current) (+ (now) delay))
               (setf (job-state current) "failed"
                     (job-finished-at current) (now)))))
        (:given-up
         (note-failure current detail)
         (setf (job-state current) "failed"
               (job-finished-at current) (now)))
        (:cancelled
         (setf (job-state current) "cancelled"
               (job-finished-at current) (now)
               (job-note current) (subseq detail 0 (min 2000 (length detail)))))
        (:snoozed
         (setf (job-state current) "queued"
               (job-due-at current) (+ (now) detail))
         (decf (job-attempts current))
         (incf (job-snoozes current))))
      (save current)
      (write-system-audit (format nil "job:~a" (job-kind current))
                          (if (member outcome '(:failed :given-up)) "rejected" "ok")
                          :entity-type "job" :entity-id (entity-id current)
                          :error-code (and (member outcome '(:failed :given-up)) "job_failed")))))

;;; ------------------------------------------------------------------
;;; One attempt

(defun job-argument-plist (definition job)
  "JOB's stored arguments as its body's keyword arguments, each read back
through its type."
  (let ((json (job-arguments job)))
    (collecting-input-errors
      (loop for parameter in (job-definition-parameters definition)
            for name = (parameter-json-name parameter)
            for value = (and (hash-table-p json) (jget json name))
            when (and value (not (json-null-p value)))
              append (list (parameter-keyword parameter)
                           (coerce-input (parameter-type parameter) value name))))))

(defun attempt-timeout (definition)
  (or (job-definition-timeout definition)
      (if (job-definition-transaction-p definition) 10 60)))

(defun call-body (definition job)
  "Run DEFINITION's body with JOB's arguments within its timeout, and record
its success: in the body's transaction for a job in a transaction, after
the body for one outside."
  (let ((function (job-definition-name definition))
        (arguments (job-argument-plist definition job))
        (*inside-operation* t)
        (*job* job))
    (with-deadline (:ms (* 1000 (attempt-timeout definition)))
      (if (job-definition-transaction-p definition)
          (with-transaction (:write)
            (apply function arguments)
            (record-outcome job :succeeded nil))
          (progn
            (apply function arguments)
            (with-transaction (:write)
              (record-outcome job :succeeded nil)))))))

(defun attempt (record definition job)
  "Run one attempt of JOB in the request RECORD.  Values what it came to and
its detail: :succeeded, :failed and the error's text, :cancelled and the
reason, :given-up and the reason, or :snoozed and the seconds."
  (handler-case
      (progn (with-backtrace-capture (record)
               (call-body definition job))
             (values :succeeded nil))
    (job-cancelled (c) (values :cancelled (job-cancelled-reason c)))
    (job-snoozed (c) (values :snoozed (job-snoozed-seconds c)))
    (job-given-up (c) (values :given-up (job-given-up-reason c)))
    (deadline-exceeded ()
      (let ((text (format nil "Forsøket tok mer enn ~d sekunder" (attempt-timeout definition))))
        (set-request-outcome record "error" :code :deadline-exceeded :message text)
        (values :failed text)))
    (serious-condition (e)
      (choose-request-backtrace record e)
      ;; Printing a condition runs its report function, which can fail too.
      (let ((text (or (ignore-errors (princ-to-string e)) "ukjent feil")))
        (set-request-outcome record "error" :code :job-failed :message text)
        (values :failed text)))))

(defun run-job (job)
  "Run one attempt of JOB, claimed by this process, as system:job in a request
of its own (introspect_request shows it), and record what it came to.
Returns the outcome: :succeeded, :failed, :given-up, :cancelled, :snoozed,
or :yielded for a snooze of 0 seconds, which ends this pass of its queue."
  (let* ((definition (find-job-definition (job-kind job)))
         (id (new-id "req"))
         (*request-id* id)
         (*deadline* nil))
    (with-request-record (:id id :at (now) :actor "system:job" :tool (format nil "job:~a" (job-kind job))
                          :kind :job :force-new t :application *application*
                          :input (jobj "job_id" (entity-id job) "kind" (job-kind job)
                                       "attempt" (job-attempts job)))
      (let ((record *request-record*))
        (with-actor ((system-actor "job"))
          (set-request-policy record :employee :system "allow")
          (with-audit-scope
            (multiple-value-bind (outcome detail)
                (if definition
                    (attempt record definition job)
                    (values :failed (format nil "Jobbtypen ~a finnes ikke" (job-kind job))))
              (unless (eq outcome :succeeded)
                (with-transaction (:write)
                  (record-outcome job outcome detail)))
              (if (and (eq outcome :snoozed) (zerop detail)) :yielded outcome))))))))

(defun run-job-now (job)
  "Claim JOB, queued or retrying, whether or not it is due, and run one
attempt of it.  Returns the outcome, or NIL when JOB is not waiting."
  (let ((claimed (with-transaction (:write)
                   (let ((current (fetch 'job (entity-id job))))
                     (when (and current (member (job-state current) '("queued" "retrying")
                                                :test #'string=))
                       (claim current))))))
    (and claimed (run-job claimed))))

(defun run-due-jobs (&key (limit 10000) queue)
  "Run every due job, of QUEUE (a queue name) when given, in this thread,
including the jobs they enqueue, until none is due.  Values how many
attempts it made and how many succeeded.  clock_set calls it in test mode."
  (let ((attempts 0) (succeeded 0) (yielded '()))
    (loop repeat limit
          until (application-stopping-p *application*)
          for job = (claim-job queue yielded)
          while job
          do (incf attempts)
             (case (run-job job)
               (:succeeded (incf succeeded))
               ;; Not ready now: its queue's next pass tries again.
               (:yielded (push (job-queue job) yielded))))
    (values attempts succeeded)))

;;; ------------------------------------------------------------------
;;; Keeping the table small (spec/jobs.md 10)

(defparameter +keep-done-days+ 14 "Days a succeeded or cancelled job is kept.")
(defparameter +keep-failed-days+ 90 "Days a failed job is kept, for whoever looks into it.")

(defun prune-jobs (&key (limit 1000))
  "Delete up to LIMIT jobs kept long enough: succeeded and cancelled ones
finished more than 14 days ago, failed ones more than 90.  Their arguments
can hold personal data.  Returns how many it deleted."
  (with-transaction (:write)
    (flet ((finished-before (states days)
             (select 'job :where `(:and (:in "state" ,states)
                                        (:< "finished_at" ,(- (now) (* days 86400))))
                          :order-by '(("seq" :asc)) :limit limit)))
      (let ((old (append (finished-before '("succeeded" "cancelled") +keep-done-days+)
                         (finished-before '("failed") +keep-failed-days+))))
        (let ((deleted (subseq old 0 (min limit (length old)))))
          (mapc #'delete-entity deleted)
          (length deleted))))))

(defun seconds-since (internal-time)
  (/ (- (get-internal-real-time) internal-time) internal-time-units-per-second))

;;; ------------------------------------------------------------------
;;; Workers and the tick (spec/jobs.md 6)

(defun known-queues ()
  (remove-duplicates (mapcar #'job-definition-queue (job-definitions))))

(defun queue-name (queue)
  (string-downcase (symbol-name queue)))

(defun start-queue-worker (app queue)
  "Start a worker that runs QUEUE's due jobs until none is left, unless the
queue already runs as many as APP allows."
  (let ((state (application-jobs-state app)))
    (flet ((change-count (delta)
             (incf (gethash queue (jobs-state-running state) 0) delta)))
      (sb-thread:with-mutex ((jobs-state-lock state))
        (when (>= (gethash queue (jobs-state-running state) 0)
                  (application-queue-limit app queue))
          (return-from start-queue-worker nil))
        (change-count 1))
      (or (start-worker
           (lambda ()
             (unwind-protect
                  (handler-case
                      (with-application (app)
                        (loop until (application-stopping-p app)
                              for job = (claim-job (queue-name queue))
                              while job
                              until (eq :yielded (run-job job))))
                    (serious-condition (e)
                      (format *error-output* "~&tun: jobs in ~(~a~): ~a~%" queue e)))
               (sb-thread:with-mutex ((jobs-state-lock state))
                 (change-count -1))))
           (format nil "tun jobs ~(~a~)" queue))
          ;; The application is stopping: no worker started.
          (sb-thread:with-mutex ((jobs-state-lock state))
            (change-count -1)
            nil)))))

(defun start-waking (app)
  "Start a worker for a job due now as soon as the write that enqueued it
commits, instead of at the next tick.  The scheduler calls it when it starts."
  (setf (jobs-state-waking-p (application-jobs-state app)) t))

(defun wake-queue (app queue)
  "After a commit that enqueued a job due now in QUEUE: start a worker for
it, when APP wakes its queues."
  (let ((state (application-jobs-state app)))
    (when (and state (jobs-state-waking-p state))
      (start-queue-worker app queue))))

(defun tend-jobs (app)
  "The scheduler's tick: every ten seconds, recover the jobs of processes
that are gone, and every hour delete old jobs; enqueue the jobs of schedules
whose occurrence has come; and start a worker for each queue that has room
and a due job."
  (with-application (app)
    (let ((state (application-jobs-state app)))
      (when (> (seconds-since (jobs-state-last-rescue state)) +rescue-seconds+)
        (setf (jobs-state-last-rescue state) (get-internal-real-time))
        (rescue-orphaned-jobs))
      (when (> (seconds-since (jobs-state-last-prune state)) +prune-seconds+)
        (setf (jobs-state-last-prune state) (get-internal-real-time))
        (prune-jobs))
      (tend-schedules)
      (dolist (queue (known-queues))
        (when (with-transaction (:read)
                (select-one 'job :where (due-job-condition (queue-name queue))))
          (start-queue-worker app queue))))))
