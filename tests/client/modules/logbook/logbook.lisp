;;;; tests/client/modules/logbook/logbook.lisp -- the test client's module
;;;; logbook: a note the staff write about anything, by its id, which the
;;;; module does not look up, with files attached, which it mails and reads
;;;; through TUN.CORE as any module may (spec/tun-platform.md 2.3).

(defpackage #:tun.logbook
  (:use #:cl #:tun.core)
  (:export #:logbook-entry #:logbook-entry-subject-id #:logbook-entry-text #:logbook-entry-author
           #:logbook-add #:logbook-list #:logbook-attach #:logbook-mail #:logbook-file))

(in-package #:tun.logbook)

(declaim (optimize (safety 3) (debug 2)))

(define-module logbook
  (:core ">= 2.19.0" "< 3.0")
  (:documentation "Logbook: notes the staff keep about anything, by its id."))

(define-entity logbook-entry (:label "Logbook entry" :id-prefix "lgb" :table "logbook_entries"
                                     :attachments (:max 5))
  ((subject-id :type (string :min 1 :max 64) :required t :label "Subject"
               :description "The id of what the note is about, such as an order's.")
   (text :type (string :min 1 :max 500) :required t :label "Note")
   (author :type (string :max 64) :input nil :label "Written by")))

(define-operation logbook-add ((:draft logbook-entry))
    (:entity logbook-entry :kind :create :policy :employee
     :title "Add a logbook entry"
     :description "Writes a note about the subject, signed by the caller.")
  (setf (logbook-entry-author logbook-entry) (actor-name *actor*))
  (insert logbook-entry))

(define-operation logbook-list ((subject-id :type (string :min 1 :max 64) :required t :label "Subject"))
    (:entity logbook-entry :kind :read :policy :employee
     :title "List logbook entries"
     :description "The notes about the subject, oldest first.")
  (jobj "items" (jarr (mapcar #'entity->json
                              (select 'logbook-entry :where `(:= "subject_id" ,subject-id))))))

(define-operation logbook-attach ((id :type (id logbook-entry) :required t :label "Logbook entry")
                                  (files :type (files :max 5) :required t :label "Files"))
    (:entity logbook-entry :kind :update :policy :employee
     :title "Attach files to a logbook entry"
     :description "Attaches pictures or PDF to an entry.")
  (let ((entry (fetch! 'logbook-entry id)))
    (attach-files entry files)
    (jobj "files" (jarr (attachments-of entry)))))

(define-operation logbook-mail ((id :type (id logbook-entry) :required t :label "Logbook entry")
                                (to :type email :required t :label "To"))
    (:entity logbook-entry :kind :update :policy :employee
     :title "Mail a logbook entry"
     :description "Mails the entry's note with its files attached, which the module names by
their ids and never reads.")
  (let ((entry (fetch! 'logbook-entry id)))
    (jobj "mail_id" (entity-id (send-mail :to to :subject "Logbook"
                                          :text (logbook-entry-text entry)
                                          :attachments (attachments-of entry))))))

(define-operation logbook-file ((id :type (string :min 1 :max 64) :required t :label "File"))
    (:entity logbook-entry :kind :read :policy :viewer
     :title "Read a file"
     :description "A stored file's name, size and SHA-256, read from its bytes, when the
caller may see its record.")
  (multiple-value-bind (octets file) (file-octets id)
    (jobj "filename" (jget file "filename")
          "bytes" (length octets)
          "sha256" (ironclad:byte-array-to-hex-string (ironclad:digest-sequence :sha256 octets)))))

(publish '(logbook-add logbook-list logbook-attach logbook-mail logbook-file))

(seal-module "logbook")
