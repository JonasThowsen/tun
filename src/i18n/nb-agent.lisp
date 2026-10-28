;;;; i18n/nb-agent.lisp -- Norwegian (bokmål) translations of MCP and the HTTP
;;;; API (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("The form came from another site and was refused."
   "Skjemaet kom fra et annet nettsted og ble avvist.")
  ("Without being signed in you can send at most 256 KB."
   "Uten å være logget inn kan du sende høyst 256 KB.")
  ("The form did not arrive whole. Try again."
   "Skjemaet kom ikke riktig fram. Prøv igjen.")
  ("You must be signed in to send files. Sign in and try again."
   "Du må være logget inn for å sende filer. Logg inn og prøv igjen.")
  ("This page is not for you, so it takes no files from you."
   "Denne siden er ikke for deg, så den tar ikke imot filer fra deg.")
  ("The form is too large: at most 25 MB of files at a time."
   "Skjemaet er for stort: høyst 25 MB med filer om gangen.")
  ("The server is taking many files now. Try again in a moment."
   "Serveren tar imot mange filer akkurat nå. Prøv igjen om et øyeblikk.")
  ("The form has too many fields (at most ~:d)."
   "Skjemaet har for mange felt (høyst ~,,' :d).")
  ("A field of the form is too long."
   "Et felt i skjemaet er for langt."))
