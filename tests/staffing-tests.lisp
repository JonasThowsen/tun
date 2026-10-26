;;;; tests/staffing-tests.lisp -- staffing README §2–§8 and its invariants (§9)
;;;; they carry: assignments (8), automatic assignment (9), overrides (10),
;;;; work sessions (11), Norwegian time (12), dateless orders (13).

(in-package #:tun.tests)

(def-suite staffing :in core)
(in-suite staffing)

(defclass two-departments () ())
(defclass same-department-rule () ())
(defclass departments-app (two-departments application) ())
(defclass staffed-app (same-department-rule two-departments application) ())
(defmethod tun.staffing:departments ((app two-departments))
  (append (call-next-method) '("nord" "sør")))
(defmethod tun.staffing:assignment-eligibility ((app same-department-rule) order employee)
  (or (call-next-method)
      (and (tun.orders:order-department order) (tun.staffing:employee-department employee)
           (string/= (tun.orders:order-department order) (tun.staffing:employee-department employee))
           "Ansatte i en annen avdeling kan ikke tildeles")))

(defun make-employee (name &key (role "employee") department auto)
  (call-ok "employees_create" "admin:jonas" "name" name
           "actor" (format nil "~a:~a" role (string-downcase name)) "role" role
           "department" (or department :null) "auto_assign_in_department" (and auto t)))

(defun assignment-ids (order &rest args)
  (map 'list (lambda (a) (jget a "employee_id"))
       (jget (apply #'call-ok "assignments_list" "viewer:vera" "order_id" order args) "items")))

;;; ------------------------------------------------------------------
;;; §9.2 Norwegian time, invariant 12

(test norwegian-local-time-is-defined-without-a-tz-database
  (flet ((utc (date time) (multiple-value-bind (instant status) (tun.staffing:to-utc date time)
                            (if instant (format-rfc3339 instant) status))))
    (is (string= "2026-01-15T08:00:00Z" (utc "2026-01-15" "09:00")))
    (is (string= "2026-07-15T07:00:00Z" (utc "2026-07-15" "09:00")))
    (is (eq :nonexistent (utc "2026-03-29" "02:30")))
    (is (string= "2026-03-29T00:59:00Z" (utc "2026-03-29" "01:59")))
    (is (string= "2026-03-29T01:00:00Z" (utc "2026-03-29" "03:00")))
    (is (eq :ambiguous (utc "2026-10-25" "02:30")))
    (is (string= "2026-10-25T02:00:00Z" (utc "2026-10-25" "03:00"))))
  (flet ((hours (date) (let ((i (tun.staffing:whole-days-interval date date))) (/ (- (cdr i) (car i)) 3600))))
    (is (= 23 (hours "2026-03-29")))
    (is (= 25 (hours "2026-10-25")))
    (is (= 24 (hours "2026-06-01"))))
  (is (string= "2026-06-30" (local-date-of (parse-rfc3339 "2026-06-29T22:30:00Z"))) "today is the local date")
  (is (string= "2026-12-31" (local-date-of (parse-rfc3339 "2026-12-31T22:59:00Z")))))

;;; ------------------------------------------------------------------
;;; §9.1 unavailability

(test unavailability-validates-in-local-time-and-never-overlaps
  (with-test-app (:class 'staffed-app)
    (let* ((kari (make-employee "Kari"))
           (per (make-employee "Per")))
      (flet ((create (actor &rest args)
               (apply #'call "unavailability_create" actor
                      (if (member "whole_day" args :test #'equal) args (append args (list "whole_day" t))))))
        (is-error "invalid_input" "Fyll inn både fra- og til-dato" (create "employee:kari" "start_date" "2026-06-01"))
        (is-error "invalid_input" "Til-dato kan ikke være før fra-dato"
                  (create "employee:kari" "start_date" "2026-06-02" "end_date" "2026-06-01"))
        (is-error "invalid_input" "Fyll inn et gyldig klokkeslett"
                  (create "employee:kari" "start_date" "2026-06-01" "end_date" "2026-06-01" "whole_day" nil
                          "start_time" "9:00" "end_time" "11:00"))
        (is-error "invalid_input" "Sluttid må være etter starttid"
                  (create "employee:kari" "start_date" "2026-06-01" "end_date" "2026-06-01" "whole_day" nil
                          "start_time" "11:00" "end_time" "11:00"))
        (is-error "invalid_input" "Klokkeslettet finnes ikke på grunn av overgang til sommertid"
                  (create "employee:kari" "start_date" "2026-03-29" "end_date" "2026-03-29" "whole_day" nil
                          "start_time" "02:30" "end_time" "05:00"))
        (is-error "invalid_input" "Klokkeslettet forekommer to ganger ved overgang til vintertid"
                  (create "employee:kari" "start_date" "2026-10-25" "end_date" "2026-10-25" "whole_day" nil
                          "start_time" "01:00" "end_time" "02:30"))
        ;; Someone else's: forbidden for an employee, fine for an admin.
        (is-error "forbidden" nil (create "employee:kari" "employee_id" (jget per "id")
                                          "start_date" "2026-06-01" "end_date" "2026-06-01"))
        (let* ((timed (call-ok "unavailability_create" "employee:kari" "start_date" "2026-07-15" "end_date" "2026-07-15"
                               "whole_day" nil "start_time" "09:00" "end_time" "11:00" "private_note" "tannlege"))
               (whole (call-ok "unavailability_create" "admin:jonas" "employee_id" (jget kari "id")
                               "start_date" "2026-07-16" "end_date" "2026-07-17" "whole_day" t)))
          (is (string= "2026-07-15T07:00:00Z" (jget timed "start_at")))
          (is (string= "2026-07-15T09:00:00Z" (jget timed "end_at")))
          (is (json-null-p (jget whole "start_time")) "whole days store no times")
          (is (string= "2026-07-15T22:00:00Z" (jget whole "start_at")) "local midnight")
          ;; Touching intervals do not overlap; overlapping ones do.
          (is (jget (call-ok "unavailability_create" "employee:kari" "start_date" "2026-07-15" "end_date" "2026-07-15"
                             "whole_day" nil "start_time" "11:00" "end_time" "12:00")
                    "id"))
          (is-error "conflict" "Registreringen overlapper en eksisterende utilgjengelighet"
                    (create "employee:kari" "start_date" "2026-07-15" "end_date" "2026-07-15" "whole_day" nil
                            "start_time" "10:59" "end_time" "11:30"))
          ;; The private note: owner and admin only.
          (flet ((note (actor) (jget (find (jget timed "id")
                                           (coerce (jget (call-ok "unavailability_list" actor "from" "2026-07-01"
                                                                  "to" "2026-07-31")
                                                         "items")
                                                   'list)
                                           :key (lambda (u) (jget u "id")) :test #'string=)
                                     "private_note")))
            (is (equal "tannlege" (note "employee:kari")))
            (is (equal "tannlege" (note "admin:jonas")))
            (is (json-null-p (note "viewer:vera")))
            (is (json-null-p (note "employee:per"))))
          ;; Versions.
          (is-error "conflict" "Endringen er basert på en utdatert versjon. Last siden på nytt."
                    (call "unavailability_update" "employee:kari" "id" (jget whole "id") "version" 7 "end_date" "2026-07-18"))
          (is-error "forbidden" nil (call "unavailability_update" "employee:per" "id" (jget whole "id") "version" 1))
          (let ((updated (call-ok "unavailability_update" "employee:kari" "id" (jget whole "id") "version" 1
                                  "end_date" "2026-07-18")))
            (is (= 2 (jget updated "version"))))
          (is (eq t (jget (call-ok "unavailability_delete" "employee:kari" "id" (jget whole "id") "version" 2) "deleted"))))))))

(test unavailability-list-is-capped
  (with-test-app (:class 'staffed-app)
    (let ((kari (make-employee "Kari")))
      (declare (ignore kari))
      (loop for day from 0 below 201
            do (call-ok "unavailability_create" "employee:kari" "whole_day" t
                        "start_date" (date-add-days "2027-01-01" day) "end_date" (date-add-days "2027-01-01" day)))
      (is-error "invalid_input" "For mange registreringer; avgrens perioden"
                (call "unavailability_list" "viewer:vera" "from" "2027-01-01" "to" "2027-12-31"))
      (is (= 200 (length (jget (call-ok "unavailability_list" "viewer:vera" "from" "2027-01-01" "to" "2027-07-19") "items")))))))

;;; ------------------------------------------------------------------
;;; §8.2, §8.3 assignments and overrides, invariants 8 and 10

(test assignments-overrides-and-their-guards
  (with-test-app (:class 'staffed-app)
    (let* ((customer (make-customer))
           (p (make-product :name "Tjeneste" :kind "tjeneste" :units-owned 0))
           (kari (make-employee "Kari" :department "nord"))
           (sondre (make-employee "Sondre" :department "sør"))
           (order (jget (new-order customer "event_date" "2026-06-20" "end_date" "2026-06-21"
                                   "department" "nord" "lines" (jarr (list (line p 1))))
                        "id")))
      (call-ok "unavailability_create" "employee:kari" "start_date" "2026-06-21" "end_date" "2026-06-21"
               "whole_day" nil "start_time" "10:00" "end_time" "12:00")
      (flet ((assign (&rest args) (apply #'call "assignments_create" "admin:jonas" "order_id" order args)))
        (is-error "forbidden" nil (call "assignments_create" "employee:kari" "order_id" order "employee_id" (jget kari "id")))
        (is-error "invalid_input" "Begrunnelse er påkrevd ved overstyring av utilgjengelighet"
                  (assign "employee_id" (jget kari "id")))
        (is-error "invalid_input" "Begrunnelsen kan ikke være lengre enn 500 tegn"
                  (assign "employee_id" (jget kari "id") "override_reason" (make-string 501 :initial-element #\x)))
        (is-error "invalid_input" "Ansatte i en annen avdeling kan ikke tildeles"
                  (assign "employee_id" (jget sondre "id")))
        (let ((rev (jget (order-of order) "revision"))
              (a (call-ok "assignments_create" "admin:jonas" "order_id" order "employee_id" (jget kari "id")
                          "override_reason" "Bare to timer, hun rekker det")))
          (is (eq nil (jget a "auto")))
          (is (= (1+ rev) (jget (order-of order) "revision")) "assigning revises the order")
          (let ((override (aref (jget (call-ok "assignment_overrides_list" "admin:jonas" "order_id" order) "items") 0)))
            (is (string= "21.06.2026 (kl. 10:00–12:00)" (jget override "conflict_summary")))
            (is (= 1 (length (jget override "conflict_ids"))))
            (is (string= "admin:jonas" (jget override "created_by"))))
          (is-error "conflict" nil (assign "employee_id" (jget kari "id")))
          (is (equal (list (jget kari "id")) (assignment-ids order)))
          (is (equal (list (jget kari "id"))
                     (map 'list (lambda (x) (jget x "employee_id"))
                          (jget (call-ok "assignments_list" "employee:kari" "mine" t) "items"))))
          (is (equalp #() (jget (call-ok "assignments_list" "viewer:nobody" "mine" t) "items")) "no employee, no mine")
          ;; Unavailability cannot be registered over an active assignment.
          (is-error "conflict" "Perioden overlapper en aktiv ordretildeling. Fjern tildelingen før utilgjengeligheten registreres."
                    (call "unavailability_create" "employee:kari" "start_date" "2026-06-20" "end_date" "2026-06-20"
                          "whole_day" t))
          ;; Ending keeps the row; ending twice is invalid_transition.
          (call-ok "assignments_end" "admin:jonas" "id" (jget a "id"))
          (is-error "invalid_transition" "Tildelingen er allerede avsluttet" (call "assignments_end" "admin:jonas" "id" (jget a "id")))
          (is (null (assignment-ids order)))
          (is (equal (list (jget kari "id")) (assignment-ids order "active" nil)) "ended rows are kept")))
      ;; Dateless orders have no period and no conflicts.
      (let ((dateless (jget (new-order customer "lines" (jarr (list (line p 1)))) "id")))
        (is (jget (call-ok "assignments_create" "admin:jonas" "order_id" dateless "employee_id" (jget kari "id")) "id")))
      ;; Cancelled orders take no one.
      (let ((cancelled (jget (new-order customer "lines" (jarr (list (line p 1)))) "id")))
        (two-step "orders_cancel" "employee:anna" "id" cancelled)
        (is-error "invalid_transition" nil (call "assignments_create" "admin:jonas" "order_id" cancelled
                                                 "employee_id" (jget kari "id")))))))

;;; ------------------------------------------------------------------
;;; §8.4 automatic assignment, invariant 9

(test automatic-assignment-by-department
  (with-test-app (:class 'departments-app)
    (let* ((customer (make-customer))
           (p (make-product :name "Tjeneste" :kind "tjeneste" :units-owned 0))
           (a (make-employee "Anne" :department "nord" :auto t))
           (b (make-employee "Bjorn" :department "nord" :auto t))
           (c (make-employee "Cato" :department "nord" :auto nil))
           (d (make-employee "Dina" :department "sør" :auto t))
           (e (make-employee "Eli" :department "nord" :auto t)))
      (declare (ignore c e))
      (call-ok "unavailability_create" "employee:eli" "start_date" "2026-06-20" "end_date" "2026-06-20" "whole_day" t)
      (let* ((created (new-order customer "event_date" "2026-06-20" "department" "nord" "lines" (jarr (list (line p 1)))))
             (order (jget created "id")))
        (is (equal (list (jget a "id") (jget b "id")) (assignment-ids order))
            "eligible, auto, active, available employees of the department, in creation order; Eli is unavailable (skipped)")
        (is (= 2 (length (jget created "assignments"))) "the created order reports them")
        (is (every (lambda (x) (eq t (jget x "auto"))) (coerce (jget created "assignments") 'list)))
        ;; A manual assignment survives department changes.
        (call-ok "assignments_create" "admin:jonas" "order_id" order "employee_id" (jget d "id"))
        (flet ((set-department (department)
                 (call-ok "orders_update" "employee:anna" "id" order "revision" (jget (order-of order) "revision")
                          "department" department)))
          (set-department "sør")
          (is (equal (list (jget d "id")) (assignment-ids order)) "nord's automatic ones ended; Dina was manual")
          (set-department :null)
          (is (equal (list (jget d "id")) (assignment-ids order)) "null ends every automatic one, never manual")
          (set-department "nord")
          (is (equal (sort (list (jget a "id") (jget b "id") (jget d "id")) #'string<)
                     (sort (assignment-ids order) #'string<))))
        ;; An edit that does not change the department assigns nobody new.
        (let ((f (make-employee "Frode" :department "nord" :auto t)))
          (call-ok "orders_update" "employee:anna" "id" order "revision" (jget (order-of order) "revision")
                   "delivery_address" "Ny gate 1")
          (is (not (member (jget f "id") (assignment-ids order) :test #'string=)) "never retroactively"))
        ;; Settings changes end automatic assignments that no longer fit.
        (call-ok "employees_update" "admin:jonas" "id" (jget a "id") "auto_assign_in_department" nil)
        (is (not (member (jget a "id") (assignment-ids order) :test #'string=)))
        ;; A running work session makes the department change fail entirely.
        (let ((bjorn-assignment (find (jget b "id") (coerce (jget (call-ok "assignments_list" "viewer:vera" "order_id" order) "items") 'list)
                                      :key (lambda (x) (jget x "employee_id")) :test #'string=)))
          (call-ok "work_sessions_start" "employee:bjorn" "order_id" order "assignment_id" (jget bjorn-assignment "id"))
          (let ((rev (jget (order-of order) "revision")))
            (is-error "conflict" "Stopp aktiv timer før tildelingen avsluttes"
                      (call "orders_update" "employee:anna" "id" order "revision" rev "department" "sør"))
            (is (= rev (jget (order-of order) "revision")) "nothing changed")
            (is (string= "nord" (jget (order-of order) "department"))))
          (is-error "conflict" "Stopp aktiv timer før tildelingen avsluttes"
                    (call "employees_update" "admin:jonas" "id" (jget b "id") "department" "sør")))))))

;;; ------------------------------------------------------------------
;;; §8.5 work sessions, invariant 11

(test work-sessions-block-closure-and-run-one-at-a-time
  (with-test-app (:class 'staffed-app)
    (let* ((customer (make-customer))
           (p (make-product :name "Tjeneste" :kind "tjeneste" :units-owned 0))
           (kari (make-employee "Kari"))
           (per (make-employee "Per"))
           (order (confirmed-order customer p "2026-06-20"))
           (other (confirmed-order customer p "2026-06-21"))
           (a (call-ok "assignments_create" "admin:jonas" "order_id" order "employee_id" (jget kari "id")))
           (a2 (call-ok "assignments_create" "admin:jonas" "order_id" other "employee_id" (jget kari "id"))))
      (declare (ignore per))
      (is-error "forbidden" nil (call "work_sessions_start" "employee:per" "order_id" order "assignment_id" (jget a "id")))
      (is-error "not_found" nil (call "work_sessions_stop" "employee:kari"))
      (let ((session (call-ok "work_sessions_start" "employee:kari" "order_id" order "assignment_id" (jget a "id"))))
        (is (string= "live" (jget session "source")))
        (is-error "conflict" "Du har allerede en aktiv timer"
                  (call "work_sessions_start" "employee:kari" "order_id" other "assignment_id" (jget a2 "id")))
        ;; Closure guards and ending the assignment.
        (is-error "conflict" "Stopp aktive timer før ordren avsluttes" (call "orders_complete" "employee:anna" "id" order))
        (is-error "conflict" "Stopp aktive timer før ordren avsluttes" (call "orders_ready_for_invoice" "employee:anna" "id" order))
        (is-error "conflict" "Stopp aktive timer før ordren avsluttes" (two-step "orders_cancel" "employee:anna" "id" order))
        (is-error "conflict" "Stopp aktiv timer før tildelingen avsluttes" (call "assignments_end" "admin:jonas" "id" (jget a "id")))
        (call-ok "clock_set" "admin:jonas" "now" (format-rfc3339 (+ (now-of *app*) 90)))
        (let ((stopped (call-ok "work_sessions_stop" "employee:kari")))
          (is (= 90 (jget stopped "duration_seconds")))))
      (is (string= "fullført" (jget (call-ok "orders_complete" "employee:anna" "id" order) "status")))
      (is-error "invalid_transition" nil (call "work_sessions_start" "employee:kari" "order_id" order "assignment_id" (jget a "id")))
      ;; Manual sessions: own assignment, end after start, at least a minute.
      (is-error "invalid_input" "Sluttid må være etter starttid"
                (call "work_sessions_create_manual" "employee:kari" "order_id" other "assignment_id" (jget a2 "id")
                      "started_at" "2026-06-21T10:00:00Z" "ended_at" "2026-06-21T10:00:00Z"))
      (let ((manual (call-ok "work_sessions_create_manual" "employee:kari" "order_id" other "assignment_id" (jget a2 "id")
                             "started_at" "2026-06-21T10:00:00Z" "ended_at" "2026-06-21T10:00:10Z")))
        (is (= 60 (jget manual "duration_seconds")))
        (is (string= "manual" (jget manual "source"))))
      (is (= 2 (length (jget (call-ok "work_sessions_list" "employee:kari" "mine" t) "items")))))))
