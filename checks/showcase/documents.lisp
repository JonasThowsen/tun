;;;; documents.lisp -- the «Document» page: the board's estimate as a
;;;; document (spec/pdf.md), its text shown with pdf-text, and its PDF made
;;;; with make-pdf in an operation that keeps it on a record of its own, so
;;;; the page links to the file, which /files/ID serves as a download
;;;; (spec/pdf.md 4).

(in-package #:showcase)

(define-entity board-document (:label "Document" :id-prefix "bdc" :table "board_documents"
                               :attachments (:max 1))
  ((title :type (string :min 1 :max 200) :required t :input nil :label "Title")
   (made-at :type timestamp :input nil :label "Made")))

(defparameter +right+ "text-align: right" "The style of a column of amounts.")

(defun estimate-row (card)
  "CARD, a card, as a line of the estimate."
  `(:tr (:td ,(card-title card))
        (:td ,(column-title (card-status card)))
        (:td ,(if (card-reported-on card) (date-text (card-reported-on card)) ""))
        (:td (:@ :style ,+right+)
             ,(if (card-estimate-minor card) (money-text (card-estimate-minor card)) "–"))))

(defun estimate-tree (cards)
  "The board's estimate of CARDS, as a document's nodes: a line a card, and
the estimates' total."
  `((:h1 ,(tr "The board's estimate"))
    (:p ,(tr "~d cards, as they stand on the board." (length cards)))
    (:table (:thead (:tr (:th ,(tr "Card")) (:th ,(tr "Column")) (:th ,(tr "Reported on"))
                         (:th (:@ :style ,+right+) ,(tr "Estimate"))))
            (:tbody ,@(mapcar #'estimate-row cards))
            (:tfoot (:tr (:td (:@ :colspan 3) (:strong ,(tr "Total")))
                         (:td (:@ :style ,+right+)
                              (:strong ,(money-text (reduce #'+ cards
                                                            :key (lambda (card)
                                                                   (or (card-estimate-minor card)
                                                                       0)))))))))))

(defun board-cards ()
  (select 'card :order-by '(("place" :asc))))

(define-operation documents-make ()
    (:entity board-document :kind :create :policy :employee :title "Make the board's PDF"
             :description "Makes the board's estimate as a PDF and keeps it as a document.")
  (let ((document (make-instance 'board-document :title (tr "The board's estimate")
                                                 :made-at (now))))
    (insert document)
    (attach-files document
                  (list (list :filename "board-estimate.pdf"
                              :content (make-pdf (estimate-tree (board-cards))
                                                 :title (tr "The board's estimate")
                                                 :footer (tr "Made by the showcase")))))
    document))

(define-operation documents-list ()
    (:entity board-document :kind :read :policy :employee :title "Documents"
             :description "The documents made, newest first, each with its file.")
  (let* ((documents (select 'board-document :order-by '(("made_at" :desc)) :limit 5))
         (files (attachments-of documents)))
    (jobj "items" (jarr (mapcar (lambda (document)
                                  (jobj "id" (entity-id document)
                                        "title" (board-document-title document)
                                        "made_at" (board-document-made-at document)
                                        "file" (let ((own (gethash (entity-id document) files)))
                                                 (if own (first own) :null))))
                                documents)))))

(define-operation documents-text ()
    (:entity board-document :kind :read :policy :employee :title "The board's document as text"
             :description "What the board's estimate says, as pdf-text gives it.")
  (jobj "text" (pdf-text (estimate-tree (board-cards)) :footer (tr "Made by the showcase"))))

(defun made-documents (items)
  "The documents made, each a link to its PDF."
  (if (zerop (length items))
      `(:p ,(tr "No PDF has been made yet."))
      `(:ul (:@ :class "documents-made")
            ,@(map 'list (lambda (item)
                           (let ((file (jget item "file")))
                             `(:li ,(if (hash-table-p file)
                                        (ui:link (:href (jget file "url")
                                                  :attributes '(:data-document-file t))
                                          (format nil "~a (~a)" (jget file "filename")
                                                  (ui:octets-text (jget file "size"))))
                                        (jget item "title")))))
                   items))))

(defun document-body (&key message)
  "The page: the document's text, the button that makes its PDF, and the
PDFs made."
  (list (ui:stack (:gap :lg)
          (ui:card (:title (tr "The board as a document")
                    :description (tr "What the PDF says, as pdf-text gives it before it is made."))
            (ui:code-block (:copy nil :wrap t) (jget (web-call "documents_text" (jobj)) "text")))
          (ui:card (:title (tr "The PDF")
                    :description (tr "Made with make-pdf and kept as a file of a document."))
            `(:form (:@ :method "post" :action "/document")
                    ,(ui:stack (:gap :md)
                       message
                       (ui:form-actions ()
                         (ui:button (:type "submit" :icon :file-text) (tr "Make the PDF")))
                       (made-documents (jget (web-call "documents_list" (jobj)) "items"))))))))

(define-page document-page ("document" :title "Document" :icon :file-text :policy :employee)
    (method path form query)
  (declare (ignore path form query))
  (if (eq method :post)
      (multiple-value-bind (json code) (web-call "documents_make" (jobj))
        (if code
            (values 422 (tr "Document") (document-body :message (error-alert json)))
            (values 303 "/document")))
      (values 200 (tr "Document") (document-body)
              (list :description (tr "The board's estimate as a PDF, made with make-pdf.")))))
