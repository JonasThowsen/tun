;;;; i18n/nb-core.lisp -- Norwegian (bokmål) translations of the kernel's
;;;; core: refusals, types, settings and formats (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("Invalid input: ~{~a: ~a~^; ~}"
   "Ugyldig input: ~{~a: ~a~^; ~}")
  ("The setting ~a is not declared"
   "Innstillingen ~a er ikke deklarert")
  ("Invalid value for the setting ~a (~a)"
   "Ugyldig verdi for innstillingen ~a (~a)")
  ("Signs links sent to customers. Changing it voids every link sent."
   "Signerer kundelenker. Rotasjon ugyldiggjør gamle lenker.")
  ("The language of the pages, and of the copy Tun stores and sends."
   "Språket sidene vises på, og som Tun lagrer og sender tekst på.")
  ("The currency amounts are counted in. It cannot change while amounts are stored."
   "Valutaen beløpene regnes i. Den kan ikke endres mens det finnes lagrede beløp.")
  ("The time zone of local dates and times, and of schedules."
   "Tidssonen som lokale datoer, klokkeslett og tidsplaner regnes i.")
  ("Settings"
   "Innstillinger")
  ("Get a setting"
   "Hent innstilling")
  ("A secret cannot be read"
   "Hemmeligheten kan ikke leses")
  ("Change a setting"
   "Endre innstilling")
  ("Give a value"
   "Oppgi verdi")
  ("The setting ~a is read from the environment variable ~a and cannot be changed here"
   "Innstillingen ~a leses fra miljøvariabelen ~a og kan ikke endres her")
  ("The currency cannot change while amounts are stored in ~a"
   "Valutaen kan ikke endres mens det finnes beløp lagret i ~a")
  (("Jan" :context "month")
   "jan.")
  (("Feb" :context "month")
   "feb.")
  (("Mar" :context "month")
   "mar.")
  (("Apr" :context "month")
   "apr.")
  (("May" :context "month")
   "mai")
  (("Jun" :context "month")
   "jun.")
  (("Jul" :context "month")
   "jul.")
  (("Aug" :context "month")
   "aug.")
  (("Sep" :context "month")
   "sep.")
  (("Oct" :context "month")
   "okt.")
  (("Nov" :context "month")
   "nov.")
  (("Dec" :context "month")
   "des.")
  ("Yes"
   "Ja")
  ("No"
   "Nei")
  ("must be an amount, such as ~a"
   "må være et beløp, som ~a")
  ("cannot have decimals in ~a"
   "kan ikke ha desimaler i ~a")
  ("can have at most ~d decimals"
   "kan ha høyst ~d desimaler")
  ("is too large: at most ~a"
   "er for stort: høyst ~a")
  ("is not a known field"
   "er ikke et kjent felt")
  ("has ~d more unknown fields"
   "har ~d ukjente felt til")
  ("has an invalid format"
   "har ugyldig format")
  ("must be text"
   "må være en tekst")
  ("must be filled in"
   "må fylles ut")
  ("must be at least ~d characters"
   "må være minst ~d tegn")
  ("cannot be longer than ~d characters"
   "kan ikke være lengre enn ~d tegn")
  ("must be a valid email address (name@example.com)"
   "må være en gyldig e-postadresse (navn@domene.no)")
  ("is too long for a number: at most ~d characters"
   "er for langt for et tall: høyst ~d tegn")
  ("must be a whole number"
   "må være et heltall")
  ("must be at least ~d"
   "må være minst ~d")
  ("cannot be more than ~d"
   "kan ikke være større enn ~d")
  ("must be true or false"
   "må være true eller false")
  ("must be a number"
   "må være et tall")
  ("must be one of: ~{~a~^, ~}"
   "må være en av: ~{~a~^, ~}")
  ("must be a valid date in the form YYYY-MM-DD"
   "må være en gyldig dato på formen ÅÅÅÅ-MM-DD")
  ("must be a time in RFC 3339 format, such as 2026-03-01T09:00:00Z"
   "må være et tidspunkt i RFC 3339-format, f.eks. 2026-03-01T09:00:00Z")
  ("must be a valid identifier"
   "må være en gyldig identifikator")
  ("is invalid"
   "er ugyldig")
  ("must be an object"
   "må være et objekt")
  ("must be a list"
   "må være en liste")
  ("can have at most ~d items"
   "kan ha høyst ~d elementer")
  ("must have at least ~d item~:p"
   "må ha minst ~d ~:*~[elementer~;element~:;elementer~]")
  ("must be a JSON object"
   "må være et JSON-objekt")
  ("must be text of 1–64 characters"
   "må være en tekst på 1–64 tegn")
  ("The key ~a is already used with other input for ~a"
   "Nøkkelen ~a er allerede brukt med annen input for ~a")
  ("Unknown confirmation token"
   "Ukjent bekreftelsestoken")
  ("The confirmation token is already used"
   "Bekreftelsestokenet er allerede brukt")
  ("The confirmation must be given in a call of its own, not in the call that asked for it"
   "Bekreftelsen må gis i et eget kall, ikke i kallet som ba om den")
  ("The confirmation token has expired"
   "Bekreftelsestokenet er utløpt")
  ("The confirmation token belongs to another actor"
   "Bekreftelsestokenet tilhører en annen aktør")
  ("The confirmation token is for another tool"
   "Bekreftelsestokenet gjelder et annet verktøy")
  ("The input, or what is to be confirmed, has changed since the confirmation was issued"
   "Input eller det som skal bekreftes er endret siden bekreftelsen ble utstedt")
  ("~a took more than ~d ms and was stopped; nothing was saved"
   "~a brukte mer enn ~d ms og ble avbrutt; ingenting er lagret")
  ("~a (~a) has no access to ~a; it requires the role ~a"
   "~a (~a) har ikke tilgang til ~a; krever rollen ~a")
  ("~a must be confirmed by a user in a call of its own; it cannot be called from an operation, a workflow or a screen"
   "~a må bekreftes av en bruker i et eget kall; det kan ikke kalles fra en operasjon, arbeidsflyt eller skjerm")
  ("~d calls are already waiting; try again shortly"
   "~d kall venter allerede; prøv igjen om litt")
  ("~d calls are already waiting from the same address; try again shortly"
   "~d kall venter allerede fra samme adresse; prøv igjen om litt")
  ("Found no ~(~a~) with the id ~a"
   "Fant ikke ~(~a~) med id ~a")
  ("You do not have access to save ~(~a~) this way"
   "Du har ikke tilgang til å lagre ~(~a~) slik")
  (("Record" :context "entity")
   "Objekt")
  ("Setting"
   "Innstilling")
  ("Key"
   "Nøkkel")
  ("Value"
   "Verdi")
  ("ID"
   "ID")
  ("Already exists (~{~a~^, ~} must be unique)"
   "Finnes allerede (~{~a~^, ~} må være unik)")
  ("The id ~a already exists"
   "Id ~a finnes allerede")
  ("Already exists (a unique value was repeated)"
   "Finnes allerede (unik verdi brutt)"))
