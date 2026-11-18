;;;; tests/scenarios.lisp -- scenarios (spec/preview.md 3): the named data a
;;;; preview, a browser check or a test starts from, made through the
;;;; client's operations; keeping what one installs from the next; and the
;;;; server `tun preview` starts.

(in-package #:tun.test-support)

(declaim (optimize (safety 3) (debug 2)))

(defstruct (scenario (:constructor make-scenario (name package actors description function)))
  (name "" :type string :read-only t)
  (package "" :type string :read-only t)
  (actors '() :type list :read-only t)
  (description nil :type (or null string) :read-only t)
  (function nil :type function :read-only t))

(defvar *scenarios* (make-hash-table :test 'equal)
  "Every scenario defined, by (PACKAGE . NAME): the name of the package it
was defined in and its name in lower case. Two systems loaded in one image
may each define a scenario of the same name, such as default.")

(defmacro define-scenario (name (&key actors) &body body)
  "Define the scenario NAME in the current package. BODY makes its records in
*APP* through CALL-OK as the actors it names, so record policies, rules and
the audit apply as they do in use. ACTORS, strings such as
\"employee:anna\", are the actors a preview offers sign-in links for. A
string first in BODY describes the scenario."
  (check-type name symbol)
  (dolist (actor actors)
    (unless (and (stringp actor) (parse-actor actor))
      (error "define-scenario ~(~a~): ~s is not an actor such as \"employee:anna\""
             name actor)))
  (let ((description (and (stringp (first body)) (first body))))
    `(register-scenario
      (make-scenario ,(string-downcase name) ,(package-name *package*) ',actors ,description
                     (lambda () ,@(if description (rest body) body))))))

(defun register-scenario (scenario)
  "Add SCENARIO to the scenarios, in place of its package's of that name."
  (setf (gethash (cons (scenario-package scenario) (scenario-name scenario)) *scenarios*)
        scenario))

(defun package-scenarios (packages)
  "The scenarios defined in PACKAGES, a list of package names, by name."
  (sort (loop for scenario being the hash-values of *scenarios*
              when (member (scenario-package scenario) packages :test #'string=)
                collect scenario)
        #'string< :key #'scenario-name))

(defun find-scenario (name &key package)
  "The scenario NAME, a string or symbol, defined in PACKAGE, a package
designator, or NIL. Without PACKAGE, the one scenario of that name in any
package; an error when several packages define one."
  (let ((name (string-downcase name)))
    (if package
        (let ((package (find-package package)))
          (and package (values (gethash (cons (package-name package) name) *scenarios*))))
        (let ((found (loop for scenario being the hash-values of *scenarios*
                           when (string= name (scenario-name scenario))
                             collect scenario)))
          (when (rest found)
            (error "The packages ~{~a~^ and ~} each define a scenario ~a; name the package"
                   (sort (mapcar #'scenario-package found) #'string<) name))
          (first found)))))

(defun scenario-names ()
  "The names of every scenario defined, in order, each once."
  (sort (remove-duplicates (loop for scenario being the hash-values of *scenarios*
                                 collect (scenario-name scenario))
                           :test #'string=)
        #'string<))

(defun run-scenario (scenario &key package)
  "Make the records of SCENARIO in *APP*, as a test does before it looks at
them. SCENARIO is a scenario, or the name of one, found as FIND-SCENARIO
finds it with PACKAGE."
  (let ((scenario (cond ((scenario-p scenario) scenario)
                        ((find-scenario scenario :package package))
                        (t (error "There is no scenario ~(~a~); the scenarios are ~{~a~^, ~}"
                                  scenario (scenario-names))))))
    (unless *app*
      (error "run-scenario ~a needs *APP*, as with-test-app binds it" (scenario-name scenario)))
    (funcall (scenario-function scenario))
    scenario))

;;; ------------------------------------------------------------------
;;; Isolation (spec/testing.md 1)

(defparameter *isolated-variables* '(tun:*program-handler* tun:*http-json-handler*)
  "Tun's variables through which a scenario or a test installs what answers
for another system for every thread. Each generated test, and each scenario
the scenario test runs, sees them NIL, and what it sets reaches neither the
next scenario nor the next test (spec/testing.md 1, Isolation).")

(defun call-with-variables-unset (variables function)
  "Call FUNCTION with each of VARIABLES, special variables, bound to NIL, so
what FUNCTION sets them to ends with it."
  (progv variables (make-list (length variables))
    (funcall function)))

;;; ------------------------------------------------------------------
;;; The check runs' image and their scenarios' templates (spec/preview.md 4,
;;; «One image, one database server, workers»)

(defvar *client-packages* '()
  "The names of the packages the client's own systems define, its own
modules' among them, as LOAD-CLIENT-SYSTEMS found them; NIL when it did not
load the client.")

(defun own-system-p (name directories)
  "True when the system NAME's directory is within one of DIRECTORIES, the
client's own."
  (let* ((system (asdf:find-system name nil))
         (place (and system (asdf:system-source-directory system))))
    (and place
         (some (lambda (directory)
                 (uiop:subpathp place (uiop:ensure-directory-pathname directory)))
               directories))))

(defun foreign-dependencies (system directories)
  "The systems SYSTEM depends on, at any depth through the client's own,
that are not the client's: those outside DIRECTORIES."
  (let ((seen '()) (foreign '()))
    (labels ((walk (name)
               (unless (member name seen :test #'equal)
                 (push name seen)
                 (dolist (dependency (asdf:system-depends-on (asdf:find-system name)))
                   (let ((dependency (if (consp dependency) (second dependency) dependency)))
                     (when (stringp dependency)
                       (if (own-system-p dependency directories)
                           (walk dependency)
                           (pushnew dependency foreign :test #'equal))))))))
      (walk system))
    (reverse foreign)))

(defun load-client-systems (system directories)
  "Load the client's SYSTEM, its dependencies outside DIRECTORIES, the
client's own, first, and note in *CLIENT-PACKAGES* the packages its own
systems define."
  (let ((*compile-verbose* nil) (*load-verbose* nil))
    (handler-bind ((warning #'muffle-warning))
      (mapc #'asdf:load-system (foreign-dependencies system directories))
      (let ((before (list-all-packages)))
        (asdf:load-system system)
        (setf *client-packages*
              (mapcar #'package-name (set-difference (list-all-packages) before)))))))

(defvar *random-state-at-start* nil
  "A copy of the random state this process started with, when the check
image's maker kept one: a server from the image starts from it, as a
fresh SBCL starts from its own, so a scenario that draws random values
makes the data a preview of it makes.")

(defun save-check-image (file)
  "Save this process, the client loaded, as the image FILE a check's server
starts from, and end. Its random state is the one it started with."
  (when *random-state-at-start*
    (setf *random-state* (make-random-state *random-state-at-start*)))
  (sb-ext:save-lisp-and-die (namestring file)))

(defun fingerprint (value)
  "What of VALUE changes when its object is changed in place and a scenario
holds it: a hash table's count, a list's length, a vector's length."
  (typecase value
    (hash-table (hash-table-count value))
    (list (list-length value))
    ((and vector (not string)) (length value))
    (t nil)))

(defun global-values (&optional (packages *client-packages*))
  "Each global variable of PACKAGES' own symbols and Tun's isolated
variables, with its value and FINGERPRINT, as (SYMBOL VALUE FINGERPRINT)."
  (let ((symbols (copy-list *isolated-variables*)))
    (dolist (name packages)
      (let ((package (find-package name)))
        (when package
          (do-symbols (symbol package)
            (when (and (eq (symbol-package symbol) package)
                       (boundp symbol)
                       (not (constantp symbol))
                       (member (sb-int:info :variable :kind symbol) '(:special :global)))
              (pushnew symbol symbols))))))
    (mapcar (lambda (symbol)
              (let ((value (symbol-value symbol)))
                (list symbol value (fingerprint value))))
            symbols)))

(defun changed-variables (before &optional (after (global-values)))
  "The variables of AFTER whose value or fingerprint differs from BEFORE's,
or that BEFORE did not have, by name."
  (sort (loop for (symbol value fingerprint) in after
              for old = (assoc symbol before)
              unless (and old (eq value (second old)) (equal fingerprint (third old)))
              collect (format nil "~a::~a" (package-name (symbol-package symbol))
                              (symbol-name symbol)))
        #'string<))

;;; ------------------------------------------------------------------
;;; The preview's server

(defun option-value (argv option)
  (second (member option argv :test #'string=)))

(defun scenario-report (scenario &optional (sets '() sets-p))
  "What a preview shows of SCENARIO as JSON: its name, description and
actors, or none; and, for a template, SETS, the variables it set."
  (let ((report (if scenario
                       (jobj "scenario" (scenario-name scenario)
                             "description" (or (scenario-description scenario) "")
                             "actors" (jarr (scenario-actors scenario)))
                    (jobj "actors" (jarr '())))))
    (when sets-p
      (setf (jget report "sets") (jarr sets)))
    report))

(defun write-preview-report (file scenario &rest sets)
  "Write to FILE, as JSON, what the preview shows of SCENARIO: its name,
description and actors, or none; with SETS, a template's report."
  (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string (to-json-string (apply #'scenario-report scenario sets)) out)))

(defun serve-preview (application-class &key (name "tun") (argv sb-ext:*posix-argv*))
  "Serve APPLICATION-CLASS as `tun preview` starts it (spec/preview.md 2).
ARGV holds the server's flags, which must include --claimed-identity, and
the preview's own: --scenario NAME, the scenario to make before the server
listens (default, when the client defines one); --preview-report FILE,
where the scenario and its actors are then written as JSON;
--scenario-made, for a database copied from a scenario's template, which
makes no scenario; --seed-template FILE, which makes the scenario,
writes its report to FILE with the variables it set, and ends without
listening; and --page-sweep FILE, which writes to FILE, once the scenario
is in place and before the server listens, the pages the page sweep's
GETs get as each of its actors, for the generated browser check
(spec/preview.md 4)."
  (unless (member "--claimed-identity" argv :test #'string=)
    (error "A preview serves with --claimed-identity"))
  (let* ((asked (option-value argv "--scenario"))
         (scenario (if asked (find-scenario asked) (find-scenario "default")))
         (report (option-value argv "--preview-report"))
         (seed (option-value argv "--seed-template"))
         (made (member "--scenario-made" argv :test #'string=))
         (sweep (option-value argv "--page-sweep")))
    (when (and asked (null scenario))
      (format *error-output* "~a: there is no scenario ~a; the scenarios are ~{~a~^, ~}~%"
              name asked (scenario-names))
      (uiop:quit 2))
    (tun.runtime:main application-class
                      :name name :argv argv
                      :before-serving (lambda (application)
                                        (cond (seed
                                               (seed-template application scenario seed))
                                              (t
                                               (when (and scenario (not made))
                                                 (let ((*app* application))
                                                   (funcall (scenario-function scenario))))
                                               (when report
                                                 (write-preview-report report scenario))
                                               (when sweep
                                                 (write-page-sweep sweep application
                                                                   scenario))))))))

(defun seed-template (application scenario file)
  "Make SCENARIO in APPLICATION's database, a template's, write its report
with the variables it set to FILE, close the application and end."
  (let ((before (global-values)))
    (when scenario
      (let ((*app* application))
        (funcall (scenario-function scenario))))
    (write-preview-report file scenario (changed-variables before))
    (tun.runtime:close-application application)
    (finish-output)
    (uiop:quit 0)))
