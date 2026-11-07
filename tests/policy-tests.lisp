;;;; tests/policy-tests.lisp -- record policies in every tool (spec/testing.md
;;;; 2, 3): probe tools on an entity with a record policy, the defects a test
;;;; plants in them, and what finds each; a waiting tool that cannot write;
;;;; :beyond-record-policy; and audit_list keeping to the policies (core.md
;;;; 3.8).  On Postgres, which alone applies record policies, when
;;;; TUN_TEST_POSTGRES names a server.

(in-package #:tun.tests)

(def-suite policy-checks :in core)
(in-suite policy-checks)

;;; ------------------------------------------------------------------
;;; Probe tools

(define-entity fuzz-memo (:label "Fuzz memo" :id-prefix "fzm" :table "fuzz_memos"
                          :record-policy ((:admin t) (:employee "author = :actor_name")))
  ((title :type (string :min 1 :max 200) :required t :label "Title")
   (parent-id :type (id fuzz-memo) :label "Part of")
   (author :type (string :max 64) :input nil :label "Author")
   (closed :type boolean :input nil :label "Closed")))

(defun write-from-thread (application function)
  "Call FUNCTION in a write transaction of APPLICATION's, as the system
actor, in a thread of its own, as a careless tool might."
  (sb-thread:join-thread
   (sb-thread:make-thread
    (lambda ()
      (with-application (application)
        (with-actor ((system-actor "probe"))
          (with-transaction (:write) (funcall function))))))))

(define-operation fuzz-memos-create ((:draft fuzz-memo))
    (:entity fuzz-memo :kind :create :policy :employee :title "Add a memo (policy probe)")
  (setf (fuzz-memo-author fuzz-memo) (actor-name *actor*))
  (insert fuzz-memo))

(define-operation fuzz-memos-list ()
    (:entity fuzz-memo :kind :read :policy :viewer :title "Memos (policy probe)")
  (jobj "items" (jarr (mapcar #'entity->json
                              (if (member :leak *planted-defects*)
                                  (with-actor ((system-actor "probe")) (select 'fuzz-memo))
                                  (select 'fuzz-memo))))))

(define-operation fuzz-memos-list-all ()
    (:entity fuzz-memo :kind :read :policy :viewer :title "Every memo (policy probe)"
     :beyond-record-policy "A probe that lists every memo on purpose, as a system acting for a person would.")
  (jobj "items" (jarr (mapcar #'entity->json
                              (with-actor ((system-actor "probe")) (select 'fuzz-memo))))))

(define-operation fuzz-memos-get ((id :type (id fuzz-memo) :required t :label "Memo"))
    (:entity fuzz-memo :kind :read :policy :viewer :title "A memo (policy probe)")
  (cond ((member :system-get *planted-defects*)
         (or (with-actor ((system-actor "probe")) (fetch 'fuzz-memo id))
             (fail :not-found "No memo ~a" id)))
        ((member :narrow *planted-defects*)
         (fail :not-found "No memo ~a" id))
        (t (fetch! 'fuzz-memo id))))

(define-operation fuzz-memos-close ((id :type (id fuzz-memo) :required t :label "Memo"))
    (:entity fuzz-memo :kind :transition :policy :employee :title "Close a memo (policy probe)")
  (when (member :forbidden-for-hidden *planted-defects*)
    ;; Ownership checked by hand, before the policy has its say.
    (let ((memo (with-actor ((system-actor "probe")) (fetch 'fuzz-memo id))))
      (when (and memo (not (eq (actor-role *actor*) :admin))
                 (string/= (fuzz-memo-author memo) (actor-name *actor*)))
        (fail :forbidden "The memo ~a is not yours" id))))
  (let ((memo (fetch! 'fuzz-memo id)))
    (setf (fuzz-memo-closed memo) t)
    (save memo)))

(define-operation fuzz-memos-delete ((id :type (id fuzz-memo) :required t :label "Memo"))
    (:entity fuzz-memo :kind :transition :policy :admin :title "Delete a memo (policy probe)")
  (delete-entity (fetch! 'fuzz-memo id))
  (jobj "deleted" id))

(define-operation fuzz-memos-peek ()
    (:kind :read :policy :viewer :title "Peek at the memos (policy probe)")
  (when (member :viewer-writes *planted-defects*)
    (write-from-thread application
                       (lambda () (insert (make-instance 'fuzz-memo :title "Seen" :author "probe")))))
  (jobj "seen" t))

(define-operation fuzz-memos-watch ((id :type (id fuzz-memo) :required t :label "Memo"))
    (:entity fuzz-memo :kind :wait :title "Wait for a memo to close (policy probe)")
  (when (member :wait-writes *planted-defects*)
    ;; A note, which has no record policy to refuse a viewer's write.
    (with-transaction (:write)
      (insert (make-instance 'fuzz-note :title "Watched"))))
  (when (member :wait-refuses *planted-defects*)
    (fail :forbidden "Memos cannot be watched"))
  (await (:seconds 1 :until #'fuzz-memo-closed)
    (fetch! 'fuzz-memo id)))

(define-operation fuzz-memos-check ((id :type (id fuzz-memo) :required t :label "Memo"))
    (:entity fuzz-memo :kind :read :policy :employee :title "Check a memo (policy probe)")
  (when (member :job-then-refuse *planted-defects*)
    ;; Queued in a write of its own, which the refusal does not undo.
    (write-from-thread application (lambda () (tun.jobs:enqueue-job 'mark-job :text "checked")))
    (fail :conflict "Memos cannot be checked"))
  (fetch! 'fuzz-memo id))

(defparameter +memo-tools+
  '("fuzz_memos_create" "fuzz_memos_list" "fuzz_memos_list_all" "fuzz_memos_get"
    "fuzz_memos_close" "fuzz_memos_delete" "fuzz_memos_peek" "fuzz_memos_watch"
    "fuzz_memos_check"))

(define-scenario fuzz-memos (:actors ("admin:jonas" "employee:anna" "employee:per"))
  "Two memos of Anna's and one of Per's, for the policy probes' ids to name."
  (dolist (title '("Anna's first" "Anna's second"))
    (call-ok "fuzz_memos_create" "employee:anna" "title" title))
  (call-ok "fuzz_memos_create" "employee:per" "title" "Per's"))

(defmacro when-postgres (&body body)
  `(if (postgres-available-p)
       (progn ,@body)
       (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")))

(defun memo-scenario ()
  (find-scenario "fuzz-memos" :package "TUN.TESTS"))

(defun fuzz-memos (tools &key (seed 7) (calls 4))
  "The report of fuzzing TOOLS, policy probes' names, on Postgres."
  (fuzz-tools (apply #'probe-operations tools) :seed seed :calls calls
                                               :scenario (memo-scenario) :database :postgres))

(defun memo-policies (tools &key (seed 7))
  "The report of checking the record policies in TOOLS, policy probes' names."
  (check-record-policies-in-tools (apply #'probe-operations tools)
                                  :seed seed :scenario (memo-scenario)))

(defun only-policy-failure (report)
  (let ((failures (policy-report-failures report)))
    (is (= 1 (length failures)) "~d failures: ~{~a~^~%~}" (length failures)
        (mapcar #'policy-failure-text failures))
    (first failures)))

;;; ------------------------------------------------------------------
;;; Without a defect

(test the-policy-probes-keep-to-the-record-policies
  (when-postgres
    (let ((report (memo-policies +memo-tools+)))
      (is (null (policy-report-failures report)) "~{~a~^~%~}"
          (mapcar #'policy-failure-text (policy-report-failures report)))
      (is (plusp (policy-report-past-validation report))
          "pairs compared past input validation: ~a" (policy-summary report "probes"))
      (is (plusp (policy-report-gets report)))
      (is (plusp (policy-report-skipped report)) "viewers, whom close and flag refuse"))
    (let ((report (fuzz-memos +memo-tools+)))
      (is (null (fuzz-report-failures report)) "~{~a~^~%~}"
          (mapcar (lambda (failure) (failure-text failure 4)) (fuzz-report-failures report))))))

(test the-record-policy-check-makes-the-same-calls-from-the-same-seed
  (when-postgres
    (let ((one (memo-policies '("fuzz_memos_close" "fuzz_memos_create")))
          (two (memo-policies '("fuzz_memos_close" "fuzz_memos_create"))))
      (is (= (policy-report-calls one) (policy-report-calls two)))
      (is (= (policy-report-compared one) (policy-report-compared two))))))

(test a-client-without-a-record-policy-has-nothing-to-check
  (let ((report (check-record-policies-in-tools (probe-operations "fuzz_notes_count"
                                                                  "fuzz_notes_archive"))))
    (is (zerop (policy-report-tools report)))
    (is (search "nothing to check" (policy-summary report "probe")))))

;;; ------------------------------------------------------------------
;;; A planted defect is found

(test a-list-that-reads-past-the-record-policy-is-found
  (when-postgres
    (let* ((report (let ((*planted-defects* '(:leak)))
                     (fuzz-memos '("fuzz_memos_list"))))
           (failure (only-failure report))
           (text (and failure (failure-text failure 4))))
      (when failure
        (is (eq :hidden-record (fuzz-failure-kind failure)))
        (is (search "fuzz_memos_list, as " text) "~a" text)
        (is (search "(seed 7)" text) "~a" text)
        (is (search "it showed the fuzz_memo fzm_" text) "~a" text)
        (is (search "record policy hides" text) "~a" text)
        (is (search ":beyond-record-policy" text) "~a" text)))
    (is (null (fuzz-report-failures (fuzz-memos '("fuzz_memos_list"))))
        "without the defect the list shows each actor only their own")))

(test a-tool-declared-beyond-the-record-policy-may-show-what-it-hides
  (when-postgres
    (is (null (fuzz-report-failures (fuzz-memos '("fuzz_memos_list_all"))))))
  (with-test-app ()
    (let ((operations (jget (call-ok "registry_describe" "viewer:vera") "operations")))
      (flet ((described (tool)
               (find tool (coerce operations 'list) :key (lambda (op) (jget op "name"))
                                                    :test #'string=)))
        (is (search "on purpose" (jget (described "fuzz_memos_list_all") "beyond_record_policy")))
        (is (null (nth-value 1 (gethash "beyond_record_policy"
                                        (described "fuzz_memos_list")))))))))

(test beyond-record-policy-says-why-as-a-text
  (dolist (reason '("" "  " t))
    (signals error
      (macroexpand-1 `(define-operation fuzz-memos-nowhere ()
                          (:kind :read :beyond-record-policy ,reason)
                        nil)))))

(test a-get-that-reads-past-the-record-policy-is-found
  ;; The call with the hidden memo's id shows it, which every call's sixth
  ;; check finds before the two answers are compared.
  (when-postgres
    (let* ((report (let ((*planted-defects* '(:system-get)))
                     (memo-policies '("fuzz_memos_get"))))
           (failure (only-policy-failure report))
           (text (and failure (policy-failure-text failure))))
      (when failure
        (is (string= "fuzz_memos_get" (policy-failure-tool failure)))
        (is (search "it showed the fuzz_memo fzm_" text) "~a" text)
        (is (search "{\"id\":\"‹fuzz_memo #" text) "the input names the memo: ~a" text)
        (is (search "(seed 7)" text) "~a" text)))))

(test a-change-that-refuses-a-hidden-record-as-forbidden-is-found
  (when-postgres
    (let* ((report (let ((*planted-defects* '(:forbidden-for-hidden)))
                     (memo-policies '("fuzz_memos_close"))))
           (failure (only-policy-failure report))
           (text (and failure (policy-failure-text failure))))
      (when failure
        (is (search "fuzz_memos_close, as employee:" text) "~a" text)
        (is (search "id answered forbidden for" text) "~a" text)
        (is (search "but not_found for fzm_fuzznothing" text) "~a" text)))
    (is (null (policy-report-failures (memo-policies '("fuzz_memos_close")))))))

(test a-get-that-misses-a-record-the-policy-admits-is-found
  (when-postgres
    (let* ((report (let ((*planted-defects* '(:narrow)))
                     (memo-policies '("fuzz_memos_get"))))
           (failure (only-policy-failure report))
           (text (and failure (policy-failure-text failure))))
      (when failure
        (is (search "it answered not_found for \"‹fuzz_memo #" text) "~a" text)
        (is (search "record policy admits" text) "~a" text)))))

(test a-viewer-s-read-that-writes-from-a-thread-is-found
  (when-postgres
    (let* ((report (let ((*planted-defects* '(:viewer-writes)))
                     (fuzz-memos '("fuzz_memos_peek"))))
           (failure (only-failure report))
           (text (and failure (failure-text failure 4))))
      (when failure
        (is (eq :viewer-wrote (fuzz-failure-kind failure)))
        (is (search "a viewer's call changed records of fuzz_memo" text) "~a" text)
        (is (search "as viewer:fuzz" text) "~a" text)))))

(test a-waiting-tool-cannot-write
  (when-postgres
    (let* ((report (let ((*planted-defects* '(:wait-writes)))
                     (fuzz-memos '("fuzz_memos_watch"))))
           (failure (only-failure report))
           (text (and failure (failure-text failure 4))))
      (when failure
        (is (eq :fault (fuzz-failure-kind failure)))
        (is (search "READ-ONLY-VIOLATION" text) "~a" text)
        (is (search "A waiting operation reads and never writes" text) "~a" text)))))

(test a-refusal-in-a-waiting-tool-is-audited
  ;; Fuzzing's fifth check fails a refusal left without its entry.
  (when-postgres
    (let ((report (let ((*planted-defects* '(:wait-refuses)))
                    (fuzz-memos '("fuzz_memos_watch")))))
      (is (null (fuzz-report-failures report)) "~{~a~^~%~}"
          (mapcar (lambda (failure) (failure-text failure 4)) (fuzz-report-failures report))))))

(test a-refusal-that-leaves-a-job-behind-is-found
  (when-postgres
    (let* ((report (let ((*planted-defects* '(:job-then-refuse)))
                     (fuzz-memos '("fuzz_memos_check"))))
           (failure (only-failure report))
           (text (and failure (failure-text failure 4))))
      (when failure
        (is (eq :changed-records (fuzz-failure-kind failure)))
        (is (search "it refused with conflict but changed records of job" text) "~a" text)))))

;;; ------------------------------------------------------------------
;;; audit_list keeps to the record policies (core.md 3.8)

(defun audit-ids (actor &rest arguments)
  "The entity ids of the audit entries ACTOR is listed, newest first."
  (map 'list (lambda (entry) (jget entry "entity_id"))
       (jget (apply #'call-ok "audit_list" actor arguments) "items")))

(defmacro with-memo-app (() &body body)
  `(when-postgres
     (with-test-app (:db (scratch-postgres "policy_audit"))
       ,@body)))

(test audit-list-leaves-out-the-entries-of-records-the-caller-does-not-reach
  (with-memo-app ()
    (let ((anna (jget (call-ok "fuzz_memos_create" "employee:anna" "title" "A") "id"))
          (per (jget (call-ok "fuzz_memos_create" "employee:per" "title" "P") "id")))
      (is (equal (list anna) (audit-ids "employee:anna" "entity_type" "fuzz_memo")))
      (is (equal (list per) (audit-ids "employee:per" "entity_type" "fuzz_memo")))
      (is (equal (list per anna) (audit-ids "admin:jonas" "entity_type" "fuzz_memo")))
      (is (null (audit-ids "viewer:vera" "entity_type" "fuzz_memo")) "no viewer clause")
      (is (null (audit-ids "employee:anna" "entity_id" per)) "as for a memo that does not exist")
      (is (null (audit-ids "employee:anna" "entity_id" "fzm_none"))))))

(test audit-list-shows-the-entries-of-a-deleted-record-to-a-role-that-reaches-every-record
  (with-memo-app ()
    (let ((per (jget (call-ok "fuzz_memos_create" "employee:per" "title" "P") "id")))
      (call-ok "fuzz_memos_delete" "admin:jonas" "id" per)
      (is (equal (list per per) (audit-ids "admin:jonas" "entity_id" per)))
      (is (null (audit-ids "employee:per" "entity_id" per))
          "Per's clause is a condition, which a deleted memo does not meet"))))

(test audit-list-fills-its-limit-past-the-entries-it-leaves-out
  (with-memo-app ()
    (let ((first (jget (call-ok "fuzz_memos_create" "employee:anna" "title" "A1") "id"))
          (second (jget (call-ok "fuzz_memos_create" "employee:anna" "title" "A2") "id")))
      ;; More of Per's than one page of entries holds.
      (dotimes (i 60)
        (call-ok "fuzz_memos_create" "employee:per" "title" (format nil "P~d" i)))
      (is (equal (list second) (audit-ids "employee:anna" "limit" 1)))
      (is (equal (list second first) (audit-ids "employee:anna" "limit" 2))))))

(test audit-list-shows-an-entry-that-names-no-record
  (with-memo-app ()
    (is (string= "forbidden" (nth-value 1 (call "fuzz_memos_create" "viewer:vera" "title" "V"))))
    (let ((entries (coerce (jget (call-ok "audit_list" "employee:anna") "items") 'list)))
      (is (find-if (lambda (entry)
                     (and (equal "fuzz_memos_create" (jget entry "tool"))
                          (equal "rejected" (jget entry "outcome"))))
                   entries)
          "~a" (to-json-string (jarr entries))))))
