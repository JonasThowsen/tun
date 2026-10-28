;;;; modules/dashboard/dashboard.lisp -- the developer's dashboard: pages for
;;;; an application's admins and developers on what it does in the background
;;;; and what goes wrong.  jobs.lisp is "Jobs" (spec/jobs.md), errors.lisp
;;;; "Errors" and log.lisp "Log" (spec/errors.md).  Every figure comes from a
;;;; core tool, called as the admin logged in, and every button calls one, so
;;;; the pages show and do exactly what an agent can over MCP.  This file has
;;;; what the pages share.

(defpackage #:tun.dashboard
  (:use #:cl #:tun.core)
  (:local-nicknames (#:ui #:tun.ui))
  (:export #:jobs-page #:errors-page #:log-page))

(in-package #:tun.dashboard)

(declaim (optimize (safety 3) (debug 2)))

(define-module dashboard
  (:core ">= 2.0.0" "< 3.0")
  (:documentation "The developer's dashboard: Jobs with jobs by state, each job's attempts,
queues, processes and schedules; Errors with the errors grouped by cause; Log with the requests
the process has in memory."))

;;; ------------------------------------------------------------------
;;; Calling the tools

(defun read-result (tool &rest arguments)
  "TOOL's result for ARGUMENTS, alternating keys and values, as the admin
logged in; a refusal is the page's."
  (multiple-value-bind (json code) (tun.web:web-call tool (apply #'jobj arguments))
    (when code
      (fail code "~a" (jget (jget json "error") "message")))
    json))

(defun items-of (json &optional (key "items"))
  "The array under KEY of JSON, as a list."
  (coerce (jget json key #()) 'list))

(defun change (tool arguments next on-error)
  "Call TOOL with ARGUMENTS and send the browser to NEXT; when it is refused,
draw ON-ERROR's page for the error, with the refusal's status."
  (multiple-value-bind (json code) (tun.web:web-call tool arguments)
    (if code
        (multiple-value-bind (status title body header) (funcall on-error json)
          (declare (ignore status))
          (values (error-status code) title body header))
        (values 303 next))))

;;; ------------------------------------------------------------------
;;; Pieces

(defun when-text (instant)
  "INSTANT, an RFC 3339 text or JSON null, in the tenant's time zone; a dash
for none."
  (if (stringp instant) (timestamp-text instant) "—"))

(defun shortened (text length)
  (if (> (length text) length)
      (concatenate 'string (subseq text 0 length) "…")
      text))

(defun subseq-at-most (list count)
  (subseq list 0 (min count (length list))))

(defun post-button (action label &key (variant :outline))
  "A one-button form posting to ACTION."
  `(:form (:@ :method "post" :action ,action)
          ,(ui:button (:type "submit" :size :sm :variant variant) label)))

(defun tab-buttons (current entries &key (variant :ghost))
  "Links between the parts of a page: ENTRIES are (KEY LABEL HREF), and the
one whose KEY is CURRENT is marked."
  (apply #'ui:cluster* '()
         (loop for (key label href) in entries
               collect (ui:button (:href href :size :sm
                                   :variant (if (equal key current) :primary variant))
                         label))))

(defun ms-text (ms)
  "Milliseconds to a tenth, as the current language writes them: 12.5 ms, or
12,5 ms; a dash for none."
  (if (realp ms)
      (tr "~a ms" (number-text (/ (round (* ms 10)) 10)))
      "—"))


;;; ------------------------------------------------------------------
;;; The paths of core 1.x

;;; The pages were /jobber, /feil and /logg before core 2.0, and a tenant
;;; from 1.x has them bookmarked: each old path answers 301 to its new one
;;; (spec/i18n.md 4.8), with its parts and query keys renamed.

(defparameter +old-path-parts+
  '(("jobber" . "jobs") ("feil" . "errors") ("logg" . "log")
    ("liste" . "list") ("tidsplaner" . "schedules") ("kjor" . "run")
    ("kjor-igjen" . "retry") ("avbryt" . "cancel"))
  "Old path parts and their new names; any other part, such as an id, stays.")

(defparameter +old-query-keys+
  '(("tilstand" . "state") ("utvalg" . "selection") ("slag" . "kind") ("status" . "status"))
  "Old query keys and their new names; any other key is dropped.")

(defun new-path-part (part)
  (or (cdr (assoc part +old-path-parts+ :test #'equal)) part))

(defun moved-path (prefix parts query)
  "The new address of the old page at /PREFIX/PARTS?QUERY.  Only values made
of letters, digits and _ are kept, so none needs escaping."
  (let ((pairs (loop for (old . new) in +old-query-keys+
                     for value = (jget query old)
                     when (and (stringp value) (plusp (length value))
                               (every (lambda (c) (or (alphanumericp c) (char= c #\_))) value))
                       collect (format nil "~a=~a" new value))))
    (format nil "/~{~a~^/~}~@[?~{~a~^&~}~]"
            (mapcar #'new-path-part (cons prefix parts)) pairs)))

(defmacro define-moved-page (name prefix)
  "NAME, the page at the old /PREFIX, answering 301 to the new address."
  `(tun.web:define-page ,name (,prefix :policy :admin :navigation nil :group :system)
       (method path form query)
     (values 301 (moved-path ,prefix path query))))

(define-moved-page old-jobs-page "jobber")
(define-moved-page old-errors-page "feil")
(define-moved-page old-log-page "logg")
