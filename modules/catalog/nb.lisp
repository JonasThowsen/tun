;;;; modules/catalog/nb.lisp -- Norwegian (bokmål) translations of the
;;;; catalog module's copy (spec/i18n.md 3.2).
;;;;
;;;; Each entry is a text as the code writes it, in English, and its
;;;; Norwegian.  Texts core already translates (Name, Created, Most
;;;; results...) are core's.

(in-package #:tun.catalog)

(define-translations "nb"
  ;; Products
  ("Product"
   "Produkt")
  ("Revision"
   "Revisjon")
  ("Product type"
   "Produkttype")
  ("rental (equipment), consumable or service."
   "utleie (utstyr), forbruk (forbruksvare) eller tjeneste.")
  ("Rental"
   "Utleie")
  ("Consumable"
   "Forbruk")
  ("Service"
   "Tjeneste")
  ("Unit"
   "Enhet")
  ("Unit price"
   "Enhetspris")
  ("Stock-tracked"
   "Lagerført")
  ("Units owned"
   "Antall eid")
  ("How many units can be rented out at once (rental)."
   "Antall enheter som kan leies ut samtidig (utleie).")
  ("Digital manual"
   "Digital bruksanvisning")
  ("Stock article"
   "Lagerartikkel")
  ("The stock article the product is counted in; several products may share one."
   "Lagerartikkelen produktet telles i; flere produkter kan dele én.")
  ("Department"
   "Avdeling")
  ("The department that owns the product; changed afterwards only with products_transfer."
   "Avdelingen som eier produktet; endres siden bare med products_transfer.")
  ("Department revision"
   "Avdelingsrevisjon")
  ("Requirements"
   "Krav")
  ("What the product requires from stock per line, quantity, serving or day; set with products_set_requirements."
   "Hva produktet krever fra lageret per linje, antall, porsjon eller dag; settes med products_set_requirements.")
  ("Own recipe requirement"
   "Eget oppskriftskrav")
  ("The requirement products_set_recipe created for the product."
   "Kravet products_set_recipe opprettet for produktet.")
  ("Own recipe"
   "Egen oppskrift")
  ("The recipe products_set_recipe created for the product; only that recipe is updated afterwards."
   "Oppskriften products_set_recipe opprettet for produktet; bare den oppdateres siden.")
  ("The manual must have a valid http(s) address"
   "Bruksanvisningen må ha en gyldig http(s)-adresse")
  ;; Requirements
  ("Requirement"
   "Krav")
  ("Target"
   "Mål")
  ("{kind: article|recipe|choice_group, id}"
   "{kind: article|recipe|choice_group, id}")
  (("Quantity" :context "product_requirement.quantity")
   "Mengde")
  ("Calculated from"
   "Beregnes fra")
  ("Per line"
   "Per linje")
  ("Per quantity"
   "Per antall")
  ("Per serving"
   "Per porsjon")
  ("Per day"
   "Per dag")
  ("Number of choices"
   "Antall valg")
  ("Rounding"
   "Avrunding")
  ("Exact"
   "Eksakt")
  ("Ceil per 100"
   "Rundes opp per 100")
  ("Place"
   "Plass")
  ;; Recipes, choice groups and catalog changes
  ("Recipe line"
   "Oppskriftslinje")
  ("Quantity per use"
   "Mengde per bruk")
  ("Recipe"
   "Oppskrift")
  ("Lines"
   "Linjer")
  ("Choice group"
   "Valggruppe")
  ("Recipes"
   "Oppskrifter")
  ("Catalog change"
   "Katalogendring")
  ("Resource"
   "Ressurs")
  ("Resource ID"
   "Ressurs-ID")
  ("Updated"
   "Endret")
  ("Deleted"
   "Slettet")
  ("Changed fields"
   "Endrede felt")
  ("Time"
   "Tidspunkt")
  ("Done by"
   "Utført av")
  ("For a requirement: the product that carries it (catalog impact reaches its orders)."
   "For et krav: produktet som har kravet (katalogendringen når produktets ordrer).")
  ;; The tools
  ("Create product"
   "Opprett produkt")
  ("Product ID"
   "Produkt-ID")
  ("Get product"
   "Hent produkt")
  ("Search in names"
   "Søk i navn")
  ("Product list"
   "Produktliste")
  ("Stock article ID"
   "Lagerartikkel-ID")
  ("Links the product to a stock article (admin); null removes the link."
   "Kobler produktet til en lagerartikkel (admin); null fjerner koblingen.")
  ("Cannot be changed here; use products_transfer."
   "Kan ikke endres her; bruk products_transfer.")
  ("Change product"
   "Endre produkt")
  ("To department"
   "Til avdeling")
  ("Reason"
   "Begrunnelse")
  ("Transfer product"
   "Overfør produkt")
  ("Service ID"
   "Tjeneste-ID")
  ("Instead of product_id, for a service."
   "I stedet for product_id, for en tjeneste.")
  ("[{id?, name?, target:{kind,id}, quantity, basis, picks?, rounding?}]; replaces the list."
   "[{id?, name?, target:{kind,id}, quantity, basis, picks?, rounding?}]; erstatter listen.")
  ("Set requirements"
   "Sett krav")
  ("[{article_id, quantity}]"
   "[{article_id, quantity}]")
  ("Create recipe"
   "Opprett oppskrift")
  ("Recipe ID"
   "Oppskrift-ID")
  ("[{id?, article_id, quantity}]"
   "[{id?, article_id, quantity}]")
  ("Change recipe"
   "Endre oppskrift")
  ("Get recipe"
   "Hent oppskrift")
  ("Archive recipe"
   "Arkiver oppskrift")
  ("Recipe ids, in order."
   "Oppskrift-id-er, i rekkefølge.")
  ("Create choice group"
   "Opprett valggruppe")
  ("Choice group ID"
   "Valggruppe-ID")
  ("Change choice group"
   "Endre valggruppe")
  ("Get choice group"
   "Hent valggruppe")
  ("Choice groups"
   "Valggrupper")
  ("Archive choice group"
   "Arkiver valggruppe")
  ("Catalog changes"
   "Katalogendringer")
  ;; Refusals
  ("No module keeps transfers between departments here"
   "Ingen modul fører overføringer mellom avdelinger her")
  ("Unknown department ~a (valid: ~{~a~^, ~})"
   "Ukjent avdeling ~a (gyldige: ~{~a~^, ~})")
  ("The department is changed with products_transfer"
   "Avdelingen endres med products_transfer")
  ("The product has changed (revision ~d, not ~d)"
   "Produktet er endret (revisjon ~d, ikke ~d)")
  ("Only an administrator can link the product to a stock article"
   "Bare en administrator kan koble produktet til en lagerartikkel")
  ("Found no stock article with the id ~a"
   "Fant ingen lagerartikkel med id ~a")
  ("Availability cannot be turned off while up to ~d are booked in active orders."
   "Tilgjengelighet kan ikke deaktiveres mens opptil ~d er booket i aktive ordrer.")
  ("The units owned cannot be set to ~d; up to ~d are already booked in active orders."
   "Antall enheter kan ikke settes til ~d; opptil ~d er allerede booket i aktive ordrer.")
  ("Choose the department to transfer the stock to"
   "Velg avdelingen lageret skal overføres til")
  ("Choose another department"
   "Velg en annen avdeling")
  ("Give the reason for the transfer"
   "Oppgi årsaken til overføringen")
  ("The department has changed since you loaded the page; reload the page"
   "Avdelingen er endret siden du lastet siden; last siden på nytt")
  ("The quantity can be at most ~d"
   "Mengden kan være høyst ~d")
  ("Quantities can have at most three decimals"
   "Mengder kan ha høyst tre desimaler")
  ("Found no recipe with the id ~a"
   "Fant ingen oppskrift med id ~a")
  ("Found no choice group with the id ~a"
   "Fant ingen valggruppe med id ~a")
  ("The lines must be a list"
   "Linjene må være en liste")
  ("A recipe line must be an object"
   "En oppskriftslinje må være et objekt")
  ("Unknown recipe line ~a"
   "Ukjent oppskriftslinje ~a")
  ("The quantity must be more than 0"
   "Mengden må være større enn 0")
  ("The members must be a list of recipe ids"
   "Medlemmene må være en liste av oppskrift-id-er")
  ("A recipe can be in a choice group only once"
   "En oppskrift kan bare stå én gang i en valggruppe")
  ("A requirement must be an object"
   "Et krav må være et objekt")
  ("The requirement has no field ~a"
   "Kravet har ikke feltet ~a")
  ("The requirement's target must be an object with kind and id"
   "Kravets mål må være et objekt med kind og id")
  ("Fill in the quantity and what the requirement is calculated from"
   "Fyll inn mengde og hva kravet beregnes fra")
  ("Unknown basis ~a; use ~{~a~^, ~}"
   "Ukjent beregningsgrunnlag ~a; bruk ~{~a~^, ~}")
  ("The requirement must be for a stock article, a recipe or a choice group"
   "Kravet må gjelde en lagerartikkel, en oppskrift eller en valggruppe")
  ("Choose a stock article for this requirement"
   "Velg en lagerartikkel for dette kravet")
  ("Choose a recipe for this requirement"
   "Velg en oppskrift for dette kravet")
  ("Choose a choice group for this requirement"
   "Velg en oppskriftgruppe for dette kravet")
  ("The number of choices must be at least 1"
   "Antall valg må være minst 1")
  ("A choice group requirement must be calculated per serving"
   "Valggruppe-krav må beregnes per porsjon")
  ("A number of choices is allowed only on a choice group requirement"
   "Antall valg er kun tillatt for valggruppe-krav")
  ("The rounding must be exact or ceil_per_100"
   "Avrundingen må være exact eller ceil_per_100")
  ("The name can be at most 120 characters"
   "Navnet kan være høyst 120 tegn")
  ("The stock article is archived"
   "Lagerartikkelen er arkivert")
  ("The recipe is archived"
   "Oppskriften er arkivert")
  ("The choice group is archived"
   "Valggruppen er arkivert")
  ("Unknown requirement ~a for this product"
   "Ukjent krav ~a for dette produktet")
  ("The choice ~a does not belong to a choice group requirement of the product"
   "Valget ~a hører ikke til et valggruppe-krav på produktet")
  ("An order line with a choice group requirement must have quantity 1. Add one line per unit."
   "Ordrelinjer med valggruppekrav må ha antall 1. Legg til én linje per enhet.")
  ("Choice group requirement"
   "Valggruppe-krav")
  ("~a needs ~d choices (~d chosen)"
   "~a krever ~d valg (~d valgt)")
  ("The servings must be shared evenly between ~d choices"
   "Porsjoner må deles likt på ~d valg")
  ("~a holds choices that are not valid"
   "~a inneholder ugyldige valg")
  ("Missing required field: input.product_id"
   "Mangler påkrevd felt: input.product_id"))
