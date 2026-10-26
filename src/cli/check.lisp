;;;; cli/check.lisp -- `tun check` (spec/preview.md 4): run a client's
;;;; browser checks, each against a fresh preview of its scenario, and say
;;;; which passed.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

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

(defun check-command (names &key dir)
  "tun check (spec/preview.md 4): run the client's browser checks, or the
ones NAMES name, each against a fresh preview of its scenario."
  (let* ((directory (absolute-directory (or dir ".")))
         (client (client-name directory))
         (files (check-files directory names))
         (runner (check-runner))
         (out (merge-pathnames ".build/checks/" directory))
         (name (format nil "~a-check" (preview-name client (worktree-branch directory))))
         (data (merge-pathnames ".data/check/" directory)))
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
          (fail-step "~d check~:p failed" failed))))))
