;;;; tests/client/modules/logbook/nb.lisp -- Norwegian (bokmål) translations
;;;; of the logbook module's copy (spec/i18n.md 3.2). Texts core already
;;;; translates (Subject, Note) are core's.

(in-package #:tun.logbook)

(define-translations "nb"
  ("Logbook entry"
   "Loggføring")
  ("The id of what the note is about, such as an order's."
   "Id-en til det notatet gjelder, som en ordres.")
  ("Written by"
   "Skrevet av")
  ("Add a logbook entry"
   "Skriv i loggboken")
  ("List logbook entries"
   "Vis loggboken"))
