;;;; core/search.lisp -- the application's one search (spec/ui.md 6.4): the
;;;; rule every search matches by, the results, and the seam a module or a
;;;; client says what of its records can be found through.
;;;;
;;;; The rule is pure: text is folded (case, marks, a few letters, a run of
;;;; «a», spaces), every word of the query must be in one of a record's
;;;; texts, and the whole query may be one of its identifiers or their
;;;; start.  SEARCH-MATCH scores a record by it; SEARCH-MARK-RANGES says
;;;; which stored characters a title's match covers.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Folding

(defparameter +search-letters+
  '((#\ø . "o") (#\æ . "ae") (#\œ . "oe") (#\ß . "ss") (#\ł . "l") (#\đ . "d")
    (#\ı . "i") (#\þ . "th"))
  "Letters folded to others that decomposing them does not reach (spec/ui.md
6.4), lower case: the upper case is lowered first.")

(defun search-space-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return #\Page #\No-break_space)))

(defun fold-char-slowly (char)
  "CHAR folded: lowered, decomposed without its marks, and its letter as
+SEARCH-LETTERS+ says."
  (let ((lower (char-downcase char)))
    (or (cdr (assoc lower +search-letters+))
        (remove-if (lambda (c) (eq (sb-unicode:general-category c) :mn))
                   (string-downcase (sb-unicode:normalize-string (string lower) :nfkd))))))

(defparameter +search-latin-folds+
  (let ((table (make-array #x250)))
    (dotimes (code #x250 table)
      (setf (aref table code) (fold-char-slowly (code-char code)))))
  "The fold of every character up to Latin Extended-B, worked out once:
nearly every text a search reads is in that range.")

(defun fold-char (char)
  "The text CHAR folds to, which may be empty (a separate mark)."
  (let ((code (char-code char)))
    (if (< code #x250)
        (aref +search-latin-folds+ code)
        (fold-char-slowly char))))

(defun search-fold (text)
  "TEXT folded as every search compares it (spec/ui.md 6.4), and as a second
value, for each character of the fold, the index in TEXT of the character it
came from."
  (let ((folded (make-array (length text) :element-type 'character :fill-pointer 0
                                          :adjustable t))
        (from (make-array (length text) :element-type 'fixnum :fill-pointer 0 :adjustable t))
        (last #\Space))
    (loop for char across text
          for index from 0
          do (loop for each across (fold-char char)
                   for c = (if (search-space-p each) #\Space each)
                   unless (or (and (char= c #\Space) (char= last #\Space))
                              (and (char= c #\a) (char= last #\a)))
                     do (vector-push-extend c folded)
                        (vector-push-extend index from)
                        (setf last c)))
    (when (and (plusp (length folded)) (char= (char folded (1- (length folded))) #\Space))
      (decf (fill-pointer folded))
      (decf (fill-pointer from)))
    (values (coerce folded 'simple-string) from)))

(defun search-identifier-key (text)
  "TEXT as an identifier is compared: folded, without spaces and the signs
+ - . # ( ) /."
  (remove-if (lambda (c) (find c " +-.#()/")) (search-fold text)))

;;; ------------------------------------------------------------------
;;; The query

(defclass search-query ()
  ((text :initarg :text :reader search-query-text :type string
         :documentation "What was typed, as it was typed.")
   (folded :initarg :folded :reader search-query-folded :type string
           :documentation "What was typed, folded.")
   (words :initarg :words :reader search-query-words :type list
          :documentation "The folded words of what was typed.")
   (identifier :initarg :identifier :reader search-query-identifier :type string
               :documentation "What was typed as an identifier is compared.")
   (kinds :initarg :kinds :initform nil :reader search-query-kinds :type list
          :documentation "The kinds asked for, keys such as \"customer\"; NIL for all."))
  (:documentation "A search: what was typed and the kinds asked for (spec/ui.md 6.4)."))

(defun make-search-query (text &key kinds)
  "The search for TEXT, a string, among KINDS (kind keys, NIL for all)."
  (check-type text string)
  (let ((folded (search-fold text)))
    (make-instance 'search-query :text text :folded folded
                                 :words (remove "" (uiop:split-string folded :separator " ")
                                                :test #'string=)
                                 :identifier (search-identifier-key text)
                                 :kinds kinds)))

(defun search-query-wants-p (query kind)
  "True when QUERY asks for results of KIND, a kind key."
  (let ((kinds (search-query-kinds query)))
    (or (null kinds) (and (member kind kinds :test #'string=) t))))

;;; ------------------------------------------------------------------
;;; The rule

(defun word-start-p (folded index)
  "True when INDEX starts a word of FOLDED: its first character, or one after
a character that is not a letter or a digit."
  (or (zerop index) (not (alphanumericp (char folded (1- index))))))

(defun word-starts-p (word folded)
  "True when WORD is the start of a word of FOLDED."
  (loop for start = (search word folded) then (search word folded :start2 (1+ start))
        while start
        thereis (word-start-p folded start)))

(defun folded-texts (texts)
  (loop for text in texts
        when (and (stringp text) (plusp (length text)))
          collect (search-fold text)))

(defun identifier-score (query identifiers)
  "100 when QUERY is one of IDENTIFIERS, 90 when it holds a digit and starts
one from three characters on, else NIL: the start of a number counts, as
of an order's or a phone's, and the start of an email does not."
  (let* ((key (search-query-identifier query))
         (number (find-if #'digit-char-p key)))
    (when (plusp (length key))
      (loop with best = nil
            for identifier in identifiers
            when (and (stringp identifier) (plusp (length identifier)))
              do (let ((candidate (search-identifier-key identifier)))
                   (cond ((string= key candidate) (return 100))
                         ((and number (>= (length key) 3) (< (length key) (length candidate))
                               (string= key candidate :end2 (length key)))
                          (setf best 90))))
            finally (return best)))))

(defun names-score (query names)
  "The score of QUERY's words, all found, by NAMES, folded: 80, 60, 45 or 25,
or 10 when they are not all in the names."
  (let ((whole (search-query-folded query))
        (words (search-query-words query)))
    (flet ((in-names-p (test)
             (every (lambda (word) (some (lambda (name) (funcall test word name)) names))
                    words)))
      (cond ((member whole names :test #'string=) 80)
            ((some (lambda (name) (string-prefix-p whole name)) names) 60)
            ((in-names-p #'word-starts-p) 45)
            ((in-names-p (lambda (word name) (search word name))) 25)
            (t 10)))))

(defun search-match (query &key names texts identifiers)
  "The score of a record by the one rule (spec/ui.md 6.4), or NIL when it does
not match QUERY, a SEARCH-QUERY.  NAMES are the texts that name the record,
TEXTS the others it is found by, IDENTIFIERS the values found only whole or
by their start (a number, an email, a phone number); each a list of strings,
NILs and empty strings ignored.  The record matches when every word of the
query is in one of the names or texts, folded, in any order; or when the
whole query is one of its identifiers (100), or, holding a digit, their
start from three characters on (90).  Otherwise the score is 80 when a name is the query, 60
when one starts with it, 45 when every word starts a word of the names, 25
when every word is in the names, and 10 when some word is only in the
texts."
  (check-type query search-query)
  (let* ((names (folded-texts names))
         (all (append names (folded-texts texts)))
         (words (search-query-words query))
         (by-words (and words
                        (every (lambda (word) (some (lambda (text) (search word text)) all))
                               words)
                        (names-score query names))))
    (let ((by-identifier (identifier-score query identifiers)))
      (if (and by-words by-identifier) (max by-words by-identifier) (or by-identifier by-words)))))

(defun search-mark-ranges (query text)
  "Where in TEXT the words of QUERY are found, as a sorted list of (START .
END) ranges of TEXT's own characters, overlapping ones joined: for each
word its first match at the start of a word, else its first anywhere."
  (multiple-value-bind (folded from) (search-fold text)
    (let ((ranges '()))
      (dolist (word (search-query-words query))
        (let ((start (or (loop for at = (search word folded) then (search word folded :start2 (1+ at))
                               while at
                               when (word-start-p folded at) return at)
                         (search word folded))))
          (when start
            (let ((end (+ start (length word))))
              (push (cons (aref from start)
                          (if (< end (length folded)) (aref from end) (length text)))
                    ranges)))))
      (let ((joined '()))
        (dolist (range (sort ranges #'< :key #'car) (nreverse joined))
          (if (and joined (<= (car range) (cdr (first joined))))
              (setf (cdr (first joined)) (max (cdr range) (cdr (first joined))))
              (push (cons (car range) (cdr range)) joined)))))))

;;; ------------------------------------------------------------------
;;; Results

(defclass search-result ()
  ((kind :initarg :kind :reader search-result-kind :type string
         :documentation "The kind's key, in English, such as \"customer\".")
   (label :initarg :label :reader search-result-label :type string
          :documentation "The kind's word in the page's language.")
   (icon :initarg :icon :initform :file :reader search-result-icon :type keyword
         :documentation "The kind's icon, an icon's name.")
   (title :initarg :title :reader search-result-title :type string
          :documentation "The record's name.")
   (meta :initarg :meta :initform nil :reader search-result-meta :type list
         :documentation "Short texts about the record, shown after the kind's word.")
   (href :initarg :href :reader search-result-href :type string
         :documentation "The record's page.")
   (score :initarg :score :reader search-result-score :type integer
          :documentation "What the rule gave it.")
   (id :initarg :id :initform nil :reader search-result-id
       :documentation "The record's id, or NIL."))
  (:documentation "One thing a search found (spec/ui.md 6.4)."))

(defun make-search-result (&key kind label icon title meta href score id)
  "A result of a search: KIND a kind's key, LABEL its word, ICON its icon,
TITLE the record's name, META a list of short texts, HREF its page, SCORE
what SEARCH-MATCH gave it and ID the record's id."
  (check-type kind string)
  (check-type title string)
  (check-type href string)
  (check-type score integer)
  (make-instance 'search-result
                 :kind kind :label (princ-to-string (or label kind)) :icon (or icon :file)
                 :title title :href href :score score :id id
                 :meta (loop for each in meta
                             when (and each (plusp (length (princ-to-string each))))
                               collect (princ-to-string each))))

(defparameter +search-per-kind+ 5
  "The most results of one kind a search shows (spec/ui.md 6.4).")

(defparameter +search-most+ 20
  "The most results a search shows in all.")

(defun search-entity (query entity &key where keep kind label icon title names texts identifiers
                                       meta href (score #'identity))
  "The best results of QUERY among the records of ENTITY, a class name, at most
+SEARCH-PER-KIND+, best first and the newest first among equals; NIL when
QUERY does not want KIND.  WHERE, as SELECT takes it, narrows the records
read, and KEEP, a function of a record, those searched.  TITLE, NAMES, TEXTS, IDENTIFIERS, META and HREF
are functions of a record: TITLE its name, NAMES the texts that name it (its
title when omitted), TEXTS and IDENTIFIERS as SEARCH-MATCH takes them, META
a list of short texts, HREF its page.  SCORE, a function of the rule's
score, may lower it.  It reads every record of ENTITY in the current
transaction, so the record policies decide what the actor finds."
  (check-type kind string)
  (when (search-query-wants-p query kind)
    (let ((scored '()))
      (dolist (record (select entity :where where))
        (let ((match (and (or (null keep) (funcall keep record))
                          (search-match query
                                        :names (if names (funcall names record)
                                                   (list (funcall title record)))
                                        :texts (and texts (funcall texts record))
                                        :identifiers (and identifiers
                                                          (funcall identifiers record))))))
          (when match (push (cons (funcall score match) record) scored))))
      ;; SCORED holds the newest first: a stable sort keeps them so.
      (loop for (points . record) in (stable-sort scored #'> :key #'car)
            repeat +search-per-kind+
            collect (make-search-result :kind kind :label label :icon icon
                                        :title (funcall title record)
                                        :meta (and meta (funcall meta record))
                                        :href (funcall href record) :score points
                                        :id (entity-id record))))))

;;; ------------------------------------------------------------------
;;; The seam

(defgeneric search-records (application query actor)
  (:method-combination traced-protocol)
  (:documentation "What of APPLICATION's records QUERY, a SEARCH-QUERY, finds for ACTOR,
as a list of SEARCH-RESULTs (spec/ui.md 6.4).  A module specialises it on its
mixin and a client on its application class or a feature; each method
returns its own results appended to (CALL-NEXT-METHOD)'s, so every
contributor's are kept.  It runs in a read transaction with *ACTOR* bound to
ACTOR.  The default, Tun's own method and the least specific, answers none.")
  (:method (application query actor)
    (declare (ignore application query actor))
    nil))
(register-extension-protocol
 'search-records "rule" :point "search"
 :description "A module or the client says what of its records the application's one search finds.")

(defun search-contributors-p (application)
  "True when a method of a module APPLICATION enables, or of the client,
besides Tun's own, says what APPLICATION's search finds."
  (let ((enabled (mapcar (lambda (entry) (module-mixin (first entry)))
                         (enabled-modules application)))
        (mixins (mapcar #'module-mixin *loaded-modules*)))
    (some (lambda (method)
            (let ((specializer (first (closer-mop:method-specializers method))))
              (or (not (typep specializer 'class))
                  (let ((name (class-name specializer)))
                    (and (not (eq name t))
                         (or (not (member name mixins)) (member name enabled)))))))
          (compute-applicable-methods #'search-records
                                      (list application (make-search-query "") nil)))))

(defun search-order (results)
  "RESULTS in the order a search shows them, best score first, then by kind in
the order the kinds first came, then as they came: at most +SEARCH-PER-KIND+
of a kind and +SEARCH-MOST+ in all."
  (let ((kinds '()) (counts (make-hash-table :test 'equal)))
    (dolist (result results)
      (pushnew (search-result-kind result) kinds :test #'string=))
    (setf kinds (reverse kinds))
    (let ((sorted (stable-sort (copy-list results)
                               (lambda (a b)
                                 (or (> (search-result-score a) (search-result-score b))
                                     (and (= (search-result-score a) (search-result-score b))
                                          (< (position (search-result-kind a) kinds
                                                       :test #'string=)
                                             (position (search-result-kind b) kinds
                                                       :test #'string=))))))))
      (loop for result in sorted
            for kind = (search-result-kind result)
            when (<= (incf (gethash kind counts 0)) +search-per-kind+)
              collect result into kept
            when (>= (length kept) +search-most+) return kept
            finally (return kept)))))
