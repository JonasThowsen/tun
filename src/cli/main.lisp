;;;; cli/main.lisp -- the command line of tun (spec/cli.md 1): parse the
;;;; arguments, run a command, print its result, and turn the way it ended
;;;; into an exit status.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +usage+
  "usage: tun list [--json] [MODULE...]
       tun new NAME [MODULE...] [--dir DIR] [--tun-url URL] [--rev REV]
       tun add MODULE... [--dir DIR]
       tun update [--rev REV] [--dir DIR]
       tun preview [--dir DIR] [--scenario NAME] [--port N] [--no-share] [--json]
       tun preview list [--json]
       tun preview stop NAME... | --all
       tun check [NAME...] [--dir DIR]
       tun loop start NAME --title TEXT [--mode MODE] [--client DIR] [--after LOOP]
                      [--item REF]
       tun loop status [NAME] [--json]
       tun loop gate A|B|C [NAME]
       tun loop decide A|B|C approve|changes --by WHO [--why TEXT] [NAME]
       tun loop verify|finish [NAME]
       tun loop show [NAME] [--path PATH]... [--actor ACTOR] [--scenario NAME]
       tun loop resume --by WHO --why TEXT [NAME]
       tun loop rebase [--onto REV] [--client-onto REV] [NAME]
       tun loop log TEXT [NAME]
  (every tun loop command also takes --dir DIR)"
  "The command lines tun accepts, printed for help and after a usage error.")

;;; ------------------------------------------------------------------
;;; Arguments

(defun parse-arguments (arguments &key flags options lists)
  "Split ARGUMENTS into positional arguments and a property list of options.
FLAGS are options without a value, such as \"--json\", given as T; OPTIONS
take the next argument as their value; LISTS are options that may be given
more than once, each value collected into a list in order. The keys are
keywords named like the option: --tun-url is :TUN-URL. Refuses an unknown
option, or an option without its value."
  (let ((positional '()) (plist '()))
    (loop while arguments
          do (let ((argument (pop arguments)))
               (flet ((key () (intern (string-upcase (subseq argument 2)) :keyword)))
                 (cond ((member argument flags :test #'string=)
                        (setf (getf plist (key)) t))
                       ((member argument (append options lists) :test #'string=)
                        (when (null arguments)
                          (refuse "~a needs a value" argument))
                        (if (member argument lists :test #'string=)
                            (setf (getf plist (key)) (append (getf plist (key)) (list (pop arguments))))
                            (setf (getf plist (key)) (pop arguments))))
                       ((eql 0 (search "-" argument))
                        (refuse "unknown option ~a" argument))
                       (t (push argument positional))))))
    (values (nreverse positional) plist)))

;;; ------------------------------------------------------------------
;;; tun list

(defun print-module-summary (module)
  "One module of `tun list`: its name and description, then what it needs."
  (format t "~&~16a~a~%" (jget module "name") (jget module "description"))
  (let ((needs (coerce (jget module "depends_on") 'list)))
    (when needs
      (format t "~16tneeds ~{~a~^, ~}~%" needs))))

(defun print-names (label items)
  "A labelled line of ITEMS, filled to the right margin and indented under
the first item."
  (when (plusp (length items))
    (format t "~&  ~18a~@<~{~a~^, ~:_~}~:>~%" label (coerce items 'list))))

(defun print-module-details (module)
  "Everything `tun list MODULE` shows about one module."
  (format t "~&~a: ~a~%" (jget module "name") (jget module "description"))
  (print-names "system" (list (jget module "system")))
  (print-names "needs" (jget module "depends_on"))
  (print-names "core" (jget module "core_range"))
  (print-names "entities" (map 'list (lambda (entity)
                                       (format nil "~a (~a)" (jget entity "name")
                                               (jget entity "label")))
                               (jget module "entities")))
  (print-names "operations" (jget module "operations"))
  (print-names "screens" (jget module "screens"))
  (print-names "settings" (jget module "settings"))
  (print-names "workflows" (jget module "workflows"))
  (print-names "message templates" (jget module "message_templates"))
  (print-names "extension points" (jget module "extension_points")))

(defun list-command (names &key json)
  "tun list (spec/cli.md 2)."
  (resolve-modules names)
  (let ((catalog (module-catalog)))
    (if json
        (format t "~a~%" (to-json-string catalog))
        (let ((*print-pretty* t) (*print-right-margin* 100)
              (modules (coerce (jget catalog "modules") 'list)))
          (if names
              (loop for name in names
                    for first = t then nil
                    unless first do (terpri)
                    do (print-module-details (find name modules
                                                   :key (lambda (m) (jget m "name"))
                                                   :test #'string=)))
              (progn
                (format t "Tun ~a, revision ~a: ~d modules~%~%"
                        (jget catalog "core_version") (jget catalog "revision")
                        (length modules))
                (mapc #'print-module-summary modules)
                (format t "~%tun list MODULE shows what a module defines; ~
                           tun list --json shows every module in full.~%")))))))

;;; ------------------------------------------------------------------
;;; tun new, tun add and tun update

(defun new-command (arguments &key dir tun-url rev)
  "tun new (spec/cli.md 3)."
  (when (null arguments)
    (refuse "tun new needs a NAME"))
  (destructuring-bind (name &rest modules) arguments
    (multiple-value-bind (directory revision)
        (create-client name modules :directory dir :revision rev
                                    :tun-url (or tun-url (uiop:getenv "TUN_URL")
                                                 +default-tun-url+))
      (format t "~&Created ~a in ~a~@[ with ~{~a~^, ~}~], pinned at Tun ~a.~%~
                 Next: cd there, enter the dev shell (nix develop, or direnv allow), ~
                 run bin/test, and commit.~%"
              name (namestring directory) (resolve-modules modules) revision))))

(defun add-command (names &key dir)
  "tun add (spec/cli.md 4)."
  (when (null names)
    (refuse "tun add needs a MODULE"))
  (multiple-value-bind (added revision) (add-modules names :directory (or dir "."))
    (cond ((null revision)
           (format t "~&The client already has ~{~a~^, ~}.~%" names))
          (added
           (format t "~&Added ~{~a~^, ~}, pinned at Tun ~a.~%" added revision))
          (t
           (format t "~&Enabled ~{~a~^, ~}, which the client already pinned.~%" names)))))

(defun update-command (arguments &key dir rev)
  "tun update (spec/cli.md 5)."
  (when arguments
    (refuse "tun update takes no ~a; it moves every Tun input" (first arguments)))
  (multiple-value-bind (revision moved) (update-client :directory (or dir ".") :revision rev)
    (if (null moved)
        (format t "~&Every Tun input is already locked at ~a; nothing changed.~%" revision)
        (format t "~&Locked every Tun input at ~a:~%~:{  ~14a~a -> ~a~%~}~
                   Next: run bin/test, and commit flake.lock when it passes.~%"
                revision (loop for (name old) in moved collect (list name old revision))))))

;;; ------------------------------------------------------------------
;;; Running a command line

(defun dispatch (arguments)
  "Run the command ARGUMENTS name."
  (let ((command (first arguments))
        (arguments (rest arguments)))
    (flet ((run-with (function &rest options)
             (multiple-value-bind (positional plist) (apply #'parse-arguments arguments options)
               (apply function positional plist))))
      (cond ((member command '(nil "help" "--help" "-h") :test #'equal)
             (format t "~a~%" +usage+))
            ((string= command "list")
             (run-with #'list-command :flags '("--json")))
            ((string= command "new")
             (run-with #'new-command :options '("--dir" "--tun-url" "--rev")))
            ((string= command "add")
             (run-with #'add-command :options '("--dir")))
            ((string= command "update")
             (run-with #'update-command :options '("--dir" "--rev")))
            ((string= command "preview")
             (run-with #'preview-command :flags '("--no-share" "--json" "--all")
                                         :options '("--dir" "--scenario" "--port")))
            ((string= command "check")
             (run-with #'check-command :options '("--dir")))
            ((string= command "loop")
             (run-with #'loop-command :flags '("--json")
                                      :options '("--dir" "--title" "--mode" "--client" "--after"
                                                 "--item" "--by" "--why" "--actor" "--scenario"
                                                 "--onto" "--client-onto")
                                      :lists '("--path")))
            (t (refuse "unknown command ~a" command))))))

(defun run (arguments)
  "Run the tun command line ARGUMENTS, a list of strings, and return its exit
status: 0 when it succeeded, 1 when a step failed, 2 for a usage error
(spec/cli.md 1)."
  (check-type arguments list)
  (handler-case (progn (dispatch arguments) 0)
    (usage-error (condition)
      (format *error-output* "~&tun: ~a~%~a~%" condition +usage+)
      2)
    (step-failed (condition)
      (format *error-output* "~&tun: ~a~%" condition)
      1)
    ;; Anything else is a defect in tun itself; one line says what it was.
    (error (condition)
      (format *error-output* "~&tun: unexpected ~a: ~a~%" (type-of condition) condition)
      1)))

(defun main ()
  "Run tun with this process's command line arguments and exit with its status."
  (let ((status (run (rest sb-ext:*posix-argv*))))
    (finish-output *standard-output*)
    (sb-ext:exit :code status)))
