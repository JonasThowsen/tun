;;;; jobs/jobs.lisp -- background jobs (spec/jobs.md): the job kinds modules
;;;; and clients define, the jobs table, and enqueueing in the caller's write.
;;;;
;;;; DEFINE-JOB names a kind of work once: its typed arguments, its body, and
;;;; how it is retried.  ENQUEUE-JOB stores a job in the caller's transaction,
;;;; so a job exists only when the work that asked for it commits: the jobs
;;;; table is its own outbox.  cron.lisp and schedules.lisp enqueue jobs on a
;;;; timetable, triggers.lisp one for each record meeting a condition;
;;;; runner.lisp claims and runs due jobs and recovers those of a
;;;; process that died; tools.lisp has the admin tools.

(defpackage #:tun.jobs
  (:use #:cl #:tun.core)
  (:export #:define-job #:enqueue-job #:cancel-job #:snooze-job #:fail-job #:last-attempt-p
           #:job-cancelled #:job-cancelled-reason #:job-snoozed #:job-snoozed-seconds
           #:job-given-up #:job-given-up-reason
           #:job #:job-kind #:job-queue #:job-arguments #:job-state #:job-priority #:job-due-at
           #:job-attempts #:job-max-attempts #:job-snoozes #:job-unique-key #:job-enqueued-at
           #:job-enqueued-by #:job-claimed-by #:job-started-at #:job-finished-at
           #:job-last-error #:job-errors #:job-note
           #:job-definition #:find-job-definition #:job-definitions #:job-definition-name
           #:job-definition-kind #:job-definition-parameters #:job-definition-queue #:job-definition-max-attempts
           #:job-definition-transaction-p #:job-definition-after-crash #:backoff-seconds
           #:check-job-definitions
           #:job-process #:job-process-lock-key #:process-id #:open-job-process #:close-job-process #:tend-jobs #:run-due-jobs
           #:rescue-orphaned-jobs #:run-job-now #:start-waking
           #:jobs-list #:jobs-get #:jobs-retry #:jobs-cancel
           ;; schedules
           #:define-schedule #:remove-schedule #:schedule #:schedules #:find-schedule #:tend-schedules
           #:define-trigger #:trigger #:trigger-entity
           #:job-schedule #:cron #:parse-cron #:cron-error #:cron-text #:cron-minutes #:cron-hours
           #:cron-days #:cron-months #:cron-weekdays #:cron-day-p
           #:previous-occurrence #:next-occurrence #:wall-time-instant #:describe-cron
           #:jobs-summary #:prune-jobs
           #:schedules-list #:schedules-run))

(in-package #:tun.jobs)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Job kinds

(defclass job-definition ()
  ((name :initarg :name :reader job-definition-name
         :documentation "The symbol DEFINE-JOB named: its body's function, and what ENQUEUE-JOB takes.")
   (kind :initarg :kind :reader job-definition-kind
         :documentation "The kind a job row stores, such as \"remind_reporter\".")
   (parameters :initarg :parameters :reader job-definition-parameters
               :documentation "The arguments, as PARAMETER objects, like an operation's inputs.")
   (queue :initarg :queue :reader job-definition-queue :type keyword)
   (max-attempts :initarg :max-attempts :reader job-definition-max-attempts :type (integer 1))
   (backoff :initarg :backoff :reader job-definition-backoff
            :documentation "NIL for the default formula, a list of seconds, or a function of the attempt.")
   (timeout :initarg :timeout :reader job-definition-timeout :type (or null (integer 1))
            :documentation "Seconds one attempt may take; NIL for the default of its kind of run.")
   (transaction :initarg :transaction :reader job-definition-transaction-p
                :documentation "True when the body and the job's completion commit together (spec/jobs.md 4.1).")
   (unique :initarg :unique :reader job-definition-unique
           :documentation "NIL, or a plist (:keys json-names :period seconds :states state-names).")
   (priority :initarg :priority :reader job-definition-priority :type (integer 0 9))
   (after-crash :initarg :after-crash :reader job-definition-after-crash :type (member :retry :fail))
   (module :initarg :module :reader job-definition-module)
   (location :initarg :location :reader job-definition-location)))

(defvar *job-definitions* (make-hash-table :test 'equal) "Kind -> JOB-DEFINITION.")

(defun find-job-definition (kind)
  "The definition of KIND, a kind string or the symbol DEFINE-JOB named, or NIL."
  (if (symbolp kind)
      (find kind (job-definitions) :key #'job-definition-name)
      (gethash kind *job-definitions*)))

(defun job-definitions ()
  "Every job kind, by kind."
  (sort (loop for definition being the hash-values of *job-definitions* collect definition)
        #'string< :key #'job-definition-kind))

(defparameter +incomplete-states+ '("queued" "running" "retrying"))

(defun unique-states (states)
  (ecase states
    (:incomplete +incomplete-states+)
    (:all '("queued" "running" "retrying" "succeeded" "failed" "cancelled"))))

(defun make-job-definition (name parameters options module location)
  "The JOB-DEFINITION DEFINE-JOB's arguments describe.  OPTIONS is its
option plist, already checked."
  (destructuring-bind (&key (queue :default) (max-attempts 20) backoff timeout (transaction t)
                         unique (priority 0) (after-crash :retry))
      options
    (let ((parameters (mapcar #'parse-parameter-spec parameters)))
      (make-instance
       'job-definition
       :name name :kind (json-name-of name) :parameters parameters :queue queue
       :max-attempts max-attempts :backoff backoff :timeout timeout
       :transaction (and transaction t) :priority priority :after-crash after-crash
       :unique (and unique
                    (destructuring-bind (&key (keys nil keys-p) period (states :incomplete)) unique
                      (list :keys (if keys-p
                                      (mapcar #'json-name-of keys)
                                      (mapcar #'parameter-json-name parameters))
                            :period period
                            :states (unique-states states))))
       :module module :location location))))

(defun register-job-definition (definition)
  "Make DEFINITION the handler of its kind.  One function per kind: another
definition of a kind is refused, only the same function may define it again
(a reload)."
  (let ((existing (gethash (job-definition-kind definition) *job-definitions*)))
    (when (and existing (not (eq (job-definition-name existing) (job-definition-name definition))))
      (extension-error "Job kind ~a is already defined by ~s (~a); ~s (~a) cannot take it over"
                       (job-definition-kind definition) (job-definition-name existing)
                       (job-definition-module existing) (job-definition-name definition)
                       (job-definition-module definition))))
  (setf (gethash (job-definition-kind definition) *job-definitions*) definition))

(defparameter +job-options+
  '(:queue :max-attempts :backoff :timeout :transaction :unique :priority :after-crash))

(defun evaluated-option-p (key value)
  "True when DEFINE-JOB's option KEY with VALUE is code to evaluate: a
:backoff that is not a list of seconds, such as #'my-backoff."
  (and (eq key :backoff)
       (not (and (listp value) (every #'integerp value)))))

(defun uncarried-type-reason (type)
  "Why a job cannot carry an argument of TYPE, a field type, or NIL when it
can: a job stores its arguments as JSON and takes ids and values, never
files or records (spec/jobs.md 2)."
  (cond ((files-type-p type)
         (format nil "a job cannot carry files; attach them to a record in the operation ~
                      and pass the record's id"))
        ((not (typep type 'list-type)) nil)
        ((list-element-entity-p type)
         (format nil "a job takes ids and values, never records; pass the ~(~a~) records' ids, ~
                      or a json argument" (list-element type)))
        (t (uncarried-type-reason (list-element type)))))

(defun parameter-spec-name (spec)
  "The variable SPEC, an argument's spec, binds in the job's body: its name,
or the field's for (:FIELD ENTITY NAME)."
  (if (eq (first spec) :field) (third spec) (first spec)))

(defun check-job-parameter-spec (name spec)
  "Refuse SPEC, an argument of the job NAME, when its declared type is one a
job cannot carry.  An argument that reuses an entity's field is checked
when an application opens (CHECK-JOB-DEFINITIONS): the entity may not be
defined yet."
  (unless (eq (first spec) :field)
    (let* ((designator (getf (rest spec) :type 'string))
           (reason (uncarried-type-reason (parse-field-type designator))))
      (when reason
        (error "define-job ~s: argument ~(~a~) is ~s: ~a"
               name (parameter-spec-name spec) designator reason)))))

(defun check-job-definitions ()
  "Refuse, as an application opens, a job with an argument (:FIELD ENTITY
NAME) whose entity or field does not exist, or whose field's type a job
cannot carry (spec/jobs.md 2)."
  (dolist (definition (job-definitions))
    (dolist (parameter (job-definition-parameters definition))
      (let ((reference (parameter-entity-field parameter)))
        (when reference
          (destructuring-bind (entity json-name) reference
            (let* ((class (find-entity-class entity nil))
                   (field (and class (find-field class json-name)))
                   (reason (and field (uncarried-type-reason (field-type field)))))
              (flet ((refuse (control &rest arguments)
                       (extension-error "Job ~a (~s): argument ~a reuses ~s's field ~a, ~?"
                                        (job-definition-kind definition)
                                        (job-definition-name definition)
                                        (parameter-json-name parameter) entity json-name
                                        control arguments)))
                (cond ((null class) (refuse "but ~s is not an entity" entity))
                      ((null field) (refuse "but ~s has no field ~a" entity json-name))
                      (reason (refuse "~a" reason)))))))))))

(defmacro define-job (name (&rest parameters) (&rest options) &body body)
  "Define the job kind NAME (spec/jobs.md 2).  PARAMETERS are its arguments,
written as an operation's inputs, bound as variables in BODY.  OPTIONS:
:queue (a keyword, :default), :max-attempts (20), :backoff (a list of
seconds, or a function of the attempt), :timeout (seconds), :transaction (T:
the body and the job's completion commit together; NIL: the body runs
outside any transaction), :unique (:keys (argument...) :period seconds
:states :incomplete or :all), :priority (0 to 9, 0 first) and :after-crash
(:retry or :fail).  BODY runs as system:job; it may call CANCEL-JOB or
SNOOZE-JOB, FAIL-JOB and LAST-ATTEMPT-P, and a condition it signals fails
the attempt."
  (let ((unknown (loop for key in options by #'cddr unless (member key +job-options+) collect key)))
    (when unknown
      (error "define-job ~s: unknown option~p ~{~s~^, ~}; the options are ~{~s~^, ~}"
             name (length unknown) unknown +job-options+)))
  (dolist (spec parameters)
    (check-job-parameter-spec name spec))
  `(progn
     (defun ,name (&key ,@(mapcar #'parameter-spec-name parameters))
       (declare (ignorable ,@(mapcar #'parameter-spec-name parameters)))
       ,@body)
     (register-job-definition
      (make-job-definition ',name ',parameters
                           (list ,@(loop for (key value) on options by #'cddr
                                         append (list key (if (evaluated-option-p key value)
                                                              value
                                                              `',value))))
                           ,(current-definition-module) ,(current-source-location)))
     ',name))

;;; ------------------------------------------------------------------
;;; What a body can say (spec/jobs.md 4.3)

(define-condition job-cancelled (condition)
  ((reason :initarg :reason :reader job-cancelled-reason))
  (:report (lambda (c s) (format s "The job was cancelled: ~a" (job-cancelled-reason c))))
  (:documentation "Signalled by CANCEL-JOB; the runner makes the job cancelled."))

(define-condition job-snoozed (condition)
  ((seconds :initarg :seconds :reader job-snoozed-seconds))
  (:report (lambda (c s) (format s "The job was snoozed for ~d seconds" (job-snoozed-seconds c))))
  (:documentation "Signalled by SNOOZE-JOB; the runner queues the job again."))

(define-condition job-given-up (condition)
  ((reason :initarg :reason :reader job-given-up-reason))
  (:report (lambda (c s) (format s "The job failed for good: ~a" (job-given-up-reason c))))
  (:documentation "Signalled by FAIL-JOB; the runner makes the job failed at once."))

(defvar *job* nil "The job whose body is running.")

(defun last-attempt-p ()
  "True when the running job's attempt is its last: a failure now fails it
for good."
  (unless *job* (error "LAST-ATTEMPT-P outside a job's body"))
  (>= (job-attempts *job*) (job-max-attempts *job*)))

(defun fail-job (reason)
  "End the running job as failed at once, with no more attempts: what went
wrong will not get better by trying again, such as an address the provider
refuses.  REASON, a string, is kept as its last error.  Writes the attempt
made in its transaction roll back."
  (check-type reason string)
  (error 'job-given-up :reason reason))

(defun cancel-job (reason)
  "End the running job as cancelled, no longer needed: not an error, never
retried.  REASON, a string, is kept as the job's note.  Writes the attempt
made in its transaction roll back."
  (check-type reason string)
  (error 'job-cancelled :reason reason))

(defun snooze-job (seconds)
  "End the running attempt and queue the job again, due in SECONDS, without
counting the attempt.  With 0 the job is not ready now, for a reason that
passes, such as a provider with no room: it is due again at once, and this
pass of its queue ends, so the next tick or drain tries it.  Writes the
attempt made in its transaction roll back."
  (check-type seconds (integer 0))
  (error 'job-snoozed :seconds seconds))

;;; ------------------------------------------------------------------
;;; The jobs table

(define-entity job (:label "Job" :id-prefix "job" :table "jobs" :internal t
                           :indexes (("state" "queue" "due_at") ("kind" "unique_key")
                                     ("claimed_by")))
  ((kind :type (string :max 100) :required t :input nil :label "Kind")
   (queue :type (string :max 64) :required t :input nil :label "Queue")
   (arguments :type json :input nil :label "Arguments")
   (state :type (enum "queued" "running" "retrying" "succeeded" "failed" "cancelled")
          :input nil :initform "queued" :label "State")
   (priority :type integer :input nil :initform 0 :label "Priority")
   (due-at :type timestamp :input nil :label "Due")
   (attempts :type integer :input nil :initform 0 :label "Attempts")
   (max-attempts :type integer :input nil :label "Most attempts")
   (snoozes :type integer :input nil :initform 0 :label "Snoozes")
   (unique-key :type (string :max 64) :input nil :label "Unique key")
   (enqueued-at :type timestamp :input nil :label "Enqueued")
   (enqueued-by :type (string :max 200) :input nil :label "Enqueued by")
   (claimed-by :type (string :max 64) :input nil :label "Process"
               :description "The process running the job, or that ran it last.")
   (started-at :type timestamp :input nil :label "Started")
   (finished-at :type timestamp :input nil :label "Finished")
   (last-error :type (string :max 2000) :input nil :label "Last error")
   (errors :type json :input nil :label "Errors"
           :description "The last ten failures: attempt, at and error.")
   (note :type (string :max 2000) :input nil :label "Note"
         :description "Why the job was cancelled or failed without an error of its own.")))

;;; ------------------------------------------------------------------
;;; Enqueueing (spec/jobs.md 3)

(defun job-arguments-json (definition arguments)
  "ARGUMENTS, a plist of Lisp values by argument keyword, as the JSON object
a job stores, each checked as its declared type checks input.  A missing
required argument, an unknown one or a bad value is collected for
COLLECTING-INPUT-ERRORS."
  (let ((json (jobj))
        (parameters (job-definition-parameters definition)))
    (loop for (key nil) on arguments by #'cddr
          unless (find key parameters :key #'parameter-keyword)
            do (input-error (json-name-of key) "is not an argument of the job"))
    (dolist (parameter parameters json)
      (let ((value (getf arguments (parameter-keyword parameter))))
        (cond ((and (null value) (parameter-required-p parameter))
               (input-error (parameter-json-name parameter) "must be filled in"))
              ((null value))
              (t (let ((stored (type->json (parameter-type parameter) value)))
                   (coerce-input (parameter-type parameter) stored (parameter-json-name parameter))
                   (setf (gethash (parameter-json-name parameter) json) stored))))))))

(defun unique-key (definition arguments-json)
  "The key two jobs of DEFINITION share when their unique arguments are the
same, or NIL when the kind is not unique."
  (let ((unique (job-definition-unique definition)))
    (when unique
      (sha256-hex (to-json-string
                   (jarr (cons (job-definition-kind definition)
                               (mapcar (lambda (key) (or (jget arguments-json key) :null))
                                       (getf unique :keys)))))))))

(defun duplicate-job (definition key)
  "The job a new one with unique KEY would duplicate, or NIL."
  (let* ((unique (job-definition-unique definition))
         (period (getf unique :period)))
    (select-one 'job :where `(:and (:= "kind" ,(job-definition-kind definition))
                                   (:= "unique_key" ,key)
                                   (:in "state" ,(getf unique :states))
                                   ,@(when period `((:>= "enqueued_at" ,(- (now) period)))))
                     :order-by '(("seq" :desc)))))

(defun enqueue-job (kind &rest arguments &key at in &allow-other-keys)
  "Queue a job of KIND, the symbol DEFINE-JOB named, with ARGUMENTS, inside
the current write: it exists only when that write commits (spec/jobs.md 3).
It is due at AT, an instant, or IN seconds from now, else now; a job due
now starts as soon as the write commits, in a server.  Returns the job; when KIND is unique and a matching job exists, returns that one and
stores nothing.  A bad argument fails the operation with invalid_input."
  (assert-writable)
  (let ((definition (or (find-job-definition kind)
                        (error "~s is not a job kind; define it with define-job" kind)))
        (arguments (loop for (key value) on arguments by #'cddr
                         unless (member key '(:at :in)) append (list key value))))
    (when in (check-type in (integer 0)))
    (when at (check-type at (integer 0)))
    (let* ((json (collecting-input-errors (job-arguments-json definition arguments)))
           (key (unique-key definition json))
           (due (cond (at) (in (+ (now) in)) (t (now)))))
      (or (and key (duplicate-job definition key))
          (progn
            (when (<= due (now))
              (let ((app *application*)
                    (queue (job-definition-queue definition)))
                (on-commit (lambda () (wake-queue app queue)))))
            (insert (make-instance 'job
                                 :kind (job-definition-kind definition)
                                 :queue (string-downcase (job-definition-queue definition))
                                 :arguments json
                                 :priority (job-definition-priority definition)
                                 :due-at due
                                 :max-attempts (job-definition-max-attempts definition)
                                 :unique-key key
                                 :enqueued-at (now)
                                 ;; Kernel code may enqueue with no actor bound, as the
                                 ;; system it is.
                                 :enqueued-by (if *actor* (actor-string *actor*) "system")
                                 :errors (jarr '()))))))))
