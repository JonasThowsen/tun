;;;; jobs/cron.lisp -- cron times in Norwegian time (spec/jobs.md 8).
;;;;
;;;; A cron time is five fields, minute, hour, day of month, month and
;;;; weekday, or an alias such as @daily.  Occurrences are wall-clock times
;;;; in Norway: «07:00 on weekdays» is 07:00 in winter and in summer.  A
;;;; wall-clock time is turned into an instant with the kernel's rule for
;;;; summer time (OSLO-OFFSET): one that does not exist, in the spring gap,
;;;; becomes the first valid minute after it; one that happens twice, in the
;;;; autumn overlap, the first of the two.  Pure functions only: nothing here
;;;; reads the clock or the store.

(in-package #:tun.jobs)

(declaim (optimize (safety 3) (debug 2)))

(define-condition cron-error (error)
  ((text :initarg :text :reader cron-error-text)
   (problem :initarg :problem :reader cron-error-problem))
  (:report (lambda (c s) (format s "~s is not a cron time: ~a"
                                 (cron-error-text c) (cron-error-problem c))))
  (:documentation "A cron time that cannot be read, or that never happens."))

(defclass cron ()
  ((text :initarg :text :reader cron-text :documentation "The cron time as written.")
   (minutes :initarg :minutes :reader cron-minutes)
   (hours :initarg :hours :reader cron-hours)
   (days :initarg :days :reader cron-days :documentation "Days of the month, 1 to 31.")
   (months :initarg :months :reader cron-months)
   (weekdays :initarg :weekdays :reader cron-weekdays :documentation "0 is Sunday, 6 Saturday.")
   (days-restricted :initarg :days-restricted :reader cron-days-restricted-p)
   (weekdays-restricted :initarg :weekdays-restricted :reader cron-weekdays-restricted-p))
  (:documentation "A parsed cron time: for each field, the values it allows, ascending."))

(defparameter +cron-aliases+
  '(("@hourly" . "0 * * * *") ("@daily" . "0 0 * * *") ("@midnight" . "0 0 * * *")
    ("@weekly" . "0 0 * * 0") ("@monthly" . "0 0 1 * *")
    ("@yearly" . "0 0 1 1 *") ("@annually" . "0 0 1 1 *")))

(defparameter +cron-fields+
  ;; Name, smallest and largest value, and the names a value may have.
  '((:minute 0 59 ())
    (:hour 0 23 ())
    (:day 1 31 ())
    (:month 1 12 ("JAN" "FEB" "MAR" "APR" "MAY" "JUN" "JUL" "AUG" "SEP" "OCT" "NOV" "DEC"))
    (:weekday 0 7 ("SUN" "MON" "TUE" "WED" "THU" "FRI" "SAT"))))

(defun cron-value (text field-spec cron-text)
  "The number TEXT names in the field FIELD-SPEC of +CRON-FIELDS+."
  (destructuring-bind (field low high names) field-spec
    (let* ((named (position (string-upcase text) names :test #'string=))
           (value (cond (named (+ low named))
                        ((and (plusp (length text)) (every #'digit-char-p text))
                         (parse-integer text))
                        (t (error 'cron-error :text cron-text
                                              :problem (format nil "~a is not a ~(~a~)" text field))))))
      (unless (<= low value high)
        (error 'cron-error :text cron-text
                           :problem (format nil "the ~(~a~) ~d is outside ~d to ~d" field value low high)))
      value)))

(defun cron-part-values (part field-spec cron-text)
  "The values one comma-separated PART of a field allows: *, N, A-B, each
optionally with a step /S."
  (destructuring-bind (field low high names) field-spec
    (declare (ignore field names))
    (destructuring-bind (range &optional step) (cl-ppcre:split "/" part :limit 2)
      (let ((step (if step (cron-value step (list :step 1 high '()) cron-text) 1)))
        (destructuring-bind (from to)
            (cond ((string= range "*") (list low high))
                  ((find #\- range)
                   (mapcar (lambda (end) (cron-value end field-spec cron-text))
                           (cl-ppcre:split "-" range :limit 2)))
                  (t (let ((value (cron-value range field-spec cron-text)))
                       ;; A/S, like cron, runs from A to the end of the field.
                       (list value (if (> step 1) high value)))))
          (when (> from to)
            (error 'cron-error :text cron-text
                               :problem (format nil "the range ~a runs backwards" range)))
          (loop for value from from to to by step collect value))))))

(defun cron-field-values (text field-spec cron-text)
  (sort (remove-duplicates
         (loop for part in (cl-ppcre:split "," text)
               append (cron-part-values part field-spec cron-text)))
        #'<))

(defun parse-cron (text)
  "The CRON that TEXT, five fields or an alias such as @daily, describes.
Signals CRON-ERROR when it cannot be read or never happens."
  (check-type text string)
  (let* ((expanded (or (cdr (assoc (string-downcase (string-trim " " text)) +cron-aliases+
                                   :test #'string=))
                       text))
         (fields (cl-ppcre:split "\\s+" (string-trim " " expanded))))
    (unless (= 5 (length fields))
      (error 'cron-error :text text :problem "it needs five fields: minute, hour, day, month, weekday"))
    (destructuring-bind (minutes hours days months weekdays)
        (mapcar (lambda (field spec) (cron-field-values field spec text)) fields +cron-fields+)
      (let ((cron (make-instance 'cron
                                 :text text :minutes minutes :hours hours :days days :months months
                                 :weekdays (sort (remove-duplicates (substitute 0 7 weekdays)) #'<)
                                 :days-restricted (string/= (third fields) "*")
                                 :weekdays-restricted (string/= (fifth fields) "*"))))
        (unless (next-occurrence cron (encode-universal-time 0 0 0 1 1 2026 0))
          (error 'cron-error :text text :problem "it never happens"))
        cron))))

;;; ------------------------------------------------------------------
;;; Occurrences

(defun cron-day-p (cron date)
  "True when the local DATE, YYYY-MM-DD, is a day CRON runs on.  As in cron,
a time that names both days of the month and weekdays runs on either."
  (multiple-value-bind (s m h day month year weekday) (decode-universal-time (parse-date date) 0)
    (declare (ignore s m h year))
    (let ((day-p (member day (cron-days cron)))
          ;; DECODE-UNIVERSAL-TIME counts from Monday, 0; cron from Sunday, 0.
          (weekday-p (member (mod (1+ weekday) 7) (cron-weekdays cron))))
      (and (member month (cron-months cron))
           (if (and (cron-days-restricted-p cron) (cron-weekdays-restricted-p cron))
               (or day-p weekday-p)
               (and day-p weekday-p))))))

(defun wall-time-instant (date hour minute)
  "The instant Norwegian wall-clock HOUR:MINUTE on DATE happens: the first of
two in the autumn overlap, and for a time in the spring gap the first valid
minute after it."
  (let ((wall (+ (parse-date date) (* 3600 hour) (* 60 minute))))
    (loop for candidate from wall by 60
          for summer = (- candidate 7200)
          for winter = (- candidate 3600)
          do (cond ((= 7200 (oslo-offset summer)) (return summer))
                   ((= 3600 (oslo-offset winter)) (return winter))))))

(defun occurrence-key (date hour minute)
  "How an occurrence is known: its wall-clock time, such as
\"2026-10-25T02:30\", the same for both instants of an overlap."
  (format nil "~aT~2,'0d:~2,'0d" date hour minute))

(defparameter +cron-search-days+ (* 4 366)
  "How far to look for an occurrence: far enough for the 29th of February.")

(defun previous-occurrence (cron instant)
  "Values the latest occurrence of CRON at or before INSTANT and its key, or
NIL when there is none within four years."
  (let ((today (local-date-of instant)))
    (loop for offset from 0 below +cron-search-days+
          for date = (date-add-days today (- offset))
          when (cron-day-p cron date)
            do (dolist (hour (reverse (cron-hours cron)))
                 (dolist (minute (reverse (cron-minutes cron)))
                   (let ((at (wall-time-instant date hour minute)))
                     (when (<= at instant)
                       (return-from previous-occurrence
                         (values at (occurrence-key date hour minute))))))))))

(defun next-occurrence (cron instant)
  "Values the first occurrence of CRON after INSTANT and its key, or NIL when
there is none within four years."
  (let ((today (local-date-of instant)))
    (loop for offset from 0 below +cron-search-days+
          for date = (date-add-days today offset)
          when (cron-day-p cron date)
            do (dolist (hour (cron-hours cron))
                 (dolist (minute (cron-minutes cron))
                   (let ((at (wall-time-instant date hour minute)))
                     (when (> at instant)
                       (return-from next-occurrence
                         (values at (occurrence-key date hour minute))))))))))

;;; ------------------------------------------------------------------
;;; In words, for people (the «Jobber» page, schedules_list)

(defparameter +weekday-names+
  '("søndag" "mandag" "tirsdag" "onsdag" "torsdag" "fredag" "lørdag")
  "Weekday names by cron's number, 0 Sunday.")

(defun norwegian-list (words)
  "WORDS joined as Norwegian lists them: «a, b og c»."
  (format nil "~{~a~#[~; og ~:;, ~]~}" words))

(defun cron-days-text (cron)
  "Which days CRON runs, in words, or NIL when that takes more than a phrase."
  (let ((weekdays (cron-weekdays cron)))
    (cond ((cron-days-restricted-p cron)
           (and (not (cron-weekdays-restricted-p cron)) (= 1 (length (cron-days cron)))
                (format nil "den ~d. hver måned" (first (cron-days cron)))))
          ((not (cron-weekdays-restricted-p cron)) "hver dag")
          ((equal weekdays '(1 2 3 4 5)) "hverdager")
          ((equal weekdays '(0 6)) "i helgene")
          ((= 1 (length weekdays)) (format nil "hver ~a" (nth (first weekdays) +weekday-names+)))
          ;; Monday first, as a Norwegian week runs.
          (t (norwegian-list (mapcar (lambda (day) (nth day +weekday-names+))
                                     (append (remove 0 weekdays) (and (member 0 weekdays) '(0)))))))))

(defun even-step (values limit)
  "The step S when VALUES are 0, S, 2S ... below LIMIT, or NIL."
  (let ((step (and (rest values) (- (second values) (first values)))))
    (and step (zerop (first values)) (zerop (mod limit step))
         (equal values (loop for value from 0 below limit by step collect value))
         step)))

(defun describe-cron (cron)
  "When CRON runs, in Norwegian, such as «hverdager kl. 07:00»; its cron text
when it takes more than a phrase."
  (let ((minutes (cron-minutes cron))
        (hours (cron-hours cron))
        (days (cron-days-text cron)))
    (flet ((at (hour minute) (format nil "~2,'0d:~2,'0d" hour minute)))
      (or (and days (= 12 (length (cron-months cron)))
               (cond ((and (= 24 (length hours)) (string= days "hver dag"))
                      (cond ((equal minutes '(0)) "hver hele time")
                            ((= 1 (length minutes))
                             (format nil "hver time, ~d minutter over" (first minutes)))
                            ((even-step minutes 60)
                             (format nil "hvert ~d. minutt" (even-step minutes 60)))))
                     ((= 1 (length minutes))
                      (format nil "~a kl. ~a" days
                              (norwegian-list (mapcar (lambda (hour) (at hour (first minutes)))
                                                      hours))))))
          (cron-text cron)))))
