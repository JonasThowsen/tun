;;;; modules/reviews/nb.lisp -- Norwegian (bokmål) translations of the
;;;; reviews module's copy (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  Texts core already translates (Type, Status, Subject, Key,
;;;; Note...) are core's.

(in-package #:tun.reviews)

(define-translations "nb"
  ;; The review
  ("Review"
   "Gjennomgang")
  ("Pending"
   "Venter")
  ("Approved"
   "Godkjent")
  (("Rejected" :context "review.status")
   "Avvist")
  ("Superseded"
   "Utdatert")
  ("Priority"
   "Prioritet")
  ("Low"
   "Lav")
  ("Normal"
   "Normal")
  ("High"
   "Høy")
  ("Critical"
   "Kritisk")
  ("{type, id, revision}"
   "{type, id, revision}")
  ("Proposal"
   "Forslag")
  ("Source"
   "Kilde")
  ("{type, id}: what led to the proposal."
   "{type, id}: det som førte til forslaget.")
  ("Title"
   "Tittel")
  ("Summary"
   "Sammendrag")
  ("Requested by"
   "Bedt om av")
  ("Requested"
   "Bedt om")
  ("Deadline"
   "Frist")
  ("Handled by"
   "Behandlet av")
  ("Handled"
   "Behandlet")
  ("Subject (id)"
   "Gjelder (id)")
  ("Proposal (id)"
   "Forslag (id)")
  ;; The tools
  ("Reviews"
   "Gjennomganger")
  ("Review ID"
   "Gjennomgang-ID")
  ("Get review"
   "Hent gjennomgang")
  ("Decision"
   "Beslutning")
  ("Approve"
   "Godkjenn")
  ("Reject"
   "Avvis")
  ("Handle review"
   "Behandle gjennomgang")
  ;; Refusals
  ("There is no handler for reviews of the kind ~a"
   "Ingen behandler for gjennomganger av typen ~a")
  ("The review has already been handled"
   "Gjennomgangen er allerede behandlet"))
