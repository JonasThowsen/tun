;;;; mail.lisp -- the «E-post» page: a summary of the cards as a mail,
;;;; built from nodes and previewed with render-mail before anything is sent
;;;; (spec/mail.md 2.1): the HTML part in a sandboxed frame, as a mail app
;;;; shows it, and the text part below it.

(in-package #:showcase)

(defparameter +summary-cards+ 5
  "The most cards the summary lists of each column; the rest are counted.")

(defun card-link (card)
  "CARD, a card's JSON, as an item of the summary: its title, linked to its page."
  `(:li (:a (:@ :href ,(format nil "/saker/~a" (jget card "id"))) ,(jget card "title"))))

(defun column-section (title column)
  "The summary's nodes for the cards COLUMN of the column TITLE: a heading,
the first cards linked, and how many more there are."
  (let ((more (max 0 (- (length column) +summary-cards+))))
    `((:h2 ,(format nil "~a (~d)" title (length column)))
      (:ul ,@(mapcar #'card-link (subseq column 0 (- (length column) more))))
      ,@(when (plusp more)
          `((:p (:a (:@ :href "/saker") ,(format nil "… og ~d til" more))))))))

(defun summary-tree (cards)
  "A summary of CARDS, the cards' JSON, as a mail's node tree: a section per
column that has cards, each card's title a link to its page."
  `((:h1 "Sammendrag fra tavla")
    (:p ,(format nil "Det er ~d kort på tavla. Slik står de nå:" (length cards)))
    ,@(loop for (key title) in +columns+
            for column = (remove-if-not (lambda (card) (equal key (jget card "status"))) cards)
            when column
              append (column-section title column))
    (:hr)
    (:p (:em "Sendt fra tavla. Svar på e-posten om noe er galt."))))

(defun mail-frame (html)
  "A frame showing HTML, a mail's HTML part, as a mail app would.  Its
sandbox is empty: the mail runs nothing and reaches nothing of the page
around it.  Without a script it cannot take the mail's height, so it is
tall enough for the summary on a phone, and a person can drag it taller."
  `(:iframe (:@ :sandbox "" :srcdoc ,html :title "Sammendrag fra tavla" :data-mail-preview t
                :style "display: block; width: 100%; height: 60rem; border: 0; resize: vertical")))

(define-page mail-page ("e-post" :title "E-post" :icon :mail :policy :employee)
    (method path form query)
  (declare (ignore method path form query))
  (multiple-value-bind (html text)
      (render-mail (summary-tree (coerce (jget (web-call "cards_list" (jobj)) "items") 'list))
                   :subject "Sammendrag fra tavla")
    (values 200 "E-post"
            (list (ui:stack (:gap :lg)
                    (ui:card (:title "Slik ser e-posten ut"
                              :description "HTML-delen, i en ramme uten skript, som en
e-postapp viser den.")
                      (mail-frame html))
                    (ui:card (:title "Tekstdelen"
                              :description "Laget av de samme nodene, for e-postapper som
viser tekst.")
                      (ui:code-block (:copy nil :wrap t) text))))
            (list :description "Et sammendrag av kortene som e-post, slik render-mail
lager det før det sendes."))))
