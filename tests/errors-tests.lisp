;;;; tests/errors-tests.lisp -- errors and logs (spec/errors.md): faults
;;;; recorded and grouped by cause, refusals left out, statuses, the mail
;;;; about a new error, the occurrences kept, erasure, the log line, and the
;;;; requests in memory narrowed by kind and tool.

(in-package #:tun.tests)

(def-suite errors :in core)
(in-suite errors)

;;; ------------------------------------------------------------------
;;; Operations that fail

(defun crash (text)
  (error "Krasj med ~a" text))

(defun crash-elsewhere (text)
  (error "Krasj med ~a" text))

(define-operation errors-test-crash ((text :type string :required t)
                                     (elsewhere :type boolean))
    (:kind :read :policy :employee :title "Crash (test)")
  (if elsewhere (crash-elsewhere text) (crash text)))

(define-operation errors-test-refuse ()
    (:kind :read :policy :employee :title "Refuse (test)")
  (fail :not-found "Fant ingenting"))

(defun crash-call (tool actor &rest arguments)
  "Call TOOL, which may signal the condition no one handles; values its JSON
and error code, internal_error for such a condition."
  (handler-case (apply #'call tool actor arguments)
    (error () (values nil "internal_error"))))

(define-application error-mail-application ()
  (:error-mail "utvikler@example.no"))

(defun errors-of (&optional (status "open"))
  (call-ok-items "errors_list" "status" status))

(defun only-error ()
  (let ((errors (errors-of)))
    (is (= 1 (length errors)))
    (first errors)))

(defun mail-subjects ()
  (mapcar (lambda (mail) (jget mail "subject")) (call-ok-items "mail_list")))

;;; ------------------------------------------------------------------
;;; Recording and grouping

(test a-fault-is-recorded-and-grouped-by-its-cause
  (with-test-app ()
    (is (equal "internal_error"
               (nth-value 1 (crash-call "errors_test_crash" "employee:kari" "text" "ordre 1"))))
    (crash-call "errors_test_crash" "employee:kari" "text" "ordre 2")
    (let ((error (only-error)))
      (is (= 2 (jget error "count")) "two messages, one cause")
      (is (equal "internal_error" (jget error "code")))
      (is (equal "simple-error" (jget error "error_type")))
      (is (equal "Krasj med ordre 2" (jget error "message")) "the latest message")
      (is (equal "errors_test_crash" (jget error "tool")))
      (is (null (jget error "backtrace")) "the list leaves the backtrace out")
      (let ((full (call-ok "errors_get" "admin:root" "id" (jget error "id"))))
        (is (find "tun.tests::crash" (coerce (jget full "backtrace") 'list) :test #'search))
        (let ((occurrences (coerce (jget full "occurrences") 'list)))
          (is (equal '("Krasj med ordre 2" "Krasj med ordre 1")
                     (mapcar (lambda (o) (jget o "message")) occurrences)))
          (is (equal "employee:kari" (jget (first occurrences) "actor")))
          (is (stringp (jget (first occurrences) "request_id"))))))
    (crash-call "errors_test_crash" "employee:kari" "text" "ordre 3" "elsewhere" t)
    (is (= 2 (length (errors-of))) "the same message from another place is another error")))

(test what-the-code-meant-is-not-a-fault
  (with-test-app ()
    (is (equal "not_found" (nth-value 1 (call "errors_test_refuse" "employee:kari"))))
    (is (equal "invalid_input" (nth-value 1 (crash-call "errors_test_crash" "employee:kari"))))
    (is (equal "forbidden" (nth-value 1 (call "errors_list" "employee:kari"))))
    (is (null (errors-of)))))

(test a-failed-job-attempt-and-a-deadline-are-faults
  (setf *job-calls* '())
  (with-test-app ()
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (with-transaction (:write)
          (tun.jobs:enqueue-job 'failing-job :text "jobb")
          (tun.jobs:enqueue-job 'slow-job)))
      (tun.jobs:run-due-jobs))
    (let ((errors (errors-of)))
      (is (equal '("deadline_exceeded" "job_failed")
                 (sort (mapcar (lambda (e) (jget e "code")) errors) #'string<)))
      (is (find "job:failing_job" errors :key (lambda (e) (jget e "tool")) :test #'equal))
      (is (find "Det gikk galt med jobb" errors :key (lambda (e) (jget e "message")) :test #'equal)))))

(test a-failing-web-request-records-its-condition
  (with-test-app ()
    (ignore-errors
     (with-request-record (:kind :web :tool "web:GET /krasj" :application *app*
                           :at (with-application (*app*) (now)))
       (error "Siden krasjet")))
    (let ((error (only-error)))
      (is (equal "Siden krasjet" (jget error "message")) "not «Forespørselen ble avbrutt»")
      (is (equal "web:GET /krasj" (jget error "tool"))))))

;;; ------------------------------------------------------------------
;;; Statuses

(test a-resolved-error-opens-again-and-an-ignored-one-keeps-counting
  (with-test-app ()
    (crash-call "errors_test_crash" "employee:kari" "text" "a")
    (crash-call "errors_test_crash" "employee:kari" "text" "b" "elsewhere" t)
    (destructuring-bind (first second) (errors-of)
      (call-ok "errors_set_status" "admin:root" "id" (jget first "id") "status" "resolved")
      (call-ok "errors_set_status" "admin:root" "id" (jget second "id") "status" "ignored")
      (is (null (errors-of)))
      (let ((counts (jget (call-ok "errors_list" "admin:root") "counts")))
        (is (= 1 (jget counts "resolved")))
        (is (= 1 (jget counts "ignored"))))
      (crash-call "errors_test_crash" "employee:kari" "text" "a igjen")
      (crash-call "errors_test_crash" "employee:kari" "text" "b igjen" "elsewhere" t)
      (let ((open (only-error)))
        (is (equal (jget first "id") (jget open "id")) "the resolved error is open again")
        (is (equal "system:errors" (jget open "status_changed_by"))))
      (is (= 2 (jget (first (errors-of "ignored")) "count")) "the ignored one counted, quietly"))))

(test an-error-keeps-its-latest-occurrences
  (with-test-app ()
    (dotimes (i 52)
      (crash-call "errors_test_crash" "employee:kari" "text" (format nil "~d" i)))
    (let* ((error (only-error))
           (full (call-ok "errors_get" "admin:root" "id" (jget error "id"))))
      (is (= 52 (jget error "count")))
      (is (= 50 (length (jget full "occurrences"))))
      (is (equal "Krasj med 51" (jget (aref (jget full "occurrences") 0) "message"))))))

(test errors-are-recorded-on-postgres
  (if (not (postgres-available-p))
      (skip "no Postgres")
      (with-test-app (:db (scratch-postgres "errors"))
        (dotimes (i 53)
          (crash-call "errors_test_crash" "employee:kari" "text" (format nil "~d" i)))
        (let* ((error (only-error))
               (full (call-ok "errors_get" "admin:root" "id" (jget error "id"))))
          (is (= 53 (jget error "count")))
          (is (= 50 (length (jget full "occurrences"))) "the oldest go")
          (is (plusp (length (jget full "backtrace"))))))))

;;; ------------------------------------------------------------------
;;; Mail

(test a-new-error-is-mailed-once-an-hour-at-most
  (with-test-app (:class 'error-mail-application)
    (is (null (mail-subjects)))
    (crash-call "errors_test_crash" "employee:kari" "text" "første")
    (crash-call "errors_test_crash" "employee:kari" "text" "andre")
    (is (equal '("New error in tun: Krasj med første") (mail-subjects)) "one mail for a new error")
    (let ((mail (first (call-ok-items "mail_list"))))
      (is (equal "utvikler@example.no" (jget mail "to"))))
    (let ((id (jget (only-error) "id")))
      (call-ok "errors_set_status" "admin:root" "id" id "status" "resolved")
      (crash-call "errors_test_crash" "employee:kari" "text" "tredje")
      (is (= 1 (length (mail-subjects))) "open again within the hour: no second mail")
      (call-ok "errors_set_status" "admin:root" "id" id "status" "resolved")
      (set-clock-ahead 7200)
      (crash-call "errors_test_crash" "employee:kari" "text" "fjerde")
      (is (equal "The error is back in tun: Krasj med fjerde" (first (mail-subjects)))))))

(test the-error-mail-is-in-the-tenants-language
  ;; spec/i18n.md 8: the error mail is written in the tenant's language; the
  ;; error's own message stays as it was recorded.
  (with-test-app (:class 'error-mail-application)
    (call-ok "settings_set" "admin:root" "key" "locale.language" "value" "nb")
    (crash-call "errors_test_crash" "employee:kari" "text" "norsk")
    (is (equal '("Ny feil i tun: Krasj med norsk") (mail-subjects)))
    (let ((text (jget (call-ok "mail_get" "admin:root" "id" (jget (first (call-ok-items "mail_list")) "id"))
                      "text")))
      (dolist (part '("Hvor: errors_test_crash" "Antall ganger: 1" "Først sett: "
                      "Agenter finner den med errors_get"))
        (is (search part text) "~a" part))
      (is (cl-ppcre:scan "Først sett: \\d\\d\\.\\d\\d\\.\\d{4} kl\\. \\d\\d:\\d\\d" text)
          "the time as Norwegian writes it"))))

(test without-error-mail-nothing-is-sent
  (with-test-app ()
    (crash-call "errors_test_crash" "employee:kari" "text" "stille")
    (is (= 1 (length (errors-of))))
    (is (null (mail-subjects)))))

;;; ------------------------------------------------------------------
;;; Erasure, the log line, the requests in memory

(test erasure-reaches-the-recorded-errors
  (with-test-app ()
    (crash-call "errors_test_crash" "employee:kari" "text" "Ola Nordmann")
    (crash-call "errors_test_crash" "employee:kari" "text" "Kari" "elsewhere" t)
    (with-application (*app*)
      (with-transaction (:write)
        (redact-request-traces (list "ola nordmann"))))
    (let ((messages (mapcar (lambda (e) (jget e "message")) (errors-of))))
      (is (member "[deleted]" messages :test #'equal))
      (is (member "Krasj med Kari" messages :test #'equal)))
    (let* ((erased (find "[deleted]" (errors-of) :key (lambda (e) (jget e "message")) :test #'equal))
           (occurrence (aref (jget (call-ok "errors_get" "admin:root" "id" (jget erased "id"))
                                   "occurrences")
                             0)))
      (is (equal "[deleted]" (jget occurrence "message"))))))

(test a-request-has-a-log-line
  (with-test-app ()
    (crash-call "errors_test_crash" "employee:kari" "text" "logg")
    (call-ok "errors_list" "admin:root")
    (destructuring-bind (listed crashed &rest older) (finished-requests)
      (declare (ignore older))
      (let ((line (tun.errors:log-line crashed (with-application (*app*)
                                                 (with-transaction (:read)
                                                   (select-one 'tun.errors:error-group))))))
        (is (equal "error" (jget line "level")))
        (is (equal "internal_error" (jget line "code")))
        (is (equal "Krasj med logg" (jget line "message")))
        (is (equal "employee:kari" (jget line "actor")))
        (is (stringp (jget line "error_id"))))
      (let ((line (tun.errors:log-line listed nil)))
        (is (equal "info" (jget line "level")))
        (is (equal "errors_list" (jget line "tool")))
        (is (null (nth-value 1 (jget line "message"))) "no message for a request that succeeded")))
    (call "errors_test_refuse" "employee:kari")
    (let ((line (tun.errors:log-line (first (finished-requests)) nil)))
      (is (equal "warn" (jget line "level")))
      (is (null (nth-value 1 (jget line "message"))) "a refusal's message is not logged"))))

(test the-requests-in-memory-narrow-by-kind-and-tool
  (with-test-app ()
    (crash-call "errors_test_crash" "employee:kari" "text" "minne")
    (with-application (*app*)
      (with-actor ((system-actor "test"))
        (with-transaction (:write)
          (tun.jobs:enqueue-job 'mark-job :text "minne")))
      (tun.jobs:run-due-jobs))
    (let ((jobs (call-ok-items "introspect_recent" "request_kind" "job")))
      (is (plusp (length jobs)))
      (is (every (lambda (r) (equal "job" (jget r "kind"))) jobs)))
    ;; The requests in memory are the whole process's, earlier tests' too.
    (let ((crashes (call-ok-items "introspect_recent" "tool" "errors_test")))
      (is (every (lambda (r) (search "errors_test" (jget r "tool"))) crashes))
      (is (equal "Krasj med minne" (jget (first crashes) "message")))
      (is (equal "operation" (jget (first crashes) "kind"))))))

;;; ------------------------------------------------------------------
;;; The dashboard's "Errors" and "Log"

(test the-dashboard-shows-errors-and-requests
  (with-test-server (port)
    (let ((admin (web-login port "admin:root"))
          (kari (web-login port "employee:kari")))
      (crash-call "errors_test_crash" "employee:kari" "text" "på siden")
      (let ((id (jget (only-error) "id")))
        (flet ((html (path) (nth-value 1 (web-request port path :jar admin)))
               (post (path) (web-request port path :method :post :jar admin)))
          (is (= 403 (web-request port "/errors" :jar kari)) "for admins only")
          (is (= 403 (web-request port "/log" :jar kari)))
          (let ((list (html "/errors")))
            (dolist (part '("Open (1)" "Krasj med på siden" "simple-error" "errors_test_crash"))
              (is (search part list) "the list shows ~a" part)))
          (let ((detail (html (format nil "/errors/~a" id))))
            (dolist (part '("Backtrace" "tun.tests::crash" "Occurrences" "employee:kari"
                            "Mark as resolved"))
              (is (search part detail) "the error's page shows ~a" part)))
          (is (= 303 (post (format nil "/errors/~a/status/resolved" id))))
          (is (equal "resolved" (jget (call-ok "errors_get" "admin:root" "id" id) "status")))
          (is (search "Open again" (html (format nil "/errors/~a" id))))
          (multiple-value-bind (status body) (post (format nil "/errors/~a/status/gone" id))
            (is (= 422 status) "a status that does not exist is refused on the page")
            (is (search "data-code=\"invalid_input\"" body)))
          (is (search "errors_test_crash" (html "/log?selection=errors")))
          (let* ((request (jget (first (call-ok-items "introspect_recent" "tool" "errors_test_crash"))
                                "request_id"))
                 (page (html (format nil "/log/~a" request))))
            (dolist (part '("Input" "på siden" "Steps" "policy" "Backtrace"))
              (is (search part page) "the request's page shows ~a" part)))
          (is (search "in memory only" (nth-value 1 (web-request port "/log/req_gone" :jar admin)))
              "a request the process no longer has says so"))))))
