;;;; scripts/serve.lisp -- start a client system from the working tree.
;;;; Usage: bin/serve --client NAME --port N --db PATH [--test-clock] [--address A]
;;;; The Nix-built servers (a client's flake.nix, through buildClient) call
;;;; the same TUN.RUNTIME:MAIN but load everything from the store.

(load (merge-pathnames "setup.lisp" *load-truename*))
(in-package #:tun-build)

(defparameter *client*
  (let ((tail (member "--client" sb-ext:*posix-argv* :test #'string=)))
    (or (second tail)
        (progn (format *error-output* "~&usage: bin/serve --client NAME --port N --db PATH|URL ...~%~
                                         NAME is a client system, such as test-client.~%")
               (exit-with 2)))))

(load-quietly "alexandria" "bordeaux-threads" "cl-base64" "cl-ppcre" "closer-mop" "com.inuoe.jzon"
              "hunchentoot" "ironclad" "sqlite" "cl-postgres" "swank")

(let ((*compile-verbose* nil) (*compile-print* nil) (*load-verbose* nil))
  (handler-bind ((warning #'muffle-warning))
    (asdf:load-system *client*)))

(funcall (find-symbol "MAIN" "TUN.RUNTIME") (client-application-class *client*)
         :name *client*)
