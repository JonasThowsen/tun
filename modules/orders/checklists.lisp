;;;; modules/orders/checklists.lisp -- packing checklists generated from
;;;; requirements and synchronised on every save (README §7).
;;;;
;;;; Automatic items are a pure function of (order line, the line's
;;;; requirements, order dates): one per (line, component product, unit),
;;;; keyed lager:<component>:<unit>, plus the client's rule items (seam
;;;; checklist_items, keyed client:<key>).  Synchronisation creates missing
;;;; items, updates changed ones (carrying packed quantities over, §7.3) and
;;;; deletes automatic items no longer planned; manual items are never
;;;; touched.  A sync that changes nothing stores nothing.

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defstruct (planned-item (:constructor make-planned-item (line-id key description category quantity)))
  line-id key description category quantity)

(defun checklist-plan-lines (order)
  "The requirement lines ORDER's automatic items follow: the active plan on a
started order, the fresh snapshot on a not-started one (README §7.2)."
  (let ((active (and (entity-id order) (active-plan (entity-id order)))))
    (if (or (null active) (member (order-status order) +not-started-statuses+ :test #'string=))
        (resolve-order order)
        (plan-line-list active))))

(defun planned-items (order)
  "The automatic items ORDER should have now: one per (line, article, unit),
keyed lager:<the article's product, or the article>:<unit> (README §7.2),
plus the client's rule items."
  (append
   (loop for pl in (checklist-plan-lines order)
         for article = (tun.inventory:find-article (jget pl "article_id"))
         for quantity = (line-quantity pl)
         collect (make-planned-item
                  (jget pl "order_line_id")
                  (format nil "lager:~a:~a" (tun.inventory:article-key-product article) (jget pl "unit"))
                  (format nil "~a: ~a ~a" (tun.inventory:article-name article) (format-quantity quantity)
                          (jget pl "unit"))
                  (tun.inventory:article-name article)
                  quantity))
   (loop for item in (order-checklist-items *application* order)
         collect (destructuring-bind (&key key description category (quantity 1) line-id) item
                   (make-planned-item line-id (format nil "client:~a" key) description
                                      (or category description) quantity)))))

(defun order-checklist (order-id)
  (select 'checklist-item :where `(:= "order_id" ,order-id)))

(defun carry-over (item new-quantity)
  "Set ITEM's done state for its new computed quantity (README §7.3)."
  (let ((carried (or (checklist-item-done-quantity item)
                     (and (checklist-item-done item) (checklist-item-computed-quantity item)))))
    (cond ((and (or (null carried) (zerop carried)) (not (checklist-item-done item)))
           (setf (checklist-item-done item) nil (checklist-item-done-quantity item) nil))
          ((null carried)
           (setf (checklist-item-done item) nil (checklist-item-done-quantity item) nil))
          ((> carried new-quantity)
           (setf (checklist-item-done item) nil (checklist-item-done-quantity item) carried))
          ((= carried new-quantity)
           (setf (checklist-item-done item) t (checklist-item-done-quantity item) carried))
          (t
           (setf (checklist-item-done item) nil (checklist-item-done-quantity item) carried)))))

(defun sync-checklist (order)
  "Make ORDER's automatic checklist items match the plan.  Values: created,
updated and deleted counts."
  (let* ((planned (planned-items order))
         (existing (remove "manual" (order-checklist (entity-id order))
                           :key #'checklist-item-origin :test #'string=))
         (created 0) (updated 0) (deleted 0))
    (flet ((same-slot-p (item plan)
             (and (equal (checklist-item-order-line-id item) (planned-item-line-id plan))
                  (string= (checklist-item-source-key item) (planned-item-key plan)))))
      (dolist (plan planned)
        (let ((item (find-if (lambda (i) (same-slot-p i plan)) existing)))
          (cond ((null item)
                 (insert (make-instance 'checklist-item :order-id (entity-id order)
                                                        :order-line-id (planned-item-line-id plan)
                                                        :origin "automatic" :source-key (planned-item-key plan)
                                                        :description (planned-item-description plan)
                                                        :category (planned-item-category plan)
                                                        :computed-quantity (planned-item-quantity plan)))
                 (incf created))
                ((or (string/= (checklist-item-description item) (planned-item-description plan))
                     (not (equal (checklist-item-category item) (planned-item-category plan)))
                     (not (eql (checklist-item-computed-quantity item) (planned-item-quantity plan))))
                 (unless (eql (checklist-item-computed-quantity item) (planned-item-quantity plan))
                   (carry-over item (planned-item-quantity plan)))
                 (setf (checklist-item-description item) (planned-item-description plan)
                       (checklist-item-category item) (planned-item-category plan)
                       (checklist-item-computed-quantity item) (planned-item-quantity plan))
                 (save item)
                 (incf updated)))))
      (dolist (item existing)
        (unless (find-if (lambda (plan) (same-slot-p item plan)) planned)
          (delete-entity item)
          (incf deleted))))
    (values created updated deleted)))

(defun reset-checklist (order)
  "Every item of ORDER back to not done (orders_reopen)."
  (dolist (item (order-checklist (entity-id order)))
    (when (or (checklist-item-done item) (checklist-item-done-quantity item))
      (setf (checklist-item-done item) nil (checklist-item-done-quantity item) nil)
      (save item))))

(defun order-packed-p (order)
  "Every checklist item done (vacuously true with none)."
  (or (null (entity-id order))
      (every #'checklist-item-done (order-checklist (entity-id order)))))

(defun checklist-json (order-id)
  (let ((items (order-checklist order-id)))
    (jobj "items" (jarr (mapcar #'entity->json items))
          "packed" (json-bool (every #'checklist-item-done items)))))

(defun item-order (item)
  (let ((order (find-order (checklist-item-order-id item))))
    (check-order-not-locked order)
    order))

;;; ------------------------------------------------------------------
;;; Operations

(define-operation checklists-list ((order-id :type (id order) :required t :label "Order ID"))
    (:entity checklist-item :kind :read :title "Checklist"
     :description "The order's checklist (automatic items from the requirements, and manual items) and whether everything is packed.")
  (find-order order-id)
  (checklist-json order-id))

(define-operation checklists-sync ((order-id :type (id order) :required t :label "Order ID"))
    (:entity checklist-item :kind :update :title "Synchronise the checklist"
     :description "Makes the automatic items match the requirements now: creates the missing ones, updates changed ones (packed quantities carry over), deletes those no longer needed. Manual items are not touched. No change stores nothing.")
  (let ((order (find-order order-id)))
    (check-order-not-locked order)
    (multiple-value-bind (created updated deleted) (sync-checklist order)
      (when (plusp (+ created updated deleted)) (touch-order order))
      (let ((json (checklist-json order-id)))
        (jobj "created" created "updated" updated "deleted" deleted
              "items" (jget json "items") "packed" (jget json "packed"))))))

(define-operation checklists-mark ((id :type (id checklist-item) :required t :label "Item ID")
                                   (done :type boolean :required t :label "Done")
                                   (done-quantity :type (decimal :scale 3) :label "Packed quantity"))
    (:entity checklist-item :kind :update :title "Mark a checklist item"
     :description "done true without a quantity sets the packed quantity to the computed one; done false clears it, or registers partial packing with done_quantity.")
  (let* ((item (fetch! 'checklist-item id))
         (order (item-order item)))
    (setf (checklist-item-done item) done
          (checklist-item-done-quantity item)
          (cond ((input-provided-p :done-quantity) done-quantity)
                (done (checklist-item-computed-quantity item))
                (t nil)))
    (save item)
    (touch-order order)
    item))

(define-operation checklists-add-manual ((order-id :type (id order) :required t :label "Order ID")
                                         (order-line-id :type id :label "Order line ID")
                                         (description :type (string :min 1 :max 500) :required t :label "Description")
                                         (category :type (string :max 200) :label "Category"))
    (:entity checklist-item :kind :create :title "Add a checklist item"
     :description "A manual item on the order or on one of its lines; synchronisation never touches it.")
  (let ((order (find-order order-id)))
    (check-order-not-locked order)
    (when (and order-line-id (not (find order-line-id (order-lines order) :key #'order-line-id :test #'string=)))
      (fail :invalid-input "The line ~a does not belong to order ~a" order-line-id order-id))
    (prog1 (insert (make-instance 'checklist-item :order-id order-id :order-line-id order-line-id
                                                  :origin "manual" :source-key nil
                                                  :description description :category category))
      (touch-order order))))

(define-operation checklists-delete ((id :type (id checklist-item) :required t :label "Item ID"))
    (:entity checklist-item :kind :update :title "Delete a checklist item"
     :description "Deletes a manual item (automatic items cannot be deleted; they follow the requirements).")
  (let* ((item (fetch! 'checklist-item id))
         (order (item-order item)))
    (unless (string= (checklist-item-origin item) "manual")
      (fail :invalid-input "Automatic items cannot be deleted; they follow the requirements"))
    (delete-entity item)
    (touch-order order)
    (jobj "deleted" t "id" id)))
