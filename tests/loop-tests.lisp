;;;; tests/loop-tests.lisp -- the feature loop (spec/loop.md): its record,
;;;; who decides a gate, a reviewer's verdict, the tree that leaves the
;;;; record out, a loop from start to finish in a repository of its own
;;;; whose bin/test passes or fails on demand, and the same loop mirrored in
;;;; a stand-in tracker. `tun loop show` starts a preview, so it is run by
;;;; hand, not here.

(in-package #:tun.tests)

(def-suite loop :in core)
(in-suite loop)

(defparameter *loop-text*
  (format nil "# Kort bytter kolonne~%~%- loop: paging~%- mode: reviewed~%- stage: gate-a~%~
               - base: none~%~%## Brief~%~%- a list in the brief: not a field~%~%## Log~%"))

(test a-records-fields-are-read-set-and-taken-out
  (is (equal "reviewed" (tun.cli:text-field *loop-text* "mode")))
  (is (null (tun.cli:text-field *loop-text* "a list in the brief")) "only above the first section")
  (let ((text (tun.cli:set-text-field *loop-text* "stage" "build")))
    (is (equal "build" (tun.cli:text-field text "stage")))
    (is (= (count #\Newline *loop-text*) (count #\Newline text)) "in place"))
  (let ((text (tun.cli:set-text-field *loop-text* "verified" "abc")))
    (is (search (format nil "- base: none~%- verified: abc~%~%## Brief") text) "after the last field")
    (is (equal *loop-text* (tun.cli:set-text-field text "verified" nil)) "and out again")))

(test a-gate-goes-to-the-person-or-a-reviewer-by-the-mode
  (flet ((decider (mode gate &rest log)
           (tun.cli:gate-decider
            (tun.cli:make-record #p"/" "paging"
                                 (format nil "~a~{- 2026-10-24 15:00  ~a~%~}"
                                         (tun.cli:set-text-field *loop-text* "mode" mode) log))
            gate)))
    (is (eq :person (decider "hands-on" "A")))
    (is (eq :person (decider "hands-on" "B")))
    (is (eq :reviewer (decider "reviewed" "A")))
    (is (eq :reviewer (decider "reviewed" "B")))
    (is (eq :person (decider "reviewed" "C")) "a deploy is the person's")
    (is (eq :person (decider "autonomous" "C")) "no target is marked for an autonomous deploy")
    (is (eq :reviewer (decider "reviewed" "A" "gate A: changes (reviewer): x")))
    (is (eq :person (decider "reviewed" "A" "gate A: changes (reviewer): x"
                             "gate A: changes (reviewer): y"))
        "two requests for changes in a row")
    (is (eq :reviewer (decider "reviewed" "B" "gate A: changes (reviewer): x"
                               "gate A: changes (reviewer): y"))
        "at one gate")
    (is (eq :reviewer (decider "reviewed" "A" "gate A: changes (reviewer): x"
                               "gate A: changes (reviewer): y" "gate A: changes (jonas): z"))
        "the person's answer starts the count again")))

(test a-reviewers-verdict-is-its-last-verdict-line
  (is (equal '("approve" "Fint.") (multiple-value-list (tun.cli:reviewer-verdict
                                                         (format nil "Fint.~%~%VERDICT: approve~%")))))
  (is (equal "changes" (tun.cli:reviewer-verdict
                        (format nil "I could say VERDICT: approve here.~%~%**VERDICT: changes**~%"))))
  (is (null (tun.cli:reviewer-verdict "Looks good to me."))))

(defun git-in (directory &rest arguments)
  (uiop:run-program (list* "git" "-C" (namestring directory) "-c" "user.name=t"
                           "-c" "user.email=t@localhost" arguments)
                    :output :string :error-output nil))

(defun write-file-in (directory path text &key program)
  (let ((file (merge-pathnames path directory)))
    (ensure-directories-exist file)
    (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
      (write-string text out))
    (when program
      (sb-posix:chmod (namestring file) #o755))
    file))

(test a-loops-tree-leaves-out-its-record-and-what-tun-writes
  (let ((directory (cli-scratch-directory)))
    (ensure-directories-exist directory)
    (unwind-protect
         (progn
           (git-in directory "init" "--quiet")
           (write-file-in directory "a.txt" "a")
           (let ((tree (tun.cli:repository-tree directory)))
             (write-file-in directory "loops/x.md" "# x")
             (write-file-in directory ".build/loop/x/verify-1/test.log" "ok")
             (write-file-in directory ".data/loop/server.log" "ok")
             (is (equal tree (tun.cli:repository-tree directory)))
             (write-file-in directory "b.txt" "b")
             (is (not (equal tree (tun.cli:repository-tree directory))) "an untracked file counts")
             (is (equal "" (git-in directory "status" "--porcelain" "--untracked-files=no"))
                 "git's own index is untouched")
             (git-in directory "add" "--all")
             (git-in directory "commit" "--quiet" "-m" "x")
             (is (equal (tun.cli:repository-tree directory)
                        (tun.cli:repository-tree directory "HEAD"))
                 "the commit's tree is the working tree's, the record left out")))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(test a-loop-goes-from-start-to-finish-through-its-gates
  (let* ((root (cli-scratch-directory))
         (directory (merge-pathnames "repository/" root))
         (dir (namestring directory))
         (reviewer (write-file-in root "reviewer.sh"
                                  (format nil "#!/bin/sh~%cat > /dev/null~%test -e README.md || exit 1~%~
                                               echo 'Kriteriene er oppfylt.'~%echo~%~
                                               echo \"VERDICT: $(cat '~averdict')\"~%"
                                          (namestring root))
                                  :program t)))
    (ensure-directories-exist directory)
    (labels ((tun (&rest arguments)
               (apply #'run-tun "loop" (append arguments (list "--dir" dir))))
             (expect (wanted &rest arguments)
               (multiple-value-bind (status output) (apply #'tun arguments)
                 (is (= wanted status) "tun loop ~{~a~^ ~}: ~a" arguments output)
                 output))
             (stage ()
               (jget (parse-json (nth-value 1 (tun "status" "paging" "--json"))) "stage"))
             (verdict (text)
               (write-file-in root "verdict" text)))
      (with-environment-variable ("TUN_WORKTREE" (namestring (asdf:system-source-directory "tun")))
        (with-environment-variable ("TUN_REVIEWER" (namestring reviewer))
          (unwind-protect
               (progn
                 (git-in directory "init" "--quiet")
                 (write-file-in directory "demo.asd" "(defsystem \"demo\")")
                 (write-file-in directory "bin/test" (format nil "#!/bin/sh~%test ! -e fail~%")
                                :program t)
                 (git-in directory "add" "--all")
                 (git-in directory "commit" "--quiet" "-m" "demo")
                 (is (search "No open loop" (expect 0 "status")))
                 (is (search "a loop's name matches" (expect 2 "start" "Paging" "--title" "x")))
                 (expect 0 "start" "paging" "--title" "Kort bytter kolonne" "--mode" "reviewed")
                 (is (search "exists already" (expect 2 "start" "paging" "--title" "x")))
                 (is (equal "brief" (stage)))
                 (is (search "needs the criteria" (expect 1 "gate" "A")))
                 (let ((file (merge-pathnames "loops/paging.md" directory)))
                   (write-file-in directory "loops/paging.md"
                                  (cl-ppcre:regex-replace "## Criteria\\n"
                                                          (uiop:read-file-string file)
                                                          (format nil "## Criteria~%~%1. Et kort.~%"))))
                 (is (search "runs at gate-a" (expect 1 "decide" "A" "approve" "--by" "jonas")))
                 (verdict "changes")
                 (is (search "answered changes" (expect 0 "gate" "A")))
                 (is (equal "brief" (stage)) "changes at A go back to the brief")
                 (verdict "approve")
                 (is (search "answered approve" (expect 0 "gate" "A")))
                 (is (equal "build" (stage)))
                 (write-file-in directory "fail" "")
                 (dotimes (round 5)
                   (expect 1 "verify"))
                 (is (equal "stuck" (stage)) "five failed rounds in a row")
                 (is (search "runs at build or verified or shown or ship" (expect 1 "verify")))
                 (expect 0 "resume" "--by" "jonas" "--why" "«prøv igjen»")
                 (delete-file (merge-pathnames "fail" directory))
                 (write-file-in directory "pages.lisp" ";; the change")
                 (expect 0 "verify")
                 (is (equal "verified" (stage)))
                 (is (search "runs at shown" (expect 1 "gate" "B")))
                 ;; What tun loop show records, without its preview.
                 (let* ((file (merge-pathnames "loops/paging.md" directory))
                        (text (uiop:read-file-string file)))
                   (write-file-in directory "loops/paging.md"
                                  (tun.cli:set-text-field
                                   (tun.cli:set-text-field text "stage" "shown")
                                   "shown" (tun.cli:text-field text "verified"))))
                 (expect 0 "log" "an agent's line")
                 (expect 0 "gate" "B")
                 (is (equal "ship" (stage)))
                 (is (search "not the tree that was shown" (expect 1 "gate" "C")) "nothing committed")
                 (git-in directory "add" "--all")
                 (git-in directory "commit" "--quiet" "-m" "the change")
                 (is (search "waits for the person" (expect 0 "gate" "C")) "a deploy is the person's")
                 (is (search "the person's to decide" (expect 2 "decide" "C" "approve" "--by" "reviewer")))
                 (is (search "needs --why" (expect 2 "decide" "C" "changes" "--by" "jonas")))
                 (expect 0 "decide" "C" "approve" "--by" "jonas" "--why" "«kjør»")
                 (expect 0 "finish")
                 (is (equal "done" (stage)))
                 (is (search "the loops done are paging" (expect 0 "status")))
                 (let ((log (uiop:read-file-string (merge-pathnames "loops/paging.md" directory))))
                   (dolist (line '("started, reviewed" "gate A: changes (reviewer)"
                                   "  Kriteriene er oppfylt." "gate A: approve (reviewer)"
                                   "verify 5: failed test" "resumed (jonas): «prøv igjen»"
                                   "verify 6: passed test" "an agent's line"
                                   "gate B: approve (reviewer)" "gate C asked of the person"
                                   "gate C: approve (jonas): «kjør»" "finished at demo"))
                     (is (search line log) "the log has ~s" line)))
                 (is (probe-file (merge-pathnames ".build/loop/paging/gate-B-1/diff.patch" directory)))
                 (is (search "pages.lisp" (uiop:read-file-string
                                           (merge-pathnames ".build/loop/paging/gate-B-1/diff.patch"
                                                            directory))))
                 (is (not (search "tracker:" (uiop:read-file-string
                                              (merge-pathnames "loops/paging.md" directory))))
                     "without TUN_TRACKER, no tracker")
                 (is (not (probe-file (merge-pathnames ".build/loop/paging/tracker.log" directory)))))
            (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))))))

;;; The tracker (spec/loop.md 6.1)

(defun demo-repository (directory)
  "A repository in DIRECTORY whose bin/test fails while a file fail exists."
  (ensure-directories-exist directory)
  (git-in directory "init" "--quiet")
  (write-file-in directory "demo.asd" "(defsystem \"demo\")")
  (write-file-in directory "bin/test" (format nil "#!/bin/sh~%test ! -e fail~%") :program t)
  (git-in directory "add" "--all")
  (git-in directory "commit" "--quiet" "-m" "demo"))

(defun with-criteria (directory name)
  "Give the record NAME in DIRECTORY a criterion, as an agent writes one."
  (let ((file (merge-pathnames (format nil "loops/~a.md" name) directory)))
    (write-file-in directory (format nil "loops/~a.md" name)
                   (cl-ppcre:regex-replace "## Criteria\\n" (uiop:read-file-string file)
                                           (format nil "## Criteria~%~%1. Et kort.~%")))))

(defun as-shown (directory name)
  "What tun loop show records once its preview runs, without the preview."
  (let ((record (tun.cli:read-record directory name)))
    (tun.cli:record-shown record (tun.cli:text-field (uiop:read-file-string
                                                      (merge-pathnames (format nil "loops/~a.md" name)
                                                                       directory))
                                                     "verified")
                          "https://preview.example/paging" '("/saker" "/saker/1"))))

(defun tracker-calls (file)
  "The calls a stand-in tracker wrote to FILE, each (event record input)."
  (if (probe-file file)
      (mapcar (lambda (line)
                (destructuring-bind (event record json) (cl-ppcre:split " " line :limit 3)
                  (list event record (parse-json json))))
              (remove "" (uiop:read-file-lines file) :test #'string=))
      '()))

(test a-loop-is-mirrored-in-the-tracker-event-by-event
  (let* ((root (cli-scratch-directory))
         (directory (merge-pathnames "repository/" root))
         (dir (namestring directory))
         (calls (merge-pathnames "calls" root))
         (tracker (write-file-in root "tracker.sh"
                                 (format nil "#!/bin/sh~%test \"$1\" = --quiet && shift~%~
                                              { printf '%s %s ' \"$1\" \"$2\"; cat; echo; } >> '~a'~%~
                                              test \"$1\" = start && printf '\\n  https://tracker.example/items/7  \\n'~%~
                                              exit 0~%"
                                         (namestring calls))
                                 :program t))
         (reviewer (write-file-in root "reviewer.sh"
                                  (format nil "#!/bin/sh~%cat > /dev/null~%echo 'Kriteriene er oppfylt.'~%~
                                               echo~%echo 'VERDICT: approve'~%")
                                  :program t)))
    (labels ((tun (&rest arguments)
               (apply #'run-tun "loop" (append arguments (list "--dir" dir))))
             (expect (wanted &rest arguments)
               (multiple-value-bind (status output) (apply #'tun arguments)
                 (is (= wanted status) "tun loop ~{~a~^ ~}: ~a" arguments output)
                 output)))
      (with-environment-variable ("TUN_WORKTREE" (namestring (asdf:system-source-directory "tun")))
        (with-environment-variable ("TUN_REVIEWER" (namestring reviewer))
          (with-environment-variable ("TUN_TRACKER" (format nil "'~a' --quiet" (namestring tracker)))
            (unwind-protect
                 (progn
                   (demo-repository directory)
                   (expect 0 "start" "paging" "--title" "Kort bytter kolonne" "--mode" "reviewed")
                   (is (search "item https://tracker.example/items/7"
                               (expect 0 "status" "paging"))
                       "the tracker's first line that is not blank is the item")
                   (expect 2 "start" "paging" "--title" "x")
                   (expect 1 "gate" "A")
                   (with-criteria directory "paging")
                   (expect 0 "gate" "A")
                   (write-file-in directory "fail" "")
                   (dotimes (round 5)
                     (expect 1 "verify"))
                   (expect 0 "resume" "--by" "jonas" "--why" "«prøv igjen»")
                   (delete-file (merge-pathnames "fail" directory))
                   (expect 0 "verify")
                   (as-shown directory "paging")
                   (expect 0 "log" "an agent's line")
                   (expect 0 "gate" "B")
                   (git-in directory "add" "--all")
                   (git-in directory "commit" "--quiet" "-m" "the change")
                   (expect 0 "gate" "C")
                   (expect 0 "decide" "C" "approve" "--by" "jonas" "--why" "«kjør»")
                   (expect 0 "finish")
                   (let* ((calls (tracker-calls calls))
                          (record (namestring (merge-pathnames "loops/paging.md" directory))))
                     (is (equal '("start" "gate" "decide" "verify" "verify" "verify" "verify" "verify"
                                  "resume" "verify" "show" "log" "gate" "decide" "gate" "decide" "finish")
                                (mapcar #'first calls))
                         "each event once, and none for a refused step")
                     (is (every (lambda (call) (equal record (second call))) calls))
                     (flet ((input (event &optional (n 0))
                              (third (nth n (remove event calls :key #'first :test-not #'string=))))
                            (member-of (event key &optional (n 0))
                              (jget (third (nth n (remove event calls :key #'first :test-not #'string=)))
                                    key)))
                       (let ((start (input "start")))
                         (is (equal "paging" (jget start "loop")))
                         (is (equal "Kort bytter kolonne" (jget start "title")))
                         (is (equal "reviewed" (jget start "mode")))
                         (is (equal "brief" (jget start "stage")))
                         (is (json-null-p (jget start "item")) "the item comes from the answer")
                         (is (equal (string-right-trim "/" dir) (jget start "repository")))
                         (is (cl-ppcre:scan "^\\d{4}-\\d\\d-\\d\\dT\\d\\d:\\d\\d:\\d\\d[+-]\\d\\d:\\d\\d$"
                                            (jget start "time"))))
                       (is (equal "https://tracker.example/items/7" (member-of "finish" "item"))
                           "later events carry the item")
                       (is (equal "reviewer" (member-of "gate" "decider")))
                       (is (json-null-p (member-of "gate" "message")) "a reviewer is told nothing")
                       (is (equal "approve" (member-of "decide" "decision")))
                       (is (equal "reviewer" (member-of "decide" "by")))
                       (is (json-null-p (member-of "decide" "why")))
                       (is (search "Kriteriene er oppfylt." (member-of "decide" "reasons")))
                       (is (equal 1 (member-of "verify" "round")))
                       (is (null (member-of "verify" "passed")))
                       (is (equalp #("test") (member-of "verify" "failed")))
                       (is (equalp #("test") (member-of "verify" "steps")))
                       (is (equal "stuck" (member-of "verify" "stage" 4)))
                       (is (eq t (member-of "verify" "passed" 5)))
                       (is (equalp #() (member-of "verify" "failed" 5)))
                       (is (equal "«prøv igjen»" (member-of "resume" "why")))
                       (is (equal "https://preview.example/paging" (member-of "show" "preview"))
                           "the tracker gets the link")
                       (is (equalp #("/saker" "/saker/1") (member-of "show" "paths")))
                       (is (equal "an agent's line" (member-of "log" "line")))
                       (is (equal "C" (member-of "gate" "gate" 2)))
                       (is (equal "person" (member-of "gate" "decider" 2)))
                       (is (eql 0 (search "«Kort bytter kolonne» is ready for gate C"
                                          (member-of "gate" "message" 2)))
                           "the person's gate carries what they are to be told")
                       (is (equal "«kjør»" (member-of "decide" "why" 2)))
                       (let ((commit (aref (member-of "finish" "commits") 0)))
                         (is (equal "demo" (jget commit "repository")))
                         (is (equal (string-trim '(#\Newline) (git-in directory "rev-parse" "--short" "HEAD"))
                                    (jget commit "revision"))))
                       (is (equal "done" (member-of "finish" "stage"))))))
              (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))))))

(test a-tracker-that-fails-or-hangs-leaves-a-line-and-the-loop-goes-on
  (let* ((root (cli-scratch-directory))
         (directory (merge-pathnames "repository/" root))
         (dir (namestring directory))
         (failing (write-file-in root "failing.sh"
                                 (format nil "#!/bin/sh~%cat > /dev/null~%echo https://tracker.example/1~%~
                                              echo 'the tracker is down' >&2~%exit 3~%")
                                 :program t))
         (child (merge-pathnames "child" root))
         (hanging (write-file-in root "hanging.sh"
                                 (format nil "#!/bin/sh~%sleep 30 &~%echo $! > '~a'~%sleep 30~%"
                                         (namestring child))
                                 :program t))
         (long (write-file-in root "long.sh"
                              (format nil "#!/bin/sh~%cat > /dev/null~%printf '%0600d\\n' 0~%")
                              :program t)))
    (labels ((tun (&rest arguments)
               (apply #'run-tun "loop" (append arguments (list "--dir" dir))))
             (log-text (name)
               (uiop:read-file-string (merge-pathnames (format nil "loops/~a.md" name) directory))))
      (with-environment-variable ("TUN_WORKTREE" (namestring (asdf:system-source-directory "tun")))
        (unwind-protect
             (progn
               (demo-repository directory)
               (with-environment-variable ("TUN_TRACKER" (namestring failing))
                 (is (= 0 (tun "start" "down" "--title" "x")) "the step goes on")
                 (is (= 0 (tun "log" "a line" "down")))
                 (let ((text (log-text "down")))
                   (is (search "tracker: start failed: exit 3" text))
                   (is (search "tracker: log failed: exit 3" text))
                   (is (search "a line" text) "the log line is kept")
                   (is (null (tun.cli:text-field text "item")) "a failed answer is not read")
                   (is (= 2 (cl-ppcre:count-matches "tracker:" text)) "a failure line sends no event of its own"))
                 (is (search "the tracker is down"
                             (uiop:read-file-string
                              (merge-pathnames ".build/loop/down/tracker.log" directory)))))
               (with-environment-variable ("TUN_TRACKER" (namestring hanging))
                 (let ((tun.cli:*tracker-limit* 1)
                       (started (get-internal-real-time)))
                   (is (= 0 (tun "start" "slow" "--title" "x")))
                   (is (< (- (get-internal-real-time) started) (* 10 internal-time-units-per-second))
                       "stopped at the limit")
                   (is (search "tracker: start failed: no answer within 1 s, stopped" (log-text "slow")))
                   (let ((pid (parse-integer (uiop:read-file-string child) :junk-allowed t)))
                     (is (loop repeat 40
                               thereis (let ((status (probe-file (format nil "/proc/~d/status" pid))))
                                         (or (null status)
                                             (search "State:	Z" (uiop:read-file-string status))))
                               do (sleep 0.05))
                         "what the tracker started is stopped with it"))))
               (with-environment-variable ("TUN_TRACKER" (namestring long))
                 (is (= 0 (tun "start" "long" "--title" "x")))
                 (is (null (tun.cli:text-field (log-text "long") "item")))
                 (is (search "more than 500; not taken" (log-text "long"))))
               (with-environment-variable ("TUN_TRACKER" (namestring failing))
                 (is (= 0 (tun "start" "given" "--title" "x" "--item" "OPS-12")))
                 (is (equal "OPS-12" (tun.cli:text-field (log-text "given") "item"))
                     "with --item, the tracker's answer is not read")
                 (is (equal "OPS-12" (jget (parse-json (nth-value 1 (tun "status" "given" "--json")))
                                           "item"))))
               (is (= 2 (tun "start" "broken" "--title" "x" "--item" (format nil "a~%b"))))
               (is (= 2 (tun "start" "empty" "--title" "x" "--item" " "))))
          (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))))

;;; The preview's link stays out of the record (spec/loop.md 5)

(test a-shown-loop-keeps-its-preview-link-out-of-the-record
  (let* ((root (cli-scratch-directory))
         (directory (merge-pathnames "repository/" root))
         (dir (namestring directory))
         (file (merge-pathnames "loops/paging.md" directory)))
    (labels ((tun (&rest arguments)
               (apply #'run-tun "loop" (append arguments (list "--dir" dir)))))
      (with-environment-variable ("TUN_WORKTREE" (namestring (asdf:system-source-directory "tun")))
        (with-environment-variable ("TUN_TRACKER" nil)
          (with-environment-variable ("TUN_REVIEWER" nil)
            (unwind-protect
                 (progn
                   (demo-repository directory)
                   (tun "start" "paging" "--title" "Kort bytter kolonne" "--mode" "hands-on")
                   (is (json-null-p (jget (parse-json (nth-value 1 (tun "status" "--json"))) "preview"))
                       "no link before a show")
                   (with-criteria directory "paging")
                   (tun "gate" "A")
                   (tun "decide" "A" "approve" "--by" "jonas")
                   (tun "verify")
                   (as-shown directory "paging")
                   (let ((text (uiop:read-file-string file)))
                     (is (null (tun.cli:text-field text "preview")))
                     (is (not (search "preview.example" text)) "no link anywhere in the record")
                     (is (search "shown (/saker, /saker/1)" text)))
                   (is (equal (format nil "https://preview.example/paging~%")
                              (uiop:read-file-string
                               (merge-pathnames ".build/loop/paging/show/link" directory))))
                   (is (equal "https://preview.example/paging"
                              (jget (parse-json (nth-value 1 (tun "status" "--json"))) "preview")))
                   (multiple-value-bind (status output) (tun "gate" "B")
                     (is (= 0 status))
                     (is (search "Open https://preview.example/paging" output)
                         "the person is told the link"))
                   (is (equal (format nil "https://preview.example/paging~%")
                              (uiop:read-file-string
                               (merge-pathnames ".build/loop/paging/gate-B-1/link" directory)))
                       "the packet carries it")
                   (is (not (search "preview.example" (uiop:read-file-string file)))))
              (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))))))

(test saving-a-record-takes-out-an-older-tun-loops-links
  (let ((text (format nil "# x~%~%- loop: x~%- stage: shown~%- preview: https://box.example:4204~%~%~
                           ## Log~%~%- 2026-10-26 16:23  shown at https://box.example:4204 (/, /a)~%~
                           - 2026-10-26 16:24  an agent's line: shown at noon (x)~%")))
    (let ((clean (tun.cli:without-links text)))
      (is (null (tun.cli:text-field clean "preview")))
      (is (search "- 2026-10-26 16:23  shown (/, /a)" clean))
      (is (not (search "box.example" clean)))
      (is (search "an agent's line: shown at noon (x)" clean) "only tun loop's own show lines"))))

;;; rebase (spec/loop.md 6)

(test a-loop-is-rebased-when-its-repository-moves-under-it
  (let* ((root (cli-scratch-directory))
         (directory (merge-pathnames "repository/" root))
         (dir (namestring directory))
         (calls (merge-pathnames "calls" root))
         (tracker (write-file-in root "tracker.sh"
                                 (format nil "#!/bin/sh~%{ printf '%s %s ' \"$1\" \"$2\"; cat; echo; } >> '~a'~%"
                                         (namestring calls))
                                 :program t)))
    (labels ((tun (&rest arguments)
               (apply #'run-tun "loop" (append arguments (list "--dir" dir))))
             (expect (wanted &rest arguments)
               (multiple-value-bind (status output) (apply #'tun arguments)
                 (is (= wanted status) "tun loop ~{~a~^ ~}: ~a" arguments output)
                 output))
             (record ()
               (uiop:read-file-string (merge-pathnames "loops/paging.md" directory)))
             (head ()
               (string-trim '(#\Newline) (git-in directory "rev-parse" "HEAD")))
             (diff ()
               (tun.cli:loop-diff (tun.cli:read-record directory "paging") :stat t)))
      (with-environment-variable ("TUN_WORKTREE" (namestring (asdf:system-source-directory "tun")))
        (with-environment-variable ("TUN_REVIEWER" nil)
          (with-environment-variable ("TUN_TRACKER" (namestring tracker))
            (unwind-protect
                 (progn
                   (demo-repository directory)
                   (expect 0 "start" "paging" "--title" "Kort bytter kolonne" "--mode" "reviewed")
                   (let ((first-base (head)))
                     (with-criteria directory "paging")
                     (expect 0 "gate" "A")
                     (is (search "runs at brief or build" (expect 1 "rebase")) "not at a gate")
                     (expect 0 "decide" "A" "approve" "--by" "reviewer")
                     (write-file-in directory "pages.lisp" ";; the change")
                     (expect 0 "verify")
                     ;; Newer work lands under the loop, as a merge of main would bring it.
                     (write-file-in directory "other.lisp" ";; someone else's work")
                     (git-in directory "add" "other.lisp")
                     (git-in directory "commit" "--quiet" "-m" "other work")
                     (is (search "other.lisp" (diff)) "before: the other work shows as the loop's")
                     (is (= 2 (tun "rebase" "--onto" "no-such-revision")) "not a commit")
                     (expect 0 "rebase")
                     (is (equal (head) (tun.cli:text-field (record) "base")))
                     (is (equal "build" (tun.cli:text-field (record) "stage")) "verified goes back to build")
                     (is (search (format nil "rebased: demo ~a → ~a" (subseq first-base 0 7) (subseq (head) 0 7))
                                 (record)))
                     (is (search "pages.lisp" (diff)))
                     (is (not (search "other.lisp" (diff))) "after: only the loop's change")
                     (let ((event (third (find "rebase" (tracker-calls calls) :key #'first :test #'string=))))
                       (is (equal "verified" (jget event "from_stage")))
                       (let ((base (aref (jget event "bases") 0)))
                         (is (equal "demo" (jget base "repository")))
                         (is (equal first-base (jget base "old")))
                         (is (equal (head) (jget base "new")))))
                     (expect 0 "rebase")
                     (is (equal "build" (tun.cli:text-field (record) "stage")) "at build it stays")
                     ;; The loop's own work committed: rebasing onto it would drop it.
                     (let ((before (head)))
                       (git-in directory "add" "pages.lisp")
                       (git-in directory "commit" "--quiet" "-m" "the change")
                       (is (search "--onto" (expect 1 "rebase")))
                       (is (equal before (tun.cli:text-field (record) "base")) "refused: unchanged")
                       (expect 0 "rebase" "--onto" "HEAD~1")
                       (is (equal before (tun.cli:text-field (record) "base")))
                       (is (search "pages.lisp" (diff))))
                     (is (search "--client-onto is for a loop with a client"
                                 (expect 2 "rebase" "--client-onto" "HEAD")))))
              (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore))))))))

(defun set-stage (directory name stage)
  "Put the loop NAME in DIRECTORY at STAGE, as the steps before would have."
  (let ((file (merge-pathnames (format nil "loops/~a.md" name) directory)))
    (write-file-in directory (format nil "loops/~a.md" name)
                   (tun.cli:set-text-field (uiop:read-file-string file) "stage" stage))))

(test rebase-moves-the-stage-only-past-build-and-refuses-where-it-would-skip-a-step
  (let* ((root (cli-scratch-directory))
         (directory (merge-pathnames "repository/" root))
         (dir (namestring directory)))
    (labels ((tun (&rest arguments)
               (apply #'run-tun "loop" (append arguments (list "--dir" dir))))
             (stage ()
               (tun.cli:text-field (uiop:read-file-string (merge-pathnames "loops/paging.md" directory))
                                   "stage")))
      (with-environment-variable ("TUN_WORKTREE" (namestring (asdf:system-source-directory "tun")))
        (with-environment-variable ("TUN_TRACKER" nil)
          (unwind-protect
               (progn
                 (demo-repository directory)
                 (tun "start" "paging" "--title" "x")
                 (write-file-in directory "pages.lisp" ";; the change")
                 (is (= 0 (tun "rebase")))
                 (is (equal "brief" (stage)) "at brief it stays")
                 (dolist (from '("shown" "ship"))
                   (set-stage directory "paging" from)
                   (is (= 0 (tun "rebase")))
                   (is (equal "build" (stage)) "~a goes back to build" from))
                 (dolist (from '("stuck" "gate-b" "deploy" "done"))
                   (set-stage directory "paging" from)
                   (multiple-value-bind (status output) (tun "rebase" "paging")
                     (is (= 1 status) "refused at ~a" from)
                     (is (search "runs at brief or build or verified or shown or ship" output)))))
            (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))))))

(test a-loop-with-a-client-rebases-both-repositories
  (let* ((root (cli-scratch-directory))
         (tun-directory (merge-pathnames "tun/" root))
         (client (merge-pathnames "client/" root))
         (dir (namestring tun-directory))
         (calls (merge-pathnames "calls" root))
         (tracker (write-file-in root "tracker.sh"
                                 (format nil "#!/bin/sh~%{ printf '%s %s ' \"$1\" \"$2\"; cat; echo; } >> '~a'~%"
                                         (namestring calls))
                                 :program t)))
    (labels ((tun (&rest arguments)
               (apply #'run-tun "loop" (append arguments (list "--dir" dir))))
             (field (key)
               (tun.cli:text-field (uiop:read-file-string (merge-pathnames "loops/paging.md" tun-directory))
                                   key))
             (head (directory)
               (string-trim '(#\Newline) (git-in directory "rev-parse" "HEAD")))
             (commit (directory file)
               (write-file-in directory file ";; work")
               (git-in directory "add" file)
               (git-in directory "commit" "--quiet" "-m" file)))
      (with-environment-variable ("TUN_WORKTREE" (namestring (asdf:system-source-directory "tun")))
        (with-environment-variable ("TUN_TRACKER" (namestring tracker))
          (unwind-protect
               (progn
                 ;; A stand-in Tun, which tun loop knows by tun.asd and bin/build, and a client.
                 (demo-repository tun-directory)
                 (write-file-in tun-directory "tun.asd" "(defsystem \"tun\")")
                 (write-file-in tun-directory "bin/build" (format nil "#!/bin/sh~%") :program t)
                 (git-in tun-directory "add" "--all")
                 (git-in tun-directory "commit" "--quiet" "-m" "tun")
                 (demo-repository client)
                 (is (= 0 (tun "start" "paging" "--title" "x" "--client" (namestring client))))
                 (write-file-in tun-directory "kernel.lisp" ";; the loop's Tun change")
                 (write-file-in client "pages.lisp" ";; the loop's client change")
                 (let ((old-client (head client)))
                   (commit client "other.lisp")
                   (is (= 0 (tun "rebase")))
                   (is (equal (head client) (field "client-base")) "the client's base moves too")
                   (let ((event (third (find "rebase" (tracker-calls calls) :key #'first
                                                                              :test #'string=))))
                     (is (= 2 (length (jget event "bases"))))
                     (let ((second (aref (jget event "bases") 1)))
                       (is (equal "demo" (jget second "repository")))
                       (is (equal old-client (jget second "old")))
                       (is (equal (head client) (jget second "new")))))
                   (let ((diff (tun.cli:loop-diff (tun.cli:read-record tun-directory "paging") :stat t)))
                     (is (search "pages.lisp" diff))
                     (is (not (search "other.lisp" diff)) "the client's newer work is not the loop's")))
                 ;; The client's own work committed: only --client-onto gets past it.
                 (let ((before (head client)))
                   (commit client "pages.lisp")
                   (multiple-value-bind (status output) (tun "rebase")
                     (is (= 1 status))
                     (is (search "--client-onto" output) "the refusal names the client's option")
                     (is (not (search "loop rebase --onto" output))))
                   (is (equal before (field "client-base")))
                   (is (= 0 (tun "rebase" "--client-onto" "HEAD~1")))
                   (is (equal before (field "client-base")))
                   (is (equal (head tun-directory) (field "base")))))
            (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))))))
