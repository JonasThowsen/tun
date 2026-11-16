;;;; documents.lisp -- the «Document» page: the board's estimate as a
;;;; document (spec/pdf.md), its text shown with pdf-text, and its PDF made
;;;; with make-pdf in an operation that keeps it on a record of its own, so
;;;; the page links to the file, which /files/ID serves as a download
;;;; (spec/pdf.md 4); and made on the spot and answered as a download by the
;;;; page itself, kept nowhere (spec/files.md 5.5).

(in-package #:showcase)

(define-entity board-document (:label "Document" :id-prefix "bdc" :table "board_documents"
                               :attachments (:max 1))
  ((title :type (string :min 1 :max 200) :required t :input nil :label "Title")
   (made-at :type timestamp :input nil :label "Made")))

(defparameter +right+ "text-align: right" "The style of a column of amounts.")

(defun estimate-line (card)
  "CARD, a card, as a line of the estimate: a JSON object of the texts it
shows, and its estimate."
  (jobj "title" (card-title card)
        "column" (column-title (card-status card))
        "reported_on" (if (card-reported-on card) (date-text (card-reported-on card)) "")
        "estimate_minor" (or (card-estimate-minor card) :null)))

(defun line-estimate (line)
  "The estimate of LINE, in minor units, or NIL."
  (let ((estimate (jget line "estimate_minor")))
    (and (integerp estimate) estimate)))

(defun estimate-row (line)
  "LINE, a line of the estimate, as a table's row."
  `(:tr (:td ,(jget line "title"))
        (:td ,(jget line "column"))
        (:td ,(jget line "reported_on"))
        (:td (:@ :style ,+right+)
             ,(if (line-estimate line) (money-text (line-estimate line)) "–"))))

(defun estimate-tree (lines)
  "The board's estimate of LINES, as a document's nodes: a line a card, and
the estimates' total."
  `((:h1 ,(tr "The board's estimate"))
    (:p ,(tr "~d cards, as they stand on the board." (length lines)))
    (:table (:thead (:tr (:th ,(tr "Card")) (:th ,(tr "Column")) (:th ,(tr "Reported on"))
                         (:th (:@ :style ,+right+) ,(tr "Estimate"))))
            (:tbody ,@(mapcar #'estimate-row lines))
            (:tfoot (:tr (:td (:@ :colspan 3) (:strong ,(tr "Total")))
                         (:td (:@ :style ,+right+)
                              (:strong ,(money-text (reduce #'+ lines
                                                            :key (lambda (line)
                                                                   (or (line-estimate line)
                                                                       0)))))))))))

(defun board-lines ()
  "The board's cards, in their order, as lines of the estimate."
  (mapcar #'estimate-line (select 'card :order-by '(("place" :asc)))))

(define-operation documents-estimate ()
    (:entity board-document :kind :read :policy :employee :title "The board's estimate"
             :description "The lines of the board's estimate: each card's title, column, day reported and estimate.")
  (jobj "lines" (jarr (board-lines))))

(defun board-estimate-pdf ()
  "The board's estimate as a PDF, made now from what documents_estimate reads
as the person signed in."
  (make-pdf (estimate-tree (coerce (jget (web-call "documents_estimate" (jobj)) "lines") 'list))
            :title (tr "The board's estimate")
            :footer (tr "Made by the showcase")))

(define-operation documents-make ()
    (:entity board-document :kind :create :policy :employee :title "Make the board's PDF"
             :description "Makes the board's estimate as a PDF and keeps it as a document.")
  (let ((document (make-instance 'board-document :title (tr "The board's estimate")
                                                 :made-at (now))))
    (insert document)
    (attach-files document
                  (list (list :filename "board-estimate.pdf"
                              :content (make-pdf (estimate-tree (board-lines))
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
  (jobj "text" (pdf-text (estimate-tree (board-lines)) :footer (tr "Made by the showcase"))))

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
                         (ui:button (:type "submit" :icon :file-text) (tr "Make the PDF"))
                         ;; Made for this request and answered as a download.
                         (ui:button (:href "/document/board-estimate.pdf" :variant :outline
                                     :icon :download
                                     :attributes '(:download t :hx-boost "false"
                                                   :data-document-download t))
                           (tr "Download the PDF")))
                       (made-documents (jget (web-call "documents_list" (jobj)) "items"))))))))

(define-page document-page ("document" :title "Document" :icon :file-text :policy :employee)
    (method path form query)
  (declare (ignore form query))
  (cond
    ((equal path '("board-estimate.pdf"))
     (values 200 :download (make-download (board-estimate-pdf)
                                          :filename "board-estimate.pdf"
                                          :content-type "application/pdf")))
    ((eq method :post)
     (multiple-value-bind (json code) (web-call "documents_make" (jobj))
       (if code
           (values 422 (tr "Document") (document-body :message (error-alert json)))
           (values 303 "/document"))))
    (t
     (values 200 (tr "Document") (document-body)
             (list :description (tr "The board's estimate as a PDF, made with make-pdf."))))))
