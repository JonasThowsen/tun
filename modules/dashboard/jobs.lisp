;;;; modules/dashboard/jobs.lisp -- «Jobber»: an application's background
;;;; jobs and schedules (spec/jobs.md 9), as Hangfire's dashboard shows them.

(in-package #:tun.dashboard)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +states+
  '(("queued" "Venter" :secondary)
    ("running" "Kjører" :info)
    ("retrying" "Prøver igjen" :warning)
    ("failed" "Feilet" :destructive)
    ("succeeded" "Fullført" :success)
    ("cancelled" "Avbrutt" :outline))
  "Each job state: its name, its label, and its badge.")

;;; ------------------------------------------------------------------
;;; Pieces

(defun state-label (state) (or (second (assoc state +states+ :test #'string=)) state))

(defun state-badge (state)
  (ui:badge (:variant (or (third (assoc state +states+ :test #'string=)) :secondary))
    (state-label state)))

(defun occurrence-text (key)
  "An occurrence's key, a Norwegian wall-clock time such as 2026-03-01T10:00,
written as the page writes times: 01.03.2026 kl. 10:00; a dash for none."
  (if (and (stringp key) (= 16 (length key)))
      (format nil "~a.~a.~a kl. ~a" (subseq key 8 10) (subseq key 5 7) (subseq key 0 4)
              (subseq key 11 16))
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
           (format nil "forfaller ~a" (when-text (jget job "due_at"))))
          ((string= state "running") (format nil "startet ~a" (when-text (jget job "started_at"))))
          (t (when-text (jget job "finished_at"))))))

(defun dashboard-nav (current)
  "The links between the page's parts, CURRENT among them marked."
  (tab-buttons current '((:overview "Oversikt" "/jobber")
                         (:jobs "Jobber" "/jobber/liste")
                         (:schedules "Tidsplaner" "/jobber/tidsplaner"))
               :variant :outline))

(defun jobs-table (jobs &key (empty "Ingen jobber."))
  (ui:table (:columns '("Type" "Kø" "Tilstand" "Argumenter" "Forsøk" "Når" "Siste feil")
                      :rows (mapcar (lambda (job)
                                      (list (jget job "kind") (jget job "queue")
                                            (state-badge (jget job "state")) (arguments-text job)
                                            (format nil "~d av ~d" (jget job "attempts")
                                                    (jget job "max_attempts"))
                                            (job-time job)
                                            (let ((last (jget job "last_error")))
                                              (if (stringp last) (shortened last 80) "—"))))
                                    jobs)
                      :row-href (mapcar (lambda (job) (format nil "/jobber/~a" (jget job "id"))) jobs)
                      :empty empty)))

;;; ------------------------------------------------------------------
;;; Oversikt

(defun overview-stats (summary)
  (let ((states (jget summary "states"))
        (last-day (jget summary "last_day")))
    (ui:grid (:min :xs)
      (ui:stat (:label "Venter" :value (jget states "queued") :icon :clock))
      (ui:stat (:label "Kjører" :value (jget states "running") :icon :loader-circle))
      (ui:stat (:label "Prøver igjen" :value (jget states "retrying") :icon :circle-alert))
      (ui:stat (:label "Feilet" :value (jget states "failed") :icon :circle-x))
      (ui:stat (:label "Fullført siste døgn" :value (jget last-day "succeeded") :icon :circle-check))
      (ui:stat (:label "Feilet siste døgn" :value (jget last-day "failed") :icon :ban)))))

(defun queues-table (summary)
  (ui:table (:columns '("Kø" "Grense" "Venter" "Senere" "Kjører" "Eldste ventende")
                      :rows (mapcar (lambda (queue)
                                      (list (jget queue "name") (jget queue "limit")
                                            (jget queue "waiting") (jget queue "later")
                                            (jget queue "running")
                                            (when-text (jget queue "oldest_waiting_at"))))
                                    (items-of summary "queues"))
                      :empty "Ingen køer.")))

(defun processes-table (summary)
  (ui:table (:columns '("Prosess" "Startet" "Lever" "Kjører nå")
                      :rows (mapcar (lambda (process)
                                      (list (format nil "~a~:[~; (denne)~]" (jget process "id")
                                                    (eq t (jget process "own")))
                                            (when-text (jget process "started_at"))
                                            (if (eq t (jget process "alive"))
                                                (ui:badge (:variant :success) "Ja")
                                                (ui:badge (:variant :destructive) "Nei"))
                                            (jget process "running")))
                                    (items-of summary "processes"))
                      :empty "Ingen prosesser.")))

(defun overview-page ()
  (let ((summary (read-result "jobs_summary"))
        (failed (subseq-at-most (items-of (read-result "jobs_list" "state" "failed")) 5)))
    (values 200 "Jobber"
            (list (dashboard-nav :overview)
                  (overview-stats summary)
                  (ui:section (:title "Køer" :description "Hvor mange jobber hver kø kjører samtidig, og hva som venter.")
                    (queues-table summary))
                  (ui:section (:title "Prosesser" :description "Prosessene som kjører jobber. En prosess som ikke lever, har fått jobbene sine tatt over.")
                    (processes-table summary))
                  (ui:section (:title "Siste feil")
                    (jobs-table failed :empty "Ingen jobber har feilet.")))
            (list :description "Bakgrunnsjobbene: hva som venter, kjører og feilet, og tidsplanene."))))

;;; ------------------------------------------------------------------
;;; Jobber, one state at a time

(defun state-tabs (current counts)
  (tab-buttons current (loop for (state label) in +states+
                             collect (list state (format nil "~a (~d)" label (jget counts state))
                                           (format nil "/jobber/liste?tilstand=~a" state)))))

(defun list-page (query)
  (let* ((state (let ((asked (jget query "tilstand")))
                  (if (assoc asked +states+ :test #'equal) asked "queued")))
         (counts (jget (read-result "jobs_summary") "states")))
    (values 200 "Jobber"
            (list (dashboard-nav :jobs)
                  (state-tabs state counts)
                  (jobs-table (items-of (read-result "jobs_list" "state" state))
                              :empty (format nil "Ingen jobber som ~(~a~)." (state-label state))))
            (list :description "De siste 100 jobbene i tilstanden, nyeste først."
                  :breadcrumbs (list (list :label "Jobber" :href "/jobber")
                                     (list :label (state-label state)))))))

;;; ------------------------------------------------------------------
;;; One job

(defun attempt-entries (job)
  "JOB's failed attempts, newest first, as timeline entries."
  (reverse
   (map 'list (lambda (failure)
                (list :time (when-text (jget failure "at"))
                      :datetime (jget failure "at")
                      :actor (format nil "Forsøk ~d" (jget failure "attempt"))
                      :text (format nil "~a~@[ (forespørsel ~a)~]" (jget failure "error")
                                    (let ((request (jget failure "request_id")))
                                      (and (stringp request) request)))
                      :icon :circle-alert))
        (or (jget job "errors") #()))))

(defun job-actions (job)
  (let ((id (jget job "id"))
        (state (jget job "state")))
    (cond ((member state '("failed" "cancelled") :test #'string=)
           (post-button (format nil "/jobber/~a/kjor-igjen" id) "Kjør på nytt" :variant :primary))
          ((member state '("queued" "retrying") :test #'string=)
           (post-button (format nil "/jobber/~a/avbryt" id) "Avbryt")))))

(defun job-page (id &key error)
  (let ((job (read-result "jobs_get" "id" id)))
    (values 200 (jget job "kind")
            (list (when error (tun.web:error-alert error))
                  (ui:summary-list
                   (:rows (list (list "Tilstand" (state-badge (jget job "state")))
                                (list "Kø" (jget job "queue"))
                                (list "Forsøk" (format nil "~d av ~d" (jget job "attempts")
                                                       (jget job "max_attempts")))
                                (list "Lagt i kø" (format nil "~a av ~a" (when-text (jget job "enqueued_at"))
                                                          (jget job "enqueued_by")))
                                (list "Forfaller" (when-text (jget job "due_at")))
                                (list "Startet" (when-text (jget job "started_at")))
                                (list "Ferdig" (when-text (jget job "finished_at")))
                                (list "Prosess" (let ((process (jget job "claimed_by")))
                                                  (if (stringp process) process "—")))
                                (list "Merknad" (let ((note (jget job "note")))
                                                  (if (stringp note) note "—"))))))
                  (ui:section (:title "Argumenter")
                    (ui:code-block (:wrap t) (to-json-string (jget job "arguments"))))
                  (ui:section (:title "Forsøk som feilet")
                    (let ((entries (attempt-entries job)))
                      (if entries
                          (ui:timeline (:entries entries))
                          (ui:empty-state (:icon :circle-check :title "Ingen feil")))))
                  (job-actions job))
            (list :breadcrumbs (list (list :label "Jobber" :href "/jobber")
                                     (list :label (state-label (jget job "state"))
                                           :href (format nil "/jobber/liste?tilstand=~a" (jget job "state")))
                                     (list :label (jget job "id")))))))

;;; ------------------------------------------------------------------
;;; Tidsplaner

(defun trigger-p (schedule)
  (equal "trigger" (jget schedule "kind")))

(defun schedule-name-cell (schedule)
  "SCHEDULE's name, and for a trigger the entity whose records it goes through."
  (if (trigger-p schedule)
      (ui:cluster ()
        (jget schedule "name")
        (ui:badge (:variant :secondary) (format nil "utløser på ~a" (jget schedule "entity"))))
      (jget schedule "name")))

(defun last-occurrence-text (schedule)
  "When SCHEDULE last ran, and for a trigger how many jobs that sweep enqueued."
  (let ((text (occurrence-text (jget schedule "last_occurrence")))
        (enqueued (jget schedule "last_enqueued")))
    (if (and (trigger-p schedule) (integerp enqueued))
        (format nil "~a (~d ~:*~[jobber~;jobb~:;jobber~])" text enqueued)
        text)))

(defun schedules-page (&key error)
  (let ((schedules (items-of (read-result "schedules_list"))))
    (values 200 "Tidsplaner"
            (list (dashboard-nav :schedules)
                  (when error (tun.web:error-alert error))
                  (ui:table (:columns '("Tidsplan" "Når" "Cron" "Jobb" "Sist" "Neste" "")
                                      :rows (mapcar (lambda (schedule)
                                                      (list (schedule-name-cell schedule)
                                                            (jget schedule "description")
                                                            (jget schedule "cron")
                                                            (jget schedule "job")
                                                            (last-occurrence-text schedule)
                                                            (when-text (jget schedule "next_occurrence_at"))
                                                            (post-button (format nil "/jobber/tidsplaner/~a/kjor"
                                                                                 (jget schedule "name"))
                                                                         "Kjør nå")))
                                                    schedules)
                                      :empty "Ingen tidsplaner.")))
            (list :description "Jobbene som legges i køen etter klokken, i norsk tid, og utløserne, som legger en jobb i køen for hver post som oppfyller et vilkår."
                  :breadcrumbs (list (list :label "Jobber" :href "/jobber")
                                     (list :label "Tidsplaner"))))))

;;; ------------------------------------------------------------------
;;; The page

(tun.web:define-page jobs-page ("jobber" :title "Jobber" :icon :layout-dashboard :policy :admin
                                     :group :system)
    (method path form query)
  (destructuring-bind (&optional first second third &rest more) path
    (cond (more (fail :not-found "Siden finnes ikke"))
          ((null first) (overview-page))
          ((and (string= first "liste") (null second)) (list-page query))
          ((and (string= first "tidsplaner") (null second)) (schedules-page))
          ((and (string= first "tidsplaner") (equal third "kjor") (eq method :post))
           (change "schedules_run" (jobj "name" second) "/jobber/liste?tilstand=queued"
                   (lambda (error) (schedules-page :error error))))
          ((and (null second) (eq method :get)) (job-page first))
          ((and (member second '("kjor-igjen" "avbryt") :test #'equal) (null third) (eq method :post))
           (change (if (string= second "avbryt") "jobs_cancel" "jobs_retry") (jobj "id" first)
                   (format nil "/jobber/~a" first)
                   (lambda (error) (job-page first :error error))))
          (t (fail :not-found "Siden finnes ikke")))))
