;;;; i18n/nb-pdf.lisp -- Norwegian (bokmål) translations of PDFs: the page
;;;; numbers and the refusals of a document (spec/i18n.md 3.2, spec/pdf.md).
;;;;
;;;; The refusals a document shares with a mail's tree are in nb-mail.lisp.

(in-package #:tun.core)

(define-translations "nb"
  ("Page ~a of ~a"
   "Side ~a av ~a")
  ("The PDF could not be made."
   "PDF-en kunne ikke lages.")
  ("is :a4 or :letter"
   "er :a4 eller :letter")
  ("are millimetres from ~d to ~d: one number, or a list of four"
   "er millimeter fra ~d til ~d: ett tall, eller en liste med fire")
  ("a document cannot hold more than ~d elements"
   "et dokument kan ikke ha mer enn ~d elementer")
  ("a document cannot hold more than ~d characters of text"
   "et dokument kan ikke ha mer enn ~d tegn tekst")
  ("a document cannot be deeper than ~d levels"
   "et dokument kan ikke være dypere enn ~d nivåer")
  ("href on <a> cannot hold spaces, control characters or \\ in a PDF: “~a”"
   "href på <a> kan ikke ha mellomrom, kontrolltegn eller \\ i en PDF: «~a»")
  ("the style “~a” cannot be used in a PDF"
   "stilen «~a» kan ikke brukes i en PDF")
  ("the value “~a” for ~(~a~) cannot be used in a PDF"
   "verdien «~a» for ~(~a~) kan ikke brukes i en PDF")
  ("the attribute ~a cannot be used on <~a> in a PDF"
   "attributtet ~a kan ikke brukes på <~a> i en PDF")
  ("<img> cannot be used in a PDF yet"
   "<img> kan ikke brukes i en PDF ennå")
  ("<~a> cannot be used in a PDF"
   "<~a> kan ikke brukes i en PDF")
  ("<~a> holds <li> items, not “~a”"
   "<~a> har <li>-punkter, ikke «~a»")
  ("<tr> holds <th> and <td> cells, not “~a”"
   "<tr> har <th>- og <td>-celler, ikke «~a»")
  ("<~a> holds rows, not “~a”"
   "<~a> har rader, ikke «~a»"))
