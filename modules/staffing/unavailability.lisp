;;;; modules/staffing/unavailability.lisp -- employee unavailability in
;;;; Norwegian local time (README §7): whole days or a timed span, as
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

(defun local-instant (date time)
  "The instant of local DATE and TIME, refusing a time that does not exist or
occurs twice at a daylight saving change."
  (multiple-value-bind (instant status) (to-utc date time)
    (ecase status
      (:ok instant)
      (:nonexistent (fail :invalid-input "Klokkeslettet finnes ikke på grunn av overgang til sommertid"))
      (:ambiguous (fail :invalid-input "Klokkeslettet forekommer to ganger ved overgang til vintertid")))))

(defun validate-entry (entry)
  "README §7.2's checks in order; values the entry's interval."
  (let ((start (unavailability-start-date entry)) (end (unavailability-end-date entry)))
    (unless (and start end) (fail :invalid-input "Fyll inn både fra- og til-dato"))
    (when (date< end start) (fail :invalid-input "Til-dato kan ikke være før fra-dato"))
    (if (unavailability-whole-day entry)
        (progn (setf (unavailability-start-time entry) nil (unavailability-end-time entry) nil)
               (whole-days-interval start end))
        (progn
          (unless (and (parse-local-time (unavailability-start-time entry))
                       (parse-local-time (unavailability-end-time entry)))
            (fail :invalid-input "Fyll inn et gyldig klokkeslett"))
          (let ((from (local-instant start (unavailability-start-time entry)))
                (to (local-instant end (unavailability-end-time entry))))
            (unless (> to from) (fail :invalid-input "Sluttid må være etter starttid"))
            (cons from to))))))

(defun check-overlaps (entry interval)
  "Refuse an entry over another of the employee's entries or over an active assignment."
  (let ((employee-id (unavailability-employee-id entry)))
    (dolist (other (employee-unavailabilities employee-id))
      (when (and (not (equal (entity-id other) (entity-id entry)))
                 (overlaps-p (unavailability-interval other) interval))
        (fail :conflict "Registreringen overlapper en eksisterende utilgjengelighet")))
    (dolist (a (active-assignments :employee-id employee-id))
      (let* ((order (fetch 'order (assignment-order-id a)))
             (period (and order (order-interval order))))
        (when (and period (overlaps-p period interval))
          (fail :conflict "Perioden overlapper en aktiv ordretildeling. Fjern tildelingen før utilgjengeligheten registreres."))))))

(defun target-employee (employee-id)
  "The employee an entry is for: EMPLOYEE-ID (an admin's choice, or the
actor's own), else the actor's employee."
  (let ((me (actor-employee)))
    (cond ((and employee-id (eq :admin (actor-role *actor*))) (fetch! 'employee employee-id))
          ((and employee-id (or (null me) (string/= employee-id (entity-id me))))
           (fetch! 'employee employee-id)
           (reject :forbidden "Du kan bare registrere din egen utilgjengelighet"))
          (me me)
          (t (fail :invalid-input "Ingen ansatt er knyttet til aktøren ~a; oppgi employee_id" (actor-string *actor*))))))

(defun load-entry (id version)
  (let ((entry (fetch! 'unavailability id)))
    (unless (owner-or-admin-p entry)
      (reject :forbidden "Bare eieren eller en admin kan endre registreringen"))
    (unless (= version (unavailability-version entry))
      (fail :conflict "Endringen er basert på en utdatert versjon. Last siden på nytt."))
    entry))

(defun entry-date (value)
  "A date input: a malformed date is answered like a missing one."
  (cond ((null value) nil)
        ((valid-date-string-p value) value)
        (t (fail :invalid-input "Fyll inn både fra- og til-dato"))))

(define-operation unavailability-create ((employee-id :type (id employee) :label "Ansatt-ID"
                                                      :description "Standard: din egen ansattpost (admin kan velge hvem som helst).")
                                         (start-date :type (string :max 20) :label "Fra dato (ÅÅÅÅ-MM-DD)")
                                         (end-date :type (string :max 20) :label "Til dato (ÅÅÅÅ-MM-DD)")
                                         (whole-day :type boolean :required t :label "Hele dager")
                                         (start-time :type (string :max 10) :label "Fra klokken (HH:MM, norsk tid)")
                                         (end-time :type (string :max 10) :label "Til klokken (HH:MM, norsk tid)")
                                         (private-note :type (string :max 1000) :label "Privat merknad"))
    (:entity unavailability :kind :create :title "Registrer utilgjengelighet"
     :description "Registrerer når en ansatt ikke er tilgjengelig: hele dager eller et tidsrom i norsk tid (sommertid håndteres). Kan ikke overlappe egne registreringer eller en aktiv ordretildeling.")
  (let* ((employee (target-employee employee-id))
         (entry (make-instance 'unavailability :employee-id (entity-id employee)
                                               :start-date (entry-date start-date) :end-date (entry-date end-date)
                                               :whole-day (and whole-day t)
                                               :start-time start-time :end-time end-time
                                               :private-note private-note :version 1)))
    (check-overlaps entry (validate-entry entry))
    (unavailability->json (insert entry))))

(define-operation unavailability-update ((id :type (id unavailability) :required t :label "ID")
                                         (version :type integer :required t :label "Versjon")
                                         (start-date :type (string :max 20) :label "Fra dato (ÅÅÅÅ-MM-DD)")
                                         (end-date :type (string :max 20) :label "Til dato (ÅÅÅÅ-MM-DD)")
                                         (whole-day :type boolean :label "Hele dager")
                                         (start-time :type (string :max 10) :label "Fra klokken")
                                         (end-time :type (string :max 10) :label "Til klokken")
                                         (private-note :type (string :max 1000) :label "Privat merknad"))
    (:entity unavailability :kind :update :title "Endre utilgjengelighet"
     :description "Endrer en registrering (eieren eller admin) med gjeldende versjon; utdatert versjon gir conflict.")
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
                                         (version :type integer :required t :label "Versjon"))
    (:entity unavailability :kind :update :title "Slett utilgjengelighet"
     :description "Sletter en registrering (eieren eller admin) med gjeldende versjon.")
  (delete-entity (load-entry id version))
  (jobj "deleted" t "id" id))

(define-operation unavailability-list ((employee-id :type (id employee) :label "Ansatt-ID")
                                       (from :type date :required t :label "Fra dato")
                                       (to :type date :required t :label "Til dato"))
    (:entity unavailability :kind :read :title "Utilgjengelighet"
     :description "Registreringer som overlapper perioden, med tidsrommet i UTC. Private merknader vises bare for eieren og admin. Flere enn 200 treff gir invalid_input.")
  (let* ((where (remove nil (list (and employee-id `(:= "employee_id" ,employee-id))
                                  `(:<= "start_date" ,to) `(:>= "end_date" ,from))))
         (entries (select 'unavailability :where `(:and ,@where) :order-by '(("start_date" :asc)))))
    (when (> (length entries) +list-cap+)
      (fail :invalid-input "For mange registreringer; avgrens perioden"))
    (jobj "items" (jarr (mapcar #'unavailability->json entries)))))

;;; What clients may use (the rest of the package is for dependent modules).
(publish '(departments assignment-eligibility employee employee-name employee-department
           employee-actor employee-role employee-active actor-employee to-utc
           employees-create employees-get employees-list employees-update
           assignments-create assignments-end assignments-list assignment-overrides-list
           work-sessions-start work-sessions-stop work-sessions-create-manual work-sessions-list
           unavailability-create unavailability-update unavailability-delete unavailability-list))

(seal-module "staffing")
