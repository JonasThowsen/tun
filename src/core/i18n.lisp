;;;; core/i18n.lisp -- copy in the tenant's language (spec/i18n.md 2, 3).
;;;;
;;;; Copy is written in the code in its owner's source language, English in
;;;; core and the modules, and the text itself is the key a catalogue
;;;; translates: (tr "Save") is «Lagre» in Norwegian.  The catalogues of
;;;; every owner make one table per language.
;;;;
;;;; A message that may be shown in more than one language, such as a
;;;; refusal's, is kept as a TEXT, its control string and arguments, and
;;;; written in the language of the place it is shown: the tenant's on a
;;;; page, source text to a machine (spec/i18n.md 7).

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +languages+ '("en" "nb")
  "The languages Tun ships, as BCP 47 codes: English, the language Tun's own
copy is written in, and Norwegian bokmål.")

(defparameter +pseudo-language+ "qps"
  "The pseudo-language of the checks (spec/i18n.md 3.7): every looked-up text
is shown as ⟦TEXT⟧.  Never a tenant's.")

(defvar *language* nil
  "The language being written in, when something has chosen one: a code of
+LANGUAGES+, +PSEUDO-LANGUAGE+, or :SOURCE for source text, untranslated.
NIL means the language of the request being answered (CURRENT-LANGUAGE).")

;;; ------------------------------------------------------------------
;;; The locale of a request

(defstruct (locale (:constructor make-locale (&key (language "en") (currency "EUR")
                                                    (time-zone "UTC"))))
  "What a tenant's settings say about its language, currency and time zone
(spec/i18n.md 9)."
  (language "en" :type string :read-only t)
  (currency "EUR" :type string :read-only t)
  (time-zone "UTC" :type string :read-only t))

(defvar *locale* nil
  "The locale of the request being answered, read from the tenant's settings
when it starts, or NIL outside one.")

(defgeneric default-locale (application)
  (:documentation "The locale APPLICATION's class declares for a new tenant,
from its (:locale ...), or Tun's defaults: en, EUR, UTC.")
  (:method (application)
    (declare (ignore application))
    (make-locale)))

(defvar *application*)

(defun current-locale ()
  "The locale being written in: the request's, else the application's
defaults, else Tun's."
  (or *locale*
      (and (boundp '*application*) *application* (default-locale *application*))
      (make-locale)))

(defun current-language ()
  "The language being written in: the one WITH-LANGUAGE chose, else the
tenant's (spec/i18n.md 2.4).  :SOURCE means source text, untranslated."
  (or *language* (locale-language (current-locale))))

(defmacro with-language ((language) &body body)
  "Write BODY in LANGUAGE: a code of +LANGUAGES+, or :SOURCE for source text."
  `(let ((*language* ,language))
     ,@body))

;;; ------------------------------------------------------------------
;;; Catalogues

(defvar *catalogues* (make-hash-table :test 'equal)
  "Language code -> an EQUAL hash table from (SOURCE . CONTEXT) to
(TRANSLATION . OWNER), from every owner's DEFINE-TRANSLATIONS.")

(defvar *missing-translation-hook* nil
  "When non-NIL, a function of the language, the source text and its
context, called for each text looked up and not found.  The checks bind it.")

(defun text-key (source context)
  (cons source context))

(defun catalogue (language)
  (or (gethash language *catalogues*)
      (setf (gethash language *catalogues*) (make-hash-table :test 'equal))))

(defstruct (entry (:constructor make-entry (translation owner place)))
  "A catalogue's translation of one text: who gave it and in which file."
  (translation "" :type string :read-only t)
  (owner "" :type string :read-only t)
  (place nil :read-only t))

(defun register-translations (language owner entries &optional place)
  "Add ENTRIES, a list of (SOURCE CONTEXT TRANSLATION), to LANGUAGE's
catalogue as OWNER's, given in PLACE (its DEFINE-TRANSLATIONS' file).  A
file may replace its own entries, as a reloaded file does; a different
translation of the same source and context given anywhere else, by another
owner or another file, is refused (spec/i18n.md 3.2)."
  (let ((table (catalogue language)))
    (dolist (entry entries)
      (destructuring-bind (source context translation) entry
        (let* ((key (text-key source context))
               (old (gethash key table)))
          (when (and old (not (equal (entry-translation old) translation))
                     (not (and (equal (entry-owner old) owner) (equal (entry-place old) place))))
            (error "The ~a translation of ~s~@[ (context ~s)~] is ~s in ~a~@[ (~a)~] and ~s in ~
                    ~a~@[ (~a)~]"
                   language source context (entry-translation old) (entry-owner old)
                   (entry-place old) translation owner place))
          (setf (gethash key table) (make-entry translation owner place)))))
    language))

(defun catalogue-entries (language)
  "LANGUAGE's catalogue as a list of (SOURCE CONTEXT TRANSLATION OWNER)."
  (let ((table (gethash language *catalogues*)))
    (and table
         (loop for (source . context) being the hash-keys of table using (hash-value entry)
               collect (list source context (entry-translation entry) (entry-owner entry))))))

(defun find-translation (language source context)
  "SOURCE's translation into LANGUAGE in CONTEXT, or NIL."
  (let ((table (gethash language *catalogues*)))
    (let ((entry (and table (gethash (text-key source context) table))))
      (and entry (entry-translation entry)))))

(defun translate (source &optional context)
  "SOURCE, a text in its owner's source language, in the current language:
its catalogue's translation, else SOURCE as written (spec/i18n.md 3.3)."
  (let ((language (current-language)))
    (cond ((eq language :source) source)
          ((equal language +pseudo-language+) (format nil "⟦~a⟧" source))
          ((find-translation language source context))
          (t (when (and *missing-translation-hook* (not (equal language "en")))
               (funcall *missing-translation-hook* language source context))
             source))))

;;; ------------------------------------------------------------------
;;; Texts known from the code: for the checks of spec/i18n.md 3.7

(defvar *noted-texts* (make-hash-table :test 'equal)
  "(SOURCE . CONTEXT) -> the list of (OWNER . WHERE) of each TR and refusal
whose text is a literal, noted when its code is loaded.")

(defun note-text (source context owner where)
  "Note that OWNER's code at WHERE writes the text SOURCE in CONTEXT."
  (pushnew (cons owner where) (gethash (text-key source context) *noted-texts*) :test #'equal)
  source)

(defun noted-texts ()
  "Every text code writes as a literal: a list of (SOURCE CONTEXT OWNER WHERE)."
  (loop for key being the hash-keys of *noted-texts* using (hash-value uses)
        append (loop for (owner . where) in uses
                     collect (list (car key) (cdr key) owner where))))

(defun text-source-parts (text)
  "The source string and context of TEXT, as TR takes it: a string, or
(STRING :CONTEXT WORD).  Anything else is an error."
  (cond ((stringp text) (values text nil))
        ((and (consp text) (stringp (first text)) (eq (second text) :context)
              (stringp (third text)) (null (cdddr text)))
         (values (first text) (third text)))
        (t (error "A text is a literal string or (STRING :context WORD), not ~s" text))))

(defun definition-place ()
  "Where the form being compiled is, for a check's report: its package and
file, as PACKAGE:FILE."
  (let ((file (or *compile-file-truename* *load-truename*)))
    (format nil "~a:~a" (package-name *package*) (if file (file-namestring file) "REPL"))))

(defmacro tr (text &rest args)
  "TEXT in the current language, used as a FORMAT control with ARGS:
(tr \"~d files attached\" n).  TEXT is a literal string, or (STRING :context
WORD) for a text that needs two translations (spec/i18n.md 3.1)."
  (multiple-value-bind (source context) (text-source-parts text)
    `(progn
       (load-time-value (note-text ,source ,context ,(current-definition-module)
                                   ,(definition-place)))
       (format nil (translate ,source ,context) ,@args))))

(defun check-translation-control (language source translation)
  "Refuse TRANSLATION when it holds a FORMAT directive that is not valid, so a
broken translation fails its file's compile (spec/i18n.md 3.2)."
  (when (find #\~ translation)
    (handler-case (macroexpand-1 `(formatter ,translation))
      (error (e)
        (error "The ~a translation of ~s is not a valid FORMAT control: ~a"
               language source e)))))

(defmacro define-translations (language &body entries)
  "Translate texts into LANGUAGE, a code of +LANGUAGES+: each entry is
(SOURCE TRANSLATION), SOURCE a text as TR takes it (spec/i18n.md 3.2)."
  (unless (member language +languages+ :test #'equal)
    (error "define-translations: ~s is not one of Tun's languages ~s" language +languages+))
  (let ((parsed (loop for entry in entries
                      collect (destructuring-bind (text translation) entry
                                (multiple-value-bind (source context) (text-source-parts text)
                                  (unless (stringp translation)
                                    (error "define-translations: the translation of ~s is not a ~
                                            string: ~s" source translation))
                                  (check-translation-control language source translation)
                                  (list source context translation))))))
    (loop for (entry . rest) on parsed
          for twin = (find-if (lambda (other) (and (equal (first other) (first entry))
                                                   (equal (second other) (second entry))))
                              rest)
          when twin
            do (error "define-translations: ~s~@[ (context ~s)~] is translated twice"
                      (first entry) (second entry)))
    `(register-translations ,language ,(current-definition-module) ',parsed
                            ,(definition-place))))

;;; ------------------------------------------------------------------
;;; Texts written where they are shown

(defstruct (text (:constructor make-text (control args &optional context)))
  "A message kept as its control string and arguments, written in the
language of the place it is shown (spec/i18n.md 3.1)."
  (control "" :type string :read-only t)
  (args '() :type list :read-only t)
  (context nil :type (or null string) :read-only t))

(defstruct (label (:include text) (:constructor %make-label (control context)))
  "A stored value as a person reads it, its label looked up in the context
of its field first.")

(defun humanize-value (value)
  "VALUE, a stored word such as quote_sent, as its source label: Quote sent."
  (let ((text (substitute #\Space #\_ (princ-to-string value))))
    (if (plusp (length text))
        (concatenate 'string (string-upcase (subseq text 0 1)) (subseq text 1))
        text)))

(defun label (entity field value)
  "The label of VALUE, stored in FIELD of ENTITY (JSON names), as a text a
message takes as an argument: «Quote sent», or its translation, looked up
with the context ENTITY.FIELD first (spec/i18n.md 3.1)."
  (%make-label (humanize-value value) (format nil "~a.~a" entity field)))

(defun translate-in-context (source context)
  "SOURCE in the current language, its translation in CONTEXT first, then
without one: the label of a field or a stored value, whose context is its
ENTITY.FIELD (spec/i18n.md 3.1)."
  (let ((language (current-language)))
    (if (and context (stringp language) (find-translation language source context))
        (translate source context)
        (translate source))))

(defun render-text (text)
  "TEXT, a TEXT or a string, written in the current language."
  (cond ((stringp text) text)
        ((label-p text) (translate-in-context (text-control text) (text-context text)))
        (t (apply #'format nil (translate (text-control text) (text-context text))
                  (text-args text)))))

(defmethod print-object ((text text) stream)
  (if *print-escape*
      (print-unreadable-object (text stream :type t)
        (format stream "~s" (text-control text)))
      (write-string (render-text text) stream)))

(defmacro deferred-tr (text &rest args)
  "TEXT and ARGS as a TEXT, written later in the language of the place it is
shown, as a refusal's message is: TEXT is literal, as TR's (spec/i18n.md 3.1)."
  (multiple-value-bind (source context) (text-source-parts text)
    `(progn
       (load-time-value (note-text ,source ,context ,(current-definition-module)
                                   ,(definition-place)))
       (make-text ,source (list ,@args) ,context))))
