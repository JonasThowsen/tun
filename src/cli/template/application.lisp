;;;; application.lisp -- the {{name}} application: the modules it enables,
;;;; how people sign in (through WorkOS AuthKit, whose domain, client id and
;;;; secret come from the deployment's SOPS file), who delivers its mail (no
;;;; one, it is logged, unless a (:mail ...) option names a provider), the
;;;; languages a tenant may be set to with a new tenant's currency and time
;;;; zone (its copy is written in the first language, its Norwegian in
;;;; nb.lisp) and, as the client grows, the features (mixin classes) that carry its own
;;;; methods. $TUN_SOURCE/docs/client-api.md shows what a client can define.

(in-package #:{{name}})

(define-application {{name}} ()
  (:modules{{modules}})
  (:locale :languages ("en" "nb") :currency "EUR" :time-zone "UTC")
  (:sign-in (:workos :domain (:env "WORKOS_DOMAIN")
                     :client-id (:env "WORKOS_CLIENT_ID")
                     :client-secret (:env "WORKOS_CLIENT_SECRET")))
  (:default-initargs :name "{{name}}")
  (:documentation "{{name}} on Tun."))

(defparameter *application-class* '{{name}}
  "The application class the server runs.")
