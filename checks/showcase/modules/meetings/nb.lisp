;;;; checks/showcase/modules/meetings/nb.lisp -- Norwegian (bokmål)
;;;; translations of the meetings module's copy (spec/i18n.md 3.2).

(in-package #:tun.meetings)

(define-translations "nb"
  ("Meeting" "Møte")
  ("Meetings" "Møter")
  ("Day" "Dag")
  ("The customer the meeting is with." "Kunden møtet er med.")
  ("Create meeting" "Nytt møte")
  ("Records a meeting with a customer." "Fører opp et møte med en kunde.")
  ("Get meeting" "Hent møte")
  ("Gets one meeting by id." "Henter ett møte etter id.")
  ("List meetings" "Vis møter")
  ("Lists meetings, oldest first, those with CUSTOMER alone when it is given."
   "Viser møtene, eldste først, bare de med CUSTOMER når den er gitt.")
  (("Planned" :context "meeting.status") "Planlagt")
  (("Held" :context "meeting.status") "Holdt")
  (("Cancelled" :context "meeting.status") "Avlyst")
  ("Mark as held" "Merk som holdt")
  ("Cancel the meeting" "Avlys møtet")
  ("Mark «~a» as held." "Merk «~a» som holdt.")
  ("Cancel «~a». It stays in the list as cancelled." "Avlys «~a». Det blir stående i listen som avlyst.")
  ("planned → held. Needs confirmation." "planlagt → holdt. Må bekreftes.")
  ("planned → cancelled. Needs confirmation." "planlagt → avlyst. Må bekreftes.")
  ("The meeting is ~a, not planned" "Møtet er ~a, ikke planlagt"))
