;;;; cards.lisp -- cards on a board: what the board page shows and moves.

(in-package #:showcase)

(defparameter +columns+ '(("ny" "Ny") ("planlagt" "Planlagt") ("under_arbeid" "Under arbeid")
                          ("ferdig" "Ferdig"))
  "The board's columns: each status's key and title.")

(define-entity card (:label "Kort" :id-prefix "krt" :table "cards")
  ((title :type (string :min 1 :max 200) :required t :label "Tittel")
   (status :type (enum "ny" "planlagt" "under_arbeid" "ferdig") :initform "ny" :label "Status")
   (rank :type integer :input nil :label "Rekkefølge")))

(define-operation cards-create ((:draft card))
    (:entity card :kind :create :policy :employee :title "Nytt kort"
             :description "Et kort på tavla, sist i sin kolonne.")
  (setf (card-rank card) (1+ (length (select 'card))))
  (insert card))

(define-operation cards-move ((id :type (id card) :required t :label "Kort")
                              (:field card status))
    (:entity card :kind :update :policy :employee :title "Flytt kort"
             :description "Flytter et kort til en annen kolonne.")
  (let ((card (fetch! 'card id)))
    (setf (card-status card) status)
    (save card)))

(define-operation cards-list ()
    (:entity card :kind :read :policy :employee :title "Kort"
             :description "Alle kortene, i rekkefølge.")
  (jobj "items" (jarr (mapcar #'entity->json (select 'card :order-by '(("rank" :asc)))))))
