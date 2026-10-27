;;;; tests/jobs-tests.lisp -- background jobs (spec/jobs.md): a job stored in
;;;; the enqueuer's write, the two kinds of run, retries with backoff, cancel
;;;; and snooze, unique jobs, timeouts, recovering a lost process's jobs, the
;;;; workers of each queue, and the admin tools.

(in-package #:tun.tests)

(def-suite jobs :in core)
(in-suite jobs)

;;; ------------------------------------------------------------------
;;; Job kinds the tests run

(define-entity job-mark (:label "Merke" :id-prefix "jm" :table "test_job_marks")
  ((text :type (string :min 1 :max 200) :required t :label "Tekst")))

(defvar *job-calls* '() "What the test jobs' bodies did, newest first.")

(tun.jobs:define-job mark-job ((text :type (string :min 1 :max 100) :required t)) ()
  (insert (make-instance 'job-mark :text text)))

(tun.jobs:define-job failing-job ((text :type string :required t)) (:max-attempts 3 :backoff (30 120))
  (push text *job-calls*)
  (error "Det gikk galt med ~a" text))

(tun.jobs:define-job failing-after-write ((text :type string :required t)) (:max-attempts 1)
  (insert (make-instance 'job-mark :text text))
  (error "Feil etter skrivingen"))

(tun.jobs:define-job cancelling-job () ()
  (tun.jobs:cancel-job "Ikke nødvendig lenger"))

(tun.jobs:define-job snoozing-job () (:max-attempts 1)
  (if (member :snoozed *job-calls*)
      (push :ran *job-calls*)
      (progn (push :snoozed *job-calls*)
             (tun.jobs:snooze-job 60))))

(tun.jobs:define-job outside-job ((text :type string :required t)) (:transaction nil)
  (push text *job-calls*))

(tun.jobs:define-job unique-job ((customer :type string :required t) (note :type string))
    (:unique (:keys (customer)))
  nil)

(tun.jobs:define-job slow-job () (:timeout 1 :max-attempts 1)
  (sleep-with-deadline 3000))

(tun.jobs:define-job careful-job () (:transaction nil :after-crash :fail)
  nil)

(tun.jobs:define-job mail-queue-job () (:queue :mail)
  nil)

(defvar *carried* nil "The arguments CARRYING-JOB and EARLY-JOB last ran with.")

(tun.jobs:define-job carrying-job ((text :type string) (mail :type email) (count :type integer)
                                   (amount :type (decimal :scale 2)) (flag :type boolean)
                                   (kind :type (enum "a" "b")) (day :type date)
                                   (moment :type timestamp) (ref :type id) (data :type json)
                                   (names :type (list-of string)))
    ()
  (setf *carried* (list text mail count amount flag kind day moment ref data names)))

;; Defined before the entity whose field it reuses: a (:field ...) argument
;; is checked when an application opens (spec/jobs.md 2).
(tun.jobs:define-job early-job ((:field late-holder title)) ()
  (setf *carried* (list title)))

(define-entity late-line (:embedded t :json-name "late_line" :label "Linje")
  ((title :type string :required t :label "Tittel")))

(define-entity late-holder (:label "Holder" :id-prefix "lh" :table "test_late_holders")
  ((title :type string :label "Tittel")
   (lines :type (list-of late-line) :label "Linjer")))

(tun.jobs:define-job yielding-job () ()
  (push :yielded *job-calls*)
  (tun.jobs:snooze-job 0))

(define-operation jobs-test-enqueue ((text :type string :required t)
                                     (then-fail :type boolean))
    (:kind :update :policy :employee :title "Legg en jobb i køen (test)")
  (let ((job (tun.jobs:enqueue-job 'mark-job :text text)))
    (when then-fail
      (fail :conflict "Arbeidet feilet etter at jobben ble lagt i køen"))
    (jobj "id" (entity-id job))))

(defun job-json (id)
  (call-ok "jobs_get" "admin:root" "id" id))

(defun marks ()
  (with-application (*app*)
    (with-transaction (:read)
      (mapcar #'job-mark-text (select 'job-mark :order-by '(("seq" :asc)))))))

(defun call-ok-items (tool &rest arguments)
  "The items TOOL answers the admin for ARGUMENTS."
  (coerce (jget (apply #'call-ok tool "admin:root" arguments) "items") 'list))

(defun set-clock-ahead (seconds)
  "Move the test clock SECONDS on through clock_set; its answer."
  (call-ok "clock_set" "admin:root" "now"
           (format-rfc3339 (+ (test-clock-now (application-clock *app*)) seconds))))

;;; ------------------------------------------------------------------
;;; Enqueueing

(test a-job-exists-only-when-its-write-commits
  (with-test-app ()
    (call-ok "jobs_test_enqueue" "employee:kari" "text" "en")
    (is (equal "conflict" (nth-value 1 (call "jobs_test_enqueue" "employee:kari"
                                             "text" "to" "then_fail" t))))
    (is (equal '("en") (mapcar (lambda (job) (jget (jget job "arguments") "text"))
                               (enqueued-jobs 'mark-job)))
        "the refused operation left no job")
    (is (equal "employee:kari" (jget (first (enqueued-jobs 'mark-job)) "enqueued_by")))
    (with-application (*app*)
      (signals read-only-violation
        (with-transaction (:read) (tun.jobs:enqueue-job 'mark-job :text "tre")))
      (with-actor ((system-actor "test"))
        (flet ((refusal (&rest arguments)
                 (handler-case (progn (with-transaction (:write)
                                        (apply #'tun.jobs:enqueue-job 'mark-job arguments))
                                      nil)
                   (operation-error (e) (operation-error-code e)))))
          (is (eq :invalid-input (refusal)) "a required argument")
          (is (eq :invalid-input (refusal :text "")) "a value its type refuses")
          (is (eq :invalid-input (refusal :text "fire" :colour "blå")) "an unknown argument"))))))

(test a-job-is-due-when-it-says
  (with-test-app ()
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (with-transaction (:write)
          (tun.jobs:enqueue-job 'mark-job :text "senere" :in 3600))))
    (is (zerop (drain-jobs)) "not due yet")
    (is (= 1 (jget (set-clock-ahead 3600) "job_attempts")) "clock_set runs it when due")
    (is (equal '("senere") (marks)))))

;;; ------------------------------------------------------------------
;;; Running

(test a-job-in-a-transaction-commits-with-its-completion
  (with-test-app ()
    (multiple-value-bind (outcome job) (perform-job 'mark-job :text "merket")
      (is (eq :succeeded outcome))
      (is (equal "succeeded" (jget job "state")))
      (is (= 1 (jget job "attempts"))))
    (is (equal '("merket") (marks)))
    (multiple-value-bind (outcome job) (perform-job 'failing-after-write :text "rulles tilbake")
      (is (eq :failed outcome))
      (is (equal "failed" (jget job "state")) "its one attempt is used")
      (is (search "Feil etter skrivingen" (jget job "last_error")))
      (let ((errors (coerce (jget job "errors") 'list)))
        (is (= 1 (length errors)))
        (is (= 1 (jget (first errors) "attempt")))
        (is (stringp (jget (first errors) "request_id")))))
    (is (equal '("merket") (marks)) "the failed attempt's write rolled back")))

(test a-job-outside-a-transaction-runs-its-body-then-records
  (with-test-app ()
    (setf *job-calls* '())
    (is (eq :succeeded (perform-job 'outside-job :text "ute")))
    (is (equal '("ute") *job-calls*))))

(test failures-retry-with-backoff-then-fail
  (with-test-app ()
    (setf *job-calls* '())
    (let ((id (jget (nth-value 1 (perform-job 'failing-job :text "a")) "id")))
      (flet ((state () (jget (job-json id) "state")))
        (is (equal "retrying" (state)))
        (is (zerop (drain-jobs)) "not due before its backoff")
        (is (zerop (jget (set-clock-ahead 29) "job_attempts")))
        (is (= 1 (jget (set-clock-ahead 1) "job_attempts")) "after 30 seconds")
        (is (equal "retrying" (state)))
        (is (zerop (jget (set-clock-ahead 119) "job_attempts")))
        (is (= 1 (jget (set-clock-ahead 1) "job_attempts")) "then after 120")
        (is (equal "failed" (state)) "the third attempt was its last")
        (is (= 3 (length (jget (job-json id) "errors"))))
        (is (equal '("a" "a" "a") *job-calls*))
        (call-ok "jobs_retry" "admin:root" "id" id)
        (is (equal "queued" (state)))
        (is (zerop (jget (job-json id) "attempts")))
        (is (equal "invalid_transition" (nth-value 1 (call "jobs_retry" "admin:root" "id" id))))))))

(test the-default-backoff-is-obans
  (let ((default (tun.jobs:find-job-definition 'mark-job))
        (listed (tun.jobs:find-job-definition 'failing-job)))
    (with-test-app ()
      (with-application (*app*)
        (is (= 17 (tun.jobs:backoff-seconds default 1)) "15 + 2^1, exact in test mode")
        (is (= 47 (tun.jobs:backoff-seconds default 5)))
        (is (= 1039 (tun.jobs:backoff-seconds default 10)))
        (is (= 30 (tun.jobs:backoff-seconds listed 1)))
        (is (= 120 (tun.jobs:backoff-seconds listed 5)) "a list's last delay repeats")))))

(test a-body-cancels-or-snoozes
  (with-test-app ()
    (multiple-value-bind (outcome job) (perform-job 'cancelling-job)
      (is (eq :cancelled outcome))
      (is (equal "cancelled" (jget job "state")))
      (is (equal "Ikke nødvendig lenger" (jget job "note"))))
    (setf *job-calls* '())
    (multiple-value-bind (outcome job) (perform-job 'snoozing-job)
      (is (eq :snoozed outcome))
      (is (equal "queued" (jget job "state")))
      (is (zerop (jget job "attempts")) "a snooze gives its attempt back")
      (is (= 1 (jget job "snoozes")))
      (is (zerop (jget (set-clock-ahead 59) "job_attempts")))
      (is (= 1 (jget (set-clock-ahead 1) "job_attempts")))
      (is (equal "succeeded" (jget (job-json (jget job "id")) "state"))
          "its one attempt was still there"))
    (is (equal '(:ran :snoozed) *job-calls*))))

(test an-attempt-past-its-timeout-fails
  (with-test-app ()
    (multiple-value-bind (outcome job) (perform-job 'slow-job)
      (is (eq :failed outcome))
      (is (search "mer enn 1 sekunder" (jget job "last_error"))))))

(test a-unique-job-is-enqueued-once
  (with-test-app ()
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (flet ((enqueue (&rest arguments)
                 (entity-id (with-transaction (:write)
                              (apply #'tun.jobs:enqueue-job 'unique-job arguments)))))
          (let ((first (enqueue :customer "kun_1" :note "første")))
            (is (equal first (enqueue :customer "kun_1" :note "andre"))
                "only the unique keys count")
            (is (not (equal first (enqueue :customer "kun_2"))))
            (is (= 2 (drain-jobs)))
            (is (not (equal first (enqueue :customer "kun_1")))
                "a job that is done no longer blocks a new one")))))))

;;; ------------------------------------------------------------------
;;; A process that is gone (spec/jobs.md 7)

(test the-jobs-of-a-lost-process-are-recovered
  (with-test-app ()
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (flet ((running-on (process kind &rest arguments)
                 (with-transaction (:write)
                   (let ((job (apply #'tun.jobs:enqueue-job kind arguments)))
                     (setf (tun.jobs:job-state job) "running"
                           (tun.jobs:job-claimed-by job) process
                           (tun.jobs:job-attempts job) 1)
                     (save job)
                     (entity-id job))))
               (process (key &key holding)
                 ;; A process holds its presence lock while it runs.
                 (when holding
                   (store-claim-presence (application-store *app*) key))
                 (with-transaction (:write)
                   (entity-id (insert (make-instance 'tun.jobs:job-process
                                                     :started-at (now) :lock-key key))))))
          (let* ((lost (process 7001))
                 (alive (process 7002 :holding t))
                 (lost-mark (running-on lost 'mark-job :text "tapt"))
                 (lost-careful (running-on lost 'careful-job))
                 (gone-mark (running-on "jpr_closed" 'mark-job :text "lukket"))
                 (alive-mark (running-on alive 'mark-job :text "lever")))
            (is (= 3 (tun.jobs:rescue-orphaned-jobs)))
            (flet ((state (id) (with-transaction (:read)
                                 (tun.jobs:job-state (fetch 'tun.jobs:job id)))))
              (is (equal "retrying" (state lost-mark)) "retried, its attempt counted")
              (is (equal "failed" (state lost-careful)) ":after-crash :fail leaves it to a person")
              (is (equal "retrying" (state gone-mark)) "a process with no row is gone")
              (is (equal "running" (state alive-mark)) "a process holding its lock keeps its jobs"))
            (is (null (with-transaction (:read) (fetch 'tun.jobs:job-process lost)))
                "the lost process's row is removed")))))))

;;; ------------------------------------------------------------------
;;; Queues and workers (spec/jobs.md 6)

(define-application queued-application ()
  (:queues (:default 2) (:mail 1)))

(test an-application-says-how-many-jobs-each-queue-runs
  (is (= 2 (application-queue-limit 'queued-application :default)))
  (is (= 1 (application-queue-limit 'queued-application :mail)))
  (is (= 1 (application-queue-limit 'queued-application :reports)) "a queue it does not name")
  (is (= 1 (application-queue-limit 'application :default)))
  (signals error (macroexpand-1 '(define-application broken-queues () (:queues (:mail 0)))))
  (signals error (macroexpand-1 '(tun.jobs:define-job broken-job () (:retries 3) nil))))

(test workers-run-the-due-jobs-of-each-queue
  (with-test-app (:test-clock nil :class 'queued-application)
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (with-transaction (:write)
          (dolist (text '("en" "to" "tre"))
            (tun.jobs:enqueue-job 'mark-job :text text))
          (tun.jobs:enqueue-job 'mail-queue-job)))
      (tun.jobs:tend-jobs *app*)
      (loop repeat 100
            until (= 4 (length (call-ok-items "jobs_list" "state" "succeeded")))
            do (sleep 0.05))
      (is (= 4 (length (call-ok-items "jobs_list" "state" "succeeded"))))
      (is (equal '("en" "to" "tre") (sort (marks) #'string<)))
      (is (equal '("mail") (remove-duplicates
                            (mapcar (lambda (job) (jget job "queue"))
                                    (call-ok-items "jobs_list" "kind" "mail_queue_job"))
                            :test #'equal))))))

(test a-commit-wakes-the-queue-in-a-server
  (with-test-app (:test-clock nil)
    (tun.jobs:start-waking *app*)
    (call-ok "jobs_test_enqueue" "employee:kari" "text" "straks")
    (loop repeat 100 until (marks) do (sleep 0.05))
    (is (equal '("straks") (marks)) "run without waiting for a tick")
    (wait-for-workers *app*)))

(test a-job-not-ready-ends-its-queues-pass
  (with-test-app ()
    (setf *job-calls* '())
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (with-transaction (:write)
          (tun.jobs:enqueue-job 'yielding-job)
          (tun.jobs:enqueue-job 'mark-job :text "venter")
          (tun.jobs:enqueue-job 'mail-queue-job))))
    (is (= 2 (drain-jobs)) "the yielding job, then the other queue's; not its own queue's next")
    (is (null (marks)))
    (let ((yielding (first (enqueued-jobs 'yielding-job))))
      (is (equal "queued" (jget yielding "state")))
      (is (zerop (jget yielding "attempts")) "its attempt was given back"))
    (is (= 1 (drain-jobs)) "the next pass tries it again first")
    (is (equal '(:yielded :yielded) *job-calls*))))

;;; ------------------------------------------------------------------
;;; The tools

(test the-job-tools-are-the-admins
  (with-test-app ()
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (with-transaction (:write)
          (tun.jobs:enqueue-job 'mark-job :text "vent" :in 3600))))
    (let ((id (jget (first (call-ok-items "jobs_list" "state" "queued")) "id")))
      (is (equal "mark_job" (jget (job-json id) "kind")))
      (is (equal "forbidden" (nth-value 1 (call "jobs_list" "employee:kari"))))
      (is (equal "forbidden" (nth-value 1 (call "jobs_cancel" "employee:kari" "id" id))))
      (call-ok "jobs_cancel" "admin:root" "id" id)
      (is (equal "cancelled" (jget (job-json id) "state")))
      (is (equal "Avbrutt av admin:root" (jget (job-json id) "note")))
      (is (equal "invalid_transition" (nth-value 1 (call "jobs_cancel" "admin:root" "id" id))))
      (is (null (call-ok-items "jobs_list" "state" "queued")))
      (call-ok "jobs_retry" "admin:root" "id" id)
      (is (= 1 (length (call-ok-items "jobs_list" "kind" "mark_job" "queue" "default")))))))

;;; ------------------------------------------------------------------
;;; What a job can carry (spec/jobs.md 2)

(defun expansion-refusal (form)
  "The message of the error expanding FORM signals, or NIL."
  (handler-case (progn (macroexpand-1 form) nil)
    (error (condition) (princ-to-string condition))))

(test a-job-refuses-an-argument-it-cannot-carry-when-it-is-defined
  (dolist (type '(files (files :max 3) (list-of files)))
    (let ((message (expansion-refusal `(tun.jobs:define-job shots-job ((shots :type ,type)) ()))))
      (is (and message (search "SHOTS-JOB" message) (search "shots" message)
               (search "record's id" message))
          "~s: ~a" type message)))
  (let ((message (expansion-refusal '(tun.jobs:define-job lines-job
                                      ((lines :type (list-of late-line))) ()))))
    (is (and message (search "LINES-JOB" message) (search "never records" message)
             (search "late-line records' ids" message))
        "a list of records: ~a" message))
  (is (null (expansion-refusal '(tun.jobs:define-job names-job
                                  ((names :type (list-of string))) ())))
      "a list of values is carried"))

(defun opening-refusal (job-form)
  "Load JOB-FORM, a define-job, then open an application: the message it is
refused with, or NIL.  The job is removed again, as it would keep every
other application from opening."
  (let ((name (second job-form)))
    (eval job-form)
    (unwind-protect
         (handler-case (progn (with-test-app ()) nil)
           (error (condition) (princ-to-string condition)))
      (remhash (tun.jobs:job-definition-kind (tun.jobs:find-job-definition name))
               tun.jobs::*job-definitions*))))

(test a-jobs-reused-field-is-checked-when-an-application-opens
  (let ((message (opening-refusal '(tun.jobs:define-job lines-later-job
                                    ((:field late-holder lines)) ()))))
    (is (and message (search "lines_later_job" message) (search "lines" message)
             (search "LATE-HOLDER" message) (search "never records" message))
        "a field a job cannot carry, of an entity defined after the job: ~a" message))
  (let ((message (opening-refusal '(tun.jobs:define-job no-entity-job
                                    ((:field no-such-entity title)) ()))))
    (is (and message (search "no_entity_job" message) (search "NO-SUCH-ENTITY" message)
             (search "is not an entity" message))
        "an entity that does not exist: ~a" message))
  (let ((message (opening-refusal '(tun.jobs:define-job no-field-job
                                    ((:field late-holder colour)) ()))))
    (is (and message (search "no_field_job" message) (search "has no field colour" message))
        "a field that does not exist: ~a" message))
  (with-test-app ()
    (setf *carried* nil)
    (is (eq :succeeded (perform-job 'early-job :title "Først jobben, så posten")))
    (is (equal '("Først jobben, så posten") *carried*)
        "a job loaded before its entity, with a field it carries, opens and runs")))

(test a-job-carries-every-other-type
  (with-test-app ()
    (setf *carried* nil)
    (let ((data (jobj "a" 1)))
      (is (eq :succeeded (perform-job 'carrying-job :text "tekst" :mail "kari@example.no"
                                                    :count 3 :amount 3/2 :flag t :kind "b"
                                                    :day "2026-10-27" :moment 3970000000
                                                    :ref "cus_1" :data data
                                                    :names '("a" "b"))))
      (destructuring-bind (&optional text mail count amount flag kind day moment ref json names)
          *carried*
        (is (equal '("tekst" "kari@example.no" 3 3/2 t "b" "2026-10-27" 3970000000 "cus_1")
                   (list text mail count amount flag kind day moment ref)))
        (is (equal 1 (and (hash-table-p json) (jget json "a"))))
        (is (equal '("a" "b") names))))))
