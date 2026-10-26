;;;; core/registry.lisp -- workflow and message-template registries, and the
;;;; projections of the whole registry: registry_describe and MCP tool
;;;; definitions.  Both are computed from the live classes and operation
;;;; objects at call time, so client extensions loaded after core appear
;;;; without any re-registration step.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Workflow kinds (handlers run by the workflow engine in tun.workflows)

(defclass workflow-kind ()
  ((kind :initarg :kind :reader workflow-kind-name)
   (label :initarg :label :reader workflow-kind-label)
   (function :initarg :function :reader workflow-kind-function)
   (source :initarg :source :reader workflow-kind-source)
   (module :initarg :module :initform "core" :reader workflow-kind-module)
   (location :initarg :location :initform nil :reader workflow-kind-location)
   (debug :initarg :debug :initform nil :reader workflow-kind-debug-p)
   (templates :initarg :templates :initform nil :reader workflow-kind-templates)
   (own-transactions :initarg :own-transactions :initform nil :reader workflow-kind-own-transactions-p
                     :documentation "The handler commits its own units of work (each in its own
transaction and deadline) instead of running inside the run's transaction.")))

(defvar *workflow-kinds* '() "Registered WORKFLOW-KIND objects in definition order.")

(defmacro define-workflow (name (&key kind label debug own-transactions templates) (workflow-var) &body body)
  "Define the handler NAME for workflows of KIND (a Norwegian string).
Expands into a DEFUN taking the due workflow entity, plus a registration.
The engine runs it at most once, inside a transaction, as the system actor.
With OWN-TRANSACTIONS the run is marked done first and the handler runs
outside any transaction, committing its own units of work (a long run that
must make progress, core.md §4.4)."
  (let ((source (current-definition-source))
        (module (current-definition-module))
        (location (current-source-location)))
    `(progn
       (defun ,name (,workflow-var) ,@body)
       (register-workflow-kind ,kind ',name :label ,(or label kind) :source ,source :debug ,(and debug t)
                                            :own-transactions ,(and own-transactions t) :templates ' ,templates
                                            :module ,module :location ,location)
       ',name)))

(defun register-workflow-kind (kind function-name &key label source debug own-transactions templates (module "core") location)
  ;; One handler per kind (platform 2.8): another definition of a kind is
  ;; refused; only the same handler may register it again (a reload).
  (let ((existing (find-workflow-kind kind)))
    (when (and existing (not (eq (workflow-kind-function existing) function-name)))
      (extension-error "Workflow kind ~a is already handled by ~s (~a); ~s (~a) cannot take it over"
                       kind (workflow-kind-function existing) (workflow-kind-module existing)
                       function-name module)))
  (setf *workflow-kinds*
        (append (remove kind *workflow-kinds* :key #'workflow-kind-name :test #'string=)
                (list (make-instance 'workflow-kind :kind kind :label label :debug debug
                                                    :own-transactions own-transactions :templates templates
                                                    :function function-name :source source
                                                    :module module :location location))))
  kind)

(defun find-workflow-kind (kind)
  (find kind *workflow-kinds* :key #'workflow-kind-name :test #'string=))

;;; ------------------------------------------------------------------
;;; Message templates

(defclass message-template ()
  ((name :initarg :name :reader message-template-name)
   (label :initarg :label :reader message-template-label)
   (function :initarg :function :reader message-template-function)
   (source :initarg :source :reader message-template-source)
   (module :initarg :module :initform "core" :reader message-template-module)
   (final :initarg :final :initform nil :reader message-template-final-p
          :documentation "A module's template a client may not replace (tun-platform.md 2.8).")
   (version :initarg :version :initform 1 :reader message-template-version)
   (subject :initarg :subject :initform nil :reader message-template-subject)
   (text :initarg :text :initform nil :reader message-template-text)
   (html :initarg :html :initform nil :reader message-template-html)
   (variables :initarg :variables :initform nil :reader message-template-variables)
   (manual :initarg :manual :initform nil :reader message-template-manual-p)
   (marketing :initarg :marketing :initform nil :reader message-template-marketing-p)
   (overridden :initarg :overridden :initform nil :reader message-template-overridden-p)
   (location :initarg :location :initform nil :reader message-template-location)))

(defvar *message-templates* '())

(defmacro define-message-template (name (&key template label final subject text html variables manual marketing) lambda-list &body body)
  "Define message template TEMPLATE (its Norwegian key, e.g. \"påminnelse\").
Expands into a DEFUN named NAME with LAMBDA-LIST (keywords among :ORDER
:CUSTOMER :INVOICE) returning two values: subject and body.  A client
template with the same key as a module's default replaces the default,
unless the module marked it FINAL (then the client's is refused)."
  (let* ((source (current-definition-source))
         (module (current-definition-module))
         (location (current-source-location))
         (keys (rest (member '&key lambda-list)))
         (vars (mapcar (lambda (k) (if (consp k) (first k) k)) keys)))
    `(progn
       (defun ,name (&rest args &key ,@keys &allow-other-keys)
         (declare (ignore args) (ignorable ,@vars))
         ,@(or body `((values ,subject ,text))))
       (register-message-template ,template ',name :label ,(or label template) :source ,source
                                                   :module ,module :final ,(and final t)
                                                   :location ,location :subject ,subject :text ,text :html ,html
                                                   :variables ',variables :manual ,manual :marketing ,marketing)
       ',name)))

(defun template-placeholder-variables (subject text)
  (let ((combined (concatenate 'string subject text)))
    (remove-duplicates
     (loop with cursor = 0
           for match = (multiple-value-list (cl-ppcre:scan "\\{\\{([^}]+)\\}\\}" combined :start cursor))
           while (first match)
           collect (subseq combined (aref (third match) 0) (aref (fourth match) 0))
           do (setf cursor (second match))) :test #'equal)))

(defun register-message-template (template function-name &key label source (module "core") final location
                                                            subject text html variables manual marketing)
  (let ((existing (find template *message-templates* :key #'message-template-name :test #'string=)))
    (when (and existing (message-template-final-p existing) (eq source :client))
      (extension-error "Template ~a belongs to module ~a, which marked it final; a client cannot replace it"
                       template (message-template-module existing)))
    (when (and existing (eq source :core) (eq (message-template-source existing) :core)
               (string/= module (message-template-module existing)))
      (extension-error "Template ~a is defined by both ~a and ~a" template (message-template-module existing) module))
    (when (and existing (eq source :core) (eq (message-template-source existing) :client))
      (when final (extension-error "Template ~a is final and cannot be overridden" template))
      (setf (slot-value existing 'overridden) t))
    ;; A module's default never replaces a client template, whatever the load order.
    (unless (and existing (eq source :core) (eq (message-template-source existing) :client))
      (setf *message-templates*
            (append (remove template *message-templates* :key #'message-template-name :test #'string=)
                    (list (make-instance 'message-template :name template :label label
                                                           :function function-name :source source
                                                           :module module :final final :subject subject :text text :html html
                                                           :variables (or variables (and text (template-placeholder-variables subject text)))
                                                           :manual manual :marketing marketing
                                                           :version (if (and existing (eq source :client)
                                                                             (or (not (eq (message-template-source existing) source))
                                                                                 (not (equal (message-template-module existing) module))
                                                                                 (not (eq function-name (message-template-function existing)))
                                                                                 (not (equal (message-template-subject existing) subject))
                                                                                 (not (equal (message-template-text existing) text))
                                                                                 (not (equal (message-template-html existing) html))))
                                                                        (1+ (message-template-version existing))
                                                                        (if existing (message-template-version existing) (if (eq source :client) 2 1)))
                                                           :overridden (and existing (or (message-template-overridden-p existing)
                                                                                        (eq source :client)))
                                                           :location location))))))
  template)

(defun message-template-description (template)
  "Template data and ownership; code templates remain supported for legacy staff messages."
  (jobj "name" (message-template-name template) "version" (message-template-version template)
        "subject" (or (message-template-subject template) (message-template-label template))
        "text" (or (message-template-text template) "") "html" (or (message-template-html template) :null)
        "variables" (jarr (message-template-variables template))
        "manual" (json-bool (message-template-manual-p template))
        "marketing" (json-bool (message-template-marketing-p template))
        "final" (json-bool (message-template-final-p template))
        "source" (string-downcase (symbol-name (message-template-source template)))
        "module" (message-template-module template)
        "overridden_by" (if (message-template-overridden-p template) "client" :null)))

(defun find-message-template (template)
  (find template *message-templates* :key #'message-template-name :test #'string=))

;;; The messaging port (kernel).  A module that sends messages (orders sends
;;; tilbud, invoicing faktura) calls NOTIFY; the messaging module, when it
;;; is enabled, registers the adapter that renders and sends.  Without it a
;;; notification sends nothing (core.md §5.1).

(defvar *message-sender* nil
  "The messaging port's adapter: a function (template &key order customer) that
renders and sends one message, or NIL when no messaging module is loaded.")

(defun register-message-sender (function)
  (setf *message-sender* function))

(defun notify (template &rest context &key order customer &allow-other-keys)
  "Send TEMPLATE for ORDER and CUSTOMER through the messaging port, if a
messaging module is enabled; otherwise do nothing.  Returns the message or NIL."
  (declare (ignore order customer))
  (and *message-sender* (apply *message-sender* template context)))

(defun render-message-template (template &rest context)
  "Values subject and body of TEMPLATE for CONTEXT (:order :customer :invoice)."
  (let ((tpl (or (find-message-template template)
                 (error "No message template ~s is registered" template))))
    (multiple-value-bind (subject body) (apply (message-template-function tpl) context)
      (check-type subject string)
      (check-type body string)
      (values subject body))))

;;; ------------------------------------------------------------------
;;; Paging helper for list operations

(defun page (items limit)
  "{items, returned, has_more} from ITEMS fetched with LIMIT + 1."
  (let* ((more (> (length items) limit))
         (shown (if more (subseq items 0 limit) items)))
    (jobj "items" (jarr (mapcar #'result->json shown))
          "returned" (length shown)
          "has_more" (json-bool more))))

;;; ------------------------------------------------------------------
;;; registry_describe

(defun source-string (source) (string-downcase (symbol-name source)))

(defun describe-field (field)
  (let ((type (field-type field)))
    (let ((object (jobj "name" (field-json-name field)
                        "type" (type-name type)
                        "label" (or (field-label field) (field-json-name field))
                        "required" (json-bool (field-required-p field))
                        "source" (source-string (field-source field))
                        "module" (field-module field)
                        "input" (json-bool (field-input-p field))
                        "computed" nil)))
      (typecase type
        (enum-type (setf (gethash "values" object) (jarr (enum-values type))))
        (list-type (when (symbolp (list-element type))
                     (setf (gethash "items" object)
                           (entity-json-name (find-entity-class (list-element type))))))
        (id-type (when (id-references type)
                   (let ((ref (find-entity-class (id-references type) nil)))
                     (when ref (setf (gethash "references" object) (entity-json-name ref)))))))
      object)))

(defun describe-computed-field (cf)
  (let* ((type (computed-field-type cf))
         (object (jobj "name" (computed-field-json-name cf)
                       "type" (type-name type)
                       "label" (computed-field-label cf)
                       "required" nil
                       "source" (source-string (computed-field-source cf))
                       "module" (computed-field-module cf)
                       "input" nil
                       "computed" t)))
    (when (typep type 'enum-type)
      (setf (gethash "values" object) (jarr (enum-values type))))
    object))

(defun describe-record-policy (class)
  (jarr (loop for (role text) in (entity-record-policy class)
              collect (jobj "role" (string-downcase (symbol-name role))
                            "condition" (if (eq text t) t text)))))

(defun describe-entity (class)
  (let ((object (describe-entity-definition class)))
    ;; Only an entity with a policy has the key, so other descriptions keep
    ;; their shape.
    (when (entity-record-policy class)
      (setf (gethash "record_policy" object) (describe-record-policy class)))
    object))

(defun describe-entity-definition (class)
  (jobj "name" (entity-json-name class)
        "label" (entity-label class)
        "source" (source-string (entity-source class))
        "module" (entity-module class)
        "embedded" (json-bool (entity-embedded-p class))
        "fields" (jarr (append (mapcar #'describe-field (entity-fields class))
                               (mapcar #'describe-computed-field (entity-computed-fields class))))
        "rules" (jarr (mapcar (lambda (r) (jobj "name" (json-name-of (rule-name r))
                                                "field" (or (rule-field r) :null)
                                                "message" (rule-message r)
                                                "source" (source-string (rule-source r))
                                                "module" (rule-module r)))
                              (entity-rules class)))))

(defun operation-entity-name (op)
  (let ((entity (operation-entity op)))
    (if entity (entity-json-name (find-entity-class entity)) :null)))

(defun describe-operation (op)
  (jobj "name" (operation-tool op)
        "title" (operation-title op)
        "entity" (operation-entity-name op)
        "kind" (string-downcase (symbol-name (operation-kind op)))
        "confirm" (json-bool (operation-confirm-p op))
        "idempotent" (json-bool (operation-idempotent-p op))
        "audit" (json-bool (operation-audited-p op))
        "policy" (string-downcase (symbol-name (operation-policy op)))
        "source" (source-string (operation-source op))
        "module" (operation-module op)))

(defun describe-registry (&optional (application *application*))
  (jobj "templates" (jarr (mapcar #'message-template-description *message-templates*))
        "settings" (jarr (settings-description :value nil))
        "entities" (jarr (mapcar #'describe-entity
                                 (remove-if #'entity-internal-p (all-entity-classes))))
        "operations" (jarr (mapcar #'describe-operation (visible-operations application)))
        "workflows" (jarr (mapcar (lambda (w) (jobj "kind" (workflow-kind-name w)
                                                    "label" (workflow-kind-label w)
                                                    "source" (source-string (workflow-kind-source w))
                                                    "module" (workflow-kind-module w)))
                                  (remove-if (lambda (w) (and (workflow-kind-debug-p w)
                                                              (not (application-debug-tools-p application))))
                                             *workflow-kinds*)))
        "message_templates" (jarr (mapcar (lambda (m) (jobj "name" (message-template-name m)
                                                            "label" (message-template-label m)
                                                            "source" (source-string (message-template-source m))
                                                            "module" (message-template-module m)
                                                            "final" (json-bool (message-template-final-p m))))
                                          *message-templates*))
        "screens" (jarr (describe-screens application))
        "extension_points" (jarr (mapcar #'describe-extension-point *extension-protocols*))
        "modules" (jarr (mapcar (lambda (entry) (describe-module (first entry) (second entry)))
                                (enabled-modules application)))))

(defun describe-module (module enabled-by)
  (jobj "name" (module-name module)
        "revision" (module-revision (module-name module))
        "depends_on" (jarr (module-depends-on module))
        "enabled_by" enabled-by
        "core_range" (jarr (module-core-range module))))

(defun describe-extension-point (protocol)
  (jobj "name" (extension-protocol-point protocol)
        "kind" "seam"
        "hook_kind" (extension-protocol-kind protocol)
        "function" (json-name-of (extension-protocol-name protocol))
        "module" (extension-protocol-module protocol)
        "description" (or (extension-protocol-description protocol) :null)))

(defvar *screens* '()
  "Screens the generated UI renders, as (keyword module) in registration order.")

(defun register-screen (name &optional (module (current-definition-module)))
  (setf *screens* (append (remove name *screens* :key #'first) (list (list name module))))
  name)

(defun describe-screens (application)
  "Every screen of the UI with its owner (core or the module that registered
it), then every override of one (a method for that screen on a module's or
the client's class), least specific first."
  (let ((protocol (find "screen" *extension-protocols* :key #'extension-protocol-kind :test #'string=)))
    (append
     (loop for (name module) in *screens*
           collect (jobj "name" (json-name-of name) "source" "core" "module" module "override" nil))
     (when (and protocol (fboundp (extension-protocol-name protocol)))
       (let ((methods (remove-if-not
                       (lambda (m)
                         (let ((owner (first (closer-mop:method-specializers m)))
                               (screen (second (closer-mop:method-specializers m))))
                           (and (typep screen 'closer-mop:eql-specializer)
                                (typep owner 'class) (typep application owner))))
                       (closer-mop:generic-function-methods (fdefinition (extension-protocol-name protocol))))))
         (loop for m in (reverse methods)
               collect (jobj "name" (json-name-of (closer-mop:eql-specializer-object
                                                   (second (closer-mop:method-specializers m))))
                             "source" (source-string (method-source m))
                             "module" (method-module m)
                             "override" t)))))))

;;; ------------------------------------------------------------------
;;; MCP tool definitions (tools/list is a query against the live registry)

(defun tool-definition (op)
  (jobj "name" (operation-tool op)
        "title" (operation-title op)
        "description" (operation-description op)
        "inputSchema" (operation-input-schema op)
        "annotations" (jobj "title" (operation-title op)
                            "readOnlyHint" (json-bool (not (operation-mutating-p op)))
                            "destructiveHint" (json-bool (operation-destructive-p op))
                            "idempotentHint" (json-bool (not (operation-mutating-p op)))
                            "openWorldHint" nil)))

(defun tool-definitions (&optional (application *application*))
  (mapcar #'tool-definition (visible-operations application)))
