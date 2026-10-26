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
  (:core ">= 1.0" "< 2.0")
  (:documentation "Warehouse: tasks per department, with an event per change."))

(defun task-rollback-finding (task)
  (declare (ignore task))
  "warehouse task, which the older core cannot show")

(define-entity task (:label "Lageroppgave" :id-prefix "opg" :table "tasks" :revisioned t
                     :indexes (("department") ("assignee_id")) :rollback-check task-rollback-finding)
  ((revision :type (integer :min 1) :input nil :initform 1 :label "Revisjon")
   (department :type (string :max 100) :input nil :label "Avdeling")
   (title :type (string :max 160) :input nil :label "Tittel")
   (description :type (string :max 2000 :trim nil) :input nil :label "Beskrivelse")
   (status :type (enum "open" "completed") :input nil :initform "open" :label "Status")
   (due-date :type date :input nil :label "Frist")
   (assignee-id :type (id employee) :input nil :label "Ansvarlig")
   (created-by :type (string :max 200) :input nil :label "Opprettet av")
   (completed-at :type timestamp :input nil :label "Fullført")
   (completed-by :type (string :max 200) :input nil :label "Fullført av")
   (created-at :type timestamp :input nil :label "Opprettet")))

(define-entity task-event (:json-name "task_event" :label "Hendelse på lageroppgave" :id-prefix "tev"
                           :table "task_events" :indexes (("task_id")))
  ((task-id :type (id task) :input nil :label "Oppgave")
   (kind :type (enum "created" "changed" "assigned" "completed" "reopened") :input nil :label "Type")
   (actor :type (string :max 200) :input nil :label "Utført av")
   (at :type timestamp :input nil :label "Tidspunkt")
   (recipient-id :type (id employee) :input nil :label "Mottaker")
   (details :type json :input nil :label "Detaljer")))

;;; ------------------------------------------------------------------
;;; Helpers

(defun task-event! (task kind &key recipient-id details)
  (insert (make-instance 'task-event :task-id (entity-id task) :kind kind :actor (actor-string *actor*)
                                     :at (now) :recipient-id recipient-id :details (or details (jobj)))))

(defun deep-link (task) (jobj "deep_link" (format nil "/tasks/~a" (entity-id task))))

(defun check-task-department (department)
  (when (blank-p department)
    (fail :invalid-input "Velg avdeling for lageroppgaven"))
  (unless (member department (departments *application*) :test #'string=)
    (fail :invalid-input "Ukjent avdeling ~a (gyldige: ~{~a~^, ~})" department (departments *application*))))

(defun check-assignee (department employee-id)
  "The employee EMPLOYEE-ID, who must belong to DEPARTMENT now (or NIL for no one)."
  (when employee-id
    (let ((employee (fetch! 'employee employee-id)))
      (unless (equal (employee-department employee) department)
        (fail :invalid-input "Ansvarlig må tilhøre samme avdeling som lageroppgaven"))
      employee)))

(defun check-title (title)
  (let ((title (trim (or title ""))))
    (unless (<= 2 (length title) 160)
      (fail :invalid-input "Tittelen må ha mellom 2 og 160 tegn"))
    title))

(defun load-task (id revision)
  (let ((task (fetch! 'task id)))
    (when (and revision (/= revision (task-revision task)))
      (fail :conflict "Oppgaven er endret (revisjon ~d, ikke ~d)" (task-revision task) revision))
    task))

;;; ------------------------------------------------------------------
;;; Operations

(define-operation tasks-create ((department :type (string :max 100) :label "Avdeling")
                                (title :type (string :max 1000) :label "Tittel")
                                (description :type (string :max 2000 :trim nil) :label "Beskrivelse")
                                (due-date :type date :label "Frist")
                                (assignee-id :type (id employee) :label "Ansvarlig"))
    (:entity task :kind :create :policy :admin :title "Opprett lageroppgave"
     :description "En lageroppgave i en avdeling, med frist og eventuelt en ansvarlig fra samme avdeling.")
  (check-task-department department)
  (let ((title (check-title title)))
    (check-assignee department assignee-id)
    (let ((task (insert (make-instance 'task :department department :title title :description description
                                             :due-date due-date :assignee-id assignee-id
                                             :created-by (actor-string *actor*)))))
      (task-event! task "created" :recipient-id assignee-id :details (deep-link task))
      task)))

(define-operation tasks-update ((id :type (id task) :required t :label "Oppgave-ID")
                                (revision :type integer :required t :label "Revisjon")
                                (title :type (string :max 1000) :label "Tittel")
                                (description :type (string :max 2000 :trim nil) :label "Beskrivelse")
                                (due-date :type date :label "Frist"))
    (:entity task :kind :update :policy :admin :title "Endre lageroppgave"
     :description "Endrer tittel, beskrivelse eller frist.")
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

(define-operation tasks-assign ((id :type (id task) :required t :label "Oppgave-ID")
                                (revision :type integer :required t :label "Revisjon")
                                (assignee-id :type (id employee) :label "Ansvarlig"
                                             :description "Den ansatte som skal ha oppgaven; null fjerner tildelingen."))
    (:entity task :kind :update :policy :admin :title "Tildel lageroppgave"
     :description "Gir oppgaven en ansvarlig fra samme avdeling, eller fjerner tildelingen (null).")
  (let ((task (load-task id revision)))
    (when (equal assignee-id (task-assignee-id task))
      (fail :invalid-input "Oppgaven er allerede tildelt denne personen"))
    (check-assignee (task-department task) assignee-id)
    (setf (task-assignee-id task) assignee-id)
    (save task)
    (if assignee-id
        (task-event! task "assigned" :recipient-id assignee-id :details (deep-link task))
        (task-event! task "changed" :details (jobj "assignment_removed" t)))
    task))

(define-operation tasks-complete ((id :type (id task) :required t :label "Oppgave-ID")
                                  (revision :type integer :required t :label "Revisjon"))
    (:entity task :kind :transition :title "Fullfør lageroppgave"
     :description "Den ansvarlige i oppgavens avdeling (eller en admin) fullfører oppgaven.")
  (let ((task (fetch! 'task id)))
    (unless (eq :admin (actor-role *actor*))
      (let ((me (actor-employee)))
        (unless (and me (equal (entity-id me) (task-assignee-id task)))
          (reject :forbidden "Bare nåværende ansvarlig kan fullføre lageroppgaven"))
        (unless (equal (employee-department me) (task-department task))
          (reject :forbidden "Du må tilhøre samme avdeling som lageroppgaven for å fullføre den"))))
    (setf task (load-task id revision))
    (unless (string= (task-status task) "open")
      (fail :invalid-transition "Oppgaven er allerede fullført"))
    (setf (task-status task) "completed"
          (task-completed-at task) (now)
          (task-completed-by task) (actor-string *actor*))
    (save task)
    (task-event! task "completed")
    task))

(define-operation tasks-reopen ((id :type (id task) :required t :label "Oppgave-ID")
                                (revision :type integer :required t :label "Revisjon"))
    (:entity task :kind :transition :policy :admin :title "Gjenåpne lageroppgave"
     :description "En fullført oppgave blir åpen igjen.")
  (let ((task (load-task id revision)))
    (unless (string= (task-status task) "completed")
      (fail :invalid-transition "Oppgaven er ikke fullført"))
    (setf (task-status task) "open" (task-completed-at task) nil (task-completed-by task) nil)
    (save task)
    (task-event! task "reopened")
    task))

(define-operation tasks-list ((department :type (string :max 100) :label "Avdeling")
                              (status :type (enum "open" "completed") :label "Status")
                              (mine :type boolean :label "Mine"
                                    :description "Bare oppgaver i min avdeling eller tildelt meg.")
                              (query :type (string :max 200) :label "Søk i tittel og beskrivelse")
                              (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:entity task :kind :read :title "Lageroppgaver"
     :description "Åpne oppgaver først etter frist (uten frist sist), så de fullførte; nyeste først ellers.")
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

(define-operation tasks-get ((id :type (id task) :required t :label "Oppgave-ID"))
    (:entity task :kind :read :title "Hent lageroppgave" :description "Én lageroppgave.")
  (fetch! 'task id))

(define-operation task-events-list ((id :type (id task) :required t :label "Oppgave-ID")
                                    (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:entity task-event :kind :read :title "Hendelser på lageroppgave"
     :description "Hendelsene på oppgaven, eldste først: én per endring.")
  (fetch! 'task id)
  (page (select 'task-event :where `(:= "task_id" ,id) :order-by '(("seq" :asc)) :limit (1+ limit)) limit))

(publish '(task tasks-create tasks-update tasks-assign tasks-complete tasks-reopen tasks-list tasks-get
           task-events-list))

(seal-module "warehouse")
