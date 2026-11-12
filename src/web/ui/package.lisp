;;;; web/ui/package.lisp -- TUN.UI: the design system (spec/ui.md).
;;;;
;;;; Components are functions from options and children to markup nodes
;;;; (TUN.HTML).  DEFINE-COMPONENT exports each one by name, so this list
;;;; holds only the machinery around them.

(defpackage #:tun.ui
  (:use #:cl #:tun.html)
  ;; A component's own copy is written with TR (spec/i18n.md 3.1).
  (:import-from #:tun.core #:tr #:current-language #:number-text)
  ;; A chart writes its times and hands its points to its script.
  (:import-from #:tun.core #:date-text #:day-text #:instant-text #:local-date-of
                #:local-time-of #:jarr #:to-json-string)
  ;; The fields a person types a date, a time and an amount in, and a
  ;; list's period (fields.lisp, toolbar.lisp).
  (:import-from #:tun.core #:read-date-text #:period-text #:money-number-text #:month-name
                #:month-abbreviation #:calendar-day-name #:calendar-day-short-name #:week-first-day
                #:page-today #:valid-date-string-p #:date-add-days #:date-add-months
                #:current-currency #:currency-mark #:weekday-of)
  ;; The search's results mark what the one rule matched (search.lisp).
  (:import-from #:tun.core #:make-search-query #:search-mark-ranges)
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
