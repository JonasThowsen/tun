;;;; tun.asd -- the tun kernel (client-agnostic, business-agnostic).
;;;;
;;;; Systems (one ASDF system per building of the tun):
;;;;   tun/core       registry macros, types, entities, operations, execution path, store port,
;;;;                  module registry
;;;;   tun/memory     in-memory store adapter
;;;;   tun/sqlite     SQLite store adapter
;;;;   tun/postgres   Postgres store adapter
;;;;   tun            the kernel a deployment needs (workflows, platform tools,
;;;;                  introspection, accounts, accounting port, MCP, web) + public facade
;;;;   tun/tests      core test-suite: the kernel and every module, no client
;;;;
;;;; Two companions have .asd files of their own, so Nix can build each as a
;;;; package beside the kernel: tun-test-support.asd (helpers for the core
;;;; suite and every client's) and tun-cli.asd (the tun command, spec/cli.md).
;;;;
;;;; Kernel sources live under src/.  The business modules are separate systems
;;;; under modules/<name>/, named tun-<name>, and clients pin each separately.

(defsystem "tun/core"
  :pathname "src"
  :description "tun core: registry, operations, guarded execution path, store port."
  :depends-on ("closer-mop" "com.inuoe.jzon" "ironclad" "cl-ppcre" "uiop" (:require "sb-introspect"))
  :serial t
  :components ((:module "core"
                :components ((:file "package")
                             (:file "util")
                             (:file "i18n")
                             (:file "zones")
                             (:file "counts")
                             (:file "json")
                             (:file "conditions")
                             (:file "rank")
                             (:file "trace")
                             (:file "module")
                             (:file "types")
                             (:file "formats")
                             (:file "sql-text")
                             (:file "entity")
                             (:file "deadline")
                             (:file "actor")
                             (:file "store")
                             (:file "application")
                             (:file "system-entities")
                             (:file "operation")
                             (:file "query")
                             (:file "record-policy")
                             (:file "execution")
                             (:file "waiting")
                             (:file "registry")
                             (:file "settings")
                             (:file "core-migration")))))

(defsystem "tun/memory"
  :pathname "src"
  :depends-on ("tun/core")
  :components ((:module "store" :components ((:file "memory")))))

(defsystem "tun/sqlite"
  :pathname "src"
  :depends-on ("tun/core" "sqlite" "cl-ppcre" "closer-mop")
  :components ((:module "store" :components ((:file "sqlite")))))

(defsystem "tun/postgres"
  :pathname "src"
  :depends-on ("tun/core" "cl-postgres" "cl-ppcre" "closer-mop" "ironclad" "uiop")
  :components ((:module "store" :components ((:file "postgres")))))

(defsystem "tun"
  :pathname "src"
  :description "tun: the client-agnostic kernel."
  :version "1.3.0"
  :depends-on ("tun/core" "tun/memory" "tun/sqlite" "tun/postgres" "hunchentoot" "chunga" "flexi-streams"
               "cl-base64" "drakma" "uiop" "swank")
  :serial t
  :components ((:module "ports" :components ((:file "accounting")))
               (:module "adapters" :components ((:file "fake-accounting")))
               (:module "jobs" :components ((:file "jobs") (:file "cron") (:file "schedules") (:file "triggers")
                                            (:file "runner") (:file "tools")))
               ;; HTML as data, before mail: a mail's HTML part is built of it.
               (:module "html" :pathname "web" :components ((:file "html")))
               (:module "mail" :components ((:file "mail") (:file "html") (:file "resend")))
               (:module "outbound" :components ((:file "outbound") (:file "programs")))
               (:module "files" :components ((:file "package") (:file "formats") (:file "multipart")
                                             (:file "attachments")))
               (:module "platform"
                :components ((:file "live-definitions")
                             (:file "workflows")
                             (:file "platform")
                             (:file "introspection")
                             (:file "errors")))
               (:module "auth"
                :components ((:file "package")
                             (:file "accounts")
                             (:file "oidc")
                             (:file "sign-in")
                             (:file "oauth")
                             (:file "tools")))
               (:module "push"
                :components ((:file "package")
                             (:file "crypto")
                             (:file "push")))
               (:module "agent"
                :components ((:file "mcp")
                             (:file "http")))
               (:module "web"
                :components ((:module "components"
                              :pathname "ui"
                              :serial t
                              :components ((:file "package")
                                           (:static-file "htmx.min.js")
                                           (:file "kit")
                                           (:file "icon-data")
                                           (:file "icons")
                                           (:file "actions")
                                           (:file "forms")
                                           (:file "data")
                                           (:file "feedback")
                                           (:file "interaction")
                                           (:file "board")
                                           (:file "files")
                                           (:file "push")
                                           (:file "layout")
                                           (:file "specimen")))
                             (:file "ui")
                             (:file "access")
                             (:file "web-app")
                             (:file "push")
                             (:file "files")))
               ;; The Norwegian catalogues of the kernel's copy (spec/i18n.md 3.2).
               (:module "i18n" :components ((:file "nb-core") (:file "nb-platform")
                                            (:file "nb-jobs") (:file "nb-mail")
                                            (:file "nb-files") (:file "nb-auth")
                                            (:file "nb-push") (:file "nb-agent")
                                            (:file "nb-web") (:file "nb-ui")))
               (:file "runtime")
               (:file "public")))

(defsystem "tun/tests"
  :description "Core test-suite: the kernel and every module, with no client loaded."
  :depends-on ("tun" "tun-customers" "tun-catalog" "tun-inventory" "tun-reviews" "tun-orders" "tun-invoicing"
               "tun-messaging" "tun-staffing" "tun-notifications" "tun-inbox" "tun-calendar" "tun-warehouse" "tun-dashboard" "tun-test-support" "tun-cli" "fiveam")
  :serial t
  :components ((:module "tests"
                :components ((:file "package")
                             (:file "util-tests")
                             (:file "rank-tests")
                             (:file "settings-tests")
                             (:file "registry-tests")
                             (:file "widgets")
                             (:file "safety-tests")
                             (:file "mcp-tests")
                             (:file "store-tests")
                             (:file "core-migration-tests")
                             (:file "i18n-tests")
                             (:file "query-tests")
                             (:file "record-policy-tests")
                             (:file "files-tests")
                             (:file "hostile-tests")
                             (:file "module-tests")
                             (:file "module-system-tests")
                             (:file "orders-depth-tests")
                             (:file "staffing-tests")
                             (:file "web-tests")
                             (:file "fake-provider")
                             (:file "auth-tests")
                             (:file "sign-in-tests")
                             (:file "oauth-tests")
                             (:file "api-tests")
                             (:file "waiting-tests")
                             (:file "outbound-tests")
                             (:file "program-tests")
                             (:file "web-app-tests")
                             (:file "mail-tests")
                             (:file "mail-html-tests")
                             (:file "push-tests")
                             (:file "jobs-tests")
                             (:file "schedule-tests")
                             (:file "dashboard-tests")
                             (:file "errors-tests")
                             (:file "ui-tests")
                             (:file "ui-feedback-tests")
                             (:file "ui-actions-tests")
                             (:file "ui-data-tests")
                             (:file "ui-forms-tests")
                             (:file "ui-layout-tests")
                             (:file "ui-interaction-tests")
                             (:file "review-tests")
                             (:file "review2-tests")
                             (:file "slice1-review-tests")
                             (:file "slice2-tests")
                             (:file "slice2-review-tests")
                             (:file "pressure-tests")
                             (:file "communication-tests")
                             (:file "slice3-review-tests")
                             (:file "slice3-review-round3-tests")
                             (:file "slice3-review-round4-tests")
                             (:file "group-commit-tests")
                             (:file "introspection-tests")
                             (:file "cli-tests")
                             (:file "preview-tests")
                             (:file "loop-tests")
                             (:file "run")))))
