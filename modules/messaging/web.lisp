;;;; web.lisp -- communication history and the preview/send composer, built
;;;; from the design system's components (spec/ui.md).
(in-package #:tun.messaging)

(defparameter +delivery-variants+
  '(("queued" . :secondary) ("sending" . :info) ("accepted" . :success)
    ("failed" . :destructive) ("outcome_unknown" . :warning))
  "The badge of each delivery status; a reply from the customer is :info.")

(defun text-paragraphs (text)
  "TEXT, a message body, as paragraphs: a blank line starts a new one, a line
break stays a line break."
  (flet ((paragraph (lines)
           `(:p ,@(loop for (line . more) on (cl-ppcre:split "\\n" lines)
                        collect line
                        when more collect '(:br)))))
    (apply #'ui:stack* (list :gap :sm)
           (mapcar #'paragraph (cl-ppcre:split "\\n\\s*\\n" (or text ""))))))

(defun submit-button (label)
  "The button that sends a form of the history or the composer."
  (ui:cluster ()
              (ui:button (:type "submit" :variant :outline) label)))

(defun resolve-form (id)
  "An admin's form that settles a delivery whose outcome is unknown."
  `(:form (:@ :method "post" :action "/messages/resolve")
          (:input (:@ :type "hidden" :name "id" :value ,id))
          ,(ui:stack (:gap :md)
                     (ui:select (:label (tr ("Outcome" :context "settle")) :name "outcome"
                                 :options (list (list "accepted" (tr "Accepted"))
                                                (list "failed" (tr "Failed")))))
                     (ui:text-input (:label (tr "Note") :name "note" :required t))
                     (submit-button (tr "Settle")))))

(defun delivery-badges (item)
  "What became of a message: how its delivery went, its status's label, or
Received for a reply, and Settled when an admin settled it."
  (let* ((delivery (jget item "delivery"))
         (status (jget delivery "status"))
         (resolved (jget delivery "resolved_by")))
    (ui:cluster ()
                (if (equal (jget item "kind") "inbound")
                    (ui:badge (:variant :info) (tr "Received"))
                    (ui:badge (:variant (or (cdr (assoc status +delivery-variants+ :test #'equal))
                                            :secondary))
                              (if (stringp status)
                                  (render-text (label "delivery" "status" status))
                                  (render-text (label "message" "status" (jget item "status"))))))
                (when (and resolved (not (json-null-p resolved)))
                  (ui:badge (:variant :outline) (tr "Settled"))))))

(defun message-history-row (item)
  (let* ((delivery (jget item "delivery"))
         (recipient (jget item "recipient"))
         (error-message (jget delivery "safe_error_message")))
    (ui:card (:title (jget item "subject") :heading-level 3
                     :description (if (hash-table-p recipient) (jget recipient "email") recipient))
             (ui:stack (:gap :md)
                       (delivery-badges item)
                       (when (stringp error-message)
                         (ui:alert (:variant :destructive) error-message))
                       (text-paragraphs (jget item "body"))
                       (when (and (equal (jget delivery "status") "outcome_unknown")
                                  (eq (actor-role *actor*) :admin))
                         (resolve-form (jget item "id")))))))

(defun preview-form (order-id &rest fields)
  "A form that previews a message to ORDER-ID's customer, with FIELDS."
  `(:form (:@ :method "post" :action "/messages/preview")
          (:input (:@ :type "hidden" :name "order_id" :value ,order-id))
          ,@fields))

(defun composer (order-id templates)
  "The forms that preview a message to the order's customer: from a
template for employees, and a message of their own for admins."
  (let ((choices (loop for tpl in templates
                       unless (equal (message-template-name tpl) "order_message")
                       collect (list (message-template-name tpl)
                                     (translate (message-template-label tpl))))))
    (ui:card (:title (tr "New message to the customer") :heading-level 3
                     :description (tr "You see the message before it is queued."))
             (ui:stack (:gap :xl)
                       (when choices
                         (preview-form
                          order-id
                          (ui:stack (:gap :md)
                                    (ui:select (:label (tr "Template") :name "template"
                                                :options choices))
                                    (submit-button (tr "Preview message")))))
                       (when (and (eq (actor-role *actor*) :admin)
                                  (find-message-template "order_message"))
                         (preview-form
                          order-id
                          '(:input (:@ :type "hidden" :name "template" :value "order_message"))
                          (ui:stack (:gap :md)
                                    (ui:text-input (:label (tr ("Subject" :context "email"))
                                                    :name "subject" :required t))
                                    (ui:textarea (:label (tr "Message") :name "text" :required t
                                                         :rows 4))
                                    (submit-button (tr "Preview order message")))))))))

(defmethod tun.web:render-resource-extras ((app messaging-module) (entity (eql 'order)) record)
  (let* ((order (or (jget record "order") record)) (id (jget order "id"))
         (history (communication-history :order-id id))
         (items (subseq history (max 0 (- (length history) 100))))
         (templates (remove-if-not #'message-template-manual-p *message-templates*))
         (questions (coerce (or (jget order "open_questions") #()) 'list)))
    (list (apply #'tun.web:section (tr "Communication")
                 (append
                  (when questions
                    (list (ui:alert (:variant :info :title (tr "Questions for the customer"))
                                    `(:ul ,@(mapcar (lambda (question) `(:li ,question))
                                                    questions)))))
                  (if items
                      (mapcar #'message-history-row (reverse items))
                      (list `(:p ,(tr "No messages yet."))))
                  (when (actor-permits-p *actor* :employee)
                    (list (composer id templates))))))))

(defun composer-arguments (form)
  (let ((args (jobj)))
    (dolist (key '("template" "order_id" "customer_id" "subject" "text" "snapshot_hash"))
      (let ((value (jget form key))) (when value (setf (gethash key args) value)))) args))

(defun order-path (order-id)
  (when (stringp order-id) (format nil "/orders/~a" order-id)))

(defun send-form (args)
  "The form that confirms the previewed message ARGS and puts it in the queue."
  `(:form (:@ :method "post" :action "/messages/send")
          ,@(loop for key being the hash-keys of args using (hash-value value)
                  collect `(:input (:@ :type "hidden" :name ,key :value ,value)))
          ,(ui:form-actions (:cancel (order-path (jget args "order_id")))
             (ui:button (:type "submit" :icon :send) (tr "Confirm and queue")))))

(defun staff-message-page (method parts form query)
  (declare (ignore query))
  (unless (eq method :post) (return-from staff-message-page (values 404 (tr "Page not found") nil)))
  (let ((action (first parts)))
    (cond ((equal action "preview")
           (let* ((args (composer-arguments form)) (snapshot (call-tool "messages_preview" args)))
             (setf (gethash "snapshot_hash" args) (jget snapshot "snapshot_hash"))
             (values 200 (tr "Preview message")
                     (list (ui:card (:title (jget snapshot "subject") :heading-level 2)
                                    (ui:stack (:gap :lg)
                                              (text-paragraphs (jget snapshot "body"))
                                              (send-form args)))))))
          ((equal action "send")
           (call-tool "messages_send" (composer-arguments form))
           (let ((back (order-path (jget form "order_id"))))
             (values 200 (tr "The message is queued")
                     (list (ui:flash () (tr "The delivery status shows under Communication."))
                           (when back
                             (ui:button (:href back :variant :outline)
                                        (tr "Back to the order")))))))
          ((equal action "resolve")
           (call-tool "messages_resolve" (jobj "id" (jget form "id") "outcome" (jget form "outcome")
                                               "note" (jget form "note")))
           (values 200 (tr "Settled") (list (ui:flash () (tr "The delivery is settled.")))))
          (t (values 404 (tr "Page not found") nil)))))

;; The page answers the composer's posts; it is not a place to go to.
(tun.web:register-staff-page "messages" #'staff-message-page :title "Messages" :navigation nil)
(seal-module "messaging")
