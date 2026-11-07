;;;; tests/scenarios.lisp -- scenarios (spec/preview.md 3): the named data a
;;;; preview, a browser check or a test starts from, made through the
;;;; client's operations; and the server `tun preview` starts.

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
;;; The preview's server

(defun option-value (argv option)
  (second (member option argv :test #'string=)))

(defun write-preview-report (file scenario)
  "Write to FILE, as JSON, what the preview shows of SCENARIO: its name,
description and actors, or none."
  (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string (to-json-string
                   (if scenario
                       (jobj "scenario" (scenario-name scenario)
                             "description" (or (scenario-description scenario) "")
                             "actors" (jarr (scenario-actors scenario)))
                       (jobj "actors" (jarr '()))))
                  out)))

(defun serve-preview (application-class &key (name "tun") (argv sb-ext:*posix-argv*))
  "Serve APPLICATION-CLASS as `tun preview` starts it (spec/preview.md 2).
ARGV holds the server's flags, which must include --claimed-identity, and
two of the preview's own: --scenario NAME, the scenario to make before the
server listens (default, when the client defines one), and --preview-report
FILE, where the scenario and its actors are then written as JSON."
  (unless (member "--claimed-identity" argv :test #'string=)
    (error "A preview serves with --claimed-identity"))
  (let* ((asked (option-value argv "--scenario"))
         (scenario (if asked (find-scenario asked) (find-scenario "default")))
         (report (option-value argv "--preview-report")))
    (when (and asked (null scenario))
      (format *error-output* "~a: there is no scenario ~a; the scenarios are ~{~a~^, ~}~%"
              name asked (scenario-names))
      (uiop:quit 2))
    (tun.runtime:main application-class
                      :name name :argv argv
                      :before-serving (lambda (application)
                                        (when scenario
                                          (let ((*app* application))
                                            (funcall (scenario-function scenario))))
                                        (when report
                                          (write-preview-report report scenario))))))
