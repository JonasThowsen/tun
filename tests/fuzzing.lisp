;;;; tests/fuzzing.lisp -- fuzzing every tool (spec/testing.md 2).  Each
;;;; tool is called with inputs made up from its schema (tests/fuzz-inputs.lisp)
;;;; on a fresh copy of the database the scenario filled, as each actor, the
;;;; way tools/call goes, with nothing leaving the process.  What must hold is
;;;; checked after every call; a call that breaks it is shrunk, replayed on
;;;; fresh copies, and reported with the seed that makes it again.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; What a run fuzzes, and how much

(defparameter +fuzz-calls+ 8
  "How many inputs each tool is called with per actor in bin/test, unless
TUN_FUZZ_CALLS says otherwise: few enough that a client's generated tests
stay within 30 seconds (spec/testing.md 1).")

(defparameter +fuzz-seed+ 20261107
  "The seed bin/test fuzzes with, unless TUN_FUZZ_SEED says otherwise: the
same every run, so a run fails only for what changed.")

(defparameter +fuzz-actors+ '("admin:fuzz" "employee:fuzz" "viewer:fuzz")
  "The actors every tool is called as, besides those the scenario names.")

(defparameter +unfuzzed-tools+ '("clock_get" "clock_set" "eval")
  "Tools left out, besides the debug_ ones: the test clock's, which move the
clock and run due jobs, and eval, which runs text as code.  Each exists only
to test or to debug (spec/testing.md 2).")

(defparameter +shrink-attempts+ 200
  "The most replays shrinking a failing input makes.")

(defun fuzzed-tool-p (operation)
  "True unless OPERATION's tool is one fuzzing leaves out."
  (let ((tool (operation-tool operation)))
    (not (or (member tool +unfuzzed-tools+ :test #'string=)
             (eql 0 (search "debug_" tool))))))

(defun client-operations (package)
  "The operations a client defines in PACKAGE, a package designator, in the
order they were defined."
  (let ((package (find-package package)))
    (remove-if-not (lambda (operation)
                     (and (string= "client" (operation-module operation))
                          (eq package (symbol-package (operation-name operation)))))
                   (all-operations))))

(defun environment-integer (name default)
  "The value of the environment variable NAME as an integer, or DEFAULT when
it is not set."
  (let ((text (uiop:getenv name)))
    (if (or (null text) (string= text ""))
        default
        (multiple-value-bind (number end) (parse-integer text :junk-allowed t)
          (if (and number (= end (length text)))
              number
              (error "~a must be a whole number, not ~s" name text))))))

(defun fuzz-seed ()
  "The seed of this run: TUN_FUZZ_SEED, a whole number or random for a new
one each run, else +FUZZ-SEED+."
  (if (equal (uiop:getenv "TUN_FUZZ_SEED") "random")
      (random (expt 2 31) (make-random-state t))
      (environment-integer "TUN_FUZZ_SEED" +fuzz-seed+)))

(defun fuzz-calls ()
  "How many inputs each tool is called with per actor: TUN_FUZZ_CALLS, else
+FUZZ-CALLS+."
  (environment-integer "TUN_FUZZ_CALLS" +fuzz-calls+))

;;; ------------------------------------------------------------------
;;; Nothing leaves the process

(defvar *connection-attempts* '()
  "What tried to reach another host while connections were refused, newest
first.  Any thread may add to it, so it is guarded by
*CONNECTION-ATTEMPTS-LOCK*.")

(defvar *connection-attempts-lock* (sb-thread:make-mutex :name "fuzz connection attempts"))

(defparameter +connecting-functions+
  '(sb-bsd-sockets:socket-connect sb-bsd-sockets:get-host-by-name
    sb-bsd-sockets:get-host-by-address)
  "The functions below drakma and usocket through which a process looks up
or connects to another host on SBCL.")

(defun attempt-text (function arguments)
  "What a call of FUNCTION, one of +CONNECTING-FUNCTIONS+, with ARGUMENTS
tried to do."
  (if (eq function 'sb-bsd-sockets:socket-connect)
      (destructuring-bind (socket &optional address port) arguments
        (declare (ignore socket))
        (format nil "a connection to ~:[~a~;~{~d~^.~}~]~@[:~d~]"
                (vectorp address) (if (vectorp address) (coerce address 'list) address) port))
      (format nil "a lookup of the host ~{~a~}" arguments)))

(defun refuse-connection (function arguments)
  "Note that FUNCTION was called with ARGUMENTS, and fail the call."
  (let ((attempt (attempt-text function arguments)))
    (sb-thread:with-mutex (*connection-attempts-lock*)
      (push attempt *connection-attempts*))
    (error "~a was refused: nothing leaves the process while tools are fuzzed" attempt)))

(defun take-connection-attempts ()
  "The attempts to reach another host made since this was last called,
oldest first."
  (sb-thread:with-mutex (*connection-attempts-lock*)
    (prog1 (reverse *connection-attempts*)
      (setf *connection-attempts* '()))))

(defun local-socket-call-p (name arguments)
  "True when NAME, one of +CONNECTING-FUNCTIONS+, is called with ARGUMENTS to
connect a Unix socket, which reaches this machine only: the test Postgres
server's, for an application on Postgres."
  (and (eq name 'sb-bsd-sockets:socket-connect)
       (typep (first arguments) 'sb-bsd-sockets:local-socket)))

(defun call-with-connections-refused (function)
  "Call FUNCTION with every lookup of and connection to another host, from
any thread, failing and noted (TAKE-CONNECTION-ATTEMPTS).  The functions
below drakma and usocket are wrapped for as long as FUNCTION runs; a Unix
socket still connects.  The wrapping is the whole image's: while it lasts,
any thread's connection fails, and two runs at once would unwrap under each
other.  bin/test gives each suite a process of its own and FiveAM runs one
test at a time, so neither happens there."
  (let ((wrapped '()))
    (unwind-protect
         (progn
           (dolist (name +connecting-functions+)
             (unless (sb-int:encapsulated-p name 'refuse-connection)
               (let ((name name))
                 (sb-int:encapsulate name 'refuse-connection
                                     (lambda (original &rest arguments)
                                       (if (local-socket-call-p name arguments)
                                           (apply original arguments)
                                           (refuse-connection name arguments)))))
               (push name wrapped)))
           (funcall function))
      (dolist (name wrapped)
        (sb-int:unencapsulate name 'refuse-connection)))))

(defmacro with-connections-refused (() &body body)
  "Run BODY with every lookup of and connection to another host failing and
noted, as CALL-WITH-CONNECTIONS-REFUSED does."
  `(call-with-connections-refused (lambda () ,@body)))

(defun unreachable-system (url body headers)
  "An *HTTP-JSON-HANDLER* for which every other system is unreachable: it
gives no answer."
  (declare (ignore url body headers))
  nil)

(defun program-not-started (name arguments directory input environment)
  "A *PROGRAM-HANDLER* for which no program can be started."
  (declare (ignore name arguments directory input environment))
  (values "" nil ""))

;;; ------------------------------------------------------------------
;;; A run

(defstruct (fuzz-run (:constructor make-fuzz-run
                         (class scenario actors seed calls variables database observe)))
  "What a fuzzing run does: it calls each tool CALLS times as each of ACTORS,
strings, with inputs made from SEED, on an application of CLASS holding
the records of SCENARIO, a scenario or NIL, with VARIABLES unset around it,
as around a generated test.  DATABASE is :MEMORY or :POSTGRES.  The
scenario is made once, in TEMPLATE, a memory store or the URL of a Postgres
database, and each tool's database is a copy of it, with VALUES, the values
the scenario left VARIABLES with.  OBSERVE is NIL, or a function called
after each call with the operation, the FUZZ-CALL and its OUTCOME, while
*APP* is the tool's application."
  class scenario actors seed calls variables database observe template values)

(defstruct (fuzz-call (:constructor make-fuzz-call (actor input purpose)))
  "One call of a tool, as a replay makes it again.  ACTOR is a string, INPUT
the input as it was made, with RECORD-REFs for ids, and PURPOSE one of :CALL;
or, for a tool that asks for confirmation, :ASK, without a token; :WRONG-TOKEN,
with one it never gave; :OTHER-INPUT, with the token it gave for another
input; and :CONFIRM, with the token it gave for this input."
  (actor "" :type string :read-only t)
  (input nil :type hash-table :read-only t)
  (purpose :call :type (member :call :ask :wrong-token :other-input :confirm) :read-only t))

(defstruct (outcome (:constructor make-outcome (kind &key code result condition (seconds 0))))
  "How a call ended: KIND :RESULT with its RESULT, :ERROR with its CODE,
:FAULT with the CONDITION Tun did not expect, or :REFUSED when the arguments
were not JSON a request may carry, which MCP refuses before any tool runs."
  kind code result condition seconds)

(defstruct (call-state (:constructor make-call-state
                           (fingerprint known-ids commits rejections
                            &aux (rejections-commits commits))))
  "What the calls of one tool on one database share: the records as they
were after the last call, as RECORDS-FINGERPRINT gives them, with the ids of
the records of each entity with a record policy then (KNOWN-IDS), the
store's commit count then, the rejected audit entries of each tool as
REJECTION-COUNTS gives them with the commit count they were counted at, and
the confirmation token each actor was given last."
  fingerprint
  known-ids
  commits
  rejections
  rejections-commits
  (tokens (make-hash-table :test 'equal)))

(defun stored-entity-classes ()
  "The entities whose records an erring call, or a viewer's, must leave as
they were (spec/testing.md 2): every one stored in a table of its own,
internal ones and settings among them, but the audit's entries, which a
refusal writes; on a store that cannot apply record policies, those without
one, which no tool there can reach."
  (let ((store (application-store *app*)))
    (remove-if (lambda (class)
                 (or (eq (class-name class) 'audit-entry) (entity-embedded-p class)
                     (and (entity-record-policy class) (not (store-runs-queries-p store)))))
               (all-entity-classes))))

(defun policy-entity-classes ()
  "The entities of *APP* with a record policy, when its store applies them."
  (and (store-runs-queries-p (application-store *app*))
       (remove-if-not #'entity-record-policy (stored-entity-classes))))

(defmacro reading-every-record (() &body body)
  "Run BODY in a read transaction of *APP* as a system actor, whom no record
policy holds back."
  `(with-application (*app*)
     (with-actor ((system-actor "fuzz"))
       (with-transaction (:read) ,@body))))

(defun records-text (class)
  "Each record of CLASS in *APP*, its id and stored values, in insertion
order, as one text."
  (with-output-to-string (out)
    (dolist (record (select (class-name class) :order-by '(("seq" :asc))))
      (prin1 (entity-id record) out)
      (dolist (field (entity-fields class))
        (prin1 (type->db (field-type field) (field-value record field)) out)))))

(defun table-digests (classes)
  "A hash table from the json name of each of CLASSES to a digest of its
table's rows in insertion order, which the Postgres server computes, all
in one query."
  (let ((digests (make-hash-table :test 'equal)))
    (when classes
      (loop for (name digest)
              in (store-query (application-store *app*)
                              (format nil "~{~a~^ UNION ALL ~}"
                                      (mapcar (lambda (class)
                                                (format nil "SELECT '~a', (SELECT md5(coalesce(~
                                                             string_agg(t::text, ',' ORDER BY t.seq), '')) ~
                                                             FROM \"~a\" t)"
                                                        (entity-json-name class) (entity-table class)))
                                              classes))
                              '())
            do (setf (gethash name digests) digest)))
    digests))

(defun policy-record-ids (classes)
  "The ids of every record of those of CLASSES with a record policy, read
in one query from their Postgres tables."
  (let ((tables (loop for class in classes
                      when (entity-record-policy class)
                        collect (format nil "SELECT id FROM \"~a\"" (entity-table class)))))
    (and tables
         (mapcar #'first (store-query (application-store *app*)
                                      (format nil "~{~a~^ UNION ALL ~}" tables) '())))))

(defun records-fingerprint ()
  "Every record of each of STORED-ENTITY-CLASSES in *APP*, as a list of
(entity-name . text): on Postgres the digest of its table, else the text
RECORDS-TEXT gives.  Its second value is a hash table holding the id of
each record of an entity with a record policy."
  (let ((ids (make-hash-table :test 'equal))
        (classes (stored-entity-classes))
        (postgres (store-runs-queries-p (application-store *app*))))
    (values
     (reading-every-record ()
       ;; Records with a policy are only on Postgres (store.md 6 item 7).
       (dolist (id (and postgres (policy-record-ids classes)))
         (setf (gethash id ids) t))
       (let ((digests (and postgres (table-digests classes))))
         (loop for class in classes
               collect (cons (entity-json-name class)
                             (if postgres
                                 (gethash (entity-json-name class) digests)
                                 (records-text class))))))
     ids)))

(defun rejection-counts ()
  "How many audit entries with outcome rejected each tool has in *APP*: a
hash table from the tool's name."
  (let ((counts (make-hash-table :test 'equal)))
    (reading-every-record ()
      (dolist (entry (select 'audit-entry :where '(:= "outcome" "rejected")))
        (incf (gethash (audit-entry-tool entry) counts 0))))
    counts))

(defun new-rejections (tool state)
  "How many rejected audit entries TOOL has gained since STATE last counted
them, which are then counted again: only when the store has committed since,
as an entry is written in a transaction of its own or of its call.  The check
asks for at least one: a tool that calls itself has one entry per call, and
a nested call's entry for the same tool cannot be told from the outer's."
  (let ((commits (store-commits (application-store *app*))))
    (if (eql commits (call-state-rejections-commits state))
        0
        (let ((before (gethash tool (call-state-rejections state) 0))
              (now (rejection-counts)))
          (setf (call-state-rejections state) now
                (call-state-rejections-commits state) commits)
          (- (gethash tool now 0) before)))))

(defun fresh-call-state ()
  "A CALL-STATE for the calls about to be made on *APP*."
  (multiple-value-bind (fingerprint ids) (records-fingerprint)
    (make-call-state fingerprint ids (store-commits (application-store *app*))
                     (rejection-counts))))

(defun changed-entities (state)
  "The entities whose records changed since STATE's fingerprint, which is
then taken again: only when the store has committed since."
  (let ((commits (store-commits (application-store *app*))))
    (unless (eql commits (call-state-commits state))
      (let ((before (call-state-fingerprint state)))
        (multiple-value-bind (now ids) (records-fingerprint)
          (setf (call-state-fingerprint state) now
                (call-state-known-ids state) ids
                (call-state-commits state) commits)
          (loop for (name . text) in now
                for old = (cdr (assoc name before :test #'string=))
                unless (equal text old)
                  collect name))))))

;;; What an actor reaches (spec/store.md 6): what the store reads as that
;;; actor, against what it reads as the system actor.

(defun record-ids (class-name &optional actor)
  "The ids of the records of CLASS-NAME in *APP* that ACTOR, a string, or
the system actor without one, reaches, in insertion order."
  (with-application (*app*)
    (with-actor ((if actor (parse-actor actor) (system-actor "fuzz")))
      (with-transaction (:read)
        (mapcar #'entity-id (select class-name :order-by '(("seq" :asc))))))))

(defun reaches-p (class-name id actor)
  "True when ACTOR, a string, reaches the record ID of CLASS-NAME in *APP*:
at once when the entity has no record policy or the clause of the actor's
role is T, and not when the policy has no clause for the role; else as the
store reads it as the actor."
  (let* ((actor (parse-actor actor))
         (policy (entity-record-policy (find-entity-class class-name)))
         (clause (assoc (actor-role actor) policy)))
    (cond ((null policy) t)
          ((null clause) nil)
          ((eq t (second clause)) t)
          (t (with-application (*app*)
               (with-actor (actor)
                 (with-transaction (:read)
                   (and (fetch class-name id) t))))))))

(defun exists-p (class-name id)
  (reading-every-record () (and (fetch class-name id) t)))

(defun shown-records (result classes)
  "The (class . id) of each object in RESULT, a tool's result as JSON, whose
id has the prefix of one of CLASSES, entity classes."
  (let ((shown '()))
    (labels ((walk (value)
               (cond ((hash-table-p value)
                      (let* ((id (gethash "id" value))
                             (class (and (stringp id)
                                         (find-if (lambda (class)
                                                    (let ((prefix (entity-id-prefix class)))
                                                      (and (> (length id) (length prefix))
                                                           (string= prefix id :end2 (length prefix))
                                                           (char= #\_ (char id (length prefix))))))
                                                  classes))))
                        (when class
                          (pushnew (cons class id) shown :test #'equal)))
                      (maphash (lambda (key item) (declare (ignore key)) (walk item)) value))
                     ((and (vectorp value) (not (stringp value))) (map nil #'walk value))
                     ((consp value) (mapc #'walk value)))))
      (walk result))
    (nreverse shown)))

(defun hidden-records-shown (operation call outcome state)
  "The records of an entity with a record policy that OUTCOME's result
shows and CALL's actor does not reach, as (entity-name . id), judged now;
leaving out those the call itself inserted, which STATE's known ids, taken
before it, lack, and every one for a tool declared :BEYOND-RECORD-POLICY
(spec/testing.md 2, sixth point).  Called before STATE's fingerprint is
taken again."
  (let ((classes (and (eq (outcome-kind outcome) :result)
                      (not (operation-beyond-record-policy operation))
                      (policy-entity-classes))))
    (when classes
      (loop for (class . id) in (shown-records (outcome-result outcome) classes)
            when (and (gethash id (call-state-known-ids state))
                      (not (reaches-p (class-name class) id (fuzz-call-actor call)))
                      (exists-p (class-name class) id))
              collect (cons (entity-json-name class) id)))))

(defun viewer-mutation-p (operation)
  "True for a tool a viewer may call to change records: a mutating one whose
policy is viewer, which :VIEWER-MUTATION allows."
  (and (operation-mutating-p operation) (eq (operation-policy operation) :viewer)))

(defun viewer-call-p (call)
  (let ((actor (parse-actor (fuzz-call-actor call))))
    (and actor (eq (actor-role actor) :viewer))))

(defun record-ref-id (ref)
  "The id REF names in *APP*: of the record of its entity inserted at its
index, or that far back from the newest, counted round; or one that names
nothing when there is none."
  (let ((ids (reading-every-record ()
               (mapcar #'entity-id (select (record-ref-entity ref) :order-by '(("seq" :asc)))))))
    (if ids
        (let ((index (mod (record-ref-index ref) (length ids))))
          (nth (if (record-ref-newest ref) (- (length ids) 1 index) index) ids))
        (missing-id (record-ref-entity ref)))))

(defun call-with-fuzz-database (run function)
  "Call FUNCTION with the initargs of an application on a fresh copy of RUN's
template: a memory store, or a Postgres database dropped when FUNCTION
returns."
  (let ((template (fuzz-run-template run)))
    (ecase (fuzz-run-database run)
      (:memory (funcall function (list :store (tun.store.memory:copy-memory-store template))))
      (:postgres (let ((url (scratch-postgres "fuzz" :template template)))
                   (unwind-protect (funcall function (list :db url))
                     (drop-scratch-postgres url)))))))

(defun call-with-fuzzed-application (run function)
  "Call FUNCTION with *APP* a fresh application of RUN's class, on the test
clock, holding a copy of RUN's template; with the variables RUN unsets bound
to the values the scenario left them with, every job held, every other
system answering as unreachable and no call waiting."
  (call-with-fuzz-database
   run
   (lambda (initargs)
     (let ((*app* (apply #'tun.runtime:open-application (fuzz-run-class run) :test-clock t
                         initargs)))
       (unwind-protect
            (progv (fuzz-run-variables run) (fuzz-run-values run)
              (tun.jobs:hold-jobs *app*)
              (let ((tun:*http-json-handler* #'unreachable-system)
                    (tun:*program-handler* #'program-not-started)
                    (*await-limit* 0))
                (funcall function (fresh-call-state))))
         (tun.runtime:close-application *app*))))))

(defun make-template (run)
  "Make RUN's template: a database with the records of its scenario, which
runs once with RUN's variables unset; and note the values it leaves them
with."
  (flet ((make-records (initargs)
           (let ((*app* (apply #'tun.runtime:open-application (fuzz-run-class run) :test-clock t
                               initargs)))
             (unwind-protect
                  (call-with-variables-unset
                   (fuzz-run-variables run)
                   (lambda ()
                     (when (fuzz-run-scenario run)
                       (run-scenario (fuzz-run-scenario run))
                       (let ((attempts (take-connection-attempts)))
                         (when attempts
                           (error "The scenario ~a tried to reach another system: ~{~a~^; ~}"
                                  (scenario-name (fuzz-run-scenario run)) attempts))))
                     (setf (fuzz-run-values run)
                           (mapcar #'symbol-value (fuzz-run-variables run)))))
               (tun.runtime:close-application *app*)))))
    (ecase (fuzz-run-database run)
      (:memory (let ((store (make-instance 'tun.store.memory:memory-store)))
                 (make-records (list :store store))
                 (setf (fuzz-run-template run) store)))
      (:postgres (let ((url (scratch-postgres "fuzz_template")))
                   (make-records (list :db url))
                   (setf (fuzz-run-template run) url))))))

(defun drop-template (run)
  "Drop RUN's template when it is a Postgres database."
  (when (and (eq (fuzz-run-database run) :postgres) (fuzz-run-template run))
    (drop-scratch-postgres (fuzz-run-template run))))

(defmacro with-fuzzed-application ((state run) &body body)
  "Run BODY with STATE, a fresh CALL-STATE, as CALL-WITH-FUZZED-APPLICATION
says."
  `(call-with-fuzzed-application ,run (lambda (,state) ,@body)))

;;; ------------------------------------------------------------------
;;; A call

(defparameter +wrong-token+ "cnf_fuzz_never_given"
  "A confirmation token no tool gave.")

(defun call-arguments (call state)
  "CALL's arguments as they are sent: its input with each id read, and its
confirmation token."
  (let ((arguments (resolve-input (fuzz-call-input call) #'record-ref-id)))
    (case (fuzz-call-purpose call)
      (:wrong-token (setf (gethash "confirmation_token" arguments) +wrong-token+))
      ((:other-input :confirm)
       (setf (gethash "confirmation_token" arguments)
             (gethash (fuzz-call-actor call) (call-state-tokens state) +wrong-token+))))
    arguments))

(defun perform-call (operation call state)
  "Call OPERATION's tool as CALL says, the way tools/call does: the
arguments written and parsed as a request's JSON, the tool called, its
result written as JSON (core.md §3).  Values the outcome."
  (let* ((arguments (call-arguments call state))
         (parsed (handler-case (parse-request-json (to-json-string arguments))
                   (error () (return-from perform-call (make-outcome :refused)))))
         (actor (parse-actor (fuzz-call-actor call)))
         (start (get-internal-real-time)))
    (flet ((seconds ()
             (/ (- (get-internal-real-time) start) internal-time-units-per-second)))
      (let ((outcome (handler-case
                         (let ((result (call-tool (operation-tool operation) parsed
                                                  :application *app* :actor actor)))
                           (to-json-string result)
                           (make-outcome :result :result result :seconds (seconds)))
                       (operation-error (e)
                         (make-outcome :error :code (operation-error-code e) :seconds (seconds)))
                       (serious-condition (e)
                         (make-outcome :fault :condition e :seconds (seconds))))))
        (note-token call outcome state)
        outcome))))

(defun note-token (call outcome state)
  "Keep the confirmation token OUTCOME gives for CALL's actor, and forget the
one a confirmation used."
  (let ((tokens (call-state-tokens state))
        (token (and (eq (outcome-kind outcome) :result)
                    (hash-table-p (outcome-result outcome))
                    (jget (outcome-result outcome) "confirmation_token"))))
    (cond ((stringp token) (setf (gethash (fuzz-call-actor call) tokens) token))
          ((eq (fuzz-call-purpose call) :confirm) (remhash (fuzz-call-actor call) tokens)))))

(defun condition-description (condition)
  "CONDITION's type and text, for a report."
  (format nil "~s: ~a" (type-of condition)
          ;; A fault's own report may fail too; its type still says something.
          (or (ignore-errors (princ-to-string condition)) "(its text cannot be written)")))

(defun call-problem (operation call outcome state)
  "What CALL's OUTCOME breaks of what must hold (spec/testing.md 2): values
a sentence for the report and a keyword for its kind, or NIL when nothing;
and, third, the json names of the entities whose records the call changed.
Takes the fingerprint and the connection attempts anew, so it is called
after every call."
  (let* ((attempts (take-connection-attempts))
         (hidden (hidden-records-shown operation call outcome state))
         (changed (changed-entities state))
         (rejections (new-rejections (operation-tool operation) state))
         (kind (outcome-kind outcome))
         (code (outcome-code outcome)))
    (multiple-value-bind (problem problem-kind)
        (cond (attempts
               (values (format nil "it tried to reach another system: ~{~a~^; ~}" attempts)
                       :connection))
              ((eq kind :fault)
               (values (format nil "it signalled an error Tun did not expect, a fault: ~a"
                               (condition-description (outcome-condition outcome)))
                       :fault))
              ((eq code :deadline-exceeded)
               (values "it ran past its deadline: deadline_exceeded" :deadline))
              ((and (eq kind :error) (not (typep code 'error-code)))
               (values (format nil "it answered ~s, not a code of core.md §3" code) :code))
              ((and (member (fuzz-call-purpose call) '(:wrong-token :other-input))
                    (member kind '(:result :error))
                    (not (eq code :confirmation-invalid))
                    ;; The other input may itself be refused before the token
                    ;; is read, which core.md 3.6 allows.
                    (not (and (eq (fuzz-call-purpose call) :other-input)
                              (eq code :invalid-input))))
               (values (format nil "~a it answered ~:[with a result~;~:*~a~], not confirmation_invalid"
                               (purpose-text call) (and code (json-name-of code)))
                       :confirmation))
              ((and (eq kind :error) changed)
               (values (format nil "it refused with ~a but changed records of ~{~a~^, ~}"
                               (json-name-of code) changed)
                       :changed-records))
              ((and (eq kind :error) (audited-refusal-code-p code) (< rejections 1))
               (values (format nil "it refused with ~a but left no rejected audit entry (core.md §3.8)"
                               (json-name-of code))
                       :unaudited))
              (hidden
               (values (format nil "it showed ~{~a~^, ~}, which ~a's record policy hides (store.md §6); ~
                                    a tool that does so on purpose says why with :beyond-record-policy"
                               (mapcar (lambda (record) (format nil "the ~a ~a" (car record) (cdr record)))
                                       hidden)
                               (fuzz-call-actor call))
                       :hidden-record))
              ((and changed (viewer-call-p call) (not (viewer-mutation-p operation)))
               (values (format nil "a viewer's call changed records of ~{~a~^, ~}" changed)
                       :viewer-wrote))
              ((and (eq (operation-kind operation) :wait) (> (outcome-seconds outcome) 1))
               (values (format nil "it waited ~,1f seconds" (outcome-seconds outcome)) :waited)))
      (values problem problem-kind changed))))

(defun purpose-text (call)
  "How CALL was made, as the report says it."
  (ecase (fuzz-call-purpose call)
    (:call "")
    (:ask "without a confirmation token")
    (:wrong-token "with a confirmation token it never gave")
    (:other-input "with the confirmation token it gave for another input")
    (:confirm "with the confirmation token it gave")))

;;; ------------------------------------------------------------------
;;; A tool's run

(defun fuzz-schema (operation)
  "OPERATION's input schema as inputs are made from it: without
confirmation_token, which the run sends itself."
  (let ((schema (operation-input-schema operation)))
    (remhash "confirmation_token" (jget schema "properties"))
    schema))

(defun note-references (references path type)
  "Note in REFERENCES, by PATH, the entity whose ids TYPE, a field type, and
the fields of the records it holds take."
  (typecase type
    (id-type
     (let* ((name (id-references type))
            (class (and name (find-entity-class name nil))))
       (when (and class (not (entity-embedded-p class)))
         (setf (gethash path references) name))))
    (list-type
     (let ((element (list-element type)))
       (if (symbolp element)
           (note-field-references references (item-path path) (find-entity-class element))
           (note-references references (item-path path) element))))))

(defun note-field-references (references path class)
  (dolist (field (entity-input-fields class))
    (note-references references (property-path path (field-json-name field)) (field-type field))))

(defun operation-references (operation)
  "A hash table from the path of each property of OPERATION's input that
takes ids to the entity whose ids: from the types of its parameters and of
its draft's fields; id naming the operation's own entity, as its audit reads
it; and a NAME_id whose type names no entity, the entity NAME."
  (let ((references (make-hash-table :test 'equal)))
    (when (operation-draft-p operation)
      (note-field-references references "" (find-entity-class (operation-entity operation))))
    (dolist (parameter (operation-parameters operation))
      (note-references references (parameter-json-name parameter) (parameter-type parameter)))
    (dolist (name (schema-properties (operation-input-schema operation)))
      (let* ((suffix (search "_id" name :from-end t))
             (class (cond ((string= name "id")
                           (and (operation-entity operation)
                                (find-entity-class (operation-entity operation) nil)))
                          ((and suffix (= suffix (- (length name) 3)))
                           (find-entity-by-json-name (subseq name 0 suffix))))))
        (when (and class (not (entity-embedded-p class)) (not (gethash name references)))
          (setf (gethash name references) (class-name class)))))
    references))

(defun get-tool-property (operation)
  "The property of OPERATION, a read, that takes ids of its own entity when
that is its only required property, which makes it a get; else NIL."
  (let ((required (required-properties (operation-input-schema operation)))
        (entity (operation-entity operation)))
    (and (eq (operation-kind operation) :read)
         entity
         (= 1 (length required))
         (eq entity (gethash (first required) (operation-references operation)))
         (first required))))

(defun without-request-key (input)
  (let ((copy (copy-object input)))
    (remhash "request_key" copy)
    copy))

(defparameter +changeable-shapes+
  '(:enum :boolean :text :integer :number :date :timestamp :email)
  "The kinds of property another input changes: one valid value of them is
as good as another for the tool's input parser.")

(defun other-input (schema input)
  "INPUT without request_key and with one property's value changed to
another valid one; NIL when no property can be."
  (let ((names (remove-if-not (lambda (name)
                                (let ((property (property-schema schema name)))
                                  (and property
                                       (member (schema-shape property) +changeable-shapes+))))
                              (remove "request_key" (jkeys input) :test #'string=))))
    (loop repeat 8
          for name = (and names (pick names))
          for value = (and name (valid-value (property-schema schema name) name))
          when (and name (not (equal value (gethash name input))))
            return (let ((other (without-request-key input)))
                     (setf (gethash name other) value)
                     other))))

(defstruct (fuzz-failure (:constructor make-fuzz-failure
                             (tool seed index call problem kind earlier)))
  "A call that broke what must hold: the INDEXth call, from 1, of TOOL in the
run with SEED; the CALL; PROBLEM, the sentence saying what broke, of KIND;
EARLIER, the calls before it, oldest first.  Shrinking fills in SHRUNK, the
smallest input that still fails, and ALONE, true when it fails after only
the calls of its own confirmation, or NIL when it did not fail again."
  tool seed index call problem kind earlier shrunk alone)

(defun fuzz-tool (operation run state)
  "Call OPERATION's tool as RUN says, on *APP*, holding the scenario's
records, with STATE, a fresh CALL-STATE, until a call breaks what must
hold.  Values how many calls were made, and the failure or NIL."
  (let* ((*fuzz-random-state* (make-fuzz-random-state (fuzz-run-seed run)
                                                      (operation-tool operation)))
         (schema (fuzz-schema operation))
         (references (operation-references operation))
         (history '()))
    (flet ((make-call (actor input purpose)
             (let* ((call (make-fuzz-call actor input purpose))
                    (outcome (perform-call operation call state)))
               (when (fuzz-run-observe run)
                 (funcall (fuzz-run-observe run) operation call outcome))
               (multiple-value-bind (problem kind) (call-problem operation call outcome state)
                 (when problem
                   (return-from fuzz-tool
                     (values (1+ (length history))
                             (make-fuzz-failure (operation-tool operation) (fuzz-run-seed run)
                                                (1+ (length history)) call problem kind
                                                (reverse history))))))
               (push call history)
               outcome)))
      (dotimes (round (fuzz-run-calls run))
        (dolist (actor (fuzz-run-actors run))
          (let ((input (generate-input schema :references references)))
            (cond ((not (operation-confirm-p operation))
                   (make-call actor input :call))
                  ;; core.md §3.6: the first call asks for confirmation;
                  ;; then a wrong token and the token with another input
                  ;; are refused, and the token with the input confirms.
                  (t (remhash actor (call-state-tokens state))
                     (make-call actor input :ask)
                     (when (gethash actor (call-state-tokens state))
                       (make-call actor (without-request-key input) :wrong-token)
                       (let ((other (other-input schema input)))
                         (when other
                           (make-call actor other :other-input)))
                       (make-call actor input :confirm))))))))
    (values (length history) nil)))

;;; ------------------------------------------------------------------
;;; Shrinking a failure

(defun fails-again-p (operation run earlier call kind)
  "Whether CALL breaks what must hold in the way KIND names when made after
EARLIER, calls made first, on a fresh application of RUN's."
  (with-fuzzed-application (state run)
    (dolist (call earlier)
      (call-problem operation call (perform-call operation call state) state))
    (eq kind (nth-value 1 (call-problem operation call
                                        (perform-call operation call state) state)))))

(defun with-input (call input)
  (make-fuzz-call (fuzz-call-actor call) input (fuzz-call-purpose call)))

(defun shrink-failure (operation run failure)
  "FAILURE with its smallest failing input found.  A call that confirms is
made after the call that asked, with the same input: a smaller input
replaces it in both.  The calls before the failing one are replayed when it
does not fail after only its own confirmation's."
  (let* ((call (fuzz-failure-call failure))
         (kind (fuzz-failure-kind failure))
         (own (remove-if-not (lambda (earlier)
                               (eq (fuzz-call-input earlier) (fuzz-call-input call)))
                             (fuzz-failure-earlier failure)))
         (alone (fails-again-p operation run own call kind))
         (earlier (if alone own (fuzz-failure-earlier failure))))
    (when (or alone (fails-again-p operation run earlier call kind))
      (flet ((replaced (candidate)
               (mapcar (lambda (earlier-call)
                         (if (eq (fuzz-call-input earlier-call) (fuzz-call-input call))
                             (with-input earlier-call candidate)
                             earlier-call))
                       earlier)))
        (setf (fuzz-failure-shrunk failure)
              (shrink-input (fuzz-call-input call)
                            (lambda (candidate)
                              (fails-again-p operation run (replaced candidate)
                                             (with-input call candidate) kind))
                            :attempts +shrink-attempts+)
              (fuzz-failure-alone failure) alone)))
    failure))

;;; ------------------------------------------------------------------
;;; Many tools

(defstruct (fuzz-report (:constructor make-fuzz-report (seed calls-per-actor)))
  "What a fuzzing run did: the SEED and CALLS-PER-ACTOR it ran with, the
TOOLS it fuzzed, the CALLS it made, the SECONDS it took and its FAILURES."
  seed calls-per-actor (tools 0) (calls 0) (seconds 0) (failures '()))

(defun fuzz-tools-on-copies (run operations report)
  "Fuzz each of OPERATIONS as RUN says, noting what it did in REPORT.  A
tool's calls start from the scenario's records: on a fresh copy of RUN's
template, or on the one the tool before it used when its calls left every
record as they found it but the audit's entries, which is the same
records; a fresh copy costs a database and an application of its own.  A
failure is shrunk, and the next tool starts on a fresh copy."
  (loop while operations
        do (with-fuzzed-application (state run)
             (let ((pristine (call-state-fingerprint state))
                   (first t))
               (loop while operations
                     do (let ((operation (pop operations)))
                          (multiple-value-bind (made failure)
                              (fuzz-tool operation run (if first state (fresh-call-state)))
                            (setf first nil)
                            (incf (fuzz-report-tools report))
                            (incf (fuzz-report-calls report) made)
                            (when failure
                              (push (shrink-failure operation run failure)
                                    (fuzz-report-failures report))
                              (return))
                            (unless (equal pristine (records-fingerprint))
                              (return)))))))))

(defun fuzz-tools (operations &key (class 'application) scenario (actors +fuzz-actors+)
                                   (seed (fuzz-seed)) (calls (fuzz-calls)) variables
                                   (database :memory) observe)
  "Fuzz the tool of each of OPERATIONS that FUZZED-TOOL-P keeps, as
spec/testing.md 2 says: each on a fresh application of CLASS with the
records of SCENARIO, a scenario or NIL, made once and copied; CALLS inputs
made from SEED per tool and actor, as each of ACTORS and the actors
SCENARIO names; with VARIABLES, and Tun's *ISOLATED-VARIABLES*, unset
around the scenario and each tool's run.  DATABASE is :MEMORY, or :POSTGRES
for an application that needs it, whose record policies and queries only
Postgres runs: then each tool's is a fresh database on the test Postgres
server.  OBSERVE, a function, is called
after each call as FUZZ-RUN says.  Returns a FUZZ-REPORT, each failure
shrunk."
  (check-type database (member :memory :postgres))
  (let* ((actors (remove-duplicates (append actors (and scenario (scenario-actors scenario)))
                                    :test #'string= :from-end t))
         (report (make-fuzz-report seed calls))
         (start (get-internal-real-time)))
    (let ((run (make-fuzz-run class scenario actors seed calls
                              (append *isolated-variables* variables) database observe)))
      (with-connections-refused ()
        (take-connection-attempts)
        (unwind-protect
             (progn
               (make-template run)
               (fuzz-tools-on-copies run (remove-if-not #'fuzzed-tool-p operations) report))
          (drop-template run))))
    (setf (fuzz-report-failures report) (nreverse (fuzz-report-failures report))
          (fuzz-report-seconds report) (/ (- (get-internal-real-time) start)
                                          internal-time-units-per-second))
    report))

(defun shown-input (input)
  "INPUT as a report shows it: JSON, each id of a record as ‹ENTITY #N›, or
‹ENTITY #-N› counted back from the newest, -1 the newest itself."
  (to-json-string
   (resolve-input input (lambda (ref)
                          (format nil "‹~a #~:[~;-~]~d›"
                                  (entity-json-name (find-entity-class (record-ref-entity ref)))
                                  (record-ref-newest ref)
                                  (if (record-ref-newest ref)
                                      (1+ (record-ref-index ref))
                                      (record-ref-index ref)))))))

(defun failure-text (failure calls)
  "FAILURE, of a run with CALLS per tool and actor, as the report says it:
the tool, the actor, the seed, what broke, the shrunk input, and how to make
it again."
  (let* ((call (fuzz-failure-call failure))
         (shrunk (fuzz-failure-shrunk failure))
         (purpose (purpose-text call)))
    (with-output-to-string (out)
      (format out "~a, as ~a, call ~d~@[ ~a~] (seed ~d):~%  ~a~%"
              (fuzz-failure-tool failure) (fuzz-call-actor call) (fuzz-failure-index failure)
              (and (plusp (length purpose)) purpose) (fuzz-failure-seed failure)
              (fuzz-failure-problem failure))
      (cond ((null shrunk)
             (format out "  It did not fail again when replayed. Its input:~%    ~a~%"
                     (shown-input (fuzz-call-input call))))
            ((fuzz-failure-alone failure)
             (format out "  The smallest input that still fails, on the scenario's records ~
                          alone:~%    ~a~%"
                     (shown-input shrunk)))
            (t
             (format out "  The smallest input that still fails, after the ~d calls before it:~
                          ~%    ~a~%"
                     (1- (fuzz-failure-index failure)) (shown-input shrunk))))
      (format out "  ‹ENTITY #N› is the id of the record of ENTITY inserted at N, from 0, ~
                   counted round the records there are.~%  ~
                   TUN_FUZZ_SEED=~d TUN_FUZZ_CALLS=~d makes it again."
              (fuzz-failure-seed failure) calls))))

(defun fuzz-summary (report what)
  "One line on REPORT, a run on WHAT: the tools, the calls, the time, the
seed and the calls per tool and actor, and how to change them."
  (format nil "Fuzzed ~d tool~:p of ~a: ~d calls in ~,1f s, seed ~d (TUN_FUZZ_SEED), ~
               ~d per tool and actor (TUN_FUZZ_CALLS)~:[~;, ~:*~d failed~]."
          (fuzz-report-tools report) what (fuzz-report-calls report)
          (float (fuzz-report-seconds report)) (fuzz-report-seed report)
          (fuzz-report-calls-per-actor report)
          (and (fuzz-report-failures report) (length (fuzz-report-failures report)))))

(defun check-every-tool-withstands-fuzzing (operations what &key (class 'application)
                                                                  scenario variables
                                                                  (database :memory))
  "Fuzz OPERATIONS, the tools of WHAT (a name for the summary), as
FUZZ-TOOLS does, print the summary, and fail the FiveAM test for each tool
that broke what must hold."
  (let ((report (fuzz-tools operations :class class :scenario scenario :variables variables
                                       :database database)))
    (format t "~&~a~%" (fuzz-summary report what))
    (dolist (failure (fuzz-report-failures report))
      (fiveam:fail "~a" (failure-text failure (fuzz-report-calls-per-actor report))))
    (fiveam:pass)
    report))
