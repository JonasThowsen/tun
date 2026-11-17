;;;; core/outputs.lisp -- what an operation declares it returns
;;;; (spec/core.md 3.11): the forms of a :RETURNS declaration, the JSON
;;;; Schema each stands for, which registry_describe shows and the
;;;; TypeScript module types (spec/typescript.md 3.3), and the check of a
;;;; result against it under the test clock.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The forms

(defun entity-name-form-p (form)
  "True for a form that names an entity: a symbol that is no keyword."
  (and form (symbolp form) (not (keywordp form))))

(defun check-output-form (form operation)
  "Refuse FORM, the :RETURNS of OPERATION's definition, unless it is an
output: ENTITY, (:PAGE ENTITY) or (:OBJECT (KEY OUTPUT [:OPTIONAL T]) ...)
with each key once, whose keys may also be (:LIST OUTPUT) or (:VALUE TYPE)
of a field type: a result is a JSON object (spec/core.md 3.11).  Called
when the definition is compiled; an entity is looked up only when the
output is used."
  (labels ((refuse (control &rest args)
             (error "Operation ~s: :returns ~s ~?" operation form control args))
           (check (part)
             (cond ((entity-name-form-p part))
                   ((not (consp part))
                    (refuse "is not an output: ~s is neither an entity nor (:page E), (:list X), ~
                             (:object (KEY X) ...) or (:value TYPE)" part))
                   (t (case (first part)
                        (:page (unless (and (= 2 (length part)) (entity-name-form-p (second part)))
                                 (refuse "has ~s, where (:page ENTITY) is meant" part)))
                        (:list (unless (= 2 (length part))
                                 (refuse "has ~s, where (:list OUTPUT) is meant" part))
                               (check (second part)))
                        (:object (check-object part))
                        (:value (unless (= 2 (length part))
                                  (refuse "has ~s, where (:value TYPE) is meant" part))
                                (handler-case (parse-field-type (second part))
                                  (error (e)
                                    (refuse "has ~s, which is no field type: ~a" (second part) e))))
                        (t (refuse "has ~s, which is no output" part))))))
           (check-object (part)
             (let ((names '()))
               (dolist (entry (rest part))
                 (unless (and (consp entry) (entity-name-form-p (first entry)) (consp (rest entry))
                              (member (cddr entry) '(() (:optional t) (:optional nil))
                                      :test #'equal))
                   (refuse "has ~s, where (KEY OUTPUT [:optional t]) is meant" entry))
                 (let ((name (json-name-of (first entry))))
                   (when (member name names :test #'string=)
                     (refuse "names the key ~a twice" name))
                   (push name names))
                 (check (second entry))))))
    (when (and (consp form) (member (first form) '(:list :value)))
      (refuse "is not an object: a result is a record, a page or an object, and ~
               (:list X) and (:value TYPE) are the values of its keys"))
    (check form)
    form))

(defun output-entity-class (name)
  "The entity class an output's NAME names, or an error saying it names none."
  (or (find-entity-class name nil)
      (error "An operation's :returns names ~s, which is no entity" name)))

;;; ------------------------------------------------------------------
;;; Their JSON Schema

(defgeneric type-output-schema (type)
  (:documentation "The JSON Schema of a value of the field type TYPE as TYPE->JSON
writes it: the schema of its input, unless it writes something else.")
  (:method ((type field-type))
    (type-json-schema type)))

(defmethod type-output-schema ((type list-type))
  (jobj "type" "array"
        "items" (if (list-element-entity-p type)
                    (entity-output-schema (find-entity-class (list-element type)))
                    (type-output-schema (list-element type)))))

(defun nullable-schema (schema)
  "SCHEMA, or null."
  (jobj "anyOf" (jarr (list schema (jobj "type" "null")))))

(defun never-null-type-p (type)
  "True for a field type whose TYPE->JSON never writes null: a boolean is
false, a list or a field of files empty."
  (typep type '(or boolean-type list-type files-type)))

(defun entity-output-schema (class)
  "The JSON Schema of a record of the entity CLASS as ENTITY->JSON gives it:
every field and computed field, always present.  A required field's value
is never null, nor a stored record's id, a boolean's or a list's; any other
may be; a secret field reads \"***\"."
  (let ((properties (jobj))
        (keys '()))
    (flet ((add (name type required secret)
             (setf (gethash name properties)
                   (cond (secret (jobj "type" "string"))
                         ((or required (never-null-type-p type)) (type-output-schema type))
                         (t (nullable-schema (type-output-schema type)))))
             (push name keys)))
      (dolist (field (entity-fields class))
        ;; A stored record always has its id.
        (add (field-json-name field) (field-type field)
             (or (field-required-p field)
                 (and (string= (field-json-name field) "id") (not (entity-embedded-p class))))
             (field-secret-p field)))
      (dolist (computed (entity-computed-fields class))
        (add (computed-field-json-name computed) (computed-field-type computed) nil nil)))
    (jobj "type" "object"
          "title" (entity-json-name class)
          "properties" properties
          "required" (jarr (reverse keys)))))

(defun output-schema (form)
  "The JSON Schema of the output FORM declares (CHECK-OUTPUT-FORM)."
  (if (symbolp form)
      (entity-output-schema (output-entity-class form))
      (ecase (first form)
        (:page (jobj "type" "object"
                     "properties" (jobj "items" (jobj "type" "array"
                                                      "items" (output-schema (second form)))
                                        "returned" (jobj "type" "integer")
                                        "has_more" (jobj "type" "boolean"))
                     "required" (jarr (list "items" "returned" "has_more"))))
        (:list (jobj "type" "array" "items" (output-schema (second form))))
        (:object (let ((properties (jobj))
                       (required '()))
                   (dolist (entry (rest form))
                     (destructuring-bind (key output &key optional) entry
                       (let ((name (json-name-of key))
                             (schema (output-schema output)))
                         (setf (gethash name properties)
                               (if optional (nullable-schema schema) schema))
                         (unless optional (push name required)))))
                   (jobj "type" "object" "properties" properties
                         "required" (jarr (reverse required)))))
        (:value (type-output-schema (parse-field-type (second form)))))))

;;; ------------------------------------------------------------------
;;; The check of a result (spec/core.md 3.11)

(defun json-type-fits-p (type value)
  "True when VALUE, JSON as Tun builds it, is of the JSON Schema TYPE."
  (cond ((string= type "string") (stringp value))
        ((string= type "integer") (integerp value))
        ((string= type "number") (realp value))
        ((string= type "boolean") (member value '(t nil)))
        ((string= type "array") (json-array-p value))
        ((string= type "object") (hash-table-p value))
        ((string= type "null") (json-null-p value))
        (t t)))

(defun child-path (path key)
  (if (string= path "") key (format nil "~a.~a" path key)))

(defun schema-mismatch (schema value &optional (path ""))
  "NIL when VALUE fits SCHEMA, an output's JSON Schema (OUTPUT-SCHEMA);
else values the path where it first does not, \"\" for the whole value,
and what was expected there."
  (let ((forms (jget schema "anyOf"))
        (type (jget schema "type"))
        (choices (jget schema "enum")))
    (cond (forms
           (if (some (lambda (form) (null (schema-mismatch form value path))) forms)
               nil
               (schema-mismatch (aref forms 0) value path)))
          ((and type (not (json-type-fits-p type value)))
           (values path (format nil "a value of type ~a, not ~a" type (to-json-string value))))
          ((and choices (not (find value choices :test #'equal)))
           (values path (format nil "one of ~{~a~^, ~}, not ~a" (coerce choices 'list)
                                (to-json-string value))))
          ((and (equal type "array") (jget schema "items"))
           (loop for item across value
                 for index from 0
                 do (multiple-value-bind (where expected)
                        (schema-mismatch (jget schema "items") item (format nil "~a[~d]" path index))
                      (when where (return (values where expected))))))
          ((equal type "object")
           (let ((properties (jget schema "properties")))
             (dolist (key (coerce (or (jget schema "required") #()) 'list))
               (multiple-value-bind (item present) (jget value key)
                 (declare (ignore item))
                 (unless present
                   (return-from schema-mismatch (values (child-path path key) "a value")))))
             (when properties
               (maphash (lambda (key property)
                          (multiple-value-bind (item present) (jget value key)
                            (when present
                              (multiple-value-bind (where expected)
                                  (schema-mismatch property item (child-path path key))
                                (when where
                                  (return-from schema-mismatch (values where expected)))))))
                        properties))
             nil))
          (t nil))))

(defun check-declared-output (op result)
  "Signal an error when RESULT, the JSON OP's call answers, does not fit the
output OP declares: under the test clock every call through CALL-TOOL is
checked (spec/core.md 3.11).  A request for confirmation is not."
  (unless (and (operation-confirm-p op) (hash-table-p result)
               (eq t (jget result "confirmation_required")))
    (multiple-value-bind (where expected)
        (schema-mismatch (output-schema (operation-returns op)) result)
      (when where
        (error "~a answered what its :returns does not say: at ~a, ~a was expected"
               (operation-tool op) (if (string= where "") "the result" where) expected)))))
