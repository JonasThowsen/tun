;;;; i18n/nb-ui.lisp -- Norwegian (bokmål) translations of the design system's
;;;; components (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.  The
;;;; names in braces, such as {title}, are filled in by the components'
;;;; script, so a translation keeps them as they are.

(in-package #:tun.core)

(define-translations "nb"
  ;; Actions
  ("(another site)"
   "(annet nettsted)")
  ("~d more: ~{~a~^, ~}"
   "~d til: ~{~a~^, ~}")
  ;; Forms
  ("Error:"
   "Feil:")
  ("(optional)"
   "(valgfritt)")
  ("There is a problem"
   "For å gå videre må du rette opp følgende feil:")
  ("Cancel"
   "Avbryt")
  ;; Data
  ("No entries."
   "Ingen oppføringer.")
  ("Change"
   "Endre")
  ("Pagination"
   "Sidenavigering")
  ("Previous page"
   "Forrige side")
  ("Previous"
   "Forrige")
  ("Next page"
   "Neste side")
  ("Next"
   "Neste")
  ("More pages"
   "Flere sider")
  ("Page ~d"
   "Side ~d")
  ("Page ~d of ~d"
   "Side ~d av ~d")
  ("Copy"
   "Kopier")
  ("Copied"
   "Kopiert")
  ("Could not copy. The text is selected."
   "Kunne ikke kopiere. Teksten er merket.")
  ;; Feedback
  ("Close the message"
   "Lukk meldingen")
  ("Warning:"
   "Advarsel:")
  ("~d%"
   "~d %")
  ("Loading…"
   "Laster…")
  ;; Interaction
  ("Close"
   "Lukk")
  ;; The board
  ("Move to the top"
   "Flytt øverst")
  ("Move up"
   "Flytt opp")
  ("Move down"
   "Flytt ned")
  ("Move to the bottom"
   "Flytt nederst")
  ("Position"
   "Rekkefølge")
  ("Move to"
   "Flytt til")
  ("Move “~a”"
   "Flytt «~a»")
  ("None"
   "Ingen")
  ("Moved “{title}” to {column}."
   "Flyttet «{title}» til {column}.")
  ("Moved “{title}” to place {place} of {count} in {column}."
   "Flyttet «{title}» til plass {place} av {count} i {column}.")
  ;; Files
  ("~d B"
   "~d B")
  ("~d kB"
   "~d kB")
  ("~a MB"
   "~a MB")
  ("{size} B"
   "{size} B")
  ("{size} kB"
   "{size} kB")
  ("{size} MB"
   "{size} MB")
  ("PDF"
   "PDF")
  ("Drag files here, or paste a screenshot."
   "Dra filer hit, eller lim inn et skjermbilde.")
  ("Chosen files"
   "Valgte filer")
  ("Remove"
   "Fjern")
  ("Remove {name}"
   "Fjern {name}")
  ("Drop to attach"
   "Slipp for å legge ved")
  ("“{name}”: this file type is not allowed."
   "«{name}»: filtypen er ikke tillatt.")
  ("“{name}” is larger than 10 MB."
   "«{name}» er større enn 10 MB.")
  ("You can attach at most {most} files."
   "Du kan legge ved høyst {most} filer.")
  ("The files can be at most 25 MB together."
   "Filene kan ikke være større enn 25 MB til sammen.")
  ("screenshot-{time}"
   "skjermbilde-{time}")
  ("Attachments"
   "Vedlegg")
  ("No attachments"
   "Ingen vedlegg")
  ("Show ~a"
   "Vis ~a")
  ("Image"
   "Bilde")
  ("Open the original"
   "Åpne original")
  ;; The push switch
  ("Notifications on this device"
   "Varsler på denne enheten")
  ("Get notified here when something needs you."
   "Få varsel her når noe trenger deg.")
  ("Send a test notification"
   "Send et prøvevarsel")
  ("Notifications are on for this device."
   "Varsler er på for denne enheten.")
  ("Notifications are not available here."
   "Varsler er ikke tilgjengelige her.")
  ("Notifications work only in the app. Add it to your Home Screen first: tap Share, then “Add to Home Screen”, and open it from there."
   "Varsler virker bare i appen. Legg den på Hjem-skjermen først: trykk Del, så «Legg til på Hjem-skjerm», og åpne den derfra.")
  ("This device cannot show notifications from the app. That needs iOS 16.4 or later."
   "Denne enheten kan ikke vise varsler fra appen. Det krever iOS 16.4 eller nyere.")
  ("This browser cannot show notifications."
   "Denne nettleseren kan ikke vise varsler.")
  ("Notifications are blocked for this app. Turn them on in the settings of your browser or phone, and reload the page."
   "Varsler er blokkert for denne appen. Slå dem på i innstillingene for nettleseren eller telefonen, og last inn siden på nytt.")
  ("Could not turn on notifications. Try again."
   "Kunne ikke slå på varsler. Prøv igjen.")
  ("The test notification was sent to {count} device."
   "Prøvevarselet er sendt til {count} enhet.")
  ("The test notification was sent to {count} devices."
   "Prøvevarselet er sendt til {count} enheter.")
  ("A test notification was sent less than a minute ago. Wait a little before you send another."
   "Et prøvevarsel ble sendt for under ett minutt siden. Vent litt før du sender et nytt.")
  ("Could not send the test notification. Try again."
   "Kunne ikke sende prøvevarselet. Prøv igjen.")
  ;; Layout and navigation
  ("Breadcrumbs"
   "Brødsmuler")
  ("Back to ~a"
   "Tilbake til ~a")
  ("Signed in as"
   "Innlogget som")
  ("Sign out"
   "Logg ut")
  ("Menu"
   "Meny")
  ("Close the menu"
   "Lukk menyen")
  ("Skip to the main content"
   "Hopp til hovedinnholdet")
  ("Main menu"
   "Hovedmeny"))
