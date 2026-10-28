;;;; modules/staffing/nb.lisp -- Norwegian (bokmål) translations of the
;;;; staffing module's copy (spec/i18n.md 3.2).

(in-package #:tun.staffing)

;;; Employees, assignments and overrides

(define-translations "nb"
  ("Actor"
   "Aktør")
  ("The exact X-Tun-Actor value, such as employee:kari (unique)."
   "Den nøyaktige X-Tun-Actor-verdien, f.eks. employee:kari (unik).")
  ("Department"
   "Avdeling")
  ("Assigned automatically in the department"
   "Tildeles automatisk i avdelingen")
  ("Employee ID"
   "Ansatt-ID")
  ("Employees"
   "Ansatte")
  ("Create an employee"
   "Opprett ansatt")
  ("Get an employee"
   "Hent ansatt")
  ("Change an employee"
   "Endre ansatt")
  ("Unknown department ~a (valid: ~{~a~^, ~})"
   "Ukjent avdeling ~a (gyldige: ~{~a~^, ~})")
  ("The actor must have the form role:name (admin, employee or viewer)"
   "Aktør må være på formen rolle:navn (admin, employee eller viewer)")
  ("The actor ~a already belongs to an employee"
   "Aktøren ~a er allerede knyttet til en ansatt")
  ("Assignment"
   "Tildeling")
  ("Assignments"
   "Tildelinger")
  ("Assignment ID"
   "Tildelings-ID")
  ("Assigned"
   "Tildelt")
  ("Automatic"
   "Automatisk")
  ("Department (automatic)"
   "Avdeling (automatisk)")
  ("End"
   "Slutt")
  ("Mine"
   "Mine")
  ("Only the assignments of your own employee record."
   "Bare tildelinger til din ansattpost.")
  ("Active ones"
   "Aktive")
  ("true (the default): only active ones; false: only ended ones."
   "true (standard): bare aktive; false: bare avsluttede.")
  ("Assign an employee"
   "Tildel ansatt")
  ("End an assignment"
   "Avslutt tildeling")
  ("Reason for the override"
   "Begrunnelse for overstyring")
  ("Needed if the employee is unavailable during the order (1–500 characters)."
   "Påkrevd når den ansatte er utilgjengelig i ordreperioden (1–500 tegn).")
  ("The order is ~a; no one can be assigned"
   "Ordren har status ~a; ingen kan tildeles")
  ("The employee is not active"
   "Den ansatte er ikke aktiv")
  ("The employee is already assigned to the order"
   "Den ansatte er allerede tildelt ordren")
  ("The employee is unavailable in the order's period and cannot be assigned"
   "Den ansatte er utilgjengelig i ordreperioden og kan ikke tildeles")
  ("A reason is required to override unavailability"
   "Begrunnelse er påkrevd ved overstyring av utilgjengelighet")
  ("The reason cannot be longer than 500 characters"
   "Begrunnelsen kan ikke være lengre enn 500 tegn")
  ("The assignment has already ended"
   "Tildelingen er allerede avsluttet")
  ("Unavailability override"
   "Overstyring av utilgjengelighet")
  ("Overrides"
   "Overstyringer")
  ("Reason"
   "Begrunnelse")
  ("Unavailabilities"
   "Utilgjengeligheter")
  ("Conflicts"
   "Konflikter")
  ("Overridden by"
   "Overstyrt av")
  ("~a (whole days)"
   "~a (hele dager)")
  (("~a (~a–~a)" :context "time span")
   "~a (kl. ~a–~a)"))

;;; Work sessions

(define-translations "nb"
  ("Work session"
   "Arbeidsøkt")
  ("Work sessions"
   "Arbeidsøkter")
  ("Duration (seconds)"
   "Varighet (sekunder)")
  ("Source"
   "Kilde")
  (("Live" :context "work_session.source")
   "Tidtaker")
  (("Manual" :context "work_session.source")
   "Manuell")
  ("Start a timer"
   "Start timer")
  ("Stop the timer"
   "Stopp timer")
  ("Record a work session"
   "Registrer arbeidsøkt")
  ("Stop the running timer before the assignment ends"
   "Stopp aktiv timer før tildelingen avsluttes")
  ("Stop the running timers before the order is closed"
   "Stopp aktive timer før ordren avsluttes")
  ("The assignment ~a is not your active assignment on order ~a"
   "Tildelingen ~a er ikke din aktive tildeling på ordre ~a")
  ("The order is ~a; a timer cannot be started"
   "Ordren har status ~a; timer kan ikke startes")
  ("You already have a running timer"
   "Du har allerede en aktiv timer")
  ("You have no running timer"
   "Du har ingen aktiv timer")
  ("The end time must be after the start time"
   "Sluttid må være etter starttid"))

;;; Unavailability

(define-translations "nb"
  ("Unavailability"
   "Utilgjengelighet")
  ("From date"
   "Fra dato")
  ("To date"
   "Til dato")
  ("Whole days"
   "Hele dager")
  ("From time"
   "Fra klokken")
  ("To time"
   "Til klokken")
  ("Private note"
   "Privat merknad")
  ("Version"
   "Versjon")
  ("By default your own employee record (an admin can choose anyone)."
   "Standard: din egen ansattpost (admin kan velge hvem som helst).")
  ("From date (YYYY-MM-DD)"
   "Fra dato (ÅÅÅÅ-MM-DD)")
  ("To date (YYYY-MM-DD)"
   "Til dato (ÅÅÅÅ-MM-DD)")
  ("From time (HH:MM, local time)"
   "Fra klokken (HH:MM, lokal tid)")
  ("To time (HH:MM, local time)"
   "Til klokken (HH:MM, lokal tid)")
  ("Record unavailability"
   "Registrer utilgjengelighet")
  ("Change unavailability"
   "Endre utilgjengelighet")
  ("Delete unavailability"
   "Slett utilgjengelighet")
  ("The time does not exist because of the change to summer time"
   "Klokkeslettet finnes ikke på grunn av overgang til sommertid")
  ("The time occurs twice at the change to winter time"
   "Klokkeslettet forekommer to ganger ved overgang til vintertid")
  ("Fill in both the from date and the to date"
   "Fyll inn både fra- og til-dato")
  ("The to date cannot be before the from date"
   "Til-dato kan ikke være før fra-dato")
  ("Fill in a valid time"
   "Fyll inn et gyldig klokkeslett")
  ("The entry overlaps an existing unavailability"
   "Registreringen overlapper en eksisterende utilgjengelighet")
  ("The period overlaps an active assignment to an order. Remove the assignment before you record the unavailability."
   "Perioden overlapper en aktiv ordretildeling. Fjern tildelingen før utilgjengeligheten registreres.")
  ("You can only record your own unavailability"
   "Du kan bare registrere din egen utilgjengelighet")
  ("No employee belongs to the actor ~a; give employee_id"
   "Ingen ansatt er knyttet til aktøren ~a; oppgi employee_id")
  ("Only the owner or an admin can change the entry"
   "Bare eieren eller en admin kan endre registreringen")
  ("The change is based on an old version. Reload the page."
   "Endringen er basert på en utdatert versjon. Last siden på nytt.")
  ("Too many entries; narrow the period"
   "For mange registreringer; avgrens perioden"))
