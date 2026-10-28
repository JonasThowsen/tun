;;;; i18n/nb-push.lisp -- Norwegian (bokmål) translations of push notifications
;;;; (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("Address"
   "Adresse")
  ("The browser's key"
   "Nettleserens nøkkel")
  ("The browser's secret"
   "Nettleserens hemmelighet")
  ("Device"
   "Enhet")
  ("Turn on notifications"
   "Slå på varsler")
  ("Turn off notifications"
   "Slå av varsler")
  ("Does this device have notifications on"
   "Har denne enheten varsler på")
  ("Devices with notifications"
   "Enheter med varsler")
  ("Send a test notification"
   "Send et prøvevarsel")
  ("Tun's key for notifications on the phone (VAPID) is made from this. If it changes, every device must turn notifications on again."
   "Tuns nøkkel for varsler på telefonen (VAPID) lages av denne. Endres den, må hver enhet slå på varsler igjen.")
  ("~a on ~a"
   "~a på ~a")
  ("is not a key from the browser"
   "er ikke en nøkkel fra nettleseren")
  ("must be text"
   "må være en tekst")
  ("can have at most ~d characters"
   "kan ha høyst ~d tegn")
  ("must be a path on this server, such as /cases/12"
   "må være en sti på denne serveren, som /saker/12")
  ("the notification is ~d bytes; it can be at most ~d"
   "varselet er ~d byte; det kan være høyst ~d")
  ("The subscription no longer exists"
   "Abonnementet finnes ikke lenger")
  ("The address is not at a push service"
   "Adressen er ikke hos en push-tjeneste")
  ("The device no longer takes notifications"
   "Enheten tar ikke lenger imot varsler")
  ("Notifications need the client to be installable as an app"
   "Varsler krever at klienten kan installeres som app")
  ("is not an address at a push service"
   "er ikke en adresse hos en push-tjeneste")
  ("This device does not have notifications on"
   "Denne enheten har ikke varsler på")
  ("A test notification was sent less than a minute ago"
   "Et prøvevarsel ble sendt for under ett minutt siden")
  ("Notifications are on"
   "Varsler er på")
  ("This is what a notification from ~a looks like."
   "Slik ser et varsel fra ~a ut."))
