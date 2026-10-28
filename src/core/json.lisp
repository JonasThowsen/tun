;;;; core/json.lisp -- JSON values, parsing (jzon) and encoding (own).
;;;;
;;;; Representation, shared by every layer:
;;;;   object  -> EQUAL hash table (SBCL keeps insertion order)
;;;;   array   -> vector, or a non-empty list on output
;;;;   true    -> T          false -> NIL
;;;;   null    -> :NULL (CL:NULL is accepted too, it is what jzon returns)
;;;; An empty array must be a vector: NIL always encodes as false.  The
;;;; encoder is ours so this rule lives in exactly one place, and so a
;;;; canonical (sorted-key) form exists for hashing inputs.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defun json-null-p (value)
  (or (eq value :null) (eq value 'null)))

(defun jobj (&rest keys-and-values)
  "Build a JSON object from alternating string keys and values, in order."
  (let ((table (make-hash-table :test 'equal)))
    (loop for (key value) on keys-and-values by #'cddr
          do (check-type key string)
             (setf (gethash key table) value))
    table))

(defun jarr (list)
  "Coerce a list to a JSON array value (a vector), so NIL becomes []."
  (coerce list 'simple-vector))

(defun json-bool (generalized-boolean)
  (if generalized-boolean t nil))

(defun json-object-p (value) (hash-table-p value))

(defun json-array-p (value) (and (vectorp value) (not (stringp value))))

(defun jget (object key &optional default)
  "Value of KEY in JSON OBJECT (NIL-safe). Second value: whether KEY is present."
  (if (hash-table-p object)
      (multiple-value-bind (value present) (gethash key object)
        (if present (values value t) (values default nil)))
      (values default nil)))

(defun (setf jget) (value object key)
  (setf (gethash key object) value))

(defun jkeys (object)
  (loop for k being the hash-keys of object collect k))

;;; ------------------------------------------------------------------
;;; Parsing

(define-condition json-parse-failure (error)
  ((detail :initarg :detail :reader json-parse-failure-detail))
  (:report (lambda (c s) (format s "Invalid JSON: ~a" (json-parse-failure-detail c)))))

(defvar *max-number-length* 1000
  "Longest numeric literal PARSE-JSON takes: jzon reads long numbers in time
that grows with their square.  Tun writes integers of any size into JSON it
keeps, so its own bound is generous; PARSE-REQUEST-JSON binds it to
+MOST-REQUEST-NUMBER-LENGTH+.")

(defparameter +most-request-number-length+ 64
  "Longest numeric literal a caller may send.")

(defparameter +most-exponent-digits+ 4
  "The most digits a number's exponent may have, in any JSON: jzon makes 10
to the exponent as an integer, in time that grows with its square, and Tun
writes at most three.")

(defvar *caller-numbers* nil
  "True while parsing what a caller sent (PARSE-REQUEST-JSON): numbers are
then held to what Tun takes as input, +MOST-SIGNIFICANT-DIGITS+ and a
double's normal range.  JSON Tun wrote itself, kept in the store or a
receipt, is never refused for a number Tun can write.")

(defparameter +most-significant-digits+ 19
  "The most significant digits a caller's number may have: an integer of 64
bits has 19, a double needs 17.  More make jzon work in big integers for
each number, about 4 KB a number.")

(defparameter +most-decimal-exponent+ 308
  "The largest power of ten a caller's number may reach: a double holds up
to about 1.8e308; one past it is refused when jzon cannot make it.")

(defparameter +least-normal-digits+ 22250738585072014
  "The digits of the least normal double, 2.2250738585072014e-308: the
smallest a caller's number other than 0 may be.  Below it a double is
subnormal, and jzon works in big integers to make one, about 2 KB a number;
further out, in time that grows with the square of the exponent.")

(defparameter +least-normal-power+ -308
  "The power of ten of +LEAST-NORMAL-DIGITS+' first digit.")

(defparameter +max-request-json-values+ 10000
  "The most values a request's JSON may hold (core.md §7.5), counted as its
brackets, commas and colons outside strings.  Parsed, a value costs up to
about half a kilobyte of heap (an empty object is a hash table), so a
request's JSON costs at most about 5 MB however small its text, and the 64
requests --max-inflight lets in at once at most about 320 MB of the 2 GiB
heap.  A tool call, even one with ten files, has a few dozen.")

(defvar *max-json-values* nil
  "The most values PARSE-JSON takes, or NIL for no bound: JSON Tun wrote
itself.  PARSE-REQUEST-JSON binds it for what a caller sent.")

(define-condition json-too-many-values (json-parse-failure) ()
  (:documentation "JSON with more values than *MAX-JSON-VALUES*."))

(defparameter +number-too-many-digits+ "A number can have at most 19 digits."
  "What a caller is told of a number with more than +MOST-SIGNIFICANT-DIGITS+
significant digits (core.md §7.5).")

(defparameter +number-out-of-range+
  (format nil "A number must be 0, or between 2.2250738585072014e-308 and ~
               1.7976931348623157e308, with or without a minus.")
  "What a caller is told of a number out of a double's normal range (core.md §7.5).")

(define-condition json-number-out-of-range (json-parse-failure)
  ((message :initarg :message :initform +number-out-of-range+ :reader json-number-message))
  (:documentation "JSON with a number Tun does not read: an exponent of more than
+MOST-EXPONENT-DIGITS+ digits, a number a double cannot hold, or from a
caller, more than +MOST-SIGNIFICANT-DIGITS+ significant digits or one
outside a double's normal range.  JSON-NUMBER-MESSAGE says which, for the
caller."))

(defun number-refusal (significant digits power exponent-digits)
  "Why a number is refused, as its message, or NIL: SIGNIFICANT, how many
significant digits it has; DIGITS, the first of them as an integer; POWER,
the power of ten of the first; EXPONENT-DIGITS, how many digits its
exponent has."
  (cond ((> exponent-digits +most-exponent-digits+) +number-out-of-range+)
        ((not *caller-numbers*) nil)
        ((> significant +most-significant-digits+) +number-too-many-digits+)
        ((zerop significant) nil)
        ((> power +most-decimal-exponent+) +number-out-of-range+)
        ((< power +least-normal-power+) +number-out-of-range+)
        ;; At the least normal double's power: compare the digits, both
        ;; scaled to as many digits as the longer has.
        ((and (= power +least-normal-power+)
              (let ((least-length (length (princ-to-string +least-normal-digits+))))
                (< (* digits (expt 10 (max 0 (- least-length significant))))
                   (* +least-normal-digits+ (expt 10 (max 0 (- significant least-length)))))))
         +number-out-of-range+)))

(defun check-json-shape (text)
  "Signal JSON-PARSE-FAILURE if a numeric literal outside strings is longer
than *MAX-NUMBER-LENGTH*; JSON-NUMBER-OUT-OF-RANGE for a number
NUMBER-REFUSAL refuses; and JSON-TOO-MANY-VALUES if TEXT, a string or its
UTF-8 octets, holds more values than *MAX-JSON-VALUES*.  One linear pass,
before jzon sees the text: what it looks at is ASCII, the same in both."
  (let ((in-string nil) (escaped nil) (values 0)
        ;; The number being read: its length; its significant digits (from
        ;; the first that is not 0), the first 20 of them as an integer; how
        ;; many are before its point, or, when none is, how many zeros
        ;; follow the point; and its exponent's sign, digits and value.
        (in-number nil) (length 0) (significant 0) (digits 0) (whole 0) (zeros 0)
        (point-p nil) (exponent-p nil) (exponent-sign 1) (exponent-digits 0) (exponent 0))
    (labels ((digit-p (code) (<= 48 code 57))
             (power-of-ten ()
               ;; The power of ten of the number's first significant digit.
               (+ (* exponent-sign exponent) (if (plusp whole) (1- whole) (- (1+ zeros)))))
             (end-number ()
               (when in-number
                 (let ((refusal (number-refusal significant digits (power-of-ten)
                                                exponent-digits)))
                   (when refusal
                     (error 'json-number-out-of-range :detail "number out of range"
                                                      :message refusal))))
               (setf in-number nil))
             (read-number (code)
               (unless in-number
                 (setf in-number t length 0 significant 0 digits 0 whole 0 zeros 0 point-p nil
                       exponent-p nil exponent-sign 1 exponent-digits 0 exponent 0))
               (when (> (incf length) *max-number-length*)
                 (error 'json-parse-failure :detail "number literal too long"))
               (cond ((or (= code 101) (= code 69)) (setf exponent-p t)) ; e E
                     ((= code 46) (setf point-p t))                       ; .
                     ((and exponent-p (= code 45)) (setf exponent-sign -1))
                     ((not (digit-p code)))
                     (exponent-p
                      (when (<= (incf exponent-digits) (1+ +most-exponent-digits+))
                        (setf exponent (+ (* 10 exponent) (- code 48)))))
                     ((or (plusp significant) (/= code 48))
                      (when (<= (incf significant) (1+ +most-significant-digits+))
                        (setf digits (+ (* 10 digits) (- code 48))))
                      (unless point-p (incf whole)))
                     (point-p (incf zeros))))
             (look (code)
               (cond (in-string
                      (cond (escaped (setf escaped nil))
                            ((= code 92) (setf escaped t))       ; \
                            ((= code 34) (setf in-string nil)))) ; "
                     ((or (digit-p code) (= code 45) ; a number starts with a digit or -
                          (and in-number (find code '(43 46 101 69)))) ; then + . e E
                      (read-number code))
                     (t (end-number)
                        (when (= code 34) (setf in-string t))
                        (when (and *max-json-values* (find code '(123 91 44 58)) ; { [ , :
                                   (> (incf values) *max-json-values*))
                          (error 'json-too-many-values
                                 :detail (format nil "more than ~d values" *max-json-values*)))))))
      (if (stringp text)
          (loop for char across text do (look (char-code char)))
          (loop for octet across text do (look octet)))
      (end-number))))

(defvar *max-json-string-length* 1048576
  "The longest string PARSE-JSON takes (core.md §7.5).")

(defun parse-json (text)
  "Parse TEXT, a string or its UTF-8 octets, strictly. Never evaluates
anything; depth, string and number lengths bounded.  From octets, a string
of only ASCII characters is made a base string, one octet a character."
  (check-json-shape text)
  (handler-case
      (com.inuoe.jzon:parse text :max-depth 64 :allow-comments nil :allow-trailing-comma nil
                                 :max-string-length *max-json-string-length*)
    ;; Such as 1.8e308 or 2e-324: a double cannot hold it.
    ((or floating-point-overflow floating-point-underflow) ()
      (error 'json-number-out-of-range :detail "number beyond a double"
                                       :message +number-out-of-range+))
    (error (e) (error 'json-parse-failure :detail (princ-to-string e)))))

(defun parse-request-json (text)
  "Parse TEXT, JSON a caller sent, as PARSE-JSON does, holding it to
+MAX-REQUEST-JSON-VALUES+ values (JSON-TOO-MANY-VALUES) and its numbers to
what Tun takes as input (*CALLER-NUMBERS*)."
  (let ((*max-json-values* +max-request-json-values+)
        (*max-number-length* +most-request-number-length+)
        (*caller-numbers* t))
    (parse-json text)))

;;; ------------------------------------------------------------------
;;; Encoding

(defun write-json-string (string stream)
  (write-char #\" stream)
  (loop for ch across string
        for code = (char-code ch)
        do (case ch
             (#\" (write-string "\\\"" stream))
             (#\\ (write-string "\\\\" stream))
             (#\Newline (write-string "\\n" stream))
             (#\Return (write-string "\\r" stream))
             (#\Tab (write-string "\\t" stream))
             (#\Backspace (write-string "\\b" stream))
             (#\Page (write-string "\\f" stream))
             (t (if (< code #x20)
                    (format stream "\\u~4,'0x" code)
                    (write-char ch stream)))))
  (write-char #\" stream))

(defun write-json (value stream &key canonical)
  "Write VALUE as JSON. With CANONICAL, object keys are sorted (for hashing)."
  (labels ((emit (v)
             (cond ((eq v t) (write-string "true" stream))
                   ((null v) (write-string "false" stream))
                   ((json-null-p v) (write-string "null" stream))
                   ((stringp v) (write-json-string v stream))
                   ;; A message kept as its text (core/i18n.lisp), written in
                   ;; the current language.
                   ((text-p v) (write-json-string (render-text v) stream))
                   ((integerp v) (format stream "~d" v))
                   ((rationalp v) (emit (float v 1d0)))
                   ((floatp v)
                    ;; A whole number of modest size as an integer (3, not
                    ;; 3.0); else the shortest form that reads back as V
                    ;; (Schubfach), never printed digit by digit as ~F
                    ;; would, which for 1e-300 costs bignums and 300 digits.
                    (cond ((and (< (abs v) 1d15) (= v (ftruncate v)))
                           (format stream "~d" (truncate v)))
                          ((typep v 'double-float)
                           (com.inuoe.jzon/schubfach:write-double v stream))
                          (t (com.inuoe.jzon/schubfach:write-float v stream))))
                   ((hash-table-p v)
                    (write-char #\{ stream)
                    (let ((keys (jkeys v)) (first t))
                      (when canonical (setf keys (sort (copy-list keys) #'string<)))
                      (dolist (k keys)
                        (unless first (write-char #\, stream))
                        (setf first nil)
                        (write-json-string (if (stringp k) k (princ-to-string k)) stream)
                        (write-char #\: stream)
                        (emit (gethash k v))))
                    (write-char #\} stream))
                   ((or (vectorp v) (consp v))
                    (write-char #\[ stream)
                    (let ((first t))
                      (map nil (lambda (x)
                                 (unless first (write-char #\, stream))
                                 (setf first nil)
                                 (emit x))
                           v))
                    (write-char #\] stream))
                   ((keywordp v) (write-json-string (json-name-of v) stream))
                   (t (error "Cannot encode ~s as JSON" v)))))
    (emit value)))

(defun to-json-string (value &key canonical)
  (with-output-to-string (out)
    (write-json value out :canonical canonical)))

(defun canonical-json-hash (value)
  "SHA-256 of the canonical encoding of VALUE."
  (sha256-hex (to-json-string value :canonical t)))

(defun json-copy (value)
  "Deep copy through the encoder (used for snapshots)."
  (parse-json (to-json-string value)))
