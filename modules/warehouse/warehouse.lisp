;;;; modules/warehouse/warehouse.lisp -- the warehouse module: warehouse tasks
;;;; with an append-only event ledger (README §2, §3).
;;;;
;;;; A task belongs to one of the client's departments (staffing's
;;;; DEPARTMENTS).  Every mutation writes exactly one event in its own
;;;; transaction, so an event that cannot be written rolls the mutation back.
;;;; Tasks are never created from orders.

(defpackage #:tun.warehouse
  (:use #:cl #:tun.core #:tun.staffing)
  (:export #:task #:task-department #:task-title #:task-status #:task-assignee-id #:task-revision
           #:task-event #:tasks-create #:tasks-update #:tasks-assign #:tasks-complete #:tasks-reopen
           #:tasks-list #:tasks-get #:task-events-list))

(in-package #:tun.warehouse)

(declaim (optimize (safety 3) (debug 2)))

(define-module warehouse
  (:depends-on staffing)
  (:core ">= 2.0.0" "< 3.0")
  (:documentation "Warehouse: tasks per department, with an event per change."))

(defun task-rollback-finding (task)
  (declare (ignore task))
  "warehouse task, which the older core cannot show")

(define-entity task (:label "Warehouse task" :id-prefix "opg" :table "tasks" :revisioned t
                     :indexes (("department") ("assignee_id")) :rollback-check task-rollback-finding)
  ((revision :type (integer :min 1) :input nil :initform 1 :label "Revision")
   (department :type (string :max 100) :input nil :label "Department")
   (title :type (string :max 160) :input nil :label "Title")
   (description :type (string :max 2000 :trim nil) :input nil :label "Description")
   (status :type (enum "open" "completed") :input nil :initform "open" :label "Status")
   (due-date :type date :input nil :label "Due date")
   (assignee-id :type (id employee) :input nil :label "Assignee")
   (created-by :type (string :max 200) :input nil :label "Created by")
   (completed-at :type timestamp :input nil :label "Completed")
   (completed-by :type (string :max 200) :input nil :label "Completed by")
   (created-at :type timestamp :input nil :label "Created")))

(define-entity task-event (:json-name "task_event" :label "Event on a warehouse task"
                                      :id-prefix "tev" :table "task_events" :indexes (("task_id")))
  ((task-id :type (id task) :input nil :label "Task")
   (kind :type (enum "created" "changed" "assigned" "completed" "reopened") :input nil
         :label "Kind")
   (actor :type (string :max 200) :input nil :label "Done by")
   (at :type timestamp :input nil :label "Time")
   (recipient-id :type (id employee) :input nil :label "Recipient")
   (details :type json :input nil :label "Event details")))

;;; ------------------------------------------------------------------
;;; Helpers

(defun task-event! (task kind &key recipient-id details)
  (insert (make-instance 'task-event :task-id (entity-id task) :kind kind :actor (actor-string *actor*)
                                     :at (now) :recipient-id recipient-id :details (or details (jobj)))))

(defun deep-link (task) (jobj "deep_link" (format nil "/tasks/~a" (entity-id task))))

(defun check-task-department (department)
  (when (blank-p department)
    (fail :invalid-input "Choose a department for the warehouse task"))
  (unless (member department (departments *application*) :test #'string=)
    (fail :invalid-input "Unknown department ~a (valid: ~{~a~^, ~})"
          department (departments *application*))))

(defun check-assignee (department employee-id)
  "The employee EMPLOYEE-ID, who must belong to DEPARTMENT now (or NIL for no one)."
  (when employee-id
    (let ((employee (fetch! 'employee employee-id)))
      (unless (equal (employee-department employee) department)
        (fail :invalid-input "The assignee must belong to the warehouse task's department"))
      employee)))

(defun check-title (title)
  (let ((title (trim (or title ""))))
    (unless (<= 2 (length title) 160)
      (fail :invalid-input "The title must have between 2 and 160 characters"))
    title))

(defun load-task (id revision)
  (let ((task (fetch! 'task id)))
    (when (and revision (/= revision (task-revision task)))
      (fail :conflict "The task has changed (revision ~d, not ~d)" (task-revision task) revision))
    task))

;;; ------------------------------------------------------------------
;;; Operations

(define-operation tasks-create ((department :type (string :max 100) :label "Department")
                                (title :type (string :max 1000) :label "Title")
                                (description :type (string :max 2000 :trim nil) :label "Description")
                                (due-date :type date :label "Due date")
                                (assignee-id :type (id employee) :label "Assignee"))
    (:entity task :kind :create :policy :admin :title "Create a warehouse task"
             :description "A warehouse task in a department, with a due date and perhaps an assignee
from the same department.")
  (check-task-department department)
  (let ((title (check-title title)))
    (check-assignee department assignee-id)
    (let ((task (insert (make-instance 'task :department department :title title :description description
                                             :due-date due-date :assignee-id assignee-id
                                             :created-by (actor-string *actor*)))))
      (task-event! task "created" :recipient-id assignee-id :details (deep-link task))
      task)))

(define-operation tasks-update ((id :type (id task) :required t :label "Task ID")
                                (revision :type integer :required t :label "Revision")
                                (title :type (string :max 1000) :label "Title")
                                (description :type (string :max 2000 :trim nil) :label "Description")
                                (due-date :type date :label "Due date"))
    (:entity task :kind :update :policy :admin :title "Change a warehouse task"
             :description "Changes the title, the description or the due date.")
  (let ((task (load-task id revision))
        (changed '()))
    (when (input-provided-p :title)
      (setf (task-title task) (check-title title))
      (push "title" changed))
    (when (or (input-provided-p :description) (input-null-p :description))
      (setf (task-description task) description)
      (push "description" changed))
    (when (or (input-provided-p :due-date) (input-null-p :due-date))
      (setf (task-due-date task) due-date)
      (push "due_date" changed))
    (save task)
    (task-event! task "changed" :details (jobj "fields" (jarr (sort changed #'string<))))
    task))

(define-operation tasks-assign
    ((id :type (id task) :required t :label "Task ID")
     (revision :type integer :required t :label "Revision")
     (assignee-id :type (id employee) :label "Assignee"
                  :description "The employee who is to have the task; null removes the assignment."))
    (:entity task :kind :update :policy :admin :title "Assign a warehouse task"
             :description "Gives the task an assignee from the same department, or removes the
assignment (null).")
  (let ((task (load-task id revision)))
    (when (equal assignee-id (task-assignee-id task))
      (fail :invalid-input "The task is already assigned to this person"))
    (check-assignee (task-department task) assignee-id)
    (setf (task-assignee-id task) assignee-id)
    (save task)
    (if assignee-id
        (task-event! task "assigned" :recipient-id assignee-id :details (deep-link task))
        (task-event! task "changed" :details (jobj "assignment_removed" t)))
    task))

(define-operation tasks-complete ((id :type (id task) :required t :label "Task ID")
                                  (revision :type integer :required t :label "Revision"))
    (:entity task :kind :transition :title "Complete a warehouse task"
             :description "The assignee in the task's department (or an admin) completes the task.")
  (let ((task (fetch! 'task id)))
    (unless (eq :admin (actor-role *actor*))
      (let ((me (actor-employee)))
        (unless (and me (equal (entity-id me) (task-assignee-id task)))
          (reject :forbidden "Only the current assignee can complete the warehouse task"))
        (unless (equal (employee-department me) (task-department task))
          (reject :forbidden
                  "You must belong to the warehouse task's department to complete it"))))
    (setf task (load-task id revision))
    (unless (string= (task-status task) "open")
      (fail :invalid-transition "The task is already completed"))
    (setf (task-status task) "completed"
          (task-completed-at task) (now)
          (task-completed-by task) (actor-string *actor*))
    (save task)
    (task-event! task "completed")
    task))

(define-operation tasks-reopen ((id :type (id task) :required t :label "Task ID")
                                (revision :type integer :required t :label "Revision"))
    (:entity task :kind :transition :policy :admin :title "Reopen a warehouse task"
             :description "A completed task becomes open again.")
  (let ((task (load-task id revision)))
    (unless (string= (task-status task) "completed")
      (fail :invalid-transition "The task is not completed"))
    (setf (task-status task) "open" (task-completed-at task) nil (task-completed-by task) nil)
    (save task)
    (task-event! task "reopened")
    task))

(define-operation tasks-list ((department :type (string :max 100) :label "Department")
                              (status :type (enum "open" "completed") :label "Status")
                              (mine :type boolean :label "Mine"
                                    :description "Only the tasks in my department or assigned to me.")
                              (query :type (string :max 200) :label "Search the title and description")
                              (limit :type (integer :min 1 :max 100) :default 20 :label "Limit"))
    (:entity task :kind :read :title "Warehouse tasks"
             :description "Open tasks first by due date (those without one last), then the completed
ones; newest first otherwise.")
  (let ((me (and mine (actor-employee))))
    (if (and mine (null me))
        (page '() limit)
        (let* ((where (remove nil (list (and department `(:= "department" ,department))
                                        (and status `(:= "status" ,status)))))
               (rows (select 'task :where (and where `(:and ,@where)) :order-by '(("seq" :desc))))
               (hits (remove-if-not
                      (lambda (task)
                        (and (or (null me)
                                 (equal (task-department task) (employee-department me))
                                 (equal (task-assignee-id task) (entity-id me)))
                             (or (null query)
                                 (contains-ci-p query (or (task-title task) ""))
                                 (contains-ci-p query (or (task-description task) "")))))
                      rows)))
          (flet ((rank (task)
                   (list (if (string= (task-status task) "open") 0 1)
                         (if (task-due-date task) 0 1)
                         (or (task-due-date task) ""))))
            (page (stable-sort hits (lambda (a b)
                                      (destructuring-bind (s1 n1 d1) (rank a)
                                        (destructuring-bind (s2 n2 d2) (rank b)
                                          (or (< s1 s2)
                                              (and (= s1 s2) (or (< n1 n2)
                                                                 (and (= n1 n2) (string< d1 d2)))))))))
                  limit))))))

(define-operation tasks-get ((id :type (id task) :required t :label "Task ID"))
    (:entity task :kind :read :title "Get a warehouse task" :description "One warehouse task.")
  (fetch! 'task id))

(define-operation task-events-list ((id :type (id task) :required t :label "Task ID")
                                    (limit :type (integer :min 1 :max 100) :default 20 :label "Limit"))
    (:entity task-event :kind :read :title "Events on a warehouse task"
             :description "The events on the task, oldest first: one per change.")
  (fetch! 'task id)
  (page (select 'task-event :where `(:= "task_id" ,id) :order-by '(("seq" :asc)) :limit (1+ limit)) limit))

(publish '(task tasks-create tasks-update tasks-assign tasks-complete tasks-reopen tasks-list tasks-get
           task-events-list))

(seal-module "warehouse")
