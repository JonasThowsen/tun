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
        (multiple-value-bind (status output) (run-tun "preview" "stop" "acme-main")
          (is (= 0 status))
          (is (search "Stopped acme-main." output)))
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
