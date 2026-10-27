;;;; platform/errors.lisp -- errors and logs (spec/errors.md).
;;;;
;;;; When a request ends, the kernel calls REQUEST-FINISHED.  A request that
;;;; ended in a fault, an error the code did not mean, is recorded in the
;;;; store as one more occurrence of its error: the faults with one cause,
;;;; known by a fingerprint of the condition's type and where it was
;;;; signalled.  A new error, or a resolved one that occurs again, is mailed
;;;; to the addresses in the application's (:error-mail ...).  A server also
;;;; writes one JSON line per request to standard output.  The requests
;;;; themselves stay in memory (core/trace.lisp): only faults are stored, so
;;;; a read never becomes a write.

(defpackage #:tun.errors
  (:use #:cl #:tun.core)
  (:export #:error-group #:error-group-fingerprint #:error-group-code #:error-group-error-type
           #:error-group-message #:error-group-tool #:error-group-count
           #:error-group-status #:error-group-notified-at
           #:error-occurrence #:error-occurrence-group-id #:error-occurrence-message
           #:error-occurrence-actor
           #:fault-p #:fault-fingerprint #:record-fault #:error-mail-recipients #:check-error-mail
           #:log-line
           #:errors-list #:errors-get #:errors-set-status))

(in-package #:tun.errors)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Faults and their fingerprints (spec/errors.md 2, 3)

(defparameter +fault-codes+ '(:internal-error :job-failed :deadline-exceeded)
  "The error codes of a request that failed in a way its code did not mean.")

(defparameter +fingerprint-frames+ 8
  "How many frames of the backtrace, from where the condition was signalled, say where it was.")

(defun fault-p (record)
  "True when the request RECORD ended in a fault."
  (and (equal (request-outcome record) "error")
       (member (request-error-code record) +fault-codes+)
       t))

(defun code-text (record)
  (json-name-of (request-error-code record)))

(defun fault-fingerprint (record)
  "What the faults with one cause have in common: the code, and the
condition's type and where it was signalled, or for a deadline, which shows
only where the clock ran out, the tool."
  (let ((backtrace (request-backtrace record)))
    (sha256-hex
     (to-json-string
      (jarr (list* (code-text record)
                   (if (or (eq (request-error-code record) :deadline-exceeded) (null backtrace))
                       (list (or (request-tool record) ""))
                       (cons (or (request-error-type record) "")
                             (subseq backtrace 0 (min +fingerprint-frames+ (length backtrace)))))))))))

;;; ------------------------------------------------------------------
;;; What is kept (spec/errors.md 4)

(define-entity error-group (:label "Feil" :id-prefix "err" :table "error_groups" :internal t
                                   :unique (("fingerprint")) :indexes (("status" "last_seen_at")))
  ((fingerprint :type (string :max 64) :required t :input nil :label "Fingeravtrykk")
   (code :type (string :max 64) :required t :input nil :label "Kode")
   (error-type :type (string :max 200) :input nil :label "Type"
               :description "The condition's type, such as tun.mail::mail-not-delivered.")
   (message :type (string :max 2000) :input nil :label "Melding"
            :description "The latest occurrence's message.")
   (tool :type (string :max 200) :input nil :label "Verktøy"
         :description "Where the latest occurrence happened: a tool, web:GET /path or job:kind.")
   (backtrace :type json :input nil :label "Backtrace"
              :description "The latest occurrence's frames, innermost first.")
   (request-id :type (string :max 100) :input nil :label "Siste forespørsel")
   (first-seen-at :type timestamp :input nil :label "Først sett")
   (last-seen-at :type timestamp :input nil :label "Sist sett")
   (count :type integer :input nil :initform 0 :label "Antall"
          :description "How many times it has happened.")
   (status :type (enum "open" "resolved" "ignored") :input nil :initform "open" :label "Status")
   (status-changed-at :type timestamp :input nil :label "Status endret")
   (status-changed-by :type (string :max 200) :input nil :label "Status endret av")
   (notified-at :type timestamp :input nil :label "Varslet"
                :description "When the last mail about the error went.")))

(define-entity error-occurrence (:label "Forekomst" :id-prefix "eoc" :table "error_occurrences"
                                        :internal t :indexes (("group_id")))
  ((group-id :type (id error-group) :required t :input nil :label "Feil")
   (at :type timestamp :input nil :label "Tidspunkt")
   (request-id :type (string :max 100) :input nil :label "Forespørsel")
   (kind :type (string :max 20) :input nil :label "Slags")
   (tool :type (string :max 200) :input nil :label "Verktøy")
   (actor :type (string :max 200) :input nil :label "Aktør")
   (message :type (string :max 2000) :input nil :label "Melding")
   (total-ms :type json :input nil :label "Tid (ms)")))

(defparameter +kept-occurrences+ 50 "The occurrences kept of each error, latest first.")
(defparameter +kept-closed-days+ 90
  "How long a resolved or ignored error is kept after it was last seen.")
(defparameter +mail-interval+ 3600 "At most one mail about an error in this many seconds.")

(defun clipped (text &optional (length 2000))
  (and text (if (> (length text) length) (subseq text 0 length) text)))

(defun keep-latest-occurrences (group)
  (dolist (old (select 'error-occurrence :where `(:= "group_id" ,(entity-id group))
                                         :order-by '(("seq" :desc)) :offset +kept-occurrences+))
    (delete-entity old)))

(defun prune-closed-errors ()
  "Delete the resolved and ignored errors not seen for +KEPT-CLOSED-DAYS+, with
their occurrences."
  (dolist (group (select 'error-group
                         :where `(:and (:in "status" ("resolved" "ignored"))
                                       (:< "last_seen_at" ,(- (now) (* +kept-closed-days+ 86400))))
                         :limit 100))
    (mapc #'delete-entity (select 'error-occurrence :where `(:= "group_id" ,(entity-id group))))
    (delete-entity group)))

(defun record-fault (record)
  "In a write transaction: record the fault RECORD as an occurrence of its
error, opening the error when it is new or was resolved, and mail about it
when it opened.  Returns the error."
  (let* ((at (or (request-at record) (now)))
         (fingerprint (fault-fingerprint record))
         (existing (select-one 'error-group :where `(:= "fingerprint" ,fingerprint)))
         (group (or existing
                    (make-instance 'error-group :fingerprint fingerprint :code (code-text record)
                                                :first-seen-at at)))
         (opened (or (null existing) (string= (error-group-status existing) "resolved"))))
    (setf (error-group-error-type group) (request-error-type record)
          (error-group-message group) (clipped (request-error-message record))
          (error-group-tool group) (clipped (request-tool record) 200)
          (error-group-backtrace group) (jarr (request-backtrace record))
          (error-group-request-id group) (request-id record)
          (error-group-last-seen-at group) at)
    (incf (error-group-count group))
    (when (and existing opened)
      (setf (error-group-status group) "open"
            (error-group-status-changed-at group) at
            (error-group-status-changed-by group) "system:errors"))
    (if existing (save group) (insert group))
    (insert (make-instance 'error-occurrence
                           :group-id (entity-id group) :at at :request-id (request-id record)
                           :kind (string-downcase (symbol-name (request-kind record)))
                           :tool (clipped (request-tool record) 200)
                           :actor (request-actor record)
                           :message (clipped (request-error-message record))
                           :total-ms (or (us->ms (request-total-us record)) :null)))
    (keep-latest-occurrences group)
    (when opened
      (mail-error group (null existing)))
    (prune-closed-errors)
    group))

;;; ------------------------------------------------------------------
;;; Mail (spec/errors.md 5)

(defun error-mail-recipients (&optional (application *application*))
  "The addresses that hear of APPLICATION's new errors; APPLICATION is an
application or the name of its class.  Values them and what is missing, for
each address given as an environment variable that is not set."
  (let ((addresses '()) (problems '()))
    (dolist (spec (application-error-mail-specs application))
      (multiple-value-bind (address problem) (configured-value spec)
        (if address (push address addresses) (push problem problems))))
    (values (nreverse addresses) (nreverse problems))))

(defun check-error-mail (application-class name)
  "Say on stderr, at start, which error mail addresses are missing."
  (multiple-value-bind (addresses problems) (error-mail-recipients application-class)
    (declare (ignore addresses))
    (dolist (problem problems)
      (format *error-output* "~&~a: error mail: ~a is not set; no mail goes to it~%" name problem))))

(defun time-text (ut)
  (format nil "~a kl. ~a" (let ((date (local-date-of ut)))
                            (format nil "~a.~a.~a" (subseq date 8 10) (subseq date 5 7) (subseq date 0 4)))
          (local-time-of ut)))

(defun error-page-link (group)
  "The link to GROUP's page, when people can follow one: the application has
a public URL and enables the dashboard."
  (and (application-public-url *application*)
       (find "dashboard" (enabled-modules *application*)
             :key (lambda (entry) (module-name (first entry))) :test #'string=)
       (absolute-url (format nil "/feil/~a" (entity-id group)))))

(defun error-mail-text (group)
  (format nil "~a~%~%Hvor: ~a~%Type: ~a (~a)~%Først sett: ~a~%Antall ganger: ~d~%Forespørsel: ~a~%~
               ~:[~*~;~%Se feilen: ~a~%~]~%Agenter finner den med errors_get ~a."
          (or (error-group-message group) "")
          (or (error-group-tool group) "—")
          (or (error-group-error-type group) "—") (error-group-code group)
          (time-text (error-group-first-seen-at group))
          (error-group-count group)
          (or (error-group-request-id group) "—")
          (error-page-link group) (error-page-link group)
          (entity-id group)))

(defun mail-error (group new)
  "Mail GROUP, NEW or open again, to the application's error mail
addresses, at most once in +MAIL-INTERVAL+."
  (let ((addresses (error-mail-recipients))
        (last (error-group-notified-at group)))
    (when (and addresses (or (null last) (>= (- (now) last) +mail-interval+)))
      (dolist (address addresses)
        (tun.mail:send-mail :to address
                            :subject (format nil "~:[Feilen er tilbake~;Ny feil~] i ~a: ~a" new
                                             (application-title *application*)
                                             (clipped (or (error-group-message group)
                                                          (error-group-code group))
                                                      80))
                            :text (error-mail-text group)
                            :key (format nil "error:~a:~d:~a" (entity-id group) (now) address)))
      (setf (error-group-notified-at group) (now))
      (save group))))

;;; ------------------------------------------------------------------
;;; Erasure (spec/errors.md 4)

(defun redact-recorded-errors (needles)
  "Erase the messages and actors of recorded errors that mention NEEDLES,
subject ids or personal data, in the erasing write."
  (let ((needles (remove-if-not (lambda (value) (and (stringp value) (plusp (length value)))) needles)))
    (flet ((mentions-p (text)
             (and (stringp text)
                  (some (lambda (needle) (search needle text :test #'char-equal)) needles))))
      (when needles
        (dolist (group (select 'error-group))
          (when (mentions-p (error-group-message group))
            (setf (error-group-message group) "[slettet]")
            (save group)))
        (dolist (occurrence (select 'error-occurrence))
          (when (or (mentions-p (error-occurrence-message occurrence))
                    (mentions-p (error-occurrence-actor occurrence)))
            (setf (error-occurrence-message occurrence) "[slettet]"
                  (error-occurrence-actor occurrence) "[slettet]")
            (save occurrence)))))))

(pushnew 'redact-recorded-errors *stored-diagnostics-redactors*)

;;; ------------------------------------------------------------------
;;; Log lines (spec/errors.md 6)

(defun log-level (record)
  (cond ((fault-p record) "error")
        ((member (request-outcome record) '("error" "rejected") :test #'equal) "warn")
        (t "info")))

(defun log-line (record group)
  "The JSON object of RECORD's log line; GROUP is the error it was recorded
as, if any."
  (let ((line (jobj "at" (format-rfc3339 (or (request-at record) (now)))
                    "level" (log-level record)
                    "request_id" (request-id record)
                    "kind" (string-downcase (symbol-name (request-kind record)))
                    "tool" (or (request-tool record) :null)
                    "actor" (or (request-actor record) :null)
                    "outcome" (or (request-outcome record) :null)
                    "ms" (or (us->ms (request-total-us record)) :null)
                    "statements" (request-store-statements record))))
    (when (request-error-code record)
      (setf (gethash "code" line) (code-text record)))
    ;; Only a fault's message: a refusal's often repeats what someone typed.
    (when (fault-p record)
      (setf (gethash "message" line) (clipped (or (request-error-message record) "") 500)))
    (when group
      (setf (gethash "error_id" line) (entity-id group)))
    line))

(defvar *log-lock* (sb-thread:make-mutex :name "request log")
  "Keeps the lines of requests that end at once from mixing.")

(defun write-log-line (record group)
  (let ((text (to-json-string (log-line record group)))
        (out sb-sys:*stdout*))
    (sb-thread:with-mutex (*log-lock*)
      (write-line text out)
      (force-output out))))

;;; ------------------------------------------------------------------
;;; The kernel's hook

(defun record-fault-of (application record)
  "Record the fault RECORD of APPLICATION in a write of its own, or in the
write it ended in.  Returns the error."
  (with-application (application)
    (let ((*deadline* nil))
      (ecase *transaction-mode*
        ((nil) (with-transaction (:write) (record-fault record)))
        (:write (record-fault record))
        (:read (error "the request ended inside a read transaction"))))))

(defmethod request-finished ((application application) record)
  ;; A thread eval started may not write (core.md §8.3): what fails there is the
  ;; eval call's to report, not a fault to keep.
  (let ((group (when (and (fault-p record) (not *under-eval*))
                 (handler-case (record-fault-of application record)
                   (serious-condition (e)
                     (ignore-errors
                      (format *error-output* "~&;; tun errors: could not record the fault of ~a: ~a~%"
                              (request-id record) e))
                     nil)))))
    (when (application-log-requests-p application)
      (handler-case (write-log-line record group)
        (serious-condition (e)
          (ignore-errors (format *error-output* "~&;; tun errors: could not log ~a: ~a~%"
                                 (request-id record) e)))))))

;;; ------------------------------------------------------------------
;;; Tools (spec/errors.md 7)

(defun group-summary (group)
  (let ((json (entity->json group)))
    (remhash "backtrace" json)
    (remhash "fingerprint" json)
    json))

(define-operation errors-list ((status :type (enum "open" "resolved" "ignored") :default "open"
                                       :label "Status")
                               (limit :type (integer :min 1 :max 500) :default 100 :label "Maks antall"))
    (:entity error-group :kind :read :policy :admin :title "Feil"
             :description "Feilene i én status (open som standard), sist sett først: feil som koden
ikke mente, gruppert etter årsak (type og hvor den oppsto). Hver med kode, type, siste melding,
verktøy, antall ganger, først og sist sett. counts sier hvor mange det er i hver status.")
  (jobj "items" (jarr (mapcar #'group-summary
                              (select 'error-group :where `(:= "status" ,status)
                                                   :order-by '(("last_seen_at" :desc)) :limit limit)))
        "counts" (let ((counts (jobj)))
                   (dolist (each '("open" "resolved" "ignored") counts)
                     (setf (gethash each counts)
                           (length (select 'error-group :where `(:= "status" ,each))))))))

(define-operation errors-get ((id :type (id error-group) :required t :label "Feil"))
    (:entity error-group :kind :read :policy :admin :title "Les feil"
             :description "Én feil med backtrace fra siste gang og de siste 50 forekomstene, nyeste
først: når, forespørselen (introspect_request, så lenge prosessen har den i minnet), verktøy,
aktør, melding og tid.")
  (let ((json (entity->json (fetch! 'error-group id))))
    (setf (gethash "occurrences" json)
          (jarr (mapcar #'entity->json
                        (select 'error-occurrence :where `(:= "group_id" ,id)
                                                  :order-by '(("seq" :desc))))))
    json))

(define-operation errors-set-status ((id :type (id error-group) :required t :label "Feil")
                                     (status :type (enum "open" "resolved" "ignored") :required t
                                             :label "Status"))
    (:entity error-group :kind :update :policy :admin :title "Sett status på feil"
             :description "Merker en feil som løst (resolved), ignorert (ignored) eller åpen (open).
En løst feil som skjer igjen, blir åpen og varsles på nytt; en ignorert teller videre uten varsel.")
  (let ((group (fetch! 'error-group id)))
    (setf (error-group-status group) status
          (error-group-status-changed-at group) (now)
          (error-group-status-changed-by group) (actor-string *actor*))
    (save group)))
