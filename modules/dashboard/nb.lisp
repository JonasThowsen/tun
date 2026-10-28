;;;; modules/dashboard/nb.lisp -- Norwegian (bokmål) translations of the
;;;; dashboard's pages (spec/i18n.md 3.2).  A tenant from core 1.x reads
;;;; these pages as it did, in Norwegian.

(in-package #:tun.dashboard)

;;; What the pages share

(define-translations "nb"
  ("The page does not exist"
   "Siden finnes ikke")
  ("~a ms"
   "~a ms")
  ("When"
   "Når")
  ("Where"
   "Hvor")
  ("What"
   "Hva")
  ("Actor"
   "Aktør")
  ("Message"
   "Melding")
  (("Duration" :context "time taken")
   "Tid")
  ("Backtrace"
   "Backtrace")
  ("Where the error happened, innermost first."
   "Der feilen oppsto, innerst først."))

;;; Jobs

(define-translations "nb"
  ("Overview"
   "Oversikt")
  ("due ~a"
   "forfaller ~a")
  ("started ~a"
   "startet ~a")
  ("~d of ~d"
   "~d av ~d")
  ("No jobs."
   "Ingen jobber.")
  ("Arguments"
   "Argumenter")
  ("Attempts"
   "Forsøk")
  ("Last error"
   "Siste feil")
  ("Succeeded in the last day"
   "Fullført siste døgn")
  ("Failed in the last day"
   "Feilet siste døgn")
  (("Limit" :context "queue")
   "Grense")
  ("Later"
   "Senere")
  ("Oldest waiting"
   "Eldste ventende")
  ("No queues."
   "Ingen køer.")
  ("Process"
   "Prosess")
  ("Started"
   "Startet")
  ("Alive"
   "Lever")
  ("Running now"
   "Kjører nå")
  ("~a~:[~; (this one)~]"
   "~a~:[~; (denne)~]")
  ("No processes."
   "Ingen prosesser.")
  ("Queues"
   "Køer")
  ("How many jobs each queue runs at once, and what is waiting."
   "Hvor mange jobber hver kø kjører samtidig, og hva som venter.")
  ("Processes"
   "Prosesser")
  ("The processes that run jobs. A process that is not alive has had its jobs taken over."
   "Prosessene som kjører jobber. En prosess som ikke lever, har fått jobbene sine tatt over.")
  ("Recent failures"
   "Siste feil")
  ("No job has failed."
   "Ingen jobber har feilet.")
  ("The background jobs: what is waiting, running and failed, and the schedules."
   "Bakgrunnsjobbene: hva som venter, kjører og feilet, og tidsplanene.")
  ("No jobs that are ~(~a~)."
   "Ingen jobber som ~(~a~).")
  ("The last 100 jobs in the state, newest first."
   "De siste 100 jobbene i tilstanden, nyeste først.")
  ("Attempt ~d"
   "Forsøk ~d")
  ("~a~@[ (request ~a)~]"
   "~a~@[ (forespørsel ~a)~]")
  ("Run again"
   "Kjør på nytt")
  ("Enqueued"
   "Lagt i kø")
  ("~a by ~a"
   "~a av ~a")
  ("Due at"
   "Forfaller")
  ("Finished"
   "Ferdig")
  ("Failed attempts"
   "Forsøk som feilet")
  ("No errors"
   "Ingen feil")
  ("trigger on ~a"
   "utløser på ~a")
  ("~a (~d job~:p)"
   "~a (~d ~:*~[jobber~;jobb~:;jobber~])")
  ("Cron"
   "Cron")
  ("Last"
   "Sist")
  ("Run now"
   "Kjør nå")
  ("No schedules."
   "Ingen tidsplaner.")
  ("The jobs queued by the clock, in local time, and the triggers, which queue a job for each record that meets a condition."
   "Jobbene som legges i køen etter klokken, i lokal tid, og utløserne, som legger en jobb i køen for hver post som oppfyller et vilkår."))

;;; Errors

(define-translations "nb"
  (("Open" :context "errors")
   "Åpne")
  (("Resolved" :context "errors")
   "Løste")
  (("Ignored" :context "errors")
   "Ignorerte")
  ("No errors."
   "Ingen feil.")
  ("No open errors."
   "Ingen åpne feil.")
  ("No ~(~a~) errors."
   "Ingen ~(~a~) feil.")
  ("Count"
   "Antall")
  ("Last seen"
   "Sist sett")
  ("Errors the code did not mean, grouped by cause: what happened, where, how many times and when. A resolved error that happens again is open again."
   "Feil koden ikke mente, gruppert etter årsak: hva som skjedde, hvor, hvor mange ganger og når. En løst feil som skjer igjen, blir åpen.")
  ("No occurrences."
   "Ingen forekomster.")
  ("Mark as resolved"
   "Merk som løst")
  ("Ignore"
   "Ignorer")
  ("Open again"
   "Åpne igjen")
  ("Times"
   "Antall ganger")
  ("First seen"
   "Først sett")
  ("Last request"
   "Siste forespørsel")
  ("Where the error happened, innermost first, the last time."
   "Der feilen oppsto, innerst først, siste gang.")
  ("No backtrace"
   "Ingen backtrace")
  ("Occurrences"
   "Forekomster")
  ("The last 50, newest first. A request shows as long as the process has it in memory."
   "De siste 50, nyeste først. Forespørselen vises så lenge prosessen har den i minnet."))

;;; Log

(define-translations "nb"
  ("Log"
   "Logg")
  ("Tools"
   "Verktøy")
  ("Web pages"
   "Nettsider")
  ("MCP"
   "MCP")
  ("Waiting for the write lock"
   "Venter på skrivelåsen")
  ("Calling another system"
   "Kaller et annet system")
  ("OK"
   "OK")
  ("Request kind"
   "Slag")
  ("Outcome"
   "Utfall")
  ("No requests."
   "Ingen forespørsler.")
  ("Running for"
   "Har kjørt")
  ("All kinds"
   "Alle slag")
  ("In progress"
   "Pågår nå")
  ("The last ~d requests the process has in memory, newest first. They are not stored: after a restart the list begins again, and errors are in “Errors”."
   "De siste ~d forespørslene prosessen har i minnet, nyeste først. De lagres ikke: etter en omstart begynner listen på nytt, og feil finnes i «Feil».")
  ("Step"
   "Steg")
  ("Steps"
   "Steg")
  ("Detail"
   "Detalj")
  ("No steps."
   "Ingen steg.")
  ("Store calls"
   "Lagringskall")
  ("Waited for the write lock"
   "Ventet på skrivelåsen")
  ("~a requires ~a, the actor is ~a"
   "~a krever ~a, aktøren er ~a")
  ("In time order, each step's time against the whole request's~@[; ~d more steps were not kept~]."
   "I tidsrekkefølge, med tiden målt mot hele forespørselens~@[; ~d steg til ble ikke tatt vare på~]."))
