;;;; platform/workflows.lisp -- durable workflows (kernel).
;;;;
;;;; Workflows are durable rows, and each planned one has a job
;;;; (spec/jobs.md 12), RUN-WORKFLOW in the :workflows queue, due when the
;;;; workflow is: jobs decide when it runs, which process takes it, and what
;;;; happens after a crash.  RUN-ONE-WORKFLOW decides how: inside its own
;;;; write transaction as the system actor, where the status change to
;;;; executed commits together with the handler's effects, so a workflow runs
;;;; at most once even across restarts; a handler that fails is rolled back
;;;; and marked failed with the error noted.
;;;;
;;;; Handlers are registered with DEFINE-WORKFLOW by modules and clients.  A
;;;; workflow refers to the record it is about by opaque id (order_id): the
;;;; kernel knows no business entity.

(defpackage #:tun.workflows
  (:use #:cl #:tun.core)
  (:import-from #:tun.jobs #:define-job #:enqueue-job #:cancel-job #:fail-job)
  (:export #:workflow #:workflow-kind #:workflow-order-id #:workflow-customer-id #:workflow-due-at
           #:workflow-key #:workflow-request-id #:workflow-status #:workflow-executed-at #:workflow-note #:workflow-subject-id
           #:schedule-workflow #:cancel-workflows #:cancel-subject-workflows #:cancel-customer-workflows #:pending-workflows #:run-due-workflows #:enqueue-planned-workflows #:note-workflow-run
           #:workflows-list #:workflows-get #:*running-workflow*))

(in-package #:tun.workflows)

(declaim (optimize (safety 3) (debug 2)))

(define-entity workflow (:label "Workflow" :id-prefix "wf" :table "workflows"
                         :indexes (("order_id") ("status" "due_at") ("kind" "key" "status")))
  ((key :type (string :max 200) :input nil :label "Key")
   (request-id :type id :input nil :label "Request")
   (kind :type (string :max 100) :input nil :label "Kind")
   (order-id :type id :input nil :label "Order")
   (customer-id :type id :input nil :label "Customer")
   (due-at :type timestamp :input nil :label "Due")
   (status :type (enum "planned" "executed" "cancelled" "failed") :input nil :initform "planned"
           :label "Status")
   (executed-at :type timestamp :input nil :label "Executed")
   (note :type (string :max 2000) :input nil :label "Note")
   (subject-id :type id :input nil :label "Subject"
               :description "The record a workflow not about an order is about (a catalog change).")))

(defun schedule-workflow (kind &key order order-id customer-id subject-id due-at key)
  "Plan a workflow of registered KIND for ORDER (an entity) or ORDER-ID (or,
for a workflow about something else, SUBJECT-ID), due at DUE-AT (universal
time)."
  (unless (find-workflow-kind kind)
    (error "Workflow kind ~s is not registered (define it with DEFINE-WORKFLOW)" kind))
  (check-type due-at universal-time)
  (when key
    (let ((existing (select-one 'workflow :where `(:and (:= "kind" ,kind) (:= "key" ,key) (:= "status" "planned")))))
      (when existing (return-from schedule-workflow existing))))
  (let ((workflow (insert (make-instance 'workflow :key key :kind kind
                                                   :order-id (or order-id (and order (entity-id order)))
                                                   :customer-id customer-id
                                                   :subject-id subject-id
                                                   :due-at due-at))))
    (enqueue-job 'run-workflow :workflow-id (entity-id workflow) :at due-at)
    workflow))

(defun pending-workflows (order-id &key kinds)
  (remove-if-not (lambda (w) (or (null kinds) (member (workflow-kind w) kinds :test #'string=)))
                 (select 'workflow :where `(:and (:= "order_id" ,order-id) (:= "status" "planned")))))

(defun cancel-workflows (order-id &key kinds note)
  "Cancel ORDER-ID's planned workflows (only KINDS when given). Returns how many."
  (let ((pending (pending-workflows order-id :kinds kinds)))
    (dolist (w pending)
      (setf (workflow-status w) "cancelled" (workflow-note w) note)
      (save w))
    (length pending)))

(defun cancel-matching-workflows (field id kinds note)
  (let ((rows (select 'workflow :where `(:and (:= ,field ,id) (:= "status" "planned")))))
    (loop for wf in rows when (or (null kinds) (member (workflow-kind wf) kinds :test #'equal))
          count (progn (setf (workflow-status wf) "cancelled" (workflow-note wf) note) (save wf) t))))
(defun cancel-subject-workflows (id &key kinds note) (cancel-matching-workflows "subject_id" id kinds note))
(defun cancel-customer-workflows (id &key kinds note) (cancel-matching-workflows "customer_id" id kinds note))

(defun claim-workflow (wf)
  "Mark WF (re-read under the write lock: another runner may have taken it)
executed; the current record, or NIL when it is no longer planned."
  (let ((current (fetch 'workflow (entity-id wf))))
    (when (and current (string= (workflow-status current) "planned"))
      (setf (workflow-request-id current) *request-id*
            (workflow-status current) "executed"
            (workflow-executed-at current) (now))
      (save current))))

(defvar *running-workflow* nil "The id of the workflow whose handler is running.")

(defun note-workflow-run (text)
  "Record TEXT as the note of the workflow run in progress: what it could not
do (a missing recipient, core.md §4.3), shown by workflows_get and
introspect_workflows.  The note is for people: write TEXT with TR, in the
tenant's language (spec/i18n.md 3.5)."
  (let ((id (or *running-workflow* (error "NOTE-WORKFLOW-RUN outside a workflow run"))))
    (flet ((note ()
             (let ((wf (fetch 'workflow id)))
               (setf (workflow-note wf) (subseq text 0 (min 2000 (length text))))
               (save wf))))
      (if (eq *transaction-mode* :write)
          (note)
          (with-transaction (:write) (note))))
    text))

(defun call-handler (kind current)
  (if kind
      (let ((*inside-operation* t)
            (*running-workflow* (entity-id current)))
        (with-step (:operation :name (format nil "workflow:~a" (workflow-kind-name kind))
                    :source (workflow-kind-source kind)
                    :detail (string-downcase (symbol-name (workflow-kind-function kind))))
          (funcall (workflow-kind-function kind) current)))
      (error "No handler registered for workflow kind ~s" (workflow-kind current))))

(defun run-one-workflow (wf)
  "Run WF as system:workflow, auditing the run; true when it ran.  Each run
is its own request (it cannot confirm a confirm-gated tool for itself, and
introspect_request shows it on its own), its own audit scope, and, when no
transaction is open (the scheduler, clock_set after its commit), its own
transaction and deadline: one failing or slow workflow never undoes or
blocks another (core.md §4.4).  A kind with own transactions is marked
done first and commits its own units of work."
  (let* ((kind (find-workflow-kind (workflow-kind wf)))
         (tool (format nil "workflow:~a" (workflow-kind wf)))
         (id (new-id "req"))
         (*request-id* id)
         (*deadline* (if *transaction-mode* *deadline* nil)))
    (with-step (:operation :name tool :source (if kind (workflow-kind-source kind) :core)
                :detail (format nil "its own request ~a" id))
      (with-request-record (:id id :at (now) :actor "system:workflow" :tool tool :kind :workflow :force-new t
                            :application *application*
                            :input (jobj "workflow_id" (entity-id wf) "kind" (workflow-kind wf)
                                         "order_id" (or (workflow-order-id wf) :null)))
        (let ((record *request-record*))
          (with-actor ((system-actor "workflow"))
            (with-step (:policy :name "system:workflow" :source :core)
              (set-request-policy record :employee :system "allow"))
            (with-audit-scope
              (handler-case
                  (with-backtrace-capture (record)
                    (if (and kind (workflow-kind-own-transactions-p kind) (null *transaction-mode*))
                        ;; Done first, then the handler's own units of work.
                        (let ((current (with-transaction (:write) (claim-workflow wf))))
                          (when current
                            (call-handler kind current)
                            (with-transaction (:write)
                              (write-system-audit tool "ok" :entity-type "workflow" :entity-id (entity-id current)))
                            t))
                        (with-deadline ()
                          (with-transaction (:write)
                            (let ((current (claim-workflow wf)))
                              (when current
                                (call-handler kind current)
                                (write-system-audit tool "ok" :entity-type "workflow" :entity-id (entity-id current))
                                t))))))
                (serious-condition (e)
                  (let ((text (ignore-errors (princ-to-string e))))
                    (choose-request-backtrace record e)
                    (set-request-outcome record "error" :code :workflow-failed
                                                        :message (or text "unknown error"))
                    (with-step (:rollback :name tool :source :core) nil)
                    (with-transaction (:write)
                      (let ((current (fetch 'workflow (entity-id wf))))
                        (when (and current (or (string= (workflow-status current) "planned")
                                               (and kind (workflow-kind-own-transactions-p kind))))
                          (setf (workflow-status current) "failed"
                                (workflow-request-id current) id
                                (workflow-executed-at current) (now)
                                (workflow-note current) (if text (subseq text 0 (min 2000 (length text))) "unknown error"))
                          (save current)
                          (write-system-audit tool "rejected" :entity-type "workflow" :entity-id (entity-id current)
                                                              :error-code "workflow_failed"))))
                    nil))))))))))

(define-job run-workflow ((workflow-id :type (id workflow) :required t))
    (:queue :workflows :transaction nil :max-attempts 3 :unique (:keys (workflow-id)))
  "Run the workflow WORKFLOW-ID if it is still planned.  A handler that fails
marks the workflow failed and fails the job at once; a crash before the run
committed leaves it planned, so the job's next attempt runs it."
  ;; As before every request: no workflow runs on a modified kernel.
  (unless (application-debug-tools-p *application*)
    (check-definition-integrity "run workflows"))
  (let ((wf (with-transaction (:read) (fetch 'workflow workflow-id))))
    (unless (and wf (string= (workflow-status wf) "planned"))
      (cancel-job (tr "The workflow is no longer planned")))
    (unless (run-one-workflow wf)
      (let ((after (with-transaction (:read) (fetch 'workflow workflow-id))))
        (if (string= (workflow-status after) "failed")
            (fail-job (or (workflow-note after) "The workflow failed"))
            (cancel-job (tr "The workflow was run or cancelled by another")))))))

(defun run-due-workflows (&key (limit 10000))
  "Run every due workflow now, in this thread, oldest due first, including
workflows that running ones schedule.  Returns how many ran."
  (nth-value 1 (tun.jobs:run-due-jobs :queue "workflows" :limit limit)))

(defun enqueue-planned-workflows ()
  "Give every planned workflow its job, due when it is, unless it has one:
for workflows stored before they ran on jobs.  Runs when the application
opens."
  (with-transaction (:write)
    (dolist (wf (select 'workflow :where '(:= "status" "planned")))
      (enqueue-job 'run-workflow :workflow-id (entity-id wf) :at (workflow-due-at wf)))))

;;; ------------------------------------------------------------------
;;; Operations

(define-operation workflows-list ((order-id :type id :schema-required t :label "Order ID")
                                   (customer-id :type id :label "Customer ID")
                                   (kind :type (string :max 100) :label "Kind")
                                   (status :type (enum "planned" "executed" "cancelled" "failed")
                                           :label "Status"))
    (:entity workflow :kind :read :title "Workflows")
  (unless (or order-id customer-id kind status)
    (fail :invalid-input "Give an order, a customer, a kind or a status"))
  (let ((where (remove nil (list (and order-id `(:= "order_id" ,order-id))
                                 (and customer-id `(:= "customer_id" ,customer-id))
                                 (and kind `(:= "kind" ,kind)) (and status `(:= "status" ,status))))))
    (jobj "items" (jarr (mapcar #'entity->json (select 'workflow :where `(:and ,@where)
                                                             :order-by '(("due_at" :asc))))))))

(define-operation workflows-get ((id :type (id workflow) :required t :label "Workflow ID"))
    (:entity workflow :kind :read :title "Get a workflow"
     :description "One workflow: its kind, due time, status and when it was executed.")
  (fetch! 'workflow id))
