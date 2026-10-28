;;;; modules/staffing/unavailability.lisp -- employee unavailability in
;;;; the tenant's local time (README §7): whole days or a timed span, as
;;;; half-open UTC intervals that may not overlap the employee's other
;;;; entries nor an active assignment.

(in-package #:tun.staffing)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +list-cap+ 200)

(defun owner-or-admin-p (entry)
  (or (eq :admin (actor-role *actor*))
      (let ((me (actor-employee)))
        (and me (string= (entity-id me) (unavailability-employee-id entry))))))

(defun unavailability->json (entry)
  "The entry with its UTC interval; the private note only for its owner or an admin."
  (let ((json (entity->json entry))
        (interval (ignore-errors (unavailability-interval entry))))
    (setf (gethash "start_at" json) (if (and interval (car interval)) (format-rfc3339 (car interval)) :null)
          (gethash "end_at" json) (if (and interval (cdr interval)) (format-rfc3339 (cdr interval)) :null))
    (unless (owner-or-admin-p entry)
      (setf (gethash "private_note" json) :null))
    json))

(defun entry-instant (date time)
  "The instant of local DATE and TIME, refusing a time that does not exist or
occurs twice at a daylight saving change."
  (multiple-value-bind (instant status) (to-utc date time)
    (ecase status
      (:ok instant)
      (:nonexistent
       (fail :invalid-input "The time does not exist because of the change to summer time"))
      (:ambiguous
       (fail :invalid-input "The time occurs twice at the change to winter time")))))

(defun validate-entry (entry)
  "README §7.2's checks in order; values the entry's interval."
  (let ((start (unavailability-start-date entry)) (end (unavailability-end-date entry)))
    (unless (and start end) (fail :invalid-input "Fill in both the from date and the to date"))
    (when (date< end start) (fail :invalid-input "The to date cannot be before the from date"))
    (if (unavailability-whole-day entry)
        (progn (setf (unavailability-start-time entry) nil (unavailability-end-time entry) nil)
               (whole-days-interval start end))
        (progn
          (unless (and (parse-local-time (unavailability-start-time entry))
                       (parse-local-time (unavailability-end-time entry)))
            (fail :invalid-input "Fill in a valid time"))
          (let ((from (entry-instant start (unavailability-start-time entry)))
                (to (entry-instant end (unavailability-end-time entry))))
            (unless (> to from) (fail :invalid-input "The end time must be after the start time"))
            (cons from to))))))

(defun check-overlaps (entry interval)
  "Refuse an entry over another of the employee's entries or over an active assignment."
  (let ((employee-id (unavailability-employee-id entry)))
    (dolist (other (employee-unavailabilities employee-id))
      (when (and (not (equal (entity-id other) (entity-id entry)))
                 (overlaps-p (unavailability-interval other) interval))
        (fail :conflict "The entry overlaps an existing unavailability")))
    (dolist (a (active-assignments :employee-id employee-id))
      (let* ((order (fetch 'order (assignment-order-id a)))
             (period (and order (order-interval order))))
        (when (and period (overlaps-p period interval))
          (fail :conflict
                "The period overlaps an active assignment to an order. Remove the assignment before you record the unavailability."))))))

(defun target-employee (employee-id)
  "The employee an entry is for: EMPLOYEE-ID (an admin's choice, or the
actor's own), else the actor's employee."
  (let ((me (actor-employee)))
    (cond ((and employee-id (eq :admin (actor-role *actor*))) (fetch! 'employee employee-id))
          ((and employee-id (or (null me) (string/= employee-id (entity-id me))))
           (fetch! 'employee employee-id)
           (reject :forbidden "You can only record your own unavailability"))
          (me me)
          (t (fail :invalid-input "No employee belongs to the actor ~a; give employee_id"
                   (actor-string *actor*))))))

(defun load-entry (id version)
  (let ((entry (fetch! 'unavailability id)))
    (unless (owner-or-admin-p entry)
      (reject :forbidden "Only the owner or an admin can change the entry"))
    (unless (= version (unavailability-version entry))
      (fail :conflict "The change is based on an old version. Reload the page."))
    entry))

(defun entry-date (value)
  "A date input: a malformed date is answered like a missing one."
  (cond ((null value) nil)
        ((valid-date-string-p value) value)
        (t (fail :invalid-input "Fill in both the from date and the to date"))))

(define-operation unavailability-create
    ((employee-id :type (id employee) :label "Employee ID"
                  :description "By default your own employee record (an admin can choose anyone).")
     (start-date :type (string :max 20) :label "From date (YYYY-MM-DD)")
     (end-date :type (string :max 20) :label "To date (YYYY-MM-DD)")
     (whole-day :type boolean :required t :label "Whole days")
     (start-time :type (string :max 10) :label "From time (HH:MM, local time)")
     (end-time :type (string :max 10) :label "To time (HH:MM, local time)")
     (private-note :type (string :max 1000) :label "Private note"))
    (:entity unavailability :kind :create :title "Record unavailability"
             :description "Records when an employee is not available: whole days, or a span of time
in the tenant's time zone (summer time is handled). It cannot overlap the employee's other entries
or an active assignment to an order.")
  (let* ((employee (target-employee employee-id))
         (entry (make-instance 'unavailability :employee-id (entity-id employee)
                                               :start-date (entry-date start-date) :end-date (entry-date end-date)
                                               :whole-day (and whole-day t)
                                               :start-time start-time :end-time end-time
                                               :private-note private-note :version 1)))
    (check-overlaps entry (validate-entry entry))
    (unavailability->json (insert entry))))

(define-operation unavailability-update
    ((id :type (id unavailability) :required t :label "ID")
     (version :type integer :required t :label "Version")
     (start-date :type (string :max 20) :label "From date (YYYY-MM-DD)")
     (end-date :type (string :max 20) :label "To date (YYYY-MM-DD)")
     (whole-day :type boolean :label "Whole days")
     (start-time :type (string :max 10) :label "From time")
     (end-time :type (string :max 10) :label "To time")
     (private-note :type (string :max 1000) :label "Private note"))
    (:entity unavailability :kind :update :title "Change unavailability"
             :description "Changes an entry (its owner or an admin) at its current version; an old
version is conflict.")
  (let ((entry (load-entry id version)))
    (macrolet ((update (key accessor)
                 `(cond ((input-provided-p ,key) (setf (,accessor entry) (input-value ,key)))
                        ((input-null-p ,key) (setf (,accessor entry) nil)))))
      (when (input-provided-p :start-date) (setf (unavailability-start-date entry) (entry-date start-date)))
      (when (input-provided-p :end-date) (setf (unavailability-end-date entry) (entry-date end-date)))
      (update :start-time unavailability-start-time)
      (update :end-time unavailability-end-time)
      (update :private-note unavailability-private-note)
      (when (input-provided-p :whole-day) (setf (unavailability-whole-day entry) (and whole-day t))))
    (check-overlaps entry (validate-entry entry))
    (incf (unavailability-version entry))
    (unavailability->json (save entry))))

(define-operation unavailability-delete ((id :type (id unavailability) :required t :label "ID")
                                         (version :type integer :required t :label "Version"))
    (:entity unavailability :kind :update :title "Delete unavailability"
             :description "Deletes an entry (its owner or an admin) at its current version.")
  (delete-entity (load-entry id version))
  (jobj "deleted" t "id" id))

(define-operation unavailability-list ((employee-id :type (id employee) :label "Employee ID")
                                       (from :type date :required t :label "From date")
                                       (to :type date :required t :label "To date"))
    (:entity unavailability :kind :read :title "Unavailability"
             :description "The entries that overlap the period, with their span in UTC. A private
note shows only to its owner and an admin. More than 200 entries is invalid_input.")
  (let* ((where (remove nil (list (and employee-id `(:= "employee_id" ,employee-id))
                                  `(:<= "start_date" ,to) `(:>= "end_date" ,from))))
         (entries (select 'unavailability :where `(:and ,@where) :order-by '(("start_date" :asc)))))
    (when (> (length entries) +list-cap+)
      (fail :invalid-input "Too many entries; narrow the period"))
    (jobj "items" (jarr (mapcar #'unavailability->json entries)))))

;;; What clients may use (the rest of the package is for dependent modules).
(publish '(departments assignment-eligibility employee employee-name employee-department
           employee-actor employee-role employee-active actor-employee to-utc
           employees-create employees-get employees-list employees-update
           assignments-create assignments-end assignments-list assignment-overrides-list
           work-sessions-start work-sessions-stop work-sessions-create-manual work-sessions-list
           unavailability-create unavailability-update unavailability-delete unavailability-list))

(seal-module "staffing")
