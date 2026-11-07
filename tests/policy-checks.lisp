;;;; tests/policy-checks.lisp -- every tool keeps to the record policies
;;;; (spec/testing.md 3).  For each tool that takes ids of an entity with a
;;;; record policy, and each actor, a record the actor's policy hides must
;;;; be answered as one that does not exist, and a get must reach the
;;;; records the policy admits.  The calls go as fuzzed calls do
;;;; (tests/fuzzing.lisp), and each is checked as one is.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +policy-input-attempts+ 4
  "How many valid inputs a pair is made with, at most, while the call with
the id that names nothing is refused as invalid_input.")

(defparameter +admitted-records-asked+ 3
  "How many of the records an actor reaches a get is asked for.")

;;; ------------------------------------------------------------------
;;; Which tools, and which of their properties

(defun top-level-path-p (path)
  (not (find-if (lambda (char) (member char '(#\. #\[))) path)))

(defun policy-references (operation)
  "The top-level properties of OPERATION's input that take ids of an entity
with a record policy, as a list of (property . class-name), in the order of
its schema."
  (let ((references (operation-references operation)))
    (loop for name in (schema-properties (operation-input-schema operation))
          for entity = (gethash name references)
          when (and entity (top-level-path-p name)
                    (entity-record-policy (find-entity-class entity)))
            collect (cons name entity))))

(defun get-property (operation)
  "The property of OPERATION, a read, that takes ids of its own entity when
that is its only required property and the entity has a record policy;
else NIL (spec/testing.md 3, a get agrees)."
  (let ((required (required-properties (operation-input-schema operation)))
        (entity (operation-entity operation)))
    (and (eq (operation-kind operation) :read)
         entity
         (= 1 (length required))
         (eq entity (cdr (assoc (first required) (policy-references operation)
                                :test #'string=)))
         (first required))))

(defun policy-checked-p (operation)
  "True for a tool this test calls: a fuzzed one with a property that takes
ids of an entity with a record policy."
  (and (fuzzed-tool-p operation) (policy-references operation) t))

;;; ------------------------------------------------------------------
;;; What a run found

(defstruct (policy-report (:constructor make-policy-report (seed)))
  "What a run of this test did: the SEED it made inputs from, the TOOLS it
called, the CALLS it made, the pairs it COMPARED (PAST-VALIDATION of them
with a first call not refused as invalid_input), those it SKIPPED because
the tool's policy refuses the actor, those NOT-MADE because a required id
could not name a record the actor reaches, the GETS it asked, its SECONDS
and its FAILURES."
  seed (tools 0) (calls 0) (compared 0) (past-validation 0) (skipped 0) (not-made 0)
  (gets 0) (seconds 0) (failures '()))

(defstruct (policy-failure (:constructor make-policy-failure (tool actor seed problem input)))
  "A call of TOOL as ACTOR, in the run with SEED, that broke what must hold:
PROBLEM, the sentence saying what, and INPUT, the input it was called with."
  tool actor seed problem input)

(defun policy-failure-text (failure)
  (format nil "~a, as ~a (seed ~d):~%  ~a~%  Its input:~%    ~a~%  ~
               ‹ENTITY #N› is the id of the record of ENTITY inserted at N, from 0.~%  ~
               TUN_FUZZ_SEED=~d makes it again."
          (policy-failure-tool failure) (policy-failure-actor failure)
          (policy-failure-seed failure) (policy-failure-problem failure)
          (shown-input (policy-failure-input failure)) (policy-failure-seed failure)))

;;; ------------------------------------------------------------------
;;; A call

(defvar *policy-report* nil "The report of the run under way.")

(defun policy-call (operation actor input purpose state)
  "Call OPERATION's tool as ACTOR with INPUT for PURPOSE, as a fuzzed call
is, and check it as one.  Values the outcome; a call that breaks what must
hold ends the tool's calls (THROW to POLICY-FAILURE)."
  (let* ((call (make-fuzz-call actor input purpose))
         (outcome (perform-call operation call state)))
    (incf (policy-report-calls *policy-report*))
    (multiple-value-bind (problem kind) (call-problem operation call outcome state)
      (declare (ignore kind))
      (when problem
        (throw 'policy-failure (list actor problem input))))
    outcome))

(defun final-outcome (operation actor input state)
  "The outcome of calling OPERATION's tool as ACTOR with INPUT: of the call
itself, or, for a tool that asks for confirmation, of the call that
confirms it when the ask gave a token, as fuzzing confirms one."
  (if (not (operation-confirm-p operation))
      (policy-call operation actor input :call state)
      (progn
        (remhash actor (call-state-tokens state))
        (let ((asked (policy-call operation actor input :ask state)))
          (if (gethash actor (call-state-tokens state))
              (policy-call operation actor input :confirm state)
              asked)))))

(defun outcome-text (outcome)
  (if (eq (outcome-kind outcome) :result)
      "with a result"
      (json-name-of (outcome-code outcome))))

(defun policy-problem (actor control format &rest arguments)
  (throw 'policy-failure (list actor (apply #'format nil format arguments) control)))

;;; ------------------------------------------------------------------
;;; A hidden record is a missing one

(defun record-index (class-name actor test)
  "The insertion index, among every record of CLASS-NAME, of the first that
ACTOR reaches when TEST is :REACHED, or does not when it is :HIDDEN; NIL
when there is none."
  (let ((reached (record-ids class-name actor)))
    (position-if (lambda (id)
                   (eq (and (member id reached :test #'string=) t) (eq test :reached)))
                 (record-ids class-name))))

(defun pair-input (operation references property actor)
  "A valid input for OPERATION without request_key, its ids at the top
level other than PROPERTY's naming the first record ACTOR reaches of their
entity, or left out when optional and it reaches none; NIL when a required
one cannot be filled.  REFERENCES is OPERATION-REFERENCES."
  (let ((input (without-request-key
                (generate-input (fuzz-schema operation) :kind :valid :references references)))
        (required (required-properties (operation-input-schema operation))))
    (loop for path being the hash-keys of references using (hash-value entity)
          when (and (top-level-path-p path) (string/= path property) (nth-value 1 (gethash path input)))
            do (let ((index (record-index entity actor :reached)))
                 (cond (index (setf (gethash path input) (make-record-ref entity index)))
                       ((member path required :test #'string=) (return-from pair-input nil))
                       (t (remhash path input)))))
    input))

(defun with-property (input property value)
  (let ((copy (copy-object input)))
    (setf (gethash property copy) value)
    copy))

(defun compare-pair (operation references property entity actor state)
  "Call OPERATION's tool as ACTOR with an id of ENTITY that names nothing
in PROPERTY, then with the first record of ENTITY the actor's policy hides,
and fail unless both end alike (spec/testing.md 3)."
  (let ((hidden (record-index entity actor :hidden))
        (report *policy-report*))
    (when hidden
      (loop for attempt from 1 to +policy-input-attempts+
            for input = (pair-input operation references property actor)
            do (unless input
                 (incf (policy-report-not-made report))
                 (return))
               (let* ((missing-input (with-property input property (missing-id entity)))
                      (missing (final-outcome operation actor missing-input state)))
                 (when (or (not (eq (outcome-code missing) :invalid-input))
                           (= attempt +policy-input-attempts+))
                   (let* ((hidden-input (with-property input property
                                          (make-record-ref entity hidden)))
                          (shown (final-outcome operation actor hidden-input state)))
                     (incf (policy-report-compared report))
                     (unless (eq (outcome-code missing) :invalid-input)
                       (incf (policy-report-past-validation report)))
                     (unless (and (eq (outcome-kind missing) (outcome-kind shown))
                                  (eq (outcome-code missing) (outcome-code shown)))
                       (policy-problem actor hidden-input
                                       "~a answered ~a for ~a, which ~a's record policy hides, ~
                                        but ~a for ~a, which names nothing (store.md §6): ~
                                        the answers tell the caller the record is there"
                                       property (outcome-text shown)
                                       (shown-input (make-record-ref entity hidden)) actor
                                       (outcome-text missing) (missing-id entity)))
                     (return))))))))

;;; ------------------------------------------------------------------
;;; A get agrees

(defun check-get (operation property actor state)
  "Ask OPERATION's tool, a get by PROPERTY, as ACTOR for an id that names
nothing and then for the first records ACTOR reaches, and fail when one
of those is answered not_found (spec/testing.md 3)."
  (let* ((entity (operation-entity operation))
         (missing (policy-call operation actor (jobj property (missing-id entity)) :call state)))
    (unless (eq (outcome-code missing) :forbidden)
      (let ((reached (record-ids entity actor))
            (all (record-ids entity)))
        (loop for id in reached
              repeat +admitted-records-asked+
              do (let* ((input (jobj property (make-record-ref entity
                                                                (position id all :test #'string=))))
                        (outcome (policy-call operation actor input :call state)))
                   (incf (policy-report-gets *policy-report*))
                   (when (eq (outcome-code outcome) :not-found)
                     (policy-problem actor input
                                     "it answered not_found for ~a, which ~a's record policy ~
                                      admits (store.md §6)"
                                     (shown-input (jget input property)) actor))))))))

;;; ------------------------------------------------------------------
;;; The run

(defun policy-steps (operation actors seed)
  "The steps of OPERATION's calls, each a function of a CALL-STATE: a get
by each actor its policy admits, and a pair for each such actor and each
property that takes ids of an entity with a record policy.  The steps
share one random state, made from SEED and the tool, and run in order."
  (let ((random-state (make-fuzz-random-state seed "policy" (operation-tool operation)))
        (references (operation-references operation))
        (get-property (get-property operation))
        (steps '()))
    (dolist (actor actors)
      (if (not (actor-permits-p (parse-actor actor) (operation-policy operation)))
          (incf (policy-report-skipped *policy-report*)
                (length (policy-references operation)))
          (let ((actor actor))
            (when get-property
              (push (lambda (state) (check-get operation get-property actor state)) steps))
            (loop for (property . entity) in (policy-references operation)
                  do (let ((property property) (entity entity))
                       (push (lambda (state)
                               (let ((*fuzz-random-state* random-state))
                                 (compare-pair operation references property entity actor state)))
                             steps))))))
    (nreverse steps)))

(defun run-policy-steps (run operations)
  "Run the steps of each of OPERATIONS on copies of RUN's template: one copy
for as long as no call has changed a record other than the audit's
entries, a fresh one before the next step once one has.  A tool's steps
end at its first failure, which is noted in *POLICY-REPORT*."
  (let ((work (loop for operation in operations
                    for steps = (policy-steps operation (fuzz-run-actors run) (fuzz-run-seed run))
                    when steps collect (cons operation steps)))
        (report *policy-report*))
    (setf (policy-report-tools report) (length work))
    (loop while work
          do (with-fuzzed-application (state run)
               (let ((pristine (call-state-fingerprint state)))
                 (loop
                   (let* ((entry (first work))
                          (operation (car entry)))
                     (cond ((null work) (return))
                           ((null (cdr entry)) (pop work))
                           ;; A call changed a record: the next step starts
                           ;; on a fresh copy.
                           ((not (equal pristine (call-state-fingerprint state))) (return))
                           (t (let ((failure (catch 'policy-failure
                                               (funcall (pop (cdr entry)) state)
                                               nil)))
                                (when failure
                                  (destructuring-bind (actor problem input) failure
                                    (push (make-policy-failure (operation-tool operation) actor
                                                               (fuzz-run-seed run) problem input)
                                          (policy-report-failures report)))
                                  (pop work))))))))))))

(defun check-record-policies-in-tools (operations &key (class 'application) scenario
                                                       (actors +fuzz-actors+) (seed (fuzz-seed))
                                                       variables)
  "Call the tools of OPERATIONS that take ids of an entity with a record
policy, as spec/testing.md 3 says, on copies of a Postgres database the
records of SCENARIO fill, as each of ACTORS and the actors SCENARIO names,
with VARIABLES and Tun's *ISOLATED-VARIABLES* unset.  Returns a
POLICY-REPORT."
  (let* ((actors (remove-duplicates (append actors (and scenario (scenario-actors scenario)))
                                    :test #'string= :from-end t))
         (*policy-report* (make-policy-report seed))
         (start (get-internal-real-time))
         (operations (remove-if-not #'policy-checked-p operations)))
    (when operations
      (let ((run (make-fuzz-run class scenario actors seed 0
                                (append *isolated-variables* variables) :postgres nil)))
        (with-connections-refused ()
          (take-connection-attempts)
          (unwind-protect
               (progn (make-template run)
                      (run-policy-steps run operations))
            (drop-template run)))))
    (setf (policy-report-failures *policy-report*) (nreverse (policy-report-failures *policy-report*))
          (policy-report-seconds *policy-report*) (/ (- (get-internal-real-time) start)
                                                    internal-time-units-per-second))
    *policy-report*))

(defun policy-summary (report what)
  (if (zerop (policy-report-tools report))
      (format nil "No tool of ~a takes ids of an entity with a record policy: ~
                   nothing to check." what)
      (format nil "Checked the record policies in ~d tool~:p of ~a: ~d calls in ~,1f s, seed ~d; ~
                   ~d pair~:p compared, ~d past input validation; ~d skipped for the tool's ~
                   policy; ~d could not be made; ~d get~:p~:[~;; ~:*~d failed~]."
              (policy-report-tools report) what (policy-report-calls report)
              (float (policy-report-seconds report)) (policy-report-seed report)
              (policy-report-compared report) (policy-report-past-validation report)
              (policy-report-skipped report) (policy-report-not-made report)
              (policy-report-gets report)
              (and (policy-report-failures report) (length (policy-report-failures report))))))

(defun check-every-tool-keeps-to-the-record-policies (operations what &rest options)
  "Run CHECK-RECORD-POLICIES-IN-TOOLS on OPERATIONS, the tools of WHAT (a
name for the summary), with OPTIONS, print the summary, and fail the FiveAM
test for each tool that broke what must hold."
  (let ((report (apply #'check-record-policies-in-tools operations options)))
    (format t "~&~a~%" (policy-summary report what))
    (dolist (failure (policy-report-failures report))
      (fiveam:fail "~a" (policy-failure-text failure)))
    (fiveam:pass)
    report))
