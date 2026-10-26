;;;; core/system-entities.lisp -- entities the execution path itself stores.
;;;; They are internal: stored like any entity, not listed by registry_describe.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(define-entity audit-entry (:json-name "audit" :label "Revisjonslogg" :id-prefix "aud" :internal t
                            :indexes (("entity_type" "entity_id")))
  ((at :type timestamp :input nil :label "Tidspunkt")
   (actor :type (string :max 200) :input nil :label "Aktør")
   (tool :type (string :max 200) :input nil :label "Verktøy")
   (outcome :type (enum "ok" "rejected") :input nil :label "Utfall")
   (entity-type :type (string :max 100) :input nil :label "Entitetstype")
   (entity-id :type (string :max 100) :input nil :label "Entitets-ID")
   (request-key :type (string :max 64) :input nil :label "Forespørselsnøkkel")
   (error-code :type (string :max 64) :input nil :label "Feilkode")
   (request-id :type (string :max 64) :input nil :label "Forespørsel"
               :description "X-Tun-Request-Id of the call (introspect_request).")
   (reason :type (string :max 500) :input nil :label "Begrunnelse"
           :description "The reason an override or forced transition was given.")
   (credential :type (string :max 64) :input nil :label "Legitimasjon"
               :description "The token or session the call was made with, or claimed (spec/auth.md 7).")))

(define-entity receipt (:json-name "receipt" :label "Kvittering" :id-prefix "rcp" :internal t
                        :unique (("actor" "tool" "request_key")))
  ((actor :type (string :max 200) :input nil)
   (tool :type (string :max 200) :input nil)
   (request-key :type (string :max 64) :input nil)
   (input-hash :type (string :max 64) :input nil)
   (redacted :type boolean :input nil :initform nil)
   (result :type (string :max 10000000) :input nil :label "Opprinnelig resultat (JSON)")
   (created-at :type timestamp :input nil)))

(define-entity confirmation (:json-name "confirmation" :label "Bekreftelse" :id-prefix "cnf" :internal t
                             :unique (("token_hash")))
  ((token-hash :type (string :max 64) :input nil :label "SHA-256 av token")
   (actor :type (string :max 200) :input nil)
   (tool :type (string :max 200) :input nil)
   (input-hash :type (string :max 64) :input nil)
   (expires-at :type timestamp :input nil)
   (request-id :type (string :max 64) :input nil
               :description "The top-level request that issued the token; it cannot confirm itself.")
   (used-at :type timestamp :input nil)
   (created-at :type timestamp :input nil)))

(define-entity setting (:json-name "setting" :label "Innstilling" :id-prefix "set"
                        :unique (("key")))
  ((key :type (string :max 200) :input nil)
   (value :type json :input nil)))

(defun read-setting (key)
  (let ((row (select-one 'setting :where `(:= "key" ,key))))
    (and row (setting-value row))))

(defun write-setting (key value)
  (let ((row (select-one 'setting :where `(:= "key" ,key))))
    (if row
        (progn (setf (setting-value row) value) (save row))
        (insert (make-instance 'setting :key key :value value)))))
