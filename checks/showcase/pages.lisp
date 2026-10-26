;;;; pages.lisp -- the board page, shaped as a work tracker's /saker: a page header
;;;; with icon buttons, tabs above, and a board that fills the screen, whose
;;;; cards are in an order a person sets; and /tavle, the same cards on a
;;;; board that only moves them between columns (spec/ui.md 6.1).

(in-package #:showcase)

(defun board-card (card)
  "CARD, a card's JSON, as the board shows it."
  (let ((id (jget card "id")))
    (list :id id :title (jget card "title") :href (format nil "/saker/~a" id)
          :meta "Kari · 21.10.2026")))

(defun board (&key message (ordered t))
  "The board of every card, by status, in their order, with MESSAGE above
it.  ORDERED NIL gives the board at /tavle, which only moves cards between
columns."
  (let ((cards (coerce (jget (web-call "cards_list" (jobj)) "items") 'list)))
    (ui:board* (list :id (if ordered "saker" "tavle") :label "Saker etter status"
                     :action (if ordered "/saker/flytt" "/tavle/flytt") :ordered ordered
                     :message message
                     :columns (loop for (key title) in +columns+
                                    collect (list :key key :title title
                                                  :cards (loop for card in cards
                                                               when (equal (jget card "status") key)
                                                                 collect (board-card card))))))))

(defun move-card (form &key (ordered t))
  "Move the card FORM names to its column, and on the ordered board before
the card before= names: answer htmx with the board, else send the browser
back to it."
  (let* ((before (jget form "before"))
         (arguments (if (and (stringp before) (plusp (length before)))
                        (jobj "id" (jget form "card") "status" (jget form "column") "before" before)
                        (jobj "id" (jget form "card") "status" (jget form "column")))))
    (multiple-value-bind (json code) (web-call "cards_move" arguments)
      (if (htmx-request-p)
          (values (if code 409 200) :fragment
                  (list (board :ordered ordered :message (and code (list (error-alert json))))))
          (values 303 (if ordered "/saker" "/tavle"))))))

(defun search-dialog ()
  "The search the header's «Søk» opens, on Ctrl+K too, as a tracker's does."
  (ui:dialog (:id "sok" :title "Søk" :shortcut "Ctrl+K" :action "/saker" :method "get"
              :footer (list (ui:button (:type "submit") "Søk")))
    (ui:text-input (:label "Søk etter saker" :name "q" :type :search
                    :attributes (list :autofocus t)))))

(define-page cards-page ("saker" :title "Saker" :icon :list-checks :policy :employee :width :wide
                                 :remembers '("p"))
    (method path form query)
  (cond ((and (eq method :post) (equal path '("flytt")))
         (move-card form))
        ((first path)
         (values 200 "Kort"
                 (list `(:p ,(first path))
                       ;; Links a preload leaves alone (spec/ui.md 4.1).
                       '(:p (:a (:@ :href "/saker" :data-tun-preload "off") "Til sakene"))
                       '(:p (:a (:@ :href "/access" :target "_blank") "Tilgang i en ny fane"))
                       '(:div (:@ :data-tun-preload "off")
                         (:p (:a (:@ :href "/access") "Tilgang"))))))
        (t
         (values 200 "Saker"
                 (list (ui:stack (:gap :lg)
                         ;; «Alle» names the key, so choosing it clears the
                         ;; remembered project.
                         (ui:tabs (:label "Prosjekter"
                                   :items (let ((project (jget query "p")))
                                            (list (list :label "Alle" :href "/saker?p="
                                                        :current (not (equal project "1")))
                                                  (list :label "Nettside" :href "/saker?p=1"
                                                        :current (equal project "1"))))))
                         (board))
                       (search-dialog))
                 (list :actions (list (ui:button (:variant :outline :size :icon :label "Søk"
                                                  :icon :search :shortcut "Ctrl+K"
                                                  :attributes (list :command "show-modal"
                                                                    :commandfor "sok")))
                                      (ui:button (:variant :outline :size :icon :label "Filtrer"
                                                  :icon :funnel))
                                      (ui:button (:icon :plus) "Meld en sak")))))))

(define-page plain-board-page ("tavle" :title "Tavle" :icon :layout-dashboard :policy :employee
                                       :width :wide)
    (method path form query)
  (declare (ignore query))
  (if (and (eq method :post) (equal path '("flytt")))
      (move-card form :ordered nil)
      (values 200 "Tavle" (list (board :ordered nil)))))
