;;;; files/multipart.lisp -- a page's multipart/form-data post, read in
;;;; memory from a body the server has already bounded (spec/files.md 4.3).
;;;;
;;;; Hunchentoot's own parser writes every file part to a temporary file as
;;;; it reads, before anything could count them.  This one counts parts,
;;;; file parts and header octets as it goes and stops at the first excess,
;;;; and writes nothing anywhere.

(in-package #:tun.files)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +most-parts+ 64 "The most parts one post has.")
(defparameter +most-file-parts+ 10 "The most parts with a file one post has.")
(defparameter +most-part-header-octets+ (* 8 1024) "The most octets of one part's headers.")
(defparameter +most-text-part-octets+ (* 1024 1024) "The longest text part.")
(defparameter +most-text-octets+ (* 2 1024 1024)
  "The most octets of text parts one post has together: what a body besides
its files may hold (core.md §7.5).")
(defparameter +most-boundary+ 70 "The longest boundary (RFC 2046 5.1.1).")

(define-condition multipart-refused (error)
  ((status :initarg :status :reader multipart-refused-status)
   (message :initarg :message
            :documentation "A string, or a TEXT written in the language of the place it is
shown."))
  (:report (lambda (c s) (format s "~d: ~a" (multipart-refused-status c)
                                 (multipart-refused-message c))))
  (:documentation "A multipart post Tun does not read: STATUS and the page's MESSAGE."))

(defun multipart-refused-message (condition)
  "The page's message for CONDITION, written in the current language."
  (render-text (slot-value condition 'message)))

(defmacro refuse-post (status control &rest arguments)
  "Refuse the post with STATUS, its message the literal CONTROL with ARGUMENTS."
  `(error 'multipart-refused :status ,status :message (deferred-tr ,control ,@arguments)))

(defun unreadable ()
  (refuse-post 400 "The form could not be read. Reload the page and try again."))

(defun multipart-boundary (content-type)
  "The boundary CONTENT-TYPE, a multipart/form-data Content-Type header,
names in its parameter boundary; refused as unreadable when there is none or
it is too long."
  (let* ((parameter (find-if (lambda (part)
                               (let ((part (string-left-trim " " part)))
                                 (and (> (length part) 9)
                                      (string-equal "boundary=" part :end2 9))))
                             (rest (split-sequence-on #\; content-type))))
         (value (and parameter (subseq (string-left-trim " " parameter) 9)))
         (boundary (cond ((null value) nil)
                         ((and (plusp (length value)) (char= (char value 0) #\"))
                          (let ((end (position #\" value :start 1)))
                            (and end (subseq value 1 end))))
                         (t (string-right-trim " " value)))))
    (unless (and boundary (<= 1 (length boundary) +most-boundary+))
      (unreadable))
    boundary))

(defun split-sequence-on (char text)
  "TEXT split at each CHAR."
  (loop for start = 0 then (1+ end)
        for end = (position char text :start start)
        collect (subseq text start end)
        while end))

(defun utf-8-text (octets)
  "OCTETS as UTF-8 text, each invalid sequence as U+FFFD."
  (sb-ext:octets-to-string octets :external-format '(:utf-8 :replacement #\REPLACEMENT_CHARACTER)))

(defun find-octets (pattern octets start)
  "The position of PATTERN in OCTETS at or after START, or NIL."
  (let ((first (aref pattern 0))
        (last (- (length octets) (length pattern))))
    (loop for i from start to last
          when (and (= (aref octets i) first)
                    (not (mismatch pattern octets :start2 i :end2 (+ i (length pattern)))))
          do (return i))))

(defun browser-unescape (text)
  "TEXT, a quoted name or filename, with the escapes browsers write there
undone: %22 for a double quote, %0D and %0A for a line break, and no other."
  (with-output-to-string (out)
    (loop with i = 0
          while (< i (length text))
          do (let ((escape (and (char= (char text i) #\%) (<= (+ i 3) (length text))
                                (cdr (assoc (subseq text (1+ i) (+ i 3))
                                            '(("22" . #\") ("0D" . #\Return) ("0d" . #\Return)
                                              ("0A" . #\Newline) ("0a" . #\Newline))
                                            :test #'string=)))))
               (cond (escape (write-char escape out) (incf i 3))
                     (t (write-char (char text i) out) (incf i)))))))

(defun disposition-parameter (header name)
  "The parameter NAME of HEADER, a Content-Disposition's octets after its
colon, decoded (spec/files.md 4.3), or NIL."
  (let ((key (octets-of (concatenate 'string name "="))))
    (loop for at = (find-octets key header 0) then (find-octets key header (1+ at))
          while at
          ;; A whole parameter name: at the start, or after ; or a space.
          when (or (zerop at) (member (aref header (1- at)) '(32 59 9)))
          do (let ((start (+ at (length key))))
               (return
                 (if (and (< start (length header)) (= (aref header start) 34))
                     (let ((end (position 34 header :start (1+ start))))
                       (unless end (unreadable))
                       (browser-unescape (utf-8-text (subseq header (1+ start) end))))
                     (utf-8-text (subseq header start (or (position 59 header :start start)
                                                          (length header))))))))))

(defun part-headers (octets)
  "The headers OCTETS, one part's, as (NAME . VALUE-OCTETS), names lower case."
  (loop for start = 0 then (+ end 2)
        for end = (or (find-octets (octets-of (format nil "~c~c" #\Return #\Newline)) octets start)
                      (length octets))
        while (< start (length octets))
        collect (let ((colon (or (position 58 octets :start start :end end) (unreadable))))
                  (cons (string-downcase (utf-8-text (subseq octets start colon)))
                        (trim-octets (subseq octets (1+ colon) end))))))

(defun trim-octets (octets)
  (let ((start (or (position-if-not (lambda (b) (member b '(32 9))) octets) (length octets))))
    (subseq octets start)))

(defun form-data-names (headers)
  "Values the part's name and its filename (NIL for a text part), from
HEADERS; refused as unreadable without Content-Disposition: form-data or a name."
  (let ((disposition (cdr (assoc "content-disposition" headers :test #'string=))))
    (unless (and disposition
                 (let ((value (trim-octets disposition)))
                   (and (octets-at-p value 0 "form-data")
                        (or (= (length value) 9) (member (aref value 9) '(59 32 9))))))
      (unreadable))
    (let ((name (disposition-parameter disposition "name")))
      (unless name (unreadable))
      (values name (disposition-parameter disposition "filename")))))

(defun parse-multipart (octets boundary)
  "Values the text parts of OCTETS, a multipart/form-data body with BOUNDARY,
as (NAME . TEXT) in order, and its parts with a file as (NAME FILENAME
OCTETS), leaving out a part with an empty filename and no content.  Signals
MULTIPART-REFUSED at the first part past the bounds, or for a body it
cannot read (spec/files.md 4.3)."
  (let* ((delimiter (octets-of (concatenate 'string "--" boundary)))
         (next (octets-of (format nil "~c~c--~a" #\Return #\Newline boundary)))
         (line-end (octets-of (format nil "~c~c" #\Return #\Newline)))
         (headers-end (octets-of (format nil "~c~c~c~c" #\Return #\Newline #\Return #\Newline)))
         (texts '()) (files '()) (parts 0) (file-parts 0) (text-octets 0)
         (at (if (octets-at-p octets 0 delimiter)
                 (length delimiter)
                 (let ((found (find-octets next octets 0)))
                   (if found (+ found (length next)) (unreadable))))))
    (loop
     (cond ((octets-at-p octets at "--")
            (return (values (nreverse texts) (nreverse files))))
           ((octets-at-p octets at line-end) (incf at 2))
           (t (unreadable)))
     (when (> (incf parts) +most-parts+)
       (refuse-post 413 "The form has too many fields (at most ~d)." +most-parts+))
     (let ((end (find-octets headers-end octets at)))
       (when (or (and end (> (- end at) +most-part-header-octets+))
                 (and (null end) (> (- (length octets) at) +most-part-header-octets+)))
         (refuse-post 413 "A part of the form has headers that are too long (at most 8 KB)."))
       (unless end (unreadable))
       (let* ((headers (part-headers (subseq octets at end)))
              (content-start (+ end 4))
              (content-end (or (find-octets next octets content-start) (unreadable))))
         (multiple-value-bind (name filename) (form-data-names headers)
           (let ((length (- content-end content-start)))
             (cond (filename
                    (when (> (incf file-parts) +most-file-parts+)
                      (refuse-post 413 "You can send at most ~d files at a time."
                                   +most-file-parts+))
                    (unless (and (zerop (length filename)) (zerop length))
                      (push (list name filename (subseq octets content-start content-end))
                            files)))
                   ((> length +most-text-part-octets+)
                    (refuse-post 413 "A field in the form is longer than 1 MB."))
                   ((> (incf text-octets length) +most-text-octets+)
                    (refuse-post 413 "The form's fields hold more than 2 MB of text together."))
                   (t (push (cons name (utf-8-text (subseq octets content-start content-end)))
                            texts)))))
         (setf at (+ content-end (length next))))))))
