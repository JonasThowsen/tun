;;;; core/entity.lisp -- entities as CLOS classes with a custom metaclass.
;;;;
;;;; DEFINE-ENTITY expands into an ordinary DEFCLASS whose metaclass is
;;;; ENTITY-CLASS.  Field metadata (type, label, required, source, ...) lives
;;;; on the slot definition objects, so every surface (JSON, schema, store
;;;; columns, registry_describe, generated UI) is computed from the live class
;;;; through the MOP.  EXTEND-ENTITY defines a mixin class holding the client's
;;;; slots and adds it to the entity's direct superclasses; core code that does
;;;; (MAKE-INSTANCE 'CUSTOMER) then gets the client's fields too.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Metaclass and slot definitions

(defclass entity-class (standard-class)
  ((json-name :initform nil :accessor entity-json-name)
   (label :initform nil :accessor entity-label)
   (table :initform nil :accessor entity-table)
   (id-prefix :initform "id" :accessor entity-id-prefix)
   (embedded :initform nil :accessor entity-embedded-p)
   (internal :initform nil :accessor entity-internal-p
             :documentation "Internal entities are stored but not listed by registry_describe.")
   (revisioned :initform nil :accessor entity-revisioned-p
               :documentation "SAVE increments the revision field: every accepted update counts.")
   (source :initform :core :accessor entity-source)
   (module :initform "core" :accessor entity-module
           :documentation "Who defined the entity: \"core\", a module name or \"client\".")
   (indexes :initform nil :accessor entity-indexes)
   (unique :initform nil :accessor entity-unique)
   (rules :initform nil :accessor entity-rules)
   (attachments :initform nil :accessor entity-attachments
                :documentation "Whether the entity's records take files (spec/files.md 1): NIL,
or a property list of :MAX, the most files one record holds, and :POLICY, the
least role that may add them.")
   (record-policy :initform nil :accessor entity-record-policy
                  :documentation "Which records each role reaches (spec/store.md 6): a list of
(ROLE TEXT PARTS), TEXT being T for every record or the condition's SQL text,
and PARTS that text split by SPLIT-SQL-TEXT.  NIL when the entity has none.")
   (computed :initform nil :accessor entity-computed-fields)
   (extensions :initform nil :accessor entity-extensions
               :documentation "Names of extension mixin classes, in registration order.")
   (rollback-check :initform nil :accessor entity-rollback-check
                   :documentation "A function of one stored record returning a finding (a string)
when an older core without this entity could not take a database holding the
record, or NIL (core.md §6.4).  Records of entities without one
are invisible to such a core and not counted.")
   (record-checks :initform nil :accessor entity-record-rollback-checks
                  :documentation "(function . entity-name) pairs: FUNCTION, of one stored record,
returns a finding or NIL; it runs for every record whether or not the older
core knows this entity, when the older core lacks ENTITY-NAME (always when
NIL): what a later module made a record of an entity it depends on mean
(ADD-ROLLBACK-CHECK).")
   (field-cache :initform nil :accessor entity-field-cache)
   (location :initform nil :accessor entity-location
             :documentation "file:line of the DEFINE-ENTITY form."))
  (:documentation "Metaclass of every tun entity."))

(defmethod closer-mop:validate-superclass ((class entity-class) (super standard-class)) t)

(defclass field-definition ()
  ((field-type :initarg :field-type :initform 'string :reader field-type-designator)
   (field-type-object :initform nil)
   (label :initarg :label :initform nil :reader field-label)
   (description :initarg :description :initform nil :reader field-description)
   (required :initarg :required :initform nil :reader field-required-p)
   (input :initarg :input :initform t :reader field-input-p
          :documentation "Accepted in create/update input.")
   (stored :initarg :stored :initform t :reader field-stored-p)
   (secret :initarg :secret :initform nil :reader field-secret-p
           :documentation "A credential (a token or session hash): every JSON projection shows \"***\".")
   (source :initarg :source :initform :core :reader field-source)
   (module :initarg :module :initform "core" :reader field-module
           :documentation "Who added the field: \"core\", a module name or \"client\".")
   (location :initarg :location :initform nil :reader field-location
             :documentation "file:line of the form that defined the field.")
   (json-name :initarg :json-name :initform nil)))

(defclass field-direct-slot-definition (field-definition closer-mop:standard-direct-slot-definition) ())
(defclass field-effective-slot-definition (field-definition closer-mop:standard-effective-slot-definition) ())

(defmethod closer-mop:direct-slot-definition-class ((class entity-class) &rest initargs)
  (declare (ignore initargs))
  (find-class 'field-direct-slot-definition))

(defmethod closer-mop:effective-slot-definition-class ((class entity-class) &rest initargs)
  (declare (ignore initargs))
  (find-class 'field-effective-slot-definition))

(defmethod closer-mop:compute-effective-slot-definition :around ((class entity-class) name direct-slots)
  (let ((effective (call-next-method))
        (direct (find-if (lambda (d) (typep d 'field-definition)) direct-slots)))
    (when (and direct (typep effective 'field-definition))
      (dolist (slot '(field-type label description required input stored secret source module location
                      json-name))
        (setf (slot-value effective slot) (slot-value direct slot))))
    effective))

(defun field-name (field) (closer-mop:slot-definition-name field))

(defun field-json-name (field)
  ;; Memoized: the derived name never changes for a slot definition.
  (or (slot-value field 'json-name)
      (setf (slot-value field 'json-name) (json-name-of (field-name field)))))

(defun field-type (field)
  "The parsed FIELD-TYPE object of FIELD (memoized)."
  (or (slot-value field 'field-type-object)
      (setf (slot-value field 'field-type-object)
            (parse-field-type (field-type-designator field)))))

;;; ------------------------------------------------------------------
;;; Root classes

(defclass entity () ()
  (:metaclass entity-class)
  (:documentation "Root of all entities, stored and embedded."))

(defclass stored-entity (entity)
  ((id :initarg :id :initform nil :accessor entity-id :type (or null string)
       :field-type id :label "ID" :input nil :source :core))
  (:metaclass entity-class)
  (:documentation "An entity with its own identity and table."))

;;; ------------------------------------------------------------------
;;; Registry of entity classes

(defvar *entities* '()
  "Entity class names in definition order (most recent last).")

(defun current-definition-source ()
  "The source of a definition being macroexpanded now: :CORE inside tun
packages, :CLIENT everywhere else.  Decided at expansion time, so a client
cannot claim to be core."
  (if (core-package-p *package*) :core :client))

(defun find-entity-class (name &optional (errorp t))
  (let ((class (find-class name nil)))
    (cond ((typep class 'entity-class) class)
          (errorp (error "~s does not name an entity" name))
          (t nil))))

(defun entity-label-text (class)
  "The label of the entity CLASS as a TEXT, an argument a message writes in
its own language: \"Order\", or its translation."
  (if (entity-label class)
      (make-text (entity-label class) '())
      (deferred-tr ("Record" :context "entity"))))

(defun all-entity-classes ()
  (mapcar #'find-class *entities*))

(defun find-entity-by-json-name (json-name)
  (find json-name (all-entity-classes) :key #'entity-json-name :test #'string=))

(defun entity-fields (class)
  "Ordered field definitions of CLASS: core fields (root class first), then
each extension's fields in registration order."
  (let ((class (if (symbolp class) (find-entity-class class) class)))
    (or (entity-field-cache class)
        (setf (entity-field-cache class)
              (progn
                (closer-mop:ensure-finalized class)
                (let* ((extensions (mapcar #'find-class (entity-extensions class)))
                       (own (remove-if (lambda (c)
                                         (or (member c extensions)
                                             (not (typep c 'entity-class))))
                                       (reverse (closer-mop:class-precedence-list class)))))
                  (remove-duplicates
                   (append (mapcan (lambda (c) (copy-list (closer-mop:class-direct-slots c))) own)
                           (mapcan (lambda (c) (copy-list (closer-mop:class-direct-slots c))) extensions))
                   :key #'field-name :from-end t)))))))

(defun find-field (class json-name)
  (find json-name (entity-fields class) :key #'field-json-name :test #'string=))

(defun entity-input-fields (class)
  (remove-if-not #'field-input-p (entity-fields class)))

(defun entity-stored-fields (class)
  (remove-if-not #'field-stored-p (entity-fields class)))

(defun invalidate-field-caches ()
  (dolist (class (all-entity-classes))
    (setf (entity-field-cache class) nil)))

;;; ------------------------------------------------------------------
;;; Macros

(defun field-spec->slot-spec (entity spec source &optional location (module (current-definition-module)))
  "Translate a field spec (NAME &key TYPE REQUIRED LABEL ...) into a DEFCLASS slot spec."
  (destructuring-bind (name &key (type 'string) required label description (input t) (stored t)
                                 secret (initform nil initform-p) json-name)
      spec
    (check-written-text (format nil "Field ~(~a~) of ~(~a~)" name entity) :label label)
    (check-written-text (format nil "Field ~(~a~) of ~(~a~)" name entity) :description description)
    (check-money-name type (or json-name (json-name-of name))
                      (format nil "Field ~(~a~) of ~(~a~)" name entity))
    (when (files-type-p (parse-field-type type))
      (error "Field ~(~a~) of ~(~a~): files are attached to a record (spec/files.md 1), ~
              not stored in a field; (files ...) is for an operation's parameters"
             name entity))
    (let ((lisp-type (type-lisp-type (parse-field-type type))))
      `(,name :initarg ,(intern (symbol-name name) :keyword)
              :accessor ,(symbolicate entity "-" name)
              :initform ,(if initform-p initform nil)
              :type ,lisp-type
              :field-type ,type
              :label ,(or label (string-downcase (symbol-name name)))
              ,@(when description `(:description ,description))
              :required ,(and required t)
              :input ,(and input t)
              :stored ,(and stored t)
              ,@(when secret '(:secret t))
              :source ,source
              :module ,module
              :location ,location
              ,@(when json-name `(:json-name ,json-name))))))

(defparameter +record-policy-roles+ '(:viewer :employee :admin)
  "The roles a record policy has clauses for (spec/store.md 6.1).")

(defparameter +record-policy-parameters+ '("actor" "actor_name")
  "The parameters a record policy's condition may use (spec/store.md 6.3).")

(defun parse-record-policy (entity clauses package)
  "CLAUSES, the :RECORD-POLICY of ENTITY, as ENTITY-RECORD-POLICY keeps
them, each condition's text read in PACKAGE.  Signals an error for anything
spec/store.md 6 refuses."
  (let ((roles '()))
    (mapcar (lambda (clause)
              (unless (and (consp clause) (= 2 (length clause))
                           (member (first clause) +record-policy-roles+)
                           (or (eq (second clause) t) (stringp (second clause))))
                (error "~s: a record policy clause is (ROLE CONDITION), ROLE one of ~
                        ~{~s~^, ~} and CONDITION t or SQL text, not ~s"
                       entity +record-policy-roles+ clause))
              (destructuring-bind (role condition) clause
                (when (member role roles)
                  (error "~s: the record policy has two clauses for ~s" entity role))
                (push role roles)
                (list role condition
                      (and (stringp condition)
                           (record-condition-parts entity condition package)))))
            clauses)))

(defun record-condition-parts (entity text package)
  (let ((parts (split-sql-text text package)))
    (dolist (part parts parts)
      (when (and (consp part) (eq (first part) :parameter)
                 (not (member (second part) +record-policy-parameters+ :test #'string=)))
        (error "~s: a record policy may use ~{:~a~^ and ~}, not :~a"
               entity +record-policy-parameters+ (second part))))))

(defparameter +attachment-policies+ '(:employee :admin)
  "The roles an entity's :ATTACHMENTS may name as the least that adds files.")

(defun parse-attachments-option (entity option)
  "OPTION, the :ATTACHMENTS of ENTITY, as ENTITY-ATTACHMENTS keeps it: NIL or
(:MAX N :POLICY ROLE) with the defaults filled in (spec/files.md 1).
Signals an error for anything else."
  (flet ((refuse ()
           (error "~s: :attachments is t or (:max N :policy ROLE), N from 1 to 100 and ROLE ~
                   ~{~s~^ or ~}, not ~s" entity +attachment-policies+ option)))
    (cond ((null option) nil)
          ((eq option t) (list :max 20 :policy :employee))
          ((not (and (listp option) (evenp (length option)))) (refuse))
          (t (destructuring-bind (&key (max 20) (policy :employee) &allow-other-keys) option
               (unless (and (null (set-difference (loop for key in option by #'cddr collect key)
                                                  '(:max :policy)))
                            (typep max '(integer 1 100))
                            (member policy +attachment-policies+))
                 (refuse))
               (list :max max :policy policy))))))

(defmacro define-entity (name (&key json-name label table id-prefix embedded internal
                                    indexes unique revisioned rollback-check record-policy
                                    attachments)
                         &body (fields))
  "Define entity NAME: a DEFCLASS with metaclass ENTITY-CLASS plus registration.
FIELDS are (field-name &key type required label description input stored secret initform
json-name).
ROLLBACK-CHECK names a function of one record for the rollback preflight
(see ENTITY-ROLLBACK-CHECK).  RECORD-POLICY is a list of (ROLE CONDITION):
which records each role reads and writes (spec/store.md 6).  ATTACHMENTS,
T or (:MAX N :POLICY ROLE), lets its records take files (spec/files.md 1)."
  (when (and embedded record-policy)
    (error "~s is embedded; only a stored entity has a record policy" name))
  (when (and embedded attachments)
    (error "~s is embedded; only a stored entity takes files" name))
  (let ((source (current-definition-source))
        (module (current-definition-module))
        (location (current-source-location))
        (json-name (or json-name (json-name-of name))))
    `(progn
       (defclass ,name (,(if embedded 'entity 'stored-entity))
         ,(mapcar (lambda (spec) (field-spec->slot-spec name spec source location)) fields)
         (:metaclass entity-class))
       (register-entity ',name
                        :json-name ,json-name
                        :label ,(or label json-name)
                        :table ,(or table json-name)
                        :id-prefix ,(or id-prefix (subseq json-name 0 (min 3 (length json-name))))
                        :embedded ,(and embedded t)
                        :internal ,(and internal t)
                        :revisioned ,(and revisioned t)
                        :source ,source
                        :module ,module
                        :location ,location
                        :indexes ',indexes
                        :unique ',unique
                        :rollback-check ',rollback-check
                        :record-policy ',(parse-record-policy name record-policy *package*)
                        :attachments ',(parse-attachments-option name attachments))
       ',name)))

(defun add-rollback-check (entity-name function &key older-lacks)
  "Have the rollback preflight run FUNCTION (a symbol: of one stored record,
returning a finding or NIL) on every record of ENTITY-NAME, an entity of
the calling module or of a module it depends on, also when the older core
knows the entity (a value it would read differently, such as a product's
link to an article).  With OLDER-LACKS (an entity name), only when the
older core lacks that entity: an older core that has it reads the record
the same way."
  (let ((class (find-class entity-name)))
    (setf (entity-record-rollback-checks class)
          (cons (cons function older-lacks)
                (remove function (entity-record-rollback-checks class) :key #'car)))
    entity-name))

(defparameter +reserved-tables+ '("schema_history")
  "Tables the stores keep for themselves (and SQLite's sqlite_*).")

(defun entity-claims (name json-name table id-prefix embedded)
  "The ways an entity NAME registering JSON-NAME, TABLE and ID-PREFIX would
take what another registered entity owns (platform 2.5, 2.8): its JSON name,
or for a stored entity its table or id prefix; or a store's own table."
  (append
   (when (and (not embedded)
              (or (member table +reserved-tables+ :test #'string-equal)
                  (string-prefix-p "sqlite_" (string-downcase table))))
     (list (format nil "table ~a is the store's own" table)))
   (loop for other in *entities*
         for class = (find-class other nil)
         unless (or (eq other name) (not (typep class 'entity-class)))
           append (append
                   (when (equal json-name (entity-json-name class))
                     (list (format nil "name ~a belongs to ~a (~a)" json-name other (entity-module class))))
                   (unless (or embedded (entity-embedded-p class))
                     (append
                      (when (and table (entity-table class) (string-equal table (entity-table class)))
                        (list (format nil "table ~a belongs to ~a (~a)" table other (entity-module class))))
                      (when (equal id-prefix (entity-id-prefix class))
                        (list (format nil "id prefix ~a belongs to ~a (~a)" id-prefix other (entity-module class))))))))))

(defun entity-registry-conflicts ()
  "Every claim of a registered entity on what another owns (open-application
refuses to start on any)."
  (loop for name in *entities*
        for class = (find-class name nil)
        when (typep class 'entity-class)
          append (mapcar (lambda (claim) (format nil "~a: ~a" name claim))
                         (entity-claims name (entity-json-name class) (entity-table class)
                                        (entity-id-prefix class) (entity-embedded-p class)))))

(defun check-entity-registry ()
  (let ((conflicts (entity-registry-conflicts)))
    (when conflicts
      (extension-error "Refusing to start; entities claim what another owns:~{~%  ~a~}" conflicts))
    t))

(defun table-owner (table)
  "The registered stored entity whose table is TABLE, or NIL."
  (loop for name in *entities*
        for class = (find-class name nil)
        when (and (typep class 'entity-class) (not (entity-embedded-p class))
                  (entity-table class) (string-equal table (entity-table class)))
          return name))

(defun register-entity (name &key json-name label table id-prefix embedded internal revisioned
                             source (module "core") location indexes unique rollback-check
                             record-policy attachments)
  (let ((claims (entity-claims name json-name table id-prefix embedded)))
    (when claims
      (extension-error "Entity ~s (~a) is refused: ~{~a~^; ~}" name module claims)))
  (let ((class (find-entity-class name)))
    (setf (entity-revisioned-p class) revisioned
          (entity-json-name class) json-name
          (entity-label class) label
          (entity-table class) table
          (entity-id-prefix class) id-prefix
          (entity-embedded-p class) embedded
          (entity-internal-p class) internal
          (entity-source class) source
          (entity-module class) module
          (entity-location class) location
          (entity-indexes class) indexes
          (entity-unique class) unique
          (entity-rollback-check class) rollback-check
          (entity-record-policy class) record-policy
          (entity-attachments class) attachments)
    ;; Re-evaluating DEFCLASS resets the direct superclasses; put registered
    ;; extensions back so a reload of core keeps client fields.
    (reapply-entity-extensions class)
    (setf *entities* (append (remove name *entities*) (list name)))
    (invalidate-field-caches)
    class))

(defmacro extend-entity (entity (&key name) &body (fields))
  "Add FIELDS to the existing ENTITY without editing its definition.  Expands
into a DEFCLASS of a mixin (named NAME, default ENTITY-EXTENSION in the
current package) that is added to the entity's direct superclasses."
  (let ((source (current-definition-source))
        (location (current-source-location))
        (mixin (or name (symbolicate entity "-EXTENSION"))))
    `(progn
       (defclass ,mixin ()
         ,(mapcar (lambda (spec) (field-spec->slot-spec entity spec source location)) fields)
         (:metaclass entity-class))
       (add-entity-extension ',entity ',mixin)
       ',mixin)))

(defun add-entity-extension (entity mixin-name)
  (let* ((class (find-entity-class entity))
         (mixin (find-class mixin-name))
         (existing (mapcar #'field-json-name (entity-fields class))))
    (closer-mop:ensure-finalized mixin)
    (dolist (slot (closer-mop:class-direct-slots mixin))
      (when (and (member (field-json-name slot) existing :test #'string=)
                 (not (member mixin-name (entity-extensions class))))
        (extension-error "Extension ~s redefines field ~a of entity ~a"
                         mixin-name (field-json-name slot) (entity-json-name class)))
      (when (find (field-json-name slot) (entity-computed-fields class)
                  :key #'computed-field-json-name :test #'string=)
        (extension-error "Extension ~s adds field ~a, which is a computed field of ~a"
                         mixin-name (field-json-name slot) (entity-json-name class))))
    (unless (member mixin-name (entity-extensions class))
      (setf (entity-extensions class) (append (entity-extensions class) (list mixin-name))))
    (reapply-entity-extensions class)
    (invalidate-field-caches)
    mixin))

(defun reapply-entity-extensions (class)
  (let* ((supers (closer-mop:class-direct-superclasses class))
         (missing (remove-if (lambda (m) (member (find-class m) supers))
                             (entity-extensions class))))
    (when missing
      (reinitialize-instance class :direct-superclasses
                             (append supers (mapcar #'find-class missing))))))

;;; ------------------------------------------------------------------
;;; Client code computes; it never changes a record in passing
;;;
;;; Rules, computed fields and seam methods receive live records.  A client's
;;; may change its own fields of them but not a core- or module-owned field:
;;; that is what operations, with their status machine, locks, confirmation
;;; and audit, are for (a discount method must not, say, set an order's
;;; status to bekreftet).  The guarded TUN:SAVE makes the same comparison.

(defun entity-core-state (entity)
  "The stored form of ENTITY's core-owned fields."
  (loop for field in (entity-stored-fields (class-of entity))
        when (eq :core (field-source field))
          collect (type->db (field-type field) (field-value entity field))))

(defun call-with-core-fields-unchanged (objects what thunk)
  "Call THUNK (client code: WHAT names it); signal an extension error when it
changed a core-owned field of an entity among OBJECTS."
  (let* ((entities (remove-if-not (lambda (o) (typep o 'entity)) objects))
         (before (mapcar #'entity-core-state entities)))
    (multiple-value-prog1 (funcall thunk)
      (loop for entity in entities
            for state in before
            unless (equal state (entity-core-state entity))
              do (extension-error "~a changed a core field of ~a ~a; client code may only compute (an operation changes records)"
                                  what (entity-json-name (class-of entity))
                                  (if (typep entity 'stored-entity) (entity-id entity) ""))))))

;;; ------------------------------------------------------------------
;;; Rules and computed fields (client extension points)

(defclass rule ()
  ((name :initarg :name :reader rule-name)
   (function :initarg :function :reader rule-function)
   (field :initarg :field :reader rule-field)
   (message :initarg :message :reader rule-message)
   (source :initarg :source :reader rule-source)
   (module :initarg :module :initform "core" :reader rule-module)
   (location :initarg :location :initform nil :reader rule-location)))

(defparameter +invalid-rule-text+ "is invalid"
  "The error of a record a rule refuses, when the rule gives no message.")

(note-text +invalid-rule-text+ nil "core" "entity.lisp")

(defmacro define-rule (name (entity var) (&key field message) &body body)
  "Define validation rule NAME on ENTITY.  BODY returns true when VAR is valid;
otherwise the write is rejected with invalid_input on FIELD with MESSAGE, a
literal text in the definer's source language, translated where it is shown.
Rules run on every insert and update of the entity, whichever operation writes."
  (check-written-text (format nil "Rule ~(~a~)" name) :message message)
  (let ((source (current-definition-source))
        (module (current-definition-module))
        (location (current-source-location))
        (place (definition-place)))
    `(progn
       ,@(when message `((load-time-value (note-text ,message nil ,module ,place))))
       (defun ,name (,var) ,@body)
       (register-rule ',entity ',name #',name
                      :field ,(if field (json-name-of field) nil)
                      :message ,(or message '+invalid-rule-text+)
                      :source ,source :module ,module :location ,location)
       ',name)))

(defun register-rule (entity name function &key field message source (module "core") location)
  (let ((class (find-entity-class entity)))
    ;; Rules run when a stored record is inserted or saved; an embedded entity
    ;; (an order line) is never written on its own, so a rule on it would never run.
    (when (entity-embedded-p class)
      (extension-error "Rule ~a is attached to ~a, which runs no rules (it is embedded in another entity)"
                       name (entity-json-name class)))
    (setf (entity-rules class)
          (append (remove name (entity-rules class) :key #'rule-name)
                  (list (make-instance 'rule :name name :function function :field field
                                             :message message :source source :module module
                                             :location location))))
    name))

(defclass computed-field ()
  ((name :initarg :name :reader computed-field-name)
   (json-name :initarg :json-name :reader computed-field-json-name)
   (function :initarg :function :reader computed-field-function)
   (field-type :initarg :field-type :reader computed-field-type-designator)
   (label :initarg :label :reader computed-field-label)
   (source :initarg :source :reader computed-field-source)
   (module :initarg :module :initform "core" :reader computed-field-module)
   (location :initarg :location :initform nil :reader computed-field-location)))

(defun computed-field-type (cf) (parse-field-type (computed-field-type-designator cf)))

(defmacro define-computed-field (entity name (var) (&key (type 'string) label) &body body)
  "Define a computed (not stored) field NAME on ENTITY.  Expands into a DEFUN
named ENTITY-NAME and a registration; the value appears in the entity's JSON
and in registry_describe."
  (let ((source (current-definition-source))
        (module (current-definition-module))
        (location (current-source-location))
        (fn (symbolicate entity "-" name)))
    `(progn
       (defun ,fn (,var) ,@body)
       (register-computed-field ',entity ',name #',fn
                                :type ',type :label ,(or label (json-name-of name)) :source ,source
                                :module ,module :location ,location)
       ',fn)))

(defun register-computed-field (entity name function &key type label source (module "core") location)
  (let* ((class (find-entity-class entity))
         (json (json-name-of name))
         (other (find json (entity-computed-fields class) :key #'computed-field-json-name :test #'string=)))
    (when (find-field class json)
      (extension-error "Computed field ~a would shadow the stored field ~a of ~a" name json (entity-json-name class)))
    (when (and other (not (eq (computed-field-name other) name)))
      (extension-error "Computed field ~a would replace ~a on ~a" name (computed-field-name other) (entity-json-name class)))
    (setf (entity-computed-fields class)
          (append (remove name (entity-computed-fields class) :key #'computed-field-name)
                  (list (make-instance 'computed-field :name name :json-name (json-name-of name)
                                                       :function function :field-type type
                                                       :label label :source source :module module
                                                       :location location))))
    name))

;;; ------------------------------------------------------------------
;;; Instances: construction, JSON, validation

(defun make-entity (name &rest initargs)
  (apply #'make-instance name initargs))

(defun field-value (entity field)
  (slot-value entity (field-name field)))

(defun (setf field-value) (value entity field)
  (setf (slot-value entity (field-name field)) value))

(declaim (ftype (function (t t) *) entity-readable-p))

(defun field-json-value (record field)
  "FIELD of RECORD as JSON: \"***\" for a secret field, so no projection shows a credential."
  (if (field-secret-p field)
      "***"
      (type->json (field-type field) (field-value record field))))

(defgeneric entity->json (entity)
  (:documentation "The public JSON projection: every field plus computed fields."))

(defmethod entity->json ((entity entity))
  (let* ((class (class-of entity))
         (object (jobj)))
    (dolist (field (entity-fields class))
      (setf (gethash (field-json-name field) object) (field-json-value entity field)))
    (dolist (cf (entity-computed-fields class))
      (setf (gethash (computed-field-json-name cf) object)
            (type->json (computed-field-type cf)
                        (if (eq :client (computed-field-source cf))
                            (call-with-core-fields-unchanged
                             (list entity) (format nil "Computed field ~a" (computed-field-json-name cf))
                             (lambda () (funcall (computed-field-function cf) entity)))
                            (funcall (computed-field-function cf) entity)))))
    object))

(defun entity->storage-json (entity)
  "JSON of the stored fields only (for embedding inside a parent's column)."
  (let ((object (jobj)))
    (dolist (field (entity-stored-fields (class-of entity)) object)
      (setf (gethash (field-json-name field) object)
            (type->db-json (field-type field) (field-value entity field))))))

(defun type->db-json (type value)
  "Like TYPE->JSON but embedded lists keep storage form."
  (if (typep type 'list-type)
      (jarr (mapcar (lambda (x) (if (typep x 'entity) (entity->storage-json x) (type->json (list-element type) x)))
                    value))
      (type->json type value)))

(defun storage-json->entity (class-name object)
  (let ((instance (make-instance class-name)))
    (dolist (field (entity-stored-fields (class-of instance)) instance)
      (multiple-value-bind (value present) (jget object (field-json-name field))
        (when present
          (setf (field-value instance field) (db-json->type (field-type field) value)))))))

(defun db-json->type (type value)
  (cond ((json-null-p value) nil)
        ((typep type 'timestamp-type) (parse-rfc3339 value))
        ((typep type 'decimal-type) (if (integerp value) value (round-decimal value (decimal-scale type))))
        ((typep type 'boolean-type) (and value t))
        ((typep type 'list-type)
         (let ((element (list-element type)))
           (map 'list (lambda (x) (if (symbolp element)
                                      (storage-json->entity element x)
                                      (db-json->type element x)))
                value)))
        (t value)))

(defun copy-entity (entity)
  (let ((copy (make-instance (class-of entity))))
    (dolist (field (entity-fields (class-of entity)) copy)
      (setf (field-value copy field) (field-value entity field)))))

;;; Input -> instance.  Unknown keys and every field error are reported together.

(defun input->entity (class-name object path &key (fields nil fields-p) (allowed-extra '()))
  "Build an instance of CLASS-NAME from the JSON OBJECT, validating every input field."
  (let* ((class (find-entity-class class-name))
         (fields (if fields-p fields (entity-input-fields class)))
         (instance (make-instance class-name)))
    (if (not (hash-table-p object))
        (input-error (if (string= path "") "input" path) "must be an object")
        (progn
          (unknown-names-errors
           path (remove-if (lambda (key)
                             (or (find key fields :key #'field-json-name :test #'string=)
                                 (member key allowed-extra :test #'string=)))
                           (jkeys object)))
          (dolist (field fields)
            (let ((field-path (join-path path (field-json-name field))))
              (multiple-value-bind (value present) (jget object (field-json-name field))
                (if (or (not present) (json-null-p value))
                    (when (field-required-p field)
                      (input-error field-path "must be filled in"))
                    (let* ((before (length *input-errors*))
                           (coerced (coerce-input (field-type field) value field-path)))
                      (when (= before (length *input-errors*))
                        (setf (field-value instance field) coerced)))))))))
    instance))

(defun entity-input-schema (class)
  "JSON Schema (object) for the input fields of CLASS."
  (let ((properties (jobj))
        (required '()))
    (dolist (field (entity-input-fields class))
      (let ((schema (type-json-schema (field-type field))))
        (setf (gethash "description" schema) (or (field-description field) (field-label field)))
        (setf (gethash (field-json-name field) properties) schema)
        (when (field-required-p field) (push (field-json-name field) required))))
    (jobj "type" "object"
          "properties" properties
          "required" (jarr (reverse required))
          "additionalProperties" nil)))

(defun validate-entity (entity)
  "Check required fields and every registered rule; signal invalid_input."
  (let* ((class (class-of entity))
         (errors '()))
    (dolist (field (entity-fields class))
      (when (and (field-required-p field)
                 (not (typep (field-type field) 'boolean-type))
                 (null (field-value entity field)))
        (push (cons (field-json-name field) (deferred-tr "must be filled in")) errors)))
    (loop for rule in (entity-rules class)
          for order from 1
          do (unless (with-step (:rule :name (json-name-of (rule-name rule)) :source (rule-source rule)
                                 :order order :detail (entity-json-name class))
                       (if (eq :client (rule-source rule))
                           (call-with-core-fields-unchanged
                            (list entity) (format nil "Rule ~a" (json-name-of (rule-name rule)))
                            (lambda () (funcall (rule-function rule) entity)))
                           (funcall (rule-function rule) entity)))
               (push (cons (or (rule-field rule) (entity-json-name class))
                           (make-text (rule-message rule) '()))
                     errors)))
    (when errors (fail-fields (reverse errors)))
    entity))

;;; Lists of embedded entities (methods for LIST-TYPE that need entities)

(defun list-element-entity-p (type)
  (symbolp (list-element type)))

(defmethod type-json-schema ((type list-type))
  (jobj "type" "array"
        "minItems" (list-min-items type)
        "maxItems" (list-max-items type)
        "items" (if (list-element-entity-p type)
                    (entity-input-schema (find-entity-class (list-element type)))
                    (type-json-schema (list-element type)))))

(defmethod coerce-input ((type list-type) value path)
  (cond ((not (json-array-p value)) (input-error path "must be a list"))
        ((> (length value) (list-max-items type))
         (input-error path "can have at most ~d items" (list-max-items type)))
        ((< (length value) (list-min-items type))
         (input-error path "must have at least ~d item~:p" (list-min-items type)))
        (t (loop for item across value
                 for i from 0
                 for item-path = (format nil "~a[~d]" path i)
                 collect (if (list-element-entity-p type)
                             (input->entity (list-element type) item item-path)
                             (coerce-input (list-element type) item item-path))))))

(defmethod type->json ((type list-type) value)
  (jarr (mapcar (lambda (x) (if (typep x 'entity) (entity->json x) (type->json (list-element type) x)))
                value)))

(defmethod type->db ((type list-type) value)
  (to-json-string (type->db-json type value)))

(defmethod db->type ((type list-type) value)
  (if (null value) nil (db-json->type type (parse-json value))))
