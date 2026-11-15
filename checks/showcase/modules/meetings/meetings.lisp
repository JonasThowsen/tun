;;;; checks/showcase/modules/meetings/meetings.lisp -- the showcase's module
;;;; meetings: a meeting with a customer, served as a generated resource,
;;;; so its form's customer field and its list's customer filter are the
;;;; generated pages' choice of a record (spec/ui.md 8, «Choosing a
;;;; record»), and its record's actions ask for confirmation in the confirm
;;;; dialog (spec/ui.md 8, «A record's action that asks first»).  It is a
;;;; module because only a module registers a resource.

(defpackage #:tun.meetings
  (:use #:cl #:tun.core)
  (:export #:meeting #:meeting-name #:meeting-customer #:meeting-day #:meeting-status
           #:meetings-create #:meetings-get #:meetings-list #:meetings-hold
           #:meetings-cancel))

(in-package #:tun.meetings)

(declaim (optimize (safety 3) (debug 2)))

(define-module meetings
  (:core ">= 2.35.0" "< 3.0")
  (:depends-on customers)
  (:documentation "Meetings: a meeting with a customer, on a day."))

(define-entity meeting (:label "Meeting" :id-prefix "mtg" :table "meetings")
  ((name :type (string :min 1 :max 120) :required t :label "Title")
   (customer :type (id tun.customers:customer) :required t :label "Customer"
             :description "The customer the meeting is with.")
   (day :type date :label "Day")
   (status :type (enum "planned" "held" "cancelled") :input nil :initform "planned"
           :label "Status")))

(define-operation meetings-create ((:draft meeting))
    (:entity meeting :kind :create :title "Create meeting"
     :description "Records a meeting with a customer.")
  (insert meeting))

(define-operation meetings-get ((id :type (id meeting) :required t :label "Meeting"))
    (:entity meeting :kind :read :title "Get meeting"
     :description "Gets one meeting by id.")
  (fetch! 'meeting id))

(define-operation meetings-list ((customer :type (id tun.customers:customer) :label "Customer")
                                 (limit :type (integer :min 1 :max 100) :default 100
                                        :label "Most results"))
    (:entity meeting :kind :read :title "List meetings"
     :description "Lists meetings, oldest first, those with CUSTOMER alone when it is given.")
  (page (select 'meeting :where (and customer `(:= "customer" ,customer)) :limit (1+ limit))
        limit))

;;; Two record actions that ask first: one plain, one drawn as a warning
;;; (a tool ending in _cancel ends something).

(defun planned-meeting (id)
  "The meeting ID, refused unless it is still planned."
  (let ((meeting (fetch! 'meeting id)))
    (unless (string= (meeting-status meeting) "planned")
      (fail :invalid-transition "The meeting is ~a, not planned" (meeting-status meeting)))
    meeting))

(defun hold-summary ()
  (let ((meeting (fetch! 'meeting (input-value :id))))
    (tr "Mark «~a» as held." (meeting-name meeting))))

(defun cancel-summary ()
  (let ((meeting (fetch! 'meeting (input-value :id))))
    (tr "Cancel «~a». It stays in the list as cancelled." (meeting-name meeting))))

(define-operation meetings-hold ((id :type (id meeting) :required t :label "Meeting"))
    (:entity meeting :kind :transition :confirm t :title "Mark as held"
     :summary hold-summary
     :description "planned → held. Needs confirmation.")
  (let ((meeting (planned-meeting id)))
    (setf (meeting-status meeting) "held")
    (save meeting)))

(define-operation meetings-cancel ((id :type (id meeting) :required t :label "Meeting"))
    (:entity meeting :kind :transition :confirm t :title "Cancel the meeting"
     :summary cancel-summary
     :description "planned → cancelled. Needs confirmation.")
  (let ((meeting (planned-meeting id)))
    (setf (meeting-status meeting) "cancelled")
    (save meeting)))

(tun.web:register-web-resource :path "/meetings" :entity 'meeting :title "Meetings"
                               :icon :calendar
                               :list-tool "meetings_list" :create-tool "meetings_create"
                               :get-tool "meetings_get" :list-screen :meeting-list
                               :detail-screen :meeting-detail :detail-key :meeting)

(publish '(meeting meeting-name meeting-customer meeting-day meeting-status
           meetings-create meetings-get meetings-list meetings-hold meetings-cancel))

(seal-module "meetings")
