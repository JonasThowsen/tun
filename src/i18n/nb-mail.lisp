;;;; i18n/nb-mail.lisp -- Norwegian (bokmål) translations of mail: its tools and the refusals
;;;; (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("Email"
   "E-post")
  ("To"
   "Til")
  (("Queued" :context "mail.status")
   "Lagt i kø")
  ("Sending"
   "Sender")
  ("Sent"
   "Sendt")
  ("Failed"
   "Feilet")
  ("Read an email"
   "Les e-post")
  ("Send an email again"
   "Send e-post på nytt")
  ("must be filled in"
   "må fylles ut")
  ("Only an email that failed can be sent again; this one is ~a"
   "Bare en e-post som feilet kan sendes på nytt; denne er ~a")
  ("~a on <~a> cannot hold spaces, control characters or \\ in mail: “~a”"
   "~a på <~a> kan ikke ha mellomrom, kontrolltegn eller \\ i e-post: «~a»")
  ("the link “~a” must start with https://, http://, mailto: or /"
   "lenken «~a» må begynne med https://, http://, mailto: eller /")
  ("the image “~a” must have an address that starts with https://"
   "bildet «~a» må ha en adresse som begynner med https://")
  ("the style “~a” on <~a> lacks “:”"
   "stilen «~a» på <~a> mangler «:»")
  ("the style “~a” cannot be used in mail"
   "stilen «~a» kan ikke brukes i e-post")
  ("the value “~a” for ~(~a~) cannot be used in mail"
   "verdien «~a» for ~(~a~) kan ikke brukes i e-post")
  ("(:@ …) on <~a> must have a name and a value for each attribute"
   "(:@ …) på <~a> må ha et navn og en verdi for hvert attributt")
  ("~a on <~a> is not an attribute name; a name is a keyword, such as :href"
   "~a på <~a> er ikke et attributtnavn; et navn er et nøkkelord, som :href")
  ("the attribute ~a cannot be used on <~a> in mail"
   "attributtet ~a kan ikke brukes på <~a> i e-post")
  ("the attribute ~a on <~a> must be a text or a number, not ~a"
   "attributtet ~a på <~a> må være en tekst eller et tall, ikke ~a")
  ("“~a” is not a node: the list does not end"
   "«~a» er ikke en node: lista er ikke avsluttet")
  ("(:@ …) must come right after the tag: “~a”"
   "(:@ …) må stå rett etter taggen: «~a»")
  ("<~a> cannot be used in mail"
   "<~a> kan ikke brukes i e-post")
  ("html is deeper than ~d levels"
   "html er dypere enn ~d nivåer")
  ("“~a” is not a node: a node is a text, a number, a list or an element such as (:p …)"
   "«~a» er ikke en node: en node er en tekst, et tall, en liste eller et element som (:p …)")
  ("html is nodes, such as (:p \"…\"), not text with HTML; plain text goes in text"
   "html er noder, som (:p \"…\"), ikke tekst med HTML; ren tekst går i text"))
