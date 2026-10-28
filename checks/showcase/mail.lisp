;;;; mail.lisp -- the «Email» page: a summary of the cards as a mail,
;;;; built from nodes and previewed with render-mail before anything is sent
;;;; (spec/mail.md 2.1): the HTML part in a sandboxed frame, as a mail app
;;;; shows it, and the text part below it.

(in-package #:showcase)

(defparameter +summary-cards+ 5
  "The most cards the summary lists of each column; the rest are counted.")

(defun card-link (card)
  "CARD, a card's JSON, as an item of the summary: its title, linked to its page."
  `(:li (:a (:@ :href ,(format nil "/items/~a" (jget card "id"))) ,(jget card "title"))))

(defun column-section (title column)
  "The summary's nodes for the cards COLUMN of the column TITLE: a heading,
the first cards linked, and how many more there are."
  (let ((more (max 0 (- (length column) +summary-cards+))))
    `((:h2 ,(format nil "~a (~d)" title (length column)))
      (:ul ,@(mapcar #'card-link (subseq column 0 (- (length column) more))))
      ,@(when (plusp more)
          `((:p (:a (:@ :href "/items") ,(tr "… and ~d more" more))))))))

(defun summary-tree (cards)
  "A summary of CARDS, the cards' JSON, as a mail's node tree: a section per
column that has cards, each card's title a link to its page."
  `((:h1 ,(tr "Summary from the board"))
    (:p ,(tr "There are ~d cards on the board. This is where they stand:" (length cards)))
    ,@(loop for key in +columns+
            for column = (column-of cards key)
            when column
              append (column-section (column-title key) column))
    (:hr)
    (:p (:em ,(tr "Sent from the board. Reply to this email if something is wrong.")))))

(defun mail-frame (html)
  "A frame showing HTML, a mail's HTML part, as a mail app would.  Its
sandbox is empty: the mail runs nothing and reaches nothing of the page
around it.  Without a script it cannot take the mail's height, so it is
tall enough for the summary on a phone, and a person can drag it taller."
  `(:iframe (:@ :sandbox "" :srcdoc ,html :title ,(tr "Summary from the board")
                :data-mail-preview t
                :style "display: block; width: 100%; height: 60rem; border: 0; resize: vertical")))

(defun mail-parts (html text)
  "The page's two cards: the mail's HTML part in its frame, and TEXT, its text part."
  (ui:stack (:gap :lg)
    (ui:card (:title (tr "How the email looks")
              :description
              (tr "The HTML part, in a frame without scripts, as an email app shows it."))
      (mail-frame html))
    (ui:card (:title (tr "The text part")
              :description (tr "Made from the same nodes, for email apps that show text."))
      (ui:code-block (:copy nil :wrap t) text))))

(define-page mail-page ("mail" :title "Email" :icon :mail :policy :employee)
    (method path form query)
  (declare (ignore method path form query))
  (multiple-value-bind (html text)
      (render-mail (summary-tree (coerce (jget (web-call "cards_list" (jobj)) "items") 'list))
                   :subject (tr "Summary from the board"))
    (values 200 (tr "Email") (list (mail-parts html text))
            (list :description
                  (tr "The cards as an email summary, as render-mail makes it before sending.")))))
