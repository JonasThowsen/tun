;;;; i18n/nb-web.lisp -- Norwegian (bokmål) translations of the generated
;;;; pages, the access pages and the web app (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("No access"
   "Ingen tilgang")
  ("This page is not for you"
   "Denne siden er ikke for deg")
  ("The page needs a role other than yours."
   "Siden krever en annen rolle enn din.")
  ("The message could not be saved"
   "Meldingen kunne ikke lagres")
  ("System"
   "System")
  ("You do not have access to this"
   "Du har ikke tilgang til dette")
  ("Not found"
   "Finnes ikke")
  ("Someone else has changed this"
   "Noen andre har endret dette")
  ("The form has already been sent"
   "Skjemaet er allerede sendt")
  ("This cannot be done now"
   "Dette kan ikke gjøres nå")
  ("Not available"
   "Ikke tilgjengelig")
  ("Not enough in stock"
   "Ikke nok på lager")
  ("Something needs correcting"
   "Noe må rettes")
  ("That did not work"
   "Det gikk ikke")
  ("~d item~:p"
   "~d ~:*~[elementer~;element~:;elementer~]")
  ("None."
   "Ingen.")
  ("Details"
   "Opplysninger")
  ("More about this record"
   "Mer om posten")
  ("There is no ~(~a~) yet."
   "Det finnes ingen ~(~a~) ennå.")
  ("Choose"
   "Velg")
  ("More options"
   "Flere valg")
  ("Row"
   "Rad")
  ("~a in ~(~a~)"
   "~a i ~(~a~)")
  ("There is a problem"
   "For å gå videre må du rette opp følgende feil:")
  ("No ~(~a~) yet"
   "Ingen ~(~a~) ennå")
  ("What you create shows here."
   "Det du oppretter, vises her.")
  ("What is created shows here."
   "Det som blir opprettet, vises her.")
  ("Actions"
   "Handlinger")
  ("Test sign-in"
   "Testinnlogging")
  ("This server lets you choose who you are: /login?actor=role:name, with the role admin, employee or viewer."
   "Denne serveren lar deg velge hvem du er: /login?actor=rolle:navn, med rollen admin, employee eller viewer.")
  ("As an administrator"
   "Som administrator")
  ("As an employee"
   "Som ansatt")
  ("With read access"
   "Med lesetilgang")
  ("Sign in"
   "Logg inn")
  ("You are not signed in"
   "Du er ikke innlogget")
  ("Sign in to see this page."
   "Logg inn for å se denne siden.")
  ("You have read access"
   "Du har lesetilgang")
  ("You are signed in with read access (viewer); anything you send is refused."
   "Du er innlogget som lesetilgang (viewer); innsending blir avvist.")
  ("Go back"
   "Gå tilbake")
  ("The confirmation expires ~a."
   "Bekreftelsen utløper ~a.")
  ("Unknown action"
   "Ukjent handling")
  ("This action does not exist for the record."
   "Denne handlingen finnes ikke for posten.")
  ("Refused"
   "Avvist")
  ("The form was refused"
   "Skjemaet ble avvist")
  ("The form came from another site and was refused."
   "Skjemaet kom fra et annet nettsted og ble avvist.")
  ("Not set"
   "Ikke satt")
  (("Norsk (bokmål)" :context "language name")
   "Norsk (bokmål)")
  (("English" :context "language name")
   "English")
  ("New value"
   "Ny verdi")
  ("New secret"
   "Ny hemmelighet")
  ("The old one is never shown. The field is empty on purpose."
   "Den gamle vises aldri. Feltet er tomt med vilje.")
  ("Write null to remove the value."
   "Skriv null for å fjerne verdien.")
  ("Now"
   "Nå")
  ("Read from"
   "Leses fra")
  ("the environment variable ~a"
   "miljøvariabelen ~a")
  ("Save"
   "Lagre")
  ("Invalid setting value"
   "Ugyldig innstillingsverdi")
  ("The setting ~a is saved."
   "Innstillingen ~a er lagret.")
  ("Active"
   "Aktiv")
  ("Disabled"
   "Deaktivert")
  ("Revoked"
   "Trukket tilbake")
  ("Expired"
   "Utløpt")
  ("Person"
   "Person")
  ("Agent"
   "Agent")
  ("Admin"
   "Administrator")
  ("Employee"
   "Ansatt")
  ("Viewer"
   "Lesetilgang"))

;;; Signing in, the first administrator and /access (web/access.lisp)

(define-translations "nb"
  ("Sign in with ~a"
   "Logg inn med ~a")
  ("You were not signed in"
   "Du ble ikke logget inn")
  ("This Tun has no way to sign in yet."
   "Denne Tun-en har ingen måte å logge inn på ennå.")
  ("No account yet?"
   "Ingen konto ennå?")
  ("An administrator gives you access with your email address. Sign in with it afterwards."
   "En administrator gir deg tilgang med e-postadressen din. Logg inn med den etterpå.")
  ("Sign in to ~a."
   "Logg inn i ~a.")
  ("Invalid actor"
   "Ugyldig aktør")
  ("Use"
   "Bruk")
  ("/login?actor=role:name"
   "/login?actor=rolle:navn")
  ("with the role admin, employee or viewer."
   "med rolle admin, employee eller viewer.")
  ("Sign out"
   "Logg ut")
  ("The link does not work"
   "Lenken virker ikke")
  ("The link is unknown, used or expired. Ask an administrator for a new one."
   "Lenken er ukjent, brukt eller utløpt. Be en administrator om en ny.")
  ("Lower-case letters, such as alex."
   "Små bokstaver, for eksempel kari.")
  ("How others see you, such as Alex Morgan."
   "Slik andre ser deg, for eksempel Kari Nordmann.")
  ("Continue with ~a"
   "Fortsett med ~a")
  ("Continue"
   "Fortsett")
  ("Create the first administrator"
   "Opprett den første administratoren")
  ("What happens now?"
   "Hva skjer nå?")
  ("The account you make here can create the other accounts and the access tokens."
   "Kontoen du lager her, kan opprette de andre kontoene og tilgangsnøklene.")
  ("The link works only until the first administrator is made."
   "Lenken virker bare til den første administratoren er laget.")
  ("Tun has no administrator yet."
   "Tun har ingen administrator ennå.")
  ("Waiting"
   "Venter")
  ("~a for ~a"
   "~a for ~a")
  ("Sign-in"
   "Innlogging")
  ("Role and status"
   "Rolle og status")
  ("~{~a~^ or ~}"
   "~{~a~^ eller ~}")
  ("State"
   "Tilstand")
  ("Action"
   "Handling")
  ("No tokens yet."
   "Ingen nøkler ennå.")
  ("Revoke"
   "Trekk tilbake")
  ("An agent or a script, such as Claude Code, calls MCP with a token in Authorization: Bearer and may do the same as you, never more. The token is shown only when it is made."
   "En agent eller et skript, som Claude Code, kaller MCP med en nøkkel i Authorization: Bearer og får gjøre det samme som du, aldri mer. Nøkkelen vises bare når den lages.")
  ("My tokens"
   "Mine nøkler")
  ("~a has no account, and so no tokens."
   "~a har ingen konto, og så ingen nøkler.")
  ("Connect without a token"
   "Koble til uten nøkkel")
  ("Claude Code and other MCP clients that can do OAuth sign in as you through WorkOS, without a token."
   "Claude Code og andre MCP-klienter som kan OAuth, logger inn som deg gjennom WorkOS, uten nøkkel.")
  ("For Claude Code"
   "For Claude Code")
  ("Copy the command"
   "Kopier kommandoen")
  ("New token for me"
   "Ny nøkkel for meg")
  ("Create token"
   "Lag nøkkel")
  ("Accounts"
   "Kontoer")
  ("People sign in with ~a, agents with tokens."
   "Personer logger inn med ~a, agenter med nøkler.")
  ("New account"
   "Ny konto")
  ("All access tokens"
   "Alle tilgangsnøkler")
  ("New token for an agent"
   "Ny nøkkel for en agent")
  ("No agents yet"
   "Ingen agenter ennå")
  ("An agent gets tokens when it has an account of the type agent."
   "En agent får nøkler når den har en konto av typen agent.")
  ("Copy it now: it will not be shown again."
   "Kopier den nå: den vises ikke igjen.")
  ("The token was made earlier with the same form; it is not shown again."
   "Nøkkelen ble laget tidligere med det samme skjemaet; den vises ikke igjen.")
  ("New access token"
   "Ny tilgangsnøkkel")
  ("Copy the token"
   "Kopier nøkkelen")
  ("The account is created. ~a signs in with ~a with the email ~a."
   "Kontoen er opprettet. ~a logger inn med ~a med e-posten ~a.")
  ("The account is created, and ~a has been sent an invitation at ~a."
   "Kontoen er opprettet, og ~a har fått en invitasjon på ~a.")
  ("The account is saved."
   "Kontoen er lagret.")
  ("The token is revoked."
   "Nøkkelen er trukket tilbake.")
  ("Access"
   "Tilgang"))

;;; The web app (web/web-app.lisp), push (web/push.lisp) and files
;;; (web/files.lisp)

(define-translations "nb"
  ("You are offline"
   "Du er frakoblet")
  ("The page could not be fetched. Try again when you are online."
   "Siden kunne ikke hentes. Prøv igjen når du er på nett.")
  ("Try again"
   "Prøv igjen")
  ("You have a new notification"
   "Du har et nytt varsel")
  ("Sign in first"
   "Logg inn først")
  ("The form was not sent"
   "Skjemaet ble ikke sendt")
  ("Back"
   "Tilbake")
  ("File not found"
   "Fant ikke filen")
  ("The file does not exist, or you do not have access to it."
   "Filen finnes ikke, eller du har ikke tilgang til den."))
