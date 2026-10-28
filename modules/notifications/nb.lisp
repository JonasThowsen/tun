;;;; nb.lisp -- Norwegian (bokmål) translations of the notifications module:
;;;; the notifications' texts, the tools and the page (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.notifications)

(define-translations "nb"
  ("Notification"
   "Varsel")
  ("Recipient"
   "Mottaker")
  ("Text"
   "Tekst")
  ("Link"
   "Lenke")
  ("Concerns"
   "Gjelder")
  ("Concerns ID"
   "Gjelder-ID")
  ("Event ID"
   "Hendelses-ID")
  ("Read at"
   "Lest")
  ("My notifications"
   "Mine varsler")
  ("Mark a notification read"
   "Merk varsel lest")
  ("The notification does not exist"
   "Varselet finnes ikke")
  ("Unread notifications"
   "Uleste varsler")
  ("You have been given a new task."
   "Du er tildelt en ny oppgave.")
  ("The quote for order ~a has been accepted."
   "Tilbudet på ordre ~a er akseptert.")
  ("The quote for order ~a has been declined."
   "Tilbudet på ordre ~a er avslått.")
  ("Order ~a has been confirmed."
   "Ordre ~a er bekreftet.")
  ("The quote for order ~a has expired."
   "Tilbudet på ordre ~a er utløpt.")
  ("Notifications"
   "Varsler")
  ("Mark as read"
   "Marker som lest")
  ("Unread"
   "Ulest")
  (("Read" :context "notification")
   "Lest")
  ("Unread:"
   "Uleste:")
  ("No notifications"
   "Ingen varsler")
  ("What needs you arrives here."
   "Det som trenger deg, kommer hit."))
