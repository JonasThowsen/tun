;;;; modules/orders/requirements.lisp -- what an order requires from stock
;;;; (README §8): each line resolved by the catalog's resolver (or by the
;;;; requirements seam, when a client registers one: it overrides the
;;;; resolver, §8.1), aggregated per line and article into the lines of a
;;;; requirement plan, and the order's choices.

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defun order-days (order)
  "Inclusive days end_date - event_date + 1; 1 for single-day and dateless orders."
  (if (order-event-date order)
      (1+ (round (- (parse-date (order-last-date order)) (parse-date (order-event-date order))) 86400))
      1))

(defun line-servings (line)
  "LINE's servings: a client field (README §8.1); none counts as 0."
  (let ((field (find-field (class-of line) "servings")))
    (and field (field-value line field))))

(defun lite-seam-registered-p (order)
  "True when a client added a method to the requirements seam (README §8.1)."
  (rest (compute-applicable-methods #'compute-order-requirements (list *application* order))))

(defun line-entries (order line)
  "Entries (article-id quantity source) LINE of ORDER requires."
  (if (lite-seam-registered-p order)
      (let ((copy (copy-entity order)))
        (setf (order-lines copy) (list line))
        (loop for (product-id . quantity) in (compute-order-requirements *application* copy)
              for product = (fetch 'product product-id)
              for article-id = (and product (product-article-id product))
              when article-id
                collect (list article-id quantity
                              (jobj "requirement_id" :null "requirement_name" :null "recipe_id" :null
                                    "pick_name" :null "position" :null
                                    "source_key" (format nil "seam:~a" product-id)))))
      (resolve-line (order-line-product-id line) :quantity (order-line-quantity line)
                                                 :servings (line-servings line)
                                                 :choices (order-line-choices line)
                                                 :days (order-days order))))

(defconstant +max-resolved-quantity+ (expt 10 12)
  "Largest quantity one resolved requirement may come to (README §8.1).")

(defun check-resolved (article-id quantity)
  (when (> quantity +max-resolved-quantity+)
    (fail :invalid-input "The requirement for ~a comes to ~a, more than ~d; reduce the quantity, the servings or the requirement"
          (tun.inventory:article-name (tun.inventory:find-article article-id)) (format-quantity quantity)
          +max-resolved-quantity+))
  quantity)

(defun resolve-order (order)
  "ORDER's requirement snapshot: per line and article the summed quantity, with
its sources, sorted by article name then id within each line (README §8.1).
A list of JSON objects {order_line_id, article_id, article_name, quantity,
unit, sources}."
  (loop for line in (order-lines order)
        append (let ((per '()))
                 (dolist (entry (line-entries order line))
                   (destructuring-bind (article-id quantity source) entry
                     (check-resolved article-id quantity)
                     (let ((cell (assoc article-id per :test #'string=)))
                       (if cell
                           (progn (incf (second cell) quantity)
                                  (setf (third cell) (append (third cell) (list source))))
                           (setf per (append per (list (list article-id quantity (list source)))))))))
                 (let ((rows (loop for (article-id quantity sources) in per
                                   for article = (progn (check-resolved article-id quantity)
                                                        (tun.inventory:find-article article-id))
                                   when (plusp quantity)
                                     collect (list article quantity sources))))
                   (loop for (article quantity sources) in (stable-sort rows #'plan-line<
                                                                       :key #'first)
                         collect (jobj "order_line_id" (order-line-id line)
                                       "article_id" (entity-id article)
                                       "article_name" (tun.inventory:article-name article)
                                       "quantity" (quantity-json quantity)
                                       "unit" (tun.inventory:article-unit article)
                                       "sources" (jarr sources)))))))

(defun plan-line< (a b)
  "Articles by name, then id."
  (let ((na (tun.inventory:article-name a)) (nb (tun.inventory:article-name b)))
    (or (string< na nb) (and (string= na nb) (string< (entity-id a) (entity-id b))))))

(defun line-quantity (plan-line)
  (round-decimal (jget plan-line "quantity") 3))

(defun plan-totals (lines)
  "Alist article-id -> total quantity of plan LINES, in first-seen order."
  (let ((totals '()))
    (dolist (line lines (nreverse totals))
      (let ((cell (assoc (jget line "article_id") totals :test #'string=)))
        (if cell
            (incf (cdr cell) (line-quantity line))
            (push (cons (jget line "article_id") (line-quantity line)) totals))))))

(defun requirements-of (lines)
  "The order's requirements ({product_id, quantity} plus article_id, README §8.3)
from plan LINES."
  (loop for (article-id . quantity) in (plan-totals lines)
        for article = (tun.inventory:find-article article-id)
        collect (make-instance 'requirement :product-id (tun.inventory:article-key-product article)
                                            :article-id article-id :quantity quantity)))

;;; ------------------------------------------------------------------
;;; Order-line choices (README §8.2)

(defun normalised-choices (choices)
  "CHOICES as stored: NIL when empty, else an object requirement id -> recipe ids."
  (cond ((or (null choices) (json-null-p choices)) nil)
        ((not (and (hash-table-p choices)
                   (every (lambda (k) (let ((v (gethash k choices)))
                                        (and (json-array-p v) (every #'stringp v))))
                          (jkeys choices))))
         (fail :invalid-input "choices must be an object of lists of recipe ids"))
        ((zerop (hash-table-count choices)) nil)
        (t choices)))

(defun check-choices (order)
  "Every line's choices are well formed and valid for its product."
  (dolist (line (order-lines order))
    (setf (order-line-choices line) (normalised-choices (order-line-choices line)))
    (check-line-choices (order-line-product-id line) (order-line-quantity line) (line-servings line)
                        (order-line-choices line))))

(defun stamp-choices (lines old-lines)
  "Each of LINES keeps the time of its last change of choices: the old line's
when it kept its identity and its choices, else now."
  (dolist (line lines)
    (let ((old (and (order-line-id line) (find (order-line-id line) old-lines :key #'order-line-id :test #'equal)))
          (choices (normalised-choices (order-line-choices line))))
      (setf (order-line-choices-at line)
            (cond ((null choices) nil)
                  ((and old (equal (to-json-string (or (order-line-choices old) (jobj)) :canonical t)
                                   (to-json-string choices :canonical t)))
                   (order-line-choices-at old))
                  (t (now)))))))
