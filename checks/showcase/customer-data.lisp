;;;; customer-data.lisp -- the «Customer data» page: an admin downloads a
;;;; customer's data as JSON, read by an operation that is audited with the
;;;; reason the admin gives (spec/core.md 3.8), and answered by the page as a
;;;; download, kept nowhere (spec/files.md 5.5); and the «Audit log» page,
;;;; where the export's entry is seen.

(in-package #:showcase)

(define-operation customer-data-export
    ((customer-id :type (id customer) :required t :label "Customer")
     (reason :type (string :min 1 :max 500) :required t :label "Reason"
             :description "Why the customer's data is exported, for the audit log."))
    (:entity customer :kind :read :policy :admin :audit t :title "Export a customer's data"
             :description "The customer's data as one JSON document; each export is in the audit log with its reason.")
  (audit-reason reason)
  (jobj "customer" (entity->json (fetch! 'customer customer-id))))

(defun export-customer-choices ()
  "Each customer not erased, as a choice: its id and name."
  (loop for item across (jget (web-call "customers_list" (jobj "limit" 100)) "items")
        unless (jget item "erased")
        collect (list (jget item "id") (jget item "name"))))

(defun customer-data-body (&key problem form)
  "The page: a customer to choose, the reason, and the button that downloads."
  (let ((fields (list (ui:select (:label (tr "Customer") :name "customer_id"
                                         :options (export-customer-choices)
                                         :selected (and form (jget form "customer_id"))))
                      (ui:textarea (:label (tr "Reason") :name "reason" :rows 3
                                           :hint (tr "Why the data is exported: it is kept in the audit log.")
                                           :value (and form (jget form "reason")))))))
    (list (ui:card (:title (tr "A customer's data")
                           :description (tr "Everything the showcase holds about a customer, as JSON."))
            ;; Sent without htmx: the answer is a file, not a page.
            `(:form (:@ :method "post" :action "/customer-data" :hx-boost "false")
                    ,(apply #'ui:stack* (list :gap :lg)
                            (append (when problem (list (error-alert problem :fields fields)))
                                    fields
                                    (list (ui:form-actions ()
                                            (ui:button (:type "submit" :icon :download)
                                              (tr "Download the data")))))))))))

(defun export-filename (json)
  "The name of the export JSON: the customer's name, as a page's data gives it."
  (format nil "customer-~a.json" (jget (jget json "customer") "name")))

(define-page customer-data-page ("customer-data" :title "Customer data" :icon :download
                                                 :policy :admin :group :system)
    (method path form query)
  (declare (ignore path query))
  (if (eq method :post)
      (multiple-value-bind (json code)
          (web-call "customer_data_export" (jobj "customer_id" (jget form "customer_id")
                                                 "reason" (jget form "reason")))
        (if code
            (values 422 (tr "Customer data") (customer-data-body :problem json :form form))
            (values 200 :download (make-download (to-json-string json)
                                                 :filename (export-filename json)
                                                 :content-type "application/json"))))
      (values 200 (tr "Customer data") (customer-data-body)
              (list :description (tr "An export of a customer's data, audited with its reason.")))))

(defun audit-rows (items)
  "The audit log's ITEMS as the table's rows, newest first."
  (map 'list (lambda (entry)
               (list (jget entry "tool")
                     (jget entry "actor")
                     (let ((type (jget entry "entity_type")) (id (jget entry "entity_id")))
                       (if (stringp id) (format nil "~a ~a" type id) ""))
                     (let ((reason (jget entry "reason"))) (if (stringp reason) reason ""))
                     (jget entry "outcome")))
       items))

(define-page audit-log-page ("audit" :title "Audit log" :icon :shield-check :policy :admin
                                     :group :system)
    (method path form query)
  (declare (ignore method path form query))
  (values 200 (tr "Audit log")
          (list (ui:table (:caption (tr "Audit log") :caption-hidden t
                                    :columns (list (tr "Tool") (tr "Actor") (tr "Record") (tr "Reason")
                                                   (list (tr "Outcome") :narrow nil))
                                    :rows (audit-rows (jget (web-call "audit_list" (jobj "limit" 20))
                                                            "items"))
                                    :attributes '(:data-audit-log t))))
          (list :description (tr "The latest entries, newest first."))))
