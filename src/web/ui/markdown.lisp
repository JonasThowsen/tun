;;;; web/ui/markdown.lisp -- MARKDOWN: text people and agents write, with the
;;;; parts of Markdown they use most (spec/ui.md 6.2).  The text is parsed
;;;; into markup (TUN.HTML), never into HTML: each of its characters ends in
;;;; a text node, which the renderer escapes, or is a mark the parser read.
;;;;
;;;; The rules are CommonMark's, made smaller.  Blocks are read line by line;
;;;; inline marks are read in one pass that keeps the brackets and the marks
;;;; of bold and italic on stacks, as CommonMark's own algorithm does, so the
;;;; time taken and the output stay linear in the text whatever it holds.

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defconstant +markdown-list-depth+ 4 "How deep lists nest.")
(defconstant +markdown-emphasis-depth+ 8 "How deep bold and italic nest.")
(defconstant +markdown-table-columns+ 20 "The most columns a table has.")
(defconstant +markdown-address-length+ 2048 "The longest address a link takes.")
(defconstant +markdown-title-length+ 256 "The longest title a link's address may have after it.")
(defconstant +markdown-label-length+ 80
  "Where a heading is cut when it labels a value in a table's card.")

;;; ------------------------------------------------------------------
;;; Queues: the children of what is being built, appended to at the end and
;;; joined to one another in constant time.

(defun make-queue () (cons nil nil))

(defun enqueue (item queue)
  (let ((cell (list item)))
    (if (car queue)
        (setf (cddr queue) cell (cdr queue) cell)
        (setf (car queue) cell (cdr queue) cell))
    queue))

(defun queue-join (queue other)
  "QUEUE with OTHER's items after its own; OTHER is not to be used again."
  (when (car other)
    (if (car queue)
        (setf (cddr queue) (car other) (cdr queue) (cdr other))
        (setf (car queue) (car other) (cdr queue) (cdr other))))
  queue)

(defun queue-items (queue)
  "QUEUE's items, adjacent texts joined into one."
  (let ((items '()) (texts '()))
    (flet ((flush ()
             (when texts
               (push (if (rest texts)
                         (with-output-to-string (out)
                           (dolist (text (reverse texts)) (write-string text out)))
                         (first texts))
                     items)
               (setf texts '()))))
      (dolist (item (car queue))
        (if (stringp item)
            (push item texts)
            (progn (flush) (push item items))))
      (flush))
    (nreverse items)))

;;; ------------------------------------------------------------------
;;; Characters and addresses

(defun markdown-space-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return #\Page)))

(defun ascii-punctuation-p (char)
  (find char "!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"))

(defun word-char-p (char)
  (and char (alphanumericp char)))

(defun starts-with-p (prefix text &optional (start 0))
  (let ((end (+ start (length prefix))))
    (and (<= end (length text))
         (string-equal prefix text :start2 start :end2 end))))

(defun markdown-address-p (address &key (paths t))
  "True when ADDRESS may be a link's: an http(s) URL, a mailto: address, or
with PATHS a path on the same site.  Nothing in it is a space or a control
character, and it is at most +MARKDOWN-ADDRESS-LENGTH+ long."
  (and (<= 1 (length address) +markdown-address-length+)
       (every (lambda (char) (and (char> char #\Space) (char/= char #\Rubout))) address)
       (or (and (starts-with-p "https://" address) (> (length address) 8))
           (and (starts-with-p "http://" address) (> (length address) 7))
           (and (starts-with-p "mailto:" address) (> (length address) 7))
           (and paths
                (char= (char address 0) #\/)
                (not (and (> (length address) 1)
                          (find (char address 1) "/\\")))))))

;;; ------------------------------------------------------------------
;;; Inline: code spans, bold and italic, links and escapes

(defstruct (delimiter (:constructor make-delimiter (char length opens closes)))
  "A run of * or _ that may open or close bold or italic."
  char length opens closes)

(defstruct (bracket (:constructor make-bracket (index)))
  "A [ that may start a link's text: its place among the tokens."
  index)

(defun delimiter-text (delimiter)
  (make-string (delimiter-length delimiter)
               :initial-element (delimiter-char delimiter)))

(defun backtick-runs (text)
  "The runs of backticks in TEXT: a hash table from a run's length to the
vector of the places where runs of that length start, in order."
  (let ((runs (make-hash-table)) (i 0) (end (length text)))
    (loop while (< i end)
          do (if (char= (char text i) #\`)
                 (let ((run-end (or (position #\` text :start i :test-not #'char=) end)))
                   (vector-push-extend i (or (gethash (- run-end i) runs)
                                             (setf (gethash (- run-end i) runs)
                                                   (make-array 4 :adjustable t :fill-pointer 0))))
                   (setf i run-end))
                 (incf i)))
    runs))

(defun next-run (runs length after)
  "Where the first run of LENGTH backticks that starts after AFTER starts, or NIL."
  (let ((starts (gethash length runs)))
    (when starts
      (let ((low 0) (high (length starts)))
        (loop while (< low high)
              do (let ((middle (floor (+ low high) 2)))
                   (if (> (aref starts middle) after)
                       (setf high middle)
                       (setf low (1+ middle)))))
        (when (< low (length starts)) (aref starts low))))))

(defun code-span-text (text start end)
  "The text of a code span between START and END: line breaks as spaces, and
one space taken from each end when both ends have one and it is not all spaces."
  (let ((code (substitute #\Space #\Newline (subseq text start end))))
    (if (and (>= (length code) 2)
             (char= (char code 0) #\Space)
             (char= (char code (1- (length code))) #\Space)
             (find #\Space code :test-not #'char=))
        (subseq code 1 (1- (length code)))
        code)))

(defun link-tail (text start)
  "The address of the ( at START, the part of [text](address \"title\") after the
brackets, and the place after its ), or NIL when there is none to read."
  (let ((end (length text)) (i (1+ start)))
    (flet ((skip-spaces ()
             (loop while (and (< i end) (member (char text i) '(#\Space #\Tab))) do (incf i))))
      (skip-spaces)
      (let ((address
              (if (and (< i end) (char= (char text i) #\<))
                  (let ((close (position-if (lambda (char) (find char "><
"))
                                            text :start (1+ i)
                                                 :end (min end (+ i 2 +markdown-address-length+)))))
                    (when (and close (char= (char text close) #\>))
                      (prog1 (subseq text (1+ i) close) (setf i (1+ close)))))
                  (let ((from i) (depth 0))
                    (loop while (and (< i end) (< (- i from) +markdown-address-length+))
                          do (let ((char (char text i)))
                               (cond ((or (markdown-space-p char) (char< char #\Space)) (return))
                                     ((char= char #\() (if (< depth 32) (incf depth) (return)))
                                     ((char= char #\)) (if (zerop depth) (return) (decf depth))))
                               (incf i)))
                    (when (zerop depth) (subseq text from i))))))
        (when address
          (skip-spaces)
          (when (and (< i end) (find (char text i) "\"'("))
            (let* ((closing (if (char= (char text i) #\() #\) (char text i)))
                   (close (position-if (lambda (char) (or (char= char closing) (char= char #\Newline)))
                                       text :start (1+ i)
                                            :end (min end (+ i 2 +markdown-title-length+)))))
              (unless (and close (char= (char text close) closing))
                (return-from link-tail nil))
              (setf i (1+ close))
              (skip-spaces)))
          (when (and (< i end) (char= (char text i) #\)))
            (values address (1+ i))))))))

(defun url-stop-p (char)
  "True for a character that ends a URL written on its own."
  (or (markdown-space-p char) (find char "<[]")))

(defun bare-url-end (text start stop)
  "Where the http(s) URL written on its own at START ends, or NIL: at STOP,
the first space, <, [ or ] after START, without its final punctuation or a )
that no ( matches.  A URL whose run to STOP is over the longest address
makes no link, so no more than that is ever looked at."
  (when (<= (- stop start) +markdown-address-length+)
    (let ((end stop)
          (unmatched (- (count #\) text :start start :end stop)
                        (count #\( text :start start :end stop))))
      (loop while (> end start)
            do (let ((char (char text (1- end))))
                 (cond ((find char ".,:;!?*_'\"") (decf end))
                       ((and (char= char #\)) (plusp unmatched))
                        (decf end)
                        (decf unmatched))
                       (t (return)))))
      (when (markdown-address-p (subseq text start end) :paths nil)
        end))))

(defun markdown-link (address children)
  (link* (list :href address) children))

(defun link-text-only (nodes)
  "NODES with every link in them, at any depth, replaced by its text: a
link's text holds no other link.  NODES are a link's text, so they hold only
text, code, bold, italic and links, and are nested no deeper than bold and
italic are."
  (mapcan (lambda (node)
            (cond ((and (consp node) (eq (first node) :a))
                   (link-text-only (nth-value 2 (tun.html:node-parts node))))
                  ((and (consp node) (keywordp (first node)))
                   (list (cons (first node) (link-text-only (rest node)))))
                  ((consp node) (link-text-only node))
                  (t (list node))))
          nodes))

(defun emphasis-node (length children)
  (ecase length
    (1 `(:em ,@children))
    (2 `(:strong ,@children))
    (3 `(:em (:strong ,@children)))))

(defstruct (frame (:constructor make-frame (delimiter)))
  "An opening mark of bold or italic and what follows it so far."
  delimiter (children (make-queue)) (depth 0))

(defun resolve-emphasis (tokens)
  "TOKENS as nodes: each pair of matching marks around what is between them
as bold or italic, the marks with no match as text (spec/ui.md 6.2).  The
frames of the opening marks are kept on a stack; BOTTOMS remembers, for
each kind of mark, how far down the stack no opening mark of that kind is,
so a closing mark with no match does not look through the stack again."
  (let ((stack (list (make-frame nil)))
        (height 1)
        (bottoms (make-hash-table :test #'equal)))
    (labels ((kind (delimiter) (cons (delimiter-char delimiter) (delimiter-length delimiter)))
             (add (item &optional (depth 0))
               (let ((top (first stack)))
                 (enqueue item (frame-children top))
                 (setf (frame-depth top) (max (frame-depth top) depth))))
             (pop-frame ()
               (decf height)
               (maphash (lambda (key bottom)
                          (when (> bottom height) (setf (gethash key bottoms) height)))
                        bottoms)
               (pop stack))
             (collapse ()
               ;; The top frame's mark had no match: it and its children go
               ;; to the frame below as they are.
               (let ((frame (pop-frame)) (below (first stack)))
                 (enqueue (delimiter-text (frame-delimiter frame)) (frame-children below))
                 (queue-join (frame-children below) (frame-children frame))
                 (setf (frame-depth below) (max (frame-depth below) (frame-depth frame)))))
             (opener-height (delimiter)
               ;; The height of the nearest frame opened by a mark like
               ;; DELIMITER, counted from the bottom, or NIL.
               (let ((bottom (gethash (kind delimiter) bottoms 1)))
                 (loop for frame in stack
                       for at downfrom height
                       while (> at bottom)
                       when (and (frame-delimiter frame)
                                 (eql (delimiter-char (frame-delimiter frame))
                                      (delimiter-char delimiter))
                                 (= (delimiter-length (frame-delimiter frame))
                                    (delimiter-length delimiter)))
                         return at
                       finally (setf (gethash (kind delimiter) bottoms) height)
                               (return nil))))
             (close-at (at delimiter)
               ;; Close the frame at height AT: the frames above it had no
               ;; match, and its own children become bold or italic, unless
               ;; that would nest too deep.
               (loop while (> height at) do (collapse))
               (let ((depth (1+ (frame-depth (first stack)))))
                 (if (> depth +markdown-emphasis-depth+)
                     (progn (collapse) (add (delimiter-text delimiter)))
                     (let ((frame (pop-frame)))
                       (add (emphasis-node (delimiter-length delimiter)
                                           (queue-items (frame-children frame)))
                            depth))))))
      (dolist (token tokens)
        (if (delimiter-p token)
            (let ((at (and (delimiter-closes token) (opener-height token))))
              (cond (at (close-at at token))
                    ((delimiter-opens token)
                     (push (make-frame token) stack)
                     (incf height))
                    (t (add (delimiter-text token)))))
            (add token)))
      (loop while (> height 1) do (collapse))
      (queue-items (frame-children (first stack))))))

(defun markdown-inline (text)
  "The nodes of TEXT, a paragraph's, a heading's, an item's or a cell's,
with its code spans, bold, italic, links and escapes (spec/ui.md 6.2)."
  (let ((tokens (make-array 16 :adjustable t :fill-pointer 0))
        (brackets '())
        (plain (make-string-output-stream))
        (runs (backtick-runs text))
        (end (length text))
        (url-stop -1)
        (url-end nil)
        (i 0))
    (labels ((flush ()
               (let ((chunk (get-output-stream-string plain)))
                 (when (plusp (length chunk)) (vector-push-extend chunk tokens))))
             (token (item) (flush) (vector-push-extend item tokens))
             (text-token (string) (token string))
             (previous () (and (> i 0) (char text (1- i))))
             (close-bracket ()
               ;; A ] at I: the link whose text the latest [ started, or text.
               (let ((bracket (pop brackets)))
                 (multiple-value-bind (address after)
                     (and bracket
                          (< (1+ i) end) (char= (char text (1+ i)) #\()
                          (link-tail text (1+ i)))
                   (if (and address (markdown-address-p address))
                       (let* ((from (progn (flush) (bracket-index bracket)))
                              (inner (coerce (subseq tokens (1+ from)) 'list)))
                         (setf (fill-pointer tokens) from)
                         (vector-push-extend
                          (markdown-link address (link-text-only (resolve-emphasis inner)))
                          tokens)
                         ;; A link's text holds no other link (CommonMark 6.3):
                         ;; the earlier [s can only be text now, as the
                         ;; tokens left over at the end are.
                         (setf brackets '())
                         (setf i after))
                       (progn (when bracket
                                (setf (aref tokens (bracket-index bracket)) "["))
                              (text-token "]")
                              (incf i)))))))
      (loop while (< i end)
            do (let ((char (char text i)))
                 (cond
                   ((and (char= char #\\) (< (1+ i) end) (ascii-punctuation-p (char text (1+ i))))
                    (write-char (char text (1+ i)) plain)
                    (incf i 2))
                   ((char= char #\`)
                    (let* ((run-end (or (position #\` text :start i :test-not #'char=) end))
                           (length (- run-end i))
                           (close (next-run runs length (1- run-end))))
                      (if close
                          (progn (token `(:code ,(code-span-text text run-end close)))
                                 (setf i (+ close length)))
                          (progn (write-string text plain :start i :end run-end)
                                 (setf i run-end)))))
                   ((find char "*_")
                    (let* ((run-end (or (position char text :start i :test-not #'char=) end))
                           (length (- run-end i))
                           (before (previous))
                           (after (and (< run-end end) (char text run-end)))
                           (opens (and after (not (markdown-space-p after))
                                       (or (char= char #\*) (not (word-char-p before)))))
                           (closes (and before (not (markdown-space-p before))
                                        (or (char= char #\*) (not (word-char-p after))))))
                      (if (and (<= length 3) (or opens closes))
                          (token (make-delimiter char length opens closes))
                          (write-string text plain :start i :end run-end))
                      (setf i run-end)))
                   ((char= char #\[)
                    (flush)
                    (let ((bracket (make-bracket (fill-pointer tokens))))
                      (vector-push-extend bracket tokens)
                      (push bracket brackets))
                    (incf i))
                   ((char= char #\])
                    (close-bracket))
                   ((char= char #\<)
                    (let ((close (position-if (lambda (char) (or (markdown-space-p char) (find char "<>")))
                                              text :start (1+ i)
                                                   :end (min end (+ i 2 +markdown-address-length+)))))
                      (if (and close (char= (char text close) #\>)
                               (markdown-address-p (subseq text (1+ i) close) :paths nil))
                          (let ((address (subseq text (1+ i) close)))
                            (token (markdown-link address (list address)))
                            (setf i (1+ close)))
                          (progn (write-char char plain) (incf i)))))
                   ((and (char-equal char #\h)
                         (not (word-char-p (previous)))
                         (or (starts-with-p "https://" text i) (starts-with-p "http://" text i))
                         (progn
                           ;; Where the run of the URL stops is found once
                           ;; for every URL that starts before it.
                           (when (< url-stop i)
                             (setf url-stop (or (position-if #'url-stop-p text :start i) end)))
                           (setf url-end (bare-url-end text i url-stop))))
                    (let ((url (subseq text i url-end)))
                      (token (markdown-link url (list url)))
                      (setf i url-end)))
                   ((char= char #\Newline)
                    (token '(:br))
                    (incf i))
                   (t (write-char char plain) (incf i)))))
      (flush)
      (resolve-emphasis (map 'list (lambda (token) (if (bracket-p token) "[" token)) tokens)))))

;;; ------------------------------------------------------------------
;;; Lines

(defun line-ends-as-newlines (text)
  "TEXT with each of its line ends, CR LF, CR or LF, as one newline."
  (if (find #\Return text)
      (with-output-to-string (out)
        (loop for i from 0 below (length text)
              for char = (char text i)
              do (cond ((char/= char #\Return) (write-char char out))
                       ((and (< (1+ i) (length text)) (char= (char text (1+ i)) #\Newline)))
                       (t (write-char #\Newline out)))))
      text))

(defun markdown-lines (text)
  "TEXT's lines as a vector, without their line ends (CR LF, CR or LF), the
tabs that indent them as four spaces each; and as a second value the same
lines with their tabs, as a code block shows them."
  (let ((text (line-ends-as-newlines text))
        (lines (make-array 16 :adjustable t :fill-pointer 0))
        (raw (make-array 16 :adjustable t :fill-pointer 0)))
    (loop for start = 0 then (1+ newline)
          for newline = (position #\Newline text :start start)
          do (let* ((line (subseq text start newline))
                    (indent (or (position-if-not (lambda (char) (find char '(#\Space #\Tab))) line)
                                (length line))))
               (vector-push-extend line raw)
               (vector-push-extend
                (if (find #\Tab line :end indent)
                    (concatenate 'string
                                 (with-output-to-string (out)
                                   (loop for char across (subseq line 0 indent)
                                         do (if (char= char #\Tab)
                                                (write-string "    " out)
                                                (write-char char out))))
                                 (subseq line indent))
                    line)
                lines))
          while newline)
    (values lines raw)))

(defun line-indent (line)
  (or (position #\Space line :test-not #'char=) (length line)))

(defun blank-line-p (line)
  (every (lambda (char) (char= char #\Space)) line))

(defun fence-open (line)
  "The number of backticks of the fence LINE opens, and its indent, or NIL."
  (let ((indent (line-indent line)))
    (when (<= indent 3)
      (let* ((end (or (position #\` line :start indent :test-not #'char=) (length line)))
             (count (- end indent)))
        (when (and (>= count 3) (not (find #\` line :start end)))
          (values count indent))))))

(defun fence-close-p (line count)
  (let ((indent (line-indent line)))
    (and (<= indent 3)
         (let ((end (or (position #\` line :start indent :test-not #'char=) (length line))))
           (and (>= (- end indent) count)
                (blank-line-p (subseq line end)))))))

(defun rule-line-p (line)
  (and (<= (line-indent line) 3)
       (let ((marks (remove #\Space line)))
         (and (>= (length marks) 3)
              (find (char marks 0) "-*_")
              (every (lambda (char) (char= char (char marks 0))) marks)))))

(defun heading-line (line)
  "The level of the heading LINE is, 1 or 2, and its text, or NIL."
  (let ((indent (line-indent line)))
    (when (<= indent 3)
      (let* ((end (or (position #\# line :start indent :test-not #'char=) (length line)))
             (count (- end indent)))
        (when (and (<= 1 count 6) (or (= end (length line)) (char= (char line end) #\Space)))
          (let* ((text (string-trim " " (subseq line end)))
                 (closing (position #\# text :from-end t :test-not #'char=)))
            ;; Closing #s, after a space or alone, are left out.
            (cond ((null closing) (setf text ""))
                  ((and (< closing (1- (length text))) (char= (char text closing) #\Space))
                   (setf text (string-right-trim " " (subseq text 0 closing)))))
            (values (if (= count 1) 1 2) text)))))))

(defun list-marker (line)
  "When LINE starts an item: its indent, :BULLET or :ORDERED, its number, and
its text after the marker."
  (let* ((indent (line-indent line))
         (at indent)
         (length (length line)))
    (multiple-value-bind (kind number)
        (cond ((and (< at length) (find (char line at) "-*+"))
               (incf at)
               (values :bullet nil))
              ((and (< at length) (digit-char-p (char line at)))
               (let ((digits-end (or (position-if-not #'digit-char-p line :start at) length)))
                 (when (and (<= (- digits-end at) 9) (< digits-end length)
                            (find (char line digits-end) ".)"))
                   (multiple-value-prog1
                       (values :ordered (parse-integer line :start at :end digits-end))
                     (setf at (1+ digits-end)))))))
      (when (and kind (< at length) (char= (char line at) #\Space)
                 (not (blank-line-p (subseq line at))))
        (values indent kind number (string-left-trim " " (subseq line at)))))))

(defun table-cells (line)
  "LINE's cells: split at each | not written \\|, one | at each end optional,
each cell trimmed."
  (let* ((text (string-trim " " line))
         (start (if (and (plusp (length text)) (char= (char text 0) #\|)) 1 0))
         (end (length text))
         (cells '())
         (from start))
    (when (and (> end start) (char= (char text (1- end)) #\|)
               (not (and (> end 1) (char= (char text (- end 2)) #\\))))
      (decf end))
    (loop for i from start below end
          do (case (char text i)
               (#\\ (incf i))
               (#\| (push (string-trim " " (subseq text from i)) cells)
                    (setf from (1+ i)))))
    (push (string-trim " " (subseq text from (max from end))) cells)
    (nreverse cells)))

(defun delimiter-row (line)
  "When LINE is a table's delimiter row, its columns' alignments: NIL, \"start\",
\"center\" or \"end\" for each."
  (when (find #\| line)
    (let ((cells (table-cells line)))
      (when (every (lambda (cell)
                     (let ((dashes (string-trim ":" cell)))
                       (and (plusp (length dashes))
                            (every (lambda (char) (char= char #\-)) dashes)
                            (<= (- (length cell) (length dashes)) 2))))
                   cells)
        (mapcar (lambda (cell)
                  (let ((left (char= (char cell 0) #\:))
                        (right (char= (char cell (1- (length cell))) #\:)))
                    (cond ((and left right) "center") (right "end") (left "start"))))
                cells)))))

(defun table-start-p (lines i)
  "True when the line at I starts a table: a | in it, and a delimiter row of as
many cells, at most +MARKDOWN-TABLE-COLUMNS+, after it."
  (and (< (1+ i) (length lines))
       (find #\| (aref lines i))
       (let ((columns (length (table-cells (aref lines i))))
             (alignments (delimiter-row (aref lines (1+ i)))))
         (and alignments
              (= columns (length alignments))
              (<= columns +markdown-table-columns+)))))

(defun starts-block-p (lines i)
  "True when the line at I starts a block other than a paragraph, so that it
ends a paragraph before it: of the ordered lists, only one starting at 1."
  (let ((line (aref lines i)))
    (or (fence-open line)
        (rule-line-p line)
        (heading-line line)
        (multiple-value-bind (indent kind number) (list-marker line)
          (and indent (<= indent 3) (or (eq kind :bullet) (eql number 1))))
        (table-start-p lines i))))

;;; ------------------------------------------------------------------
;;; Blocks

(defun heading-tag-of (level)
  (ecase level (2 :h2) (3 :h3) (4 :h4) (5 :h5) (6 :h6)))

(defun markdown-paragraph (lines i)
  (let ((end (loop for j from (1+ i) below (length lines)
                   when (or (blank-line-p (aref lines j)) (starts-block-p lines j))
                     return j
                   finally (return (length lines)))))
    (values `(:p ,@(markdown-inline (format nil "~{~a~^~%~}"
                                            (coerce (subseq lines i end) 'list))))
            end)))

(defun markdown-fence (lines i raw)
  "The code block whose fence opens at I, and the line after it.  Its lines
are RAW's, with their tabs, less the spaces the fence is indented by."
  (multiple-value-bind (count indent) (fence-open (aref lines i))
    (let* ((close (loop for j from (1+ i) below (length lines)
                        when (fence-close-p (aref lines j) count) return j))
           (code (loop for j from (1+ i) below (or close (length lines))
                       for line = (aref raw j)
                       collect (subseq line (min indent (line-indent line))))))
      (values (code-block () (format nil "~{~a~^~%~}" code))
              (if close (1+ close) (length lines))))))

(defun markdown-table (lines i)
  (let* ((alignments (delimiter-row (aref lines (1+ i))))
         (columns (length alignments))
         (wide (> columns 3))
         (headings (mapcar #'markdown-inline (table-cells (aref lines i))))
         (labels (when wide
                   (mapcar (lambda (cell)
                             (let ((label (plain-text cell)))
                               (if (> (length label) +markdown-label-length+)
                                   (concatenate 'string (subseq label 0 (1- +markdown-label-length+)) "…")
                                   label)))
                           headings)))
         (end (loop for j from (+ i 2) below (length lines)
                    for line = (aref lines j)
                    when (or (blank-line-p line) (not (find #\| line))
                             (fence-open line) (rule-line-p line) (heading-line line)
                             (let ((indent (list-marker line))) (and indent (<= indent 3))))
                      return j
                    finally (return (length lines))))
         (rows (loop for j from (+ i 2) below end
                     collect `(:tr ,@(loop for cell in (table-cells (aref lines j))
                                          for alignment in alignments
                                          for label in (or labels alignments)
                                          collect (markdown-cell (markdown-inline cell) alignment
                                                              (and wide (plusp (length cell)) label)))))))
    (values `(:div (:@ :class "tun-markdown-table" :data-wide ,(when wide "true"))
                   (:table (:thead (:tr ,@(loop for heading in headings
                                                for alignment in alignments
                                                collect `(:th (:@ :scope "col" :data-align ,alignment)
                                                              ,@heading))))
                           ,@(when rows `((:tbody ,@rows)))))
            end)))

(defun markdown-cell (nodes alignment label)
  `(:td (:@ :data-align ,alignment)
        ,@(when label `((:span (:@ :class "tun-markdown-table-label") ,label)))
        (:span (:@ :class "tun-markdown-table-value") ,@nodes)))

(defun plain-text (nodes)
  "The text of NODES, without their markup."
  (with-output-to-string (out)
    (labels ((walk (node)
               (cond ((stringp node) (write-string node out))
                     ((and (consp node) (keywordp (first node)))
                      (mapc #'walk (nth-value 2 (tun.html:node-parts node))))
                     ((listp node) (mapc #'walk node)))))
      (walk nodes))))

(defstruct (md-list (:constructor make-md-list (kind start indent)))
  "A list being read: its kind, its first number, the indent of its markers
and its items, the last first."
  kind start indent (items '()))

(defstruct md-item
  "An item being read: its lines and the lists inside it, the last first."
  (lines '()) (lists '()))

(defun markdown-list (lines i)
  "The lists starting with the item at I, and the line after them."
  (let ((roots '()) (stack '()) (blank nil) (j i) (n (length lines)))
    (labels ((open-list (indent kind number parent)
               (let ((list (make-md-list kind number indent)))
                 (if parent
                     (push list (md-item-lists (first (md-list-items parent))))
                     (push list roots))
                 list))
             (add-item (list text)
               (push (make-md-item :lines (list text)) (md-list-items list))))
      (multiple-value-bind (indent kind number text) (list-marker (aref lines i))
        (let ((list (open-list indent kind number nil)))
          (setf stack (list list))
          (add-item list text)))
      (incf j)
      (loop while (< j n)
            do (let ((line (aref lines j)))
                 (multiple-value-bind (indent kind number text) (list-marker line)
                   (cond
                     ((blank-line-p line) (setf blank t))
                     (indent
                      (if (and (>= indent (+ (md-list-indent (first stack)) 2))
                               (< (length stack) +markdown-list-depth+))
                          (push (open-list indent kind number (first stack)) stack)
                          (progn
                            (loop while (and (rest stack) (< indent (md-list-indent (first stack))))
                                  do (pop stack))
                            (unless (eq kind (md-list-kind (first stack)))
                              (setf (first stack)
                                    (open-list (md-list-indent (first stack)) kind number
                                               (second stack))))))
                      (add-item (first stack) text)
                      (setf blank nil))
                     ((or blank (fence-open line) (rule-line-p line) (heading-line line))
                      (return))
                     (t (push (string-left-trim " " line)
                              (md-item-lines (first (md-list-items (first stack)))))))))
               (incf j))
      ;; A blank line at the end belongs to no item.
      (values (mapcar #'list-node (reverse roots))
              (if blank
                  (loop for k downfrom (1- j) when (not (blank-line-p (aref lines k))) return (1+ k))
                  j)))))

(defun list-node (list)
  (let ((items (mapcar (lambda (item)
                         `(:li ,@(markdown-inline (format nil "~{~a~^~%~}"
                                                          (reverse (md-item-lines item))))
                               ,@(mapcar #'list-node (reverse (md-item-lists item)))))
                       (reverse (md-list-items list)))))
    (if (eq (md-list-kind list) :ordered)
        `(:ol (:@ :start ,(unless (eql (md-list-start list) 1) (md-list-start list))) ,@items)
        `(:ul ,@items))))

(defun markdown-blocks (text heading-level)
  "The blocks of TEXT as nodes (spec/ui.md 6.2), its headings from HEADING-LEVEL."
  (multiple-value-bind (lines raw) (markdown-lines text)
    (let ((nodes '()) (i 0))
      (flet ((read-with (reader)
               ;; READER reads the block at I: one node or a list of them,
               ;; and the line after the block.
               (multiple-value-bind (node next) (funcall reader lines i)
                 (if (and (consp node) (consp (first node)))
                     (dolist (one node) (push one nodes))
                     (push node nodes))
                 (setf i next))))
        (loop while (< i (length lines))
              do (let ((line (aref lines i)))
                   (cond ((blank-line-p line) (incf i))
                         ((fence-open line)
                          (read-with (lambda (lines i) (markdown-fence lines i raw))))
                         ((rule-line-p line) (push '(:hr) nodes) (incf i))
                         ((heading-line line)
                          (multiple-value-bind (level text) (heading-line line)
                            (push `(,(heading-tag-of (+ heading-level level -1))
                                    (:@ :data-level ,(princ-to-string level))
                                    ,@(markdown-inline text))
                                  nodes))
                          (incf i))
                         ((let ((indent (list-marker line))) (and indent (<= indent 3)))
                          (read-with #'markdown-list))
                         ((table-start-p lines i) (read-with #'markdown-table))
                         (t (read-with #'markdown-paragraph))))))
      (nreverse nodes))))

;;; ------------------------------------------------------------------
;;; The component

(define-component markdown ((&key text (heading-level 3) id attributes))
  (:group "Data")
  (:doc "Text that people and agents write, such as a description or a comment, with the
parts of Markdown they use most: paragraphs, headings, lists, code, rules, tables, bold,
italic and links. Nothing in the text is passed on as HTML. HEADING-LEVEL, 2 to 5, is the
element of the text's first level of heading, so its headings stay below the page's.")
  (:source "CommonMark 0.31 and GitHub's tables, a subset (spec/ui.md 6.2)")
  (:css "
.tun-markdown {
  container: tun-markdown / inline-size;
  min-width: 0;
  overflow-wrap: anywhere;
  & > * + * { margin-block-start: calc(var(--spacing) * 3); }
  & > * + :is(h2, h3, h4, h5, h6) { margin-block-start: calc(var(--spacing) * 5); }
  & :is(h2, h3, h4, h5, h6) {
    font-weight: var(--font-weight-semibold);
    line-height: 1.4;
  }
  & [data-level='1'] { font-size: var(--text-lg); }
  & [data-level='2'] { font-size: var(--text-base); }
  & :is(ul, ol) { padding-inline-start: 1.5em; }
  & ul { list-style: disc; }
  & ul ul { list-style: circle; }
  & ol { list-style: decimal; }
  & li::marker { color: var(--muted-foreground); }
  & li + li, & li > :is(ul, ol) { margin-block-start: var(--spacing); }
  & strong { font-weight: var(--font-weight-semibold); }
  & em { font-style: italic; }
  & hr { border: 0; border-block-start: 1px solid var(--border); }
  & :not(pre) > code {
    padding: 0.125em 0.375em;
    border-radius: var(--radius-sm);
    background-color: var(--muted);
    font-family: var(--font-mono);
    font-size: 0.875em;
  }
  /* Code keeps its lines; its box scrolls instead. */
  & .tun-code-block { overflow-wrap: normal; }
  & .tun-markdown-table {
    overflow-x: auto;
    & table {
      width: 100%;
      border-collapse: collapse;
      font-size: var(--text-sm);
      line-height: var(--text-sm--line-height);
    }
    & :is(th, td) {
      padding: calc(var(--spacing) * 2);
      border-block-end: 1px solid var(--border);
      text-align: start;
      vertical-align: top;
    }
    & th { font-weight: var(--font-weight-medium); }
    & :is(th, td)[data-align='center'] { text-align: center; }
    & :is(th, td)[data-align='end'] { text-align: end; }
    & .tun-markdown-table-label { display: none; }
  }
  /* Four columns or more keep their words whole and scroll in their box. */
  & .tun-markdown-table[data-wide] { overflow-wrap: break-word; }
  /* Narrow, as on a phone: each row of such a table is a card, each value
     under its column's heading. */
  @container tun-markdown (width < 36rem) {
    & .tun-markdown-table[data-wide] {
      overflow-wrap: anywhere;
      & :is(table, tbody, tr, td) { display: block; }
      & thead { display: none; }
      & tbody { display: flex; flex-direction: column; gap: calc(var(--spacing) * 3); }
      & tr {
        padding: calc(var(--spacing) * 2) calc(var(--spacing) * 4);
        border: 1px solid var(--border);
        border-radius: var(--radius-lg);
        background-color: var(--card);
        box-shadow: var(--shadow-xs);
      }
      & td { padding: calc(var(--spacing) * 1.5) 0; border: 0; text-align: start; }
      & td:has(> .tun-markdown-table-value:empty) { display: none; }
      & .tun-markdown-table-label {
        display: block;
        color: var(--muted-foreground);
        font-size: var(--text-xs);
        line-height: var(--text-xs--line-height);
        font-weight: var(--font-weight-medium);
      }
    }
  }
}")
  (:examples
   (("An agent's comment" :layout :stack)
    (markdown (:text "## What I changed

The export now writes **one file a day**, and `bin/export` takes `--from`.

1. Read the orders since the last run
2. Write them to `exports/`
   - one line an order
3. Mark them as sent

```
bin/export --from 2026-11-01
```

See [the item](/items/12) or https://example.com/docs/export_(v2).")))
   (("A table of three columns" :layout :stack)
    (markdown (:text "| Step | Who | When |
|---|---|--:|
| Plan | Kari | Monday |
| Build | an agent | Tuesday |")))
   (("A wide table, cards on a phone" :layout :stack)
    (markdown (:text "| Order | Customer | Date | Status | Amount |
|---|---|---|---|--:|
| 10482 | Fjord Coffee Ltd | 12 Oct 2026 | New | €4,380.00 |
| 10481 | Hansen Building and Construction Ltd | 11 Oct 2026 | In progress | €128,950.00 |")))
   (("HTML shows as written" :layout :stack)
    (markdown (:text "<script>alert(1)</script> and [a link](javascript:alert(1)) stay text."))))
  (check-type text (or null string))
  (check-type heading-level (integer 2 5))
  `(:div ,(attrs (list :class "tun-markdown" :id id) attributes)
         ,@(markdown-blocks (or text "") heading-level)))
