;;;; core/rank.lisp -- rank keys: strings that put records in an order a
;;;; person chose, one key per record (core.md 2.6).
;;;;
;;;; A key sorts between its neighbours by code point, the order every store
;;;; compares text in, so moving a record changes only its own key.  This is
;;;; fractional indexing in base 62, ported from rocicorp's
;;;; fractional-indexing (CC0): a key is a whole part, whose first letter
;;;; gives its length, then a fraction that never ends in the digit 0.
;;;; Adding at either end steps the whole part, which stays short; adding
;;;; between two keys lengthens the fraction.  Stored keys depend on every
;;;; detail here, so the format must not change.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +rank-digits+ "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  "The 62 digits of a rank key, in code-point order.")

(defparameter +smallest-whole-part+ (concatenate 'string "A" (make-string 26 :initial-element #\0))
  "The smallest whole part.  It is not a key alone, so a key can always be
made before any key.")

(defun rank-digit (char)
  "The value of the digit CHAR, or NIL when it is not one."
  (position char +rank-digits+))

(defun digit-char-of (value)
  (char +rank-digits+ value))

(defun whole-part-length (head)
  "The length of a whole part that starts with HEAD, or NIL when HEAD
starts none: a to z give 2 to 27, Z to A give 2 to 27."
  (cond ((char<= #\a head #\z) (+ 2 (- (char-code head) (char-code #\a))))
        ((char<= #\A head #\Z) (+ 2 (- (char-code #\Z) (char-code head))))))

(defun rank-key-p (object)
  "True when OBJECT is a rank key (core.md 2.6)."
  (and (stringp object)
       (plusp (length object))
       (every #'rank-digit object)
       (let ((length (whole-part-length (char object 0))))
         (and length
              (<= length (length object))
              (string/= object +smallest-whole-part+)
              (or (= length (length object))
                  (char/= (char object (1- (length object))) #\0))))))

(deftype rank-key ()
  "A string `rank-between` accepts and returns."
  '(satisfies rank-key-p))

(define-condition rank-order-error (error)
  ((low :initarg :low :reader rank-order-error-low)
   (high :initarg :high :reader rank-order-error-high))
  (:report (lambda (condition stream)
             (format stream "The rank key ~s is not before ~s"
                     (rank-order-error-low condition) (rank-order-error-high condition))))
  (:documentation "Signalled by `rank-between` when LOW does not sort before HIGH."))

(defun whole-part (key)
  (subseq key 0 (whole-part-length (char key 0))))

(defun fraction-part (key)
  (subseq key (whole-part-length (char key 0))))

(defun fraction-between (low high)
  "A fraction after LOW and before HIGH, or after LOW alone when HIGH is
NIL.  LOW may be empty; neither ends in 0.  The digit chosen is the one
halfway between the neighbours' digits, a half rounded up."
  (let ((shared (if high
                    (loop for n from 0
                          while (char= (if (< n (length low)) (char low n) #\0) (char high n))
                          finally (return n))
                    0)))
    (if (plusp shared)
        (concatenate 'string (subseq high 0 shared)
                     (fraction-between (subseq low (min shared (length low))) (subseq high shared)))
        (let ((low-digit (if (plusp (length low)) (rank-digit (char low 0)) 0))
              (high-digit (if high (rank-digit (char high 0)) (length +rank-digits+))))
          (cond ((> (- high-digit low-digit) 1)
                 (string (digit-char-of (floor (+ low-digit high-digit 1) 2))))
                ((and high (> (length high) 1))
                 (subseq high 0 1))
                (t
                 (concatenate 'string (string (digit-char-of low-digit))
                              (fraction-between (subseq low (min 1 (length low))) nil))))))))

(defun step-whole-part (whole by)
  "The whole part after WHOLE (BY 1) or before it (BY -1), or NIL past the
largest or before the smallest."
  (let* ((head (char whole 0))
         (digits (map 'vector #'rank-digit (subseq whole 1)))
         (top (1- (length +rank-digits+)))
         (carry t))
    (loop for i from (1- (length digits)) downto 0
          while carry
          do (let ((value (+ (aref digits i) by)))
               (cond ((> value top) (setf (aref digits i) 0))
                     ((< value 0) (setf (aref digits i) top))
                     (t (setf (aref digits i) value carry nil)))))
    (let ((rest (map 'list #'digit-char-of digits)))
      (cond ((not carry)
             (coerce (cons head rest) 'string))
            ;; The digits wrapped around: the whole part changes length.
            ((and (= by 1) (char= head #\Z)) "a0")
            ((and (= by -1) (char= head #\a)) (coerce (list #\Z (digit-char-of top)) 'string))
            ((and (= by 1) (char= head #\z)) nil)
            ((and (= by -1) (char= head #\A)) nil)
            (t
             (let ((next (code-char (+ (char-code head) by))))
               ;; Away from zero a whole part is one digit longer, towards it one shorter.
               (coerce (cons next (if (if (= by 1) (char> next #\a) (char< next #\Z))
                                      (append rest (list (digit-char-of (if (= by 1) 0 top))))
                                      (butlast rest)))
                       'string)))))))

(defun rank-between (low high)
  "A new rank key that sorts after LOW and before HIGH (core.md 2.6).  LOW
NIL means nothing above, HIGH NIL nothing below; both NIL gives \"a0\".
Each of LOW and HIGH is NIL or a rank key, else this is a TYPE-ERROR, and
when both are keys LOW must sort before HIGH, else this signals
RANK-ORDER-ERROR."
  (check-type low (or null rank-key))
  (check-type high (or null rank-key))
  (when (and low high (string>= low high))
    (error 'rank-order-error :low low :high high))
  (cond ((and (null low) (null high))
         "a0")
        ((null low)
         (let ((whole (whole-part high)))
           (cond ((string= whole +smallest-whole-part+)
                  (concatenate 'string whole (fraction-between "" (fraction-part high))))
                 ((string< whole high) whole)
                 (t (step-whole-part whole -1)))))
        ((null high)
         (let ((whole (whole-part low)))
           (or (step-whole-part whole 1)
               (concatenate 'string whole (fraction-between (fraction-part low) nil)))))
        (t
         (let ((low-whole (whole-part low))
               (high-whole (whole-part high)))
           (if (string= low-whole high-whole)
               (concatenate 'string low-whole
                            (fraction-between (fraction-part low) (fraction-part high)))
               (let ((next (step-whole-part low-whole 1)))
                 (if (and next (string< next high))
                     next
                     (concatenate 'string low-whole
                                  (fraction-between (fraction-part low) nil)))))))))
