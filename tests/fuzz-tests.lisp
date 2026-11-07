;;;; tests/fuzz-tests.lisp -- fuzzing every tool (spec/testing.md 2): Tun's
;;;; own tools, core's and the modules', fuzzed as a client's are; what that
;;;; found; and the fuzzer itself, on probe tools whose defects a test plants:
;;;; it finds a fault and a refusal that writes, shrinks what fails, replays
;;;; from its seed, and lets nothing leave the process.

(in-package #:tun.tests)

(def-suite fuzz :in core)
(in-suite fuzz)

;;; ------------------------------------------------------------------
;;; Tun's own tools

(define-scenario fuzz-records (:actors ("admin:jonas" "employee:anna"))
  "A record or two of each kind the modules keep, so a fuzzed tool's ids
name records that are there: customers, products, an article, an order
confirmed and one drafted, an invoice, an employee and an assignment, a
calendar event, an inquiry and an account."
  (call-ok "accounts_create" "admin:jonas" "name" "kari" "kind" "person" "role" "employee"
           "email" "kari@example.no")
  (let* ((customer (make-customer "Kari Nordmann"))
         (other (make-customer "Ola Nordmann"))
         (tent (make-product :name "Partytelt"))
         (chairs (make-product :name "Servietter" :kind "consumable" :price 5000))
         (accepted (jget (call-ok "orders_create" "employee:anna" "customer_id" customer
                                  "event_date" "2026-12-12" "lines" (lines tent 1 chairs 20))
                         "id"))
         (employee (jget (make-employee "Per") "id")))
    (make-article "Duk")
    (call-ok "orders_create" "employee:anna" "customer_id" other "lines" (lines chairs 4))
    (advance-to-accepted accepted)
    (two-step "orders_confirm" "employee:anna" "id" accepted)
    (call-ok "invoices_create_from_order" "employee:anna" "order_id" accepted)
    (call-ok "assignments_create" "admin:jonas" "order_id" accepted "employee_id" employee)
    (call-ok "calendar_events_create" "admin:jonas" "title" "Bryllup" "start_date" "2026-12-12"
             "order_id" accepted)
    (call-ok "inquiries_create" "viewer:web" "name" "Lise" "email" "lise@example.no"
             "message" "Har dere telt til 50?" "marketing_consent" t)))

(defun tun-operation-p (operation)
  "True for an operation of core or of a module: one in a kernel or module
package, not in this suite's, whose tests define operations of their own."
  (let ((package (symbol-package (operation-name operation))))
    (and (core-package-p package)
         (not (member package (list (find-package "TUN.TESTS")
                                    (find-package "TUN.TEST-SUPPORT")))))))

(defun check-tun-tools (modulep what)
  "Fuzz Tun's tools whose module MODULEP, a function of a module name or
\"core\", keeps, as a client's tools are fuzzed, from the scenario
fuzz-records."
  (check-every-tool-withstands-fuzzing
   (remove-if-not (lambda (operation)
                    (and (tun-operation-p operation)
                         (funcall modulep (operation-module operation))))
                  (all-operations))
   what :scenario (find-scenario "fuzz-records" :package "TUN.TESTS")))

;;; Core's tools and the modules' are fuzzed in suites of their own, which
;;; bin/test runs at once, each in a process of its own.

(def-suite fuzz-core :in core)
(in-suite fuzz-core)

(test every-core-tool-withstands-fuzzing
  (check-tun-tools (lambda (module) (string= module "core")) "Tun's core"))

(def-suite fuzz-modules :in core)
(in-suite fuzz-modules)

(test every-module-tool-withstands-fuzzing
  (check-tun-tools (lambda (module) (string/= module "core")) "Tun's modules"))

(in-suite fuzz)

;;; ------------------------------------------------------------------
;;; What fuzzing found

(test a-day-past-the-last-date-is-refused-not-a-fault
  ;; The day after 9999-12-31 has a fifth digit of year, which compares
  ;; before 9999 as text: a forecast to that date stepped on past it.
  (is (string= "9999-12-31" (date-add-days "9999-12-30" 1)))
  (signals operation-error (date-add-days "9999-12-31" 1))
  (signals operation-error (date-add-days "1900-01-01" -1))
  (signals operation-error (date-add-months "9999-12-31" 1))
  (is (string= "1900-01-28" (date-add-months "1900-02-28" -1)))
  (signals operation-error (date-add-months "1900-01-31" -1))
  (with-test-app ()
    (make-article "Duk")
    (is (equal "invalid_input" (nth-value 1 (call "inventory_forecast" "employee:anna"
                                                  "from" "9999-12-31" "to" "9999-12-31"))))
    (is (equal "invalid_input" (nth-value 1 (call "inventory_shortages" "employee:anna"
                                                  "before_date" "9999-12-31"))))))

(test text-holding-nul-is-refused-not-a-fault
  ;; Postgres cannot store NUL in text: an id holding it failed the query.
  (dolist (db (cons nil (and (postgres-available-p) (list (scratch-postgres "nul")))))
    (with-test-app (:db db)
      (let ((nul (string (code-char 0))))
        (is (equal "invalid_input" (nth-value 1 (call "customers_get" "employee:anna" "id" nul))))
        (is (equal "invalid_input" (nth-value 1 (call "customers_create" "employee:anna"
                                                      "name" (format nil "Kari~aNordmann" nul)))))
        (is (equal "invalid_input" (nth-value 1 (call "customers_create" "employee:anna"
                                                      "name" "Kari" "request_key" nul))))))))

(test a-required-text-left-blank-is-refused
  ;; Blank text is no value: a tool's body never sees NIL for a required
  ;; text, as widgets_run_program did, which passed it on to a program.
  (with-test-app (:class 'program-application)
    (dolist (text '("" "   "))
      (multiple-value-bind (json code) (call "widgets_run_program" "employee:anna" "text" text)
        (is (equal "invalid_input" code))
        (is (equal "text" (jget (aref (jget (jget json "error") "fields") 0) "field")))))))

;;; ------------------------------------------------------------------
;;; Probe tools, and the defects a test plants in them

(defvar *planted-defects* '()
  "The defects the probe tools below have while a test binds this: :FAULT,
an error Tun did not expect for most input; :WRITE-THEN-REFUSE, a refusal
after the record is written; :DIRECT-CONNECTION, a call to another host past
Tun's handlers; :UNAUDITED, a refusal whose audit entry the body drops.
None elsewhere, so the probes behave in every other test.")

(define-entity fuzz-note (:label "Fuzz note" :id-prefix "fzn" :table "fuzz_notes")
  ((title :type (string :min 1 :max 200) :required t :label "Title")
   (body :type (string :max 2000) :label "Body")))

(define-operation fuzz-notes-count ((quantity :type (string :max 20) :required t
                                              :label "Quantity"))
    (:kind :read :policy :viewer :title "Count (fuzz probe)")
  (jobj "count" (if (member :fault *planted-defects*)
                    ;; Text taken for a number, as a careless tool does.
                    (parse-integer quantity)
                    (or (and quantity (parse-integer quantity :junk-allowed t)) 0))))

(define-operation fuzz-notes-create ((:draft fuzz-note))
    (:entity fuzz-note :kind :create :policy :employee :title "Add a note (fuzz probe)")
  (insert fuzz-note)
  (if (and (member :write-then-refuse *planted-defects*) (fuzz-note-body fuzz-note))
      ;; Refused after the note is committed, as a call to another system
      ;; made after the commit may be.
      (complete-after-commit fuzz-note
                             (lambda () (fail :unavailable "The archive did not answer")))
      fuzz-note))

(define-operation fuzz-notes-share ((title :type (string :max 200) :required t :label "Title"))
    (:kind :read :policy :viewer :title "Share a note (fuzz probe)")
  (when (member :direct-connection *planted-defects*)
    ;; Straight to another host, past *HTTP-JSON-HANDLER*: 192.0.2.1 is an
    ;; address for documentation, which no host has.
    (drakma:http-request "http://192.0.2.1:9/notes" :method :post :content title
                                                    :connection-timeout 1))
  (jobj "shared" t))

(define-operation fuzz-notes-archive ((id :type (id fuzz-note) :required t :label "Note"))
    (:entity fuzz-note :kind :transition :confirm t :policy :employee
     :title "Archive a note (fuzz probe)")
  (delete-entity (fetch! 'fuzz-note id))
  (jobj "archived" id))

(define-operation fuzz-notes-lock ((id :type (id fuzz-note) :required t :label "Note"))
    (:entity fuzz-note :kind :transition :policy :employee :title "Lock a note (fuzz probe)")
  ;; Always refused; with the defect, inside a binding of core's deferred
  ;; audits that the body then drops, so its entry is never written.
  (if (member :unaudited *planted-defects*)
      (let ((tun.core::*deferred-audits* '()))
        (fail :forbidden "Notes cannot be locked"))
      (fail :forbidden "Notes cannot be locked")))

(defun probe-operations (&rest tools)
  (mapcar #'find-operation-by-tool tools))

(define-scenario fuzz-notes (:actors ("employee:anna"))
  "Three notes, for the probe tools' ids to name."
  (dolist (title '("Første" "Andre" "Tredje"))
    (call-ok "fuzz_notes_create" "employee:anna" "title" title)))

(defun fuzz-probes (tools &rest options &key (seed 1) (calls 4) &allow-other-keys)
  "The report of fuzzing TOOLS, probe tools' names, with SEED and CALLS and
the other OPTIONS FUZZ-TOOLS takes, on the scenario fuzz-notes."
  (apply #'fuzz-tools (apply #'probe-operations tools)
         :seed seed :calls calls :scenario (find-scenario "fuzz-notes" :package "TUN.TESTS")
         options))

(defun only-failure (report)
  "REPORT's one failure; the test fails when there is not exactly one."
  (let ((failures (fuzz-report-failures report)))
    (is (= 1 (length failures)) "~d failures" (length failures))
    (first failures)))

;;; ------------------------------------------------------------------
;;; A planted defect is found (criterion 3)

(test fuzzing-finds-a-fault-and-says-what-makes-it-again
  (let ((report (let ((*planted-defects* '(:fault)))
                  (fuzz-probes '("fuzz_notes_count") :seed 7))))
    (let* ((failure (only-failure report))
           (text (failure-text failure 4)))
      (is (eq :fault (fuzz-failure-kind failure)))
      (is (search "fuzz_notes_count, as " text) "~a" text)
      (is (search "(seed 7)" text) "~a" text)
      (is (search "TUN_FUZZ_SEED=7 TUN_FUZZ_CALLS=4" text) "~a" text)
      (is (search "a fault: " text) "~a" text)
      (is (search (fuzz-call-actor (fuzz-failure-call failure)) text))
      (let ((shrunk (fuzz-failure-shrunk failure)))
        (is (equal '("quantity") (jkeys shrunk)) "only the property that fails")
        (is (<= (length (jget shrunk "quantity")) 1) "a short text: ~s" (jget shrunk "quantity"))
        (is (search (to-json-string shrunk) text) "the report shows it: ~a" text))))
  (is (null (fuzz-report-failures (fuzz-probes '("fuzz_notes_count") :seed 7)))
      "without the defect the tool withstands the same calls"))

(test fuzzing-finds-a-refusal-that-wrote
  (let ((report (let ((*planted-defects* '(:write-then-refuse)))
                  (fuzz-probes '("fuzz_notes_create") :seed 7))))
    (let* ((failure (only-failure report))
           (text (failure-text failure 4)))
      (is (eq :changed-records (fuzz-failure-kind failure)))
      (is (search "it refused with unavailable but changed records of fuzz_note" text) "~a" text)
      (is (search "fuzz_notes_create, as " text))
      (is (equal '("body" "title") (sort (jkeys (fuzz-failure-shrunk failure)) #'string<))
          "the title it needs and the body that makes it fail: ~a" text)))
  (is (null (fuzz-report-failures (fuzz-probes '("fuzz_notes_create") :seed 7)))))

;;; ------------------------------------------------------------------
;;; The generated test (criterion 1)

(defun forget-operation (name)
  "Remove the operation NAME, which a test defined, from the registry."
  (remhash name tun.core::*operations*)
  (setf tun.core::*operation-order* (remove name tun.core::*operation-order*))
  (fmakunbound name))

(test fuzzing-finds-a-refusal-left-unaudited
  (let ((report (let ((*planted-defects* '(:unaudited)))
                  (fuzz-probes '("fuzz_notes_lock") :seed 7))))
    (let* ((failure (only-failure report))
           (text (failure-text failure 4)))
      (is (eq :unaudited (fuzz-failure-kind failure)))
      (is (search "it refused with forbidden but left no rejected audit entry" text) "~a" text)
      (is (search "fuzz_notes_lock, as " text) "~a" text)
      (is (search "(seed 7)" text) "~a" text)
      (is (search (fuzz-call-actor (fuzz-failure-call failure)) text))))
  (is (null (fuzz-report-failures (fuzz-probes '("fuzz_notes_lock") :seed 7)))
      "the same refusals, each with its entry, pass"))

(test a-refusal-without-its-audit-entry-fails-the-run
  ;; The check on the call it judges, once with no entry written and once
  ;; with the entry the refusal leaves.
  (with-test-app ()
    (let ((operation (find-operation-by-tool "fuzz_notes_archive"))
          (call (tun.test-support::make-fuzz-call "viewer:fuzz" (jobj "id" "fzn_none") :call))
          (refused (tun.test-support::make-outcome :error :code :forbidden)))
      (let ((state (tun.test-support::fresh-call-state)))
        (is (eq :unaudited (nth-value 1 (tun.test-support::call-problem operation call refused state)))
            "a refusal with no entry"))
      (let ((state (tun.test-support::fresh-call-state)))
        (is (string= "forbidden" (nth-value 1 (call "fuzz_notes_archive" "viewer:vera" "id" "fzn_none"))))
        (is (null (tun.test-support::call-problem operation call refused state))
            "the same refusal with the entry it left")))))

(test the-generated-fuzzing-test-fuzzes-the-client-s-tools
  (with-probe-client ()
    (let ((tool (probe-symbol "PROBE-COUNT")))
      (unwind-protect
           (progn
             (let ((*package* (find-package +probe-package+)))
               (eval `(define-operation ,tool ((quantity :type (string :max 20) :required t))
                          (:kind :read :policy :viewer :title "Count (probe)")
                        (jobj "count" (if (member :fault *planted-defects*)
                                          (parse-integer quantity)
                                          0)))))
             (is (equal (list tool) (mapcar #'operation-name
                                            (client-operations +probe-package+))))
             (is (eq t (run-probe-test "EVERY-TOOL-WITHSTANDS-FUZZING")))
             (let ((*planted-defects* '(:fault)))
               (multiple-value-bind (passed explained)
                   (run-probe-test "EVERY-TOOL-WITHSTANDS-FUZZING")
                 (is (not passed))
                 (is (search "probe_count, as " explained) "~a" explained))))
        (forget-operation tool)))))

;;; ------------------------------------------------------------------
;;; Shrinking (criterion 5)

(test shrinking-keeps-the-one-property-and-the-short-text-that-fail
  (let* ((input (jobj "name" (make-string 180 :initial-element #\n)
                      "title" (concatenate 'string (make-string 90 :initial-element #\a)
                                           "<script>" (make-string 90 :initial-element #\b))
                      "body" (make-string 1500 :initial-element #\c)
                      "count" 4711
                      "tags" (jarr '("x" "y" "z"))
                      "lines" (jarr (list (jobj "quantity" 3 "note" "Hei")))
                      "email" "kari@example.no"
                      "active" t))
         (calls 0)
         (shrunk (shrink-input input (lambda (candidate)
                                       (incf calls)
                                       (search "<" (or (jget candidate "title") ""))))))
    (is (equal "{\"title\":\"<\"}" (to-json-string shrunk)))
    (is (< calls 300) "~d attempts" calls)))

(test shrinking-makes-numbers-simpler-and-ids-the-first-record
  (let ((shrunk (shrink-input (jobj "count" 4711 "price" 12.5d0
                                    "id" (make-record-ref 'fuzz-note 5))
                              (lambda (candidate)
                                (and (integerp (jget candidate "count"))
                                     (> (jget candidate "count") 100)
                                     (record-ref-p (jget candidate "id")))))))
    (is (< 100 (jget shrunk "count") 300) "~a" (jget shrunk "count"))
    (is (equal '("count" "id") (jkeys shrunk)))
    (is (= 0 (record-ref-index (jget shrunk "id"))))))

;;; ------------------------------------------------------------------
;;; The seed (criterion 4)

(defun inputs-made (seed &key (calls 3))
  "The inputs the fuzzer sends fuzz_notes_archive with SEED, as each call
shows them, ids as the records they name, and the ids they were sent with."
  (let ((shown '()) (ids '()))
    (fuzz-probes '("fuzz_notes_archive") :seed seed :calls calls
                 :observe (lambda (operation call outcome)
                            (declare (ignore operation outcome))
                            (let ((input (fuzz-call-input call)))
                              (push (list (fuzz-call-actor call) (fuzz-call-purpose call)
                                          (shown-input input))
                                    shown)
                              (when (record-ref-p (jget input "id"))
                                (push (record-ref-id (jget input "id")) ids)))))
    (values (reverse shown) ids)))

(test the-same-seed-makes-the-same-calls-and-names-the-same-records
  (multiple-value-bind (first first-ids) (inputs-made 11)
    (multiple-value-bind (again again-ids) (inputs-made 11)
      (is (equal first again))
      (is (plusp (length first-ids)))
      (is (not (intersection (remove-if (lambda (id) (search "fuzznothing" id)) first-ids)
                             again-ids :test #'string=))
          "a fresh database's records have new ids, and the calls name them by insertion order")))
  (is (not (equal (inputs-made 11) (inputs-made 12))) "another seed makes other calls"))

(test the-seed-comes-from-tun-fuzz-seed-and-is-fixed-without-it
  (flet ((with-environment (value function)
           (let ((old (uiop:getenv "TUN_FUZZ_SEED")))
             (unwind-protect
                  (progn (if value
                             (sb-posix:setenv "TUN_FUZZ_SEED" value 1)
                             (sb-posix:unsetenv "TUN_FUZZ_SEED"))
                         (funcall function))
               (if old
                   (sb-posix:setenv "TUN_FUZZ_SEED" old 1)
                   (sb-posix:unsetenv "TUN_FUZZ_SEED"))))))
    (is (= +fuzz-seed+ (with-environment nil #'fuzz-seed)))
    (is (= 42 (with-environment "42" #'fuzz-seed)))
    (is (/= (with-environment "random" #'fuzz-seed) (with-environment "random" #'fuzz-seed)))
    (signals error (with-environment "many" #'fuzz-seed))))

(test a-failure-s-seed-makes-it-again
  (let ((*planted-defects* '(:fault)))
    (let* ((failure (only-failure (fuzz-probes '("fuzz_notes_count") :seed 23)))
           (again (only-failure (fuzz-probes '("fuzz_notes_count")
                                             :seed (fuzz-failure-seed failure)))))
      (is (= (fuzz-failure-index failure) (fuzz-failure-index again)))
      (is (equal (fuzz-call-actor (fuzz-failure-call failure))
                 (fuzz-call-actor (fuzz-failure-call again))))
      (is (equal (to-json-string (fuzz-failure-shrunk failure))
                 (to-json-string (fuzz-failure-shrunk again)))))))

;;; ------------------------------------------------------------------
;;; Confirmation (core.md §3.6)

(test a-tool-that-asks-for-confirmation-is-confirmed-and-refuses-other-tokens
  (let ((seen '()))
    (is (null (fuzz-report-failures
               (fuzz-probes '("fuzz_notes_archive") :calls 6
                            :observe (lambda (operation call outcome)
                                       (declare (ignore operation))
                                       (push (list (fuzz-call-purpose call) (outcome-kind outcome)
                                                   (outcome-code outcome))
                                             seen))))))
    (flet ((outcomes (purpose)
             (mapcar #'rest (remove purpose seen :key #'first :test-not #'eq))))
      (is (find '(:result nil) (outcomes :ask) :test #'equal) "a token was asked for")
      (is (every (lambda (o) (equal o '(:error :confirmation-invalid))) (outcomes :wrong-token)))
      (is (outcomes :wrong-token))
      (is (every (lambda (o) (equal o '(:error :confirmation-invalid))) (outcomes :other-input)))
      (is (outcomes :other-input))
      (is (find :result (outcomes :confirm) :key #'first) "the token confirmed"))))

;;; ------------------------------------------------------------------
;;; Nothing leaves the process (criterion 2)

(test a-tool-calling-another-system-finds-it-unreachable
  (let ((*remote-url* "https://api.example.no/v1/check")
        (codes '()))
    (flet ((note (operation call outcome)
             (declare (ignore call))
             (push (list (operation-tool operation) (outcome-kind outcome) (outcome-code outcome))
                   codes)))
      (is (null (fuzz-report-failures
                 (fuzz-tools (probe-operations "widgets_ask_remote" "widgets_read_remote"
                                               "widgets_post_form")
                             :seed 3 :calls 4 :observe #'note))))
      (is (null (fuzz-report-failures
                 (fuzz-tools (probe-operations "widgets_run_program") :class 'program-application
                                                                      :seed 3 :calls 4
                                                                      :observe #'note)))))
    (dolist (tool '("widgets_ask_remote" "widgets_read_remote" "widgets_post_form"
                    "widgets_run_program"))
      (let ((outcomes (remove tool codes :key #'first :test-not #'string=)))
        (is (find '(:error :unavailable) outcomes :key #'rest :test #'equal)
            "~a reached the other system as unreachable: ~s" tool outcomes)
        (is (not (find :result outcomes :key #'second)) "~a got no answer" tool)))))

(test a-connection-to-another-host-fails-the-run
  (let* ((report (let ((*planted-defects* '(:direct-connection)))
                   (fuzz-probes '("fuzz_notes_share") :seed 5)))
         (text (failure-text (only-failure report) 4)))
    ;; usocket looks the address up before it connects.
    (is (search "it tried to reach another system: a lookup of the host 192.0.2.1" text)
        "~a" text))
  (is (null (fuzz-report-failures (fuzz-probes '("fuzz_notes_share") :seed 5))))
  (is (null (with-connections-refused ()
              (take-connection-attempts)
              (handler-case (progn (usocket:socket-connect "192.0.2.1" 9 :timeout 1) :connected)
                (error () nil)))))
  (is (equal '("a lookup of the host 192.0.2.1") (take-connection-attempts)))
  (is (null (with-connections-refused ()
              (let ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream
                                                                       :protocol :tcp)))
                (unwind-protect
                     (handler-case (progn (sb-bsd-sockets:socket-connect socket #(192 0 2 1) 9)
                                          :connected)
                       (error () nil))
                  (sb-bsd-sockets:socket-close socket))))))
  (is (equal '("a connection to 192.0.2.1:9") (take-connection-attempts)))
  (is (not (sb-int:encapsulated-p 'sb-bsd-sockets:socket-connect
                                  'tun.test-support::refuse-connection))
      "connections are refused only while the fuzzer runs"))

(test no-job-runs-while-tools-are-fuzzed
  (let ((attempts '()))
    (is (null (fuzz-report-failures
               (fuzz-tools (probe-operations "jobs_test_enqueue") :seed 3 :calls 3
                           :observe (lambda (operation call outcome)
                                      (declare (ignore operation call outcome))
                                      (push (drain-jobs) attempts))))))
    (is (every #'zerop attempts) "the queued jobs wait: ~s" attempts))
  (with-test-app ()
    (call-ok "jobs_test_enqueue" "employee:anna" "text" "Hei")
    (tun.jobs:hold-jobs *app*)
    (is (zerop (drain-jobs)))
    (tun.jobs:hold-jobs *app* nil)
    (is (= 1 (drain-jobs)))))

(define-scenario fuzz-widgets ()
  "Two widgets, which no one archives."
  (call-ok "widgets_create" "employee:anna" "name" "Dings")
  (call-ok "widgets_create" "employee:anna" "name" "Dongs"))

(test a-waiting-tool-waits-no-time
  (let ((seconds '()))
    (is (null (fuzz-report-failures
               (fuzz-tools (probe-operations "widgets_await_archived")
                           :seed 3 :calls 3
                           :scenario (find-scenario "fuzz-widgets" :package "TUN.TESTS")
                           :observe (lambda (operation call outcome)
                                      (declare (ignore call))
                                      (when (eq :wait (operation-kind operation))
                                        (push (outcome-seconds outcome) seconds)))))))
    (is (plusp (length seconds)))
    (is (every (lambda (s) (< s 1)) seconds) "~s" seconds)))
