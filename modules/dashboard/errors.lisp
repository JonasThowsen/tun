;;;; modules/dashboard/errors.lisp -- "Errors": the errors an application has
;;;; had, grouped by cause (spec/errors.md 3, 8), as Sentry lists its issues.

(in-package #:tun.dashboard)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +error-statuses+
  '(("open" :destructive)
    ("resolved" :success)
    ("ignored" :outline))
  "Each status of an error: its name and its badge.")

(defun error-status-label (status)
  "STATUS's label as the page writes it, for the errors in it: Open, Resolved,
Ignored."
  (cond ((equal status "open") (tr ("Open" :context "errors")))
        ((equal status "resolved") (tr ("Resolved" :context "errors")))
        ((equal status "ignored") (tr ("Ignored" :context "errors")))
        (t (text-or-dash status))))

(defun error-status-badge (status)
  (ui:badge (:variant (or (second (assoc status +error-statuses+ :test #'string=)) :secondary))
    (error-status-label status)))

(defun text-or-dash (value)
  (if (and (stringp value) (plusp (length value))) value "—"))

(defun errors-table (errors &key (empty (tr "No errors.")))
  (ui:table (:columns (list (tr "Error") (tr "Type") (tr "Where") (tr "Count") (tr "Last seen"))
                      :rows (mapcar (lambda (error)
                                      (list (shortened (text-or-dash (jget error "message")) 80)
                                            (text-or-dash (jget error "error_type"))
                                            (text-or-dash (jget error "tool"))
                                            (jget error "count")
                                            (when-text (jget error "last_seen_at"))))
                                    errors)
                      :row-href (mapcar (lambda (error) (format nil "/errors/~a" (jget error "id")))
                                        errors)
                      :empty empty)))

(defun errors-list-page (query)
  (let* ((status (let ((asked (jget query "status")))
                   (if (assoc asked +error-statuses+ :test #'equal) asked "open")))
         (result (read-result "errors_list" "status" status))
         (counts (jget result "counts")))
    (values 200 (tr "Errors")
            (list (tab-buttons status
                               (loop for (each) in +error-statuses+
                                     collect (list each
                                                   (format nil "~a (~d)" (error-status-label each)
                                                           (jget counts each))
                                                   (format nil "/errors?status=~a" each))))
                  (errors-table (items-of result)
                                :empty (if (string= status "open")
                                           (tr "No open errors.")
                                           (tr "No ~(~a~) errors." (error-status-label status)))))
            (list :description (tr "Errors the code did not mean, grouped by cause: what happened, where, how many times and when. A resolved error that happens again is open again.")))))

;;; ------------------------------------------------------------------
;;; One error

(defun request-link (request-id)
  "A link to REQUEST-ID's page in the log, or a dash."
  (if (stringp request-id)
      (ui:link (:href (format nil "/log/~a" request-id)) request-id)
      "—"))

(defun occurrences-table (occurrences)
  (ui:table (:columns (list (tr "When") (tr "Request") (tr "Where") (tr "Actor") (tr "Message")
                            (tr ("Duration" :context "time taken")))
                      :rows (mapcar (lambda (occurrence)
                                      (list (when-text (jget occurrence "at"))
                                            (text-or-dash (jget occurrence "request_id"))
                                            (text-or-dash (jget occurrence "tool"))
                                            (text-or-dash (jget occurrence "actor"))
                                            (shortened (text-or-dash (jget occurrence "message")) 80)
                                            (ms-text (jget occurrence "total_ms"))))
                                    occurrences)
                      :row-href (mapcar (lambda (occurrence)
                                          (format nil "/log/~a" (jget occurrence "request_id")))
                                        occurrences)
                      :empty (tr "No occurrences."))))

(defun error-actions (error)
  (let ((path (format nil "/errors/~a/status/" (jget error "id"))))
    (if (string= (jget error "status") "open")
        (ui:cluster ()
          (post-button (concatenate 'string path "resolved") (tr "Mark as resolved")
                       :variant :primary)
          (post-button (concatenate 'string path "ignored") (tr "Ignore")))
        (post-button (concatenate 'string path "open") (tr "Open again")))))

(defun error-detail-page (id &key problem)
  (let ((error (read-result "errors_get" "id" id)))
    (values 200 (shortened (text-or-dash (jget error "message")) 80)
            (list (when problem (tun.web:error-alert problem))
                  (ui:summary-list
                   (:rows (list (list (tr "Status") (error-status-badge (jget error "status")))
                                (list (tr "Code") (jget error "code"))
                                (list (tr "Type") (text-or-dash (jget error "error_type")))
                                (list (tr "Where") (text-or-dash (jget error "tool")))
                                (list (tr "Times") (jget error "count"))
                                (list (tr "First seen") (when-text (jget error "first_seen_at")))
                                (list (tr "Last seen") (when-text (jget error "last_seen_at")))
                                (list (tr "Last request")
                                      (request-link (jget error "request_id"))))))
                  (ui:section (:title (tr "Message"))
                    (ui:code-block (:wrap t) (text-or-dash (jget error "message"))))
                  (ui:section (:title (tr "Backtrace")
                                      :description (tr "Where the error happened, innermost first, the last time."))
                    (let ((frames (coerce (or (jget error "backtrace") #()) 'list)))
                      (if frames
                          (ui:code-block () (format nil "~{~a~^~%~}" frames))
                          (ui:empty-state (:icon :circle-alert :title (tr "No backtrace"))))))
                  (ui:section (:title (tr "Occurrences")
                                      :description (tr "The last 50, newest first. A request shows as long as the process has it in memory."))
                    (occurrences-table (items-of error "occurrences")))
                  (error-actions error))
            (list :breadcrumbs (list (list :label (tr "Errors") :href "/errors")
                                     (list :label (error-status-label (jget error "status"))
                                           :href (format nil "/errors?status=~a" (jget error "status")))
                                     (list :label (jget error "id")))))))

(tun.web:define-page errors-page ("errors" :title "Errors" :icon :triangle-alert :policy :admin
                                     :group :system)
    (method path form query)
  (destructuring-bind (&optional id action status &rest more) path
    (cond (more (fail :not-found "The page does not exist"))
          ((null id) (errors-list-page query))
          ((and (null action) (eq method :get)) (error-detail-page id))
          ((and (equal action "status") status (eq method :post))
           (change "errors_set_status" (jobj "id" id "status" status) (format nil "/errors/~a" id)
                   (lambda (problem) (error-detail-page id :problem problem))))
          (t (fail :not-found "The page does not exist")))))
