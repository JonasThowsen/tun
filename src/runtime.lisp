;;;; runtime.lisp -- assembling a deployment: application class + store
;;;; adapter + clock (+ ports), migrated and checked.

(defpackage #:tun.runtime
  (:use #:cl #:tun.core)
  (:export #:open-application #:close-application #:start-scheduler #:stop-scheduler #:main
           #:server-port #:server-trusted-proxy #:*server-application*))

(in-package #:tun.runtime)

(declaim (optimize (safety 3) (debug 2)))

(defparameter *core-packages* '()
  "Names of the kernel's packages (set in public.lisp); modules seal their own.")

;;; Core integrity.  A client may add methods to core's and the modules'
;;; generic functions; it may not redefine a core or module function or
;;; macro, nor replace or remove a method they defined.  The kernel is
;;; snapshot when it has finished loading (public.lisp), each module when it
;;; has (SEAL-MODULE); every application start compares against the snapshot
;;; and refuses to run on a mismatch (TUN.CORE:CHECK-DEFINITION-INTEGRITY).

(defun snapshot-core-definitions ()
  (seal-packages *core-packages*))

(defun core-integrity-violations () (definition-integrity-violations))

(defun check-core-integrity () (check-definition-integrity))

(defun make-store (db &key (synchronous :full) (group-commit 16))
  "The store DB names (spec/store.md): a Postgres URL, a SQLite file, or, when
DB is NIL, memory.  SYNCHRONOUS and GROUP-COMMIT apply to SQLite only."
  (cond ((null db)
         (make-instance 'tun.store.memory:memory-store))
        ((tun.store.postgres:postgres-url-p db)
         (make-instance 'tun.store.postgres:postgres-store :url db))
        (t
         (make-instance 'tun.store.sqlite:sqlite-store :path (namestring db)
                                                       :synchronous synchronous
                                                       :max-batch group-commit))))

(defun database-designator (db)
  "DB as given to --db or in DATABASE_URL: a Postgres URL as it is, a file
path made absolute against the working directory."
  (if (tun.store.postgres:postgres-url-p db)
      db
      (namestring (merge-pathnames db (uiop:getcwd)))))

(defun open-application (class &rest initargs &key db test-clock store &allow-other-keys)
  "Make an instance of the application CLASS with the store DB names (see
MAKE-STORE), migrate the store, check every record policy and query against
it, verify that every operation's methods respect the OPERATION method
combination and that every job can carry its arguments, and restore the virtual clock in test mode."
  (let* ((store (or store (make-store db)))
         (clock (if test-clock
                    (make-instance 'test-clock :now (parse-rfc3339 +test-clock-start+))
                    (make-instance 'system-clock)))
         (app (apply #'make-instance class :store store :clock clock
                     (loop for (k v) on initargs by #'cddr
                           unless (member k '(:db :test-clock :store)) append (list k v)))))
    (unless (application-accounting app)
      (setf (application-accounting app) (make-instance 'tun.accounting.fake:fake-accounting)))
    (unless (application-mail app)
      (setf (application-mail app) (tun.mail:make-mail-adapter (application-mail-spec app))))
    (unless (application-push-service app)
      (setf (application-push-service app)
            (make-instance (if test-clock 'tun.push:log-push-service 'tun.push:web-push-service))))
    (check-core-integrity)
    (check-entity-registry)
    (tun.jobs:check-job-definitions)
    (check-operation-methods)
    (check-enabled-modules app)
    (tun.web:check-http-route-conflicts)
    (store-open store)
    ;; Migrate, refusing a database a newer core major has opened
    ;; (spec/store.md 2, item 10) and a 1.x database core 2.0 cannot take
    ;; (spec/i18n.md 4.3 to 4.5), then check every record policy and query
    ;; against the migrated schema (6.6, 5.7).  A refusal closes the
    ;; connections it opened once the migrate transaction has unwound,
    ;; since that transaction holds the writer connection.  The migration
    ;; asks the application which languages it offers.
    (let ((checked nil))
      (unwind-protect
           (progn
             (let ((*application* app))
               (store-migrate store (all-entity-classes)))
             (with-application (app)
               (check-record-policies)
               (check-queries))
             (setf checked t))
        (unless checked
          (store-close store))))
    (when test-clock
      (with-application (app)
        (let ((saved (with-transaction (:read) (read-setting "test_clock.now"))))
          (when (stringp saved)
            (set-test-clock clock (parse-rfc3339 saved))))))
    ;; Each enabled module's start-up work, in dependency order (invoicing
    ;; reconciles sends whose outcome was never recorded before any retry).
    (with-application (app)
      (let ((*actor* (system-actor "reconcile")))
        (initialise-settings)
        (tun.jobs:open-job-process app)
        (tun.workflows:enqueue-planned-workflows)
        (dolist (entry (enabled-modules app))
          (dolist (function (module-on-open (first entry)))
            (funcall function)))
        ;; Then the client's (define-application ... (:on-open ...)): each in
        ;; its own write transaction, since a client cannot open one itself.
        (dolist (function (application-on-open-functions app))
          (with-transaction (:write) (funcall function)))))
    (snapshot-live-definitions app)
    (start-deadline-watchdog)
    app))

(defun close-application (app)
  (stop-application-workers app)
  (tun.jobs:close-job-process app)
  (store-close (application-store app))
  app)

;;; Rollback preflight (core.md §6.4).  Additive
;;; migrations let an older core start on a newer database, but not read
;;; everything in it.  Before a tenant is switched back to an older
;;; core, this deployment (the newer one, which knows every field and table)
;;; reads the database and compares each stored record with the older core's
;;; registry (its registry_describe, taken from it on an empty database):
;;;   - a value of an enum field outside the older core's values (statuses
;;;     such as hentet, returnert, send_faktura): it cannot decode it;
;;;   - an enum field the older core does not have, set to anything but its
;;;     default (a price mode other than automatisk): it cannot decode it,
;;;     and reprices the record as if it were the default;
;;;   - an input field of an embedded record (an order line) the older core
;;;     does not have, set to anything but its default (a line's price mode,
;;;     discount, manual total, reason, note): its next write of the parent
;;;     drops it.
;;;   - a record of an entity the older core does not have, when the module
;;;     that owns it says the older core cannot take it (the entity's
;;;     ROLLBACK-CHECK: slice 2's articles, plans, reviews, tasks, transfers,
;;;     recipes and choice groups, each with its own reason).
;;; Not counted: other top-level fields the older core does not have (tags,
;;; department, end_date, logistics, notes): its writes name their columns,
;;; so they stay, invisible to it; tables of other entities it does not
;;; have, which it never reads; derived fields (input nil), which the newer
;;; core recomputes.  Nothing is written.

(defun registry-entities (registry)
  "json-name -> (field-name -> field object) of REGISTRY (registry_describe)."
  (let ((entities (make-hash-table :test 'equal)))
    (loop for entity across (jget registry "entities")
          do (let ((fields (make-hash-table :test 'equal)))
               (loop for field across (jget entity "fields")
                     unless (eq t (jget field "computed"))
                       do (setf (gethash (jget field "name") fields) field))
               (setf (gethash (jget entity "name") entities) fields)))
    entities))

(defun field-default-p (field value)
  "True when VALUE is what FIELD holds before anyone sets it."
  (let* ((initfunction (closer-mop:slot-definition-initfunction field))
         (default (and initfunction (funcall initfunction)))
         (type (field-type field)))
    (or (null value)
        (and (listp value) (null value))
        (and (vectorp value) (not (stringp value)) (zerop (length value)))
        (equal (type->db type value) (type->db type default)))))

(defun preflight-record (record class target entities findings path &optional embedded)
  "Note in FINDINGS (kind -> count) every way RECORD (of CLASS; EMBEDDED in a
parent's column) is outside TARGET (the older core's fields of that entity)."
  (dolist (field (entity-stored-fields class))
    (let* ((name (field-json-name field))
           (value (field-value record field))
           (type (field-type field))
           (known (gethash name target))
           (where (format nil "~a.~a" path name)))
      (cond ((null known)
             (when (and (field-input-p field) (or embedded (typep type 'enum-type))
                        (not (field-default-p field value)))
               (incf (gethash (format nil "~a set (~a): the older core has no such field~:[~;; its next write drops it~]"
                                      where (if (typep type 'enum-type) value "a value") embedded)
                              findings 0))))
            ((and (typep type 'enum-type) (stringp value) (jget known "values")
                  (not (find value (jget known "values") :test #'equal)))
             (incf (gethash (format nil "~a = ~a: not a value the older core knows" where value) findings 0)))
            ((and (typep type 'list-type) (symbolp (list-element type)) (jget known "items"))
             (let ((items (gethash (jget known "items") entities))
                   (item-class (find-entity-class (list-element type))))
               (when items
                 (dolist (item value)
                   (preflight-record item item-class items entities findings (format nil "~a[]" where) t)))))))))

(defun argv-database (argv)
  "The database the server's ARGV names: --db, else DATABASE_URL."
  (or (argument argv "--db") (uiop:getenv "DATABASE_URL")))

(defun core-2-marked-p (db)
  "True when the database DB names has core 2.0's mark (spec/i18n.md 4.6)."
  (let ((store (make-store (database-designator db))))
    (store-open store)
    (unwind-protect
         (let ((mark (nth-value 1 (core-major-mark 2))))
           (some (lambda (migration)
                   (and (equal (jget migration "module") +core-major-module+)
                        (equal (jget migration "id") mark)))
                 (coerce (nth-value 1 (store-describe-schema store)) 'list)))
      (store-close store))))

(defun revert-to-core-1 (db name)
  "Undo core 2.0's migration of the database DB names (spec/i18n.md 4.6),
saying on standard output or standard error what happened: the exit code,
0 when it is undone, 2 when it is refused."
  (unless db
    (format *error-output* "~a: --db PATH|URL or DATABASE_URL is required~%" name)
    (return-from revert-to-core-1 2))
  (let ((store (make-store (database-designator db))))
    (store-open store)
    (unwind-protect
         (handler-case
             (progn (store-revert-to-core-1 store)
                    (format t "~&~a: reverted to core 1: core 1.23.1 can open this database~%" name)
                    (finish-output)
                    0)
           ((or newer-database database-refused) (refusal)
             (format *error-output* "~&~a: ~a~%" name refusal)
             (finish-output *error-output*)
             2))
      (store-close store))))

(defun preflight-command (application-class db registry-path name)
  "--rollback-preflight REGISTRY-PATH on the database DB names, saying what it
found: the exit code, 0 when the older core can take the database, 3 when
not, 2 without a database.  While core 2.0's mark is in the database it
refuses before reading REGISTRY-PATH (spec/i18n.md 4.6)."
  (cond ((null db)
         (format *error-output* "~&~a: --rollback-preflight needs --db PATH|URL or DATABASE_URL~%"
                 name)
         (finish-output *error-output*)
         2)
        ((core-2-marked-p db)
         (format t "~&rollback preflight: REFUSED, core 2.0 has migrated this database; ~
                    run the server with --revert-to-core-1 first (spec/i18n.md 4.6)~%")
         (finish-output)
         3)
        (t
         (let ((findings (rollback-preflight application-class db registry-path)))
           (if findings
               (format t "~&rollback preflight: REFUSED, ~d record~:p or value~:p outside the older core's vocabulary:~%~:{  ~a: ~d~%~}"
                       (reduce #'+ findings :key #'cdr)
                       (mapcar (lambda (f) (list (car f) (cdr f))) findings))
               (format t "~&rollback preflight: ok, every stored record is inside the older core's vocabulary~%"))
           (finish-output)
           (if findings 3 0)))))

(defun open-for-serving (application-class name &rest initargs)
  "OPEN-APPLICATION of APPLICATION-CLASS with INITARGS, or NIL when the
database is refused, after saying why on standard error: one a newer core
major has opened (spec/store.md 2, item 10), or one core 2.0 cannot take
(spec/i18n.md 4.3 to 4.5).  The server then exits 2, as the other start
checks do."
  (handler-case (apply #'open-application application-class initargs)
    ((or newer-database database-refused) (refusal)
      (format *error-output* "~&~a: ~a~%" name refusal)
      (finish-output *error-output*)
      nil)))

(defun rollback-preflight (application-class db registry-path)
  "Findings (a list of (kind . count), sorted) for rolling the database DB
back to the core whose registry_describe is in REGISTRY-PATH; NIL when every
stored record is inside its vocabulary.  Opens DB read-only in effect: no
migration, one read transaction."
  (let* ((registry (with-open-file (in registry-path :external-format :utf-8)
                     (let ((text (make-string (file-length in))))
                       (parse-json (subseq text 0 (read-sequence text in))))))
         (entities (registry-entities registry))
         (store (make-store db))
         (app (make-instance application-class :store store :clock (make-instance 'system-clock)))
         (findings (make-hash-table :test 'equal)))
    (store-open store)
    (unwind-protect
         (with-application (app)
           (with-transaction (:read)
             ;; The preflight reads SQLite, which never holds records of an
             ;; entity with a record policy (spec/store.md 6.7).
             (dolist (class (remove-if #'entity-record-policy (all-entity-classes)))
               (let ((target (gethash (entity-json-name class) entities)))
                 (cond ((entity-embedded-p class))
                       (target
                        (dolist (record (select (class-name class)))
                          (preflight-record record class target entities findings (entity-json-name class))))
                       ((entity-rollback-check class)
                        (dolist (record (select (class-name class)))
                          (let ((finding (funcall (entity-rollback-check class) record)))
                            (when finding
                              (incf (gethash (format nil "~a: ~a" (entity-json-name class) finding)
                                             findings 0)))))))
                 (let ((checks (loop for (check . older-lacks) in (entity-record-rollback-checks class)
                                     unless (and older-lacks
                                                 (gethash (entity-json-name (find-class older-lacks)) entities))
                                       collect check)))
                   (when (and checks (not (entity-embedded-p class)))
                     (dolist (record (select (class-name class)))
                       (dolist (check checks)
                         (let ((finding (funcall check record)))
                           (when finding
                             (incf (gethash (format nil "~a: ~a" (entity-json-name class) finding)
                                            findings 0))))))))))))
      (store-close store))
    (sort (loop for kind being the hash-keys of findings using (hash-value count) collect (cons kind count))
          #'string< :key #'car)))

;;; Normal mode: a scheduler thread tends the jobs every tick: heartbeat,
;;; recovery, schedules, and a worker per queue with due jobs, workflows and
;;; mail delivery among them.  (In test mode clock_set runs the due jobs
;;; synchronously instead.)

(defvar *scheduler* nil)

(defun start-scheduler (app &key (interval 1))
  (tun.jobs:start-waking app)
  (setf *scheduler*
        (sb-thread:make-thread
         (lambda ()
           (loop
             (handler-case
                 (with-application (app)
                   (let ((*actor* (system-actor "scheduler")))
                     (tun.jobs:tend-jobs app)
                     (application-after-request app)))
               (serious-condition (e) (ignore-errors (format *error-output* "~&;; tun scheduler: ~a~%" e))))
             (sleep interval)))
         :name "tun workflow scheduler")))

(defun stop-scheduler ()
  (when (and *scheduler* (sb-thread:thread-alive-p *scheduler*))
    (sb-thread:terminate-thread *scheduler*))
  (setf *scheduler* nil))

;;; Command-line entry point, shared by bin/serve (working tree) and the
;;; launcher that lib.buildClient in flake.nix builds (Nix store only).

(defun argument (argv name &optional default)
  (let ((tail (member name argv :test #'string=)))
    (if (and tail (second tail)) (second tail) default)))

(defun server-port (argv)
  "The port --port in ARGV names, else the PORT environment variable, else
8080 (spec/deploy.md 1). NIL when that is not a port number."
  (let* ((text (or (argument argv "--port") (uiop:getenv "PORT") "8080"))
         (port (handler-case (parse-integer text)
                 (parse-error () nil))))
    (and port (<= 1 port 65535) port)))

(defun public-url-p (text)
  "True when TEXT is an http or https URL with a host and no path, query or
fragment beyond a lone trailing slash."
  (let ((rest (cond ((string-prefix-p "https://" text) (subseq text 8))
                    ((string-prefix-p "http://" text) (subseq text 7)))))
    (and rest
         (plusp (length (string-right-trim "/" rest)))
         (not (find-if (lambda (c) (find c "/?#@ ")) (string-right-trim "/" rest))))))

(defun server-public-url (argv)
  "The public URL --public-url in ARGV names, else the PUBLIC_URL environment
variable, without a trailing slash (spec/deploy.md 1).  Values NIL when
neither is given, and NIL and T when the one given is not a URL."
  (let ((text (or (argument argv "--public-url") (uiop:getenv "PUBLIC_URL"))))
    (cond ((zerop (length text)) nil)
          ((public-url-p text) (string-right-trim "/" text))
          (t (values nil t)))))

(defun server-trusted-proxy (argv)
  "The trusted proxy's address --trusted-proxy in ARGV names, else the
TRUSTED_PROXY environment variable (spec/deploy.md 1).  Values NIL when
neither is given, and NIL and T when the one given is not an IP address."
  (let ((text (or (argument argv "--trusted-proxy") (uiop:getenv "TRUSTED_PROXY"))))
    (cond ((zerop (length text)) nil)
          ((tun.http:parse-ip-address text) (string-trim " " text))
          (t (values nil t)))))

(defun check-mail (application-class claimed name)
  "Say what keeps the mail provider APPLICATION-CLASS names from working
(spec/mail.md 1).  An authenticated server cannot start without it (exit
2); a claimed one logs mail instead of sending it."
  (let ((problems (tun.mail:mail-problems application-class)))
    (dolist (problem problems)
      (format *error-output* "~&~a: mail: ~a~%" name problem))
    (when problems
      (if claimed
          (format *error-output* "~&~a: logging mail instead of sending it (claimed identity)~%"
                  name)
          (sb-ext:exit :code 2)))
    (finish-output *error-output*)))

(defun check-sign-in (application-class claimed name)
  "Say what keeps the sign-in strategies APPLICATION-CLASS lists from working
(spec/auth.md 3.5).  An authenticated server cannot start without them
(exit 2); a claimed one starts without those strategies."
  (let ((problems (tun.auth:sign-in-problems application-class)))
    (dolist (problem problems)
      (format *error-output* "~&~a: sign-in: ~a~%" name problem))
    (when problems
      (if claimed
          (format *error-output* "~&~a: starting without those sign-in strategies ~
                                  (claimed identity)~%" name)
          (sb-ext:exit :code 2)))
    (finish-output *error-output*)))

(defun check-programs (application-class name &key (exit (lambda (code) (sb-ext:exit :code code))))
  "Refuse to start (EXIT with code 2) when a program APPLICATION-CLASS
declares with (:programs ...) is not on PATH, naming each one missing
(spec/outbound.md 6).  Only a server looks: tests and OPEN-APPLICATION do not."
  (let ((missing (tun.outbound:missing-programs application-class)))
    (dolist (program missing)
      (format *error-output* "~&~a: the program ~a is not on PATH~%" name program))
    (finish-output *error-output*)
    (when missing
      (funcall exit 2))))

(defun thread-guard-hook (condition hook)
  "Debugger hook for servers: an unhandled condition in a worker thread ends
that thread only (unwinding its cleanups); only the main thread exits."
  (declare (ignore hook))
  (ignore-errors
   (format *error-output* "~&;; tun: unhandled ~a in thread ~a: ~a~%" (type-of condition)
           (sb-thread:thread-name sb-thread:*current-thread*) condition)
   (finish-output *error-output*))
  (if (eq sb-thread:*current-thread* (sb-thread:main-thread))
      (sb-ext:exit :code 70 :abort t)
      (sb-thread:abort-thread)))

(defun install-thread-guard ()
  "--non-interactive makes any unhandled condition in any thread quit the
process; a server must survive one bad request or workflow."
  (setf sb-ext:*invoke-debugger-hook* #'thread-guard-hook))

(defvar *server-application* nil
  "The application this process serves (set by MAIN): what REPL code binds
with TUN.CORE:WITH-APPLICATION, since REPL threads run outside any request.")

(defun start-repl (port)
  "Start Swank (the SLIME protocol) on 127.0.0.1:PORT: the native REPL of the
running image (core.md §8.2).  Debug-only; unlike eval it is not read-only."
  (let ((create-server (find-symbol "CREATE-SERVER" "SWANK")))
    (unless create-server
      (format *error-output* "~&;; tun: Swank is not loaded; no REPL~%")
      (return-from start-repl nil))
    (funcall create-server :port port :interface "127.0.0.1" :dont-close t :style :spawn)))

(defun start-listening (app &key port address max-inflight trusted-proxy (name "tun")
                                (exit (lambda (code) (sb-ext:exit :code code))))
  "Bind PORT on ADDRESS and serve APP; the acceptor.  When the socket cannot
be bound, say so on standard error and EXIT with code 1 (core.md §7.7):
the caller logs \"listening\" only after this returns."
  (handler-case (tun.http:start-server app :port port :address address :max-inflight max-inflight
                                           :trusted-proxy trusted-proxy)
    (error (e)
      (format *error-output* "~&~a: cannot listen on ~a:~d: ~a~%" name address port e)
      (finish-output *error-output*)
      (funcall exit 1))))

(defun main (application-class &key (argv sb-ext:*posix-argv*) (name "tun") before-serving)
  "Serve APPLICATION-CLASS.  Flags: [--port N] --db PATH|URL [--test-clock]
[--address A] [--deadline-ms N] [--max-inflight N] [--tick-ms N]
[--debug-tools] [--fake-accounting-latency-ms N] [--sqlite-synchronous full|normal]
[--group-commit N] [--gc-nursery-mb N] [--allow-eval] [--repl-port N]
[--request-history N] [--claimed-identity] [--public-url URL] [--trusted-proxy ADDRESS]
[--log json|none].
--log json, the default, writes a JSON line per request to standard output
(spec/errors.md 6).  The fake accounting adapter's latency defaults to
FAKE_ACCOUNTING_LATENCY_MS from the environment (0 when unset).  Runs until
terminated.  Without --db, the DATABASE_URL environment variable names the
database (spec/store.md); without --port, PORT names the port, else 8080.
--claimed-identity takes the actor a request claims (spec/auth.md 1), for
tests, previews and local development only.  Without --public-url,
PUBLIC_URL names where people reach the server, and without
--trusted-proxy, TRUSTED_PROXY the proxy whose X-Forwarded-For names the
client (spec/deploy.md 1).
BEFORE-SERVING, when given, is called with the open application before the
server listens, so what it does is done before /health answers: a preview
makes its scenario's records there (spec/preview.md 3)."
  (setf *read-eval* nil)
  (install-thread-guard)
  ;; --revert-to-core-1 [--db PATH]: undo core 2.0's migration, with no
  ;; server on the database, and exit (spec/i18n.md 4.6).
  (when (member "--revert-to-core-1" argv :test #'string=)
    (sb-ext:exit :code (revert-to-core-1 (argv-database argv) name)))
  ;; --rollback-preflight REGISTRY [--db PATH]: check, print, exit (0 when
  ;; the older core can take the database, 3 when not).  While core 2.0's
  ;; mark is in the database, it refuses before reading REGISTRY.
  (let ((registry (argument argv "--rollback-preflight")))
    (when registry
      (sb-ext:exit :code (preflight-command application-class (argv-database argv) registry name))))
  (flet ((flag (option) (and (member option argv :test #'string=) t))
         (number (option default) (parse-integer (argument argv option (princ-to-string default)))))
    (let ((port (or (server-port argv)
                    (progn (format *error-output* "~a: --port or PORT is not a port number~%" name)
                           (sb-ext:exit :code 2))))
          (db (argv-database argv))
          (test-clock (flag "--test-clock"))
          (address (argument argv "--address" "127.0.0.1"))
          (max-inflight (number "--max-inflight" 64))
          (tick-ms (number "--tick-ms" 1000))
          (repl-port (let ((value (argument argv "--repl-port"))) (and value (parse-integer value))))
          (latency-ms (let ((value (argument argv "--fake-accounting-latency-ms")))
                        (and value (parse-integer value))))
          (synchronous (let ((value (argument argv "--sqlite-synchronous" "full")))
                         (cond ((string-equal value "full") :full)
                               ((string-equal value "normal") :normal)
                               (t (format *error-output* "~a: --sqlite-synchronous is full or normal~%" name)
                                  (sb-ext:exit :code 2)))))
          (group-commit (max 1 (number "--group-commit" 16)))
          (nursery-mb (argument argv "--gc-nursery-mb"))
          (history (max 1000 (number "--request-history" 1000)))
          (log (let ((value (argument argv "--log" "json")))
                 (cond ((string-equal value "json") t)
                       ((string-equal value "none") nil)
                       (t (format *error-output* "~a: --log is json or none~%" name)
                          (sb-ext:exit :code 2)))))
          (public-url (multiple-value-bind (url invalid) (server-public-url argv)
                        (when invalid
                          (format *error-output* "~a: --public-url or PUBLIC_URL is not an ~
                                                  http or https URL~%" name)
                          (sb-ext:exit :code 2))
                        url))
          (trusted-proxy (multiple-value-bind (proxy invalid) (server-trusted-proxy argv)
                           (when invalid
                             (format *error-output* "~a: --trusted-proxy or TRUSTED_PROXY is not ~
                                                     an IP address~%" name)
                             (sb-ext:exit :code 2))
                           proxy)))
      (setf *deadline-ms* (number "--deadline-ms" 10000)
            *request-history-size* history)
      (when nursery-mb
        (setf (sb-ext:bytes-consed-between-gcs) (* (parse-integer nursery-mb) 1024 1024)))
      (unless db
        (format *error-output* "~a: --db PATH|URL or DATABASE_URL is required~%" name)
        (sb-ext:exit :code 2))
      (when (and repl-port (not (flag "--debug-tools")))
        (format *error-output* "~a: --repl-port is debug-only: add --debug-tools~%" name)
        (sb-ext:exit :code 2))
      (check-programs application-class name)
      (check-sign-in application-class (flag "--claimed-identity") name)
      (check-mail application-class (flag "--claimed-identity") name)
      (tun.errors:check-error-mail application-class name)
      (let* ((app (or (open-for-serving application-class name
                                        :store (make-store (database-designator db)
                                                           :synchronous synchronous
                                                           :group-commit group-commit)
                                        :test-clock test-clock
                                        :debug-tools (flag "--debug-tools")
                                        :allow-eval (flag "--allow-eval")
                                        :repl-port repl-port
                                        :public-url public-url
                                        :log-requests log
                                        :identity (if (flag "--claimed-identity") :claimed :authenticated))
                      (sb-ext:exit :code 2)))
             (acceptor (progn
                         (when before-serving
                           (funcall before-serving app))
                         (when latency-ms
                           (setf (tun.accounting.fake:fake-latency-ms (application-accounting app)) latency-ms))
                         (start-listening app :port port :address address :max-inflight max-inflight
                                              :trusted-proxy trusted-proxy :name name))))
        (unless test-clock (start-scheduler app :interval (/ tick-ms 1000.0)))
        (setf *server-application* app)
        (when repl-port (start-repl repl-port))
      (push (lambda ()
              (ignore-errors (tun.http:stop-server acceptor))
              (ignore-errors (close-application app)))
            sb-ext:*exit-hooks*)
        (format t "~&tun: ~a listening on http://~a:~d/mcp (~a~:[~;, test clock~]; ~
                   deadline ~d ms, max in-flight ~d~:[~;, debug tools~]~
                   ~:[~2*~;; sqlite synchronous ~(~a~), group commit ~d~]; ~
                   gc nursery ~d MB~:[~;; eval~]~@[; REPL (Swank) on 127.0.0.1:~d~]~
                   ~@[; trusted proxy ~a~]~
                   ~:[~;; CLAIMED IDENTITY: requests choose their own actor~])~%"
                name address port (store-description (application-store app)) test-clock
                *deadline-ms* max-inflight (application-debug-tools-p app)
                (typep (application-store app) 'tun.store.sqlite:sqlite-store)
                synchronous group-commit
                (floor (sb-ext:bytes-consed-between-gcs) (* 1024 1024))
                (application-allow-eval-p app) repl-port trusted-proxy (claimed-identity-p app))
        (unless (claimed-identity-p app)
          (tun.auth:announce-setup app))
        (finish-output)
        (handler-case (loop (sleep 3600))
          (sb-sys:interactive-interrupt () (sb-ext:exit :code 0)))))))
