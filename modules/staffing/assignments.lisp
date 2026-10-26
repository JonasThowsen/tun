;;;; modules/staffing/assignments.lisp -- assignments of employees to orders
;;;; (README §3), unavailability conflicts and overrides (README §4), automatic
;;;; assignment by department (README §5) and work sessions (README §6).

(in-package #:tun.staffing)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +stop-timer-message+ "Stopp aktiv timer før tildelingen avsluttes")

(defun active-assignments (&key order-id employee-id)
  (let ((where (remove nil (list (and order-id `(:= "order_id" ,order-id))
                                 (and employee-id `(:= "employee_id" ,employee-id))
                                 '(:null "ended_at")))))
    (select 'assignment :where `(:and ,@where))))

(defun running-sessions (&key order-id employee-id assignment-id)
  (let ((where (remove nil (list (and order-id `(:= "order_id" ,order-id))
                                 (and employee-id `(:= "employee_id" ,employee-id))
                                 (and assignment-id `(:= "assignment_id" ,assignment-id))
                                 '(:null "ended_at")))))
    (select 'work-session :where `(:and ,@where))))

(defun end-assignment (assignment)
  "End ASSIGNMENT now; refused (conflict) while a work session on it runs."
  (when (running-sessions :assignment-id (entity-id assignment))
    (fail :conflict "~a" +stop-timer-message+))
  (setf (assignment-ended-at assignment) (now))
  (save assignment))

(defun order-assignees (order-id)
  "Names of the employees actively assigned to ORDER-ID, in assignment order."
  (loop for a in (active-assignments :order-id order-id)
        for employee = (fetch 'employee (assignment-employee-id a))
        when employee collect (employee-name employee)))

(define-computed-field order assignments (order) (:type json :label "Tildelt")
  (jarr (loop for a in (and (entity-id order) (active-assignments :order-id (entity-id order)))
              for employee = (fetch 'employee (assignment-employee-id a))
              collect (jobj "id" (entity-id a) "employee_id" (assignment-employee-id a)
                            "employee_name" (if employee (employee-name employee) :null)
                            "auto" (json-bool (assignment-auto a))))))

;;; ------------------------------------------------------------------
;;; Automatic assignment by department (README §5)

(defun auto-assignment-fits-p (assignment order)
  "Step 1: an automatic assignment stays only while its department, the
employee's and the order's agree, the employee is auto-assigned and active."
  (let ((employee (fetch 'employee (assignment-employee-id assignment))))
    (and employee
         (order-department order)
         (equal (assignment-auto-department assignment) (order-department order))
         (equal (employee-department employee) (order-department order))
         (employee-auto-assign-in-department employee)
         (employee-active employee))))

(defun reconcile-order-assignments (order)
  "Run README §5 for ORDER (its department was set or changed): end the automatic
assignments that no longer fit, then assign the eligible employees of the
department who are not assigned, not unavailable and not refused by the
eligibility rule, in creation order (ids are opaque, so the store's
insertion order is the deterministic order README §5.2 asks for)."
  (let ((order-id (entity-id order)))
    (dolist (a (active-assignments :order-id order-id))
      (when (and (assignment-auto a) (not (auto-assignment-fits-p a order)))
        (end-assignment a)))
    (when (order-department order)
      (let ((interval (order-interval order)))
        (dolist (employee (select 'employee :where `(:= "department" ,(order-department order))))
          (when (and (employee-auto-assign-in-department employee)
                     (employee-active employee)
                     (null (active-assignments :order-id order-id :employee-id (entity-id employee)))
                     (null (employee-unavailable-p (entity-id employee) interval))
                     (null (assignment-eligibility *application* order employee)))
            (store-assignment (make-instance 'assignment :order-id order-id :employee-id (entity-id employee)
                                               :auto t :auto-department (order-department order)
                                               :started-at (now)))))))))

(defmethod order-department-changed ((application staffing-module) order previous)
  (declare (ignore previous))
  (call-next-method)
  (reconcile-order-assignments order))

(defmethod order-closure-check ((application staffing-module) order tool)
  (declare (ignore tool))
  (call-next-method)
  (when (running-sessions :order-id (entity-id order))
    (fail :conflict "Stopp aktive timer før ordren avsluttes")))

(defun reconcile-employee (employee)
  "After an employee's settings change: end their automatic assignments that
no longer fit, everywhere (locked orders too).  Never assigns retroactively."
  (dolist (a (active-assignments :employee-id (entity-id employee)))
    (when (assignment-auto a)
      (let ((order (fetch 'order (assignment-order-id a))))
        (unless (and order (auto-assignment-fits-p a order))
          (end-assignment a)
          (when order (touch-order order)))))))

(define-operation employees-update ((id :type (id employee) :required t :label "Ansatt-ID")
                                    (:field employee name)
                                    (:field employee actor)
                                    (:field employee role)
                                    (:field employee department)
                                    (:field employee auto-assign-in-department)
                                    (:field employee active))
    (:entity employee :kind :update :policy :admin :title "Endre ansatt"
     :description "Endrer en ansatt. Endret rolle, avdeling, automatisk tildeling eller aktiv-status avslutter de automatiske tildelingene som ikke lenger passer (aldri manuelle, og aldri nye tildelinger bakover i tid).")
  (let* ((employee (fetch! 'employee id))
         (before (list (employee-role employee) (employee-department employee)
                       (employee-auto-assign-in-department employee) (employee-active employee))))
    (macrolet ((update (key accessor)
                 `(cond ((input-provided-p ,key) (setf (,accessor employee) (input-value ,key)))
                        ((input-null-p ,key) (setf (,accessor employee) nil)))))
      (update :name employee-name)
      (update :actor employee-actor)
      (update :role employee-role)
      (update :department employee-department)
      (update :auto-assign-in-department employee-auto-assign-in-department)
      (update :active employee-active))
    (check-employee employee)
    (let ((other (select-one 'employee :where `(:= "actor" ,(employee-actor employee)))))
      (when (and other (string/= (entity-id other) id))
        (fail :conflict "Aktøren ~a er allerede knyttet til en ansatt" (employee-actor employee))))
    (save employee)
    (unless (equal before (list (employee-role employee) (employee-department employee)
                                (employee-auto-assign-in-department employee) (employee-active employee)))
      (reconcile-employee employee))
    employee))

;;; ------------------------------------------------------------------
;;; Manual assignments, conflicts and overrides (README §3, §4)

(define-operation assignments-create ((order-id :type (id order) :required t :label "Ordre-ID")
                                      (employee-id :type (id employee) :required t :label "Ansatt-ID")
                                      (override-reason :type (string :max 10000) :label "Begrunnelse for overstyring"
                                                       :description "Påkrevd når den ansatte er utilgjengelig i ordreperioden (1–500 tegn)."))
    (:entity assignment :kind :create :policy :admin :title "Tildel ansatt"
     :description "Tildeler en ansatt til en ordre. Er den ansatte utilgjengelig i ordreperioden (hele dager), kreves en begrunnelse, og overstyringen lagres sammen med tildelingen.")
  (let ((order (find-order order-id))
        (employee (fetch! 'employee employee-id)))
    (when (member (order-status order) '("avbrutt" "fullført") :test #'string=)
      (fail :invalid-transition "Ordren har status ~a; ingen kan tildeles" (order-status order)))
    (check-order-not-locked order)
    (unless (employee-active employee)
      (fail :invalid-input "Den ansatte er ikke aktiv"))
    (when (active-assignments :order-id order-id :employee-id employee-id)
      (fail :conflict "Den ansatte er allerede tildelt ordren"))
    (let ((refusal (assignment-eligibility *application* order employee)))
      (when refusal (fail :invalid-input "~a" refusal)))
    (let* ((conflicts (employee-unavailable-p employee-id (order-interval order)))
           (reason (and override-reason (trim override-reason))))
      (when conflicts
        (unless (eq :admin (actor-role *actor*))
          (reject :forbidden "Den ansatte er utilgjengelig i ordreperioden og kan ikke tildeles"))
        (when (blank-p reason)
          (fail :invalid-input "Begrunnelse er påkrevd ved overstyring av utilgjengelighet"))
        (when (> (length reason) 500)
          (fail :invalid-input "Begrunnelsen kan ikke være lengre enn 500 tegn")))
      (let ((assignment (store-assignment (make-instance 'assignment :order-id order-id :employee-id employee-id
                                                           :auto nil :started-at (now)))))
        (when conflicts
          (insert (make-instance 'assignment-override
                                 :assignment-id (entity-id assignment) :order-id order-id :employee-id employee-id
                                 :reason reason :conflict-ids (mapcar #'entity-id conflicts)
                                 :conflict-summary (format nil "~{~a~^; ~}" (mapcar #'entry-summary conflicts))
                                 :created-by (actor-string *actor*)))
          (audit-as :reason reason))
        (touch-order order)
        assignment))))

(define-operation assignments-end ((id :type (id assignment) :required t :label "Tildelings-ID"))
    (:entity assignment :kind :transition :policy :admin :title "Avslutt tildeling"
     :description "Avslutter en tildeling (den beholdes, med sine arbeidsøkter). Ikke mens en timer på den går.")
  (let* ((assignment (fetch! 'assignment id))
         (order (find-order (assignment-order-id assignment))))
    (check-order-not-locked order)
    (when (assignment-ended-at assignment)
      (fail :invalid-transition "Tildelingen er allerede avsluttet"))
    (end-assignment assignment)
    (touch-order order)
    assignment))

(define-operation assignments-list ((order-id :type (id order) :label "Ordre-ID")
                                    (employee-id :type (id employee) :label "Ansatt-ID")
                                    (mine :type boolean :label "Mine" :description "Bare tildelinger til din ansattpost.")
                                    (active :type boolean :default t :label "Aktive"
                                            :description "true (standard): bare aktive; false: bare avsluttede."))
    (:entity assignment :kind :read :title "Tildelinger"
     :description "Tildelinger, filtrert på ordre, ansatt, dine egne (mine) og aktive.")
  (let ((me (and mine (actor-employee))))
    (if (and mine (null me))
        (jobj "items" (jarr '()))
        (let ((where (remove nil (list (and order-id `(:= "order_id" ,order-id))
                                       (and employee-id `(:= "employee_id" ,employee-id))
                                       (and me `(:= "employee_id" ,(entity-id me)))
                                       (if active '(:null "ended_at") '(:not-null "ended_at"))))))
          (jobj "items" (jarr (mapcar #'entity->json (select 'assignment :where `(:and ,@where)))))))))

(define-operation assignment-overrides-list ((order-id :type (id order) :required t :label "Ordre-ID"))
    (:entity assignment-override :kind :read :policy :admin :title "Overstyringer"
     :description "Overstyringer av utilgjengelighet på en ordre (bare tillegg; aldri endret).")
  (find-order order-id)
  (jobj "items" (jarr (mapcar #'entity->json (select 'assignment-override :where `(:= "order_id" ,order-id))))))

;;; ------------------------------------------------------------------
;;; Work sessions (README §6)

(defun own-assignment (order-id assignment-id &key active)
  "The actor's own assignment ASSIGNMENT-ID on ORDER-ID, else forbidden."
  (let* ((assignment (fetch 'assignment assignment-id))
         (me (actor-employee)))
    (unless (and assignment me
                 (string= (assignment-order-id assignment) order-id)
                 (string= (assignment-employee-id assignment) (entity-id me))
                 (or (not active) (null (assignment-ended-at assignment))))
      (reject :forbidden "Tildelingen ~a er ikke din aktive tildeling på ordre ~a" assignment-id order-id))
    (values assignment me)))

(define-operation work-sessions-start ((order-id :type (id order) :required t :label "Ordre-ID")
                                       (assignment-id :type (id assignment) :required t :label "Tildelings-ID")
                                       (note :type (string :max 1000) :label "Merknad"))
    (:entity work-session :kind :create :title "Start timer"
     :description "Starter en arbeidsøkt på din aktive tildeling. Ordren må være aktiv i kalenderen; du kan ha én timer om gangen.")
  (let ((order (find-order order-id)))
    (multiple-value-bind (assignment me) (own-assignment order-id assignment-id :active t)
      (unless (member (order-status order) +calendar-active-statuses+ :test #'string=)
        (fail :invalid-transition "Ordren har status ~a; timer kan ikke startes" (order-status order)))
      (when (running-sessions :employee-id (entity-id me))
        (fail :conflict "Du har allerede en aktiv timer"))
      (insert (make-instance 'work-session :order-id order-id :assignment-id (entity-id assignment)
                                           :employee-id (entity-id me) :started-at (now) :note note
                                           :source "live")))))

(define-operation work-sessions-stop ()
    (:entity work-session :kind :transition :title "Stopp timer"
     :description "Stopper din løpende arbeidsøkt (alltid tillatt). Varighet minst ett sekund.")
  (let* ((me (actor-employee))
         (session (and me (first (running-sessions :employee-id (entity-id me))))))
    (unless session (fail :not-found "Du har ingen aktiv timer"))
    (setf (work-session-ended-at session) (now)
          (work-session-duration-seconds session) (max 1 (- (now) (work-session-started-at session))))
    (save session)))

(define-operation work-sessions-create-manual ((order-id :type (id order) :required t :label "Ordre-ID")
                                               (assignment-id :type (id assignment) :required t :label "Tildelings-ID")
                                               (started-at :type timestamp :required t :label "Start")
                                               (ended-at :type timestamp :required t :label "Slutt")
                                               (note :type (string :max 1000) :label "Merknad"))
    (:entity work-session :kind :create :title "Registrer arbeidsøkt"
     :description "Registrerer en arbeidsøkt i etterkant på din tildeling. Varighet minst ett minutt.")
  (find-order order-id)
  (multiple-value-bind (assignment me) (own-assignment order-id assignment-id)
    (unless (> ended-at started-at)
      (fail :invalid-input "Sluttid må være etter starttid"))
    (insert (make-instance 'work-session :order-id order-id :assignment-id (entity-id assignment)
                                         :employee-id (entity-id me) :started-at started-at :ended-at ended-at
                                         :duration-seconds (max 60 (- ended-at started-at)) :note note
                                         :source "manual"))))

(define-operation work-sessions-list ((order-id :type (id order) :label "Ordre-ID")
                                      (mine :type boolean :label "Mine")
                                      (from :type date :label "Fra dato") (to :type date :label "Til dato"))
    (:entity work-session :kind :read :title "Arbeidsøkter"
     :description "Arbeidsøkter, filtrert på ordre, dine egne (mine) og periode (startdato, norsk tid).")
  (let ((me (and mine (actor-employee))))
    (if (and mine (null me))
        (jobj "items" (jarr '()))
        (let* ((where (remove nil (list (and order-id `(:= "order_id" ,order-id))
                                        (and me `(:= "employee_id" ,(entity-id me))))))
               (sessions (select 'work-session :where (and where `(:and ,@where)))))
          (jobj "items" (jarr (loop for s in sessions
                                    for day = (local-date-of (work-session-started-at s))
                                    when (and (or (null from) (date<= from day)) (or (null to) (date<= day to)))
                                      collect (entity->json s))))))))

(defun store-assignment (assignment)
  (insert assignment)
  (assignment-created *application* assignment)
  assignment)
