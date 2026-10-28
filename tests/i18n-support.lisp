;;;; tests/i18n-support.lisp -- the checks of spec/i18n.md 3.7: every text
;;;; an owner writes has a translation into each language it is shown in, no
;;;; catalogue entry goes unused, and no page writes a text it did not look
;;;; up (the pseudo-language).

(in-package #:tun.test-support)

;;; ------------------------------------------------------------------
;;; The texts the definitions give for people
;;;
;;; Each text is (SOURCE CONTEXT OWNER WHERE . OPTIONS), OPTIONS a plist of
;;; :LABEL (true for a stored value's label) and :PACKAGE (the name of the
;;; package that wrote it, so a suite can leave its own definitions out).

(defun symbol-package-name (symbol)
  (and (symbolp symbol) (symbol-package symbol) (package-name (symbol-package symbol))))

(defun enum-type-of (type)
  "TYPE's enum type: itself, or the element type of a list of an enum; else NIL."
  (cond ((typep type 'enum-type) type)
        ((and (typep type 'list-type) (typep (list-element type) 'enum-type)) (list-element type))
        (t nil)))

(defun enum-label-texts (type context owner where package)
  "The labels of the values of TYPE, an enum or a list of one, in CONTEXT."
  (let ((enum (enum-type-of type)))
    (when enum
      (loop for value in (enum-values enum)
            collect (list (humanize-value value) context owner where :label t :package package)))))

(defun entity-texts (class)
  "What the entity CLASS gives people to read: its label, its fields' labels
and descriptions, the labels of its fields' stored words, and its computed
fields' labels."
  (let ((entity (entity-json-name class))
        (owner (entity-module class))
        (package (symbol-package-name (class-name class))))
    (append
     (when (entity-label class)
       (list (list (entity-label class) nil owner entity :package package)))
     (loop for field in (entity-fields class)
           for where = (format nil "~a.~a" entity (field-json-name field))
           append (append (when (field-label field)
                            ;; Looked up in its field's context first, as a
                            ;; stored value's label is.
                            (list (list (field-label field) where (field-module field) where
                                        :label t :package package)))
                          (when (field-description field)
                            (list (list (field-description field) nil (field-module field) where
                                        :package package)))
                          (enum-label-texts (field-type field) where (field-module field) where
                                            package)))
     (loop for computed in (entity-computed-fields class)
           when (computed-field-label computed)
             collect (list (computed-field-label computed) nil (computed-field-module computed)
                           (format nil "~a.~a" entity (computed-field-json-name computed))
                           :package package)))))

(defun operation-texts (op)
  "What the operation OP gives people to read: its title, its parameters'
labels and descriptions, and the labels of their enums' values.  Its own
description is for agents only (spec/i18n.md 3.1)."
  (let ((owner (operation-module op))
        (tool (operation-tool op))
        (package (symbol-package-name (operation-name op))))
    (append (list (list (operation-title op) nil owner tool :package package))
            (loop for parameter in (operation-parameters op)
                  for where = (format nil "~a(~a)" tool (parameter-json-name parameter))
                  append (append (when (parameter-label parameter)
                                   (list (list (parameter-label parameter) nil owner where
                                               :package package)))
                                 (when (parameter-description parameter)
                                   (list (list (parameter-description parameter) nil owner where
                                               :package package)))
                                 (enum-label-texts (parameter-type parameter) nil owner where
                                                   package))))))

(defun definition-texts ()
  "Every text a definition gives people to read: entities, operations,
pages and resources, settings, workflows and message templates."
  (append
   (loop for class in (all-entity-classes)
         unless (entity-internal-p class) append (entity-texts class))
   (loop for op in (all-operations)
         unless (or (operation-debug-only-p op) (operation-test-only-p op))
           append (operation-texts op))
   (loop for (title owner package) in (tun.web:page-texts)
         collect (list title nil owner "page" :package package))
   (loop for (description owner key) in (setting-texts)
         collect (list description nil owner key))
   (loop for kind in *workflow-kinds*
         unless (workflow-kind-debug-p kind)
           collect (list (workflow-kind-label kind) nil (workflow-kind-module kind)
                         (workflow-kind-name kind)
                         :package (symbol-package-name (workflow-kind-function kind))))
   (loop for template in *message-templates*
         collect (list (message-template-label template) nil (message-template-module template)
                       (message-template-name template)
                       :package (symbol-package-name (message-template-function template))))))

(defun known-texts ()
  "Every text code and definitions write for people: those of TR and the
refusals, noted where their code was compiled, then DEFINITION-TEXTS'."
  (append (loop for (source context owner where) in (noted-texts)
                collect (list source context owner where
                              :package (subseq where 0 (or (position #\: where) 0))))
          (definition-texts)))

;;; ------------------------------------------------------------------
;;; Untranslated and unused texts

(defun owner-source-language (owner application)
  "The language OWNER writes its copy in: a client's :SOURCE-LANGUAGE, else
English, Tun's own."
  (if (equal owner "client")
      (application-source-language application)
      "en"))

(defun translated-p (language source context labelp)
  "True when LANGUAGE's catalogue translates SOURCE in CONTEXT; a stored
value's label also counts when translated without its context."
  (or (find-translation language source context)
      (and labelp (find-translation language source nil))))

(defun words-p (source)
  "True when SOURCE, a format control, holds a word to translate: a letter
outside its directives (\"~a\" holds none)."
  (some #'alpha-char-p (cl-ppcre:regex-replace-all "~[0-9,'@:#vV]*[^0-9,'@:#vV]" source "")))

(defun untranslated-texts (language &key owner (application *app*) exclude-packages)
  "Every text an OWNER (all owners by default) writes for people whose
source language is not LANGUAGE and that LANGUAGE's catalogue lacks, as
(SOURCE CONTEXT OWNER WHERE), each source and context once (spec/i18n.md
3.7).  APPLICATION decides a client's source language; texts written in
EXCLUDE-PACKAGES (names, such as a suite's own) are left out."
  (let ((seen (make-hash-table :test 'equal)) (missing '()))
    (loop for (source context text-owner where . options) in (known-texts)
          for key = (list source context text-owner)
          when (and (or (null owner) (equal owner text-owner))
                    (not (member (getf options :package) exclude-packages :test #'equal))
                    (words-p source)
                    (not (equal language (owner-source-language text-owner application)))
                    (not (gethash key seen))
                    (not (translated-p language source context (getf options :label))))
            do (setf (gethash key seen) t)
               (push (list source context text-owner where) missing))
    (nreverse missing)))

(defun unused-translations (language &key owner owners)
  "Every entry of LANGUAGE's catalogue, of OWNER's or of one of OWNERS (every
owner's by default), that no known text uses, as (SOURCE CONTEXT OWNER).  A
stored value's label uses its plain entry and its entry in context."
  (let ((used (make-hash-table :test 'equal)))
    (loop for (source context nil nil . options) in (known-texts)
          do (setf (gethash (cons source context) used) t)
             (when (getf options :label)
               (setf (gethash (cons source nil) used) t)))
    (loop for (source context nil entry-owner) in (catalogue-entries language)
          when (and (or (null owner) (equal owner entry-owner))
                    (or (null owners) (member entry-owner owners :test #'equal))
                    (not (gethash (cons source context) used))
                    ;; A label's entry with a context is used by its value.
                    (not (and context (gethash (cons source nil) used))))
            collect (list source context entry-owner))))

;;; ------------------------------------------------------------------
;;; Texts a page writes without looking them up (the pseudo-language)

(defparameter +pseudo-open+ (string (code-char #x27E6)))
(defparameter +pseudo-close+ (string (code-char #x27E7)))

(defun decode-entities (text)
  "TEXT with the HTML entities Tun's renderer writes decoded."
  (let ((text (cl-ppcre:regex-replace-all "&#(\\d+);" text
                                          (lambda (match &rest registers)
                                            (declare (ignore match))
                                            (string (code-char (parse-integer (first registers)))))
                                          :simple-calls t)))
    (loop for (entity . char) in '(("&lt;" . "<") ("&gt;" . ">") ("&quot;" . "\"")
                                   ("&#39;" . "'") ("&nbsp;" . " ") ("&amp;" . "&"))
          do (setf text (cl-ppcre:regex-replace-all entity text char)))
    text))

(defun page-visible-texts (html)
  "The texts a person reads in the page HTML: its text between tags (not in
scripts, styles or the head's title), and its aria-label, title,
placeholder and alt attributes."
  (let* ((body (cl-ppcre:regex-replace-all "(?is)<(script|style|title)\\b.*?</\\1>" html ""))
         (texts '()))
    (cl-ppcre:do-register-groups (value) ("(?i)\\s(?:aria-label|title|placeholder|alt)=\"([^\"]*)\"" body)
      (push (decode-entities value) texts))
    (dolist (piece (cl-ppcre:split "<[^>]*>" body))
      (let ((text (string-trim '(#\Space #\Tab #\Newline #\Return) (decode-entities piece))))
        (when (plusp (length text)) (push text texts))))
    (nreverse texts)))

(defun strip-looked-up (text)
  "TEXT without its looked-up parts, each written ⟦…⟧ in the pseudo-language,
the innermost first, since a looked-up text may hold another."
  (let ((pattern (format nil "~a[^~a~a]*~a" +pseudo-open+ +pseudo-open+ +pseudo-close+
                         +pseudo-close+)))
    (loop for stripped = (cl-ppcre:regex-replace-all pattern text " ")
          until (string= stripped text)
          do (setf text stripped))
    text))

(defun json-strings (value)
  "Every string in the JSON VALUE: data a page shows as it is."
  (cond ((stringp value) (list value))
        ((hash-table-p value) (loop for v being the hash-values of value append (json-strings v)))
        ((json-array-p value) (loop for v across value append (json-strings v)))
        (t nil)))

(defun unlooked-up-texts (html &key allowed)
  "The visible texts of the page HTML, rendered in the pseudo-language, that
hold a letter outside what was looked up and outside the strings ALLOWED
(the data the page shows): each a text written without a lookup."
  (let ((allowed (sort (remove-if (lambda (s) (< (length s) 1)) (copy-list allowed))
                       #'> :key #'length)))
    (loop for text in (page-visible-texts html)
          for rest = (let ((rest (strip-looked-up text)))
                       (dolist (data allowed rest)
                         (setf rest (cl-ppcre:regex-replace-all (cl-ppcre:quote-meta-chars data)
                                                                rest " "))))
          when (some #'alpha-char-p rest)
            collect text)))

(defun stored-strings ()
  "Every string of the stored records of the running application, as their
JSON holds them: the data a page may show as it is."
  (let ((strings '()))
    (labels ((walk (value)
               (cond ((stringp value) (push value strings))
                     ((hash-table-p value) (maphash (lambda (k v) (declare (ignore k)) (walk v)) value))
                     ((json-array-p value) (map nil #'walk value)))))
      (with-application (*app*)
        (with-transaction (:read)
          (dolist (class (all-entity-classes))
            ;; An entity with a record policy is kept on Postgres only.
            (unless (or (entity-embedded-p class) (entity-record-policy class))
              (dolist (record (select (class-name class)))
                (walk (entity->json record))))))))
    (remove-duplicates strings :test #'string=)))

(defun data-codes ()
  "Codes a page shows as they are: currencies and time zones, the language
codes, and the application's title."
  (let ((title (tun.core:application-title *app*)))
    (append (mapcar #'first +currencies+) (mapcar #'first +time-zones+) +languages+
            ;; The app shell's mark is the title's first letter.
            (list title (subseq title 0 (min 1 (length title)))))))

;;; ------------------------------------------------------------------
;;; Pages fetched over HTTP

(defun pages-missing-translations (port jar paths &key owners)
  "The (SOURCE CONTEXT) of the texts that the pages at PATHS, fetched with
JAR, looked up and found no translation for (only OWNERS' texts, when
given), and the pages' bodies.  The pages are drawn in the server's
threads, so the hook is set, not bound."
  (let ((missing '())
        (texts (and owners (loop for (source context owner) in (known-texts)
                                 when (member owner owners :test #'equal)
                                   collect (list source context)))))
    (setf *missing-translation-hook*
          (lambda (language source context)
            (declare (ignore language))
            (when (or (null owners) (member (list source context) texts :test #'equal))
              (pushnew (list source context) missing :test #'equal))))
    (unwind-protect
         (values missing
                 (mapcar (lambda (path) (nth-value 1 (web-request port path :jar jar))) paths))
      (setf *missing-translation-hook* nil))))

(defun pseudo-page-problems (port path jar &key allowed)
  "The texts of the page at PATH, fetched with JAR and rendered in the
pseudo-language, that were written without a lookup."
  (multiple-value-bind (status body) (web-request port path :jar jar)
    (declare (ignore status))
    (unlooked-up-texts body :allowed allowed)))
