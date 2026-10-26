;;;; cli/loop.lisp -- `tun loop` (spec/loop.md 6): the feature loop's record
;;;; in loops/NAME.md, the steps that move it from stage to stage, and its
;;;; gates, which a person or a reviewer decides. Everything is files and
;;;; commands, so any agent harness, or a person, runs it the same way.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +modes+ '("hands-on" "reviewed" "autonomous")
  "The modes a loop runs in (spec/loop.md 4).")

(defparameter +verify-rounds+ 5
  "How many verify rounds may fail in a row before the loop stops and asks.")

(defparameter +gates+
  '(("A" "brief" "gate-a" "build" "brief" "the spec: the criteria and the contract's change")
    ("B" "shown" "gate-b" "ship" "build" "the preview: the change as it runs, its checks and its code")
    ("C" "ship" "gate-c" "deploy" "build" "the deploy: the commit that was shown, to be deployed"))
  "Each gate: its letter, the stage it is asked from, the stage while it
waits, the stages an approval and a request for changes move to, and what
it decides.")

(defparameter +pressure-paths+ '("src/runtime.lisp" "src/jobs/" "src/store/" "src/core/store.lisp")
  "The files of Tun whose change makes verify run the pressure suite.")

(defun pressure-command ()
  "The pressure suite verify runs on a change to +PRESSURE-PATHS+: the program
the environment variable TUN_PRESSURE names, or NIL. Load and restart
measurements need a client and its acceptance suites, which this repository
does not hold."
  (let ((program (uiop:getenv "TUN_PRESSURE")))
    (and (plusp (length program)) program)))

(defvar *tracker-limit* 30
  "Seconds the tracker may take for one event before it is stopped (spec/loop.md 6.1).")

(defparameter +item-length+ 500
  "The longest item reference a tracker's answer at start may give.")

(defun tracker-command ()
  "The tracker the loop is mirrored in: the command TUN_TRACKER names, or NIL."
  (let ((command (uiop:getenv "TUN_TRACKER")))
    (and (plusp (length command)) command)))

(defparameter +outside-the-tree+ '("loops" ".build" ".data")
  "What a loop's tree leaves out: its record, and what tun itself writes.")

;;; ------------------------------------------------------------------
;;; The record (spec/loop.md 5)

(defstruct (record (:constructor make-record (top name text)))
  "A loop's record: the repository it is in, its name and its text."
  top name text)

(defun record-file (record)
  (merge-pathnames (format nil "loops/~a.md" (record-name record)) (record-top record)))

(defun text-lines (text)
  (uiop:split-string text :separator '(#\Newline)))

(defun lines-text (lines)
  (format nil "~{~a~^~%~}" lines))

(defun fields-end (lines)
  "The position of the first section heading in LINES; the fields are above it."
  (or (position-if (lambda (line) (eql 0 (search "## " line))) lines) (length lines)))

(defun field-line (line)
  "The key and value of LINE when it is a field, `- key: value`."
  (cl-ppcre:register-groups-bind (key value) ("^- ([a-z-]+): ?(.*)$" line)
    (values key value)))

(defun text-field (text key)
  "The value of the field KEY in the record TEXT, or NIL."
  (let ((lines (text-lines text)))
    (dolist (line (subseq lines 0 (fields-end lines)))
      (multiple-value-bind (name value) (field-line line)
        (when (equal name key)
          (return value))))))

(defun set-text-field (text key value)
  "TEXT with the field KEY set to VALUE, or taken out when VALUE is NIL. A
new field goes after the last one."
  (let* ((lines (text-lines text))
         (end (fields-end lines))
         (at (position key lines :end end :test #'equal
                                 :key (lambda (line) (values (field-line line)))))
         (new (and value (format nil "- ~a: ~a" key value))))
    (lines-text
     (cond ((and at new) (append (subseq lines 0 at) (list new) (nthcdr (1+ at) lines)))
           (at (append (subseq lines 0 at) (nthcdr (1+ at) lines)))
           ((null new) lines)
           (t (let ((after (1+ (or (position-if #'field-line lines :end end :from-end t)
                                   (min 1 end)))))
                (append (subseq lines 0 after) (list new) (nthcdr after lines))))))))

(defun field (record key)
  (text-field (record-text record) key))

(defun (setf field) (value record key)
  (setf (record-text record) (set-text-field (record-text record) key value))
  value)

(defun stage (record)
  (field record "stage"))

(defun record-title (record)
  (let ((first (first (text-lines (record-text record)))))
    (string-trim " " (if (eql 0 (search "# " first)) (subseq first 2) first))))

(defun record-section (record heading)
  "The lines of the section HEADING of RECORD, without the heading."
  (let* ((lines (text-lines (record-text record)))
         (start (position (format nil "## ~a" heading) lines :test #'string=)))
    (when start
      (let ((rest (nthcdr (1+ start) lines)))
        (subseq rest 0 (or (position-if (lambda (line) (eql 0 (search "## " line))) rest)
                           (length rest)))))))

(defun log-time ()
  (subseq (local-time-string) 0 16))

(defun add-log (record line &optional block)
  "Add LINE to RECORD's log, with the lines of the text BLOCK indented under it."
  (let ((text (string-right-trim '(#\Newline #\Space) (record-text record))))
    (setf (record-text record)
          (format nil "~a~%~:[~;~%~]- ~a  ~a~%~{  ~a~%~}"
                  text (uiop:string-suffix-p text "## Log") (log-time) line
                  (and block (text-lines (string-trim '(#\Newline #\Space) block)))))))

(defun log-lines (record)
  (remove-if-not (lambda (line) (eql 0 (search "- " line))) (record-section record "Log")))

(defun decisions (record gate)
  "The decisions at GATE in RECORD's log, oldest first, each (decision by)."
  (loop for line in (log-lines record)
        for decision = (cl-ppcre:register-groups-bind (letter decision by)
                           ("^- \\S+ \\S+  gate ([ABC]): (approve|changes) \\(([^)]*)\\)" line)
                         (and (string= letter gate) (list decision by)))
        when decision collect decision))

(defun without-links (text)
  "TEXT, a record's, without the links an older tun loop wrote into it: the
field preview and the link in a log line `shown at LINK (...)`. A shared
preview's link names the machine it runs on, and the record is committed."
  (cl-ppcre:regex-replace-all "(?m)^(- \\S+ \\S+  shown) at \\S+ \\("
                              (set-text-field text "preview" nil) "\\1 ("))

(defun save-record (record)
  (setf (record-text record) (without-links (record-text record)))
  (write-text (record-file record) (record-text record)))

(defun repository-top (directory)
  (let ((top (git-line directory "rev-parse" "--show-toplevel")))
    (unless top
      (refuse "~a is not in a git repository; a loop's record is committed with its change"
              (namestring directory)))
    (uiop:ensure-directory-pathname top)))

(defun record-names (top)
  (sort (mapcar #'pathname-name (directory (merge-pathnames "loops/*.md" top))) #'string<))

(defun read-record (top name)
  (let ((file (merge-pathnames (format nil "loops/~a.md" name) top)))
    (unless (probe-file file)
      (refuse "there is no loop ~a in ~a~@[; the loops are ~{~a~^, ~}~]"
              name (namestring top) (record-names top)))
    (make-record top name (read-text file))))

(defun find-record (top name)
  "The loop NAME in the repository TOP, or without NAME its only open loop."
  (if name
      (read-record top name)
      (let ((open (remove-if (lambda (record) (equal (stage record) "done"))
                             (mapcar (lambda (name) (read-record top name)) (record-names top)))))
        (cond ((null open)
               (fail-step "~a has no open loop; start one with tun loop start NAME --title TEXT"
                       (namestring top)))
              ((rest open)
               (refuse "~a has ~d open loops, ~{~a~^, ~}; name one"
                       (namestring top) (length open) (mapcar #'record-name open)))
              (t (first open))))))

(defun record-client (record)
  (let ((client (field record "client")))
    (and client (uiop:ensure-directory-pathname client))))

(defun tun-repository-p (directory)
  (and (probe-file (merge-pathnames "tun.asd" directory))
       (probe-file (merge-pathnames "bin/build" directory))))

(defun output-directory (record &optional (relative ""))
  "Where tun loop writes what RECORD's loop produces: .build/loop/NAME/RELATIVE."
  (merge-pathnames (format nil ".build/loop/~a/~a" (record-name record) relative)
                   (record-top record)))

(defun tun-command ()
  "How the person or agent runs tun here: bin/tun in Tun's worktree."
  (if (uiop:getenv "TUN_WORKTREE") "bin/tun" "tun"))

;;; ------------------------------------------------------------------
;;; Trees and diffs

(defparameter +empty-tree+ "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
  "git's empty tree, the base of a loop started before the first commit.")

(defun git-output (directory &rest arguments)
  (string-right-trim '(#\Newline) (apply #'step-output directory "git" arguments)))

(defun git-with-index (directory index &rest arguments)
  "git ARGUMENTS in DIRECTORY on the index file INDEX instead of git's own."
  (string-right-trim '(#\Newline)
                     (apply #'step-output directory "env"
                            (format nil "GIT_INDEX_FILE=~a" (namestring index)) "git" arguments)))

(defun head-commit (directory)
  (git-line directory "rev-parse" "--verify" "--quiet" "HEAD"))

(defun repository-tree (directory &optional commit)
  "git's tree for the working tree of the repository DIRECTORY, untracked
files included, or for COMMIT; either without +OUTSIDE-THE-TREE+. It is
written through a temporary index, so git's own is untouched."
  (let ((index (merge-pathnames (format nil "tun-loop-index-~d" (sb-posix:getpid))
                                (uiop:temporary-directory))))
    (uiop:delete-file-if-exists index)
    (unwind-protect
         (progn
           (if commit
               (git-with-index directory index "read-tree" commit)
               (let ((own (git-line directory "rev-parse" "--path-format=absolute"
                                    "--git-path" "index")))
                 ;; git's own index lets add skip the files whose stat has
                 ;; not changed; without one, it hashes every file.
                 (if (and own (probe-file own))
                     (uiop:copy-file own index)
                     (git-with-index directory index "read-tree" "--empty"))
                 (git-with-index directory index "add" "--all" "--" ".")))
           (apply #'git-with-index directory index "rm" "-r" "--cached" "--quiet"
                  "--ignore-unmatch" "--" +outside-the-tree+)
           (git-with-index directory index "write-tree"))
      (uiop:delete-file-if-exists index))))

(defun loop-repositories (record)
  "The repositories RECORD's loop changes, each (directory base): its own
and its client's."
  (cons (list (record-top record) (field record "base"))
        (let ((client (record-client record)))
          (and client (list (list client (field record "client-base")))))))

(defun loop-trees (record &key committed)
  "The trees RECORD's loop is judged by, one per repository, as one string:
of the working trees, or COMMITTED of their checked-out commits."
  (format nil "~{~a~^ ~}"
          (loop for (directory) in (loop-repositories record)
                collect (repository-tree
                         directory
                         (and committed
                              (or (head-commit directory)
                                  (fail-step "~a has no commit yet" (namestring directory))))))))

(defun base-tree (base)
  (if (or (null base) (string= base "none")) +empty-tree+ base))

(defun exclusions ()
  (mapcar (lambda (path) (format nil ":(exclude)~a" path)) +outside-the-tree+))

(defun loop-diff (record &key stat)
  "The change of RECORD's loop since its base, in each repository: a patch,
or with STAT the files changed and how much. The client's paths start with
its name."
  (with-output-to-string (out)
    (loop for (directory base) in (loop-repositories record)
          for first = t then nil
          for prefix = (if first "" (format nil "~a/" (client-name directory)))
          do (write-string
              (apply #'git-output directory "diff" (if stat "--stat" "--patch")
                     (format nil "--src-prefix=a/~a" prefix) (format nil "--dst-prefix=b/~a" prefix)
                     (base-tree base) (repository-tree directory) "--" "." (exclusions))
              out)
             (terpri out))))

(defun changed-files (record)
  "The files of RECORD's own repository changed since the loop's base."
  (let ((top (record-top record)))
    (remove "" (uiop:split-string
                (apply #'git-output top "diff" "--name-only" (base-tree (field record "base"))
                       (repository-tree top) "--" "." (exclusions))
                :separator '(#\Newline))
            :test #'string=)))

;;; ------------------------------------------------------------------
;;; The tracker (spec/loop.md 6.1)

(defun iso-time ()
  "The time now, ISO 8601 with the zone's offset."
  (multiple-value-bind (second minute hour day month year weekday dst zone) (get-decoded-time)
    (declare (ignore weekday))
    (let ((offset (round (* 60 (- (if dst 1 0) zone)))))
      (format nil "~d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0d~:[-~;+~]~2,'0d:~2,'0d"
              year month day hour minute second (>= offset 0)
              (floor (abs offset) 60) (mod (abs offset) 60)))))

(defun tracker-input (record event members)
  "The JSON the tracker reads for EVENT of RECORD's loop: the members every
event has, then the event's own MEMBERS."
  (to-json-string
   (apply #'jobj "event" event "loop" (record-name record) "title" (record-title record)
          "mode" (field record "mode") "stage" (stage record)
          "item" (or (field record "item") :null)
          "repository" (string-right-trim "/" (namestring (record-top record)))
          "record" (namestring (record-file record)) "time" (iso-time)
          members)))

(defun run-tracker (record command event input)
  "Run the tracker COMMAND for EVENT with INPUT on its standard input, for at
most *TRACKER-LIMIT* seconds. Return what it printed, or NIL and why it
failed. Its standard input is a file, so SBCL starts it in a process group
of its own, and stopping that group stops whatever it started too."
  (let* ((out (output-directory record))
         (input-file (merge-pathnames "tracker-input.json" out))
         (output-file (merge-pathnames "tracker-output.txt" out)))
    (ensure-directories-exist out)
    (write-text input-file input)
    (let ((process (sb-ext:run-program "sh" (list "-c" (format nil "~a \"$@\"" command) "tun-tracker"
                                                  event (namestring (record-file record)))
                                       :search t :wait nil :directory (namestring (record-top record))
                                       :input input-file
                                       :output output-file :if-output-exists :supersede
                                       :error (merge-pathnames "tracker.log" out)
                                       :if-error-exists :append))
          (deadline (+ (get-internal-real-time) (* *tracker-limit* internal-time-units-per-second))))
      (unwind-protect
           (progn
             (loop while (and (sb-ext:process-alive-p process) (< (get-internal-real-time) deadline))
                   do (sleep 0.05))
             (cond ((sb-ext:process-alive-p process)
                    (sb-ext:process-kill process sb-unix:sigkill :process-group)
                    (sb-ext:process-wait process)
                    (values nil (format nil "no answer within ~d s, stopped" *tracker-limit*)))
                   ((zerop (sb-ext:process-exit-code process))
                    (read-text output-file))
                   (t (values nil (format nil "exit ~d" (sb-ext:process-exit-code process))))))
        (sb-ext:process-close process)
        (uiop:delete-file-if-exists input-file)
        (uiop:delete-file-if-exists output-file)))))

(defun tell-tracker (record event &rest members)
  "Tell the tracker, if there is one, about EVENT of RECORD's loop, once its
record is saved, with the event's own MEMBERS. Return what the tracker
printed. A tracker that fails adds a line to the log and nothing else: the
loop goes on as it would have."
  (let ((command (tracker-command)))
    (when command
      (multiple-value-bind (output failure)
          (run-tracker record command event (tracker-input record event members))
        (when failure
          (add-log record (format nil "tracker: ~a failed: ~a" event failure))
          (save-record record))
        output))))

(defun take-item (record output)
  "Record as RECORD's item the first line of the tracker's OUTPUT that is
not blank, at start."
  (let ((line (find-if (lambda (line) (plusp (length line)))
                       (mapcar (lambda (line) (string-trim '(#\Space #\Tab #\Return) line))
                               (text-lines (or output ""))))))
    (cond ((null line))
          ((> (length line) +item-length+)
           (add-log record (format nil "tracker: start gave an item of ~d characters, more than ~d; ~
                                        not taken" (length line) +item-length+)))
          (t (setf (field record "item") line)))
    (save-record record)))

;;; ------------------------------------------------------------------
;;; Stages and what comes next

(defun gate-stages (gate)
  (or (rest (assoc gate +gates+ :test #'string=))
      (refuse "there is no gate ~a; the gates are A, B and C" gate)))

(defun reviewer-p (by)
  (eql 0 (search "reviewer" by)))

(defun gate-decider (record gate)
  "Who decides GATE of RECORD's loop, :person or :reviewer (spec/loop.md 4):
the person in the hands-on mode, at C, and after two requests for changes
in a row from a reviewer."
  (let ((last-two (last (decisions record gate) 2)))
    (if (or (string= (field record "mode") "hands-on")
            (string= gate "C")
            (and (= 2 (length last-two))
                 (every (lambda (decision)
                          (and (string= (first decision) "changes") (reviewer-p (second decision))))
                        last-two)))
        :person
        :reviewer)))

(defun next-step (record)
  "What comes next in RECORD's loop, and who acts."
  (let ((tun (tun-command))
        (file (enough-namestring (record-file record) (record-top record))))
    (flet ((waiting (gate)
             (format nil "Waiting at gate ~a for ~:[a reviewer~;the person~]. Record the answer: ~
                          ~a loop decide ~a approve|changes --by WHO --why \"…\"."
                     gate (eq :person (gate-decider record gate)) tun gate)))
      (let ((stage (stage record)))
        (cond ((string= stage "brief")
               (format nil "Write Brief, Criteria and Decisions in ~a and change the spec; then ~
                            ~a loop gate A." file tun))
              ((string= stage "gate-a") (waiting "A"))
              ((string= stage "build")
               (format nil "Build the change, its tests, its scenario and its checks; then ~a loop verify."
                       tun))
              ((string= stage "stuck")
               (format nil "~d verify rounds failed in a row. Tell the person what fails and what ~
                            you tried, and wait. Their go-ahead: ~a loop resume --by WHO --why \"…\"."
                       +verify-rounds+ tun))
              ((string= stage "verified")
               (format nil "~a loop show --path PATH (each page that changed)." tun))
              ((string= stage "shown")
               (format nil "Look at the screenshots in ~a; then ~a loop gate B."
                       (enough-namestring (output-directory record "show/") (record-top record)) tun))
              ((string= stage "gate-b") (waiting "B"))
              ((string= stage "ship")
               (format nil "Commit the shown tree with ~a, and push only where that is authorized. ~
                            Then ~a loop gate C before a deploy, or ~a loop finish when nothing ~
                            is deployed." file tun tun))
              ((string= stage "gate-c") (waiting "C"))
              ((string= stage "deploy")
               (format nil "Deploy (spec/deploy.md), ~a loop log \"deployed …\", then ~a loop finish."
                       tun tun))
              ((string= stage "done")
               (format nil "Done. Commit ~a, and tell the asker where they asked." file))
              (t (format nil "~a has the unknown stage ~a." file stage)))))))

(defun print-next (record)
  (format t "~&~%Next: ~a~%" (next-step record)))

(defun require-stage (record command stages)
  (unless (member (stage record) stages :test #'string=)
    (fail-step "tun loop ~a runs at ~{~a~^ or ~}, and the loop ~a is at ~a. ~a"
               command stages (record-name record) (stage record) (next-step record))))

;;; ------------------------------------------------------------------
;;; start, status, log, resume and finish

(defun start-loop (top name &key title mode client after item)
  "tun loop start: write the record of a new loop NAME in TOP."
  (unless (and (stringp name) (cl-ppcre:scan "^[a-z][a-z0-9-]{0,59}$" name))
    (refuse "a loop's name matches [a-z][a-z0-9-]*, not ~s" name))
  (unless (and title (plusp (length (string-trim " " title))))
    (refuse "tun loop start needs --title, the request in a line"))
  (when (and item (or (zerop (length (string-trim " " item)))
                      (find-if (lambda (char) (member char '(#\Newline #\Return))) item)))
    (refuse "--item is one line, a link or an id, not ~s" item))
  (let ((mode (or mode "hands-on"))
        (client (and client (absolute-directory client))))
    (unless (member mode +modes+ :test #'string=)
      (refuse "the modes are ~{~a~^, ~}, not ~a" +modes+ mode))
    (when client
      (unless (tun-repository-p top)
        (refuse "--client is for a loop in Tun, shown in the client that asked"))
      (client-name client))
    (when after
      (read-record top after))
    (when (probe-file (merge-pathnames (format nil "loops/~a.md" name) top))
      (refuse "the loop ~a exists already" name))
    (let ((record (make-record top name
                               (format nil "# ~a~%~%- loop: ~a~%- mode: ~a~%- stage: brief~%- base: ~a~%~
                                            ~:[~*~*~;- client: ~a~%- client-base: ~a~%~]~
                                            ~@[- after: ~a~%~]~@[- item: ~a~%~]~
                                            ~%## Brief~%~%## Criteria~%~%## Decisions~%~%## Log~%"
                                       (string-trim " " title) name mode (or (head-commit top) "none")
                                       client (and client (string-right-trim "/" (namestring client)))
                                       (and client (or (head-commit client) "none"))
                                       after (and item (string-trim " " item))))))
      (add-log record (format nil "started, ~a" mode))
      (save-record record)
      (let ((output (tell-tracker record "start")))
        (when (and output (null item))
          (take-item record output)))
      (format t "~&Started the loop ~a in ~a, ~a.~%"
              name (enough-namestring (record-file record) top) mode)
      (print-next record))))

(defun loop-status (record &key json)
  "tun loop status: where RECORD's loop is, and what comes next."
  (let* ((stage (stage record))
         (gate (find stage +gates+ :key #'third :test #'string=))
         (decider (and gate (gate-decider record (first gate))))
         (log (last (log-lines record) 5)))
    (if json
        (format t "~a~%" (to-json-string
                          (jobj "name" (record-name record) "title" (record-title record)
                                "file" (namestring (record-file record))
                                "stage" stage "mode" (field record "mode")
                                "item" (or (field record "item") :null)
                                "waiting_for" (if decider (string-downcase decider) :null)
                                "preview" (or (preview-link record) :null)
                                "next" (next-step record)
                                "log" (jarr (mapcar (lambda (line) (subseq line 2)) log)))))
        (progn
          (format t "~&~a: ~a~%  stage ~a, ~a~@[, item ~a~]~@[, preview ~a~]~%~%~{  ~a~%~}"
                  (record-name record) (record-title record) stage (field record "mode")
                  (field record "item") (preview-link record)
                  (mapcar (lambda (line) (subseq line 2)) log))
          (print-next record)))))

(defun log-loop (record text)
  "tun loop log: add the agent's line TEXT to RECORD's log."
  (when (zerop (length (string-trim " " text)))
    (refuse "tun loop log needs a TEXT"))
  (add-log record (string-trim " " text))
  (save-record record)
  (tell-tracker record "log" "line" (string-trim " " text))
  (format t "~&Logged in ~a.~%" (record-name record))
  (print-next record))

(defun check-by (by)
  (unless (and by (cl-ppcre:scan "^[^()\\n]+$" by))
    (refuse "--by names who decided, such as jonas or reviewer, without parentheses")))

(defun resume-loop (record &key by why)
  "tun loop resume: the person's go-ahead after verify failed too often."
  (require-stage record "resume" '("stuck"))
  (check-by by)
  (unless why
    (refuse "tun loop resume needs --why, what the person said"))
  (setf (field record "stage") "build"
        (field record "failures") nil)
  (add-log record (format nil "resumed (~a): ~a" by why))
  (save-record record)
  (tell-tracker record "resume" "by" by "why" why)
  (format t "~&The loop ~a is back at build.~%" (record-name record))
  (print-next record))

(defun require-shown-commit (record)
  "Refuse unless the commits checked out are exactly the tree that was shown."
  (unless (equal (field record "shown") (loop-trees record :committed t))
    (fail-step "what is committed is not the tree that was shown at gate B. ~
                Commit exactly that, or go back: ~a loop verify" (tun-command))))

(defun finish-loop (record)
  "tun loop finish: the loop is done."
  (require-stage record "finish" '("ship" "deploy"))
  (require-shown-commit record)
  (setf (field record "stage") "done")
  (let ((commits (loop for (directory) in (loop-repositories record)
                       collect (list (client-name-or-tun directory)
                                     (git-line directory "rev-parse" "--short" "HEAD")))))
    (add-log record (format nil "finished at ~{~{~a ~a~}~^, ~}" commits))
    (save-record record)
    (tell-tracker record "finish"
                  "commits" (jarr (loop for (repository revision) in commits
                                        collect (jobj "repository" repository "revision" revision)))))
  (format t "~&The loop ~a is done.~%" (record-name record))
  (print-next record))

(defun client-name-or-tun (directory)
  (if (tun-repository-p directory) "tun" (client-name directory)))

;;; ------------------------------------------------------------------
;;; rebase

(defun commit-of (directory revision)
  "REVISION's commit in the repository DIRECTORY, or NIL when it names none."
  (git-line directory "rev-parse" "--verify" "--quiet" (format nil "~a^{commit}" revision)))

(defun changed-since-p (directory base)
  "Whether the working tree of DIRECTORY differs from BASE, a commit or
\"none\", outside +OUTSIDE-THE-TREE+. A BASE git no longer has counts as
changed."
  (handler-case (string/= (repository-tree directory (base-tree base)) (repository-tree directory))
    (step-failed () t)))

(defun rebase-loop (record &key onto client-onto)
  "tun loop rebase: move the loop's base after its repository moved under it,
to ONTO's commit or the one checked out, and the client's to CLIENT-ONTO's or
its checked-out one (spec/loop.md 6)."
  (let ((from (stage record)))
    (require-stage record "rebase" '("brief" "build" "verified" "shown" "ship"))
    (when (and client-onto (null (record-client record)))
      (refuse "--client-onto is for a loop with a client"))
    (let ((moves (loop for (directory old) in (loop-repositories record)
                       for revision in (list onto client-onto)
                       collect (list directory old
                                     (if revision
                                         (or (commit-of directory revision)
                                             (refuse "~a is not a commit in ~a"
                                                     revision (namestring directory)))
                                         (or (head-commit directory)
                                             (fail-step "~a has no commit yet"
                                                        (namestring directory))))))))
      (loop for (directory old new) in moves
            for option in '("--onto" "--client-onto")
            when (and (changed-since-p directory old) (not (changed-since-p directory new)))
              do (fail-step "~a has no change since ~a, though it had one since the loop's base: ~
                             its work is committed there. Name the commit the work builds on: ~
                             ~a loop rebase ~a REV"
                            (client-name-or-tun directory) (subseq new 0 7) (tun-command) option))
      (setf (field record "base") (third (first moves)))
      (when (second moves)
        (setf (field record "client-base") (third (second moves))))
      (when (member from '("verified" "shown" "ship") :test #'string=)
        (setf (field record "stage") "build"))
      (add-log record (format nil "rebased: ~{~a ~a → ~a~^, ~}"
                              (loop for (directory old new) in moves
                                    append (list (client-name-or-tun directory)
                                                 (if (string= old "none") old (subseq old 0 (min 7 (length old))))
                                                 (subseq new 0 7)))))
      (save-record record)
      (tell-tracker record "rebase" "from_stage" from
                    "bases" (jarr (loop for (directory old new) in moves
                                        collect (jobj "repository" (client-name-or-tun directory)
                                                      "old" old "new" new))))
      (format t "~&The loop ~a's base is ~a~:[~;, and it is back at build~].~%"
              (record-name record) (subseq (third (first moves)) 0 7) (string/= from (stage record)))
      (print-next record))))

;;; ------------------------------------------------------------------
;;; verify

(defun round-number (record prefix)
  "The number of the next directory PREFIX-N under RECORD's output."
  (1+ (reduce #'max (uiop:subdirectories (output-directory record))
              :initial-value 0
              :key (lambda (directory)
                     (or (cl-ppcre:register-groups-bind ((#'parse-integer n))
                             ((format nil "^~a-([0-9]+)$" prefix)
                              (car (last (pathname-directory directory))))
                           n)
                         0)))))

(defun verify-steps (record)
  "The steps of a verify round for RECORD (spec/loop.md 6): each
(name directory program argument...)."
  (let ((top (record-top record))
        (client (record-client record)))
    (if (tun-repository-p top)
        `(("build" ,top "bin/build")
          ("test" ,top "bin/test")
          ("check" ,top "bin/check")
          ,@(when (and (pressure-command)
                       (some (lambda (file)
                               (some (lambda (path) (eql 0 (search path file))) +pressure-paths+))
                             (changed-files record)))
              `(("pressure" ,top ,(pressure-command))))
          ,@(when (and client (browser-checks client))
              `(("client-check" ,top "bin/tun" "check" "--dir" ,(namestring client)))))
        `(("test" ,top "bin/test")
          ,@(when (browser-checks top)
              `(("check" ,top "tun" "check")))))))

(defun caller-environment ()
  "The arguments to env that give a program the ASDF settings of whoever ran
tun, which tun's launcher keeps in TUN_CALLER_*. This process's SBCL changed
them: an SBCL started with its settings would add its own a second time, and
the client's dev shell's would be missing."
  (loop for name in '("CL_SOURCE_REGISTRY" "ASDF_OUTPUT_TRANSLATIONS")
        for kept = (uiop:getenv (format nil "TUN_CALLER_~a" name))
        if (plusp (length kept))
          collect (format nil "~a=~a" name kept) into settings
        else
          append (list "-u" name) into unset
        ;; env takes its options before its settings.
        finally (return (append unset settings))))

(defun run-verify-step (directory command log)
  "Run COMMAND in DIRECTORY, with the caller's ASDF settings and its output in
the file LOG; true when it passed."
  (finish-output *standard-output*)
  (zerop (nth-value 2 (uiop:run-program (append '("env") (caller-environment) command)
                                        :directory directory :ignore-error-status t
                                        :output log :if-output-exists :supersede
                                        :error-output :output))))

(defun latest-output (record prefix)
  "RECORD's output directory PREFIX-N with the highest N, or NIL."
  (let ((n (1- (round-number record prefix))))
    (and (plusp n) (output-directory record (format nil "~a-~d/" prefix n)))))

(defun verify-loop (record)
  "tun loop verify: run the round's steps and record whether they passed."
  (require-stage record "verify" '("build" "verified" "shown" "ship"))
  (let* ((tree (loop-trees record))
         (round (round-number record "verify"))
         (out (output-directory record (format nil "verify-~d/" round)))
         (steps (verify-steps record)))
    (ensure-directories-exist out)
    (format t "~&Verify round ~d of ~a:~%" round (record-name record))
    (let* ((results
             (loop for (name directory . command) in steps
                   for log = (merge-pathnames (format nil "~a.log" name) out)
                   collect (let ((started (get-universal-time))
                                 (ok (run-verify-step directory command log)))
                             (format t "~&  ~:[FAIL~;ok  ~]  ~14a~4ds  ~a~%" ok name
                                     (- (get-universal-time) started)
                                     (enough-namestring log (record-top record)))
                             (list name ok))))
           (failed (mapcar #'first (remove-if #'second results)))
           (failures (if failed (1+ (or (ignore-errors (parse-integer (field record "failures"))) 0)) 0)))
      (write-text (merge-pathnames "summary.txt" out)
                  (format nil "Verify round ~d of ~a~%~:{~:[FAIL~;ok  ~]  ~a~%~}"
                          round (record-name record)
                          (mapcar (lambda (result) (list (second result) (first result))) results)))
      (cond (failed
             (setf (field record "stage") (if (>= failures +verify-rounds+) "stuck" "build")
                   (field record "failures") (princ-to-string failures))
             (add-log record (format nil "verify ~d: failed ~{~a~^, ~}" round failed)))
            (t
             (setf (field record "stage") "verified"
                   (field record "verified") tree
                   (field record "failures") nil)
             (add-log record (format nil "verify ~d: passed ~{~a~^, ~}" round (mapcar #'first results)))))
      (save-record record)
      (tell-tracker record "verify" "round" round "passed" (null failed)
                    "steps" (jarr (mapcar #'first results)) "failed" (jarr failed))
      (print-next record)
      (when failed
        (fail-step "verify round ~d failed: ~{~a~^, ~}" round failed)))))

;;; ------------------------------------------------------------------
;;; show

(defun shown-directory (record)
  "The client a loop is shown in: its client, the showcase in Tun, or itself."
  (let ((top (record-top record)))
    (cond ((record-client record))
          ((tun-repository-p top) (merge-pathnames "checks/showcase/" top))
          (t top))))

(defun take-screenshots (runner out url actor paths)
  "Screenshots of PATHS at URL, at a phone's width and a desktop's, signed in
as ACTOR, in OUT, taken by RUNNER; return what it says it took."
  (run-checked (append runner (list (namestring out) url (or actor "")) paths)
               :output :interactive :error-output :interactive)
  (coerce (parse-json (read-text (merge-pathnames "shots.json" out))) 'list))

(defun show-loop (record &key paths actor scenario)
  "tun loop show: the verified tree at a shared preview, with screenshots
and a report."
  (require-stage record "show" '("verified" "shown"))
  (let ((tree (loop-trees record)))
    (unless (equal tree (field record "verified"))
      (fail-step "the tree has changed since it passed verify; run ~a loop verify again"
                 (tun-command)))
    (let* ((runner (check-runner "scripts/tun_shots.py"))
           (out (output-directory record "show/"))
           (shown (shown-directory record))
           ;; A preview of the loop's own, beside the one tun preview starts
           ;; for the branch, which the person may have open.
           (preview (start-preview :directory (namestring shown) :scenario scenario
                                   :name (preview-name (client-name shown) (record-name record))
                                   :data (merge-pathnames ".data/loop/" shown)))
           (actors (coerce (jget preview "actors") 'list))
           (actor (or actor (and actors (jget (first actors) "actor"))))
           (paths (or paths '("/"))))
      (uiop:delete-directory-tree out :validate (lambda (path) (search "/.build/loop/" (namestring path)))
                                      :if-does-not-exist :ignore)
      (ensure-directories-exist out)
      (let ((shots (take-screenshots runner out (jget preview "local_url") actor paths))
            (verified (latest-output record "verify")))
        (write-text (merge-pathnames "report.md" out)
                    (format nil "# ~a~%~%The loop ~a, shown in ~a (~a, ~a) on ~a.~%~%~
                                 Open ~a~:[~;, on the tailnet only~].~%~
                                 ~@[~%Sign in as~%~%~:{- ~a: ~a~%~}~]~
                                 ~%## Changed since the loop began~%~%```~%~a```~%~
                                 ~%## Verified~%~%```~%~a```~%~
                                 ~%## Screenshots~%~%~:{- ~a, signed in as ~a: ~a, ~a~@[ (JavaScript errors: ~a)~]~%~}"
                            (record-title record) (record-name record)
                            (jget preview "name") (jget preview "branch") (jget preview "revision")
                            (jget preview "tun") (jget preview "url") (jget preview "shared")
                            (mapcar (lambda (a) (list (jget a "actor") (jget a "url"))) actors)
                            (loop-diff record :stat t)
                            (if verified (read-text (merge-pathnames "summary.txt" verified)) "")
                            (mapcar (lambda (shot)
                                      (list (jget shot "path") (or actor "nobody")
                                            (jget shot "phone") (jget shot "desktop")
                                            (let ((errors (coerce (jget shot "errors") 'list)))
                                              (and errors (format nil "~{~a~^; ~}" errors)))))
                                    shots)))
        (record-shown record tree (jget preview "url")
                      (mapcar (lambda (shot) (jget shot "path")) shots))
        (print-preview preview)
        (format t "~&~%Report and screenshots: ~a~%" (namestring out))
        (print-next record)))))

(defun preview-link (record)
  "The link of RECORD's loop's shared preview, from the last show, or NIL."
  (let ((file (output-directory record "show/link")))
    (and (probe-file file) (string-trim '(#\Newline #\Space) (read-text file)))))

(defun record-shown (record tree link paths)
  "Record that TREE was shown at the preview LINK, at PATHS. The link goes to
.build/loop/NAME/show/link, not into the record (spec/loop.md 5)."
  (let ((file (output-directory record "show/link")))
    (ensure-directories-exist file)
    (write-text file (format nil "~a~%" link)))
  (setf (field record "stage") "shown"
        (field record "shown") tree)
  (add-log record (format nil "shown (~{~a~^, ~})" paths))
  (save-record record)
  (tell-tracker record "show" "preview" link "paths" (jarr paths)))

;;; ------------------------------------------------------------------
;;; Gates

(defun gate-ready-p (record gate)
  "Refuse GATE unless its precondition holds (spec/loop.md 6)."
  (cond ((string= gate "A")
         (unless (some (lambda (line) (cl-ppcre:scan "^\\s*[0-9]+\\.\\s+\\S" line))
                       (record-section record "Criteria"))
           (fail-step "gate A needs the criteria, numbered, under ## Criteria in ~a"
                   (namestring (record-file record)))))
        ((string= gate "B")
         (unless (equal (loop-trees record) (field record "shown"))
           (fail-step "the tree has changed since it was shown; run ~a loop verify and show again"
                      (tun-command))))
        ((string= gate "C")
         (require-shown-commit record))))

(defun copy-files (pattern from to)
  "Copy the files matching PATTERN in the directory FROM into TO."
  (dolist (file (directory (merge-pathnames pattern from)))
    (uiop:copy-file file (merge-pathnames (file-namestring file) to))))

(defun write-packet (record gate)
  "Write the packet for GATE of RECORD's loop (spec/loop.md 6) and return
its directory."
  (let* ((n (round-number record (format nil "gate-~a" gate)))
         (packet (output-directory record (format nil "gate-~a-~d/" gate n)))
         (instructions (read-text (tun-path "docs/review.md"))))
    (ensure-directories-exist packet)
    (write-text (merge-pathnames "README.md" packet)
                (format nil "~a~%~%## This packet~%~%Gate ~a of the loop ~a, «~a»: ~a. ~
                             Mode ~a.~%"
                        (string-right-trim '(#\Newline) instructions) gate (record-name record)
                        (record-title record) (sixth (assoc gate +gates+ :test #'string=))
                        (field record "mode")))
    (write-text (merge-pathnames "loop.md" packet) (record-text record))
    (write-text (merge-pathnames "diff.patch" packet) (loop-diff record))
    (unless (string= gate "A")
      (let ((verified (latest-output record "verify"))
            (checks (merge-pathnames "checks/" packet))
            (shots (merge-pathnames "shots/" packet)))
        (when verified
          (uiop:copy-file (merge-pathnames "summary.txt" verified) (merge-pathnames "verify.txt" packet)))
        (ensure-directories-exist checks)
        (dolist (directory (remove-duplicates
                            (list* (record-top record) (shown-directory record)
                                   (mapcar #'first (loop-repositories record)))
                            :test #'equal))
          (let ((results (merge-pathnames ".build/checks/" directory)))
            (copy-files "*.json" results checks)
            (copy-files "*.png" results checks)))
        (ensure-directories-exist shots)
        (copy-files "*.*" (output-directory record "show/") shots)
        (let ((link (preview-link record)))
          (when link
            (write-text (merge-pathnames "link" packet) (format nil "~a~%" link))))))
    packet))

(defun record-decision (record gate decision by why &optional reasons)
  "Record DECISION at GATE by BY, with WHY and a reviewer's REASONS, and move
RECORD's loop on."
  (destructuring-bind (from waiting approved changed what) (gate-stages gate)
    (declare (ignore from waiting what))
    (setf (field record "stage") (if (string= decision "approve") approved changed))
    (add-log record (format nil "gate ~a: ~a (~a)~@[: ~a~]" gate decision by why) reasons)
    (save-record record)
    (tell-tracker record "decide" "gate" gate "decision" decision "by" by
                  "why" (or why :null) "reasons" (or reasons :null))))

(defun reviewer-verdict (answer)
  "The verdict ANSWER ends on, \"approve\" or \"changes\", and the reasons before it."
  (let ((at nil) (verdict nil))
    (cl-ppcre:do-scans (start end starts ends "(?im)^[\\s*_`]*VERDICT:\\s*(approve|changes)\\b" answer)
      (setf at start
            verdict (string-downcase (subseq answer (aref starts 0) (aref ends 0)))))
    (values verdict (and at (string-trim '(#\Newline #\Space) (subseq answer 0 at))))))

(defun run-reviewer (record gate packet command)
  "Run the reviewer COMMAND in PACKET with its instructions on its standard
input, and record its verdict."
  (let ((answer (merge-pathnames "review.md" packet)))
    (format t "~&Gate ~a goes to the reviewer: ~a~%" gate command)
    (finish-output)
    (uiop:run-program (list "sh" "-c" command) :directory packet :ignore-error-status t
                                               :input (merge-pathnames "README.md" packet)
                                               :output answer :if-output-exists :supersede
                                               :error-output (merge-pathnames "review.log" packet)
                                               :if-error-output-exists :supersede)
    (multiple-value-bind (verdict reasons) (reviewer-verdict (read-text answer))
      (unless verdict
        (add-log record (format nil "gate ~a: the reviewer gave no verdict" gate))
        (save-record record)
        (fail-step "the reviewer gave no verdict; its answer is in ~a, and the gate is still open"
                   (namestring answer)))
      (record-decision record gate verdict "reviewer" nil reasons)
      (format t "~&The reviewer answered ~a.~%~%~a~%" verdict reasons))))

(defun person-message (record gate)
  "What the person is to be told at GATE of RECORD's loop."
  (with-output-to-string (out)
    (format out "«~a» is ready for gate ~a, ~a.~%"
            (record-title record) gate (sixth (assoc gate +gates+ :test #'string=)))
    (cond ((string= gate "A")
           (format out "~%The criteria:~%~{~a~%~}~%The change so far:~%~{  ~a~%~}"
                   (remove "" (record-section record "Criteria") :test #'string=)
                   (text-lines (string-right-trim '(#\Newline) (loop-diff record :stat t)))))
          ((string= gate "B")
           (format out "~%Open ~a, and sign in with the links in ~a.~%"
                   (preview-link record) (namestring (output-directory record "show/report.md"))))
          (t
           (format out "~%What is deployed: ~{~a~^, ~}.~%"
                   (loop for (directory) in (loop-repositories record)
                         collect (format nil "~a ~a" (client-name-or-tun directory)
                                         (git-line directory "rev-parse" "--short" "HEAD"))))))))

(defun print-person-request (gate message)
  (format t "~&Gate ~a waits for the person. Tell them, in your own words:~%~%~{  ~a~%~}"
          gate (text-lines (string-right-trim '(#\Newline) message)))
  (format t "~%Wait for their answer, then record it, quoting them:~%  ~
             ~a loop decide ~a approve|changes --by WHO --why \"…\"~%"
          (tun-command) gate))

(defun print-reviewer-request (gate packet)
  (format t "~&Gate ~a goes to a reviewer, and TUN_REVIEWER names no command to run one. ~
             Start a reviewer in a fresh session of any agent, one that does not share your ~
             context, in ~a, with:~%~%  Read README.md and review this packet.~%~%~
             Then record its answer: ~a loop decide ~a approve|changes --by reviewer --why \"…\"~%~
             (TUN_REVIEWER can name a command that takes the packet's README.md on its standard ~
             input, such as \"claude -p\" or \"codex exec -\".)~%"
          gate (namestring packet) (tun-command) gate))

(defun gate-loop (record gate)
  "tun loop gate: ask GATE of the one who decides it."
  (destructuring-bind (from waiting approved changed what) (gate-stages gate)
    (declare (ignore approved changed what))
    (require-stage record (format nil "gate ~a" gate) (list from waiting))
    (gate-ready-p record gate)
    (let ((packet (write-packet record gate))
          (decider (gate-decider record gate))
          (command (uiop:getenv "TUN_REVIEWER")))
      (setf (field record "stage") waiting)
      (add-log record (format nil "gate ~a asked of ~:[a reviewer~;the person~]"
                              gate (eq decider :person)))
      (save-record record)
      (let ((message (and (eq decider :person) (person-message record gate))))
        (tell-tracker record "gate" "gate" gate "decider" (string-downcase decider)
                      "message" (or message :null))
        (format t "~&The packet for gate ~a: ~a~%~%" gate (namestring packet))
        (when message
          (print-person-request gate message)))
      (cond ((eq decider :person))
            ((plusp (length command)) (run-reviewer record gate packet command))
            (t (print-reviewer-request gate packet)))
      (print-next record))))

(defun decide-loop (record gate decision &key by why)
  "tun loop decide: record the decision at the gate the loop waits at."
  (destructuring-bind (from waiting . rest) (gate-stages gate)
    (declare (ignore from rest))
    (require-stage record (format nil "decide ~a" gate) (list waiting))
    (unless (member decision '("approve" "changes") :test #'equal)
      (refuse "a decision is approve or changes, not ~a" decision))
    (check-by by)
    (when (and (string= decision "changes") (null why))
      (refuse "a request for changes needs --why, what is to change"))
    (when (and (reviewer-p by) (eq :person (gate-decider record gate)))
      (refuse "gate ~a of the loop ~a is the person's to decide, not a reviewer's"
              gate (record-name record)))
    (record-decision record gate decision by why)
    (format t "~&Gate ~a: ~a, by ~a.~%" gate decision by)
    (print-next record)))

;;; ------------------------------------------------------------------
;;; tun loop

(defun loop-command (arguments &key dir title mode client after item by why actor scenario path json
                                     onto client-onto)
  "tun loop (spec/loop.md 6)."
  (let ((top (repository-top (absolute-directory (or dir "."))))
        (subcommand (first arguments))
        (arguments (rest arguments)))
    (flet ((named-record ()
             (when (rest arguments)
               (refuse "tun loop ~a takes at most one NAME, not ~{~a~^ ~}" subcommand arguments))
             (find-record top (first arguments))))
      (cond ((null subcommand)
             (refuse "tun loop needs a command: start, status, gate, decide, verify, show, ~
                      resume, rebase, log or finish"))
            ((string= subcommand "start")
             (unless (= 1 (length arguments))
               (refuse "tun loop start takes one NAME"))
             (start-loop top (first arguments) :title title :mode mode :client client :after after
                                              :item item))
            ((and (string= subcommand "status") (null arguments)
                  (notany (lambda (name) (string/= "done" (stage (read-record top name))))
                          (record-names top)))
             (if json
                 (format t "null~%")
                 (format t "~&No open loop in ~a~@[; the loops done are ~{~a~^, ~}~].~%~
                            A request for a change starts one: ~a loop start NAME --title TEXT ~
                            ($TUN_SOURCE/docs/loop.md).~%"
                         (namestring top) (record-names top) (tun-command))))
            ((string= subcommand "status") (loop-status (named-record) :json json))
            ((string= subcommand "verify") (verify-loop (named-record)))
            ((string= subcommand "show")
             (show-loop (named-record) :paths path :actor actor :scenario scenario))
            ((string= subcommand "resume") (resume-loop (named-record) :by by :why why))
            ((string= subcommand "rebase")
             (rebase-loop (named-record) :onto onto :client-onto client-onto))
            ((string= subcommand "finish") (finish-loop (named-record)))
            ((string= subcommand "log")
             (when (null arguments)
               (refuse "tun loop log needs a TEXT"))
             (let ((text (pop arguments)))
               (log-loop (named-record) text)))
            ((string= subcommand "gate")
             (when (null arguments)
               (refuse "tun loop gate needs a gate, A, B or C"))
             (let ((gate (string-upcase (pop arguments))))
               (gate-stages gate)
               (gate-loop (named-record) gate)))
            ((string= subcommand "decide")
             (when (< (length arguments) 2)
               (refuse "tun loop decide needs a gate and a decision: A approve"))
             (let ((gate (string-upcase (pop arguments)))
                   (decision (pop arguments)))
               (gate-stages gate)
               (decide-loop (named-record) gate decision :by by :why why)))
            (t (refuse "unknown tun loop command ~a" subcommand))))))
