;;;; tests/case-guard.lisp -- the cases guard (spec/testing.md 1, test 11): a
;;;; client's sources switch over a declared set only through ECASE-OF and
;;;; CASE-OF (spec/core.md 2.7).  It reads the sources with the Lisp reader,
;;;; each file in the package its IN-PACKAGE names, and finds a CASE, ECASE
;;;; or CCASE on the reader of an enum field, and a COND whose branches
;;;; compare one form with two or more strings of one set.

(in-package #:tun.test-support)

(defparameter +case-operators+ '(case ecase ccase)
  "The operators whose key form the guard looks at.")

(defparameter +string-comparisons+ '(string= equal string-equal equalp)
  "The comparisons a COND's branch makes of a form with a string.")

(defun skip-blank-and-comments (text start)
  "The index of the first character at or after START in TEXT, Lisp source,
that is neither blank nor in a comment."
  (loop with i = start
        while (< i (length text))
        do (let ((c (char text i)))
             (cond ((member c '(#\Space #\Tab #\Newline #\Return #\Page)) (incf i))
                   ((char= c #\;) (setf i (or (position #\Newline text :start i) (length text))))
                   ((and (char= c #\#) (< (1+ i) (length text)) (char= (char text (1+ i)) #\|))
                    (setf i (block-comment-end text i)))
                   (t (return i))))
        finally (return i)))

(defun line-at (text index)
  (1+ (count #\Newline text :end (min index (length text)))))

(defun top-level-forms (text package)
  "The top-level forms of TEXT, each (FORM LINE PACKAGE): read in PACKAGE, and
after an IN-PACKAGE form in the package it names.  Reading stops at the
first form the reader refuses."
  (let ((*package* (or (find-package package) (find-package "COMMON-LISP-USER")))
        (*read-eval* nil)
        (forms '()))
    (with-input-from-string (in text)
      (handler-case
          (loop
            (let ((start (skip-blank-and-comments text (file-position in))))
              (when (>= start (length text)) (return))
              (file-position in start)
              (let ((form (read in nil in)))
                (when (eq form in) (return))
                (push (list form (line-at text start) *package*) forms)
                (when (and (consp form) (eq (first form) 'in-package)
                           (find-package (second form)))
                  (setf *package* (find-package (second form)))))))
        (reader-error () nil)))
    (nreverse forms)))

(defun nameable-fields (package)
  "The enum fields code read in PACKAGE can name with ECASE-OF: those whose
entity's symbol is accessible there.  A set of a module that does not
publish its entity is not the code's to name, so it is not looked for."
  (remove-if-not (lambda (field)
                   (let ((entity (declared-field-entity field)))
                     (eq entity (find-symbol (symbol-name entity) package))))
                 (declared-fields)))

(defun field-readers (fields)
  "A table of the reader of each of FIELDS to its DECLARED-FIELD."
  (let ((table (make-hash-table :test 'eq)))
    (dolist (field fields table)
      (setf (gethash (declared-field-reader field) table) field))))

(defun field-set-name (field)
  (format nil "(~(~a ~a~))" (declared-field-entity field) (declared-field-name field)))

(defun reader-call-field (form readers)
  "The DECLARED-FIELD whose reader FORM calls, or NIL."
  (and (consp form) (symbolp (first form)) (= 2 (length form))
       (gethash (first form) readers)))

(defun quoted-strings (form)
  "The strings of FORM when it is a quoted list of strings, else NIL."
  (and (consp form) (eq (first form) 'quote) (consp (second form))
       (every #'stringp (second form))
       (second form)))

(defun string-comparison (test)
  "When TEST, a COND branch's test, compares a form with strings, as
(STRING= FORM \"x\") or (MEMBER FORM '(\"x\" \"y\") ...): the form and the
strings."
  (when (consp test)
    (cond ((and (member (first test) +string-comparisons+) (= 3 (length test)))
           (destructuring-bind (a b) (rest test)
             (cond ((and (stringp b) (not (stringp a))) (values a (list b)))
                   ((and (stringp a) (not (stringp b))) (values b (list a))))))
          ((and (eq (first test) 'member) (<= 3 (length test)) (quoted-strings (third test)))
           (values (second test) (copy-list (quoted-strings (third test))))))))

(defun sets-holding (strings fields)
  "The fields among FIELDS whose set holds every one of STRINGS."
  (remove-if-not (lambda (field)
                   (subsetp strings (declared-field-values field) :test #'string=))
                 fields))

(defun cond-findings (form readers fields)
  "The sets a COND FORM switches over: for each form its branches compare
with two or more strings, the fields whose set holds them all."
  (let ((compared '()))                 ; (key branches . strings), latest first
    (dolist (clause (rest form))
      (when (consp clause)
        (multiple-value-bind (key strings) (string-comparison (first clause))
          (when strings
            (let ((entry (or (assoc key compared :test #'equal)
                             (first (push (list key 0) compared)))))
              (incf (second entry))
              (dolist (string strings)
                (pushnew string (cddr entry) :test #'string=)))))))
    (loop for (key branches . strings) in compared
          for field = (reader-call-field key readers)
          for sets = (if field (sets-holding strings (list field)) (sets-holding strings fields))
          when (and (< 1 branches) sets)
            collect (format nil "a cond comparing ~(~s~) with ~{~s~^, ~}, values of ~{~a~^, ~}"
                            key (reverse strings) (mapcar #'field-set-name sets)))))

(defun form-findings (form readers fields)
  "What the guard finds in FORM and every form inside it."
  (let ((findings '()))
    (walk-forms form
                (lambda (f)
                  (cond ((and (member (first f) +case-operators+) (consp (rest f)))
                         (let ((field (reader-call-field (second f) readers)))
                           (when field
                             (push (format nil "~(~a~) on ~(~s~), the field ~a"
                                           (first f) (second f) (field-set-name field))
                                   findings))))
                        ((eq (first f) 'cond)
                         (setf findings (append (reverse (cond-findings f readers fields))
                                                findings))))))
    (nreverse findings)))

(defun definition-name (form)
  (if (and (consp form) (consp (rest form)) (symbolp (second form)))
      (format nil "(~(~a ~a~))" (first form) (second form))
      "a top-level form"))

(defun plain-case-findings-in-text (text &key (package "COMMON-LISP-USER") (source "<string>"))
  "The cases guard's findings in TEXT, Lisp source read in PACKAGE: each a
line naming SOURCE, the line of the top-level form, the form and the set
it switches over without ECASE-OF or CASE-OF (spec/testing.md 1, test 11)."
  (loop for (form line read-in) in (top-level-forms text package)
        append (let* ((*package* read-in)
                      (fields (nameable-fields read-in)))
                 (mapcar (lambda (finding)
                           (format nil "~a:~d ~a: ~a; write it with ecase-of or case-of ~
                                        (spec/core.md 2.7)"
                                   source line (definition-name form) finding))
                         (form-findings form (field-readers fields) fields)))))

(defun plain-case-findings (files &key (package "COMMON-LISP-USER") root)
  "The cases guard's findings in FILES, Lisp source files each read from
PACKAGE until its IN-PACKAGE, each file named from ROOT when given."
  (loop for file in files
        append (plain-case-findings-in-text
                (file-text file)
                :package package
                :source (if root (enough-namestring file root) (namestring file)))))

(defun client-case-sources (system)
  "The sources the cases guard reads for the client SYSTEM: those of test 2
and those of its own modules, as test 10 reads them (spec/testing.md 1)."
  (let ((root (client-root system)))
    (append (client-source-files system)
            (and root
                 (loop for (nil directory) in (client-module-directories (truename root))
                       append (remove-if (lambda (file)
                                           (directory-namestring-under-p
                                            file (merge-pathnames "tests/" directory)))
                                         (directory (merge-pathnames "**/*.lisp" directory))))))))

(defun check-cases-over-declared-sets (system package)
  "Test 11 of the generated tests: the client SYSTEM, whose package is
PACKAGE, switches over a declared set only through ECASE-OF and CASE-OF."
  (let* ((root (client-root system))
         (findings (plain-case-findings (client-case-sources system)
                                        :package package
                                        :root (and root (truename root)))))
    (fiveam:is (null findings) "~{~a~^~%~}" findings)))
