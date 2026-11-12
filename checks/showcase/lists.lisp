;;;; lists.lisp -- /cards, the cards as a list with its toolbar (spec/ui.md 6,
;;;; list-toolbar, table): a search and a filter of each kind, and a sort by
;;;; title or estimate, applied on the server from the address; and /days,
;;;; the cards by the day each was reported on, with a period.

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

(defun card-sort (query)
  "The sort QUERY asks for: its key, \"title\" or \"estimate\", or NIL, and its
direction, \"asc\" or \"desc\"."
  (let ((key (first (query-values query "sort")))
        (direction (first (query-values query "direction"))))
    (values (and (member key '("title" "estimate") :test #'equal) key)
            (if (equal direction "desc") "desc" "asc"))))

(defun address-text (text)
  "TEXT written for an address's query: the characters that mean something
there as %XX, the rest as they are, which the browser encodes."
  (with-output-to-string (out)
    (loop for char across text
          do (if (find char " %&+#=?/")
                 (format out "%~2,'0X" (char-code char))
                 (write-char char out)))))

(defun cards-href (query &key sort direction)
  "The address of /cards with QUERY's search and filters, every key named,
and the sort SORT in DIRECTION."
  (format nil "/cards?q=~a~{&status=~a~}&status=&estimate=~a&files=~@[true~]~@[&sort=~a~]~
~@[&direction=~a~]"
          (address-text (or (first (query-values query "q")) ""))
          (query-values query "status")
          (or (first (query-values query "estimate")) "")
          (query-values query "files")
          sort (and sort direction)))

(defun sorted-cards (cards query)
  "CARDS in the order QUERY's sort asks for, else as they come."
  (multiple-value-bind (key direction) (card-sort query)
    (let ((sorted (cond ((equal key "title")
                         (stable-sort (copy-list cards) #'string-lessp
                                      :key (lambda (card) (jget card "title"))))
                        ((equal key "estimate")
                         (stable-sort (copy-list cards) #'<
                                      :key (lambda (card)
                                             (let ((estimate (jget card "estimate_minor")))
                                               (if (integerp estimate) estimate -1)))))
                        (t cards))))
      (if (and key (equal direction "desc")) (reverse sorted) sorted))))

(defun cards-toolbar (query)
  "The toolbar of /cards, as QUERY has it, keeping its sort."
  (ui:list-toolbar (:action "/cards" :id "cards-toolbar"
                    :keep (multiple-value-bind (key direction) (card-sort query)
                            (when key (list (list "sort" key) (list "direction" direction))))
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

(defun cards-table (cards query)
  "The table of CARDS, sorted as QUERY says, its headers' links keeping the
toolbar's filters."
  (multiple-value-bind (key direction) (card-sort query)
    (flet ((sorted (name) (when (equal key name) (if (equal direction "desc") :desc :asc))))
      (ui:table (:caption (tr "Cards") :caption-hidden t
                 :columns (list (list (tr "Title") :sort "title" :sorted (sorted "title"))
                                (tr "Status")
                                (list (tr "Estimate") :width :min :align :end :sort "estimate"
                                                      :sorted (sorted "estimate")))
                 :sort-href (lambda (sort direction)
                              (cards-href query :sort sort :direction direction))
                 :rows (mapcar (lambda (card)
                                 (let ((estimate (jget card "estimate_minor")))
                                   (list (jget card "title") (column-title (jget card "status"))
                                         (if (integerp estimate) (money-text estimate) ""))))
                               cards)
                 :row-href (mapcar (lambda (card) (format nil "/items/~a" (jget card "id")))
                                   cards))))))

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
                            (cards-table (sorted-cards cards query) query)
                            (ui:empty-state (:icon :search :title (tr "No card matches"))))))))))

;;; /days: the cards by the day they were reported on, a period among the
;;; toolbar's filters (spec/ui.md 6, list-toolbar, «A period»).

(defun period-of (query)
  "The first and last day QUERY's period names, each YYYY-MM-DD or NIL, and
the messages of those it cannot read."
  (let ((dates '()) (errors '()))
    (dolist (key '("from" "to"))
      (multiple-value-bind (date problem) (read-date-text (first (query-values query key)))
        (push date dates)
        (push (and problem (princ-to-string problem)) errors)))
    (values (nreverse dates) (nreverse errors))))

(defun reported-within-p (card query)
  "Whether CARD was reported on a day of QUERY's period, and has the status
and the files QUERY asks for."
  (destructuring-bind (from to) (period-of query)
    (let ((day (jget card "reported_on"))
          (statuses (query-values query "status"))
          (text (first (query-values query "q"))))
      (and (or (null text) (search (string-downcase text) (string-downcase (jget card "title"))))
           (or (null statuses) (member (jget card "status") statuses :test #'equal))
           (or (null (query-values query "files")) (card-files-p card))
           (or (and (null from) (null to))
               (and (stringp day)
                    (or (null from) (string<= from day))
                    (or (null to) (string<= day to))))))))

(defun days-toolbar (query)
  "The toolbar of /days, as QUERY has it."
  (ui:list-toolbar (:action "/days" :id "days-toolbar"
                    :search (list :name "q" :label (tr "Search the cards")
                                  :value (first (query-values query "q")))
                    :filters (list (list :kind :period :label (tr "Reported") :names '("from" "to")
                                         :value (list (first (query-values query "from"))
                                                      (first (query-values query "to")))
                                         :errors (nth-value 1 (period-of query)))
                                   (list :name "status" :label (tr "Status") :kind :several
                                         :choices (mapcar (lambda (key)
                                                            (list key (column-title key)))
                                                          +columns+)
                                         :value (query-values query "status"))
                                   (list :name "files" :label (tr "With files") :kind :toggle
                                         :value (and (query-values query "files") t))))))

(define-page days-page ("days" :title "Days" :icon :calendar-days :policy :employee)
    (method path form query)
  (declare (ignore form))
  (if (or path (eq method :post))
      (values 404 (tr "Days") (list (ui:alert (:variant :warning :title (tr "Page not found")))))
      (let ((cards (remove-if-not (lambda (card) (reported-within-p card query))
                                  (coerce (jget (web-call "cards_list" (jobj)) "items") 'list))))
        (values 200 (tr "Days")
                (list (ui:stack (:gap :md)
                        (days-toolbar query)
                        (if cards
                            (ui:table (:caption (tr "Cards") :caption-hidden t
                                       :columns (list (tr "Title") (tr "Reported on")
                                                      (tr "Status"))
                                       :rows (mapcar (lambda (card)
                                                       (list (jget card "title")
                                                             (date-text (jget card "reported_on"))
                                                             (column-title (jget card "status"))))
                                                     cards)))
                            (ui:empty-state (:icon :search :title (tr "No card matches"))))))))))
