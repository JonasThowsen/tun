;;;; tests/sequences.lisp -- tools called in sequence (spec/testing.md 4).
;;;; A sequence is a list of steps made up from the seed, each a call of one
;;;; of the client's tools, run on one copy of the scenario's database, so
;;;; each call meets what the calls before it made, changed and removed.
;;;; After every call what fuzzing checks holds, a replayed request answers
;;;; as it first did, what a call made its get finds and what it removed its
;;;; get no longer does, and every invariant of the application holds.  A
;;;; failing sequence is shrunk to the steps that still fail.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; How much a run does

(defparameter +sequences+ 4
  "How many sequences a run makes in bin/test, unless TUN_SEQUENCES says
otherwise.")

(defparameter +sequence-steps+ 25
  "How many steps each sequence has in bin/test, unless TUN_SEQUENCE_STEPS
says otherwise.  With +SEQUENCES+, few enough that a client's generated
tests stay within 30 seconds (spec/testing.md 1).")

(defparameter +replay-chance+ 5
  "One step in this many repeats an earlier mutation, when there is one.")

(defparameter +sequence-shrink-attempts+ 200
  "The most sequences shrinking a failing one replays.")

(defun sequence-count ()
  (environment-integer "TUN_SEQUENCES" +sequences+))

(defun sequence-steps ()
  (environment-integer "TUN_SEQUENCE_STEPS" +sequence-steps+))

;;; ------------------------------------------------------------------
;;; Steps

(defstruct (sequence-step (:constructor make-sequence-step (operation actor input &optional original)))
  "One step of a sequence: OPERATION called as ACTOR, a string, with INPUT,
made up with RECORD-REFs for ids.  A replay has ORIGINAL, the earlier step
it repeats with the arguments that step sent."
  (operation nil :read-only t)
  (actor "" :type string :read-only t)
  (input nil :read-only t)
  (original nil :read-only t))

(defun replay-step-p (step)
  (and (sequence-step-original step) t))

(defun with-step-input (step input)
  (make-sequence-step (sequence-step-operation step) (sequence-step-actor step) input
                      (sequence-step-original step)))

(defun newest-refs (input)
  "INPUT with each RECORD-REF, half the time, naming one of the two records
of its entity inserted last instead, so a step often names what the steps
before it made."
  (resolve-input input (lambda (ref)
                         (if (chance 2)
                             (make-record-ref (record-ref-entity ref) (below 2) t)
                             ref))))

(defun revision-target (operation)
  "The entity whose record OPERATION's id property names when the input
also takes that record's revision, which a stale one refuses (core.md
2.1); else NIL."
  (let ((properties (schema-properties (operation-input-schema operation)))
        (references (operation-references operation)))
    (and (member "revision" properties :test #'string=)
         (gethash "id" references))))

(defun step-input (operation key)
  "A valid or edge input for OPERATION, with KEY as its request_key when it
mutates, and, three times in four, :CURRENT for a revision of the record
its id names, which the step reads when it runs (CURRENT-REVISIONS)."
  (let ((input (newest-refs (generate-input (fuzz-schema operation)
                                            :kind (pick '(:valid :valid :edge))
                                            :references (operation-references operation)))))
    (when (operation-mutating-p operation)
      (setf (gethash "request_key" input) key))
    (when (and (revision-target operation) (nth-value 1 (gethash "id" input)) (not (chance 4)))
      (setf (gethash "revision" input) :current))
    input))

(defun current-revisions (operation arguments)
  "ARGUMENTS, with ids read, their :CURRENT revision replaced by that of
the record their id names, or 1 when there is none."
  (when (eq :current (gethash "revision" arguments))
    (let ((entity (revision-target operation)))
      (setf (gethash "revision" arguments)
            (or (reading-every-record ()
                  (let ((record (fetch entity (gethash "id" arguments))))
                    (and record (jget (entity->json record) "revision"))))
                1))))
  arguments)

(defun shown-step-input (input)
  "INPUT as a report shows it (SHOWN-INPUT), a revision read when the step
runs as ‹current›."
  (if (eq :current (gethash "revision" input))
      (let ((copy (copy-object input)))
        (setf (gethash "revision" copy) "‹current›")
        (shown-input copy))
      (shown-input input)))

(defun admitting-actors (operation actors)
  "Those of ACTORS whom OPERATION's own policy admits."
  (remove-if-not (lambda (actor)
                   (actor-permits-p (parse-actor actor) (operation-policy operation)))
                 actors))

(defun shuffled (list)
  "A copy of LIST in an order chosen from *FUZZ-RANDOM-STATE*."
  (let ((vector (coerce list 'vector)))
    (loop for i from (1- (length vector)) downto 1
          do (rotatef (aref vector i) (aref vector (below (1+ i)))))
    (coerce vector 'list)))

(defun make-sequences (operations actors seed count steps)
  "COUNT sequences of STEPS steps for a run with SEED, each step a replay
of an earlier step of its sequence that mutates, one in +REPLAY-CHANCE+
when there is one, or else a call of the next tool dealt from a deck of
OPERATIONS some of ACTORS may call: shuffled from SEED, again each time it
runs out, one deck across the sequences, so every tool is dealt once
before any is dealt twice.  A step's actor and input come from a random
state of its sequence's own."
  (let ((tools (remove-if-not (lambda (operation) (admitting-actors operation actors))
                              operations))
        (deck-state (make-fuzz-random-state seed "deck"))
        (deck '()))
    (flet ((deal ()
             (when (null deck)
               (setf deck (let ((*fuzz-random-state* deck-state)) (shuffled tools))))
             (pop deck)))
      (and tools
           (loop for number from 1 to count
                 collect
                 (let ((*fuzz-random-state* (make-fuzz-random-state seed "sequence" number))
                       (made '()))
                   (dotimes (index steps (nreverse made))
                     (let ((mutations (remove-if (lambda (step)
                                                   (or (replay-step-p step)
                                                       (not (operation-mutating-p
                                                             (sequence-step-operation step)))))
                                                 made)))
                       (push (if (and mutations (chance +replay-chance+))
                                 (let ((original (pick mutations)))
                                   (make-sequence-step (sequence-step-operation original)
                                                       (sequence-step-actor original)
                                                       (sequence-step-input original) original))
                                 (let ((operation (deal)))
                                   (make-sequence-step operation
                                                       (pick (admitting-actors operation actors))
                                                       (step-input operation
                                                                   (format nil "seq-~d-~d"
                                                                           number index)))))
                             made)))))))))

;;; ------------------------------------------------------------------
;;; Gets

(defun get-tools (operations)
  "A hash table from each entity of a get among OPERATIONS to (operation
. property): a read whose only required property takes ids of its own
entity (spec/testing.md 4)."
  (let ((gets (make-hash-table :test 'eq)))
    (dolist (operation operations gets)
      (let ((property (get-tool-property operation)))
        (when (and property (not (gethash (operation-entity operation) gets)))
          (setf (gethash (operation-entity operation) gets) (cons operation property)))))))

(defun get-entity-ids (gets)
  "A hash table from each entity GETS has a get for to the ids of its
records in *APP*."
  (let ((ids (make-hash-table :test 'eq)))
    (reading-every-record ()
      (maphash (lambda (entity get)
                 (declare (ignore get))
                 (setf (gethash entity ids) (mapcar #'entity-id (select entity))))
               gets))
    ids))

;;; ------------------------------------------------------------------
;;; Running a sequence

(defstruct (sequence-run (:constructor make-sequence-run (fuzz-run gets invariants)))
  "What the steps of one sequence share as they run: the FUZZ-RUN, the GETS
(GET-TOOLS) and the INVARIANTS checked; the arguments each step that
performed a mutation SENT and its first RESULT; the ids of the records of
each entity with a get as they were after the last call; which gets refuse
an actor whatever the id (REFUSING, by tool and actor); the commit count
the invariants were last checked at; the outcome of each step (TRACE,
newest first); what was counted; and the tools its steps CALLED, those
that ANSWERED with a result and those REPLAYED, hash tables by tool."
  fuzz-run gets invariants
  (sent (make-hash-table :test 'eq))
  (results (make-hash-table :test 'eq))
  ids
  (refusing (make-hash-table :test 'equal))
  checked-commits
  (trace '())
  (calls 0) (replays 0) (gets-asked 0)
  (called (make-hash-table :test 'equal))
  (answered (make-hash-table :test 'equal))
  (replayed (make-hash-table :test 'equal)))

(define-condition sequence-problem (error)
  ((text :initarg :text :reader sequence-problem-text)
   (kind :initarg :kind :reader sequence-problem-kind
         :documentation "The kind of problem: a keyword, or (:invariant NAME) for an invariant's."))
  (:report (lambda (condition stream) (write-string (sequence-problem-text condition) stream))))

(defun sequence-problem (kind control &rest arguments)
  (error 'sequence-problem :kind kind :text (apply #'format nil control arguments)))

(defun check-invariants (sequence)
  "Check every invariant of SEQUENCE, failing at the first that breaks or
whose body signals."
  (dolist (invariant (sequence-run-invariants sequence))
    (let* ((name (invariant-name invariant))
           (breaches (handler-case (with-application (*app*) (check-invariant invariant))
                       (serious-condition (condition)
                         (sequence-problem (list :invariant-fault name)
                                           "the invariant ~(~a~) signalled: ~a"
                                           name (condition-description condition))))))
      (when breaches
        (sequence-problem (list :invariant name)
                          "the invariant ~(~a~) (~a) breaks: ~{~a~^; ~}~:[~;; …~]"
                          name (invariant-description invariant)
                          (subseq breaches 0 (min 3 (length breaches))) (> (length breaches) 3)))))
  (setf (sequence-run-checked-commits sequence) (store-commits (application-store *app*))))

(defun sequence-call (sequence operation actor arguments purpose state)
  "Call OPERATION as ACTOR with ARGUMENTS, ids read, for PURPOSE, as a
fuzzed call, and check it as one, and the invariants when it committed.
Values the outcome and the entities whose records it changed."
  (let ((call (make-fuzz-call actor arguments purpose))
        (run (sequence-run-fuzz-run sequence)))
    (let ((outcome (perform-call operation call state)))
      (incf (sequence-run-calls sequence))
      (when (fuzz-run-observe run)
        (funcall (fuzz-run-observe run) operation call outcome))
      (multiple-value-bind (problem kind changed) (call-problem operation call outcome state)
        (when problem
          (sequence-problem kind "~a ~a~@[ ~a~]: ~a" (operation-tool operation) actor
                            (let ((text (purpose-text call))) (and (plusp (length text)) text))
                            problem))
        (unless (eql (store-commits (application-store *app*)) (sequence-run-checked-commits sequence))
          (check-invariants sequence))
        (values outcome changed)))))

(defun get-refuses-p (sequence get actor state)
  "True when GET, (operation . property), refuses ACTOR whatever the id:
its policy refuses the actor, or it answers forbidden for an id that names
nothing, asked once per sequence."
  (destructuring-bind (operation . property) get
    (or (not (actor-permits-p (parse-actor actor) (operation-policy operation)))
        (let ((key (cons (operation-tool operation) actor)))
          (multiple-value-bind (refuses known) (gethash key (sequence-run-refusing sequence))
            (if known
                refuses
                (setf (gethash key (sequence-run-refusing sequence))
                      (eq :forbidden
                          (outcome-code (sequence-call sequence operation actor
                                                       (jobj property (missing-id (operation-entity operation)))
                                                       :call state))))))))))

(defun check-gets (sequence actor state)
  "Ask each get of SEQUENCE, as ACTOR, for the records of its entity made
since the ids were last taken that ACTOR reaches, and for those removed
since; fail when a made one is not found or a removed one is.  Then take
the ids again."
  (let ((before (sequence-run-ids sequence))
        (after (get-entity-ids (sequence-run-gets sequence))))
    (setf (sequence-run-ids sequence) after)
    (maphash
     (lambda (entity get)
       (let* ((old (gethash entity before))
              (new (gethash entity after))
              (made (set-difference new old :test #'string=))
              (removed (set-difference old new :test #'string=)))
         (when (and (or made removed) (not (get-refuses-p sequence get actor state)))
           (destructuring-bind (operation . property) get
             (flet ((ask (id)
                      (incf (sequence-run-gets-asked sequence))
                      (outcome-code (sequence-call sequence operation actor (jobj property id)
                                                   :call state))))
               (dolist (id made)
                 (when (and (reaches-p entity id actor) (eq :not-found (ask id)))
                   (sequence-problem :not-found-after-made
                                     "~a answered not_found for ~a, which this step made ~
                                      and ~a reaches (spec/testing.md 4)"
                                     (operation-tool operation) id actor)))
               (dolist (id removed)
                 (unless (eq :not-found (ask id))
                   (sequence-problem :found-after-removed
                                     "~a did not answer not_found for ~a, which this step ~
                                      removed (spec/testing.md 4)"
                                     (operation-tool operation) id))))))))
     (sequence-run-gets sequence))))

(defun receipt-of (actor tool key)
  "The receipt ACTOR's call of TOOL with KEY left in *APP*, or NIL."
  (reading-every-record ()
    (select-one 'receipt :where `(:and (:= "actor" ,(actor-string (parse-actor actor)))
                                       (:= "tool" ,tool)
                                       (:= "request_key" ,key)))))

(defun as-written (result)
  "RESULT, a tool's, as its caller reads it: written as JSON and parsed."
  (parse-json (to-json-string result)))

(defun json-equal (a b)
  "True when A and B, parsed JSON, are the same value: objects with the same
keys in any order."
  (cond ((and (hash-table-p a) (hash-table-p b))
         (and (= (hash-table-count a) (hash-table-count b))
              (loop for key being the hash-keys of a using (hash-value value)
                    always (multiple-value-bind (other present) (gethash key b)
                             (and present (json-equal value other))))))
        ((and (stringp a) (stringp b)) (string= a b))
        ((and (vectorp a) (vectorp b))
         (and (= (length a) (length b)) (every #'json-equal a b)))
        ((and (numberp a) (numberp b)) (= a b))
        (t (equal a b))))

(defun replay-differences (first replay kept)
  "The keys of FIRST, a mutation's first result, that REPLAY, its replay's,
answers otherwise, as spec/testing.md 4 compares them: a key KEPT, what
the receipt holds, lacks is the live view's and is not compared, nor is a
value the receipt holds as null that FIRST showed, shown once.  Values T
when the results are not objects and differ."
  (if (not (and (hash-table-p first) (hash-table-p replay) (hash-table-p kept)))
      (not (json-equal first replay))
      (let ((keys (remove-duplicates (append (jkeys first) (jkeys replay)) :test #'string=)))
        (loop for key in keys
              for (kept-value present) = (multiple-value-list (gethash key kept))
              unless (or (not present)
                         (and (eq kept-value :null) (not (eq (gethash key first :null) :null)))
                         (json-equal (gethash key first :null) (gethash key replay :null)))
                collect key))))

(defun perform-replay (sequence step state)
  "Repeat STEP's original with the arguments it sent, and fail unless it
answers as the first call did and changes nothing (spec/testing.md 4).
Nothing happens when the original performed no mutation."
  (let* ((original (sequence-step-original step))
         (arguments (gethash original (sequence-run-sent sequence)))
         (operation (sequence-step-operation step))
         (actor (sequence-step-actor step)))
    (if (null arguments)
        "not made: the step it repeats performed no mutation"
        (multiple-value-bind (outcome changed)
            (sequence-call sequence operation actor arguments :call state)
          (incf (sequence-run-replays sequence))
          (setf (gethash (operation-tool operation) (sequence-run-replayed sequence)) t)
          (let ((first (gethash original (sequence-run-results sequence)))
                (receipt (receipt-of actor (operation-tool operation)
                                     (gethash "request_key" arguments))))
            (cond ((not (eq (outcome-kind outcome) :result))
                   (sequence-problem :replay "the replay of ~a answered ~a, not the result it ~
                                              first gave (core.md §3.7)"
                                     (operation-tool operation) (outcome-text outcome)))
                  (changed
                   (sequence-problem :replay "the replay of ~a changed records of ~{~a~^, ~} ~
                                              (core.md §3.7)"
                                     (operation-tool operation) changed))
                  ((and receipt (receipt-redacted receipt)) "with a result, its receipt redacted")
                  (t (let ((differences (replay-differences first (as-written (outcome-result outcome))
                                                            (if receipt
                                                                (parse-json (receipt-result receipt))
                                                                first))))
                       (when differences
                         (sequence-problem :replay "the replay of ~a answered otherwise than it ~
                                                    first did~:[~;, in ~:*~{~a~^, ~}~] (core.md §3.7)"
                                           (operation-tool operation)
                                           (and (listp differences) differences)))
                       "with its first result"))))))))

(defun perform-step (sequence step state)
  "Perform STEP of SEQUENCE: a call, or for a tool that asks for
confirmation the ask and the confirming call, or a replay; then check the
gets.  Values how it ended, as the report says it."
  (if (replay-step-p step)
      (perform-replay sequence step state)
      (let* ((operation (sequence-step-operation step))
             (actor (sequence-step-actor step))
             (arguments (current-revisions operation
                                           (resolve-input (sequence-step-input step) #'record-ref-id)))
             (commits (store-commits (application-store *app*)))
             (outcome
               (if (not (operation-confirm-p operation))
                   (sequence-call sequence operation actor arguments :call state)
                   (progn
                     (remhash actor (call-state-tokens state))
                     (let ((asked (sequence-call sequence operation actor arguments :ask state)))
                       (if (gethash actor (call-state-tokens state))
                           (sequence-call sequence operation actor arguments :confirm state)
                           asked))))))
        (setf (gethash (operation-tool operation) (sequence-run-called sequence)) t)
        (when (eq (outcome-kind outcome) :result)
          (setf (gethash (operation-tool operation) (sequence-run-answered sequence)) t))
        (when (and (eq (outcome-kind outcome) :result) (operation-mutating-p operation)
                   (not (and (hash-table-p (outcome-result outcome))
                             (jget (outcome-result outcome) "confirmation_required"))))
          (setf (gethash step (sequence-run-sent sequence)) arguments
                (gethash step (sequence-run-results sequence)) (as-written (outcome-result outcome))))
        (when (and (eq (outcome-kind outcome) :result)
                   (not (eql commits (store-commits (application-store *app*)))))
          (check-gets sequence actor state))
        (outcome-text outcome))))

(defstruct (sequence-failure (:constructor make-sequence-failure (number steps index problem kind)))
  "A sequence that broke what must hold: the NUMBERth of its run, its
STEPS, the INDEXth of them, from 1, the one that failed (0 before the
first), PROBLEM, the sentence, and KIND.  Shrinking fills in SHRUNK, the
steps that still fail, and TRACE, how each of them ended; NIL when it did
not fail again."
  number steps index problem kind shrunk trace)

(defun run-sequence (run steps &key gets)
  "Run STEPS on a fresh application of RUN's, checking its invariants and
GETS.  Values NIL, or the index of the step that failed (0 when the
invariants broke before the first), the SEQUENCE-PROBLEM; and the
SEQUENCE-RUN, its trace oldest first."
  (with-fuzzed-application (state run)
    (let ((sequence (make-sequence-run run gets (application-invariants *app*))))
      (setf (sequence-run-ids sequence) (get-entity-ids gets))
      (let ((index 0))
        (handler-case
            (progn
              (check-invariants sequence)
              (dolist (step steps)
                (incf index)
                (push (perform-step sequence step state) (sequence-run-trace sequence)))
              (setf (sequence-run-trace sequence) (nreverse (sequence-run-trace sequence)))
              (values nil nil sequence))
          (sequence-problem (problem)
            (push "failed" (sequence-run-trace sequence))
            (setf (sequence-run-trace sequence) (nreverse (sequence-run-trace sequence)))
            (values index problem sequence)))))))

;;; ------------------------------------------------------------------
;;; Shrinking

(defun without-steps (steps dropped)
  "STEPS without those in DROPPED, nor the replays of a step dropped."
  (remove-if (lambda (step)
               (or (member step dropped)
                   (and (replay-step-p step) (member (sequence-step-original step) dropped))))
             steps))

(defun shrink-sequence (run failure gets)
  "FAILURE with its steps shrunk: the steps after the failing one dropped,
then halves, quarters and so on down to single steps, each dropped while
the rest still fails with the same kind of problem, replayed on a fresh
copy each time, at most +SEQUENCE-SHRINK-ATTEMPTS+ replays; then the
failing step's input shrunk as fuzzing shrinks one, at most
+SHRINK-ATTEMPTS+ replays more."
  (let ((kind (sequence-failure-kind failure))
        (tried 0)
        (limit +sequence-shrink-attempts+))
    (labels ((fails-p (steps)
               (and (< tried limit)
                    (progn (incf tried)
                           (let ((problem (nth-value 1 (run-sequence run steps :gets gets))))
                             (and problem (equal kind (sequence-problem-kind problem))))))))
      (let ((steps (subseq (sequence-failure-steps failure) 0 (sequence-failure-index failure))))
        (when (fails-p steps)
          (loop with size = (max 1 (floor (length steps) 2))
                do (let ((dropped-any nil))
                     (loop for start from 0 below (length steps) by size
                           do (let* ((chunk (subseq steps start (min (length steps) (+ start size))))
                                     (candidate (without-steps steps chunk)))
                                (when (and candidate (< (length candidate) (length steps))
                                           (fails-p candidate))
                                  (setf steps candidate dropped-any t)
                                  (return))))
                     (cond (dropped-any)
                           ((= size 1) (return))
                           (t (setf size (max 1 (floor size 2)))))))
          (let ((last (car (last steps))))
            (setf limit (+ tried +shrink-attempts+))
            (unless (replay-step-p last)
              (let ((input (shrink-input (sequence-step-input last)
                                         (lambda (candidate)
                                           (fails-p (append (butlast steps)
                                                            (list (with-step-input last candidate)))))
                                         :attempts +shrink-attempts+)))
                (setf steps (append (butlast steps) (list (with-step-input last input)))))))
          ;; Once more, for how each step ends and what the last breaks.
          (multiple-value-bind (index problem sequence) (run-sequence run steps :gets gets)
            (declare (ignore index))
            (setf (sequence-failure-shrunk failure) steps
                  (sequence-failure-trace failure) (sequence-run-trace sequence))
            (when problem
              (setf (sequence-failure-problem failure) (sequence-problem-text problem)))))))
    failure))

;;; ------------------------------------------------------------------
;;; A run

(defstruct (sequence-report (:constructor make-sequence-report (seed sequences steps)))
  "What a sequence run did: the SEED, how many SEQUENCES of how many STEPS,
the CALLS, REPLAYS and GETS it made, the INVARIANTS it checked, the SECONDS
it took and its FAILURES; the TOOLS it could call and the MUTATING ones
among them, by name, and those it CALLED, those that ANSWERED with a
result and those it REPLAYED, hash tables by tool."
  seed sequences steps (calls 0) (replays 0) (gets 0) (invariants 0) (seconds 0)
  (failures '()) (tools '()) (mutating '())
  (called (make-hash-table :test 'equal))
  (answered (make-hash-table :test 'equal))
  (replayed (make-hash-table :test 'equal)))

(defun merge-tools (into from)
  (maphash (lambda (tool value) (setf (gethash tool into) value)) from))

(defun call-tools-in-sequence (operations &key (class 'application) scenario
                                               (actors +fuzz-actors+) (seed (fuzz-seed))
                                               (sequences (sequence-count))
                                               (steps (sequence-steps))
                                               variables (database :memory) observe)
  "Call the tools of OPERATIONS that fuzzing calls in SEQUENCES sequences of
STEPS steps each, as spec/testing.md 4 says: each on a fresh copy of a
database the records of SCENARIO fill, made as FUZZ-TOOLS makes it, as each
of ACTORS and the actors SCENARIO names, checking every invariant of the
application.  The run stops at the first sequence that fails, which is
shrunk.  OBSERVE is called after each call as FUZZ-RUN says.  Returns a
SEQUENCE-REPORT."
  (check-type database (member :memory :postgres))
  (let* ((actors (remove-duplicates (append actors (and scenario (scenario-actors scenario)))
                                    :test #'string= :from-end t))
         (operations (remove-if-not #'fuzzed-tool-p operations))
         (callable (remove-if-not (lambda (operation) (admitting-actors operation actors))
                                  operations))
         (gets (get-tools operations))
         (report (make-sequence-report seed sequences steps))
         (start (get-internal-real-time))
         (run (make-fuzz-run class scenario actors seed 0
                             (append *isolated-variables* variables) database observe)))
    (setf (sequence-report-tools report) (mapcar #'operation-tool callable)
          (sequence-report-mutating report) (mapcar #'operation-tool
                                                    (remove-if-not #'operation-mutating-p callable)))
    (with-connections-refused ()
      (take-connection-attempts)
      (unwind-protect
           (progn
             (make-template run)
             (progn
               (loop for made in (make-sequences callable actors seed sequences steps)
                     for number from 1
                     do (multiple-value-bind (index problem sequence)
                              (run-sequence run made :gets gets)
                            (setf (sequence-report-invariants report)
                                  (length (sequence-run-invariants sequence)))
                            (incf (sequence-report-calls report) (sequence-run-calls sequence))
                            (incf (sequence-report-replays report) (sequence-run-replays sequence))
                            (incf (sequence-report-gets report) (sequence-run-gets-asked sequence))
                            (merge-tools (sequence-report-called report) (sequence-run-called sequence))
                            (merge-tools (sequence-report-answered report)
                                         (sequence-run-answered sequence))
                            (merge-tools (sequence-report-replayed report)
                                         (sequence-run-replayed sequence))
                            (when problem
                              (let ((failure (make-sequence-failure
                                              number made index (sequence-problem-text problem)
                                              (sequence-problem-kind problem))))
                                (push (if (zerop index)
                                          failure
                                          (shrink-sequence run failure gets))
                                      (sequence-report-failures report)))
                              (return))))))
        (drop-template run)))
    (setf (sequence-report-seconds report)
          (/ (- (get-internal-real-time) start) internal-time-units-per-second))
    report))

;;; ------------------------------------------------------------------
;;; The report

(defun step-text (step steps)
  "STEP, one of STEPS, as a report lists it."
  (if (replay-step-p step)
      (format nil "a replay of step ~d" (1+ (position (sequence-step-original step) steps)))
      (format nil "~a as ~a: ~a" (operation-tool (sequence-step-operation step))
              (sequence-step-actor step) (shown-step-input (sequence-step-input step)))))

(defun sequence-failure-text (failure report what)
  "FAILURE of REPORT, a run on WHAT, as the report says it."
  (with-output-to-string (out)
    (format out "Sequence ~d of ~a (seed ~d):~%  ~a~%" (sequence-failure-number failure) what
            (sequence-report-seed report) (sequence-failure-problem failure))
    (cond ((zerop (sequence-failure-index failure))
           (format out "  It broke on the scenario's records, before the first step.~%"))
          ((null (sequence-failure-shrunk failure))
           (format out "  It did not fail again when replayed. It failed at step ~d of:~%"
                   (sequence-failure-index failure))
           (let ((steps (sequence-failure-steps failure)))
             (loop for step in (subseq steps 0 (sequence-failure-index failure))
                   for number from 1
                   do (format out "    ~d. ~a~%" number (step-text step steps)))))
          (t
           (let ((steps (sequence-failure-shrunk failure)))
             (format out "  The fewest steps that still fail, from step ~d of ~d:~%"
                     (sequence-failure-index failure) (length (sequence-failure-steps failure)))
             (loop for step in steps
                   for number from 1
                   for ended in (sequence-failure-trace failure)
                   do (format out "    ~d. ~a~%       ~a~%" number (step-text step steps) ended)))))
    (format out "  ‹ENTITY #N› is the id of the record of ENTITY inserted at N, from 0, ~
                 ‹ENTITY #-N› the Nth back from the newest, each counted round the records ~
                 there are.~%  TUN_FUZZ_SEED=~d TUN_SEQUENCES=~d TUN_SEQUENCE_STEPS=~d makes it again."
            (sequence-report-seed report) (sequence-report-sequences report)
            (sequence-report-steps report))))

(defun tools-not-in (tools table)
  (remove-if (lambda (tool) (gethash tool table)) tools))

(defun sequence-summary (report what)
  "What REPORT, a run on WHAT, did, as the test says it: a line, then the
tools it never called and those that never answered with a result."
  (let ((tools (sequence-report-tools report)))
    (format nil "Called the tools of ~a in ~d sequence~:p of ~d steps: ~d calls (~d replays, ~d gets) ~
                 in ~,1f s, seed ~d (TUN_FUZZ_SEED, TUN_SEQUENCES, TUN_SEQUENCE_STEPS); ~
                 ~d of ~d tools called, ~d of ~d mutating ones replayed; ~d invariant~:p checked~
                 ~:[~;; ~:*~d failed~].~
                 ~@[~%  Never called: ~{~a~^, ~}.~]~@[~%  Never answered with a result: ~{~a~^, ~}.~]"
            what (sequence-report-sequences report) (sequence-report-steps report)
            (sequence-report-calls report) (sequence-report-replays report)
            (sequence-report-gets report) (float (sequence-report-seconds report))
            (sequence-report-seed report)
            (hash-table-count (sequence-report-called report)) (length tools)
            (hash-table-count (sequence-report-replayed report))
            (length (sequence-report-mutating report))
            (sequence-report-invariants report)
            (and (sequence-report-failures report) (length (sequence-report-failures report)))
            (tools-not-in tools (sequence-report-called report))
            (tools-not-in (remove-if-not (lambda (tool) (gethash tool (sequence-report-called report)))
                                         tools)
                          (sequence-report-answered report)))))

(defun check-tools-called-in-sequence (operations what &rest options)
  "Run CALL-TOOLS-IN-SEQUENCE on OPERATIONS, the tools of WHAT (a name for
the summary), with OPTIONS, print the summary, and fail the FiveAM test for
each sequence that broke what must hold."
  (let ((report (apply #'call-tools-in-sequence operations options)))
    (format t "~&~a~%" (sequence-summary report what))
    (dolist (failure (sequence-report-failures report))
      (fiveam:fail "~a" (sequence-failure-text failure report what)))
    (fiveam:pass)
    report))
