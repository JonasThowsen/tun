;;;; core/sql-text.lisp -- SQL text with holes, as queries (spec/store.md 5)
;;;; and record policies (6) are written.
;;;;
;;;; The text has two kinds of holes: {ENTITY} for an entity's table and
;;;; :NAME for a parameter.  SPLIT-SQL-TEXT cuts it into parts when a
;;;; definition is compiled, leaving strings, quoted identifiers, comments
;;;; and casts alone, and refuses what would let a value or a second
;;;; statement into the text.  It reads no definition: the entities are
;;;; looked up when the SQL runs.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defun sql-text-error (text position control &rest arguments)
  "Signal that TEXT is refused at POSITION, quoting the text around it."
  (error "~?~%  in SQL text near: ~s" control arguments
         (subseq text (max 0 (- position 20)) (min (length text) (+ position 20)))))

(defun literal-end (text start closing)
  "The index after the CLOSING character that ends the literal opened at
START, where a doubled CLOSING stands for itself; NIL if it never ends."
  (loop with i = (1+ start)
        while (< i (length text))
        do (cond ((char/= (char text i) closing) (incf i))
                 ((and (< (1+ i) (length text)) (char= (char text (1+ i)) closing)) (incf i 2))
                 (t (return (1+ i))))))

(defun comment-end (text start)
  "The index after the comment starting at START (-- or /*), or NIL if a
block comment never ends.  A block comment may not hold another /*:
Postgres nests them, and the split must see the text as Postgres does."
  (if (char= (char text (1+ start)) #\-)
      (or (position #\Newline text :start start) (length text))
      (let ((end (search "*/" text :start2 (+ start 2))))
        (when (and end (search "/*" text :start2 (+ start 2) :end2 end))
          (sql-text-error text start "A block comment may not contain /*"))
        (and end (+ end 2)))))

(defun comment-start-p (text i)
  (and (< (1+ i) (length text))
       (or (string= "--" text :start2 i :end2 (+ i 2))
           (string= "/*" text :start2 i :end2 (+ i 2)))))

(defun first-word (text)
  "The first word of TEXT after whitespace and comments, in upper case."
  (let ((i 0))
    (loop while (< i (length text))
          do (cond ((whitespace-char-p (char text i)) (incf i))
                   ((comment-start-p text i) (setf i (or (comment-end text i) (length text))))
                   (t (return))))
    (string-upcase (subseq text i (or (position-if-not #'alpha-char-p text :start i)
                                      (length text))))))

(defun name-end (text start first-char-p rest-char-p)
  "The index after a name starting at START, or NIL when there is none."
  (when (and (< start (length text)) (funcall first-char-p (char text start)))
    (or (position-if-not rest-char-p text :start (1+ start)) (length text))))

(defun lower-name-start-p (char)
  (char<= #\a char #\z))

(defun parameter-name-char-p (char)
  (or (char<= #\a char #\z) (digit-char-p char) (char= char #\_)))

(defun entity-name-char-p (char)
  (or (char<= #\a char #\z) (digit-char-p char) (char= char #\-)))

(defun parameter-end (text i)
  "The index after the parameter :NAME at I, or NIL when there is none."
  (and (char= (char text i) #\:)
       (name-end text (1+ i) #'lower-name-start-p #'parameter-name-char-p)))

(defun entity-end (text i)
  "The index after {NAME} at I.  Signals an error for a { without one."
  (let ((end (name-end text (1+ i) #'lower-name-start-p #'entity-name-char-p)))
    (unless (and end (< end (length text)) (char= (char text end) #\}))
      (sql-text-error text i "{ must enclose an entity's name, as in {order}"))
    (1+ end)))

(defun skipped-end (text i)
  "The index after the string, quoted identifier, comment or cast at I,
which pass through unchanged, or NIL when none starts there."
  (let ((c (char text i)))
    (cond ((or (char= c #\') (char= c #\"))
           (or (literal-end text i c)
               (sql-text-error text i "Unterminated ~:[quoted identifier~;string~]"
                               (char= c #\'))))
          ((comment-start-p text i)
           (or (comment-end text i) (sql-text-error text i "Unterminated comment")))
          ((and (char= c #\:) (< (1+ i) (length text)) (char= (char text (1+ i)) #\:))
           (+ i 2)))))

(defun split-sql-text (text package)
  "TEXT as a list of parts: strings of SQL, (:ENTITY SYMBOL) for {ENTITY},
with the symbol read in PACKAGE, and (:PARAMETER NAME) for :NAME.  Signals
an error for anything spec/store.md 5.2 refuses but the first word."
  (let ((parts '())
        (sql (make-string-output-stream))
        (depth 0)
        (i 0))
    (labels ((copy-to (end)
               (write-string text sql :start i :end end)
               (setf i end))
             (flush ()
               (let ((copied (get-output-stream-string sql)))
                 (when (plusp (length copied)) (push copied parts))))
             (hole (part end)
               (flush)
               (push part parts)
               (setf i end)))
      (loop while (< i (length text))
            do (let ((c (char text i)))
                 (cond ((skipped-end text i) (copy-to (skipped-end text i)))
                       ((char= c #\()
                        (incf depth)
                        (copy-to (1+ i)))
                       ((char= c #\))
                        (when (zerop depth)
                          (sql-text-error text i "This ) closes no ("))
                        (decf depth)
                        (copy-to (1+ i)))
                       ((char= c #\;)
                        (sql-text-error text i "One statement only: no ;"))
                       ((char= c #\$)
                        (sql-text-error text i "No $: parameters are named (:name), ~
                                                  and there is no dollar quoting"))
                       ((parameter-end text i)
                        (let ((end (parameter-end text i)))
                          (hole (list :parameter (subseq text (1+ i) end)) end)))
                       ((char= c #\{)
                        (let ((end (entity-end text i)))
                          (hole (list :entity (intern (string-upcase (subseq text (1+ i) (1- end)))
                                                      package))
                                end)))
                       (t (copy-to (1+ i))))))
      (flush))
    (unless (zerop depth)
      (sql-text-error text (length text) "~d ( never closed" depth))
    (nreverse parts)))
