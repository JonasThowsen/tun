;;;; i18n/nb-jobs.lisp -- Norwegian (bokmål) translations of jobs, schedules
;;;; and triggers (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("is not an argument of the job"
   "er ikke et argument til jobben")
  ("Schedules"
   "Tidsplaner")
  ("Run a schedule now"
   "Kjør tidsplan nå")
  ("There is no schedule ~a"
   "Det finnes ingen tidsplan ~a")
  ("State"
   "Tilstand")
  ("Kind"
   "Type")
  ("Queue"
   "Kø")
  ("Jobs"
   "Jobber")
  ("Jobs overview"
   "Jobboversikt")
  ("Job"
   "Jobb")
  ("Read a job"
   "Les jobb")
  ("Run a job again"
   "Kjør jobb på nytt")
  ("Cancel a job"
   "Avbryt jobb")
  ("Schedule"
   "Tidsplan")
  ("Only a job that failed or was cancelled can run again; this one is ~a"
   "Bare en jobb som feilet eller ble avbrutt, kan kjøres på nytt; denne er ~a")
  ("Only a waiting job can be cancelled; this one is ~a"
   "Bare en jobb som venter, kan avbrytes; denne er ~a")
  ("Cancelled by ~a"
   "Avbrutt av ~a")
  ("The process stopped mid-attempt; check what it did before running it again"
   "Prosessen stoppet under forsøket; sjekk utfallet før jobben kjøres igjen")
  ("The trigger ~a no longer exists"
   "Utløseren ~a finnes ikke lenger")
  ("The record no longer meets the trigger's condition"
   "Posten oppfyller ikke lenger utløserens vilkår")
  ("Queued"
   "Venter")
  ("Running"
   "Kjører")
  ("Retrying"
   "Prøver igjen")
  ("Succeeded"
   "Fullført")
  ("Failed"
   "Feilet")
  ("Cancelled"
   "Avbrutt")
  (("Sunday" :context "weekday")
   "søndag")
  (("Monday" :context "weekday")
   "mandag")
  (("Tuesday" :context "weekday")
   "tirsdag")
  (("Wednesday" :context "weekday")
   "onsdag")
  (("Thursday" :context "weekday")
   "torsdag")
  (("Friday" :context "weekday")
   "fredag")
  (("Saturday" :context "weekday")
   "lørdag")
  ("~{~a~#[~; and ~:;, ~]~}"
   "~{~a~#[~; og ~:;, ~]~}")
  ("on day ~d of every month"
   "den ~d. hver måned")
  ("every day"
   "hver dag")
  ("weekdays"
   "hverdager")
  ("weekends"
   "i helgene")
  ("every ~a"
   "hver ~a")
  ("every hour on the hour"
   "hver hele time")
  ("every hour, ~d minutes past"
   "hver time, ~d minutter over")
  ("every ~d minutes"
   "hvert ~d. minutt")
  ("~a at ~a"
   "~a kl. ~a"))
