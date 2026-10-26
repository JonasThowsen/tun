;;;; jobs/tools.lisp -- the admin tools for jobs (spec/jobs.md 9).

(in-package #:tun.jobs)

(declaim (optimize (safety 3) (debug 2)))

(define-operation jobs-list ((state :type (enum "queued" "running" "retrying" "succeeded" "failed"
                                                "cancelled")
                                    :label "Tilstand")
                             (kind :type (string :max 100) :label "Type")
                             (queue :type (string :max 64) :label "Kø"))
    (:entity job :kind :read :policy :admin :title "Jobber"
             :description "De siste 100 jobbene, nyeste først: type, kø, argumenter, tilstand,
forsøk, forfall og siste feil. Kan begrenses til én tilstand, type eller kø.")
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
    (:entity job :kind :read :policy :admin :title "Jobboversikt"
             :description "Hvordan bakgrunnsjobbene står: hvor mange i hver tilstand, hvor mange
som lyktes og feilet siste døgn, hver kø med grense, ventende, senere og kjørende jobber og den
eldste ventende, og prosessene som kjører jobber, om de lever og hvor mange de kjører nå.")
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

(define-operation jobs-get ((id :type (id job) :required t :label "Jobb"))
    (:entity job :kind :read :policy :admin :title "Les jobb"
             :description "Én jobb med argumentene og feilene fra hvert forsøk, hver med
forespørselen den kom fra (introspect_request).")
  (fetch! 'job id))

(define-operation jobs-retry ((id :type (id job) :required t :label "Jobb"))
    (:entity job :kind :update :policy :admin :title "Kjør jobb på nytt"
             :description "Legger en jobb som feilet eller ble avbrutt, i køen igjen, forfalt
nå og med forsøkene nullstilt. Feilene den hadde, beholdes.")
  (let ((job (fetch! 'job id)))
    (unless (member (job-state job) '("failed" "cancelled") :test #'string=)
      (fail :invalid-transition "Bare en jobb som feilet eller ble avbrutt, kan kjøres på nytt; denne er ~a"
            (job-state job)))
    (setf (job-state job) "queued"
          (job-attempts job) 0
          (job-due-at job) (now)
          (job-finished-at job) nil
          (job-note job) nil)
    (save job)))

(define-operation jobs-cancel ((id :type (id job) :required t :label "Jobb"))
    (:entity job :kind :update :policy :admin :title "Avbryt jobb"
             :description "Avbryter en jobb som venter i køen. En jobb som kjører nå, gjør
forsøket ferdig.")
  (let ((job (fetch! 'job id)))
    (unless (member (job-state job) '("queued" "retrying") :test #'string=)
      (fail :invalid-transition "Bare en jobb som venter, kan avbrytes; denne er ~a" (job-state job)))
    (setf (job-state job) "cancelled"
          (job-finished-at job) (now)
          (job-note job) (format nil "Avbrutt av ~a" (actor-string *actor*)))
    (save job)))
