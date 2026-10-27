;;;; core/package.lisp -- the TUN.CORE package: the registry, the execution
;;;; path and the store port.  Symbols exported here are available to other
;;;; tun packages; the client-facing public interface is the curated TUN
;;;; package (see public.lisp), not this list.

(defpackage #:tun.core
  (:use #:cl)
  (:export
   ;; util
   #:json-name-of #:trim #:blank-p #:symbolicate #:string-prefix-p #:join-strings #:contains-ci-p
   #:random-bytes #:random-token-string #:new-id #:new-secret-token #:sha256-hex
   #:universal-time #:parse-rfc3339 #:format-rfc3339 #:parse-date #:valid-date-string-p #:format-date
   #:date-add-days #:date-add-months #:date-at #:date-of #:date<= #:date<
   #:last-sunday #:summer-time-p #:oslo-offset #:local-date-of #:local-time-of #:local-today
   ;; json
   #:jobj #:jarr #:json-bool #:jget #:jkeys #:json-null-p #:json-object-p #:json-array-p
   #:parse-json #:json-parse-failure #:*max-json-string-length*
   #:parse-request-json #:json-too-many-values #:+max-request-json-values+ #:write-json
   #:to-json-string #:canonical-json-hash #:json-copy
   #:json-number-out-of-range #:json-number-message #:+number-out-of-range+
   #:+number-too-many-digits+
   ;; conditions
   #:error-code #:operation-error #:operation-error-code #:operation-error-message
   #:operation-error-fields #:operation-error-details #:fail #:fail-with-details #:fail-fields
   #:operation-error-json #:error-status #:actor-error #:actor-error-message #:extension-error
   ;; rank keys
   #:rank-between #:rank-key #:rank-key-p #:rank-order-error #:rank-order-error-low
   #:rank-order-error-high
   ;; types (and the designator symbols used in field specs)
   #:field-type #:type-name #:type-json-schema #:coerce-input #:type->json #:type->db #:db->type
   #:type-sql #:type-lisp-type #:parse-field-type #:string-type #:email-type #:integer-type
   #:boolean-type #:enum-type #:enum-values #:date-type #:timestamp-type #:id-type #:id-references
   #:json-type #:list-type #:list-element #:list-element-entity-p #:input-error
   #:collecting-input-errors #:*input-errors*
   #:files-type #:files-max #:files-type-p #:files #:recorded-value #:shown-name
   #:long-number-text-p #:+most-number-text+
   #:email #:enum #:date #:timestamp #:id #:list-of #:json
   ;; entities
   #:entity-class #:entity #:stored-entity #:entity-id #:define-entity #:extend-entity
   #:define-rule #:define-computed-field
   #:entity-fields #:entity-input-fields #:entity-stored-fields #:find-field #:field-name
   #:field-json-name #:field-type #:field-label #:field-description #:field-required-p
   #:field-input-p #:field-stored-p #:field-source #:field-value #:field-secret-p #:field-json-value
   #:entity-registry-conflicts #:check-entity-registry #:table-owner
   #:entity-json-name #:entity-label #:entity-table #:entity-id-prefix #:entity-embedded-p
   #:entity-internal-p #:entity-attachments #:entity-source #:entity-rules
   #:entity-computed-fields #:entity-extensions
   #:entity-indexes #:entity-unique #:entity-rollback-check #:entity-record-rollback-checks #:add-rollback-check #:entity-revisioned-p #:entity-location #:field-location
   #:rule-name #:rule-field #:rule-message #:rule-source #:rule-location #:rule-function
   #:computed-field-location #:computed-field-function
   #:computed-field-name #:computed-field-json-name #:computed-field-label #:computed-field-source
   #:computed-field-type
   #:find-entity-class #:all-entity-classes #:find-entity-by-json-name #:make-entity
   #:entity->json #:entity-readable-p #:entity->storage-json #:storage-json->entity #:copy-entity #:input->entity
   #:entity-input-schema #:validate-entity #:current-definition-source #:core-package-p
   ;; request records and step traces (core.md §8.1)
   #:with-step #:note-step #:call-with-step #:note-store-statement #:note-write-lock-wait
   #:with-request-state #:trace-clock-us #:us->ms #:*request-record* #:request-record
   #:with-request-record #:call-with-request-record #:set-request-outcome #:set-request-policy
   #:choose-request-backtrace #:with-backtrace-capture #:outcome-for-code #:rejection-signal #:find-request
   #:redact-request-traces #:in-flight-requests #:finished-requests #:request->json #:request-summary->json
   #:request-id #:request-tool #:request-actor #:request-credential #:request-outcome #:request-total-us #:request-at
   #:request-state #:request-started-us #:request-error-code #:request-elapsed-us #:request-kind
   #:request-steps #:request-claimed #:request-input #:request-input-json
   #:request-policy-required #:trace-step-kind #:trace-step-name #:trace-step-source
   #:trace-step-order
   #:trace-step-detail #:*request-history-size* #:capture-backtrace
   #:request-finished #:request-application #:request-error-type #:request-error-message
   #:request-backtrace #:request-store-statements #:*stored-diagnostics-redactors*
   #:current-source-location #:definition-source-location #:display-source-path
   #:call-collecting-steps #:*extension-protocols* #:register-extension-protocol
   ;; deadlines
   #:*deadline-ms* #:*watchdog-grace-ms* #:deadline-exceeded #:*deadline* #:check-deadline
   #:deadline-remaining-ms #:sleep-with-deadline #:without-deadline-interrupts #:*interruptible* #:with-deadline
   #:call-with-deadline #:start-deadline-watchdog
   ;; store port
   #:store #:*store* #:*transaction-mode* #:*under-eval* #:*now-function*
   #:store-open #:store-close #:store-migrate #:store-call-in-transaction #:store-insert
   #:store-update #:store-delete #:store-find #:store-select #:store-lock-row #:store-description
   #:store-claim-presence #:store-present-p #:store-presences
   #:with-transaction #:call-in-transaction #:assert-writable #:insert #:save #:delete-entity #:fetch #:fetch!
   #:select #:select-one #:lock-row #:where-field #:where-value->db #:read-only-violation
   #:store-describe-schema #:store-write-queue-depth #:store-runs-queries-p #:store-query
   #:store-write-content #:store-read-content #:store-delete-content
   ;; queries (spec/store.md 5)
   #:define-query #:query-name #:query-parameters #:query-returns #:query-description
   #:query-source #:query-module #:query-location #:find-query #:all-queries #:run-query
   #:check-queries
   ;; record policies (spec/store.md 6)
   #:entity-record-policy #:record-condition #:record-source-sql #:refuse-record-write
   #:record-not-found #:check-record-policies
   ;; actors
   #:actor #:actor-p #:actor-role #:actor-name #:role #:policy #:*actor* #:parse-actor #:make-actor
   #:system-actor #:actor-string #:actor-permits-p #:with-actor #:role-rank #:*credential*
   ;; application, clock
   #:clock #:clock-now #:system-clock #:test-clock #:test-clock-now #:set-test-clock
   #:+test-clock-start+ #:application #:application-name #:application-store #:application-clock
   #:application-accounting #:application-message-transport #:application-mail #:application-debug-tools-p
   #:application-allow-eval-p #:application-repl-port #:application-identity #:claimed-identity-p
   #:application-auth-state #:application-jobs-state #:application-queue-limit #:declare-queue-default #:application-push-service #:application-log-requests-p
   #:application-public-url #:absolute-url
   #:application-started-us #:application-max-inflight #:application-inflight-cell
   #:operation-eval-only-p
   #:*application* #:test-mode-p
   #:now #:now-ms #:now-string #:today #:with-application #:call-with-application #:application-title
   #:secret-setting-p #:setting-key #:define-setting #:setting-value-at-use #:settings-description #:initialise-settings
   #:setting-actor-exists-p
   ;; system entities
   #:audit-entry #:audit-entry-at #:audit-entry-actor #:audit-entry-tool #:audit-entry-outcome
   #:audit-entry-entity-type #:audit-entry-entity-id #:audit-entry-request-key #:audit-entry-error-code
   #:audit-entry-reason #:audit-entry-credential #:audit-as #:audit-target #:*audit-actor*
   #:*audit-reason* #:reject #:reject-as #:input-null-p
   #:decimal #:decimal-type #:json-number->rational #:round-decimal #:quantity-json #:format-quantity #:format-kroner
   #:receipt #:confirmation #:setting #:read-setting #:write-setting
   ;; operations
   #:operation #:define-operation #:operation-name #:operation-tool #:operation-entity
   #:operation-kind #:operation-title #:operation-description #:operation-policy
   #:operation-confirm-p #:operation-destructive-p #:operation-test-only-p #:operation-debug-only-p
   #:operation-visible-p #:operation-parameters
   #:operation-draft-p #:operation-source #:operation-mutating-p #:operation-idempotent-p
   #:operation-audited-p #:all-operations #:find-operation #:find-operation-by-tool
   #:visible-operations #:operation-input #:make-input #:input-arguments #:input-value
   #:input-provided-p #:input-draft #:input-request-key #:operation-result #:current-operation-tool
   #:*input* #:*operation* #:operation-input-schema
   #:parameter-json-name #:parameter-type #:parameter-entity-field #:parameter-required-p
   #:parameter-label
   #:parameter-text #:parameter-name #:parameter-keyword #:parameter-default #:parse-parameter-spec
   #:check-operation-methods
   #:operation-location #:method-owner-name #:method-source #:traced-protocol
   #:parse-operation-input #:confirmation-summary #:recorded-input #:explain-would
   ;; execution
   #:run-operation #:call-tool #:invoke #:unknown-tool #:unknown-tool-name #:result->json
   #:complete-after-commit #:deferred-result #:show-once
   #:*request-id* #:*inside-operation* #:with-audit-scope #:write-system-audit #:on-rollback #:on-commit
   ;; waiting for a change (spec/waiting.md)
   #:application-instructions
   #:await #:call-awaiting #:*await-limit* #:*await-heartbeat* #:*waiting-leaves*
   #:*wait-client* #:+await-max-seconds+ #:+await-heartbeat-seconds+ #:*max-waiting*
   #:*max-waiting-per-client* #:waiting-count #:client-waiting-count
   ;; counts by key (core.md 7.5)
   #:key-counts #:make-key-counts #:take-count #:give-back-count #:key-count
   #:write-audit #:defer-audit #:audit-entry-request-id
   ;; registry
   #:define-workflow #:workflow-kind #:workflow-kind-name #:workflow-kind-label #:workflow-kind-function
   #:workflow-kind-source #:workflow-kind-location #:workflow-kind-debug-p #:workflow-kind-own-transactions-p #:workflow-kind-templates #:find-workflow-kind #:*workflow-kinds*
   #:define-message-template #:message-template #:message-template-name #:message-template-label
   #:message-template-source #:message-template-location #:message-template-function #:find-message-template #:render-message-template #:*message-templates*
   #:message-template-version #:message-template-subject #:message-template-text #:message-template-html
   #:message-template-variables #:message-template-manual-p #:message-template-marketing-p #:message-template-description
   #:link-token #:constant-time-string= #:application-after-request
   #:page #:describe-registry #:describe-entity #:describe-operation #:tool-definition #:tool-definitions
   #:workflow-kind-module #:message-template-module #:message-template-final-p
   #:notify #:register-message-sender #:*message-sender* #:describe-module #:describe-screens #:register-screen #:*screens*
   ;; modules (tun-platform.md 2)
   #:+core-version+ #:parse-version #:version-compare #:version-satisfies-p
   #:module #:module-name #:module-depends-on #:module-core-range #:module-packages #:module-mixin
   #:module-description #:module-location #:module-on-open #:module-sealed-p
   #:all-modules #:find-module #:package-module #:current-definition-module #:class-owner-module
   #:module-dependency-closure #:define-module #:register-module #:publish
   #:seal-packages #:seal-module #:check-definition-integrity #:definition-integrity-violations
   #:snapshot-live-definitions #:live-definition-patches #:live-definition-sources
   #:*sealed-packages* #:define-application #:application-declared-modules #:application-on-open-functions
   #:application-sign-in-specs #:application-mail-spec #:application-error-mail-specs #:application-web-app #:configured-value #:enabled-modules
   #:check-enabled-modules #:module-revision #:*module-revisions*
   #:entity-module #:field-module #:rule-module #:computed-field-module #:operation-module #:method-module
   #:extension-protocol #:extension-protocol-name #:extension-protocol-kind #:extension-protocol-point
   #:extension-protocol-module #:extension-protocol-description
   #:define-setting-initial-value #:normalize-message-text #:message-grapheme-count #:utf8-byte-count
   #:provider-call-capacity-p #:stop-application-workers #:application-stopping-p
   #:unicode-text-scanner #:unicode-word-character-p #:unicode-digit-p #:unicode-whitespace-p #:unicode-punctuation-p
   #:worker-running-p #:call-with-worker-lock #:start-worker #:wait-for-workers #:call-with-time-limit #:redact-entity-receipts #:sign-response-proof #:verify-response-proof
   #:call-customer-action #:new-ordered-id))
