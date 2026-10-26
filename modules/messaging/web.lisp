;;;; web.lisp -- communication history and the preview/send composer, built
;;;; from the design system's components (spec/ui.md).
(in-package #:tun.messaging)

(defparameter +delivery-labels+
  '(("queued" . "Lagt i kø") ("sending" . "Sender") ("accepted" . "Akseptert av e-postleverandør")
    ("failed" . "Kunne ikke sendes") ("outcome_unknown" . "Ukjent leveringsutfall")))

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
                     (ui:select (:label "Avklaring" :name "outcome"
                                        :options '(("accepted" "Akseptert") ("failed" "Feilet"))))
                     (ui:text-input (:label "Merknad" :name "note" :required t))
                     (submit-button "Avklar"))))

(defun delivery-badges (item)
  "What became of a message: how its delivery went, or Mottatt for a reply,
and Avklart when an admin settled it."
  (let* ((delivery (jget item "delivery"))
         (status (jget delivery "status"))
         (resolved (jget delivery "resolved_by")))
    (ui:cluster ()
                (if (equal (jget item "kind") "innkommende")
                    (ui:badge (:variant :info) "Mottatt")
                    (ui:badge (:variant (or (cdr (assoc status +delivery-variants+ :test #'equal))
                                            :secondary))
                              (or (cdr (assoc status +delivery-labels+ :test #'equal))
                                  (jget item "status"))))
                (when (and resolved (not (json-null-p resolved)))
                  (ui:badge (:variant :outline) "Avklart")))))

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
                       unless (equal (message-template-name tpl) "ordremelding")
                       collect (list (message-template-name tpl)
                                     (message-template-label tpl)))))
    (ui:card (:title "Ny melding til kunden" :heading-level 3
                     :description "Du ser meldingen før den legges i kø.")
             (ui:stack (:gap :xl)
                       (when choices
                         (preview-form
                          order-id
                          (ui:stack (:gap :md)
                                    (ui:select (:label "Mal" :name "template" :options choices))
                                    (submit-button "Forhåndsvis melding"))))
                       (when (and (eq (actor-role *actor*) :admin)
                                  (find-message-template "ordremelding"))
                         (preview-form
                          order-id
                          '(:input (:@ :type "hidden" :name "template" :value "ordremelding"))
                          (ui:stack (:gap :md)
                                    (ui:text-input (:label "Emne" :name "subject" :required t))
                                    (ui:textarea (:label "Melding" :name "text" :required t
                                                         :rows 4))
                                    (submit-button "Forhåndsvis ordremelding"))))))))

(defmethod tun.web:render-resource-extras ((app messaging-module) (entity (eql 'order)) record)
  (let* ((order (or (jget record "order") record)) (id (jget order "id"))
         (history (communication-history :order-id id))
         (items (subseq history (max 0 (- (length history) 100))))
         (templates (remove-if-not #'message-template-manual-p *message-templates*))
         (questions (coerce (or (jget order "open_questions") #()) 'list)))
    (list (apply #'tun.web:section "Kommunikasjon"
                 (append
                  (when questions
                    (list (ui:alert (:variant :info :title "Spørsmål til kunden")
                                    `(:ul ,@(mapcar (lambda (question) `(:li ,question))
                                                    questions)))))
                  (if items
                      (mapcar #'message-history-row (reverse items))
                      (list '(:p "Ingen meldinger ennå.")))
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
             (ui:button (:type "submit" :icon :send) "Bekreft og legg i kø"))))

(defun staff-message-page (method parts form query)
  (declare (ignore query))
  (unless (eq method :post) (return-from staff-message-page (values 404 "Siden finnes ikke" nil)))
  (let ((action (first parts)))
    (cond ((equal action "preview")
           (let* ((args (composer-arguments form)) (snapshot (call-tool "messages_preview" args)))
             (setf (gethash "snapshot_hash" args) (jget snapshot "snapshot_hash"))
             (values 200 "Forhåndsvis melding"
                     (list (ui:card (:title (jget snapshot "subject") :heading-level 2)
                                    (ui:stack (:gap :lg)
                                              (text-paragraphs (jget snapshot "body"))
                                              (send-form args)))))))
          ((equal action "send")
           (call-tool "messages_send" (composer-arguments form))
           (let ((back (order-path (jget form "order_id"))))
             (values 200 "Meldingen er lagt i kø"
                     (list (ui:flash () "Leveringsstatus vises under Kommunikasjon.")
                           (when back
                             (ui:button (:href back :variant :outline) "Tilbake til ordren"))))))
          ((equal action "resolve")
           (call-tool "messages_resolve" (jobj "id" (jget form "id") "outcome" (jget form "outcome")
                                               "note" (jget form "note")))
           (values 200 "Avklart" (list (ui:flash () "Leveringen er avklart."))))
          (t (values 404 "Siden finnes ikke" nil)))))

;; The page answers the composer's posts; it is not a place to go to.
(tun.web:register-staff-page "messages" #'staff-message-page :title "Meldinger" :navigation nil)
(seal-module "messaging")
