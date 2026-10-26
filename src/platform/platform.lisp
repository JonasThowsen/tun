;;;; platform/platform.lisp -- platform tools (kernel, entity null):
;;;; registry_describe, audit_list, the virtual clock, accounting_status and
;;;; the debug tools.

(defpackage #:tun.platform
  (:use #:cl #:tun.core)
  (:export #:registry-describe #:audit-list #:clock-get #:clock-set #:accounting-status
           #:debug-burn #:debug-sleep #:debug-schedule))

(in-package #:tun.platform)

(declaim (optimize (safety 3) (debug 2)))

(define-operation registry-describe ()
    (:kind :read :title "Beskriv registeret"
     :description "Alle entiteter (med felt og kilde: core eller klient), operasjoner med flagg, arbeidsflyter og meldingsmaler.")
  (describe-registry))

(defun audit-entry->json (entry)
  (jobj "id" (entity-id entry)
        "at" (format-rfc3339 (audit-entry-at entry))
        "actor" (audit-entry-actor entry)
        "tool" (audit-entry-tool entry)
        "outcome" (audit-entry-outcome entry)
        "entity_type" (or (audit-entry-entity-type entry) :null)
        "entity_id" (or (audit-entry-entity-id entry) :null)
        "request_key" (or (audit-entry-request-key entry) :null)
        "error_code" (or (audit-entry-error-code entry) :null)
        "reason" (or (audit-entry-reason entry) :null)
        "credential" (or (audit-entry-credential entry) :null)))

(define-operation audit-list ((entity-type :type (string :max 100) :label "Entitetstype")
                              (entity-id :type (string :max 100) :label "Entitets-ID")
                              (limit :type (integer :min 1 :max 100) :default 20 :label "Maks antall"))
    (:kind :read :title "List revisjonslogg"
     :description "Revisjonslogg, nyeste først. Inneholder aldri tokens eller hemmeligheter.")
  (let ((where (remove nil (list (and entity-type `(:= "entity_type" ,entity-type))
                                 (and entity-id `(:= "entity_id" ,entity-id))))))
    (jobj "items" (jarr (mapcar #'audit-entry->json
                                (select 'audit-entry :where (and where `(:and ,@where))
                                                     :order-by '(("seq" :desc))
                                                     :limit limit))))))

;;; ------------------------------------------------------------------
;;; The virtual clock (test mode only: hidden from tools/list otherwise)

(define-operation clock-get ()
    (:kind :read :test-only t :title "Les klokken"
     :description "Serverens nåværende tid (testmodus).")
  (jobj "now" (now-string)))

(define-operation clock-set ((now :type timestamp :required t :label "Nytt tidspunkt"))
    (:kind :workflow :policy :admin :test-only t :title "Still klokken"
     :description "Stiller den virtuelle klokken, kjører alle forfalte arbeidsflyter i forfallsrekkefølge og alle forfalte jobber, med e-postene som skal sendes, før den svarer (testmodus).")
  (let* ((clock (application-clock *application*))
         (previous (test-clock-now clock)))
    (set-test-clock clock now)
    ;; If the transaction does not commit (here or later, at audit or COMMIT),
    ;; the stored clock rolls back; so must the in-memory one.
    (on-rollback (lambda () (set-test-clock clock previous)))
    (write-setting "test_clock.now" (format-rfc3339 now))
    ;; The clock commits first; then every due workflow runs in its own
    ;; transaction with its own deadline, and the schedules and every due
    ;; job run (spec/jobs.md 11), mail delivery among them, as the
    ;; scheduler does in normal mode.
    (complete-after-commit (jobj "now" (format-rfc3339 now))
                           (lambda ()
                             (let ((executed (tun.workflows:run-due-workflows)))
                               (jobj "now" (format-rfc3339 now)
                                     "executed_workflows" executed
                                     "job_attempts" (progn (tun.jobs:tend-schedules)
                                                           (tun.jobs:run-due-jobs))))))))

;;; ------------------------------------------------------------------
;;; The accounting port's adapter, as the kernel sees it

(define-operation accounting-status ()
    (:kind :read :policy :admin :title "Regnskapsstatus"
     :description "Hva regnskapsadapteren har mottatt: ekstern referanse og antall kall per faktura.")
  (let ((adapter (application-accounting *application*)))
    (jobj "adapter" (tun.accounting:adapter-name adapter)
          "invoices" (jarr (mapcar (lambda (s) (jobj "invoice_id" (getf s :invoice-id)
                                                     "external_ref" (getf s :external-ref)
                                                     "calls" (getf s :calls)))
                                   (tun.accounting:adapter-status adapter))))))

;;; ------------------------------------------------------------------
;;; Debug tools (core.md §7.6): present only with --debug-tools.  Policy runs
;;; before the work, like every operation.  burn and sleep are read
;;; operations (they hold no write lock) and stop at the deadline.

(define-operation debug-burn ((ms :type (integer :min 0 :max 3600000) :required t :label "Millisekunder"))
    (:kind :read :policy :employee :debug-only t :title "Brenn CPU (debug)"
     :description "Spinner CPU-en i operasjonen i ms millisekunder (avbrytes ved fristen).")
  (let ((end (+ (get-internal-real-time) (round (* ms internal-time-units-per-second) 1000)))
        (x 0))
    (declare (type fixnum x))
    (loop while (< (get-internal-real-time) end)
          do (check-deadline)
             (dotimes (i 20000) (setf x (logand (+ x i 7) #xfffff))))
    (jobj "burned_ms" ms "checksum" x)))

(define-operation debug-sleep ((ms :type (integer :min 0 :max 3600000) :required t :label "Millisekunder"))
    (:kind :read :policy :employee :debug-only t :title "Sov (debug)"
     :description "Blokkerer i operasjonen i ms millisekunder (avbrytes ved fristen).")
  (sleep-with-deadline ms)
  (jobj "slept_ms" ms))

(define-workflow debug-ping (:kind "debug_ping" :label "Debug-ping" :debug t) (wf)
  ;; Only records: the workflow row's status and executed_at are the record.
  (declare (ignore wf)))

(define-operation debug-schedule ((due-in-ms :type (integer :min 0 :max 86400000) :required t
                                             :label "Forfall om (ms)"))
    (:kind :create :policy :admin :debug-only t :title "Planlegg debug-ping (debug)"
     :description "Planlegger en debug_ping-arbeidsflyt som forfaller om due_in_ms.")
  ;; Stored times are whole seconds: round the due time up, so the ping never
  ;; runs before DUE-IN-MS has passed (it may run up to a second later).
  (tun.workflows:schedule-workflow "debug_ping" :due-at (ceiling (+ (now-ms) due-in-ms) 1000)))
