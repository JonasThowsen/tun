;;;; modules/invoicing/nb.lisp -- Norwegian (bokmål) translations of the
;;;; invoicing module's copy (spec/i18n.md 3.2).

(in-package #:tun.invoicing)

(define-translations "nb"
  ("Invoice"
   "Faktura")
  ("Invoice line"
   "Fakturalinje")
  ("Invoice ID"
   "Faktura-ID")
  ("Quantity"
   "Antall")
  ("Unit price"
   "Enhetspris")
  ("Line total"
   "Linjesum")
  ("Line total after price mode"
   "Linjesum etter prisvalg")
  ("Line adjustment"
   "Linjejustering")
  ("A copy of the customer's details when the invoice was made."
   "Kopi av kundens opplysninger da fakturaen ble laget.")
  ("Lines"
   "Linjer")
  ("Subtotal before discount"
   "Sum før rabatt")
  ("Discount"
   "Rabatt")
  ("Adjustment"
   "Justering")
  ("Total"
   "Totalt")
  ("External reference"
   "Ekstern referanse")
  ("Draft"
   "Utkast")
  ("Create an invoice"
   "Lag faktura")
  ("Get an invoice"
   "Hent faktura")
  ("List invoices"
   "Fakturaliste")
  ("Send an invoice"
   "Send faktura")
  ("Send invoice ~a (order ~a, total ~a) to the accounting system and the customer."
   "Send faktura ~a (ordre ~a, totalt ~a) til regnskapssystemet og kunden.")
  ("The order is ~a; an invoice needs a confirmed order"
   "Ordren har status ~a; faktura krever en bekreftet ordre")
  ("Order ~a has already been invoiced"
   "Ordre ~a er allerede fakturert")
  ("The invoice ~a is being sent"
   "Fakturaen ~a er i ferd med å bli sendt")
  ("The accounting system did not answer (~a); the invoice was not sent, try again"
   "Regnskapssystemet svarte ikke (~a); fakturaen er ikke sendt, prøv igjen")
  ("The invoice is ~a and cannot be sent again"
   "Fakturaen har status ~a og kan ikke sendes på nytt"))
