;;;; web.lisp -- inbox handling forms call the same guarded operations as MCP;
;;;; the pages are built from the design system's components (spec/ui.md).
(in-package #:tun.inbox)

(defparameter +request-status-variants+
  '(("new" . :info) ("handled" . :success) ("dismissed" . :destructive)))

(defun inquiry-status-label (status)
  "The label of the inquiry status STATUS, in the current language."
  (render-text (label "inquiry" "status" status)))

(defun request-status-badge (status)
  (ui:badge (:variant (or (cdr (assoc status +request-status-variants+ :test #'equal))
                          :secondary))
            (if (stringp status) (inquiry-status-label status) "")))

(defun request-body (text)
  "The text of a request, a paragraph per block and its line breaks kept."
  (flet ((paragraph (lines)
           `(:p ,@(loop for (line . more) on (cl-ppcre:split "\\n" lines)
                        collect line
                        when more collect '(:br)))))
    (apply #'ui:stack* (list :gap :sm)
           (mapcar #'paragraph (cl-ppcre:split "\\n\\s*\\n" (or text ""))))))

(defun received-date (item)
  "The day ITEM was received, in the tenant's time zone and language."
  (let ((at (and (stringp (jget item "received_at")) (parse-rfc3339 (jget item "received_at")))))
    (if at (date-text (local-date-of at)) "")))

(defun handling-choices (item)
  "What can be done with the new request ITEM: a draft order unless it has one."
  (append (unless (stringp (jget item "created_order_id"))
            (list (list "convert" (tr "Create a draft order"))))
          (list (list "attach" (tr "Attach to an order"))
                (list "dismiss" (tr "Dismiss")))))

(defun handling-form (item)
  "The form that converts, attaches or dismisses a new request."
  (let ((choices (handling-choices item)))
    `(:form (:@ :method "post" :action ,(format nil "/inquiries/~a" (jget item "id")))
            ,(ui:stack (:gap :lg)
                       (ui:radios (:legend (tr "Action") :name "action" :required t
                                           :choices choices :selected (first (first choices))))
                       (ui:text-input (:label (tr "Order ID") :name "order_id" :optional t
                                       :width 30
                                       :hint (tr "Only when the inquiry is attached to an order.")))
                       (ui:textarea (:label (tr "Note") :name "note" :optional t :rows 3))
                       (ui:form-actions (:cancel "/inquiries")
                         (ui:button (:type "submit") (tr "Handle")))))))

(defun request-detail (item)
  (let ((questions (coerce (or (jget item "questions") #()) 'list))
        (note (jget item "note")))
    (list (ui:card (:title (jget item "subject") :heading-level 2
                           :description (jget item "from_email")
                           :action (request-status-badge (jget item "status")))
                   (request-body (jget item "body")))
          (when (stringp note)
            (ui:alert (:title (tr "Note")) note))
          (when questions
            (ui:alert (:variant :info :title (tr "Questions for the customer"))
                      `(:ul ,@(mapcar (lambda (q) `(:li ,q)) questions))))
          (when (equal (jget item "status") "new")
            (ui:card (:title (tr "Handle the inquiry") :heading-level 2)
                     (handling-form item))))))

(defun request-table (items)
  (if items
      (ui:table (:columns (list (tr ("Subject" :context "email")) (tr "From") (tr "Status")
                                (tr "Received"))
                          :rows (mapcar (lambda (item)
                                          (list (jget item "subject")
                                                (jget item "from_email")
                                                (request-status-badge (jget item "status"))
                                                (received-date item)))
                                        items)
                          :row-href (mapcar (lambda (item)
                                              (format nil "/inquiries/~a" (jget item "id")))
                                            items)))
      (ui:empty-state (:icon :inbox :title (tr "No inquiries")
                             :description (tr "Email from customers arrives here.")))))

(defun status-choices ()
  "The statuses the list can be narrowed to, with their labels."
  (cons (list "" (tr "All"))
        (mapcar (lambda (status) (list status (inquiry-status-label status)))
                '("new" "handled" "dismissed"))))

(defun status-filter (current)
  `(:form (:@ :method "get" :action "/inquiries")
          ,(ui:cluster (:align :end)
                       (ui:select (:label (tr "Status") :name "status" :selected current
                                          :options (status-choices)))
                       (ui:button (:type "submit" :variant :outline :icon :funnel) (tr "Filter")))))

(defun staff-inbox-page (method parts form query)
  (let ((id (first parts)))
    (when (eq method :post)
      (let ((args (jobj "id" id "action" (jget form "action"))))
        (dolist (key '("order_id" "note"))
          (let ((value (jget form key)))
            (unless (blank-p value) (setf (gethash key args) value))))
        (call-tool "inquiries_handle" args)))
    (if id
        (values 200 (tr "Inquiry") (request-detail (call-tool "inquiries_get" (jobj "id" id))))
        (let ((args (jobj "limit" 100)))
          (dolist (key '("status" "kind"))
            (let ((value (jget query key)))
              (unless (blank-p value) (setf (gethash key args) value))))
          (values 200 (tr "Inquiries")
                  (list (status-filter (jget query "status"))
                        (request-table (coerce (jget (call-tool "inquiries_list" args) "items")
                                               'list))))))))

(tun.web:register-staff-page "inquiries" #'staff-inbox-page :title "Inquiries" :icon :inbox)
(seal-module "inbox")
