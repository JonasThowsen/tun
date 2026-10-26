;;;; cli/preview.lisp -- `tun preview` (spec/preview.md 2): start a client's
;;;; working tree in the background on a port of its own, with a fresh
;;;; database, anyone's sign-in and its scenario's records; share it on the
;;;; tailnet; and list and stop the previews running on this machine.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +first-port+ 4200
  "Where a preview looks for a free port when --port names none.")

(defparameter +ready-seconds+ 180
  "How long a preview's server has to answer /health, compiling included.")

;;; ------------------------------------------------------------------
;;; The client, its worktree and the preview's name

(defun client-name (directory)
  "The name of the client in DIRECTORY: its system, defined in the .asd at
the top of it."
  (pathname-name (client-file directory "*.asd"
                              (lambda (text) (search "(defsystem" text))
                              "client system (NAME.asd)")))

(defun git-line (directory &rest arguments)
  "The first line git ARGUMENTS prints in DIRECTORY, or NIL when git fails."
  (multiple-value-bind (output error-output status)
      (ignore-errors (uiop:run-program (list* "git" "-C" (namestring directory) arguments)
                                       :output :string :error-output nil
                                       :ignore-error-status t))
    (declare (ignore error-output))
    (when (eql status 0)
      (let ((line (string-trim '(#\Space #\Newline) output)))
        (and (plusp (length line)) (first (uiop:split-string line :separator '(#\Newline))))))))

(defun worktree-branch (directory)
  "The branch checked out in DIRECTORY, one without a commit yet too, else
its short revision (a detached head), else NIL."
  (or (git-line directory "symbolic-ref" "--short" "--quiet" "HEAD")
      (git-line directory "rev-parse" "--short" "HEAD")))

(defun worktree-revision (directory)
  "The short revision checked out in DIRECTORY, with -dirty when the tree
has changes, or unknown."
  (let ((revision (git-line directory "rev-parse" "--short" "HEAD")))
    (cond ((null revision) "unknown")
          ((git-line directory "status" "--porcelain") (format nil "~a-dirty" revision))
          (t revision))))

(defun preview-name (client branch)
  "The name of CLIENT's preview of BRANCH: tracker-board-paging."
  (string-trim "-" (cl-ppcre:regex-replace-all
                    "[^a-z0-9-]+" (string-downcase (format nil "~a-~a" client (or branch "")))
                    "-")))

;;; ------------------------------------------------------------------
;;; The previews running on this machine

(defun state-directory ()
  "Where each running preview has its file: $XDG_STATE_HOME/tun/previews/."
  (merge-pathnames "tun/previews/"
                   (or (uiop:getenv-absolute-directory "XDG_STATE_HOME")
                       (merge-pathnames ".local/state/" (user-homedir-pathname)))))

(defun state-file (name)
  (merge-pathnames (make-pathname :name name :type "json") (state-directory)))

(defun previews ()
  "Every preview with a file, running or not, by name."
  (sort (mapcar (lambda (file) (parse-json (read-text file)))
                (directory (merge-pathnames "*.json" (state-directory))))
        #'string< :key (lambda (preview) (jget preview "name"))))

(defun find-preview (name)
  (find name (previews) :key (lambda (preview) (jget preview "name")) :test #'string=))

(defun process-alive-p (pid)
  "True when the process PID exists."
  (handler-case (progn (sb-posix:kill pid 0) t)
    (sb-posix:syscall-error (condition)
      ;; Someone else's process: it exists, though we may not signal it.
      (= (sb-posix:syscall-errno condition) sb-posix:eperm))))

(defun preview-running-p (preview)
  (process-alive-p (jget preview "pid")))

;;; ------------------------------------------------------------------
;;; Its port, and sharing it on the tailnet

(defun port-free-p (port)
  "True when nothing listens on 127.0.0.1:PORT. Connections that ended
moments ago do not count, as the server binds with SO_REUSEADDR too."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (unwind-protect
         (handler-case (progn (sb-bsd-sockets:socket-bind socket #(127 0 0 1) port) t)
           (sb-bsd-sockets:socket-error () nil))
      (sb-bsd-sockets:socket-close socket))))

(defun choose-port (taken)
  "The first port from +FIRST-PORT+ that no preview in TAKEN has and nothing
listens on."
  (loop for port from +first-port+ below (+ +first-port+ 100)
        when (and (not (member port taken)) (port-free-p port))
          return port
        finally (fail-step "no free port from ~d to ~d" +first-port+ (+ +first-port+ 99))))

(defun tailnet-host ()
  "This machine's name on its tailnet, such as HOST.TAILNET.ts.net,
or NIL when tailscale is not installed or not connected."
  (let ((status (ignore-errors
                 (uiop:run-program '("tailscale" "status" "--json")
                                   :output :string :error-output nil))))
    (when status
      (let ((name (ignore-errors (jget (jget (parse-json status) "Self") "DNSName"))))
        (when (and (stringp name) (plusp (length name)))
          (string-right-trim "." name))))))

(defun share-command (port)
  "The tailscale command that serves 127.0.0.1:PORT over HTTPS on PORT of
this machine's tailnet name, to devices on the tailnet only."
  (list "tailscale" "serve" "--bg" (format nil "--https=~d" port)
        (format nil "http://127.0.0.1:~d" port)))

(defun unshare-command (port)
  (list "tailscale" "serve" (format nil "--https=~d" port) "off"))

(defun share (port)
  (handler-case (run-checked (share-command port) :output :string :error-output :string)
    (step-failed (condition)
      (fail-step "~a; tailscale serve needs operator rights, given once with ~
                  sudo tailscale set --operator=$USER, or start with --no-share"
                 condition))))

;;; ------------------------------------------------------------------
;;; Its database: a Postgres server of its own, made empty at every start

(defun data-directory (directory)
  (merge-pathnames ".data/preview/" directory))

(defun preview-data-p (path)
  "True for a path under a client's .data/, the only place a preview removes."
  (search "/.data/" (namestring path)))

(defun socket-directory (port)
  "Where the Postgres server of the preview on PORT has its socket: a short
path, as a socket's may be at most 107 bytes long, which a worktree's own
directory can exceed."
  (merge-pathnames (format nil "tun-preview-~d/" port)
                   (or (uiop:getenv-absolute-directory "XDG_RUNTIME_DIR") #p"/tmp/")))

(defun start-database (data socket-directory)
  "Start a new, empty Postgres server in DATA, reachable only through a
socket in SOCKET-DIRECTORY, and return the URL of its database."
  (let ((cluster (namestring (merge-pathnames "cluster/" data)))
        (socket (string-right-trim "/" (namestring socket-directory))))
    (ensure-directories-exist data)
    (ensure-directories-exist socket-directory)
    (run-checked (list "initdb" "-D" cluster "-U" "preview" "--auth=trust"
                       "--encoding=UTF8" "--no-locale")
                 :output (namestring (merge-pathnames "initdb.log" data)) :error-output :output)
    (run-checked (list "pg_ctl" "-D" cluster "-l" (namestring (merge-pathnames "postgres.log" data))
                       "-w" "-o" (format nil "-c listen_addresses= -k ~a" socket) "start")
                 :output nil)
    (run-checked (list "createdb" "-h" socket "-U" "preview" "preview"))
    (format nil "postgresql://preview@/preview?host=~a" socket)))

(defun stop-database (data)
  (ignore-errors
   (uiop:run-program (list "pg_ctl" "-D" (namestring (merge-pathnames "cluster/" data))
                           "-m" "fast" "stop")
                     :output nil :error-output nil :ignore-error-status t)))

;;; ------------------------------------------------------------------
;;; Its server

(defun lisp-form (control &rest arguments)
  "A form for sbcl's --eval, printed readably in CL-USER."
  (with-standard-io-syntax
    ;; Readably, but without #A for a string that happens to be a BASE-STRING.
    (let ((*package* (find-package "CL-USER"))
          (*print-readably* nil))
      (apply #'format nil control arguments))))

(defun server-command (client directory worktree flags)
  "The command that serves CLIENT from DIRECTORY with FLAGS: on the Tun the
client's dev shell provides, or with WORKTREE, on that working tree of Tun,
whose kernel and modules then take the place of the client's pins. The
client's files compile apart from those of its own shell then, so neither
loads files compiled against the other's Tun. The server starts without
the ASDF configuration tun's own launcher left in the environment, which
its sbcl would otherwise add to its own."
  (let ((client-directory (namestring directory)))
    (append
     (list "env" "-u" "CL_SOURCE_REGISTRY" "-u" "ASDF_OUTPUT_TRANSLATIONS"
           "sbcl" "--noinform" "--non-interactive" "--no-userinit" "--no-sysinit")
     (if worktree
         (let ((tun (namestring (uiop:ensure-directory-pathname worktree))))
           (list "--load" (namestring (merge-pathnames "scripts/setup.lisp" tun))
                 "--eval" (lisp-form "(asdf:initialize-source-registry '(:source-registry (:directory ~s) (:directory ~s) (:tree ~s) :inherit-configuration))"
                                     client-directory tun (namestring (merge-pathnames "modules/" tun)))
                 "--eval" (lisp-form "(asdf:initialize-output-translations '(:output-translations (~s ~s) (~s ~s) :inherit-configuration))"
                                     client-directory
                                     (namestring (merge-pathnames (format nil ".build/preview-fasl/~a/" client) tun))
                                     tun (namestring (merge-pathnames ".build/fasl/" tun)))))
         (list "--eval" "(load (sb-ext:posix-getenv \"ASDF\"))"
               "--eval" (lisp-form "(asdf:initialize-source-registry '(:source-registry (:directory ~s) :inherit-configuration))"
                                   client-directory)))
     (list "--eval" (lisp-form "(let ((*compile-verbose* nil) (*load-verbose* nil)) (handler-bind ((warning #'muffle-warning)) (asdf:load-system ~s)))"
                               (format nil "~a/tests" client))
           "--eval" (lisp-form "(uiop:symbol-call \"TUN.TEST-SUPPORT\" \"SERVE-PREVIEW\" (symbol-value (find-symbol \"*APPLICATION-CLASS*\" ~s)) :name ~s)"
                               (string-upcase client) client)
           "--end-toplevel-options")
     flags)))

(defun start-server (command log)
  "Start COMMAND in the background, writing to the file LOG, in a session of
its own so that it outlives the terminal and the tun that started it.
Returns its process id. setsid forks the server off; a shell in between
writes the server's process id to a file, then becomes the server."
  (let ((pid-file (make-pathname :name "server" :type "pid" :defaults log))
        (setsid (ignore-errors (string-trim '(#\Newline)
                                            (uiop:run-program '("sh" "-c" "command -v setsid")
                                                              :output :string)))))
    (if (and setsid (plusp (length setsid)))
        (progn
          (uiop:delete-file-if-exists pid-file)
          (run-checked (list* "setsid" "--fork" "sh" "-c" "echo $$ > \"$0\" && exec \"$@\""
                              (namestring pid-file) command)
                       :input nil :output (namestring log) :if-output-exists :supersede
                       :error-output :output)
          (loop repeat 100
                until (probe-file pid-file)
                do (sleep 0.05))
          (or (ignore-errors (parse-integer (read-text pid-file) :junk-allowed t))
              (fail-step "the preview's server did not start; see ~a" (namestring log))))
        ;; Without setsid, SBCL's own process group for the child keeps an
        ;; interrupt at the terminal from reaching it.
        (uiop:process-info-pid
         (uiop:launch-program command :input nil :output log :if-output-exists :supersede
                                      :error-output :output)))))

(defun log-tail (log &optional (lines 30))
  (let ((all (and (probe-file log) (uiop:read-file-lines log))))
    (format nil "~{~a~%~}" (last all lines))))

(defun health-p (port)
  (eql 200 (ignore-errors
            (nth-value 1 (drakma:http-request (format nil "http://127.0.0.1:~d/health" port)
                                              :connection-timeout 2)))))

(defun wait-until-ready (port pid log)
  "Wait until the server PID answers /health on PORT. Signals STEP-FAILED,
with the end of its LOG, when it stops or takes longer than +READY-SECONDS+.
The message carries the lines, as the log goes when the preview is
removed."
  (loop with deadline = (+ (get-universal-time) +ready-seconds+)
        until (health-p port)
        do (unless (process-alive-p pid)
             (fail-step "the preview's server stopped before it answered. Its log ended:~%~a"
                        (log-tail log)))
           (when (> (get-universal-time) deadline)
             (stop-process pid)
             (fail-step "the preview's server did not answer within ~d seconds. Its log ended:~%~a"
                        +ready-seconds+ (log-tail log)))
           (sleep 0.5)))

(defun stop-process (pid)
  "Ask the process PID to end, and end it after ten seconds if it has not."
  (ignore-errors (sb-posix:kill pid sb-posix:sigterm))
  (loop repeat 100
        while (process-alive-p pid)
        do (sleep 0.1)
        finally (when (process-alive-p pid)
                  (ignore-errors (sb-posix:kill pid sb-posix:sigkill)))))

;;; ------------------------------------------------------------------
;;; Starting and stopping

(defun local-time-string ()
  (multiple-value-bind (second minute hour day month year) (get-decoded-time)
    (format nil "~d-~2,'0d-~2,'0d ~2,'0d:~2,'0d:~2,'0d" year month day hour minute second)))

(defun tun-description (worktree)
  "Which Tun a preview runs on: the WORKTREE, or the one the client pins."
  (if worktree
      (format nil "Tun from the worktree ~a (~a)" worktree (worktree-revision worktree))
      (let ((revision (tun-revision)))
        (format nil "Tun ~a, as the client pins it" (subseq revision 0 (min 12 (length revision)))))))

(defun record-scenario (preview report)
  "Add to PREVIEW the scenario its server's REPORT names, and a sign-in
link for each of its actors."
  (let ((shown (parse-json (read-text report)))
        (url (jget preview "url")))
    (setf (jget preview "scenario") (jget shown "scenario" "")
          (jget preview "description") (jget shown "description" "")
          (jget preview "actors") (jarr (map 'list (lambda (actor)
                                                     (jobj "actor" actor
                                                           "url" (format nil "~a/login?actor=~a" url actor)))
                                             (jget shown "actors"))))
    preview))

(defun stop-preview (preview)
  "Stop PREVIEW: its server, its Postgres and its share, and remove its
database and its file."
  (let ((data (uiop:ensure-directory-pathname (jget preview "data"))))
    (stop-process (jget preview "pid"))
    (stop-database data)
    (uiop:delete-directory-tree (socket-directory (jget preview "port"))
                                :validate (lambda (path) (search "/tun-preview-" (namestring path)))
                                :if-does-not-exist :ignore)
    (when (jget preview "shared")
      (ignore-errors (uiop:run-program (unshare-command (jget preview "port"))
                                       :output nil :error-output nil :ignore-error-status t)))
    (uiop:delete-directory-tree data :validate #'preview-data-p
                                     :if-does-not-exist :ignore)
    (uiop:delete-file-if-exists (state-file (jget preview "name")))))

(defun start-preview (&key (directory ".") scenario port (share t) name data)
  "Start a preview of the client in DIRECTORY (spec/preview.md 2), stopping
the one running there first, and return its record. NAME and DATA, its
database's directory, default to the worktree's preview's; tun check gives
its own."
  (when (and port (not (cl-ppcre:scan "^[0-9]{1,5}$" port)))
    (refuse "--port takes a port number, not ~s" port))
  (let* ((directory (absolute-directory directory))
         (client (client-name directory))
         (name (or name (preview-name client (worktree-branch directory))))
         (worktree (uiop:getenv "TUN_WORKTREE"))
         (running (find-preview name)))
    (when (and running
               (string/= (jget running "directory") (namestring directory))
               (preview-running-p running))
      (refuse "~a is already a preview of ~a; stop it first with tun preview stop ~a"
              name (jget running "directory") name))
    (when running
      (stop-preview running))
    (let* ((port (cond (port (parse-integer port))
                       (running (jget running "port"))
                       (t (choose-port (mapcar (lambda (preview) (jget preview "port"))
                                               (previews))))))
           (host (and share (tailnet-host)))
           (local-url (format nil "http://127.0.0.1:~d" port))
           (url (if host (format nil "https://~a:~d" host port) local-url))
           (data (or data (data-directory directory)))
           (log (merge-pathnames "server.log" data))
           (report (merge-pathnames "report.json" data)))
      (unless (port-free-p port)
        (fail-step "something already listens on port ~d" port))
      (uiop:delete-directory-tree data :validate #'preview-data-p
                                       :if-does-not-exist :ignore)
      (let* ((database (start-database data (socket-directory port)))
             (pid (start-server (server-command client directory worktree
                                                (list* "--port" (princ-to-string port)
                                                       "--db" database
                                                       "--claimed-identity"
                                                       "--public-url" url
                                                       "--preview-report" (namestring report)
                                                       (and scenario (list "--scenario" scenario))))
                                log))
             (preview (jobj "name" name "client" client
                            "directory" (namestring directory)
                            "branch" (or (worktree-branch directory) "")
                            "revision" (worktree-revision directory)
                            "tun" (tun-description worktree)
                            "port" port "pid" pid
                            "url" url "local_url" local-url "shared" (and host t)
                            "data" (namestring data) "log" (namestring log)
                            "started" (local-time-string))))
        (ensure-directories-exist (state-directory))
        (write-text (state-file name) (to-json-string preview))
        (handler-bind ((step-failed (lambda (condition)
                                      (declare (ignore condition))
                                      (stop-preview preview))))
          (wait-until-ready port pid log)
          (when host (share port)))
        (record-scenario preview report)
        (write-text (state-file name) (to-json-string preview))
        preview))))

;;; ------------------------------------------------------------------
;;; tun preview

(defun print-preview (preview)
  "What `tun preview` prints about the PREVIEW it started."
  (format t "~&~a is running ~a (~a) on ~a.~%~%  ~a~:[~;   (tailnet only)~]~%"
          (jget preview "name") (jget preview "branch") (jget preview "revision")
          (jget preview "tun") (jget preview "url") (jget preview "shared"))
  (when (jget preview "shared")
    (format t "  ~a~%" (jget preview "local_url")))
  (let ((actors (coerce (jget preview "actors") 'list)))
    (if (string= (jget preview "scenario") "")
        (format t "~%No scenario: the database is empty.~%")
        (format t "~%Scenario ~a~@[: ~a~]~%" (jget preview "scenario")
                (let ((text (jget preview "description"))) (and (plusp (length text)) text))))
    (when actors
      (format t "~%Sign in as~%~:{  ~18a~a~%~}" (mapcar (lambda (actor)
                                                         (list (jget actor "actor") (jget actor "url")))
                                                       actors)))
    (format t "~%Log: ~a~%Stop it with: tun preview stop ~a~%"
            (jget preview "log") (jget preview "name"))))

(defun list-previews (&key json)
  "tun preview list: every preview on this machine, and whether it runs."
  (let ((previews (previews)))
    (dolist (preview previews)
      (setf (jget preview "running") (preview-running-p preview)))
    (cond (json (format t "~a~%" (to-json-string (jarr previews))))
          ((null previews) (format t "~&No previews.~%"))
          (t (format t "~&~:{~28a~:[stopped~;running~]  ~a  ~a~%~}"
                     (mapcar (lambda (preview)
                               (list (jget preview "name") (jget preview "running")
                                     (jget preview "url") (jget preview "directory")))
                             previews))))))

(defun stop-previews (names &key all)
  "tun preview stop: stop the previews NAMES, or every one."
  (when (and (null names) (not all))
    (refuse "tun preview stop needs a NAME, or --all"))
  (let ((previews (if all
                      (previews)
                      (mapcar (lambda (name)
                                (or (find-preview name)
                                    (refuse "there is no preview ~a; tun preview list shows them" name)))
                              names))))
    (dolist (preview previews)
      (stop-preview preview)
      (format t "~&Stopped ~a.~%" (jget preview "name")))
    (when (null previews)
      (format t "~&No previews.~%"))))

(defun preview-command (arguments &key dir scenario port no-share json all)
  "tun preview, tun preview list and tun preview stop (spec/preview.md 2)."
  (let ((subcommand (first arguments)))
    (cond ((null subcommand)
           (let ((preview (start-preview :directory (or dir ".") :scenario scenario :port port
                                         :share (not no-share))))
             (if json
                 (format t "~a~%" (to-json-string preview))
                 (print-preview preview))))
          ((string= subcommand "list")
           (list-previews :json json))
          ((string= subcommand "stop")
           (stop-previews (rest arguments) :all all))
          (t (refuse "unknown tun preview command ~a; it takes list or stop" subcommand)))))
