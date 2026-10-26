;;;; tests/registry-tests.lisp -- phase 1: one definition yields the domain
;;;; function, the input schema, the MCP tool and the registry entry.

(in-package #:tun.tests)

(def-suite registry :in core)
(in-suite registry)

(test define-operation-yields-a-guarded-generic-function
  (let ((gf (fdefinition 'tun.customers:customers-create)))
    (is (typep gf 'generic-function))
    (is (eq 'tun.core::operation
            (sb-pcl::method-combination-type-name (sb-mop:generic-function-method-combination gf))))
    (is (= 1 (length (sb-mop:generic-function-methods gf))))
    (let ((op (find-operation 'tun.customers:customers-create)))
      (is (string= "customers_create" (operation-tool op)))
      (is (eq :create (operation-kind op)))
      (is (operation-idempotent-p op))
      (is (operation-audited-p op))
      (is (not (operation-confirm-p op)))
      (is (eq :employee (operation-policy op))))))

(test input-schema-comes-from-the-entity
  (let* ((schema (operation-input-schema (find-operation 'tun.customers:customers-create)))
         (props (jget schema "properties")))
    (is (string= "object" (jget schema "type")))
    (is (equal '("name" "email") (coerce (jget schema "required") 'list)))
    (is (= 120 (jget (jget props "name") "maxLength")))
    (is (string= "email" (jget (jget props "email") "format")))
    (is (jget props "request_key"))
    (is (null (jget props "id")) "system fields are not input")
    (is (eq nil (jget schema "additionalProperties")))))

(test tool-definition-is-a-projection
  (let ((tool (tool-definition (find-operation 'tun.customers:customers-get))))
    (is (string= "customers_get" (jget tool "name")))
    (is (string= "Hent kunde" (jget tool "title")))
    (is (eq t (jget (jget tool "annotations") "readOnlyHint")))
    (is (eq nil (jget (jget tool "annotations") "destructiveHint")))
    (is (equal '("id") (coerce (jget (jget tool "inputSchema") "required") 'list)))))

(test tool-names-match-the-contract
  (dolist (op (all-operations))
    (is (cl-ppcre:scan "^[a-z][a-z0-9_]*$" (operation-tool op)) "bad tool name ~a" (operation-tool op))))

(test entity-metadata-is-read-through-the-mop
  (let* ((class (find-class 'tun.customers:customer))
         (slots (sb-mop:class-slots class))
         (name (find 'tun.customers::name slots :key #'sb-mop:slot-definition-name)))
    (is (typep class 'entity-class))
    (is (typep name 'tun.core::field-effective-slot-definition))
    (is (string= "Navn" (field-label name)))
    (is (field-required-p name))
    (is (eq :core (field-source name)))))

(test registry-describe-lists-entities-and-operations
  (with-test-app ()
    (let* ((d (call-ok "registry_describe" "viewer:vera"))
           (customer (find-by "name" "customer" (jget d "entities")))
           (create (find-by "name" "customers_create" (jget d "operations")))
           (describe (find-by "name" "registry_describe" (jget d "operations"))))
      (is (not (null customer)))
      (is (equal '("id" "marketing_consent" "consent_source" "consent_at" "erased" "erased_at" "revision" "name" "email" "phone" "notes" "completed_orders" "created_at")
                 (mapcar (lambda (f) (jget f "name")) (coerce (jget customer "fields") 'list))))
      (let ((name (find-by "name" "name" (jget customer "fields"))))
        (is (string= "string" (jget name "type")))
        (is (string= "Navn" (jget name "label")))
        (is (eq t (jget name "required")))
        (is (string= "core" (jget name "source"))))
      (is (string= "customer" (jget create "entity")))
      (is (string= "create" (jget create "kind")))
      (is (eq t (jget create "idempotent")))
      (is (eq nil (jget create "confirm")))
      (is (string= "employee" (jget create "policy")))
      (is (string= "core" (jget create "source")))
      (is (string= "read" (jget describe "kind")))
      (is (string= "viewer" (jget describe "policy")))
      (is (null (find-by "name" "audit" (jget d "entities"))) "internal entities are hidden"))))

(test domain-function-called-directly-from-lisp
  (with-test-app ()
    (with-application (*app*)
      (with-actor ((make-actor :employee "anna"))
        (let ((json (tun.customers:customers-create
                     *app* (make-input (jobj "name" "  Kari Nordmann  " "email" "kari@example.no")))))
          (is (string= "Kari Nordmann" (jget json "name")) "name is trimmed")
          (is (string-prefix-p "cus_" (jget json "id")))
          (is (= 1 (jget json "revision")))
          (is (string= "2026-03-01T09:00:00Z" (jget json "created_at")))
          (let ((again (invoke 'tun.customers:customers-get "id" (jget json "id"))))
            (is (string= "kari@example.no" (jget again "email")))))))))

(test invalid-input-lists-every-field-and-stores-nothing
  (with-test-app ()
    (multiple-value-bind (json code)
        (call "customers_create" "employee:anna" "name" "" "email" "ikke-epost" "favoritt" 1)
      (is (string= "invalid_input" code))
      (let ((fields (mapcar (lambda (f) (jget f "field")) (coerce (jget (jget json "error") "fields") 'list))))
        (is (member "name" fields :test #'string=))
        (is (member "email" fields :test #'string=))
        (is (member "favoritt" fields :test #'string=))))
    (is (= 0 (jget (call-ok "customers_list" "viewer:vera") "returned")))))

(test list-paging-and-search
  (with-test-app ()
    (dotimes (i 3)
      (call-ok "customers_create" "employee:anna" "name" (format nil "Kunde ~d" i)
               "email" (format nil "k~d@example.no" i)))
    (call-ok "customers_create" "employee:anna" "name" "Åse Ødegård" "email" "aase@example.no")
    (let ((page (call-ok "customers_list" "viewer:vera" "limit" 2)))
      (is (= 2 (jget page "returned")))
      (is (eq t (jget page "has_more"))))
    (let ((found (call-ok "customers_list" "viewer:vera" "query" "ødegÅrd")))
      (is (= 1 (jget found "returned")))
      (is (string= "Åse Ødegård" (jget (aref (jget found "items") 0) "name"))))))
