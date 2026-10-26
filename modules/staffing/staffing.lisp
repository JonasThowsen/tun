;;;; modules/staffing/staffing.lisp -- the staffing module: employees and the
;;;; client's departments (README §2), Norwegian local time to UTC (README §8),
;;;; and the module's entities.
;;;;
;;;; Extension points it publishes:
;;;;   DEPARTMENTS             departments             the client's departments (such as nord
;;;;                                                   and sør)
;;;;   ASSIGNMENT-ELIGIBILITY  assignment_eligibility  a rule that may refuse assigning an employee to an
;;;;                                                   order, with a message
;;;; and it implements the orders module's departments, department_changed
;;;; (automatic assignment, README §5) and closure_guard (running work sessions)
;;;; seams.

(defpackage #:tun.staffing
  (:use #:cl #:tun.core #:tun.orders)
  (:export #:employee #:employee-name #:employee-actor #:employee-role #:employee-department
           #:employee-auto-assign-in-department #:employee-active
           #:assignment #:assignment-order-id #:assignment-employee-id #:assignment-auto
           #:assignment-auto-department #:assignment-started-at #:assignment-ended-at
           #:assignment-override #:unavailability #:work-session
           #:departments #:assignment-eligibility
           #:actor-employee #:active-assignments #:order-assignees #:employee-unavailable-p
           #:to-utc #:whole-days-interval #:unavailability-interval
           #:employees-create #:employees-get #:employees-list #:employees-update
           #:assignment-created #:assignments-create #:assignments-end #:assignments-list #:assignment-overrides-list
           #:work-sessions-start #:work-sessions-stop #:work-sessions-create-manual #:work-sessions-list
           #:unavailability-create #:unavailability-update #:unavailability-delete #:unavailability-list))

(in-package #:tun.staffing)

(declaim (optimize (safety 3) (debug 2)))

(define-module staffing
  (:depends-on orders)
  (:core ">= 1.0" "< 2.0")
  (:documentation "Staffing: employees, departments, assignments, unavailability, work sessions."))

;;; ------------------------------------------------------------------
;;; Entities

(define-entity employee (:label "Ansatt" :id-prefix "emp" :table "employees" :unique (("actor"))
                         :indexes (("department")))
  ((name :type (string :min 1 :max 120) :required t :label "Navn")
   (actor :type (string :min 3 :max 200) :required t :label "Aktør"
          :description "Den nøyaktige X-Tun-Actor-verdien, f.eks. employee:kari (unik).")
   (role :type (enum "viewer" "employee" "admin") :required t :label "Rolle")
   (department :type (string :max 100) :label "Avdeling")
   (auto-assign-in-department :type boolean :initform nil :label "Tildeles automatisk i avdelingen")
   (active :type boolean :initform t :label "Aktiv")
   (created-at :type timestamp :input nil :label "Opprettet")))

(define-entity assignment (:label "Tildeling" :id-prefix "asg" :table "assignments"
                           :indexes (("order_id") ("employee_id")))
  ((order-id :type (id order) :input nil :label "Ordre")
   (employee-id :type (id employee) :input nil :label "Ansatt")
   (auto :type boolean :input nil :initform nil :label "Automatisk")
   (auto-department :type (string :max 100) :input nil :label "Avdeling (automatisk)")
   (started-at :type timestamp :input nil :label "Start")
   (ended-at :type timestamp :input nil :label "Slutt")))

(define-entity assignment-override (:json-name "assignment_override" :label "Overstyring av utilgjengelighet"
                                    :id-prefix "ovr" :table "assignment_overrides" :indexes (("order_id")))
  ((assignment-id :type (id assignment) :input nil :label "Tildeling")
   (order-id :type (id order) :input nil :label "Ordre")
   (employee-id :type (id employee) :input nil :label "Ansatt")
   (reason :type (string :max 500) :input nil :label "Begrunnelse")
   (conflict-ids :type (list-of id) :input nil :label "Utilgjengeligheter")
   (conflict-summary :type (string :max 5000) :input nil :label "Konflikter")
   (created-by :type (string :max 200) :input nil :label "Overstyrt av")
   (created-at :type timestamp :input nil :label "Opprettet")))

(define-entity unavailability (:label "Utilgjengelighet" :id-prefix "una" :table "unavailabilities"
                               :indexes (("employee_id" "start_date")))
  ((employee-id :type (id employee) :input nil :label "Ansatt")
   (start-date :type date :input nil :label "Fra dato")
   (end-date :type date :input nil :label "Til dato")
   (whole-day :type boolean :input nil :initform t :label "Hele dager")
   (start-time :type (string :max 5) :input nil :label "Fra klokken")
   (end-time :type (string :max 5) :input nil :label "Til klokken")
   (private-note :type (string :max 1000) :input nil :label "Privat merknad")
   (version :type (integer :min 1) :input nil :initform 1 :label "Versjon")))

(define-entity work-session (:json-name "work_session" :label "Arbeidsøkt" :id-prefix "wks" :table "work_sessions"
                             :indexes (("order_id") ("employee_id" "ended_at")))
  ((order-id :type (id order) :input nil :label "Ordre")
   (assignment-id :type (id assignment) :input nil :label "Tildeling")
   (employee-id :type (id employee) :input nil :label "Ansatt")
   (started-at :type timestamp :input nil :label "Start")
   (ended-at :type timestamp :input nil :label "Slutt")
   (duration-seconds :type integer :input nil :label "Varighet (sekunder)")
   (note :type (string :max 1000) :input nil :label "Merknad")
   (source :type (enum "live" "manual") :input nil :initform "live" :label "Kilde")))

;;; ------------------------------------------------------------------
;;; Extension points

(defgeneric departments (application)
  (:method-combination traced-protocol)
  (:documentation "The departments of this business (a client declares them).  An
order and an employee may name one of them or none.")
  (:method ((application staffing-module))
    '()))

(defgeneric assignment-eligibility (application order employee)
  (:method-combination traced-protocol)
  (:documentation "NIL when EMPLOYEE may be assigned to ORDER, else the refusal's
message (answered invalid_input).  A client adds a rule with a method.")
  (:method ((application staffing-module) order employee)
    (declare (ignore order employee))
    nil))

(register-extension-protocol 'departments "rule" :point "departments"
                             :description "The business's departments (orders and employees name them).")
(register-extension-protocol 'assignment-eligibility "rule" :point "assignment_eligibility"
                             :description "May refuse assigning an employee to an order, with a message.")

;; The orders module asks staffing which departments an order may name, and
;; the catalog which ones may own a product or a stock article.
(defmethod order-departments ((application staffing-module))
  (append (call-next-method) (departments application)))

(defmethod tun.catalog:catalog-departments ((application staffing-module))
  (append (call-next-method) (departments application)))

(defun check-department (department)
  (when (and department (not (member department (departments *application*) :test #'string=)))
    (fail :invalid-input "Ukjent avdeling ~a (gyldige: ~{~a~^, ~})" department (departments *application*))))

;;; ------------------------------------------------------------------
;;; Norwegian local time to UTC (README §8).  The other direction, and the rule
;;; for when summer time applies, are the kernel's (OSLO-OFFSET, core.md §2.2).

(defun parse-local-time (time)
  "Values hours and minutes of an HH:MM string, or NIL."
  (and (stringp time) (cl-ppcre:scan "^([01][0-9]|2[0-3]):[0-5][0-9]$" time)
       (values (parse-integer time :end 2) (parse-integer time :start 3))))

(defun to-utc (date time)
  "Values the instant of Norwegian local DATE and TIME and :ok, or NIL and
:nonexistent (in the spring gap) or :ambiguous (in the autumn overlap): of
the CET and CEST readings, exactly one must be a real instant."
  (multiple-value-bind (hours minutes) (parse-local-time time)
    (let* ((wall (+ (parse-date date) (* 3600 hours) (* 60 minutes)))
           (as-cet (- wall 3600))
           (as-cest (- wall 7200))
           (cet-p (= 3600 (oslo-offset as-cet)))
           (cest-p (= 7200 (oslo-offset as-cest))))
      (cond ((and cet-p cest-p) (values nil :ambiguous))
            (cet-p (values as-cet :ok))
            (cest-p (values as-cest :ok))
            (t (values nil :nonexistent))))))

(defun local-midnight (date)
  (values (to-utc date "00:00")))

(defun whole-days-interval (first last)
  "[local midnight of FIRST, local midnight of the day after LAST)."
  (cons (local-midnight first) (local-midnight (date-add-days last 1))))

(defun unavailability-interval (entry)
  "The half-open UTC interval of an unavailability entry, as (start . end)."
  (if (unavailability-whole-day entry)
      (whole-days-interval (unavailability-start-date entry) (unavailability-end-date entry))
      (cons (values (to-utc (unavailability-start-date entry) (unavailability-start-time entry)))
            (values (to-utc (unavailability-end-date entry) (unavailability-end-time entry))))))

(defun overlaps-p (a b)
  "Half-open intervals (start . end): touching boundaries do not overlap."
  (and (< (car a) (cdr b)) (< (car b) (cdr a))))

(defun order-interval (order)
  "ORDER's period as whole local days, or NIL for a dateless order."
  (multiple-value-bind (first last) (order-period order)
    (and first (whole-days-interval first last))))

(defun norwegian-date (date)
  (format nil "~a.~a.~a" (subseq date 8 10) (subseq date 5 7) (subseq date 0 4)))

(defun entry-summary (entry)
  "dd.mm.yyyy[–dd.mm.yyyy] (hele dager) or dd.mm.yyyy (kl. HH:MM–HH:MM)."
  (let ((dates (if (string= (unavailability-start-date entry) (unavailability-end-date entry))
                   (norwegian-date (unavailability-start-date entry))
                   (format nil "~a–~a" (norwegian-date (unavailability-start-date entry))
                           (norwegian-date (unavailability-end-date entry))))))
    (if (unavailability-whole-day entry)
        (format nil "~a (hele dager)" dates)
        (format nil "~a (kl. ~a–~a)" dates (unavailability-start-time entry) (unavailability-end-time entry)))))

;;; ------------------------------------------------------------------
;;; Employees (README §2)

(defun actor-employee (&optional (actor *actor*))
  "The employee record bound to ACTOR (an actor, or its header text such as
\"admin:lager\"), or NIL: one indexed lookup (the actor is unique)."
  (let ((key (cond ((stringp actor) actor)
                   ((actor-p actor) (actor-string actor)))))
    (and key (select-one 'employee :where `(:= "actor" ,key)))))

(defun employee-unavailabilities (employee-id)
  (select 'unavailability :where `(:= "employee_id" ,employee-id)))

(defun employee-unavailable-p (employee-id interval)
  "The employee's unavailability entries that overlap INTERVAL."
  (and interval
       (remove-if-not (lambda (u) (overlaps-p (unavailability-interval u) interval))
                      (employee-unavailabilities employee-id))))

(defun check-employee (employee)
  (unless (parse-actor (employee-actor employee))
    (fail :invalid-input "Aktør må være på formen rolle:navn (admin, employee eller viewer)"))
  (check-department (employee-department employee)))

(define-operation employees-create ((:draft employee))
    (:entity employee :kind :create :policy :admin :title "Opprett ansatt"
     :description "Registrerer en ansatt med aktør (X-Tun-Actor-verdien, unik), rolle, avdeling og om den tildeles automatisk i avdelingen.")
  (check-employee employee)
  (when (select-one 'employee :where `(:= "actor" ,(employee-actor employee)))
    (fail :conflict "Aktøren ~a er allerede knyttet til en ansatt" (employee-actor employee)))
  (insert employee))

(define-operation employees-get ((id :type (id employee) :required t :label "Ansatt-ID"))
    (:entity employee :kind :read :title "Hent ansatt" :description "Henter én ansatt.")
  (fetch! 'employee id))

(define-operation employees-list ((department :type (string :max 100) :label "Avdeling")
                                  (active :type boolean :label "Aktiv")
                                  (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:entity employee :kind :read :title "Ansatte" :description "Lister ansatte, eldste først; filter på avdeling og aktiv.")
  (let ((where (remove nil (list (and department `(:= "department" ,department))
                                 (and (or (input-provided-p :active) (input-null-p :active))
                                      `(:= "active" ,(and active t)))))))
    (page (select 'employee :where (and where `(:and ,@where)) :limit (1+ limit)) limit)))

(defgeneric assignment-created (application assignment)
  (:method-combination traced-protocol)
  (:method ((application staffing-module) assignment) (declare (ignore assignment)) nil))
(register-extension-protocol 'assignment-created "after" :point "assignment_created"
                            :description "React to a manual or automatic assignment in its transaction.")
(defmethod setting-actor-exists-p ((application staffing-module) actor)
  (not (null (actor-employee actor))))
