;;;; core/execution.lisp -- RUN-OPERATION: the one guarded path every
;;;; operation call takes, whoever the caller is (MCP, web UI, workflow engine,
;;;; a client's Lisp code, a test).
;;;;
;;;;   1. actor present            (else ACTOR-ERROR, a transport-level error)
;;;;   2. policy                   forbidden + rejected audit entry, before any lookup
;;;;   3. input against schema     invalid_input
;;;;   read:  run the methods in a read transaction (writes are impossible there)
;;;;   mutating:
;;;;   4. confirm op, no token     replay an existing receipt, else issue a token
;;;;   5. write transaction:
;;;;        receipt for (actor, tool, request_key)?  same input -> original result,
;;;;                                                 other input -> idempotency_conflict
;;;;        confirm op: consume token                 else confirmation_invalid
;;;;        :before methods, primary, :after methods
;;;;        audit entry (ok), receipt
;;;;   Rejections (forbidden, confirmation_invalid, idempotency_conflict) are
;;;;   audited in their own transaction after the business transaction rolled back.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *confirmation-ttl-seconds* 600)

(define-condition rejection (rejection-signal)
  ((code :initarg :code :reader rejection-code :type error-code)
   (message :initarg :message :reader rejection-message)
   (audit-actor :initarg :audit-actor :initform nil :reader rejection-audit-actor
                :documentation "Who the rejected call is audited as, when not the caller (a quote's customer)."))
  (:report (lambda (c s) (format s "~a: ~a" (rejection-code c) (rejection-message c)))))

(defun reject (code control &rest args)
  "Refuse the call with CODE (forbidden, confirmation_invalid,
idempotency_conflict): the call is audited as rejected, like a policy denial."
  (declare (type error-code code))
  (error 'rejection :code code :message (apply #'format nil control args)))

(defun reject-as (actor code control &rest args)
  "Like REJECT, audited as ACTOR (a string such as \"customer:qte_x\")."
  (declare (type error-code code))
  (error 'rejection :code code :audit-actor actor :message (apply #'format nil control args)))

(define-condition unknown-tool (error)
  ((tool :initarg :tool :reader unknown-tool-name))
  (:report (lambda (c s) (format s "Ukjent verktøy: ~a" (unknown-tool-name c)))))

;;; ------------------------------------------------------------------
;;; Results

(defgeneric entity-readable-p (record actor)
  (:method-combination traced-protocol)
  (:documentation "Apply entity read policy and row ownership to diagnostic record access.")
  (:method ((record entity) actor)
    (let ((reads (remove-if-not
                  (lambda (op) (and (eq (operation-entity op) (class-name (class-of record)))
                                    (eq (operation-kind op) :read))) (all-operations))))
      (if reads (some (lambda (op) (and actor (actor-permits-p actor (operation-policy op)))) reads)
          (and actor (eq (actor-role actor) :admin))))))
(register-extension-protocol 'entity-readable-p "rule" :point "record_read"
  :description "An entity's row read policy, applied by introspection and diagnostic evaluation.")

(defgeneric result->json (result)
  (:documentation "The JSON object returned to callers for an operation RESULT."))
(defmethod result->json ((result entity)) (entity->json result))
(defmethod result->json ((result hash-table)) result)

;;; ------------------------------------------------------------------
;;; Audit

(defun input-target (op input)
  "Values entity-type and entity-id that INPUT names: \"id\" names the
operation's own entity; another id parameter (order_id, product_id, ...)
names the entity its type references."
  (let ((args (input-arguments input)))
    (flet ((usable (v) (and (stringp v) (<= 1 (length v) 100) v)))
      (let ((id (usable (jget args "id"))))
        (when (and id (operation-entity op))
          (return-from input-target
            (values (entity-json-name (find-entity-class (operation-entity op))) id))))
      (dolist (p (operation-parameters op))
        (let ((type (parameter-type p))
              (value (usable (jget args (parameter-json-name p)))))
          (when (and value (typep type 'id-type) (id-references type)
                     (find-entity-class (id-references type) nil))
            (return-from input-target
              (values (entity-json-name (find-entity-class (id-references type))) value)))))
      (values (and (operation-entity op) (entity-json-name (find-entity-class (operation-entity op))))
              nil))))

(defun audit-subject (op input result)
  "Values entity-type and entity-id for an audit entry: the stored entity a
successful call returned, else the target its input names."
  (if (typep result 'stored-entity)
      (values (entity-json-name (class-of result)) (entity-id result))
      (input-target op input)))

(defun raw-request-key (input)
  (let ((key (jget (input-arguments input) "request_key")))
    (and (stringp key) (<= (length key) 64) (plusp (length key)) key)))

(defvar *audit-actor* nil
  "Set by an operation's body (AUDIT-AS) to audit the call as someone other
than the caller: a customer answering a quote by its access code.")
(defvar *audit-reason* nil
  "Set by an operation's body (AUDIT-AS) to record the reason of an override.")

(defun audit-as (&key actor reason)
  "Inside a mutating operation: audit this call with ACTOR (a string such as
\"customer:qte_x\") instead of the caller, and/or with REASON."
  (when actor (setf *audit-actor* actor))
  (when reason (setf *audit-reason* (subseq reason 0 (min 500 (length reason))))))

(defun write-audit (op input actor outcome &key result error-code)
  (multiple-value-bind (entity-type entity-id) (audit-subject op input result)
    (with-step (:audit :name outcome :source :core :detail (operation-tool op))
     (insert (make-instance 'audit-entry
                           :at (now)
                           :actor (or *audit-actor* (actor-string actor))
                           :reason (and (string= outcome "ok") *audit-reason*)
                           :tool (operation-tool op)
                           :outcome outcome
                           :entity-type entity-type
                           :entity-id entity-id
                           :request-key (raw-request-key input)
                           :error-code (and error-code (json-name-of error-code))
                           :request-id *request-id*
                           :credential *credential*)))))

(defvar *deferred-audits* :none
  "Inside an audit scope: rejection audits waiting for the outermost transaction to end.")

(defun flush-deferred-audits (thunks)
  (when thunks
    (handler-case (with-transaction (:write) (mapc #'funcall (reverse thunks)))
      (error (e) (format *error-output* "~&;; tun: could not write deferred audit entries: ~a~%" e)))))

(defmacro with-audit-scope (&body body)
  "Run BODY so that rejections audited while a transaction is open are
written after the outermost transaction ends, whatever its outcome: a
rejection inside a call that is later rolled back still leaves its entry."
  `(if (listp *deferred-audits*)
       (progn ,@body)
       (let ((*deferred-audits* '()))
         (unwind-protect (progn ,@body)
           (let ((thunks *deferred-audits*))
             (setf *deferred-audits* '())
             (flush-deferred-audits thunks))))))

(defun defer-audit (thunk)
  "Write an audit entry (THUNK, called in a write transaction) after the
outermost transaction ends; inside a read operation it cannot be written in place."
  (if (listp *deferred-audits*)
      (push thunk *deferred-audits*)
      (with-transaction (:write) (funcall thunk))))

(defun record-rejection (op input actor code &key as)
  "Audit a rejected call (as AS, a string, when given). Never masks the rejection itself."
  (let ((thunk (lambda () (let ((*audit-actor* as)) (write-audit op input actor "rejected" :error-code code)))))
    (if (and *transaction-mode* (listp *deferred-audits*))
        (push thunk *deferred-audits*)
        (handler-case (with-transaction (:write) (funcall thunk))
          (error (e)
            (format *error-output* "~&;; tun: could not audit rejection of ~a: ~a~%" (operation-tool op) e))))))

(defun write-system-audit (tool outcome &key entity-type entity-id error-code reason)
  "An audit entry for work the system does itself (workflow runs), as *ACTOR*."
  (with-step (:audit :name outcome :source :core :detail tool)
    (insert (make-instance 'audit-entry :at (now) :actor (actor-string *actor*) :tool tool
                                        :outcome outcome :entity-type entity-type :entity-id entity-id
                                        :error-code error-code :reason reason :request-id *request-id*
                                        :credential *credential*))))

(defun call-customer-action (customer-id tool entity-type entity-id function &key reason)
  "Run an already token-authorized public command as its customer, with trace and audit."
  (with-actor ((make-actor :customer customer-id))
    (when *request-record* (setf (request-actor *request-record*) (actor-string *actor*)))
    (with-step (:policy :name "customer token" :source :core :detail (actor-string *actor*))
      (with-step (:operation :name tool :source :core)
        (with-transaction (:write)
          (let ((result (funcall function)))
            (write-system-audit tool "ok" :entity-type entity-type :entity-id (or entity-id (and (typep result 'entity) (entity-id result))) :reason reason)
            result))))))

;;; ------------------------------------------------------------------
;;; Idempotency receipts

(defun find-receipt (op actor key)
  (select-one 'receipt :where `(:and (:= "actor" ,(actor-string actor))
                                     (:= "tool" ,(operation-tool op))
                                     (:= "request_key" ,key))))

(defun replay-receipt (op actor key hash)
  "The original result for KEY, NIL when there is none; idempotency_conflict when
KEY was used with different input."
  (let ((receipt (find-receipt op actor key)))
    (when receipt
      ;; Replaying anonymised data must not reintroduce the original input into diagnostics.
      (when (and (receipt-redacted receipt) *request-record*)
        (sb-thread:with-mutex ((request-lock *request-record*)) (redact-request-payload *request-record*)))
      (if (string= hash (receipt-input-hash receipt))
          (parse-json (receipt-result receipt))
          (reject :idempotency-conflict
                  "Nøkkelen ~a er allerede brukt med annen input for ~a" key (operation-tool op))))))

(defun redact-entity-receipts (record &optional (replacement (entity->json record)))
  "Replace retained receipt projections atomically; owners may supply a credential-safe replacement."
  (let ((id (entity-id record)) (affected nil))
    (labels ((redact (value)
               (cond ((hash-table-p value)
                      (if (equal id (jget value "id")) (progn (setf affected t) replacement)
                          (progn (maphash (lambda (key nested) (setf (gethash key value) (redact nested))) value) value)))
                     ((and (vectorp value) (not (stringp value))) (map 'vector #'redact value))
                     (t value))))
      (dolist (receipt (select 'receipt))
        (setf affected nil)
        (let* ((old (receipt-result receipt)) (new (to-json-string (redact (parse-json old)))))
          (when (and affected (or (not (equal old new)) (not (receipt-redacted receipt))))
            (setf (receipt-result receipt) new (receipt-redacted receipt) t)
            (save receipt)))))))

(defun store-receipt (op actor key hash json)
  (insert (make-instance 'receipt :actor (actor-string actor) :tool (operation-tool op)
                                  :request-key key :input-hash hash
                                  :result (to-json-string json))))

;;; ------------------------------------------------------------------
;;; Confirmation tokens (stored hashed, one-time, bound to actor/tool/input)

(defun confirmation-summary (op input)
  (let ((fn (operation-summary-function op)))
    (if fn
        (let ((*input* input)) (funcall fn))
        (let ((args (jobj)))
          (maphash (lambda (k v) (unless (member k '("request_key" "confirmation_token") :test #'string=)
                                   (setf (gethash k args) v)))
                   (input-arguments input))
          (format nil "~a: ~a" (operation-title op) (to-json-string args))))))

(defvar *inside-operation* nil
  "True while operation methods, a workflow handler or a screen run: code that
is not a person at a client.  Confirm-gated tools cannot be asked for there.")

(defun confirmation-target-version (op input)
  "The revision of the record a confirm tool's \"id\" names, when its entity
is revisioned: the token is bound to what the person saw."
  (let ((id (jget (input-arguments input) "id"))
        (entity (operation-entity op)))
    (when (and (stringp id) entity (entity-revisioned-p (find-entity-class entity)))
      (let ((record (fetch entity id)))
        (and record (field-value record (find-field (class-of record) "revision")))))))

(defun confirmation-hash (op input)
  "What a token is bound to: the tool, the input minus confirmation_token and
request_key, and the target's revision."
  (canonical-json-hash (jobj "input" (input-hash op input)
                             "version" (or (confirmation-target-version op input) :null))))

(defun issue-confirmation (op input actor hash)
  (declare (ignore hash))
  (let* ((summary nil)
         (hash (with-transaction (:read)
                 (setf summary (confirmation-summary op input))
                 (confirmation-hash op input)))
         (token (new-secret-token))
        (expires (+ (now) *confirmation-ttl-seconds*)))
    (with-transaction (:write)
      (insert (make-instance 'confirmation :token-hash (sha256-hex token)
                                           :actor (actor-string actor) :tool (operation-tool op)
                                           :input-hash hash :expires-at expires
                                           :request-id *request-id*)))
    (jobj "confirmation_required" t
          "confirmation_token" token
          "expires_at" (format-rfc3339 expires)
          "summary" summary)))

(defun consume-confirmation (op actor token hash)
  (let ((row (select-one 'confirmation :where `(:= "token_hash" ,(sha256-hex token)))))
    (cond ((null row)
           (reject :confirmation-invalid "Ukjent bekreftelsestoken"))
          ((confirmation-used-at row)
           (reject :confirmation-invalid "Bekreftelsestokenet er allerede brukt"))
          ((equal (confirmation-request-id row) *request-id*)
           (reject :confirmation-invalid "Bekreftelsen må gis i et eget kall, ikke i kallet som ba om den"))
          ((> (now) (confirmation-expires-at row))
           (reject :confirmation-invalid "Bekreftelsestokenet er utløpt"))
          ((string/= (confirmation-actor row) (actor-string actor))
           (reject :confirmation-invalid "Bekreftelsestokenet tilhører en annen aktør"))
          ((string/= (confirmation-tool row) (operation-tool op))
           (reject :confirmation-invalid "Bekreftelsestokenet gjelder et annet verktøy"))
          ((string/= (confirmation-input-hash row) hash)
           (reject :confirmation-invalid "Input eller det som skal bekreftes er endret siden bekreftelsen ble utstedt"))
          (t (setf (confirmation-used-at row) (now))
             (save row)))))

;;; ------------------------------------------------------------------
;;; RUN-OPERATION

(defun recorded-input (input)
  "INPUT's arguments as given, minus confirmation_token and request_key (core.md §8.2)."
  (let ((args (input-arguments input)) (copy (jobj)))
    (when (hash-table-p args)
      (maphash (lambda (k v)
                 (unless (member k '("confirmation_token" "request_key") :test #'string=)
                   (setf (gethash k copy) v)))
               args))
    (when (and (equal (current-operation-tool) "settings_set")
               (secret-setting-p (jget args "key")))
      (setf (gethash "value" copy) "***"))
    copy))

(defun condition-text (condition)
  (or (ignore-errors (princ-to-string condition)) (string-downcase (symbol-name (type-of condition)))))

(defun run-operation (name application input body)
  "Entry point of every operation's effective method (see the OPERATION method
combination). BODY runs the :before, primary and :after methods.  A call
from outside any request starts a request record (core.md §8.1); a call from
code inside one (a workflow, a client method) is a step of that request."
  (let ((op (find-operation name)))
    (with-application (application)
      (let ((*operation* op)
            (*request-id* (or *request-id* (new-id "req"))))
        (let ((record *request-record*))
          (cond ((null record)
                 (with-request-record (:id *request-id* :at (now) :application application
                                       :actor (and (actor-p *actor*) (actor-string *actor*))
                                       :credential *credential*
                                       :tool (operation-tool op) :input (recorded-input input))
                   (run-top-level op input body *request-record*)))
                ((not (request-claimed record))
                 ;; The transport's record of this /mcp request: this call is its operation.
                 (setf (request-claimed record) t
                       (request-tool record) (operation-tool op)
                       (request-input record) (recorded-input input)
                       (request-kind record) :operation
                       (request-actor record) (and (actor-p *actor*) (actor-string *actor*))
                       (request-credential record) *credential*)
                 (run-top-level op input body record))
                (t
                 (with-step (:operation :name (operation-tool op) :source (operation-source op)
                             :detail "kalt fra kode i samme forespørsel")
                   (run-guarded op input body)))))))))

(defun run-top-level (op input body record)
  "Run the call that owns RECORD; its outcome and backtrace go into RECORD."
  (handler-case (with-backtrace-capture (record)
                  (prog1 (run-guarded op input body)
                    (unless *transaction-mode* (application-after-request *application*))))
    (operation-error (e)
      (choose-request-backtrace record e)
      (set-request-outcome record (outcome-for-code (operation-error-code e))
                           :code (operation-error-code e) :message (operation-error-message e))
      (error e))
    (serious-condition (e)
      (choose-request-backtrace record e)
      (set-request-outcome record "error" :code :internal-error :message (condition-text e))
      (error e))))

(defun run-guarded (op input body)
  (with-audit-scope
    (flet ((run ()
             (handler-case (execute-operation op input body)
               (rejection (r)
                 (record-rejection op input *actor* (rejection-code r) :as (rejection-audit-actor r))
                 (fail (rejection-code r) "~a" (rejection-message r))))))
      (if *deadline*
          (run)                         ; nested: the outermost call owns the deadline
          ;; Top level: run under the deadline; on expiry everything has
          ;; rolled back by the time the handler runs, and the rejection
          ;; is audited outside the deadline.
          ;; The capture sits inside the deadline handler, so the backtrace
          ;; is taken where the deadline hit, not where it was reported.
          (handler-case (with-deadline () (with-backtrace-capture (*request-record*) (run)))
            (deadline-exceeded (c)
              (choose-request-backtrace *request-record* c)
              (record-rejection op input *actor* :deadline-exceeded)
              (fail :deadline-exceeded "~a brukte mer enn ~d ms og ble avbrutt; ingenting er lagret"
                    (operation-tool op) *deadline-ms*)))))))

(defun note-policy (op actor permitted)
  (let ((record *request-record*))
    (when (and record (equal (request-tool record) (operation-tool op)))
      (set-request-policy record (operation-policy op) (actor-role actor) (if permitted "allow" "deny")))))

(defun execute-operation (op input body)
  (let ((actor *actor*))
    (unless (actor-p actor)
      (error 'actor-error :message "Kallet mangler aktør (X-Tun-Actor)"))
    (let ((permitted (with-step (:policy :name (string-downcase (symbol-name (operation-policy op))) :source :core)
                       (actor-permits-p actor (operation-policy op)))))
      (note-policy op actor permitted)
      (unless permitted
        (reject :forbidden "~a (~a) har ikke tilgang til ~a; krever rollen ~a"
                (actor-name actor) (string-downcase (symbol-name (actor-role actor)))
                (operation-tool op) (string-downcase (symbol-name (operation-policy op))))))
    (with-step (:decode :source :core) (parse-operation-input op input))
    (cond ((operation-mutating-p op)
           (execute-mutation op input actor body))
          ;; A wait's body opens its own read transactions (AWAIT), so it
          ;; holds none while it waits (spec/waiting.md 1).
          ((eq (operation-kind op) :wait)
           (let ((result (let ((*input* input) (*inside-operation* t)) (funcall body))))
             (with-transaction (:read) (result->json result))))
          (t (with-transaction (:read)
               (let ((*input* input) (*inside-operation* t))
                 (result->json (funcall body))))))))

(defvar *shown-once* :none
  "Inside a mutation's transaction: the (key . value) pairs SHOW-ONCE added.")

(defun show-once (key value)
  "Show VALUE under KEY in the result of the running mutation to this caller
only (spec/auth.md 7): the receipt, and so any replay, holds null there.  For
a credential the call creates, such as a new access token."
  (declare (type string key))
  (when (eq *shown-once* :none)
    (error "SHOW-ONCE is only meaningful inside a mutating operation"))
  (push (cons key value) *shown-once*)
  value)

(defun hide-shown-once (json)
  "JSON with null for every key SHOW-ONCE set: what the receipt keeps."
  (when (and *shown-once* (hash-table-p json))
    (dolist (entry *shown-once*)
      (setf (gethash (car entry) json) :null)))
  json)

(defun reveal-shown-once (json shown)
  "A copy of JSON with the values in SHOWN, for the caller that produced them."
  (if (and shown (hash-table-p json))
      (let ((copy (make-hash-table :test 'equal :size (hash-table-count json))))
        (maphash (lambda (k v) (setf (gethash k copy) v)) json)
        (dolist (entry shown copy)
          (setf (gethash (car entry) copy) (cdr entry))))
      json))

(defun present-result (op json)
  "JSON, the result of mutation OP, with the operation's live view added (to
a copy of the top-level object; the receipt keeps its own text): in the
caller's transaction when nested in one, else in a read transaction of its
own, after the commit."
  (let ((live-view (operation-live-view op)))
    (if (or (null live-view) (not (hash-table-p json)))
        json
        (let ((copy (make-hash-table :test 'equal :size (hash-table-count json))))
          (maphash (lambda (k v) (setf (gethash k copy) v)) json)
          (if *transaction-mode*
              (funcall live-view copy)
              (with-transaction (:read) (funcall live-view copy)))))))

(defun execute-mutation (op input actor body)
  (let ((key (input-request-key input))
        (token (input-confirmation-token input))
        (hash (input-hash op input)))
    (when (and (operation-confirm-p op) (null token) *inside-operation*)
      (reject :confirmation-invalid
              "~a må bekreftes av en bruker i et eget kall; det kan ikke kalles fra en operasjon, arbeidsflyt eller skjerm"
              (operation-tool op)))
    (if (and (operation-confirm-p op) (null token))
        (let ((replayed (and key (with-transaction (:read)
                                   (with-step (:idempotency :name "receipt lookup" :source :core)
                                     (replay-receipt op actor key hash))))))
          (if replayed
              (present-result op replayed)
              (with-step (:confirmation :name "issue token" :source :core)
                (issue-confirmation op input actor hash))))
        (present-result
         op
         (let* ((deferred nil)
                (*audit-actor* nil)
                (*audit-reason* nil)
                (*shown-once* '())
                (json (with-transaction (:write)
                        (or (and key (with-step (:idempotency :name "receipt lookup" :source :core)
                                       (replay-receipt op actor key hash)))
                            (progn
                              (when (operation-confirm-p op)
                                (with-step (:confirmation :name "consume token" :source :core)
                                  (consume-confirmation op actor token (confirmation-hash op input))))
                              (let ((result (let ((*input* input) (*inside-operation* t)) (funcall body))))
                                (if (deferred-result-p result)
                                    (progn (write-audit op input actor "ok" :result (deferred-result-subject result))
                                           (setf deferred result)
                                           nil)
                                    (let ((json (hide-shown-once (result->json result))))
                                      (write-audit op input actor "ok" :result result)
                                      (when key
                                        (with-step (:idempotency :name "receipt store" :source :core)
                                          (store-receipt op actor key hash json)))
                                      json))))))))
           (cond ((null deferred) (reveal-shown-once json *shown-once*))
                 ;; Nested inside another transaction: nothing can commit
                 ;; first, so finish in place.
                 (*transaction-mode* (result->json (funcall (deferred-result-thunk deferred))))
                 (t (let* ((final (funcall (deferred-result-thunk deferred)))
                           (json (with-transaction (:read) (result->json final))))
                      (when key
                        (with-transaction (:write) (store-receipt op actor key hash json)))
                      json))))))))

;;; ------------------------------------------------------------------
;;; Calling operations

(defun call-tool (tool arguments &key (application *application*) (actor *actor*))
  "Call the operation exposed as TOOL with JSON ARGUMENTS as ACTOR.
Returns the result JSON object or signals OPERATION-ERROR / UNKNOWN-TOOL / ACTOR-ERROR."
  (let ((op (find-operation-by-tool tool)))
    ;; The start-up integrity check again, before every request (about
    ;; 0.1 ms): a wrapper installed while serving is refused at the next
    ;; request, not only at the next start.  --debug-tools (the REPL, TRACE)
    ;; may wrap and redefine; then only start-up checks.
    (unless (application-debug-tools-p application)
      (check-definition-integrity "serve the request"))
    (when (or (null op) (not (operation-visible-p op application)))
      (error 'unknown-tool :tool tool))
    (let ((*actor* actor)
          (*request-id* (or *request-id* (new-id "req"))))
      (funcall (operation-name op) application (make-input arguments)))))

(defun invoke (name &rest keys-and-values)
  "Call operation NAME (a symbol) in the current application as *ACTOR*.
KEYS-AND-VALUES are alternating JSON keys and values."
  (funcall name *application* (make-input (apply #'jobj keys-and-values))))
