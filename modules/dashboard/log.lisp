;;;; modules/dashboard/log.lisp -- «Logg»: the requests the process has in
;;;; memory (spec/errors.md 8), as Telescope lists them, and one request with
;;;; its steps in time order, read from the trace core keeps (core.md §8.1).

(in-package #:tun.dashboard)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +log-selections+
  '(("all" "Alle") ("errors" "Feil") ("rejected" "Avvist") ("slow" "Trege"))
  "introspect_recent's selections and their labels.")

(defparameter +request-kinds+
  '(("operation" "Verktøy") ("web" "Nettsider") ("job" "Jobber") ("workflow" "Arbeidsflyter")
    ("mcp" "MCP"))
  "The kinds of request and their labels.")

(defparameter +log-rows+ 200 "How many requests the list shows.")
(defparameter +shown-steps+ 300 "How many steps a request's page shows.")

(defun kind-label (kind)
  (or (second (assoc kind +request-kinds+ :test #'equal)) (text-or-dash kind)))

(defun outcome-badge (outcome)
  (cond ((equal outcome "ok") (ui:badge (:variant :success) "OK"))
        ((equal outcome "rejected") (ui:badge (:variant :warning) "Avvist"))
        ((equal outcome "running") (ui:badge (:variant :info) "Kjører"))
        (t (ui:badge (:variant :destructive) "Feil"))))

(defun log-href (selection kind)
  (format nil "/logg?utvalg=~a~@[&slag=~a~]" selection kind))

(defun requests-table (requests)
  (ui:table (:columns '("Når" "Slag" "Hva" "Aktør" "Utfall" "Tid")
                      :rows (mapcar (lambda (request)
                                      (list (when-text (jget request "at"))
                                            (kind-label (jget request "kind"))
                                            (text-or-dash (jget request "tool"))
                                            (text-or-dash (jget request "actor"))
                                            (outcome-badge (jget request "outcome"))
                                            (ms-text (jget request "total_ms"))))
                                    requests)
                      :row-href (mapcar (lambda (request)
                                          (format nil "/logg/~a" (jget request "request_id")))
                                        requests)
                      :empty "Ingen forespørsler.")))

(defun inflight-table (requests)
  (ui:table (:columns '("Forespørsel" "Hva" "Aktør" "Tilstand" "Har kjørt")
                      :rows (mapcar (lambda (request)
                                      (list (jget request "request_id")
                                            (text-or-dash (jget request "tool"))
                                            (text-or-dash (jget request "actor"))
                                            (jget request "state")
                                            (ms-text (jget request "elapsed_ms"))))
                                    requests))))

(defun log-list-page (query)
  (let* ((selection (let ((asked (jget query "utvalg")))
                      (if (assoc asked +log-selections+ :test #'equal) asked "all")))
         (kind (let ((asked (jget query "slag")))
                 (and (assoc asked +request-kinds+ :test #'equal) asked)))
         (requests (items-of (apply #'read-result "introspect_recent" "kind" selection
                                    "limit" +log-rows+
                                    (and kind (list "request_kind" kind)))))
         (inflight (items-of (read-result "introspect_inflight"))))
    (values 200 "Logg"
            (list (tab-buttons selection (loop for (each label) in +log-selections+
                                               collect (list each label (log-href each kind))))
                  (tab-buttons kind (cons (list nil "Alle slag" (log-href selection nil))
                                          (loop for (each label) in +request-kinds+
                                                collect (list each label (log-href selection each))))
                               :variant :outline)
                  (when inflight
                    (ui:section (:title "Pågår nå")
                      (inflight-table inflight)))
                  (requests-table requests))
            (list :description (format nil "De siste ~d forespørslene prosessen har i minnet, nyeste først. De lagres ikke: etter en omstart begynner listen på nytt, og feil finnes i «Feil»." +log-rows+)))))

;;; ------------------------------------------------------------------
;;; One request

(defun step-share (entry total)
  "The time of ENTRY, one of a request's steps, drawn as a bar against TOTAL,
the request's."
  (let ((duration (jget entry "duration_ms")))
    (if (and (realp duration) (realp total) (plusp total))
        (let ((percent (min 100 (round (* 100 duration) total))))
          (ui:progress (:label (ms-text duration) :value percent :value-text (format nil "~d %" percent))))
        (ms-text duration))))

(defun steps-table (request)
  (let ((steps (subseq-at-most (items-of request "steps") +shown-steps+))
        (total (jget request "total_ms")))
    (ui:table (:columns '("Start" "Steg" "Navn" "Tid" "Detalj")
                        :rows (mapcar (lambda (entry)
                                        (list (ms-text (jget entry "started_ms"))
                                              (jget entry "kind")
                                              (text-or-dash (jget entry "name"))
                                              (step-share entry total)
                                              (let ((detail (jget entry "detail")))
                                                (if (stringp detail) (shortened detail 120) "—"))))
                                      steps)
                        :empty "Ingen steg."))))

(defun request-detail-page (id)
  (let* ((request (read-result "introspect_request" "request_id" id))
         (error (jget request "error"))
         (policy (jget request "policy"))
         (backtrace (coerce (or (jget request "backtrace") #()) 'list))
         (dropped (jget request "steps_dropped")))
    (values 200 (text-or-dash (jget request "tool"))
            (list (ui:summary-list
                   (:rows (list (list "Forespørsel" (jget request "request_id"))
                                (list "Når" (when-text (jget request "at")))
                                (list "Slag" (kind-label (or (jget request "kind") "operation")))
                                (list "Aktør" (text-or-dash (jget request "actor")))
                                (list "Utfall" (outcome-badge (jget request "outcome")))
                                (list "Feil" (if error
                                                 (format nil "~a: ~a" (jget error "code") (jget error "message"))
                                                 "—"))
                                (list "Tid" (ms-text (jget request "total_ms")))
                                (list "Lagringskall" (jget request "store_statements"))
                                (list "Ventet på skrivelåsen" (ms-text (jget request "write_lock_wait_ms")))
                                (list "Tilgang" (format nil "~a krever ~a, aktøren er ~a"
                                                        (text-or-dash (jget policy "decision"))
                                                        (text-or-dash (jget policy "required"))
                                                        (text-or-dash (jget policy "actor_role")))))))
                  (ui:section (:title "Input")
                    (ui:code-block (:wrap t) (to-json-string (jget request "input"))))
                  (ui:section (:title "Steg"
                               :description (format nil "I tidsrekkefølge, med tiden målt mot hele forespørselens~@[; ~d steg til ble ikke tatt vare på~]."
                                                    (and (integerp dropped) dropped)))
                    (steps-table request))
                  (when backtrace
                    (ui:section (:title "Backtrace" :description "Der feilen oppsto, innerst først.")
                      (ui:code-block () (format nil "~{~a~^~%~}" backtrace)))))
            (list :breadcrumbs (list (list :label "Logg" :href "/logg")
                                     (list :label (jget request "request_id")))))))

(tun.web:define-page log-page ("logg" :title "Logg" :icon :file-text :policy :admin
                                     :group :system)
    (method path form query)
  (destructuring-bind (&optional id &rest more) path
    (cond ((or more (not (eq method :get))) (fail :not-found "Siden finnes ikke"))
          ((null id) (log-list-page query))
          (t (request-detail-page id)))))

(seal-module "dashboard")
