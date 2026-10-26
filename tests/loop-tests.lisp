;;;; tests/loop-tests.lisp -- the feature loop (spec/loop.md): its record,
;;;; who decides a gate, a reviewer's verdict, the tree that leaves the
;;;; record out, and a loop from start to finish in a repository of its own
;;;; whose bin/test passes or fails on demand. `tun loop show` starts a
;;;; preview, so it is run by hand, not here.

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
                                                            directory)))))
            (uiop:delete-directory-tree root :validate t :if-does-not-exist :ignore)))))))
