;;;; core/types.lisp -- field types.
;;;;
;;;; A field type is a CLOS object built from a designator such as
;;;; (STRING :MIN 1 :MAX 120) or (ENUM "private" "business").  One type object
;;;; yields the JSON Schema fragment, the input coercion (with its error
;;;; messages, written where they are shown), the JSON and database
;;;; encodings, the SQL column type and the Lisp type used for the slot's
;;;; :TYPE declaration.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defconstant +max-safe-integer+ 9007199254740991)

;;; Input errors are collected per parse, so one call reports every bad field.
(defvar *input-errors* nil)

(defun input-error (path control &rest args)
  "Record an input error for PATH, its message CONTROL formatted with ARGS
and written where it is shown (spec/i18n.md 3.1). Returns NIL."
  (push (cons path (make-text control args)) *input-errors*)
  nil)

(defparameter +most-shown-name+ 100
  "The most characters of a name a caller sent that an error repeats.")

(defparameter +most-unknown-names+ 20
  "The most unknown names one input's errors list; the rest are counted.")

(defun shown-name (name)
  "NAME, sent by a caller, as an error repeats it: at most +MOST-SHOWN-NAME+
characters, then …."
  (if (> (length name) +most-shown-name+)
      (concatenate 'string (subseq name 0 +most-shown-name+) "…")
      name))

(defun unknown-names-errors (prefix names)
  "Input errors for NAMES, keys under PREFIX that are not known fields: each
of the first +MOST-UNKNOWN-NAMES+ at its name, cut by SHOWN-NAME, and the
rest counted under PREFIX."
  (loop for name in names
        for i from 0
        while (< i +most-unknown-names+)
        do (input-error (join-path prefix (shown-name name)) "is not a known field"))
  (when (> (length names) +most-unknown-names+)
    (input-error (if (blank-p prefix) "input" prefix) "has ~d more unknown fields"
                 (- (length names) +most-unknown-names+))))

(defmacro collecting-input-errors (&body body)
  "Run BODY collecting INPUT-ERRORs; signal invalid_input if any were recorded."
  (let ((result (gensym "RESULT")))
    `(let* ((*input-errors* nil)
            (,result (progn ,@body)))
       (when *input-errors*
         (fail-fields (reverse *input-errors*)))
       ,result)))

(defun join-path (prefix name)
  (if (or (null prefix) (string= prefix "")) name (format nil "~a.~a" prefix name)))

;;; ------------------------------------------------------------------
;;; Protocol

(defclass field-type ()
  ((designator :initarg :designator :reader field-type-designator)))

(defgeneric type-name (type)
  (:documentation "Short type name used by registry_describe."))
(defgeneric type-json-schema (type)
  (:documentation "JSON Schema fragment (a JSON object) for input of this type."))
(defgeneric coerce-input (type value path)
  (:documentation "Validate and convert the JSON VALUE. On failure record an INPUT-ERROR and return NIL."))
(defgeneric type->json (type value)
  (:documentation "Convert a Lisp slot VALUE to its JSON value."))
(defgeneric type->db (type value))
(defgeneric db->type (type value))
(defgeneric type-sql (type))
(defgeneric type-lisp-type (type))

;;; Defaults shared by most scalar types.
(defmethod type->json ((type field-type) value) (if (null value) :null value))
(defmethod type->db ((type field-type) value) value)
(defmethod db->type ((type field-type) value) value)
(defmethod type-sql ((type field-type)) "TEXT")
(defmethod type-lisp-type ((type field-type)) t)

;;; ------------------------------------------------------------------
;;; Strings

(defparameter +invalid-format-text+ "has an invalid format"
  "The error of a string that does not match its pattern, when its type gives
no message of its own.")

(defparameter +invalid-email-text+ "must be a valid email address (name@example.com)"
  "The error of an email that is not one.")

;;; Noted for the checks of spec/i18n.md 3.7, as a refusal's literal is.
(note-text +invalid-format-text+ nil "core" "types.lisp")
(note-text +invalid-email-text+ nil "core" "types.lisp")

(defclass string-type (field-type)
  ((min :initarg :min :initform 0 :reader string-min)
   (max :initarg :max :initform 1000 :reader string-max)
   (pattern :initarg :pattern :initform nil :reader string-pattern)
   (pattern-message :initarg :pattern-message :initform +invalid-format-text+
                    :reader string-pattern-message
                    :documentation "The error of a value the pattern refuses, in its
definer's source language: translated where it is shown.")
   (trim :initarg :trim :initform t :reader string-trim-p)))

(defmethod type-name ((type string-type)) "string")
(defmethod type-lisp-type ((type string-type)) '(or null string))

(defmethod type-json-schema ((type string-type))
  (let ((schema (jobj "type" "string" "maxLength" (string-max type))))
    (when (plusp (string-min type)) (setf (gethash "minLength" schema) (string-min type)))
    (when (string-pattern type) (setf (gethash "pattern" schema) (string-pattern type)))
    schema))

(defmethod coerce-input ((type string-type) value path)
  (cond ((not (stringp value)) (input-error path "must be text"))
        (t (let ((s (if (string-trim-p type) (trim value) value)))
             (cond ((and (zerop (length s)) (zerop (string-min type)) (string-trim-p type))
                    nil)                ; an empty (trimmed) optional string means "no value"
                   ((< (length s) (string-min type))
                    (if (zerop (length s))
                        (input-error path "must be filled in")
                        (input-error path "must be at least ~d characters" (string-min type))))
                   ((> (length s) (string-max type))
                    (input-error path "cannot be longer than ~d characters" (string-max type)))
                   ((and (string-pattern type) (plusp (length s))
                         (not (cl-ppcre:scan (string-pattern type) s)))
                    (input-error path (string-pattern-message type)))
                   (t (coerce s 'simple-string)))))))

(defclass email-type (string-type) ()
  (:default-initargs :min 1 :max 160
                     :pattern "^[^@\\s]+@[^@\\s.]+(\\.[^@\\s.]+)+$"
                     :pattern-message +invalid-email-text+))

(defmethod type-name ((type email-type)) "email")
(defmethod type-json-schema ((type email-type))
  (let ((schema (call-next-method)))
    (setf (gethash "format" schema) "email")
    schema))

;;; ------------------------------------------------------------------
;;; Integers and booleans

(defclass integer-type (field-type)
  ((min :initarg :min :initform (- +max-safe-integer+) :reader integer-min)
   (max :initarg :max :initform +max-safe-integer+ :reader integer-max)))

(defmethod type-name ((type integer-type)) "integer")
(defmethod type-sql ((type integer-type)) "INTEGER")
(defmethod type-lisp-type ((type integer-type)) '(or null integer))
(defmethod type-json-schema ((type integer-type))
  (let ((schema (jobj "type" "integer")))
    (when (> (integer-min type) (- +max-safe-integer+)) (setf (gethash "minimum" schema) (integer-min type)))
    (when (< (integer-max type) +max-safe-integer+) (setf (gethash "maximum" schema) (integer-max type)))
    schema))

(defparameter +most-number-text+ 40
  "The most characters of a number given as text, such as a form's field,
that is parsed (core.md §7.5): more than any number field holds.")

(defun long-number-text-p (value)
  "True when VALUE is text too long to be parsed as a number."
  (and (stringp value) (> (length value) +most-number-text+)))

(defmethod coerce-input ((type integer-type) value path)
  (cond ((long-number-text-p value)
         (input-error path "is too long for a number: at most ~d characters" +most-number-text+))
        ((not (integerp value)) (input-error path "must be a whole number"))
        ((< value (integer-min type)) (input-error path "must be at least ~d" (integer-min type)))
        ((> value (integer-max type)) (input-error path "cannot be more than ~d" (integer-max type)))
        (t value)))

;;; Money: an integer count of the tenant's currency's minor units
;;; (spec/i18n.md 5.2).  JSON carries the integer; a page writes and reads
;;; it in the tenant's language (core/formats.lisp).

(defclass money-type (integer-type) ())

(defmethod type-name ((type money-type)) "money")

(defvar *written-amounts* nil
  "True while a page's form is the input: an amount given as text is then
read as a person writes it in the tenant's language (spec/i18n.md 5.4).
Over MCP and the API an amount is the integer.")

(defmethod coerce-input ((type money-type) value path)
  ;; Text too long for a number is refused as an integer's is, unread.
  (if (and *written-amounts* (stringp value) (not (long-number-text-p value)))
      (multiple-value-bind (amount problem) (read-money-text value)
        (if amount
            (call-next-method type amount path)
            (progn (push (cons path problem) *input-errors*) nil)))
      (call-next-method)))

(defgeneric money-schema-description (type)
  (:documentation "What a money field's JSON Schema says about its unit: the
tenant's currency and its minor digits (core/formats.lisp)."))

(defmethod type-json-schema ((type money-type))
  (let ((schema (call-next-method)))
    (setf (gethash "description" schema) (money-schema-description type))
    schema))

(defun money-name-p (json-name)
  "True when JSON-NAME, a field's or parameter's, ends _minor, as a money
field's must (spec/i18n.md 5.2)."
  (let ((suffix "_minor"))
    (and (> (length json-name) (length suffix))
         (string= suffix json-name :start2 (- (length json-name) (length suffix))))))

(defun check-money-name (designator json-name what)
  "Refuse the money type DESIGNATOR on a field or parameter whose JSON-NAME
does not end _minor, when the definition is compiled.  WHAT names the
definition.  It reads the designator alone, since a type class of the
definition's own file is not defined yet."
  (when (and (string= (designator-head designator) "MONEY") (not (money-name-p json-name)))
    (error "~a: the money field ~a must be named …_minor (spec/i18n.md 5.2)" what json-name)))

(defclass boolean-type (field-type) ())
(defmethod type-name ((type boolean-type)) "boolean")
(defmethod type-sql ((type boolean-type)) "INTEGER")
(defmethod type-lisp-type ((type boolean-type)) 'boolean)
(defmethod type-json-schema ((type boolean-type)) (jobj "type" "boolean"))
(defmethod coerce-input ((type boolean-type) value path)
  (cond ((eq value t) t)
        ((null value) nil)
        (t (input-error path "must be true or false"))))
(defmethod type->json ((type boolean-type) value) (json-bool value))
(defmethod type->db ((type boolean-type) value) (if value 1 0))
(defmethod db->type ((type boolean-type) value) (and value (not (eql value 0))))

;;; ------------------------------------------------------------------
;;; Decimals: exact, with at most SCALE decimals (a percentage such as 12.5).
;;; Held as a rational; JSON numbers in, JSON numbers out, TEXT in the store.

(defclass decimal-type (field-type)
  ((scale :initarg :scale :initform 2 :reader decimal-scale)))

(defmethod type-name ((type decimal-type)) "decimal")
;; NUMERIC affinity: SQLite stores the exact text form (DECIMAL-TEXT) as an
;; INTEGER when it is whole (a balance of 430 reads as 430 to any SQL client)
;; and as a REAL otherwise, keeping 15 significant digits: every value up to
;; 10^12 with three decimals (999999999999.999) reads back as written, and
;; DB->TYPE makes it exact again (core.md §2.1).  Columns an earlier
;; revision created as TEXT keep the text.
(defmethod type-sql ((type decimal-type)) "NUMERIC")
(defmethod type-lisp-type ((type decimal-type)) '(or null rational))
(defmethod type-json-schema ((type decimal-type))
  (jobj "type" "number" "multipleOf" (/ 1 (expt 10 (decimal-scale type)))))

(defun decimal-text->rational (text)
  "Decimal TEXT (430, -0.5, 123456.789; no exponent) as the exact rational."
  (let* ((text (string-trim " " text))
         (negative (and (plusp (length text)) (char= (char text 0) #\-)))
         (digits (remove #\. (string-left-trim "+-" text)))
         (dot (position #\. text))
         (decimals (if dot (- (length text) dot 1) 0)))
    (* (if negative -1 1) (/ (parse-integer digits) (expt 10 decimals)))))

(defun decimal-text (value scale)
  "VALUE (a real) as exact decimal text with at most SCALE fractional digits
and no trailing zeros: 430, -0.5, 123456.789.  Never through a float, which
keeps only part of the digits (core.md §2.1)."
  (let ((factor (expt 10 scale)))
    (multiple-value-bind (whole fraction) (floor (round (* (abs (rational value)) factor)) factor)
      (let ((sign (if (and (minusp value) (or (plusp whole) (plusp fraction))) "-" "")))
        (if (zerop fraction)
            (format nil "~a~d" sign whole)
            (format nil "~a~d.~a" sign whole (string-right-trim "0" (format nil "~v,'0d" scale fraction))))))))

(defun json-number->rational (value)
  "VALUE (an integer or a float from JSON) as the rational it was written as: a
double is read as its shortest decimal form (999999999999.999), not as the
binary fraction nearest to it, nor as the simplest rational near it."
  (if (rationalp value)
      value
      (decimal-text->rational (let ((*read-default-float-format* (if (typep value 'double-float) 'double-float 'single-float)))
                                (format nil "~f" value)))))

(defmethod coerce-input ((type decimal-type) value path)
  (if (not (realp value))
      (if (long-number-text-p value)
          (input-error path "is too long for a number: at most ~d characters" +most-number-text+)
          (input-error path "must be a number"))
      (let ((r (json-number->rational value)))
        (if (integerp (* r (expt 10 (decimal-scale type))))
            r
            (input-error path "can have at most ~d decimals" (decimal-scale type))))))

(defmethod type->json ((type decimal-type) value)
  (cond ((null value) :null)
        ((integerp value) value)
        (t (float value 1d0))))

(defmethod type->db ((type decimal-type) value)
  (and value (decimal-text value (decimal-scale type))))

(defun round-decimal (value scale)
  "VALUE (a real) as the rational with at most SCALE decimals nearest to it: a
float read back from a column with numeric affinity (an INTEGER column that
an earlier revision created) is exact again."
  (let ((factor (expt 10 scale)))
    (/ (round (* (rational value) factor)) factor)))

(defun quantity-json (value &optional (scale 3))
  "A quantity for JSON: an integer when whole, else a double of at most SCALE
decimals (the encoder prints the shortest form, e.g. 0.3)."
  (let ((r (round-decimal value scale)))
    (if (integerp r) r (float r 1d0))))

(defun format-quantity (value &optional (scale 3))
  "VALUE as text the way JSON shows it: 200, 0.3, 7.5."
  (let ((r (round-decimal value scale)))
    (if (integerp r)
        (format nil "~d" r)
        (let ((*read-default-float-format* 'double-float))
          (format nil "~f" (float r 1d0))))))

(defmethod db->type ((type decimal-type) value)
  (cond ((null value) nil)
        ((integerp value) value)
        ((realp value) (round-decimal value (decimal-scale type)))
        (t (decimal-text->rational value))))

;;; ------------------------------------------------------------------
;;; Enumerations

(defclass enum-type (field-type)
  ((choices :initarg :values :reader enum-values)))

(defmethod type-name ((type enum-type)) "enum")
(defmethod type-lisp-type ((type enum-type)) '(or null string))
(defmethod type-json-schema ((type enum-type))
  (jobj "type" "string" "enum" (jarr (enum-values type))))
(defmethod coerce-input ((type enum-type) value path)
  (if (and (stringp value) (member value (enum-values type) :test #'string=))
      (coerce value 'simple-string)
      (input-error path "must be one of: ~{~a~^, ~}" (enum-values type))))

;;; ------------------------------------------------------------------
;;; Dates and timestamps

(defclass date-type (field-type) ())
(defmethod type-name ((type date-type)) "date")
(defmethod type-lisp-type ((type date-type)) '(or null string))
(defmethod type-json-schema ((type date-type))
  (jobj "type" "string" "format" "date" "pattern" "^[0-9]{4}-[0-9]{2}-[0-9]{2}$"))
(defmethod coerce-input ((type date-type) value path)
  (if (valid-date-string-p value)
      (coerce value 'simple-string)
      (input-error path "must be a valid date in the form YYYY-MM-DD")))

(defclass timestamp-type (field-type) ())
(defmethod type-name ((type timestamp-type)) "timestamp")
(defmethod type-lisp-type ((type timestamp-type)) '(or null (integer 0)))
(defmethod type-json-schema ((type timestamp-type)) (jobj "type" "string" "format" "date-time"))
(defmethod coerce-input ((type timestamp-type) value path)
  (or (parse-rfc3339 value)
      (input-error path "must be a time in RFC 3339 format, such as 2026-03-01T09:00:00Z")))
(defmethod type->json ((type timestamp-type) value)
  (if value (format-rfc3339 value) :null))
(defmethod type->db ((type timestamp-type) value)
  (and value (format-rfc3339 value)))
(defmethod db->type ((type timestamp-type) value)
  (and value (parse-rfc3339 value)))

;;; ------------------------------------------------------------------
;;; Identifiers (opaque strings), optionally naming the referenced entity

(defclass id-type (field-type)
  ((references :initarg :references :initform nil :reader id-references)))
(defmethod type-name ((type id-type)) "id")
(defmethod type-lisp-type ((type id-type)) '(or null string))
(defmethod type-json-schema ((type id-type)) (jobj "type" "string" "minLength" 1 "maxLength" 64))
(defmethod coerce-input ((type id-type) value path)
  (if (and (stringp value) (< 0 (length value) 65))
      (coerce value 'simple-string)
      (input-error path "must be a valid identifier")))

;;; ------------------------------------------------------------------
;;; Opaque JSON

(defclass json-type (field-type) ())
(defmethod type-name ((type json-type)) "json")
(defmethod type-json-schema ((type json-type)) (jobj))
(defmethod coerce-input ((type json-type) value path)
  (declare (ignore path))
  value)
(defmethod type->json ((type json-type) value) (if (null value) :null value))
(defmethod type->db ((type json-type) value) (and value (to-json-string value)))
(defmethod db->type ((type json-type) value) (and value (parse-json value)))

;;; ------------------------------------------------------------------
;;; Lists: of scalar types, or of embedded entities (see entity.lisp)

(defclass list-type (field-type)
  ((element :initarg :element :reader list-element
            :documentation "A FIELD-TYPE, or a symbol naming an embedded entity class.")
   (min-items :initarg :min-items :initform 0 :reader list-min-items)
   (max-items :initarg :max-items :initform 200 :reader list-max-items)))

(defmethod type-name ((type list-type)) "list")
(defmethod type-lisp-type ((type list-type)) 'list)

;;; ------------------------------------------------------------------
;;; Files: an operation parameter that carries uploaded files (spec/files.md
;;; 4.1).  Only the class is here, so designators parse; decoding, checking
;;; and stripping a file are in src/files/, which adds the methods.

(defclass files-type (field-type)
  ((max-files :initarg :max :initform 10 :reader files-max)))

(defmethod initialize-instance :after ((type files-type) &key)
  (unless (typep (files-max type) '(integer 1 10))
    (error "(files :max ~s): the most files is an integer from 1 to 10" (files-max type))))

(defmethod type-name ((type files-type)) "files")
(defmethod type-lisp-type ((type files-type)) 'list)

(defun files-type-p (type)
  "True when TYPE, a field type, carries files."
  (typep type 'files-type))

;;; ------------------------------------------------------------------
;;; Designator parsing

(defun designator-head (designator)
  (symbol-name (if (consp designator) (first designator) designator)))

(defun parse-field-type (designator)
  "Build a FIELD-TYPE from DESIGNATOR. Symbols are matched by name, so client
packages need not import every type keyword."
  (let ((head (designator-head designator))
        (args (if (consp designator) (rest designator) nil)))
    (flet ((make (class &rest initargs)
             (apply #'make-instance class :designator designator initargs)))
      (cond ((string= head "STRING") (apply #'make 'string-type args))
            ((string= head "EMAIL") (apply #'make 'email-type args))
            ((string= head "INTEGER") (apply #'make 'integer-type args))
            ((string= head "MONEY") (apply #'make 'money-type args))
            ((string= head "DECIMAL") (apply #'make 'decimal-type args))
            ((string= head "BOOLEAN") (make 'boolean-type))
            ((string= head "ENUM") (make 'enum-type :values (copy-list args)))
            ((string= head "DATE") (make 'date-type))
            ((string= head "TIMESTAMP") (make 'timestamp-type))
            ((string= head "ID") (make 'id-type :references (first args)))
            ((string= head "JSON") (make 'json-type))
            ((string= head "FILES") (apply #'make 'files-type args))
            ((string= head "LIST-OF")
             (destructuring-bind (element &rest options) args
               (apply #'make 'list-type
                      :element (if (and (symbolp element) (embedded-entity-designator-p element))
                                   element
                                   (parse-field-type element))
                      options)))
            ((and (symbolp designator) (find-class designator nil)
                  (subtypep designator 'field-type))
             (make designator))
            (t (error "Unknown field type designator ~s" designator))))))

(defun embedded-entity-designator-p (symbol)
  "True when SYMBOL is not a scalar type name, i.e. it names an entity class."
  (not (member (symbol-name symbol)
               '("STRING" "EMAIL" "INTEGER" "MONEY" "DECIMAL" "BOOLEAN" "DATE" "TIMESTAMP" "ID"
                 "JSON" "FILES")
               :test #'string=)))
