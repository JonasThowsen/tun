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

(defun fixed-decimals-text (value digits)
  "VALUE, a real, with exactly DIGITS decimals, rounded half away from zero,
and a point as its decimal mark: 281.40 for 281.4 and 2."
  (let ((scaled (floor (+ (* (abs (rational value)) (expt 10 digits)) 1/2))))
    (multiple-value-bind (whole fraction) (floor scaled (expt 10 digits))
      (format nil "~:[~;-~]~d~:[~2*~;.~v,'0d~]" (and (minusp value) (plusp scaled))
              whole (plusp digits) digits fraction))))

(defun number-text (value &key digits)
  "VALUE, a real, with the current language's decimal mark: 12.5, or 12,5.
With DIGITS, from 0 to 6, it has that many decimals, rounded half away from
zero: 12.50, or 12,50; without, as many as it has, up to three."
  (check-type digits (or null (integer 0 6)))
  (let ((text (cond (digits (fixed-decimals-text value digits))
                    ((integerp value) (princ-to-string value))
                    (t (format-quantity value 3)))))
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

(defun day-text (date)
  "DATE, YYYY-MM-DD, without its year as the current language writes it: 21
Oct, or 21.10.; anything else as it is."
  (if (and (stringp date) (valid-date-string-p date))
      (let ((month (subseq date 5 7)) (day (subseq date 8 10)))
        (if (equal (writing-language) "nb")
            (format nil "~a.~a." day month)
            (format nil "~d ~a" (parse-integer day) (month-abbreviation (parse-integer month)))))
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

;;; ------------------------------------------------------------------
;;; Dates and times as a person writes them (spec/i18n.md 6.2)
;;;
;;; The same forms in every language, day first, as Tun writes its dates:
;;; one reader, on the server, judges every date and time a form posts.

(defun money-number-text (amount &key (currency (current-currency)))
  "AMOUNT, an integer of CURRENCY's minor units, as the current language
writes the number of it, without the currency: 12,450.00 or 12 450,00, a
negative one with - or −.  What a money field shows."
  (check-type amount integer)
  (let* ((digits (currency-minor-digits currency))
         (nb (equal (writing-language) "nb"))
         (factor (expt 10 digits)))
    (multiple-value-bind (whole fraction) (floor (abs amount) factor)
      (format nil "~a~a~:[~2*~;~a~v,'0d~]"
              (cond ((not (minusp amount)) "") (nb "−") (t "-"))
              (group-digits whole (if nb (string #\No-break_space) ","))
              (plusp digits) (if nb "," ".") digits fraction))))

(defun month-name (month)
  "The name of MONTH, 1 to 12, in the current language: November, november."
  (ecase month
    (1 (tr ("January" :context "month"))) (2 (tr ("February" :context "month")))
    (3 (tr ("March" :context "month"))) (4 (tr ("April" :context "month")))
    (5 (tr ("May" :context "month"))) (6 (tr ("June" :context "month")))
    (7 (tr ("July" :context "month"))) (8 (tr ("August" :context "month")))
    (9 (tr ("September" :context "month"))) (10 (tr ("October" :context "month")))
    (11 (tr ("November" :context "month"))) (12 (tr ("December" :context "month")))))

(defun calendar-day-name (day)
  "The name of DAY, 1 for Monday to 7 for Sunday, in the current language."
  (ecase day
    (1 (tr ("Monday" :context "weekday"))) (2 (tr ("Tuesday" :context "weekday")))
    (3 (tr ("Wednesday" :context "weekday"))) (4 (tr ("Thursday" :context "weekday")))
    (5 (tr ("Friday" :context "weekday"))) (6 (tr ("Saturday" :context "weekday")))
    (7 (tr ("Sunday" :context "weekday")))))

(defun calendar-day-short-name (day)
  "The short name of DAY, 1 for Monday to 7 for Sunday, a calendar's column
heading: Mo, ma."
  (ecase day
    (1 (tr ("Mo" :context "weekday"))) (2 (tr ("Tu" :context "weekday")))
    (3 (tr ("We" :context "weekday"))) (4 (tr ("Th" :context "weekday")))
    (5 (tr ("Fr" :context "weekday"))) (6 (tr ("Sa" :context "weekday")))
    (7 (tr ("Su" :context "weekday")))))

(defun week-first-day ()
  "The day a week starts on, 1 for Monday to 7 for Sunday: Monday in every
language Tun writes (ISO 8601), the one place a regional setting would
change it."
  1)

(defun weekday-of (date)
  "The day of the week of DATE, YYYY-MM-DD: 1 for Monday to 7 for Sunday."
  (1+ (nth-value 6 (decode-universal-time (parse-date date) 0))))

(defun page-today ()
  "Today as the tenant's calendar has it, YYYY-MM-DD; outside an
application, as the system's clock has it in Tun's default zone."
  (if *application* (local-today) (local-date-of (get-universal-time))))

(defparameter +english-months+
  '("january" "february" "march" "april" "may" "june" "july" "august" "september"
    "october" "november" "december"))

(defun month-of-word (word)
  "The month, 1 to 12, WORD names in English or in the current language,
whole or by its first three letters, in any case, with a dot after it or
not; NIL for any other word."
  (let ((word (string-downcase (string-right-trim "." word))))
    (flet ((names (whole short)
             (or (position word whole :test #'string=)
                 (position word short :test #'string=)))
           (local (function)
             (loop for month from 1 to 12
                   collect (string-downcase (string-right-trim "." (funcall function month))))))
      (let* ((local-whole (local #'month-name))
             (found (or (names +english-months+
                               (mapcar (lambda (name) (subseq name 0 3)) +english-months+))
                        (names local-whole
                               (mapcar (lambda (name) (subseq name 0 (min 3 (length name))))
                                       local-whole))
                        (names '() (local #'month-abbreviation)))))
        (and found (1+ found))))))

(defun date-separator-p (char)
  (or (find char "./-,") (member char '(#\Space #\Tab #\No-break_space))))

(defun ascii-digit-p (char)
  (char<= #\0 char #\9))

(defun date-tokens (text)
  "TEXT split into its runs of digits and of letters, as strings, or NIL
when it holds anything else, starts with a separator, or is empty.
Separators between the runs, and after the last, are dropped."
  (let ((tokens '()) (i 0) (n (length text)))
    (loop while (< i n)
          do (let ((char (char text i)))
               (cond ((date-separator-p char)
                      (when (null tokens) (return-from date-tokens nil))
                      (incf i))
                     ((ascii-digit-p char)
                      (let ((end (or (position-if-not #'ascii-digit-p text :start i) n)))
                        (push (subseq text i end) tokens)
                        (setf i end)))
                     ((alpha-char-p char)
                      (let ((end (or (position-if-not #'alpha-char-p text :start i) n)))
                        (push (subseq text i end) tokens)
                        (setf i end)))
                     (t (return-from date-tokens nil)))))
    (nreverse tokens)))

(defun date-of-parts (year month day)
  "YYYY-MM-DD for YEAR, MONTH and DAY when that day exists from 1900 to
9999, else NIL."
  (and (integerp year) (integerp month) (integerp day)
       (<= 1900 year 9999) (<= 1 month 12) (<= 1 day 31)
       (let ((date (format nil "~4,'0d-~2,'0d-~2,'0d" year month day)))
         (and (valid-date-string-p date) date))))

(defun digits-of-length-p (token &rest lengths)
  (and (stringp token) (every #'ascii-digit-p token) (member (length token) lengths) t))

(defun year-of (token this-year)
  "The year TOKEN names: four digits as they are, two as 20YY, none
(NIL) as THIS-YEAR; :REFUSED for anything else."
  (cond ((null token) this-year)
        ((digits-of-length-p token 4) (parse-integer token))
        ((digits-of-length-p token 2) (+ 2000 (parse-integer token)))
        (t :refused)))

(defun read-date-parts (tokens this-year)
  "The date the TOKENS of a date name, or NIL."
  (let* ((words (remove-if (lambda (token) (ascii-digit-p (char token 0))) tokens))
         (numbers (remove-if-not (lambda (token) (ascii-digit-p (char token 0))) tokens)))
    (flet ((dmy (day month year)
             (let ((year (year-of year this-year)))
               (and (digits-of-length-p day 1 2) (integerp year)
                    (date-of-parts year (if (integerp month) month (parse-integer month))
                                   (parse-integer day))))))
      (cond ((null tokens) nil)
            ((and (null words) (= 1 (length tokens)))
             (let ((digits (first tokens)))
               (case (length digits)
                 (8 (dmy (subseq digits 0 2) (subseq digits 2 4) (subseq digits 4)))
                 (6 (dmy (subseq digits 0 2) (subseq digits 2 4) (subseq digits 4)))
                 (4 (dmy (subseq digits 0 2) (subseq digits 2 4) nil)))))
            ((null words)
             (destructuring-bind (first second &optional third &rest more) tokens
               (cond (more nil)
                     ((and third (digits-of-length-p first 4))
                      (and (digits-of-length-p second 1 2) (digits-of-length-p third 1 2)
                           (date-of-parts (parse-integer first) (parse-integer second)
                                          (parse-integer third))))
                     ((digits-of-length-p second 1 2) (dmy first second third)))))
            ((and (= 1 (length words)) (<= 1 (length numbers) 2) (<= (length tokens) 3))
             (let ((month (month-of-word (first words)))
                   (at (position (first words) tokens)))
               (when month
                 (case at
                   ;; 21 Oct, 21 Oct 2026
                   (1 (dmy (first tokens) month (third tokens)))
                   ;; Oct 21, Oct 21 2026
                   (0 (dmy (second tokens) month (third tokens)))))))))))

(defparameter +example-date+ "2026-10-21"
  "The date a field's hint and error show as an example: a day past the
twelfth, so the order of day and month shows.")

(defun read-date-text (text &key (today (page-today)))
  "TEXT, a date a person wrote, as YYYY-MM-DD: day first in every language,
in the forms of spec/i18n.md 6.2, a date without a year in TODAY's year.
Values NIL and a message for the field when it is not one, and NIL alone
for an empty text."
  (let ((text (string-trim '(#\Space #\Tab #\No-break_space) (or text ""))))
    (if (zerop (length text))
        nil
        (let ((date (and (<= (length text) 40)
                         (read-date-parts (date-tokens text)
                                          (parse-integer today :end 4)))))
          (or date
              (values nil (deferred-tr "must be a date, such as ~a"
                                       (date-text +example-date+))))))))

(defun read-time-text (text)
  "TEXT, a time of day a person wrote, as HH:MM, 24 hours: an hour alone
(9), three or four digits (930, 1330), or the hour and two digits of
minutes between :, ., , or a space (spec/i18n.md 6.2).  Values NIL and a
message for the field when it is not one, and NIL alone for an empty text."
  (let ((text (string-trim '(#\Space #\Tab #\No-break_space) (or text ""))))
    (if (zerop (length text))
        nil
        (destructuring-bind (&optional hour minute)
            (or (cl-ppcre:register-groups-bind ((#'parse-integer h) (#'parse-integer m))
                    ("^([0-9]{1,2})(?:[ ]*[:.,][ ]*|[ ]+)([0-9]{2})$" text)
                  (list h m))
                (cl-ppcre:register-groups-bind ((#'parse-integer h))
                    ("^([0-9]{1,2})$" text)
                  (list h 0))
                (cl-ppcre:register-groups-bind ((#'parse-integer h) (#'parse-integer m))
                    ("^([0-9]{1,2})([0-9]{2})$" text)
                  (list h m)))
          (if (and hour (<= 0 hour 23) (<= 0 minute 59))
              (format nil "~2,'0d:~2,'0d" hour minute)
              (values nil (deferred-tr "must be a time of day, such as ~a" "09:30")))))))

(defun period-text (from to &key (today (page-today)))
  "The period from FROM to TO, dates YYYY-MM-DD or NIL, as the current
language writes it (spec/i18n.md 6.2): 1–14 Nov, 28 Oct – 3 Nov, From 1
Nov, Until 14 Nov; nb 01.–14.11., 28.10.–03.11., Fra 01.11., Til 14.11.
The years show when a day is not in TODAY's year.  A value that is not a
date is written as it is; NIL when both are empty."
  (flet ((given (value) (and (stringp value) (plusp (length value)) value))
         (dated (value) (and (stringp value) (valid-date-string-p value))))
    (let* ((from (given from)) (to (given to))
           (nb (equal (writing-language) "nb"))
           (year (subseq today 0 4))
           (years (some (lambda (value) (and (dated value) (string/= year (subseq value 0 4))))
                        (list from to))))
      (flet ((day (value)
               (cond ((not (dated value)) value)
                     (years (date-text value))
                     (t (day-text value)))))
        (cond ((and from to (string= from to)) (day from))
              ((and from to)
               (cond ((and (not years) (dated from) (dated to)
                           (string= (subseq from 0 7) (subseq to 0 7)))
                      (if nb
                          (format nil "~a.–~a" (subseq from 8 10) (day-text to))
                          (format nil "~d–~a" (parse-integer from :start 8) (day-text to))))
                     (nb (format nil "~a–~a" (day from) (day to)))
                     (t (format nil "~a – ~a" (day from) (day to)))))
              (from (tr "From ~a" (day from)))
              (to (tr "Until ~a" (day to))))))))

(defun currency-mark (&optional (currency (current-currency)))
  "What stands beside an amount of CURRENCY in the current language, and
where: values the symbol or the code, and :BEFORE in English (€, NOK) or
:AFTER in Norwegian (kr, €), as MONEY-TEXT writes it."
  (destructuring-bind (code digits english-symbol norwegian-symbol) (currency-spec currency)
    (declare (ignore digits))
    (if (equal (writing-language) "nb")
        (values (or norwegian-symbol code) :after)
        (values (or english-symbol code) :before))))
