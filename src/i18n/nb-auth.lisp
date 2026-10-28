;;;; i18n/nb-auth.lisp -- Norwegian (bokmål) translations of accounts and
;;;; signing in (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ;; Accounts and access tokens
  ("Account"
   "Konto")
  ("Name"
   "Navn")
  ("The actor's name: lower-case letters, digits, full stops, underscores or hyphens."
   "Aktørnavnet: små bokstaver, sifre, punktum, understrek eller bindestrek.")
  ("Display name"
   "Visningsnavn")
  ("Type"
   "Type")
  ("A person signs in in the browser; an agent uses access tokens only."
   "person logger inn i nettleseren; agent bruker bare tilgangsnøkler.")
  ("Role"
   "Rolle")
  ("Email"
   "E-post")
  ("The address a person signs in with."
   "Adressen en person logger inn med.")
  ("Status"
   "Status")
  ("Created"
   "Opprettet")
  ("Created by"
   "Opprettet av")
  ("Invited"
   "Invitert")
  ("When the last invitation by email was sent."
   "Når den siste invitasjonen på e-post ble sendt.")
  ("Access token"
   "Tilgangsnøkkel")
  ("Description"
   "Beskrivelse")
  ("Start"
   "Start")
  ("The first characters after tun_, to recognise the token by."
   "De første tegnene etter tun_, for å kjenne igjen nøkkelen.")
  ("SHA-256 of the token"
   "SHA-256 av nøkkelen")
  ("Expires"
   "Utløper")
  ("Last used"
   "Sist brukt")
  ;; The tools
  ("Who am I"
   "Hvem er jeg")
  ("Most results"
   "Maks antall")
  ("List accounts"
   "List kontoer")
  ("Send an invitation by email"
   "Send invitasjon på e-post")
  ("Sends the person an email about how they sign in: with which email, and where."
   "Sender personen en e-post om hvordan de logger inn: med hvilken e-post, og hvor.")
  ("Create account"
   "Opprett konto")
  ("Send an invitation"
   "Send invitasjon")
  ("Change account"
   "Endre konto")
  ("List access tokens"
   "List tilgangsnøkler")
  ("Without it: your own account. An admin can choose an agent's account."
   "Uten den: din egen konto. En admin kan velge en agentkonto.")
  ("What the token is for, such as “Claude Code on my laptop”."
   "Hva nøkkelen er til, for eksempel «Claude Code på laptopen».")
  ("At most the account's role; without it, the account's."
   "Høyst kontoens rolle; uten den, kontoens.")
  ("Create access token"
   "Opprett tilgangsnøkkel")
  ("Token"
   "Nøkkel")
  ("Revoke access token"
   "Trekk tilbake tilgangsnøkkel")
  ;; Refusals
  ("only lower-case letters, digits, full stops, underscores and hyphens"
   "bare små bokstaver, sifre, punktum, understrek og bindestrek")
  ("at most ~d characters"
   "høyst ~d tegn")
  ("a person needs an email to sign in"
   "en person trenger e-post for å logge inn")
  ("an agent does not sign in and has no email"
   "en agent logger ikke inn og har ingen e-post")
  ("an agent does not sign in and gets no invitation"
   "en agent logger ikke inn og får ingen invitasjon")
  ("The account name ~a is in use"
   "Kontonavnet ~a er i bruk")
  ("The email ~a already has an account"
   "E-posten ~a har allerede en konto")
  ("~a is disabled; enable the account first"
   "~a er deaktivert; aktiver kontoen først")
  ("~a got an invitation less than five minutes ago"
   "~a fikk en invitasjon for under fem minutter siden")
  ("~a is the last active administrator; give another person the role first"
   "~a er den siste aktive administratoren; gi en annen person rollen først")
  ("an agent has no email"
   "en agent har ingen e-post")
  ("~a has no account; give account_id"
   "~a har ingen konto; oppgi account_id")
  ("You can only see your own access tokens"
   "Du kan bare se dine egne tilgangsnøkler")
  ("An access token cannot make new tokens for its own account; make them in the browser"
   "En tilgangsnøkkel kan ikke lage nye nøkler for sin egen konto; lag dem i nettleseren")
  ("You can only make access tokens for your own account"
   "Du kan bare lage tilgangsnøkler for din egen konto")
  ("~a makes their own tokens"
   "~a lager sine egne nøkler")
  ("~a is disabled"
   "~a er deaktivert")
  ("cannot be higher than the account's role (~a)"
   "kan ikke være høyere enn kontoens rolle (~a)")
  ("must be in the future"
   "må være fram i tid")
  ("You can only revoke your own access tokens"
   "Du kan bare trekke tilbake dine egne tilgangsnøkler")
  ;; The invitation (spec/auth.md 3.6)
  ("You have been given access to ~a"
   "Du har fått tilgang til ~a")
  ("~a has given you access to ~a.~%~%Sign in with ~@[~{~a~^ or ~} and ~]the email address ~a:~%~a"
   "~a har gitt deg tilgang til ~a.~%~%Logg inn med ~@[~{~a~^ eller ~} og ~]e-postadressen ~a:~%~a")
  ;; Signing in with an identity provider
  ("The sign-in could not be completed. Try again."
   "Innloggingen kunne ikke fullføres. Prøv igjen.")
  ("~a did not answer as expected. Try again."
   "~a svarte ikke som forventet. Prøv igjen.")
  ("There is no account for ~a here. Ask an administrator for access."
   "Det finnes ingen konto for ~a her. Be en administrator om tilgang.")
  ("Setup has already been done."
   "Oppsettet er allerede gjort.")
  ("Signing in with ~a was cancelled."
   "Innloggingen med ~a ble avbrutt."))
