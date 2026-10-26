;;;; tests/support.lisp -- test helpers shared by the core suite and the
;;;; client suite: calling tools as an actor, fresh applications, scratch
;;;; databases, concurrency, and a real HTTP server.  Scenarios and the
;;;; preview's server are in tests/scenarios.lisp.

(defpackage #:tun.test-support
  (:use #:cl #:tun.core)
  (:export #:*app* #:call #:call-ok #:error-code-of #:with-test-app #:scratch-path #:find-by
           #:postgres-available-p #:scratch-postgres #:scratch-databases #:raw-sql #:table-columns
           #:run-concurrently #:free-port #:http-post #:with-test-server #:http-tool-call
           #:web-request #:web-login #:location
           #:enqueued-jobs #:perform-job #:drain-jobs
           #:public-interface-violations #:client-source-files #:client-files-under
           #:client-violations #:module-violations #:asd-violations #:module-asd-files #:+kernel-public-packages+ #:+module-library-packages+ #:file-text
           #:define-scenario #:find-scenario #:run-scenario #:scenario-names #:scenario-name #:scenario-actors
           #:scenario-description #:serve-preview))

(in-package #:tun.test-support)

(defvar *app* nil)

(defun call (tool actor &rest keys-and-values)
  "Call TOOL as ACTOR (\"role:name\") with JSON arguments; returns (values json error-code)."
  (handler-case
      (values (call-tool tool (apply #'jobj keys-and-values)
                         :application *app* :actor (parse-actor actor))
              nil)
    (operation-error (e) (values (operation-error-json e) (json-name-of (operation-error-code e))))))

(defun call-ok (tool actor &rest keys-and-values)
  "Like CALL but fails the test on an error result."
  (multiple-value-bind (json code) (apply #'call tool actor keys-and-values)
    (when code
      (error "~a as ~a failed: ~a" tool actor (to-json-string json)))
    json))

(defun error-code-of (json) (jget (jget json "error") "code"))

(defmacro with-test-app ((&rest keys &key db (test-clock t) (class ''application) &allow-other-keys) &body body)
  "Run BODY with *APP* bound to a fresh application (in-memory unless DB).
Other keys (such as :debug-tools and :allow-eval) are application initargs."
  `(let ((*app* (tun.runtime:open-application ,class :db ,db :test-clock ,test-clock
                                              ,@(loop for (k v) on keys by #'cddr
                                                      unless (member k '(:db :test-clock :class)) append (list k v)))))
     (unwind-protect (progn ,@body)
       (tun.runtime:close-application *app*))))

(defun arguments-include-p (definition json arguments)
  "True when JSON, a job's stored arguments, holds each of ARGUMENTS, a plist
of Lisp values by argument keyword, as the job would store it."
  (loop for (key value) on arguments by #'cddr
        for parameter = (find key (tun.jobs:job-definition-parameters definition)
                              :key #'parameter-keyword)
        always (and parameter
                    (equal (jget json (parameter-json-name parameter))
                           (type->json (parameter-type parameter) value)))))

(defun enqueued-jobs (kind &rest arguments)
  "The waiting jobs (queued or retrying) of KIND, the symbol DEFINE-JOB named,
whose arguments include ARGUMENTS, a plist by argument keyword: oldest
first, as JSON."
  (let ((definition (tun.jobs:find-job-definition kind)))
    (with-application (*app*)
      (with-transaction (:read)
        (mapcar #'entity->json
                (remove-if-not (lambda (job)
                                 (arguments-include-p definition (tun.jobs:job-arguments job)
                                                      arguments))
                               (select 'tun.jobs:job
                                       :where `(:and (:= "kind" ,(tun.jobs:job-definition-kind
                                                                  definition))
                                                     (:in "state" ("queued" "retrying")))
                                       :order-by '(("seq" :asc)))))))))

(defun perform-job (kind &rest arguments)
  "Enqueue a job of KIND with ARGUMENTS and run one attempt of it now, as the
runner does: its arguments through JSON, its body as system:job.  Values the
outcome (:succeeded, :failed, :cancelled or :snoozed) and the job afterwards,
as JSON."
  (with-application (*app*)
    (let ((job (with-actor ((system-actor "test"))
                 (with-transaction (:write)
                   (apply #'tun.jobs:enqueue-job kind arguments)))))
      (values (tun.jobs:run-job-now job)
              (with-transaction (:read)
                (entity->json (fetch 'tun.jobs:job (entity-id job))))))))

(defun drain-jobs (&key queue)
  "Run every due job, of QUEUE (a queue name) when given, until none is due,
including those the jobs enqueue.  Returns how many attempts it made."
  (with-application (*app*)
    (tun.jobs:run-due-jobs :queue queue)))

(defun scratch-path (name)
  "A fresh file path for a test database under the build directory."
  (let ((dir (merge-pathnames ".build/test-db/" (asdf:system-source-directory "tun"))))
    (ensure-directories-exist dir)
    (let ((path (merge-pathnames (format nil "~a-~a.sqlite" name (new-id "t")) dir)))
      (dolist (suffix '("" "-wal" "-shm"))
        (let ((p (probe-file (concatenate 'string (namestring path) suffix))))
          (when p (delete-file p))))
      path)))

(defun postgres-available-p ()
  "True when TUN_TEST_POSTGRES names a Postgres server tests may create
databases on (bin/test runs the core suite under bin/with-postgres)."
  (plusp (length (uiop:getenv "TUN_TEST_POSTGRES"))))

(defun scratch-postgres (name)
  "The URL of a fresh, empty database on the test Postgres server."
  (unless (postgres-available-p)
    (error "No test Postgres: TUN_TEST_POSTGRES is not set (bin/test sets it)"))
  (tun.store.postgres:postgres-create-database
   (uiop:getenv "TUN_TEST_POSTGRES")
   (substitute-if #\_ (lambda (c) (not (or (lower-case-p c) (digit-char-p c))))
                  (string-downcase (format nil "~a_~a" name (new-id "t"))))))

(defun scratch-databases (name)
  "A fresh database on every durable adapter available, as (label . db)
pairs: SQLite always, Postgres when the test server is there."
  (append (list (cons "sqlite" (scratch-path name)))
          (and (postgres-available-p) (list (cons "postgres" (scratch-postgres name))))))

(defun raw-sql (sql)
  "Run SQL directly on the current transaction's connection, bypassing the
store port: for tests that must change a schema behind the kernel's back."
  (etypecase (application-store *app*)
    (tun.store.sqlite:sqlite-store (sqlite:execute-to-list tun.store.sqlite::*connection* sql))
    (tun.store.postgres:postgres-store (tun.store.postgres::query sql))))

(defun table-columns (table)
  "The column names of TABLE, as the store describes its schema."
  (let ((entry (find-by "name" table (store-describe-schema (application-store *app*)))))
    (and entry (map 'list (lambda (column) (jget column "name")) (jget entry "columns")))))

(defun find-by (key value items)
  (find value (coerce items 'list) :key (lambda (x) (jget x key)) :test #'equal))

(defun run-concurrently (n function)
  "Call FUNCTION with indices 0..N-1 in N threads that start together; return
the vector of results (an error is returned as the condition object)."
  (let* ((app *app*)
         (results (make-array n :initial-element nil))
         (gate (sb-thread:make-semaphore :count 0))
         (threads (loop for i below n
                        collect (let ((i i))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (let ((*app* app))
                                       (sb-thread:wait-on-semaphore gate)
                                       (setf (aref results i)
                                             (handler-case (funcall function i)
                                               (error (e) e)))))
                                   :name (format nil "test worker ~d" i))))))
    (sb-thread:signal-semaphore gate n)
    (mapc #'sb-thread:join-thread threads)
    results))

;;; Over real HTTP

(defun free-port ()
  (let ((socket (usocket:socket-listen "127.0.0.1" 0 :reuse-address t)))
    (prog1 (usocket:get-local-port socket) (usocket:socket-close socket))))

(defun http-post (port path body &key actor)
  "POST BODY; returns (values status body-string headers)."
  (multiple-value-bind (bytes status headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d~a" port path)
                           :method :post :content (sb-ext:string-to-octets body :external-format :utf-8)
                           :content-type "application/json"
                           :additional-headers (and actor (list (cons "X-Tun-Actor" actor)))
                           :force-binary t :want-stream nil)
    (values status (if bytes (sb-ext:octets-to-string bytes :external-format :utf-8) "") headers)))

(defmacro with-test-server ((port &rest app-args) &body body)
  "Run BODY with *APP* served over HTTP on PORT.  The server takes claimed
identity (X-Tun-Actor, spec/auth.md 1) unless APP-ARGS give :IDENTITY."
  (let ((acceptor (gensym))
        (app-args (if (getf app-args :identity) app-args (list* :identity :claimed app-args))))
    `(with-test-app (,@app-args)
       (let* ((,port (free-port))
              (,acceptor (tun.http:start-server *app* :port ,port)))
         (unwind-protect (progn ,@body)
           (tun.http:stop-server ,acceptor))))))

(defun http-tool-call (port actor name arguments)
  (multiple-value-bind (status body)
      (http-post port "/mcp" (to-json-string (jobj "jsonrpc" "2.0" "id" 7 "method" "tools/call"
                                                   "params" (jobj "name" name "arguments" arguments)))
                 :actor actor)
    (let ((result (jget (parse-json body) "result")))
      (values (parse-json (jget (aref (jget result "content") 0) "text")) (jget result "isError") status))))


;;; The generated UI over real HTTP

(defun web-request (port path &key (method :get) parameters jar headers)
  "Values status, body and headers; redirects are not followed.  HEADERS is
an alist of further request headers."
  (multiple-value-bind (bytes status headers)
      (drakma:http-request (format nil "http://127.0.0.1:~d~a" port path)
                           :method method :parameters parameters :cookie-jar jar :redirect nil
                           :additional-headers headers
                           :external-format-out :utf-8 :force-binary t)
    (values status (if bytes (sb-ext:octets-to-string bytes :external-format :utf-8) "") headers)))

(defun web-login (port actor)
  "Log in through GET /login?actor=...; returns the cookie jar."
  (let ((jar (make-instance 'drakma:cookie-jar)))
    (web-request port "/login" :parameters (list (cons "actor" actor)) :jar jar)
    jar))

(defun location (headers)
  "The path of a redirect's Location header (Hunchentoot sends absolute URLs)."
  (let* ((url (cdr (assoc :location headers)))
         (scheme (and url (search "://" url))))
    (if scheme
        (subseq url (or (position #\/ url :start (+ scheme 3)) (length url)))
        url)))

;;; The public-interface check for client projects: a client may use only
;;; CL and the external symbols of the TUN package, and of TUN.UI for its
;;; pages.  It reads every client source file with the Lisp reader
;;; (*READ-EVAL* off) and rejects:
;;;   - any `::' qualifier outside strings and comments, and any symbol from a
;;;     package other than CL, KEYWORD, the client's own packages, or the
;;;     external symbols of TUN and TUN.UI;
;;;   - IN-PACKAGE to anything but the client's own packages, and DEFPACKAGE
;;;     options that use, import from or nickname a core package other than
;;;     those two;
;;;   - reflection and evaluation that reach packages by name (FIND-SYMBOL,
;;;     INTERN, FIND-PACKAGE, EVAL, READ-FROM-STRING, ...), or find symbols
;;;     another way (APROPOS, SYMBOL-PACKAGE, WITH-PACKAGE-ITERATOR, LOOP over
;;;     a package's symbols), bind them dynamically (PROGV), build functions
;;;     at run time (COERCE to FUNCTION or to a computed type) or call them
;;;     by name from a string (FORMAT's ~/name/), TRACE and STEP; and string
;;;     literals naming a core package;
;;;   - anything the reader refuses (#. is off, locked packages refuse interning).
;;; It is a review aid and a tripwire, not a sandbox: Lisp code in the same
;;; image can always reach further; see docs/architecture.md, "Known limits".

(defparameter +forbidden-cl-operators+
  '(find-symbol intern find-package find-all-symbols do-symbols do-external-symbols do-all-symbols
    list-all-packages use-package unuse-package import shadowing-import shadow export unexport unintern
    rename-package make-package delete-package package-name package-use-list package-used-by-list
    eval compile compile-file load read read-from-string read-preserving-whitespace read-delimited-list
    set-macro-character set-dispatch-macro-character make-dispatch-macro-character
    *readtable* *package* *read-eval*
    ;; review finding 5: other ways to find, bind or call symbols by name
    apropos apropos-list symbol-package with-package-iterator package-shadowing-symbols
    package-nicknames progv trace untrace step)
  "CL symbols a client never needs and that would reach core by name.")

(defun public-symbol-p (symbol &optional (packages '("TUN")))
  "True when SYMBOL is reachable as an external symbol of one of PACKAGES
(by default TUN, the clients' interface)."
  (some (lambda (package)
          (multiple-value-bind (found status) (find-symbol (symbol-name symbol) package)
            (and (eq found symbol) (eq status :external))))
        packages))

(defun core-package-name-p (designator)
  (let ((package (find-package designator)))
    (and package (core-package-p package))))

(defun walk-symbols (form function)
  (cond ((symbolp form) (funcall function form))
        ((consp form) (walk-symbols (car form) function) (walk-symbols (cdr form) function))
        ((and (vectorp form) (not (stringp form))) (map nil (lambda (x) (walk-symbols x function)) form))))

(defun walk-forms (form function)
  "Call FUNCTION on FORM and every cons inside it."
  (when (consp form)
    (funcall function form)
    (loop for tail on form
          do (walk-forms (car tail) function)
          while (consp (cdr tail)))))

(defun walk-strings (form function)
  (cond ((stringp form) (funcall function form))
        ((consp form) (walk-strings (car form) function) (walk-strings (cdr form) function))))

(defun designator-name (designator)
  (cond ((stringp designator) designator)
        ((symbolp designator) (symbol-name designator))
        (t nil)))

(defun read-all-forms (text package)
  (let ((*package* (find-package package))
        (*read-eval* nil))
    (with-input-from-string (in text)
      (loop for form = (read in nil in)
            until (eq form in)
            collect form))))

(defparameter +package-iteration-loop-words+
  '("SYMBOL" "SYMBOLS" "PRESENT-SYMBOL" "PRESENT-SYMBOLS" "EXTERNAL-SYMBOL" "EXTERNAL-SYMBOLS"))

(defun computed-coerce-p (form)
  "True for a COERCE FORM that makes a function, or whose type is computed."
  (let ((type (third form)))
    (or (not (and (consp type) (eq (first type) 'quote)))
        (let ((names '()))
          (walk-symbols (second type) (lambda (s) (push (symbol-name s) names)))
          (intersection names '("FUNCTION" "COMPILED-FUNCTION") :test #'string=)))))

(defun library-entry (package-name library-packages)
  (find package-name library-packages
        :key (lambda (entry) (if (consp entry) (first entry) entry)) :test #'string=))

(defun published-p (symbol)
  "Whether SYMBOL is part of TUN, the interface clients use (a module's
PUBLISH list)."
  (multiple-value-bind (found status) (find-symbol (symbol-name symbol) "TUN")
    (and (eq found symbol) (eq status :external))))

(defun stored-entity-name-p (symbol)
  "Whether SYMBOL names an entity with a table of its own."
  (let ((class (find-class symbol nil)))
    (and class (typep class 'tun.core::entity-class) (not (tun.core:entity-embedded-p class)))))

;;; A :: qualifier names a package's internal symbol.  In a string or a
;;; comment it is text, such as a Postgres cast in a query (:since::text).

(defun block-comment-end (text start)
  "The index after the #| comment that opens at START; block comments nest."
  (loop with depth = 0 and i = start
        while (< (1+ i) (length text))
        do (cond ((string= "#|" text :start2 i :end2 (+ i 2)) (incf depth) (incf i 2))
                 ((string= "|#" text :start2 i :end2 (+ i 2))
                  (incf i 2)
                  (when (zerop (decf depth)) (return i)))
                 (t (incf i)))
        finally (return (length text))))

(defun delimited-end (text start)
  "The index after the string or |symbol| whose delimiter is at START."
  (loop with closing = (char text start) and i = (1+ start)
        while (< i (length text))
        do (cond ((char= (char text i) #\\) (incf i 2))
                 ((char= (char text i) closing) (return (1+ i)))
                 (t (incf i)))
        finally (return (length text))))

(defun qualifier-in-code-p (text)
  "Whether TEXT, Lisp source, has :: outside its strings, comments and
character literals."
  (loop with i = 0
        while (< i (length text))
        do (let ((c (char text i))
                 (next (and (< (1+ i) (length text)) (char text (1+ i)))))
             (cond ((member c '(#\" #\|)) (setf i (delimited-end text i)))
                   ((char= c #\;) (setf i (or (position #\Newline text :start i) (length text))))
                   ((and (char= c #\#) (eql next #\|)) (setf i (block-comment-end text i)))
                   ((and (char= c #\#) (eql next #\\)) (incf i 3))
                   ((and (char= c #\:) (eql next #\:)) (return t))
                   (t (incf i))))
        finally (return nil)))

(defun public-interface-violations (text &key (package "COMMON-LISP-USER") (source "<string>")
                                          own-packages allowed-packages (public-packages '("TUN"))
                                          library-packages module-packages)
  "Every way TEXT (Lisp source, read in PACKAGE) reaches past CL and the
external symbols of PUBLIC-PACKAGES (for a client: TUN; for a module: the
kernel's public packages and those of the modules it depends on).
LIBRARY-PACKAGES (a module's libraries) may be used through their external
symbols: an entry is a package name (every external symbol) or (package
symbol-name...) (only those).  MODULE-PACKAGES (for a module: those of the
modules it depends on): an entity of theirs, whose table is that module's
own, is named only when the module publishes it (platform 2.3, 2.5); else
it is reached through the module's functions, by id."
  (let* ((violations '())
         (own (mapcar #'string-upcase (cons package own-packages)))
         (public (mapcar #'string-upcase public-packages))
         (allowed (append '("COMMON-LISP" "KEYWORD") own (mapcar #'string-upcase allowed-packages))))
    (flet ((note (control &rest args)
             (pushnew (format nil "~a: ~?" source control args) violations :test #'string=)))
      (when (qualifier-in-code-p text)
        (note "uses a :: qualifier"))
      (handler-case
          (let ((forms (read-all-forms text package)))
            (dolist (form forms)
              ;; Symbols: CL, KEYWORD, the client's own packages, TUN externals.
              (walk-symbols form
                            (lambda (s)
                              (let ((home (symbol-package s)))
                                (cond ((null home))
                                      ;; Backquote reads as SB-INT:QUASIQUOTE: syntax, not a use.
                                      ((eq s 'sb-int:quasiquote))
                                      ((member (package-name home) allowed :test #'string=)
                                       (when (and (eq home (find-package "COMMON-LISP"))
                                                  (member s +forbidden-cl-operators+))
                                         (note "uses ~a, which reaches packages by name or evaluates code" s)))
                                      ((core-package-p home)
                                       (cond ((not (public-symbol-p s public))
                                              (note "~a::~a is not part of the public interface (~{~a~^, ~})"
                                                    (package-name home) (symbol-name s) public))
                                             ((and (member (package-name home) module-packages :test #'string-equal)
                                                   (stored-entity-name-p s)
                                                   (not (published-p s)))
                                              (note "~a:~a is another module's table, which it does not publish (platform 2.5)"
                                                    (package-name home) (symbol-name s)))))
                                      ((library-entry (package-name home) library-packages)
                                       (let ((entry (library-entry (package-name home) library-packages)))
                                         (cond ((not (public-symbol-p s (list (package-name home))))
                                                (note "~a::~a is internal to its library" (package-name home) (symbol-name s)))
                                               ((and (consp entry) (not (member (symbol-name s) (rest entry) :test #'string=)))
                                                (note "~a:~a is not among the library symbols a module may use"
                                                      (package-name home) (symbol-name s))))))
                                      (t (note "uses ~a::~a from outside CL and ~{~a~^, ~}"
                                               (package-name home) (symbol-name s) public))))))
              ;; Package forms.
              (walk-forms form
                          (lambda (f)
                            (let ((head (and (symbolp (car f)) (symbol-name (car f)))))
                              (cond ((and (eq (car f) 'coerce) (computed-coerce-p f))
                                     (note "COERCE to a function or a computed type builds code at run time: ~s" f))
                                    ((and (eq (car f) 'loop)
                                          (some (lambda (x) (and (symbolp x) (member (symbol-name x) +package-iteration-loop-words+
                                                                                     :test #'string=)))
                                                f))
                                     (note "LOOP over a package's symbols reaches packages by name"))
                                    ((equal head "IN-PACKAGE")
                                     (let ((name (designator-name (second f))))
                                       (unless (and name (member (string-upcase name) own :test #'string=))
                                         (note "switches to package ~a" (second f)))))
                                    ((member head '("DEFPACKAGE" "DEFINE-PACKAGE") :test #'equal)
                                     (dolist (option (cddr f))
                                       (when (consp option)
                                         (dolist (item (if (eq (car option) :local-nicknames)
                                                           (mapcar (lambda (pair) (if (consp pair) (second pair) pair)) (cdr option))
                                                           (cdr option)))
                                           (let ((name (designator-name (if (consp item) (car item) item))))
                                             (when (and name (member (car option) '(:use :import-from :shadowing-import-from :local-nicknames))
                                                        (core-package-name-p name)
                                                        (not (member (string-upcase name) (append own public) :test #'string=)))
                                               (note "package option ~s names internal package ~a" (car option) name)))))))))))
              ;; Strings naming core packages.
              (walk-strings form
                            (lambda (string)
                              (when (cl-ppcre:scan "~[0-9,'#vV:@]*/" string)
                                (note "FORMAT's ~~/name/ calls a function by name: ~s" string))
                              (when (and (core-package-name-p string)
                                         (not (member (string-upcase string) (append own public) :test #'string=)))
                                (note "names internal package ~s" string))))))
        (error (e) (note "cannot be read in ~a: ~a" package e))))
    (nreverse violations)))

(defun client-files-under (root)
  "Every .lisp file under ROOT (any depth) except the test-suite under tests/.
DIRECTORY follows symbolic links and answers truenames, so a link out of
ROOT, such as direnv's .direnv/ into the Nix store, would bring in other
projects' sources; only files whose truename is under ROOT count."
  (let* ((root (namestring (truename root)))
         (tests (concatenate 'string root "tests/")))
    (remove-if-not (lambda (path)
                     (let ((name (namestring path)))
                       (and (eql 0 (search root name))
                            (not (eql 0 (search tests name))))))
                   (directory (merge-pathnames "**/*.lisp" root)))))

(defun client-source-files (system)
  "All Lisp sources of client SYSTEM, at any depth, except its tests."
  (client-files-under (asdf:system-source-directory system)))

(defparameter +asd-system-options+
  '(:description :long-description :version :author :maintainer :license :homepage
    :depends-on :serial :components :pathname)
  "What a client's or a module's DEFSYSTEM may say: data, no code.")

(defun asd-violations (text &key (source "<string>"))
  "A .asd of a client or a module may hold only DEFSYSTEM forms with the data
options of +ASD-SYSTEM-OPTIONS+, whose values are strings, keywords, numbers,
T and NIL: no :perform, no code, no symbols of ASDF or UIOP (review finding
5: (uiop:symbol-call :sb-ext :unlock-package ...) in a :perform)."
  (let ((violations '()))
    (flet ((note (control &rest args)
             (pushnew (format nil "~a: ~?" source control args) violations :test #'string=)))
      (when (qualifier-in-code-p text) (note "uses a :: qualifier"))
      (handler-case
          (dolist (form (read-all-forms text "ASDF-USER"))
            (if (not (and (consp form) (symbolp (first form)) (string= (symbol-name (first form)) "DEFSYSTEM")
                          (stringp (second form)) (evenp (length (cddr form)))))
                (note "holds a form other than (defsystem \"name\" ...): ~s" form)
                (loop for (key value) on (cddr form) by #'cddr
                      do (if (not (member key +asd-system-options+))
                             (note "DEFSYSTEM option ~s is not data a client or module may give" key)
                             (walk-symbols value
                                           (lambda (s)
                                             (unless (or (keywordp s) (eq s t) (eq s nil))
                                               (note "DEFSYSTEM ~s names the symbol ~s" key s))))))))
        (error (e) (note "cannot be read: ~a" e))))
    (nreverse violations)))

(defparameter +client-public-packages+ '("TUN" "TUN.UI")
  "What a client reaches past CL: TUN, and the components its pages are built
from (spec/ui.md 8).")

(defun client-violations (system package)
  "Public-interface violations in every source file of client SYSTEM and in
its .asd files (data only: ASD-VIOLATIONS)."
  (let ((root (asdf:system-source-directory system)))
    (append
     (loop for file in (client-source-files system)
           append (public-interface-violations (file-text file) :package package
                                                                :source (enough-namestring file root)
                                                                :public-packages +client-public-packages+))
     (loop for asd in (directory (merge-pathnames "*.asd" root))
           append (asd-violations (file-text asd) :source (file-namestring asd))))))

(defun file-text (path)
  (with-open-file (in path :external-format :utf-8)
    (let ((text (make-string (file-length in))))
      (subseq text 0 (read-sequence text in)))))

;;; Modules (tun-platform.md 2.3): a module reaches the kernel and other
;;; modules only through their public interfaces.  For a module that is the
;;; external symbols of the kernel's public packages and of the packages of
;;; the modules it depends on (directly or through them); never another
;;; module's internals, nor a module it does not declare.

(defparameter +kernel-public-packages+ '("TUN.CORE" "TUN.WORKFLOWS" "TUN.JOBS" "TUN.WEB" "TUN.UI" "TUN.ACCOUNTING")
  "The kernel's interface for modules.  Not TUN: that is the clients'
interface, and it re-exports what every loaded module publishes.")

(defparameter +module-library-packages+
  '(("SB-THREAD" "MAKE-MUTEX" "WITH-MUTEX" "WITH-RECURSIVE-LOCK")
    ("CL-PPCRE" "SCAN" "SCAN-TO-STRINGS" "SPLIT" "REGEX-REPLACE" "REGEX-REPLACE-ALL" "QUOTE-META-CHARS")
    ("IRONCLAD" "DIGEST-SEQUENCE" "BYTE-ARRAY-TO-HEX-STRING" "ASCII-STRING-TO-BYTE-ARRAY"))
  "Library symbols a module may use, by name: locks, regular expressions and
digests.  Nothing of SB-EXT, SB-INT, SB-KERNEL, the MOP or UIOP, whose
externals unlock packages, wrap functions or call symbols by name (review
finding 2).")

(defun module-violations (name)
  "Interface violations in every source file of the loaded module NAME."
  (let* ((module (find-module name t))
         (root (asdf:system-source-directory (format nil "tun-~a" name)))
         (own (module-packages module))
         (dependencies (remove name (module-dependency-closure (module-depends-on module)) :test #'string=))
         (public (append +kernel-public-packages+
                         (loop for d in dependencies append (module-packages (find-module d t))))))
    (append
     (loop for file in (directory (merge-pathnames "**/*.lisp" root))
           append (public-interface-violations (file-text file) :package (first own) :own-packages (rest own)
                                                                :source (enough-namestring file root)
                                                                :public-packages public
                                                                :library-packages +module-library-packages+
                                                                :module-packages
                                                                (loop for d in dependencies
                                                                      append (module-packages (find-module d t)))))
     (loop for asd in (module-asd-files name)
           append (asd-violations (file-text asd) :source (file-namestring asd))))))

(defun module-asd-files (name)
  "The .asd files of module NAME (scanned like its sources: data only)."
  (directory (merge-pathnames "*.asd" (asdf:system-source-directory (format nil "tun-~a" name)))))
