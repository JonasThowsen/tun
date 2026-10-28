;;;; modules/dashboard/jobs.lisp -- "Jobs": an application's background
;;;; jobs and schedules (spec/jobs.md 9), as Hangfire's dashboard shows them.

(in-package #:tun.dashboard)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +states+
  '(("queued" :secondary)
    ("running" :info)
    ("retrying" :warning)
    ("failed" :destructive)
    ("succeeded" :success)
    ("cancelled" :outline))
  "Each job state: its name and its badge.")

;;; ------------------------------------------------------------------
;;; Pieces

(defun state-label (state)
  "The label of the job state STATE in the current language: Queued, Venter."
  (render-text (label "job" "state" state)))

(defun state-badge (state)
  (ui:badge (:variant (or (second (assoc state +states+ :test #'string=)) :secondary))
    (state-label state)))

(defun occurrence-text (key)
  "An occurrence's key, a wall-clock time in the tenant's zone such as
2026-03-01T10:00, written as the page writes instants: 1 Mar 2026, 10:00;
a dash for none.  A time the clock shows twice is the earlier instant."
  (if (and (stringp key) (= 16 (length key)) (valid-date-string-p (subseq key 0 10)))
      (multiple-value-bind (instant kind earlier)
          (local-instant (subseq key 0 10) (parse-integer key :start 11 :end 13)
                         (parse-integer key :start 14 :end 16))
        (let ((at (or instant (and (eq kind :ambiguous) earlier))))
          (if at (instant-text at) key)))
      "—"))

(defun arguments-text (job)
  (let ((arguments (jget job "arguments")))
    (if (and (hash-table-p arguments) (plusp (hash-table-count arguments)))
        (shortened (to-json-string arguments) 60)
        "—")))

(defun job-time (job)
  "The time that matters in JOB's state: when it is due, started or finished."
  (let ((state (jget job "state")))
    (cond ((member state '("queued" "retrying") :test #'string=)
           (tr "due ~a" (when-text (jget job "due_at"))))
          ((string= state "running") (tr "started ~a" (when-text (jget job "started_at"))))
          (t (when-text (jget job "finished_at"))))))

(defun dashboard-nav (current)
  "The links between the page's parts, CURRENT among them marked."
  (tab-buttons current (list (list :overview (tr "Overview") "/jobs")
                             (list :jobs (tr "Jobs") "/jobs/list")
                             (list :schedules (tr "Schedules") "/jobs/schedules"))
               :variant :outline))

(defun attempts-text (job)
  (tr "~d of ~d" (jget job "attempts") (jget job "max_attempts")))

(defun jobs-table (jobs &key (empty (tr "No jobs.")))
  (ui:table (:columns (list (tr "Kind") (tr "Queue") (tr "State") (tr "Arguments") (tr "Attempts")
                            (tr "When") (tr "Last error"))
                      :rows (mapcar (lambda (job)
                                      (list (jget job "kind") (jget job "queue")
                                            (state-badge (jget job "state")) (arguments-text job)
                                            (attempts-text job)
                                            (job-time job)
                                            (let ((last (jget job "last_error")))
                                              (if (stringp last) (shortened last 80) "—"))))
                                    jobs)
                      :row-href (mapcar (lambda (job) (format nil "/jobs/~a" (jget job "id"))) jobs)
                      :empty empty)))

;;; ------------------------------------------------------------------
;;; The overview

(defun overview-stats (summary)
  (let ((states (jget summary "states"))
        (last-day (jget summary "last_day")))
    (ui:grid (:min :xs)
      (ui:stat (:label (state-label "queued") :value (jget states "queued") :icon :clock))
      (ui:stat (:label (state-label "running") :value (jget states "running") :icon :loader-circle))
      (ui:stat (:label (state-label "retrying") :value (jget states "retrying")
                       :icon :circle-alert))
      (ui:stat (:label (state-label "failed") :value (jget states "failed") :icon :circle-x))
      (ui:stat (:label (tr "Succeeded in the last day") :value (jget last-day "succeeded")
                       :icon :circle-check))
      (ui:stat (:label (tr "Failed in the last day") :value (jget last-day "failed") :icon :ban)))))

(defun queues-table (summary)
  (ui:table (:columns (list (tr "Queue") (tr ("Limit" :context "queue")) (tr "Waiting")
                            (tr "Later") (tr "Running") (tr "Oldest waiting"))
                      :rows (mapcar (lambda (queue)
                                      (list (jget queue "name") (jget queue "limit")
                                            (jget queue "waiting") (jget queue "later")
                                            (jget queue "running")
                                            (when-text (jget queue "oldest_waiting_at"))))
                                    (items-of summary "queues"))
                      :empty (tr "No queues."))))

(defun processes-table (summary)
  (ui:table (:columns (list (tr "Process") (tr "Started") (tr "Alive") (tr "Running now"))
                      :rows (mapcar (lambda (process)
                                      (list (tr "~a~:[~; (this one)~]" (jget process "id")
                                                (eq t (jget process "own")))
                                            (when-text (jget process "started_at"))
                                            (let ((alive (eq t (jget process "alive"))))
                                              (ui:badge (:variant (if alive :success :destructive))
                                                (yes-no-text alive)))
                                            (jget process "running")))
                                    (items-of summary "processes"))
                      :empty (tr "No processes."))))

(defun overview-page ()
  (let ((summary (read-result "jobs_summary"))
        (failed (subseq-at-most (items-of (read-result "jobs_list" "state" "failed")) 5)))
    (values 200 (tr "Jobs")
            (list (dashboard-nav :overview)
                  (overview-stats summary)
                  (ui:section (:title (tr "Queues")
                                      :description (tr "How many jobs each queue runs at once, and what is waiting."))
                    (queues-table summary))
                  (ui:section (:title (tr "Processes")
                                      :description (tr "The processes that run jobs. A process that is not alive has had its jobs taken over."))
                    (processes-table summary))
                  (ui:section (:title (tr "Recent failures"))
                    (jobs-table failed :empty (tr "No job has failed."))))
            (list :description
                  (tr "The background jobs: what is waiting, running and failed, and the schedules.")))))

;;; ------------------------------------------------------------------
;;; The jobs, one state at a time

(defun state-tabs (current counts)
  (tab-buttons current (loop for (state) in +states+
                             collect (list state (format nil "~a (~d)" (state-label state)
                                                         (jget counts state))
                                           (format nil "/jobs/list?state=~a" state)))))

(defun list-page (query)
  (let* ((state (let ((asked (jget query "state")))
                  (if (assoc asked +states+ :test #'equal) asked "queued")))
         (counts (jget (read-result "jobs_summary") "states")))
    (values 200 (tr "Jobs")
            (list (dashboard-nav :jobs)
                  (state-tabs state counts)
                  (jobs-table (items-of (read-result "jobs_list" "state" state))
                              :empty (tr "No jobs that are ~(~a~)." (state-label state))))
            (list :description (tr "The last 100 jobs in the state, newest first.")
                  :breadcrumbs (list (list :label (tr "Jobs") :href "/jobs")
                                     (list :label (state-label state)))))))

;;; ------------------------------------------------------------------
;;; One job

(defun attempt-entries (job)
  "JOB's failed attempts, newest first, as timeline entries."
  (reverse
   (map 'list (lambda (failure)
                (list :time (when-text (jget failure "at"))
                      :datetime (jget failure "at")
                      :actor (tr "Attempt ~d" (jget failure "attempt"))
                      :text (tr "~a~@[ (request ~a)~]" (jget failure "error")
                                (let ((request (jget failure "request_id")))
                                  (and (stringp request) request)))
                      :icon :circle-alert))
        (or (jget job "errors") #()))))

(defun job-actions (job)
  (let ((id (jget job "id"))
        (state (jget job "state")))
    (cond ((member state '("failed" "cancelled") :test #'string=)
           (post-button (format nil "/jobs/~a/retry" id) (tr "Run again") :variant :primary))
          ((member state '("queued" "retrying") :test #'string=)
           (post-button (format nil "/jobs/~a/cancel" id) (tr "Cancel"))))))

(defun job-page (id &key error)
  (let ((job (read-result "jobs_get" "id" id)))
    (values 200 (jget job "kind")
            (list (when error (tun.web:error-alert error))
                  (ui:summary-list
                   (:rows (list (list (tr "State") (state-badge (jget job "state")))
                                (list (tr "Queue") (jget job "queue"))
                                (list (tr "Attempts") (attempts-text job))
                                (list (tr "Enqueued")
                                      (tr "~a by ~a" (when-text (jget job "enqueued_at"))
                                          (jget job "enqueued_by")))
                                (list (tr "Due at") (when-text (jget job "due_at")))
                                (list (tr "Started") (when-text (jget job "started_at")))
                                (list (tr "Finished") (when-text (jget job "finished_at")))
                                (list (tr "Process") (let ((process (jget job "claimed_by")))
                                                       (if (stringp process) process "—")))
                                (list (tr "Note") (let ((note (jget job "note")))
                                                    (if (stringp note) note "—"))))))
                  (ui:section (:title (tr "Arguments"))
                    (ui:code-block (:wrap t) (to-json-string (jget job "arguments"))))
                  (ui:section (:title (tr "Failed attempts"))
                    (let ((entries (attempt-entries job)))
                      (if entries
                          (ui:timeline (:entries entries))
                          (ui:empty-state (:icon :circle-check :title (tr "No errors"))))))
                  (job-actions job))
            (list :breadcrumbs (list (list :label (tr "Jobs") :href "/jobs")
                                     (list :label (state-label (jget job "state"))
                                           :href (format nil "/jobs/list?state=~a" (jget job "state")))
                                     (list :label (jget job "id")))))))

;;; ------------------------------------------------------------------
;;; Schedules

(defun trigger-p (schedule)
  (equal "trigger" (jget schedule "kind")))

(defun schedule-name-cell (schedule)
  "SCHEDULE's name, and for a trigger the entity whose records it goes through."
  (if (trigger-p schedule)
      (ui:cluster ()
        (jget schedule "name")
        (ui:badge (:variant :secondary) (tr "trigger on ~a" (jget schedule "entity"))))
      (jget schedule "name")))

(defun last-occurrence-text (schedule)
  "When SCHEDULE last ran, and for a trigger how many jobs that sweep enqueued."
  (let ((text (occurrence-text (jget schedule "last_occurrence")))
        (enqueued (jget schedule "last_enqueued")))
    (if (and (trigger-p schedule) (integerp enqueued))
        (tr "~a (~d job~:p)" text enqueued)
        text)))

(defun schedules-page (&key error)
  (let ((schedules (items-of (read-result "schedules_list"))))
    (values 200 (tr "Schedules")
            (list (dashboard-nav :schedules)
                  (when error (tun.web:error-alert error))
                  (ui:table (:columns (list (tr "Schedule") (tr "When") (tr "Cron") (tr "Job")
                                            (tr "Last") (tr "Next") "")
                                      :rows (mapcar (lambda (schedule)
                                                      (list (schedule-name-cell schedule)
                                                            (jget schedule "description")
                                                            (jget schedule "cron")
                                                            (jget schedule "job")
                                                            (last-occurrence-text schedule)
                                                            (when-text (jget schedule "next_occurrence_at"))
                                                            (post-button (format nil "/jobs/schedules/~a/run"
                                                                                 (jget schedule "name"))
                                                                         (tr "Run now"))))
                                                    schedules)
                                      :empty (tr "No schedules."))))
            (list :description (tr "The jobs queued by the clock, in local time, and the triggers, which queue a job for each record that meets a condition.")
                  :breadcrumbs (list (list :label (tr "Jobs") :href "/jobs")
                                     (list :label (tr "Schedules")))))))

;;; ------------------------------------------------------------------
;;; The page

(tun.web:define-page jobs-page ("jobs" :title "Jobs" :icon :layout-dashboard :policy :admin
                                     :group :system)
    (method path form query)
  (destructuring-bind (&optional first second third &rest more) path
    (cond (more (fail :not-found "The page does not exist"))
          ((null first) (overview-page))
          ((and (string= first "list") (null second)) (list-page query))
          ((and (string= first "schedules") (null second)) (schedules-page))
          ((and (string= first "schedules") (equal third "run") (eq method :post))
           (change "schedules_run" (jobj "name" second) "/jobs/list?state=queued"
                   (lambda (error) (schedules-page :error error))))
          ((and (null second) (eq method :get)) (job-page first))
          ((and (member second '("retry" "cancel") :test #'equal) (null third) (eq method :post))
           (change (if (string= second "cancel") "jobs_cancel" "jobs_retry") (jobj "id" first)
                   (format nil "/jobs/~a" first)
                   (lambda (error) (job-page first :error error))))
          (t (fail :not-found "The page does not exist")))))
