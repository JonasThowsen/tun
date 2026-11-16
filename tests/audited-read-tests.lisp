;;;; tests/audited-read-tests.lisp -- a read that asks for an audit entry
;;;; (spec/core.md 3.8): the entry it writes, and that it holds nothing read;
;;;; the entry before the data; where :audit and audit-reason are refused.

(in-package #:tun.tests)
(def-suite audited-reads :in core)
(in-suite audited-reads)

(define-operation audited-customer-export
    ((customer-id :type (id tun.customers:customer) :required t :label "Customer")
     (reason :type (string :min 1 :max 1000) :required t :label "Reason"))
    (:entity tun.customers:customer :kind :read :policy :admin :audit t
             :title "Export a customer, audited")
  (audit-reason reason)
  (jobj "customer" (entity->json (fetch! 'tun.customers:customer customer-id))))

(define-operation plain-customer-export
    ((customer-id :type (id tun.customers:customer) :required t :label "Customer"))
    (:entity tun.customers:customer :kind :read :policy :admin :title "Export a customer")
  (jobj "customer" (entity->json (fetch! 'tun.customers:customer customer-id))))

(define-operation audited-customer-get ((id :type (id tun.customers:customer) :required t))
    (:entity tun.customers:customer :kind :read :policy :viewer :audit t
             :title "Get a customer, audited")
  (fetch! 'tun.customers:customer id))

(define-operation audited-named-read ((customer :type string :required t))
    (:kind :read :policy :viewer :audit t :title "A read naming its record")
  (audit-target "customer" customer)
  (jobj "ok" t))

(define-operation audited-export-in-a-read
    ((customer-id :type (id tun.customers:customer) :required t))
    (:kind :read :policy :admin :title "An audited read inside a read")
  (invoke 'audited-customer-export "customer_id" customer-id "reason" "inside"))

(define-operation audited-export-in-a-mutation
    ((customer-id :type (id tun.customers:customer) :required t)
     (roll-back :type boolean))
    (:kind :update :policy :admin :title "An audited read inside a mutation")
  (let ((json (invoke 'audited-customer-export "customer_id" customer-id "reason" "inside")))
    (when roll-back
      (fail :conflict "rolled back"))
    json))

(define-operation reason-in-a-plain-read ()
    (:kind :read :policy :viewer :title "A reason where no entry is")
  (audit-reason "lost")
  (jobj "ok" t))

(defun distinctive-customer ()
  "A customer whose every field is a text found nowhere else; its id."
  (jget (call-ok "customers_create" "employee:anna" "name" "Zygmunt Quillfeather"
                 "email" "zq.unique-77@example.no" "phone" "+47 123 45 678"
                 "notes" "Prefers ultramarine envelopes")
        "id"))

(defun audit-entries (tool)
  "The audit entries of TOOL, newest first, as audit_list gives them."
  (remove tool (coerce (jget (call-ok "audit_list" "admin:root" "limit" 100) "items") 'list)
          :key (lambda (entry) (jget entry "tool")) :test-not #'equal))

(defun stored-audit-texts ()
  "Every stored audit entry, as its JSON text."
  (with-application (*app*)
    (with-actor ((system-actor "test"))
      (with-transaction (:read)
        (mapcar (lambda (entry) (to-json-string (entity->json entry)))
                (select 'audit-entry))))))

(test an-audited-read-leaves-an-entry-and-a-plain-one-none
  (with-test-app ()
    (let ((id (distinctive-customer)))
      (let ((*credential* "tok_audited"))
        (call-ok "audited_customer_export" "admin:ada" "customer_id" id
                 "reason" "The customer asked"))
      (let ((entries (audit-entries "audited_customer_export")))
        (is (= 1 (length entries)))
        (let ((entry (first entries)))
          (is (equal "admin:ada" (jget entry "actor")))
          (is (equal "ok" (jget entry "outcome")))
          (is (equal "customer" (jget entry "entity_type")))
          (is (equal id (jget entry "entity_id")) "the record its customer_id names")
          (is (equal "The customer asked" (jget entry "reason")))
          (is (equal "tok_audited" (jget entry "credential")) "the credential the call used")))
      (is (some (lambda (text) (and (search "audited_customer_export" text)
                                    (search "\"request_id\":\"req_" text)))
                (stored-audit-texts))
          "the request's id")
      (let ((before (length (stored-audit-texts))))
        (call-ok "plain_customer_export" "admin:ada" "customer_id" id)
        (call-ok "customers_get" "viewer:v" "id" id)
        (is (= before (length (stored-audit-texts))) "a read that does not ask leaves none"))
      (call-ok "audited_customer_get" "viewer:v" "id" id)
      (let ((entry (first (audit-entries "audited_customer_get"))))
        (is (equal id (jget entry "entity_id")) "the record it returned")
        (is (eq :null (jget entry "reason"))))
      (call-ok "audited_named_read" "viewer:v" "customer" id)
      (let ((entry (first (audit-entries "audited_named_read"))))
        (is (equal "customer" (jget entry "entity_type")) "the record the body named")
        (is (equal id (jget entry "entity_id")))))))

(test an-audited-reads-entry-holds-nothing-it-read
  (with-test-app ()
    (let ((id (distinctive-customer)))
      (call-ok "audited_customer_export" "admin:ada" "customer_id" id "reason" "Export")
      (dolist (text (append (mapcar #'to-json-string (audit-entries "audited_customer_export"))
                            (stored-audit-texts)))
        (dolist (secret '("Zygmunt" "Quillfeather" "zq.unique-77" "123 45 678" "ultramarine"))
          (is (null (search secret text)) "~a is not in the audit log: ~a" secret text))))))

(test an-audited-read-returns-its-data-only-after-its-entry
  (with-test-app ()
    (let ((id (distinctive-customer)))
      ;; A thread eval starts cannot write: the entry cannot be written there.
      (let ((json (let ((tun.core::*under-eval* t))
                    (handler-case (call "audited_customer_export" "admin:ada"
                                        "customer_id" id "reason" "Under eval")
                      (error () :failed)))))
        (is (eq :failed json) "the call fails: ~a" json))
      (is (null (audit-entries "audited_customer_export")))
      (multiple-value-bind (json code)
          (call "audited_customer_export" "admin:ada"
                "customer_id" "cus_00000000000000000000000000" "reason" "x")
        (is (equal "not_found" code) "a customer that is not there: ~a" (to-json-string json)))
      (is (null (remove "ok" (audit-entries "audited_customer_export")
                        :key (lambda (entry) (jget entry "outcome")) :test-not #'equal))
          "a read that fails writes no ok entry")
      (is (equal "forbidden" (nth-value 1 (call "audited_customer_export" "viewer:v"
                                                "customer_id" id "reason" "x"))))
      (let ((refused (first (audit-entries "audited_customer_export"))))
        (is (equal "rejected" (jget refused "outcome")))
        (is (equal "viewer:v" (jget refused "actor")))))))

(test an-audited-read-in-a-mutation-or-in-a-read
  (with-test-app ()
    (let ((id (distinctive-customer)))
      (call-ok "audited_export_in_a_mutation" "admin:ada" "customer_id" id)
      (is (= 1 (length (audit-entries "audited_customer_export")))
          "in a mutation: in its transaction")
      (is (equal "conflict" (nth-value 1 (call "audited_export_in_a_mutation" "admin:ada"
                                               "customer_id" id "roll_back" t))))
      (is (= 1 (length (audit-entries "audited_customer_export")))
          "gone with the mutation that rolled back")
      (let ((answer (handler-case (call "audited_export_in_a_read" "admin:ada" "customer_id" id)
                      (error (e) (princ-to-string e)))))
        (is (stringp answer) "inside a read it fails: ~a" answer)
        (is (search "audited read" answer))
        (is (null (search "Zygmunt" answer)) "with none of its data"))
      (is (= 1 (length (audit-entries "audited_customer_export"))) "and no entry"))))

(test audit-is-declared-on-reads-only-and-shown
  (dolist (kind '(:create :update :transition :wait :workflow))
    (signals error (macroexpand-1 `(define-operation never-defined () (:kind ,kind :audit t)
                                     nil))))
  (with-test-app ()
    (let ((operations (coerce (jget (call-ok "registry_describe" "viewer:v") "operations") 'list)))
      (flet ((audit-of (tool)
               (jget (find tool operations :key (lambda (op) (jget op "name")) :test #'equal)
                     "audit")))
        (is (eq t (audit-of "audited_customer_export")))
        (is (eq t (audit-of "customers_update")) "a mutation is always audited")
        (is (member (audit-of "plain_customer_export") '(nil :false)))
        (is (member (audit-of "customers_get") '(nil :false)))))))

(test audit-reason-is-refused-where-no-entry-is-and-cut-to-500
  (signals error (audit-reason "nowhere"))
  (with-test-app ()
    (let ((answer (handler-case (call "reason_in_a_plain_read" "viewer:v")
                    (error (e) (princ-to-string e)))))
      (is (and (stringp answer) (search "AUDIT-REASON" answer)) "refused: ~a" answer))
    (let ((id (distinctive-customer)))
      (call-ok "audited_customer_export" "admin:ada" "customer_id" id
               "reason" (make-string 700 :initial-element #\r))
      (is (= 500 (length (jget (first (audit-entries "audited_customer_export")) "reason")))))))
