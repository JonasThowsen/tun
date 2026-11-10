;;;; tests/customers-tests.lisp -- customers_update (modules/customers
;;;; README §2.1): what it changes, what it refuses, and its audit.

(in-package #:tun.tests)
(def-suite customers :in core)
(in-suite customers)

(defun update-customer (actor id revision &rest fields)
  "Call customers_update as ACTOR on the customer ID at REVISION, changing
FIELDS, a plist of JSON names and values: values JSON and the error code."
  (call "customers_update" actor "id" id "revision" revision "fields" (apply #'jobj fields)))

(defun refused-paths (json)
  "The field paths of the refusal JSON."
  (map 'list (lambda (fe) (jget fe "field")) (jget (jget json "error") "fields" #())))

(test customers-update-changes-the-named-fields-and-raises-the-revision
  (with-test-app ()
    (let* ((id (jget (call-ok "customers_create" "employee:anna" "name" "Kari Nordmann"
                              "email" "kari@example.no" "phone" "+47 900 00 000"
                              "notes" "Ringer helst om morgenen")
                     "id"))
           (changed (update-customer "employee:anna" id 1 "name" "  Kari Hansen "
                                     "email" "kari.hansen@example.no")))
      (is (equal "Kari Hansen" (jget changed "name")) "the name is trimmed, as on create")
      (is (equal "kari.hansen@example.no" (jget changed "email")))
      (is (equal "+47 900 00 000" (jget changed "phone")) "what fields leaves out is kept")
      (is (equal "Ringer helst om morgenen" (jget changed "notes")))
      (is (= 2 (jget changed "revision")))
      (let ((again (update-customer "employee:anna" id 2
                                    "phone" " 22 00 00 00 " "notes" "Ny note")))
        (is (equal " 22 00 00 00 " (jget again "phone")) "the phone is stored as given")
        (is (equal "Ny note" (jget again "notes")))
        (is (= 3 (jget again "revision"))))
      (is (equal "Kari Hansen" (jget (call-ok "customers_get" "viewer:v" "id" id) "name"))))))

(test customers-update-clears-an-optional-field-with-null
  (with-test-app ()
    (let* ((id (jget (call-ok "customers_create" "employee:anna" "name" "Per"
                              "email" "per@example.no" "phone" "123" "notes" "Note")
                     "id"))
           (changed (update-customer "employee:anna" id 1 "phone" :null "notes" :null)))
      (is (eq :null (jget changed "phone")))
      (is (eq :null (jget changed "notes")))
      (is (equal "Per" (jget changed "name"))))))

(test customers-update-refuses-a-stale-revision-and-changes-nothing
  (with-test-app ()
    (let ((id (make-customer "Ola Nordmann")))
      (update-customer "employee:anna" id 1 "notes" "First")
      (is (equal "conflict" (nth-value 1 (update-customer "employee:anna" id 1 "notes" "Second"))))
      (is (equal "conflict" (nth-value 1 (update-customer "employee:anna" id 3 "notes" "Third"))))
      (is (equal "Kunden er endret (revisjon 2, ikke 1)"
                 (refusal-in-norwegian "customers_update" "employee:anna" "id" id "revision" 1
                                       "fields" (jobj "notes" "Second"))))
      (let ((stored (call-ok "customers_get" "viewer:v" "id" id)))
        (is (equal "First" (jget stored "notes")))
        (is (= 2 (jget stored "revision")))))))

(test customers-update-checks-each-field-as-create-does
  (with-test-app ()
    (let ((id (make-customer "Ola Nordmann")))
      (flet ((refused-at (&rest fields)
               (multiple-value-bind (json code)
                   (apply #'update-customer "employee:anna" id 1 fields)
                 (is (equal "invalid_input" code) "~s" fields)
                 (refused-paths json))))
        (is (equal '("fields.name") (refused-at "name" :null)))
        (is (equal '("fields.name") (refused-at "name" "   ")))
        (is (equal '("fields.name") (refused-at "name" (make-string 121 :initial-element #\a))))
        (is (equal '("fields.email") (refused-at "email" :null)))
        (is (equal '("fields.email") (refused-at "email" "not an email")))
        (is (equal '("fields.phone") (refused-at "phone" (make-string 41 :initial-element #\1))))
        (is (equal '("fields.notes") (refused-at "notes" 12)))
        (is (equal '("fields.name" "fields.email") (refused-at "name" "" "email" "x")))
        (is (= 1 (jget (call-ok "customers_get" "viewer:v" "id" id) "revision")))))))

(test customers-update-changes-only-the-customers-own-input-fields
  (with-test-app ()
    (let ((id (make-customer "Ola Nordmann")))
      (flet ((refused-at (&rest fields)
               (multiple-value-bind (json code)
                   (apply #'update-customer "employee:anna" id 1 fields)
                 (is (equal "invalid_input" code) "~s" fields)
                 (refused-paths json))))
        (is (equal '("fields.marketing_consent") (refused-at "marketing_consent" t)))
        (dolist (kept '("revision" "completed_orders" "consent_source" "consent_at" "erased"
                        "erased_at" "created_at" "id" "loyalty"))
          (is (equal (list (format nil "fields.~a" kept)) (refused-at kept 5))))
        (is (equal '("fields") (refused-at)) "an empty fields changes nothing"))
      (is (equal "invalid_input" (nth-value 1 (call "customers_update" "employee:anna" "id" id
                                                    "revision" 1 "fields" "name"))))
      (is (equal "invalid_input" (nth-value 1 (call "customers_update" "employee:anna" "id" id
                                                    "revision" 1))))
      (is (equal "not_found" (nth-value 1 (update-customer "employee:anna" "cus_nothing" 1
                                                           "name" "X"))))
      (let ((stored (call-ok "customers_get" "viewer:v" "id" id)))
        (is (= 1 (jget stored "revision")))
        (is (null (jget stored "marketing_consent")))))))

(test customers-update-refuses-an-erased-customer
  (with-test-app ()
    (let* ((id (make-customer "Erase Me"))
           (erased (two-step "customers_erase" "admin:ada" "id" id))
           (revision (jget erased "revision")))
      (is (equal "invalid_input" (nth-value 1 (update-customer "admin:ada" id revision
                                                               "name" "Back Again"))))
      (is (equal "invalid_input" (nth-value 1 (update-customer "admin:ada" id 1 "name" "Back")))
          "whatever the revision")
      (is (equal "kunden er slettet"
                 (refusal-in-norwegian "customers_update" "admin:ada" "id" id "revision" revision
                                       "fields" (jobj "notes" "x"))))
      (let ((stored (call-ok "customers_get" "viewer:v" "id" id)))
        (is (equal (jget erased "name") (jget stored "name")))
        (is (= revision (jget stored "revision")))))))

(test customers-update-is-an-employees-and-audited-with-the-changed-names
  (with-test-app ()
    (let ((id (make-customer "Ola Nordmann")))
      (is (equal "forbidden" (nth-value 1 (update-customer "viewer:v" id 1 "name" "Viewer"))))
      (let ((first (call-ok "customers_update" "employee:anna" "id" id "revision" 1
                            "fields" (jobj "name" "Ola Hansen" "notes" "Secret note")
                            "request_key" "update-1")))
        (let ((replayed (call-ok "customers_update" "employee:anna" "id" id "revision" 1
                                 "fields" (jobj "name" "Ola Hansen" "notes" "Secret note")
                                 "request_key" "update-1")))
          (is (= 2 (jget replayed "revision")) "the same request_key gives the same result")
          (is (equal (jget first "name") (jget replayed "name"))))
        (is (= 2 (jget (call-ok "customers_get" "viewer:v" "id" id) "revision"))))
      (let* ((items (jget (call-ok "audit_list" "viewer:v" "entity_type" "customer" "entity_id" id)
                          "items"))
             (update (find "customers_update" items :key (lambda (e) (jget e "tool"))
                                                    :test #'equal)))
        (is (equal "ok" (jget update "outcome")))
        (is (equal "employee:anna" (jget update "actor")))
        (is (equal "name, notes" (jget update "reason")) "the names, never the values")
        (is (find "rejected" items :key (lambda (e) (jget e "outcome")) :test #'equal)
            "the viewer's refusal is audited")))))

(test customers-update-lists-the-changeable-fields-in-its-schema
  (with-test-app ()
    (let* ((op (find-operation-by-tool "customers_update"))
           (schema (operation-input-schema op))
           (fields (jget (jget schema "properties") "fields")))
      (is (equal '("id" "revision" "fields") (coerce (jget schema "required") 'list)))
      (is (equal "object" (jget fields "type")))
      (is (equal '("name" "email" "phone" "notes") (jkeys (jget fields "properties"))))
      (is (eq nil (jget fields "additionalProperties"))))))
