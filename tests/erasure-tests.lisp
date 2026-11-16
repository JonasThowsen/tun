;;;; tests/erasure-tests.lisp -- erasing a customer outside customers_erase
;;;; (modules/customers README 5.1): a job or a workflow an admin or the
;;;; system asked for erases as the tool does, audited; no caller who could
;;;; not erase through the tool reaches it.

(in-package #:tun.tests)
(def-suite erasure :in core)
(in-suite erasure)

(tun.jobs:define-job erase-customer-job ((customer-id :type string :required t)
                                         (reason :type string))
  (:max-attempts 5)
  (tun.customers:erase-customer customer-id :reason reason))

(tun.jobs:define-job erase-customer-outside-job ((customer-id :type string :required t))
  (:transaction nil :max-attempts 5)
  (tun.customers:erase-customer customer-id))

(tun.jobs:define-job queue-erasure-job ((customer-id :type string :required t)) ()
                     (tun.jobs:enqueue-job 'erase-customer-job :customer-id customer-id))

(define-workflow erase-planned-customer (:kind "test_erase_customer" :label "Erase") (wf)
  (tun.customers:erase-customer (tun.workflows:workflow-subject-id wf)))

(define-operation erase-customer-here ((id :type string :required t))
    (:kind :update :policy :employee :title "Erase in an operation")
  (tun.customers:erase-customer id))

(define-operation erase-customer-as-system ((id :type string :required t))
    (:kind :update :policy :employee :title "Erase under a system actor")
  (with-actor ((system-actor "sneaky"))
    (tun.customers:erase-customer id)))

(define-operation queue-customer-erasure ((id :type string :required t)
                                          (chain :type boolean))
    (:kind :update :policy :employee :title "Queue an erasure")
  (tun.jobs:enqueue-job (if chain 'queue-erasure-job 'erase-customer-job) :customer-id id)
  (jobj "id" id))

(define-operation queue-customer-erasure-as-system ((id :type string :required t))
    (:kind :update :policy :employee :title "Queue an erasure under a system actor")
  (with-actor ((system-actor "sneaky"))
    (tun.jobs:enqueue-job 'erase-customer-job :customer-id id))
  (jobj "id" id))

(define-operation plan-customer-erasure ((id :type string :required t))
    (:kind :update :policy :employee :title "Plan an erasure")
  (tun.workflows:schedule-workflow "test_erase_customer" :subject-id id :due-at (now))
  (jobj "id" id))

(define-operation erase-customer-from-the-tool ((id :type string :required t))
    (:kind :update :policy :admin :title "Call customers_erase from code")
  (invoke 'tun.customers:customers-erase "id" id))

(defun customer-with-a-closed-quote (name key)
  "A customer named NAME, created with the request key KEY, whose order had a
quote and was cancelled: values the customer's id and the order's."
  (let* ((customer (jget (call-ok "customers_create" "employee:anna" "name" name
                                  "email" "same@example.no" "phone" "+47 900 00 000"
                                  "notes" "A note" "marketing_consent" t "request_key" key)
                         "id"))
         (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer
                               "lines" (lines (make-product) 1))
                      "id")))
    (advance-to-accepted order)
    (two-step "orders_cancel" "employee:anna" "id" order)
    (values customer order)))

(defun queue-as (actor kind &rest arguments)
  "Queue a job of KIND with ARGUMENTS as ACTOR, a \"role:name\" or an actor."
  (with-application (*app*)
    (with-actor ((if (stringp actor) (parse-actor actor) actor))
      (with-transaction (:write)
        (apply #'tun.jobs:enqueue-job kind arguments)))))

(defun erasure-job-json (job)
  "JOB as it is stored now."
  (with-application (*app*)
    (with-transaction (:read) (entity->json (fetch 'tun.jobs:job (entity-id job))))))

(defun customer-entries (id &optional outcome)
  "The audit entries of customers_erase about the customer ID, of OUTCOME when given."
  (remove-if-not (lambda (entry) (and (equal "customers_erase" (jget entry "tool"))
                                      (or (null outcome) (equal outcome (jget entry "outcome")))))
                 (coerce (jget (call-ok "audit_list" "admin:root" "entity_type" "customer"
                                        "entity_id" id "limit" 100)
                               "items")
                         'list)))

(defun erased-p (id)
  (jget (call-ok "customers_get" "viewer:v" "id" id) "erased"))

(defun alike-but-who (one other)
  "The keys whose values differ between ONE and OTHER, two customers' JSON,
besides those that name the customer or say when."
  (loop for key in (remove-duplicates (append (jkeys one) (jkeys other)) :test #'equal)
        unless (or (member key '("id" "name" "email" "erased_at" "created_at" "consent_at")
                           :test #'equal)
                   (equalp (jget one key) (jget other key)))
        collect key))

(test the-tool-erases-as-before-through-erase-customer
  (with-test-app ()
    (let ((id (make-customer "Tool Person")))
      (let ((first (call-ok "customers_erase" "admin:ada" "id" id)))
        (is (jget first "confirmation_required") "without a token it asks for one")
        (is (not (erased-p id))))
      (is (jget (two-step "customers_erase" "admin:ada" "id" id) "erased"))
      (let ((entries (customer-entries id "ok")))
        (is (= 1 (length entries)) "one entry, the tool's")
        (is (equal "admin:ada" (jget (first entries) "actor"))))
      (is (equal "confirmation_invalid"
                 (nth-value 1 (call "erase_customer_from_the_tool" "admin:ada" "id" id)))
          "the tool from code still needs a person's confirmation"))))

(test a-job-erases-a-customer-as-the-tool-does
  (with-test-app ()
    (multiple-value-bind (by-tool tool-order) (customer-with-a-closed-quote "Twin One" "twin-1")
      (multiple-value-bind (by-job job-order) (customer-with-a-closed-quote "Twin Two" "twin-2")
        (let ((tool-erased (two-step "customers_erase" "admin:ada" "id" by-tool))
              (job (queue-as "admin:ada" 'erase-customer-job :customer-id by-job
                             :reason "The customer asked")))
          (drain-jobs)
          (is (equal "succeeded" (jget (erasure-job-json job) "state")))
          (let ((job-erased (call-ok "customers_get" "viewer:v" "id" by-job)))
            (is (jget job-erased "erased"))
            (is (null (alike-but-who tool-erased job-erased))
                "alike but who: ~a" (alike-but-who tool-erased job-erased))
            (is (search (subseq by-job (- (length by-job) 8)) (jget job-erased "name"))
                "the placeholder ends in the id's last eight")
            (is (search "@slettet.local" (jget job-erased "email"))))
          (dolist (order (list tool-order job-order))
            (is (equal "[erased]" (jget (jget (call-ok "quotes_get" "admin:ada" "order_id" order)
                                              "snapshot")
                                        "customer_name"))
                "the quote of ~a" order))
          (loop for (id key name) in `((,by-tool "twin-1" "Twin One") (,by-job "twin-2" "Twin Two"))
                for replay = (call-ok "customers_create" "employee:anna" "name" name
                                      "email" "same@example.no" "phone" "+47 900 00 000"
                                      "notes" "A note" "marketing_consent" t "request_key" key)
                do (is (equal id (jget replay "id")))
                (is (jget replay "erased") "the receipt of ~a holds the erased record" id))
          (let ((entries (customer-entries by-job "ok")))
            (is (= 1 (length entries)) "audited once")
            (is (equal "system:job" (jget (first entries) "actor")))
            (is (equal "The customer asked" (jget (first entries) "reason")))))))))

(test a-job-without-a-transaction-a-workflow-and-a-schedules-job-erase
  (with-test-app ()
    (let ((outside (make-customer "Outside Person"))
          (planned (make-customer "Planned Person"))
          (swept (make-customer "Swept Person")))
      (let ((job (queue-as "admin:ada" 'erase-customer-outside-job :customer-id outside)))
        (drain-jobs)
        (is (equal "succeeded" (jget (erasure-job-json job) "state")))
        (is (erased-p outside))
        (let ((entries (customer-entries outside "ok")))
          (is (= 1 (length entries)))
          (is (equal (format nil "job ~a, enqueued by admin:ada" (entity-id job))
                     (jget (first entries) "reason"))
              "where it ran, without a reason: ~a" (jget (first entries) "reason"))))
      (call-ok "plan_customer_erasure" "admin:ada" "id" planned)
      (drain-jobs)
      (is (erased-p planned) "a workflow an admin planned erases")
      (let ((entries (customer-entries planned "ok")))
        (is (= 1 (length entries)))
        (is (equal "system:workflow" (jget (first entries) "actor"))))
      (queue-as (system-actor "schedule") 'erase-customer-job :customer-id swept)
      (drain-jobs)
      (is (erased-p swept) "a job a schedule queued erases")
      (is (= 1 (length (customer-entries swept "ok")))))))

(test no-caller-who-could-not-erase-reaches-erase-customer
  (with-test-app ()
    (flet ((refused-once (id)
             (is (not (erased-p id)) "~a is not erased" id)
             (let ((entries (customer-entries id "rejected")))
               (is (= 1 (length entries)) "~a: one rejected entry: ~a" id entries)
               (is (equal "forbidden" (jget (first entries) "error_code"))))))
      (let ((id (make-customer "Here Person")))
        (is (equal "forbidden" (nth-value 1 (call "erase_customer_here" "employee:anna" "id" id))))
        (refused-once id)
        (is (equal "employee:anna" (jget (first (customer-entries id "rejected")) "actor"))))
      (let ((id (make-customer "Admin Person")))
        (is (equal "forbidden" (nth-value 1 (call "erase_customer_here" "admin:ada" "id" id)))
            "an admin's operation does not skip the confirmation")
        (refused-once id))
      (let ((id (make-customer "System Person")))
        (is (equal "forbidden"
                   (nth-value 1 (call "erase_customer_as_system" "employee:anna" "id" id))))
        (refused-once id))
      (dolist (chain '(nil t))
        (let ((id (make-customer (if chain "Chain Person" "Queued Person"))))
          (call-ok "queue_customer_erasure" "employee:anna" "id" id "chain" chain)
          (drain-jobs)
          (refused-once id)
          (let ((job (aref (jget (call-ok "jobs_list" "admin:root" "kind" "erase_customer_job")
                                 "items")
                           0)))
            (is (equal "failed" (jget job "state")) "the job fails at once")
            (is (= 1 (jget job "attempts")) "after one attempt")
            (is (equal "employee:anna" (jget job "enqueued_by"))
                "a job a job queued names the call it started from"))))
      (let ((id (make-customer "Disguised Person")))
        (call-ok "queue_customer_erasure_as_system" "employee:anna" "id" id)
        (let ((job (aref (jget (call-ok "jobs_list" "admin:root" "kind" "erase_customer_job"
                                        "state" "queued")
                               "items")
                         0)))
          (is (equal "employee:anna" (jget job "enqueued_by"))
              "queued under a system actor, it names the caller: ~a" (jget job "enqueued_by")))
        (drain-jobs)
        (refused-once id))
      (let ((id (make-customer "Workflow Person")))
        (call-ok "plan_customer_erasure" "employee:anna" "id" id)
        (drain-jobs)
        (refused-once id)
        (is (equal '("failed")
                   (with-application (*app*)
                     (with-transaction (:read)
                       (mapcar #'tun.workflows:workflow-status
                               (select 'tun.workflows:workflow
                                       :where `(:= "subject_id" ,id))))))
            "the workflow fails, so it is not run again")))))

(test a-refusal-of-the-erasure-fails-a-job-as-the-tool
  (with-test-app ()
    (let* ((customer (make-customer "Open Person"))
           (order (jget (call-ok "orders_create" "employee:anna" "customer_id" customer
                                 "lines" (lines (make-product) 1))
                        "id")))
      (advance-to-accepted order)
      (is (equal "conflict" (nth-value 1 (two-step "customers_erase" "admin:ada" "id" customer))))
      (let ((job (queue-as "admin:ada" 'erase-customer-job :customer-id customer)))
        (drain-jobs)
        (is (member (jget (erasure-job-json job) "state") '("retrying" "failed") :test #'equal))
        (is (search "open order" (jget (erasure-job-json job) "last_error"))
            "the module's refusal: ~a" (jget (erasure-job-json job) "last_error")))
      (is (not (erased-p customer)))
      (is (null (customer-entries customer "ok"))))))
