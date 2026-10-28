;;;; modules/customers/nb.lisp -- Norwegian (bokmål) translations of the
;;;; customers module's copy (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  Texts core already translates (Customer, Name, Email,
;;;; Note, Created...) are core's.

(in-package #:tun.customers)

(define-translations "nb"
  ;; The customer
  ("Marketing consent"
   "Samtykke til markedsføring")
  ("Consent source"
   "Kilde for samtykke")
  ("Consent changed"
   "Samtykke endret")
  ("Erased"
   "Slettet")
  ("Erased at"
   "Slettet den")
  ("Manual"
   "Manuelt")
  ("Contact form"
   "Kontaktskjema")
  ("Unsubscribe"
   "Avmelding")
  ("Revision"
   "Revisjon")
  ("The customer's name (1–120 characters, trimmed)."
   "Kundens navn (1–120 tegn, trimmes).")
  ("An email address of the form name@domain.com (at most 160 characters)."
   "E-postadresse på formen navn@domene.no (høyst 160 tegn).")
  ("Phone"
   "Telefon")
  ("Stored as given."
   "Lagres slik det oppgis.")
  ("Free text about the customer (at most 500 characters)."
   "Fritekst om kunden (høyst 500 tegn).")
  ("Completed orders"
   "Fullførte ordrer")
  ("Erased customer ~a"
   "Slettet kunde ~a")
  ;; The tools and the screen
  ("Create customer"
   "Opprett kunde")
  ("Get customer"
   "Hent kunde")
  ("Search in names and email"
   "Søk i navn og e-post")
  ("List customers"
   "List kunder")
  ("Customers"
   "Kunder")
  ("Change consent"
   "Endre samtykke")
  ("Erase customer data"
   "Slett kundedata")
  ("the customer is erased"
   "kunden er slettet")
  ;; The unsubscribe page
  ("You will no longer get offers and news from us by email."
   "Du får ikke lenger tilbud og nyheter på e-post fra oss.")
  ("You will still get messages about your bookings."
   "Meldinger om bestillinger får du fortsatt.")
  ("Unsubscribe me"
   "Meld meg av")
  ("You are unsubscribed."
   "Du er avmeldt.")
  ("Page not found"
   "Siden finnes ikke")
  ("Check the link in the email."
   "Kontroller lenken i e-posten."))
