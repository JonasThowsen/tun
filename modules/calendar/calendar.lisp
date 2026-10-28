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
  (:core ">= 2.0.0" "< 3.0")
  (:documentation "Calendar: events and the merged calendar of orders and events."))

(define-entity calendar-event (:json-name "calendar_event" :label "Event" :id-prefix "cev"
                               :table "calendar_events" :indexes (("start_date") ("order_id")))
  ((title :type (string :min 1 :max 200) :required t :label "Title")
   (description :type (string :max 2000) :label "Description")
   (start-date :type date :required t :label "From date")
   (end-date :type date :label "To date" :description "By default the from date.")
   (order-id :type (id order) :label "Order")
   (created-at :type timestamp :input nil :label "Created")))

(defun check-event (event)
  (unless (calendar-event-end-date event)
    (setf (calendar-event-end-date event) (calendar-event-start-date event)))
  (when (date< (calendar-event-end-date event) (calendar-event-start-date event))
    (fail :invalid-input "The end date cannot be before the start date"))
  (when (calendar-event-order-id event)
    (find-order (calendar-event-order-id event)))
  event)

(define-operation calendar-events-create ((:draft calendar-event))
    (:entity calendar-event :kind :create :policy :admin :title "Create an event"
             :description "An event in the calendar (a fair, maintenance, a site visit), perhaps
linked to an order.")
  (insert (check-event calendar-event)))

(define-operation calendar-events-update ((id :type (id calendar-event) :required t :label "Event ID")
                                          (:field calendar-event title)
                                          (:field calendar-event description)
                                          (:field calendar-event start-date)
                                          (:field calendar-event end-date)
                                          (:field calendar-event order-id))
    (:entity calendar-event :kind :update :policy :admin :title "Change an event"
             :description "Changes an event; the fields not given are kept.")
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

(define-operation calendar-events-delete ((id :type (id calendar-event) :required t :label "Event ID"))
    (:entity calendar-event :kind :update :policy :admin :title "Delete an event"
             :description "Deletes an event.")
  (delete-entity (fetch! 'calendar-event id))
  (jobj "deleted" t "id" id))

(define-operation calendar-events-get ((id :type (id calendar-event) :required t :label "Event ID"))
    (:entity calendar-event :kind :read :policy :admin :title "Get an event"
             :description "Gets one event.")
  (fetch! 'calendar-event id))

(defun events-between (from to)
  (select 'calendar-event :where `(:and (:<= "start_date" ,to) (:>= "end_date" ,from))))

(define-operation calendar-events-list ((from :type date :required t :label "From date")
                                        (to :type date :required t :label "To date"))
    (:entity calendar-event :kind :read :policy :admin :title "Events"
             :description "The events that overlap the period.")
  (jobj "items" (jarr (mapcar #'entity->json (events-between from to)))))

;;; ------------------------------------------------------------------
;;; The merged calendar

(defun side-start (logistics side)
  (let* ((s (jget logistics side))
         (earliest (and s (not (eq t (jget s "not_agreed"))) (jget s "earliest"))))
    (and (stringp earliest) earliest)))

(defun tag-label (tag)
  "The order tag TAG as the calendar shows it: its label, in upper case."
  (string-upcase (render-text (label "order" "tags" tag))))

(defun order-entry (order)
  "ORDER as an entry of the calendar, and its sort key.  Its labels are copy,
in the tenant's language: PACKED, the status's label, the tags' in upper case."
  (let* ((logistics (order-logistics-object order))
         (labels (append (and (order-packed-p order) (list (tr "PACKED")))
                         (list (status-label (order-status order)))
                         (mapcar #'tag-label (order-tags order)))))
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
                "title" (calendar-event-title event) "labels" (jarr (list (tr "Event")))
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
    (fail :invalid-input "The to date (~a) is before the from date (~a)" to from))
  (when (date< (date-add-days from *calendar-list-max-days*) to)
    (fail :invalid-input "The period can be at most ~d days" *calendar-list-max-days*)))

(define-operation calendar-list ((from :type date :required t :label "From date")
                                 (to :type date :required t :label "To date")
                                 (mine :type boolean :label "Mine"
                                       :description "Only the orders you are assigned to."))
    (:entity calendar-event :kind :read :title "Calendar"
             :description "The calendar of the period (at most 366 days, at most 1000 entries; more
gives truncated): the active orders (draft to confirmed) whose dates overlap it, and the events (for
an admin only), sorted by start date, delivery time, return time and creation. Unavailability is not
shown here.")
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
