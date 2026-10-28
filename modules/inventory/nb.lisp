;;;; modules/inventory/nb.lisp -- Norwegian (bokmål) translations of the
;;;; inventory module's copy (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  Texts core or the catalog already translates (Name,
;;;; Product, Stock article, Department...) are theirs.

(in-package #:tun.inventory)

(define-translations "nb"
  (("Quantity" :context "inventory_movement.quantity")
   "Mengde")
  ;; Stock articles
  ("SKU"
   "Varenummer")
  ("Package size"
   "Pakningsstørrelse")
  ("Balance"
   "Beholdning")
  ("A projection of the ledger; no tool sets it directly."
   "Projeksjon av lagerboken; ingen verktøy setter den direkte.")
  ("Movement revision"
   "Bevegelsesrevisjon")
  ("Minimum"
   "Minimum")
  ("Maximum"
   "Maksimum")
  ("Cost price"
   "Innkjøpspris")
  ("Supplier"
   "Leverandør")
  ("{name, contact, article_no, order_url}"
   "{name, contact, article_no, order_url}")
  ("Lead time (days)"
   "Leveringstid (dager)")
  ("The product the article was made for (by products_create), if any."
   "Produktet artikkelen ble laget for (av products_create), om noen.")
  ;; The ledger
  ("Stock movement"
   "Lagerbevegelse")
  ("Opening"
   "Åpning")
  ("Receipt"
   "Mottak")
  ("Adjustment"
   "Justering")
  ("Recount"
   "Telling")
  ("Consumption"
   "Forbruk")
  ("Reservation"
   "Reservasjon")
  ("Release"
   "Frigivelse")
  ("Balance after"
   "Beholdning etter")
  ("Balance updated"
   "Beholdning oppdatert")
  ("false for a consumption row recreated after a later recount: the count wins."
   "false for en forbruksrad laget på nytt etter en senere telling: tellingen gjelder.")
  ("Opening balance"
   "Åpningsbeholdning")
  ("Reserved for order"
   "Reservert for ordre")
  ("Reserved for order (balance adjusted by hand)"
   "Reservert for ordre (beholdning manuelt justert)")
  ;; Transfers
  ("Transfer"
   "Overføring")
  ("Article"
   "Artikkel")
  ("From department"
   "Fra avdeling")
  ;; The tools
  ("Create stock article"
   "Opprett lagerartikkel")
  ("The purchase package in the article's unit (> 0)."
   "Innkjøpspakningen i artikkelens enhet (> 0).")
  ("Starting balance"
   "Startbeholdning")
  ("Article ID"
   "Artikkel-ID")
  ("Get stock article"
   "Hent lagerartikkel")
  ("Only active"
   "Aktive")
  ("true by default; false shows the archived ones."
   "Standard true; false viser de arkiverte.")
  ("Stock articles"
   "Lagerartikler")
  ("Cannot be set; it follows the ledger."
   "Kan ikke settes; den følger lagerboken.")
  ("Cannot be changed here; use articles_transfer."
   "Kan ikke endres her; bruk articles_transfer.")
  ("Change stock article"
   "Endre lagerartikkel")
  ("Archive stock article"
   "Arkiver lagerartikkel")
  ("Counted quantity"
   "Talt mengde")
  ("Stock count"
   "Varetelling")
  ("Transfer stock article"
   "Overfør lagerartikkel")
  ("Transfers"
   "Overføringer")
  ("Instead of product_id."
   "I stedet for product_id.")
  ("Number of units"
   "Antall")
  ("Goods receipt"
   "Varemottak")
  ("Change (+/-)"
   "Endring (+/-)")
  ("Stock adjustment"
   "Lagerjustering")
  ("Stock balance"
   "Lagerbeholdning")
  ("Stock movements"
   "Lagerbevegelser")
  ("From date"
   "Fra dato")
  ("To date"
   "Til dato")
  ("Include unconfirmed"
   "Ta med ubekreftede")
  ("Adds drafts, quotes sent and accepted orders as expected demand."
   "Legg til utkast, tilbud sendt og akseptert som forventet behov.")
  ("Stock forecast"
   "Lagerprognose")
  ("Before date"
   "Før dato")
  ("Shortage list"
   "Mangelliste")
  ("Days"
   "Dager")
  ("Purchase suggestions"
   "Innkjøpsforslag")
  ("Products"
   "Produkter")
  ("1–6 products."
   "1–6 produkter.")
  ("Availability overview"
   "Tilgjengelighetsoversikt")
  ;; Refusals
  ("The balance can be at most ~d"
   "Beholdningen kan være høyst ~d")
  ("Not enough ~a in stock: ~a in stock, ~a needed"
   "Ikke nok ~a på lager: ~a på lager, trenger ~a")
  ("The order link must be an http or https address without a user name or password"
   "Bestillingslenken må være en http- eller https-adresse uten brukernavn eller passord")
  ("The supplier must be an object with name, contact, article_no and order_url"
   "Leverandøren må være et objekt med name, contact, article_no og order_url")
  ("The supplier has no field ~a"
   "Leverandøren har ikke feltet ~a")
  ("The supplier field ~a must be text of at most 200 characters"
   "Leverandørfeltet ~a må være en tekst på høyst 200 tegn")
  ("The SKU ~a is already in use"
   "Varenummeret ~a er allerede i bruk")
  ("The package size must be more than 0"
   "Pakningsstørrelsen må være større enn 0")
  ("The level cannot be negative"
   "Nivået kan ikke være negativt")
  ("Name and unit must be filled in"
   "Navn og enhet må fylles ut")
  ("The starting balance cannot be negative"
   "Startbeholdningen kan ikke være negativ")
  ("The balance changes only through stock movements"
   "Beholdningen endres bare gjennom lagerbevegelser")
  ("The department is changed with articles_transfer"
   "Avdelingen endres med articles_transfer")
  ("The stock article has changed (revision ~d, not ~d)"
   "Lagerartikkelen er endret (revisjon ~d, ikke ~d)")
  ("Give the reason for the stock correction"
   "Oppgi årsaken til lagerkorrigeringen")
  ("The counted quantity cannot be negative"
   "Talt mengde kan ikke være negativ")
  ("The product ~a is not stock-tracked"
   "Produktet ~a er ikke lagerført")
  ("The adjustment cannot be 0"
   "Justeringen kan ikke være 0")
  ("Stock consumption is already recorded for this version"
   "Lagerforbruk er allerede registrert for denne versjonen")
  ("Invalid period: the to date must be after the from date and at most ~d days later"
   "Ugyldig periode: til-dato må være etter fra-dato og høyst ~d dager senere"))
