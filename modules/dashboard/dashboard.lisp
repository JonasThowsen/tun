;;;; modules/dashboard/dashboard.lisp -- the developer's dashboard: pages for
;;;; an application's admins and developers on what it does in the background
;;;; and what goes wrong.  jobs.lisp is «Jobber» (spec/jobs.md), errors.lisp
;;;; «Feil» and log.lisp «Logg» (spec/errors.md).  Every figure comes from a
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
  (:core ">= 1.4.0" "< 2.0")
  (:documentation "The developer's dashboard: «Jobber» with jobs by state, each job's attempts, queues, processes and schedules; «Feil» with the errors grouped by cause; «Logg» with the requests the process has in memory."))

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
  "INSTANT, an RFC 3339 text or JSON null, in Norwegian time; a dash for none."
  (if (stringp instant) (tun.web:timestamp-text instant) "—"))

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
  "Milliseconds as Norwegian writes them: 12,5 ms; a dash for none."
  (if (realp ms)
      (format nil "~a ms" (substitute #\, #\. (format nil "~,1f" ms)))
      "—"))
