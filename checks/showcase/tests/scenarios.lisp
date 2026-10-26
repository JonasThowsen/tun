;;;; tests/scenarios.lisp -- what the checks start from (spec/preview.md 3).

(in-package #:showcase.tests)

(defun create-card (title &optional (status "ny"))
  "Create a card titled TITLE, last in the column STATUS, and return its id."
  (let ((id (tun:jget (call-ok "cards_create" "employee:anna" "title" title) "id")))
    (unless (equal status "ny")
      (call-ok "cards_move" "employee:anna" "id" id "status" status))
    id))

(define-scenario default (:actors ("employee:anna"))
  "25 kort i Ny, med ett som haster satt øverst, tre planlagte og ett ferdig."
  (let ((first (create-card "Sak nummer 1")))
    (loop for i from 2 to 25
          do (create-card (format nil "Sak nummer ~d" i)))
    (dolist (title '("Ny side for fakturaer" "Eksport til regnskap" "Varsel på e-post"))
      (create-card title "planlagt"))
    (create-card "Rett skrivefeil" "ferdig")
    ;; Made last, put first: the board shows the order a person chose.
    (call-ok "cards_move" "employee:anna" "id" (create-card "Haster: kunden får ikke logget inn")
                                          "status" "ny" "before" first)))

(define-scenario few-cards (:actors ("employee:anna"))
  "Tre kort i Ny."
  (dotimes (i 3)
    (create-card (format nil "Sak nummer ~d" (1+ i)))))
