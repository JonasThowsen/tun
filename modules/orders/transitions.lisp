;;;; modules/orders/transitions.lisp -- the order status machine (README §2.2)
;;;; and its locks (§2.3).  Every transition takes an optional revision (a
;;;; stale one is conflict); every other (from, to) pair is
;;;; invalid_transition and nothing is stored.

(in-package #:tun.orders)

(declaim (optimize (safety 3) (debug 2)))

(defun load-for-transition (id revision &key lock)
  "The order ID, checked against REVISION and, with LOCK, refused when locked."
  (let ((order (find-order id)))
    (check-revision order revision)
    (when lock (check-order-not-locked order))
    order))

(defun close-guard (order tool)
  "Completing, invoicing readiness and cancelling may be refused by a seam
(staffing: a running work session)."
  (order-closure-check *application* order tool))

(defun actor-admin-p () (eq :admin (actor-role *actor*)))

;;; ------------------------------------------------------------------
;;; Quote, acceptance, confirmation

(define-operation orders-send-quote ((id :type (id order) :required t :label "Ordre-ID")
                                     (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :title "Send tilbud"
     :description "utkast eller tilbud_sendt → tilbud_sendt. Lager tilbudet (revisjon 1) eller sender det på nytt (revisjon + 1, samme kode), og sender det til kunden. Kan sendes uten dato.")
  ;; Allowed only from utkast and tilbud_sendt, never locked: any other status
  ;; is invalid_transition (the lock message is for what a locked order allows).
  (let ((order (load-for-transition id revision))
        (customer nil))
    (transition order '("utkast" "tilbud_sendt") "tilbud_sendt")
    (setf customer (order-customer order))
    (when (blank-p (customer-email customer))
      (fail :invalid-transition "Kunden har ingen e-postadresse; tilbudet kan ikke sendes"))
    (issue-quote order customer)
    (setf (order-accepted-snapshot-stale order) nil)
    (save order)
    ;; Through the kernel's messaging port: nothing is sent without messaging.
    (notify "tilbud" :order order :customer customer)
    order))

(defun accept-order (order)
  "tilbud_sendt -> akseptert, recording the answer on the quote."
  (transition order '("tilbud_sendt") "akseptert")
  (let ((quote (quote-for-order (entity-id order))))
    (when quote
      (when (quote-stale-p quote order) (setf (order-accepted-snapshot-stale order) t))
      (setf (order-quote-status quote) "accepted"
            (order-quote-responded-at quote) (now))
      (save quote)))
  order)

(define-operation orders-accept ((id :type (id order) :required t :label "Ordre-ID")
                                 (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :title "Aksepter tilbud"
     :description "tilbud_sendt → akseptert: kunden har akseptert tilbudet (registrert av en ansatt). Tilbudet merkes akseptert.")
  (let ((order (load-for-transition id revision)))
    (accept-order order)
    (save order)))

(defun confirm-summary ()
  (let* ((order (find-order (input-value :id)))
         (customer (order-customer order)))
    (format nil "Bekreft ordre ~a for ~a, arrangement ~a, totalt ~a kr. Utstyr bookes og forbruksvarer reserveres."
            (entity-id order) (customer-name customer) (or (order-event-date order) "(ingen dato)")
            (format-kroner (order-total-ore order)))))

(define-operation orders-confirm ((id :type (id order) :required t :label "Ordre-ID")
                                  (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :confirm t :destructive t :title "Bekreft ordre"
     :summary confirm-summary
     :description "akseptert → bekreftet. Krever arrangementsdato; booker utleieutstyr (unavailable ved kapasitetsmangel), reserverer forbruksvarer og planlegger kundens arbeidsflyt. Krever bekreftelse.")
  (let ((order (load-for-transition id revision)))
    ;; The active plan is reserved (README §10.1); a catalog change reaches the order
    ;; through katalog_endring, not through confirmation.
    (transition order '("akseptert") "bekreftet")
    (book-order order)
    (sync-reservations order)
    (setf (order-accepted-snapshot-stale order) nil)
    (save order)))

;;; ------------------------------------------------------------------
;;; Pickup, return, invoicing readiness

(defun check-requires-pickup (order)
  (unless (order-requires-pickup-p order)
    (fail :invalid-transition "henting/retur gjelder bare ordrer med produkter av type utleie")))

(defun handover-record (at &rest keys-and-values)
  (apply #'jobj "at" (format-rfc3339 (or at (now))) (append keys-and-values (list "by" (actor-string *actor*)))))

(define-operation orders-register-pickup ((id :type (id order) :required t :label "Ordre-ID")
                                          (condition :type (string :min 1 :max 500) :required t :label "Tilstand"
                                                     :description "Utstyrets tilstand ved henting.")
                                          (at :type timestamp :label "Tidspunkt" :description "Standard: nå.")
                                          (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :title "Registrer henting"
     :description "bekreftet → hentet: utleieutstyret er hentet. Bare ordrer med utleieprodukter. Frigir bookingene og reservasjonene og trekker forbruket i den aktive kravplanen fra lageret (insufficient_stock avbryter).")
  (let ((order (load-for-transition id revision :lock t)))
    (when (string= (order-status order) "bekreftet") (check-requires-pickup order))
    (transition order '("bekreftet") "hentet")
    ;; A new pickup starts a new rental: an earlier cycle's return is history.
    (setf (order-pickup order) (handover-record at "condition" condition)
          (order-return-record order) nil)
    ;; The machine is out: no booking, and no reservation either (only
    ;; bekreftet reserves; README §10.1).  The consumables go with it:
    ;; the active plan is consumed now (README §10.2; insufficient_stock
    ;; aborts the pickup).
    (release-bookings order)
    (consume order)
    (sync-reservations order)
    (save order)))

(define-operation orders-register-return ((id :type (id order) :required t :label "Ordre-ID")
                                          (condition :type (string :min 1 :max 500) :required t :label "Tilstand")
                                          (damages :type (string :max 2000) :label "Skader")
                                          (fee-ore :type (integer :min 0 :max 9007199254740991) :label "Gebyr (øre)")
                                          (at :type timestamp :label "Tidspunkt" :description "Standard: nå.")
                                          (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :title "Registrer retur"
     :description "hentet → returnert: utleieutstyret er levert tilbake, med tilstand, eventuelle skader og gebyr.")
  (let ((order (load-for-transition id revision :lock t)))
    (check-requires-pickup order)
    (transition order '("hentet") "returnert")
    (setf (order-return-record order)
          (handover-record at "condition" condition "damages" (or damages :null) "fee_ore" (or fee-ore 0)))
    (save order)))

(define-operation orders-ready-for-invoice ((id :type (id order) :required t :label "Ordre-ID")
                                            (force :type boolean :label "Tving (admin)"
                                                   :description "Fakturer utleie før retur er registrert; krever admin og begrunnelse.")
                                            (reason :type (string :max 500) :label "Begrunnelse")
                                            (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :title "Klar til fakturering"
     :description "bekreftet eller returnert → send_faktura (med force også fra hentet). Utleieordrer krever registrert retur, unntatt når en admin tvinger med begrunnelse. Låser ordren og frigir bookingene.")
  (let ((order (load-for-transition id revision)))
    (when (and force (not (actor-admin-p)))
      (reject :forbidden "Bare admin kan tvinge fakturering"))
    ;; From hentet only by force: without it the missing return is the refusal below.
    (transition order '("bekreftet" "returnert" "hentet") "send_faktura")
    (close-guard order "orders_ready_for_invoice")
    (when (and (order-requires-pickup-p order) (null (order-return-record order)))
      (cond ((not force)
             (fail :invalid-transition "kan ikke fakturere før retur er registrert; utleie-ordrer krever retur før faktura"))
            ((blank-p reason)
             (fail :invalid-input "Begrunnelse er påkrevd for å tvinge fakturering før retur"))
            (t (audit-as :reason (trim reason)))))
    (release-bookings order)
    ;; Consumed at the first of pickup, invoicing readiness and completion (§10.2).
    (consume order)
    (sync-reservations order)
    (save order)))

;;; ------------------------------------------------------------------
;;; Completion and cancellation

(define-operation orders-complete ((id :type (id order) :required t :label "Ordre-ID")
                                   (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :title "Fullfør ordre"
     :description "bekreftet eller send_faktura → fullført. Trekker reservert forbruk fra lageret (insufficient_stock avbryter alt), øker kundens antall fullførte ordrer og låser ordren.")
  (let ((order (load-for-transition id revision)))
    (transition order '("bekreftet" "send_faktura") "fullført")
    (close-guard order "orders_complete")
    ;; Completion's ledger effects, once, from the active plan (README
    ;; §10.2): consumed at the first of pickup, invoicing readiness and
    ;; completion, so from send_faktura nothing more.
    (consume order)
    (sync-reservations order)
    (record-completed-order (order-customer-id order))
    (save order)))

(defun cancel-summary ()
  (let ((order (find-order (input-value :id))))
    (format nil "Avbryt ordre ~a (status ~a). Bookinger og reservasjoner frigis, planlagte arbeidsflyter avbrytes."
            (entity-id order) (order-status order))))

(define-operation orders-cancel ((id :type (id order) :required t :label "Ordre-ID")
                                 (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :confirm t :destructive t :title "Avbryt ordre"
     :summary cancel-summary
     :description "utkast, tilbud_sendt, akseptert, bekreftet eller send_faktura → avbrutt. Frigir bookinger og reservasjoner og avbryter planlagte arbeidsflyter. Krever bekreftelse.")
  (let ((order (load-for-transition id revision)))
    (transition order '("utkast" "tilbud_sendt" "akseptert" "bekreftet" "send_faktura") "avbrutt")
    (close-guard order "orders_cancel")
    (release-bookings order)
    ;; A consumed order's consumption is reversed (a later recount wins).
    (reverse-consumption order)
    (sync-reservations order)
    (tun.workflows:cancel-workflows id)
    (save order)))

;;; ------------------------------------------------------------------
;;; Reopening and reactivation

(defun reopen-summary ()
  (let ((order (find-order (input-value :id))))
    (format nil "Åpne ordre ~a (status ~a) for redigering igjen: den blir bekreftet, utstyr bookes på nytt og sjekklisten nullstilles."
            (entity-id order) (order-status order))))

(define-operation orders-reopen ((id :type (id order) :required t :label "Ordre-ID")
                                 (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :confirm t :destructive t :policy :admin :title "Åpne ordre igjen"
     :summary reopen-summary
     :description "send_faktura eller fullført → bekreftet (admin). Låser opp, booker utstyr på nytt (unavailable om kapasiteten er borte), reserverer forbruk igjen og nullstiller sjekklisten. Forbruk som er trukket fra lageret, føres ikke tilbake. Fra fullført telles kundens fullførte ordrer ned igjen.")
  (let* ((order (load-for-transition id revision))
         (was-completed (string= (order-status order) "fullført")))
    (transition order '("send_faktura" "fullført") "bekreftet")
    ;; Completion counts once per order: the next orders_complete counts it again.
    (when was-completed
      (record-reopened-order (order-customer-id order)))
    (book-order order)
    ;; Reserved again unless consumed (reopen from fullført does not reverse it).
    (sync-reservations order)
    (reset-checklist order)
    (save order)))

(define-operation orders-reactivate ((id :type (id order) :required t :label "Ordre-ID")
                                     (revision :type integer :label "Revisjon"))
    (:entity order :kind :transition :title "Gjenoppta som utkast"
     :description "avbrutt, akseptert eller bekreftet → utkast. Frigir bookinger og reservasjoner, avbryter planlagte arbeidsflyter, og et tilbud som venter på svar merkes avslått.")
  (let ((order (load-for-transition id revision)))
    (transition order '("avbrutt" "akseptert" "bekreftet") "utkast")
    (release-bookings order)
    ;; A consumed order is editable again: its consumption is reversed (§10.2).
    (reverse-consumption order)
    (sync-reservations order)
    (tun.workflows:cancel-workflows id)
    (let ((quote (quote-for-order id)))
      (when (and quote (string= (order-quote-status quote) "awaiting_response"))
        (setf (order-quote-status quote) "declined"
              (order-quote-responded-at quote) (now))
        (save quote)))
    (save order)))
