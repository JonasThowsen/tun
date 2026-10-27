;;;; cards.lisp -- cards on a board: what the board pages show and move, in
;;;; an order a person sets within each column (spec/core.md 2.6), each with
;;;; the files attached to it (spec/files.md).

(in-package #:showcase)

(defparameter +columns+ '(("ny" "Ny") ("planlagt" "Planlagt") ("under_arbeid" "Under arbeid")
                          ("ferdig" "Ferdig"))
  "The board's columns: each status's key and title.")

(define-entity card (:label "Kort" :id-prefix "krt" :table "cards" :attachments (:max 20))
  ((title :type (string :min 1 :max 200) :required t :label "Tittel")
   (status :type (enum "ny" "planlagt" "under_arbeid" "ferdig") :initform "ny" :label "Status")
   (place :type (string :max 1000) :input nil :label "Plass"
          :description "Rangnøkkelen kortet sorteres etter i sin kolonne.")))

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
      (fail :conflict "Kortet ble ikke flyttet: tavla er endret siden du åpnet den. ~
                       Last den inn på nytt."))
    (rank-between (and above (card-place above)) (and below (card-place (first below))))))

(define-operation cards-create ((:draft card)
                                (screenshots :type (files :max 10) :label "Skjermbilder"
                                             :description "Skjermbilder eller andre filer som viser
saken: PNG, JPEG, WebP, GIF eller PDF."))
    (:entity card :kind :create :policy :employee :title "Nytt kort"
             :description "Et kort på tavla, sist i sin kolonne, med filene som er lagt ved.")
  (setf (card-place card) (place-before card (card-status card) nil))
  (insert card)
  (attach-files card screenshots)
  card)

(define-operation cards-get ((id :type (id card) :required t :label "Kort"))
    (:entity card :kind :read :policy :employee :title "Kort" :description "Ett kort.")
  (fetch! 'card id))

(define-operation cards-move ((id :type (id card) :required t :label "Kort")
                              (:field card status)
                              (before :type (id card) :label "Før kortet"
                                      :description "Kortet det skal stå rett over; uten står
det nederst."))
    (:entity card :kind :update :policy :employee :title "Flytt kort"
             :description "Flytter et kort til en kolonne, rett over et annet kort eller nederst.")
  (let ((card (fetch! 'card id)))
    (setf (card-place card) (place-before card status before)
          (card-status card) status)
    (save card)))

(define-operation cards-list ()
    (:entity card :kind :read :policy :employee :title "Kort"
             :description "Alle kortene, i rekkefølge.")
  (jobj "items" (jarr (mapcar #'entity->json (select 'card :order-by '(("place" :asc)))))))
