;;;; modules/calendar/calendar.lisp -- the calendar module: calendar events
;;;; and the merged calendar of orders and events (README §2, §3).

(defpackage #:tun.calendar
  (:use #:cl #:tun.core #:tun.orders #:tun.staffing)
  (:export #:calendar-event #:calendar-event-title #:calendar-event-start-date #:calendar-event-end-date
           #:calendar-event-order-id
           #:calendar-events-create #:calendar-events-update #:calendar-events-delete #:calendar-events-get
           #:calendar-events-list #:calendar-list))

(in-package #:tun.calendar)

(declaim (optimize (safety 3) (debug 2)))

(define-module calendar
  (:depends-on orders staffing)
  (:core ">= 1.0" "< 2.0")
  (:documentation "Calendar: events and the merged calendar of orders and events."))

(define-entity calendar-event (:json-name "calendar_event" :label "Hendelse" :id-prefix "cev"
                               :table "calendar_events" :indexes (("start_date") ("order_id")))
  ((title :type (string :min 1 :max 200) :required t :label "Tittel")
   (description :type (string :max 2000) :label "Beskrivelse")
   (start-date :type date :required t :label "Fra dato")
   (end-date :type date :label "Til dato" :description "Standard: fra-datoen.")
   (order-id :type (id order) :label "Ordre")
   (created-at :type timestamp :input nil :label "Opprettet")))

(defun check-event (event)
  (unless (calendar-event-end-date event)
    (setf (calendar-event-end-date event) (calendar-event-start-date event)))
  (when (date< (calendar-event-end-date event) (calendar-event-start-date event))
    (fail :invalid-input "Sluttdato kan ikke være før startdato"))
  (when (calendar-event-order-id event)
    (find-order (calendar-event-order-id event)))
  event)

(define-operation calendar-events-create ((:draft calendar-event))
    (:entity calendar-event :kind :create :policy :admin :title "Opprett hendelse"
     :description "En hendelse i kalenderen (messe, vedlikehold, befaring), eventuelt knyttet til en ordre.")
  (insert (check-event calendar-event)))

(define-operation calendar-events-update ((id :type (id calendar-event) :required t :label "Hendelse-ID")
                                          (:field calendar-event title)
                                          (:field calendar-event description)
                                          (:field calendar-event start-date)
                                          (:field calendar-event end-date)
                                          (:field calendar-event order-id))
    (:entity calendar-event :kind :update :policy :admin :title "Endre hendelse"
     :description "Endrer en hendelse; feltene som ikke oppgis, beholdes.")
  (let ((event (fetch! 'calendar-event id)))
    (macrolet ((update (key accessor)
                 `(cond ((input-provided-p ,key) (setf (,accessor event) (input-value ,key)))
                        ((input-null-p ,key) (setf (,accessor event) nil)))))
      (update :title calendar-event-title)
      (update :description calendar-event-description)
      (update :start-date calendar-event-start-date)
      (update :end-date calendar-event-end-date)
      (update :order-id calendar-event-order-id))
    (save (check-event event))))

(define-operation calendar-events-delete ((id :type (id calendar-event) :required t :label "Hendelse-ID"))
    (:entity calendar-event :kind :update :policy :admin :title "Slett hendelse" :description "Sletter en hendelse.")
  (delete-entity (fetch! 'calendar-event id))
  (jobj "deleted" t "id" id))

(define-operation calendar-events-get ((id :type (id calendar-event) :required t :label "Hendelse-ID"))
    (:entity calendar-event :kind :read :policy :admin :title "Hent hendelse" :description "Henter én hendelse.")
  (fetch! 'calendar-event id))

(defun events-between (from to)
  (select 'calendar-event :where `(:and (:<= "start_date" ,to) (:>= "end_date" ,from))))

(define-operation calendar-events-list ((from :type date :required t :label "Fra dato")
                                        (to :type date :required t :label "Til dato"))
    (:entity calendar-event :kind :read :policy :admin :title "Hendelser"
     :description "Hendelser som overlapper perioden.")
  (jobj "items" (jarr (mapcar #'entity->json (events-between from to)))))

;;; ------------------------------------------------------------------
;;; The merged calendar

(defun side-start (logistics side)
  (let* ((s (jget logistics side))
         (earliest (and s (not (eq t (jget s "not_agreed"))) (jget s "earliest"))))
    (and (stringp earliest) earliest)))

(defun order-entry (order)
  (let* ((logistics (order-logistics-object order))
         (labels (append (and (order-packed-p order) (list "PAKKET"))
                         (list (status-label (order-status order)))
                         (mapcar #'string-upcase (order-tags order)))))
    (values (jobj "kind" "order" "id" (entity-id order)
                  "start_date" (order-event-date order) "end_date" (order-last-date order)
                  "title" (customer-name-of order)
                  "customer_id" (order-customer-id order)
                  "labels" (jarr labels)
                  "time_labels" (jobj "start" (side-summary (jget logistics "delivery"))
                                      "end" (side-summary (jget logistics "return")))
                  "status" (order-status order)
                  "department" (or (order-department order) :null)
                  "assignees" (jarr (order-assignees (entity-id order))))
            (list (order-event-date order) (side-start logistics "delivery") (side-start logistics "return")
                  (order-created-at order) (entity-id order)))))

(defun customer-name-of (order)
  (tun.customers:customer-name (order-customer order)))

(defun linked-order-status (event)
  "The status of the order EVENT refers to, or :null."
  (let ((order (and (calendar-event-order-id event) (fetch 'order (calendar-event-order-id event)))))
    (if order (order-status order) :null)))

(defun event-entry (event)
  (values (jobj "kind" "event" "id" (entity-id event)
                "start_date" (calendar-event-start-date event) "end_date" (calendar-event-end-date event)
                "title" (calendar-event-title event) "labels" (jarr (list "Hendelse"))
                "description" (or (calendar-event-description event) :null)
                "order_id" (or (calendar-event-order-id event) :null)
                "order_status" (linked-order-status event))
          (list (calendar-event-start-date event) nil nil (calendar-event-created-at event) (entity-id event))))

(defun entry< (a b)
  "Start date, then delivery earliest, then return earliest (entries without a
time after those with one), then creation."
  (destructuring-bind (date-a delivery-a return-a created-a id-a) a
    (destructuring-bind (date-b delivery-b return-b created-b id-b) b
      (flet ((time< (x y) (cond ((and x y) (string< x y)) (x t) (t nil)))
             (time= (x y) (equal x y)))
        (cond ((string/= date-a date-b) (string< date-a date-b))
              ((not (time= delivery-a delivery-b)) (time< delivery-a delivery-b))
              ((not (time= return-a return-b)) (time< return-a return-b))
              ((/= (or created-a 0) (or created-b 0)) (< (or created-a 0) (or created-b 0)))
              (t (string< id-a id-b)))))))

(defparameter *calendar-list-max-days* 366
  "The longest period calendar_list covers (README §3.1).")

(defparameter *calendar-list-max-items* 1000
  "The most entries calendar_list returns; beyond it the answer says truncated.")

(defun check-calendar-period (from to)
  (when (date< to from)
    (fail :invalid-input "Til dato (~a) er før fra dato (~a)" to from))
  (when (date< (date-add-days from *calendar-list-max-days*) to)
    (fail :invalid-input "Perioden kan være høyst ~d dager" *calendar-list-max-days*)))

(define-operation calendar-list ((from :type date :required t :label "Fra dato")
                                 (to :type date :required t :label "Til dato")
                                 (mine :type boolean :label "Mine" :description "Bare ordrer du er tildelt."))
    (:entity calendar-event :kind :read :title "Kalender"
     :description "Kalenderen for perioden (høyst 366 dager, høyst 1000 oppføringer; flere gir truncated): aktive ordrer (utkast til bekreftet) med dato som overlapper, og hendelser (bare for admin), sortert på startdato, utleveringstid, returtid og opprettelse. Utilgjengelighet vises ikke her.")
  (check-calendar-period from to)
  (let* ((me (and mine (actor-employee)))
         (mine-ids (and me (mapcar #'assignment-order-id (active-assignments :employee-id (entity-id me)))))
         (orders (remove-if-not
                  (lambda (o) (and (member (order-status o) +calendar-active-statuses+ :test #'string=)
                                   (date<= from (order-last-date o))
                                   (or (not mine) (member (entity-id o) mine-ids :test #'string=))))
                  ;; Bounded on both sides in the store: event_date <= to and
                  ;; (end_date ?? event_date) >= from, active statuses only.
                  (select 'order :where `(:and (:not-null "event_date") (:<= "event_date" ,to)
                                               (:or (:>= "event_date" ,from) (:>= "end_date" ,from))
                                               (:in "status" ,+calendar-active-statuses+)))))
         (entries (append (mapcar (lambda (o) (multiple-value-list (order-entry o))) orders)
                          (when (eq :admin (actor-role *actor*))
                            (mapcar (lambda (e) (multiple-value-list (event-entry e))) (events-between from to))))))
    (let* ((sorted (mapcar #'first (sort entries #'entry< :key #'second)))
           (truncated (> (length sorted) *calendar-list-max-items*))
           (result (jobj "items" (jarr (if truncated (subseq sorted 0 *calendar-list-max-items*) sorted)))))
      (when truncated (setf (gethash "truncated" result) t))
      result)))

(publish '(calendar-event calendar-events-create calendar-events-update calendar-events-delete
           calendar-events-get calendar-events-list calendar-list))

(seal-module "calendar")
