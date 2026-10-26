;;;; tests/group-commit-tests.lisp -- the SQLite adapter's group commit
;;;; (store/sqlite.lisp): write transactions queued behind each other share
;;;; one COMMIT, and none of them returns before that COMMIT is durable.

(in-package #:tun.tests)

(def-suite group-commit :in core)
(in-suite group-commit)

(defun gc-store () (application-store *app*))
(defun gc-waiting () (car (tun.store.sqlite::writers-waiting (gc-store))))

(defun gc-thread (function)
  "Run FUNCTION in a thread with the test application; join returns its value or the error."
  (let ((app *app*))
    (sb-thread:make-thread (lambda ()
                             (let ((*app* app))
                               (with-application (app)
                                 (handler-case (funcall function) (error (e) e)))))
                           :name "group commit test writer")))

(defun gc-names ()
  "Widget names visible to a reader on another thread (committed data only)."
  (sb-thread:join-thread
   (gc-thread (lambda () (with-transaction (:read) (sort (mapcar #'widget-name (select 'widget)) #'string<))))))

(defun gc-first-member (name inside &key before-end)
  "A writer that inserts NAME, signals INSIDE and stays in its transaction until
another writer queues for the lock; returns :returned after its transaction."
  (gc-thread (lambda ()
               (with-transaction (:write)
                 (insert (make-instance 'widget :name name))
                 (when before-end (funcall before-end))
                 (sb-thread:signal-semaphore inside)
                 (loop repeat 1000 until (plusp (gc-waiting)) do (sleep 0.005)))
               :returned)))

(defmacro with-sqlite-app ((name &key (group-commit 16)) &body body)
  `(let ((*app* (tun.runtime:open-application
                 'application :test-clock t
                 :store (tun.runtime::make-store (scratch-path ,name) :group-commit ,group-commit))))
     (unwind-protect (with-application (*app*) ,@body)
       (tun.runtime:close-application *app*))))

(test gc-queued-writers-share-one-commit-and-wait-for-it
  (with-sqlite-app ("group")
    (let* ((inside (sb-thread:make-semaphore))
           (commits (tun.store.sqlite::commit-count (gc-store)))
           (first-state :unset) (visible :unset)
           (first (gc-first-member "en" inside)))
      (sb-thread:wait-on-semaphore inside)
      (let ((second (gc-thread (lambda ()
                                 (with-transaction (:write)
                                   (insert (make-instance 'widget :name "to"))
                                   ;; The first writer handed the lock on without committing:
                                   (setf first-state (sb-thread:thread-alive-p first)
                                         visible (gc-names)))
                                 :returned))))
        (is (eq :returned (sb-thread:join-thread second)))
        (is (eq :returned (sb-thread:join-thread first)))
        (is (eq t first-state) "the first writer had not returned while the second ran")
        (is (null visible) "readers do not see a batch before its COMMIT: ~s" visible)
        (is (equal '("en" "to") (gc-names)))
        (is (= (1+ commits) (tun.store.sqlite::commit-count (gc-store))) "two transactions, one COMMIT")))))

(test gc-a-failing-member-leaves-the-batch-intact
  (with-sqlite-app ("group-fail")
    (let* ((inside (sb-thread:make-semaphore))
           (first (gc-first-member "en" inside)))
      (sb-thread:wait-on-semaphore inside)
      (let ((second (gc-thread (lambda ()
                                 (with-transaction (:write)
                                   (insert (make-instance 'widget :name "to"))
                                   (error "boom"))))))
        (is (typep (sb-thread:join-thread second) 'simple-error))
        (is (eq :returned (sb-thread:join-thread first)))
        (is (equal '("en") (gc-names)) "the failed member rolled back alone; the batch committed")))))

(test gc-a-failed-commit-fails-every-member
  (with-sqlite-app ("group-commit-fails")
    (let* ((inside (sb-thread:make-semaphore))
           (rolled-back (list nil nil))
           (first (gc-first-member
                   "en" inside
                   :before-end (lambda ()
                                 (on-rollback (lambda () (setf (first rolled-back) t)))
                                 ;; A deferred foreign key is checked only at COMMIT.
                                 (tun.store.sqlite::exec "CREATE TEMP TABLE gc_parent (id INTEGER PRIMARY KEY)")
                                 (tun.store.sqlite::exec "CREATE TEMP TABLE gc_child (pid INTEGER REFERENCES gc_parent(id) DEFERRABLE INITIALLY DEFERRED)")
                                 (tun.store.sqlite::exec "INSERT INTO gc_child VALUES (42)")))))
      (sb-thread:wait-on-semaphore inside)
      (let ((second (gc-thread (lambda ()
                                 (with-transaction (:write)
                                   (on-rollback (lambda () (setf (second rolled-back) t)))
                                   (insert (make-instance 'widget :name "to")))
                                 :returned))))
        (is (typep (sb-thread:join-thread second) 'tun.store.sqlite::batch-commit-failed))
        (is (typep (sb-thread:join-thread first) 'tun.store.sqlite::batch-commit-failed))
        (is (equal '(t t) rolled-back) "both members ran their rollback actions")
        (is (null (gc-names)) "nothing of the batch was stored")
        (with-transaction (:write) (insert (make-instance 'widget :name "etter")))
        (is (equal '("etter") (gc-names)) "the writer connection works after the failed batch")))))

(test gc-a-batch-whose-queued-writer-left-is-committed-by-its-member
  (with-sqlite-app ("group-rescue")
    (let ((waiting (tun.store.sqlite::writers-waiting (gc-store))))
      ;; A writer that queues and then gives up (its lock wait hit the
      ;; deadline) after the lock was handed to it: simulated by the count.
      (sb-ext:atomic-incf (car waiting))
      (let ((result (unwind-protect
                         (sb-thread:join-thread
                          (gc-thread (lambda ()
                                       (with-transaction (:write) (insert (make-instance 'widget :name "en")))
                                       :returned))
                          :timeout 5 :default :hung)
                      (sb-ext:atomic-decf (car waiting)))))
        (is (eq :returned result))
        (is (equal '("en") (gc-names)))))))

(test gc-group-commit-1-commits-every-transaction-alone
  (with-sqlite-app ("group-off" :group-commit 1)
    (let* ((inside (sb-thread:make-semaphore))
           (visible :unset)
           (first (gc-first-member "en" inside)))
      (sb-thread:wait-on-semaphore inside)
      (let ((second (gc-thread (lambda ()
                                 (with-transaction (:write)
                                   (insert (make-instance 'widget :name "to"))
                                   (setf visible (gc-names)))
                                 :returned))))
        (is (eq :returned (sb-thread:join-thread second)))
        (is (eq :returned (sb-thread:join-thread first)))
        (is (equal '("en") visible) "the first transaction was committed before the second ran")))))

(test gc-many-writers-many-failures
  (with-sqlite-app ("group-many")
    (let* ((commits (tun.store.sqlite::commit-count (gc-store)))
           (results (run-concurrently 24 (lambda (i)
                                           (with-application (*app*)
                                             (loop for j below 10
                                                   count (handler-case
                                                             (with-transaction (:write)
                                                               (insert (make-instance 'widget :name (format nil "w~d-~d" i j)))
                                                               (when (zerop (mod (+ i j) 7)) (error "boom"))
                                                               t)
                                                           (simple-error () nil)))))))
           (ok (reduce #'+ results))
           (expected (loop for i below 24 sum (loop for j below 10 count (plusp (mod (+ i j) 7))))))
      (is (= expected ok))
      (is (= expected (length (gc-names))) "every successful transaction, and only those, is stored")
      (let ((used (- (tun.store.sqlite::commit-count (gc-store)) commits)))
        (is (< used 240) "transactions were grouped (~d commits for 240 transactions)" used)))))

(test gc-a-batch-sqlite-rolled-back-is-not-joined-again
  ;; On an I/O error or a full disk SQLite rolls the whole transaction back.
  ;; The batch must fail at once: a writer queued behind it must start a new
  ;; batch, not issue SAVEPOINT outside any transaction (which would commit
  ;; on RELEASE) and then be told that its COMMIT failed.
  (with-sqlite-app ("group-lost")
    (let* ((inside (sb-thread:make-semaphore))
           (inside-2 (sb-thread:make-semaphore))
           (first (gc-first-member "en" inside)))
      (sb-thread:wait-on-semaphore inside)
      (let ((second (gc-thread (lambda ()
                                 (with-transaction (:write)
                                   (insert (make-instance 'widget :name "to"))
                                   (sb-thread:signal-semaphore inside-2)
                                   (loop repeat 1000 until (plusp (gc-waiting)) do (sleep 0.005))
                                   (tun.store.sqlite::exec "ROLLBACK") ; what SQLite does on SQLITE_FULL
                                   (error "disken er full"))))))
        (sb-thread:wait-on-semaphore inside-2)
        (let ((third (gc-thread (lambda ()
                                  (with-transaction (:write) (insert (make-instance 'widget :name "tre")))
                                  :returned))))
          (is (typep (sb-thread:join-thread second) 'simple-error))
          (is (typep (sb-thread:join-thread first) 'tun.store.sqlite::batch-commit-failed)
              "the member whose batch SQLite discarded is told so")
          (is (eq :returned (sb-thread:join-thread third)) "the next writer starts a new batch and succeeds")
          (is (equal '("tre") (gc-names))))))))
