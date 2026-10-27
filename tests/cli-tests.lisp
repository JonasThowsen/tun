;;;; tests/cli-tests.lisp -- the tun command (spec/cli.md): the module
;;;; catalog, client names, the files of a new client, the edits of tun add,
;;;; the inputs and head tun update reads, and exit statuses; and the
;;;; server's port as a deployed client gets it (spec/deploy.md). bin/test-cli
;;;; runs the whole path with Nix.

(in-package #:tun.tests)

(def-suite cli :in core)
(in-suite cli)

(defun catalog-modules ()
  (coerce (jget (tun.cli:module-catalog) "modules") 'list))

(defun catalog-module (name)
  (find name (catalog-modules) :key (lambda (module) (jget module "name")) :test #'string=))

(defun new-client-text (path &key (modules '("orders")) (tun-url "git+ssh://git@example.com/tun"))
  "The text of PATH in a new client acme that enables MODULES."
  (second (find path (tun.cli:client-files "acme" modules tun-url) :key #'first :test #'string=)))

(defun cli-scratch-directory ()
  "A directory path under .build/ that does not exist yet."
  (merge-pathnames (format nil ".build/test-cli/~a/" (new-id "t"))
                   (asdf:system-source-directory "tun")))

(test the-catalog-describes-every-loaded-module
  (let ((modules (catalog-modules)))
    (is (equal (sort (mapcar #'module-name (all-modules)) #'string<)
               (mapcar (lambda (module) (jget module "name")) modules)))
    (is (every (lambda (module)
                 (equal (jget module "system") (format nil "tun-~a" (jget module "name"))))
               modules)))
  (let ((orders (catalog-module "orders")))
    (is (equal '("customers" "catalog" "inventory" "reviews")
               (coerce (jget orders "depends_on") 'list)))
    (is (find "orders_create" (jget orders "operations") :test #'equal))
    (is (notany (lambda (operation) (search "customers_" operation)) (jget orders "operations")))
    (is (find "order" (jget orders "entities")
              :key (lambda (entity) (jget entity "name")) :test #'equal)))
  (is (find "customer_list" (jget (catalog-module "customers") "screens") :test #'equal)))

(test modules-resolve-with-their-dependencies
  (is (equal '("catalog" "inventory") (tun.cli:resolve-modules '("inventory"))))
  (signals tun.cli:usage-error (tun.cli:resolve-modules '("inventory" "no_such_module"))))

(test a-client-name-is-lowercase-and-not-one-of-tuns-own
  (dolist (name '("acme" "fjord-service" "tunfisk" "a1"))
    (is (equal name (tun.cli:check-client-name name))))
  (dolist (name (list "" "Acme" "1acme" "acme_x" "a b" "tun" "tun-x"
                      (make-string 41 :initial-element #\a)))
    (signals tun.cli:usage-error (tun.cli:check-client-name name))))

(test a-new-client-pins-every-module-it-needs-in-one-repository
  (is (equal '(("tun" "git+ssh://git@example.com/tun?ref=main")
               ("catalog" "git+ssh://git@example.com/tun?ref=main&dir=modules/catalog")
               ("customers" "git+ssh://git@example.com/tun?ref=main&dir=modules/customers")
               ("inventory" "git+ssh://git@example.com/tun?ref=main&dir=modules/inventory")
               ("orders" "git+ssh://git@example.com/tun?ref=main&dir=modules/orders")
               ("reviews" "git+ssh://git@example.com/tun?ref=main&dir=modules/reviews"))
             (let ((inputs (tun.cli:flake-inputs (new-client-text "flake.nix"))))
               (cons (first inputs) (sort (rest inputs) #'string< :key #'first)))))
  ;; Only the module named is the client's choice; the rest come with it.
  (is (search ":depends-on (\"tun\" \"tun-orders\")" (new-client-text "acme.asd")))
  (is (search "(:modules orders)" (new-client-text "application.lisp"))))

(test a-new-client-has-every-file-filled-in
  (let ((files (tun.cli:client-files "acme" '() "git+file:///srv/tun")))
    (is (equal '(".envrc" ".gitignore" "AGENTS.md" "README.md" "acme.asd" "application.lisp"
                 "bin/serve" "bin/test" "deploy.nix" "flake.nix" "package.lisp"
                 "tests/package.lisp" "tests/run.lisp" "tests/scenarios.lisp" "tests/tests.lisp")
               (sort (mapcar #'first files) #'string<)))
    (is (notany (lambda (file) (search "{{" (second file))) files))
    (is (equal '("bin/serve" "bin/test")
               (sort (mapcar #'first (remove-if-not #'third files)) #'string<))))
  ;; Without modules the client runs on the kernel alone.
  (is (equal '(("tun" "git+file:///srv/tun?ref=main"))
             (tun.cli:flake-inputs (new-client-text "flake.nix" :modules '()
                                                                :tun-url "git+file:///srv/tun"))))
  (is (search "(:modules)" (new-client-text "application.lisp" :modules '())))
  (is (search ":depends-on (\"tun\")" (new-client-text "acme.asd" :modules '()))))

(test tun-add-edits-each-place-once
  (let ((flake (tun.cli:add-flake-inputs
                (new-client-text "flake.nix" :modules '("customers") :tun-url "git+file:///t")
                '(("catalog" "git+file:///t?ref=main&dir=modules/catalog")))))
    (is (equal '("tun" "customers" "catalog") (mapcar #'first (tun.cli:flake-inputs flake))))
    (is (search (format nil "~%  inputs.catalog.url = ~s;~%"
                        "git+file:///t?ref=main&dir=modules/catalog")
                flake)))
  (let ((asd (tun.cli:add-asd-dependencies (new-client-text "acme.asd" :modules '("customers"))
                                           '("tun-catalog" "tun-customers"))))
    (is (search ":depends-on (\"tun\" \"tun-customers\" \"tun-catalog\")" asd))
    (is (equal asd (tun.cli:add-asd-dependencies asd '("tun-catalog")))))
  (let ((application (tun.cli:add-application-modules
                      (new-client-text "application.lisp" :modules '("customers"))
                      '("catalog" "customers"))))
    (is (search "(:modules customers catalog)" application))
    (is (equal application (tun.cli:add-application-modules application '("catalog")))))
  ;; A place that is not there is NIL, so tun add changes nothing.
  (is (null (tun.cli:add-flake-inputs "{ outputs = { self }: { }; }" '(("a" "b")))))
  (is (null (tun.cli:add-asd-dependencies "(defsystem \"x\" :depends-on (\"fiveam\"))" '("tun-a"))))
  (is (null (tun.cli:add-application-modules "(defclass x () ())" '("catalog")))))

(test module-inputs-share-the-kernels-repository-and-ref
  (is (equal "git+ssh://h/tun?ref=main&dir=modules/orders"
             (tun.cli:module-input-url "git+ssh://h/tun?ref=main" "orders")))
  (is (equal "git+file:///t?dir=modules/orders"
             (tun.cli:module-input-url "git+file:///t" "orders"))))

(test tun-update-moves-the-kernel-and-every-module-and-nothing-else
  (let ((flake (tun.cli:add-flake-inputs
                (new-client-text "flake.nix" :modules '("customers" "reviews"))
                '(("other" "github:example/other")
                  ("fork" "git+ssh://git@example.com/fork?ref=main&dir=modules/catalog")))))
    (is (equal '("tun" "customers" "reviews")
               (mapcar #'first (tun.cli:tun-inputs (tun.cli:flake-inputs flake))))))
  (is (null (tun.cli:tun-inputs '(("nixpkgs" "github:NixOS/nixpkgs"))))))

(test tun-update-reads-the-head-of-the-tun-inputs-ref
  (flet ((location (url)
           (multiple-value-list (tun.cli:git-head-location url))))
    (is (equal '("ssh://git@github.com/JonasThowsen/tun" "refs/heads/main")
               (location "git+ssh://git@github.com/JonasThowsen/tun?ref=main")))
    (is (equal '("https://example.com/tun" "refs/tags/v1")
               (location "git+https://example.com/tun?dir=modules/a&ref=refs/tags/v1")))
    (is (equal '("file:///srv/tun" "HEAD") (location "git+file:///srv/tun")))
    (is (equal '(nil) (location "github:JonasThowsen/tun")))))

(defun write-file-text (file text)
  (with-open-file (out file :direction :output :if-exists :supersede :external-format :utf-8)
    (write-string text out)))

(defun flake-lock-text (pins)
  "The text of a flake.lock that pins each (input revision) of PINS."
  (let ((root (apply #'jobj (loop for (name) in pins
                                  append (list name name))))
        (nodes (loop for (name revision) in pins
                     append (list name (jobj "locked" (jobj "rev" revision))))))
    (to-json-string
     (jobj "nodes" (apply #'jobj "root" (jobj "inputs" root) nodes)
           "root" "root"
           "version" 7))))

(defun write-update-fixture (directory pins)
  "A client in DIRECTORY whose flake's Tun inputs, tun and customers, are in
a repository that does not exist, and whose flake.lock pins each (input
revision) of PINS. Returns the text of the flake.lock."
  (let ((tun "git+file:///nonexistent/tun?ref=main")
        (lock (flake-lock-text pins)))
    (write-file-text (merge-pathnames "flake.nix" directory)
                     (format nil "{~%  inputs.tun.url = ~s;~%  inputs.customers.url = ~s;~%  ~
                                  inputs.nixploy.url = \"github:JonasThowsen/nixploy\";~%  ~
                                  outputs = _: { };~%}~%"
                             tun (tun.cli:module-input-url tun "customers")))
    (write-file-text (merge-pathnames "flake.lock" directory) lock)
    lock))

(test tun-update-changes-nothing-unless-it-locks-every-tun-input
  (let* ((directory (cli-scratch-directory))
         (lock-file (merge-pathnames "flake.lock" directory))
         (new (make-string 40 :initial-element #\a))
         (old (make-string 40 :initial-element #\b)))
    (unwind-protect
         (progn
           (ensure-directories-exist directory)
           (signals tun.cli:step-failed (tun.cli:update-client :directory (namestring directory)
                                                               :revision new))
           (let ((lock (write-update-fixture directory `(("tun" ,new) ("customers" ,new)
                                                         ("nixploy" ,old)))))
             ;; Every Tun input is there already; nixploy is not Tun's.
             (is (equal (list new nil)
                        (multiple-value-list
                         (tun.cli:update-client :directory (namestring directory)
                                                :revision new))))
             (signals tun.cli:usage-error (tun.cli:update-client
                                           :directory (namestring directory) :revision "main"))
             (is (equal lock (uiop:read-file-string lock-file))))
           ;; customers is behind, so tun update locks, and locking fails
           ;; because nix cannot be found: flake.lock is as it was.
           (let ((lock (write-update-fixture directory `(("tun" ,new) ("customers" ,old))))
                 (path (uiop:getenv "PATH")))
             (unwind-protect
                  (progn
                    (sb-posix:setenv "PATH" "" 1)
                    (signals tun.cli:step-failed (tun.cli:update-client
                                                  :directory (namestring directory)
                                                  :revision new)))
               (sb-posix:setenv "PATH" path 1))
             (is (equal lock (uiop:read-file-string lock-file)))))
      (uiop:delete-directory-tree directory :validate t :if-does-not-exist :ignore))))

(test the-server-port-is-the-flag-else-port-else-8080
  (let ((saved (uiop:getenv "PORT")))
    (unwind-protect
         (progn
           (sb-posix:unsetenv "PORT")
           (is (= 8080 (tun.runtime:server-port '())))
           (is (= 9001 (tun.runtime:server-port '("--port" "9001"))))
           (sb-posix:setenv "PORT" "4100" 1)
           (is (= 4100 (tun.runtime:server-port '())))
           (is (= 9001 (tun.runtime:server-port '("--port" "9001"))))
           (dolist (port '("" "80x" "0" "-1" "65536"))
             (sb-posix:setenv "PORT" port 1)
             (is (null (tun.runtime:server-port '())))))
      (if saved
          (sb-posix:setenv "PORT" saved 1)
          (sb-posix:unsetenv "PORT")))))

(test the-trusted-proxy-is-the-flag-else-trusted-proxy-and-an-ip-address
  (let ((saved (uiop:getenv "TRUSTED_PROXY")))
    (unwind-protect
         (progn
           (sb-posix:unsetenv "TRUSTED_PROXY")
           (is (equal '(nil) (multiple-value-list (tun.runtime:server-trusted-proxy '())))
               "none: every peer is a client")
           (is (equal "127.0.0.1" (tun.runtime:server-trusted-proxy
                                   '("--trusted-proxy" "127.0.0.1"))))
           (sb-posix:setenv "TRUSTED_PROXY" "::1" 1)
           (is (equal "::1" (tun.runtime:server-trusted-proxy '())))
           (is (equal "10.0.0.5" (tun.runtime:server-trusted-proxy
                                  '("--trusted-proxy" "10.0.0.5"))))
           (dolist (value '("localhost" "127.0.0" "caddy:80" "1.2.3.4/32"))
             (sb-posix:setenv "TRUSTED_PROXY" value 1)
             (is (equal '(nil t) (multiple-value-list (tun.runtime:server-trusted-proxy '())))
                 "~s is refused" value)))
      (if saved
          (sb-posix:setenv "TRUSTED_PROXY" saved 1)
          (sb-posix:unsetenv "TRUSTED_PROXY")))))

(test tun-new-refuses-before-writing-anything
  (let ((directory (cli-scratch-directory)))
    (signals tun.cli:usage-error (tun.cli:create-client "acme" '("no_such_module")
                                                       :directory (namestring directory)))
    (signals tun.cli:usage-error (tun.cli:create-client "acme" '() :directory (namestring directory)
                                                                   :tun-url "not a url"))
    (signals tun.cli:usage-error (tun.cli:create-client "acme" '() :directory (namestring directory)
                                                                   :revision "main"))
    (is (null (probe-file directory)))
    (let ((kept (merge-pathnames "kept.txt" directory)))
      (ensure-directories-exist kept)
      (with-open-file (out kept :direction :output) (write-line "mine" out))
      (signals tun.cli:usage-error (tun.cli:create-client "acme" '()
                                                          :directory (namestring directory)))
      (is (equal (list (truename kept)) (directory (merge-pathnames "*.*" directory))))
      (uiop:delete-directory-tree directory :validate t))))

(test the-command-line-exits-with-the-status-spec-cli-1-gives
  (flet ((status (&rest arguments)
           (let ((*standard-output* (make-broadcast-stream))
                 (*error-output* (make-broadcast-stream)))
             (tun.cli:run arguments))))
    (is (= 0 (status "help")))
    (is (= 0 (status "list" "orders")))
    (is (= 2 (status "frobnicate")))
    (is (= 2 (status "list" "--bogus")))
    (is (= 2 (status "list" "no_such_module")))
    (is (= 2 (status "new")))
    (is (= 2 (status "new" "acme" "--dir")))
    (is (= 2 (status "add")))
    (is (= 2 (status "update" "customers")))
    (is (= 2 (status "update" "--rev" "main"))))
  (let ((catalog (parse-json (with-output-to-string (*standard-output*)
                               (tun.cli:run '("list" "--json"))))))
    (is (equal +core-version+ (jget catalog "core_version")))
    (is (= (length (all-modules)) (length (jget catalog "modules"))))))
