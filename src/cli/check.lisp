;;;; cli/check.lisp -- `tun check` (spec/preview.md 4): run a client's
;;;; browser checks, each against a fresh preview of its scenario, and say
;;;; which passed.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The verify lock (spec/preview.md 4): one builder's checks at a time

(defparameter +lock-report-seconds+ 300
  "How often a wait for the verify lock says again what it waits for.")

(defconstant +lock-ex+ 2 "flock(2)'s LOCK_EX.")
(defconstant +lock-nb+ 4 "flock(2)'s LOCK_NB.")
(defconstant +fd-cloexec+ 1 "fcntl(2)'s FD_CLOEXEC.")

(defun call-flock (fd operation)
  "flock(2) FD with OPERATION, again when a signal interrupts it; true when it
took the lock, NIL when LOCK_NB found it held."
  (loop for result = (sb-alien:alien-funcall
                      (sb-alien:extern-alien "flock" (function sb-alien:int sb-alien:int sb-alien:int))
                      fd operation)
        for errno = (and (minusp result) (sb-alien:get-errno))
        while (eql errno sb-posix:eintr)
        finally (cond ((zerop result) (return t))
                      ((eql errno sb-posix:ewouldblock) (return nil))
                      (t (fail-step "cannot lock ~a: ~a" fd (sb-int:strerror errno))))))

(defun flock-now-p (fd)
  "Take an exclusive flock(2) lock on FD if no one else holds one; whether it
was taken."
  (call-flock fd (logior +lock-ex+ +lock-nb+)))

(defun flock-wait (fd)
  "Take an exclusive flock(2) lock on FD, waiting in the kernel's queue for
it: a wait that only looked now and then would lose the lock to every
`flock` waiting in that queue whenever it is let go."
  (call-flock fd +lock-ex+))

(defun file-device-and-inode (path)
  "The device of the file PATH, as /proc/locks writes it (MAJOR:MINOR in
hexadecimal), and its inode."
  (let* ((stat (sb-posix:stat path))
         (device (sb-posix:stat-dev stat)))
    (values (format nil "~(~2,'0x:~2,'0x~)"
                    (logior (ldb (byte 12 8) device) (ash (ldb (byte 20 44) device) 12))
                    (logior (ldb (byte 8 0) device) (ash (ldb (byte 12 20) device) 8)))
            (sb-posix:stat-ino stat))))

(defun flock-holders (path)
  "The processes /proc/locks names as holding a flock on the file PATH (not
those waiting for one), or NIL where there is no /proc/locks or no PATH."
  (let ((lines (ignore-errors (uiop:read-file-lines "/proc/locks"))))
    (when (and lines (probe-file path))
      (multiple-value-bind (device inode) (ignore-errors (file-device-and-inode path))
        (let ((place (format nil "~a:~d" device inode)))
          (loop for line in lines
                for words = (remove "" (uiop:split-string line :separator " ") :test #'string=)
                ;; "1: FLOCK  ADVISORY  WRITE 4242 00:2c:1234 0 EOF"; a waiter's has "->".
                when (and (equal (second words) "FLOCK") (not (find "->" words :test #'string=))
                          (string-equal (sixth words) place))
                  collect (parse-integer (fifth words) :junk-allowed t)))))))

(defun parent-pid (pid)
  "The parent of process PID, or NIL."
  (let ((stat (ignore-errors (uiop:read-file-string (format nil "/proc/~d/stat" pid)))))
    ;; "PID (COMMAND) STATE PPID ...": the command may hold spaces and parentheses.
    (when stat
      (let ((fields (uiop:split-string (subseq stat (1+ (position #\) stat :from-end t)))
                                       :separator " ")))
        (parse-integer (third fields) :junk-allowed t)))))

(defun ancestor-holds-p (path &optional (pid (sb-posix:getpid)))
  "True when a process that the process PID descends from holds a flock on
PATH, as `flock PATH tun loop verify` does."
  (let ((holders (flock-holders path)))
    (and holders
         (loop for ancestor = (parent-pid pid) then (parent-pid ancestor)
               while (and ancestor (> ancestor 1))
               thereis (member ancestor holders)))))

(defun process-command (pid)
  "The command line of process PID, shortened, or ?."
  (let ((text (ignore-errors (uiop:read-file-string (format nil "/proc/~d/cmdline" pid)))))
    (if (plusp (length text))
        (let ((line (string-trim " " (cl-ppcre:regex-replace-all "[\\s\\x00]+" text " "))))
          (if (> (length line) 120) (format nil "~a…" (subseq line 0 120)) line))
        "?")))

(defun holders-text (path)
  (let ((holders (flock-holders path)))
    (if holders
        (format nil ", held by ~{~a~^, ~}"
                (mapcar (lambda (pid) (format nil "process ~d (~a)" pid (process-command pid)))
                        holders))
        "")))

(defun duration-text (seconds)
  (format nil "~dm~2,'0ds" (floor seconds 60) (mod seconds 60)))

(defun call-with-verify-lock (function)
  "Call FUNCTION holding the verify lock on the file TUN_VERIFY_LOCK names,
waiting for it and saying so (spec/preview.md 4); without the variable,
or when this process's verify or an ancestor already holds it, just call
FUNCTION."
  (let ((path (uiop:getenv "TUN_VERIFY_LOCK")))
    (if (or (zerop (length path))
            (equal (uiop:getenv "TUN_VERIFY_LOCK_HELD") path)
            (and (probe-file path) (ancestor-holds-p path)))
        (funcall function)
        (let ((fd (handler-case (sb-posix:open path (logior sb-posix:o-rdonly sb-posix:o-creat) #o666)
                    (sb-posix:syscall-error (condition)
                      (fail-step "cannot open the verify lock ~a (TUN_VERIFY_LOCK): ~a" path condition)))))
          (unwind-protect
               (progn
                 ;; The lock stays with this process: a program it starts,
                 ;; such as a preview's server, does not keep it.
                 (sb-posix:fcntl fd sb-posix:f-setfd +fd-cloexec+)
                 (unless (flock-now-p fd)
                   (let* ((started (get-universal-time))
                          (out *standard-output*)
                          ;; Says again, now and then, what the wait is for.
                          (reporter (sb-thread:make-thread
                                     (lambda ()
                                       (loop (sleep +lock-report-seconds+)
                                             (format out "~&tun: still waiting for the verify lock ~a (~a)~a~%"
                                                     path (duration-text (- (get-universal-time) started))
                                                     (holders-text path))
                                             (finish-output out)))
                                     :name "verify lock reporter")))
                     (format t "~&tun: waiting for the verify lock ~a~a~%" path (holders-text path))
                     (finish-output)
                     (unwind-protect (flock-wait fd)
                       (sb-thread:terminate-thread reporter))
                     (format t "~&tun: took the verify lock ~a after ~a~%"
                             path (duration-text (- (get-universal-time) started)))
                     (finish-output)))
                 (sb-posix:setenv "TUN_VERIFY_LOCK_HELD" path 1)
                 (unwind-protect (funcall function)
                   (sb-posix:unsetenv "TUN_VERIFY_LOCK_HELD")))
            ;; Closing the file releases the lock.
            (sb-posix:close fd))))))

(defmacro with-verify-lock (() &body body)
  `(call-with-verify-lock (lambda () ,@body)))

;;; ------------------------------------------------------------------
;;; The checks

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
    (with-verify-lock ()
      (run-checks client files runner out name directory data))))

(defun run-checks (client files runner out name directory data)
  "Run FILES, CLIENT's checks in DIRECTORY, each against a fresh preview NAME
with its database in DATA, by RUNNER, their results in OUT."
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
        (fail-step "~d check~:p failed" failed)))))
