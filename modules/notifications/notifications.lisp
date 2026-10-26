(defpackage #:tun.notifications
  (:use #:cl #:tun.core #:tun.customers #:tun.orders #:tun.staffing)
  (:local-nicknames (#:ui #:tun.ui))
  (:export #:notification #:publish-notification #:notification-recipients))
(in-package #:tun.notifications)

(define-module notifications (:depends-on customers orders staffing) (:core ">= 1.2.0" "< 2.0")
  (:documentation "Employee notifications with durable event identities and private read state."))

(define-entity notification (:label "Varsel" :id-prefix "ntf" :table "notifications"
                             :unique (("type" "event_id" "recipient")) :indexes (("recipient")))
  ((type :type (string :max 100) :input nil)
   (recipient :type (string :max 200) :input nil)
   (text :type (string :max 2000) :input nil)
   (link :type (string :max 500) :input nil)
   (subject-type :type (string :max 100) :input nil)
   (subject-id :type id :input nil)
   (order-id :type id :input nil)
   (event-id :type id :input nil)
   (created-at :type timestamp :input nil)
   (read-at :type timestamp :input nil)))

(defmethod entity-readable-p ((record notification) actor)
  (and (call-next-method) (equal (field-value record (find-field 'notification "recipient")) (actor-string actor))))

(defun notification-recipients (&optional order-id)
  "Active admins, plus an order's active assignees; actors are deduplicated."
  (remove-duplicates
   (append (loop for employee in (select 'employee :where '(:= "active" t))
                 when (let ((actor (parse-actor (employee-actor employee))))
                        (and actor (eq (actor-role actor) :admin)))
                   collect (employee-actor employee))
           (when order-id
             (loop for item in (active-assignments :order-id order-id)
                   for employee = (fetch 'employee (assignment-employee-id item))
                   when (and employee (employee-active employee)) collect (employee-actor employee))))
   :test #'equal))

(defun publish-notification (type event-id text link subject-type subject-id &key order-id (recipients nil recipients-supplied-p))
  "Publish exactly once per event and recipient, within the caller's transaction."
  (dolist (recipient (if recipients-supplied-p recipients (notification-recipients order-id)))
    (unless (select-one 'notification :where `(:and (:= "type" ,type) (:= "event_id" ,event-id)
                                                   (:= "recipient" ,recipient)))
      (insert (make-instance 'notification :type type :event-id event-id :recipient recipient
                             :text text :link link :subject-type subject-type :subject-id subject-id
                             :order-id order-id :created-at (now)))))
  nil)

(define-operation notifications-list ((unread-only :type boolean)
                                      (limit :type (integer :min 1 :max 100) :default 25))
    (:entity notification :kind :read :policy :employee :title "Mine varsler")
  (jobj "items" (jarr (mapcar #'entity->json
    (select 'notification :where (if unread-only
       `(:and (:= "recipient" ,(actor-string *actor*)) (:null "read_at"))
       `(:= "recipient" ,(actor-string *actor*))) :order-by '(("seq" :desc)) :limit limit)))))

(define-operation notifications-mark-read ((id :type (id notification) :required t))
    (:entity notification :kind :update :policy :employee :title "Merk varsel lest")
  (let ((item (select-one 'notification :where `(:and (:= "id" ,id) (:= "recipient" ,(actor-string *actor*))))))
    (unless item (fail :not-found "Varselet finnes ikke"))
    (unless (notification-read-at item) (setf (notification-read-at item) (now)) (save item))
    item))

(define-operation notifications-unread-count ()
    (:entity notification :kind :read :policy :employee :title "Uleste varsler")
  (let ((count (length (select 'notification :where `(:and (:= "recipient" ,(actor-string *actor*))
                                                          (:null "read_at")) :limit 100))))
    (jobj "count" count "capped" (json-bool (= count 100)))))

(defmethod assignment-created ((app notifications-module) item)
  (call-next-method)
  (let ((employee (fetch! 'employee (assignment-employee-id item)))
        (order-id (assignment-order-id item)))
    (publish-notification "oppgave_tildelt" (entity-id item) "Du er tildelt en ny oppgave."
                          (format nil "/orders/~a" order-id) "assignment" (entity-id item)
                          :order-id order-id :recipients (list (employee-actor employee)))))

(defun publish-quote-response (order-id accepted event-id)
  (publish-notification (if accepted "tilbud_akseptert" "tilbud_avslått") event-id
    (format nil "Tilbudet på ordre ~a er ~a." order-id (if accepted "akseptert" "avslått"))
    (format nil "/orders/~a" order-id) "order" order-id :order-id order-id))

(defmethod quotes-respond :after ((app notifications-module) input)
  (declare (ignore input))
  (let ((result (operation-result)))
    (publish-quote-response (jget result "order_id") (equal (jget result "status") "accepted") *request-id*)))
(defmethod orders-accept :after ((app notifications-module) input)
  (declare (ignore input))
  (publish-quote-response (entity-id (operation-result)) t *request-id*))
(defmethod orders-confirm :after ((app notifications-module) input)
  (declare (ignore input))
  (let* ((id (entity-id (operation-result)))
         (recipients (loop for item in (active-assignments :order-id id)
                           for employee = (fetch! 'employee (assignment-employee-id item))
                           when (and (employee-active employee)
                                     (not (equal (employee-actor employee) (actor-string *actor*))))
                             collect (employee-actor employee))))
    (when recipients
      (publish-notification "ordre_bekreftet" *request-id* (format nil "Ordre ~a er bekreftet." id)
                            (format nil "/orders/~a" id) "order" id :order-id id :recipients recipients))))

(defmethod quote-expired ((app notifications-module) quote)
  (call-next-method)
  (let ((order-id (jget (entity->json quote) "order_id")))
    (publish-notification "tilbud_utløpt" *request-id* (format nil "Tilbudet på ordre ~a er utløpt." order-id)
                          (format nil "/orders/~a" order-id) "order" order-id :order-id order-id)))

(defmethod customer-erasing ((app notifications-module) customer)
  (call-next-method)
  (let* ((id (entity-id customer))
         (orders (mapcar #'entity-id (select 'order :where `(:= "customer_id" ,id))))
         (where `(:and (:in "type" ("leveranse_feilet" "kundesvar_mottatt"))
                       (:or (:= "link" ,(format nil "/customers/~a" id))
                            ,@(when orders `((:in "order_id" ,orders)))))))
    (dolist (item (select 'notification :where where))
      (let ((text (cl-ppcre:regex-replace-all (cl-ppcre:quote-meta-chars (customer-name customer))
                                            (notification-text item) "[slettet]")))
        (unless (equal text (notification-text item))
          (setf (notification-text item) text)
          (save item)
          (redact-entity-receipts item))))))

(publish '(publish-notification))
