;;;; nb.lisp -- the Norwegian (bokmål) translations of the showcase's own copy
;;;; (spec/i18n.md 3.2): each entry is a text as the code writes it and its
;;;; Norwegian.

(in-package #:showcase)

;;; The cards (cards.lisp)

(define-translations "nb"
  ("Card" "Kort")
  ("Cards" "Kort")
  ("Title" "Tittel")
  ("Status" "Status")
  ("New" "Ny")
  ("Planned" "Planlagt")
  ("In progress" "Under arbeid")
  ("Done" "Ferdig")
  ("Reported on" "Meldt")
  ("Estimate" "Anslag")
  ("What the work is expected to cost." "Hva arbeidet ventes å koste.")
  ("Place" "Plass")
  ("The rank key the card is sorted by in its column."
   "Rangnøkkelen kortet sorteres etter i sin kolonne.")
  ("The card was not moved: the board has changed since you opened it. Reload it."
   "Kortet ble ikke flyttet: tavla er endret siden du åpnet den. Last den inn på nytt.")
  ("New card" "Nytt kort")
  ("Screenshots" "Skjermbilder")
  ("Screenshots or other files that show the item: PNG, JPEG, WebP, GIF or PDF."
   "Skjermbilder eller andre filer som viser saken: PNG, JPEG, WebP, GIF eller PDF.")
  ("Move card" "Flytt kort")
  ("Before the card" "Før kortet")
  ("The card it goes directly above; without one, it goes last."
   "Kortet det skal stå rett over; uten står det nederst."))

;;; The board, a card's page and the attachments (pages.lisp)

(define-translations "nb"
  ("Items" "Saker")
  ("Items by status" "Saker etter status")
  ("Board" "Tavle")
  ("Projects" "Prosjekter")
  ("All" "Alle")
  ("Website" "Nettside")
  ("Search" "Søk")
  ("Search the items" "Søk etter saker")
  ("Filter" "Filtrer")
  ("New item" "Meld en sak")
  ("Report the item" "Meld saken")
  ("Paste a screenshot, drag files here or choose them."
   "Lim inn et skjermbilde, dra filer hit eller velg dem.")
  ("Attachments" "Vedlegg")
  ("Attach" "Legg ved")
  ("Attach files" "Legg ved filer")
  ("Attach in a window" "Legg ved i et vindu")
  ("Files" "Filer")
  ("PNG, JPEG, WebP, GIF or PDF, up to 10 MB each."
   "PNG, JPEG, WebP, GIF eller PDF, opptil 10 MB hver.")
  ("Back to the items" "Til sakene")
  ("To the item" "Til saken")
  ("Access" "Tilgang")
  ("Access in a new tab" "Tilgang i en ny fane")
  ("Page not found" "Fant ikke siden")
  ("No attachments" "Ingen vedlegg"))

;;; The summary as an email (mail.lisp)

(define-translations "nb"
  ("Email" "E-post")
  ("Summary from the board" "Sammendrag fra tavla")
  ("There are ~d cards on the board. This is where they stand:"
   "Det er ~d kort på tavla. Slik står de nå:")
  ("… and ~d more" "… og ~d til")
  ("Sent from the board. Reply to this email if something is wrong."
   "Sendt fra tavla. Svar på e-posten om noe er galt.")
  ("How the email looks" "Slik ser e-posten ut")
  ("The HTML part, in a frame without scripts, as an email app shows it."
   "HTML-delen, i en ramme uten skript, som en e-postapp viser den.")
  ("The text part" "Tekstdelen")
  ("Made from the same nodes, for email apps that show text."
   "Laget av de samme nodene, for e-postapper som viser tekst.")
  ("The cards as an email summary, as render-mail makes it before sending."
   "Et sammendrag av kortene som e-post, slik render-mail lager det før det sendes."))

;;; Notifications (notifications.lisp)

(define-translations "nb"
  ("Notifications" "Varsler")
  ("Text" "Tekst")
  ("Send a notification to me" "Send et varsel til meg")
  ("This device" "Denne enheten")
  ("Turn notifications on here, and off whenever you like."
   "Slå på varsler her, og slå dem av når du vil.")
  ("Send a notification to yourself" "Send et varsel til deg selv")
  ("It arrives on each device with notifications on, and opens the items."
   "Det kommer på hver enhet du har slått på varsler for, og åpner sakene.")
  ("A new item for you" "Ny sak til deg")
  ("The export fails for the customer" "Eksporten feiler for kunden")
  ("Send the notification" "Send varselet")
  ("Sent" "Sendt")
  ("The notification goes to ~d device~:p."
   "Varselet går til ~d ~:*~[enheter~;enhet~:;enheter~]."))
