;;;; tun-catalog.asd -- the catalog module (tun-platform.md 2).

(defsystem "tun-catalog"
  :description "tun module catalog: products, requirements, recipes, choice groups and the resolver."
  :version "1.0.0"
  :depends-on ("tun")
  :serial t
  :components ((:file "catalog")
               (:file "requirements")
               (:file "publish")))
