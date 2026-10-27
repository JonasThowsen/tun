;;;; core/operation.lisp -- operations, their method combination, and the
;;;; guarded execution path.
;;;;
;;;; DEFINE-OPERATION expands into a DEFGENERIC using the OPERATION method
;;;; combination, one primary DEFMETHOD specialized on APPLICATION (the domain
;;;; function), and a registration (the metadata every surface projects).
;;;;
;;;; The OPERATION method combination is the security boundary.  Its effective
;;;; method always wraps the methods in RUN-OPERATION, which performs policy,
;;;; input validation, idempotency, confirmation, the transaction and audit.
;;;; It accepts only :BEFORE, :AFTER and exactly one primary method, so a
;;;; module or client can add behaviour before or after an operation (in a
;;;; defined order, the same for both phases: least specific class first,
;;;; i.e. the modules in dependency order, then the client's features) but
;;;; cannot replace the domain body or wrap it with an :AROUND method that
;;;; skips the guard.  Calling the generic function
;;;; directly from Lisp goes through the same guard as MCP and the web UI.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(deftype operation-kind () '(member :read :wait :create :update :transition :workflow))

(defun mutating-kind-p (kind)
  "True for the kinds of operation that write: all but :READ and :WAIT, which
reads until something changes (spec/waiting.md 1)."
  (not (member kind '(:read :wait))))

;;; ------------------------------------------------------------------
;;; Parameters

(defclass parameter ()
  ((name :initarg :name :reader parameter-name)
   (keyword :initarg :keyword :reader parameter-keyword)
   (json-name :initarg :json-name :reader parameter-json-name)
   (type-designator :initarg :type :reader parameter-type-designator)
   (type-object :initform nil)
   (required :initarg :required :initform nil :reader parameter-required-p)
   (schema-required :initarg :schema-required :initform nil :reader parameter-schema-required-p
                    :documentation "Listed as required in the JSON Schema without being enforced by
the parser: the operation accepts an alternative in its place (the
inventory tools keep product_id required and take article_id instead).")
   (default :initarg :default :initform nil :reader parameter-default)
   (label :initarg :label :initform nil :reader parameter-label)
   (description :initarg :description :initform nil :reader parameter-description)
   (secret :initarg :secret :initform nil
           :documentation "True for a credential: a request's record shows \"***\" for it.")
   (entity-field :initarg :entity-field :initform nil :reader parameter-entity-field
                 :documentation "(entity json-name) when the parameter reuses an entity field.")))

(defun parameter-field (parameter)
  (let ((ref (parameter-entity-field parameter)))
    (and ref (find-field (find-entity-class (first ref)) (second ref)))))

(defun parameter-secret-p (parameter)
  "True when PARAMETER carries a credential: declared :SECRET T, or reusing a
secret field (core.md 8.2)."
  (let ((field (parameter-field parameter)))
    (or (slot-value parameter 'secret)
        (and field (field-secret-p field)))))

(defun parameter-type (parameter)
  (let ((field (parameter-field parameter)))
    (if field
        (field-type field)
        (or (slot-value parameter 'type-object)
            (setf (slot-value parameter 'type-object)
                  (parse-field-type (parameter-type-designator parameter)))))))

(defun parameter-text (parameter)
  (let ((field (parameter-field parameter)))
    (or (parameter-description parameter)
        (parameter-label parameter)
        (and field (or (field-description field) (field-label field)))
        (parameter-json-name parameter))))

(defun check-parameter-texts (spec)
  "Refuse SPEC, a parameter spec, when its label or description is not a
string written out: a spec is data, so +TEXT+ would not be evaluated."
  (let ((name (if (eq (first spec) :field) (third spec) (first spec)))
        (options (if (eq (first spec) :field) (cdddr spec) (rest spec))))
    (check-written-text (format nil "Parameter ~(~a~)" name) :label (getf options :label))
    (check-written-text (format nil "Parameter ~(~a~)" name) :description
                        (getf options :description))))

(defun parse-parameter-spec (spec)
  "SPEC is (NAME &key TYPE REQUIRED DEFAULT LABEL DESCRIPTION SECRET) or
(:FIELD ENTITY FIELD-NAME &key REQUIRED) reusing an entity field definition."
  (check-parameter-texts spec)
  (if (eq (first spec) :field)
      (destructuring-bind (entity field-name &key required label description) (rest spec)
        (make-instance 'parameter :name field-name
                                  :keyword (intern (symbol-name field-name) :keyword)
                                  :json-name (json-name-of field-name)
                                  :type nil :required required :label label :description description
                                  :entity-field (list entity (json-name-of field-name))))
      (destructuring-bind (name &key (type 'string) required schema-required default label
                                description secret)
          spec
        (make-instance 'parameter :name name
                                  :keyword (intern (symbol-name name) :keyword)
                                  :json-name (json-name-of name)
                                  :type type :required required :schema-required schema-required
                                  :default default :label label :description description
                                  :secret secret))))

;;; ------------------------------------------------------------------
;;; Operation metadata

(defclass operation ()
  ((name :initarg :name :reader operation-name :documentation "The generic function name.")
   (tool :initarg :tool :reader operation-tool)
   (entity :initarg :entity :reader operation-entity)
   (kind :initarg :kind :reader operation-kind :type operation-kind)
   (title :initarg :title :reader operation-title)
   (description :initarg :description :reader operation-description)
   (policy :initarg :policy :reader operation-policy :type policy)
   (confirm :initarg :confirm :reader operation-confirm-p)
   (destructive :initarg :destructive :reader operation-destructive-p)
   (test-only :initarg :test-only :reader operation-test-only-p)
   (debug-only :initarg :debug-only :initform nil :reader operation-debug-only-p)
   (eval-only :initarg :eval-only :initform nil :reader operation-eval-only-p
              :documentation "Present only when the server runs with --allow-eval (the eval tool).")
   (parameters :initarg :parameters :reader operation-parameters)
   (draft :initarg :draft :reader operation-draft-p
          :documentation "Create operations receive a validated draft entity built from the entity's input fields.")
   (summary :initarg :summary :reader operation-summary-function)
   (live-view :initarg :live-view :initform nil :reader operation-live-view
              :documentation "A function of a mutation's result JSON adding what the response shows
but the operation does not record (a live view, such as an order's stock
warnings).  It runs after the commit, in a read transaction, for a fresh
result and a replayed receipt alike: it never holds the writer lock, and
the receipt keeps the recorded result only.")
   (source :initarg :source :reader operation-source)
   (module :initarg :module :initform "core" :reader operation-module
           :documentation "Who defined the operation: \"core\", a module name or \"client\".")
   (location :initarg :location :initform nil :reader operation-location)))

(defun operation-mutating-p (op) (mutating-kind-p (operation-kind op)))
(defun operation-idempotent-p (op)
  "Idempotency receipts apply to every mutating operation; not configurable."
  (operation-mutating-p op))
(defun operation-audited-p (op)
  "Audit applies to every mutating operation; not configurable."
  (operation-mutating-p op))

(defvar *operations* (make-hash-table :test 'eq) "Generic function name -> OPERATION.")
(defvar *operation-order* '() "Operation names in definition order.")

(defun register-operation (operation)
  (let ((name (operation-name operation)))
    (when (find-if (lambda (other) (and (not (eq (operation-name other) name))
                                        (string= (operation-tool other) (operation-tool operation))))
                   (all-operations))
      (extension-error "Tool name ~a is already defined" (operation-tool operation)))
    (setf (gethash name *operations*) operation)
    (setf *operation-order* (append (remove name *operation-order*) (list name)))
    operation))

(defun all-operations ()
  (mapcar (lambda (n) (gethash n *operations*)) *operation-order*))

(defun find-operation (name &optional (errorp t))
  (or (gethash name *operations*)
      (and errorp (error "No operation named ~s" name))))

(defun find-operation-by-tool (tool)
  (find tool (all-operations) :key #'operation-tool :test #'string=))

(defun operation-visible-p (op &optional (application *application*))
  "Test-only tools need the test clock; debug-only tools need --debug-tools;
eval-only tools need --allow-eval."
  (not (or (and (operation-test-only-p op) (not (test-mode-p application)))
           (and (operation-debug-only-p op) (not (application-debug-tools-p application)))
           (and (operation-eval-only-p op) (not (application-allow-eval-p application))))))

(defun visible-operations (&optional (application *application*))
  "Operations exposed by this deployment."
  (remove-if-not (lambda (op) (operation-visible-p op application)) (all-operations)))

;;; ------------------------------------------------------------------
;;; Input objects

(defclass operation-input ()
  ((arguments :initarg :arguments :reader input-arguments
              :documentation "The raw JSON arguments object as received.")
   (values :initform '() :accessor input-values :documentation "Plist keyword -> parsed value.")
   (provided :initform '() :accessor input-provided :documentation "Keywords present in the input.")
   (nulls :initform '() :accessor input-nulls :documentation "Keywords present in the input as JSON null.")
   (draft :initform nil :accessor input-draft)
   (request-key :initform nil :accessor input-request-key)
   (confirmation-token :initform nil :accessor input-confirmation-token)
   (parsed :initform nil :accessor input-parsed-p)))

(defun make-input (&optional (arguments (jobj)))
  "An operation input from a JSON object (hash table)."
  (make-instance 'operation-input :arguments (or arguments (jobj))))

(defvar *input* nil "The input of the operation being executed.")
(defvar *operation* nil "The OPERATION being executed.")
(defvar *operation-result* nil "Bound to the primary method's result while :AFTER methods run.")

(defun input-value (key &optional (input *input*))
  "Parsed value of input parameter KEY (a keyword) of the current operation."
  (getf (input-values input) key))

(defun input-provided-p (key &optional (input *input*))
  (and (member key (input-provided input)) t))

(defun input-null-p (key &optional (input *input*))
  "True when the caller sent KEY explicitly as null (an update that clears it)."
  (and (member key (input-nulls input)) t))

(defun operation-result ()
  "In an :AFTER method: the value returned by the operation's primary method."
  *operation-result*)

(defun current-operation-tool ()
  (and *operation* (operation-tool *operation*)))

;;; ------------------------------------------------------------------
;;; Schema (projection for tools/list and forms)

(defun operation-input-schema (op)
  (let* ((base (if (operation-draft-p op)
                   (entity-input-schema (find-entity-class (operation-entity op)))
                   (jobj "type" "object" "properties" (jobj) "required" (vector)
                         "additionalProperties" nil)))
         (properties (gethash "properties" base))
         (required (coerce (gethash "required" base) 'list)))
    (dolist (p (operation-parameters op))
      (let ((schema (type-json-schema (parameter-type p))))
        (setf (gethash "description" schema) (parameter-text p))
        (when (parameter-default p) (setf (gethash "default" schema) (parameter-default p)))
        (setf (gethash (parameter-json-name p) properties) schema)
        (when (or (parameter-required-p p) (parameter-schema-required-p p))
          (setf required (append required (list (parameter-json-name p)))))))
    (when (operation-mutating-p op)
      (setf (gethash "request_key" properties)
            (jobj "type" "string" "minLength" 1 "maxLength" 64
                  "description" "Idempotensnøkkel: samme nøkkel og input gir samme resultat.")))
    (when (operation-confirm-p op)
      (setf (gethash "confirmation_token" properties)
            (jobj "type" "string"
                  "description" "Token fra første kall; uten token returneres en bekreftelsesforespørsel.")))
    (setf (gethash "required" base) (jarr (remove-duplicates required :test #'string= :from-end t)))
    base))

;;; ------------------------------------------------------------------
;;; Input parsing

(defun parse-operation-input (op input)
  "Validate INPUT's arguments against OP's schema; fill parsed values.
Signals invalid_input listing every problem."
  (unless (input-parsed-p input)
    (let ((args (input-arguments input))
          (params (operation-parameters op))
          (meta '()))
      (when (operation-mutating-p op) (push "request_key" meta))
      (when (operation-confirm-p op) (push "confirmation_token" meta))
      (collecting-input-errors
        (unless (hash-table-p args)
          (input-error "input" "må være et JSON-objekt")
          (return-from parse-operation-input nil))
        ;; Meta arguments.
        (multiple-value-bind (key present) (jget args "request_key")
          (when (and present (not (json-null-p key)) (member "request_key" meta :test #'string=))
            (if (and (stringp key) (< 0 (length key) 65))
                (setf (input-request-key input) key)
                (input-error "request_key" "må være en tekst på 1–64 tegn"))))
        (multiple-value-bind (token present) (jget args "confirmation_token")
          (when (and present (not (json-null-p token)) (member "confirmation_token" meta :test #'string=))
            (if (and (stringp token) (< 0 (length token) 200))
                (setf (input-confirmation-token input) token)
                (input-error "confirmation_token" "må være en tekst"))))
        (let ((param-names (mapcar #'parameter-json-name params)))
          (if (operation-draft-p op)
              (setf (input-draft input)
                    (input->entity (operation-entity op) args ""
                                   :allowed-extra (append meta param-names)))
              (unknown-names-errors
               "" (remove-if (lambda (key)
                               (or (member key param-names :test #'string=)
                                   (member key meta :test #'string=)))
                             (jkeys args)))))
        (dolist (p params)
          (multiple-value-bind (value present) (jget args (parameter-json-name p))
            (when (and present (json-null-p value))
              (push (parameter-keyword p) (input-nulls input)))
            (cond ((or (not present) (json-null-p value))
                   (if (parameter-required-p p)
                       (input-error (parameter-json-name p) "må fylles ut")
                       (setf (getf (input-values input) (parameter-keyword p)) (parameter-default p))))
                  (t (let* ((before (length *input-errors*))
                            (coerced (coerce-input (parameter-type p) value (parameter-json-name p))))
                       (when (= before (length *input-errors*))
                         (push (parameter-keyword p) (input-provided input))
                         (setf (getf (input-values input) (parameter-keyword p)) coerced)))))))))
    (setf (input-parsed-p input) t))
  input)

(defun input-hash (op input)
  "Hash binding confirmation tokens and idempotency receipts to the tool and its
input, excluding request_key and confirmation_token."
  (let ((copy (jobj)))
    (when (hash-table-p (input-arguments input))
      (maphash (lambda (k v)
                 (unless (member k '("request_key" "confirmation_token") :test #'string=)
                   (setf (gethash k copy) v)))
               (input-arguments input)))
    (canonical-json-hash (jobj "tool" (operation-tool op) "input" copy))))

;;; ------------------------------------------------------------------
;;; The method combination

(defun method-owner (method)
  "The class a method is specialized on (its first specializer)."
  (let ((specializer (first (closer-mop:method-specializers method))))
    (if (typep specializer 'class) specializer nil)))

(defun method-owner-name (method)
  (let ((class (method-owner method)))
    (if class (string-downcase (symbol-name (class-name class))) "t")))

(defun method-source (method)
  "Core or client: decided by the package of the class the method is specialized on
(a module's mixin is core: the platform, not the client)."
  (let* ((class (method-owner method))
         (package (and class (symbol-package (class-name class)))))
    (if (or (null class)
            (and package (or (core-package-p package) (eq package (find-package "COMMON-LISP")))))
        :core :client)))

(defun method-module (method)
  "\"core\", the module name or \"client\" owning METHOD's specializer."
  (class-owner-module (method-owner method)))

(define-method-combination operation ()
  ;; Both phases run least specific first: the modules in dependency order
  ;; (APPLICATION inherits their mixins, most dependent first), then the
  ;; client's features (tun-platform.md 2.7).
  ((before (:before) :order :most-specific-last)
   (primary () :required t)
   (after (:after) :order :most-specific-last))
  (:arguments application input)
  (:generic-function generic-function)
  (when (rest primary)
    (invalid-method-error (second primary)
                          "an operation has exactly one primary method (the core body); ~
                           extend it with :BEFORE or :AFTER methods"))
  (let ((tool (json-name-of (closer-mop:generic-function-name generic-function))))
    (flet ((call-methods (methods phase)
             ;; Each method is a step of the request: core.md §8.2 "hook" steps
             ;; with their source and their order in the chain.
             (loop for m in methods
                   for order from 1
                   collect `(with-step (:hook :name ,(format nil "~(~a~):~a" phase (method-owner-name m))
                                        :source ,(method-source m) :order ,order :detail ,tool)
                              (call-method ,m)))))
      `(run-operation ',(closer-mop:generic-function-name generic-function) ,application ,input
                      (lambda ()
                        ,@(call-methods before :before)
                        (let ((result (with-step (:operation :name ,tool
                                                  :source ,(method-source (first primary)))
                                        (call-method ,(first primary)))))
                          ;; :AFTER methods get a deep copy: changing it cannot
                          ;; alter what the operation returns or stored.
                          (let ((*operation-result* (result-copy result)))
                            ,@(call-methods after :after))
                          result))))))

(define-method-combination traced-protocol ()
  ((around (:around))
   (before (:before))
   (primary () :required t)
   (after (:after) :order :most-specific-last))
  (:arguments &whole arguments)
  (:generic-function generic-function)
  "The standard method combination, with every method a hook step of the
current request (core.md §8.2): used by the domain protocols clients extend.
When a client method takes part, the call may not change a core field of a
record among its arguments (CALL-WITH-CORE-FIELDS-UNCHANGED)."
  (let ((protocol (json-name-of (closer-mop:generic-function-name generic-function))))
    (labels ((traced (method phase order)
               `(make-method
                 (with-step (:hook :name ,(format nil "~a:~a" protocol (method-owner-name method))
                             :source ,(method-source method) :order ,order :detail ,phase)
                   (call-method ,method))))
             (chain (methods order)
               ;; The primary chain: CALL-NEXT-METHOD in one method calls the
               ;; next, which is itself traced.
               (when methods
                 `(make-method
                   (with-step (:hook :name ,(format nil "~a:~a" protocol (method-owner-name (first methods)))
                               :source ,(method-source (first methods)) :order ,order :detail "primary")
                     (call-method ,(first methods)
                                  ,(let ((next (chain (rest methods) (1+ order))))
                                     (and next (list next)))))))))
      (let* ((main `(call-method ,(chain primary 1)))
             (form (if (or before after)
                       `(multiple-value-prog1
                            (progn ,@(loop for m in before for i from 1 collect `(call-method ,(traced m "before" i)))
                                   ,main)
                          ,@(loop for m in after for i from 1 collect `(call-method ,(traced m "after" i))))
                       main))
             (whole (if around
                        `(call-method ,(first around) (,@(rest around) (make-method ,form)))
                        form)))
        (if (some (lambda (m) (eq :client (method-source m))) (append around before primary after))
            `(call-with-core-fields-unchanged ,arguments ,(format nil "A client method on ~a" protocol)
                                              (lambda () ,whole))
            whole)))))

(defstruct (deferred-result (:constructor complete-after-commit (subject thunk)))
  "Returned by an operation that must reach outside the database (the
accounting port): its transaction commits with SUBJECT audited, then THUNK
runs outside any transaction (doing its own) and returns the final result."
  subject thunk)

(defun result-copy (result)
  (cond ((typep result 'entity)
         (storage-json->entity (class-name (class-of result)) (entity->storage-json result)))
        ((typep result 'deferred-result) (result-copy (deferred-result-subject result)))
        (t result)))

;;; ------------------------------------------------------------------
;;; DEFINE-OPERATION

(defmacro define-operation (name (&rest parameters)
                            (&key tool entity (kind :read) title description
                                  (policy nil policy-p) confirm (destructive nil destructive-p)
                                  test-only debug-only eval-only summary viewer-mutation live-view)
                            &body body)
  "Define operation NAME.  PARAMETERS are parameter specs bound as variables in
BODY; a (:DRAFT VAR) element binds the validated draft entity of a :CREATE
operation.  One definition produces the domain function (a generic function
on the application), the input schema, the MCP tool and the registry entry."
  (check-type kind operation-kind)
  (let* ((source (current-definition-source))
         (module (current-definition-module))
         (location (current-source-location))
         (draft-spec (find :draft parameters :key (lambda (p) (and (consp p) (first p)))))
         (draft-var (second draft-spec))
         (param-specs (remove draft-spec parameters))
         (param-names (mapcar (lambda (spec) (if (eq (first spec) :field) (third spec) (first spec)))
                              param-specs))
         (policy (if policy-p policy (if (mutating-kind-p kind) :employee :viewer)))
         (tool (or tool (json-name-of name)))
         (doc (or description title "")))
    (unless (cl-ppcre:scan "^[a-z][a-z0-9_]*$" tool)
      (error "Tool name ~s must match ^[a-z][a-z0-9_]*$" tool))
    ;; A viewer mutation must say so, and check in its body whose record it
    ;; changes: a customer's answer to a quote, authorised by the quote's
    ;; access code (slice 1, 5.4), or a person's own access tokens.
    (when (and (mutating-kind-p kind) (eq policy :viewer) (not viewer-mutation))
      (error "Operation ~s mutates, so its policy cannot be :viewer (unless :viewer-mutation t)" name))
    (when (and draft-spec (not (eq kind :create)))
      (error "Only :create operations take a :draft"))
    ;; Refused when the definition is compiled, not when it is loaded.
    (mapc #'check-parameter-texts param-specs)
    (let ((input (gensym "INPUT")))
      `(progn
         (defgeneric ,name (application input)
           (:method-combination operation)
           (:documentation ,doc))
         (defmethod ,name ((application application) (,input operation-input))
           (declare (ignorable application))
           (let (,@(when draft-var `((,draft-var (input-draft ,input))))
                 ,@(mapcar (lambda (p) `(,p (getf (input-values ,input) ,(intern (symbol-name p) :keyword))))
                           param-names))
             (declare (ignorable ,@(when draft-var (list draft-var)) ,@param-names))
             ,@body))
         (register-operation
          (make-instance 'operation
                         :name ',name :tool ,tool :entity ',entity :kind ,kind
                         :title ,(or title tool) :description ,doc
                         :policy ,policy :confirm ,(and confirm t)
                         :destructive ,(if destructive-p
                                           (and destructive t)
                                           (and (member kind '(:update :transition)) t))
                         :test-only ,(and test-only t)
                         :debug-only ,(and debug-only t)
                         :eval-only ,(and eval-only t)
                         :parameters (mapcar #'parse-parameter-spec ',param-specs)
                         :draft ,(and draft-spec t)
                         :summary ',summary
                         :live-view ',live-view
                         :source ,source
                         :module ,module
                         :location ,location))
         ',name))))

;;; ------------------------------------------------------------------
;;; explain (core.md §8.2): what an operation would produce

(defgeneric explain-would (operation-name input)
  (:documentation "For explain: what the operation OPERATION-NAME would produce for
the parsed INPUT, computed by the code the operation itself runs, inside a
read transaction (a write signals; nothing is stored).  A JSON object, or
NIL for operations that do not describe their effect.")
  (:method (operation-name input)
    (declare (ignore operation-name input))
    nil))

;;; ------------------------------------------------------------------
;;; Checking extension methods at start-up

(defun check-operation-methods ()
  "Refuse to start if any operation generic function has methods the
OPERATION combination would reject at call time (a second primary, an
:AROUND, or a primary not specialized on APPLICATION)."
  (dolist (op (all-operations))
    (let* ((gf (fdefinition (operation-name op)))
           (methods (closer-mop:generic-function-methods gf))
           (primaries (remove-if #'method-qualifiers methods)))
      (dolist (m methods)
        (unless (member (method-qualifiers m) '(() (:before) (:after)) :test #'equal)
          (extension-error "Operation ~a: method qualifiers ~s are not allowed (only :before and :after)"
                           (operation-tool op) (method-qualifiers m))))
      (unless (and (= 1 (length primaries))
                   (eq (first (closer-mop:method-specializers (first primaries)))
                       (find-class 'application)))
        (extension-error "Operation ~a must have exactly one primary method, on APPLICATION"
                         (operation-tool op)))))
  t)
