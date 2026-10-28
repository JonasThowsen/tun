;;;; core/zones.lisp -- the tenant's time zone, without a time-zone database
;;;; (spec/i18n.md 6.1, core.md 2.2).
;;;;
;;;; A zone is an offset from UTC and whether it keeps European summer time:
;;;; one hour ahead from the last Sunday of March 01:00 UTC to the last Sunday
;;;; of October 01:00 UTC (exclusive).  Instants are universal times; local
;;;; dates and times are the tenant's.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +time-zones+
  (let ((zones '()))
    (flet ((add (offset summer &rest names)
             (dolist (name names) (push (list name offset summer) zones))))
      (add 0 nil "UTC" "Atlantic/Reykjavik")
      (add 0 t "Europe/London" "Europe/Dublin" "Europe/Lisbon" "Atlantic/Faroe")
      (add 3600 t "Europe/Oslo" "Europe/Stockholm" "Europe/Copenhagen" "Europe/Berlin"
           "Europe/Amsterdam" "Europe/Brussels" "Europe/Luxembourg" "Europe/Paris"
           "Europe/Madrid" "Europe/Rome" "Europe/Vienna" "Europe/Zurich" "Europe/Warsaw"
           "Europe/Prague" "Europe/Budapest")
      (add 7200 t "Europe/Helsinki" "Europe/Tallinn" "Europe/Riga" "Europe/Vilnius"
           "Europe/Athens" "Europe/Sofia" "Europe/Bucharest"))
    (nreverse zones))
  "The zones Tun knows: (NAME STANDARD-OFFSET-SECONDS SUMMER-TIME-P).")

(defun time-zone-p (name)
  "True when NAME is a zone of +TIME-ZONES+."
  (and (stringp name) (assoc name +time-zones+ :test #'string=) t))

(defun zone-spec (zone)
  (or (assoc zone +time-zones+ :test #'string=)
      (error "~s is not a time zone Tun knows (spec/i18n.md 6.1)" zone)))

(defun european-summer-time-p (ut)
  "True when the instant UT falls in European summer time."
  (let ((year (nth-value 5 (decode-universal-time ut 0))))
    (and (<= (+ (last-sunday year 3) 3600) ut)
         (< ut (+ (last-sunday year 10) 3600)))))

(defun current-time-zone ()
  "The tenant's time zone, the request's when one is being answered."
  (locale-time-zone (current-locale)))

(defun zone-offset (ut &optional (zone (current-time-zone)))
  "Seconds ZONE's local time is ahead of UTC at the instant UT."
  (destructuring-bind (name standard summer) (zone-spec zone)
    (declare (ignore name))
    (if (and summer (european-summer-time-p ut)) (+ standard 3600) standard)))

(defun local-date-of (ut &optional (zone (current-time-zone)))
  "The local calendar date of the instant UT in ZONE, the tenant's by default."
  (format-date (+ ut (zone-offset ut zone))))

(defun local-time-of (ut &optional (zone (current-time-zone)))
  "The local wall-clock time HH:MM of the instant UT in ZONE."
  (multiple-value-bind (s m h) (decode-universal-time (+ ut (zone-offset ut zone)) 0)
    (declare (ignore s))
    (format nil "~2,'0d:~2,'0d" h m)))

(defun local-instant (date hour minute &optional (zone (current-time-zone)))
  "The instant local DATE at HOUR:MINUTE in ZONE stands for (core.md 2.2,
to_utc): values the instant and :OK when exactly one reading is real; NIL and
:AMBIGUOUS when both are (the autumn overlap), as a second and third value
the earlier and later instants; NIL and :NONEXISTENT when neither is (the
spring gap)."
  (destructuring-bind (name standard summer) (zone-spec zone)
    (declare (ignore name))
    (let* ((wall (+ (parse-date date) (* 3600 hour) (* 60 minute)))
           (as-standard (- wall standard))
           (standard-p (= standard (zone-offset as-standard zone))))
      (if (not summer)
          (values as-standard :ok)
          (let* ((as-summer (- wall standard 3600))
                 (summer-p (= (+ standard 3600) (zone-offset as-summer zone))))
            (cond ((and standard-p summer-p) (values nil :ambiguous as-summer as-standard))
                  (standard-p (values as-standard :ok))
                  (summer-p (values as-summer :ok))
                  (t (values nil :nonexistent))))))))
