;;;; cli/clients.lisp -- `tun clients test` (spec/cli.md 5.2): each client's
;;;; bin/test on this Tun tree's head, in the client's dev shell with every
;;;; input of Tun's repository overridden, several at once under one hold of
;;;; the verify lock.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; A client's flake and its inputs of Tun's repository

(defun git-top (directory)
  "The top of the git repository DIRECTORY is in, or NIL."
  (let ((top (git-line directory "rev-parse" "--show-toplevel")))
    (and top (uiop:ensure-directory-pathname top))))

(defun client-flake-directory (directory)
  "The directory of DIRECTORY's flake: the nearest at or above it, within its
git repository, that holds a flake.nix; NIL when none does."
  (let ((top (or (git-top directory) directory)))
    (loop for candidate = (uiop:ensure-directory-pathname directory)
          then (uiop:pathname-parent-directory-pathname candidate)
          while (uiop:subpathp candidate top)
          when (probe-file (merge-pathnames "flake.nix" candidate))
          return candidate
          until (equal (namestring candidate) (namestring top)))))

(defun input-source (lock node)
  "The (TYPE URL DIR) of the input whose node in the flake.lock LOCK is
NODE, from what it was asked for (its original), or NIL."
  (let ((original (and (stringp node) (jget (jget (jget lock "nodes") node) "original"))))
    (and original
         (list (jget original "type") (jget original "url")
               (let ((dir (jget original "dir"))) (and (stringp dir) dir))))))

(defun locked-tun-inputs (lock)
  "The inputs of the flake.lock LOCK, a parsed JSON object, whose source is
Tun's repository, the one the input tun names: (NAME . DIR) each, DIR the
directory within it, or NIL for the kernel's. NIL when LOCK has no tun."
  (let* ((root (jget (jget lock "nodes") (jget lock "root")))
         (inputs (jget root "inputs"))
         (tun (input-source lock (and inputs (jget inputs "tun")))))
    (when tun
      (let ((found '()))
        (maphash (lambda (name node)
                   (let ((source (input-source lock node)))
                     (when (and source (equal (subseq source 0 2) (subseq tun 0 2)))
                       (push (cons name (third source)) found))))
                 inputs)
        (sort found #'string< :key #'car)))))

(defun override-arguments (inputs worktree revision)
  "nix's --override-input arguments that put each of INPUTS, (NAME . DIR),
at REVISION of the Tun tree WORKTREE, DIR within it."
  (loop for (name . dir) in inputs
        append (list "--override-input" name
                     (format nil "git+file://~a?rev=~a~@[&dir=~a~]"
                             (string-right-trim "/" (namestring worktree)) revision dir))))

(defparameter +clients-unset+
  '("CL_SOURCE_REGISTRY" "ASDF_OUTPUT_TRANSLATIONS" "TUN_WORKTREE" "TUN_CORE_REVISION"
    "TUN_CALLER_CL_SOURCE_REGISTRY" "TUN_CALLER_ASDF_OUTPUT_TRANSLATIONS" "TUN_TEST_SUITES")
  "What of tun's own environment a client's bin/test does not get: Tun's
dev shell's ASDF settings and the Tun working tree tun runs from, which
would take the place of the client's own.")

(defun client-test-command (flake inputs worktree revision jobs)
  "The command, a list of arguments, that runs a client's bin/test in the
dev shell of FLAKE, with INPUTS at REVISION of WORKTREE and TUN_TEST_JOBS
JOBS."
  (append (list "env")
          (loop for name in +clients-unset+ append (list "-u" name))
          (list (format nil "TUN_TEST_JOBS=~d" jobs)
                "nix" "develop" (string-right-trim "/" (namestring flake)))
          (override-arguments inputs worktree revision)
          (list "-c" "bin/test")))

(defun client-log-names (directories)
  "The name of each client in DIRECTORIES for its log: its directory's name,
with its repository's before it when another client has the same."
  (let ((plain (mapcar (lambda (directory) (car (last (pathname-directory directory))))
                       directories)))
    (loop for directory in directories
          for name in plain
          collect (if (> (count name plain :test #'string=) 1)
                      ;; Outside a repository, the directory above stands for it.
                      (let ((top (or (and (uiop:directory-exists-p directory) (git-top directory))
                                     (uiop:pathname-parent-directory-pathname directory))))
                        (format nil "~a-~a" (car (last (pathname-directory top))) name))
                      name))))

;;; ------------------------------------------------------------------
;;; The command

(defun default-client-jobs (available-gb)
  "How many clients' suites AVAILABLE-GB of memory allows at once: 4 GB
each, with 4 GB left over, at least one."
  (max 1 (floor (- available-gb 4) 4)))

(defstruct (client-run (:constructor make-client-run (name directory command log)))
  name directory command log)

(defun client-runs (directories worktree revision jobs log)
  "A run for each client in DIRECTORIES, refusing one without a bin/test, a
flake or an input of Tun's repository."
  (let ((per-client (max 1 (floor (processors) jobs))))
    (loop for directory in directories
          for name in (client-log-names directories)
          collect (let* ((flake (client-flake-directory directory))
                         (lock (and flake (merge-pathnames "flake.lock" flake)))
                         (inputs (and lock (probe-file lock)
                                      (locked-tun-inputs (parse-json (read-text lock))))))
                    (unless (probe-file (merge-pathnames "bin/test" directory))
                      (refuse "~a has no bin/test" (namestring directory)))
                    (unless inputs
                      (refuse "~a pins no Tun: its flake.lock~@[ (~a)~] has no input tun"
                              (namestring directory) (and lock (namestring lock))))
                    (make-client-run name directory
                                     (client-test-command flake inputs worktree revision per-client)
                                     (merge-pathnames (format nil "~a.log" name) log))))))

(defun run-client (run)
  "Run RUN's bin/test, its output to its log: (RUN PASSED SECONDS)."
  (let* ((started (get-universal-time))
         (log (namestring (client-run-log run)))
         (status (handler-case
                     (nth-value 2 (uiop:run-program (client-run-command run)
                                                    :directory (client-run-directory run)
                                                    :output log :if-output-exists :supersede
                                                    :error-output :output :ignore-error-status t))
                   (error (condition)
                     (write-text log (format nil "cannot run it: ~a~%" condition))
                     -1))))
    (list run (eql status 0) (- (get-universal-time) started))))

(defun print-client-result (result)
  (destructuring-bind (run passed seconds) result
    (format t "~&  ~:[FAIL~;ok  ~]  ~24a~5ds  ~a~%" passed (client-run-name run) seconds
            (namestring (client-run-log run)))
    (finish-output)))

(defun clients-test-command (arguments &key jobs log)
  "tun clients test DIR... (spec/cli.md 5.2)."
  (unless (equal (first arguments) "test")
    (refuse "tun clients takes test, then the clients' directories"))
  (let ((worktree (uiop:getenv "TUN_WORKTREE"))
        (directories (mapcar #'absolute-directory (rest arguments))))
    (unless worktree
      (refuse "tun clients test runs from Tun's working tree, as bin/tun"))
    (when (null directories)
      (refuse "tun clients test needs the clients' directories"))
    (when (git-line worktree "status" "--porcelain")
      (refuse "~a has changes: commit them, so that its head is what the clients run on"
              worktree))
    (let* ((revision (git-line worktree "rev-parse" "HEAD"))
           (jobs (if jobs
                     (or (ignore-errors (let ((n (parse-integer jobs))) (and (plusp n) n)))
                         (refuse "--jobs takes a whole number from 1, not ~s" jobs))
                     (min (length directories) (default-client-jobs (available-gb)))))
           (log (uiop:ensure-directory-pathname
                 (absolute-directory
                  (or log (namestring (merge-pathnames ".build/clients/"
                                                       (uiop:ensure-directory-pathname worktree)))))))
           (runs (client-runs directories worktree revision jobs log)))
      (ensure-directories-exist log)
      (format t "~&~d client~:p on Tun ~a, ~d at once~%" (length runs) (subseq revision 0 12) jobs)
      (finish-output)
      (with-verify-lock ()
        (let* ((results (in-workers-printing jobs runs
                                             (lambda (run index)
                                               (declare (ignore index))
                                               (run-client run))
                                             #'print-client-result))
               (passed (count-if #'second results)))
          (format t "~&~d of ~d clients passed.~%" passed (length results))
          (unless (= passed (length results))
            (fail-step "~d client~:p failed" (- (length results) passed))))))))
