;;;; jobs/schedules.lisp -- schedules: a job enqueued at each occurrence of a
;;;; cron time (spec/jobs.md 8).
;;;;
;;;; Each tick looks, for every schedule, at the latest occurrence at or
;;;; before now.  When job_schedules has not recorded it, the tick records it
;;;; and enqueues the job, in one write transaction.  Writers are serialised,
;;;; so two processes, a restart or a deploy never run an occurrence twice,
;;;; and no process has to be the leader.  An occurrence is known by its
;;;; wall-clock time, so the hour that happens twice in October runs once.

(in-package #:tun.jobs)

(declaim (optimize (safety 3) (debug 2)))

(defclass schedule ()
  ((name :initarg :name :reader schedule-name
         :documentation "The schedule's name as job_schedules and the tools know it, such as \"daily_summary\".")
   (cron :initarg :cron :reader schedule-cron :type cron)
   (job :initarg :job :reader schedule-job :type symbol
        :documentation "The job kind it enqueues, the symbol DEFINE-JOB named.")
   (arguments :initarg :arguments :reader schedule-arguments
              :documentation "The job's arguments, a plist by argument keyword.")
   (catch-up :initarg :catch-up :reader schedule-catch-up :type (or null (integer 0))
             :documentation "How old a missed occurrence may be and still run, in seconds; NIL runs none.")
   (module :initarg :module :reader schedule-module)
   (location :initarg :location :reader schedule-location))
  (:documentation "A timetable that enqueues a job at each occurrence of a cron time."))

(defvar *schedules* (make-hash-table :test 'equal) "Name -> SCHEDULE.")

(defun schedules ()
  "Every schedule, by name."
  (sort (loop for schedule being the hash-values of *schedules* collect schedule)
        #'string< :key #'schedule-name))

(defun find-schedule (name)
  "The schedule named NAME, a string, or NIL."
  (gethash name *schedules*))

(defun register-schedule (schedule)
  (setf (gethash (schedule-name schedule) *schedules*) schedule))

(defun remove-schedule (name)
  "Forget the schedule NAME, the symbol DEFINE-SCHEDULE named, so that no
tick enqueues its job: in a live image, or after a test.  Its row in
job_schedules stays, so defining it again resumes where it was."
  (remhash (json-name-of name) *schedules*))

(defparameter +default-catch-up+ 86400
  "A missed occurrence runs when it is less than a day old.")

(defparameter +on-time-seconds+ 60
  "How late an occurrence may be found and still count as on time, for a
schedule that catches nothing up: a tick, a busy minute.")

(defmacro define-schedule (name cron job &rest arguments)
  "Define the schedule NAME: at each occurrence of CRON, five cron fields or
an alias such as @daily read in the tenant's time zone, enqueue a job of JOB, the
symbol DEFINE-JOB named, with ARGUMENTS, keyword arguments evaluated when
the schedule is defined.  :catch-up SECONDS (a day) is how old a missed
occurrence may be and still run, once; NIL runs none (spec/jobs.md 8)."
  (parse-cron cron)                     ; a bad cron time fails the build
  (let ((catch-up (getf arguments :catch-up +default-catch-up+))
        (arguments (loop for (key value) on arguments by #'cddr
                         unless (eq key :catch-up) append (list key value))))
    `(progn
       (register-schedule
        (make-instance 'schedule :name ,(json-name-of name) :cron (parse-cron ,cron) :job ',job
                                 :arguments (list ,@arguments) :catch-up ,catch-up
                                 :module ,(current-definition-module)
                                 :location ,(current-source-location)))
       ',name)))

(defgeneric check-schedule (schedule)
  (:documentation "Signal an extension error when SCHEDULE cannot run in this image.")
  (:method ((schedule schedule))
    (let ((definition (find-job-definition (schedule-job schedule))))
      (unless definition
        (extension-error "Schedule ~a enqueues ~s, which is not a job kind"
                         (schedule-name schedule) (schedule-job schedule)))
      (handler-case (collecting-input-errors
                      (job-arguments-json definition (schedule-arguments schedule)))
        (operation-error (e)
          (extension-error "Schedule ~a gives ~s arguments it refuses: ~a"
                           (schedule-name schedule) (schedule-job schedule) e))))))

(defun check-schedules ()
  "Refuse to start when a schedule names a job kind that does not exist, or
arguments its job would refuse."
  (mapc #'check-schedule (schedules)))

(defgeneric run-occurrence (schedule)
  (:documentation "In a write transaction: do what an occurrence of SCHEDULE does.
Returns the jobs it enqueued.")
  (:method ((schedule schedule))
    (list (apply #'enqueue-job (schedule-job schedule) (schedule-arguments schedule)))))

;;; ------------------------------------------------------------------
;;; Runs

(define-entity job-schedule (:label "Schedule" :id-prefix "jsc" :table "job_schedules"
                                    :internal t :unique (("name")))
  ((name :type (string :max 100) :required t :input nil :label "Name")
   (first-seen-at :type timestamp :input nil :label "First seen"
                  :description "When a process first knew the schedule: earlier occurrences never run.")
   (last-occurrence :type (string :max 16) :input nil :label "Last occurrence"
                    :description "The wall-clock time of the latest occurrence recorded, such as 2026-10-21T07:00.")
   (last-occurrence-at :type timestamp :input nil :label "Last occurrence, instant")
   (last-job-id :type id :input nil :label "Last job")
   (last-enqueued :type (integer :min 0) :input nil :label "Jobs last enqueued"
                  :description "How many jobs the latest occurrence enqueued: one for a schedule, any number for a trigger.")))

(defun find-schedule-row (schedule)
  (select-one 'job-schedule :where `(:= "name" ,(schedule-name schedule))))

(defun occurrence-runs-p (schedule row at)
  "True when the occurrence at AT, not yet recorded in ROW, should enqueue
SCHEDULE's job: it is not from before the schedule was first seen, and it
is recent enough (spec/jobs.md 8)."
  (and (>= at (job-schedule-first-seen-at row))
       (<= (- (now) at) (or (schedule-catch-up schedule) +on-time-seconds+))))

(defun new-occurrence-p (row at key)
  "True when the occurrence KEY at AT comes after the one ROW records: its
instant is later than the recorded one's, so a change of the tenant's time
zone runs no occurrence twice nor one before the last (spec/jobs.md 8).  A
row with no recorded instant compares the keys."
  (let ((recorded-at (job-schedule-last-occurrence-at row)))
    (if recorded-at
        (and at (> at recorded-at))
        (not (equal key (job-schedule-last-occurrence row))))))

(defun record-occurrence (schedule at key)
  "In a write transaction: record SCHEDULE's occurrence KEY at AT unless it is
recorded already, running it when it should run.  True when it ran."
  (let ((row (find-schedule-row schedule)))
    (cond ((null row)
           ;; First sight: what happened before the schedule existed never runs.
           (insert (make-instance 'job-schedule :name (schedule-name schedule)
                                                :first-seen-at (now)
                                                :last-occurrence key :last-occurrence-at at))
           nil)
          ((not (new-occurrence-p row at key)) nil)
          (t (let ((runs (occurrence-runs-p schedule row at)))
               (setf (job-schedule-last-occurrence row) key
                     (job-schedule-last-occurrence-at row) at)
               (when runs
                 (let ((jobs (run-occurrence schedule)))
                   (setf (job-schedule-last-job-id row) (and jobs (entity-id (car (last jobs))))
                         (job-schedule-last-enqueued row) (length jobs))))
               (save row)
               runs)))))

(defun tend-schedule (schedule)
  "Run SCHEDULE's latest occurrence when that has not run.  True when it ran."
  (multiple-value-bind (at key) (previous-occurrence (schedule-cron schedule) (now))
    (let ((row (with-transaction (:read) (find-schedule-row schedule))))
      ;; Most ticks find the occurrence recorded and write nothing.
      (when (or (null row) (and key (new-occurrence-p row at key)))
        (with-transaction (:write)
          (record-occurrence schedule at key))))))

(defun tend-schedules ()
  "Run every schedule whose latest occurrence has not run, as
system:schedule.  Returns how many ran.  The tick calls it; so do
clock_set in test mode and the application when it opens."
  (with-actor ((system-actor "schedule"))
    (count-if #'tend-schedule (schedules))))

;;; ------------------------------------------------------------------
;;; Tools (spec/jobs.md 9)

(defgeneric schedule->json (schedule)
  (:documentation "SCHEDULE as schedules_list shows it.")
  (:method ((schedule schedule))
    (let ((row (find-schedule-row schedule))
          (json (jobj "name" (schedule-name schedule)
                      "kind" "schedule"
                      "cron" (cron-text (schedule-cron schedule))
                      "description" (describe-cron (schedule-cron schedule))
                      "job" (json-name-of (schedule-job schedule))
                      "catch_up" (or (schedule-catch-up schedule) :null))))
      (multiple-value-bind (at key) (next-occurrence (schedule-cron schedule) (now))
        (setf (gethash "next_occurrence" json) (or key :null)
              (gethash "next_occurrence_at" json) (if at (format-rfc3339 at) :null)))
      (setf (gethash "last_occurrence" json) (or (and row (job-schedule-last-occurrence row)) :null)
            (gethash "last_job_id" json) (or (and row (job-schedule-last-job-id row)) :null)
            (gethash "last_enqueued" json) (or (and row (job-schedule-last-enqueued row)) :null))
      json)))

(define-operation schedules-list ()
    (:entity job-schedule :kind :read :policy :admin :title "Schedules"
             :description "Each schedule and trigger: when it runs, in words and as cron in the
tenant's time zone, the job it queues, its last occurrence and job, and its next occurrence. A
trigger (kind trigger) also shows the entity it sweeps and how many jobs its last sweep queued.")
  (jobj "items" (jarr (mapcar #'schedule->json (schedules)))))

(define-operation schedules-run ((name :type (string :min 1 :max 100) :required t :label "Schedule"))
    (:entity job-schedule :kind :update :policy :admin :destructive nil :title "Run a schedule now"
             :description "Queues the schedule's job now, outside its times, or sweeps a
trigger's records now. Answers with the jobs it queued. The next occurrence runs as before.")
  (let ((schedule (or (find-schedule name)
                      (fail :not-found "There is no schedule ~a" name))))
    (jobj "jobs" (jarr (mapcar #'entity->json (run-occurrence schedule))))))
