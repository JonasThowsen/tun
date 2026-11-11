;;;; tests/ui-sheets-tests.lisp -- what opens moves into place: the dialog as
;;;; a sheet on a phone and above the keyboard, the motion of what opens and
;;;; closes, the dim, the one confirm and the flash as a toast, read from the
;;;; stylesheet, the markup and the script (spec/ui.md 2.1, 6, 10).

(in-package #:tun.tests)

(def-suite ui-sheets :in core)
(in-suite ui-sheets)

;;; ------------------------------------------------------------------
;;; What opens

(defparameter +opening-parts+
  '(("dialog" . nil) ("dropdown-menu" . "tun-dropdown-menu-content")
    ("combobox" . "tun-combobox-listbox") ("tooltip" . "tun-tooltip-content")
    ("flash" . nil))
  "Each component that opens and the class of its part that does, NIL for
the component's root.")

(defparameter +discrete-properties+ '("display" "overlay" "visibility" "content-visibility")
  "What may be in a transition of what opens without moving: it flips.")

(defun state-selector-p (selector)
  "True when nested SELECTOR only narrows the element it is in (&[open],
&:popover-open, &::backdrop), rather than reaching a part inside it."
  (and (or (eql 0 (search "&[" selector)) (eql 0 (search "&:" selector)))
       (not (find #\Space selector))))

(defun opening-declarations (name part)
  "The declarations of component NAME's CSS on PART, its class, or on its
root for NIL: in any state, but not on the parts inside it."
  (remove-if-not
   (lambda (declaration)
     (let* ((selectors (declaration-selectors declaration))
            (at (if part
                    (position-if (lambda (selector) (search part selector)) selectors)
                    0)))
       (and at (every #'state-selector-p (nthcdr (1+ at) selectors)))))
   (component-declarations name)))

(defun transition-names (declaration)
  "The properties a transition declaration names."
  (let ((value (declaration-value declaration)))
    (cond ((string= "transition-property" (declaration-property declaration))
           (split-sequence-commas value))
          ((string= "transition" (declaration-property declaration))
           (mapcar (lambda (part) (first (cl-ppcre:split " " part)))
                   (split-sequence-commas value))))))

(test what-opens-moves-only-by-opacity-and-translate
  (loop for (name . part) in +opening-parts+
        do (let ((declarations (opening-declarations name part)))
             (is (find-if #'transition-names declarations) "~a has a transition" name)
             (dolist (declaration declarations)
               (dolist (property (transition-names declaration))
                 (is (member property (list* "opacity" "translate" +discrete-properties+)
                             :test #'string=)
                     "~a animates ~a: ~a" name property (declaration-where declaration)))
               (is (not (member (declaration-property declaration)
                                '("scale" "transform" "rotate" "animation" "animation-name")
                                :test #'string=))
                   "~a: ~a" name (declaration-where declaration)))
             (is (not (search "@keyframes" (tun.ui:component-css (tun.ui:find-component name))))
                 "~a opens by transitions, not keyframes" name)
             (is (find-if (lambda (d) (and (string= "transition-duration" (declaration-property d))
                                           (string= "var(--duration-close)" (declaration-value d))))
                          declarations)
                 "~a leaves over --duration-close" name)
             (is (find-if (lambda (d) (and (member "translate" (transition-names d) :test #'string=)
                                           (member "opacity" (transition-names d) :test #'string=)))
                          declarations)
                 "~a moves and fades" name)))
  (is (search "class=\"tun-dialog\"" (tun.html:render-html (tun.ui:confirm-dialog ())))
      "the confirm dialog is a dialog, and moves as one"))

(test what-opens-starts-from-its-closed-state-and-flips-at-the-end
  (loop for (name . part) in (remove "flash" +opening-parts+ :key #'car :test #'string=)
        do (let ((declarations (opening-declarations name part)))
             (unless (string= name "tooltip")
               (is (find-if (lambda (d) (and (string= "transition-behavior"
                                                      (declaration-property d))
                                             (string= "allow-discrete" (declaration-value d))))
                            declarations)
                   "~a keeps showing while it leaves the top layer" name)
               (is (find-if (lambda (d) (some (lambda (m) (search "@starting-style" m))
                                              (declaration-media d)))
                            declarations)
                   "~a starts from its closed state" name))
             (is (find-if (lambda (d) (and (string= "transition-timing-function"
                                                    (declaration-property d))
                                           (string= "var(--ease)" (declaration-value d))))
                          declarations)
                 "~a eases with --ease" name))))

(test the-scan-finds-what-moves-otherwise
  (let ((declarations (css-declarations
                       ".tun-x { transition-property: opacity, scale; & .tun-x-part {
                          transition: height var(--duration); } &[open] { opacity: 1; } }")))
    (is (equal '(("opacity" "scale"))
               (mapcar #'transition-names
                       (remove-if-not (lambda (d) (and (transition-names d)
                                                       (every #'state-selector-p
                                                              (rest (declaration-selectors d)))))
                                      declarations)))
        "the root's own transition is read, a part's is not")))

;;; ------------------------------------------------------------------
;;; The sheet and the keyboard

(defun dialog-value (property &key media state)
  "The value component dialog's root sets for PROPERTY: outside any @media,
or inside the one whose text holds MEDIA; on its root, or in STATE (&[open])."
  (let ((found (find-if (lambda (d)
                          (and (string= property (declaration-property d))
                               (equal (declaration-selectors d)
                                      (if state (list ".tun-dialog" state) (list ".tun-dialog")))
                               (if media
                                   (some (lambda (m) (search media m)) (declaration-media d))
                                   (null (declaration-media d)))))
                        (component-declarations "dialog"))))
    (and found (declaration-value found))))

(test a-dialog-is-a-sheet-on-a-phone
  (is (equal "auto 0 0" (dialog-value "margin")) "at the bottom")
  (is (equal "100%" (dialog-value "width")))
  (is (equal "var(--radius-xl) var(--radius-xl) 0 0" (dialog-value "border-radius")))
  (is (equal "calc(var(--spacing) * 8)" (dialog-value "--tun-dialog-strip")))
  (is (equal "var(--tun-dialog-max-height)" (dialog-value "max-height")))
  (is (search "var(--tun-dialog-strip)" (dialog-value "--tun-dialog-max-height")))
  (is (search "env(safe-area-inset-bottom)" (dialog-value "padding-bottom")))
  (is (equal "0 100%" (dialog-value "translate")) "closed below the window")
  (is (equal "var(--duration-close)" (dialog-value "transition-duration")))
  (is (equal "var(--duration-sheet)" (dialog-value "transition-duration" :state "&[open]")))
  (is (equal "auto" (dialog-value "margin" :media "min-width: 40rem")) "centred from 40rem")
  (is (equal "var(--radius-xl)" (dialog-value "border-radius" :media "min-width: 40rem")))
  (is (equal "28rem" (dialog-value "max-width" :media "min-width: 40rem")))
  (is (equal "0 calc(var(--spacing) * 2)" (dialog-value "translate" :media "min-width: 40rem")))
  (is (equal "var(--duration)"
             (dialog-value "transition-duration" :media "min-width: 40rem" :state "&[open]")))
  (let ((declarations (component-declarations "dialog")))
    (flet ((part (class property)
             (declaration-value
              (find-if (lambda (d) (and (equal (declaration-selectors d)
                                               (list ".tun-dialog" (format nil "& .~a" class)))
                                        (string= property (declaration-property d))
                                        (null (declaration-media d))))
                       declarations))))
      (is (equal "auto" (part "tun-dialog-body" "overflow-y")) "only the body scrolls")
      (is (equal "none" (part "tun-dialog-header" "flex")) "the header stays")
      (is (equal "none" (part "tun-dialog-footer" "flex")) "the footer stays")
      (is (equal "wrap" (part "tun-dialog-footer" "flex-wrap")) "its buttons share a row"))))

(test a-dialog-to-type-in-fills-the-phone
  (let ((rule (find-if (lambda (d) (and (string= "height" (declaration-property d))
                                        (some (lambda (m) (search "max-width: 39.99rem" m))
                                              (declaration-media d))))
                       (component-declarations "dialog"))))
    (is (not (null rule)))
    (when rule
      (is (equal "var(--tun-dialog-max-height)" (declaration-value rule)))
      (let ((selector (selectors-text rule)))
        (dolist (field '("textarea" "[role='combobox']" "input:not("))
          (is (search field selector) "~a makes it full height" field))))))

(test a-dialog-stands-inside-the-visible-part-of-the-window
  (is (equal "var(--tun-visual-top, 0px) var(--tun-visual-bottom, 0px)"
             (dialog-value "inset-block")))
  (let ((script (tun.ui:component-script (tun.ui:find-component "dialog"))))
    (dolist (part '("visualViewport" "--tun-visual-top" "--tun-visual-bottom" "removeProperty"
                    "viewport.scale" "root.style.overflow = 'hidden'" "scrollbarGutter = 'stable'"
                    "attributeFilter: ['open']" "'Tab'"))
      (is (search part script) "the dialog's script has ~s" part))))

(test the-scripts-ask-for-popovers-and-modals-only-through-the-helpers
  (let ((script (tun.ui:script)))
    (is (= 1 (occurrences ":popover-open" script)) "only tunPopoverOpen names :popover-open")
    (is (= 1 (occurrences "':modal'" script)) "only tunModal names :modal")
    (is (search "try { return element.matches(':popover-open'); } catch (e)" script))
    (is (search "try { return dialog.matches(':modal'); } catch (e)" script)))
  (dolist (name '("dialog" "confirm-dialog" "dropdown-menu" "tooltip" "combobox"))
    (is (not (search "setTimeout" (tun.ui:component-script (tun.ui:find-component name))))
        "~a's script times nothing" name)))

(defun occurrences (needle haystack)
  "How many times NEEDLE is in HAYSTACK."
  (loop for start = 0 then (+ at (length needle))
        for at = (search needle haystack :start2 start)
        while at
        count t))

;;; ------------------------------------------------------------------
;;; The dim

(test the-dim-is-one-fade-of-the-overlay
  (is (equal "light-dark(#00000066, #0000008a)" (token "--overlay")))
  (flet ((backdrop (property &optional (state "&::backdrop"))
           (let ((found (find-if (lambda (d) (and (equal (declaration-selectors d)
                                                         (list ".tun-dialog" state))
                                                  (string= property (declaration-property d))
                                                  (notany (lambda (m) (search "@starting" m))
                                                          (declaration-media d))))
                                 (component-declarations "dialog"))))
             (and found (declaration-value found)))))
    (is (equal "var(--overlay)" (backdrop "background-color")))
    (is (equal "0" (backdrop "opacity")))
    (is (equal "1" (backdrop "opacity" "&[open]::backdrop")))
    (is (equal "opacity, display, overlay" (backdrop "transition-property")))
    (is (equal "var(--duration-close)" (backdrop "transition-duration")))
    (is (equal "var(--duration)" (backdrop "transition-duration" "&[open]::backdrop"))))
  (is (not (search "backdrop-filter" (tun.ui:component-css (tun.ui:find-component "dialog"))))
      "no blur"))

;;; ------------------------------------------------------------------
;;; One confirm

(test the-confirm-dialog-asks-with-the-pages-words
  (let ((html (tun.html:render-html (tun.ui:confirm-dialog ()))))
    (is (eql 0 (search "<div class=\"tun-confirm-dialog\" data-tun-confirm-dialog" html)))
    (is (search "data-cancel-label=\"Cancel\" data-confirm-label=\"Confirm\"" html))
    (is (search "data-variant=\"confirm\"" html))
    (is (search "role=\"alertdialog\"" html))
    (is (search "data-tun-confirm-cancel></button>" html)
        "its buttons take their words when it asks")
    (is (search "data-tun-confirm-ok></button>" html))
    (is (< (search "data-tun-confirm-cancel" html) (search "data-tun-confirm-ok" html))
        "«Cancel» first")
    (is (not (search "tun-dialog-close" html)) "no close button: it asks"))
  (let ((html (with-language ("nb") (tun.html:render-html (tun.ui:confirm-dialog ())))))
    (is (search "data-cancel-label=\"Avbryt\" data-confirm-label=\"Bekreft\"" html))))

(test a-control-is-marked-to-confirm
  (is (equal '(:data-tun-confirm "Slette ordre 1042?"
               :data-tun-confirm-detail "Ordren slettes for godt."
               :data-tun-confirm-action nil)
             (tun.ui:confirm-attributes "Slette ordre 1042?" :detail "Ordren slettes for godt.")))
  (let ((html (tun.html:render-html
               (tun.html:untrusted
                (tun.ui:button (:type "submit" :variant :destructive
                                :attributes (tun.ui:confirm-attributes "Slette ordre 1042?"
                                                                       :action "Slett"))
                  "Slett ordren")))))
    (is (search "data-tun-confirm=\"Slette ordre 1042?\"" html) "kept in extension output")
    (is (search "data-tun-confirm-action=\"Slett\"" html))
    (is (not (search "data-tun-confirm-detail" html)) "no sentence, no attribute"))
  (signals error (tun.ui:confirm-attributes nil)))

(test every-shell-holds-one-confirm-dialog
  (let ((html (tun.html:render-html (tun.ui:app-shell (:title "Nordvik Utleie") "Innhold"))))
    (is (= 1 (occurrences "data-tun-confirm-dialog" html)))
    (is (not (search ">Cancel<" html)) "and no «Cancel» in its text while it does not ask")))

(test the-confirm-script-holds-the-control-and-htmx
  (let ((script (tun.ui:component-script (tun.ui:find-component "confirm-dialog"))))
    (dolist (part '("'htmx:confirm'" "issueRequest()" "dropRequest()" "[data-tun-confirm]"
                    "stopImmediatePropagation" "agreed.add(control)" "control.click()"
                    "action.length <= 40" "'destructive'" "(danger ? cancel : ok).focus"
                    "text.slice(0, end + 1)" "window.confirm"))
      (is (search part script) "the confirm's script has ~s" part))))

;;; ------------------------------------------------------------------
;;; The flash as a toast

(test a-flash-is-a-toast-where-scripts-run
  (is (search "role=\"status\"" (tun.html:render-html (tun.ui:flash () "Lagret."))))
  (is (search "role=\"alert\""
              (tun.html:render-html (tun.ui:flash (:variant :destructive) "Feilet."))))
  (is (not (search "data-placement" (tun.html:render-html (tun.ui:flash () "Lagret.")))))
  (is (search "data-placement=\"page\""
              (tun.html:render-html (tun.ui:flash (:toast nil) "Lagret."))))
  (let ((toast (remove-if-not (lambda (d) (some (lambda (m) (search "scripting: enabled" m))
                                                (declaration-media d)))
                              (component-declarations "flash"))))
    (flet ((value (property &optional media)
             (let ((found (find-if (lambda (d)
                                     (and (string= property (declaration-property d))
                                          (equal (declaration-selectors d)
                                                 '(".tun-flash"
                                                   "&:not([data-placement='page'])"))
                                          (if media
                                              (some (lambda (m) (search media m))
                                                    (declaration-media d))
                                              (= 1 (length (declaration-media d))))))
                                   toast)))
               (and found (declaration-value found)))))
      (is (equal "fixed" (value "position")))
      (is (equal "var(--z-toast)" (value "z-index")))
      (is (search "env(safe-area-inset-bottom)" (value "inset")) "at the bottom of a phone")
      (is (equal "calc(var(--spacing) * 4) calc(var(--spacing) * 4) auto auto"
                 (value "inset" "min-width: 40rem"))
          "at the top right from 40rem")
      (is (equal "min(25rem, calc(100% - var(--spacing) * 8))"
                 (value "width" "min-width: 40rem")))))
  (let ((script (tun.ui:component-script (tun.ui:find-component "flash"))))
    (dolist (part '("const lifetime = 5000;" "/^(success|info)$/" "'pointerover'" "'focusin'"
                    "data-tun-leaving" "getAnimations()"))
      (is (search part script) "the flash's script has ~s" part))))
