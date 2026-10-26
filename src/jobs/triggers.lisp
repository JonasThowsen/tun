;;;; jobs/triggers.lisp -- triggers: a job for every record where a
;;;; condition holds (spec/jobs.md 8.1).
;;;;
;;;; A trigger is a schedule whose occurrence sweeps an entity instead of
;;;; enqueueing one job: every record that meets the trigger's condition and
;;;; has no job waiting or running gets one.  The job is unique by its record,
;;;; reads the record again with the condition when it runs, and cancels
;;;; itself when the record no longer meets it, so work queued before a person
;;;; acted is never done after.  The body should make the condition false;
;;;; a record that still meets it gets a new job at the next sweep.

(in-package #:tun.jobs)

(declaim (optimize (safety 3) (debug 2)))

(defclass trigger (schedule)
  ((entity :initarg :entity :reader trigger-entity :type symbol
           :documentation "The entity it sweeps, by class name.")
   (condition :initarg :condition :reader trigger-condition :type function
              :documentation "A function of no arguments that gives the SELECT condition a
record must meet, built when called so that it may read the clock.")
   (limit :initarg :limit :reader trigger-limit :type (integer 1)
          :documentation "The most jobs one sweep enqueues."))
  (:documentation "A schedule that enqueues a job for every record meeting a condition."))

(defparameter +default-trigger-cron+ "* * * * *" "A trigger sweeps every minute unless it says otherwise.")
(defparameter +default-trigger-limit+ 1000)

(defparameter +trigger-options+ '(:where :cron :catch-up :limit)
  "The options of DEFINE-TRIGGER that are the trigger's; the rest are its job's.")

(defmacro define-trigger (name (variable-spec) (&rest options) &body body)
  "Define the trigger NAME: at each occurrence of :cron (every minute), enqueue
a job for every record of the entity that meets :where, a form giving a
SELECT condition, evaluated at each sweep and when each job runs.  The job
is named NAME, takes the record's id, is unique by it while incomplete, and
runs BODY with the record bound to the variable of VARIABLE-SPEC, VARIABLE
or (VARIABLE ENTITY); when the record is gone or no longer meets :where, the
job cancels itself.  :limit (1000) caps the jobs one sweep enqueues;
:catch-up is a schedule's; the other options are DEFINE-JOB's (spec/jobs.md 8.1)."
  (destructuring-bind (variable &optional (entity variable))
      (if (consp variable-spec) variable-spec (list variable-spec))
    (let ((where (getf options :where))
          (cron (getf options :cron +default-trigger-cron+))
          (catch-up (getf options :catch-up +default-catch-up+))
          (limit (getf options :limit +default-trigger-limit+))
          (job-options (loop for (key value) on options by #'cddr
                             unless (member key +trigger-options+) append (list key value)))
          (documentation (and (stringp (first body)) (rest body) (first body)))
          (body (if (and (stringp (first body)) (rest body)) (rest body) body)))
      (unless where
        (error "Trigger ~s needs :where, the condition its records meet" name))
      (when (getf job-options :unique)
        (error "Trigger ~s: a trigger's job is unique by its record; it takes no :unique" name))
      (parse-cron cron)                 ; a bad cron time fails the build
      `(progn
         (define-job ,name ((record-id :type (id ,entity) :required t))
             (:unique (:keys (record-id)) ,@job-options)
           ,@(and documentation (list documentation))
           (let ((,variable (trigger-record ',name record-id)))
             (declare (ignorable ,variable))
             ,@body))
         (register-schedule
          (make-instance 'trigger :name ,(json-name-of name) :cron (parse-cron ,cron) :job ',name
                                  :arguments '() :catch-up ,catch-up
                                  :entity ',entity :condition (lambda () ,where) :limit ,limit
                                  :module ,(current-definition-module)
                                  :location ,(current-source-location)))
         ',name))))

(defun trigger-where (trigger)
  (funcall (trigger-condition trigger)))

(defun trigger-record (name id)
  "The record ID of the trigger NAME as it is now.  Cancels the job when the
record is gone or no longer meets the trigger's condition."
  (let ((trigger (find-schedule (json-name-of name))))
    (unless (typep trigger 'trigger)
      (cancel-job (format nil "Utløseren ~a finnes ikke lenger" (json-name-of name))))
    (or (with-transaction (:read)
          (select-one (trigger-entity trigger)
                      :where `(:and (:= "id" ,id) ,(trigger-where trigger))))
        (cancel-job "Posten oppfyller ikke lenger utløserens vilkår"))))

(defun records-with-jobs (trigger)
  "The ids of the records whose job from TRIGGER waits or runs."
  (mapcar (lambda (job) (jget (job-arguments job) "record_id"))
          (select 'job :where `(:and (:= "kind" ,(json-name-of (schedule-job trigger)))
                                     (:in "state" ("queued" "running" "retrying"))))))

(defmethod run-occurrence ((trigger trigger))
  "Enqueue the job of every record that meets TRIGGER's condition and has no
job waiting or running, at most TRIGGER's limit."
  (let ((busy (records-with-jobs trigger))
        (jobs '()))
    (dolist (record (select (trigger-entity trigger) :where (trigger-where trigger)
                                                     :order-by '(("seq" :asc)))
                    (nreverse jobs))
      (when (>= (length jobs) (trigger-limit trigger))
        (return (nreverse jobs)))
      (unless (member (entity-id record) busy :test #'string=)
        (push (enqueue-job (schedule-job trigger) :record-id (entity-id record)) jobs)))))

(defmethod check-schedule ((trigger trigger))
  (unless (find-entity-class (trigger-entity trigger) nil)
    (extension-error "Trigger ~a sweeps ~s, which is not an entity"
                     (schedule-name trigger) (trigger-entity trigger)))
  (unless (find-job-definition (schedule-job trigger))
    (extension-error "Trigger ~a has no job; define it with define-trigger"
                     (schedule-name trigger))))

(defmethod schedule->json ((trigger trigger))
  (let ((json (call-next-method)))
    (setf (gethash "kind" json) "trigger"
          (gethash "entity" json) (entity-json-name (find-entity-class (trigger-entity trigger))))
    json))
