;;;; core/system-entities.lisp -- entities the execution path itself stores.
;;;; They are internal: stored like any entity, not listed by registry_describe.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(define-entity audit-entry (:json-name "audit" :label "Audit log" :id-prefix "aud" :internal t
                            :indexes (("entity_type" "entity_id")))
  ((at :type timestamp :input nil :label "Time")
   (actor :type (string :max 200) :input nil :label "Actor")
   (tool :type (string :max 200) :input nil :label "Tool")
   (outcome :type (enum "ok" "rejected") :input nil :label "Outcome")
   (entity-type :type (string :max 100) :input nil :label "Entity type")
   (entity-id :type (string :max 100) :input nil :label "Entity ID")
   (request-key :type (string :max 64) :input nil :label "Request key")
   (error-code :type (string :max 64) :input nil :label "Error code")
   (request-id :type (string :max 64) :input nil :label "Request"
               :description "X-Tun-Request-Id of the call (introspect_request).")
   (reason :type (string :max 500) :input nil :label "Reason"
           :description "The reason an override or forced transition was given.")
   (credential :type (string :max 64) :input nil :label "Credential"
               :description "The token or session the call was made with, or claimed (spec/auth.md 7).")))

(define-entity receipt (:json-name "receipt" :label "Receipt" :id-prefix "rcp" :internal t
                        :unique (("actor" "tool" "request_key")))
  ((actor :type (string :max 200) :input nil)
   (tool :type (string :max 200) :input nil)
   (request-key :type (string :max 64) :input nil)
   (input-hash :type (string :max 64) :input nil)
   (redacted :type boolean :input nil :initform nil)
   (result :type (string :max 10000000) :input nil :label "Original result (JSON)")
   (created-at :type timestamp :input nil)))

(define-entity confirmation (:json-name "confirmation" :label "Confirmation" :id-prefix "cnf" :internal t
                             :unique (("token_hash")))
  ((token-hash :type (string :max 64) :input nil :label "SHA-256 of the token")
   (actor :type (string :max 200) :input nil)
   (tool :type (string :max 200) :input nil)
   (input-hash :type (string :max 64) :input nil)
   (expires-at :type timestamp :input nil)
   (request-id :type (string :max 64) :input nil
               :description "The top-level request that issued the token; it cannot confirm itself.")
   (used-at :type timestamp :input nil)
   (created-at :type timestamp :input nil)))

(define-entity setting (:json-name "setting" :label "Setting" :id-prefix "set"
                        :unique (("key")))
  ((key :type (string :max 200) :input nil :label "Key")
   (value :type json :input nil :label "Value")))

(defun read-setting (key)
  (let ((row (select-one 'setting :where `(:= "key" ,key))))
    (and row (setting-value row))))

(defun write-setting (key value)
  (let ((row (select-one 'setting :where `(:= "key" ,key))))
    (if row
        (progn (setf (setting-value row) value) (save row))
        (insert (make-instance 'setting :key key :value value)))))
