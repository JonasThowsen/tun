;;;; nb.lisp -- Norwegian (bokmål) translations of the messaging module: its
;;;; default templates and their variables' texts, the tools and refusals,
;;;; the outbox's delivery outcomes and the communication section
;;;; (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.messaging)

(define-translations "nb"
  ;; Messages, deliveries and their stored words
  ("Message template"
   "Meldingsmal")
  ("Message"
   "Melding")
  ("Email delivery"
   "E-postleveranse")
  ("The send_delivery job that makes its provider call."
   "Jobben send_delivery som gjør leverandørkallet.")
  ("Version"
   "Versjon")
  ("Variables"
   "Variabler")
  ("Can be sent by hand"
   "Kan sendes manuelt")
  ("Marketing"
   "Markedsføring")
  ("Final"
   "Endelig")
  ("HTML"
   "HTML")
  ("Sender"
   "Avsender")
  ("Scheduled for"
   "Planlagt til")
  ("Attempts"
   "Forsøk")
  ("Transition version"
   "Overgangsversjon")
  ("Idempotency key"
   "Idempotensnøkkel")
  ("Provider"
   "Leverandør")
  ("Provider's message ID"
   "Leverandørens meldings-ID")
  ("Error code"
   "Feilkode")
  ("Error message"
   "Feilmelding")
  ("Queued at"
   "Lagt i kø")
  ("Sending started"
   "Sending startet")
  ("Settled by"
   "Avklart av")
  ("Settlement note"
   "Merknad til avklaringen")
  ("Outbound"
   "Utgående")
  ("Inbound"
   "Innkommende")
  ("Accepted"
   "Akseptert")
  (("Queued" :context "delivery.status")
   "Lagt i kø")
  (("Accepted" :context "delivery.status")
   "Akseptert av e-postleverandør")
  (("Failed" :context "delivery.status")
   "Kunne ikke sendes")
  ("Outcome unknown"
   "Ukjent leveringsutfall")
  ("The name in outgoing email."
   "Navnet i utgående e-post.")
  ("The sender's address."
   "Avsenderadresse.")
  ("The reply-to address, or the sender's address."
   "Svaradresse, eller avsenderadressen.")

  ;; The default templates
  ("Quote (default)"
   "Tilbud (standard)")
  ("Hello {{customer.name}}, here is your quote: {{order.total}}."
   "Hei {{customer.name}}, her er tilbudet ditt: {{order.total}}.")
  ("Invoice (default)"
   "Faktura (standard)")
  ("Invoice"
   "Faktura")
  ("Hello ~a! The invoice for order ~a, ~a in total, has been sent."
   "Hei ~a! Fakturaen for ordre ~a, totalt ~a, er sendt.")
  ("Stock alert (default)"
   "Lagervarsel (standard)")
  ("Stock alert: missing items"
   "Lagervarsel: varer som mangler")
  ("You are missing items:~{ ~a~}"
   "Du mangler varer:~{ ~a~}")

  ;; The templates' variables
  ("date not set"
   "dato ikke fastsatt")
  ("Get in touch by replying to this email if anything needs clarifying."
   "Ta kontakt ved å svare på denne e-posten hvis noe må avklares.")
  (" at ~a"
   " på ~a")
  (("at ~a" :context "time of day")
   "kl. ~a")
  ("not agreed"
   "ikke avtalt")
  ("the address you gave"
   "adressen dere oppga")
  ("Digital manual:~%~a~%~%"
   "Digital bruksanvisning:~%~a~%~%")
  ("We are missing some details:~%~{- ~a~%~}~%"
   "Vi mangler noen opplysninger:~%~{- ~a~%~}~%")
  ("We would also be grateful for a short recommendation:~%~a~%~%"
   "Ellers setter vi stor pris på en aldri så liten anbefaling:~%~a~%~%")

  ;; Tools and refusals
  ("Message templates"
   "Meldingsmaler")
  ("Preview message"
   "Forhåndsvis melding")
  ("Queue a message"
   "Legg melding i kø")
  ("Messages"
   "Meldinger")
  ("Read a message"
   "Hent melding")
  ("Test provider"
   "Testleverandør")
  ("Settle a delivery outcome"
   "Avklar leveringsutfall")
  ("Give either an order or a customer"
   "Oppgi enten ordre eller kunde")
  ("The template needs an order"
   "Malen krever en ordre")
  ("The template does not exist"
   "Malen finnes ikke")
  ("the customer has not consented to marketing"
   "kunden har ikke samtykket til markedsføring")
  ("the customer has been erased"
   "kunden er slettet")
  ("The template cannot be sent manually"
   "Malen kan ikke sendes manuelt")
  ("An order message needs an admin"
   "Ordremelding krever admin")
  ("Text can only be changed for an order message"
   "Tekst kan bare endres for ordremelding")
  ("The subject cannot hold line breaks or control characters"
   "Emnet kan ikke inneholde linjeskift eller kontrolltegn")
  ("The subject and the message text must be filled in"
   "Emne og meldingstekst må fylles ut")
  ("The subject can be up to 200 characters or 800 bytes"
   "Emnet kan være opptil 200 tegn eller 800 byte")
  ("The message text holds a control character that is not allowed"
   "Meldingsteksten inneholder et kontrolltegn som ikke er tillatt")
  ("The message text can be up to 4000 characters or 16,000 bytes"
   "Meldingsteksten kan være opptil 4000 tegn eller 16 000 byte")
  ("The preview is out of date. Open a new preview before you send."
   "Forhåndsvisningen er utdatert. Åpne en ny forhåndsvisning før du sender.")
  ("The message does not exist"
   "Meldingen finnes ikke")
  ("The delivery cannot be settled"
   "Leveransen kan ikke avklares")

  ;; The outbox: what a person reads about a delivery
  ("Delivery watchdog"
   "Leveringsvakt")
  ("An email to ~a could not be sent."
   "En e-post til ~a kunne ikke sendes.")
  ("The message was not sent: the customer has withdrawn consent or been erased."
   "Meldingen ble ikke sendt: kunden har trukket samtykket eller er slettet.")
  ("Email delivery is turned off. The message was not sent."
   "E-postlevering er deaktivert. Meldingen ble ikke sendt.")
  ("The email provider refused the message. Check the recipient and the content."
   "E-postleverandøren avviste meldingen. Kontroller mottaker og innhold.")
  ("The email provider refused access. The message was not sent."
   "E-postleverandøren avviste tilgangen. Meldingen ble ikke sendt.")
  ("The message snapshot is not valid and was not sent."
   "Meldingssnapshotet er ugyldig og ble ikke sendt.")
  ("The email provider asked us to wait. Settle the outcome before another try."
   "E-postleverandøren ba oss vente. Utfallet må avklares før nytt forsøk.")
  ("The email delivery timed out. The outcome is unknown and must be reviewed."
   "E-postleveringen fikk tidsavbrudd. Utfallet er ukjent og må gjennomgås.")
  ("The connection to the email provider broke. The outcome is unknown and needs review."
   "Forbindelsen til e-postleverandøren brøt. Utfallet er ukjent og må gjennomgås.")
  ("The email provider's outcome is unknown. Nothing is retried automatically."
   "E-postleverandørens utfall er ukjent. Ingen automatisk retry utføres.")

  ;; The communication section and the composer
  ("Communication"
   "Kommunikasjon")
  ("No messages yet."
   "Ingen meldinger ennå.")
  ("Settled"
   "Avklart")
  (("Outcome" :context "settle")
   "Avklaring")
  ("Settle"
   "Avklar")
  ("New message to the customer"
   "Ny melding til kunden")
  ("You see the message before it is queued."
   "Du ser meldingen før den legges i kø.")
  ("Template"
   "Mal")
  ("Preview order message"
   "Forhåndsvis ordremelding")
  ("Confirm and queue"
   "Bekreft og legg i kø")
  ("The message is queued"
   "Meldingen er lagt i kø")
  ("The delivery status shows under Communication."
   "Leveringsstatus vises under Kommunikasjon.")
  ("Back to the order"
   "Tilbake til ordren")
  ("The delivery is settled."
   "Leveringen er avklart."))
