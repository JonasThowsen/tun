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

(defparameter *max-number-length* 64
  "Longest numeric literal accepted (jzon parses long numbers in quadratic time).")

(defun check-number-lengths (string)
  "Signal JSON-PARSE-FAILURE if a numeric literal outside strings is longer
than *MAX-NUMBER-LENGTH*. One linear pass, before jzon sees the text."
  (let ((in-string nil) (escaped nil) (run 0))
    (loop for ch across string
          do (cond (in-string
                    (cond (escaped (setf escaped nil))
                          ((char= ch #\\) (setf escaped t))
                          ((char= ch #\") (setf in-string nil))))
                   ((char= ch #\") (setf in-string t run 0))
                   ((find ch "0123456789+-.eE")
                    (when (> (incf run) *max-number-length*)
                      (error 'json-parse-failure :detail "number literal too long")))
                   (t (setf run 0))))))

(defun parse-json (string)
  "Parse STRING strictly. Never evaluates anything; depth, string and number
lengths bounded."
  (check-number-lengths string)
  (handler-case
      (com.inuoe.jzon:parse string :max-depth 64 :allow-comments nil :allow-trailing-comma nil
                                   :max-string-length 1048576)
    (error (e) (error 'json-parse-failure :detail (princ-to-string e)))))

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
                   ((integerp v) (format stream "~d" v))
                   ((rationalp v) (emit (float v 1d0)))
                   ((floatp v)
                    (if (= v (ftruncate v))
                        (format stream "~d" (truncate v))
                        (let ((*read-default-float-format* 'double-float))
                          (format stream "~f" v))))
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
