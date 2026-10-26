;;;; scripts/repl.lisp -- an SBCL image for working on Tun from Emacs with SLY.
;;;; Usage: bin/repl [--port N] [SYSTEM]
;;;; Starts Slynk on 127.0.0.1:N (default 4010), then loads SYSTEM (default
;;;; tun/tests) from this checkout.  The contract is in spec/tooling.md and
;;;; the editor setup in docs/emacs.md.

(load (merge-pathnames "setup.lisp" *load-truename*))
(in-package #:tun-build)

;;; bin/build compiles incrementally into .build/fasl/ and sees a file's
;;; warnings only when it compiles that file itself.  The REPL compiles into
;;; its own directory, so the strict build never skips a file the REPL
;;; compiled first.  The directory is also the REPL's alone because of the
;;; policy below: ASDF compiles a file again when its source changes, not
;;; when the policy does, so files compiled under another one must not be
;;; found here.
(asdf:initialize-output-translations
 `(:output-translations
   (,(namestring *root*) ,(namestring (merge-pathnames ".build/repl-debug-fasl/" *root*)))
   :inherit-configuration))

;;; Below (debug 2) SBCL cannot restart a function's frames, and below
;;; (debug 3) it drops a local the rest of the function does not read, so
;;; the debugger could not show it.
(sb-ext:restrict-compiler-policy 'debug 3)

(load-quietly "alexandria" "bordeaux-threads" "cl-base64" "cl-ppcre" "closer-mop" "com.inuoe.jzon"
              "drakma" "fiveam" "hunchentoot" "ironclad" "sqlite" "cl-postgres" "swank" "usocket"
              "slynk")

;;; SLY's compile-file (C-c C-k) writes the fasl beside the source by default.
;;; Put it with the REPL's other compiled files instead.
(setf slynk:*fasl-pathname-function*
      (lambda (source options)
        (declare (ignore options))
        (ensure-directories-exist (asdf:compile-file-pathname* source))))

(defparameter *default-port* 4010)
(defparameter *default-system* "tun/tests")

(defun usage-error (format-control &rest arguments)
  "Report a bad command line on standard error and exit 2."
  (format *error-output* "~&bin/repl: ~?~%usage: bin/repl [--port N] [SYSTEM]~%"
          format-control arguments)
  (exit-with 2))

(defun parse-port (string)
  "The TCP port STRING names, or a usage error."
  (let ((port (and string
                   (handler-case (parse-integer string)
                     (parse-error () nil)))))
    (if (typep port '(integer 1 65535))
        port
        (usage-error "--port needs a number from 1 to 65535, not ~s" string))))

(defun parse-arguments (arguments)
  "The port and the system named by ARGUMENTS, bin/repl's command line, as two values."
  (let ((port *default-port*)
        (system *default-system*))
    (loop while arguments
          do (let ((argument (pop arguments)))
               (cond ((string= argument "--port")
                      (setf port (parse-port (pop arguments))))
                     ((or (zerop (length argument)) (char= (char argument 0) #\-))
                      (usage-error "unknown option ~a" argument))
                     (t
                      (setf system argument)))))
    (values port system)))

(defun start-slynk (port)
  "Start Slynk on 127.0.0.1:PORT, or exit 1 when the port cannot be bound."
  (handler-case (slynk:create-server :port port :interface "127.0.0.1" :dont-close t)
    (error (condition)
      (format *error-output* "~&bin/repl: cannot listen on 127.0.0.1:~d: ~a~%" port condition)
      (exit-with 1))))

(defun load-system-reporting-failure (system)
  "Load SYSTEM.  A failure is reported, not fatal: the REPL stays up so the
file can be fixed and the system loaded again."
  (handler-case (asdf:load-system system)
    (error (condition)
      (format *error-output* "~&;; bin/repl: loading ~a failed:~%;;   ~a~%~
                              ;; Fix it, then evaluate (asdf:load-system ~s).~%"
              system condition system))))

(multiple-value-bind (port system) (parse-arguments (rest sb-ext:*posix-argv*))
  ;; Slynk starts before the load, so a load that fails can be fixed from Emacs.
  (start-slynk port)
  (load-system-reporting-failure system)
  (format t "~&;; bin/repl: ~a loaded; Slynk on 127.0.0.1:~d (M-x sly-connect)~%"
          system port)
  (finish-output))

;;; On exit SBCL waits up to *exit-timeout* seconds, 60 by default, for other
;;; threads to finish.  Slynk's connection threads never do by themselves, so
;;; stopping the REPL would hang for a minute.
(setf sb-ext:*exit-timeout* 2)

;;; setup.lisp turns off the reader's #. for the build scripts.  At a REPL the
;;; person typing is the author, so the reader gets its default back.
(setf *read-eval* t)

;;; Without a terminal (started by an agent or in the background) SBCL's own
;;; REPL would read end-of-file and exit, so wait instead until stopped.
(unless (interactive-stream-p *standard-input*)
  (loop (sleep 3600)))
