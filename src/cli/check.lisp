;;;; cli/check.lisp -- `tun check` (spec/preview.md 4): run a client's
;;;; browser checks, each against a fresh preview of its scenario, and say
;;;; which passed.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The verify lock (spec/preview.md 4): one builder's checks at a time

(defparameter +lock-report-seconds+ 300
  "How often a wait for the verify lock says again what it waits for.")

(defconstant +lock-ex+ 2 "flock(2)'s LOCK_EX.")
(defconstant +lock-nb+ 4 "flock(2)'s LOCK_NB.")
(defconstant +fd-cloexec+ 1 "fcntl(2)'s FD_CLOEXEC.")

(defun call-flock (fd operation)
  "flock(2) FD with OPERATION, again when a signal interrupts it; true when it
took the lock, NIL when LOCK_NB found it held."
  (loop for result = (sb-alien:alien-funcall
                      (sb-alien:extern-alien "flock" (function sb-alien:int sb-alien:int sb-alien:int))
                      fd operation)
        for errno = (and (minusp result) (sb-alien:get-errno))
        while (eql errno sb-posix:eintr)
        finally (cond ((zerop result) (return t))
                      ((eql errno sb-posix:ewouldblock) (return nil))
                      (t (fail-step "cannot lock ~a: ~a" fd (sb-int:strerror errno))))))

(defun flock-now-p (fd)
  "Take an exclusive flock(2) lock on FD if no one else holds one; whether it
was taken."
  (call-flock fd (logior +lock-ex+ +lock-nb+)))

(defun flock-wait (fd)
  "Take an exclusive flock(2) lock on FD, waiting in the kernel's queue for
it: a wait that only looked now and then would lose the lock to every
`flock` waiting in that queue whenever it is let go."
  (call-flock fd +lock-ex+))

(defun file-device-and-inode (path)
  "The device of the file PATH, as /proc/locks writes it (MAJOR:MINOR in
hexadecimal), and its inode."
  (let* ((stat (sb-posix:stat path))
         (device (sb-posix:stat-dev stat)))
    (values (format nil "~(~2,'0x:~2,'0x~)"
                    (logior (ldb (byte 12 8) device) (ash (ldb (byte 20 44) device) 12))
                    (logior (ldb (byte 8 0) device) (ash (ldb (byte 12 20) device) 8)))
            (sb-posix:stat-ino stat))))

(defun flock-holders (path)
  "The processes /proc/locks names as holding a flock on the file PATH (not
those waiting for one), or NIL where there is no /proc/locks or no PATH."
  (let ((lines (ignore-errors (uiop:read-file-lines "/proc/locks"))))
    (when (and lines (probe-file path))
      (multiple-value-bind (device inode) (ignore-errors (file-device-and-inode path))
        (let ((place (format nil "~a:~d" device inode)))
          (loop for line in lines
                for words = (remove "" (uiop:split-string line :separator " ") :test #'string=)
                ;; "1: FLOCK  ADVISORY  WRITE 4242 00:2c:1234 0 EOF"; a waiter's has "->".
                when (and (equal (second words) "FLOCK") (not (find "->" words :test #'string=))
                          (string-equal (sixth words) place))
                  collect (parse-integer (fifth words) :junk-allowed t)))))))

(defun parent-pid (pid)
  "The parent of process PID, or NIL."
  (let ((stat (ignore-errors (uiop:read-file-string (format nil "/proc/~d/stat" pid)))))
    ;; "PID (COMMAND) STATE PPID ...": the command may hold spaces and parentheses.
    (when stat
      (let ((fields (uiop:split-string (subseq stat (1+ (position #\) stat :from-end t)))
                                       :separator " ")))
        (parse-integer (third fields) :junk-allowed t)))))

(defun ancestor-holds-p (path &optional (pid (sb-posix:getpid)))
  "True when a process that the process PID descends from holds a flock on
PATH, as `flock PATH tun loop verify` does."
  (let ((holders (flock-holders path)))
    (and holders
         (loop for ancestor = (parent-pid pid) then (parent-pid ancestor)
               while (and ancestor (> ancestor 1))
               thereis (member ancestor holders)))))

(defun process-command (pid)
  "The command line of process PID, shortened, or ?."
  (let ((text (ignore-errors (uiop:read-file-string (format nil "/proc/~d/cmdline" pid)))))
    (if (plusp (length text))
        (let ((line (string-trim " " (cl-ppcre:regex-replace-all "[\\s\\x00]+" text " "))))
          (if (> (length line) 120) (format nil "~a…" (subseq line 0 120)) line))
        "?")))

(defun holders-text (path)
  (let ((holders (flock-holders path)))
    (if holders
        (format nil ", held by ~{~a~^, ~}"
                (mapcar (lambda (pid) (format nil "process ~d (~a)" pid (process-command pid)))
                        holders))
        "")))

(defun duration-text (seconds)
  (format nil "~dm~2,'0ds" (floor seconds 60) (mod seconds 60)))

(defun call-with-verify-lock (function)
  "Call FUNCTION holding the verify lock on the file TUN_VERIFY_LOCK names,
waiting for it and saying so (spec/preview.md 4); without the variable,
or when this process's verify or an ancestor already holds it, just call
FUNCTION."
  (let ((path (uiop:getenv "TUN_VERIFY_LOCK")))
    (if (or (zerop (length path))
            (equal (uiop:getenv "TUN_VERIFY_LOCK_HELD") path)
            (and (probe-file path) (ancestor-holds-p path)))
        (funcall function)
        (let ((fd (handler-case (sb-posix:open path (logior sb-posix:o-rdonly sb-posix:o-creat) #o666)
                    (sb-posix:syscall-error (condition)
                      (fail-step "cannot open the verify lock ~a (TUN_VERIFY_LOCK): ~a" path condition)))))
          (unwind-protect
               (progn
                 ;; The lock stays with this process: a program it starts,
                 ;; such as a preview's server, does not keep it.
                 (sb-posix:fcntl fd sb-posix:f-setfd +fd-cloexec+)
                 (unless (flock-now-p fd)
                   (let* ((started (get-universal-time))
                          (out *standard-output*)
                          ;; Says again, now and then, what the wait is for.
                          (reporter (sb-thread:make-thread
                                     (lambda ()
                                       (loop (sleep +lock-report-seconds+)
                                             (format out "~&tun: still waiting for the verify lock ~a (~a)~a~%"
                                                     path (duration-text (- (get-universal-time) started))
                                                     (holders-text path))
                                             (finish-output out)))
                                     :name "verify lock reporter")))
                     (format t "~&tun: waiting for the verify lock ~a~a~%" path (holders-text path))
                     (finish-output)
                     (unwind-protect (flock-wait fd)
                       (sb-thread:terminate-thread reporter))
                     (format t "~&tun: took the verify lock ~a after ~a~%"
                             path (duration-text (- (get-universal-time) started)))
                     (finish-output)))
                 (sb-posix:setenv "TUN_VERIFY_LOCK_HELD" path 1)
                 (unwind-protect (funcall function)
                   (sb-posix:unsetenv "TUN_VERIFY_LOCK_HELD")))
            ;; Closing the file releases the lock.
            (sb-posix:close fd))))))

(defmacro with-verify-lock (() &body body)
  `(call-with-verify-lock (lambda () ,@body)))

;;; ------------------------------------------------------------------
;;; The checks

(defun browser-checks (directory)
  "The browser checks of the client in DIRECTORY: checks/*.py, without the
files whose name starts with _."
  (sort (remove-if (lambda (file) (eql 0 (search "_" (pathname-name file))))
                   (directory (merge-pathnames "checks/*.py" directory)))
        #'string< :key #'pathname-name))

(defun check-files (directory names)
  "The browser checks of the client in DIRECTORY, or the ones NAMES name, by
file name without .py."
  (let ((files (browser-checks directory)))
    (when (null files)
      (fail-step "~a has no browser checks: they are checks/*.py (spec/preview.md 4)"
                 (namestring directory)))
    (if names
        (mapcar (lambda (name)
                  (or (find name files :key #'pathname-name :test #'string=)
                      (refuse "there is no check ~a; the checks are ~{~a~^, ~}"
                              name (mapcar #'pathname-name files))))
                names)
        files)))

(defun check-scenario (file)
  "The scenario the check FILE starts from: its SCENARIO = \"NAME\", else
default."
  (or (cl-ppcre:register-groups-bind (name)
          ("(?m)^SCENARIO\\s*=\\s*[\"']([a-z0-9-]+)[\"']" (read-text file))
        name)
      "default"))

(defun tun-path (relative)
  "The file RELATIVE in the Tun the client runs on: the worktree under
bin/tun, else TUN_SOURCE, which a client's dev shell sets."
  (let ((tun (or (uiop:getenv "TUN_WORKTREE") (uiop:getenv "TUN_SOURCE"))))
    (unless tun
      (fail-step "tun needs TUN_SOURCE for ~a, and a client's dev shell sets it" relative))
    (merge-pathnames relative (uiop:ensure-directory-pathname tun))))

(defun check-runner (&optional (script "scripts/tun_check.py"))
  "The program and script that drive Chromium: tun-check-python from the dev
shell, and SCRIPT of the Tun the client runs on."
  (unless (ignore-errors (zerop (nth-value 2 (uiop:run-program '("sh" "-c" "command -v tun-check-python")
                                                               :ignore-error-status t))))
    (fail-step "tun needs tun-check-python, which the dev shell of Tun and of a client ~
                on Tun 1.12 or later has"))
  (list "tun-check-python" (namestring (tun-path script))))

(defun check-result (out file)
  (let ((report (merge-pathnames (make-pathname :name (pathname-name file) :type "json") out)))
    (if (probe-file report)
        (parse-json (read-text report))
        (jobj "name" (pathname-name file) "passed" nil
              "results" (jarr (list (jobj "text" "the check ran" "ok" nil "screenshot" :null)))))))

(defun print-check-result (result)
  (let ((failed (remove-if (lambda (check) (jget check "ok")) (coerce (jget result "results") 'list))))
    (format t "~&  ~:[FAIL~;ok  ~]  ~a~:[: ~d of ~d failed~;~2*~]~%"
            (jget result "passed") (jget result "name") (jget result "passed")
            (length failed) (length (jget result "results")))
    (dolist (check failed)
      (format t "~&          ~a~@[~%            ~a~]~%" (jget check "text")
              (let ((shot (jget check "screenshot"))) (and (stringp shot) shot))))
    (let ((error (jget result "error")))
      (when (stringp error)
        (format t "~&          ~a~%" (string-trim '(#\Newline) error))))))

(defstruct (browser-check (:constructor make-browser-check (name scenario file &optional sweep)))
  "A check the runner runs: its NAME, the SCENARIO its server starts from
and the FILE tun_check.py drives; with SWEEP, its server first writes the
pages the page sweep gets, which the check opens. The files in checks/ are
these, and so is the check Tun makes for every client (spec/preview.md 4)."
  (name "" :type string)
  (scenario "default" :type string)
  file
  (sweep nil))

(defparameter +generated-check-name+ "generated-every-page-at-both-widths"
  "The browser check Tun makes for every client (spec/preview.md 4, «The
generated check»).")

(defun generated-check ()
  "The check Tun makes for every client: every page the page sweep reaches,
as each of its actors, at 390 and 1280 px, from the default scenario."
  (make-browser-check +generated-check-name+ "default"
                      (tun-path (format nil "scripts/checks/~a.py" +generated-check-name+))
                      t))

(defun run-list (directory names)
  "The checks a run of the client in DIRECTORY runs: the generated check
first, being the longest, then the files of checks/; or the ones NAMES
name, by name."
  (let* ((generated (or (null names) (member +generated-check-name+ names :test #'string=)))
         (file-names (remove +generated-check-name+ names :test #'string=)))
    (append (and generated (list (generated-check)))
            (cond (file-names (file-checks (check-files directory file-names)))
                  ((null names) (file-checks (browser-checks directory)))))))

(defun file-checks (files)
  "The checks of FILES, browser checks in checks/."
  (mapcar (lambda (file) (make-browser-check (pathname-name file) (check-scenario file) file))
          files))

(defun files-without-image (directory names)
  "The files of checks/ that TUN_CHECK_IMAGE=0 runs, all or those NAMES
name: the generated check runs only from the image, so naming it alone is
refused."
  (let ((file-names (remove +generated-check-name+ names :test #'string=)))
    (when (and names (null file-names))
      (refuse "~a runs only from the client's image; TUN_CHECK_IMAGE=0 runs the files of checks/"
              +generated-check-name+))
    (check-files directory file-names)))

(defun check-command (names &key dir)
  "tun check (spec/preview.md 4): run the client's browser checks, or the
ones NAMES name, each against a server and a database of its own: in
workers, from one image of the client and its scenarios' templates, or
with TUN_CHECK_IMAGE=0 against a fresh preview each, one after another."
  (let* ((directory (absolute-directory (or dir ".")))
         (client (client-name directory))
         (runner (check-runner))
         (out (merge-pathnames ".build/checks/" directory))
         (name (format nil "~a-check" (preview-name client (worktree-branch directory))))
         (data (merge-pathnames ".data/check/" directory)))
    (with-verify-lock ()
      (if (equal (uiop:getenv "TUN_CHECK_IMAGE") "0")
          (run-checks client (files-without-image directory names) runner out name directory data)
          (run-checks-from-image client (run-list directory names) runner out name directory data
                                 :jobs (check-jobs))))))

(defun run-checks (client files runner out name directory data)
  "Run FILES, CLIENT's checks in DIRECTORY, each against a fresh preview NAME
with its database in DATA, by RUNNER, their results in OUT."
  (uiop:delete-directory-tree out :validate (lambda (path) (search "/.build/checks/" (namestring path)))
                                  :if-does-not-exist :ignore)
  (ensure-directories-exist out)
  (format t "~&~a: ~d check~:p~%" client (length files))
  (let ((results
          (loop for file in files
                collect (let ((preview (start-preview :directory (namestring directory) :share nil
                                                      :scenario (check-scenario file)
                                                      :name name :data data)))
                          (unwind-protect
                               (progn
                                 (uiop:run-program (append runner (list (namestring out)
                                                                        (jget preview "local_url")
                                                                        (namestring file)))
                                                   :output :interactive :error-output :interactive
                                                   :ignore-error-status t)
                                 (let ((result (check-result out file)))
                                   (print-check-result result)
                                   (finish-output)
                                   result))
                            (stop-preview preview))))))
    (let ((failed (count-if-not (lambda (result) (jget result "passed")) results)))
      (format t "~&~:[~d of ~d checks failed~;Every check passed~*~*~]. Results and screenshots: ~a~%"
              (zerop failed) failed (length results) (namestring out))
      (unless (zerop failed)
        (fail-step "~d check~:p failed" failed)))))

;;; ------------------------------------------------------------------
;;; One image, one database server, workers (spec/preview.md 4)

(defun environment-jobs (name)
  "The whole number from 1 the environment variable NAME holds, or NIL when
it is unset or empty; refuses anything else."
  (let ((text (uiop:getenv name)))
    (unless (zerop (length text))
      (let ((number (ignore-errors (parse-integer text))))
        (unless (and number (plusp number))
          (refuse "~a is ~s; it takes a whole number from 1" name text))
        number))))

(defun processors ()
  "The processors this process may run on, as nproc counts them."
  (or (ignore-errors (parse-integer (uiop:run-program '("nproc") :output :string)
                                    :junk-allowed t))
      1))

(defun available-gb ()
  "The memory available for new work, MemAvailable of /proc/meminfo, in GB."
  (let ((line (find-if (lambda (line) (eql 0 (search "MemAvailable:" line)))
                       (ignore-errors (uiop:read-file-lines "/proc/meminfo")))))
    (/ (or (and line (parse-integer line :start (length "MemAvailable:") :junk-allowed t)) 0)
       (* 1024.0 1024.0))))

(defun default-check-jobs (processors available-gb)
  "How many check workers PROCESSORS and AVAILABLE-GB allow: at most 4 and
a third of the processors, each taking 1.5 GB with 6 GB left over, at
least one."
  (max 1 (min 4 (floor processors 3) (floor (- available-gb 6) 1.5))))

(defun check-jobs ()
  "The workers tun check runs its checks in: TUN_CHECK_JOBS, else
DEFAULT-CHECK-JOBS of this machine."
  (or (environment-jobs "TUN_CHECK_JOBS")
      (default-check-jobs (processors) (available-gb))))

(defun check-socket-directory ()
  "Where the run's Postgres server has its socket: a short path of this
process's own."
  (merge-pathnames (format nil "tun-check-~d/" (sb-posix:getpid))
                   (or (uiop:getenv-absolute-directory "XDG_RUNTIME_DIR") #p"/tmp/")))

(defun database-url (socket name)
  (format nil "postgresql://preview@/~a?host=~a" name (string-right-trim "/" (namestring socket))))

(defun database-name (&rest parts)
  "A database's name of PARTS, in the letters Postgres takes bare."
  (substitute-if #\_ (lambda (c) (not (alphanumericp c)))
                 (string-downcase (format nil "~{~a~^_~}" parts))))

(defun postgres-program (socket program &rest arguments)
  "Run PROGRAM, createdb or dropdb, with ARGUMENTS on the run's server."
  (run-checked (list* program "-h" (string-right-trim "/" (namestring socket)) "-U" "preview"
                      arguments)
               :output nil :error-output :string))

(defun build-check-image (client directory worktree image log)
  "Save IMAGE, an SBCL that has loaded CLIENT in DIRECTORY and its tests as a
preview's server loads them, noting the client's own packages; its output
in LOG."
  (let ((own (remove nil (list (namestring directory)
                               (let ((shared (repository-modules directory)))
                                 (and shared (namestring shared)))))))
    (handler-case
        (run-checked
         (client-lisp-command
          client directory worktree
          ;; The random state SBCL starts with, before anything draws from
          ;; it, goes into the image (SAVE-CHECK-IMAGE).
          (list (lisp-form "(let ((state (make-random-state nil)) (*compile-verbose* nil) (*load-verbose* nil)) (handler-bind ((warning #'muffle-warning)) (asdf:load-system \"tun-test-support\")) (setf (symbol-value (find-symbol \"*RANDOM-STATE-AT-START*\" \"TUN.TEST-SUPPORT\")) state))")
                (lisp-form "(uiop:symbol-call \"TUN.TEST-SUPPORT\" \"LOAD-CLIENT-SYSTEMS\" ~s '~s)"
                           (format nil "~a/tests" client) own)
                (lisp-form "(uiop:symbol-call \"TUN.TEST-SUPPORT\" \"SAVE-CHECK-IMAGE\" ~s)"
                           (namestring image))))
         :output (namestring log) :error-output :output)
      (step-failed (condition)
        (fail-step "the client's image for the checks was not made: ~a. Its log ended:~%~a"
                   condition (log-tail log))))
    (unless (probe-file image)
      (fail-step "the client's image for the checks was not saved. Its log ended:~%~a"
                 (log-tail log)))))

;;; A run's state, which its workers share: the run's places and programs,
;;; what each scenario was found to be, and the templates made so far.

(defstruct (check-run (:constructor make-check-run
                                    (client directory worktree image socket data name runner out)))
  client directory worktree image socket data name runner out
  (lock (sb-thread:make-mutex :name "tun check"))
  ;; By scenario: (:per-check REASON) once one was found to set a
  ;; variable, (:error TEXT) once it could not be made.
  (verdicts (make-hash-table :test 'equal))
  ;; By (SCENARIO . PORT): the template database made for that port.
  (templates (make-hash-table :test 'equal)))

(defvar *worker-port* nil
  "The port the current check worker serves its checks on, or NIL before its
first: one port a worker, so a template it made holds that port's address.")

(defun worker-port ()
  "Claim the port of this worker's next check: its port again, or, when
another has taken it meanwhile, a new one, which this worker keeps."
  (setf *worker-port*
        (or (and *worker-port*
                 (handler-case (claim-port :port *worker-port*)
                   (step-failed () nil)))
            (claim-port :taken (mapcar (lambda (preview) (jget preview "port")) (previews))))))

(defun say (run control &rest arguments)
  "Print a line of the run, from any of its workers."
  (sb-thread:with-mutex ((check-run-lock run))
    (format t "~&~?~%" control arguments)
    (finish-output)))

(defun image-server-command (run flags)
  "The command of a server of RUN's client from its image, with FLAGS."
  (append (image-lisp-command (check-run-image run) (check-run-client run)
                              (check-run-directory run) (check-run-worktree run)
                              (list (serve-form (check-run-client run))))
          flags))

(defun seed-template (run scenario port)
  "Make SCENARIO on a database of its own, served from PORT's address, by a
server from the image that ends once it has: the template of SCENARIO's
checks on PORT, or NIL when it set a variable, which RUN's verdicts then
say, or signals STEP-FAILED with the end of its log."
  (let* ((database (database-name "template" scenario port))
         (place (merge-pathnames (format nil "~a/" database) (check-run-data run)))
         (report (merge-pathnames "report.json" place))
         (log (merge-pathnames "server.log" place))
         (socket (check-run-socket run)))
    (ensure-directories-exist place)
    (postgres-program socket "createdb" database)
    (handler-case
        (run-checked (image-server-command
                      run (list "--port" (princ-to-string port)
                                "--db" (database-url socket database)
                                "--claimed-identity"
                                "--public-url" (format nil "http://127.0.0.1:~d" port)
                                "--scenario" scenario "--seed-template" (namestring report)))
                     :output (namestring log) :error-output :output)
      (step-failed (condition)
        (fail-step "the scenario ~a was not made: ~a. Its server's log ended:~%~a"
                   scenario condition (log-tail log))))
    (let ((sets (coerce (jget (parse-json (read-text report)) "sets" (jarr '())) 'list)))
      (cond (sets
             (postgres-program socket "dropdb" "--if-exists" "--force" database)
             (sb-thread:with-mutex ((check-run-lock run))
               (setf (gethash scenario (check-run-verdicts run))
                     (list :per-check (format nil "sets ~{~a~^, ~}" sets))))
             (say run "scenario ~a sets ~{~a~^, ~}: made by each of its checks" scenario sets)
             nil)
            (t
             (sb-thread:with-mutex ((check-run-lock run))
               (setf (gethash (cons scenario port) (check-run-templates run)) database)))))))

(defun check-database (run scenario port database)
  "Make DATABASE for a check of SCENARIO served from PORT: a copy of its
template, made first when this port has none; or empty, for a scenario its
checks make. True when it is a copy."
  (let* ((socket (check-run-socket run))
         (verdict (sb-thread:with-mutex ((check-run-lock run))
                    (gethash scenario (check-run-verdicts run))))
         (template (and (null verdict)
                        (or (sb-thread:with-mutex ((check-run-lock run))
                              (gethash (cons scenario port) (check-run-templates run)))
                            (handler-case (seed-template run scenario port)
                              (step-failed (condition)
                                (sb-thread:with-mutex ((check-run-lock run))
                                  (setf (gethash scenario (check-run-verdicts run))
                                        (list :error (princ-to-string condition))))
                                (error condition)))))))
    (when (eq (first verdict) :error)
      (fail-step "~a" (second verdict)))
    (if template
        (postgres-program socket "createdb" "-T" template database)
        (postgres-program socket "createdb" database))
    (and template t)))

(defun start-check-server (run check index)
  "Start the server of CHECK, the INDEXth of RUN, from the image, on this
worker's port and a database of its own; its record, as START-PREVIEW's,
named NAME-INDEX."
  (let* ((port (worker-port))
         (socket (check-run-socket run))
         (database (database-name "check" index))
         (place (merge-pathnames (format nil "check-~d/" index) (check-run-data run)))
         (log (merge-pathnames "server.log" place))
         (sweep (and (browser-check-sweep check) (merge-pathnames "sweep.json" place)))
         (self (sb-posix:getpid))
         (url (format nil "http://127.0.0.1:~d" port))
         (pid nil)
         (started nil))
    (unwind-protect
         (let ((copied (check-database run (browser-check-scenario check) port database))
               (deadline (+ (get-universal-time) +ready-seconds+)))
           (ensure-directories-exist place)
           (setf pid (start-server
                      (image-server-command
                       run (append (list "--port" (princ-to-string port)
                                         "--db" (database-url socket database)
                                         "--claimed-identity" "--public-url" url
                                         "--preview-report"
                                         (namestring (merge-pathnames "report.json" place)))
                                   (and sweep (list "--page-sweep" (namestring sweep)))
                                   (if copied
                                       (list "--scenario-made")
                                       (list "--scenario" (browser-check-scenario check)))))
                      log :deadline deadline))
           (hand-over-claim port self pid)
           (let ((preview (jobj "name" (format nil "~a-~d" (check-run-name run) index)
                                "client" (check-run-client run)
                                "directory" (namestring (check-run-directory run))
                                "port" port "pid" pid "url" url "local_url" url "shared" nil
                                "data" (namestring place) "log" (namestring log)
                                "database" database "started" (local-time-string)
                                "sweep" (if sweep (namestring sweep) :null))))
             (ensure-directories-exist (state-directory))
             (write-text (state-file (jget preview "name")) (to-json-string preview))
             (handler-bind ((step-failed (lambda (condition)
                                           (declare (ignore condition))
                                           (stop-check-server run preview))))
               (wait-until-ready port pid log deadline))
             (setf started t)
             preview))
      (unless started
        (release-claim port (remove nil (list self pid)))
        (ignore-errors (postgres-program socket "dropdb" "--if-exists" "--force" database))))))

(defun stop-check-server (run preview)
  "Stop a check's server: its process, its claim, its files, its database."
  (stop-preview preview)
  (ignore-errors (postgres-program (check-run-socket run) "dropdb" "--if-exists" "--force"
                                   (jget preview "database"))))

(defun failed-check (check text)
  "The result of CHECK that did not run, with TEXT saying why."
  (jobj "name" (browser-check-name check) "passed" nil
        "results" (jarr (list (jobj "text" "the check ran" "ok" nil "screenshot" :null)))
        "error" text))

(defun keep-log (run log check what)
  "Copy LOG, when there is one, beside CHECK's results as NAME-WHAT.log."
  (when (probe-file log)
    (uiop:copy-file log (merge-pathnames (format nil "~a-~a.log" (browser-check-name check) what)
                                         (check-run-out run)))))

(defun sweep-environment (sweep)
  "What goes before the runner's command for a check whose server wrote the
page sweep's pages to SWEEP, a file's name or :NULL: the generated check
reads them from TUN_PAGE_SWEEP."
  (and (stringp sweep) (list "env" (format nil "TUN_PAGE_SWEEP=~a" sweep))))

(defun run-one-check (run check index)
  "Run CHECK, the INDEXth of RUN, against a server of its own; its result
and what the runner printed, as (RESULT . OUTPUT)."
  (handler-case
      (let* ((preview (start-check-server run check index))
             (output (merge-pathnames "runner.log" (jget preview "data"))))
        (unwind-protect
             (progn
               (uiop:run-program (append (sweep-environment (jget preview "sweep"))
                                         (check-run-runner run)
                                         (list (namestring (check-run-out run))
                                               (jget preview "local_url")
                                               (namestring (browser-check-file check))))
                                 :output (namestring output) :error-output :output
                                 :ignore-error-status t)
               (let ((result (check-result (check-run-out run) (browser-check-file check))))
                 ;; A failed check's server log stays beside its results,
                 ;; and so does the log of the server that made its template.
                 (unless (jget result "passed")
                   (keep-log run (jget preview "log") check "server")
                   (keep-log run (merge-pathnames
                                  (format nil "~a/server.log"
                                          (database-name "template" (browser-check-scenario check)
                                                         (jget preview "port")))
                                  (check-run-data run))
                             check "template"))
                 (cons result (if (probe-file output) (read-text output) ""))))
          (stop-check-server run preview)))
    (error (condition)
      (cons (failed-check check (princ-to-string condition)) ""))))

(defun in-workers-printing (jobs items function printer)
  "Call FUNCTION on each of ITEMS and its index in JOBS threads, and PRINTER
with each result in the order of ITEMS as soon as it and every one before
it are known; the results, in that order. FUNCTION handles its own errors.
Each thread has its own *WORKER-PORT*."
  (let* ((count (length items))
         (results (make-array count :initial-element nil))
         (done (make-array count :initial-element nil))
         (next 0)
         (lock (sb-thread:make-mutex :name "check workers"))
         (changed (sb-thread:make-waitqueue)))
    (flet ((work ()
             (let ((*worker-port* nil))
               (loop for index = (sb-thread:with-mutex (lock)
                                   (when (< next count) (prog1 next (incf next))))
                     while index
                     do (let ((result (funcall function (elt items index) index)))
                          (sb-thread:with-mutex (lock)
                            (setf (aref results index) result (aref done index) t)
                            (sb-thread:condition-broadcast changed)))))))
      (let ((threads (loop repeat (max 1 (min jobs count))
                           collect (sb-thread:make-thread #'work :name "check worker"))))
        (dotimes (index count)
          (sb-thread:with-mutex (lock)
            (loop until (aref done index)
                  do (sb-thread:condition-wait changed lock)))
          (funcall printer (aref results index)))
        (mapc #'sb-thread:join-thread threads)
        (coerce results 'list)))))

(defun run-checks-from-image (client checks runner out name directory data &key (jobs 1))
  "Run CHECKS, CLIENT's in DIRECTORY, by RUNNER in JOBS workers, each
against a server of its own started from one image of the client, with a
database copied from its scenario's template on the run's one Postgres
server, all of it in DATA; their results in OUT (spec/preview.md 4)."
  (uiop:delete-directory-tree out :validate (lambda (path) (search "/.build/checks/" (namestring path)))
                              :if-does-not-exist :ignore)
  (ensure-directories-exist out)
  (format t "~&~a: ~d check~:p~%" client (length checks))
  (finish-output)
  (uiop:delete-directory-tree data :validate #'preview-data-p :if-does-not-exist :ignore)
  (ensure-directories-exist data)
  (let* ((socket (check-socket-directory))
         (run (make-check-run client directory (uiop:getenv "TUN_WORKTREE")
                              (merge-pathnames "image.core" data) socket data name runner out)))
    (unwind-protect
         (progn
           (build-check-image client directory (check-run-worktree run) (check-run-image run)
                              (merge-pathnames "image.log" data))
           (start-database (merge-pathnames "server/" data) socket
                           :settings "-c fsync=off -c full_page_writes=off -c max_connections=300")
           (let* ((results (in-workers-printing
                            jobs checks
                            (lambda (check index) (run-one-check run check index))
                            (lambda (result)
                              (sb-thread:with-mutex ((check-run-lock run))
                                (write-string (cdr result))
                                (print-check-result (car result))
                                (finish-output)))))
                  (failed (count-if-not (lambda (result) (jget (car result) "passed")) results)))
             (format t "~&~:[~d of ~d checks failed~;Every check passed~*~*~]. Results and screenshots: ~a~%"
                     (zerop failed) failed (length results) (namestring out))
             (unless (zerop failed)
               (fail-step "~d check~:p failed" failed))))
      (stop-database (merge-pathnames "server/" data))
      (uiop:delete-directory-tree socket :validate (lambda (path) (search "/tun-check-" (namestring path)))
                                  :if-does-not-exist :ignore)
      (uiop:delete-directory-tree data :validate #'preview-data-p :if-does-not-exist :ignore))))
