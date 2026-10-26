;;;; web/ui/package.lisp -- TUN.UI: the design system (spec/ui.md).
;;;;
;;;; Components are functions from options and children to markup nodes
;;;; (TUN.HTML).  DEFINE-COMPONENT exports each one by name, so this list
;;;; holds only the machinery around them.

(defpackage #:tun.ui
  (:use #:cl #:tun.html)
  (:export
   ;; defining components
   #:define-component #:component #:find-component #:all-components #:component-name
   #:component-group #:component-doc #:component-source #:component-css #:component-script
   #:component-examples #:component-internal-p #:root-class #:scoped-css-problem
   ;; helpers for component bodies
   #:attrs #:option-string #:element-id #:heading-tag
   ;; the stylesheet and the script
   #:stylesheet #:stylesheet-path #:script #:script-path #:asset-content #:asset-hashes
   ;; htmx
   #:htmx-path #:htmx-config
   ;; icons
   #:icon-names #:icon-shapes
   ;; the specimen
   #:specimen-html #:write-specimen))
