;;;; outbound/programs.lisp -- running a declared program on the server
;;;; (spec/outbound.md 6).
;;;;
;;;; RUN-PROGRAM runs one of the programs the application names in
;;;; (:programs ...), with an argument list and no shell, in a small
;;;; environment, and values its standard output, exit code and standard
;;;; error.  An exit code is an answer.  PROGRAM-FAILURE, an operation error
;;;; with code unavailable, is signalled when no answer came: the program
;;;; could not be started, ran past its time, wrote more than 8 MB to a
;;;; stream, or found four of the tenant's programs running.  Each run is
;;;; one :external step in the request's trace, and a test answers in place
;;;; of the program by binding *PROGRAM-HANDLER*.
;;;;
;;;; The program runs in a process group of its own.  SBCL's RUN-PROGRAM
;;;; calls setpgrp() in the child between fork and exec whenever the child's
;;;; standard input is not the parent's, and here it is always a pipe or
;;;; /dev/null; so the group's id is the program's pid, and stopping the
;;;; group stops everything the program started that stayed in it.
;;;;
;;;; The caller's thread feeds the input and drains both outputs in one
;;;; loop, touching a pipe only when poll says it is ready, so a program
;;;; that fills one pipe while the other waits to be read cannot deadlock.
;;;; With :ON-ERROR-LINE the same loop hands the caller each line of
;;;; standard error as it completes, so a deploy's progress can be shown
;;;; while it runs.

(in-package #:tun.outbound)

(declaim (optimize (safety 3) (debug 2)))

(defvar *program-handler* nil
  "NIL, or a function of the name, the arguments, the directory, the input
and the environment that answers in place of the program, with its output,
its exit code (NIL for a program that could not be started) and its error
output (spec/outbound.md 6.1).")

(defparameter +program-limit+ 4
  "How many programs a tenant runs at once.  The count is its own, not the
calls to other systems', so a long deploy does not hold up mail.")

(defparameter +output-limit+ (* 8 1024 1024)
  "The most a program may write to its standard output or its standard
error, in octets.")

(defparameter +stop-grace-seconds+ 5
  "How long a program's group has between SIGTERM and SIGKILL.")

(defparameter +passed-environment+ '("PATH" "HOME" "TMPDIR" "LANG" "SSH_AUTH_SOCK")
  "The variables of the server's environment a program sees: what nixploy,
git, ssh and Nix need to find themselves, a home and the SSH agent.  The rest,
the database URL and every secret of the deployment among them, stay out.")

(defparameter +trace-name-limit+ 300
  "The most characters of a run's name, its program and arguments, that the
trace keeps.")

(defparameter +pipe-chunk+ 4096
  "The most octets written to the program's input at once: a pipe that poll
says is writable takes this many without blocking.")

(defparameter +line-piece+ (* 16 1024)
  "The most octets of standard error one call of :ON-ERROR-LINE is handed: a
longer line comes in pieces.")

;;; ------------------------------------------------------------------
;;; The failure, and its messages in English with Norwegian in the
;;; catalogue (spec/i18n.md 3.1)

(define-condition program-failure (operation-error)
  ((name :initarg :name :reader program-failure-name
         :documentation "The program, as RUN-PROGRAM was given it.")
   (output :initarg :output :initform nil :reader program-failure-output
           :documentation "What the program had written to its standard output, or NIL.")
   (error-output :initarg :error-output :initform nil :reader program-failure-error-output
                 :documentation "What the program had written to its standard error, or NIL."))
  (:default-initargs :code :unavailable)
  (:documentation "A program that gave no answer: it could not be started, ran past
its time, wrote more than 8 MB to a stream, or was not started because four of
the tenant's programs were running (spec/outbound.md 6)."))

(defparameter +program-failure-texts+
  '(:timeout "~a did not finish within ~d second~:p"
    :not-started "~a could not be started"
    :too-much "~a wrote more than 8 MB"
    :full "~a was not started: four programs are running already"
    :no-time "~a was not started: the operation has less than a second left")
  "The message of each kind of PROGRAM-FAILURE, a FORMAT control taking the
program's name and, for :TIMEOUT, the seconds it had.")

(loop for (nil text) on +program-failure-texts+ by #'cddr
      do (note-text text nil "core" "programs.lisp"))

(defun program-failure (kind name &key output error-output seconds)
  "Signal the PROGRAM-FAILURE of KIND, a key of +PROGRAM-FAILURE-TEXTS+, for
the program NAME."
  (error 'program-failure
         :name name :output output :error-output error-output
         :message (make-text (getf +program-failure-texts+ kind)
                             (if (eq kind :timeout) (list name seconds) (list name)))))

;;; ------------------------------------------------------------------
;;; What a run is given

(defun argument-string-p (value)
  "True when VALUE is a string an argument vector or an environment can hold."
  (and (stringp value) (not (find (code-char 0) value))))

(defun environment-entry-p (entry)
  "True when ENTRY is a (NAME . VALUE) pair of an environment."
  (and (consp entry)
       (argument-string-p (car entry)) (plusp (length (car entry)))
       (not (find #\= (car entry)))
       (argument-string-p (cdr entry))))

(defun check-run (name arguments directory input environment timeout on-error-line)
  "Signal an error, in the client's code, unless NAME is a program the
application declares and the rest are what RUN-PROGRAM takes."
  (unless *application*
    (error "run-program: no application is current"))
  (unless (and (stringp name)
               (member name (application-programs *application*) :test #'string=))
    (error "run-program: ~s is not a program the application declares; ~
            (:programs ...) names ~:[none~;~:*~{~s~^, ~}~]"
           name (application-programs *application*)))
  (unless (and (listp arguments) (every #'argument-string-p arguments))
    (error "run-program: the arguments are a list of strings, not ~s" arguments))
  (unless (or (null directory)
              (and (argument-string-p directory) (plusp (length directory))
                   (char= #\/ (char directory 0))))
    (error "run-program: the directory is an absolute path, not ~s" directory))
  (unless (or (null input) (stringp input))
    (error "run-program: the input is a string, not ~s" input))
  (unless (and (listp environment) (every #'environment-entry-p environment))
    (error "run-program: the environment is an alist of names and values, both strings, ~
            not ~s" environment))
  (unless (typep timeout '(real 1 3600))
    (error "run-program: the timeout is from 1 to 3600 seconds, not ~s" timeout))
  (unless (or (null on-error-line) (functionp on-error-line)
              (and (symbolp on-error-line) (fboundp on-error-line)))
    (error "run-program: on-error-line is a function, not ~s" on-error-line)))

(defun program-path (name)
  "The executable file NAME on the server's PATH, as execvp would find it,
or NIL.  An empty entry of PATH, which execvp reads as the working
directory, is skipped."
  (loop for directory in (uiop:split-string (or (sb-ext:posix-getenv "PATH") "")
                                            :separator ":")
        for path = (and (plusp (length directory))
                        (concatenate 'string (string-right-trim "/" directory) "/" name))
        when (and path
                  (sb-unix:unix-access path sb-unix:x_ok)
                  (not (uiop:directory-exists-p path)))
          return path))

(defun missing-programs (application)
  "The programs APPLICATION (an application or the name of its class)
declares that are not on the server's PATH, for the start check."
  (remove-if #'program-path (application-programs application)))

(defun program-environment (environment)
  "The environment a program sees, as NAME=VALUE strings: those of
+PASSED-ENVIRONMENT+ the server has, then ENVIRONMENT, whose entries replace
any of the same name."
  (let ((entries (loop for name in +passed-environment+
                       for value = (sb-ext:posix-getenv name)
                       when value collect (cons name value))))
    (loop for (name . value) in environment
          do (setf entries (append (remove name entries :key #'car :test #'string=)
                                   (list (cons name value)))))
    (loop for (name . value) in entries
          collect (concatenate 'string name "=" value))))

(defun run-name (name arguments)
  "The run's name in the trace: the program and its arguments joined by
spaces, clipped."
  (let ((text (format nil "~a~{ ~a~}" name arguments)))
    (if (> (length text) +trace-name-limit+)
        (subseq text 0 +trace-name-limit+)
        text)))

;;; ------------------------------------------------------------------
;;; The tenant's places for programs

(defun claim-program-place ()
  "The current application when it has a place for one more program, which
is then taken; else NIL."
  (let ((app *application*))
    (sb-thread:with-mutex ((application-programs-lock app))
      (when (< (application-programs-running app) +program-limit+)
        (incf (application-programs-running app))
        app))))

(defun release-program-place (app)
  (sb-thread:with-mutex ((application-programs-lock app))
    (decf (application-programs-running app))))

;;; ------------------------------------------------------------------
;;; Lines of standard error, handed on as they complete

(defun octets-text (octets &key (start 0) end)
  "OCTETS from START to END as UTF-8, with an invalid byte replaced."
  (sb-ext:octets-to-string octets :start start :end end
                                  :external-format (list :utf-8 :replacement
                                                         (code-char #xFFFD))))

(defclass line-reader ()
  ((function :initarg :function :reader line-function
             :documentation "Called with each line, as text.")
   (pending :initform (make-array 1024 :element-type '(unsigned-byte 8)
                                       :adjustable t :fill-pointer 0)
            :accessor line-pending
            :documentation "What came after the last line handed on."))
  (:documentation "Hands a function each line of what a program writes, as the
lines complete (spec/outbound.md 6)."))

(defun piece-end (pending start)
  "Where a piece of at most +LINE-PIECE+ octets of PENDING from START ends:
before a character the limit would cut, not inside it."
  (let ((end (+ start +line-piece+)))
    ;; An octet 10xxxxxx continues the character before it.
    (loop while (and (> end start) (= #x80 (logand #xC0 (aref pending end))))
          do (decf end))
    (if (= end start) (+ start +line-piece+) end)))

(defun read-lines (reader octets count)
  "Add the first COUNT octets of OCTETS to what READER holds, and hand on
each line they complete, and each piece of a line too long to wait for."
  (let ((pending (line-pending reader))
        (start 0))
    (loop for index below count
          do (vector-push-extend (aref octets index) pending (max 1024 count)))
    (loop
      (let ((newline (position 10 pending :start start))
            (limit (+ start +line-piece+)))
        (cond ((and newline (<= newline limit))
               (funcall (line-function reader) (octets-text pending :start start :end newline))
               (setf start (1+ newline)))
              ((> (length pending) limit)
               (let ((end (piece-end pending start)))
                 (funcall (line-function reader) (octets-text pending :start start :end end))
                 (setf start end)))
              (t (return)))))
    (replace pending pending :start2 start)
    (decf (fill-pointer pending) start)))

(defun finish-lines (reader)
  "Hand on what READER holds after the last line: the program has ended."
  (let ((pending (line-pending reader)))
    (when (plusp (length pending))
      (let ((text (octets-text pending)))
        (setf (fill-pointer pending) 0)
        (funcall (line-function reader) text)))))

(defun pass-error-lines (function text)
  "Hand FUNCTION each line of TEXT, as a program's would be: what a test's
handler answers as standard error."
  (let ((reader (make-instance 'line-reader :function function))
        (octets (sb-ext:string-to-octets text :external-format :utf-8)))
    (read-lines reader octets (length octets))
    (finish-lines reader)))

;;; ------------------------------------------------------------------
;;; The program's pipes

(defclass captured-output ()
  ((stream :initarg :stream :reader captured-stream
           :documentation "The stream SBCL made for the pipe; only its descriptor is read.")
   (octets :initform (make-array 4096 :element-type '(unsigned-byte 8)
                                      :adjustable t :fill-pointer 0)
           :accessor captured-octets)
   (open :initform t :accessor captured-open-p
         :documentation "NIL once the pipe has given its end.")
   (lines :initarg :lines :initform nil :reader captured-lines
          :documentation "A LINE-READER that is handed what is read, or NIL."))
  (:documentation "What a program writes to one of its outputs, read as it comes."))

(defun captured-full-p (capture)
  (> (length (captured-octets capture)) +output-limit+))

(defun keep-octets (capture buffer count)
  "Add the first COUNT octets of BUFFER to what CAPTURE holds."
  (let* ((octets (captured-octets capture))
         (start (fill-pointer octets))
         (end (+ start count)))
    (when (> end (array-dimension octets 0))
      (setf octets (adjust-array octets (max end (* 2 (array-dimension octets 0))))
            (captured-octets capture) octets))
    (setf (fill-pointer octets) end)
    (replace octets buffer :start1 start :end2 count)))

(defun read-available (capture buffer)
  "Read what CAPTURE's pipe holds now, without waiting.  True when anything
was read or the pipe ended."
  (let ((fd (sb-sys:fd-stream-fd (captured-stream capture))))
    (when (and (captured-open-p capture) (sb-sys:wait-until-fd-usable fd :input 0 nil))
      (multiple-value-bind (count errno)
          (sb-sys:with-pinned-objects (buffer)
            (sb-unix:unix-read fd (sb-sys:vector-sap buffer) (length buffer)))
        (cond ((and (null count) (eql errno sb-unix:eintr)) nil)
              ((or (null count) (zerop count))
               (setf (captured-open-p capture) nil)
               (finish-captured-lines capture)
               t)
              (t (keep-octets capture buffer count)
                 (when (captured-lines capture)
                   (read-lines (captured-lines capture) buffer count))
                 t))))))

(defun finish-captured-lines (capture)
  "Hand on the last line of CAPTURE, when its lines are read."
  (when (captured-lines capture)
    (finish-lines (captured-lines capture))))

(defun captured-text (capture)
  "What CAPTURE holds, at most +OUTPUT-LIMIT+ octets of it, as UTF-8 with an
invalid byte replaced."
  (let ((octets (captured-octets capture)))
    (octets-text octets :end (min (length octets) +output-limit+))))

(defclass program-input ()
  ((stream :initarg :stream :reader input-stream
           :documentation "The stream SBCL made for the pipe, or NIL without input.")
   (octets :initarg :octets :reader input-octets)
   (position :initform 0 :accessor input-position))
  (:documentation "What is still to be written to a program's standard input."))

(defun close-input (input)
  "Close INPUT's pipe, so the program reads the end of its input."
  (when (and (input-stream input) (open-stream-p (input-stream input)))
    (close (input-stream input) :abort t)))

(defun write-available (input)
  "Write to INPUT's pipe what it takes now, without waiting, and close it
when all is written or the program has closed its end.  True when anything
changed."
  (let ((stream (input-stream input)))
    (when (and stream (open-stream-p stream))
      (let ((fd (sb-sys:fd-stream-fd stream))
            (left (- (length (input-octets input)) (input-position input))))
        (cond ((zerop left) (close-input input) t)
              ((sb-sys:wait-until-fd-usable fd :output 0 nil)
               (multiple-value-bind (count errno)
                   (sb-unix:unix-write fd (input-octets input) (input-position input)
                                       (min left +pipe-chunk+))
                 (cond (count (incf (input-position input) count))
                       ;; The program ended or closed its input unread: what it
                       ;; did not read was not for it.
                       ((not (eql errno sb-unix:eintr)) (close-input input)))
                 t)))))))

;;; ------------------------------------------------------------------
;;; The process and its group

(defun group-alive-p (process)
  "True while any process of PROCESS's group remains.  PROCESS is reaped
first when it has ended, so it does not count as a zombie."
  (sb-ext:process-alive-p process)
  (values (sb-ext:process-kill process 0 :process-group)))

(defun stop-group (process)
  "Stop PROCESS's group: SIGTERM, then SIGKILL to what is left after
+STOP-GRACE-SECONDS+.  PROCESS is reaped."
  (sb-ext:process-kill process sb-unix:sigterm :process-group)
  (let ((end (+ (get-internal-real-time)
                (* +stop-grace-seconds+ internal-time-units-per-second))))
    (loop while (and (group-alive-p process) (< (get-internal-real-time) end))
          do (sleep 0.05)))
  (when (group-alive-p process)
    (sb-ext:process-kill process sb-unix:sigkill :process-group)
    (loop repeat 100 while (group-alive-p process) do (sleep 0.01))))

(defun stop-in-background (process app)
  "Stop PROCESS's group in a thread of its own, which gives back APP's place
for programs when it is done: a program being stopped still runs."
  (sb-thread:make-thread (lambda ()
                           (unwind-protect
                                ;; Nothing waits for this thread, and the place
                                ;; must come back whatever stopping met.
                                (handler-case (stop-group process)
                                  (error () nil))
                             (release-program-place app)))
                         :name "program stopper"))

(defun start-process (path arguments directory input environment)
  "The process running PATH, or NIL when it could not be started."
  (handler-case
      (sb-ext:run-program (sb-ext:parse-native-namestring path) arguments
                          :wait nil :search nil
                          :environment (program-environment environment)
                          :directory (and directory (sb-ext:parse-native-namestring directory))
                          :input (if input :stream nil)
                          :output :stream :error :stream
                          :external-format :utf-8)
    (error () nil)))

(defun process-answer (process)
  "How PROCESS ended: :EXITED and its exit code, or :SIGNALED and 128 plus
the signal's number, as a shell gives it."
  (if (eq (sb-ext:process-status process) :signaled)
      (values :signaled (+ 128 (sb-ext:process-exit-code process)))
      (values :exited (sb-ext:process-exit-code process))))

(defun wait-for-output (output errors)
  "Wait a moment for either open output to have something to read."
  (let ((open (find-if #'captured-open-p (list output errors))))
    (if open
        (sb-sys:wait-until-fd-usable (sb-sys:fd-stream-fd (captured-stream open)) :input 0.01 nil)
        (sleep 0.01))))

(defun drain (output errors buffer)
  "Read what both outputs hold now, until neither has more or one is too
large."
  (loop while (and (or (read-available output buffer) (read-available errors buffer))
                   (not (captured-full-p output))
                   (not (captured-full-p errors)))))

(defun drive (process input output errors seconds)
  "Feed INPUT to PROCESS and drain its OUTPUT and ERRORS until it ends, an
output is too large, or SECONDS pass.  Values :EXITED or :SIGNALED and the
exit code, :TOO-MUCH or :TIMEOUT.  The program has ended when it exits, even
while processes it started hold its outputs open: what it wrote is read, and
they are left to be stopped with its group."
  (let ((buffer (make-array 65536 :element-type '(unsigned-byte 8)))
        (end (+ (get-internal-real-time) (* seconds internal-time-units-per-second))))
    (loop
      (let ((progress (write-available input)))
        (when (read-available output buffer) (setf progress t))
        (when (read-available errors buffer) (setf progress t))
        (cond ((or (captured-full-p output) (captured-full-p errors))
               (return :too-much))
              ((not (sb-ext:process-alive-p process))
               ;; It has exited, so all it wrote is in the pipes already.
               (drain output errors buffer)
               (when (or (captured-full-p output) (captured-full-p errors))
                 (return :too-much))
               (finish-captured-lines errors)
               (return (process-answer process)))
              ((>= (get-internal-real-time) end)
               (return :timeout))
              ((not progress)
               (wait-for-output output errors)))))))

(defun run-process (app path arguments directory input environment seconds on-error-line)
  "Run PATH with ARGUMENTS for at most SECONDS, handing ON-ERROR-LINE, when
given, each line of its standard error as it comes.  Values how it ended (as
DRIVE does, or :NOT-STARTED), the exit code, the output and the error output.
APP's place for programs is given back once the program's group has ended,
by a thread of its own when the group has not ended by then, as when
ON-ERROR-LINE signals."
  (let ((process nil))
    (unwind-protect
         (progn
           (setf process (start-process path arguments directory input environment))
           (if (null process)
               :not-started
               (let ((input (make-instance 'program-input
                                           :stream (sb-ext:process-input process)
                                           :octets (sb-ext:string-to-octets
                                                    (or input "") :external-format :utf-8)))
                     (output (make-instance 'captured-output
                                            :stream (sb-ext:process-output process)))
                     (errors (make-instance 'captured-output
                                            :stream (sb-ext:process-error process)
                                            :lines (and on-error-line
                                                        (make-instance 'line-reader
                                                                       :function on-error-line)))))
                 (unwind-protect
                      (multiple-value-bind (outcome code)
                          (drive process input output errors seconds)
                        (values outcome code (captured-text output) (captured-text errors)))
                   ;; Closing the outputs before the group is stopped also
                   ;; tells a program still writing that no one reads.
                   (close-input input)
                   (close (captured-stream output) :abort t)
                   (close (captured-stream errors) :abort t)))))
      (if (and process (group-alive-p process))
          (stop-in-background process app)
          (release-program-place app)))))

;;; ------------------------------------------------------------------
;;; Answered by a test

(defun handler-answer (handler name arguments directory input environment)
  "What HANDLER, standing in for the program, answers, as RUN-PROCESS values
it."
  (multiple-value-bind (output code error-output)
      (funcall handler name arguments directory input environment)
    (let ((error-output (or error-output "")))
      (unless (and (stringp output) (stringp error-output) (typep code '(or null integer)))
        (error "*program-handler* answered ~s, ~s and ~s, not an output, an exit code ~
                or NIL, and an error output" output code error-output))
      (flet ((size (text) (length (sb-ext:string-to-octets text :external-format :utf-8))))
        (cond ((null code) :not-started)
              ((or (> (size output) +output-limit+) (> (size error-output) +output-limit+))
               (values :too-much code output error-output))
              (t (values :exited code output error-output)))))))

;;; ------------------------------------------------------------------
;;; One run

(defun run-outcome (name arguments directory input environment seconds on-error-line)
  "Run the program NAME, or ask *PROGRAM-HANDLER*, within SECONDS and the
tenant's places.  Values how it ended, the exit code, the output and the
error output."
  (let* ((handler *program-handler*)
         (path (and (not handler) (program-path name))))
    (cond ((< seconds 1) :no-time)
          ((and (not handler) (not path)) :not-started)
          (t (let ((app (claim-program-place)))
               (cond ((null app) :full)
                     (handler
                      (unwind-protect
                           (multiple-value-bind (outcome code output error-output)
                               (handler-answer handler name arguments directory input environment)
                             (when (and on-error-line (eq outcome :exited))
                               (pass-error-lines on-error-line error-output))
                             (values outcome code output error-output))
                        (release-program-place app)))
                     (t (run-process app path arguments directory input environment
                                     seconds on-error-line))))))))

(defun outcome-detail (outcome code)
  "What the trace shows of a run's OUTCOME."
  (ecase outcome
    (:exited (format nil "exit ~d" code))
    (:signaled (format nil "signal ~d" (- code 128)))
    (:timeout "timeout")
    (:not-started "could not start")
    (:too-much "output too large")
    (:full "full")
    (:no-time "no time")
    ((nil) "stopped by the caller")))

(defun run-program (name arguments &key directory input environment (timeout 10)
                                        on-error-line)
  "Run NAME, a program the application declares with (:programs ...), with
ARGUMENTS, a list of strings passed as they are with no shell between.
DIRECTORY, an absolute path, is where it runs; INPUT, a string, its standard
input; ENVIRONMENT, an alist of strings, is added to the few variables of the
server's it sees.  Values its standard output, its exit code and its standard
error, the outputs decoded as UTF-8.  A code other than 0 is an answer.
ON-ERROR-LINE, a function, is called with each line of standard error as the
program writes it; an error it signals stops the program and is signalled
from here.  Signals PROGRAM-FAILURE when the program cannot be started, runs
past TIMEOUT seconds (from 1 to 3600, and held to the operation's deadline
less one second), writes more than 8 MB to either output, or when four of
the tenant's programs are running (spec/outbound.md 6)."
  (check-run name arguments directory input environment timeout on-error-line)
  (let ((seconds (seconds-allowed timeout))
        (started (trace-clock-us))
        (outcome nil) (code nil) (output nil) (error-output nil))
    (unwind-protect
         (multiple-value-setq (outcome code output error-output)
           (run-outcome name arguments directory input environment seconds on-error-line))
      ;; Recorded also when ON-ERROR-LINE stopped the run, which then has
      ;; no outcome.
      (note-step :external :name (run-name name arguments) :source :core
                           :detail (outcome-detail outcome code)
                           :started started :duration (- (trace-clock-us) started)))
    (case outcome
      ((:exited :signaled) (values output code error-output))
      (t (program-failure outcome name :output output :error-output error-output
                                       :seconds (ceiling seconds))))))
