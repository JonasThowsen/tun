;;;; core/formats.lisp -- amounts, dates and numbers as the tenant's language
;;;; writes them, and amounts read back from a form (spec/i18n.md 5, 6.2).
;;;;
;;;; Every amount is an integer of minor units and is written and read with
;;;; integers only: a float would read 0,29 as 28 øre.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Currencies

(defparameter +currencies+
  '(("NOK" 2 nil "kr") ("SEK" 2 nil nil) ("DKK" 2 nil nil) ("ISK" 0 nil nil)
    ("EUR" 2 "€" "€") ("GBP" 2 "£" "£") ("USD" 2 "US$" nil) ("CHF" 2 nil nil) ("PLN" 2 nil nil))
  "The currencies Tun knows (spec/i18n.md 5.1): (CODE MINOR-DIGITS
ENGLISH-SYMBOL NORWEGIAN-SYMBOL).  A currency without a symbol in a language
is written with its code.")

(defun currency-p (code)
  "True when CODE is a currency of +CURRENCIES+."
  (and (stringp code) (assoc code +currencies+ :test #'string=) t))

(defun currency-spec (code)
  (or (assoc code +currencies+ :test #'string=)
      (error "~s is not a currency Tun knows (spec/i18n.md 5.1)" code)))

(defun current-currency ()
  "The tenant's currency, the request's when one is being answered."
  (locale-currency (current-locale)))

(defun currency-minor-digits (&optional (currency (current-currency)))
  "How many minor digits CURRENCY has: 2 for NOK, 0 for ISK."
  (second (currency-spec currency)))

(defparameter +most-amount+ 9007199254740991
  "The largest amount, in minor units, JSON carries exactly: 2^53 - 1.")

(defmethod money-schema-description ((type money-type))
  (let ((currency (current-currency)))
    (format nil "An amount in minor units of the tenant's currency, ~a, which has ~d ~
                 minor digits: an integer, never a decimal."
            currency (currency-minor-digits currency))))

;;; ------------------------------------------------------------------
;;; Writing

(defun writing-language ()
  "The language whose conventions numbers and dates follow: Norwegian's for
nb, English's for everything else, source text and the pseudo-language
included."
  (if (equal (current-language) "nb") "nb" "en"))

(defun group-digits (n separator)
  "The natural number N with SEPARATOR between each group of three digits."
  (let ((digits (princ-to-string n)))
    (with-output-to-string (out)
      (loop for char across digits
            for left downfrom (length digits)
            do (write-char char out)
               (when (and (> left 1) (zerop (mod (1- left) 3)))
                 (write-string separator out))))))

(defun money-text (amount &key (currency (current-currency)))
  "AMOUNT, an integer of CURRENCY's minor units, as the current language
writes it: €12,450.00, NOK 12,450.00, 12 450,00 kr (spec/i18n.md 5.4)."
  (check-type amount integer)
  (destructuring-bind (code digits english-symbol norwegian-symbol) (currency-spec currency)
    (let* ((nb (equal (writing-language) "nb"))
           (factor (expt 10 digits)))
      (multiple-value-bind (whole fraction) (floor (abs amount) factor)
        (let ((number (format nil "~a~:[~3*~;~a~v,'0d~]"
                              (group-digits whole (if nb (string #\No-break_space) ","))
                              (plusp digits) (if nb "," ".") digits fraction)))
          (if nb
              (format nil "~:[~;−~]~a~c~a" (minusp amount) number #\No-break_space
                      (or norwegian-symbol code))
              (format nil "~:[~;-~]~:[~a~c~;~a~*~]~a" (minusp amount)
                      english-symbol (or english-symbol code) #\No-break_space number)))))))

(defun number-text (value)
  "VALUE, a real, with the current language's decimal mark: 12.5, or 12,5."
  (let ((text (if (integerp value) (princ-to-string value) (format-quantity value 3))))
    (if (equal (writing-language) "nb") (substitute #\, #\. text) text)))

(defun month-abbreviation (month)
  "The abbreviated name of MONTH, 1 to 12, in the current language."
  (ecase month
    (1 (tr ("Jan" :context "month"))) (2 (tr ("Feb" :context "month")))
    (3 (tr ("Mar" :context "month"))) (4 (tr ("Apr" :context "month")))
    (5 (tr ("May" :context "month"))) (6 (tr ("Jun" :context "month")))
    (7 (tr ("Jul" :context "month"))) (8 (tr ("Aug" :context "month")))
    (9 (tr ("Sep" :context "month"))) (10 (tr ("Oct" :context "month")))
    (11 (tr ("Nov" :context "month"))) (12 (tr ("Dec" :context "month")))))

(defun date-text (date)
  "DATE, YYYY-MM-DD, as the current language writes it: 21 Oct 2026, or
21.10.2026; anything else as it is."
  (if (and (stringp date) (valid-date-string-p date))
      (let ((year (subseq date 0 4)) (month (subseq date 5 7)) (day (subseq date 8 10)))
        (if (equal (writing-language) "nb")
            (format nil "~a.~a.~a" day month year)
            (format nil "~d ~a ~a" (parse-integer day) (month-abbreviation (parse-integer month))
                    year)))
      (princ-to-string date)))

(defun instant-text (ut)
  "The instant UT, a universal time, in the tenant's time zone as the current
language writes it: 21 Oct 2026, 14:32, or 21.10.2026 kl. 14:32."
  (let ((date (date-text (local-date-of ut))) (time (local-time-of ut)))
    (if (equal (writing-language) "nb")
        (format nil "~a kl. ~a" date time)
        (format nil "~a, ~a" date time))))

(defun timestamp-text (value)
  "The RFC 3339 instant VALUE as INSTANT-TEXT writes it; anything else as it is."
  (let ((ut (and (stringp value) (parse-rfc3339 value))))
    (if ut (instant-text ut) (princ-to-string value))))

(defun yes-no-text (value)
  "Yes or No, in the current language."
  (if value (tr "Yes") (tr "No")))

;;; ------------------------------------------------------------------
;;; Reading what a person wrote in a form

(defun digits-p (string)
  (and (plusp (length string)) (every #'digit-char-p string)))

(defun grouped-whole-part (text separators)
  "The digits of TEXT, a whole part a person wrote, when it is digits alone
or groups of three after the first, separated by one of SEPARATORS: \"12450\"
and \"12 450\", not \"1 23\".  NIL otherwise."
  (let ((groups (cl-ppcre:split (format nil "[~a]" (cl-ppcre:quote-meta-chars separators))
                                text :limit most-positive-fixnum)))
    (cond ((and (= (length groups) 1) (digits-p text)) text)
          ((and (> (length groups) 1)
                (digits-p (first groups)) (<= (length (first groups)) 3)
                (every (lambda (g) (and (= (length g) 3) (digits-p g))) (rest groups)))
           (apply #'concatenate 'string groups))
          (t nil))))

(defun read-decimal-text (text &key (language (writing-language)))
  "TEXT, a number a person wrote in LANGUAGE, as values its sign (1 or -1),
its whole digits and its decimal digits, or NIL when it is not one: in en,
groups by , or a space and decimals after .; in nb, groups by a space or a
no-break space and decimals after , or . (spec/i18n.md 5.4)."
  (let* ((text (string-trim '(#\Space #\Tab) text))
         (negative (and (plusp (length text)) (member (char text 0) '(#\- #\−))))
         (body (if negative (subseq text 1) text))
         (nb (equal language "nb"))
         (marks (if nb ",." "."))
         (separators (if nb (format nil " ~c" #\No-break_space) ", "))
         (mark-positions (loop for i from 0 below (length body)
                               when (find (char body i) marks) collect i)))
    (when (and (plusp (length body)) (<= (length mark-positions) 1))
      (let* ((mark (first mark-positions))
             (whole (grouped-whole-part (subseq body 0 (or mark (length body))) separators))
             (fraction (if mark (subseq body (1+ mark)) "")))
        (when (and whole (or (null mark) (digits-p fraction)))
          (values (if negative -1 1) whole fraction))))))

(defun read-money-text (text &key (currency (current-currency)) (language (writing-language)))
  "TEXT, an amount a person wrote in LANGUAGE, as an integer of CURRENCY's
minor units, read with integers only: \"0,29\" is 29.  Values NIL and a
message when it is not an amount CURRENCY can hold (spec/i18n.md 5.4)."
  (let ((digits (currency-minor-digits currency)))
    (multiple-value-bind (sign whole fraction) (read-decimal-text text :language language)
      (cond ((null sign) (values nil (deferred-tr "must be an amount, such as ~a"
                                               (money-text 1245050 :currency currency))))
            ((> (length fraction) digits)
             (values nil (if (zerop digits)
                             (deferred-tr "cannot have decimals in ~a" currency)
                             (deferred-tr "can have at most ~d decimals" digits))))
            (t (let ((amount (* sign (+ (* (parse-integer whole) (expt 10 digits))
                                        (if (plusp (length fraction))
                                            (* (parse-integer fraction)
                                               (expt 10 (- digits (length fraction))))
                                            0)))))
                 (if (> (abs amount) +most-amount+)
                     (values nil (deferred-tr "is too large: at most ~a"
                                              (money-text +most-amount+ :currency currency)))
                     amount)))))))
