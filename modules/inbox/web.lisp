;;;; web.lisp -- inbox handling forms call the same guarded operations as MCP;
;;;; the pages are built from the design system's components (spec/ui.md).
(in-package #:tun.inbox)

(defparameter +request-status-variants+
  '(("ny" . :info) ("behandlet" . :success) ("avvist" . :destructive)))

(defun request-status-badge (status)
  (ui:badge (:variant (or (cdr (assoc status +request-status-variants+ :test #'equal))
                          :secondary))
            (if (stringp status) (string-capitalize status :end (min 1 (length status))) "")))

(defun request-body (text)
  "The text of a request, a paragraph per block and its line breaks kept."
  (flet ((paragraph (lines)
           `(:p ,@(loop for (line . more) on (cl-ppcre:split "\\n" lines)
                        collect line
                        when more collect '(:br)))))
    (apply #'ui:stack* (list :gap :sm)
           (mapcar #'paragraph (cl-ppcre:split "\\n\\s*\\n" (or text ""))))))

(defun received-date (item)
  "The day ITEM was received, as DD.MM.YYYY."
  (let ((at (jget item "received_at")))
    (if (and (stringp at) (>= (length at) 10))
        (format nil "~a.~a.~a" (subseq at 8 10) (subseq at 5 7) (subseq at 0 4))
        "")))

(defun handling-choices (item)
  "What can be done with the new request ITEM: a draft order unless it has one."
  (append (unless (stringp (jget item "created_order_id"))
            '(("convert" "Opprett ordreutkast")))
          '(("attach" "Knytt til ordre") ("dismiss" "Avvis"))))

(defun handling-form (item)
  "The form that converts, attaches or dismisses a new request."
  (let ((choices (handling-choices item)))
    `(:form (:@ :method "post" :action ,(format nil "/henvendelser/~a" (jget item "id")))
            ,(ui:stack (:gap :lg)
                       (ui:radios (:legend "Handling" :name "action" :required t
                                           :choices choices :selected (first (first choices))))
                       (ui:text-input (:label "Ordre-ID" :name "order_id" :optional t :width 30
                                              :hint "Bare når henvendelsen knyttes til en ordre."))
                       (ui:textarea (:label "Merknad" :name "note" :optional t :rows 3))
                       (ui:form-actions (:cancel "/henvendelser")
                         (ui:button (:type "submit") "Behandle"))))))

(defun request-detail (item)
  (let ((questions (coerce (or (jget item "questions") #()) 'list))
        (note (jget item "note")))
    (list (ui:card (:title (jget item "subject") :heading-level 2
                           :description (jget item "from_email")
                           :action (request-status-badge (jget item "status")))
                   (request-body (jget item "body")))
          (when (stringp note)
            (ui:alert (:title "Merknad") note))
          (when questions
            (ui:alert (:variant :info :title "Spørsmål til kunden")
                      `(:ul ,@(mapcar (lambda (q) `(:li ,q)) questions))))
          (when (equal (jget item "status") "ny")
            (ui:card (:title "Behandle henvendelsen" :heading-level 2)
                     (handling-form item))))))

(defun request-table (items)
  (if items
      (ui:table (:columns '("Emne" "Fra" "Status" "Mottatt")
                          :rows (mapcar (lambda (item)
                                          (list (jget item "subject")
                                                (jget item "from_email")
                                                (request-status-badge (jget item "status"))
                                                (received-date item)))
                                        items)
                          :row-href (mapcar (lambda (item)
                                              (format nil "/henvendelser/~a" (jget item "id")))
                                            items)))
      (ui:empty-state (:icon :inbox :title "Ingen henvendelser"
                             :description "E-post fra kunder kommer hit."))))

(defparameter +status-choices+
  '(("" "Alle") ("ny" "Ny") ("behandlet" "Behandlet") ("avvist" "Avvist"))
  "The statuses the list can be narrowed to.")

(defun status-filter (current)
  `(:form (:@ :method "get" :action "/henvendelser")
          ,(ui:cluster (:align :end)
                       (ui:select (:label "Status" :name "status" :selected current
                                          :options +status-choices+))
                       (ui:button (:type "submit" :variant :outline :icon :funnel) "Filtrer"))))

(defun staff-inbox-page (method parts form query)
  (let ((id (first parts)))
    (when (eq method :post)
      (let ((args (jobj "id" id "action" (jget form "action"))))
        (dolist (key '("order_id" "note"))
          (let ((value (jget form key)))
            (unless (blank-p value) (setf (gethash key args) value))))
        (call-tool "henvendelser_handle" args)))
    (if id
        (values 200 "Henvendelse" (request-detail (call-tool "henvendelser_get" (jobj "id" id))))
        (let ((args (jobj "limit" 100)))
          (dolist (key '("status" "kind"))
            (let ((value (jget query key)))
              (unless (blank-p value) (setf (gethash key args) value))))
          (values 200 "Henvendelser"
                  (list (status-filter (jget query "status"))
                        (request-table (coerce (jget (call-tool "henvendelser_list" args) "items")
                                               'list))))))))

(tun.web:register-staff-page "henvendelser" #'staff-inbox-page :title "Henvendelser" :icon :inbox)
(seal-module "inbox")
