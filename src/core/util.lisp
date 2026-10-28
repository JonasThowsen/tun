;;;; core/util.lisp -- small utilities: strings, identifiers, hashing, time.
;;;;
;;;; Everything here is pure or reads only from /dev/urandom.  Time values are
;;;; integers in Common Lisp universal time (seconds since 1900-01-01T00:00Z);
;;;; dates are validated "YYYY-MM-DD" strings.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Strings and symbols

(declaim (ftype (function (symbol) (values simple-string &optional)) json-name-of))
(defun json-name-of (symbol)
  "The JSON (snake_case) name of a Lisp symbol: ORG-NUMBER -> \"org_number\"."
  (coerce (substitute #\_ #\- (string-downcase (symbol-name symbol))) 'simple-string))

(defun whitespace-char-p (char)
  (member char '(#\Space #\Tab #\Newline #\Return #\Page #\No-break_space)))

(declaim (ftype (function (string) (values string &optional)) trim))
(defun trim (string)
  (string-trim '(#\Space #\Tab #\Newline #\Return #\Page #\No-break_space) string))

(defun blank-p (value)
  (or (null value)
      (and (stringp value) (zerop (length (trim value))))))

(defun symbolicate (&rest parts)
  "Intern the concatenation of PARTS (strings or symbols) in *PACKAGE*."
  (intern (format nil "~{~a~}" (mapcar (lambda (p) (if (symbolp p) (symbol-name p) (string-upcase p))) parts))))

(defun string-prefix-p (prefix string)
  (and (<= (length prefix) (length string))
       (string= prefix string :end2 (length prefix))))

(defun join-strings (strings separator)
  (with-output-to-string (out)
    (loop for (s . rest) on strings
          do (write-string s out)
             (when rest (write-string separator out)))))

(defun contains-ci-p (needle haystack)
  "Case-insensitive (Unicode-aware via CHAR-EQUAL) substring test."
  (and (stringp haystack)
       (search needle haystack :test #'char-equal)))

;;; ------------------------------------------------------------------
;;; Randomness, identifiers, hashing

(defun random-bytes (n)
  "N cryptographically strong random bytes from the kernel."
  (declare (type (integer 1 1024) n))
  (let ((bytes (make-array n :element-type '(unsigned-byte 8))))
    (with-open-file (in "/dev/urandom" :element-type '(unsigned-byte 8))
      (unless (= n (read-sequence bytes in))
        (error "short read from /dev/urandom")))
    bytes))

(defparameter +id-alphabet+ "0123456789abcdefghjkmnpqrstvwxyz"
  "Crockford-style base32 alphabet (no i, l, o, u).")

(defun random-token-string (n-chars)
  (let ((bytes (random-bytes n-chars))
        (out (make-string n-chars)))
    (dotimes (i n-chars out)
      (setf (char out i) (char +id-alphabet+ (logand (aref bytes i) 31))))))

(declaim (ftype (function (string) (values simple-string &optional)) new-id))
(defun new-id (prefix)
  "A fresh opaque identifier such as \"cus_7k2m...\" (80 random bits)."
  (coerce (concatenate 'string prefix "_" (random-token-string 16)) 'simple-string))

(defvar *ordered-id-last* 0)
(defvar *ordered-id-lock* (sb-thread:make-mutex :name "ordered identifiers"))
(defun new-ordered-id (prefix)
  "Opaque catalog identity with creation order and the usual 80 random bits.
Client rules that select the first catalog id consequently have stable order."
  (sb-thread:with-mutex (*ordered-id-lock*)
    (multiple-value-bind (seconds micros) (sb-ext:get-time-of-day)
      (setf *ordered-id-last* (max (1+ *ordered-id-last*) (+ (* seconds 1000000) micros)))
      (coerce (format nil "~a_~20,'0d~a" prefix *ordered-id-last* (random-token-string 16)) 'simple-string))))

(defun new-secret-token ()
  "A high-entropy one-time token: 32 random bytes, hex encoded (256 bits)."
  (ironclad:byte-array-to-hex-string (random-bytes 32)))

(declaim (ftype (function (string) (values simple-string &optional)) sha256-hex))
(defun sha256-hex (string)
  (coerce (ironclad:byte-array-to-hex-string
           (ironclad:digest-sequence :sha256 (sb-ext:string-to-octets string :external-format :utf-8)))
          'simple-string))

;;; ------------------------------------------------------------------
;;; Time.  Universal time integers internally; RFC 3339 UTC on the wire.

(deftype universal-time () '(integer 0))

(defun two-digits (string start)
  (parse-integer string :start start :end (+ start 2)))

(declaim (ftype (function (t) (values (or null universal-time) &optional)) parse-rfc3339))
(defun parse-rfc3339 (string)
  "Parse YYYY-MM-DDTHH:MM:SS[.frac](Z|+HH:MM|-HH:MM) into universal time, or NIL.
Fractional seconds are truncated."
  (when (and (stringp string) (>= (length string) 20))
    (handler-case
        (let* ((s string)
               (year (parse-integer s :start 0 :end 4))
               (month (two-digits s 5))
               (day (two-digits s 8))
               (hour (two-digits s 11))
               (minute (two-digits s 14))
               (second (two-digits s 17))
               (pos 19))
          (unless (and (char= (char s 4) #\-) (char= (char s 7) #\-)
                       (char-equal (char s 10) #\T)
                       (char= (char s 13) #\:) (char= (char s 16) #\:)
                       (<= 1 month 12) (<= 1 day 31) (<= 0 hour 23) (<= 0 minute 59) (<= 0 second 59)
                       (<= 1900 year 9999))
            (return-from parse-rfc3339 nil))
          (when (and (< pos (length s)) (char= (char s pos) #\.))
            (incf pos)
            (loop while (and (< pos (length s)) (digit-char-p (char s pos))) do (incf pos)))
          (let ((offset
                  (cond ((>= pos (length s)) (return-from parse-rfc3339 nil))
                        ((and (char-equal (char s pos) #\Z) (= (1+ pos) (length s))) 0)
                        ((and (member (char s pos) '(#\+ #\-)) (= (+ pos 6) (length s))
                              (char= (char s (+ pos 3)) #\:))
                         (* (if (char= (char s pos) #\-) -1 1)
                            (+ (* 3600 (two-digits s (1+ pos))) (* 60 (two-digits s (+ pos 4))))))
                        (t (return-from parse-rfc3339 nil)))))
            ;; Validate the calendar date by round-tripping.
            (let ((ut (encode-universal-time second minute hour day month year 0)))
              (multiple-value-bind (s2 m2 h2 d2 mo2 y2) (decode-universal-time ut 0)
                (declare (ignore s2 m2 h2))
                (unless (and (= d2 day) (= mo2 month) (= y2 year))
                  (return-from parse-rfc3339 nil)))
              (- ut offset))))
      (error () nil))))

(declaim (ftype (function (universal-time) (values simple-string &optional)) format-rfc3339))
(defun format-rfc3339 (ut)
  (multiple-value-bind (s m h d mo y) (decode-universal-time ut 0)
    (coerce (format nil "~4,'0d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ" y mo d h m s) 'simple-string)))

(declaim (ftype (function (t) (values (or null universal-time) &optional)) parse-date))
(defun parse-date (string)
  "Universal time of 00:00Z on the date YYYY-MM-DD, or NIL when invalid."
  (when (and (stringp string) (= (length string) 10)
             (char= (char string 4) #\-) (char= (char string 7) #\-)
             ;; Exactly YYYY-MM-DD: ASCII digits in every other position.
             (loop for i in '(0 1 2 3 5 6 8 9) always (char<= #\0 (char string i) #\9)))
    (let ((year (parse-integer string :start 0 :end 4))
          (month (parse-integer string :start 5 :end 7))
          (day (parse-integer string :start 8 :end 10)))
      (when (and (<= 1900 year 9999) (<= 1 month 12) (<= 1 day 31))
        (let ((ut (encode-universal-time 0 0 0 day month year 0)))
          (multiple-value-bind (s m h d2 mo2 y2) (decode-universal-time ut 0)
            (declare (ignore s m h))
            (when (and (= d2 day) (= mo2 month) (= y2 year))
              ut)))))))

(defun valid-date-string-p (string)
  (and (parse-date string) t))

(declaim (ftype (function (universal-time) (values simple-string &optional)) format-date))
(defun format-date (ut)
  (multiple-value-bind (s m h d mo y) (decode-universal-time ut 0)
    (declare (ignore s m h))
    (coerce (format nil "~4,'0d-~2,'0d-~2,'0d" y mo d) 'simple-string)))

(declaim (ftype (function (string integer) (values simple-string &optional)) date-add-days))
(defun date-add-days (date days)
  "DATE (YYYY-MM-DD) shifted by DAYS calendar days."
  (let ((ut (or (parse-date date) (error "invalid date ~s" date))))
    (format-date (+ ut (* days 86400)))))

(defun date-at (date hour)
  "Universal time of HOUR:00:00Z on DATE."
  (+ (or (parse-date date) (error "invalid date ~s" date)) (* hour 3600)))

(defun date-add-months (date months)
  "Shift calendar months, clamping the day to the destination month's end."
  (multiple-value-bind (s m h day month year) (decode-universal-time (parse-date date) 0)
    (declare (ignore s m h))
    (multiple-value-bind (years zero-month) (floor (+ (* year 12) (1- month) months) 12)
      (let* ((next (+ zero-month 2))
             (last-day (nth-value 3 (decode-universal-time (- (encode-universal-time 0 0 0 1
                                                   (if (= next 13) 1 next) (if (= next 13) (1+ years) years) 0) 86400) 0))))
        (format-date (encode-universal-time 0 0 0 (min day last-day) (1+ zero-month) years 0))))))

(defun date-of (ut)
  "The UTC calendar date of universal time UT."
  (format-date ut))

(defun date<= (a b) (string<= a b))
(defun date< (a b) (string< a b))

;;; ------------------------------------------------------------------
;;; The calendar of European summer time (core/zones.lisp uses it)

(defun last-sunday (year month)
  "Universal time of 00:00Z on the last Sunday of MONTH in YEAR."
  (let* ((first-of-next (if (= month 12)
                            (encode-universal-time 0 0 0 1 1 (1+ year) 0)
                            (encode-universal-time 0 0 0 1 (1+ month) year 0)))
         (last-day (- first-of-next 86400))
         (weekday (nth-value 6 (decode-universal-time last-day 0)))) ; 0 = Monday, 6 = Sunday
    (- last-day (* 86400 (mod (- weekday 6) 7)))))

(defun unicode-digit-p (character)
  "A Unicode decimal digit (general category Nd)."
  (eq (sb-unicode:general-category character) :nd))
(defun unicode-word-character-p (character)
  "Text-rule word boundaries count Unicode letters and decimal digits, not underscore."
  (not (null (member (sb-unicode:general-category character) '(:lu :ll :lt :lm :lo :nd)))))
(defun unicode-whitespace-p (character)
  "Unicode White_Space, including newline and carriage return."
  (sb-unicode:whitespace-p character))
(defun unicode-punctuation-p (character)
  "Any Unicode punctuation or Dash property, including mathematical minus signs."
  (or (not (null (member (sb-unicode:general-category character) '(:pc :pd :ps :pe :pi :pf :po))))
      (not (null (sb-unicode:proplist-p character :dash)))))

(defun unicode-text-scanner (pattern)
  "Compile text rules with Unicode digits, whitespace and word boundaries."
  (dolist (replacement '(("[0-9]" . "\\p{tun-digit}") ("\\d" . "\\p{tun-digit}")
                         ("\\w" . "\\p{tun-word}") ("\\s" . "\\p{tun-space}")))
    (setf pattern (cl-ppcre:regex-replace-all (cl-ppcre:quote-meta-chars (car replacement)) pattern
                    (lambda (&rest arguments) (declare (ignore arguments)) (cdr replacement)))))
  (let ((cl-ppcre:*property-resolver*
          (lambda (name)
            (cond ((equal name "tun-digit") #'unicode-digit-p)
                  ((equal name "tun-word") #'unicode-word-character-p)
                  ((equal name "tun-space") #'unicode-whitespace-p)
                  (t (error "Unknown request text property ~a" name))))))
    (cl-ppcre:create-scanner pattern)))

(defun check-written-text (what option value)
  "Refuse VALUE as the OPTION (such as :LABEL) of WHAT unless it is a string
or NIL.  A field's or a parameter's options are data, not evaluated: a
constant's name there would become the text, which JSON cannot encode."
  (unless (or (null value) (stringp value))
    (error "~a: ~(~s~) must be a string written out, not ~s (it is not evaluated)"
           what option value)))
