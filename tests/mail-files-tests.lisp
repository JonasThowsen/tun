;;;; tests/mail-files-tests.lisp -- a mail's attachments (spec/mail.md 2.2):
;;;; a stored file by its id or its object and bytes the sender made,
;;;; delivered whole to a fake provider and to a fake Resend; the tools'
;;;; metadata; the limits and refusals; the mail's own copies, a retry, and
;;;; the source gone; and FILE-OCTETS (spec/files.md 4.2), the five functions
;;;; a module reaches through TUN.CORE.

(in-package #:tun.tests)

(def-suite mail-files :in core)
(in-suite mail-files)

;;; ------------------------------------------------------------------
;;; Sending with attachments

(defun attachment-items (json)
  "SEND-MAIL's attachments from JSON, an array: a string is a file's id, an
object with base64 is (:FILENAME NAME :CONTENT OCTETS), any other object an
attachment object, anything else as it is."
  (map 'list (lambda (item)
               (if (and (hash-table-p item) (jget item "base64"))
                   (list :filename (jget item "filename")
                         :content (cl-base64:base64-string-to-usb8-array (jget item "base64")))
                   item))
       json))

(define-operation mail-files-test-send ((attachments :type json) (key :type string))
    (:kind :update :policy :employee :title "Send a mail with files (test)")
  (jobj "id" (entity-id (tun.mail:send-mail :to "ola@example.no" :subject "Filer"
                                             :text "Filene ligger ved." :key key
                                             :attachments (attachment-items attachments)))))

(defun given (name octets)
  "An item for MAIL-FILES-TEST-SEND: bytes the sender made."
  (jobj "filename" name "base64" (base64 octets)))

(defun send-files (actor &rest items)
  "Values the id of the mail ACTOR queues with ITEMS, or the error and its code."
  (multiple-value-bind (json code) (call "mail_files_test_send" actor "attachments" (jarr items))
    (if code (values json code) (jget json "id"))))

(defun note-with-file (&optional (actor "employee:anna") (name "skjermbilde.png")
                         (octets (fixture "skjermbilde.png")))
  "Values a new file note's id and the id of the file ACTOR attached to it."
  (let ((note (jget (call-ok "file_notes_create" actor "title" "Med fil") "id")))
    (values note (first-file-id (call-ok "attachments_add" actor "entity" "file_note"
                                         "record_id" note "files" (files-json name octets))))))

(defun stored-octets (octets)
  "OCTETS as Tun stores them, with their metadata taken out."
  (values (tun.files:examine-file octets)))

(defun sha256-of (octets)
  (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha256 octets)))

(defun mail-attachment-count ()
  (with-application (*app*)
    (with-transaction (:read) (length (select 'tun.mail:mail-attachment)))))

(defun mail-delivery-jobs ()
  (count "send_queued_mail" (jget (call-ok "jobs_list" "admin:ada") "items")
         :key (lambda (job) (jget job "kind")) :test #'equal))

(defun mail-copy-content (id)
  "What the store holds under the mail attachment ID, or NIL."
  (with-application (*app*)
    (with-transaction (:read) (store-read-content *store* id 0 100))))

(defun delivered-files (provider)
  "The files of the scripted PROVIDER's last call, as (FILENAME TYPE OCTETS)."
  (mapcar (lambda (file)
            (list (tun.mail:mail-file-filename file) (tun.mail:mail-file-content-type file)
                  (tun.mail:mail-file-octets file)))
          (first (scripted-files provider))))

(test two-attachments-are-delivered-whole-and-shown-without-their-bytes
  (with-mail (provider)
    (multiple-value-bind (note file) (note-with-file)
      (declare (ignore note))
      (let* ((pdf (fixture "kvittering.pdf"))
             (png (stored-octets (fixture "skjermbilde.png")))
             (id (send-files "employee:anna" file (given "kvittering.pdf" pdf))))
        (let ((items (coerce (jget (mail-of id) "attachments") 'list)))
          (is (= 2 (length items)))
          (destructuring-bind (first second) items
            (is (equal "skjermbilde.png" (jget first "filename")))
            (is (equal "image/png" (jget first "content_type")))
            (is (= (length png) (jget first "size")))
            (is (equal (sha256-of png) (jget first "sha256")))
            (is (equal file (jget first "file_id")))
            (is (eq t (jget first "kept")))
            (is (equal "kvittering.pdf" (jget second "filename")))
            (is (equal "application/pdf" (jget second "content_type")))
            (is (= (length pdf) (jget second "size")))
            (is (eq :null (jget second "file_id")) "bytes the sender gave come from no file")
            (dolist (item items)
              (is (string-prefix-p "mat_" (jget item "id")))
              (is (equal '("content_type" "file_id" "filename" "id" "kept" "sha256" "size")
                         (sort (copy-list (jkeys item)) #'string<))
                  "metadata only, never the bytes"))))
        (let ((listed (find id (coerce (jget (call-ok "mail_list" "admin:ada") "items") 'list)
                            :key (lambda (m) (jget m "id")) :test #'equal)))
          (is (equal '("skjermbilde.png" "kvittering.pdf")
                     (map 'list (lambda (a) (jget a "filename")) (jget listed "attachments")))
              "mail_list shows them too"))
        (is (= 1 (deliver)))
        (is (equalp (list (list "skjermbilde.png" "image/png" png)
                         (list "kvittering.pdf" "application/pdf" pdf))
                   (delivered-files provider))
            "the provider gets both, in order, with their exact bytes")
        (is (equal "sent" (mail-field id "status")))))))

(test an-attachment-object-names-its-stored-file
  (with-mail (provider)
    (multiple-value-bind (note file) (note-with-file)
      (let* ((objects (jget (call-ok "attachments_list" "employee:anna" "entity" "file_note"
                                     "record_id" note)
                            "items"))
             (id (send-files "employee:anna" (aref objects 0))))
        (is (equal file (jget (aref (jget (mail-of id) "attachments") 0) "file_id")))
        (deliver)
        (is (equalp (stored-octets (fixture "skjermbilde.png"))
                    (third (first (delivered-files provider)))))))))

(test attachments-of-a-record-pass-as-they-are
  (with-mail (provider)
    (multiple-value-bind (note) (note-with-file)
      (let ((id (with-application (*app*)
                  (with-actor ((parse-actor "employee:anna"))
                    (with-transaction (:write)
                      (entity-id (send-mail :to "ola@example.no" :subject "Filer" :text "Ved."
                                            :attachments (attachments-of
                                                          (fetch 'file-note note)))))))))
        (is (equal '("skjermbilde.png")
                   (map 'list (lambda (a) (jget a "filename")) (jget (mail-of id) "attachments"))))))))

(test resend-receives-the-attachments-in-its-shape
  (with-fake-resend (resend)
    (multiple-value-bind (note file) (note-with-file)
      (declare (ignore note))
      (let ((pdf (fixture "kvittering.pdf"))
            (png (stored-octets (fixture "skjermbilde.png"))))
        (send-files "employee:anna" file (given "kvittering.pdf" pdf))
        (is (= 1 (deliver)))
        (let ((attachments (jget (getf (first (resend-requests resend)) :body) "attachments")))
          (is (= 2 (length attachments)))
          (is (equal '("content" "content_type" "filename")
                     (sort (copy-list (jkeys (aref attachments 0))) #'string<)))
          (is (equal "skjermbilde.png" (jget (aref attachments 0) "filename")))
          (is (equal "image/png" (jget (aref attachments 0) "content_type")))
          (is (equal (base64 png) (jget (aref attachments 0) "content")))
          (is (equalp png (cl-base64:base64-string-to-usb8-array
                           (jget (aref attachments 0) "content"))))
          (is (equal "kvittering.pdf" (jget (aref attachments 1) "filename")))
          (is (equal "application/pdf" (jget (aref attachments 1) "content_type")))
          (is (equal (base64 pdf) (jget (aref attachments 1) "content")))
          (is (notany (lambda (c) (member c '(#\Return #\Newline)))
                      (jget (aref attachments 1) "content"))
              "base64 without line breaks"))))
    (queue-mail "key" "uten-filer")
    (deliver)
    (is (not (nth-value 1 (gethash "attachments" (getf (first (resend-requests resend)) :body))))
        "no attachments member without attachments")))

;;; ------------------------------------------------------------------
;;; Limits and refusals: nothing is stored

(defun refused-fields (json)
  (map 'list (lambda (f) (list (jget f "field") (jget f "message")))
       (jget (jget json "error") "fields")))

(defun nothing-queued-p ()
  (and (zerop (length (jget (call-ok "mail_list" "admin:ada") "items")))
       (zerop (mail-attachment-count))
       (zerop (mail-delivery-jobs))))

(test attachments-past-the-limits-are-refused-when-queued
  (with-mail (provider)
    (let ((pdf (fixture "kvittering.pdf")))
      (multiple-value-bind (json code)
          (apply #'send-files "employee:anna"
                 (loop for i below 11 collect (given (format nil "~d.pdf" i) pdf)))
        (is (equal "invalid_input" code))
        (is (equal '(("attachments" "A mail can carry at most 10 files.")) (refused-fields json))))
      (multiple-value-bind (json code)
          (send-files "employee:anna" (given "a.pdf" (padded-pdf (* 6 +mib+)))
                      (given "b.pdf" (padded-pdf (+ (* 4 +mib+) 1))))
        (is (equal "invalid_input" code))
        (is (equal '(("attachments" "A mail's files can be at most 10 MB together."))
                   (refused-fields json))))
      (multiple-value-bind (json code)
          (send-files "employee:anna" (given "kvittering.pdf" pdf) (given "notat.txt" (bytes "hei"))
                      (given "tom.pdf" (bytes)) (given "stor.pdf" (padded-pdf (1+ (* 10 +mib+))))
                      42)
        (is (equal "invalid_input" code))
        (is (equal '(("attachments[1]"
                      "“notat.txt”: This type of file is not allowed. Use PNG, JPEG, WebP, GIF or PDF.")
                     ("attachments[2]" "“tom.pdf”: The file is empty.")
                     ("attachments[3]" "“stor.pdf”: The file is larger than 10 MB.")
                     ("attachments[4]"
                      "must be a file's id, an attachment object or (:filename NAME :content OCTETS)"))
                   (refused-fields json))))
      (is (nothing-queued-p) "nothing of a refused mail is stored")
      (is (stringp (send-files "employee:anna" (given "a.pdf" (padded-pdf (* 5 +mib+)))
                               (given "b.pdf" (padded-pdf (* 5 +mib+)))))
          "10 MiB together is taken")
      (is (= 2 (mail-attachment-count))))))

(test a-stored-file-the-sender-may-not-see-is-not-found
  (with-mail (provider)
    (multiple-value-bind (note file) (note-with-file)
      (declare (ignore note))
      (let ((admins (jget (call-ok "admin_notes_create" "admin:ada" "title" "Hemmelig") "id")))
        (let ((secret (first-file-id (call-ok "attachments_add" "admin:ada" "entity" "admin_note"
                                              "record_id" admins
                                              "files" (files-json "hemmelig.png"
                                                                  (fixture "skjermbilde.png"))))))
          (dolist (id (list secret "fil_finnes_ikke"))
            (multiple-value-bind (json code) (send-files "employee:anna" file id)
              (is (equal "not_found" code))
              (is (equal (format nil "Could not find the file ~a" id)
                         (jget (jget json "error") "message"))))))
        (let* ((class (find-class 'file-note))
               (option (entity-attachments class)))
          (unwind-protect
               (progn (setf (entity-attachments class) nil)
                      (is (equal "not_found" (nth-value 1 (send-files "employee:anna" file)))
                          "a file whose entity no longer takes files"))
            (setf (entity-attachments class) option)))
        (is (nothing-queued-p))))))

(test a-key-that-exists-keeps-its-attachments
  (with-mail (provider)
    (let ((first (call-ok "mail_files_test_send" "employee:anna" "key" "faktura:1"
                          "attachments" (jarr (list (given "a.pdf" (fixture "kvittering.pdf"))))))
          (again (call-ok "mail_files_test_send" "employee:anna" "key" "faktura:1"
                          "attachments" (jarr (list (given "b.pdf" (fixture "kvittering.pdf"))
                                                    (given "c.pdf" (fixture "kvittering.pdf")))))))
      (is (equal (jget first "id") (jget again "id")))
      (is (equal '("a.pdf") (map 'list (lambda (a) (jget a "filename"))
                                 (jget (mail-of (jget first "id")) "attachments"))))
      (is (= 1 (mail-attachment-count))))))

;;; ------------------------------------------------------------------
;;; The mail's own copies (spec/mail.md 2.2, 3, 5)

(test a-file-removed-before-sending-is-sent-all-the-same
  (with-mail (provider)
    (multiple-value-bind (note file) (note-with-file)
      (let ((png (stored-octets (fixture "skjermbilde.png")))
            (removed (send-files "employee:anna" file))
            (deleted (send-files "employee:anna" file)))
        (call-ok "attachments_remove" "employee:anna" "id" file)
        (with-application (*app*)
          (with-actor ((system-actor "test"))
            (with-transaction (:write) (delete-entity (fetch 'file-note note)))
            (with-transaction (:write) (tun.files:sweep-attachments))))
        (is (= 2 (deliver)))
        (dolist (id (list removed deleted))
          (is (equal "sent" (mail-field id "status"))))
        (is (every (lambda (files) (equalp png (tun.mail:mail-file-octets (first files))))
                   (scripted-files provider))
            "removed from its record, its record deleted, and the sweep run: the mail keeps it")))))

(test a-sent-mail-keeps-what-its-files-were-not-their-bytes
  (with-mail (provider)
    (let* ((id (send-files "employee:anna" (given "kvittering.pdf" (fixture "kvittering.pdf"))))
           (copy (jget (aref (jget (mail-of id) "attachments") 0) "id")))
      (is (mail-copy-content copy) "kept while queued")
      (deliver)
      (let ((item (aref (jget (mail-of id) "attachments") 0)))
        (is (eq nil (jget item "kept")))
        (is (equal "kvittering.pdf" (jget item "filename")))
        (is (= (length (fixture "kvittering.pdf")) (jget item "size")))
        (is (equal (sha256-of (fixture "kvittering.pdf")) (jget item "sha256"))))
      (is (null (mail-copy-content copy)) "the bytes are gone once it is sent"))))

(test a-retry-sends-the-same-files-after-the-source-is-gone
  (with-mail (provider '(:failed "resend 422 validation_error: nope"))
    (multiple-value-bind (note file) (note-with-file)
      (declare (ignore note))
      (let ((png (stored-octets (fixture "skjermbilde.png")))
            (id (send-files "employee:anna" file)))
        (deliver)
        (is (equal "failed" (mail-field id "status")))
        (is (eq t (jget (aref (jget (mail-of id) "attachments") 0) "kept"))
            "a failed mail keeps its bytes")
        (call-ok "attachments_remove" "employee:anna" "id" file)
        (call-ok "mail_retry" "admin:ada" "id" id)
        (is (= 1 (deliver)))
        (is (equal "sent" (mail-field id "status")))
        (is (= 2 (length (scripted-files provider))))
        (is (equalp png (third (first (delivered-files provider))))
            "the retry carries the same bytes")
        (is (equalp (second (scripted-files provider)) (first (scripted-files provider))))))))

(test a-mail-whose-copy-is-gone-fails-without-calling-the-provider
  (with-mail (provider)
    (let* ((id (send-files "employee:anna" (given "kvittering.pdf" (fixture "kvittering.pdf"))))
           (copy (jget (aref (jget (mail-of id) "attachments") 0) "id")))
      (with-application (*app*)
        (with-transaction (:write) (store-delete-content *store* copy)))
      (deliver)
      (is (equal "failed" (mail-field id "status")))
      (is (equal "the attachment kvittering.pdf is no longer stored" (mail-field id "last_error")))
      (is (null (scripted-calls provider)) "the provider is not called")
      (is (equal "failed" (jget (delivery-job id) "state"))))))

(test attachments-round-trip-through-postgres
  (if (postgres-available-p)
      (let ((provider (make-instance 'scripted-mail)))
        (with-test-app (:mail provider :db (scratch-postgres "mail-files"))
          (multiple-value-bind (note file) (note-with-file)
            (declare (ignore note))
            (let ((id (send-files "employee:anna" file (given "kvittering.pdf"
                                                              (fixture "kvittering.pdf")))))
              (is (= 2 (length (jget (mail-of id) "attachments"))))
              (deliver)
              (is (equalp (list (stored-octets (fixture "skjermbilde.png"))
                               (fixture "kvittering.pdf"))
                         (mapcar #'third (delivered-files provider))))
              (is (equal '(nil nil) (map 'list (lambda (a) (jget a "kept"))
                                         (jget (mail-of id) "attachments"))))))))
      (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")))

;;; ------------------------------------------------------------------
;;; A file's bytes in code (spec/files.md 4.2)

(defun file-octets-as (actor id)
  "Values the octets and object FILE-OCTETS gives ACTOR for ID, or NIL and
the refusal's code and message."
  (with-application (*app*)
    (with-actor ((parse-actor actor))
      (handler-case (with-transaction (:read) (file-octets id))
        (operation-error (e)
          (values nil (json-name-of (operation-error-code e))
                  (with-language (:source) (operation-error-message e))))))))

(test file-octets-reads-a-file-as-its-page-serves-it
  (with-test-app ()
    (multiple-value-bind (note file) (note-with-file)
      (declare (ignore note))
      (multiple-value-bind (octets object) (file-octets-as "viewer:vera" file)
        (is (equalp (stored-octets (fixture "skjermbilde.png")) octets))
        (is (equal file (jget object "id")))
        (is (equal "skjermbilde.png" (jget object "filename"))))
      (is (equal '(nil "not_found" "Could not find the file fil_finnes_ikke")
                 (multiple-value-list (file-octets-as "viewer:vera" "fil_finnes_ikke"))))
      (let* ((admins (jget (call-ok "admin_notes_create" "admin:ada" "title" "Hemmelig") "id"))
             (secret (first-file-id (add-file "admin:ada" "admin_note" admins))))
        (is (file-octets-as "admin:ada" secret))
        (is (equal (list nil "not_found" (format nil "Could not find the file ~a" secret))
                   (multiple-value-list (file-octets-as "employee:anna" secret)))
            "a record the caller may not read, as /files/ID answers 404"))
      (let* ((class (find-class 'file-note))
             (option (entity-attachments class)))
        (unwind-protect
             (progn (setf (entity-attachments class) nil)
                    (is (equal "not_found" (nth-value 1 (file-octets-as "admin:ada" file)))))
          (setf (entity-attachments class) option))))))

(test file-octets-keeps-to-the-record-policy-on-postgres
  (if (postgres-available-p)
      (with-test-app (:db (scratch-postgres "mail-files"))
        (let* ((karis (jget (call-ok "own_notes_create" "employee:kari" "title" "Karis") "id"))
               (file (first-file-id (add-file "employee:kari" "own_note" karis))))
          (is (file-octets-as "employee:kari" file))
          (is (equal "not_found" (nth-value 1 (file-octets-as "employee:ola" file))))
          (is (equal "not_found" (nth-value 1 (send-files "employee:ola" file)))
              "nor may Ola mail it")))
      (skip "no Postgres: run the suite under bin/with-postgres with TUN_TEST_POSTGRES set")))

(test a-module-reaches-mail-and-files-through-tun-core
  (dolist (name '("SEND-MAIL" "RENDER-MAIL" "ATTACH-FILES" "ATTACHMENTS-OF" "FILE-OCTETS"))
    (multiple-value-bind (symbol status) (find-symbol name "TUN.CORE")
      (is (eq :external status) "~a is external in TUN.CORE" name)
      (is (eq symbol (find-symbol name "TUN")) "and the same symbol a client calls"))))
