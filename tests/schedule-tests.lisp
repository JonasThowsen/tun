;;;; tests/schedule-tests.lisp -- schedules (spec/jobs.md 8): reading cron
;;;; times, their occurrences in Norwegian time across summer time, and a
;;;; schedule that enqueues its job once per occurrence, catches up after
;;;; downtime, and never runs what happened before it existed; and triggers,
;;;; which run a job for each record that meets a condition.

(in-package #:tun.tests)

(def-suite schedules :in core)
(in-suite schedules)

(defun instant (text) (parse-rfc3339 text))

(defun cron-fields (text)
  (let ((cron (tun.jobs:parse-cron text)))
    (list (tun.jobs:cron-minutes cron) (tun.jobs:cron-hours cron) (tun.jobs:cron-days cron)
          (tun.jobs:cron-months cron) (tun.jobs:cron-weekdays cron))))

;;; ------------------------------------------------------------------
;;; Cron times

(test cron-times-are-read-as-cron-reads-them
  (is (equal '((0) (7) (1 31) (1 12) (1 5))
             (let ((fields (cron-fields "0 7 * * 1-5")))
               (list (first fields) (second fields)
                     (list (first (third fields)) (car (last (third fields))))
                     (list (first (fourth fields)) (car (last (fourth fields))))
                     (list (first (fifth fields)) (car (last (fifth fields))))))))
  (is (equal '(0 15 30 45) (first (cron-fields "*/15 * * * *"))))
  (is (equal '(1 7) (fourth (cron-fields "0 7 * JAN,JUL *"))) "month names")
  (is (equal '(1 2 3 4 5) (fifth (cron-fields "0 7 * * MON-FRI"))) "weekday names")
  (is (equal '(0 6) (fifth (cron-fields "0 7 * * 6,7"))) "7 is Sunday too")
  (is (equal '((0) (0) (1)) (subseq (cron-fields "@monthly") 0 3)))
  (is (equal (cron-fields "0 0 * * *") (cron-fields "@daily")))
  (dolist (bad '("61 * * * *" "* * *" "5-1 * * * *" "0 25 * * *" "0 7 * * fredag"
                 "0 0 31 2 *"))
    (signals tun.jobs:cron-error (tun.jobs:parse-cron bad))))

(test a-cron-time-naming-days-and-weekdays-runs-on-either
  ;; 2026-11-02 is a Monday, 2026-11-01 the first.
  (let ((cron (tun.jobs:parse-cron "0 0 1 * MON")))
    (is (tun.jobs:cron-day-p cron "2026-11-01"))
    (is (tun.jobs:cron-day-p cron "2026-11-02"))
    (is (not (tun.jobs:cron-day-p cron "2026-11-03")))))

;;; ------------------------------------------------------------------
;;; Occurrences in Norwegian time

(test occurrences-are-norwegian-wall-clock-times
  (let ((weekdays (tun.jobs:parse-cron "0 7 * * 1-5")))
    (flet ((previous (at) (multiple-value-list (tun.jobs:previous-occurrence weekdays (instant at))))
           (next (at) (multiple-value-list (tun.jobs:next-occurrence weekdays (instant at)))))
      (is (equal (list (instant "2026-10-21T05:00:00Z") "2026-10-21T07:00")
                 (previous "2026-10-21T10:00:00Z"))
          "07:00 in summer time is 05:00 UTC")
      (is (equal (list (instant "2026-10-23T05:00:00Z") "2026-10-23T07:00")
                 (previous "2026-10-24T10:00:00Z"))
          "on Saturday, the Friday before")
      (is (equal (list (instant "2026-11-02T06:00:00Z") "2026-11-02T07:00")
                 (next "2026-10-30T12:00:00Z"))
          "in winter time 06:00 UTC, on the Monday after")
      (is (equal (list (instant "2026-10-21T05:00:00Z") "2026-10-21T07:00")
                 (previous "2026-10-21T05:00:00Z"))
          "an occurrence at the instant itself counts"))))

(test a-time-in-the-spring-gap-runs-at-the-first-valid-minute
  ;; 2026-03-29: 02:00 CET jumps to 03:00 CEST, at 01:00 UTC.
  (is (= (instant "2026-03-29T01:00:00Z") (tun.jobs:wall-time-instant "2026-03-29" 2 30)))
  (is (equal (list (instant "2026-03-29T01:00:00Z") "2026-03-29T02:30")
             (multiple-value-list (tun.jobs:next-occurrence (tun.jobs:parse-cron "30 2 * * *")
                                                            (instant "2026-03-28T23:00:00Z"))))))

(test a-time-in-the-autumn-overlap-runs-once
  ;; 2026-10-25: 03:00 CEST falls back to 02:00 CET, at 01:00 UTC, so 02:30
  ;; happens at 00:30 and again at 01:30 UTC.
  (let ((cron (tun.jobs:parse-cron "30 2 * * *")))
    (is (= (instant "2026-10-25T00:30:00Z") (tun.jobs:wall-time-instant "2026-10-25" 2 30))
        "the first of the two")
    (is (equal (list (instant "2026-10-25T00:30:00Z") "2026-10-25T02:30")
               (multiple-value-list (tun.jobs:previous-occurrence cron (instant "2026-10-25T01:45:00Z"))))
        "during the second 02:30 the latest occurrence is still the first, so it is not run again")))

;;; ------------------------------------------------------------------
;;; A schedule in a tenant

(defmacro with-schedules ((&rest definitions) &body body)
  "Run BODY with the schedules DEFINITIONS, DEFINE-SCHEDULE forms, defined,
and forget them after: a schedule is the whole image's."
  `(unwind-protect (progn ,@definitions ,@body)
     (dolist (name ',(mapcar #'second definitions))
       (tun.jobs:remove-schedule name))))

(defun clock-to (text)
  (jget (call-ok "clock_set" "admin:root" "now" text) "job_attempts"))

(test a-schedule-runs-its-job-once-per-occurrence
  ;; The test clock starts at 2026-03-01T09:00Z, a Sunday, 10:00 in Norway.
  (with-schedules ((tun.jobs:define-schedule test-morning "0 7 * * *" mark-job :text "morgen")
                   (tun.jobs:define-schedule test-on-time "0 7 * * *" mark-job :text "presis"
                     :catch-up nil))
    (with-test-app ()
      (is (null (marks)) "07:00 today was before the schedules existed")
      (is (zerop (clock-to "2026-03-02T05:59:00Z")))
      (is (= 2 (clock-to "2026-03-02T06:00:00Z")) "07:00 CET, both schedules")
      (is (zerop (clock-to "2026-03-02T06:00:00Z")) "once")
      (is (= 2 (clock-to "2026-03-05T06:00:30Z")))
      (is (equal '("morgen" "morgen" "presis" "presis") (sort (marks) #'string<))
          "three days on, the latest occurrence only")
      (is (= 1 (clock-to "2026-03-10T12:00:00Z"))
          "after downtime the missed 07:00 runs once; the one that catches nothing up does not")
      (let ((morning (find "test_morning" (call-ok-items "schedules_list")
                           :key (lambda (s) (jget s "name")) :test #'equal)))
        (is (equal "0 7 * * *" (jget morning "cron")))
        (is (equal "mark_job" (jget morning "job")))
        (is (equal "2026-03-10T07:00" (jget morning "last_occurrence")))
        (is (equal "2026-03-11T07:00" (jget morning "next_occurrence")))
        (is (stringp (jget morning "last_job_id"))))
      (call-ok "schedules_run" "admin:root" "name" "test_morning")
      (is (= 1 (drain-jobs)) "run now, outside the timetable")
      (is (equal "not_found" (nth-value 1 (call "schedules_run" "admin:root" "name" "nothing"))))
      (is (equal "forbidden" (nth-value 1 (call "schedules_list" "employee:kari")))))))

(test a-schedule-whose-job-is-wrong-stops-the-start
  (with-schedules ((tun.jobs:define-schedule test-no-job "@daily" no-such-job))
    (signals error (with-test-app ())))
  (with-schedules ((tun.jobs:define-schedule test-bad-arguments "@daily" mark-job :colour "blå"))
    (signals error (with-test-app ())))
  (signals tun.jobs:cron-error (macroexpand-1 '(tun.jobs:define-schedule x "0 0 30 2 *" mark-job))))

;;; ------------------------------------------------------------------
;;; Triggers (spec/jobs.md 8.1)

(define-entity trigger-item (:label "Sak" :id-prefix "tgi" :table "test_trigger_items")
  ((title :type (string :min 1 :max 100) :required t :label "Tittel")
   (status :type (enum "venter" "lukket") :required t :label "Status")
   (asked-at :type timestamp :label "Spurt")
   (reminded-at :type timestamp :label "Påminnet")))

(defvar *reminded* '() "The titles the test trigger reminded, newest first.")

(defun add-trigger-item (title &key (status "venter") (asked-days-ago 0))
  (with-application (*app*)
    (with-transaction (:write)
      (entity-id (insert (make-instance 'trigger-item
                                        :title title :status status
                                        :asked-at (- (now) (* asked-days-ago 86400))))))))

(defun change-trigger-item (id &rest changes)
  (with-application (*app*)
    (with-transaction (:write)
      (let ((item (fetch! 'trigger-item id)))
        (loop for (field value) on changes by #'cddr
              do (setf (slot-value item (find-symbol (symbol-name field) :tun.tests)) value))
        (save item)))))

(defun run-schedule-now (name)
  (coerce (jget (call-ok "schedules_run" "admin:root" "name" name) "jobs") 'list))

(test a-trigger-runs-a-job-for-each-record-that-meets-its-condition
  ;; The test clock starts at 2026-03-01T09:00Z; the trigger sweeps every ten minutes.
  (setf *reminded* '())
  (with-schedules ((tun.jobs:define-trigger test-remind ((item trigger-item))
                       (:where `(:and (:= "status" "venter") (:null "reminded_at")
                                      (:< "asked_at" ,(- (now) 86400)))
                        :cron "*/10 * * * *" :max-attempts 3)
                     "Remind the reporter of an item that has waited a day."
                     (push (trigger-item-title item) *reminded*)
                     (setf (trigger-item-reminded-at item) (now))
                     (save item)))
    (with-test-app ()
      (add-trigger-item "gammel" :asked-days-ago 2)
      (let ((fresh (add-trigger-item "fersk"))
            (closed (add-trigger-item "lukket" :status "lukket" :asked-days-ago 2)))
        (declare (ignore closed))
        (is (= 1 (clock-to "2026-03-01T09:10:00Z")) "the sweep found one record, and its job ran")
        (is (equal '("gammel") *reminded*))
        (is (zerop (clock-to "2026-03-01T09:20:00Z"))
            "the body made the condition false, so the next sweep finds nothing")
        (let ((trigger (find "test_remind" (call-ok-items "schedules_list")
                             :key (lambda (s) (jget s "name")) :test #'equal)))
          (is (equal "trigger" (jget trigger "kind")))
          (is (equal "trigger_item" (jget trigger "entity")))
          (is (equal "test_remind" (jget trigger "job")))
          (is (eql 0 (jget trigger "last_enqueued")))
          (is (equal "hvert 10. minutt" (jget trigger "description"))))
        (change-trigger-item fresh :asked-at (- (with-application (*app*) (now)) (* 2 86400)))
        (is (= 1 (length (run-schedule-now "test_remind"))) "run now sweeps at once")
        (is (null (run-schedule-now "test_remind"))
            "a record whose job waits gets no second job")
        (is (= 1 (length (enqueued-jobs 'test-remind :record-id fresh))))
        (change-trigger-item fresh :status "lukket")
        (is (= 1 (drain-jobs)))
        (is (equal '("gammel") *reminded*) "the record no longer met the condition when its job ran")
        (let ((job (first (call-ok-items "jobs_list" "kind" "test_remind" "state" "cancelled"))))
          (is (equal fresh (jget (jget job "arguments") "record_id")))
          (is (search "vilkår" (jget job "note"))))))))

(test a-trigger-sweep-enqueues-at-most-its-limit
  (with-schedules ((tun.jobs:define-trigger test-limited (trigger-item)
                       (:where '(:= "status" "venter") :limit 2)
                     (setf (trigger-item-status trigger-item) "lukket")
                     (save trigger-item)))
    (with-test-app ()
      (dotimes (i 3) (add-trigger-item (format nil "sak ~d" i)))
      (is (= 2 (length (run-schedule-now "test_limited"))))
      (is (= 1 (length (run-schedule-now "test_limited"))) "the next sweep takes the rest")
      (is (= 3 (drain-jobs))))))

(test a-trigger-that-cannot-run-stops-the-start
  (with-schedules ((tun.jobs:define-trigger test-no-entity (no-such-entity)
                       (:where '(:= "status" "venter"))
                     no-such-entity))
    (signals error (with-test-app ())))
  (signals error (macroexpand-1 '(tun.jobs:define-trigger x (trigger-item) (:cron "@daily") nil)))
  (signals error (macroexpand-1 '(tun.jobs:define-trigger x (trigger-item)
                                     (:where '(:= "status" "venter") :unique (:keys ()))
                                   nil)))
  (signals tun.jobs:cron-error
    (macroexpand-1 '(tun.jobs:define-trigger x (trigger-item)
                        (:where '(:= "status" "venter") :cron "0 0 30 2 *")
                      nil))))
