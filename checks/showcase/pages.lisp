;;;; pages.lisp -- the board page, shaped as a work tracker's /items: a page header
;;;; with icon buttons, tabs above, and a board that fills the screen, whose
;;;; cards are in an order a person sets; and /board, the same cards on a
;;;; board that only moves them between columns (spec/ui.md 6.1); a card's page
;;;; with its files, «New item», and /attachments, every card's files
;;;; (spec/files.md 6).

(in-package #:showcase)

(defun board-card (card)
  "CARD, a card's JSON, as the board shows it: its title, linked to its page,
the date it was reported on and its estimate, in the tenant's language."
  (let* ((id (jget card "id"))
         (reported-on (jget card "reported_on"))
         (estimate (jget card "estimate_minor"))
         (facts (remove nil (list (and (stringp reported-on) (date-text reported-on))
                                  (and (integerp estimate) (money-text estimate))))))
    (list :id id :title (jget card "title") :href (format nil "/items/~a" id)
          :meta (and facts (format nil "~{~a~^ · ~}" facts)))))

(defun board (&key message (ordered t))
  "The board of every card, by status, in their order, with MESSAGE above
it.  ORDERED NIL gives the board at /board, which only moves cards between
columns."
  (let ((cards (coerce (jget (web-call "cards_list" (jobj)) "items") 'list)))
    (ui:board* (list :id (if ordered "items" "board") :label (tr "Items by status")
                     :action (if ordered "/items/move" "/board/move") :ordered ordered
                     :message message
                     :columns (loop for key in +columns+
                                    collect (list :key key :title (column-title key)
                                                  :cards (mapcar #'board-card
                                                                 (column-of cards key))))))))

(defun column-of (cards status)
  "Those of CARDS, cards' JSON, whose status is STATUS, in their order."
  (remove-if-not (lambda (card) (equal (jget card "status") status)) cards))

(defun move-card (form &key (ordered t))
  "Move the card FORM names to its column, and on the ordered board before
the card before= names: answer htmx with the board, else send the browser
back to it."
  (let ((before (jget form "before"))
        (arguments (jobj "id" (jget form "card") "status" (jget form "column"))))
    (when (and (stringp before) (plusp (length before)))
      (setf (jget arguments "before") before))
    (multiple-value-bind (json code) (web-call "cards_move" arguments)
      (if (htmx-request-p)
          (values (if code 409 200) :fragment
                  (list (board :ordered ordered :message (and code (list (error-alert json))))))
          (values 303 (if ordered "/items" "/board"))))))

;;; A card's own page, with its files (spec/files.md 6), and «New item»,
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
  `(:form (:@ :method "post" :action ,(format nil "/items/~a/files" id)
              :enctype "multipart/form-data" :novalidate t)
          ,(ui:stack (:gap :md)
             (ui:file-input (:label (tr "Attach files") :name "files" :error error
                             :hint (tr "PNG, JPEG, WebP, GIF or PDF, up to 10 MB each.")))
             (ui:cluster () (ui:button (:type "submit" :icon :upload) (tr "Attach"))))))

(defun card-page (id &key error (status 200))
  "The card ID, its files and the form that adds more."
  (let ((card (web-call "cards_get" (jobj "id" id)))
        (files (jget (web-call "attachments_list" (jobj "entity" "card" "record_id" id)) "items")))
    (values status (jget card "title")
            (list (ui:card (:title (tr "Attachments"))
                    (ui:attachments (:items files))
                    (ui:button (:variant :outline :icon :upload
                                :attributes (list :command "show-modal" :commandfor "attach"))
                               (tr "Attach in a window")))
                  ;; The same files posted from a dialog, whose form takes them
                  ;; without being told to (spec/files.md 6.4).
                  (ui:dialog (:id "attach" :title (tr "Attach files")
                              :action (format nil "/items/~a/files" id)
                              :footer (list (ui:button (:type "submit") (tr "Attach"))))
                    (ui:file-input (:label (tr "Files") :name "files")))
                  (ui:card (:title (tr "Attach"))
                    (files-form id :error error))
                  `(:p ,id)
                  ;; Links a preload leaves alone (spec/ui.md 4.1).
                  `(:p (:a (:@ :href "/items" :data-tun-preload "off") ,(tr "Back to the items")))
                  `(:p (:a (:@ :href "/access" :target "_blank") ,(tr "Access in a new tab")))
                  `(:div (:@ :data-tun-preload "off")
                         (:p (:a (:@ :href "/access") ,(tr "Access")))))
            (list :breadcrumbs (list (list :label (tr "Items") :href "/items"))))))

(defun attach-to-card (id form)
  "Attach the files the form at the card ID's page sent."
  (multiple-value-bind (json code)
      (web-call "attachments_add" (jobj "entity" "card" "record_id" id
                                        "files" (or (jget form "files") (jarr '()))))
    (if code
        (card-page id :status 422 :error (or (field-message json "files")
                                             (jget (jget json "error") "message")))
        (values 303 (format nil "/items/~a" id)))))

(defun report-form (&key values json)
  "«New item»: a title and screenshots, VALUES the posted form and JSON a
refusal of it."
  `(:form (:@ :method "post" :action "/items/new" :enctype "multipart/form-data" :novalidate t)
          ,(ui:stack (:gap :lg)
             (when json (error-alert json))
             (ui:text-input (:label (tr "Title") :name "title"
                             :value (and values (jget values "title"))
                             :error (and json (field-message json "title"))))
             (ui:file-input (:label (tr "Screenshots") :name "files" :optional t
                             :hint (tr "Paste a screenshot, drag files here or choose them.")
                             :error (and json (field-message json "screenshots"))))
             (ui:cluster () (ui:button (:type "submit") (tr "Report the item"))))))

(defun report-card (form)
  "Report the card FORM describes, with its screenshots, and show it."
  (multiple-value-bind (json code)
      (web-call "cards_create" (jobj "title" (jget form "title")
                                     "screenshots" (or (jget form "files") (jarr '()))))
    (if code
        (values 422 (tr "New item") (list (report-form :values form :json json)))
        (values 303 (format nil "/items/~a" (jget json "id"))))))

(defun search-dialog ()
  "The search the header's «Search» opens, on Ctrl+K too, as a tracker's does."
  (ui:dialog (:id "search" :title (tr "Search") :shortcut "Ctrl+K" :action "/items" :method "get"
              :footer (list (ui:button (:type "submit") (tr "Search"))))
    (ui:text-input (:label (tr "Search the items") :name "q" :type :search
                    :attributes (list :autofocus t)))))

(define-page cards-page ("items" :title "Items" :icon :list-checks :policy :employee :width :wide
                                 :remembers '("p"))
    (method path form query)
  (cond ((and (eq method :post) (equal path '("move")))
         (move-card form))
        ((equal path '("new"))
         (if (eq method :post)
             (report-card form)
             (values 200 (tr "New item") (list (report-form)))))
        ((and (eq method :post) (equal (rest path) '("files")))
         (attach-to-card (first path) form))
        ((first path)
         (card-page (first path)))
        (t
         (values 200 (tr "Items")
                 (list (ui:stack (:gap :lg)
                         ;; «All» names the key, so choosing it clears the
                         ;; remembered project.
                         (ui:tabs (:label (tr "Projects")
                                   :items (let ((project (jget query "p")))
                                            (list (list :label (tr "All") :href "/items?p="
                                                        :current (not (equal project "1")))
                                                  (list :label (tr "Website") :href "/items?p=1"
                                                        :current (equal project "1"))))))
                         (board))
                       (search-dialog))
                 (list :actions (list (ui:button (:variant :outline :size :icon
                                                  :label (tr "Search")
                                                  :icon :search :shortcut "Ctrl+K"
                                                  :attributes (list :command "show-modal"
                                                                    :commandfor "search")))
                                      (ui:button (:variant :outline :size :icon
                                                  :label (tr "Filter") :icon :funnel))
                                      (ui:button (:icon :plus :href "/items/new")
                                        (tr "New item"))))))))

(define-page plain-board-page ("board" :title "Board" :icon :layout-dashboard :policy :employee
                                       :width :wide)
    (method path form query)
  (declare (ignore query))
  (if (and (eq method :post) (equal path '("move")))
      (move-card form :ordered nil)
      (values 200 (tr "Board") (list (board :ordered nil)))))

(define-page attachments-page ("attachments" :title "Attachments" :icon :file :policy :employee)
    (method path form query)
  (declare (ignore form query))
  (if (or (eq method :post) path)
      (values 404 (tr "Attachments")
              (list (ui:alert (:variant :warning :title (tr "Page not found")))))
      (values 200 (tr "Attachments")
              (or (loop for card across (jget (web-call "cards_list" (jobj)) "items")
                        for files = (jget (web-call "attachments_list"
                                                    (jobj "entity" "card"
                                                          "record_id" (jget card "id")))
                                          "items")
                        when (plusp (length files))
                          collect (ui:card (:title (jget card "title"))
                                    (ui:attachments (:items files))
                                    `(:p (:a (:@ :href ,(format nil "/items/~a" (jget card "id")))
                                             ,(tr "To the item")))))
                  (list (ui:empty-state (:title (tr "No attachments"))))))))
