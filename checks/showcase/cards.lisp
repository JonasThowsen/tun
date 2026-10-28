;;;; cards.lisp -- cards on a board: what the board pages show and move, in
;;;; an order a person sets within each column (spec/core.md 2.6), each with
;;;; the files attached to it (spec/files.md).

(in-package #:showcase)

(defparameter +columns+ '("new" "planned" "in_progress" "done")
  "The board's columns, by the status of the cards in them, in order.")

(define-entity card (:label "Card" :id-prefix "crd" :table "cards" :attachments (:max 20))
  ((title :type (string :min 1 :max 200) :required t :label "Title")
   (status :type (enum "new" "planned" "in_progress" "done") :initform "new" :label "Status")
   (reported-on :type date :label "Reported on")
   (estimate-minor :type money :label "Estimate"
                   :description "What the work is expected to cost.")
   (place :type (string :max 1000) :input nil :label "Place"
          :description "The rank key the card is sorted by in its column.")))

(defun column-title (status)
  "The title of the column STATUS: the status's label, in the current language."
  (princ-to-string (label "card" "status" status)))

(defun column-cards (status)
  "The cards in the column STATUS, in their order."
  (select 'card :where `(:= "status" ,status) :order-by '(("place" :asc))))

(defun place-before (card status before)
  "A rank key that puts CARD in the column STATUS directly before the card
whose id is BEFORE, or last when BEFORE is NIL.  A BEFORE that is not
another card in that column, as from a board that is out of date, is
refused."
  (let* ((others (remove (entity-id card) (column-cards status) :key #'entity-id :test #'equal))
         (below (when before (member before others :key #'entity-id :test #'equal)))
         (above (car (last (ldiff others below)))))
    (when (and before (null below))
      (fail :conflict
            "The card was not moved: the board has changed since you opened it. Reload it."))
    (rank-between (and above (card-place above)) (and below (card-place (first below))))))

(define-operation cards-create
    ((:draft card)
     (screenshots :type (files :max 10) :label "Screenshots"
                  :description
                  "Screenshots or other files that show the item: PNG, JPEG, WebP, GIF or PDF."))
    (:entity card :kind :create :policy :employee :title "New card"
             :description "A card on the board, last in its column, with the files attached.")
  (setf (card-place card) (place-before card (card-status card) nil))
  (insert card)
  (attach-files card screenshots)
  card)

(define-operation cards-get ((id :type (id card) :required t :label "Card"))
    (:entity card :kind :read :policy :employee :title "Card" :description "One card.")
  (fetch! 'card id))

(define-operation cards-move
    ((id :type (id card) :required t :label "Card")
     (:field card status)
     (before :type (id card) :label "Before the card"
             :description "The card it goes directly above; without one, it goes last."))
    (:entity card :kind :update :policy :employee :title "Move card"
             :description "Moves a card to a column, directly above another card or to the
bottom.")
  (let ((card (fetch! 'card id)))
    (setf (card-place card) (place-before card status before)
          (card-status card) status)
    (save card)))

(define-operation cards-list ()
    (:entity card :kind :read :policy :employee :title "Cards"
             :description "All the cards, in order.")
  (jobj "items" (jarr (mapcar #'entity->json (select 'card :order-by '(("place" :asc)))))))
