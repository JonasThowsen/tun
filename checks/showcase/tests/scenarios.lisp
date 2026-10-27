;;;; tests/scenarios.lisp -- what the checks start from (spec/preview.md 3).

(in-package #:showcase.tests)

(defun create-card (title &optional (status "ny"))
  "Create a card titled TITLE, last in the column STATUS, and return its id."
  (let ((id (tun:jget (call-ok "cards_create" "employee:anna" "title" title) "id")))
    (unless (equal status "ny")
      (call-ok "cards_move" "employee:anna" "id" id "status" status))
    id))

(defun showcase-file (name)
  "The file NAME of the showcase's checks/files/, as a FILES value's item."
  (with-open-file (in (asdf:system-relative-pathname "showcase" (format nil "checks/files/~a" name))
                      :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence octets in)
      (tun:jobj "filename" name "data" (cl-base64:usb8-array-to-base64-string octets)))))

(define-scenario default (:actors ("employee:anna"))
  "25 kort i Ny, med ett som haster satt øverst, tre planlagte og ett ferdig;
«Eksport til regnskap» har et skjermbilde og en PDF ved seg."
  (let ((first (create-card "Sak nummer 1")))
    (loop for i from 2 to 25
          do (create-card (format nil "Sak nummer ~d" i)))
    (dolist (title '("Ny side for fakturaer" "Eksport til regnskap" "Varsel på e-post"))
      (let ((id (create-card title "planlagt")))
        (when (equal title "Eksport til regnskap")
          (call-ok "attachments_add" "employee:anna" "entity" "card" "record_id" id
                   "files" (tun:jarr (list (showcase-file "skjermbilde.png")
                                           (showcase-file "kvittering.pdf")))))))
    (create-card "Rett skrivefeil" "ferdig")
    ;; Made last, put first: the board shows the order a person chose.
    (call-ok "cards_move" "employee:anna" "id" (create-card "Haster: kunden får ikke logget inn")
                                          "status" "ny" "before" first)))

(define-scenario few-cards (:actors ("employee:anna"))
  "Tre kort i Ny."
  (dotimes (i 3)
    (create-card (format nil "Sak nummer ~d" (1+ i)))))
