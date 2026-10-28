;;;; modules/warehouse/nb.lisp -- Norwegian (bokmål) translations of the
;;;; warehouse module's copy (spec/i18n.md 3.2).

(in-package #:tun.warehouse)

(define-translations "nb"
  ("Warehouse task"
   "Lageroppgave")
  ("Warehouse tasks"
   "Lageroppgaver")
  ("Task"
   "Oppgave")
  ("Task ID"
   "Oppgave-ID")
  ("Revision"
   "Revisjon")
  ("Due date"
   "Frist")
  ("Assignee"
   "Ansvarlig")
  ("Completed"
   "Fullført")
  ("Completed by"
   "Fullført av")
  ("Event on a warehouse task"
   "Hendelse på lageroppgave")
  ("Events on a warehouse task"
   "Hendelser på lageroppgave")
  (("Changed" :context "task_event.kind")
   "Endret")
  (("Reopened" :context "task_event.kind")
   "Gjenåpnet")
  ("Done by"
   "Utført av")
  ("Time"
   "Tidspunkt")
  ("Recipient"
   "Mottaker")
  ("Event details"
   "Detaljer")
  ("Search the title and description"
   "Søk i tittel og beskrivelse")
  ("Only the tasks in my department or assigned to me."
   "Bare oppgaver i min avdeling eller tildelt meg.")
  ("The employee who is to have the task; null removes the assignment."
   "Den ansatte som skal ha oppgaven; null fjerner tildelingen.")
  ("Create a warehouse task"
   "Opprett lageroppgave")
  ("Change a warehouse task"
   "Endre lageroppgave")
  ("Assign a warehouse task"
   "Tildel lageroppgave")
  ("Complete a warehouse task"
   "Fullfør lageroppgave")
  ("Reopen a warehouse task"
   "Gjenåpne lageroppgave")
  ("Get a warehouse task"
   "Hent lageroppgave")
  ("Choose a department for the warehouse task"
   "Velg avdeling for lageroppgaven")
  ("The assignee must belong to the warehouse task's department"
   "Ansvarlig må tilhøre samme avdeling som lageroppgaven")
  ("The title must have between 2 and 160 characters"
   "Tittelen må ha mellom 2 og 160 tegn")
  ("The task has changed (revision ~d, not ~d)"
   "Oppgaven er endret (revisjon ~d, ikke ~d)")
  ("The task is already assigned to this person"
   "Oppgaven er allerede tildelt denne personen")
  ("Only the current assignee can complete the warehouse task"
   "Bare nåværende ansvarlig kan fullføre lageroppgaven")
  ("You must belong to the warehouse task's department to complete it"
   "Du må tilhøre samme avdeling som lageroppgaven for å fullføre den")
  ("The task is already completed"
   "Oppgaven er allerede fullført")
  ("The task is not completed"
   "Oppgaven er ikke fullført"))
