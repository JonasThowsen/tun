;;;; scripts/setup.lisp -- shared prelude for every bin/ script.
;;;; Loads ASDF from the Nix-provided SBCL wrapper, registers this tree, keeps
;;;; compiled files under .build/ (never in ~/.cache), and turns off the
;;;; reader's #. evaluation for everything that follows.

(setf *read-eval* nil)
(load (or (sb-ext:posix-getenv "ASDF") (error "Run inside `nix develop` (ASDF is not set)")))

(defpackage #:tun-build
  (:use #:cl)
  (:export #:*root* #:load-quietly #:compile-strictly #:exit-with #:client-application-class))
(in-package #:tun-build)

(defparameter *root*
  (make-pathname :name nil :type nil
                 :defaults (merge-pathnames "../" (make-pathname :name nil :type nil
                                                                 :defaults *load-truename*))))
(setf *root* (truename *root*))

;;; The kernel, its modules, the test client and any client under clients/;
;;; then whatever the environment adds, such as clients kept elsewhere.
(asdf:initialize-source-registry
 `(:source-registry (:directory ,*root*)
                    (:tree ,(merge-pathnames "modules/" *root*))
                    (:directory ,(merge-pathnames "tests/client/" *root*))
                    (:tree ,(merge-pathnames "clients/" *root*))
                    :inherit-configuration))
(asdf:initialize-output-translations
 `(:output-translations
   (,(namestring *root*) ,(namestring (merge-pathnames ".build/fasl/" *root*)))
   :inherit-configuration))

(defun load-quietly (&rest systems)
  "Load third-party SYSTEMS without letting their warnings count against us."
  (let ((*compile-verbose* nil) (*load-verbose* nil) (*compile-print* nil))
    (handler-bind ((warning #'muffle-warning))
      (dolist (s systems) (asdf:load-system s)))))

(defun our-systems ()
  "Names of every registered ASDF system whose definition lives under *ROOT*."
  (remove-if-not (lambda (name)
                   (let ((dir (asdf:system-source-directory name)))
                     (and dir (eql 0 (search (namestring *root*) (namestring dir))))))
                 (asdf:registered-systems)))

(defun compile-strictly (systems &key force)
  "Load our SYSTEMS, collecting every compiler warning and style warning.
Returns the list of warning strings (empty = clean)."
  (let ((warnings '())
        ;; A compile error (e.g. a macro rejecting its arguments) fails the
        ;; build too, instead of turning into an error at run time.
        (uiop:*compile-file-failure-behaviour* :error))
    (handler-bind ((warning (lambda (w)
                              ;; Compiling then loading a file in one image redefines its
                              ;; macros; that is not a defect in the code.
                              (unless (typep w 'sb-kernel:redefinition-with-defmacro)
                                (push (format nil "~a" w) warnings))
                              (muffle-warning w))))
      (with-compilation-unit (:override t)
        (dolist (s systems)
          (asdf:find-system s))
        ;; One operate call over the last system (which depends on the others),
        ;; so forced systems compile exactly once.
        (asdf:load-system (car (last systems)) :force (and force (our-systems)))))
    (nreverse warnings)))

(defun client-application-class (client)
  "The application class of CLIENT, an ASDF system: <name> serves the class in
<NAME>:*APPLICATION-CLASS*, a second manifest <name>-<manifest> (a system of
the same client, with no package of its own, such as a minimal manifest) the
one in <NAME>:*<MANIFEST>-APPLICATION-CLASS*."
  (let* ((dash (and (not (find-package (string-upcase client))) (position #\- client :from-end t)))
         (package (string-upcase (subseq client 0 dash)))
         (variable (if dash
                       (format nil "*~:@(~a~)-APPLICATION-CLASS*" (subseq client (1+ dash)))
                       "*APPLICATION-CLASS*")))
    (symbol-value (or (find-symbol variable package)
                      (error "~a defines no ~a" package variable)))))

(defun exit-with (code)
  (finish-output *standard-output*)
  (finish-output *error-output*)
  (sb-ext:exit :code code :abort nil))
