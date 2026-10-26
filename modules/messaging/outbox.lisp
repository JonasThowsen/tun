;;;; outbox.lisp -- serialized claims and one fake provider call outside client transactions.
;;;; Each delivery has a job, send_delivery, in the :outbox queue (spec/jobs.md):
;;;; the job decides when the worker runs; the claim decides whether it calls
;;;; the provider, once, ever (README §6, §7).
(in-package #:tun.messaging)
(defvar *outbox-lock* (sb-thread:make-mutex :name "serial tenant outbox")
  "Held by the one drain the test-mode request hook starts.")
(defvar *provider-lock* (sb-thread:make-mutex :name "serial provider calls")
  "Held around each claim and provider call: they run one at a time per tenant.")
(defconstant +outbox-batch-size+ 16)
(defparameter +provider-errors+
  '(("suppressed" . "Meldingen ble ikke sendt: kunden har trukket samtykket eller er slettet.")
    ("provider_disabled" . "E-postlevering er deaktivert. Meldingen ble ikke sendt.")
    ("provider_rejected" . "E-postleverandøren avviste meldingen. Kontroller mottaker og innhold.")
    ("provider_unauthorized" . "E-postleverandøren avviste tilgangen. Meldingen ble ikke sendt.")
    ("invalid_message" . "Meldingssnapshotet er ugyldig og ble ikke sendt.")
    ("rate_limited" . "E-postleverandøren ba oss vente. Utfallet må avklares før nytt forsøk.")
    ("timeout" . "E-postleveringen fikk tidsavbrudd. Utfallet er ukjent og må gjennomgås.")
    ("transport" . "Forbindelsen til e-postleverandøren brøt. Utfallet er ukjent og må gjennomgås.")
    ("unknown_provider_outcome" . "E-postleverandørens utfall er ukjent. Ingen automatisk retry utføres.")))
(defun provider-mode () (or (read-setting "messaging.provider.mode") "accept"))
(defun fail-delivery (row status code &key (notify t))
  (setf (delivery-status row) status (delivery-error-code row) code
        (delivery-safe-error-message row) (cdr (assoc code +provider-errors+ :test #'equal)) (delivery-failed-at row) (now))
  (incf (delivery-transition-version row)) (save row)
  (let* ((item (fetch! 'message (delivery-message-id row))) (recipient (message-recipient item))
         (order-id (message-order-id item)) (customer-id (message-customer-id item)))
    (when notify (publish-notification "leveranse_feilet" (entity-id row)
      (format nil "En e-post til ~a kunne ikke sendes." (jget recipient "name"))
      (format nil "/~a/~a" (if order-id "orders" "customers") (or order-id customer-id)) "message" (entity-id item) :order-id order-id :recipients (notification-recipients)))))
(defun delivery-job-running-p (row)
  "True when ROW's delivery job runs now in a live process: jobs of processes
that are gone are recovered before the modules open (spec/jobs.md 7)."
  (let ((job (and (delivery-job-id row) (fetch 'tun.jobs:job (delivery-job-id row)))))
    (and job (equal (tun.jobs:job-state job) "running"))))
(defun queue-delivery-job (row)
  (setf (delivery-job-id row) (entity-id (tun.jobs:enqueue-job 'send-delivery :delivery-id (entity-id row))))
  (save row))
(defun reconcile-outbox ()
  "On start: a delivery left sending by a process that is gone has an unknown
outcome (README §10); every queued one gets its job (unique, so one that has
a job keeps it)."
  (with-transaction (:write)
    (dolist (row (select 'delivery :where '(:= "status" "sending")))
      (unless (delivery-job-running-p row)
        (fail-delivery row "outcome_unknown" "unknown_provider_outcome")))
    (dolist (row (select 'delivery :where '(:= "status" "queued")))
      (queue-delivery-job row))))
(define-workflow delivery-watchdog (:kind "leveranse_vakt" :label "Leveringsvakt") (wf)
  (let ((row (fetch 'delivery (tun.workflows:workflow-subject-id wf))))
    (when (and row (equal (delivery-status row) "sending")
               (equal (tun.workflows:workflow-key wf) (format nil "~a:~d" (entity-id row) (delivery-attempt-count row))))
      (fail-delivery row "outcome_unknown" "unknown_provider_outcome"))))
(defun queued-delivery (id)
  "The delivery ID when it is queued, or without ID the oldest queued one."
  (if id
      (let ((row (fetch 'delivery id))) (and row (equal (delivery-status row) "queued") row))
      (select-one 'delivery :where '(:= "status" "queued") :order-by '(("seq" :asc)))))
(defun claim-outbox-delivery (&optional id)
  "Claim the delivery ID, or without ID the oldest queued: values the row, the
provider mode and the call number, or NIL when there is nothing to call."
  (unless (provider-call-capacity-p) (return-from claim-outbox-delivery nil))
  (with-transaction (:write)
    (let ((row (queued-delivery id)))
      (loop while row
            for item = (fetch! 'message (delivery-message-id row))
            for customer = (fetch 'customer (message-customer-id item))
            for template = (find-message-template (message-template item))
            while (or (null customer) (customer-erased customer)
                      (and template (message-template-marketing-p template)
                           (not (marketing-allowed-p customer))))
            do (fail-delivery row "failed" "suppressed" :notify nil)
               (write-system-audit "outbox.suppressed" "ok" :entity-type "message"
                 :entity-id (entity-id item) :error-code "suppressed"
                 :reason (delivery-safe-error-message row))
               (setf row (and (null id) (queued-delivery nil))))
      (when row
        (setf (delivery-status row) "sending" (delivery-sending-started-at row) (now))
        (incf (delivery-attempt-count row)) (incf (delivery-transition-version row)) (save row)
        (tun.workflows:schedule-workflow "leveranse_vakt" :subject-id (entity-id row) :due-at (+ (now) 300)
          :key (format nil "~a:~d" (entity-id row) (delivery-attempt-count row)))
        (let ((calls (1+ (or (read-setting "messaging.provider.calls") 0))))
          (write-setting "messaging.provider.calls" calls) (values row (provider-mode) calls))))))
(defgeneric deliver-snapshot (adapter request mode call-number)
  (:documentation "Provider port: frozen from/reply-to/to/subject/text/html/headers; only safe classifications leave the adapter."))
(defmethod deliver-snapshot ((adapter fake-message-transport) request mode call-number)
  (declare (ignore request))
  (cond ((equal mode "slow") (sleep 3) (values "accepted" nil (format nil "fake-~d" call-number)))
        ((equal mode "sleep_ok") (sleep 11) (values "accepted" nil (format nil "fake-~d" call-number)))
        ((equal mode "timeout") (sleep (if (test-mode-p) 4.1 10.1)) (values "outcome_unknown" "timeout" nil))
        ((equal mode "crash") (error "fake provider call aborted"))
        ((equal mode "accept") (values "accepted" nil (format nil "fake-~d" call-number)))
        ((member mode '("reject" "unauthorized" "disabled") :test #'equal)
         (values "failed" (cdr (assoc mode '(("reject" . "provider_rejected") ("unauthorized" . "provider_unauthorized") ("disabled" . "provider_disabled")) :test #'equal)) nil))
        (t (values "outcome_unknown" mode nil))))
(defun process-outbox-delivery (row mode calls)
  (let ((request (with-transaction (:read)
                   (let ((item (fetch! 'message (delivery-message-id row))))
                     (jobj "message_id" (entity-id item) "delivery_id" (entity-id row) "from" (message-sender item)
                           "reply_to" (jget (message-sender item) "reply_to") "to" (message-recipient item)
                           "subject" (message-subject item) "text" (message-body item) "html" (message-html item)
                           "headers" (jobj "X-Tun-Message-Id" (entity-id item)))))))
    (multiple-value-bind (status code provider-id)
        (handler-case
            (let ((app *application*) (adapter (or (application-message-transport *application*) (make-instance 'fake-message-transport))))
              (call-with-time-limit (lambda () (with-application (app) (deliver-snapshot adapter request mode calls))) (if (test-mode-p) 4 10)))
          (deadline-exceeded () (values "outcome_unknown" "timeout" nil))
          (serious-condition () (values "outcome_unknown" "unknown_provider_outcome" nil)))
      (with-transaction (:write)
        (let ((current (fetch! 'delivery (entity-id row))))
          (when (and (equal (delivery-status current) "sending") (= (delivery-transition-version current) (delivery-transition-version row)))
            (if (equal status "accepted")
                (progn (setf (delivery-status current) status (delivery-provider current) "fake"
                             (delivery-provider-message-id current) provider-id (delivery-accepted-at current) (now))
                       (incf (delivery-transition-version current)) (save current))
                (fail-delivery current status code))))))))
(tun.jobs:define-job send-delivery ((delivery-id :type id :required t))
    (:queue :outbox :transaction nil :max-attempts 1 :after-crash :fail :unique (:keys (delivery-id)))
  "Make the delivery DELIVERY-ID's one provider call, if it is still queued and
its customer may still get it (README §7)."
  ;; The outbox is busy with another delivery, or abandoned calls past their
  ;; deadline still run: not now.  Waiting instead would claim the moment the
  ;; other call ends, before a consent withdrawn meanwhile is seen.
  (let ((ran nil))
    (when (provider-call-capacity-p)
      (call-with-worker-lock *provider-lock*
        (lambda ()
          (setf ran t)
          (with-actor ((system-actor "outbox"))
            (multiple-value-bind (row mode calls) (claim-outbox-delivery delivery-id)
              (when row
                (process-outbox-delivery row mode calls)))))))
    (unless ran
      (tun.jobs:snooze-job 0))))
(defun drain-outbox (app)
  "Run the outbox's due delivery jobs, a batch at a time, as the test-mode
request hook does."
  (call-with-worker-lock *outbox-lock*
    (lambda ()
      (with-application (app)
        (let ((*request-record* nil) (*request-id* nil) (*inside-operation* nil) (*deadline* nil))
          (tun.jobs:run-due-jobs :queue "outbox" :limit +outbox-batch-size+))))))
(defmethod application-after-request ((app messaging-module))
  (call-next-method)
  ;; In test mode the outbox drains right after the queuing request commits,
  ;; before the next request (README §7); a server's job workers do it in
  ;; normal mode.
  (when (and (test-mode-p)
             (not (worker-running-p *outbox-lock*))
             (with-transaction (:read) (select-one 'delivery :where '(:= "status" "queued"))))
    ;; Quick adapters may finish after commit before the next request. This
    ;; bounded window never depends on a provider mode or adapter class.
    (start-worker (lambda () (drain-outbox app)) "tun outbox" .25)))
(defclass provider-mode-type (enum-type) ()
  (:default-initargs :values '("accept" "reject" "unauthorized" "disabled" "rate_limited" "transport" "timeout" "crash" "slow")))
(defmethod coerce-input ((type provider-mode-type) value path)
  (if (and *application* (test-mode-p) (equal value "sleep_ok"))
      value
      (call-next-method)))
(define-operation messaging-provider-set ((mode :type provider-mode-type :required t))
    (:kind :update :policy :admin :test-only t :title "Sett testleverandør")
  (write-setting "messaging.provider.mode" mode) (jobj "mode" mode))
(define-operation messaging-provider-get () (:kind :read :policy :admin :title "Testleverandør")
  (jobj "mode" (provider-mode) "calls" (or (read-setting "messaging.provider.calls") 0)))
(define-operation messages-resolve ((id :type id :required t) (outcome :type (enum "accepted" "failed") :required t)
                                    (note :type (string :min 1 :max 2000) :required t))
    (:entity message :kind :update :policy :admin :title "Avklar leveringsutfall")
  (let* ((item (fetch! 'message id)) (row (select-one 'delivery :where `(:= "message_id" ,id))))
    (unless (and row (equal (delivery-status row) "outcome_unknown")) (fail :invalid-transition "Leveransen kan ikke avklares"))
    (setf (delivery-status row) outcome (delivery-resolved-by row) (actor-string *actor*) (delivery-resolution-note row) note)
    (if (equal outcome "accepted") (setf (delivery-accepted-at row) (now)) (setf (delivery-failed-at row) (now)))
    (incf (delivery-transition-version row)) (save row) item))
