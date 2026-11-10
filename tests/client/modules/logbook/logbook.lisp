;;;; tests/client/modules/logbook/logbook.lisp -- the test client's module
;;;; logbook: a note the staff write about anything, by its id, which the
;;;; module does not look up.

(defpackage #:tun.logbook
  (:use #:cl #:tun.core)
  (:export #:logbook-entry #:logbook-entry-subject-id #:logbook-entry-text #:logbook-entry-author
           #:logbook-add #:logbook-list))

(in-package #:tun.logbook)

(declaim (optimize (safety 3) (debug 2)))

(define-module logbook
  (:core ">= 2.19.0" "< 3.0")
  (:documentation "Logbook: notes the staff keep about anything, by its id."))

(define-entity logbook-entry (:label "Logbook entry" :id-prefix "lgb" :table "logbook_entries")
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

(publish '(logbook-add logbook-list))

(seal-module "logbook")
