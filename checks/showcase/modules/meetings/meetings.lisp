;;;; checks/showcase/modules/meetings/meetings.lisp -- the showcase's module
;;;; meetings: a meeting with a customer, served as a generated resource,
;;;; so its form's customer field and its list's customer filter are the
;;;; generated pages' choice of a record (spec/ui.md 8, «Choosing a
;;;; record»).  It is a module because only a module registers a resource.

(defpackage #:tun.meetings
  (:use #:cl #:tun.core)
  (:export #:meeting #:meeting-name #:meeting-customer #:meeting-day
           #:meetings-create #:meetings-get #:meetings-list))

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
   (day :type date :label "Day")))

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

(tun.web:register-web-resource :path "/meetings" :entity 'meeting :title "Meetings"
                               :icon :calendar
                               :list-tool "meetings_list" :create-tool "meetings_create"
                               :get-tool "meetings_get" :list-screen :meeting-list
                               :detail-screen :meeting-detail :detail-key :meeting)

(publish '(meeting meeting-name meeting-customer meeting-day
           meetings-create meetings-get meetings-list))

(seal-module "meetings")
