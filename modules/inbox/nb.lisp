;;;; nb.lisp -- Norwegian (bokmål) translations of the inbox module: its
;;;; tools and refusals, the notes and notifications it stores, the public
;;;; feedback page and the staff pages (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.inbox)

(define-translations "nb"
  ;; The inquiry and its stored words
  ("Inquiry"
   "Henvendelse")
  ("Contact form"
   "Kontaktskjema")
  ("Feedback"
   "Tilbakemelding")
  ("New"
   "Ny")
  ("Handled"
   "Behandlet")
  ("Dismissed"
   "Avvist")
  ("Reference"
   "Referanse")
  ("Quote"
   "Tilbud")
  ("Convert"
   "Konverter")
  ("Attach"
   "Knytt til")
  ("Dismiss"
   "Avvis")
  ("Authenticates inbound email."
   "Autentiserer innkommende e-post.")
  ("Sender's name"
   "Avsenders navn")
  ("Sender's email"
   "Avsenders e-post")
  ("Message reference"
   "Meldingsreferanse")
  ("Matched by"
   "Koblet via")
  ("Draft order"
   "Ordreutkast")
  ("Questions"
   "Spørsmål")
  ("Consents to marketing"
   "Samtykker til markedsføring")
  ("Handled by"
   "Behandlet av")

  ;; Tools, refusals, and what intake stores for people
  ("Receive an email"
   "Motta e-post")
  ("Contact us"
   "Kontakt oss")
  ("Inquiries"
   "Henvendelser")
  ("Read an inquiry"
   "Hent henvendelse")
  ("Handle an inquiry"
   "Behandle henvendelse")
  ("consent must be given"
   "samtykke må gis")
  ("~a~@[~%Date: ~a~]~@[~%Guests: ~d~]"
   "~a~@[~%Dato: ~a~]~@[~%Gjester: ~d~]")
  ("request_defaults refused the draft"
   "request_defaults avviste utkastet")
  ("draft not created: ~a"
   "utkast ikke opprettet: ~a")
  ("the customer has replied"
   "kunden har svart")
  ("The customer has replied to order ~a."
   "Kunden har svart på ordre ~a.")
  ("You have a new inquiry."
   "Du har fått en ny henvendelse.")
  ("The inquiry has already been handled"
   "Henvendelsen er allerede behandlet")
  ("Give an order"
   "Oppgi ordre")
  ("The inquiry already has an order"
   "Henvendelsen har allerede en ordre")

  ;; The public feedback page
  ("What do you think?"
   "Hva tenker du?")
  ("Your feedback"
   "Tilbakemeldingen din")
  ("Praise, criticism or anything we should know for next time."
   "Ros, ris eller noe vi bør vite til neste gang.")
  ("Send"
   "Send")
  ("Page not found"
   "Siden finnes ikke")
  ("Check the link in the email."
   "Kontroller lenken i e-posten.")
  ("Write a message."
   "Skriv en melding.")
  ("The message is too long"
   "Meldingen er for lang")
  ("Thank you for your feedback!"
   "Takk for tilbakemeldingen!")

  ;; The staff pages
  (("Subject" :context "email")
   "Emne")
  ("From"
   "Fra")
  ("Received"
   "Mottatt")
  ("No inquiries"
   "Ingen henvendelser")
  ("Email from customers arrives here."
   "E-post fra kunder kommer hit.")
  ("Filter"
   "Filtrer")
  ("Questions for the customer"
   "Spørsmål til kunden")
  ("Handle the inquiry"
   "Behandle henvendelsen")
  ("Create a draft order"
   "Opprett ordreutkast")
  ("Attach to an order"
   "Knytt til ordre")
  ("Only when the inquiry is attached to an order."
   "Bare når henvendelsen knyttes til en ordre.")
  ("Handle"
   "Behandle"))
