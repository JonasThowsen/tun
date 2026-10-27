;;;; pages.lisp -- the board page, shaped as a work tracker's /saker: a page header
;;;; with icon buttons, tabs above, and a board that fills the screen, whose
;;;; cards are in an order a person sets; and /tavle, the same cards on a
;;;; board that only moves them between columns (spec/ui.md 6.1); a card's page
;;;; with its files, «Meld en sak», and /vedlegg, every card's files (spec/files.md 6).

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

;;; A card's own page, with its files (spec/files.md 6), and «Meld en sak»,
;;; which reports a card with its screenshots in one post.

(defun field-message (json name)
  "The message of the first field error in JSON, an error document, about
the input NAME or one of its items, or NIL."
  (let ((fields (jget (jget json "error") "fields")))
    (loop for field across (or fields #())
          for path = (jget field "field")
          when (or (equal path name)
                   (and (> (length path) (length name)) (string= name path :end2 (length name))
                        (char= #\[ (char path (length name)))))
            return (jget field "message"))))

(defun files-form (id &key error)
  "The form that adds files to the card ID."
  `(:form (:@ :method "post" :action ,(format nil "/saker/~a/filer" id)
              :enctype "multipart/form-data" :novalidate t)
          ,(ui:stack (:gap :md)
             (ui:file-input (:label "Legg ved filer" :name "filer" :error error
                             :hint "PNG, JPEG, WebP, GIF eller PDF, opptil 10 MB hver."))
             (ui:cluster () (ui:button (:type "submit" :icon :upload) "Legg ved")))))

(defun card-page (id &key error (status 200))
  "The card ID, its files and the form that adds more."
  (let ((card (web-call "cards_get" (jobj "id" id)))
        (files (jget (web-call "attachments_list" (jobj "entity" "card" "record_id" id)) "items")))
    (values status (jget card "title")
            (list (ui:card (:title "Vedlegg")
                    (ui:attachments (:items files)))
                  (ui:card (:title "Legg ved")
                    (files-form id :error error))
                  `(:p ,id)
                  ;; Links a preload leaves alone (spec/ui.md 4.1).
                  '(:p (:a (:@ :href "/saker" :data-tun-preload "off") "Til sakene"))
                  '(:p (:a (:@ :href "/access" :target "_blank") "Tilgang i en ny fane"))
                  '(:div (:@ :data-tun-preload "off")
                    (:p (:a (:@ :href "/access") "Tilgang"))))
            (list :breadcrumbs (list (list :label "Saker" :href "/saker"))))))

(defun attach-to-card (id form)
  "Attach the files the form at the card ID's page sent."
  (multiple-value-bind (json code)
      (web-call "attachments_add" (jobj "entity" "card" "record_id" id
                                        "files" (or (jget form "filer") (jarr '()))))
    (if code
        (card-page id :status 422 :error (or (field-message json "files")
                                             (jget (jget json "error") "message")))
        (values 303 (format nil "/saker/~a" id)))))

(defun report-form (&key values json)
  "«Meld en sak»: a title and screenshots, VALUES the posted form and JSON a
refusal of it."
  `(:form (:@ :method "post" :action "/saker/ny" :enctype "multipart/form-data" :novalidate t)
          ,(ui:stack (:gap :lg)
             (when json (error-alert json))
             (ui:text-input (:label "Tittel" :name "title" :value (and values (jget values "title"))
                             :error (and json (field-message json "title"))))
             (ui:file-input (:label "Skjermbilder" :name "filer" :optional t
                             :hint "Lim inn et skjermbilde, dra filer hit eller velg dem."
                             :error (and json (field-message json "screenshots"))))
             (ui:cluster () (ui:button (:type "submit") "Meld saken")))))

(defun report-card (form)
  "Report the card FORM describes, with its screenshots, and show it."
  (multiple-value-bind (json code)
      (web-call "cards_create" (jobj "title" (jget form "title")
                                     "screenshots" (or (jget form "filer") (jarr '()))))
    (if code
        (values 422 "Meld en sak" (list (report-form :values form :json json)))
        (values 303 (format nil "/saker/~a" (jget json "id"))))))

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
        ((equal path '("ny"))
         (if (eq method :post)
             (report-card form)
             (values 200 "Meld en sak" (list (report-form)))))
        ((and (eq method :post) (equal (rest path) '("filer")))
         (attach-to-card (first path) form))
        ((first path)
         (card-page (first path)))
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
                                      (ui:button (:icon :plus :href "/saker/ny")
                                        "Meld en sak")))))))

(define-page plain-board-page ("tavle" :title "Tavle" :icon :layout-dashboard :policy :employee
                                       :width :wide)
    (method path form query)
  (declare (ignore query))
  (if (and (eq method :post) (equal path '("flytt")))
      (move-card form :ordered nil)
      (values 200 "Tavle" (list (board :ordered nil)))))

(define-page attachments-page ("vedlegg" :title "Vedlegg" :icon :file :policy :employee)
    (method path form query)
  (declare (ignore form query))
  (if (or (eq method :post) path)
      (values 404 "Vedlegg" (list (ui:alert (:variant :warning :title "Fant ikke siden"))))
      (values 200 "Vedlegg"
              (or (loop for card across (jget (web-call "cards_list" (jobj)) "items")
                        for files = (jget (web-call "attachments_list"
                                                    (jobj "entity" "card"
                                                          "record_id" (jget card "id")))
                                          "items")
                        when (plusp (length files))
                          collect (ui:card (:title (jget card "title"))
                                    (ui:attachments (:items files))
                                    `(:p (:a (:@ :href ,(format nil "/saker/~a" (jget card "id")))
                                             "Til saken"))))
                  (list (ui:empty-state (:title "Ingen vedlegg")))))))
