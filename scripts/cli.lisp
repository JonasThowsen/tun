;;;; scripts/cli.lisp -- the tun command (spec/cli.md) from this working tree.
;;;; Usage: bin/tun COMMAND...
;;;; Loads the kernel, tun-cli and every module under modules/, then runs the
;;;; command. The Nix-built tun (flake.nix, cli) loads the same from the store.

(load (merge-pathnames "setup.lisp" *load-truename*))
(in-package #:tun-build)

;;; Compiled into a directory of its own, as the REPL is: the strict build
;;; sees a file's warnings only when it compiles that file itself.
(asdf:initialize-output-translations
 `(:output-translations
   (,(namestring *root*) ,(namestring (merge-pathnames ".build/cli-fasl/" *root*)))
   :inherit-configuration))

(defun module-systems ()
  "The ASDF systems of the modules under modules/: tun-NAME."
  (mapcar #'pathname-name (directory (merge-pathnames "modules/*/tun-*.asd" *root*))))

;;; Loading may print, and the command's output must be only its own.
(let ((*standard-output* *error-output*))
  (apply #'load-quietly "tun-cli" (module-systems)))

(funcall (find-symbol "MAIN" "TUN.CLI"))
