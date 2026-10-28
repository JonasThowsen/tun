;;;; jobs/tools.lisp -- the admin tools for jobs (spec/jobs.md 9).

(in-package #:tun.jobs)

(declaim (optimize (safety 3) (debug 2)))

(define-operation jobs-list ((state :type (enum "queued" "running" "retrying" "succeeded" "failed"
                                                "cancelled")
                                    :label "State")
                             (kind :type (string :max 100) :label "Kind")
                             (queue :type (string :max 64) :label "Queue"))
    (:entity job :kind :read :policy :admin :title "Jobs"
             :description "The latest 100 jobs, newest first: kind, queue, arguments, state,
attempts, due time and last error. It can be narrowed to one state, kind or queue.")
  (let ((conditions (remove nil (list (and state `(:= "state" ,state))
                                      (and kind `(:= "kind" ,kind))
                                      (and queue `(:= "queue" ,queue))))))
    (jobj "items" (jarr (mapcar #'entity->json
                                (select 'job :where (and conditions `(:and ,@conditions))
                                             :order-by '(("seq" :desc)) :limit 100))))))

(defun queue-summary (queue)
  "QUEUE, a queue name, as jobs_summary shows it."
  (let ((waiting (select 'job :where (due-job-condition queue)))
        (later (select 'job :where `(:and (:in "state" ("queued" "retrying")) (:> "due_at" ,(now))
                                          (:= "queue" ,queue))))
        (running (select 'job :where `(:and (:= "state" "running") (:= "queue" ,queue)))))
    (jobj "name" queue
          "limit" (application-queue-limit *application* (intern (string-upcase queue) :keyword))
          "waiting" (length waiting)
          "later" (length later)
          "running" (length running)
          "oldest_waiting_at" (if waiting
                                  (format-rfc3339 (reduce #'min (mapcar #'job-due-at waiting)))
                                  :null))))

(defun process-summary (process)
  (let ((own (equal (entity-id process) (process-id))))
    (jobj "id" (entity-id process)
          "started_at" (format-rfc3339 (job-process-started-at process))
          "own" (json-bool own)
          "alive" (json-bool (or own (store-present-p *store* (job-process-lock-key process))))
          "running" (length (select 'job :where `(:and (:= "state" "running")
                                                       (:= "claimed_by" ,(entity-id process))))))))

(define-operation jobs-summary ()
    (:entity job :kind :read :policy :admin :title "Jobs overview"
             :description "How the background jobs stand: how many in each state, how many
succeeded and failed in the last day, each queue with its limit, its waiting, later and running
jobs and the oldest waiting, and the processes that run jobs, whether they live and how many they
run now.")
  (let ((day-ago (- (now) 86400)))
    (flet ((count-where (where) (length (select 'job :where where))))
      (jobj "states" (let ((states (jobj)))
                       (dolist (state '("queued" "running" "retrying" "succeeded" "failed" "cancelled")
                                      states)
                         (setf (gethash state states) (count-where `(:= "state" ,state)))))
            "last_day" (jobj "succeeded" (count-where `(:and (:= "state" "succeeded")
                                                             (:>= "finished_at" ,day-ago)))
                             "failed" (count-where `(:and (:= "state" "failed")
                                                          (:>= "finished_at" ,day-ago))))
            "queues" (jarr (mapcar #'queue-summary
                                   (sort (remove-duplicates
                                          (append (mapcar #'queue-name (known-queues))
                                                  (mapcar #'job-queue (select 'job :where '(:in "state" ("queued" "running" "retrying")))))
                                          :test #'string=)
                                         #'string<)))
            "processes" (jarr (mapcar #'process-summary
                                      (select 'job-process :order-by '(("seq" :asc)))))))))

(define-operation jobs-get ((id :type (id job) :required t :label "Job"))
    (:entity job :kind :read :policy :admin :title "Read a job"
             :description "One job with its arguments and the errors of each attempt, each with
the request it came from (introspect_request).")
  (fetch! 'job id))

(define-operation jobs-retry ((id :type (id job) :required t :label "Job"))
    (:entity job :kind :update :policy :admin :title "Run a job again"
             :description "Queues a job that failed or was cancelled again, due now and with
its attempts set to zero. The errors it had are kept.")
  (let ((job (fetch! 'job id)))
    (unless (member (job-state job) '("failed" "cancelled") :test #'string=)
      (fail :invalid-transition "Only a job that failed or was cancelled can run again; this one is ~a"
            (label "job" "state" (job-state job))))
    (setf (job-state job) "queued"
          (job-attempts job) 0
          (job-due-at job) (now)
          (job-finished-at job) nil
          (job-note job) nil)
    (save job)))

(define-operation jobs-cancel ((id :type (id job) :required t :label "Job"))
    (:entity job :kind :update :policy :admin :title "Cancel a job"
             :description "Cancels a job waiting in its queue. A job running now finishes its
attempt.")
  (let ((job (fetch! 'job id)))
    (unless (member (job-state job) '("queued" "retrying") :test #'string=)
      (fail :invalid-transition "Only a waiting job can be cancelled; this one is ~a"
            (label "job" "state" (job-state job))))
    (setf (job-state job) "cancelled"
          (job-finished-at job) (now)
          (job-note job) (tr "Cancelled by ~a" (actor-string *actor*)))
    (save job)))
