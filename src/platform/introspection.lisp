;;;; platform/introspection.lisp -- what an agent can ask a running tenant
;;;; (core.md §8.2).  Every tool is a read with policy admin, entity null,
;;;; source core, and always present -- except eval, which exists only when
;;;; the server runs with --allow-eval.
;;;;
;;;;   introspect_record      one stored record: fields, computed, sources, related rows, audit
;;;;   introspect_request     one request's record and step trace (core/trace.lisp)
;;;;   introspect_recent      recent requests: errors, slow, rejected or all
;;;;   introspect_inflight    requests running now and what they wait for
;;;;   introspect_workflows   workflows with status, attempts and failure note
;;;;   explain                a dry run of a tool call: policy, input, rules, hooks, effect
;;;;   introspect_schema      tables, columns, applied migrations
;;;;   introspect_runtime     build, process, memory, workers, queues, clock
;;;;   introspect_extensions  every client extension with its source location
;;;;   eval                   Lisp in the running process, read-only (--allow-eval)

(defpackage #:tun.introspection
  (:use #:cl #:tun.core)
  (:export #:introspect-record #:introspect-request #:introspect-recent #:introspect-inflight
           #:introspect-workflows #:explain #:introspect-schema #:introspect-runtime
           #:introspect-extensions #:eval-code
           #:*core-revision* #:*client-revision* #:explain-call #:extension-items #:evaluate-code
           #:+eval-output-limit+))

(in-package #:tun.introspection)

(declaim (optimize (safety 3) (debug 2)))

(defun role-string (role) (string-downcase (symbol-name role)))
(defun source-name (source) (string-downcase (symbol-name source)))

(defun introspection-tool-p (tool)
  (and (stringp tool)
       (or (string-prefix-p "introspect_" tool) (string= tool "explain"))))

;;; ------------------------------------------------------------------
;;; introspect_record

(defun entity-class-named (name)
  (let ((class (find-entity-by-json-name name)))
    (unless (and class (not (entity-embedded-p class)))
      (fail :not-found "Ukjent entitet ~a (navnene står i registry_describe og introspect_schema)" name))
    class))

(defun stored-json (record)
  (let ((object (jobj)))
    (dolist (field (entity-stored-fields (class-of record)) object)
      (setf (gethash (field-json-name field) object) (field-json-value record field)))))

(defun computed-json (record)
  (let ((object (jobj)))
    (dolist (cf (entity-computed-fields (class-of record)) object)
      (setf (gethash (computed-field-json-name cf) object)
            (handler-case (type->json (computed-field-type cf) (funcall (computed-field-function cf) record))
              (error (e) (jobj "error" (princ-to-string e))))))))

(defun field-sources (class)
  (let ((object (jobj)))
    (dolist (field (entity-stored-fields class))
      (setf (gethash (field-json-name field) object) (source-name (field-source field))))
    (dolist (cf (entity-computed-fields class) object)
      (setf (gethash (computed-field-json-name cf) object) (source-name (computed-field-source cf))))))

(defun reference-fields (class target)
  "Stored fields of CLASS that hold ids of TARGET records: id fields that
reference TARGET, or untyped id fields named <target>_id."
  (let ((json (entity-json-name target)))
    (remove-if-not (lambda (field)
                     (let ((type (field-type field)))
                       (and (typep type 'id-type)
                            (string/= (field-json-name field) "id")
                            (if (id-references type)
                                (eq (id-references type) (class-name target))
                                (string= (field-json-name field) (format nil "~a_id" json))))))
                   (entity-stored-fields class))))

(defun related-json (target id)
  "Records that refer to TARGET's record ID: rows of internal entities
(bookings, reservations, movements), ids of the others."
  (let ((object (jobj)))
    (dolist (class (all-entity-classes) object)
      (unless (or (entity-embedded-p class) (eq class (find-class 'audit-entry)))
        (let ((fields (reference-fields class target)))
          (dolist (field fields)
            (let ((rows (remove-if-not (lambda (record) (entity-readable-p record *actor*))
                          (select (class-name class) :where `(:= ,(field-json-name field) ,id)
                                                   :order-by '(("seq" :desc)) :limit 50))))
              (when rows
                (setf (gethash (if (rest fields)
                                   (format nil "~a.~a" (entity-table class) (field-json-name field))
                                   (entity-table class))
                               object)
                      (jarr (if (entity-internal-p class)
                                (mapcar #'stored-json rows)
                                (mapcar #'entity-id rows))))))))))))

(defun audit-json (entry)
  (let ((object (jobj "id" (entity-id entry)
                      "at" (format-rfc3339 (audit-entry-at entry))
                      "actor" (audit-entry-actor entry)
                      "tool" (audit-entry-tool entry)
                      "outcome" (audit-entry-outcome entry))))
    (when (audit-entry-error-code entry) (setf (gethash "error_code" object) (audit-entry-error-code entry)))
    (when (audit-entry-request-key entry) (setf (gethash "request_key" object) (audit-entry-request-key entry)))
    (when (audit-entry-request-id entry) (setf (gethash "request_id" object) (audit-entry-request-id entry)))
    (when (audit-entry-credential entry)
      (setf (gethash "credential" object) (audit-entry-credential entry)))
    object))

(define-operation introspect-record ((entity :type (string :max 100) :required t :label "Entitet"
                                             :description "Entitetsnavn som i registry_describe, f.eks. order, customer, product.")
                                     (id :type (string :max 100) :required t :label "ID"))
    (:kind :read :policy :admin :title "Inspiser post"
     :description "Én lagret post: alle lagrede felt (også klientens), beregnede felt, hvor hvert felt kommer fra (core/client), poster som viser til den, og de 20 siste revisjonsloggføringene for den.")
  (let* ((class (entity-class-named entity))
         (record (or (fetch (class-name class) id)
                     (fail :not-found "~a ~a finnes ikke" (entity-json-name class) id))))
    (unless (entity-readable-p record *actor*) (fail :not-found "Posten finnes ikke"))
    (jobj "entity" (entity-json-name class)
          "id" id
          "stored" (if (typep record 'setting)
                       (let ((object (stored-json record)))
                         (when (secret-setting-p (setting-key record)) (setf (gethash "value" object) "***"))
                         object)
                       (stored-json record))
          "computed" (computed-json record)
          "field_sources" (field-sources class)
          "related" (related-json class id)
          "audit" (jarr (mapcar #'audit-json
                                (select 'audit-entry :where `(:and (:= "entity_type" ,(entity-json-name class))
                                                                   (:= "entity_id" ,id))
                                                     :order-by '(("seq" :desc)) :limit 20))))))

;;; ------------------------------------------------------------------
;;; Requests

(define-operation introspect-request ((request-id :type (string :max 100) :required t :label "Forespørsels-ID"
                                                  :description "X-Tun-Request-Id eller _meta.request_id."))
    (:kind :read :policy :admin :title "Inspiser forespørsel"
     :description "Hele forløpet til én forespørsel: aktør, verktøy, input (uten confirmation_token og request_key), utfall, policy, alle steg med tid (policy, dekoding, regler, hooks med kilde og rekkefølge, operasjon, lagringskall, eksterne kall, revisjon, commit), ventetid på skrivelåsen og backtrace ved feil.")
  (let ((record (find-request request-id)))
    (unless record
      (fail :not-found "Ingen forespørsel ~a blant de ~d siste (de lagres bare i minnet, og nullstilles ved omstart)"
            request-id *request-history-size*))
    (request->json record)))

(define-operation introspect-recent ((kind :type (enum "errors" "slow" "rejected" "all") :default "all"
                                           :label "Utvalg")
                                     (since :type timestamp :label "Fra og med")
                                     (request-kind :type (enum "operation" "mcp" "api" "web" "job" "workflow")
                                                   :label "Slags forespørsel")
                                     (tool :type (string :max 200) :label "Verktøy"
                                           :description "En del av verktøyets navn, som orders_ eller job:send.")
                                     (limit :type (integer :min 1 :max 1000) :default 20 :label "Maks antall"))
    (:kind :read :policy :admin :title "Siste forespørsler"
     :description "Avsluttede forespørsler, sist avsluttet først: errors (utfall error), rejected, slow (total_ms ≥ 1000, eller de tregeste når ingen er så trege) eller all. request_kind og tool snevrer inn til én slags forespørsel (operation, mcp, api, web, job, workflow) og verktøy hvis navn inneholder teksten. Hver har sin slags (kind) og, ved feil, feilkode og melding.")
  (let* ((records (remove-if-not (lambda (r)
                                   (and (not (and since (request-at r) (< (request-at r) since)))
                                        (or (null request-kind)
                                            (string= request-kind (string-downcase (symbol-name (request-kind r)))))
                                        (or (null tool)
                                            (and (request-tool r) (search tool (request-tool r))))))
                                 (finished-requests)))
         (selected
           (cond ((string= kind "errors") (remove "error" records :key #'request-outcome :test-not #'equal))
                 ((string= kind "rejected") (remove "rejected" records :key #'request-outcome :test-not #'equal))
                 ((string= kind "slow")
                  (or (remove-if (lambda (r) (< (request-total-us r) 1000000)) records)
                      (sort (copy-list records) #'> :key #'request-total-us)))
                 (t records))))
    (jobj "items" (jarr (mapcar #'request-summary->json
                                (subseq selected 0 (min limit (length selected))))))))

(defun state-string (state)
  (ecase state
    (:running "running")
    (:waiting-write-lock "waiting_write_lock")
    (:external-call "external_call")))

(define-operation introspect-inflight ()
    (:kind :read :policy :admin :title "Pågående forespørsler"
     :description "Forespørsler som kjører nå: hvor lenge, og om de kjører, venter på skrivelåsen eller venter på et eksternt system. (Over --max-inflight avvises nye straks med 503, så ingen venter på å slippe inn.)")
  (jobj "items"
        (jarr (loop for record in (in-flight-requests)
                    unless (eq record *request-record*)
                      collect (jobj "request_id" (request-id record)
                                    "actor" (or (request-actor record) :null)
                                    "tool" (or (request-tool record) :null)
                                    "elapsed_ms" (us->ms (request-elapsed-us record))
                                    "state" (state-string (request-state record)))))))

;;; ------------------------------------------------------------------
;;; introspect_workflows

(define-operation introspect-workflows ((status :type (enum "planlagt" "utført" "avbrutt" "feilet") :label "Status")
                                        (due-before :type timestamp :label "Forfall før")
                                        (limit :type (integer :min 1 :max 100000) :default 50 :label "Maks antall"))
    (:kind :read :policy :admin :title "Arbeidsflyter"
     :description "Arbeidsflyter på tvers av ordrer, sist forfalt først: type, forfall, status, når de ble kjørt, antall forsøk (0 eller 1: de kjøres høyst én gang) og merknaden med feilteksten når en handler feilet (status avbrutt).")
  (let ((where (remove nil (list (and status `(:= "status" ,status))
                                 (and due-before `(:< "due_at" ,due-before))))))
    (jobj "items"
          (jarr (mapcar (lambda (wf)
                          (let ((object (jobj "id" (entity-id wf)
                                              "kind" (tun.workflows:workflow-kind wf)
                                              "due_at" (format-rfc3339 (tun.workflows:workflow-due-at wf))
                                              "status" (tun.workflows:workflow-status wf)
                                              "attempts" (if (tun.workflows:workflow-executed-at wf) 1 0))))
                            (when (tun.workflows:workflow-order-id wf)
                              (setf (gethash "order_id" object) (tun.workflows:workflow-order-id wf)))
                            (when (tun.workflows:workflow-executed-at wf)
                              (setf (gethash "executed_at" object)
                                    (format-rfc3339 (tun.workflows:workflow-executed-at wf))))
                            (when (tun.workflows:workflow-note wf)
                              (setf (gethash "note" object) (tun.workflows:workflow-note wf)))
                            object))
                        (select 'tun.workflows:workflow :where (and where `(:and ,@where))
                                                        :order-by '(("due_at" :desc) ("seq" :desc))
                                                        :limit limit))))))

;;; ------------------------------------------------------------------
;;; explain

(defun error-fields-json (condition)
  (if (operation-error-fields condition)
      (mapcar (lambda (fe) (jobj "field" (car fe) "message" (cdr fe))) (operation-error-fields condition))
      (list (jobj "field" "input" "message" (operation-error-message condition)))))

(defun operation-methods (op)
  "Values: the :before methods in execution order and the :after methods in
execution order, of OP for this application.  Both phases run least
specific first (the modules in dependency order, then the client)."
  (let* ((gf (fdefinition (operation-name op)))
         (methods (closer-mop:compute-applicable-methods-using-classes
                   gf (list (class-of *application*) (find-class 'operation-input)))))
    (values (reverse (remove-if-not (lambda (m) (equal (method-qualifiers m) '(:before))) methods))
            (reverse (remove-if-not (lambda (m) (equal (method-qualifiers m) '(:after))) methods)))))

(defun step-module (step)
  "The owning module of a hook step: its detail names the protocol's method
owner as <protocol>:<class>; the class's package gives the module."
  (let* ((name (trace-step-name step))
         (colon (position #\: name))
         (owner (and colon (subseq name (1+ colon)))))
    (if (eq (trace-step-source step) :client)
        "client"
        (or (and owner
                 (loop for m in (all-modules)
                       when (string-equal owner (symbol-name (module-mixin m))) return (module-name m)))
            "core"))))

(defun hook-json (phase method order)
  (jobj "phase" phase "name" (method-owner-name method) "source" (source-name (method-source method))
        "module" (method-module method) "order" order))

(defun dry-run (op input)
  "Run OP's effect computation (EXPLAIN-WOULD) and the rules on its draft,
in a read transaction, with a scratch trace.  Values: would (JSON or :null),
summary (or NIL), the error (a condition or NIL), the steps."
  (let ((would :null) (summary nil) (failure nil))
    (multiple-value-bind (ignored steps)
        (call-collecting-steps
         (lambda ()
           (handler-case
               (with-transaction (:read)
                 (let ((*input* input) (*operation* op) (*inside-operation* t))
                   (setf would (or (explain-would (operation-name op) input) :null))
                   ;; What insert would check once the draft is complete.
                   (when (input-draft input) (validate-entity (input-draft input)))
                   (when (operation-confirm-p op)
                     (setf summary (confirmation-summary op input)))))
             (operation-error (e) (setf failure e))
             (read-only-violation (e) (setf failure e)))))
      (declare (ignore ignored))
      (values would summary failure steps))))

(defun explain-call (tool arguments)
  (let ((op (find-operation-by-tool tool)))
    (unless (and op (operation-visible-p op))
      (fail :not-found "Ukjent verktøy ~a" tool))
    (let* ((actor *actor*)
           (permitted (actor-permits-p actor (operation-policy op)))
           (input (make-input (if (hash-table-p arguments) arguments (jobj))))
           (input-errors (handler-case (progn (parse-operation-input op input) '())
                           (operation-error (e) (error-fields-json e))))
           (would :null) (summary nil) (failure nil) (steps '()))
      (unless (hash-table-p arguments)
        (setf input-errors (list (jobj "field" "input" "message" "må være et JSON-objekt"))))
      (when (null input-errors)
        (multiple-value-setq (would summary failure steps) (dry-run op input)))
      ;; Rule violations are what a real call would report as invalid_input.
      (when (and failure (typep failure 'operation-error) (eq (operation-error-code failure) :invalid-input))
        (setf input-errors (error-fields-json failure)))
      (multiple-value-bind (befores afters) (operation-methods op)
        (let ((object
                (jobj "tool" tool
                      "policy" (jobj "required" (role-string (operation-policy op))
                                     "actor_role" (role-string (actor-role actor))
                                     "decision" (if permitted "allow" "deny"))
                      "input_valid" (json-bool (null input-errors))
                      "input_errors" (jarr input-errors)
                      "confirm_required" (json-bool (operation-confirm-p op))
                      "rules" (jarr (let ((entity (operation-entity op)))
                                      (and entity
                                           (mapcar (lambda (r) (jobj "name" (json-name-of (rule-name r))
                                                                     "source" (source-name (rule-source r))))
                                                   (entity-rules (find-entity-class entity))))))
                      "hooks" (jarr (append
                                     (loop for m in befores for i from 1 collect (hook-json "before" m i))
                                     (loop for step in steps
                                           when (eq (trace-step-kind step) :hook)
                                             collect (let* ((name (trace-step-name step))
                                                            (colon (position #\: name)))
                                                       (jobj "phase" (subseq name 0 colon)
                                                             "name" (subseq name (1+ colon))
                                                             "source" (source-name (trace-step-source step))
                                                             "module" (step-module step)
                                                             "order" (trace-step-order step))))
                                     (loop for m in afters for i from 1 collect (hook-json "after" m i))))
                      "would" would)))
          (when (and failure (not (and (typep failure 'operation-error)
                                       (eq (operation-error-code failure) :invalid-input))))
            (setf (gethash "would" object) :null
                  summary (format nil "Kallet ville feilet: ~a"
                                  (if (typep failure 'operation-error)
                                      (format nil "~a: ~a" (json-name-of (operation-error-code failure))
                                              (operation-error-message failure))
                                      (princ-to-string failure))))
            (when (typep failure 'operation-error)
              (setf (gethash "would_error" object)
                    (jobj "code" (json-name-of (operation-error-code failure))
                          "message" (operation-error-message failure)))))
          (when summary (setf (gethash "summary" object) summary))
          object)))))

(defun explain-workflow (tool order-id)
  (let* ((name (subseq tool (length "workflow:"))) (kind (find-workflow-kind name)))
    (unless kind (fail :invalid-input "Ukjent arbeidsflyt ~a" name))
    (unless order-id (fail :invalid-input "Oppgi ordre"))
    (jobj "tool" tool "order_id" order-id
          "templates" (jarr (workflow-kind-templates kind))
          "hooks" (jarr (list (jobj "name" (string-downcase (symbol-name (workflow-kind-function kind)))
                                    "source" (source-name (workflow-kind-source kind))
                                    "module" (workflow-kind-module kind)))))))

(define-operation explain ((tool :type (string :max 100) :required t :label "Verktøy")
                           (order-id :type id :label "Ordre")
                           (input :type json :label "Input" :description "Argumentene kallet ville fått (et JSON-objekt)."))
    (:kind :read :policy :admin :title "Forklar et kall"
     :description "Tørrkjøring av et verktøykall i en skrivebeskyttet transaksjon: ingenting lagres, ingen kvittering, intet token. Viser policy-avgjørelsen for deg, om input er gyldig, regler og hooks i kjørerekkefølge med kilde, og hva kallet ville gitt (for orders_create/orders_update: beløp, behov og bookinger; for orders_confirm: tilgjengelighet per utleielinje).")
  (if (string-prefix-p "workflow:" tool) (explain-workflow tool order-id)
      (explain-call tool (or input (jobj)))))

;;; ------------------------------------------------------------------
;;; introspect_schema and introspect_runtime

(define-operation introspect-schema ()
    (:kind :read :policy :admin :title "Databaseskjema"
     :description "Tabeller med kolonner (navn, type, om de kan være null) og migreringene som er kjørt, i rekkefølge.")
  (multiple-value-bind (tables migrations) (store-describe-schema *store*)
    (jobj "tables" tables "migrations" migrations)))

(defvar *core-revision* nil "Set when a server image is built; TUN_CORE_REVISION overrides.")
(defvar *client-revision* nil "Set when a server image is built; TUN_CLIENT_REVISION overrides.")

(defun revision (variable value)
  (or (let ((env (sb-ext:posix-getenv variable))) (and env (plusp (length env)) env))
      value
      "unknown"))

(defun rss-bytes ()
  (ignore-errors
   (with-open-file (in "/proc/self/status")
     (loop for line = (read-line in nil)
           while line
           when (string-prefix-p "VmRSS:" line)
             return (* 1024 (parse-integer line :start 6 :junk-allowed t))))))

(define-operation introspect-runtime ()
    (:kind :read :policy :admin :title "Kjøretid"
     :description "Bygg (core- og klientrevisjon, språk, runtime), oppetid, minne (RSS, heap, GC), arbeidstråder, forespørsler i arbeid og maksimum, skrivekø, frist og klokke.")
  (let* ((app *application*)
         (cell (application-inflight-cell app)))
    (jobj "build" (jobj "core_revision" (revision "TUN_CORE_REVISION" *core-revision*)
                        "client_revision" (revision "TUN_CLIENT_REVISION" *client-revision*)
                        "language" "Common Lisp"
                        "runtime_version" (format nil "~a ~a" (lisp-implementation-type) (lisp-implementation-version))
                        "client" (application-title app))
          "live_patches" (jarr (live-definition-patches app))
          "definition_sources" (jarr (live-definition-sources app))
          "uptime_s" (round (- (trace-clock-us) (application-started-us app)) 1000000)
          "rss_bytes" (or (rss-bytes) :null)
          "heap_bytes" (sb-kernel:dynamic-usage)
          "gc" (jobj "bytes_consed" (sb-ext:get-bytes-consed)
                     "run_time_ms" (round (* 1000 sb-ext:*gc-run-time*) internal-time-units-per-second)
                     "nursery_bytes" (sb-ext:bytes-consed-between-gcs)
                     "heap_limit_bytes" (sb-ext:dynamic-space-size))
          "workers" (jobj "kind" "threads" "count" (length (sb-thread:list-all-threads)))
          "inflight" (if cell (car cell) (length (in-flight-requests)))
          "max_inflight" (or (application-max-inflight app) :null)
          "write_queue_depth" (store-write-queue-depth *store*)
          "deadline_ms" *deadline-ms*
          "clock" (jobj "mode" (if (test-mode-p app) "test" "real") "now" (now-string))
          "store" (store-description *store*)
          "requests_retained" (jobj "kept" (length (finished-requests)) "capacity" *request-history-size*
                                    "where" "memory (lost on restart)")
          "identity" (if (claimed-identity-p app) "claimed" "authenticated")
          "eval" (json-bool (application-allow-eval-p app))
          "repl_port" (or (application-repl-port app) :null)
          "modules" (jarr (mapcar (lambda (entry)
                                    (destructuring-bind (module enabled-by) entry
                                      (jobj "name" (module-name module)
                                            "revision" (module-revision (module-name module))
                                            "depends_on" (jarr (module-depends-on module))
                                            "enabled_by" enabled-by
                                            "core_range" (jarr (module-core-range module)))))
                                  (enabled-modules app))))))

;;; ------------------------------------------------------------------
;;; introspect_extensions

(defun item (kind target name location &optional order (module "client"))
  (let ((object (jobj "kind" kind "target" (or target :null) "name" name
                      "source_location" (or location "unknown")
                      ;; core.md §1.3: core, the module name, or client.
                      "source" module
                      "module" module)))
    (when order (setf (gethash "order" object) order))
    object))

(defun extension-of-p (module owner)
  "True when MODULE (who defined an item) extends something OWNER owns: the
client always does; a module does when the owner is another module or core."
  (or (string= module "client")
      (and (string/= module "core") (string/= module owner))))

(defun operation-hook-items ()
  "Client and module :before and :after methods on operations, with their
order in the chain."
  (loop for op in (visible-operations)
        append (multiple-value-bind (befores afters) (operation-methods op)
                 (append (loop for m in befores for i from 1
                               when (extension-of-p (method-module m) (operation-module op))
                                 collect (item "before" (operation-tool op) (method-owner-name m)
                                               (definition-source-location m) i (method-module m)))
                         (loop for m in afters for i from 1
                               when (extension-of-p (method-module m) (operation-module op))
                                 collect (item "after" (operation-tool op) (method-owner-name m)
                                               (definition-source-location m) i (method-module m)))))))

(defun protocol-items ()
  "Client and module methods on other owners' seams, rule points and screens."
  (loop for protocol in *extension-protocols*
        for name = (extension-protocol-name protocol)
        for kind = (extension-protocol-kind protocol)
        for gf = (and (fboundp name) (fdefinition name))
        when gf
          append (let ((methods (remove-if-not
                                 (lambda (m) (let ((owner (first (closer-mop:method-specializers m))))
                                               (and (typep owner 'class) (typep *application* owner))))
                                 (closer-mop:generic-function-methods gf))))
                   ;; Chain order: most specific first, as the application's class precedence gives.
                   (setf methods (sort (copy-list methods) #'<
                                       :key (lambda (m) (or (position (first (closer-mop:method-specializers m))
                                                                      (closer-mop:class-precedence-list (class-of *application*)))
                                                            most-positive-fixnum))))
                   (loop for m in methods
                         for i from 1
                         when (extension-of-p (method-module m) (extension-protocol-module protocol))
                           collect (let ((second (second (closer-mop:method-specializers m))))
                                     (item kind
                                           (if (typep second 'closer-mop:eql-specializer)
                                               (json-name-of (closer-mop:eql-specializer-object second))
                                               (json-name-of name))
                                           (method-owner-name m)
                                           (definition-source-location m)
                                           (and (string/= kind "screen") i)
                                           (method-module m)))))))

(defun extension-items ()
  (append
   ;; Fields, rules and computed fields added to another owner's entity.
   (loop for class in (all-entity-classes)
         for owner = (entity-module class)
         append (append
                 (loop for field in (entity-fields class)
                       when (extension-of-p (field-module field) owner)
                         collect (item "field" (entity-json-name class) (field-json-name field) (field-location field)
                                       nil (field-module field)))
                 (loop for rule in (entity-rules class)
                       when (extension-of-p (rule-module rule) owner)
                         collect (item "rule" (entity-json-name class) (json-name-of (rule-name rule)) (rule-location rule)
                                       nil (rule-module rule)))
                 (loop for cf in (entity-computed-fields class)
                       when (extension-of-p (computed-field-module cf) owner)
                         collect (item "computed" (entity-json-name class) (computed-field-json-name cf)
                                       (computed-field-location cf) nil (computed-field-module cf)))))
   ;; The client's own operations, workflows and templates.
   (loop for op in (visible-operations)
         when (eq (operation-source op) :client)
           collect (item "operation" (let ((e (operation-entity op))) (and e (entity-json-name (find-entity-class e))))
                         (operation-tool op) (operation-location op)))
   (operation-hook-items)
   (protocol-items)
   (loop for wk in *workflow-kinds*
         when (eq (workflow-kind-source wk) :client)
           collect (item "workflow" (workflow-kind-name wk)
                         (string-downcase (symbol-name (workflow-kind-function wk))) (workflow-kind-location wk)))
   (loop for template in *message-templates*
         when (and (eq (message-template-source template) :client)
                   (eq template (find-message-template (message-template-name template))))
           collect (item "template" (message-template-name template)
                         (string-downcase (symbol-name (message-template-function template)))
                         (message-template-location template)))))

(defun extension-point-items ()
  "Every extension point a module (or the kernel) publishes, with its owner:
kind seam, target the generic function a client specializes."
  (mapcar (lambda (protocol)
            (jobj "name" (extension-protocol-point protocol)
                  "kind" "seam"
                  "target" (json-name-of (extension-protocol-name protocol))
                  "hook_kind" (extension-protocol-kind protocol)
                  "module" (extension-protocol-module protocol)
                  "source" (extension-protocol-module protocol)
                  "function" (json-name-of (extension-protocol-name protocol))
                  "source_location" (or (let ((name (extension-protocol-name protocol)))
                                          (and (fboundp name) (definition-source-location (fdefinition name))))
                                        "unknown")))
          *extension-protocols*))

(define-operation introspect-extensions ()
    (:kind :read :policy :admin :title "Klientutvidelser"
     :description "Alt klienten har lagt til gjennom utvidelsespunktene, med fil:linje: felt, regler, beregnede felt, operasjoner, før/etter-metoder på operasjoner (med rekkefølge), metoder på domeneprotokollene (rabatt, behov, bookingvindu: kind before, target er protokollen), arbeidsflyter, maler og skjermbilder.")
  (jobj "items" (jarr (append (extension-items) (extension-point-items)))))

;;; ------------------------------------------------------------------
;;; eval (--allow-eval only)

(defconstant +eval-output-limit+ 65536)

(defclass capped-output (sb-gray:fundamental-character-output-stream)
  ((buffer :initform (make-string-output-stream) :reader capped-buffer)
   (written :initform 0 :accessor capped-written)
   (dropped :initform 0 :accessor capped-dropped)))

(defmethod sb-gray:stream-write-char ((stream capped-output) char)
  (if (< (capped-written stream) +eval-output-limit+)
      (progn (write-char char (capped-buffer stream)) (incf (capped-written stream)))
      (incf (capped-dropped stream)))
  char)

(defmethod sb-gray:stream-line-column ((stream capped-output)) nil)

(defun capped-string (string)
  (if (> (length string) +eval-output-limit+)
      (concatenate 'string (subseq string 0 +eval-output-limit+) "…")
      string))

(defun read-all-forms (code)
  (let ((*read-eval* nil)
        (*package* (find-package "TUN-EVAL"))
        (forms '()))
    (handler-case
        (with-input-from-string (in code)
          (loop for form = (read in nil in)
                until (eq form in)
                do (push form forms)))
      (error (e) (fail :invalid-input "Koden kunne ikke leses: ~a" (princ-to-string e))))
    (nreverse forms)))

(defun audit-eval (outcome &optional error-code)
  (let ((actor *actor*) (request-id *request-id*))
    (defer-audit (lambda ()
                   (let ((*request-id* request-id))
                     (insert (make-instance 'audit-entry :at (now) :actor (actor-string actor) :tool "eval"
                                                         :outcome outcome :error-code error-code
                                                         :request-id request-id)))))))

;;; eval is read-only in every thread it starts, too: a thread made while
;;; *UNDER-EVAL* is true runs with it true, so its write transactions are
;;; refused like the eval's own (otherwise an eval could start a thread
;;; that writes, such as one creating an admin employee).  Wrapping
;;; SB-THREAD:MAKE-THREAD reaches every thread Bordeaux Threads, Hunchentoot
;;; and SBCL's own timers start; code that calls SBCL's internals directly can
;;; still get round it (eval is not a sandbox; see docs/architecture.md, "Known limits").

(defun eval-aware-make-thread (make-thread function &rest arguments)
  (if *under-eval*
      (apply make-thread (lambda (&rest args) (let ((*under-eval* t)) (apply function args))) arguments)
      (apply make-thread function arguments)))

(unless (sb-int:encapsulated-p 'sb-thread:make-thread 'tun-under-eval)
  (sb-int:encapsulate 'sb-thread:make-thread 'tun-under-eval #'eval-aware-make-thread))

(defun evaluate-code (code)
  "Read CODE with *READ-EVAL* off in TUN-EVAL and evaluate it form by form,
here: inside the operation's read transaction (a store write signals; so does
one in any thread the code starts) and under its deadline.  Output and printed values are capped at 64 KiB."
  (let* ((forms (read-all-forms code))
         (output (make-instance 'capped-output))
         (values '()))
    (handler-case
        (let ((*standard-output* output) (*error-output* output) (*trace-output* output)
              (*package* (find-package "TUN-EVAL")) (*read-eval* nil) (*under-eval* t))
          (dolist (form forms)
            (setf values (multiple-value-list (eval form)))))
      (deadline-exceeded (e) (audit-eval "rejected" "deadline_exceeded") (error e))
      (read-only-violation (e)
        (audit-eval "rejected" "read_only")
        (fail-with-details :read-only (list "output" (get-output-stream-string (capped-buffer output)))
                           "eval kjører i en skrivebeskyttet transaksjon; skriving er ikke tillatt: ~a"
                           (princ-to-string e)))
      (operation-error (e) (audit-eval "rejected" (json-name-of (operation-error-code e))) (error e))
      (error (e)
        (let ((text (princ-to-string e)))
          (audit-eval "rejected" (if (search "readonly" (string-downcase text)) "read_only" "invalid_input"))
          (if (search "readonly" (string-downcase text))
              (fail-with-details :read-only (list "output" (get-output-stream-string (capped-buffer output)))
                                 "eval kjører skrivebeskyttet; databasen avviste skrivingen: ~a" text)
              (fail-with-details :invalid-input (list "output" (get-output-stream-string (capped-buffer output))
                                                      "condition" (string-downcase (symbol-name (type-of e))))
                                 "Evalueringen feilet: ~a" text)))))
    (audit-eval "ok")
    (let ((*print-length* 200) (*print-level* 10) (*print-readably* nil) (*package* (find-package "TUN-EVAL")))
      (jobj "values" (jarr (mapcar (lambda (v) (capped-string (prin1-to-string v))) values))
            "output" (get-output-stream-string (capped-buffer output))
            "output_truncated" (json-bool (plusp (capped-dropped output)))
            "forms" (length forms)))))

(define-operation eval-code ((code :type (string :max 1000000) :required t :label "Kode"
                                   :description "Common Lisp-uttrykk, lest med *read-eval* av i pakken TUN-EVAL (bruker CL og TUN)."))
    (:tool "eval" :kind :read :policy :admin :eval-only t :title "Evaluer Lisp i prosessen"
     :description "Bare med --allow-eval. Evaluerer Lisp-kode i den kjørende prosessen, under operasjonens frist og i en skrivebeskyttet lagringstransaksjon (skriving avvises). Utdata fanges og kuttes ved 64 KiB. Kallet revisjonslogges. Ikke en sandkasse: koden kan nå alt i prosessen.")
  (evaluate-code code))
