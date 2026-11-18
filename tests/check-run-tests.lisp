;;;; tests/check-run-tests.lisp -- the parts of a check run from one image
;;;; (spec/preview.md 4, «One image, one database server, workers») and of
;;;; `tun clients test` (spec/cli.md 5.2) that run without a browser or a
;;;; client: how many workers, the order results are printed in, the list
;;;; of checks, which scenarios a template may stand for, and a client's
;;;; command. bin/check, bin/test-cli and the loop's proof runs run the rest.

(in-package #:tun.tests)

(def-suite check-run :in core)
(in-suite check-run)

;;; ------------------------------------------------------------------
;;; Workers

(test check-workers-are-as-many-as-processors-and-memory-allow
  (is (= 4 (tun.cli::default-check-jobs 12 31)) "at most four")
  (is (= 2 (tun.cli::default-check-jobs 6 31)) "a third of the processors")
  (is (= 2 (tun.cli::default-check-jobs 12 9)) "9 GB less 6 over 1.5")
  (is (= 1 (tun.cli::default-check-jobs 12 4)) "at least one")
  (let ((before (uiop:getenv "TUN_CHECK_JOBS")))
    (unwind-protect
         (progn (sb-posix:setenv "TUN_CHECK_JOBS" "3" 1)
                (is (= 3 (tun.cli::check-jobs)))
                (sb-posix:setenv "TUN_CHECK_JOBS" "0" 1)
                (signals tun.cli:usage-error (tun.cli::check-jobs)))
      (if before
          (sb-posix:setenv "TUN_CHECK_JOBS" before 1)
          (sb-posix:unsetenv "TUN_CHECK_JOBS")))))

(test results-are-printed-in-the-order-of-the-checks
  ;; The first item ends last: it waits until every other has ended, and is
  ;; printed first all the same, the others only after it.
  (let* ((lock (sb-thread:make-mutex))
         (ended (sb-thread:make-waitqueue))
         (others 0)
         (printed '())
         (results (tun.cli::in-workers-printing
                   3 '(0 1 2 3 4)
                   (lambda (item index)
                     (if (zerop item)
                         (sb-thread:with-mutex (lock)
                           (loop until (= others 4)
                                 do (sb-thread:condition-wait ended lock)))
                         (sb-thread:with-mutex (lock)
                           (incf others)
                           (sb-thread:condition-broadcast ended)))
                     (list index tun.cli::*worker-port*))
                   (lambda (result) (push (first result) printed)))))
    (is (equal '(0 1 2 3 4) (reverse printed)))
    (is (equal '(0 1 2 3 4) (mapcar #'first results)))
    (is (every #'null (mapcar #'second results)) "each worker begins without a port")))

(test the-runner-takes-a-list-of-checks
  (let* ((directory (asdf:system-relative-pathname "tun" "checks/showcase/"))
         (checks (tun.cli::file-checks (tun.cli::check-files directory nil))))
    (is (plusp (length checks)))
    (is (every (lambda (check)
                 (and (stringp (tun.cli::browser-check-name check))
                      (stringp (tun.cli::browser-check-scenario check))
                      (probe-file (tun.cli::browser-check-file check))))
               checks))
    (let ((made (tun.cli::make-browser-check "generated-width" "default" #p"/tmp/x.py")))
      (is (equal "generated-width" (tun.cli::browser-check-name made))
          "a check Tun makes is a name, a scenario and a file, as a file's"))))

;;; ------------------------------------------------------------------
;;; Which scenarios a template stands for

(defvar *sample-handler* nil "A sample of a variable a scenario sets.")
(defvar *sample-rows* (list 1 2) "A sample of a list a scenario adds to in place.")
(defvar *sample-table* (make-hash-table) "A sample of a table a scenario fills in place.")

(test a-scenario-that-sets-a-variable-is-found
  (let ((tun.test-support:*client-packages* '("TUN.TESTS")))
    (flet ((changed-by (function)
             (let ((before (global-values)))
               (funcall function)
               (changed-variables before))))
      (let ((*sample-handler* nil) (*sample-rows* (list 1 2)) (*sample-table* (make-hash-table)))
        (is (null (changed-by (lambda ()))) "a scenario of records only sets nothing")
        (is (equal '("TUN.TESTS::*SAMPLE-HANDLER*")
                   (changed-by (lambda () (setf *sample-handler* #'identity)))))
        (is (equal '("TUN.TESTS::*SAMPLE-ROWS*")
                   (changed-by (lambda () (setf (cdr (last *sample-rows*)) (list 3)))))
            "a list's length")
        (is (equal '("TUN.TESTS::*SAMPLE-TABLE*")
                   (changed-by (lambda () (setf (gethash :a *sample-table*) 1))))
            "a table's count")
        (let ((*http-json-handler* nil))
          (is (equal '("TUN.OUTBOUND::*HTTP-JSON-HANDLER*")
                     (changed-by (lambda () (setf *http-json-handler* #'identity))))
              "Tun's isolated variables count, whoever's packages"))))))

;;; ------------------------------------------------------------------
;;; tun clients test

(defparameter +sample-lock+
  "{\"root\": \"root\", \"version\": 7, \"nodes\": {
     \"root\": {\"inputs\": {\"tun\": \"tun\", \"dashboard\": \"dashboard\", \"nixploy\": \"nixploy\",
                             \"nixpkgs\": [\"tun\", \"nixpkgs\"]}},
     \"tun\": {\"original\": {\"type\": \"git\", \"url\": \"ssh://git@github.com/owner/tun\", \"ref\": \"main\"}},
     \"dashboard\": {\"original\": {\"type\": \"git\", \"url\": \"ssh://git@github.com/owner/tun\",
                                    \"ref\": \"main\", \"dir\": \"modules/dashboard\"}},
     \"nixploy\": {\"original\": {\"type\": \"github\", \"owner\": \"owner\", \"repo\": \"nixploy\"}}}}"
  "A client's flake.lock: Tun, one of its modules, and another flake.")

(test a-client-s-tun-inputs-are-read-from-its-lock
  (is (equal '(("dashboard" . "modules/dashboard") ("tun"))
             (tun.cli::locked-tun-inputs (parse-json +sample-lock+))))
  (is (null (tun.cli::locked-tun-inputs
             (parse-json "{\"root\": \"root\", \"nodes\": {\"root\": {\"inputs\": {}}}}")))))

(test a-client-s-command-is-a-list-of-arguments
  (let ((command (tun.cli::client-test-command #p"/c/app/" '(("dashboard" . "modules/dashboard") ("tun"))
                                               #p"/t/tun/" "abc123" 3)))
    (is (equal (member "TUN_TEST_JOBS=3" command :test #'string=)
               '("TUN_TEST_JOBS=3" "nix" "develop" "/c/app"
                 "--override-input" "dashboard" "git+file:///t/tun?rev=abc123&dir=modules/dashboard"
                 "--override-input" "tun" "git+file:///t/tun?rev=abc123"
                 "-c" "bin/test"))
        "~s" command)
    (is (equal "env" (first command)))
    (dolist (name '("CL_SOURCE_REGISTRY" "TUN_WORKTREE"))
      (is (search (list "-u" name) command :test #'equal) "~a is not passed on" name))))

(test two-clients-of-one-name-are-told-apart-by-their-repository
  (is (equal '("app" "other")
             (tun.cli::client-log-names (list #p"/nowhere/a/app/" #p"/nowhere/b/other/"))))
  (let ((names (tun.cli::client-log-names (list #p"/nowhere/a/same/" #p"/nowhere/b/same/"))))
    (is (= 2 (length (remove-duplicates names :test #'string=))) "~s" names)))

(defun sample-repository (files)
  "A fresh git repository with FILES, (PATH . TEXT), committed."
  (let ((directory (uiop:ensure-directory-pathname
                    (merge-pathnames (format nil ".build/test-clients/~a/" (new-id "repo"))
                                     (asdf:system-source-directory "tun")))))
    (loop for (path . text) in files
          do (let ((file (merge-pathnames path directory)))
               (ensure-directories-exist file)
               (with-open-file (out file :direction :output :if-exists :supersede)
                 (write-string text out))))
    (flet ((git (&rest arguments)
             (uiop:run-program (list* "git" "-C" (namestring directory) "-c" "user.name=t"
                                      "-c" "user.email=t@example.com" arguments)
                               :output nil :error-output nil)))
      (git "init" "-q")
      (git "add" "-A")
      (git "commit" "-q" "-m" "sample"))
    directory))

(test tun-clients-test-refuses-what-it-cannot-run
  (let ((tun (sample-repository '(("README" . "a Tun"))))
        (client (sample-repository '(("flake.nix" . "{}") ("bin/test" . "true")
                                     ("flake.lock" . "{\"root\": \"root\", \"nodes\": {\"root\": {\"inputs\": {}}}}"))))
        (before (uiop:getenv "TUN_WORKTREE")))
    (unwind-protect
         (progn
           (sb-posix:setenv "TUN_WORKTREE" (namestring tun) 1)
           (signals tun.cli:usage-error
                    (tun.cli::clients-test-command (list "test" (namestring client)) :jobs "1"))
           (with-open-file (out (merge-pathnames "README" tun) :direction :output
                                :if-exists :supersede)
             (write-string "changed" out))
           (handler-case
               (progn (tun.cli::clients-test-command (list "test" (namestring client)) :jobs "1")
                      (is (null "a tree with changes is refused")))
             (tun.cli:usage-error (condition)
               (is (search "has changes" (princ-to-string condition)))))
           (sb-posix:unsetenv "TUN_WORKTREE")
           (signals tun.cli:usage-error
                    (tun.cli::clients-test-command (list "test" (namestring client)))))
      (if before
          (sb-posix:setenv "TUN_WORKTREE" before 1)
          (sb-posix:unsetenv "TUN_WORKTREE")))))

(test a-client-s-flake-is-the-nearest-above-it
  (let ((repository (sample-repository '(("flake.nix" . "{}") ("clients/second/bin/test" . "true")
                                         ("other/flake.nix" . "{}")))))
    (is (equal (namestring repository)
               (namestring (tun.cli::client-flake-directory
                            (merge-pathnames "clients/second/" repository)))))
    (is (equal (namestring (merge-pathnames "other/" repository))
               (namestring (tun.cli::client-flake-directory (merge-pathnames "other/" repository)))))))
