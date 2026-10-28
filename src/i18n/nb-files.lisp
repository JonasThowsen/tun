;;;; i18n/nb-files.lisp -- Norwegian (bokmål) translations of files: attaching them and the refusals
;;;; (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  A text that needs two translations names its context.

(in-package #:tun.core)

(define-translations "nb"
  ("Entity"
   "Entitet")
  ("The entity the record belongs to, such as item."
   "Entiteten posten hører til, som item.")
  ("Record"
   "Post")
  ("The record's id."
   "Postens id.")
  ("Files"
   "Filer")
  ("Attach files"
   "Legg ved filer")
  ("Files on a record"
   "Filer ved en post")
  ("File"
   "Fil")
  ("Remove a file"
   "Fjern en fil")
  ("This type of file is not allowed. Use PNG, JPEG, WebP, GIF or PDF."
   "Filtypen er ikke tillatt. Tillatt er PNG, JPEG, WebP, GIF og PDF.")
  ("The image is damaged or incomplete."
   "Bildet er skadet eller ufullstendig.")
  ("The image is too large: at most 30,000 pixels on each side and 50 megapixels."
   "Bildet er for stort: høyst 30 000 piksler på hver side og 50 megapiksler.")
  ("The content in data is not valid base64."
   "Innholdet i data er ikke gyldig base64.")
  ("The file is larger than 10 MB."
   "Filen er større enn 10 MB.")
  ("Send only the base64 content in data, without “data:…;base64,” in front."
   "Send bare base64-innholdet i data, uten «data:…;base64,» foran.")
  ("The form could not be read. Reload the page and try again."
   "Skjemaet kunne ikke leses. Last siden på nytt og prøv igjen.")
  ("The form has too many fields (at most ~d)."
   "Skjemaet har for mange felt (høyst ~d).")
  ("A part of the form has headers that are too long (at most 8 KB)."
   "En del av skjemaet har for lange overskrifter (høyst 8 KB).")
  ("You can send at most ~d files at a time."
   "Du kan sende høyst ~d filer om gangen.")
  ("A field in the form is longer than 1 MB."
   "Et felt i skjemaet er lengre enn 1 MB.")
  ("The form's fields hold more than 2 MB of text together."
   "Feltene i skjemaet har mer enn 2 MB tekst til sammen.")
  ("Send either data or upload, not both."
   "Send enten data eller upload, ikke begge.")
  ("The file must be sent as base64 in data."
   "Filen må sendes som base64 i data.")
  ("The content must be sent as base64 in data."
   "Innholdet må sendes som base64 i data.")
  ("“~a”: ~a"
   "«~a»: ~a")
  ("The file is empty."
   "Filen er tom.")
  ("must be an object with filename and data"
   "må være et objekt med filename og data")
  ("Tun does not fetch files from an address. Send the content as base64 in data."
   "Tun henter ikke filer fra en adresse. Send innholdet som base64 i data.")
  ("has unknown fields: ~{~a~^, ~}~@[ and ~d more~]"
   "har ukjente felt: ~{~a~^, ~}~@[ og ~d til~]")
  ("filename must be text"
   "filename må være en tekst")
  ("The filename cannot be longer than 255 characters."
   "Filnavnet kan ikke være lengre enn 255 tegn.")
  ("must be a list of files"
   "må være en liste av filer")
  ("You can attach at most ~d files at a time."
   "Du kan legge ved høyst ~d filer om gangen.")
  ("The files cannot be larger than 25 MB together."
   "Filene kan ikke være større enn 25 MB til sammen.")
  ("~a does not take files"
   "~a tar ikke imot filer")
  ("At most ~d files per ~(~a~)."
   "Høyst ~d filer per ~(~a~).")
  ("Files on ~(~a~) can only be attached and removed by an administrator"
   "Filer på ~(~a~) kan bare legges ved og fjernes av en administrator")
  ("Choose at least one file to attach."
   "Velg minst én fil å legge ved.")
  ("Could not find the file ~a"
   "Fant ikke filen ~a")
  ("Only the one who attached the file, or an administrator, can remove it"
   "Bare den som la ved filen, eller en administrator, kan fjerne den"))
