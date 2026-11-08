;;;; tests/fuzz-inputs.lisp -- inputs made up from a tool's JSON input
;;;; schema for fuzzing (spec/testing.md 2): valid, edge and hostile values,
;;;; every choice made from a random state the caller seeds, and shrinking an
;;;; input that fails to the smallest one that still does.  The runner that
;;;; calls the tools with them is in tests/fuzzing.lisp.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Random choices

(defvar *fuzz-random-state* (sb-ext:seed-random-state 0)
  "The random state every choice of the generators is made from. A run binds
it to one of its own (MAKE-FUZZ-RANDOM-STATE), so the same seed makes the
same inputs.")

(defun make-fuzz-random-state (seed &rest parts)
  "A random state made from SEED, an integer, and PARTS, such as a tool's
name: the same for the same SEED and PARTS in every run, and another for
another tool, so a tool's inputs do not depend on the tools fuzzed before
it."
  (let ((digest (ironclad:digest-sequence
                 :sha256 (sb-ext:string-to-octets (format nil "~d~{/~a~}" seed parts)
                                                  :external-format :utf-8))))
    (sb-ext:seed-random-state (loop for i below 8 sum (ash (aref digest i) (* 8 i))))))

(defun below (n)
  "A random integer from 0 below N, a positive integer."
  (random n *fuzz-random-state*))

(defun chance (n)
  "True once in N times."
  (zerop (below n)))

(defun pick (choices)
  "One of CHOICES, a non-empty list."
  (nth (below (length choices)) choices))

(defun between (low high)
  "A random integer from LOW to HIGH, both included."
  (+ low (below (1+ (- high low)))))

;;; ------------------------------------------------------------------
;;; Reading a schema

(defun schema-shape (schema)
  "What SCHEMA, a JSON Schema object as Tun's types make them, describes:
:ENUM, :DATE, :TIMESTAMP, :EMAIL, :FILE-CONTENT (base64), :TEXT,
:INTEGER, :NUMBER, :BOOLEAN, :ARRAY, :OBJECT, or :ANY for {}, which takes
every JSON value."
  (let ((type (jget schema "type"))
        (format (jget schema "format")))
    (cond ((jget schema "enum") :enum)
          ((equal type "string")
           (cond ((equal format "date") :date)
                 ((equal format "date-time") :timestamp)
                 ((equal format "email") :email)
                 ((jget schema "contentEncoding") :file-content)
                 (t :text)))
          ((equal type "integer") :integer)
          ((equal type "number") :number)
          ((equal type "boolean") :boolean)
          ((equal type "array") :array)
          ((equal type "object") :object)
          (t :any))))

(defun schema-properties (schema)
  "The names of an object SCHEMA's properties, in order."
  (let ((properties (jget schema "properties")))
    (if (hash-table-p properties) (jkeys properties) '())))

(defun property-schema (schema name)
  (jget (jget schema "properties") name))

(defun required-properties (schema)
  (coerce (jget schema "required" #()) 'list))

(defun text-minimum (schema)
  (jget schema "minLength" 0))

(defun text-maximum (schema)
  (jget schema "maxLength" 1000))

(defconstant +largest-exact-integer+ (1- (expt 2 53))
  "The largest integer JSON carries exactly, and so the bound of an integer
schema that gives none.")

(defun integer-minimum (schema)
  (jget schema "minimum" (- +largest-exact-integer+)))

(defun integer-maximum (schema)
  (jget schema "maximum" +largest-exact-integer+))

(defun number-scale (schema)
  "How many decimals a number SCHEMA takes, from its multipleOf, 1/10^scale."
  (let ((step (jget schema "multipleOf" 1/100)))
    (round (log (/ 1 (rational step)) 10))))

(defun property-path (path name)
  "The path of property NAME inside the object at PATH: \"lines[].product_id\"."
  (if (string= path "") name (concatenate 'string path "." name)))

(defun item-path (path)
  "The path of an item of the array at PATH."
  (concatenate 'string path "[]"))

;;; ------------------------------------------------------------------
;;; Ids of records

(defstruct (record-ref (:constructor make-record-ref (entity index &optional newest)))
  "In a made-up input, the id of a record of ENTITY, an entity's class name:
the one inserted INDEXth, from 0, counted round the records there are, or,
when NEWEST, the INDEXth counted back from the one inserted last; an id that
names nothing when there are none. The id is read when the call is made
(RESOLVE-INPUT): a replay on a fresh database, whose ids are new, names the
same record."
  (entity nil :type symbol :read-only t)
  (index 0 :type (integer 0) :read-only t)
  (newest nil :type boolean :read-only t))

(defvar *references* nil
  "While inputs are made: a hash table from a property's path to the entity
whose ids it takes, or NIL.")

(defun referenced-entity (path)
  (and *references* (values (gethash path *references*))))

(defun missing-id (entity)
  "An id of the kind the records of ENTITY, a class name or NIL, have that
names none of them."
  (format nil "~a_fuzznothing" (if entity (entity-id-prefix (find-entity-class entity)) "id")))

;;; ------------------------------------------------------------------
;;; Texts

(defparameter +text-characters+
  "abcdefghijklmnopqrstuvwxyzæøåABCDEFGHIJKLMNOPQRSTUVWXYZÆØÅ0123456789"
  "The characters an ordinary made-up text is written with, besides spaces.")

(defun code-text (&rest parts)
  "A text of PARTS: strings, and integers standing for the character of
that code, such as a right-to-left mark."
  (apply #'concatenate 'string
         (mapcar (lambda (part) (if (integerp part) (string (code-char part)) part)) parts)))

(defparameter +edge-texts+
  (list "Ærlig øl på åsen" "Ελληνικά" "日本語のテキスト" "עברית" "العربية" "Русский текст"
        "😀" (code-text "👩" #x200D "👩" #x200D "👧") "🇳🇴"
        (code-text "e" #x301)                ; e and a combining acute accent
        (code-text "A" #x30A "se")           ; Åse with the ring combining
        (code-text #x200F "abc")             ; a right-to-left mark
        (code-text "abc" #x202E "def")       ; a right-to-left override
        (code-text "a" #x200B "b")           ; a zero-width space
        (code-text #xFEFF "abc"))            ; a byte order mark
  "Texts within every limit that are not plain: other scripts, emoji, and
combining, right-to-left and invisible marks.")

(defparameter +hostile-texts+
  (list "<script>alert(1)</script>" "<img src=x onerror=alert(1)>" "]]><x/>"
        "'; DROP TABLE customers; --" "\" OR \"1\"=\"1" "1' OR '1'='1" "%' AND 1=1 --"
        "{{7*7}}" "${7*7}" "%s%s%s%n" "../../../etc/passwd" "\\" "null" "NaN" "-0"
        (code-text "a" 0 "b") (code-text 0) (code-text 7) (code-text 27 "[31mred" 27 "[0m")
        (code-text "line" 13 10 "break") (code-text 8 127) (code-text #xFFFF) (code-text #x10FFFF))
  "Texts a caller may send to break something: markup, SQL fragments,
template and format directives, a path, and control characters and NUL.")

(defun text-of-length (length)
  "A made-up text of LENGTH characters with no space at either end."
  (let ((text (make-string length)))
    (dotimes (i length text)
      (setf (char text i)
            (if (and (< 0 i (1- length)) (chance 6))
                #\Space
                (char +text-characters+ (below (length +text-characters+))))))))

(defun fitted-text (text schema)
  "TEXT cut or lengthened to fit SCHEMA's lengths."
  (let ((low (text-minimum schema))
        (high (text-maximum schema)))
    (cond ((> (length text) high) (subseq text 0 high))
          ((< (length text) low)
           (concatenate 'string text (text-of-length (- low (length text)))))
          (t text))))

(defun valid-text (schema)
  "A made-up text within SCHEMA's lengths, and matching its pattern when
one of a few tries does."
  (let* ((low (max 1 (text-minimum schema)))
         (high (max low (min (text-maximum schema) 24)))
         (pattern (jget schema "pattern")))
    (if pattern
        (or (loop repeat 8
                  for text = (text-of-length (between low high))
                  when (cl-ppcre:scan pattern text) return text)
            (text-of-length low))
        (text-of-length (between low high)))))

(defun random-date ()
  (format nil "~4,'0d-~2,'0d-~2,'0d" (between 2000 2035) (between 1 12) (between 1 28)))

(defun random-timestamp ()
  (format nil "~aT~2,'0d:~2,'0d:~2,'0dZ" (random-date) (below 24) (below 60) (below 60)))

(defun random-email ()
  (format nil "~a@example.no" (string-downcase (text-of-length (between 1 12)))))

(defparameter +small-png-base64+
  (concatenate 'string "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk"
               "+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
  "A PNG of one pixel, in base64: the content of a valid file.")

;;; ------------------------------------------------------------------
;;; Values

(defun generate-value (schema &key (kind :valid) (path "") references
                                   (random-state *fuzz-random-state*))
  "A JSON value for SCHEMA, the JSON Schema of a tool's input or of a part
of one, of KIND: :VALID, within the schema; :EDGE, at its limits or not
plain; or :HOSTILE, what a caller may send to break the tool
(spec/testing.md 2). PATH is the value's place in the input, such as
\"lines[].product_id\", and REFERENCES a hash table from such a path to the
entity whose ids it takes: a valid id there is a RECORD-REF. Every choice is
made from RANDOM-STATE."
  (let ((*fuzz-random-state* random-state)
        (*references* (or references *references*)))
    (value-of-kind schema kind path)))

(defun value-of-kind (schema kind path)
  (ecase kind
    (:valid (valid-value schema path))
    (:edge (edge-value schema path))
    (:hostile (hostile-value schema path))))

(defun valid-value (schema path)
  "A value within SCHEMA."
  (let ((entity (referenced-entity path)))
    (if entity
        (make-record-ref entity (below 8))
        (ecase (schema-shape schema)
          (:enum (pick (coerce (jget schema "enum") 'list)))
          (:date (random-date))
          (:timestamp (random-timestamp))
          (:email (random-email))
          (:file-content +small-png-base64+)
          (:text (valid-text schema))
          (:integer (valid-integer schema))
          (:number (valid-number schema))
          (:boolean (pick '(t nil)))
          (:array (array-value schema path (between (jget schema "minItems" 0)
                                                    (max (jget schema "minItems" 0)
                                                         (min (jget schema "maxItems" 200) 3)))))
          (:object (object-value schema path :valid))
          (:any (any-json 2))))))

(defun valid-integer (schema)
  "An integer within SCHEMA's range, most often a small one."
  (let ((low (integer-minimum schema))
        (high (integer-maximum schema)))
    (if (<= low 0 high)
        (max low (min high (- (below 120) 20)))
        (+ low (below (1+ (min 100 (- high low))))))))

(defun valid-number (schema)
  "A number with no more decimals than SCHEMA takes, as JSON carries it."
  (let ((value (/ (- (below 200000) 100000) (expt 10 (number-scale schema)))))
    (if (integerp value) value (float value 1d0))))

(defun array-value (schema path count &optional (kind :valid))
  "An array of COUNT items of SCHEMA's items, each of KIND."
  (let ((items (jget schema "items" (jobj))))
    (jarr (loop repeat count collect (value-of-kind items kind (item-path path))))))

(defun object-value (schema path kind)
  "An object of SCHEMA: each required property, and each optional one half
the time. In an edge object most optional properties are there, and half of
all of them at an edge."
  (let ((object (jobj))
        (required (required-properties schema)))
    (dolist (name (schema-properties schema) object)
      (when (or (member name required :test #'string=)
                (if (eq kind :edge) (not (chance 4)) (chance 2)))
        (setf (gethash name object)
              (value-of-kind (property-schema schema name)
                             (if (and (eq kind :edge) (chance 2)) :edge :valid)
                             (property-path path name)))))))

(defun any-json (depth)
  "Any JSON value, nested no deeper than DEPTH."
  (case (below (if (plusp depth) 7 5))
    (0 :null)
    (1 (pick '(t nil)))
    (2 (- (below 2000) 1000))
    (3 (text-of-length (between 1 12)))
    (4 (pick (list "" 0 1.5d0 (jobj) (jarr '()))))
    (5 (jarr (loop repeat (below 3) collect (any-json (1- depth)))))
    (t (let ((object (jobj)))
         (dotimes (i (below 3) object)
           (setf (gethash (text-of-length (between 1 8)) object) (any-json (1- depth))))))))

;;; Edge values: within the schema, at its limits.

(defun edge-value (schema path)
  "A value within SCHEMA at one of its edges (spec/testing.md 2)."
  (let ((entity (referenced-entity path)))
    (if entity
        ;; Any record, another actor's among them.
        (make-record-ref entity (below 40))
        (ecase (schema-shape schema)
          (:enum (pick (coerce (jget schema "enum") 'list)))
          (:date (pick '("1970-01-01" "2000-02-29" "2024-02-29" "2026-03-29" "2026-10-25"
                         "1900-01-01" "9999-12-31")))
          (:timestamp (pick '("1970-01-01T00:00:00Z" "2026-03-29T01:30:00+01:00"
                              "2026-10-25T02:30:00+02:00" "2099-12-31T23:59:59.999Z"
                              "2026-11-07T12:00:00-12:00" "2026-11-07T12:00:00+14:00")))
          (:email (pick (list "a@b.no" "ærlig+filter@eksempel.no" "first.last@sub.example.co.uk"
                              (fitted-text (format nil "~a@example.no"
                                                   (make-string 150 :initial-element #\x))
                                           schema))))
          (:file-content +small-png-base64+)
          (:text (edge-text schema))
          (:integer (edge-integer schema))
          (:number (pick (list 0 (float (expt 10 (- (number-scale schema))) 1d0)
                               (- (float (expt 10 (- (number-scale schema))) 1d0))
                               999999999999 -999999999999)))
          (:boolean (pick '(t nil)))
          (:array (array-value schema path
                               (if (chance 2)
                                   (jget schema "minItems" 0)
                                   (jget schema "maxItems" 200))))
          (:object (object-value schema path :edge))
          (:any (pick (list (jobj) (jarr '()) "" 0 :null (any-json 4))))))))

(defun edge-text (schema)
  "The shortest or the longest text SCHEMA takes, or one not plain."
  (case (below 3)
    (0 (if (zerop (text-minimum schema))
           ""
           (text-of-length (text-minimum schema))))
    (1 (text-of-length (text-maximum schema)))
    (t (fitted-text (pick +edge-texts+) schema))))

(defun edge-integer (schema)
  (let ((low (integer-minimum schema))
        (high (integer-maximum schema)))
    (pick (remove-if-not (lambda (n) (<= low n high)) (list low high 0 1 -1 (1+ low) (1- high))))))

;;; Hostile values: what the schema refuses, or what a careless tool chokes on.

(defun hostile-value (schema path)
  "A value a caller may send for SCHEMA to break the tool: of the wrong JSON
type, null, a text one character too long or with control characters,
markup or SQL, a number beyond the range, a deep array or object, an id
that names nothing (spec/testing.md 2)."
  (let* ((shape (schema-shape schema))
         (entity (referenced-entity path))
         (families (append '(:wrong-type :null :text :deep)
                           (and entity '(:missing-record :missing-record))
                           (case shape
                             ((:text :email :enum :date :timestamp :file-content)
                              '(:too-long :too-short :text :malformed))
                             ((:integer :number) '(:beyond-range :beyond-range))
                             (:array '(:too-many :bad-items :bad-items))
                             (:object '(:bad-object :bad-object))))))
    (ecase (pick families)
      (:wrong-type (wrong-type-value shape))
      (:null :null)
      (:text (pick +hostile-texts+))
      (:deep (deep-value (between 8 70)))
      (:missing-record (missing-id entity))
      (:too-long (text-of-length (1+ (text-maximum schema))))
      (:too-short (if (> (text-minimum schema) 1) (text-of-length (1- (text-minimum schema))) ""))
      (:malformed (malformed-text shape))
      (:beyond-range (beyond-range-number schema))
      (:too-many (array-value schema path (1+ (min (jget schema "maxItems" 200) 300))))
      (:bad-items (let ((items (coerce (array-value schema path (between 1 3)) 'list)))
                    (setf (nth (below (length items)) items)
                          (hostile-value (jget schema "items" (jobj)) (item-path path)))
                    (jarr items)))
      (:bad-object (mutated-object (object-value schema path :valid) schema path)))))

(defun wrong-type-value (shape)
  "A JSON value of another type than SHAPE's."
  (pick (ecase shape
          ((:text :email :enum :date :timestamp :file-content)
           (list 42 -1 1.5d0 t nil (jarr '()) (jobj)))
          (:integer (list "12" 1.5d0 t nil (jarr '(1)) (jobj)))
          (:number (list "1.5" t nil (jarr '()) (jobj)))
          (:boolean (list "true" 0 1 :null (jarr '()) (jobj)))
          (:array (list "x" 1 t (jobj)))
          (:object (list "x" 1 t (jarr '())))
          (:any (list "x")))))

(defun malformed-text (shape)
  "A text of the form SHAPE wants, nearly: a date that is not one, an email
without its at sign."
  (pick (case shape
          (:date '("2026-02-30" "2026-13-01" "26-1-1" "2026-01-01T00:00:00Z" "2026/01/01"))
          (:timestamp '("2026-01-01" "2026-01-01T25:00:00Z" "2026-01-01T00:00:00+99:00"
                        "yesterday" "2026-01-01 00:00:00"))
          (:email '("no-at-sign" "a@b" "@example.no" "a@@example.no" "a b@example.no"))
          (:file-content '("not base64!" "" "iVBORw0KGgo=" "data:image/png;base64,iVBORw0KGgo="))
          (:enum '("" " " "DRAFT" "unknown"))
          (t '("")))))

(defun beyond-range-number (schema)
  "A number beyond SCHEMA's range or kind: past its least and greatest, past
what JSON carries exactly, a fraction for an integer."
  (pick (list (1+ (integer-maximum schema)) (1- (integer-minimum schema))
              (expt 2 53) (- (expt 2 53)) (expt 10 20) 1d308 -1d308 1.5d0 1d-300)))

(defun deep-value (depth)
  "An array or an object nested DEPTH deep."
  (let ((value (pick (list 1 "x" :null))))
    (if (chance 2)
        (dotimes (i depth value) (setf value (jarr (list value))))
        (dotimes (i depth value) (setf value (jobj "a" value))))))

(defparameter +unknown-property-names+
  (list "fuzz_unknown" "__proto__" "constructor" "Id" "id " "" "nøkkel" "$where"
        (make-string 300 :initial-element #\k))
  "Names of properties no tool knows.")

(defun mutated-object (object schema path)
  "OBJECT, made of SCHEMA, with one to three hostile changes: a property's
value made hostile, a required one left out or null, an unknown one added."
  (let ((names (schema-properties schema))
        (required (required-properties schema)))
    (dotimes (i (between 1 3) object)
      (ecase (pick '(:value :value :value :missing :null :unknown))
        (:value (when names
                  (let ((name (pick names)))
                    (setf (gethash name object)
                          (hostile-value (property-schema schema name)
                                         (property-path path name))))))
        (:missing (when required (remhash (pick required) object)))
        (:null (when required (setf (gethash (pick required) object) :null)))
        (:unknown (setf (gethash (pick +unknown-property-names+) object) (any-json 1)))))))

;;; ------------------------------------------------------------------
;;; Inputs

(defun generate-input (schema &key kind references (random-state *fuzz-random-state*))
  "A tool's input made up for SCHEMA, its JSON input schema
(OPERATION-INPUT-SCHEMA), and REFERENCES, as GENERATE-VALUE takes them. KIND
is :VALID, :EDGE or :HOSTILE (a valid input changed in one to three ways),
chosen at random when not given. Values the input, a JSON object whose ids
of records are RECORD-REFs, and its kind."
  (let* ((*fuzz-random-state* random-state)
         (*references* references)
         (kind (or kind (pick '(:valid :valid :edge :edge :hostile :hostile :hostile)))))
    (values (ecase kind
              ((:valid :edge) (object-value schema "" kind))
              (:hostile (mutated-object (object-value schema "" :valid) schema "")))
            kind)))

(defun resolve-input (value function)
  "A copy of VALUE, a made-up input or a part of one, with each RECORD-REF
replaced by what FUNCTION, of the ref, returns: the id it names."
  (cond ((record-ref-p value) (funcall function value))
        ((hash-table-p value)
         (let ((copy (make-hash-table :test 'equal)))
           (maphash (lambda (key item) (setf (gethash key copy) (resolve-input item function)))
                    value)
           copy))
        ((json-array-p value) (map 'vector (lambda (item) (resolve-input item function)) value))
        (t value)))

;;; ------------------------------------------------------------------
;;; Shrinking

(defun copy-object (object)
  (let ((copy (make-hash-table :test 'equal)))
    (maphash (lambda (key value) (setf (gethash key copy) value)) object)
    copy))

(defun map-simpler-texts (function text)
  "Call FUNCTION with each text simpler than TEXT: the empty one, then TEXT
without one piece of it, the pieces halving in length down to one
character."
  (let ((length (length text)))
    (when (plusp length)
      (funcall function "")
      (loop for size = (ceiling length 2) then (ceiling size 2)
            do (loop for start from 0 below length by size
                     do (funcall function (concatenate 'string (subseq text 0 start)
                                                       (subseq text (min length (+ start size))))))
            until (= size 1)))))

(defun map-simpler-values (function value)
  "Call FUNCTION with each value one step simpler than VALUE, the simplest
first: an object without one of its properties, or with one of them
simpler; an array empty, without one item, or with one simpler; a text
shorter; a number nearer zero; an id of the first record, or of the newest
for one counted from the newest."
  (cond ((hash-table-p value)
         (dolist (key (jkeys value))
           (let ((copy (copy-object value)))
             (remhash key copy)
             (funcall function copy)))
         (dolist (key (jkeys value))
           (map-simpler-values (lambda (simpler)
                                 (let ((copy (copy-object value)))
                                   (setf (gethash key copy) simpler)
                                   (funcall function copy)))
                               (gethash key value))))
        ((json-array-p value)
         (when (plusp (length value))
           (funcall function (jarr '()))
           (when (> (length value) 1)
             (dotimes (i (length value))
               (funcall function (remove-if (constantly t) value :start i :end (1+ i)))))
           (dotimes (i (length value))
             (map-simpler-values (lambda (simpler)
                                   (let ((copy (copy-seq value)))
                                     (setf (aref copy i) simpler)
                                     (funcall function copy)))
                                 (aref value i)))))
        ((stringp value) (map-simpler-texts function value))
        ((integerp value)
         (unless (zerop value)
           (funcall function 0)
           (unless (zerop (truncate value 2))
             (funcall function (truncate value 2)))))
        ((floatp value)
         (funcall function 0)
         (unless (= value (truncate value))
           (funcall function (truncate value))))
        ((and (record-ref-p value) (plusp (record-ref-index value)))
         (funcall function (make-record-ref (record-ref-entity value) 0
                                            (record-ref-newest value))))))

(defun shrink-input (input fails-p &key (attempts 300))
  "The smallest input made from INPUT, a JSON object, for which FAILS-P, a
function of an input, is still true: properties dropped, texts shortened,
numbers made simpler and arrays emptied, one step at a time, keeping each
step that still fails, until no step does or FAILS-P has been called
ATTEMPTS times. INPUT itself fails. Values the input and how many times
FAILS-P was called."
  (let ((tried 0))
    (loop
      (let ((smaller (block search
                       (map-simpler-values (lambda (candidate)
                                             (when (>= tried attempts)
                                               (return-from search nil))
                                             (incf tried)
                                             (when (funcall fails-p candidate)
                                               (return-from search candidate)))
                                           input)
                       nil)))
        (if smaller
            (setf input smaller)
            (return (values input tried)))))))
