;;;; tests/sequence-tests.lisp -- tools called in sequence (spec/testing.md
;;;; 4): Tun's own tools, core's and the modules', called in sequence as a
;;;; client's are, with their invariants; and the sequence test itself, on
;;;; probe tools whose defects a test plants: it finds what only a sequence
;;;; reaches, a get that does not find what a create made or still finds
;;;; what a removal took, a replay that performs again and a broken
;;;; invariant, and shrinks each to the steps that still fail.

(in-package #:tun.tests)

(def-suite sequences :in core)
(in-suite sequences)

;;; ------------------------------------------------------------------
;;; Tun's own tools, in suites of their own that bin/test runs at once

(defparameter +tun-sequences+ 8
  "How many sequences Tun's own tools are called in, unless TUN_SEQUENCES
says otherwise: more than a client's default, as Tun's suite has the time.")

(defparameter +tun-sequence-steps+ 40
  "How many steps each has, unless TUN_SEQUENCE_STEPS says otherwise.")

(defun check-tun-tools-in-sequence (modulep what)
  "Call Tun's tools whose module MODULEP keeps in sequence, as a client's
are, from the scenario fuzz-records."
  (check-tools-called-in-sequence
   (remove-if-not (lambda (operation)
                    (and (tun-operation-p operation)
                         (funcall modulep (operation-module operation))))
                  (all-operations))
   what :scenario (find-scenario "fuzz-records" :package "TUN.TESTS")
        :sequences (environment-integer "TUN_SEQUENCES" +tun-sequences+)
        :steps (environment-integer "TUN_SEQUENCE_STEPS" +tun-sequence-steps+)))

(def-suite sequences-core :in core)
(in-suite sequences-core)

(test core-tools-called-in-sequence-keep-the-invariants
  (check-tun-tools-in-sequence (lambda (module) (string= module "core")) "Tun's core"))

(def-suite sequences-modules :in core)
(in-suite sequences-modules)

(test module-tools-called-in-sequence-keep-the-invariants
  (check-tun-tools-in-sequence (lambda (module) (string/= module "core")) "Tun's modules"))

(in-suite sequences)

;;; ------------------------------------------------------------------
;;; Probe tools: tasks, each perhaps part of another, which a test's
;;; planted defects (*PLANTED-DEFECTS*, tests/fuzz-tests.lisp) break

(define-entity seq-task (:label "Sequence task" :id-prefix "sqt" :table "seq_tasks")
  ((title :type (string :min 1 :max 200) :required t :label "Title")
   (parent-id :type (id seq-task) :label "Part of")
   (closed :type boolean :input nil :label "Closed")))

(defvar *seq-task-cache* nil
  "What the probe get keeps between calls while a defect asks it to: a hash
table from id to the task as it read it, and :IDS, the ids there were at
its first call.")

(define-operation seq-tasks-create ((:draft seq-task))
    (:entity seq-task :kind :create :policy :employee :title "Add a task (sequence probe)")
  (when (seq-task-parent-id seq-task)
    (fetch! 'seq-task (seq-task-parent-id seq-task)))
  (insert seq-task))

(define-operation seq-tasks-get ((id :type (id seq-task) :required t :label "Task"))
    (:entity seq-task :kind :read :policy :viewer :title "A task (sequence probe)")
  (let ((cache *seq-task-cache*))
    (cond ((and (member :stale-get *planted-defects*) cache)
           ;; It looks only among the tasks there were at its first call.
           (unless (gethash :ids cache)
             (setf (gethash :ids cache) (mapcar #'entity-id (select 'seq-task))))
           (if (member id (gethash :ids cache) :test #'equal)
               (fetch! 'seq-task id)
               (fail :not-found "No such task")))
          ((and (member :cached-get *planted-defects*) cache)
           ;; It keeps what it read, and answers from that.
           (or (gethash id cache)
               (setf (gethash id cache) (entity->json (fetch! 'seq-task id)))))
          (t
           (let ((task (fetch! 'seq-task id)))
             (when (member :closed-parent-fault *planted-defects*)
               (let ((parent (and (seq-task-parent-id task)
                                  (fetch 'seq-task (seq-task-parent-id task)))))
                 ;; A careless view of a task whose parent is closed.
                 (when (and parent (seq-task-closed parent))
                   (error "The parent ~a is closed and has no view" (entity-id parent)))))
             task)))))

(define-operation seq-tasks-close ((id :type (id seq-task) :required t :label "Task"))
    (:entity seq-task :kind :transition :policy :employee :title "Close a task (sequence probe)")
  (let ((task (fetch! 'seq-task id)))
    (setf (seq-task-closed task) t)
    (save task)))

(define-operation seq-tasks-delete ((id :type (id seq-task) :required t :label "Task"))
    (:entity seq-task :kind :transition :confirm t :policy :employee
     :title "Delete a task (sequence probe)")
  (let ((task (fetch! 'seq-task id)))
    (unless (member :orphans *planted-defects*)
      ;; Its parts are parts of nothing once it is gone.
      (dolist (part (select 'seq-task :where `(:= "parent_id" ,id)))
        (setf (seq-task-parent-id part) nil)
        (save part)))
    (delete-entity task)
    (jobj "deleted" id)))

(define-invariant seq-tasks-are-parts-of-tasks-there-are
    (:description "A task that is part of another names a task that exists (sequence probe)")
  (when (member :invariant-signals *planted-defects*)
    (error "The invariant could not read the tasks"))
  (loop for task in (select 'seq-task :where '(:not-null "parent_id"))
        unless (fetch 'seq-task (seq-task-parent-id task))
          collect (format nil "~a is part of ~a, which does not exist"
                          (entity-id task) (seq-task-parent-id task))))

(define-scenario seq-tasks (:actors ("employee:anna"))
  "Two tasks, the second part of the first."
  (let ((whole (jget (call-ok "seq_tasks_create" "employee:anna" "title" "Helheten") "id")))
    (call-ok "seq_tasks_create" "employee:anna" "title" "Delen" "parent_id" whole)))

(define-scenario seq-tasks-broken (:actors ("employee:anna"))
  "A task that is part of one that is not there."
  (with-application (*app*)
    (with-actor ((system-actor "probe"))
      (with-transaction (:write)
        (insert (make-instance 'seq-task :title "Foreldreløs" :parent-id "sqt_gone"))))))

(defparameter +seq-tools+ '("seq_tasks_create" "seq_tasks_get" "seq_tasks_close" "seq_tasks_delete"))

(defun seq-probes (&key (scenario "seq-tasks") (seed 1) (sequences 6) (steps 12) observe)
  "Call the probe tools in sequence from SCENARIO, with a fresh cache for
the probe get."
  (let ((*seq-task-cache* (make-hash-table :test 'equal)))
    (call-tools-in-sequence (apply #'probe-operations +seq-tools+)
                            :scenario (find-scenario scenario :package "TUN.TESTS")
                            :seed seed :sequences sequences :steps steps :observe observe)))

(defun called-tools (report)
  (loop for tool being the hash-keys of (sequence-report-called report) collect tool))

(defun step-tools (steps)
  (mapcar (lambda (step) (operation-tool (sequence-step-operation step))) steps))

(defun only-sequence-failure (report)
  "REPORT's one failing sequence; the test fails when there is not exactly one."
  (let ((failures (sequence-report-failures report)))
    (is (= 1 (length failures)) "~d failures" (length failures))
    (first failures)))

;;; ------------------------------------------------------------------
;;; The runs

(test probe-tools-called-in-sequence-pass-without-defects
  (let ((report (seq-probes)))
    (is (null (sequence-report-failures report))
        "~{~a~^~%~}" (mapcar (lambda (failure) (sequence-failure-text failure report "probes"))
                            (sequence-report-failures report)))
    (is (plusp (sequence-report-replays report)))
    (is (plusp (sequence-report-gets report)))))

(test a-run-with-as-many-steps-as-tools-calls-every-tool
  ;; The deck deals every tool once before any twice, across sequences:
  ;; the first steps that are not replays name each tool once.
  (dolist (seed '(1 2 3 4 5))
    (let* ((sequences (tun.test-support::make-sequences
                       (apply #'probe-operations +seq-tools+) '("employee:anna") seed 3 3))
           (fresh (remove-if #'tun.test-support::replay-step-p (apply #'append sequences))))
      (is (equal (sort (copy-list +seq-tools+) #'string<)
                 (sort (step-tools (subseq fresh 0 (length +seq-tools+))) #'string<))
          "seed ~d dealt ~s" seed (step-tools fresh))))
  (let* ((report (seq-probes))
         (summary (sequence-summary report "probes")))
    (is (null (set-difference +seq-tools+ (called-tools report) :test #'string=)))
    (is (search "4 of 4 tools called" summary) "~a" summary)))

(test a-fault-only-a-sequence-reaches-is-found-and-shrunk
  ;; The get faults on a task whose parent is closed. Fuzzed alone, each
  ;; tool on its own copy, nothing closes the parent before the get.
  (let ((fuzzed (let ((*planted-defects* '(:closed-parent-fault)))
                  (fuzz-tools (apply #'probe-operations +seq-tools+)
                              :scenario (find-scenario "seq-tasks" :package "TUN.TESTS")
                              :seed 1 :calls 8)))
        (report (let ((*planted-defects* '(:closed-parent-fault)))
                  (seq-probes :sequences 10 :steps 20))))
    (is (null (fuzz-report-failures fuzzed)))
    (let ((failure (only-sequence-failure report)))
      (when failure
        (is (eq :fault (sequence-failure-kind failure)))
        (is (search "is closed and has no view" (sequence-failure-problem failure)))
        (is (<= (length (sequence-failure-shrunk failure)) 2)
            "~a" (sequence-failure-text failure report "probes"))
        (is (equal '("seq_tasks_close" "seq_tasks_get")
                   (step-tools (sequence-failure-shrunk failure))))))))

(test a-get-that-does-not-find-a-new-record-is-found
  (let* ((report (let ((*planted-defects* '(:stale-get))) (seq-probes)))
         (failure (only-sequence-failure report)))
    (when failure
      (is (eq :not-found-after-made (sequence-failure-kind failure)))
      (is (search "seq_tasks_get answered not_found" (sequence-failure-problem failure)))
      (is (equal '("seq_tasks_create")
                 (step-tools (sequence-failure-shrunk failure)))
          "~a" (sequence-failure-text failure report "probes")))))

(test a-get-that-still-finds-a-removed-record-is-found
  (let* ((report (let ((*planted-defects* '(:cached-get))) (seq-probes)))
         (failure (only-sequence-failure report)))
    (when failure
      (is (eq :found-after-removed (sequence-failure-kind failure)))
      (is (member "seq_tasks_delete"
                  (step-tools (sequence-failure-shrunk failure))
                  :test #'string=)
          "~a" (sequence-failure-text failure report "probes")))))

(defun drop-receipts (operation call outcome)
  "Delete every receipt after a mutation that answered with a result, as
if the store had lost them."
  (declare (ignore call))
  (when (and (operation-mutating-p operation) (eq :result (outcome-kind outcome)))
    (with-application (*app*)
      (with-actor ((system-actor "probe"))
        (with-transaction (:write)
          (dolist (receipt (select 'receipt))
            (delete-entity receipt)))))))

(test a-replay-that-performs-again-is-found
  (let* ((report (seq-probes :observe #'drop-receipts))
         (failure (only-sequence-failure report)))
    (when failure
      (is (eq :replay (sequence-failure-kind failure)))
      (is (search "the replay of" (sequence-failure-problem failure)))
      (let ((shrunk (sequence-failure-shrunk failure)))
        (is (= 2 (length shrunk)) "~a" (sequence-failure-text failure report "probes"))
        (is (search "a replay of step 1" (sequence-failure-text failure report "probes")))))))

(test a-broken-invariant-is-found-and-shrunk-to-the-step-that-breaks-it
  (let* ((report (let ((*planted-defects* '(:orphans))) (seq-probes)))
         (failure (only-sequence-failure report)))
    (when failure
      (is (equal '(:invariant tun.tests::seq-tasks-are-parts-of-tasks-there-are)
                 (sequence-failure-kind failure)))
      (is (search "does not exist" (sequence-failure-problem failure)))
      (is (equal '("seq_tasks_delete")
                 (step-tools (sequence-failure-shrunk failure)))
          "~a" (sequence-failure-text failure report "probes")))))

(test an-invariant-the-scenario-breaks-is-reported-before-the-first-step
  (let* ((report (seq-probes :scenario "seq-tasks-broken"))
         (failure (only-sequence-failure report)))
    (when failure
      (is (zerop (sequence-failure-index failure)))
      (is (search "the scenario seq-tasks-broken, before the first step"
                  (sequence-failure-text failure report "probes"))))))

(test an-invariant-that-signals-is-its-fault
  (let* ((report (let ((*planted-defects* '(:invariant-signals))) (seq-probes)))
         (failure (only-sequence-failure report)))
    (when failure
      (is (equal '(:invariant-fault tun.tests::seq-tasks-are-parts-of-tasks-there-are)
                 (sequence-failure-kind failure)))
      (is (search "could not read the tasks" (sequence-failure-problem failure))))))

(test the-same-seed-makes-the-same-run
  ;; The same steps, kinds and outcomes; the ids differ, being new each run.
  (flet ((failures ()
           (let ((report (let ((*planted-defects* '(:orphans))) (seq-probes))))
             (mapcar (lambda (failure)
                       (let ((steps (sequence-failure-shrunk failure)))
                         (list (sequence-failure-number failure) (sequence-failure-index failure)
                               (sequence-failure-kind failure)
                               (mapcar (lambda (step) (step-text step steps)) steps)
                               (sequence-failure-trace failure))))
                     (sequence-report-failures report)))))
    (let ((first (failures)))
      (is (equal first (failures)))
      (is (plusp (length first))))))

(test registry-describe-lists-the-invariants
  (with-test-app ()
    (let ((entry (find "seq_tasks_are_parts_of_tasks_there_are"
                       (coerce (jget (call-ok "registry_describe" "viewer:v") "invariants") 'list)
                       :key (lambda (invariant) (jget invariant "name")) :test #'equal)))
      (is (not (null entry)))
      (is (equal "core" (jget entry "module")))
      (is (search "names a task that exists" (jget entry "description"))))))

(test define-invariant-wants-a-description
  (signals error (macroexpand-1 '(define-invariant no-description () nil)))
  (signals error (macroexpand-1 '(define-invariant blank-description (:description "  ") nil))))

(test a-modules-invariants-hold-only-where-it-is-enabled
  ;; The dashboard tests' application enables customers alone: orders' and
  ;; inventory's invariants are not its; core's and the client's are.
  (let ((names (mapcar #'invariant-name
                       (application-invariants (make-instance 'dashboardless-application)))))
    (is (member 'seq-tasks-are-parts-of-tasks-there-are names))
    (is (not (member 'tun.orders::one-active-and-one-proposed-plan-per-order names)))
    (is (not (member 'tun.inventory::one-consumption-per-order-and-article names))))
  (let ((names (mapcar #'invariant-name (application-invariants (make-instance 'zz-partial-app)))))
    (is (member 'tun.orders::one-active-and-one-proposed-plan-per-order names))
    (is (member 'tun.inventory::one-consumption-per-order-and-article names))))

(test a-replay-answers-with-what-its-receipt-holds
  ;; A value shown once is null in the receipt, and so in the replay; a key
  ;; the receipt lacks is the live view's, not compared.
  (flet ((differences (first replay kept)
           (tun.test-support::replay-differences (parse-json first) (parse-json replay)
                                                 (parse-json kept))))
    (is (null (differences "{\"id\":\"t1\",\"token\":\"s3cr3t\"}"
                           "{\"id\":\"t1\",\"token\":null}"
                           "{\"id\":\"t1\",\"token\":null}")))
    (is (equal '("token") (differences "{\"id\":\"t1\",\"token\":\"s3cr3t\"}"
                                       "{\"id\":\"t1\",\"token\":\"s3cr3t\"}"
                                       "{\"id\":\"t1\",\"token\":null}")))
    (is (null (differences "{\"id\":\"o1\",\"stock_warnings\":[]}"
                           "{\"id\":\"o1\",\"stock_warnings\":[\"low\"]}"
                           "{\"id\":\"o1\"}")))
    (is (equal '("id") (differences "{\"id\":\"o1\"}" "{\"id\":\"o2\"}" "{\"id\":\"o1\"}")))
    (is (equal '("title") (differences "{\"id\":\"o1\",\"title\":\"a\"}"
                                       "{\"id\":\"o1\",\"title\":\"b\"}"
                                       "{\"id\":\"o1\",\"title\":\"b\"}")))))
