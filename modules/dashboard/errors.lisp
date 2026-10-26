;;;; modules/dashboard/errors.lisp -- «Feil»: the errors an application has
;;;; had, grouped by cause (spec/errors.md 3, 8), as Sentry lists its issues.

(in-package #:tun.dashboard)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +error-statuses+
  '(("open" "Åpne" :destructive)
    ("resolved" "Løste" :success)
    ("ignored" "Ignorerte" :outline))
  "Each status of an error: its name, its label, and its badge.")

(defun error-status-label (status)
  (or (second (assoc status +error-statuses+ :test #'string=)) status))

(defun error-status-badge (status)
  (ui:badge (:variant (or (third (assoc status +error-statuses+ :test #'string=)) :secondary))
    (error-status-label status)))

(defun text-or-dash (value)
  (if (and (stringp value) (plusp (length value))) value "—"))

(defun errors-table (errors &key (empty "Ingen feil."))
  (ui:table (:columns '("Feil" "Type" "Hvor" "Antall" "Sist sett")
                      :rows (mapcar (lambda (error)
                                      (list (shortened (text-or-dash (jget error "message")) 80)
                                            (text-or-dash (jget error "error_type"))
                                            (text-or-dash (jget error "tool"))
                                            (jget error "count")
                                            (when-text (jget error "last_seen_at"))))
                                    errors)
                      :row-href (mapcar (lambda (error) (format nil "/feil/~a" (jget error "id")))
                                        errors)
                      :empty empty)))

(defun errors-list-page (query)
  (let* ((status (let ((asked (jget query "status")))
                   (if (assoc asked +error-statuses+ :test #'equal) asked "open")))
         (result (read-result "errors_list" "status" status))
         (counts (jget result "counts")))
    (values 200 "Feil"
            (list (tab-buttons status
                               (loop for (each label) in +error-statuses+
                                     collect (list each (format nil "~a (~d)" label (jget counts each))
                                                   (format nil "/feil?status=~a" each))))
                  (errors-table (items-of result)
                                :empty (if (string= status "open")
                                           "Ingen åpne feil."
                                           (format nil "Ingen ~(~a~) feil." (error-status-label status)))))
            (list :description "Feil koden ikke mente, gruppert etter årsak: hva som skjedde, hvor, hvor mange ganger og når. En løst feil som skjer igjen, blir åpen."))))

;;; ------------------------------------------------------------------
;;; One error

(defun request-link (request-id)
  "A link to REQUEST-ID's page in «Logg», or a dash."
  (if (stringp request-id)
      (ui:link (:href (format nil "/logg/~a" request-id)) request-id)
      "—"))

(defun occurrences-table (occurrences)
  (ui:table (:columns '("Når" "Forespørsel" "Hvor" "Aktør" "Melding" "Tid")
                      :rows (mapcar (lambda (occurrence)
                                      (list (when-text (jget occurrence "at"))
                                            (text-or-dash (jget occurrence "request_id"))
                                            (text-or-dash (jget occurrence "tool"))
                                            (text-or-dash (jget occurrence "actor"))
                                            (shortened (text-or-dash (jget occurrence "message")) 80)
                                            (ms-text (jget occurrence "total_ms"))))
                                    occurrences)
                      :row-href (mapcar (lambda (occurrence)
                                          (format nil "/logg/~a" (jget occurrence "request_id")))
                                        occurrences)
                      :empty "Ingen forekomster.")))

(defun error-actions (error)
  (let ((path (format nil "/feil/~a/status/" (jget error "id"))))
    (if (string= (jget error "status") "open")
        (ui:cluster ()
          (post-button (concatenate 'string path "resolved") "Merk som løst" :variant :primary)
          (post-button (concatenate 'string path "ignored") "Ignorer"))
        (post-button (concatenate 'string path "open") "Åpne igjen"))))

(defun error-detail-page (id &key problem)
  (let ((error (read-result "errors_get" "id" id)))
    (values 200 (shortened (text-or-dash (jget error "message")) 80)
            (list (when problem (tun.web:error-alert problem))
                  (ui:summary-list
                   (:rows (list (list "Status" (error-status-badge (jget error "status")))
                                (list "Kode" (jget error "code"))
                                (list "Type" (text-or-dash (jget error "error_type")))
                                (list "Hvor" (text-or-dash (jget error "tool")))
                                (list "Antall ganger" (jget error "count"))
                                (list "Først sett" (when-text (jget error "first_seen_at")))
                                (list "Sist sett" (when-text (jget error "last_seen_at")))
                                (list "Siste forespørsel" (request-link (jget error "request_id"))))))
                  (ui:section (:title "Melding")
                    (ui:code-block (:wrap t) (text-or-dash (jget error "message"))))
                  (ui:section (:title "Backtrace" :description "Der feilen oppsto, innerst først, siste gang.")
                    (let ((frames (coerce (or (jget error "backtrace") #()) 'list)))
                      (if frames
                          (ui:code-block () (format nil "~{~a~^~%~}" frames))
                          (ui:empty-state (:icon :circle-alert :title "Ingen backtrace")))))
                  (ui:section (:title "Forekomster" :description "De siste 50, nyeste først. Forespørselen vises så lenge prosessen har den i minnet.")
                    (occurrences-table (items-of error "occurrences")))
                  (error-actions error))
            (list :breadcrumbs (list (list :label "Feil" :href "/feil")
                                     (list :label (error-status-label (jget error "status"))
                                           :href (format nil "/feil?status=~a" (jget error "status")))
                                     (list :label (jget error "id")))))))

(tun.web:define-page errors-page ("feil" :title "Feil" :icon :triangle-alert :policy :admin
                                     :group :system)
    (method path form query)
  (destructuring-bind (&optional id action status &rest more) path
    (cond (more (fail :not-found "Siden finnes ikke"))
          ((null id) (errors-list-page query))
          ((and (null action) (eq method :get)) (error-detail-page id))
          ((and (equal action "status") status (eq method :post))
           (change "errors_set_status" (jobj "id" id "status" status) (format nil "/feil/~a" id)
                   (lambda (problem) (error-detail-page id :problem problem))))
          (t (fail :not-found "Siden finnes ikke")))))
