;;;; modules/reviews/reviews.lisp -- the reviews module: a generic review
;;;; workflow (README §1).
;;;;
;;;; A review asks an admin to approve or reject a proposal about a subject.
;;;; The module knows neither: subject, proposal and source are
;;;; {type, id, revision} objects, and the module that requested the review
;;;; handles its kind through two seams:
;;;;   RESOLVE-REVIEW   resolve_review   approve or reject (or report it superseded); the kind's handler
;;;;   REVIEW-DETAILS   review_details   what reviews_get adds for the kind (the order plan's diff)
;;;; Rules of the module itself: the idempotency key is unique, one pending
;;;; review per proposal, only a pending review is resolved, the resolution
;;;; and the handler's effects commit together.

(defpackage #:tun.reviews
  (:use #:cl #:tun.core)
  (:export #:review #:review-kind #:review-status #:review-priority #:review-subject #:review-proposal
           #:review-source #:review-idempotency-key #:review-title #:review-summary #:review-requested-by
           #:review-requested-at #:review-due-at #:review-reviewed-by #:review-reviewed-at #:review-note
           #:review-subject-id #:review-proposal-id
           #:request-review #:supersede-reviews #:pending-review-for #:pending-reviews-of
           #:resolve-review #:review-details
           #:reviews-list #:reviews-get #:reviews-resolve))

(in-package #:tun.reviews)

(declaim (optimize (safety 3) (debug 2)))

(define-module reviews
  (:core ">= 2.0.0" "< 3.0")
  (:documentation "Reviews: proposals an admin approves or rejects, handled per kind by the requesting module."))

(defun review-rollback-finding (review)
  "An older core without this module cannot take a pending review: nobody could resolve it."
  (and (string= (review-status review) "pending")
       "pending review, which the older core cannot resolve"))

(define-entity review (:label "Review" :id-prefix "gjg" :table "reviews"
                       :indexes (("status") ("subject_id") ("proposal_id")) :unique (("idempotency_key"))
                       :rollback-check review-rollback-finding)
  ((kind :type (string :max 100) :input nil :label "Type")
   (status :type (enum "pending" "approved" "rejected" "superseded") :input nil :initform "pending"
           :label "Status")
   (priority :type (enum "low" "normal" "high" "critical") :input nil :initform "normal"
             :label "Priority")
   (subject :type json :input nil :label "Subject" :description "{type, id, revision}")
   (proposal :type json :input nil :label "Proposal" :description "{type, id, revision}")
   (source :type json :input nil :label "Source" :description "{type, id}: what led to the proposal.")
   (idempotency-key :type (string :max 300) :input nil :label "Key")
   (title :type (string :max 300) :input nil :label "Title")
   (summary :type (string :max 1000) :input nil :label "Summary")
   (requested-by :type (string :max 200) :input nil :label "Requested by")
   (requested-at :type timestamp :input nil :label "Requested")
   (due-at :type timestamp :input nil :label "Deadline")
   (reviewed-by :type (string :max 200) :input nil :label "Handled by")
   (reviewed-at :type timestamp :input nil :label "Handled")
   (note :type (string :max 2000) :input nil :label "Note")
   ;; The subject's and proposal's ids again, as columns a query can use.
   (subject-id :type id :input nil :label "Subject (id)")
   (proposal-id :type id :input nil :label "Proposal (id)")))

(defparameter +priorities+ '("critical" "high" "normal" "low") "Most urgent first.")

;;; ------------------------------------------------------------------
;;; Seams

(defgeneric resolve-review (application review decision)
  (:method-combination traced-protocol)
  (:documentation "The handler of REVIEW's kind: DECISION is \"approve\" or \"reject\".
Values the result (\"approved\", \"rejected\" or \"superseded\") and, for a
superseded review, the reason.  An operation error (invalid_transition)
leaves the review pending.  The module that requests reviews of a kind adds
a method that handles that kind and calls the next method for any other.")
  (:method ((application reviews-module) review decision)
    (declare (ignore decision))
    (fail :invalid-transition "There is no handler for reviews of the kind ~a" (review-kind review))))

(defgeneric review-details (application review json)
  (:method-combination traced-protocol)
  (:documentation "REVIEW's JSON for reviews_get: JSON plus what the kind adds (the
order plan's diff).  A method for a kind sets its entries and calls the next method.")
  (:method ((application reviews-module) review json)
    (declare (ignore review))
    json))

(register-extension-protocol 'resolve-review "rule" :point "resolve_review"
                             :description "The handler of a review kind: approve, reject, or report it superseded.")
(register-extension-protocol 'review-details "before" :point "review_details"
                             :description "What reviews_get shows for a review kind beyond the review itself.")

;;; ------------------------------------------------------------------
;;; The interface for requesting modules

(defun pending-review-for (proposal-id)
  (select-one 'review :where `(:and (:= "proposal_id" ,proposal-id) (:= "status" "pending"))))

(defun pending-reviews-of (subject-id)
  "The pending reviews about SUBJECT-ID, oldest first."
  (select 'review :where `(:and (:= "subject_id" ,subject-id) (:= "status" "pending"))))

(defun request-review (&key kind priority subject proposal source idempotency-key title summary
                         requested-by due-at)
  "The pending review of PROPOSAL (a {type, id, revision} object), creating it
when there is none: one pending review per proposal, and an idempotency key
names at most one review (a second request with it returns that review)."
  (check-type idempotency-key string)
  (or (pending-review-for (jget proposal "id"))
      (select-one 'review :where `(:= "idempotency_key" ,idempotency-key))
      (insert (make-instance 'review :kind kind :priority (or priority "normal")
                                     :subject subject :proposal proposal :source source
                                     :subject-id (jget subject "id") :proposal-id (jget proposal "id")
                                     :idempotency-key idempotency-key :title title :summary summary
                                     :requested-by requested-by :requested-at (now) :due-at due-at))))

(defun supersede-reviews (&key proposal-id subject-id)
  "Mark the pending reviews of PROPOSAL-ID (or of anything about SUBJECT-ID) superseded."
  (dolist (review (select 'review :where `(:and (:= "status" "pending")
                                                ,(if proposal-id
                                                     `(:= "proposal_id" ,proposal-id)
                                                     `(:= "subject_id" ,subject-id)))))
    (setf (review-status review) "superseded")
    (save review)))

;;; ------------------------------------------------------------------
;;; Operations

(defun review-json (review)
  (review-details *application* review (entity->json review)))

(define-operation reviews-list ((status :type (enum "pending" "approved" "rejected" "superseded") :default "pending"
                                        :label "Status")
                                (kind :type (string :max 100) :label "Type")
                                (limit :type (integer :min 1 :max 100) :default 20 :label "Most results"))
    (:entity review :kind :read :title "Reviews"
     :description "Reviews with a status (pending by default), the most urgent first (critical, high, normal, low), then the oldest request first.")
  (let* ((where `(:and (:= "status" ,status) ,@(and kind `((:= "kind" ,kind)))))
         (rows (select 'review :where where :order-by '(("requested_at" :asc) ("seq" :asc))))
         (sorted (stable-sort rows #'< :key (lambda (r) (position (review-priority r) +priorities+ :test #'string=)))))
    (page (subseq sorted 0 (min (length sorted) (1+ limit))) limit)))

(define-operation reviews-get ((id :type (id review) :required t :label "Review ID"))
    (:entity review :kind :read :title "Get review"
     :description "One review, with what its kind shows besides (for a requirement plan: the changes article by article).")
  (review-json (fetch! 'review id)))

(define-operation reviews-resolve ((id :type (id review) :required t :label "Review ID")
                                   (decision :type (enum "approve" "reject") :required t :label "Decision")
                                   (note :type (string :max 2000) :label "Note"))
    (:entity review :kind :transition :policy :admin :title "Handle review"
     :description "Approves or rejects a pending review. The kind's handler first checks that the proposal still holds; one that is out of date gives the result superseded with a reason. Everything is stored together.")
  (lock-row 'review id)
  (let ((review (fetch! 'review id)))
    (unless (string= (review-status review) "pending")
      (fail :invalid-transition "The review has already been handled"))
    (multiple-value-bind (result reason) (resolve-review *application* review decision)
      (unless (member result '("approved" "rejected" "superseded") :test #'equal)
        (extension-error "RESOLVE-REVIEW returned ~s for a review of kind ~a" result (review-kind review)))
      (setf (review-status review) result
            (review-reviewed-by review) (actor-string *actor*)
            (review-reviewed-at review) (now)
            (review-note review) note)
      (save review)
      (when note (audit-as :reason note))
      (jobj "result" result "reason" (or reason :null) "review" (review-json review)))))

(publish '(review reviews-list reviews-get reviews-resolve))

(seal-module "reviews")
