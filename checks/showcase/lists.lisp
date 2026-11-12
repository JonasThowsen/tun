;;;; lists.lisp -- /cards, the cards as a list with its toolbar (spec/ui.md 6,
;;;; list-toolbar): a search and a filter of each kind, applied on the
;;;; server from the address.

(in-package #:showcase)

(defun card-files-p (card)
  "Whether CARD, a card's JSON, has files attached."
  (plusp (length (jget (web-call "attachments_list"
                                 (jobj "entity" "card" "record_id" (jget card "id")))
                       "items" #()))))

(defun card-matches-p (card query)
  "Whether CARD is in the list the toolbar's address QUERY asks for."
  (let ((text (first (query-values query "q")))
        (statuses (query-values query "status"))
        (estimate (first (query-values query "estimate")))
        (files (query-values query "files")))
    (and (or (null text) (search (string-downcase text) (string-downcase (jget card "title"))))
         (or (null statuses) (member (jget card "status") statuses :test #'equal))
         (or (null estimate)
             (eq (integerp (jget card "estimate_minor")) (equal estimate "with")))
         (or (null files) (card-files-p card)))))

(defun cards-toolbar (query)
  "The toolbar of /cards, as QUERY has it."
  (ui:list-toolbar (:action "/cards" :id "cards-toolbar"
                    :search (list :name "q" :label (tr "Search the cards")
                                  :value (first (query-values query "q")))
                    :filters (list (list :name "status" :label (tr "Status") :kind :several
                                         :choices (mapcar (lambda (key)
                                                            (list key (column-title key)))
                                                          +columns+)
                                         :value (query-values query "status"))
                                   (list :name "estimate" :label (tr "Estimate") :kind :one
                                         :choices (list (list "with" (tr "With an estimate"))
                                                        (list "without" (tr "Without an estimate")))
                                         :value (first (query-values query "estimate")))
                                   (list :name "files" :label (tr "With files") :kind :toggle
                                         :value (and (query-values query "files") t))))))

(defun cards-table (cards)
  (ui:table (:caption (tr "Cards") :caption-hidden t
             :columns (list (tr "Title") (tr "Status") (list (tr "Estimate") :width :min))
             :rows (mapcar (lambda (card)
                             (let ((estimate (jget card "estimate_minor")))
                               (list (jget card "title") (column-title (jget card "status"))
                                     (if (integerp estimate) (money-text estimate) ""))))
                           cards)
             :row-href (mapcar (lambda (card) (format nil "/items/~a" (jget card "id"))) cards))))

(define-page cards-list-page ("cards" :title "Cards" :icon :funnel :policy :employee)
    (method path form query)
  (declare (ignore form))
  (if (or path (eq method :post))
      (values 404 (tr "Cards") (list (ui:alert (:variant :warning :title (tr "Page not found")))))
      (let ((cards (remove-if-not (lambda (card) (card-matches-p card query))
                                  (coerce (jget (web-call "cards_list" (jobj)) "items") 'list))))
        (values 200 (tr "Cards")
                (list (ui:stack (:gap :md)
                        (cards-toolbar query)
                        (if cards
                            (cards-table cards)
                            (ui:empty-state (:icon :search :title (tr "No card matches"))))))))))
