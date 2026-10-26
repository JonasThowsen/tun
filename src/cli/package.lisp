;;;; cli/package.lisp -- the tun command (spec/cli.md): list the modules of
;;;; this Tun revision, create a client repository from them, add a module
;;;; to a client later, move a client to a newer Tun, preview a client's
;;;; working tree (spec/preview.md), and run the feature loop (spec/loop.md).

(defpackage #:tun.cli
  (:use #:cl)
  (:import-from #:tun.core
                #:+core-version+ #:all-modules #:find-module #:module-name #:module-description
                #:module-depends-on #:module-core-range #:module-dependency-closure
                #:application #:describe-registry #:jobj #:jarr #:jget #:to-json-string
                #:parse-json)
  (:export #:main #:run #:usage-error #:step-failed
           #:module-catalog #:resolve-modules
           #:check-client-name #:client-files #:create-client #:add-modules
           #:fill-template #:flake-inputs #:add-flake-inputs #:add-asd-dependencies
           #:add-application-modules #:module-input-url
           #:update-client #:tun-inputs #:git-head-location
           #:preview-name #:server-command #:share-command #:unshare-command #:state-directory
           #:check-files #:check-scenario #:worktree-branch
           #:make-record #:text-field #:set-text-field #:gate-decider #:reviewer-verdict
           #:repository-tree #:*tracker-limit* #:without-links #:record-shown #:read-record))
