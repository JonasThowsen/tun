;;;; core/module.lisp -- modules: reusable domain packages between the kernel
;;;; and a client (tun-platform.md §2, core.md §1.3).
;;;;
;;;; A module is a separate ASDF system under modules/<name>/ with its own
;;;; package(s).  Its first form after IN-PACKAGE is DEFINE-MODULE, which
;;;; declares its name, the modules it depends on and the kernel versions it
;;;; builds against, and defines the module's mixin class.  Every method the
;;;; module adds (before/after an operation, a seam, a screen) specializes on
;;;; that mixin.  APPLICATION inherits the mixins of every loaded module, most
;;;; dependent first, so methods run in dependency order of the modules and a
;;;; client's methods (on its own, more specific classes) run last.
;;;;
;;;; The module's last form is SEAL-MODULE: its packages are locked and its
;;;; definitions join the integrity snapshot, exactly as the kernel's do.

(in-package #:tun.core)

(declaim (optimize (safety 3) (debug 2)))

(defparameter +core-version+ "2.0.0"
  "The kernel's version.  Modules declare the range they build against; the
client build (flake.nix, lib.buildClient) and DEFINE-MODULE both refuse a
module whose range does not contain it.  The first versioned core was 0.1.0.")

(defun core-package-p (package)
  "True for the kernel's and the modules' packages: TUN and TUN.*."
  (let ((name (package-name package)))
    (or (string= name "TUN") (string-prefix-p "TUN." name))))

;;; ------------------------------------------------------------------
;;; Versions

(defun parse-version (string)
  (mapcar #'parse-integer (cl-ppcre:split "\\." string)))

(defun version-compare (a b)
  "-1, 0 or 1 comparing version strings A and B (missing parts are 0)."
  (loop for x in (parse-version a)
        for y in (parse-version b)
        do (cond ((< x y) (return-from version-compare -1))
                 ((> x y) (return-from version-compare 1))))
  (let ((la (length (parse-version a))) (lb (length (parse-version b))))
    (cond ((= la lb) 0)
          ((< la lb) (if (every #'zerop (nthcdr la (parse-version b))) 0 -1))
          (t (if (every #'zerop (nthcdr lb (parse-version a))) 0 1)))))

(defun parse-constraint (constraint)
  "Values operator and version of a constraint such as \">= 1.0\"."
  (multiple-value-bind (match groups)
      (cl-ppcre:scan-to-strings "^\\s*(>=|<=|>|<|=)\\s*([0-9]+(?:\\.[0-9]+)*)\\s*$" constraint)
    (unless match (error "Malformed version constraint ~s (use e.g. \">= 1.0\")" constraint))
    (values (aref groups 0) (aref groups 1))))

(defun version-satisfies-p (version constraint)
  (multiple-value-bind (operator bound) (parse-constraint constraint)
    (let ((c (version-compare version bound)))
      (cond ((string= operator ">=") (>= c 0))
            ((string= operator ">") (> c 0))
            ((string= operator "<=") (<= c 0))
            ((string= operator "<") (< c 0))
            (t (= c 0))))))

;;; ------------------------------------------------------------------
;;; The module registry

(defclass module ()
  ((name :initarg :name :reader module-name)
   (depends-on :initarg :depends-on :initform '() :reader module-depends-on)
   (core-range :initarg :core-range :initform '() :reader module-core-range)
   (packages :initarg :packages :reader module-packages)
   (mixin :initarg :mixin :reader module-mixin)
   (description :initarg :description :initform nil :reader module-description)
   (location :initarg :location :initform nil :reader module-location)
   (on-open :initarg :on-open :initform '() :reader module-on-open
            :documentation "Functions (symbols) run when an application opens, in module order.")
   (sealed :initform nil :accessor module-sealed-p)))

(defvar *loaded-modules* '()
  "Loaded modules in load order, which ASDF makes a dependency order.")

(defun all-modules () *loaded-modules*)

(defun find-module (name &optional errorp)
  (or (find name *loaded-modules* :key #'module-name :test #'string=)
      (and errorp (error "No module named ~s is loaded" name))))

(defun package-module (package)
  "The module owning PACKAGE, or NIL."
  (let ((name (package-name package)))
    (find-if (lambda (m) (member name (module-packages m) :test #'string=)) *loaded-modules*)))

(defun current-definition-module ()
  "Who owns a definition being macroexpanded now: the module whose package is
*PACKAGE*, \"core\" in a kernel package, else \"client\".  Decided at
expansion time, like CURRENT-DEFINITION-SOURCE."
  (let ((module (package-module *package*)))
    (cond (module (module-name module))
          ((core-package-p *package*) "core")
          (t "client"))))

(defun class-owner-module (class)
  "\"core\", a module name or \"client\" for the class a method specializes on."
  (let* ((name (and class (class-name class)))
         (package (and name (symbol-package name))))
    (cond ((null class) "core")
          ((null package) "client")
          ((package-module package) (module-name (package-module package)))
          ((or (core-package-p package) (eq package (find-package "COMMON-LISP"))) "core")
          (t "client"))))

(defun module-dependency-closure (names)
  "NAMES plus every module they depend on, transitively, in load order."
  (let ((wanted '()))
    (labels ((visit (name)
               (unless (member name wanted :test #'string=)
                 (push name wanted)
                 (let ((m (find-module name)))
                   (when m (mapc #'visit (module-depends-on m)))))))
      (mapc #'visit names))
    (let ((loaded (remove-if-not (lambda (m) (member (module-name m) wanted :test #'string=)) *loaded-modules*)))
      (append (mapcar #'module-name loaded)
              ;; Names not loaded at all, last (the caller reports them).
              (remove-if (lambda (n) (find-module n)) (reverse wanted))))))

(defun check-core-range (name constraints)
  (let ((failed (remove-if (lambda (c) (version-satisfies-p +core-version+ c)) constraints)))
    (when failed
      (extension-error "Module ~a builds against core ~{~a~^ and ~}, but this core is ~a (constraint ~{~a~^, ~} fails)"
                       name constraints +core-version+ failed))))

(defun install-module-mixins ()
  "APPLICATION's direct superclasses: the loaded modules' mixins, the most
dependent module first, so that every module is more specific than the
modules it depends on (CLOS runs :before and :after methods of an operation
least specific first, i.e. in dependency order)."
  (let ((mixins (mapcar (lambda (m) (find-class (module-mixin m))) (reverse *loaded-modules*))))
    (reinitialize-instance (find-class 'application)
                           :direct-superclasses (or mixins (list (find-class 'standard-object))))))

(defun register-module (name &key depends-on core-range packages mixin description location on-open)
  (unless (cl-ppcre:scan "^[a-z][a-z0-9_]*$" name)
    (extension-error "Module name ~s must match [a-z][a-z0-9_]*" name))
  (when (member name depends-on :test #'string=)
    (extension-error "Module ~a depends on itself" name))
  (dolist (dependency depends-on)
    (let ((loaded (find-module dependency)))
      (cond ((null loaded)
             (extension-error "Module ~a depends on ~a, which is not loaded (declare it in the module's .asd)"
                              name dependency))
            ((member name (module-dependency-closure (list dependency)) :test #'string=)
             (extension-error "Module dependency cycle: ~a -> ~a -> ~a" name dependency name)))))
  (check-core-range name core-range)
  (let ((existing (find-module name)))
    (when (and existing (module-sealed-p existing))
      (extension-error "Module ~a is already loaded and sealed" name))
    (dolist (package packages)
      (let ((owner (package-module (find-package package))))
        (when (and owner (string/= (module-name owner) name))
          (extension-error "Package ~a already belongs to module ~a" package (module-name owner)))))
    (let ((module (make-instance 'module :name name :depends-on depends-on :core-range core-range
                                         :packages packages :mixin mixin :description description
                                         :location location :on-open on-open)))
      (setf *loaded-modules* (if existing
                          (substitute module existing *loaded-modules*)
                          (append *loaded-modules* (list module))))
      (install-module-mixins)
      module)))

(defmacro define-module (name &body options)
  "Declare the module NAME (a symbol; its name is the downcased symbol name).
OPTIONS: (:depends-on module...), (:core constraint...) such as (:core \">= 1.0\"
\"< 2.0\"), (:packages package...) (default: the current package),
(:on-open function...) run when an application opens, and (:documentation
string).  Defines the mixin class NAME-MODULE that the module's methods
specialize on."
  (let* ((module (string-downcase (symbol-name name)))
         (mixin (symbolicate name "-MODULE"))
         (depends-on (mapcar (lambda (d) (string-downcase (string d))) (rest (assoc :depends-on options))))
         (core (rest (assoc :core options)))
         (packages (mapcar #'string (or (rest (assoc :packages options)) (list (package-name *package*)))))
         (on-open (rest (assoc :on-open options)))
         (doc (second (assoc :documentation options))))
    ;; Also at compile time: the module's own definitions, compiled next,
    ;; ask at macroexpansion which module owns them (CURRENT-DEFINITION-MODULE).
    `(eval-when (:compile-toplevel :load-toplevel :execute)
       (defclass ,mixin () ()
         (:documentation ,(format nil "Module ~a: its methods specialize on this mixin of APPLICATION." module)))
       (register-module ,module :depends-on ',depends-on :core-range ',core
                                :packages ',packages :mixin ',mixin :description ,doc
                                :location ,(current-source-location) :on-open ',on-open)
       ',mixin)))

;;; ------------------------------------------------------------------
;;; Publishing to the client-facing TUN package

(defun publish (symbols)
  "Export SYMBOLS from TUN, the public interface clients use (core.md §1.2).  A
module publishes what clients may call; the rest of its package is for the
modules that depend on it.  A name TUN already exports from elsewhere is a
conflict, refused."
  (let ((tun (or (find-package "TUN") (error "The TUN package is not defined yet"))))
    (sb-ext:with-unlocked-packages ("TUN")
      (dolist (symbol symbols)
        (multiple-value-bind (existing status) (find-symbol (symbol-name symbol) tun)
          (when (and status (not (eq existing symbol)))
            (extension-error "Cannot publish ~a::~a: TUN already has ~a::~a"
                             (package-name (symbol-package symbol)) (symbol-name symbol)
                             (package-name (symbol-package existing)) (symbol-name existing)))
          (unless status (import (list symbol) tun))
          (export (list symbol) tun))))
    symbols))

;;; ------------------------------------------------------------------
;;; Sealing: package locks and the integrity snapshot
;;;
;;; A client (or a later module) may add methods to the kernel's and the
;;; modules' generic functions; it may not redefine their functions or
;;; macros, replace or remove their methods, or define new functions in
;;; their packages.  Each package is snapshot when it is sealed (the kernel's
;;; at the end of public.lisp, a module's by SEAL-MODULE); every application
;;; start compares against the snapshot and refuses to run on a mismatch.

(defvar *sealed-packages* '() "Names of sealed (locked, snapshot) packages.")
(defvar *definition-snapshot* '()
  "List of (symbol kind definition methods) for every sealed definition.")
(defvar *snapshot-symbols* (make-hash-table :test 'eq)
  "The symbols of *DEFINITION-SNAPSHOT*, for a check cheap enough to run
before every request.")

(defun raw-definition (symbol)
  "SYMBOL's function as the call site sees it.  Unlike FDEFINITION, which
strips SBCL's encapsulations (TRACE, SB-INT:ENCAPSULATE), SYMBOL-FUNCTION
returns the wrapper when there is one; a generic function keeps its
encapsulations inside, so those are checked separately."
  (symbol-function symbol))

(defun encapsulated-generic-function-p (function)
  (and (typep function 'generic-function)
       (sb-pcl::generic-function-encapsulations function)
       t))

(defun package-definitions (package)
  (loop for symbol being the present-symbols of package
        when (and (eq (symbol-package symbol) package) (fboundp symbol))
          collect (let ((macro (macro-function symbol)))
                    (if macro
                        (list symbol :macro macro nil)
                        (let ((function (raw-definition symbol)))
                          (list symbol :function function
                                ;; Slot accessor methods are regenerated whenever an
                                ;; extension reinitializes an entity class; only
                                ;; DEFMETHOD-defined methods are kept.
                                (and (typep function 'generic-function)
                                     (remove-if (lambda (m) (typep m 'closer-mop:standard-accessor-method))
                                                (closer-mop:generic-function-methods function)))))))))

(defun seal-packages (names)
  "Snapshot and lock the packages NAMES."
  (dolist (name names)
    (let ((package (or (find-package name) (error "No package ~a to seal" name))))
      (unless (member (package-name package) *sealed-packages* :test #'string=)
        (let ((definitions (package-definitions package)))
          (dolist (entry definitions)
            (setf (gethash (first entry) *snapshot-symbols*) t))
          (setf *definition-snapshot* (append *definition-snapshot* definitions)
                *sealed-packages* (append *sealed-packages* (list (package-name package)))))
        (sb-ext:lock-package package))))
  (length *definition-snapshot*))

(defun seal-module (name)
  "The module's last form: lock its packages and snapshot its definitions."
  (let ((module (find-module name t)))
    (seal-packages (module-packages module))
    (setf (module-sealed-p module) t)
    module))

(defun sealed-fbound-symbols ()
  (loop for name in *sealed-packages*
        for package = (find-package name)
        append (loop for symbol being the present-symbols of package
                     when (and (eq (symbol-package symbol) package) (fboundp symbol))
                       collect symbol)))

(defun definition-integrity-violations ()
  (append
   (loop for symbol in (sealed-fbound-symbols)
         unless (gethash symbol *snapshot-symbols*)
           collect (format nil "~a was defined in a sealed package after it was sealed" symbol))
   (loop for (symbol kind definition methods) in *definition-snapshot*
         for current = (and (fboundp symbol)
                            (if (eq kind :macro) (macro-function symbol) (raw-definition symbol)))
         if (not (eq current definition))
           collect (format nil "~a was redefined or wrapped" symbol)
         else if (encapsulated-generic-function-p current)
           collect (format nil "~a was wrapped (encapsulated)" symbol)
         else
           append (loop for method in methods
                        unless (member method (closer-mop:generic-function-methods definition))
                          collect (format nil "a method of ~a was replaced or removed: ~a" symbol method)))))

(defun check-definition-integrity (&optional (when "start"))
  (let ((violations (definition-integrity-violations)))
    (when violations
      (extension-error "Refusing to ~a; core or a module has been modified after loading:~{~%  ~a~}"
                       when violations))
    t))

;;; ------------------------------------------------------------------
;;; Applications declare the modules they enable

(defvar *application-modules* (make-hash-table :test 'eq)
  "Application class name -> the module names the client enables (its manifest).")

(defvar *application-on-open* (make-hash-table :test 'eq)
  "Application class name -> functions (symbols) the client runs when the
application opens, after every enabled module's.")

(defvar *application-sign-in* (make-hash-table :test 'eq)
  "Application class name -> the ways people sign in, as the client wrote
them in (:sign-in strategy...) (spec/auth.md 3.5).  TUN.AUTH reads them.")

(defvar *application-mail* (make-hash-table :test 'eq)
  "Application class name -> its mail provider, as the client wrote it in
(:mail provider) (spec/mail.md 1).  TUN.MAIL reads it.")

(defvar *application-queues* (make-hash-table :test 'eq)
  "Application class name -> how many jobs each of its queues runs at once,
as the client wrote it in (:queues (name limit)...) (spec/jobs.md 6).  TUN.JOBS
reads it.")

(defvar *application-error-mail* (make-hash-table :test 'eq)
  "Application class name -> who hears of new errors, as the client wrote
them in (:error-mail address...) (spec/errors.md 5).  TUN.ERRORS reads it.")

(defvar *application-instructions* (make-hash-table :test 'eq)
  "Application class name -> what the client tells agents about working with
it, as it wrote it in (:instructions text...) (spec/waiting.md 4).")

;;; ------------------------------------------------------------------
;;; Installing the application as an app (spec/ui.md 4.2)

(defvar *application-web-app* (make-hash-table :test 'eq)
  "Application class name -> what installs it as an app, from (:web-app ...),
with its icons (spec/ui.md 4.2).  TUN.WEB serves it.")

(defparameter +web-app-icons+
  '(("icon.svg" "image/svg+xml" nil) ("icon-192.png" "image/png" 192)
    ("icon-512.png" "image/png" 512) ("icon-maskable-512.png" "image/png" 512)
    ("apple-touch-icon.png" "image/png" 180))
  "The files a web app's icon directory holds: the name, the content type and
a PNG's width and height.")

(defparameter +colour-scanner+ (cl-ppcre:create-scanner "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})$"))

(defun web-app-options (name options)
  "OPTIONS, the plist of (:web-app ...) in the definition of NAME, checked.
Values the options but :ICONS, with the defaults filled in, and the icons'
directory as written."
  (unless (and (evenp (length options))
               (loop for key in options by #'cddr
                     always (member key '(:short-name :theme-color :dark-theme-color
                                          :background-color :icons))))
    (error "define-application ~s: (:web-app ...) takes :icons, :short-name, :theme-color, ~
            :dark-theme-color and :background-color, not ~s" name options))
  (destructuring-bind (&key short-name (theme-color "#ffffff") (dark-theme-color "#0a0a0a")
                         (background-color "#ffffff") icons)
      options
    (unless (stringp icons)
      (error "define-application ~s: (:web-app ...) needs :icons, the directory of the ~
              app's icons, such as \"icons/\"" name))
    (unless (or (null short-name) (and (stringp short-name) (<= 1 (length short-name) 12)))
      (error "define-application ~s: the web app's :short-name is 1 to 12 characters, not ~s"
             name short-name))
    (loop for (option colour) on (list :theme-color theme-color :dark-theme-color dark-theme-color
                                       :background-color background-color)
            by #'cddr
          unless (and (stringp colour) (cl-ppcre:scan +colour-scanner+ colour))
            do (error "define-application ~s: the web app's ~(~s~) is #rgb or #rrggbb, not ~s"
                      name option colour))
    (values (list :short-name short-name :theme-color theme-color
                  :dark-theme-color dark-theme-color :background-color background-color)
            icons)))

(defun source-directory ()
  "The directory of the file being compiled (or loaded from source).  An editor that
compiles one form through a temporary file names its own file as SBCL's
source namestring, so that one is preferred."
  (let ((named (and (boundp 'sb-c::*source-namestring*) sb-c::*source-namestring*)))
    (uiop:pathname-directory-pathname
     (or (and named (probe-file named)) *compile-file-truename* *load-truename*
         *default-pathname-defaults*))))

(defun png-size (octets)
  "The width and height of the PNG OCTETS, or NIL when they are not a PNG."
  (flet ((u32 (start) (loop for i from start below (+ start 4)
                            for n = (aref octets i) then (+ (* n 256) (aref octets i))
                            finally (return n))))
    (when (and (> (length octets) 24)
               (equalp (subseq octets 0 8) #(137 80 78 71 13 10 26 10))
               (equalp (subseq octets 12 16) #(73 72 68 82)))
      (values (u32 16) (u32 20)))))

(defun web-app-icon (directory file type size)
  "The icon FILE in DIRECTORY, checked: a plist of its :FILE, :TYPE,
:OCTETS and :HASH (the first 12 hex digits of its SHA-256)."
  (let ((path (merge-pathnames file directory)))
    (unless (probe-file path)
      (error "The web app's icon ~a is missing (spec/ui.md 4.2)" path))
    (let ((octets (with-open-file (in path :element-type '(unsigned-byte 8))
                    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
                      (read-sequence octets in)
                      octets))))
      (if size
          (multiple-value-bind (width height) (png-size octets)
            (unless (and width (= width size) (= height size))
              (error "The web app's icon ~a is ~:[not a PNG~;~:*~a~], not a ~dx~d PNG"
                     path (and width (format nil "~dx~d" width height)) size size)))
          (unless (search "<svg" (sb-ext:octets-to-string octets :external-format '(:utf-8 :replacement #\?)))
            (error "The web app's icon ~a is not an SVG" path)))
      (list :file file :type type :octets octets
            :hash (subseq (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha256 octets))
                          0 12)))))

(defun web-app-icons (directory)
  "The icons in DIRECTORY, checked.  DEFINE-APPLICATION reads them when it
is compiled, as the kit reads htmx, so the compiled client holds them: a
built client server loads its compiled files, not its sources."
  (loop for (file type size) in +web-app-icons+
        collect (web-app-icon directory file type size)))

(defun application-web-app (application)
  "What installs APPLICATION as an app: the plist of its class's (or the
nearest declaring superclass's) (:web-app ...), with its :ICONS read, or NIL
without one (spec/ui.md 4.2)."
  (values (declared-option *application-web-app* application)))

;;; A tenant's language, currency and time zone (spec/i18n.md 2.2)

(defvar *application-locale* (make-hash-table :test 'eq)
  "Application class name -> its (:locale ...) checked, as a plist of
:LANGUAGES, :SOURCE-LANGUAGE, :CURRENCY and :TIME-ZONE.")

(defun locale-options (name options)
  "OPTIONS, the plist of (:locale ...) in the definition of NAME, checked,
with the defaults filled in (spec/i18n.md 2.2)."
  (unless (and (evenp (length options))
               (loop for key in options by #'cddr
                     always (member key '(:languages :source-language :currency :time-zone))))
    (error "define-application ~s: (:locale ...) takes :languages, :source-language, ~
            :currency and :time-zone, not ~s" name options))
  (destructuring-bind (&key (languages '("en" "nb")) source-language (currency "EUR")
                         (time-zone "UTC"))
      options
    (unless (and (consp languages)
                 (every (lambda (l) (member l +languages+ :test #'equal)) languages)
                 (= (length languages) (length (remove-duplicates languages :test #'equal))))
      (error "define-application ~s: :languages is a list of ~{~s~^ and ~}, without repeats, ~
              not ~s" name +languages+ languages))
    (let ((source-language (or source-language (first languages))))
      (unless (member source-language languages :test #'equal)
        (error "define-application ~s: :source-language ~s is not one of :languages ~s"
               name source-language languages))
      (unless (currency-p currency)
        (error "define-application ~s: :currency ~s is not a currency Tun knows ~
                (spec/i18n.md 5.1)" name currency))
      (unless (time-zone-p time-zone)
        (error "define-application ~s: :time-zone ~s is not a time zone Tun knows ~
                (spec/i18n.md 6.1)" name time-zone))
      (list :languages languages :source-language source-language
            :currency currency :time-zone time-zone))))

(defun application-locale-options (application)
  "The checked (:locale ...) of APPLICATION's class, or of the nearest
superclass that declares one, else Tun's defaults."
  (or (declared-option *application-locale* application)
      (locale-options 'application '())))

(defun application-languages (application)
  "The languages a tenant of APPLICATION may be set to, its default first."
  (getf (application-locale-options application) :languages))

(defun application-source-language (application)
  "The language APPLICATION's client writes its own copy in."
  (getf (application-locale-options application) :source-language))

(defmacro define-application (name (&rest features) &body options)
  "Define the client's application class NAME: its FEATURES (mixins carrying
its methods, most specific first) on top of APPLICATION, which inherits the
loaded modules.  (:modules name...) is the client's manifest: the modules it
enables (their dependencies are enabled with them).  (:on-open function...)
names functions the kernel calls when the application opens, after the
modules' own, each in a write transaction as the system actor (a client
schedules its recurring workflows there).  (:sign-in strategy...) lists the
ways people sign in, such as (:workos :domain (:env \"WORKOS_DOMAIN\") ...),
as spec/auth.md 3.5 describes; an authenticated server needs at least one.  (:mail provider) names the mail provider, such as (:resend
:api-key (:env \"RESEND_API_KEY\") :from ...), as spec/mail.md 1 describes;
without it, mail is logged, not sent.  (:queues (name limit)...) says how
many jobs each queue runs at once, such as (:queues (:default 2) (:mail 1)),
as spec/jobs.md 6 describes; a queue it does not name runs one.
(:error-mail address...) names who is mailed when a new error appears, each
a string or (:env NAME), as spec/errors.md 5 describes.  (:instructions
text...) tells agents how to work with the client's tools, after Tun's own
instructions in MCP's initialize, as spec/waiting.md 4 describes.  (:web-app
:icons directory ...) lets people install the application as an app, as
spec/ui.md 4.2 describes; the directory is relative to this file, and its
icons are read when the form is compiled.  (:locale :languages ... :currency
... :time-zone ...) gives the languages a tenant may be set to and a new
tenant's language, currency and time zone, as spec/i18n.md 2.2 describes.
Other OPTIONS are DEFCLASS options."
  (let* ((modules (mapcar (lambda (m) (string-downcase (string m)))
                          (rest (assoc :modules options))))
         (on-open (rest (assoc :on-open options)))
         (sign-in (assoc :sign-in options))
         (mail (assoc :mail options))
         (queues (rest (assoc :queues options)))
         (error-mail (rest (assoc :error-mail options)))
         (instructions (rest (assoc :instructions options)))
         (web-app (assoc :web-app options))
         (locale (assoc :locale options))
         (class-options (remove-if (lambda (o) (member (first o) '(:modules :on-open :sign-in :mail
                                                                   :queues :error-mail
                                                                   :instructions :web-app
                                                                   :locale)))
                                   options)))
    (dolist (strategy (rest sign-in))
      (unless (and (consp strategy) (keywordp (first strategy)))
        (error "define-application ~s: a sign-in strategy is a list such as (:google ...), ~
                not ~s" name strategy)))
    (unless (or (null mail)
                (and (= (length mail) 2) (consp (second mail)) (keywordp (first (second mail)))))
      (error "define-application ~s: (:mail provider) names one provider, such as ~
              (:mail (:resend ...)), not ~s" name mail))
    (dolist (queue queues)
      (unless (and (consp queue) (= (length queue) 2) (keywordp (first queue))
                   (typep (second queue) '(integer 1 100)))
        (error "define-application ~s: a queue is (name limit), such as (:mail 1), not ~s"
               name queue)))
    (unless (every #'stringp instructions)
      (error "define-application ~s: (:instructions text...) takes strings, not ~s"
             name instructions))
    (dolist (address error-mail)
      (unless (or (stringp address)
                  (and (consp address) (eq (first address) :env) (stringp (second address))))
        (error "define-application ~s: an error mail address is a string or (:env NAME), not ~s"
               name address)))
    `(progn
       (defclass ,name (,@features application) () ,@class-options)
       (setf (gethash ',name *application-modules*) ',modules
             (gethash ',name *application-on-open*) ',on-open)
       ,(if sign-in
            `(setf (gethash ',name *application-sign-in*) ',(rest sign-in))
            `(remhash ',name *application-sign-in*))
       ,(if mail
            `(setf (gethash ',name *application-mail*) ',(second mail))
            `(remhash ',name *application-mail*))
       (setf (gethash ',name *application-queues*) ',queues
             (gethash ',name *application-error-mail*) ',error-mail
             (gethash ',name *application-instructions*) ',instructions)
       ,(if web-app
            (multiple-value-bind (web-app-options icons) (web-app-options name (rest web-app))
              `(setf (gethash ',name *application-web-app*)
                     ',(append web-app-options
                               (list :icons (web-app-icons
                                             (merge-pathnames (uiop:ensure-directory-pathname icons)
                                                              (source-directory)))))))
            `(remhash ',name *application-web-app*))
       ,(if locale
            `(setf (gethash ',name *application-locale*) ',(locale-options name (rest locale)))
            `(remhash ',name *application-locale*))
       ',name)))

(defun declared-option (table application)
  "What APPLICATION's class, or the nearest superclass that declares one,
holds in TABLE, and as a second value whether any class declared it.
APPLICATION is an application or the name of its class."
  (let ((class (if (symbolp application) (find-class application) (class-of application))))
    (closer-mop:ensure-finalized class)
    (loop for c in (closer-mop:class-precedence-list class)
          for (value present) = (multiple-value-list (gethash (class-name c) table))
          when present return (values value t)
          finally (return (values nil nil)))))

(defun application-sign-in-specs (application)
  "The sign-in strategies APPLICATION's class (or the nearest declaring
superclass) lists, as written, and as a second value whether any class
declared them.  APPLICATION is an application or the name of its class."
  (declared-option *application-sign-in* application))

(defvar *queue-defaults* (make-hash-table :test 'eq)
  "Queue keyword -> how many jobs it runs at once when the application does
not say, for the kernel's own queues (spec/jobs.md 6).")

(defun declare-queue-default (queue limit)
  "Let the kernel's QUEUE run LIMIT jobs at once unless an application's
(:queues ...) says otherwise."
  (check-type queue keyword)
  (check-type limit (integer 1))
  (setf (gethash queue *queue-defaults*) limit))

(defun application-queue-limit (application queue)
  "How many jobs QUEUE, a keyword, runs at once in APPLICATION: what its
class (or the nearest declaring superclass) says in (:queues ...), else the
kernel's default for QUEUE, else 1."
  (or (second (assoc queue (declared-option *application-queues* application)))
      (gethash queue *queue-defaults*)
      1))

(defun application-instructions (application)
  "What APPLICATION's class (or the nearest declaring superclass) tells
agents about working with it: a list of paragraphs (spec/waiting.md 4)."
  (values (declared-option *application-instructions* application)))

(defun application-error-mail-specs (application)
  "Who APPLICATION's class (or the nearest declaring superclass) says hears
of new errors, as written: strings and (:env NAME)."
  (values (declared-option *application-error-mail* application)))

(defun application-mail-spec (application)
  "The mail provider APPLICATION's class (or the nearest declaring
superclass) names, as written, such as (:resend :api-key ...); NIL when
none does."
  (values (declared-option *application-mail* application)))

(defun configured-value (value)
  "VALUE as a client wrote it in define-application's options: a string, or
(:env NAME), read now.  Values the string, or NIL and a description of what
is missing."
  (cond ((stringp value) (if (plusp (length value)) value (values nil "an empty value")))
        ((and (consp value) (eq (first value) :env) (stringp (second value)))
         (let ((text (uiop:getenv (second value))))
           (if (plusp (length text))
               text
               (values nil (format nil "the environment variable ~a" (second value))))))
        (t (values nil (format nil "~s, which is neither a string nor (:env NAME)" value)))))

(defun application-on-open-functions (application)
  "The client's on-open functions of APPLICATION's class (or the nearest
declaring superclass)."
  (loop for class in (closer-mop:class-precedence-list (class-of application))
        for (functions present) = (multiple-value-list (gethash (class-name class) *application-on-open*))
        when present return functions))

(defun application-declared-modules (application)
  "The module names APPLICATION's class (or the nearest declaring superclass)
enables, or NIL when no client declared any (core alone: everything loaded)."
  (loop for class in (closer-mop:class-precedence-list (class-of application))
        for declared = (gethash (class-name class) *application-modules*)
        when declared return declared))

(defun enabled-modules (application)
  "List of (module enabled-by) for APPLICATION, in dependency order.
ENABLED-BY is \"client\" for a module the client names, else the first
enabled module (in dependency order) that depends on it."
  (let ((declared (application-declared-modules application)))
    (if (null declared)
        (mapcar (lambda (m) (list m "client")) *loaded-modules*)
        (let* ((names (module-dependency-closure declared))
               (modules (remove nil (mapcar #'find-module names))))
          (loop for m in modules
                collect (list m (if (member (module-name m) declared :test #'string=)
                                    "client"
                                    (or (loop for other in modules
                                              when (member (module-name m) (module-depends-on other) :test #'string=)
                                                return (module-name other))
                                        "client"))))))))

(defun check-enabled-modules (application)
  "Refuse to start when the loaded modules are not exactly what the client
enables (with dependencies): a module enabled but not loaded, or loaded but
not enabled."
  (let ((declared (application-declared-modules application)))
    (when declared
      (let* ((wanted (module-dependency-closure declared))
             (missing (remove-if #'find-module wanted))
             (extra (remove-if (lambda (m) (member (module-name m) wanted :test #'string=)) *loaded-modules*)))
        (when missing
          (extension-error "The client enables ~{~a~^, ~}, which ~:[is~;are~] not loaded (add ~:*~:[it~;them~] to the client's .asd)"
                           missing (rest missing)))
        (when extra
          (extension-error "Loaded but not enabled by the client: ~{~a~^, ~} (add to :modules or remove from the .asd)"
                           (mapcar #'module-name extra)))))
    t))

;;; Module revisions for introspect_runtime: given by the build.

(defvar *module-revisions* '()
  "Alist module name -> revision, fixed when a server image is built.")

(defun module-revision (name)
  (let ((env (sb-ext:posix-getenv (format nil "TUN_MODULE_REVISION_~:@(~a~)" name))))
    (or (and env (plusp (length env)) env)
        (cdr (assoc name *module-revisions* :test #'string=))
        "unknown")))
