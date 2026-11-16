;;;; tests/preview-tests.lisp -- previews and scenarios (spec/preview.md):
;;;; a scenario's records and actors, and the parts of `tun preview` that
;;;; run without Postgres, a server or tailscale: names, commands, the
;;;; previews' files, and refusals. bin/test-cli starts a real preview.

(in-package #:tun.tests)

(def-suite preview :in core)
(in-suite preview)

(define-scenario two-customers (:actors ("employee:anna" "viewer:vera"))
  "To kunder, laget av Anna."
  (dolist (name '("Kari" "Ola"))
    (call-ok "customers_create" "employee:anna" "name" name
             "email" (format nil "~(~a~)@example.no" name))))

(test a-scenario-makes-its-records-as-its-actors
  (with-test-app ()
    (let ((scenario (run-scenario "two-customers")))
      (is (equal "two-customers" (scenario-name scenario)))
      (is (equal '("employee:anna" "viewer:vera") (scenario-actors scenario)))
      (is (equal "To kunder, laget av Anna." (scenario-description scenario)))
      (is (= 2 (jget (call-ok "customers_list" "viewer:vera") "returned")))))
  (is (find "two-customers" (scenario-names) :test #'string=))
  (signals error (run-scenario "two-customers") "a scenario needs an application")
  (with-test-app ()
    (signals error (run-scenario "no-such-scenario"))))

(test a-scenarios-actors-are-checked-when-it-is-compiled
  (dolist (actors '(("anna") ("employee:") ("root:anna") (:anna)))
    (signals error (macroexpand-1 `(define-scenario broken (:actors ,actors)))
      "~s is refused" actors))
  (eval '(define-scenario empty () "Ingenting."))
  (unwind-protect
       (with-test-app ()
         (is (equal "Ingenting." (scenario-description (run-scenario "empty")))
             "a scenario may make nothing"))
    (remhash '("TUN.TESTS" . "empty") tun.test-support::*scenarios*)))

(test a-preview-serves-with-claimed-identity-only
  (signals error (serve-preview 'application :argv '("tun" "--port" "1" "--db" "x"))))

(test a-preview-is-named-after-its-client-and-branch
  (is (equal "tracker-board-paging" (tun.cli:preview-name "tracker" "board-paging")))
  (is (equal "tracker-feature-drag-card" (tun.cli:preview-name "tracker" "Feature/Drag_Card")))
  (is (equal "tracker-1a2b3c4" (tun.cli:preview-name "tracker" "1a2b3c4")))
  (is (equal "tracker" (tun.cli:preview-name "tracker" nil))))

(test a-previews-branch-is-named-before-the-first-commit-too
  (let ((directory (cli-scratch-directory)))
    (flet ((git (&rest arguments)
             (uiop:run-program (list* "git" "-C" (namestring directory) arguments)
                               :output nil :error-output nil)))
      (ensure-directories-exist directory)
      (unwind-protect
           (progn
             (git "init" "--quiet" "--initial-branch=board-paging")
             (is (equal "board-paging" (tun.cli:worktree-branch directory))
                 "a new repository, as tun new leaves it")
             (git "-c" "user.name=t" "-c" "user.email=t@localhost"
                  "commit" "--quiet" "--allow-empty" "-m" "x")
             (git "checkout" "--quiet" "--detach")
             (is (cl-ppcre:scan "^[0-9a-f]{7,}$" (tun.cli:worktree-branch directory))
                 "a detached head is its revision"))
        (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))))

(test a-previews-revision-is-dirty-from-its-own-directory-only
  (let* ((directory (cli-scratch-directory))
         (client (merge-pathnames "apps/a/" directory)))
    (flet ((git (&rest arguments)
             (uiop:run-program (list* "git" "-C" (namestring directory) "-c" "user.name=t"
                                      "-c" "user.email=t@localhost" arguments)
                               :output nil :error-output nil))
           (put (path)
             (let ((file (merge-pathnames path directory)))
               (ensure-directories-exist file)
               (with-open-file (out file :direction :output :if-exists :supersede)
                 (write-line "x" out)))))
      (unwind-protect
           (progn
             (ensure-directories-exist client)
             (git "init" "--quiet")
             (put "apps/a/pages.lisp")
             (git "add" "--all")
             (git "commit" "--quiet" "-m" "x")
             (is (cl-ppcre:scan "^[0-9a-f]{7,}$" (tun.cli:worktree-revision client)))
             (put "apps/b/other.lisp")
             (put "root.txt")
             (is (not (search "dirty" (tun.cli:worktree-revision client)))
                 "another directory's change does not count")
             (put "apps/a/new.lisp")
             (is (search "-dirty" (tun.cli:worktree-revision client))))
        (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))))

(test a-preview-is-shared-on-the-tailnet-only
  (is (equal '("tailscale" "serve" "--bg" "--https=4201" "http://127.0.0.1:4201")
             (tun.cli:share-command 4201)))
  (is (equal '("tailscale" "serve" "--https=4201" "off") (tun.cli:unshare-command 4201)))
  (is (notany (lambda (part) (search "funnel" part)) (tun.cli:share-command 4201))))

(test a-previews-server-loads-the-client-and-its-scenarios
  (flet ((after (part command) (rest (member part command :test #'string=))))
    (let ((command (tun.cli:server-command "acme" #p"/srv/acme/" nil
                                           '("--port" "4200" "--claimed-identity"))))
      (is (equal "(load (sb-ext:posix-getenv \"ASDF\"))" (first (after "--eval" command)))
          "on the Tun the client's shell gives")
      (is (equal '("env" "-u" "CL_SOURCE_REGISTRY" "-u" "ASDF_OUTPUT_TRANSLATIONS" "sbcl")
                 (subseq command 0 6))
          "without the ASDF configuration of tun's own launcher")
      (is (some (lambda (part) (search "(:directory \"/srv/acme/\")" part)) command))
      (is (some (lambda (part) (search "(asdf:load-system \"acme/tests\")" part)) command)
          "with its tests system, where its scenarios are")
      (is (some (lambda (part) (search "\"SERVE-PREVIEW\"" part)) command))
      (is (equal '("--port" "4200" "--claimed-identity") (after "--end-toplevel-options" command))))
    (let ((command (tun.cli:server-command "acme" #p"/srv/acme/" "/srv/tun"
                                           '("--claimed-identity"))))
      (is (equal "/srv/tun/scripts/setup.lisp" (first (after "--load" command)))
          "or on a working tree of Tun")
      (is (some (lambda (part) (search "(\"/srv/acme/\" \"/srv/tun/.build/preview-fasl/acme/\")" part))
                command)
          "whose client files compile apart from the shell's"))))

(test a-previews-server-loads-the-client-s-own-modules-from-the-working-tree
  ;; A module kept in the client's modules/ (tun-platform.md 2.1) is named
  ;; in the source registry right after the client, before what the dev
  ;; shell or Tun's working tree offers (preview.md 2).
  (let* ((client (cli-scratch-directory))
         (modules (namestring (merge-pathnames "modules/" client))))
    (ensure-directories-exist (merge-pathnames "modules/notes/" client))
    (flet ((registry (command)
             (find-if (lambda (part) (search "initialize-source-registry" part)) command)))
      (dolist (worktree (list nil "/srv/tun"))
        (let* ((form (registry (tun.cli:server-command "acme" client worktree '())))
               (own (search (format nil "(:tree ~s)" modules) form)))
          (is (and own (< (search (format nil "(:directory ~s)" (namestring client)) form) own))
              "~:[from the shell~;on Tun's working tree~]: the client, then its modules: ~a" worktree form)
          (when own
            (is (< own (search ":inherit-configuration" form)) "before the shell's")
            (when worktree
              (is (< own (search "/srv/tun/" form)) "before Tun's own"))))))
    (is (not (search "(:tree" (find-if (lambda (part) (search "initialize-source-registry" part))
                                       (tun.cli:server-command "acme" #p"/srv/acme/" nil '()))))
        "a client without modules/ names none")))

(defun with-state-home (function)
  "Call FUNCTION with XDG_STATE_HOME naming a fresh directory, so the
previews it sees are its own."
  (let ((directory (cli-scratch-directory))
        (before (uiop:getenv "XDG_STATE_HOME")))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn (sb-posix:setenv "XDG_STATE_HOME" (namestring directory) 1)
                (funcall function))
      (if before
          (sb-posix:setenv "XDG_STATE_HOME" before 1)
          (sb-posix:unsetenv "XDG_STATE_HOME"))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(defun with-runtime-home (function)
  "Call FUNCTION with XDG_RUNTIME_DIR naming a fresh, short directory, so a
preview's database it starts has its socket where no other preview's is.
Its claims are its own (WITH-STATE-HOME): without this, another builder's
preview that has claimed the same port and is still making its database
would start a Postgres in the same socket directory.  Its port is from
FREE-TEST-PORTS, for the same reason."
  (let ((directory (uiop:ensure-directory-pathname
                    (format nil "/tmp/tun-test-~a" (new-id "r"))))
        (before (uiop:getenv "XDG_RUNTIME_DIR")))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn (sb-posix:setenv "XDG_RUNTIME_DIR" (namestring directory) 1)
                (funcall function))
      (if before
          (sb-posix:setenv "XDG_RUNTIME_DIR" before 1)
          (sb-posix:unsetenv "XDG_RUNTIME_DIR"))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(defun run-tun (&rest arguments)
  "The exit status and output of the tun command line ARGUMENTS."
  (let (status)
    (let ((output (with-output-to-string (*standard-output*)
                    (let ((*error-output* *standard-output*))
                      (setf status (tun.cli:run arguments))))))
      (values status output))))

(test the-previews-on-the-machine-are-listed-and-stopped
  (with-state-home
    (lambda ()
      (multiple-value-bind (status output) (run-tun "preview" "list")
        (is (= 0 status))
        (is (search "No previews." output)))
      (let* ((ended (uiop:launch-program '("true")))
             (pid (progn (uiop:wait-process ended) (uiop:process-info-pid ended)))
             (data (merge-pathnames ".data/preview/" (cli-scratch-directory))))
        (ensure-directories-exist (merge-pathnames "server.log" data))
        (ensure-directories-exist (tun.cli:state-directory))
        (with-open-file (out (merge-pathnames "acme-main.json" (tun.cli:state-directory))
                             :direction :output)
          (write-string (to-json-string (jobj "name" "acme-main" "port" 4299 "pid" pid
                                              "url" "http://127.0.0.1:4299" "directory" "/srv/acme/"
                                              "data" (namestring data) "shared" nil))
                        out))
        (multiple-value-bind (status output) (run-tun "preview" "list" "--json")
          (is (= 0 status))
          (let ((preview (aref (parse-json output) 0)))
            (is (equal "acme-main" (jget preview "name")))
            (is (eq nil (jget preview "running")) "its process has ended")))
        (write-claim 4299 pid)
        (multiple-value-bind (status output) (run-tun "preview" "stop" "acme-main")
          (is (= 0 status))
          (is (search "Stopped acme-main." output)))
        (is (null (probe-file (tun.cli:claim-file 4299))) "its port's claim is removed")
        (is (null (uiop:directory-exists-p data)) "its database is removed")
        (is (null (directory (merge-pathnames "*.json" (tun.cli:state-directory))))
            "and its file")))))

(test tun-preview-refuses-what-it-cannot-do
  (with-state-home
    (lambda ()
      (flet ((refused (status-wanted &rest arguments)
               (multiple-value-bind (status output) (apply #'run-tun arguments)
                 (is (= status-wanted status) "~{~a~^ ~}: ~a" arguments output)
                 output)))
        (is (search "needs a NAME, or --all" (refused 2 "preview" "stop")))
        (is (search "there is no preview nope" (refused 2 "preview" "stop" "nope")))
        (is (search "unknown tun preview command" (refused 2 "preview" "start")))
        (is (search "--port takes a port number" (refused 2 "preview" "--port" "80a")))
        (is (search "no client system" (refused 1 "preview" "--dir" (namestring (cli-scratch-directory))))
            "a directory without a client")))))

(test a-clients-checks-are-its-checks-directorys-python-files
  (let ((directory (cli-scratch-directory)))
    (flet ((write-check (name text)
             (let ((file (merge-pathnames (format nil "checks/~a" name) directory)))
               (ensure-directories-exist file)
               (with-open-file (out file :direction :output) (write-string text out))
               file)))
      (unwind-protect
           (progn
             (signals tun.cli:step-failed (tun.cli:check-files directory '())
               "a client without checks")
             (write-check "board.py" (format nil "\"\"\"Tavla.\"\"\"~%SCENARIO = \"many-cards\"~%~%def run(t): pass~%"))
             (write-check "home.py" "def run(t): pass")
             (write-check "_helpers.py" "")
             (write-check "notes.txt" "")
             (is (equal '("board" "home") (mapcar #'pathname-name (tun.cli:check-files directory '()))))
             (is (equal '("home") (mapcar #'pathname-name (tun.cli:check-files directory '("home")))))
             (signals tun.cli:usage-error (tun.cli:check-files directory '("nope")))
             (is (equal "many-cards" (tun.cli:check-scenario (merge-pathnames "checks/board.py" directory))))
             (is (equal "default" (tun.cli:check-scenario (merge-pathnames "checks/home.py" directory)))))
        (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore)))))

;;; ------------------------------------------------------------------
;;; Claiming the port (spec/preview.md 2, «The port»)

(defun write-claim (port holder)
  "Make HOLDER, a process id or any text, the claim of PORT, as another
tun or a broken file would leave it."
  (let ((file (tun.cli:claim-file port)))
    (ensure-directories-exist file)
    (with-open-file (out file :direction :output :if-exists :supersede)
      (princ holder out))))

(defun claim-text (port)
  (let ((file (tun.cli:claim-file port)))
    (and (probe-file file) (string-trim '(#\Newline) (uiop:read-file-string file)))))

(defun own-pid () (princ-to-string (sb-posix:getpid)))

(defun ended-process ()
  "The id of a process that has ended."
  (let ((process (uiop:launch-program '("true"))))
    (uiop:wait-process process)
    (uiop:process-info-pid process)))

(defun call-with-live-process (function)
  "Call FUNCTION with the id of a process that runs until it returns."
  (let ((process (uiop:launch-program '("sleep" "60"))))
    (unwind-protect (funcall function (uiop:process-info-pid process))
      (uiop:terminate-process process :urgent t)
      (uiop:wait-process process))))

(defun free-preview-ports (count)
  "The first COUNT ports from 4200 that CLAIM-PORT would take, but for their
claims: nothing on this machine listens on them, and no running database
holds their socket directory, as another preview's may."
  (loop for port from 4200 below 4300
        when (and (tun.cli:port-free-p port) (not (tun.cli::socket-directory-held-p port)))
          collect port into ports
        until (= count (length ports))
        finally (return ports)))

(defun free-test-ports (count)
  "COUNT ports from 4900 that nothing on this machine listens on: outside the
range a preview takes its port from (+FIRST-PORT+ and the hundred after),
so a server a test starts never meets another builder's preview, whose
claim the test's own state directory cannot see."
  (loop for port from 4900 below 5000
        when (tun.cli:port-free-p port)
          collect port into ports
        until (= count (length ports))
        finally (return ports)))

(defun ports-files ()
  "The names of the files in ports/."
  (sort (mapcar #'file-namestring (directory (merge-pathnames "*.*" (tun.cli:ports-directory))))
        #'string<))

(defun fake-client ()
  "A directory with a client's .asd whose system does not load."
  (let ((directory (cli-scratch-directory)))
    (ensure-directories-exist directory)
    (with-open-file (out (merge-pathnames "fakeclient.asd" directory) :direction :output)
      (write-string "(defsystem \"fakeclient\" :components ((:file \"missing\")))" out))
    directory))

(test starts-at-the-same-moment-claim-different-ports
  (with-state-home
    (lambda ()
      (let* ((go nil)
             (threads (loop repeat 8
                            collect (sb-thread:make-thread
                                     (lambda ()
                                       (loop until go do (sleep 0.001))
                                       (tun.cli:claim-port :taken '())))))
             (ports (progn (setf go t) (mapcar #'sb-thread:join-thread threads))))
        (is (= 8 (length (remove-duplicates ports))) "eight different ports: ~a" ports)
        (is (every (lambda (port) (equal (own-pid) (claim-text port))) ports)
            "each claimed by this process")))))

(test a-port-whose-socket-directory-a-running-database-holds-is-skipped
  ;; A preview started under another state directory, such as a test's,
  ;; holds the socket directory of its port with no claim this one sees,
  ;; and its database listens on no TCP port.
  (with-state-home
    (lambda ()
      (let ((runtime (cli-scratch-directory))
            (before (uiop:getenv "XDG_RUNTIME_DIR"))
            (port (first (free-preview-ports 1))))
        (ensure-directories-exist runtime)
        (unwind-protect
             (progn
               (sb-posix:setenv "XDG_RUNTIME_DIR" (namestring runtime) 1)
               (let ((lock (merge-pathnames (format nil "tun-preview-~d/.s.PGSQL.5432.lock" port)
                                            runtime)))
                 (ensure-directories-exist lock)
                 (with-open-file (out lock :direction :output)
                   (format out "~d~%/somewhere/cluster~%" (own-pid))))
               (let ((claimed (tun.cli:claim-port :taken '())))
                 (is (/= port claimed) "port ~d, whose socket directory is held, skipped" port)))
          (if before
              (sb-posix:setenv "XDG_RUNTIME_DIR" before 1)
              (sb-posix:unsetenv "XDG_RUNTIME_DIR"))
          (uiop:delete-directory-tree runtime :validate t :if-does-not-exist :ignore))))))

(test a-stale-claim-is-taken-over-and-a-held-one-skipped
  (with-state-home
    (lambda ()
      (destructuring-bind (first second third) (free-preview-ports 3)
        (write-claim first (ended-process))
        (is (= first (tun.cli:claim-port :taken '())) "a stale claim is taken over")
        (is (equal (own-pid) (claim-text first)))
        (tun.cli:release-claim first (list (sb-posix:getpid)))
        (is (null (claim-text first)))
        (call-with-live-process
         (lambda (pid)
           (write-claim first pid)
           (write-claim second "ikke en prosess")
           (is (= third (tun.cli:claim-port :taken '()))
               "one a running process holds, and one that cannot be read, are skipped")
           (let ((client (namestring (fake-client))))
             (multiple-value-bind (status output)
                 (run-tun "preview" "--dir" client "--no-share" "--port" (princ-to-string first))
               (is (= 1 status) "~a" output)
               (is (search (format nil "claimed by process ~d" pid) output) "~a" output))
             (multiple-value-bind (status output)
                 (run-tun "preview" "--dir" client "--no-share" "--port" (princ-to-string second))
               (is (= 1 status) "~a" output)
               (is (search (namestring (tun.cli:claim-file second)) output) "~a" output))
             (is (equal (princ-to-string pid) (claim-text first)) "and they are left as they were")
             (is (equal "ikke en prosess" (claim-text second))))))))))

(test a-claim-is-handed-over-whole
  (with-state-home
    (lambda ()
      (let ((port (tun.cli:claim-port :taken '())))
        (call-with-live-process
         (lambda (server)
           (tun.cli:hand-over-claim port (sb-posix:getpid) server)
           (is (equal (princ-to-string server) (claim-text port)) "the server holds it now")
           (is (equal (list (princ-to-string port) "lock") (ports-files))
               "renamed into place, nothing else left")
           (tun.cli:hand-over-claim port (sb-posix:getpid) 1)
           (is (equal (princ-to-string server) (claim-text port))
               "only its holder hands it over")))))))

(test a-restart-keeps-its-port
  (with-state-home
    (lambda ()
      (let ((port (first (free-preview-ports 1))))
        (call-with-live-process
         (lambda (old-server)
           (write-claim port old-server)
           (is (= port (tun.cli:claim-port :port port :replacing old-server))
               "the restart takes the claim of the server it replaces")
           (is (equal (own-pid) (claim-text port)))
           (tun.cli:release-claim port (list old-server))
           (is (equal (own-pid) (claim-text port)) "stopping the old server leaves it")
           (is (/= port (tun.cli:claim-port :taken '()))
               "and a start meanwhile gets another port")))))))

(test a-start-that-fails-leaves-no-claim
  (with-state-home
    (lambda ()
      (let ((client (namestring (fake-client)))
            (port (first (free-preview-ports 1))))
        (let ((listener (usocket:socket-listen "127.0.0.1" port :reuse-address t)))
          (unwind-protect
               (multiple-value-bind (status output)
                   (run-tun "preview" "--dir" client "--no-share" "--port" (princ-to-string port))
                 (is (= 1 status) "~a" output)
                 (is (search "something already listens" output) "~a" output))
            (usocket:socket-close listener)))
        (is (equal '("lock") (ports-files)) "a port something listens on")
        (with-runtime-home
          (lambda ()
            (multiple-value-bind (status output)
                (run-tun "preview" "--dir" client "--no-share"
                         "--port" (princ-to-string (first (free-test-ports 1))))
              (is (= 1 status) "~a" output)
              (is (search "stopped before it answered" output) "~a" output))))
        (is (equal '("lock") (ports-files)) "a server that exits before it answers")
        (is (null (directory (merge-pathnames "*.json" (tun.cli:state-directory))))
            "and no preview's file")))))

;;; ------------------------------------------------------------------
;;; The verify lock (spec/preview.md 4)

(defun call-with-lock-variable (path function)
  "Call FUNCTION with TUN_VERIFY_LOCK naming PATH, and no holder's mark."
  (let ((before (uiop:getenv "TUN_VERIFY_LOCK")))
    (sb-posix:unsetenv "TUN_VERIFY_LOCK_HELD")
    (sb-posix:setenv "TUN_VERIFY_LOCK" (namestring path) 1)
    (unwind-protect (funcall function)
      (if before
          (sb-posix:setenv "TUN_VERIFY_LOCK" before 1)
          (sb-posix:unsetenv "TUN_VERIFY_LOCK")))))

(defun lock-path ()
  (let ((directory (cli-scratch-directory)))
    (ensure-directories-exist directory)
    (merge-pathnames "verify.lock" directory)))

(defun wait-for (predicate &optional (seconds 60))
  "Ask PREDICATE until it is true, for at most SECONDS; its last value."
  (loop with watch = (start-stopwatch)
        for value = (funcall predicate)
        until (or value (stopwatch-past-p watch seconds))
        do (sleep 0.05)
        finally (return value)))

(defun flock-exit (path)
  "The exit status of flock -n PATH true: 0 when no one holds PATH's lock."
  (nth-value 2 (uiop:run-program (list "flock" "-n" (namestring path) "true")
                                 :ignore-error-status t)))

(defvar *kept-output* (make-hash-table :test 'eq :synchronized t))

(defun get-output-stream-string-keeping (stream)
  "All STREAM has been given so far: GET-OUTPUT-STREAM-STRING empties it."
  (setf (gethash stream *kept-output*)
        (concatenate 'string (gethash stream *kept-output* "") (get-output-stream-string stream))))

(test the-verify-lock-waits-for-its-holder-says-so-and-a-killed-one-releases-it
  (let* ((path (lock-path))
         ;; -o: flock's command does not keep the lock; flock itself holds it.
         (holder (uiop:launch-program (list "flock" "-o" (namestring path) "sleep" "60")))
         (pid (uiop:process-info-pid holder))
         (output (make-string-output-stream)))
    (unwind-protect
         (call-with-lock-variable
          path
          (lambda ()
            (is (wait-for (lambda () (member pid (tun.cli::flock-holders (namestring path)))))
                "/proc/locks names flock's process as the holder")
            (let ((waiter (sb-thread:make-thread
                           (lambda ()
                             (let ((*standard-output* output))
                               (tun.cli::call-with-verify-lock (lambda () :ran)))))))
              (is (wait-for (lambda () (search "waiting for the verify lock"
                                               (get-output-stream-string-keeping output)))
                            30)
                  "the second says it waits")
              (let ((said (get-output-stream-string-keeping output)))
                (is (search (format nil "held by process ~d (flock -o" pid) said) "~a" said))
              (is (sb-thread:thread-alive-p waiter) "and does not run while flock holds it")
              (uiop:terminate-process holder :urgent t)
              (is (eq :ran (sb-thread:join-thread waiter :timeout 30 :default :still-waiting))
                  "a holder killed releases it")
              (let ((said (get-output-stream-string-keeping output)))
                (is (search "took the verify lock" said) "~a" said)))))
      (uiop:terminate-process holder :urgent t)
      (uiop:wait-process holder))))

(test a-holder-of-the-verify-lock-excludes-flock-and-its-children-do-not-wait
  (let ((path (lock-path)))
    (call-with-lock-variable
     path
     (lambda ()
       (is (eq :inside
               (tun.cli::call-with-verify-lock
                (lambda ()
                  (is (= 1 (flock-exit path)) "flock -n cannot take it while it is held")
                  (is (equal (namestring path) (uiop:getenv "TUN_VERIFY_LOCK_HELD")))
                  (is (equal (namestring path)
                             (string-trim '(#\Newline)
                                          (uiop:run-program '("sh" "-c" "echo $TUN_VERIFY_LOCK_HELD")
                                                            :output :string)))
                      "a program the holder starts knows it holds it")
                  (is (eq :nested (tun.cli::call-with-verify-lock (lambda () :nested)))
                      "a check its verify runs does not wait for it")
                  :inside))))
       (is (= 0 (flock-exit path)) "released when it is done")
       (is (null (uiop:getenv "TUN_VERIFY_LOCK_HELD")))))))

(test a-command-under-flock-of-the-same-file-does-not-wait
  (let* ((path (lock-path))
         (holder (uiop:launch-program (list "flock" (namestring path) "sleep" "60")))
         (pid (uiop:process-info-pid holder)))
    (unwind-protect
         (let ((child (wait-for (lambda ()
                                  (let ((children (ignore-errors
                                                   (uiop:read-file-string
                                                    (format nil "/proc/~d/task/~d/children" pid pid)))))
                                    (and (plusp (length children))
                                         (parse-integer children :junk-allowed t)))))))
           (is (integerp child) "flock started its command")
           (is (wait-for (lambda () (tun.cli::ancestor-holds-p (namestring path) child)))
               "its command, flock's child, sees its ancestor holds the lock")
           (is (not (tun.cli::ancestor-holds-p (namestring path)))
               "this process, not under that flock, does not"))
      (uiop:terminate-process holder :urgent t)
      (uiop:wait-process holder))))

(test without-the-variable-nothing-is-locked
  (let ((before (uiop:getenv "TUN_VERIFY_LOCK")))
    (sb-posix:unsetenv "TUN_VERIFY_LOCK")
    (unwind-protect
         (let* ((value nil)
                (said (with-output-to-string (*standard-output*)
                        (setf value (tun.cli::call-with-verify-lock (lambda () :ran))))))
           (is (eq :ran value))
           (is (string= "" said) "and nothing is said: ~s" said))
      (when before (sb-posix:setenv "TUN_VERIFY_LOCK" before 1)))))
