;;;; i18n/nb-platform.lisp -- Norwegian (bokmål) translations of workflows,
;;;; platform tools, introspection and recorded errors (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("Describe the registry"
   "Beskriv registeret")
  ("Entity type"
   "Entitetstype")
  ("Entity ID"
   "Entitets-ID")
  ("Limit"
   "Maks antall")
  ("List the audit log"
   "List revisjonslogg")
  ("Accounting status"
   "Regnskapsstatus")
  ("Unknown entity ~a (registry_describe and introspect_schema name them)"
   "Ukjent entitet ~a (navnene står i registry_describe og introspect_schema)")
  ("Entity"
   "Entitet")
  ("An entity's name as registry_describe gives it, such as order, customer or product."
   "Entitetsnavn som i registry_describe, f.eks. order, customer, product.")
  ("Inspect a record"
   "Inspiser post")
  ("~a ~a does not exist"
   "~a ~a finnes ikke")
  ("The record does not exist"
   "Posten finnes ikke")
  ("Request ID"
   "Forespørsels-ID")
  ("X-Tun-Request-Id or _meta.request_id."
   "X-Tun-Request-Id eller _meta.request_id.")
  ("Inspect a request"
   "Inspiser forespørsel")
  ("No request ~a among the ~d latest (they are kept in memory only, and cleared at a restart)"
   "Ingen forespørsel ~a blant de ~d siste (de lagres bare i minnet, og nullstilles ved omstart)")
  ("Selection"
   "Utvalg")
  ("Since"
   "Fra og med")
  ("Kind of request"
   "Slags forespørsel")
  ("Tool"
   "Verktøy")
  ("Part of the tool's name, such as orders_ or job:send."
   "En del av verktøyets navn, som orders_ eller job:send.")
  ("Recent requests"
   "Siste forespørsler")
  ("Requests in flight"
   "Pågående forespørsler")
  ("Status"
   "Status")
  ("Due before"
   "Forfall før")
  ("Workflows"
   "Arbeidsflyter")
  ("Unknown tool ~a"
   "Ukjent verktøy ~a")
  ("Unknown workflow ~a"
   "Ukjent arbeidsflyt ~a")
  ("Give an order"
   "Oppgi ordre")
  ("Order"
   "Ordre")
  ("The arguments the call would get (a JSON object)."
   "Argumentene kallet ville fått (et JSON-objekt).")
  ("Explain a call"
   "Forklar et kall")
  ("Database schema"
   "Databaseskjema")
  ("Runtime"
   "Kjøretid")
  ("Client extensions"
   "Klientutvidelser")
  ("The code could not be read: ~a"
   "Koden kunne ikke leses: ~a")
  ("eval runs in a read-only transaction; writing is not allowed: ~a"
   "eval kjører i en skrivebeskyttet transaksjon; skriving er ikke tillatt: ~a")
  ("eval runs read-only; the database refused the write: ~a"
   "eval kjører skrivebeskyttet; databasen avviste skrivingen: ~a")
  ("The evaluation failed: ~a"
   "Evalueringen feilet: ~a")
  ("Code"
   "Kode")
  ("Common Lisp forms, read with *read-eval* off in the package TUN-EVAL (which uses CL and TUN)."
   "Common Lisp-uttrykk, lest med *read-eval* av i pakken TUN-EVAL (bruker CL og TUN).")
  ("Evaluate Lisp in the process"
   "Evaluer Lisp i prosessen")
  ("Errors"
   "Feil")
  ("Error"
   "Feil")
  ("Read an error"
   "Les feil")
  ("Set an error's status"
   "Sett status på feil")
  ("Open"
   "Åpen")
  ("Resolved"
   "Løst")
  ("Ignored"
   "Ignorert")
  ("Where: ~a"
   "Hvor: ~a")
  ("Type: ~a (~a)"
   "Type: ~a (~a)")
  ("First seen: ~a"
   "Først sett: ~a")
  ("Times: ~d"
   "Antall ganger: ~d")
  ("Request: ~a"
   "Forespørsel: ~a")
  ("See the error: ~a"
   "Se feilen: ~a")
  ("Agents find it with errors_get ~a."
   "Agenter finner den med errors_get ~a.")
  ("~:[The error is back~;New error~] in ~a: ~a"
   "~:[Feilen er tilbake~;Ny feil~] i ~a: ~a")
  ("Workflow"
   "Arbeidsflyt")
  ("Customer"
   "Kunde")
  ("Due"
   "Forfall")
  ("Executed"
   "Utført")
  ("Note"
   "Merknad")
  ("Subject"
   "Gjelder")
  ("Order ID"
   "Ordre-ID")
  ("Give an order, a customer, a kind or a status"
   "Oppgi ordre, kunde, type eller status")
  ("Get a workflow"
   "Hent arbeidsflyt")
  ("Workflow ID"
   "Arbeidsflyt-ID")
  ("Customer ID"
   "Kunde-ID")
  ("Request"
   "Forespørsel")
  ("The workflow is no longer planned"
   "Arbeidsflyten er ikke planlagt lenger")
  ("The workflow was run or cancelled by another"
   "Arbeidsflyten ble kjørt eller avbrutt av en annen")
  ("Planned"
   "Planlagt")
  ("The record a workflow not about an order is about (a catalog change)."
   "Posten en arbeidsflyt som ikke gjelder en ordre, gjelder (en katalogendring).")
  ("Slow"
   "Trege")
  ("Rejected"
   "Avviste")
  ("All"
   "Alle")
  ("Operation"
   "Operasjon")
  ("Mcp"
   "MCP")
  ("Api"
   "API")
  ("Web"
   "Web")
  ("Input"
   "Input"))
