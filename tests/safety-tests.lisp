;;;; tests/safety-tests.lisp -- phase 2: actor, policy, confirmation,
;;;; idempotency and audit, all enforced in the operation execution path.

(in-package #:tun.tests)

(def-suite safety :in core)
(in-suite safety)

(defun audit-items (&rest args)
  (coerce (jget (apply #'call-ok "audit_list" "admin:ada" args) "items") 'list))

(defun widget-count ()
  (jget (call-ok "widgets_count" "viewer:vera") "count"))

(test actor-is-required-for-direct-calls
  (with-test-app ()
    (with-application (*app*)
      (let ((*actor* nil))
        (signals actor-error
          (widgets-create *app* (make-input (jobj "name" "x"))))))))

(test viewer-cannot-mutate-and-is-audited
  (with-test-app ()
    (multiple-value-bind (json code) (call "widgets_create" "viewer:vera" "name" "x" "request_key" "k1")
      (is (string= "forbidden" code))
      (is (stringp (jget (jget json "error") "message"))))
    (is (= 0 (widget-count)))
    (let ((entry (first (audit-items))))
      (is (string= "rejected" (jget entry "outcome")))
      (is (string= "widgets_create" (jget entry "tool")))
      (is (string= "viewer:vera" (jget entry "actor")))
      (is (string= "k1" (jget entry "request_key")))
      (is (string= "forbidden" (jget entry "error_code"))))))

(test policy-is-checked-before-lookup
  (with-test-app ()
    (multiple-value-bind (json code) (call "widgets_purge" "employee:anna" "id" "wdg_finnes_ikke")
      (declare (ignore json))
      (is (string= "forbidden" code)))
    (multiple-value-bind (json code) (call "widgets_purge" "admin:ada" "id" "wdg_finnes_ikke")
      (declare (ignore json))
      (is (string= "not_found" code)))
    (multiple-value-bind (json code) (call "widgets_archive" "viewer:vera" "id" "wdg_finnes_ikke")
      (declare (ignore json))
      (is (string= "forbidden" code)))))

(test read-operations-cannot-write
  (with-test-app ()
    (signals error (call "widgets_sneaky_read" "viewer:vera" "name" "x"))
    (is (= 0 (widget-count)))))

(test confirmation-two-step
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Rød") "id"))
           (first (call-ok "widgets_archive" "employee:anna" "id" id))
           (token (jget first "confirmation_token")))
      (is (eq t (jget first "confirmation_required")))
      (is (stringp token))
      (is (<= 43 (length token)) "token is high-entropy")
      (is (string= "2026-03-01T09:10:00Z" (jget first "expires_at")))
      (is (search "Rød" (jget first "summary")))
      (is (string= "aktiv" (jget (call-ok "widgets_get" "viewer:vera" "id" id) "status"))
          "no mutation without a token")
      (let ((done (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token)))
        (is (string= "arkivert" (jget done "status"))))
      (multiple-value-bind (json code)
          (call "widgets_archive" "employee:anna" "id" id "confirmation_token" token)
        (declare (ignore json))
        (is (string= "confirmation_invalid" code) "a token is one-time")))))

(test confirmation-token-is-bound-to-actor-tool-and-input
  (with-test-app ()
    (let* ((a (jget (call-ok "widgets_create" "employee:anna" "name" "A") "id"))
           (b (jget (call-ok "widgets_create" "employee:anna" "name" "B") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" a) "confirmation_token")))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:bob" "id" a "confirmation_token" token))))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:anna" "id" b "confirmation_token" token))))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:anna" "id" a "confirmation_token" "feil"))))
      (is (string= "aktiv" (jget (call-ok "widgets_get" "viewer:vera" "id" a) "status")))
      ;; Failed attempts did not burn the token for its rightful use.
      (is (string= "arkivert" (jget (call-ok "widgets_archive" "employee:anna" "id" a "confirmation_token" token)
                                    "status")))
      (let ((rejected (remove "ok" (audit-items) :key (lambda (e) (jget e "outcome")) :test #'string=)))
        (is (= 3 (length rejected)))
        (is (every (lambda (e) (string= "confirmation_invalid" (jget e "error_code"))) rejected))))))

(test confirmation-token-expires-after-ten-minutes
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Gammel") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" id) "confirmation_token")))
      (set-test-clock (application-clock *app*) (+ (parse-rfc3339 "2026-03-01T09:10:01Z")))
      (is (string= "confirmation_invalid"
                   (nth-value 1 (call "widgets_archive" "employee:anna" "id" id "confirmation_token" token)))))))

(test tokens-are-stored-hashed-and-never-audited
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "Hemmelig") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" id) "confirmation_token")))
      (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token)
      (with-application (*app*)
        (with-transaction (:read)
          (let ((rows (select 'tun.core::confirmation)))
            (is (= 1 (length rows)))
            (is (string= (sha256-hex token) (tun.core::confirmation-token-hash (first rows))))
            (is (not (search token (to-json-string (mapcar #'entity->json rows))))))
          (is (not (search token (to-json-string (mapcar #'entity->json (select 'audit-entry))))))
          (is (not (search token (to-json-string (mapcar #'entity->json (select 'tun.core::receipt)))))))))))

(test idempotent-replay-returns-the-original-result
  (with-test-app ()
    (let ((first (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "nøkkel-1"))
          (again (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "nøkkel-1")))
      (is (string= (jget first "id") (jget again "id")))
      (is (string= (to-json-string first) (to-json-string again)))
      (is (= 1 (widget-count)))
      (is (= 1 (count "ok" (audit-items) :key (lambda (e) (jget e "outcome")) :test #'string=))))))

(test idempotency-conflict-on-changed-input
  (with-test-app ()
    (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "k")
    (is (string= "idempotency_conflict"
                 (nth-value 1 (call "widgets_create" "employee:anna" "name" "To" "request_key" "k"))))
    (is (= 1 (widget-count)))
    (is (string= "idempotency_conflict" (jget (first (audit-items)) "error_code")))))

(test idempotency-key-is-scoped-to-the-actor
  (with-test-app ()
    (let ((a (call-ok "widgets_create" "employee:anna" "name" "Én" "request_key" "felles"))
          (b (call-ok "widgets_create" "employee:bob" "name" "Én" "request_key" "felles")))
      (is (string/= (jget a "id") (jget b "id")))
      (is (= 2 (widget-count))))))

(test confirmed-call-with-key-replays-instead-of-failing
  (with-test-app ()
    (let* ((id (jget (call-ok "widgets_create" "employee:anna" "name" "X") "id"))
           (token (jget (call-ok "widgets_archive" "employee:anna" "id" id "request_key" "arkiv")
                        "confirmation_token"))
           (done (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token
                          "request_key" "arkiv"))
           (retry (call-ok "widgets_archive" "employee:anna" "id" id "confirmation_token" token
                           "request_key" "arkiv")))
      (is (string= "arkivert" (jget done "status")))
      (is (string= (to-json-string done) (to-json-string retry))))))

(test audit-entry-commits-with-the-mutation
  (with-test-app ()
    (let ((before (length (audit-items))))
      (is (string= "conflict" (nth-value 1 (call "widgets_explode" "employee:anna" "name" "Bom"))))
      (is (= 0 (widget-count)) "the business write rolled back")
      (is (= before (length (audit-items))) "and so did its audit entry"))
    (let* ((w (call-ok "widgets_create" "employee:anna" "name" "Ok" "request_key" "r"))
           (entry (first (audit-items))))
      (is (string= "ok" (jget entry "outcome")))
      (is (string= "widget" (jget entry "entity_type")))
      (is (string= (jget w "id") (jget entry "entity_id")))
      (is (string= "employee:anna" (jget entry "actor")))
      (is (string= "r" (jget entry "request_key")))
      (is (= 1 (length (audit-items "entity_type" "widget" "entity_id" (jget w "id"))))))))

(test concurrent-calls-with-one-key-mutate-once
  (dolist (db (list nil (scratch-path "idem")))
    (with-test-app (:db db)
      (let ((results (run-concurrently 12 (lambda (i)
                                            (declare (ignore i))
                                            (call "widgets_create" "employee:anna"
                                                  "name" "Samtidig" "request_key" "samme")))))
        (is (every #'hash-table-p results) "no call failed: ~s" results)
        (is (= 1 (widget-count)) "store ~a" (if db "sqlite" "memory"))
        (is (= 1 (length (remove-duplicates (map 'list (lambda (r) (and (hash-table-p r) (jget r "id")))
                                                 results)
                                            :test #'equal))))))))
