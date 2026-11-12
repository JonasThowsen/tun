;;;; core/search.lisp -- the application's one search (spec/ui.md 6.4): the
;;;; rule every search matches by, the results, and the seam a module or a
;;;; client says what of its records can be found through.
;;;;
;;;; The rule is pure: text is folded (case, marks, a few letters, a run of
;;;; «a», spaces), every word of the query must be in one of a record's
;;;; texts, and the whole query may be one of its identifiers or their
;;;; start.  SEARCH-MATCH scores a record by it; SEARCH-MARK-RANGES says
;;;; which stored characters a title's match covers.
;;;;
;;;; SEARCH-MATCH runs for every record a search reads, so it folds into one
;;;; buffer per search (FOLD-INTO-BUFFER) and compares an identifier as it
;;;; folds (IDENTIFIER-COMPARISON), allocating only for a record every word
;;;; was found in; SEARCH-FOLD, which also says where each folded character
;;;; came from, is for the marks of the few results shown.

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
;;; Folding fast, for the rule

(deftype folded-string () '(simple-array character (*)))

(defun fold-entry (char)
  "What CHAR folds to as the rule reads it, spaces as #\\Space: a character
when it is one, else a string (empty, or of several)."
  (let ((folded (map 'string (lambda (c) (if (search-space-p c) #\Space c)) (fold-char char))))
    (if (= 1 (length folded))
        (char folded 0)
        (coerce folded 'folded-string))))

(defparameter +search-fold-entries+
  (let ((table (make-array #x250)))
    (dotimes (code #x250 table)
      (setf (svref table code) (fold-entry (code-char code)))))
  "FOLD-ENTRY of every character up to Latin Extended-B, worked out once.")

(defparameter +search-ascii-folds+
  (coerce (loop for code below 128 collect (fold-entry (code-char code))) 'folded-string)
  "FOLD-ENTRY of every ASCII character, each one character.")

(defvar *fold-buffer* nil
  "The string FOLD-INTO-BUFFER folds into, bound for one search by
WITH-FOLD-BUFFER and grown as a text needs; NIL outside a search.")

(defmacro with-fold-buffer (&body body)
  "Run BODY with *FOLD-BUFFER* bound to a buffer of its own unless one is."
  `(flet ((body () ,@body))
     (if *fold-buffer*
         (body)
         (let ((*fold-buffer* (make-string 256)))
           (body)))))

(defmacro do-folded-characters ((char text) &body body)
  "Run BODY with CHAR bound to each character of TEXT folded as SEARCH-FOLD
folds it, runs of spaces and of «a» made one, but with a space at the end
kept (the callers skip spaces where it matters)."
  (let ((last (gensym "LAST")) (each (gensym "EACH")) (entry (gensym "ENTRY"))
        (code (gensym "CODE")) (from (gensym "FROM")) (ascii (gensym "ASCII"))
        (entries (gensym "ENTRIES")))
    `(let ((,last #\Space)
           (,ascii +search-ascii-folds+)
           (,entries +search-fold-entries+))
       (declare (type character ,last) (type folded-string ,ascii)
                (type simple-vector ,entries))
       (flet ((,each (,char)
                (declare (type character ,char))
                (unless (or (and (char= ,char #\Space) (char= ,last #\Space))
                            (and (char= ,char #\a) (char= ,last #\a)))
                  (setf ,last ,char)
                  ,@body)))
         (declare (inline ,each))
         (flet ((,from (,code)
                  (declare (type (integer 0 (,char-code-limit)) ,code))
                  (if (< ,code 128)
                      (,each (schar ,ascii ,code))
                      (let ((,entry (if (< ,code #x250)
                                        (svref ,entries ,code)
                                        (fold-entry (code-char ,code)))))
                        (if (characterp ,entry)
                            (,each ,entry)
                            (loop for c across (the folded-string ,entry) do (,each c)))))))
           (declare (inline ,from))
           (etypecase ,text
             (folded-string (loop for c across ,text do (,from (char-code c))))
             (simple-base-string (loop for c across ,text do (,from (char-code c))))
             (string (loop for c across ,text do (,from (char-code c))))))))))

(defun fold-into-buffer (text)
  "Fold TEXT, a string, as SEARCH-FOLD folds it into *FOLD-BUFFER*, which
must be bound, growing it as needed: the length of the fold."
  (declare (optimize (speed 3) (safety 1)))
  (let ((buffer *fold-buffer*) (end 0))
    (declare (type folded-string buffer) (type fixnum end))
    (do-folded-characters (char text)
      (when (= end (length buffer))
        (let ((larger (make-string (* 2 (length buffer)))))
          (replace larger buffer)
          (setf buffer larger *fold-buffer* larger)))
      (setf (schar buffer end) char)
      (incf end))
    (if (and (plusp end) (char= (schar buffer (1- end)) #\Space))
        (1- end)
        end)))

(defun fold-to-string (text)
  "TEXT folded as SEARCH-FOLD folds it, without the indexes."
  (with-fold-buffer
    (subseq (the folded-string *fold-buffer*) 0 (fold-into-buffer text))))

(defun folded-search (word text end &optional (start 0))
  "The index in TEXT, below END, from START, where WORD is found, or NIL: CL's
SEARCH for the folded strings the rule compares."
  (declare (optimize (speed 3) (safety 1))
           (type folded-string word text) (type fixnum end start))
  (let ((length (length word)))
    (when (plusp length)
      (let ((first (schar word 0)))
        (loop for at of-type fixnum from start to (- end length)
              when (and (char= (schar text at) first)
                        (loop for k of-type fixnum from 1 below length
                              always (char= (schar text (+ at k)) (schar word k))))
                return at)))))

(defun identifier-comparison (key text)
  "How KEY, a query's identifier key, compares with TEXT as an identifier
(SEARCH-IDENTIFIER-KEY), worked out as TEXT folds: :WHOLE when they are the
same, :START when KEY is a shorter start of it, else NIL."
  (declare (optimize (speed 3) (safety 1)) (type folded-string key))
  (let ((at 0) (length (length key)))
    (declare (type fixnum at length))
    (do-folded-characters (char text)
      (unless (find char " +-.#()/")
        (cond ((= at length) (return-from identifier-comparison :start))
              ((char/= char (schar key at)) (return-from identifier-comparison nil))
              (t (incf at)))))
    (and (= at length) :whole)))

;;; ------------------------------------------------------------------
;;; Phone numbers (spec/ui.md 6.4)

(defun country-code-length (first second)
  "The length of the E.164 country code whose first two digits are FIRST and
SECOND, characters: 1 and 7 are one digit, the two-digit codes are listed,
every other is three; NIL for a code starting with 0."
  (let ((two (+ (* 10 (digit-char-p first)) (digit-char-p second))))
    (cond ((char= first #\0) nil)
          ((find first "17") 1)
          ((or (member two '(20 27 30 31 32 33 34 36 39 40 41 51 52 53 54 55 56 57 58
                             60 61 62 63 64 65 66 81 82 84 86 90 91 92 93 94 95 98))
               (<= 43 two 49))
           2)
          (t 3))))

(defun phone-national-start (text)
  "The index in TEXT where its national number starts when TEXT is a phone
number written with its country code: «+» or «00», the code, and the number,
holding only digits, spaces and «- . ( ) /»; else NIL."
  (let* ((length (length text))
         (start (position-if-not #'search-space-p text))
         (after (cond ((null start) nil)
                      ((char= (char text start) #\+) (1+ start))
                      ((and (< (1+ start) length) (char= (char text start) #\0)
                            (char= (char text (1+ start)) #\0))
                       (+ start 2)))))
    (when after
      (let ((first nil) (second nil) (digits 0))
        (loop for index from after below length
              for char = (char text index)
              do (cond ((digit-char-p char)
                        (incf digits)
                        (cond ((null first) (setf first char))
                              ((null second) (setf second char))))
                       ((or (search-space-p char) (find char "-.()/")))
                       (t (return-from phone-national-start nil))))
        (let ((code (and second (country-code-length first second))))
          (when (and code (> digits code))
            ;; Past the code's digits, and the signs and spaces after them.
            (loop with seen = 0
                  for index from after below length
                  when (digit-char-p (char text index))
                    do (when (= seen code) (return index))
                       (incf seen))))))))

(defun search-phone-forms (text)
  "The identifiers a phone number TEXT is found by (spec/ui.md 6.4): TEXT,
and when it is written with its country code («+47 912 34 567», «0047 …»),
its national number («91234567») and, unless that starts with 0, the national
number with a leading 0 («091234567»), as most countries write it; any other
TEXT answers itself alone, NIL or an empty TEXT nothing.  Give them to
SEARCH-MATCH, SEARCH-ENTITY or SEARCH-AMONG as identifiers."
  (cond ((or (null text) (zerop (length text))) nil)
        (t (check-type text string)
           (let ((start (phone-national-start text)))
             (if start
                 (let ((national (coerce (loop for index from start below (length text)
                                               for char = (char text index)
                                               when (digit-char-p char) collect char)
                                         'string)))
                   (if (char= (char national 0) #\0)
                       (list text national)
                       (list text national (concatenate 'string "0" national))))
                 (list text))))))

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
   (starts :initarg :starts :reader search-query-starts :type simple-bit-vector
           :documentation "For each character up to Latin Extended-B, 1 when its fold holds
the first character of a word: a text with none of them holds no word.")
   (kinds :initarg :kinds :initform nil :reader search-query-kinds :type list
          :documentation "The kinds asked for, keys such as \"customer\"; NIL for all."))
  (:documentation "A search: what was typed and the kinds asked for (spec/ui.md 6.4)."))

(defun make-search-query (text &key kinds)
  "The search for TEXT, a string, among KINDS (kind keys, NIL for all)."
  (check-type text string)
  (let ((folded (search-fold text)))
    (flet ((folded (string) (coerce string 'folded-string)))
      (let ((words (mapcar #'folded (remove "" (uiop:split-string folded :separator " ")
                                            :test #'string=))))
        (make-instance 'search-query :text text :folded (folded folded) :words words
                                     :identifier (folded (search-identifier-key text))
                                     :starts (word-starts-table words)
                                     :kinds kinds)))))

(defun word-starts-table (words)
  "For each character up to Latin Extended-B, 1 when its fold holds the first
character of one of WORDS."
  (let ((table (make-array #x250 :element-type 'bit :initial-element 0))
        (firsts (remove-duplicates (map 'list (lambda (word) (char word 0)) words))))
    (dotimes (code #x250 table)
      (let ((entry (if (< code 128)
                       (schar +search-ascii-folds+ code)
                       (svref +search-fold-entries+ code))))
        (when (if (characterp entry)
                  (member entry firsts)
                  (some (lambda (first) (find first entry)) firsts))
          (setf (sbit table code) 1))))))

(defun text-may-hold-p (text starts)
  "True unless TEXT surely holds no word whose first characters STARTS marks:
none of its characters folds to one, and none is beyond the table."
  (declare (optimize (speed 3) (safety 1)) (type simple-bit-vector starts))
  (macrolet ((scan (type)
               `(loop for c across (the ,type text)
                      for code = (char-code c)
                      thereis (or (>= code #x250) (= 1 (sbit starts code))))))
    (etypecase text
      (folded-string (scan folded-string))
      (simple-base-string (scan simple-base-string))
      (string (scan string)))))

(defvar *search-replaced* '()
  "The (KIND MODULE) entries of SEARCH-REPLACEMENTS for the search running
now, bound by SEARCH-RECORDS's own :AROUND method.")

(defun search-replaced-p (kind module)
  "True when the search running now has MODULE's contributor of KIND replaced."
  (and module
       (find-if (lambda (entry) (and (string= kind (first entry)) (string= module (second entry))))
                *search-replaced*)
       t))

(defun search-query-wants-p (query kind)
  "True when QUERY asks for results of KIND, a kind key, of the contributor
asking: false for a kind the caller left out, and while a module's method of
SEARCH-RECORDS runs, for a kind SEARCH-REPLACEMENTS says another answers in
place of that module's (spec/ui.md 6.4)."
  (let ((kinds (search-query-kinds query)))
    (and (or (null kinds) (member kind kinds :test #'string=))
         (not (search-replaced-p kind *protocol-method-module*)))))

;;; ------------------------------------------------------------------
;;; The rule

;;; Every function here but SEARCH-MATCH takes texts already folded, as
;;; FOLDED-STRINGs.

(defun word-start-p (folded index)
  "True when INDEX starts a word of FOLDED: its first character, or one after
a character that is not a letter or a digit."
  (or (zerop index) (not (alphanumericp (char folded (1- index))))))

(defun word-starts-p (word folded)
  "True when WORD is the start of a word of FOLDED."
  (let ((end (length folded)))
    (loop for start = (folded-search word folded end) then (folded-search word folded end (1+ start))
          while start
          thereis (word-start-p folded start))))

(defun word-in-p (word folded)
  "True when WORD is in FOLDED."
  (and (folded-search word folded (length folded)) t))

(defun identifier-score (query identifiers)
  "100 when QUERY is one of IDENTIFIERS, 90 when it holds a digit and starts
one from three characters on, else NIL: the start of a number counts, as
of an order's or a phone's, and the start of an email does not."
  (let* ((key (search-query-identifier query))
         (start-counts (and (find-if #'digit-char-p key) (>= (length key) 3))))
    (when (plusp (length key))
      (loop with best = nil
            for identifier in identifiers
            when (and (stringp identifier) (plusp (length identifier)))
              do (case (identifier-comparison key identifier)
                   (:whole (return 100))
                   (:start (when start-counts (setf best 90))))
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
            ((in-names-p #'word-in-p) 25)
            (t 10)))))

(defun words-found-p (query names texts)
  "True when every word of QUERY is in one of NAMES and TEXTS, folded: each
folded into the search's buffer in turn, until every word is found, and a
text with no character that folds to a word's first left unfolded."
  (let* ((words (search-query-words query))
         (starts (search-query-starts query))
         (left (1- (ash 1 (length words)))))
    (declare (type unsigned-byte left))
    (flet ((look (text)
             ;; Clears in LEFT the bit of each word TEXT holds.
             (when (and (stringp text) (plusp (length text)) (text-may-hold-p text starts))
               (let ((end (fold-into-buffer text))
                     (buffer *fold-buffer*))
                 (loop for word in words
                       for bit from 0
                       when (and (logbitp bit left) (folded-search word buffer end))
                         do (setf left (logandc2 left (ash 1 bit))))))))
      (dolist (text names) (look text) (when (zerop left) (return-from words-found-p t)))
      (dolist (text texts) (look text) (when (zerop left) (return-from words-found-p t)))
      nil)))

(defun search-match (query &key names texts identifiers)
  "The score of a record by the one rule (spec/ui.md 6.4), or NIL when it does
not match QUERY, a SEARCH-QUERY.  NAMES are the texts that name the record,
TEXTS the others it is found by, IDENTIFIERS the values found only whole or
by their start (a number, an email, a phone number's SEARCH-PHONE-FORMS);
each a list of strings, NILs and empty strings ignored.  The record matches
when every word of the query is in one of the names or texts, folded, in any
order; or when the whole query is one of its identifiers (100), or, holding a
digit, their start from three characters on (90).  Otherwise the score is 80
when a name is the query, 60 when one starts with it, 45 when every word
starts a word of the names, 25 when every word is in the names, and 10 when
some word is only in the texts."
  (check-type query search-query)
  (with-fold-buffer
    (let* ((words (search-query-words query))
           (by-words (and words
                          (words-found-p query names texts)
                          (names-score query (loop for name in names
                                                   when (and (stringp name) (plusp (length name)))
                                                     collect (fold-to-string name)))))
           (by-identifier (identifier-score query identifiers)))
      (if (and by-words by-identifier) (max by-words by-identifier) (or by-identifier by-words)))))

(defun identifier-mark-range (query text)
  "The (START . END) range of TEXT's own characters that QUERY covers when
TEXT, as an identifier, is what QUERY found whole or by its start (as
IDENTIFIER-SCORE counts it), or, for a phone number written with its country
code, when its national number is (SEARCH-PHONE-FORMS), else NIL."
  (let ((key (search-query-identifier query)))
    (when (plusp (length key))
      (multiple-value-bind (folded from) (search-fold text)
        (let ((kept (coerce (loop for char across folded
                                  for index from 0
                                  unless (find char " +-.#()/") collect (cons char (aref from index)))
                            'vector))
              (start-counts (and (find-if #'digit-char-p key) (>= (length key) 3))))
          (flet ((range-from (offset typed)
                   ;; TYPED, the end of KEY, as the kept characters from OFFSET.
                   (let ((left (- (length kept) offset)))
                     (when (and (plusp (length typed)) (<= (length typed) left)
                                (every (lambda (char pair) (char= char (car pair)))
                                       typed (subseq kept offset))
                                (or (= (length typed) left) start-counts))
                       (cons (cdr (aref kept offset))
                             (1+ (cdr (aref kept (+ offset (length typed) -1)))))))))
            (or (range-from 0 key)
                (let ((national (phone-national-start text)))
                  (when national
                    (let ((offset (count-if (lambda (pair) (< (cdr pair) national)) kept)))
                      (or (range-from offset key)
                          (and (char= (char key 0) #\0)
                               (char/= (car (aref kept offset)) #\0)
                               (range-from offset (subseq key 1))))))))))))))

(defun search-mark-ranges (query text &key identifier)
  "Where in TEXT the words of QUERY are found, as a sorted list of (START .
END) ranges of TEXT's own characters, overlapping ones joined: for each
word its first match at the start of a word, else its first anywhere.
With IDENTIFIER, a TEXT no word is found in, but which QUERY found as an
identifier, has the one range the query covers."
  (let ((ranges (word-mark-ranges query text)))
    (or ranges
        (let ((range (and identifier (identifier-mark-range query text))))
          (and range (list range))))))

(defun word-mark-ranges (query text)
  "SEARCH-MARK-RANGES by the words of QUERY alone."
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
       :documentation "The record's id, or NIL.")
   (matched :initarg :matched :initform nil :reader search-result-matched
            :type (or null string)
            :documentation "What the record was found by when neither its title nor its
meta shows it, as SEARCH-EXCERPT cuts it, or NIL.")
   (module :initarg :module :initform nil :reader search-result-module
           :documentation "The module (or \"client\") whose method of SEARCH-RECORDS made it,
for SEARCH-REPLACEMENTS; NIL when made outside one."))
  (:documentation "One thing a search found (spec/ui.md 6.4)."))

(defun make-search-result (&key kind label icon title meta href score id matched)
  "A result of a search: KIND a kind's key, LABEL its word, ICON its icon,
TITLE the record's name, META a list of short texts, HREF its page, SCORE
what SEARCH-MATCH gave it and ID the record's id.  MATCHED, a text or NIL,
is what the record was found by when neither TITLE nor META shows it; the
result's line shows it (spec/ui.md 6.4, «Why it was found»)."
  (check-type kind string)
  (check-type title string)
  (check-type href string)
  (check-type score integer)
  (check-type matched (or null string))
  (make-instance 'search-result
                 :kind kind :label (princ-to-string (or label kind)) :icon (or icon :file)
                 :title title :href href :score score :id id
                 :module *protocol-method-module*
                 :matched (and matched (plusp (length matched)) matched)
                 :meta (loop for each in meta
                             when (and each (plusp (length (princ-to-string each))))
                               collect (princ-to-string each))))

(defparameter +search-per-kind+ 5
  "The most results of one kind a search shows (spec/ui.md 6.4).")

(defparameter +search-most+ 20
  "The most results a search shows in all.")

(defparameter +search-excerpt-length+ 80
  "The most characters of a text a result shows as what it was found by.")

(defun search-excerpt (query text)
  "TEXT as a result shows what it was found by (spec/ui.md 6.4): whole when
it is +SEARCH-EXCERPT-LENGTH+ characters or less, else from the start of
the word holding QUERY's first mark, «…» before it unless that is TEXT's
start, at most +SEARCH-EXCERPT-LENGTH+ characters of it and «…» after it
when it is cut."
  (if (<= (length text) +search-excerpt-length+)
      text
      (let* ((first-mark (car (first (search-mark-ranges query text :identifier t))))
             (start (if first-mark
                        (or (position-if (lambda (c) (search-space-p c)) text
                                         :end first-mark :from-end t)
                            -1)
                        -1))
             (from (1+ start))
             (to (min (length text) (+ from +search-excerpt-length+))))
        (format nil "~:[~;…~]~a~:[~;…~]" (plusp from) (subseq text from to)
                (< to (length text))))))

(defun search-matched-text (query title meta candidates)
  "What a result shows it was found by: NIL when TITLE or a text of META
holds a mark of QUERY, else the excerpt of the first of CANDIDATES (its
names, texts and identifiers) that holds one, or NIL."
  (flet ((marked-p (text identifier)
           (and (stringp text) (plusp (length text))
                (search-mark-ranges query text :identifier identifier))))
    (unless (or (marked-p title nil)
                (some (lambda (text) (marked-p (princ-to-string text) t)) (remove nil meta)))
      (let ((found (find-if (lambda (text) (marked-p text t)) candidates)))
        (and found (search-excerpt query found))))))

(defun row-id (row)
  "The id of ROW: a record's id, a JSON object's \"id\", a property list's :ID."
  (typecase row
    (stored-entity (entity-id row))
    (hash-table (values (gethash "id" row)))
    (list (getf row :id))
    (t nil)))

(defun search-among (query rows &key keep kind label icon title names texts identifiers meta href
                                     id (score #'identity))
  "The best results of QUERY among ROWS, at most +SEARCH-PER-KIND+, best first and
the newest first among equals; NIL when QUERY does not want KIND (spec/ui.md
6.4).  ROWS, in the order they were read, oldest first, are records, the JSON
objects a DEFINE-QUERY of rows answers, or property lists.  KEEP, a function
of a row, says which are searched.  TITLE, NAMES, TEXTS, IDENTIFIERS, META and
HREF are functions of a row: TITLE its name, NAMES the texts that name it (its
title when omitted), TEXTS and IDENTIFIERS as SEARCH-MATCH takes them, META a
list of short texts, HREF its page; ID its id, by default ROW-ID's.  SCORE, a
function of the rule's score, may lower it.  Each result kept carries what it
was found by (SEARCH-MATCHED-TEXT)."
  (check-type kind string)
  (when (search-query-wants-p query kind)
    (with-fold-buffer
      (flet ((names-of (row)
               (if names (funcall names row) (list (funcall title row)))))
        (let ((scored '()))
          (dolist (row rows)
            (let ((match (and (or (null keep) (funcall keep row))
                              (search-match query
                                            :names (names-of row)
                                            :texts (and texts (funcall texts row))
                                            :identifiers (and identifiers
                                                              (funcall identifiers row))))))
              (when match (push (cons (funcall score match) row) scored))))
          ;; SCORED holds the newest first: a stable sort keeps them so.
          (loop for (points . row) in (stable-sort scored #'> :key #'car)
                repeat +search-per-kind+
                collect (let ((name (funcall title row))
                              (facts (and meta (funcall meta row))))
                          (make-search-result
                           :kind kind :label label :icon icon :title name :meta facts
                           :href (funcall href row) :score points
                           :id (if id (funcall id row) (row-id row))
                           :matched (search-matched-text
                                     query name facts
                                     (remove-if-not #'stringp
                                                    (append (names-of row)
                                                            (and texts (funcall texts row))
                                                            (and identifiers
                                                                 (funcall identifiers row)))))))))))))

(defun search-entity (query entity &key where fields keep kind label icon title names texts
                                       identifiers meta href (score #'identity))
  "The best results of QUERY among the records of ENTITY, a class name, as
SEARCH-AMONG makes them of rows; NIL, without a read, when QUERY does not want
KIND.  WHERE, as SELECT takes it, narrows the records read, and FIELDS, a list
of the entity's fields' JSON names, reads only those (spec/store.md 2, item
11): the functions must then read no other.  KEEP, TITLE, NAMES, TEXTS,
IDENTIFIERS, META, HREF and SCORE are as SEARCH-AMONG takes them, functions of
a record.  It reads every record of ENTITY in the current transaction, so the
record policies decide what the actor finds."
  (check-type kind string)
  (when (search-query-wants-p query kind)
    (search-among query (select entity :where where :fields fields)
                  :keep keep :kind kind :label label :icon icon :title title :names names
                  :texts texts :identifiers identifiers :meta meta :href href
                  :id #'entity-id :score score)))

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

(defgeneric search-replacements (application)
  (:method-combination traced-protocol)
  (:documentation "The kinds APPLICATION answers itself in place of a module's
contributor, as a list of (KIND MODULE): KIND a kind's key, MODULE a module's
name as a lowercase string, such as (\"customer\" \"customers\") (spec/ui.md
6.4).  While MODULE's method of SEARCH-RECORDS runs, SEARCH-QUERY-WANTS-P is
false for KIND, so it reads nothing of it, and a result of KIND it makes all
the same is dropped; MODULE's other kinds and every other contributor's
results are kept.  A module specialises it on its mixin and a client on its
application class or a feature; each method returns its own entries appended
to (CALL-NEXT-METHOD)'s.  The default, Tun's own method, answers none.")
  (:method (application)
    (declare (ignore application))
    nil))
(register-extension-protocol
 'search-replacements "rule" :point "search_replacements"
 :description "A module or the client answers a kind of the search in place of a module's contributor.")

(defun checked-replacements (entries)
  "ENTRIES of SEARCH-REPLACEMENTS that name a kind and a loaded module; each
other is written to the error output and ignored."
  (loop for entry in entries
        if (and (consp entry) (consp (rest entry)) (stringp (first entry))
                (stringp (second entry)) (find-module (second entry)))
          collect (list (first entry) (second entry))
        else do (format *error-output* "~&;; tun search: ignored the replacement ~s, which ~
                                        names no kind and loaded module~%" entry)))

(defun replaced-result-p (result)
  "True when RESULT is of a kind the search running now has its module's
contributor replaced for."
  (search-replaced-p (search-result-kind result) (search-result-module result)))

(defmethod search-records :around (application query actor)
  ;; spec/ui.md 6.4: the replacements hold for the whole search, and one
  ;; buffer serves every record the contributors match.
  (declare (ignore query actor))
  (let ((*search-replaced* (checked-replacements (search-replacements application))))
    (with-fold-buffer
      (remove-if #'replaced-result-p (call-next-method)))))

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
