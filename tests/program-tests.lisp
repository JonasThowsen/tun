;;;; tests/program-tests.lisp -- running a declared program on the server
;;;; (spec/outbound.md 6): real runs of the dev shell's sh, printf, env,
;;;; cat, head and sleep, and runs answered by *PROGRAM-HANDLER*.

(in-package #:tun.tests)

(def-suite programs :in core)
(in-suite programs)

(define-application program-application ()
  (:programs "sh" "printf" "env" "cat" "head" "sleep" "tun-test-no-such-program"))

(defmacro with-program-app (() &body body)
  "Run BODY in a fresh application that declares the programs these tests
run, with it current."
  `(with-test-app (:class 'program-application)
     (with-application (*app*) ,@body)))

(defun program-failure-of (function)
  "The PROGRAM-FAILURE FUNCTION signals, or NIL."
  (handler-case (progn (funcall function) nil)
    (program-failure (c) c)))

(defun group-left-p (pgid)
  "True while a process of the process group PGID remains."
  (handler-case (progn (sb-posix:killpg pgid 0) t)
    (sb-posix:syscall-error () nil)))

(defun group-gone-within-p (pgid seconds)
  "True when no process of the group PGID remains within SECONDS."
  (let ((end (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
    (loop while (and (group-left-p pgid) (< (get-internal-real-time) end))
          do (sleep 0.05))
    (not (group-left-p pgid))))

(defun programs-running ()
  (application-programs-running *app*))

(defun wait-for-no-programs ()
  "Wait until the tenant's programs, those being stopped included, have ended."
  (loop repeat 200 until (zerop (programs-running)) do (sleep 0.05))
  (zerop (programs-running)))

(defun leading-pid (text)
  "The process id a test program printed on its first line."
  (parse-integer text :junk-allowed t))

;;; ------------------------------------------------------------------
;;; Declared programs (criterion 1)

(test only-a-declared-program-runs
  (is (equal '("sh" "printf" "env" "cat" "head" "sleep" "tun-test-no-such-program")
             (application-programs 'program-application)))
  (with-program-app ()
    (handler-case (progn (run-program "ls" '()) (is nil "an undeclared program is refused"))
      (program-failure () (is nil "the refusal is not a program's failure"))
      (error (e) (is (search "\"ls\" is not a program the application declares"
                             (princ-to-string e)))))
    (with-test-app ()
      (with-application (*app*)
        (signals error (run-program "sh" '("-c" "true")))
        (is (not (typep (handler-case (run-program "sh" '("-c" "true")) (error (e) e))
                        'program-failure))
            "an application that declares none runs none")))))

(test a-program-is-a-file-name
  (dolist (form '((define-application bad-programs () (:programs "/bin/sh"))
                  (define-application bad-programs () (:programs ""))
                  (define-application bad-programs () (:programs nixploy))))
    (signals error (macroexpand-1 form))))

(test tests-and-open-application-do-not-look-for-programs
  (with-program-app ()
    (is (equal '("tun-test-no-such-program") (missing-programs *app*))
        "the application opened with a program missing"))
  (let ((said (make-string-output-stream)) (code nil))
    (let ((*error-output* said))
      (tun.runtime::check-programs 'program-application "server"
                                   :exit (lambda (c) (setf code c))))
    (is (eql 2 code) "a server would not start")
    (let ((text (get-output-stream-string said)))
      (is (search "server: the program tun-test-no-such-program is not on PATH" text))
      (is (not (search "sh " text)) "only the missing one is named")))
  (let ((said (make-string-output-stream)) (code nil))
    (let ((*error-output* said))
      (tun.runtime::check-programs 'application "server" :exit (lambda (c) (setf code c))))
    (is (null code))
    (is (equal "" (get-output-stream-string said)))))

(test a-server-without-a-declared-program-does-not-start
  (let* ((process (uiop:launch-program
                   (list "sbcl" "--noinform" "--non-interactive" "--no-userinit" "--no-sysinit"
                         "--load" (namestring (asdf:system-relative-pathname
                                               "tun" "tests/fixtures/programs-server.lisp"))
                         "--port" (princ-to-string (free-port))
                         "--db" (namestring (scratch-path "programs-server.db")))
                   :input nil :output nil :error-output :stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (let ((end (+ (get-internal-real-time) (* 60 internal-time-units-per-second))))
           (loop while (and (uiop:process-alive-p process) (< (get-internal-real-time) end))
                 do (sleep 0.1))
           (is (not (uiop:process-alive-p process)) "it stopped at start")
           (uiop:copy-stream-to-stream (uiop:process-info-error-output process) errors)
           (is (eql 2 (uiop:wait-process process)))
           (is (search "programs-server: the program tun-test-no-such-program is not on PATH"
                       (get-output-stream-string errors))))
      (when (uiop:process-alive-p process)
        (uiop:terminate-process process :urgent t)
        (uiop:wait-process process)))))

;;; ------------------------------------------------------------------
;;; Arguments, directory, input and the answer (criterion 2)

(test arguments-reach-the-program-as-they-are
  (let ((arguments (list "a;b" "$(touch /tmp/tun-test-pwned)" "it's \"quoted\"" "two words"
                         (format nil "line~%break") "`id`" "*" "æøå" "")))
    (with-program-app ()
      (multiple-value-bind (output code error-output) (run-program "printf" (cons "%s|" arguments))
        (is (eql 0 code))
        (is (equal "" error-output))
        (is (equal (format nil "~{~a|~}" arguments) output)
            "each argument arrives whole and unchanged, with no shell between")))
    (is (not (probe-file "/tmp/tun-test-pwned")))))

(test a-program-runs-in-its-directory-with-its-input
  (with-program-app ()
    (is (equal (format nil "/~%") (run-program "sh" '("-c" "pwd") :directory "/")))
    (let ((text (format nil "hei æøå~%linje 2")))
      (is (equal text (run-program "cat" '() :input text))))
    (is (equal "" (run-program "cat" '())) "without input, standard input is empty")
    (is (eql 0 (nth-value 1 (run-program "sh" '("-c" "exit 0")
                                          :input (make-string 1000000 :initial-element #\a))))
        "input the program does not read does not hold it up")
    (is (= 3000000 (length (run-program "cat" '() :input (make-string 3000000
                                                                       :initial-element #\b))))
        "input larger than a pipe holds")))

(test an-exit-code-is-an-answer
  (with-program-app ()
    (multiple-value-bind (output code error-output)
        (run-program "sh" '("-c" "echo '{\"error\":\"held\"}'; echo why >&2; exit 2"))
      (is (equal (format nil "{\"error\":\"held\"}~%") output))
      (is (eql 2 code))
      (is (equal (format nil "why~%") error-output)))
    (is (eql 137 (nth-value 1 (run-program "sh" '("-c" "kill -9 $$"))))
        "a program ended by a signal answers 128 and the signal, as a shell does")))

(test both-outputs-are-read-as-they-come
  (with-program-app ()
    (multiple-value-bind (output code error-output)
        (run-program "sh" '("-c" "head -c 1000000 /dev/zero >&2; head -c 1000000 /dev/zero; echo"))
      (is (eql 0 code) "a full standard error does not stop the program")
      (is (= 1000001 (length output)))
      (is (= 1000000 (length error-output))))))

(test output-is-utf-8-with-invalid-bytes-replaced
  (with-program-app ()
    (is (equal (format nil "~cok æ" (code-char #xFFFD))
               (run-program "printf" (list "\\377ok \\303\\246"))))))

;;; ------------------------------------------------------------------
;;; The environment (criterion 3)

(defun environment-of (text)
  "The NAME=VALUE lines of env's output, as an alist."
  (loop for line in (uiop:split-string text :separator '(#\Newline))
        for at = (position #\= line)
        when at collect (cons (subseq line 0 at) (subseq line (1+ at)))))

(test a-program-sees-only-a-few-variables-and-its-own
  (with-environment-variable ("DATABASE_URL" "postgres://tun:hemmelig@db/tun")
    (with-environment-variable ("TUN_TEST_SECRET" "sk-hemmelig")
      (with-environment-variable ("HOME" "/home/tun-test")
        (with-program-app ()
          (let* ((output (run-program "env" '() :environment '(("NIXPLOY_TOKEN" . "nt-1")
                                                                  ("HOME" . "/var/lib/fleet"))))
                 (seen (environment-of output)))
            (is (null (assoc "DATABASE_URL" seen :test #'string=)))
            (is (null (assoc "TUN_TEST_SECRET" seen :test #'string=)))
            (is (not (search "hemmelig" output)))
            (is (equal (sb-ext:posix-getenv "PATH") (cdr (assoc "PATH" seen :test #'string=))))
            (is (equal "nt-1" (cdr (assoc "NIXPLOY_TOKEN" seen :test #'string=))))
            (is (equal "/var/lib/fleet" (cdr (assoc "HOME" seen :test #'string=)))
                "ENVIRONMENT replaces the server's variable of the same name")
            (is (= 1 (count "HOME" seen :key #'car :test #'string=)))
            (is (subsetp (mapcar #'car seen)
                         '("PATH" "HOME" "TMPDIR" "LANG" "SSH_AUTH_SOCK" "NIXPLOY_TOKEN")
                         :test #'string=)
                "nothing else of the server's environment"))
          (is (equal "/home/tun-test"
                     (cdr (assoc "HOME" (environment-of (run-program "env" '()))
                                 :test #'string=)))
              "the server's HOME, without ENVIRONMENT"))))))

;;; ------------------------------------------------------------------
;;; Failures (criterion 4)

(test a-program-that-cannot-start-fails
  (with-program-app ()
    (let ((c (program-failure-of (lambda () (run-program "tun-test-no-such-program" '("x"))))))
      (is (typep c 'operation-error))
      (is (eq :unavailable (operation-error-code c)))
      (is (equal "tun-test-no-such-program" (program-failure-name c)))
      (is (null (program-failure-output c)))
      (is (equal "tun-test-no-such-program could not be started" (operation-error-message c))))
    (let ((c (program-failure-of (lambda ()
                                   (run-program "sh" '("-c" "true")
                                                :directory "/tun-test-no-such-directory")))))
      (is (equal "sh could not be started" (operation-error-message c))))
    (is (wait-for-no-programs) "its place is given back")))

(test a-program-past-its-time-is-stopped-with-what-it-started
  (with-program-app ()
    (let* ((start (get-internal-real-time))
           (c (program-failure-of
               (lambda ()
                 (run-program "sh" '("-c" "echo $$; echo halfway >&2; sleep 30 & sleep 30")
                              :timeout 1))))
           (pgid (leading-pid (program-failure-output c))))
      (is (<= 1 (elapsed-since start) 1.5) "it fails when its time is up")
      (is (equal "sh did not finish within 1 second" (operation-error-message c)))
      (is (eq :unavailable (operation-error-code c)))
      (is (equal (format nil "halfway~%") (program-failure-error-output c))
          "with what it had written")
      (is (group-gone-within-p pgid 6) "the program and its child are gone"))
    (let* ((c (program-failure-of
               (lambda ()
                 (run-program "sh" '("-c" "trap '' TERM; echo $$; sleep 30 & sleep 30")
                              :timeout 1))))
           (pgid (leading-pid (program-failure-output c))))
      (is (group-left-p pgid) "a group that ignores SIGTERM is still there at first")
      (is (group-gone-within-p pgid 6) "SIGKILL ends it five seconds later"))
    (is (wait-for-no-programs) "and the places are given back")))

(test a-program-that-ends-has-ended-though-its-children-hold-its-output
  (with-program-app ()
    (let ((start (get-internal-real-time)))
      (multiple-value-bind (output code)
          (run-program "sh" '("-c" "echo $$; sleep 30 & echo done; exit 4"))
        (is (< (elapsed-since start) 1) "the answer does not wait for the child")
        (is (eql 4 code))
        (is (search (format nil "~%done~%") output))
        (is (group-gone-within-p (leading-pid output) 6) "the child is stopped")))
    (is (wait-for-no-programs))))

(test a-program-may-write-at-most-8-mb-to-a-stream
  (with-program-app ()
    (is (= (* 8 1024 1024) (length (run-program "head" (list "-c" "8388608" "/dev/zero")))))
    (let* ((c (program-failure-of
               (lambda ()
                 (run-program "sh" '("-c" "echo $$; head -c 9000000 /dev/zero; sleep 30")))))
           (pgid (leading-pid (program-failure-output c))))
      (is (equal "sh wrote more than 8 MB" (operation-error-message c)))
      (is (= (* 8 1024 1024) (length (program-failure-output c))) "what it wrote, up to 8 MB")
      (is (group-gone-within-p pgid 6) "the program is stopped"))
    (let ((c (program-failure-of
              (lambda () (run-program "sh" '("-c" "head -c 8388609 /dev/zero >&2"))))))
      (is (equal "sh wrote more than 8 MB" (operation-error-message c)) "standard error too"))
    (is (wait-for-no-programs))))

(test a-tenant-runs-four-programs-at-once
  (with-program-app ()
    (let* ((app *app*)
           (threads (loop repeat 4
                          collect (sb-thread:make-thread
                                   (lambda ()
                                     (with-application (app)
                                       (handler-case (nth-value 1 (run-program "sleep" '("2")))
                                         (error (e) e))))
                                   :name "busy program"))))
      (loop repeat 100 until (= 4 (programs-running)) do (sleep 0.02))
      (is (= 4 (programs-running)))
      (is (provider-call-capacity-p) "calls to other systems have places of their own")
      (let* ((start (get-internal-real-time))
             (c (program-failure-of (lambda () (run-program "sleep" '("0"))))))
        (is (< (elapsed-since start) 0.2) "the fifth fails at once")
        (is (equal "sleep was not started: four programs are running already"
                   (operation-error-message c))))
      (is (equal '(0 0 0 0) (mapcar #'sb-thread:join-thread threads)))
      (is (eql 0 (nth-value 1 (run-program "sleep" '("0")))) "then it runs"))))

(test program-failures-are-in-norwegian-on-a-norwegian-page
  (with-program-app ()
    (with-language ("nb")
      (is (equal "sh ble ikke ferdig innen 1 sekund"
                 (operation-error-message
                  (program-failure-of (lambda () (run-program "sh" '("-c" "sleep 30")
                                                              :timeout 1))))))
      (is (equal "tun-test-no-such-program kunne ikke startes"
                 (operation-error-message
                  (program-failure-of (lambda () (run-program "tun-test-no-such-program" '())))))))
    (with-language ("nb")
      (let ((*program-handler* (lambda (name arguments directory input environment)
                                 (declare (ignore name arguments directory input environment))
                                 (values (make-string (1+ (* 8 1024 1024)) :initial-element #\a)
                                         0 ""))))
        (is (equal "sh skrev mer enn 8 MB"
                   (operation-error-message (program-failure-of
                                             (lambda () (run-program "sh" '())))))))
      (is (equal "sh ble ikke ferdig innen 2 sekunder"
                 (with-language ("nb")
                   (render-text (make-text "~a did not finish within ~d second~:p"
                                           (list "sh" 2)))))))
    (is (wait-for-no-programs))))

;;; ------------------------------------------------------------------
;;; The timeout and the operation's deadline (criterion 5)

(test the-timeout-is-from-1-to-3600-seconds
  (with-program-app ()
    (dolist (timeout '(0 3601 -1 "10" nil))
      (let ((c (handler-case (progn (run-program "sh" '("-c" "true") :timeout timeout) nil)
                 (error (e) e))))
        (is (typep c 'error) "~s is refused" timeout)
        (is (not (typep c 'program-failure)) "~s is the client's mistake" timeout)))
    (dolist (form (list (lambda () (run-program "sh" "-c true"))
                        (lambda () (run-program "sh" '("-c" 42)))
                        (lambda () (run-program "sh" '() :directory "relative/dir"))
                        (lambda () (run-program "sh" '() :input 42))
                        (lambda () (run-program "sh" '() :environment '(("A=B" . "c"))))
                        (lambda () (run-program "sh" '() :environment '(("A" . 1))))))
      (signals error (funcall form)))
    (is (eql 0 (nth-value 1 (run-program "sh" '("-c" "true") :timeout 3600))))))

(test a-program-leaves-the-operation-time-to-answer
  (with-program-app ()
    (let* ((start (get-internal-real-time))
           (c (program-failure-of (lambda ()
                                    (tun.core::with-deadline (:ms 2600)
                                      (run-program "sleep" '("30") :timeout 60))))))
      (is (<= 1.5 (elapsed-since start) 2.2) "1.6 seconds: the deadline less one")
      (is (equal "sleep did not finish within 2 seconds" (operation-error-message c))))
    (let* ((start (get-internal-real-time))
           (c (program-failure-of (lambda ()
                                    (tun.core::with-deadline (:ms 1500)
                                      (run-program "sleep" '("30")))))))
      (is (< (elapsed-since start) 0.2) "under a second left: not started")
      (is (equal "sleep was not started: the operation has less than a second left"
                 (operation-error-message c))))
    (is (wait-for-no-programs))))

;;; ------------------------------------------------------------------
;;; In an operation, in the trace (criterion 6), and answered by a test
;;; (criterion 7)

(define-operation widgets-run-program ((text :type (string :max 400) :required t))
    (:entity widget :kind :read :title "Run a program")
  (multiple-value-bind (output code)
      (run-program "sh" (list "-c" "cat; printf %s \"$TUN_TEST_KEY\"" "sh" "--target" text)
                   :input "input-text" :environment '(("TUN_TEST_KEY" . "sk-in-environment")))
    (jobj "output" output "exit" code)))

(defun external-step (request-id)
  (find "external" (trace-steps request-id) :key (lambda (s) (jget s "kind")) :test #'equal))

(test the-trace-shows-the-run-and-not-what-went-in-or-out
  (with-test-app (:class 'program-application)
    (let ((*request-id* (new-id "req")))
      (is (equal "input-textsk-in-environment"
                 (jget (call-ok "widgets_run_program" "employee:anna" "text" "production")
                       "output")))
      (let ((step (external-step *request-id*)))
        (is (equal "sh -c cat; printf %s \"$TUN_TEST_KEY\" sh --target production"
                   (jget step "name"))
            "the program and its arguments")
        (is (equal "exit 0" (jget step "detail")))
        (is (numberp (jget step "duration_ms")))
        (let ((text (to-json-string (jarr (trace-steps *request-id*)))))
          (is (not (search "input-text" text)) "no input")
          (is (not (search "sk-in-environment" text)) "no environment and no output"))))
    (let ((*request-id* (new-id "req"))
          (long (make-string 400 :initial-element #\x)))
      (call-ok "widgets_run_program" "employee:anna" "text" long)
      (let ((name (jget (external-step *request-id*) "name")))
        (is (= 300 (length name)) "clipped to 300 characters")
        (is (eql 0 (search "sh -c cat" name)))))
    (with-application (*app*)
      (flet ((detail-of (function)
               (let ((*request-id* (new-id "req")))
                 (with-request-record (:id *request-id* :application *app*)
                   (program-failure-of function))
                 (jget (external-step *request-id*) "detail"))))
        (is (equal "timeout" (detail-of (lambda () (run-program "sleep" '("30") :timeout 1)))))
        (is (equal "could not start"
                   (detail-of (lambda () (run-program "tun-test-no-such-program" '())))))
        (is (equal "exit 3" (detail-of (lambda () (run-program "sh" '("-c" "exit 3"))))))))
    (with-application (*app*) (is (wait-for-no-programs)))))

(test a-handler-answers-for-the-program
  (with-test-app (:class 'program-application)
    (let* ((seen '())
           (*program-handler* (lambda (name arguments directory input environment)
                                (push (list name arguments directory input environment) seen)
                                (if (equal "feil" (car (last arguments)))
                                    (values "" nil "")
                                    (values (format nil "{\"target\":~s}" (car (last arguments)))
                                            0 "")))))
      (let ((*request-id* (new-id "req")))
        (is (equal "{\"target\":\"production\"}"
                   (jget (call-ok "widgets_run_program" "employee:anna" "text" "production")
                         "output")))
        (is (equal "exit 0" (jget (external-step *request-id*) "detail")) "the step is recorded"))
      (destructuring-bind (name arguments directory input environment) (first seen)
        (is (equal "sh" name))
        (is (equal "production" (car (last arguments))))
        (is (null directory))
        (is (equal "input-text" input))
        (is (equal '(("TUN_TEST_KEY" . "sk-in-environment")) environment)
            "the environment as the client gave it"))
      (multiple-value-bind (json code) (call "widgets_run_program" "employee:anna" "text" "feil")
        (is (equal "unavailable" code) "an exit code of NIL is a program that could not start")
        (is (equal "sh could not be started" (jget (jget json "error") "message"))))
      (with-application (*app*)
        (signals error (run-program "ls" '()) "an undeclared program, with a handler too")
        (signals error (run-program "sh" '() :timeout 0) "the same checks")
        (is (eql 7 (nth-value 1 (let ((*program-handler* (lambda (&rest arguments)
                                                            (declare (ignore arguments))
                                                            (values "" 7 "nope"))))
                                   (run-program "tun-test-no-such-program" '()))))
            "a handler needs no program installed")
        (let ((*program-handler* (lambda (&rest arguments)
                                   (declare (ignore arguments))
                                   (values 42 0 ""))))
          (handler-case (progn (run-program "sh" '()) (is nil "an answer that is not text"))
            (program-failure () (is nil "is the test's mistake, not a failure"))
            (error () (pass))))
        (is (wait-for-no-programs) "a handler's place is given back")))))
