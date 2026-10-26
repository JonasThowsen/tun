;;;; web/ui/icons.lisp -- ICON: Lucide icons as inline SVG (spec/ui.md 6).

(in-package #:tun.ui)

(declaim (optimize (safety 3) (debug 2)))

(defun icon-names ()
  "The names of the icons Tun carries, as keywords."
  (mapcar #'first +icons+))

(defun icon-shapes (name)
  "The shapes of icon NAME, a keyword; an error for an unknown name."
  (or (rest (assoc name +icons+))
      (error "Unknown icon ~s; scripts/ui-icons.py lists the icons Tun carries" name)))

(define-component icon ((&key name label (size :default) id attributes))
  (:group "Handlinger")
  (:doc "Et ikon fra Lucide. Uten LABEL er det pynt som skjermlesere hopper over; med LABEL
leses teksten opp i stedet.")
  (:source "Lucide")
  (:css "
.tun-icon {
  width: calc(var(--spacing) * 4);
  height: calc(var(--spacing) * 4);
  flex-shrink: 0;
  pointer-events: none;
  &[data-size='xs'] { width: calc(var(--spacing) * 3); height: calc(var(--spacing) * 3); }
  &[data-size='sm'] { width: calc(var(--spacing) * 3.5); height: calc(var(--spacing) * 3.5); }
  &[data-size='lg'] { width: calc(var(--spacing) * 5); height: calc(var(--spacing) * 5); }
  &[data-size='xl'] { width: calc(var(--spacing) * 6); height: calc(var(--spacing) * 6); }
}")
  (:examples
   ("Størrelser"
    (icon (:name :package :size :xs))
    (icon (:name :package :size :sm))
    (icon (:name :package))
    (icon (:name :package :size :lg))
    (icon (:name :package :size :xl)))
   ("Med tekst for skjermlesere"
    (icon (:name :circle-alert :label "Advarsel")))
   ("Alle ikonene"
    (mapcar (lambda (name)
              `(:span (:@ :title ,(string-downcase (symbol-name name)))
                      ,(icon (:name name :size :lg))))
            (icon-names))))
  (check-type name keyword)
  `(:svg ,(attrs (list :class "tun-icon" :xmlns "http://www.w3.org/2000/svg"
                       :viewbox "0 0 24 24" :fill "none" :stroke "currentColor"
                       :stroke-width "2" :stroke-linecap "round" :stroke-linejoin "round"
                       :focusable "false" :data-size (unless (eq size :default)
                                                       (option-string size))
                       :aria-hidden (unless label "true")
                       :role (when label "img") :aria-label label :id id)
                 attributes)
         ,@(icon-shapes name)))
