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
    (remhash "empty" tun.test-support::*scenarios*)))

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
  "The first COUNT ports from 4200 that nothing on this machine listens on."
  (loop for port from 4200 below 4300
        when (tun.cli:port-free-p port) collect port into ports
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
        (multiple-value-bind (status output) (run-tun "preview" "--dir" client "--no-share")
          (is (= 1 status) "~a" output)
          (is (search "stopped before it answered" output) "~a" output))
        (is (equal '("lock") (ports-files)) "a server that exits before it answers")
        (is (null (directory (merge-pathnames "*.json" (tun.cli:state-directory))))
            "and no preview's file")))))
