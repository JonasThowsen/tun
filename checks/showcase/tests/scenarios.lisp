;;;; tests/scenarios.lisp -- what the checks start from (spec/preview.md 3).

(in-package #:showcase.tests)

(define-scenario default (:actors ("employee:anna"))
  "25 kort i Ny, ett planlagt og ett ferdig."
  (dotimes (i 25)
    (call-ok "cards_create" "employee:anna" "title" (format nil "Sak nummer ~d" (1+ i))))
  (dolist (card '(("Ny side for fakturaer" "planlagt") ("Rett skrivefeil" "ferdig")))
    (destructuring-bind (title status) card
      (call-ok "cards_move" "employee:anna"
               "id" (tun:jget (call-ok "cards_create" "employee:anna" "title" title) "id")
               "status" status))))

(define-scenario few-cards (:actors ("employee:anna"))
  "Tre kort i Ny."
  (dotimes (i 3)
    (call-ok "cards_create" "employee:anna" "title" (format nil "Sak nummer ~d" (1+ i)))))
