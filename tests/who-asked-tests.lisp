;;;; tests/who-asked-tests.lisp -- who asked for a job or a workflow
;;;; (spec/jobs.md 3.1): a workflow records who planned it, every run job of
;;;; it names the planner however it came to be queued, and a job run again
;;;; keeps who first asked.  The erasure (modules/customers README 5.1) is
;;;; the work that asks, so each case is told by whether a customer is erased.

(in-package #:tun.tests)
(def-suite who-asked :in core)
(in-suite who-asked)

;;; ------------------------------------------------------------------
;;; Work the tests ask for

(tun.jobs:define-job erase-on-second-attempt-job ((customer-id :type string :required t))
    (:max-attempts 3 :backoff (30))
  (when (= 1 (tun.jobs:job-attempts (tun.jobs:running-job)))
    (error "Not yet"))
  (tun.customers:erase-customer customer-id))

(tun.jobs:define-job erase-after-snooze-job ((customer-id :type string :required t)) ()
  (when (zerop (tun.jobs:job-snoozes (tun.jobs:running-job)))
    (tun.jobs:snooze-job 60))
  (tun.customers:erase-customer customer-id))

(tun.jobs:define-job erase-customer-once-job ((customer-id :type string :required t))
    (:max-attempts 1)
  (tun.customers:erase-customer customer-id))

(tun.jobs:define-job plan-erasure-job ((customer-id :type string :required t)) ()
  (tun.workflows:schedule-workflow "test_erase_customer" :subject-id customer-id
                                                         :due-at (now)))

(tun.jobs:define-job plan-named-erasure-job () ()
  (dolist (customer (select 'tun.customers:customer :where '(:= "name" "Scheduled Person")))
    (tun.workflows:schedule-workflow "test_erase_customer" :subject-id (entity-id customer)
                                                           :due-at (now))))

(define-workflow erase-planned-later (:kind "test_erase_later" :label "Erase later") (wf)
  (tun.workflows:schedule-workflow "test_erase_customer"
                                   :subject-id (tun.workflows:workflow-subject-id wf)
                                   :due-at (+ (now) 3600)))

(define-operation plan-erasure-in ((id :type string :required t)
                                   (in :type integer)
                                   (follow-up :type boolean))
    (:kind :update :policy :employee :title "Plan an erasure for later")
  (tun.workflows:schedule-workflow (if follow-up "test_erase_later" "test_erase_customer")
                                   :subject-id id :due-at (+ (now) (or in 0)))
  (jobj "id" id))

(define-operation plan-erasure-as-system ((id :type string :required t))
    (:kind :update :policy :employee :title "Plan an erasure under a system actor")
  (with-actor ((system-actor "sneaky"))
    (tun.workflows:schedule-workflow "test_erase_customer" :subject-id id
                                                           :due-at (+ (now) 3600)))
  (jobj "id" id))

(define-operation queue-erasure-to-run-again ((id :type string :required t)
                                              (how :type (enum "retry" "snooze" "once")
                                                   :required t))
    (:kind :update :policy :employee :title "Queue an erasure that runs again")
  (tun.jobs:enqueue-job (cond ((equal how "retry") 'erase-on-second-attempt-job)
                              ((equal how "snooze") 'erase-after-snooze-job)
                              (t 'erase-customer-once-job))
                        :customer-id id)
  (jobj "id" id))

(define-operation queue-chained-erasure-as-system ((id :type string :required t))
    (:kind :update :policy :employee :title "Queue a chained erasure under a system actor")
  (with-actor ((system-actor "sneaky"))
    (tun.jobs:enqueue-job 'queue-erasure-job :customer-id id))
  (jobj "id" id))

;;; ------------------------------------------------------------------
;;; Looking

(defun erasure-workflows (id)
  "The erasure workflows of the customer ID, as workflows_list gives them,
oldest due first."
  (remove-if-not (lambda (workflow) (equal id (jget workflow "subject_id")))
                 (coerce (jget (call-ok "workflows_list" "viewer:v" "kind" "test_erase_customer")
                               "items")
                         'list)))

(defun run-jobs-of (workflow-id)
  "The run_workflow jobs of the workflow WORKFLOW-ID, oldest first, as JSON."
  (reverse (remove-if-not (lambda (job) (equal workflow-id (jget (jget job "arguments")
                                                                 "workflow_id")))
                          (coerce (jget (call-ok "jobs_list" "admin:root" "kind" "run_workflow")
                                        "items")
                                  'list))))

(defun jobs-of-kind (kind)
  "The jobs of KIND, a kind string, oldest first, as JSON."
  (reverse (coerce (jget (call-ok "jobs_list" "admin:root" "kind" kind) "items") 'list)))

(defun refused-runs (id runs)
  "Check the customer ID is not erased, with RUNS rejected entries and no ok one."
  (is (not (erased-p id)) "~a is not erased" id)
  (is (= runs (length (customer-entries id "rejected")))
      "~a: ~d rejected entries: ~a" id runs (customer-entries id "rejected"))
  (is (equal '("forbidden") (remove-duplicates (mapcar (lambda (entry) (jget entry "error_code"))
                                                       (customer-entries id "rejected"))
                                               :test #'equal)))
  (is (null (customer-entries id "ok"))))

(defun erased-once (id)
  "Check the customer ID is erased, audited ok once."
  (is (erased-p id) "~a is erased" id)
  (is (= 1 (length (customer-entries id "ok"))) "~a: one ok entry" id))

(defun end-run-jobs-for-good ()
  "End every waiting run_workflow job for good while its workflow stays
planned, as the third crash of its process leaves it."
  (with-application (*app*)
    (with-transaction (:write)
      (dolist (job (select 'tun.jobs:job :where '(:and (:= "kind" "run_workflow")
                                                       (:in "state" ("queued" "retrying")))))
        (setf (tun.jobs:job-state job) "failed"
              (tun.jobs:job-attempts job) 3
              (tun.jobs:job-finished-at job) (now)
              (tun.jobs:job-note job) "The process stopped mid-attempt")
        (save job)))))

(defun set-run-job-asker (workflow-id text)
  "Make the waiting run job of WORKFLOW-ID name TEXT as who asked, as a
job an earlier core queued again at start does."
  (with-application (*app*)
    (with-transaction (:write)
      (dolist (job (select 'tun.jobs:job :where '(:and (:= "kind" "run_workflow")
                                                       (:in "state" ("queued" "retrying")))))
        (when (equal workflow-id (jget (tun.jobs:job-arguments job) "workflow_id"))
          (setf (tun.jobs:job-enqueued-by job) text)
          (save job))))))

(defun reopen-application ()
  "Close the application and open it again on the same database, as a
restart does."
  (let ((db (tun.store.sqlite:sqlite-store-path (application-store *app*))))
    (tun.runtime:close-application *app*)
    (setf *app* (tun.runtime:open-application 'application :db db :test-clock t))))

;;; ------------------------------------------------------------------
;;; Who planned it

(test a-workflow-records-who-planned-it
  (with-test-app ()
    (let ((employee (make-customer "Planned By Anna"))
          (disguised (make-customer "Planned Disguised"))
          (chained (make-customer "Planned In A Job"))
          (kernel (make-customer "Planned By Kernel")))
      (call-ok "plan_erasure_in" "employee:anna" "id" employee "in" 3600)
      (call-ok "plan_erasure_as_system" "employee:anna" "id" disguised)
      (queue-as "admin:ada" 'plan-erasure-job :customer-id chained)
      (with-application (*app*)
        (with-transaction (:write)
          (tun.workflows:schedule-workflow "test_erase_customer" :subject-id kernel
                                                                 :due-at (+ (now) 3600))))
      (loop for (id asker) in `((,employee "employee:anna") (,disguised "employee:anna")
                                (,kernel "system"))
            for workflow = (first (erasure-workflows id))
            do (is (equal asker (jget workflow "planned_by"))
                   "~a planned by ~a: ~a" id asker (jget workflow "planned_by"))
               (is (equal (list asker) (mapcar (lambda (job) (jget job "enqueued_by"))
                                               (run-jobs-of (jget workflow "id"))))
                   "its run job names the planner")
               (is (equal asker (jget (call-ok "workflows_get" "viewer:v"
                                               "id" (jget workflow "id"))
                                      "planned_by"))))
      (drain-jobs)
      (is (equal "admin:ada" (jget (first (erasure-workflows chained)) "planned_by"))
          "a workflow planned in a job names who asked for the job")
      (erased-once chained))))

(test a-workflow-queued-again-at-start-is-still-its-planners
  ;; Its run job ended for good (three crashes) while it stayed planned, so
  ;; the application queues it again when it opens.
  (with-test-app (:db (scratch-path "who-asked-requeue"))
    (let ((refused (make-customer "Requeued Employee"))
          (allowed (make-customer "Requeued Admin")))
      (call-ok "plan_erasure_in" "employee:anna" "id" refused "in" 3600)
      (call-ok "plan_erasure_in" "admin:ada" "id" allowed "in" 3600)
      (end-run-jobs-for-good)
      (reopen-application)
      (loop for (id asker) in `((,refused "employee:anna") (,allowed "admin:ada"))
            for jobs = (run-jobs-of (jget (first (erasure-workflows id)) "id"))
            do (is (= 2 (length jobs)) "a new run job for ~a" id)
               (is (equal asker (jget (car (last jobs)) "enqueued_by"))
                   "queued again at start, it names the planner, ~a: ~a"
                   asker (jget (car (last jobs)) "enqueued_by")))
      (set-clock-ahead 7200)
      (refused-runs refused 1)
      (is (equal "failed" (jget (first (erasure-workflows refused)) "status")))
      (erased-once allowed))))

(test a-run-job-that-names-another-runs-as-the-planner
  ;; A waiting run job whose row names someone else, as an earlier core's
  ;; requeue at start named the system: its body puts the planner back.
  (with-test-app ()
    (let ((refused (make-customer "Stale Employee"))
          (allowed (make-customer "Stale Admin")))
      (call-ok "plan_erasure_in" "employee:anna" "id" refused "in" 3600)
      (call-ok "plan_erasure_in" "admin:ada" "id" allowed "in" 3600)
      (dolist (id (list refused allowed))
        (set-run-job-asker (jget (first (erasure-workflows id)) "id") "system:reconcile"))
      (set-clock-ahead 7200)
      (refused-runs refused 1)
      (is (equal '("employee:anna")
                 (mapcar (lambda (job) (jget job "enqueued_by"))
                         (run-jobs-of (jget (first (erasure-workflows refused)) "id"))))
          "the job's row names the planner again")
      (erased-once allowed))))

(test a-workflow-from-before-has-nobody-who-asked
  (with-each-durable-store (store db "who-asked-before")
    (let (before follow after)
      (with-test-app (:db db)
        (setf before (make-customer "Before Person")
              follow (make-customer "Before Follow Person"))
        (call-ok "plan_erasure_in" "admin:ada" "id" before "in" 3600)
        (call-ok "plan_erasure_in" "admin:ada" "id" follow "in" 3600 "follow_up" t)
        ;; A database from before core 2.45.0: no planned_by.
        (with-application (*app*)
          (with-transaction (:write)
            (raw-sql "ALTER TABLE workflows DROP COLUMN planned_by"))))
      (with-test-app (:db db)
        (with-application (*app*)
          (is (member "planned_by" (table-columns "workflows") :test #'string=)
              "~a: the column is added when the application opens" store))
        (let ((workflow (first (erasure-workflows before))))
          (is (eq :null (jget workflow "planned_by")) "~a: nobody recorded" store))
        (set-clock-ahead 7200)
        (is (eq :null (jget (first (erasure-workflows follow)) "planned_by"))
            "~a: a follow-up a run with nobody planned names nobody" store)
        (set-clock-ahead 7200)
        (refused-runs before 1)
        (refused-runs follow 1)
        (is (equal '("system:workflow")
                   (mapcar (lambda (entry) (jget entry "actor"))
                           (customer-entries before "rejected")))
            "~a: audited as the run, never as who asked" store)
        (is (equal "failed" (jget (first (erasure-workflows before)) "status")))
        (let ((jobs (run-jobs-of (jget (first (erasure-workflows before)) "id"))))
          (is (eq :null (jget (car (last jobs)) "enqueued_by"))
              "~a: its job names nobody, not the system: ~a"
              store (jget (car (last jobs)) "enqueued_by")))
        (setf after (make-customer "After Person"))
        (call-ok "plan_erasure_in" "admin:ada" "id" after)
        (drain-jobs)
        (erased-once after)))))

;;; ------------------------------------------------------------------
;;; Run again, still who asked

(test a-job-run-again-is-still-who-asked
  (with-test-app ()
    (dolist (how '("retry" "snooze"))
      (let ((refused (make-customer (format nil "Again Employee ~a" how)))
            (allowed (make-customer (format nil "Again Admin ~a" how))))
        (call-ok "queue_erasure_to_run_again" "employee:anna" "id" refused "how" how)
        (call-ok "queue_erasure_to_run_again" "admin:ada" "id" allowed "how" how)
        (drain-jobs)
        (is (not (erased-p refused)) "~a: not on the first run" how)
        (set-clock-ahead 120)
        (refused-runs refused 1)
        (erased-once allowed)))))

(test a-workflow-run-later-is-still-its-planners
  (with-test-app ()
    (let ((timer-refused (make-customer "Timer Employee"))
          (timer-allowed (make-customer "Timer Admin"))
          (follow-refused (make-customer "Follow Employee"))
          (follow-allowed (make-customer "Follow Admin"))
          (crash-refused (make-customer "Crash Employee"))
          (crash-allowed (make-customer "Crash Admin")))
      (call-ok "plan_erasure_in" "employee:anna" "id" timer-refused "in" (* 2 86400))
      (call-ok "plan_erasure_in" "admin:ada" "id" timer-allowed "in" (* 2 86400))
      (call-ok "plan_erasure_in" "employee:anna" "id" follow-refused "follow_up" t)
      (call-ok "plan_erasure_in" "admin:ada" "id" follow-allowed "follow_up" t)
      (call-ok "plan_erasure_in" "employee:anna" "id" crash-refused "in" 3600)
      (call-ok "plan_erasure_in" "admin:ada" "id" crash-allowed "in" 3600)
      ;; The crash cases' run jobs stop mid-attempt on a process that is gone.
      (with-application (*app*)
        (with-transaction (:write)
          (dolist (id (list crash-refused crash-allowed))
            (let ((job (fetch 'tun.jobs:job
                              (jget (first (run-jobs-of (jget (first (erasure-workflows id)) "id")))
                                    "id"))))
              (setf (tun.jobs:job-state job) "running"
                    (tun.jobs:job-claimed-by job) "jpr_gone"
                    (tun.jobs:job-attempts job) 1)
              (save job))))
        (is (= 2 (tun.jobs:rescue-orphaned-jobs))))
      (drain-jobs)
      (dolist (id (list follow-refused follow-allowed))
        (is (equal (if (eq id follow-refused) "employee:anna" "admin:ada")
                   (jget (first (erasure-workflows id)) "planned_by"))
            "the follow-up names who planned the first"))
      (set-clock-ahead (* 3 86400))
      (dolist (id (list timer-refused follow-refused crash-refused))
        (refused-runs id 1))
      (dolist (id (list timer-allowed follow-allowed crash-allowed))
        (erased-once id)))))

(test a-chain-queued-under-a-system-actor-is-still-the-callers
  (with-test-app ()
    (let ((refused (make-customer "Chain Disguised Employee"))
          (allowed (make-customer "Chain Disguised Admin")))
      (call-ok "queue_chained_erasure_as_system" "employee:anna" "id" refused)
      (call-ok "queue_chained_erasure_as_system" "admin:ada" "id" allowed)
      (drain-jobs)
      (is (equal '("employee:anna" "admin:ada")
                 (mapcar (lambda (job) (jget job "enqueued_by"))
                         (jobs-of-kind "erase_customer_job"))))
      (refused-runs refused 1)
      (erased-once allowed))))

(test jobs-retry-keeps-who-asked-and-is-audited-as-who-retried
  (with-test-app ()
    (let ((refused (make-customer "Retried Employee")))
      (call-ok "queue_erasure_to_run_again" "employee:anna" "id" refused "how" "once")
      (drain-jobs)
      (refused-runs refused 1)
      (let ((job (jget (first (jobs-of-kind "erase_customer_once_job")) "id")))
        (is (equal "forbidden" (nth-value 1 (call "jobs_retry" "employee:anna" "id" job))))
        (call-ok "jobs_retry" "admin:root" "id" job)
        (is (equal "employee:anna" (jget (job-json job) "enqueued_by"))
            "retried, it is still who first asked")
        (drain-jobs)
        (refused-runs refused 2)
        (let ((entries (remove-if-not
                        (lambda (entry) (equal "jobs_retry" (jget entry "tool")))
                        (coerce (jget (call-ok "audit_list" "admin:root" "entity_type" "job"
                                               "entity_id" job)
                                      "items")
                                'list))))
          (is (equal '(("admin:root" "ok") ("employee:anna" "rejected"))
                     (mapcar (lambda (entry) (list (jget entry "actor") (jget entry "outcome")))
                             entries))
              "the retry is audited as who retried, and so is the refused one"))))
    (multiple-value-bind (allowed order) (values (make-customer "Retried Admin") nil)
      (setf order (jget (call-ok "orders_create" "employee:anna" "customer_id" allowed
                                 "lines" (lines (make-product) 1))
                        "id"))
      (advance-to-accepted order)
      (call-ok "queue_erasure_to_run_again" "admin:ada" "id" allowed "how" "once")
      (drain-jobs)
      (let ((job (jget (car (last (jobs-of-kind "erase_customer_once_job"))) "id")))
        (is (equal "failed" (jget (job-json job) "state")) "an open order fails it for good")
        (two-step "orders_cancel" "employee:anna" "id" order)
        (call-ok "jobs_retry" "admin:root" "id" job)
        (drain-jobs)
        (erased-once allowed)
        (is (equal (format nil "job ~a, enqueued by admin:ada" job)
                   (jget (first (customer-entries allowed "ok")) "reason"))
            "who asked is the admin who first asked, not who retried")))))

;;; ------------------------------------------------------------------
;;; The system's own, and work from outside

(test a-schedules-or-triggers-workflow-is-the-systems
  (with-schedules ((tun.jobs:define-schedule test-erasure-schedule "*/10 * * * *"
                     plan-named-erasure-job)
                   (tun.jobs:define-trigger test-erasure-trigger ((customer tun.customers:customer))
                       (:where '(:= "name" "Triggered Person") :cron "*/10 * * * *")
                     "Plan the erasure of a customer whose name asks for it."
                     (tun.workflows:schedule-workflow "test_erase_customer"
                                                      :subject-id (entity-id customer)
                                                      :due-at (now))))
    (with-test-app ()
      (let ((scheduled (make-customer "Scheduled Person"))
            (triggered (make-customer "Triggered Person")))
        (call-ok "clock_set" "admin:root" "now" "2026-03-01T09:10:00Z")
        (dolist (id (list scheduled triggered))
          (is (equal "system:schedule" (jget (first (erasure-workflows id)) "planned_by"))
              "~a's workflow is the system's" id)
          (erased-once id))))))

(test work-from-outside-is-not-the-systems
  (with-test-app ()
    (let ((inbound (make-customer "Inbound Person"))
          (public (make-customer "Public Person")))
      ;; As the inbound mail endpoint calls its operation.
      (with-application (*app*)
        (with-actor ((system-actor "inbound"))
          (call-tool "queue_customer_erasure" (jobj "id" inbound))))
      (queue-as (make-actor :customer public) 'erase-customer-job :customer-id public)
      (is (equal (list "system:inbound" (format nil "customer:~a" public))
                 (mapcar (lambda (job) (jget job "enqueued_by"))
                         (jobs-of-kind "erase_customer_job"))))
      (drain-jobs)
      (refused-runs inbound 1)
      (refused-runs public 1))))
