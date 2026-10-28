;;;; modules/orders/nb.lisp -- Norwegian (bokmål) translations of the
;;;; orders module's copy (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A stored value's label that needs another word in one field
;;;; than elsewhere names its field as the context.  Texts core's catalogue
;;;; already translates the same way (Status, Order, Note...) are not
;;;; repeated here.

(in-package #:tun.orders)

(define-translations "nb"
  ;; Order lines and requirements
  ("Order line"
   "Ordrelinje")
  ("The line's id: in orders_update a line with the same id (or the same product in the same place) keeps its identity, and the checklist follows it."
   "Linjens id; i orders_update beholder en linje med samme id (eller samme produkt på samme plass) sin identitet, og sjekklisten følger den.")
  ("Product"
   "Produkt")
  ("Quantity"
   "Antall")
  ("Price mode"
   "Prisvalg")
  ("automatic (the default), percent_discount, fixed_discount or manual_total."
   "automatic (standard), percent_discount, fixed_discount eller manual_total.")
  ("Discount in percent"
   "Rabatt i prosent")
  ("0–100, at most two decimals (price mode percent_discount)."
   "0–100, høyst to desimaler (prisvalg percent_discount).")
  ("Discount amount"
   "Rabattbeløp")
  ("Price mode fixed_discount."
   "Prisvalg fixed_discount.")
  ("Manual line total"
   "Manuell linjesum")
  ("Price mode manual_total."
   "Prisvalg manual_total.")
  ("Reason for the price"
   "Begrunnelse for prisen")
  ("Choices"
   "Valg")
  ("{requirement id: [recipe id, …]}: the picks for the product's choice-group requirements, in order."
   "{krav-id: [oppskrift-id, …]}: valgene for produktets valggruppe-krav, i rekkefølge.")
  ("Chosen"
   "Valgt")
  ("When the choices last changed (stock warnings: no receipt since the pick)."
   "Når valgene sist ble endret (lageradvarsler: ingen mottak siden valget).")
  ("Unit price"
   "Enhetspris")
  ("Line total by the catalog"
   "Linjesum etter katalog")
  ("Line total"
   "Linjesum")
  ("Line adjustment"
   "Linjejustering")
  ("Need"
   "Behov")
  ("The article's product, or the article without one (README §8.3)."
   "Artikkelens produkt, eller artikkelen når den ikke har noe (README §8.3).")
  ("Required quantity"
   "Mengde")
  ("Stock article"
   "Lagerartikkel")
  ;; Price modes and tags
  ("Automatic"
   "Automatisk")
  ("Percent discount"
   "Prosentrabatt")
  ("Fixed discount"
   "Fast rabatt")
  ("Manual total"
   "Manuell total")
  ("Rental"
   "Utleie")
  ("Entertainment"
   "Underholdning")
  ;; The order
  ("Source"
   "Kilde")
  ("Open questions"
   "Åpne spørsmål")
  ("Revision"
   "Revisjon")
  ("Event date"
   "Arrangementsdato")
  ("End date"
   "Sluttdato")
  ("The last day; empty means one day."
   "Siste dag; tom betyr én dag.")
  ("Delivery address"
   "Leveringsadresse")
  ("Lines"
   "Linjer")
  ("Tags"
   "Merker")
  ("Department"
   "Avdeling")
  ("Price mode of the order"
   "Prisvalg for ordren")
  ("automatic (the customer's discount), percent_discount or fixed_discount."
   "automatic (kundens rabatt), percent_discount eller fixed_discount.")
  ("Order discount in percent"
   "Ordrerabatt i prosent")
  ("Order discount"
   "Ordrerabatt")
  ("Logistics"
   "Logistikk")
  ("{delivery:{not_agreed,method,earliest,latest}, return:{…}, site_address}."
   "{delivery:{not_agreed,method,earliest,latest}, return:{…}, site_address}.")
  ("Catalog total"
   "Katalogsum")
  ("Subtotal"
   "Sum før rabatt")
  ("Discount"
   "Rabatt")
  ("Adjustment"
   "Justering")
  ("Total"
   "Totalt")
  ("Consumables needed"
   "Behov for forbruksvarer")
  ("Pickup"
   "Henting")
  ("Return"
   "Retur")
  ("The accepted quote was out of date"
   "Akseptert tilbud var utdatert")
  ("Bookings"
   "Bookinger")
  ("Needs pickup and return"
   "Krever henting og retur")
  ("Locked"
   "Låst")
  ("Without a date"
   "Uten dato")
  ("Logistics agreed"
   "Logistikk avtalt")
  ("Quote"
   "Tilbud")
  ("Packed"
   "Pakket")
  ("Communication"
   "Kommunikasjon")
  ;; The order's statuses: their labels, and the calendar's (README §2.1)
  ("Draft"
   "Utkast")
  ("Quote sent"
   "Tilbud sendt")
  ("Accepted"
   "Akseptert")
  (("Accepted" :context "order.status")
   "Akseptert av kunde")
  ("Confirmed"
   "Bekreftet")
  ("Picked up"
   "Hentet")
  ("Returned"
   "Returnert")
  ("Ready for invoice"
   "Send faktura")
  ("Completed"
   "Fullført")
  (("Completed" :context "order.status")
   "Ferdig")
  (("Cancelled" :context "order.status")
   "Avlyst")
  ("DRAFT"
   "UTKAST")
  ("QUOTE SENT"
   "TILBUD SENDT")
  ("ACCEPTED BY CUSTOMER"
   "AKSEPTERT AV KUNDE")
  ("CONFIRMED"
   "BEKREFTET")
  ("PICKED UP"
   "HENTET")
  ("RETURNED"
   "RETURNERT")
  ("SEND INVOICE"
   "SEND FAKTURA")
  ("CANCELLED"
   "AVLYST")
  ("COMPLETED"
   "FERDIG")
  ;; Quotes
  ("Answered"
   "Besvart")
  ("Content when the quote was sent"
   "Innhold da tilbudet ble sendt")
  ("The order when the quote was sent"
   "Ordren da tilbudet ble sendt")
  ("The total, dates, address and every line field; when they change, the quote is out of date (stale)."
   "Totalsum, datoer, adresse og alle linjefelt; endres de, er tilbudet utdatert (stale).")
  ("Access code"
   "Tilgangskode")
  (("Awaiting response" :context "quote.status")
   "Venter på svar")
  (("Declined" :context "quote.status")
   "Avslått")
  ("Accept"
   "Godta")
  ("Decline"
   "Avslå")
  ;; Checklists
  ("Checklist item"
   "Sjekklistepunkt")
  ("Origin"
   "Opprinnelse")
  (("Manual" :context "checklist_item.origin")
   "Manuell")
  ("Category"
   "Kategori")
  ("Computed quantity"
   "Beregnet antall")
  ("Packed quantity"
   "Pakket antall")
  ("Done"
   "Ferdig")
  ;; Requirement plans and catalog impacts
  ("Requirement plan"
   "Kravplan")
  ("Fingerprint"
   "Fingeravtrykk")
  ("Activation"
   "Aktivering")
  ("Activated"
   "Aktivert")
  ("Activated by"
   "Aktivert av")
  ("Order revision"
   "Ordrerevisjon")
  ("[{order_line_id, article_id, article_name, quantity, unit, sources}]"
   "[{order_line_id, article_id, article_name, quantity, unit, sources}]")
  (("Proposed" :context "plan.status")
   "Foreslått")
  (("Superseded" :context "plan.status")
   "Erstattet")
  (("Rejected" :context "plan.status")
   "Avvist")
  (("Review" :context "plan.activation")
   "Gjennomgang")
  (("Correction" :context "plan.activation")
   "Korrigering")
  ("Catalog impact"
   "Katalogpåvirkning")
  ("Catalog change"
   "Katalogendring")
  ("Detail"
   "Detalj")
  ("Plan revision"
   "Planrevisjon")
  (("Pending" :context "plan_impact.status")
   "Venter")
  (("Applied" :context "plan_impact.status")
   "Aktivert")
  (("Proposed" :context "plan_impact.status")
   "Foreslått")
  (("Unchanged" :context "plan_impact.status")
   "Uendret")
  (("Conflict" :context "plan_impact.status")
   "Konflikt")
  (("Corrected" :context "plan_impact.status")
   "Korrigert")
  ;; The tools
  ("Create an order"
   "Opprett ordre")
  ("Get an order"
   "Hent ordre")
  ("Create a request draft"
   "Opprett forespørselsutkast")
  ("Order list"
   "Ordreliste")
  ("true: only requests without a date; false: only orders with one."
   "true: bare forespørsler uten dato; false: bare ordrer med dato.")
  ("Tag"
   "Merke")
  ("From date"
   "Fra dato")
  ("To date"
   "Til dato")
  ("Order overview"
   "Ordreoversikt")
  ("Change an order"
   "Endre ordre")
  ("The revision you are changing; a wrong one is conflict."
   "Revisjonen du endrer; feil revisjon gir conflict.")
  ("Check availability"
   "Sjekk tilgjengelighet")
  ("Product ID"
   "Produkt-ID")
  ("Date"
   "Dato")
  ("Suggestions for the order"
   "Forslag til ordren")
  ("Orders"
   "Ordrer")
  ("Send the quote"
   "Send tilbud")
  ("Accept the quote"
   "Aksepter tilbud")
  ("Confirm the order"
   "Bekreft ordre")
  ("Register the pickup"
   "Registrer henting")
  ("Condition"
   "Tilstand")
  ("The equipment's condition at pickup."
   "Utstyrets tilstand ved henting.")
  ("Time"
   "Tidspunkt")
  ("Default: now."
   "Standard: nå.")
  ("Register the return"
   "Registrer retur")
  ("Damages"
   "Skader")
  ("Fee"
   "Gebyr")
  ("Ready for invoicing"
   "Klar til fakturering")
  ("Force (admin)"
   "Tving (admin)")
  ("Invoice a rental before its return is registered; needs an admin and a reason."
   "Fakturer utleie før retur er registrert; krever admin og begrunnelse.")
  ("Reason"
   "Begrunnelse")
  ("Complete the order"
   "Fullfør ordre")
  ("Cancel the order"
   "Avbryt ordre")
  ("Reopen the order"
   "Åpne ordre igjen")
  ("Resume as a draft"
   "Gjenoppta som utkast")
  ("Get the quote"
   "Hent tilbud")
  ("Preview the quote"
   "Forhåndsvis tilbud")
  ("Answer the quote"
   "Svar på tilbud")
  ("Quote ID"
   "Tilbuds-ID")
  ("The quote's revision"
   "Tilbudets revisjon")
  ("Answer"
   "Svar")
  ("Checklist"
   "Sjekkliste")
  ("Synchronise the checklist"
   "Synkroniser sjekkliste")
  ("Mark a checklist item"
   "Merk sjekklistepunkt")
  ("Item ID"
   "Punkt-ID")
  ("Add a checklist item"
   "Legg til sjekklistepunkt")
  ("Order line ID"
   "Ordrelinje-ID")
  ("Delete a checklist item"
   "Slett sjekklistepunkt")
  ("Correct the requirement plan"
   "Korriger kravplan")
  ("Requirement plans"
   "Kravplaner")
  ("Get a requirement plan"
   "Hent kravplan")
  ("Plan ID"
   "Plan-ID")
  ("Catalog impacts"
   "Katalogpåvirkninger")
  ("Quote expires"
   "Tilbud utløper")
  ;; Confirmations, notes and what the module stores for people
  ("Confirm order ~a for ~a, event ~a, total ~a. Equipment is booked and consumables reserved."
   "Bekreft ordre ~a for ~a, arrangement ~a, totalt ~a. Utstyr bookes og forbruksvarer reserveres.")
  ("(no date)"
   "(ingen dato)")
  ("Cancel order ~a (status ~a). Bookings and reservations are released, and planned workflows cancelled."
   "Avbryt ordre ~a (status ~a). Bookinger og reservasjoner frigis, planlagte arbeidsflyter avbrytes.")
  ("Reopen order ~a (status ~a) for editing: it becomes confirmed, the equipment is booked again and the checklist reset."
   "Åpne ordre ~a (status ~a) for redigering igjen: den blir bekreftet, utstyr bookes på nytt og sjekklisten nullstilles.")
  ("Correct the requirement plan of order ~a after registered stock consumption: a new plan is activated and the consumption synchronised."
   "Korriger kravplanen for ordre ~a etter registrert lagerforbruk: ny plan aktiveres og forbruket synkroniseres.")
  ("Review the changed requirements of order ~a"
   "Gjennomgå endrede krav for ordre ~a")
  ("Requirement plan revision ~d is waiting for approval."
   "Kravplan revisjon ~d venter på godkjenning.")
  ("The requirement proposal is no longer active"
   "Kravforslaget er ikke lenger aktivt")
  ("The requirement proposal does not match the review"
   "Kravforslaget samsvarer ikke med gjennomgangen")
  ("The order has another active requirement plan now"
   "Ordren har fått en annen aktiv kravplan")
  ("The order's status no longer allows approval"
   "Ordrestatusen tillater ikke lenger godkjenning")
  ("The catalog or the order has changed since the proposal"
   "Katalogen eller ordren er endret etter forslaget")
  ("The stock correction was made explicitly"
   "Lagerkorrigering er gjennomført eksplisitt")
  ("A new requirement plan was activated automatically"
   "Ny kravplan aktivert automatisk")
  ("A proposal was made for review"
   "Forslag opprettet for gjennomgang")
  ("The requirement plan was already up to date"
   "Kravplanen var allerede oppdatert")
  ("The impact could not be computed; see request ~a"
   "Påvirkningen kunne ikke beregnes; se forespørsel ~a")
  ("not needed: the quote is not open"
   "ikke nødvendig: tilbudet er ikke åpent")
  ("[erased]"
   "[slettet]")
  ;; Logistics in a few words (README §4)
  ("We deliver"
   "Vi leverer")
  ("Customer collects"
   "Kunde henter")
  ("We collect"
   "Vi henter")
  ("Customer returns"
   "Kunde returnerer")
  ("Agreed"
   "Avtalt")
  ("Not agreed"
   "Ikke avtalt")
  ("~a at ~a"
   "~a kl. ~a")
  ;; Refusals
  ("The order is locked (ready for invoice or completed). Reopen the order for editing first."
   "Ordren er låst (send faktura eller fullført). Åpne ordren for redigering først.")
  ("The order has changed (revision ~d, not ~d)"
   "Ordren er endret (revisjon ~d, ikke ~d)")
  ("~a is too large (over ~d minor units)"
   "~a blir for stort (over ~d øre)")
  ("The manual total"
   "Manuell total")
  ("The line total"
   "Linjesummen")
  ("The total"
   "Summen")
  ("Discount percent must be filled in"
   "Rabattprosent må fylles ut")
  ("Discount percent must be between 0 and 100"
   "Rabattprosent må være mellom 0 og 100")
  ("Discount amount must be filled in"
   "Rabattbeløp må fylles ut")
  ("Discount amount cannot be negative"
   "Rabattbeløp kan ikke være negativt")
  ("Manual total must be filled in"
   "Manuell total må fylles ut")
  ("Manual total cannot be negative"
   "Manuell total kan ikke være negativ")
  ("That price mode is not allowed here"
   "Prisvalg er ikke tillatt her")
  ("logistics.~a must be an object"
   "logistics.~a må være et objekt")
  ("logistics.~a.~a is not a known field"
   "logistics.~a.~a er ikke et kjent felt")
  ("logistics.~a.not_agreed must be true or false"
   "logistics.~a.not_agreed må være true eller false")
  ("logistics.~a.method must be one of: ~{~a~^, ~}"
   "logistics.~a.method må være en av: ~{~a~^, ~}")
  ("Enter a valid time of day"
   "Fyll inn et gyldig klokkeslett")
  ("logistics must be an object"
   "logistics må være et objekt")
  ("logistics.~a is not a known field"
   "logistics.~a er ikke et kjent felt")
  ("logistics.site_address must be a text"
   "logistics.site_address må være en tekst")
  ("The address cannot be longer than 300 characters"
   "Adressen kan ikke være lengre enn 300 tegn")
  ("Choose a delivery method"
   "Velg utleveringsmetode")
  ("Choose a return method"
   "Velg returmetode")
  ("Set a time window for the delivery"
   "Sett tidsvindu for utlevering")
  ("Set a time window for the return"
   "Sett tidsvindu for retur")
  ("The latest delivery time cannot be before the earliest"
   "Utlevering senest kan ikke være før tidligst")
  ("The latest return time cannot be before the earliest"
   "Retur senest kan ikke være før tidligst")
  ("The return cannot start before the delivery is done on the same day"
   "Retur kan ikke starte før utlevering er ferdig samme dag")
  ("Address must be filled in when we deliver to or collect from the customer"
   "Adresse må fylles ut når vi leverer eller henter hos kunde")
  ("The date ~a must lie between ~a and ~a"
   "Datoen ~a må ligge mellom ~a og ~a")
  ("An end date needs a start date"
   "Sluttdato krever en startdato")
  ("The end date cannot be before the start date"
   "Sluttdato kan ikke være før startdato")
  ("The end date can be at most ~d days after the start date"
   "Sluttdato kan være høyst ~d dager etter startdato")
  ("Each tag can be used only once"
   "Hvert merke kan bare brukes én gang")
  ("Unknown department ~a (valid: ~{~a~^, ~})"
   "Ukjent avdeling ~a (gyldige: ~{~a~^, ~})")
  ("~a: only ~d free on ~a (cleaning days included), the order needs ~d"
   "~a: bare ~d ledig ~a (rengjøringsdager medregnet), ordren trenger ~d")
  ("The order has no event date (event_date)"
   "Ordren mangler arrangementsdato (event_date)")
  ("The order is ~a and cannot be changed"
   "Ordren er ~a og kan ikke endres")
  ("The order is ~a and must have an event date"
   "Ordren har status ~a og må ha arrangementsdato")
  ("The order is ~a and cannot become ~a"
   "Ordren har status ~a og kan ikke bli ~a")
  ("The line ~a is not on the order"
   "Linjen ~a finnes ikke på ordren")
  ("The requirement for ~a comes to ~a, more than ~d; reduce the quantity, the servings or the requirement"
   "Behovet for ~a blir ~a, mer enn ~d; reduser antall, porsjoner eller kravet")
  ("choices must be an object of lists of recipe ids"
   "choices må være et objekt med lister av oppskrift-id-er")
  ("The order has stock consumption and needs an explicit correction"
   "Ordren har lagerforbruk og krever en eksplisitt korrigering")
  ("Stock consumption is already registered. Use an explicit correction from the order."
   "Lagerforbruk er allerede registrert. Bruk eksplisitt korrigering fra ordren.")
  ("There is no registered stock consumption to correct"
   "Det finnes ingen registrert lagerforbruk å korrigere")
  ("There is no new change of requirements to correct"
   "Det finnes ingen ny kravendring å korrigere")
  ("Give a note for the correction"
   "Oppgi en merknad for korrigeringen")
  ("No requirement plan has the id ~a"
   "Fant ingen kravplan med id ~a")
  ("The customer has no email address; the quote cannot be sent"
   "Kunden har ingen e-postadresse; tilbudet kan ikke sendes")
  ("pickup and return apply only to orders with rental products"
   "henting/retur gjelder bare ordrer med produkter av type utleie")
  ("Only an admin can force invoicing"
   "Bare admin kan tvinge fakturering")
  ("cannot invoice before the return is registered; a rental order needs its return before the invoice"
   "kan ikke fakturere før retur er registrert; utleie-ordrer krever retur før faktura")
  ("A reason is required to force invoicing before the return"
   "Begrunnelse er påkrevd for å tvinge fakturering før retur")
  ("Order ~a has no quote"
   "Ordre ~a har ikke noe tilbud")
  ("Too many wrong access codes for the quote; try again in ~d minutes"
   "For mange feil tilgangskoder for tilbudet; prøv igjen om ~d minutter")
  ("Wrong access code for the quote"
   "Feil tilgangskode for tilbudet")
  ("the quote has changed; reload the page"
   "tilbudet er endret; last siden på nytt")
  ("the quote has expired; send a new quote"
   "tilbudet er utløpt; send et nytt tilbud")
  ("The quote is already answered (~a)"
   "Tilbudet er allerede besvart (~a)")
  ("The order is ~a and is not waiting for an answer"
   "Ordren har status ~a og venter ikke på svar")
  ("the customer cannot be erased while they have an open order"
   "kunden kan ikke slettes fordi kunden har en åpen ordre")
  ("the customer cannot be erased while they have ~d open orders"
   "kunden kan ikke slettes fordi kunden har ~d åpne ordrer")
  ("The line ~a does not belong to order ~a"
   "Linjen ~a hører ikke til ordre ~a")
  ("Automatic items cannot be deleted; they follow the requirements"
   "Automatiske punkter kan ikke slettes; de følger behovene")
  ;; The offer page (README §6.6)
  ("date not set"
   "dato ikke fastsatt")
  ("The page does not exist"
   "Siden finnes ikke")
  ("Check the link in the email."
   "Kontroller lenken i e-posten.")
  ("The offer has been updated"
   "Tilbudet er oppdatert")
  ("The offer has been updated or answered in another tab. Open the link in the latest email to see the current offer."
   "Tilbudet har blitt oppdatert eller svart på i en annen fane. Åpne lenken fra den nyeste e-posten for å se gjeldende tilbud.")
  ("The offer has expired"
   "Tilbudet er utløpt")
  ("Contact ~a if you would like an updated offer."
   "Ta kontakt med ~a dersom dere ønsker et oppdatert tilbud.")
  ("Period"
   "Periode")
  ("Location"
   "Sted")
  ("Valid until"
   "Gyldig til")
  ("Amount"
   "Beløp")
  ("Accept the offer"
   "Godta tilbudet")
  ("Decline the offer"
   "Avslå tilbudet")
  ("Your answer goes to ~a. A member of staff confirms the order before it is final."
   "Svaret sendes til ~a. En ansatt bekrefter ordren før den blir endelig.")
  ("Here is an overview of what is proposed for your event."
   "Her er en oversikt over det som er foreslått for arrangementet deres.")
  ("This is included"
   "Dette er inkludert")
  ("Would you like to go ahead?"
   "Vil dere gå videre?")
  ("The code is in the email with the offer, for example ABCDE-FGHIJ."
   "Koden står i e-posten med tilbudet, for eksempel ABCDE-FGHIJ.")
  ("Open the offer"
   "Åpne tilbudet")
  ("Offer from ~a"
   "Tilbud fra ~a")
  ("Thank you"
   "Takk")
  ("The offer is accepted. ~a will follow up and confirm the order."
   "Tilbudet er akseptert. ~a følger opp og bekrefter ordren.")
  ("Your answer is registered"
   "Svaret er registrert")
  ("The offer is declined. Contact ~a if there is anything you would like to clear up."
   "Tilbudet er avslått. Ta kontakt med ~a hvis dere ønsker å avklare noe.")
  ("Answer registered"
   "Svar registrert")
  ("The offer is already accepted"
   "Tilbudet er allerede akseptert")
  ("The offer has been declined"
   "Tilbudet er avslått")
  ("Too many attempts"
   "For mange forsøk")
  ("Wait a little before you try the code again."
   "Vent litt før du prøver koden igjen.")
  ("The code is not right. Check the code in the email and try again."
   "Koden stemmer ikke. Kontroller koden i e-posten og prøv igjen."))
