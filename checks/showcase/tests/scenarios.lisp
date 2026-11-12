;;;; tests/scenarios.lisp -- what the checks start from (spec/preview.md 3).

(in-package #:showcase.tests)

(defparameter +reported-on+ "2026-10-21"
  "The date the scenarios' cards were reported on, which the board shows.")

(defun create-card (title &key (status "new") estimate (reported-on +reported-on+))
  "Create a card titled TITLE, last in the column STATUS, reported on
REPORTED-ON, with ESTIMATE in minor units when given, and return its id."
  (let ((id (tun:jget (apply #'call-ok "cards_create" "employee:anna" "title" title
                             "reported_on" reported-on
                             (and estimate (list "estimate_minor" estimate)))
                      "id")))
    (unless (equal status "new")
      (call-ok "cards_move" "employee:anna" "id" id "status" status))
    id))

(defun showcase-file (name)
  "The file NAME of the showcase's checks/files/, as a FILES value's item."
  (with-open-file (in (asdf:system-relative-pathname "showcase"
                                                     (format nil "checks/files/~a" name))
                      :element-type '(unsigned-byte 8))
    (let ((octets (make-array (file-length in) :element-type '(unsigned-byte 8))))
      (read-sequence octets in)
      (tun:jobj "filename" name "data" (cl-base64:usb8-array-to-base64-string octets)))))

(defun board-of-items ()
  "Make the default scenario's cards."
  (let ((first (create-card "Item 1")))
    (loop for i from 2 to 25
          do (create-card (format nil "Item ~d" i)))
    ;; Reported on days of their own, for the period of /days.
    (loop for title in '("New page for invoices" "Export to accounting" "Notification by email")
          for day in '("2026-11-03" "2026-11-10" "2026-12-02")
          do (let ((id (create-card title :status "planned" :reported-on day
                                         :estimate (and (equal title "Export to accounting")
                                                        1250000))))
               (when (equal title "Export to accounting")
                 (call-ok "attachments_add" "employee:anna" "entity" "card" "record_id" id
                          "files" (tun:jarr (list (showcase-file "screenshot.png")
                                                  (showcase-file "receipt.pdf")))))))
    (create-card "Fix a typo" :status "done" :reported-on "2026-09-15")
    ;; Made last, put first: the board shows the order a person chose.
    (call-ok "cards_move" "employee:anna" "id" (create-card "Urgent: the customer cannot sign in")
                                          "status" "new" "before" first)))

(defun some-customers ()
  "Make the customers the generated list at /customers shows."
  (loop for (name email) in '(("Nordvik Bakery Ltd" "post@nordvik.example")
                              ("Hansen Plumbing" "kari@hansen.example")
                              ("Fjord Events" "booking@fjord.example")
                              ("Berg Catering" "mat@berg.example"))
        do (call-ok "customers_create" "employee:anna" "name" name "email" email)))

(define-scenario default (:actors ("employee:anna" "admin:jonas"))
  "25 cards in New, with an urgent one put first, three planned and one done;
«Export to accounting» has an estimate, and a screenshot and a PDF
attached; four customers.  Jonas is an admin, who can change the settings."
  (board-of-items)
  (some-customers))

(define-scenario search (:actors ("employee:anna" "admin:jonas"))
  "The default scenario's cards and customers, and two customers whose names
are written with letters a search folds: Bjørn Åsen, with a phone, and Café
Øst (spec/ui.md 6.4)."
  (board-of-items)
  (some-customers)
  (call-ok "customers_create" "employee:anna" "name" "Bjørn Åsen" "email" "bjorn@asen.example"
           "phone" "412 34 567")
  (call-ok "customers_create" "employee:anna" "name" "Café Øst" "email" "post@cafe-ost.example"))

(define-scenario norwegian (:actors ("admin:jonas" "employee:anna"))
  "The default scenario's cards on a tenant whose language is Norwegian.
Jonas is an admin, who can set it back to English on «Innstillinger»."
  (board-of-items)
  (call-ok "settings_set" "admin:jonas" "key" "locale.language" "value" "nb"))

(define-scenario few-cards (:actors ("employee:anna"))
  "Three cards in New."
  (dotimes (i 3)
    (create-card (format nil "Item ~d" (1+ i)))))
