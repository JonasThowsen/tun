;;;; cli/catalog.lisp -- what `tun list` reports (spec/cli.md 2): every
;;;; module loaded in this image, described from its own definitions through
;;;; the kernel's registry, the same data registry_describe gives over MCP.

(in-package #:tun.cli)

(declaim (optimize (safety 3) (debug 2)))

;;; ------------------------------------------------------------------
;;; The two ways a command ends early

(define-condition usage-error (simple-error) ()
  (:documentation "A command line the tun command refuses, such as an unknown
module or an invalid name. Signalled before anything is changed; exit 2."))

(define-condition step-failed (simple-error) ()
  (:documentation "A step of a command that could not be done, such as `nix
flake lock` exiting non-zero; exit 1."))

(defun refuse (control &rest arguments)
  "Signal a USAGE-ERROR whose message is CONTROL formatted with ARGUMENTS."
  (error 'usage-error :format-control control :format-arguments arguments))

(defun fail-step (control &rest arguments)
  "Signal a STEP-FAILED whose message is CONTROL formatted with ARGUMENTS."
  (error 'step-failed :format-control control :format-arguments arguments))

;;; ------------------------------------------------------------------
;;; Modules by name

(defun module-system (name)
  "The ASDF system of the module NAME."
  (format nil "tun-~a" name))

(defun module-names ()
  "The names of the loaded modules, in alphabetical order."
  (sort (mapcar #'module-name (all-modules)) #'string<))

(defun resolve-modules (names)
  "NAMES and every module they depend on, in dependency order. Refuses a name
that is not a module of this revision."
  (check-type names list)
  (let ((unknown (remove-if #'find-module names)))
    (when unknown
      (refuse "no module named ~{~a~^, ~}; the modules are ~{~a~^, ~}"
              unknown (module-names))))
  (module-dependency-closure names))

(defun tun-revision ()
  "The Tun commit this program was built from, or \"unknown\". The launcher
passes it in TUN_CORE_REVISION, as the client servers' launcher does."
  (let ((revision (uiop:getenv "TUN_CORE_REVISION")))
    (if (and revision (plusp (length revision))) revision "unknown")))

(defun commit-revision-p (revision)
  "True when REVISION is a full commit hash, not \"unknown\" or a dirty tree."
  (and (stringp revision) (cl-ppcre:scan "^[0-9a-f]{40}$" revision) t))

;;; ------------------------------------------------------------------
;;; Describing a module

(defun owned-by (module-name items &key (key "name"))
  "The KEY of every registry entry in the vector ITEMS that MODULE-NAME owns."
  (loop for item across items
        when (equal (jget item "module") module-name)
          collect (jget item key)))

(defun module-entities (module-name registry)
  "Name and label of every entity MODULE-NAME owns."
  (loop for entity across (jget registry "entities")
        when (equal (jget entity "module") module-name)
          collect (jobj "name" (jget entity "name") "label" (jget entity "label"))))

(defun describe-catalog-module (module registry)
  "The `tun list --json` entry of MODULE, whose parts REGISTRY (the kernel's
registry description) attributes to it."
  (let ((name (module-name module)))
    (flet ((owned (key &optional (item-key "name"))
             (jarr (remove-duplicates (owned-by name (jget registry key) :key item-key)
                                      :test #'equal :from-end t))))
      (jobj "name" name
            "system" (module-system name)
            "description" (or (module-description module) "")
            "depends_on" (jarr (module-depends-on module))
            "core_range" (jarr (module-core-range module))
            "entities" (jarr (module-entities name registry))
            "operations" (owned "operations")
            "screens" (owned "screens")
            "settings" (owned "settings" "key")
            "workflows" (owned "workflows" "kind")
            "message_templates" (owned "message_templates")
            "extension_points" (owned "extension_points")))))

(defun module-catalog ()
  "The object `tun list --json` prints (spec/cli.md 2): the kernel's version,
this program's revision, and every loaded module in alphabetical order."
  ;; An application that declares no modules enables every loaded one, so
  ;; the registry describes all of them. It is never opened: describing
  ;; needs no store.
  (let ((registry (describe-registry (make-instance 'application))))
    (jobj "core_version" +core-version+
          "revision" (tun-revision)
          "modules" (jarr (mapcar (lambda (name)
                                    (describe-catalog-module (find-module name) registry))
                                  (module-names))))))
