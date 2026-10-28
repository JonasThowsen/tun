;;;; modules/orders/plans.lisp -- requirement plans (README §9): one per order
;;;; revision of its requirements, immutable but for their status; the
;;;; activation rules of §9.2; the order_plan review kind (§9.3); explicit
;;;; correction (§9.4); and the catalog's impact on future orders through the
;;;; catalog_change workflow (§11).
;;;;
;;;; Only the active plan drives reservation, consumption and the forecast.
;;;; An order an older core wrote has no plan; until its next save it is
;;;; planned by its stored requirements (EFFECTIVE-PLAN-LINES).

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defun plan-rollback-finding (plan)
  "An older core plans requirements its own way: a plan that carries
requirements, or a proposal awaiting review, is outside what it can take."
  (cond ((string= (plan-status plan) "proposed") "proposed plan awaiting review, which the older core would drop")
        ((and (string= (plan-status plan) "active") (plusp (length (plan-lines plan))))
         "active plan with requirements, which the older core would plan its own way")))

(define-entity plan (:label "Requirement plan" :id-prefix "pln" :table "plans" :indexes (("order_id"))
                     :rollback-check plan-rollback-finding)
  ((order-id :type (id order) :input nil :label "Order")
   (revision :type integer :input nil :label "Revision")
   (status :type (enum "proposed" "active" "superseded" "rejected") :input nil :label "Status")
   (fingerprint :type (string :max 64) :input nil :label "Fingerprint")
   (activation :type (enum "automatic" "review" "correction") :input nil :label "Activation")
   (activated-at :type timestamp :input nil :label "Activated")
   (activated-by :type (string :max 200) :input nil :label "Activated by")
   (note :type (string :max 2000) :input nil :label "Note")
   (order-revision :type integer :input nil :label "Order revision")
   (lines :type json :input nil :label "Lines"
          :description "[{order_line_id, article_id, article_name, quantity, unit, sources}]")))

(define-entity plan-impact (:json-name "plan_impact" :label "Catalog impact" :id-prefix "imp"
                            :table "plan_impacts" :indexes (("order_id")))
  ((catalog-change-id :type id :input nil :label "Catalog change")
   (order-id :type (id order) :input nil :label "Order")
   (status :type (enum "pending" "applied" "proposed" "unchanged" "conflict" "corrected" "failed")
           :input nil :label "Status")
   (detail :type (string :max 2000) :input nil :label "Detail")
   (plan-revision :type integer :input nil :label "Plan revision")))

(define-entity impact-queue-entry (:json-name "plan_impact_queue" :label "Queued catalog impact" :id-prefix "ikq"
                                   :table "plan_impact_queue" :internal t :indexes (("catalog_change_id")))
  ;; An order a catalog change reached when it was made (README §11), until its
  ;; impact is recorded; ATTEMPTS counts the deadlines it ran into.
  ((catalog-change-id :type id :input nil)
   (order-id :type (id order) :input nil)
   (attempts :type integer :input nil :initform 0)))

;;; ------------------------------------------------------------------
;;; Plans

(defun order-plans (order-id)
  "ORDER-ID's plans by revision."
  (sort (select 'plan :where `(:= "order_id" ,order-id)) #'< :key #'plan-revision))

(defun active-plan (order-id)
  (select-one 'plan :where `(:and (:= "order_id" ,order-id) (:= "status" "active"))))

(defun proposed-plan (order-id)
  (select-one 'plan :where `(:and (:= "order_id" ,order-id) (:= "status" "proposed"))))

(defun plan-line-list (plan) (coerce (plan-lines plan) 'list))

(defun fingerprint-key (line)
  (format nil "~a~c~a~c~a" (jget line "order_line_id" "") #\Nul (jget line "article_id" "") #\Nul (jget line "unit" "")))

(defun lines-fingerprint (lines)
  "SHA-256 of the canonical JSON of LINES without the names (README §9.1),
over the lines sorted by order_line_id, article and unit:
the order of an order's lines is not a requirement, so reordering them (or
any edit that leaves every line's requirements as they were) is neutral."
  (canonical-json-hash
   (jarr (mapcar (lambda (line)
                   (let ((copy (json-copy line)))
                     (remhash "article_name" copy)
                     (setf (gethash "sources" copy)
                           (jarr (map 'list (lambda (source)
                                              (let ((s (json-copy source)))
                                                (remhash "requirement_name" s)
                                                (remhash "pick_name" s)
                                                s))
                                      (jget line "sources"))))
                     copy))
                 (stable-sort (copy-list (coerce lines 'list)) #'string< :key #'fingerprint-key)))))

(defun plan-lines-fingerprint (plan)
  "PLAN's fingerprint, recomputed from its lines: a plan an earlier revision
stored keeps the fingerprint of its line order, which must not count as a
change of requirements."
  (lines-fingerprint (plan-line-list plan)))

(defun effective-plan-lines (order)
  "What ORDER is planned by: its active plan's lines; for an order an older
core wrote (no plan yet), its stored requirements."
  (let ((active (and (entity-id order) (active-plan (entity-id order)))))
    (cond (active (plan-line-list active))
          ((and (entity-id order) (order-plans (entity-id order))) '())
          (t (loop for r in (order-requirements order)
                   for article-id = (or (requirement-article-id r)
                                        (let ((p (fetch 'product (requirement-product-id r))))
                                          (and p (product-article-id p))))
                   when article-id
                     collect (jobj "order_line_id" :null "article_id" article-id
                                   "quantity" (quantity-json (requirement-quantity r)) "sources" (jarr '())))))))

(defun new-plan (order lines status &key activation by order-revision note)
  (insert (make-instance 'plan :order-id (entity-id order)
                               :revision (1+ (reduce #'max (order-plans (entity-id order)) :key #'plan-revision
                                                                                           :initial-value 0))
                               :status status :fingerprint (lines-fingerprint lines)
                               :activation activation
                               :activated-at (and (string= status "active") (now))
                               :activated-by (and (string= status "active") by)
                               :note note :order-revision order-revision :lines (jarr lines))))

(defun supersede-plan (plan)
  "PLAN superseded, and any pending review of it."
  (when plan
    (setf (plan-status plan) "superseded")
    (save plan)
    (tun.reviews:supersede-reviews :proposal-id (entity-id plan))))

(defun consumption-applied-p (order)
  (and (entity-id order) (tun.inventory:consumption-applied-p (entity-id order))))

(defun days-until (date)
  "Days from today (the tenant's local date) to DATE."
  (round (- (parse-date date) (parse-date (local-today))) 86400))

(defun ensure-plan-review (order plan active source by)
  "The pending review of PLAN, requested when there is none (kind order_plan)."
  (let ((days (and (order-event-date order) (days-until (order-event-date order)))))
    (tun.reviews:request-review
     :kind "order_plan"
     :priority (cond ((null days) "normal") ((<= days 2) "critical") ((<= days 7) "high") (t "normal"))
     :subject (jobj "type" "order" "id" (entity-id order) "revision" (if active (plan-revision active) :null))
     :proposal (jobj "type" "plan" "id" (entity-id plan) "revision" (plan-revision plan))
     :source source
     :idempotency-key (format nil "order-plan:~a:~a:~a" (entity-id order) (jget source "type") (jget source "id"))
     :title (tr "Review the changed requirements of order ~a"
                (subseq (entity-id order) 0 (min 8 (length (entity-id order)))))
     :summary (tr "Requirement plan revision ~d is waiting for approval." (plan-revision plan))
     :requested-by by
     :due-at (and (order-event-date order) (date-at (order-event-date order) 9)))))

(defun decide-plan (order source by order-revision &key before)
  "The activation rules of README §9.2, in order, when ORDER's
requirements may have changed; SOURCE is {type, id}.  For an order's own
edit, BEFORE is the snapshot of the order as it was, on the current
catalog: an edit that leaves it equal is neutral and keeps the active plan
and any proposal, pending review or rejection.  Returns :unchanged, :applied
or :proposed; rule 2 (consumption applied) is invalid_input.  Leaves
ORDER's requirements those of its active plan (the caller stores ORDER)."
  (let* ((own (member (jget source "type") '("order_create" "order_update") :test #'equal))
         (lines (resolve-order order))
         (fingerprint (lines-fingerprint lines))
         (active (active-plan (entity-id order)))
         (proposed (proposed-plan (entity-id order)))
         (outcome
           (cond ((and own active before (string= fingerprint (lines-fingerprint before)))
                  :unchanged)                                        ; a neutral own edit
                 ((and active (string= fingerprint (plan-lines-fingerprint active)))
                  (supersede-plan proposed)                          ; 1
                  :unchanged)
                 ((consumption-applied-p order)                      ; 2
                  (fail :invalid-input "The order has stock consumption and needs an explicit correction"))
                 ((or (null active) (member (order-status order) +not-started-statuses+ :test #'string=)
                      own)                                           ; 3, 7
                  (supersede-plan active)
                  (supersede-plan proposed)
                  (new-plan order lines "active" :activation "automatic" :by by :order-revision order-revision)
                  :applied)
                 ((and proposed (string= fingerprint (plan-lines-fingerprint proposed))) ; 4
                  (ensure-plan-review order proposed active source by)
                  :proposed)
                 (t
                  (let ((latest (car (last (order-plans (entity-id order))))))
                    (if (and latest (string= (plan-status latest) "rejected")
                             (string= fingerprint (plan-lines-fingerprint latest)))
                        :unchanged                                   ; 5
                        (progn                                       ; 6
                          (supersede-plan proposed)
                          (ensure-plan-review order (new-plan order lines "proposed" :order-revision order-revision)
                                              active source by)
                          :proposed)))))))
    (setf (order-requirements order) (requirements-of (effective-plan-lines order)))
    outcome))

(defun store-derived (order)
  "Store ORDER's derived state (requirements) without counting a revision:
what the system does on its own (an approved plan, catalog_change) is not
an edit of the order."
  (store-update *store* order)
  order)

;;; ------------------------------------------------------------------
;;; Reservations follow the active plan (README §10.1)

(defun sync-reservations (order)
  "Only confirmed orders whose consumption is not applied reserve: their
active plan's lines, summed per article."
  (if (and (string= (order-status order) "confirmed") (not (consumption-applied-p order)))
      (tun.inventory:set-order-reservations (entity-id order) (plan-totals (effective-plan-lines order))
                                            (order-event-date order))
      (tun.inventory:release-order-reservations (entity-id order))))

;;; ------------------------------------------------------------------
;;; The state on the order (orders_get.plan)

(defun plan-impacts (order-id &optional status)
  (select 'plan-impact :where `(:and (:= "order_id" ,order-id) ,@(and status `((:= "status" ,status))))))

(defun plan-state (order)
  (let* ((id (entity-id order))
         (active (active-plan id))
         (proposed (proposed-plan id))
         (pending (first (tun.reviews:pending-reviews-of id)))
         (conflicts (plan-impacts id "conflict"))
         (consumed (consumption-applied-p order)))
    (jobj "active_revision" (if active (plan-revision active) :null)
          "proposed_revision" (if proposed (plan-revision proposed) :null)
          "pending_review_id" (if pending (entity-id pending) :null)
          "consumption_applied" (json-bool consumed)
          "correction_required" (json-bool (or conflicts (and pending consumed)))
          "conflicts" (jarr (mapcar #'entity->json conflicts)))))

(define-computed-field order plan (order) (:type json :label "Requirement plan")
  (if (entity-id order) (plan-state order) :null))

;;; ------------------------------------------------------------------
;;; The order_plan review kind (README §9.3)

(defun plan-diff (before after)
  "[{article_id, article_name, unit, before, after, change}] between plan
totals BEFORE and AFTER, unchanged articles left out, by article name."
  (let ((ids (remove-duplicates (append (mapcar #'car before) (mapcar #'car after)) :test #'string= :from-end t))
        (rows '()))
    (dolist (id ids)
      (let ((b (or (cdr (assoc id before :test #'string=)) 0))
            (a (or (cdr (assoc id after :test #'string=)) 0)))
        (unless (= a b)
          (let ((article (tun.inventory:find-article id)))
            (push (list (tun.inventory:article-name article) id
                        (jobj "article_id" id "article_name" (tun.inventory:article-name article)
                              "unit" (tun.inventory:article-unit article)
                              "before" (quantity-json b) "after" (quantity-json a)
                              "change" (cond ((zerop b) "added") ((zerop a) "removed")
                                             ((> a b) "increased") (t "decreased"))))
                  rows)))))
    (jarr (mapcar #'third (sort rows (lambda (x y) (or (string< (first x) (first y))
                                                       (and (string= (first x) (first y))
                                                            (string< (second x) (second y))))))))))

(defmethod tun.reviews:review-details ((application orders-module) review json)
  (when (string= (tun.reviews:review-kind review) "order_plan")
    (let* ((subject (tun.reviews:review-subject review))
           (before (find (jget subject "revision") (order-plans (jget subject "id")) :key #'plan-revision
                         :test #'equal))
           (after (fetch 'plan (jget (tun.reviews:review-proposal review) "id"))))
      (setf (gethash "diff" json)
            (plan-diff (plan-totals (if before (plan-line-list before) '()))
                       (plan-totals (if after (plan-line-list after) '()))))))
  (call-next-method))

(defmethod tun.reviews:resolve-review ((application orders-module) review decision)
  (if (string= (tun.reviews:review-kind review) "order_plan")
      (resolve-order-plan review decision)
      (call-next-method)))

(defun resolve-order-plan (review decision)
  "Stale checks a-e of README §9.3 (each supersedes the proposal), then reject
or approve."
  (let* ((subject (tun.reviews:review-subject review))
         (proposal (tun.reviews:review-proposal review))
         (order (find-order (jget subject "id")))
         (plan (fetch 'plan (jget proposal "id")))
         (active (active-plan (entity-id order))))
    (flet ((stale (reason)
             (when (and plan (string= (plan-status plan) "proposed"))
               (setf (plan-status plan) "superseded")
               (save plan))
             (return-from resolve-order-plan (values "superseded" reason))))
      (cond ((or (null plan) (string/= (plan-status plan) "proposed"))
             (stale (tr "The requirement proposal is no longer active")))
            ((not (eql (plan-revision plan) (jget proposal "revision")))
             (stale (tr "The requirement proposal does not match the review")))
            ((not (equal (if active (plan-revision active) :null)
                         (let ((r (jget subject "revision"))) (if (json-null-p r) :null r))))
             (stale (tr "The order has another active requirement plan now")))
            ((string/= (order-status order) "confirmed")
             (stale (tr "The order's status no longer allows approval")))
            ((string/= (lines-fingerprint (resolve-order order)) (plan-lines-fingerprint plan))
             (stale (tr "The catalog or the order has changed since the proposal"))))
      (when (string= decision "reject")
        (setf (plan-status plan) "rejected")
        (save plan)
        (return-from resolve-order-plan "rejected"))
      (when (consumption-applied-p order)
        (fail :invalid-transition "Stock consumption is already registered. Use an explicit correction from the order."))
      (when active
        (setf (plan-status active) "superseded")
        (save active))
      (setf (plan-status plan) "active"
            (plan-activation plan) "review"
            (plan-activated-at plan) (now)
            (plan-activated-by plan) (actor-string *actor*))
      (save plan)
      (setf (order-requirements order) (requirements-of (plan-line-list plan)))
      (store-derived order)
      (sync-reservations order)
      (sync-checklist order)
      "approved")))

;;; ------------------------------------------------------------------
;;; Consumption from the plan (README §10.2)

(defun effective-date (order)
  "The consumption command's date: event_date, or today when dateless."
  (or (order-event-date order) (local-today)))

(defun command-revision (order)
  "The order revision a transition's consumption command carries: the one the
transition's SAVE gives ORDER, as orders_correct_plan does.  The revision
before the save is the previous command's after a correction, and the same
revision and date with another payload is a conflict (inventory README §6)."
  (1+ (order-revision order)))

(defun consume (order)
  "Apply ORDER's active plan as consumption, once (pickup, or completion from
confirmed), before the caller saves ORDER.  insufficient_stock aborts the
caller's transaction."
  (unless (consumption-applied-p order)
    (tun.inventory:sync-consumption (entity-id order) (command-revision order) (effective-date order)
                                    (plan-totals (effective-plan-lines order)))))

(defun reverse-consumption (order)
  "Cancel or reactivate a consumed order, before the caller saves ORDER: the
sync with nothing expected (recount wins), so it is editable again (§10.2)."
  (when (consumption-applied-p order)
    (tun.inventory:sync-consumption (entity-id order) (command-revision order) (effective-date order) '())))

;;; ------------------------------------------------------------------
;;; Explicit correction (README §9.4)

(defun correction-summary ()
  (let ((order (find-order (input-value :id))))
    (tr "Correct the requirement plan of order ~a after registered stock consumption: a new plan is activated and the consumption synchronised."
        (entity-id order))))

(define-operation orders-correct-plan ((id :type (id order) :required t :label "Order ID")
                                       (note :type (string :max 2000) :label "Note"))
    (:entity order :kind :transition :confirm t :destructive t :policy :admin
     :title "Correct the requirement plan"
     :summary correction-summary
     :description "After registered stock consumption: activates the requirement plan the catalog and the order give now, synchronises the consumption and the checklist, and marks the conflicts corrected. Needs a note and confirmation; prices are not touched.")
  (let ((order (find-order id)))
    (unless (consumption-applied-p order)
      (fail :invalid-transition "There is no registered stock consumption to correct"))
    (let ((lines (resolve-order order))
          (active (active-plan id)))
      (when (and active (string= (lines-fingerprint lines) (plan-lines-fingerprint active)))
        (fail :invalid-transition "There is no new change of requirements to correct"))
      (when (blank-p note)
        (fail :invalid-input "Give a note for the correction"))
      (let ((revision (command-revision order)))
        (supersede-plan active)
        (supersede-plan (proposed-plan id))
        (tun.reviews:supersede-reviews :subject-id id)
        (let ((plan (new-plan order lines "active" :activation "correction" :by (actor-string *actor*)
                                                   :order-revision revision :note (trim note))))
          (setf (order-requirements order) (requirements-of lines))
          (tun.inventory:sync-consumption id revision (effective-date order) (plan-totals (plan-line-list plan))))
        (sync-checklist order)
        (dolist (impact (plan-impacts id))
          (when (member (plan-impact-status impact) '("conflict" "proposed") :test #'string=)
            (setf (plan-impact-status impact) "corrected"
                  (plan-impact-detail impact) (tr "The stock correction was made explicitly"))
            (save impact)))
        (audit-as :reason (trim note))
        (save order)))))

;;; ------------------------------------------------------------------
;;; Catalog impact (README §11): catalog_change

(defmethod catalog-changed ((application orders-module) change)
  (call-next-method)
  ;; The orders the change reaches now are queued in its transaction, so an
  ;; order cancelled or completed before the run still gets its impact
  ;; (unchanged, README §11).
  (dolist (order (reached-orders change (local-today)))
    (insert (make-instance 'impact-queue-entry :catalog-change-id (entity-id change) :order-id (entity-id order))))
  (tun.workflows:schedule-workflow "catalog_change" :subject-id (entity-id change) :due-at (now)))

(defun impact-detail (outcome)
  "The detail an impact of OUTCOME stores (README §11), in the current language."
  (ecase outcome
    (:applied (tr "A new requirement plan was activated automatically"))
    (:proposed (tr "A proposal was made for review"))
    (:unchanged (tr "The requirement plan was already up to date"))))

(defun line-references-p (line change)
  "True when order LINE's product, its requirements' recipes and groups, or
the line's picks name the resource CHANGE changed (README §11)."
  (let* ((product (fetch 'product (order-line-product-id line)))
         (type (catalog-change-resource-type change))
         (id (catalog-change-resource-id change))
         (targets (and product (mapcar (lambda (r) (product-requirement-target r)) (product-requirements product)))))
    (flet ((targets-p (kind target-id)
             (some (lambda (target) (and (equal kind (jget target "kind")) (equal target-id (jget target "id"))))
                   targets)))
      (cond ((null product) nil)
            ((string= type "requirement")
             (equal (catalog-change-product-id change) (entity-id product)))
            ((string= type "choice_group") (targets-p "choice_group" id))
            (t                          ; a recipe: targeted, picked, or a member of a targeted group
             (or (targets-p "recipe" id)
                 (let ((choices (order-line-choices line)))
                   (and (hash-table-p choices)
                        (some (lambda (key) (find id (jget choices key) :test #'equal)) (jkeys choices))))
                 (some (lambda (target)
                         (and (equal "choice_group" (jget target "kind"))
                              (let ((group (fetch 'choice-group (jget target "id"))))
                                (and group (member id (choice-group-members group) :test #'equal)))))
                       targets)))))))

(defparameter +impact-attempts+ 3
  "Deadlines one order's impact may run into before it is failed (README §11).")

(defun impact-failed-detail ()
  ;; Never an exception's text in an impact (README §11): a fixed message and
  ;; the request, where introspect_request has the rest.
  (tr "The impact could not be computed; see request ~a" *request-id*))

(defun impact-eligible-p (order today)
  "Whether ORDER is one a catalog change reaches (README §11): still to be
delivered (not started, or confirmed) and dated TODAY or later."
  (and (member (order-status order) +calendar-active-statuses+ :test #'string=)
       (order-event-date order)
       (date<= today (order-event-date order))))

(defun reached-orders (change today)
  "The orders CHANGE reaches as of TODAY: eligible, with a line that references it."
  (remove-if-not (lambda (order) (some (lambda (line) (line-references-p line change)) (order-lines order)))
                 (select 'order :where `(:and (:in "status" ,+calendar-active-statuses+)
                                              (:not-null "event_date")
                                              (:>= "event_date" ,today)))))

(defun queued-entry (order-id change-id)
  (select-one 'impact-queue-entry :where `(:and (:= "catalog_change_id" ,change-id) (:= "order_id" ,order-id))))

(defun impact-of (order-id change-id)
  (select-one 'plan-impact :where `(:and (:= "order_id" ,order-id) (:= "catalog_change_id" ,change-id))))

(defun record-impact (change-id order-id status detail revision)
  "Record ORDER-ID's impact of the change, which takes it off the queue."
  (let ((entry (queued-entry order-id change-id)))
    (when entry (delete-entity entry)))
  (insert (make-instance 'plan-impact :catalog-change-id change-id :order-id order-id
                                      :status status :detail detail :plan-revision revision)))

(defun catalog-impact (order-id change-id today)
  "Run README §9.2 for ORDER-ID with the catalog change as source, committed in its
own transaction under its own deadline: one order's conflict or failure
never blocks the others.  The order is read again at its turn (README §11):
one cancelled, completed or moved to the past since the change was made
gets impact unchanged.  A deadline is signalled to the caller."
  (handler-case
      (let ((*deadline* nil))
        (with-deadline ()
          (with-transaction (:write)
            (let ((order (fetch 'order order-id)))
              (cond ((or (null order) (impact-of order-id change-id))
                     (let ((entry (queued-entry order-id change-id)))
                       (when entry (delete-entity entry))))
                    ((not (impact-eligible-p order today))
                     (record-impact change-id order-id "unchanged" (impact-detail :unchanged) nil))
                    (t
                     (let* ((outcome (decide-plan order (jobj "type" "catalog_change" "id" change-id)
                                                  (actor-string *actor*) (order-revision order)))
                            (plan (if (eq outcome :proposed) (proposed-plan order-id) (active-plan order-id))))
                       (store-derived order)
                       (when (eq outcome :applied)
                         (sync-reservations order)
                         (sync-checklist order))
                       (record-impact change-id order-id (string-downcase (symbol-name outcome))
                                      (impact-detail outcome) (and plan (plan-revision plan))))))))))
    (operation-error (e)
      (with-transaction (:write)
        (record-impact change-id order-id "conflict" (operation-error-message e) nil)))
    (deadline-exceeded (e) (error e))
    (error ()
      (with-transaction (:write)
        (record-impact change-id order-id "failed" (impact-failed-detail) nil)))))

(defun note-impact-deadline (order-id change-id)
  "ORDER-ID ran into its deadline once more: counted on its queue entry; the
third time its impact is failed (README §11).  True when it is to be tried
again."
  (with-transaction (:write)
    (let ((entry (or (queued-entry order-id change-id)
                     (insert (make-instance 'impact-queue-entry :catalog-change-id change-id :order-id order-id)))))
      (setf (impact-queue-entry-attempts entry) (1+ (impact-queue-entry-attempts entry)))
      (cond ((>= (impact-queue-entry-attempts entry) +impact-attempts+)
             (record-impact change-id order-id "failed" (impact-failed-detail) nil)
             nil)
            (t (save entry) t)))))

(define-workflow catalog-change-workflow (:kind "catalog_change" :label "Catalog change" :own-transactions t) (wf)
  ;; One change per run (README §11): the orders the change reached when it was
  ;; made (queued then), and any order it reaches now, each in its own
  ;; transaction, read again at its turn; past, dateless and
  ;; closed orders are left alone.  Pending runs read the current catalog:
  ;; the first applies every change.  An order that runs into its deadline
  ;; is tried again in the next pass, after the others, and failed the third
  ;; time; the run goes on with the others.  A pass longer than one deadline
  ;; leaves the rest to the next pass (a new run of the change).
  (let* ((today (local-today))
         (change-id (tun.workflows:workflow-subject-id wf))
         (change (with-transaction (:read) (fetch 'catalog-change change-id)))
         (ids (and change
                   (with-transaction (:read)
                     (let ((queued (mapcar #'impact-queue-entry-order-id
                                           (stable-sort (select 'impact-queue-entry
                                                                :where `(:= "catalog_change_id" ,change-id))
                                                        #'< :key #'impact-queue-entry-attempts))))
                       (append queued
                               (loop for order in (reached-orders change today)
                                     unless (or (member (entity-id order) queued :test #'string=)
                                                (impact-of (entity-id order) change-id))
                                       collect (entity-id order)))))))
         (pass-ends (+ (get-internal-real-time) (round (* *deadline-ms* internal-time-units-per-second) 1000)))
         (again nil))
    (loop for (order-id . rest) on ids
          do (handler-case (catalog-impact order-id change-id today)
               (deadline-exceeded ()
                 (when (note-impact-deadline order-id change-id)
                   (setf again t))))
             (when (and rest (> (get-internal-real-time) pass-ends))
               (setf again t)
               (loop-finish)))
    (when again
      (with-transaction (:write)
        (tun.workflows:schedule-workflow "catalog_change" :subject-id change-id :due-at (1+ (now)))))))

;;; ------------------------------------------------------------------
;;; Reads

(define-operation plans-list ((order-id :type (id order) :required t :label "Order ID")
                              (limit :type (integer :min 1 :max 100) :default 20 :label "Most results"))
    (:entity plan :kind :read :title "Requirement plans"
     :description "The order's requirement plans, newest revision first.")
  (find-order order-id)
  (page (reverse (order-plans order-id)) limit))

(define-operation plans-get ((id :type (id plan) :required t :label "Plan ID"))
    (:entity plan :kind :read :title "Get a requirement plan"
     :description "One requirement plan with its lines and sources.")
  (or (fetch 'plan id) (fail :not-found "No requirement plan has the id ~a" id)))

(define-operation plan-impacts-list ((order-id :type (id order) :required t :label "Order ID")
                                     (limit :type (integer :min 1 :max 100) :default 20 :label "Most results"))
    (:entity plan-impact :kind :read :title "Catalog impacts"
     :description "What catalog changes did to the order's requirement plan, oldest first.")
  (find-order order-id)
  (page (select 'plan-impact :where `(:= "order_id" ,order-id) :limit (1+ limit)) limit))
