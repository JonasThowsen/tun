;;;; modules/dashboard/log.lisp -- "Log": the requests the process has in
;;;; memory (spec/errors.md 8), as Telescope lists them, and one request with
;;;; its steps in time order, read from the trace core keeps (core.md §8.1).

(in-package #:tun.dashboard)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +log-selections+ '("all" "errors" "rejected" "slow")
  "introspect_recent's selections.")

(defparameter +request-kinds+ '("operation" "web" "job" "workflow" "mcp")
  "The kinds of request.")

(defparameter +log-rows+ 200 "How many requests the list shows.")
(defparameter +shown-steps+ 300 "How many steps a request's page shows.")

(defun selection-label (selection)
  "The label of SELECTION, one of +LOG-SELECTIONS+."
  (cond ((equal selection "all") (tr "All"))
        ((equal selection "errors") (tr "Errors"))
        ((equal selection "rejected") (tr "Refused"))
        (t (tr "Slow"))))

(defun kind-label (kind)
  "The label of a request of KIND, one of +REQUEST-KINDS+, for the requests of
that kind; a dash for none."
  (cond ((equal kind "operation") (tr "Tools"))
        ((equal kind "web") (tr "Web pages"))
        ((equal kind "job") (tr "Jobs"))
        ((equal kind "workflow") (tr "Workflows"))
        ((equal kind "mcp") (tr "MCP"))
        (t (text-or-dash kind))))

(defun inflight-state-label (state)
  "The label of the state of a request in flight, as introspect_inflight names it."
  (cond ((equal state "running") (tr "Running"))
        ((equal state "waiting_write_lock") (tr "Waiting for the write lock"))
        ((equal state "external_call") (tr "Calling another system"))
        (t (text-or-dash state))))

(defun outcome-badge (outcome)
  (cond ((equal outcome "ok") (ui:badge (:variant :success) (tr "OK")))
        ((equal outcome "rejected") (ui:badge (:variant :warning) (tr "Refused")))
        ((equal outcome "running") (ui:badge (:variant :info) (tr "Running")))
        (t (ui:badge (:variant :destructive) (tr "Error")))))

(defun log-href (selection kind)
  (format nil "/log?selection=~a~@[&kind=~a~]" selection kind))

(defun requests-table (requests)
  (ui:table (:columns (list (tr "When") (tr "Request kind") (tr "What") (tr "Actor") (tr "Outcome")
                            (tr ("Duration" :context "time taken")))
                      :rows (mapcar (lambda (request)
                                      (list (when-text (jget request "at"))
                                            (kind-label (jget request "kind"))
                                            (text-or-dash (jget request "tool"))
                                            (text-or-dash (jget request "actor"))
                                            (outcome-badge (jget request "outcome"))
                                            (ms-text (jget request "total_ms"))))
                                    requests)
                      :row-href (mapcar (lambda (request)
                                          (format nil "/log/~a" (jget request "request_id")))
                                        requests)
                      :empty (tr "No requests."))))

(defun inflight-table (requests)
  (ui:table (:columns (list (tr "Request") (tr "What") (tr "Actor") (tr "State")
                            (tr "Running for"))
                      :rows (mapcar (lambda (request)
                                      (list (jget request "request_id")
                                            (text-or-dash (jget request "tool"))
                                            (text-or-dash (jget request "actor"))
                                            (inflight-state-label (jget request "state"))
                                            (ms-text (jget request "elapsed_ms"))))
                                    requests))))

(defun log-list-page (query)
  (let* ((selection (let ((asked (jget query "selection")))
                      (if (member asked +log-selections+ :test #'equal) asked "all")))
         (kind (let ((asked (jget query "kind")))
                 (and (member asked +request-kinds+ :test #'equal) asked)))
         (requests (items-of (apply #'read-result "introspect_recent" "kind" selection
                                    "limit" +log-rows+
                                    (and kind (list "request_kind" kind)))))
         (inflight (items-of (read-result "introspect_inflight"))))
    (values 200 (tr "Log")
            (list (tab-buttons selection (loop for each in +log-selections+
                                               collect (list each (selection-label each)
                                                             (log-href each kind))))
                  (tab-buttons kind (cons (list nil (tr "All kinds") (log-href selection nil))
                                          (loop for each in +request-kinds+
                                                collect (list each (kind-label each)
                                                              (log-href selection each))))
                               :variant :outline)
                  (when inflight
                    (ui:section (:title (tr "In progress"))
                      (inflight-table inflight)))
                  (requests-table requests))
            (list :description (tr "The last ~d requests the process has in memory, newest first. They are not stored: after a restart the list begins again, and errors are in “Errors”." +log-rows+)))))

;;; ------------------------------------------------------------------
;;; One request

(defun step-share (entry total)
  "The time of ENTRY, one of a request's steps, drawn as a bar against TOTAL,
the request's."
  (let ((duration (jget entry "duration_ms")))
    (if (and (realp duration) (realp total) (plusp total))
        (let ((percent (min 100 (round (* 100 duration) total))))
          (ui:progress (:label (ms-text duration) :value percent
                               :value-text (tr "~d%" percent))))
        (ms-text duration))))

(defun steps-table (request)
  (let ((steps (subseq-at-most (items-of request "steps") +shown-steps+))
        (total (jget request "total_ms")))
    (ui:table (:columns (list (tr "Start") (tr "Step") (tr "Name")
                              (tr ("Duration" :context "time taken")) (tr "Detail"))
                        :rows (mapcar (lambda (entry)
                                        (list (ms-text (jget entry "started_ms"))
                                              (jget entry "kind")
                                              (text-or-dash (jget entry "name"))
                                              (step-share entry total)
                                              (let ((detail (jget entry "detail")))
                                                (if (stringp detail) (shortened detail 120) "—"))))
                                      steps)
                        :empty (tr "No steps.")))))

(defun request-detail-page (id)
  (let* ((request (read-result "introspect_request" "request_id" id))
         (error (jget request "error"))
         (policy (jget request "policy"))
         (backtrace (coerce (or (jget request "backtrace") #()) 'list))
         (dropped (jget request "steps_dropped")))
    (values 200 (text-or-dash (jget request "tool"))
            (list (ui:summary-list
                   (:rows (list (list (tr "Request") (jget request "request_id"))
                                (list (tr "When") (when-text (jget request "at")))
                                (list (tr "Request kind")
                                      (kind-label (or (jget request "kind") "operation")))
                                (list (tr "Actor") (text-or-dash (jget request "actor")))
                                (list (tr "Outcome") (outcome-badge (jget request "outcome")))
                                (list (tr "Error") (if error
                                                       (format nil "~a: ~a" (jget error "code")
                                                               (jget error "message"))
                                                       "—"))
                                (list (tr ("Duration" :context "time taken"))
                                      (ms-text (jget request "total_ms")))
                                (list (tr "Store calls") (jget request "store_statements"))
                                (list (tr "Waited for the write lock")
                                      (ms-text (jget request "write_lock_wait_ms")))
                                (list (tr "Access") (tr "~a requires ~a, the actor is ~a"
                                                        (text-or-dash (jget policy "decision"))
                                                        (text-or-dash (jget policy "required"))
                                                        (text-or-dash (jget policy "actor_role")))))))
                  (ui:section (:title (tr "Input"))
                    (ui:code-block (:wrap t) (to-json-string (jget request "input"))))
                  (ui:section (:title (tr "Steps")
                                      :description (tr "In time order, each step's time against the whole request's~@[; ~d more steps were not kept~]."
                                                       (and (integerp dropped) dropped)))
                    (steps-table request))
                  (when backtrace
                    (ui:section (:title (tr "Backtrace")
                                        :description (tr "Where the error happened, innermost first."))
                      (ui:code-block () (format nil "~{~a~^~%~}" backtrace)))))
            (list :breadcrumbs (list (list :label (tr "Log") :href "/log")
                                     (list :label (jget request "request_id")))))))

(tun.web:define-page log-page ("log" :title "Log" :icon :file-text :policy :admin
                                     :group :system)
    (method path form query)
  (destructuring-bind (&optional id &rest more) path
    (cond ((or more (not (eq method :get))) (fail :not-found "The page does not exist"))
          ((null id) (log-list-page query))
          (t (request-detail-page id)))))

(seal-module "dashboard")
