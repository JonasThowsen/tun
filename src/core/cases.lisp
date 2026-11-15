;;;; core/cases.lisp -- case analysis over a closed set (spec/core.md 2.7).
;;;;
;;;; ECASE-OF, CASE-OF and ETYPECASE-OF name the set they switch over: an
;;;; entity's enum field, (ENTITY FIELD), or a type.  The set is looked up
;;;; when the form is compiled, and a branch missing or outside the set is a
;;;; compiler warning, which the strict builds turn into a failure.
;;;;
;;;; A field's set is read from *DECLARED-FIELDS*, which DEFINE-ENTITY,
;;;; EXTEND-ENTITY and DEFINE-COMPUTED-FIELD fill when they are compiled,
;;;; loaded or evaluated: a form later in the same file sees the set, and
;;;; the table follows the latest definition.  Each form also notes, when it
;;;; is loaded, the set it was compiled against, so an expansion compiled
;;;; against another set warns (a file ASDF did not compile again, an entity
;;;; defined again at the REPL).

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Conditions

(define-condition case-set-warning (simple-warning) ()
  (:documentation "A form over a closed set that does not fit the set: a value
missing or outside it, a set that is not there, or a form compiled against
another set than the one there is now (spec/core.md 2.7)."))

(define-condition case-not-handled (error)
  ((value :initarg :value :reader case-not-handled-value)
   (form :initarg :form :reader case-not-handled-form
         :documentation "ECASE-OF or ETYPECASE-OF.")
   (set :initarg :set :reader case-not-handled-set
        :documentation "The set as the form names it, as text: (order status).")
   (place :initarg :place :reader case-not-handled-place
          :documentation "file:line of the top-level form the form is in, or \"the REPL\"."))
  (:report (lambda (c s)
             (format s "~s is not handled by ~(~a~) ~a at ~a"
                     (case-not-handled-value c) (case-not-handled-form c)
                     (case-not-handled-set c) (case-not-handled-place c))))
  (:documentation "Signalled when a value reaches an ECASE-OF or ETYPECASE-OF
that has no branch for it and no otherwise."))

(declaim (ftype (function (t symbol string string) nil) signal-case-not-handled))
(defun signal-case-not-handled (value form set place)
  (error 'case-not-handled :value value :form form :set set :place place))

(defun case-warning (control &rest arguments)
  (warn 'case-set-warning :format-control control :format-arguments arguments))

;;; ------------------------------------------------------------------
;;; Declared fields

(defstruct (declared-field (:constructor make-declared-field
                               (entity name designator reader location module)))
  "A field of an entity as its defining form noted it."
  entity name designator reader location module)

(defvar *declared-fields* (make-hash-table :test 'equal :synchronized t)
  "(ENTITY . FIELD-NAME) -> DECLARED-FIELD, for every field DEFINE-ENTITY,
EXTEND-ENTITY or DEFINE-COMPUTED-FIELD has noted in this image.")

(defvar *case-uses* (make-hash-table :test 'equal :synchronized t)
  "(FORM DESIGNATOR PLACE) -> the set's values (or types) the form at PLACE
was compiled against, for every form over a set loaded in this image.")

(defun designator-values (designator)
  "The values of the closed set the field type DESIGNATOR declares: an
enum's strings, or those of a list of an enum; NIL when it declares none."
  (let ((head (designator-head designator)))
    (cond ((and (string= head "ENUM") (consp designator)) (copy-list (rest designator)))
          ((and (string= head "LIST-OF") (consp designator) (consp (second designator)))
           (designator-values (second designator)))
          (t nil))))

(defun declared-field-values (field)
  (designator-values (declared-field-designator field)))

(defun field-key (entity name)
  (cons entity (string name)))

(defun value-text (value)
  "VALUE as a message lists a set's values: a string as it is, else as Lisp
prints it, in lower case."
  (if (stringp value) value (format nil "~(~s~)" value)))

(defun quoted-values (values)
  "VALUES as a message names them: strings quoted, others as Lisp prints them."
  (mapcar (lambda (value) (if (stringp value) (format nil "~s" value) (value-text value)))
          values))

(defun same-set-p (a b)
  (and (subsetp a b :test #'equal) (subsetp b a :test #'equal)))

(defun note-declared-fields (entity fields location module)
  "Note ENTITY's FIELDS, each (NAME DESIGNATOR READER), declared at LOCATION by
MODULE.  Called when the defining form is compiled, loaded or evaluated.
When a field's set changes, warn about each loaded form over it that was
compiled against another set."
  (dolist (field fields)
    (destructuring-bind (name designator reader) field
      (let* ((key (field-key entity name))
             (old (gethash key *declared-fields*))
             (new (make-declared-field entity name designator reader location module)))
        (setf (gethash key *declared-fields*) new)
        (when (and old (not (same-set-p (declared-field-values old) (declared-field-values new))))
          (warn-stale-uses (list entity name) (declared-field-values new))))))
  entity)

(defun declared-fields-form (entity fields location module)
  "The form a defining macro expands into so ENTITY's FIELDS, each (NAME
DESIGNATOR READER), are noted when it is compiled, loaded or evaluated."
  `(eval-when (:compile-toplevel :load-toplevel :execute)
     (note-declared-fields ',entity ',fields ,location ,module)))

(defun field-reader-name (entity name)
  "The reader DEFINE-ENTITY gives the field NAME of ENTITY."
  (symbolicate entity "-" name))

(defun declared-fields ()
  "Every noted field whose type declares a closed set, as DECLARED-FIELD
records: what the cases guard looks for (spec/testing.md 1, test 11)."
  (loop for field being the hash-values of *declared-fields*
        when (declared-field-values field) collect field))

;;; ------------------------------------------------------------------
;;; Sets

(defun set-text (designator)
  "DESIGNATOR as a message names the set: (order status), error-code."
  (if (consp designator)
      (format nil "(~(~{~a~^ ~}~))" designator)
      (format nil "~(~a~)" designator)))

(defun field-set-p (designator)
  (and (consp designator) (= 2 (length designator))
       (symbolp (first designator)) (symbolp (second designator))))

(defun entity-noted-p (entity)
  (loop for key being the hash-keys of *declared-fields*
        thereis (eq (car key) entity)))

(defun field-set (designator)
  "The values of the field set DESIGNATOR, (ENTITY FIELD), and where it is
declared; or NIL, NIL and why it is not a closed set."
  (destructuring-bind (entity name) designator
    (let ((field (gethash (field-key entity name) *declared-fields*)))
      (cond ((and field (declared-field-values field))
             (values (declared-field-values field)
                     (format nil "~a (~a)" (or (declared-field-location field) "the REPL")
                             (declared-field-module field))))
            (field
             (values nil nil (format nil "the field ~(~a~) of ~(~a~) is ~(~s~), not an enum: ~
                                          not a closed set"
                                     name entity (declared-field-designator field))))
            ((entity-noted-p entity)
             (values nil nil (format nil "~(~a~) has no field ~(~a~)" entity name)))
            (t
             (values nil nil (format nil "~(~a~) names no entity known when this is compiled: ~
                                          define it before this form, or add the system that ~
                                          defines it to the dependencies (a module's ~
                                          :depends-on, the client's .asd)"
                                     entity)))))))

(defun type-declared-at (type)
  "Where the DEFTYPE of TYPE is, as a message says it."
  (let ((source (ignore-errors          ; a probe: a type defined at the REPL has no file
                 (first (sb-introspect:find-definition-sources-by-name type :type)))))
    (let ((path (and source (sb-introspect:definition-source-pathname source))))
      (if path
          (format nil "deftype ~(~a~) in ~a" type (display-source-path path))
          (format nil "deftype ~(~a~)" type)))))

(defun known-type-p (type)
  "True when the symbol TYPE names a type now: a DEFTYPE or a class.  Asked
without parsing TYPE, which would note an unknown name for the compiler to
warn about."
  (or (nth-value 1 (sb-ext:typexpand-1 type))
      (find-class type nil)))

(defun member-form-p (expansion)
  (and (consp expansion) (eq (first expansion) 'member)))

(defun member-type-set (type)
  "The members of TYPE, a (MEMBER ...) type, and where it is declared; or
NIL, NIL and why it is not one."
  (if (not (and (symbolp type) (known-type-p type)))
      (values nil nil (format nil "~(~s~) names no type known when this is compiled: ~
                                   define it before this form" type))
      ;; One expansion keeps the members in the order the DEFTYPE gives them;
      ;; a type built of others is expanded in full.
      (let ((expansion (if (member-form-p (sb-ext:typexpand type))
                           (sb-ext:typexpand type)
                           (sb-ext:typexpand-all type))))
        (cond ((member-form-p expansion)
               (values (copy-list (rest expansion)) (type-declared-at type)))
              ((and (consp expansion) (eq (first expansion) 'eql))
               (values (list (second expansion)) (type-declared-at type)))
              (t (values nil nil (format nil "~(~s~) is ~(~s~), not a (member ...) type"
                                         type expansion)))))))

(defun type-components (type)
  "TYPE's alternatives: the types of its (OR ...), each flattened, or TYPE."
  (let ((expansion (sb-ext:typexpand type)))
    (if (and (consp expansion) (eq (first expansion) 'or))
        (mapcan #'type-components (rest expansion))
        (list type))))

(defun or-type-set (type)
  "The types of TYPE, an (OR ...) type, and where it is declared; or NIL,
NIL and why it is not one."
  (cond ((not (and (symbolp type) (known-type-p type)))
         (values nil nil (format nil "~(~s~) names no type known when this is compiled: ~
                                      define it before this form" type)))
        ((rest (type-components type))
         (values (type-components type) (type-declared-at type)))
        (t (values nil nil (format nil "~(~s~) is not an (or ...) type" type)))))

(defun closed-set (form designator)
  "The set FORM (ECASE-OF, CASE-OF or ETYPECASE-OF) names with DESIGNATOR:
its values (or types), where it is declared, and the test its values
compare with; or NIL, NIL, NIL and why it is not a closed set."
  (cond ((eq form 'etypecase-of)
         (multiple-value-bind (types declared problem) (or-type-set designator)
           (values types declared nil problem)))
        ((field-set-p designator)
         (multiple-value-bind (values declared problem) (field-set designator)
           (values values declared 'equal problem)))
        ((symbolp designator)
         (multiple-value-bind (values declared problem) (member-type-set designator)
           (values values declared 'eql problem)))
        (t (values nil nil nil (format nil "~s names no set: write (ENTITY FIELD) or a type"
                                       designator)))))

;;; ------------------------------------------------------------------
;;; Forms compiled against another set

(defun note-case-use (form designator compiled place)
  "Note, when it is loaded, that FORM at PLACE was compiled against COMPILED,
the set DESIGNATOR names; warn when the set is another now."
  (setf (gethash (list form designator place) *case-uses*) compiled)
  (let ((now (ignore-errors (closed-set form designator)))) ; a probe: NIL when it is gone
    (when (and now (not (same-set-p now compiled)))
      (case-warning "~(~a~) ~a at ~a was compiled against another set; compile it again ~
                     (compiled against ~{~a~^, ~}; now ~{~a~^, ~})"
                    form (set-text designator) place
                    (mapcar #'value-text compiled) (mapcar #'value-text now))))
  t)

(defun warn-stale-uses (designator values)
  "Warn about every loaded form over the field set DESIGNATOR that was
compiled against another set than VALUES."
  (let ((stale (loop for (form used place) being the hash-keys of *case-uses*
                       using (hash-value compiled)
                     when (and (field-set-p used)
                               (eq (first used) (first designator))
                               (string= (second used) (second designator))
                               (not (same-set-p compiled values)))
                       collect (format nil "~(~a~) at ~a" form place))))
    (when stale
      (case-warning "The set ~a is now ~{~a~^, ~}; these forms were compiled against another ~
                     set, compile them again: ~{~a~^; ~}"
                    (set-text designator) (mapcar #'value-text values) stale))))

;;; ------------------------------------------------------------------
;;; Checking and expanding a form

(defun otherwise-clause-p (clause)
  (and (consp clause) (member (first clause) '(otherwise t))))

(defun split-otherwise (clauses)
  "CLAUSES without a final otherwise (or T) clause, and that clause."
  (let ((last (car (last clauses))))
    (if (otherwise-clause-p last)
        (values (butlast clauses) last)
        (values clauses nil))))

(defun clause-keys (clause)
  "The keys of a case CLAUSE: its key list, or its one key."
  (let ((keys (first clause)))
    (if (listp keys) keys (list keys))))

(defun check-value-clauses (form designator clauses otherwise values declared test place)
  "Warn about what CLAUSES of FORM over the set DESIGNATOR, of VALUES
declared at DECLARED, lack or name wrongly."
  (let* ((keys (mapcan (lambda (clause) (copy-list (clause-keys clause))) clauses))
         (outside (remove-if (lambda (key) (or (member key values :test test)
                                               (and (null key) (eq test 'equal))))
                             keys))
         (twice (remove-duplicates
                 (loop for (key . more) on keys when (member key more :test test) collect key)
                 :test test))
         (missing (remove-if (lambda (value) (member value keys :test test)) values)))
    (when outside
      (case-warning "~(~a~) ~a at ~a names ~{~a~^, ~}, not in the set; the set is declared ~
                     at ~a: ~{~a~^, ~}"
                    form (set-text designator) place (quoted-values outside) declared
                    (mapcar #'value-text values)))
    (when twice
      (case-warning "~(~a~) ~a at ~a names ~{~a~^, ~} in more than one branch"
                    form (set-text designator) place (quoted-values twice)))
    (when (and missing (eq form 'ecase-of))
      (case-warning "~(~a~) ~a at ~a has no branch for ~{~a~^, ~}; the set is declared at ~a: ~
                     ~{~a~^, ~}"
                    form (set-text designator) place (quoted-values missing) declared
                    (mapcar #'value-text values)))
    (when (and (eq form 'case-of) (null otherwise))
      (case-warning "case-of ~a at ~a has no final otherwise; write ecase-of to give every ~
                     value a branch"
                    (set-text designator) place))))

(defun check-type-clauses (designator clauses types declared place)
  "Warn about what CLAUSES of ETYPECASE-OF over the type DESIGNATOR, of the
alternatives TYPES, lack or name wrongly."
  (let ((union `(or ,@(mapcar #'first clauses))))
    (dolist (clause clauses)
      (multiple-value-bind (within sure) (subtypep (first clause) designator)
        (cond ((not sure)
               (case-warning "etypecase-of ~a at ~a cannot tell whether ~(~s~) is of the set: ~
                              define the types before this form"
                             (set-text designator) place (first clause)))
              ((not within)
               (case-warning "etypecase-of ~a at ~a names ~(~s~), not in the set; the set is ~
                              declared at ~a: ~(~{~a~^, ~}~)"
                             (set-text designator) place (first clause) declared types)))))
    (let ((missing (remove-if (lambda (type) (subtypep type union)) types)))
      (when missing
        (case-warning "etypecase-of ~a at ~a has no branch for ~(~{~a~^, ~}~); the set is ~
                       declared at ~a: ~(~{~a~^, ~}~)"
                      (set-text designator) place missing declared types)))))

(defun value-test-form (value keys test)
  (cond ((null (rest keys)) `(,test ,value ',(first keys)))
        (t `(member ,value ',keys :test #',test))))

(defun form-place ()
  "Where a form being expanded is, for its messages: the file and line of its
top-level form when a file is being compiled, else the REPL."
  (or (and *compile-file-truename* (current-source-location)) "the REPL"))

(defun expand-case-over-set (form designator keyform clauses)
  "The expansion of FORM, ECASE-OF or CASE-OF, over DESIGNATOR, after
warning about what does not fit the set."
  (let ((place (form-place))
        (value (gensym "VALUE")))
    (multiple-value-bind (branches otherwise) (split-otherwise clauses)
      (multiple-value-bind (values declared test problem) (closed-set form designator)
        (if problem
            (case-warning "~(~a~) ~a at ~a: ~a" form (set-text designator) place problem)
            (check-value-clauses form designator branches otherwise values declared test place))
        (let ((test (or test 'equal)))
          `(let ((,value ,keyform))
             ,@(unless problem
                 `((load-time-value (note-case-use ',form ',designator ',values ,place) t)))
             (cond ,@(loop for clause in branches
                           for keys = (clause-keys clause)
                           when keys
                             collect `(,(value-test-form value keys test) ,@(or (rest clause) '(nil))))
                   (t ,@(if otherwise
                            (or (rest otherwise) '(nil))
                            `((signal-case-not-handled ,value ',form ,(set-text designator)
                                                       ,place)))))))))))

(defmacro ecase-of (set keyform &body clauses)
  "Evaluate KEYFORM and run the branch of CLAUSES whose key (or list of keys)
holds its value, as ECASE does, over the closed SET (spec/core.md 2.7).
SET, not evaluated, is (ENTITY FIELD), an enum field whose strings compare
with EQUAL, or a (MEMBER ...) type, whose values compare with EQL.  Every
value of SET must have a branch: one missing, or a key outside SET, is a
compiler warning naming the set and where it is declared.  A value no branch
holds signals CASE-NOT-HANDLED, or runs a final (OTHERWISE ...) branch."
  (expand-case-over-set 'ecase-of set keyform clauses))

(defmacro case-of (set keyform &body clauses)
  "As ECASE-OF, for code that handles only some values of SET: CLAUSES must
end with (OTHERWISE ...), which the values they do not name run, and only
the values they name are checked against SET."
  (expand-case-over-set 'case-of set keyform clauses))

(defmacro etypecase-of (type keyform &body clauses)
  "Evaluate KEYFORM and run the first branch of CLAUSES whose type its value
is of, as ETYPECASE does, over TYPE, a DEFTYPE of (OR ...) (spec/core.md
2.7).  Every alternative of TYPE must be covered by a branch: one missing,
or a branch's type outside TYPE, is a compiler warning.  A value of no
branch's type signals CASE-NOT-HANDLED, or runs a final (OTHERWISE ...)."
  (let ((place (form-place))
        (value (gensym "VALUE")))
    (multiple-value-bind (branches otherwise) (split-otherwise clauses)
      (multiple-value-bind (types declared test problem) (closed-set 'etypecase-of type)
        (declare (ignore test))
        (if problem
            (case-warning "etypecase-of ~a at ~a: ~a" (set-text type) place problem)
            (check-type-clauses type branches types declared place))
        `(let ((,value ,keyform))
           ,@(unless problem
               `((load-time-value (note-case-use 'etypecase-of ',type ',types ,place) t)))
           (typecase ,value
             ,@branches
             (t ,@(if otherwise
                      (or (rest otherwise) '(nil))
                      `((signal-case-not-handled ,value 'etypecase-of ,(set-text type)
                                                 ,place))))))))))
