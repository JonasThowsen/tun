;;;; cli/client.lisp -- `tun new`, `tun add` and `tun update` (spec/cli.md 3
;;;; to 6): write a client repository from the templates under template/,
;;;; add modules to one by editing the three places that name them, and lock
;;;; all of its Tun inputs at one newer revision.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; Names, URLs and revisions

(defparameter +default-tun-url+ "git+ssh://git@github.com/JonasThowsen/tun"
  "Where a client's flake fetches Tun unless --tun-url or TUN_URL says otherwise.")

(defun check-client-name (name)
  "Return NAME when it can name a client (spec/cli.md 3), else refuse it.
Tun's own systems are tun and tun-*, so a client's name is neither."
  (check-type name string)
  (unless (and (<= (length name) 40)
               (cl-ppcre:scan "^[a-z][a-z0-9-]*$" name)
               (string/= name "tun")
               (not (eql 0 (search "tun-" name))))
    (refuse "~s cannot name a client: use a-z, 0-9 and -, start with a letter, ~
             at most 40 characters, and do not use tun or start with tun-" name))
  name)

(defun check-tun-url (url)
  "Return URL when a flake input can fetch Tun from it, else refuse it. The
client adds the query (ref, dir, rev) itself, so URL has none."
  (unless (cl-ppcre:scan "^[a-z][a-z0-9+.-]*:[^\\s\"\\\\$?#]+$" url)
    (refuse "~s is not a flake URL without a query, such as ~a" url +default-tun-url+))
  url)

(defun check-revision (revision)
  "Return REVISION when it is a full commit hash, else refuse it."
  (unless (commit-revision-p revision)
    (refuse "--rev takes a full 40-character commit hash, not ~s" revision))
  revision)

(defun with-query (url parameter value)
  "URL with PARAMETER=VALUE added to its query."
  (format nil "~a~:[?~;&~]~a=~a" url (find #\? url) parameter value))

(defun module-input-url (tun-input module)
  "The flake URL of MODULE's input, given the URL of the client's tun input:
the same repository and ref, in the module's directory."
  (with-query tun-input "dir" (format nil "modules/~a" module)))

;;; ------------------------------------------------------------------
;;; Templates

(defparameter +template-files+
  '(("flake.nix" "flake.nix")
    ("deploy.nix" "deploy.nix")
    ;; Not NAME.asd: Nix's ASDF builder drops every .asd file but its own.
    ("NAME.asd.template" "{{name}}.asd")
    ("package.lisp" "package.lisp")
    ("application.lisp" "application.lisp")
    ("tests/package.lisp" "tests/package.lisp")
    ("tests/scenarios.lisp" "tests/scenarios.lisp")
    ("tests/tests.lisp" "tests/tests.lisp")
    ("tests/run.lisp" "tests/run.lisp")
    ("bin/test" "bin/test" :program)
    ("bin/serve" "bin/serve" :program)
    ("dot-envrc" ".envrc")
    ("dot-gitignore" ".gitignore")
    ("AGENTS.md" "AGENTS.md")
    ("README.md" "README.md"))
  "Each file of a new client: its template under src/cli/template/, its path
in the client (filled in like the contents), and :PROGRAM when it is one.")

(defun fill-template (text values)
  "TEXT with each {{key}} replaced by the value of key in the alist VALUES."
  (check-type text string)
  (cl-ppcre:regex-replace-all
   "\\{\\{([a-z-]+)\\}\\}" text
   (lambda (match key)
     (declare (ignore match))
     (or (cdr (assoc key values :test #'string=))
         (error "A template names {{~a}}, which has no value" key)))
   :simple-calls t))

(defun flake-input-line (indent name url)
  "The flake line that declares the input NAME at URL."
  (format nil "~ainputs.~a.url = ~s;" indent name url))

(defun client-values (name modules tun-url)
  "The template values of the client NAME, which enables MODULES and fetches
Tun from TUN-URL. Every module MODULES depend on gets a flake input too."
  (let ((tun-input (with-query tun-url "ref" "main")))
    `(("name" . ,name)
      ("package" . ,(string-upcase name))
      ("tun-input" . ,tun-input)
      ("module-inputs"
       . ,(format nil "~{~a~%~}"
                  (mapcar (lambda (module)
                            (flake-input-line "  " module (module-input-url tun-input module)))
                          (resolve-modules modules))))
      ("module-systems" . ,(format nil "~{ ~s~}" (mapcar #'module-system modules)))
      ("modules" . ,(format nil "~{ ~a~}" modules)))))

(defun template-directory ()
  (asdf:system-relative-pathname "tun-cli" "src/cli/template/"))

(defun write-text (file text)
  "Write TEXT to FILE as UTF-8, replacing what FILE held."
  (ensure-directories-exist file)
  (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string text out)))

(defun read-text (file)
  (uiop:read-file-string file :external-format :utf-8))

(defun client-files (name modules tun-url)
  "Each file of the new client NAME, which enables MODULES and fetches Tun
from TUN-URL, as (path text program-p)."
  (let ((values (client-values name modules tun-url)))
    (loop for (template target program) in +template-files+
          collect (list (fill-template target values)
                        (fill-template (read-text (merge-pathnames template (template-directory)))
                                       values)
                        program))))

(defun write-client-files (directory files)
  "Write FILES, as CLIENT-FILES returns them, into DIRECTORY."
  (loop for (path text program) in files
        for file = (uiop:merge-pathnames* (uiop:parse-unix-namestring path) directory)
        do (write-text file text)
           (when program
             (sb-posix:chmod (namestring file) #o755))))

;;; ------------------------------------------------------------------
;;; The three places that name a client's modules (spec/cli.md 4)

(defparameter +flake-input-pattern+
  "(?m)^([ \\t]*)inputs\\.([A-Za-z_][A-Za-z0-9_'-]*)\\.url[ \\t]*=[ \\t]*\"([^\"]*)\";[ \\t]*$"
  "A flake line `inputs.NAME.url = \"URL\";`, with its indentation, NAME and URL.")

(defun flake-inputs (text)
  "The (name url) of each input the flake TEXT declares on an
`inputs.NAME.url = \"URL\";` line, in order."
  (let ((inputs '()))
    (cl-ppcre:do-register-groups (indent name url) (+flake-input-pattern+ text)
      (declare (ignore indent))
      (push (list name url) inputs))
    (nreverse inputs)))

(defun add-flake-inputs (text inputs)
  "TEXT with a line for each (name url) of INPUTS after its last
`inputs.NAME.url` line, indented like that line. NIL when TEXT has none."
  (let ((end nil) (indent ""))
    (cl-ppcre:do-scans (start match-end group-starts group-ends +flake-input-pattern+ text)
      (setf end match-end
            indent (subseq text (aref group-starts 0) (aref group-ends 0))))
    (when end
      (format nil "~a~:{~%~a~}~a"
              (subseq text 0 end)
              (loop for (name url) in inputs
                    collect (list (flake-input-line indent name url)))
              (subseq text end)))))

(defun quoted-strings (text)
  "The contents of every \"…\" string in TEXT, in order."
  (let ((strings '()))
    (cl-ppcre:do-register-groups (string) ("\"([^\"]*)\"" text)
      (push string strings))
    (nreverse strings)))

(defun add-to-list-at (text pattern items listed-items format-control &key (start 0))
  "TEXT with each of ITEMS not yet listed appended, printed with
FORMAT-CONTROL, to the first list PATTERN matches from START: its first
group is the list's contents, and the match ends at the list's closing
parenthesis. LISTED-ITEMS reads the items already in the contents. NIL when
PATTERN does not match."
  (multiple-value-bind (match-start match-end group-starts group-ends)
      (cl-ppcre:scan pattern text :start start)
    (when match-start
      (let* ((listed (funcall listed-items
                              (subseq text (aref group-starts 0) (aref group-ends 0))))
             (new (remove-if (lambda (item) (member item listed :test #'string=)) items)))
        (concatenate 'string
                     (subseq text 0 (1- match-end))
                     (format nil format-control new)
                     (subseq text (1- match-end)))))))

(defun symbol-names (text)
  "The names of the symbols TEXT lists, separated by whitespace, in lowercase."
  (mapcar #'string-downcase
          (cl-ppcre:split "\\s+" (string-trim '(#\Space #\Tab #\Newline) text))))

(defun add-asd-dependencies (text systems)
  "TEXT, a client's .asd, with SYSTEMS it lacks added to the end of the
:depends-on list that starts with \"tun\". NIL when TEXT has no such list."
  (add-to-list-at text ":depends-on\\s*\\(\\s*\"tun\"([^()]*)\\)" systems
                  #'quoted-strings "~{ ~s~}"))

(defun add-application-modules (text names)
  "TEXT with the module NAMES it lacks added to the (:modules …) option of
its define-application. NIL when TEXT has no define-application with one."
  (let ((definition (search "(define-application" text)))
    (when definition
      (add-to-list-at text "\\(:modules([^()]*)\\)" names #'symbol-names "~{ ~a~}"
                      :start definition))))

;;; ------------------------------------------------------------------
;;; Running git and nix

(defun run-checked (command &rest options)
  "Run COMMAND, a program and its arguments, with the UIOP:RUN-PROGRAM
OPTIONS, and return its standard output when OPTIONS capture it. Signals
STEP-FAILED when it cannot start or exits non-zero."
  (multiple-value-bind (output error-output status)
      (handler-case (apply #'uiop:run-program command :ignore-error-status t options)
        (error (condition)
          (fail-step "cannot run ~a: ~a" (first command) condition)))
    (declare (ignore error-output))
    (unless (zerop status)
      (fail-step "~{~a~^ ~} exited with status ~d" command status))
    output))

(defun run-step (directory &rest command)
  "Run COMMAND, a program and its arguments, in DIRECTORY, writing to this
process's output. Signals STEP-FAILED when it cannot start or exits non-zero."
  (finish-output *standard-output*)
  (run-checked command :directory directory :output :interactive :error-output :interactive)
  (values))

(defun step-output (directory &rest command)
  "The standard output of COMMAND, a program and its arguments, run in
DIRECTORY. Its errors go to this process's. Signals STEP-FAILED as RUN-STEP
does."
  (run-checked command :directory directory :output :string :error-output :interactive))

(defun lock-inputs (directory inputs revision)
  "Lock the flake in DIRECTORY. Each (name url) of INPUTS is pinned at
REVISION; without one, nix locks each new input at the head of its ref.
Other inputs already locked keep their pins."
  (apply #'run-step directory "nix" "flake" "lock"
         (when revision
           (loop for (name url) in inputs
                 append (list "--override-input" name (with-query url "rev" revision))))))

(defun locked-revision (directory input)
  "The commit the flake.lock in DIRECTORY pins INPUT to."
  (let* ((file (merge-pathnames "flake.lock" directory))
         (nodes (and (probe-file file) (jget (parse-json (read-text file)) "nodes")))
         (node (jget (jget (jget nodes "root") "inputs") input))
         (revision (and (stringp node) (jget (jget (jget nodes node) "locked") "rev"))))
    (or revision
        (fail-step "~a pins no revision for the ~a input; run nix flake lock there"
                   (namestring file) input))))

;;; ------------------------------------------------------------------
;;; tun new

(defun absolute-directory (designator)
  "The directory DESIGNATOR names, relative to the current directory."
  (uiop:ensure-directory-pathname
   (uiop:merge-pathnames* (uiop:parse-native-namestring designator) (uiop:getcwd))))

(defun new-client-directory (designator)
  "The directory DESIGNATOR names, refusing one that holds anything or is a file."
  (let ((directory (absolute-directory designator)))
    (cond ((uiop:directory-exists-p directory)
           (when (or (uiop:directory-files directory) (uiop:subdirectories directory))
             (refuse "~a is not empty" (namestring directory))))
          ((uiop:file-exists-p (string-right-trim "/" (namestring directory)))
           (refuse "~a is a file" (string-right-trim "/" (namestring directory)))))
    directory))

(defun create-client (name modules &key directory (tun-url +default-tun-url+) revision)
  "Create the client repository NAME, which enables MODULES (spec/cli.md 3),
in DIRECTORY (default ./NAME). Its flake fetches Tun from TUN-URL and pins
Tun and every module at REVISION, else at this program's revision when that
is a commit, else at the head of main. Returns the directory and the
revision locked."
  (check-client-name name)
  (check-type modules list)
  (check-tun-url tun-url)
  (when revision (check-revision revision))
  (let ((modules (remove-duplicates modules :test #'string= :from-end t)))
    (resolve-modules modules)
    (let ((directory (new-client-directory (or directory name)))
          (revision (or revision (and (commit-revision-p (tun-revision)) (tun-revision)))))
      (write-client-files directory (client-files name modules tun-url))
      (run-step directory "git" "init" "--quiet")
      (run-step directory "git" "add" "--all")
      (lock-inputs directory (flake-inputs (read-text (merge-pathnames "flake.nix" directory)))
                   revision)
      (values directory (locked-revision directory "tun")))))

;;; ------------------------------------------------------------------
;;; tun add

(defun client-flake (directory)
  "The flake.nix of the client in DIRECTORY, the (name url) of its inputs
and the URL of its tun input, as three values. Signals STEP-FAILED when
there is no flake.nix or it has no tun input."
  (let ((flake (merge-pathnames "flake.nix" directory)))
    (unless (probe-file flake)
      (fail-step "~a has no flake.nix; run tun in a client's directory or give --dir"
                 (namestring directory)))
    (let* ((inputs (flake-inputs (read-text flake)))
           (tun-input (second (assoc "tun" inputs :test #'string=))))
      (unless tun-input
        (fail-step "~a has no inputs.tun.url line" (namestring flake)))
      (values flake inputs tun-input))))

(defun client-file (directory pattern acceptable-p what)
  "The one file at the top of DIRECTORY that matches PATTERN and whose text
ACCEPTABLE-P accepts. WHAT describes such a file when there is none, or
more than one."
  (let ((files (remove-if-not (lambda (file) (funcall acceptable-p (read-text file)))
                              (directory (merge-pathnames pattern directory)))))
    (if (= (length files) 1)
        (first files)
        (fail-step "found ~:[no~;more than one~] ~a at the top of ~a; edit the client by hand"
                   files what (namestring directory)))))

(defun add-modules (names &key (directory "."))
  "Add the modules NAMES to the client in DIRECTORY (spec/cli.md 4), pinned
at the revision of its tun input. Returns the modules that got flake inputs
and that revision, or NIL when the client already had every module."
  (check-type names list)
  (let* ((names (remove-duplicates names :test #'string= :from-end t))
         (wanted (resolve-modules names))
         (directory (absolute-directory directory)))
    (multiple-value-bind (flake inputs tun-input) (client-flake directory)
      (let* ((files (list flake
                          (client-file directory "*.asd"
                                       (lambda (text) (add-asd-dependencies text '()))
                                       ".asd with a :depends-on list that starts with \"tun\"")
                          (client-file directory "*.lisp"
                                       (lambda (text) (add-application-modules text '()))
                                       ".lisp file with define-application and (:modules …)")))
             (originals (mapcar #'read-text files))
             (new-inputs (loop for module in wanted
                               unless (assoc module inputs :test #'string=)
                                 collect (list module (module-input-url tun-input module))))
             (edited (list (add-flake-inputs (first originals) new-inputs)
                           (add-asd-dependencies (second originals)
                                                 (mapcar #'module-system names))
                           (add-application-modules (third originals) names))))
        (when (equal edited originals)
          (return-from add-modules nil))
        (let ((revision (locked-revision directory "tun"))
              (locked nil))
          (unwind-protect
               (progn
                 (mapc #'write-text files edited)
                 (lock-inputs directory new-inputs revision)
                 (setf locked t))
            ;; When locking fails, the client is left as it was.
            (unless locked
              (mapc #'write-text files originals)))
          (values (mapcar #'first new-inputs) revision))))))

;;; ------------------------------------------------------------------
;;; tun update

(defun url-repository (url)
  "The flake URL without its query."
  (subseq url 0 (position #\? url)))

(defun url-parameter (url parameter)
  "The value of PARAMETER in the query of URL, or NIL when it has none."
  (let ((query (position #\? url)))
    (when query
      (loop for pair in (cl-ppcre:split "&" (subseq url (1+ query)))
            for (key value) = (cl-ppcre:split "=" pair :limit 2)
            when (string= key parameter)
              return (or value "")))))

(defun tun-inputs (inputs)
  "The (name url) of each of INPUTS, as FLAKE-INPUTS returns them, that is
Tun's (spec/cli.md 5): the tun input and every input in its repository,
such as the module inputs tun new and tun add write."
  (check-type inputs list)
  (let ((tun-input (second (assoc "tun" inputs :test #'string=))))
    (when tun-input
      (remove-if-not (lambda (input)
                       (string= (url-repository (second input)) (url-repository tun-input)))
                     inputs))))

(defun git-head-location (url)
  "Where `git ls-remote` reads the head the flake input URL follows: the
repository and the ref, as two values. The ref is URL's ref, a branch
unless it starts with refs/, or HEAD when URL names none. NIL when URL is
not a git+ URL."
  (check-type url string)
  (when (eql 0 (search "git+" url))
    (let ((ref (url-parameter url "ref")))
      (values (subseq (url-repository url) (length "git+"))
              (cond ((null ref) "HEAD")
                    ((eql 0 (search "refs/" ref)) ref)
                    (t (format nil "refs/heads/~a" ref)))))))

(defun head-revision (url directory)
  "The commit at the head the flake input URL follows, read once with git
ls-remote, run in DIRECTORY."
  (multiple-value-bind (repository ref) (git-head-location url)
    (unless repository
      (fail-step "cannot read the head of ~a, which is not a git+ URL; give --rev" url))
    (let* ((output (step-output directory "git" "ls-remote" repository ref))
           (revision (first (cl-ppcre:split "\\s+" output))))
      (if (commit-revision-p revision)
          revision
          (fail-step "~a has no ~a" repository ref)))))

(defun lock-at-revision (directory inputs revision)
  "Lock each (name url) of INPUTS at REVISION in the flake in DIRECTORY, and
check that flake.lock says so. On failure, flake.lock is left as it was."
  (let* ((lock-file (merge-pathnames "flake.lock" directory))
         (original (read-text lock-file))
         (locked nil))
    (unwind-protect
         (progn
           (lock-inputs directory inputs revision)
           (loop for (name) in inputs
                 for pin = (locked-revision directory name)
                 unless (string= pin revision)
                   do (fail-step "nix flake lock left ~a at ~a, not ~a" name pin revision))
           (setf locked t))
      (unless locked
        (write-text lock-file original)))))

(defun update-client (&key (directory ".") revision)
  "Lock the Tun inputs of the client in DIRECTORY (spec/cli.md 5), its tun
input and every module input, at REVISION, else at the head its tun input
follows. Returns that revision and the (name revision) of each input that
was locked elsewhere before, or NIL when none was, and then nothing
changes. On failure, flake.lock is left as it was."
  (check-type directory string)
  (check-type revision (or null string))
  (when revision (check-revision revision))
  (let ((directory (absolute-directory directory)))
    (multiple-value-bind (flake inputs tun-input) (client-flake directory)
      (declare (ignore flake))
      (let* ((tun-inputs (tun-inputs inputs))
             (pins (loop for (name) in tun-inputs
                         collect (list name (locked-revision directory name))))
             (revision (or revision (head-revision tun-input directory)))
             (moved (remove revision pins :key #'second :test #'string=)))
        (when moved
          (lock-at-revision directory tun-inputs revision))
        (values revision moved)))))
