;;;; tests/orders-depth-tests.lisp -- orders README §1–§7: orders, statuses and locks
;;;; they carry: statuses and locks (1, 2), quotes (3, 4), logistics (5),
;;;; pricing modes (6), checklists (7), dateless orders (13) and capacity (14).

(in-package #:tun.tests)

(def-suite orders-depth :in core)
(in-suite orders-depth)

(defun message-of (json) (jget (jget json "error") "message"))

(defmacro is-error (code message form)
  "FORM (a CALL) fails with CODE, and with MESSAGE when it is a string."
  (let ((json (gensym)) (got (gensym)))
    `(multiple-value-bind (,json ,got) ,form
       (is (equal ,code ,got) "~s: expected ~a, got ~a ~a" ',form ,code ,got (to-json-string ,json))
       ,@(when message `((is (equal ,message (message-of ,json)) "message ~s" (message-of ,json)))))))

(defun line (product quantity &rest more)
  (apply #'jobj "product_id" product "quantity" quantity more))

(defun new-order (customer &rest args)
  (apply #'call-ok "orders_create" "employee:anna" "customer_id" customer args))

(defun order-of (id) (call-ok "orders_get" "viewer:vera" "id" id))

(defun confirmed-order (customer machine date &optional end-date)
  (let ((id (jget (apply #'new-order customer "event_date" date "lines" (jarr (list (line machine 1)))
                         (and end-date (list "end_date" end-date)))
                  "id")))
    (advance-to-accepted id)
    (two-step "orders_confirm" "employee:anna" "id" id)
    id))

;;; ------------------------------------------------------------------
;;; §4 pricing modes, invariant 6

(test line-and-order-price-modes
  (with-test-app ()
    (let* ((customer (make-customer))
           (p (make-product :name "Ting" :kind "tjeneste" :price 10000 :units-owned 0)))
      ;; 3 × 10000 = 30000 per line
      (let ((o (new-order customer "lines" (jarr (list (line p 3)
                                                       (line p 3 "price_mode" "prosent_rabatt" "discount_percent" 12.5)
                                                       (line p 3 "price_mode" "fast_rabatt" "discount_ore_input" 40000)
                                                       (line p 3 "price_mode" "manuell_total" "manual_total_ore" 45000))))))
        (let ((ls (coerce (jget o "lines") 'list)))
          (is (equal '(30000 26250 0 45000) (mapcar (lambda (l) (jget l "line_effective_ore")) ls))
              "percent rounds the discount down; fixed floors at 0; manual is exact (may exceed)")
          (is (equal '(0 -3750 -30000 15000) (mapcar (lambda (l) (jget l "line_adjustment_ore")) ls)))
          (is (equal '(30000 30000 30000 30000) (mapcar (lambda (l) (jget l "line_total_ore")) ls))))
        (is (= 120000 (jget o "catalog_total_ore")))
        (is (= 101250 (jget o "subtotal_ore")))
        (is (= 101250 (jget o "total_ore")))
        (is (= 0 (jget o "adjustment_ore")))
        (is (string= "automatisk" (jget o "price_mode"))))
      ;; Order modes replace the automatic discount; adjustment = total - subtotal.
      (let ((o (new-order customer "lines" (jarr (list (line p 3))) "price_mode" "prosent_rabatt" "discount_percent" 10)))
        (is (equal '(30000 30000 0 -3000 27000)
                   (mapcar (lambda (k) (jget o k)) '("catalog_total_ore" "subtotal_ore" "discount_ore" "adjustment_ore" "total_ore")))))
      (let ((o (new-order customer "lines" (jarr (list (line p 3))) "price_mode" "fast_rabatt" "discount_ore_input" 99999)))
        (is (= 0 (jget o "total_ore")) "floored at 0")
        (is (= -30000 (jget o "adjustment_ore"))))
      ;; Messages, and nothing stored.
      (let ((before (length (jget (call-ok "orders_list" "viewer:vera" "limit" 100) "items"))))
        (is-error "invalid_input" "Prisvalg er ikke tillatt her"
                  (call "orders_create" "employee:anna" "customer_id" customer "lines" (jarr (list (line p 1)))
                        "price_mode" "manuell_total"))
        (is-error "invalid_input" "Rabattprosent må fylles ut"
                  (call "orders_create" "employee:anna" "customer_id" customer
                        "lines" (jarr (list (line p 1 "price_mode" "prosent_rabatt")))))
        (is-error "invalid_input" "Rabattprosent må være mellom 0 og 100"
                  (call "orders_create" "employee:anna" "customer_id" customer
                        "lines" (jarr (list (line p 1 "price_mode" "prosent_rabatt" "discount_percent" 101)))))
        (is-error "invalid_input" nil
                  (call "orders_create" "employee:anna" "customer_id" customer
                        "lines" (jarr (list (line p 1 "price_mode" "prosent_rabatt" "discount_percent" 10.555d0)))))
        (is-error "invalid_input" "Rabattbeløp må fylles ut"
                  (call "orders_create" "employee:anna" "customer_id" customer
                        "lines" (jarr (list (line p 1 "price_mode" "fast_rabatt")))))
        (is-error "invalid_input" "Rabattbeløp kan ikke være negativt"
                  (call "orders_create" "employee:anna" "customer_id" customer
                        "lines" (jarr (list (line p 1 "price_mode" "fast_rabatt" "discount_ore_input" -1)))))
        (is-error "invalid_input" "Manuell total må fylles ut"
                  (call "orders_create" "employee:anna" "customer_id" customer
                        "lines" (jarr (list (line p 1 "price_mode" "manuell_total")))))
        (is-error "invalid_input" "Manuell total kan ikke være negativ"
                  (call "orders_create" "employee:anna" "customer_id" customer
                        "lines" (jarr (list (line p 1 "price_mode" "manuell_total" "manual_total_ore" -5)))))
        (is-error "invalid_input" nil
                  (call "orders_create" "employee:anna" "customer_id" customer "lines" (jarr (list (line p 1)))
                        "total_ore" 1))
        (is (= before (length (jget (call-ok "orders_list" "viewer:vera" "limit" 100) "items"))))))))

(defclass ten-percent-feature () ())
(defclass priced-app (ten-percent-feature application) ())
(defmethod tun.orders:order-discount ((app ten-percent-feature) order customer)
  (declare (ignore customer))
  (floor (tun.orders:order-subtotal-ore order) 10))

(test the-automatic-discount-seam-works-on-the-subtotal-of-effective-lines
  (with-test-app (:class 'priced-app)
    (let* ((customer (make-customer))
           (p (make-product :name "Ting" :kind "tjeneste" :price 10000 :units-owned 0))
           (o (new-order customer "lines" (jarr (list (line p 2 "price_mode" "fast_rabatt" "discount_ore_input" 5000))))))
      (is (equal '(20000 15000 1500 -1500 13500)
                 (mapcar (lambda (k) (jget o k)) '("catalog_total_ore" "subtotal_ore" "discount_ore" "adjustment_ore" "total_ore"))))
      ;; An explicit order mode replaces the seam: discount_ore 0.
      (let ((u (call-ok "orders_update" "employee:anna" "id" (jget o "id") "revision" (jget o "revision")
                        "price_mode" "fast_rabatt" "discount_ore_input" 1000)))
        (is (equal '(0 -1000 14000) (mapcar (lambda (k) (jget u k)) '("discount_ore" "adjustment_ore" "total_ore"))))))))

;;; ------------------------------------------------------------------
;;; §6 logistics, invariant 5

(defun logistics (&key (delivery (jobj "not_agreed" t)) (return (jobj "not_agreed" t)) address)
  (let ((l (jobj "delivery" delivery "return" return)))
    (when address (setf (gethash "site_address" l) address))
    l))

(defun side (method earliest latest)
  (jobj "not_agreed" nil "method" method "earliest" earliest "latest" latest))

(test logistics-are-either-not-agreed-or-complete
  (with-test-app ()
    (let* ((customer (make-customer))
           (p (make-product :name "Ting" :kind "tjeneste" :price 100 :units-owned 0))
           (ls (jarr (list (line p 1)))))
      (flet ((try (l &rest more) (apply #'call "orders_create" "employee:anna" "customer_id" customer
                                        "event_date" "2026-06-20" "lines" ls "logistics" l more)))
        ;; Default: both sides not agreed, site_address = delivery_address.
        (let ((o (new-order customer "event_date" "2026-06-20" "lines" ls "delivery_address" "Storgata 1")))
          (is (eq t (jget (jget (jget o "logistics") "delivery") "not_agreed")))
          (is (string= "Storgata 1" (jget (jget o "logistics") "site_address")))
          (is (eq nil (jget o "logistics_settled")))
          (is (string= "Ikke avtalt" (jget (jget o "logistics_summary") "delivery"))))
        (is-error "invalid_input" "Velg utleveringsmetode"
                  (try (logistics :delivery (jobj "not_agreed" nil))))
        (is-error "invalid_input" "Velg returmetode"
                  (try (logistics :return (jobj "not_agreed" nil))))
        (is-error "invalid_input" "Sett tidsvindu for utlevering"
                  (try (logistics :delivery (side "kunde_henter" "10:00" :null))))
        (is-error "invalid_input" "Sett tidsvindu for retur"
                  (try (logistics :return (side "kunde_returnerer" :null "12:00"))))
        (is-error "invalid_input" "Utlevering senest kan ikke være før tidligst"
                  (try (logistics :delivery (side "kunde_henter" "12:00" "10:00"))))
        (is-error "invalid_input" "Retur senest kan ikke være før tidligst"
                  (try (logistics :return (side "kunde_returnerer" "12:00" "10:00"))))
        (is-error "invalid_input" "Retur kan ikke starte før utlevering er ferdig samme dag"
                  (try (logistics :delivery (side "kunde_henter" "10:00" "12:00")
                                  :return (side "kunde_returnerer" "11:00" "13:00"))))
        (is-error "invalid_input" "Adresse må fylles ut når vi leverer eller henter hos kunde"
                  (try (logistics :delivery (side "vi_leverer" "10:00" "12:00") :address "  ")))
        ;; First failure wins: method before window.
        (is-error "invalid_input" "Velg utleveringsmetode"
                  (try (logistics :delivery (jobj "not_agreed" nil) :return (side "kunde_returnerer" "12:00" "10:00"))))
        ;; Multi-day orders may return earlier in the day than delivery.
        (is (jget (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
                           "end_date" "2026-06-22" "lines" ls
                           "logistics" (logistics :delivery (side "kunde_henter" "10:00" "12:00")
                                                  :return (side "kunde_returnerer" "08:00" "09:00")))
                  "id"))
        ;; Normalisation: a not-agreed side loses method and times; no side
        ;; needing an address clears it; the address is trimmed.
        (let ((o (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20" "lines" ls
                          "logistics" (logistics :delivery (jobj "not_agreed" t "method" "vi_leverer" "earliest" "10:00")
                                                 :return (side "kunde_returnerer" "14:00" "14:00")
                                                 :address "Storgata 1"))))
          (is (json-null-p (jget (jget (jget o "logistics") "delivery") "method")))
          (is (json-null-p (jget (jget o "logistics") "site_address")))
          (is (json-null-p (jget o "delivery_address")) "site_address and delivery_address are one value")
          (is (string= "Kunde returnerer kl. 14:00" (jget (jget o "logistics_summary") "return"))))
        (let ((o (call-ok "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20" "lines" ls
                          "logistics" (logistics :delivery (side "vi_leverer" "08:00" "10:00")
                                                 :return (side "vi_henter" "22:00" "23:30")
                                                 :address "  Kaia 3  "))))
          (is (string= "Kaia 3" (jget (jget o "logistics") "site_address")))
          (is (string= "Kaia 3" (jget o "delivery_address")))
          (is (eq t (jget o "logistics_settled")))
          (is (equal '("Vi leverer 08:00-10:00" "Vi henter 22:00-23:30")
                     (list (jget (jget o "logistics_summary") "delivery") (jget (jget o "logistics_summary") "return")))))))))

;;; ------------------------------------------------------------------
;;; §3 order fields, dateless orders, invariant 13

(test order-fields-and-dateless-requests
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product))
           (ls (jarr (list (line machine 1)))))
      (is-error "invalid_input" "Sluttdato kan ikke være før startdato"
                (call "orders_create" "employee:anna" "customer_id" customer "event_date" "2026-06-20"
                      "end_date" "2026-06-19" "lines" ls))
      (is-error "invalid_input" nil
                (call "orders_create" "employee:anna" "customer_id" customer "lines" ls "tags" (jarr '("utleie" "utleie"))))
      (let ((o (new-order customer "lines" ls "tags" (jarr '("utleie" "underholdning")))))
        (is (eq t (jget o "dateless")))
        (is (eq nil (jget o "locked")))
        (is (eq t (jget o "requires_pickup")))
        (is (equalp #("utleie" "underholdning") (jget o "tags")))
        (is (json-null-p (jget o "quote")))
        ;; A quote may be sent without a date; confirmation still needs one.
        (is (string= "tilbud_sendt" (jget (call-ok "orders_send_quote" "employee:anna" "id" (jget o "id")) "status")))
        (call-ok "orders_accept" "employee:anna" "id" (jget o "id"))
        (is-error "invalid_input" nil (two-step "orders_confirm" "employee:anna" "id" (jget o "id")))
        (is (equalp #() (jget (order-of (jget o "id")) "bookings")) "dateless orders never book"))
      (let ((dated (jget (new-order customer "event_date" "2026-06-20" "end_date" "2026-06-22" "lines" ls) "id")))
        (flet ((ids (&rest args)
                 (map 'list (lambda (o) (jget o "id")) (jget (apply #'call-ok "orders_list" "viewer:vera" args) "items"))))
          (is (= 1 (length (ids "dateless" t))))
          (is (member dated (ids "dateless" nil) :test #'string=))
          (is (member dated (ids "from" "2026-06-22" "to" "2026-06-30") :test #'string=) "overlap uses end_date")
          (is (not (member dated (ids "from" "2026-06-23") :test #'string=)))
          (is (not (member dated (ids "to" "2026-06-19") :test #'string=)))
          (is (= 1 (length (ids "tag" "underholdning"))))))
      (let ((summary (call-ok "orders_summary" "viewer:vera")))
        (is (= 2 (jget summary "total")))
        (is (= 1 (jget summary "dateless")))
        (is (= 2 (jget summary "not_started")))))))

;;; ------------------------------------------------------------------
;;; §3.2, §3.3 statuses and locks, invariants 1, 2 and 14

(test the-status-machine-and-its-locks
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 1))
           (service (make-product :name "Tjeneste" :kind "tjeneste" :units-owned 0))
           (order (confirmed-order customer machine "2026-06-20")))
      (flet ((status () (jget (order-of order) "status"))
             (revision () (jget (order-of order) "revision"))
             (blocked (date) (jget (call-ok "availability_check" "viewer:vera" "product_id" machine "date" date) "blocked")))
        (is (= 1 (blocked "2026-06-20")))
        ;; Any other pair is invalid_transition and stores nothing.
        (let ((rev (revision)))
          (is-error "invalid_transition" nil (call "orders_register_return" "employee:anna" "id" order "condition" "ok"))
          (is-error "invalid_transition" nil (call "orders_reactivate" "employee:anna" "id" (jget (new-order customer "lines" (jarr (list (line machine 1)))) "id")))
          (is-error "invalid_transition" nil (call "orders_accept" "employee:anna" "id" order))
          (is (= rev (revision))))
        (is-error "conflict" nil (call "orders_register_pickup" "employee:anna" "id" order "condition" "ok" "revision" 0))
        ;; Pickup releases the booking; return records condition, damages, fee.
        (let ((picked (call-ok "orders_register_pickup" "employee:anna" "id" order "condition" "ok")))
          (is (string= "hentet" (jget picked "status")))
          (is (string= "employee:anna" (jget (jget picked "pickup") "by"))))
        (is (= 0 (blocked "2026-06-20")) "hentet holds no booking")
        (is-error "invalid_transition" nil (two-step "orders_cancel" "employee:anna" "id" order))
        ;; Invoicing readiness needs the return, unless an admin forces it with a reason.
        (is-error "invalid_transition" "kan ikke fakturere før retur er registrert; utleie-ordrer krever retur før faktura"
                  (call "orders_ready_for_invoice" "employee:anna" "id" order))
        (is-error "forbidden" nil (call "orders_ready_for_invoice" "employee:anna" "id" order "force" t "reason" "x"))
        (is-error "invalid_input" nil (call "orders_ready_for_invoice" "admin:jonas" "id" order "force" t "reason" " "))
        (let ((returned (call-ok "orders_register_return" "employee:anna" "id" order "condition" "skadet"
                                 "damages" "bulk" "fee_ore" 5000)))
          (is (= 5000 (jget (jget returned "return") "fee_ore"))))
        (is (string= "send_faktura" (jget (call-ok "orders_ready_for_invoice" "employee:anna" "id" order) "status")))
        ;; Locked: send_faktura refuses edits with the lock message.
        (is (eq t (jget (order-of order) "locked")))
        (is-error "conflict" "Ordren er låst (send faktura eller fullført). Åpne ordren for redigering først."
                  (call "orders_update" "employee:anna" "id" order "revision" (revision) "delivery_address" "x"))
        (is-error "conflict" "Ordren er låst (send faktura eller fullført). Åpne ordren for redigering først."
                  (call "checklists_add_manual" "employee:anna" "order_id" order "description" "x"))
        ;; A status tool that never applies to a locked order answers invalid_transition.
        (is-error "invalid_transition" nil (call "orders_send_quote" "employee:anna" "id" order))
        ;; Complete from send_faktura; fullført refuses updates with invalid_transition.
        (is (string= "fullført" (jget (call-ok "orders_complete" "employee:anna" "id" order) "status")))
        (is-error "invalid_transition" nil
                  (call "orders_update" "employee:anna" "id" order "revision" (revision) "delivery_address" "x"))
        ;; Reopen: admin, two steps; re-books, unlocks.
        (is-error "forbidden" nil (call "orders_reopen" "employee:anna" "id" order))
        (multiple-value-bind (reopened code) (two-step "orders_reopen" "admin:jonas" "id" order)
          (is (null code))
          (is (string= "bekreftet" (jget reopened "status")))
          (is (eq nil (jget reopened "locked"))))
        (is (= 1 (blocked "2026-06-20")) "reopen re-books")
        ;; Reopen fails (unavailable, as confirmation does) when the capacity is gone.
        (call-ok "orders_register_pickup" "employee:anna" "id" order "condition" "ok")
        (call-ok "orders_ready_for_invoice" "admin:jonas" "id" order "force" t "reason" "kunden betaler før retur")
        (let ((other (confirmed-order customer machine "2026-06-20")))
          (is (stringp other))
          (is-error "unavailable" nil (two-step "orders_reopen" "admin:jonas" "id" order)))
        (is (string= "send_faktura" (status)))
        ;; The forced readiness carries its reason in the audit entry.
        (let ((entry (find "orders_ready_for_invoice"
                           (coerce (jget (call-ok "audit_list" "viewer:vera" "entity_type" "order" "entity_id" order) "items") 'list)
                           :key (lambda (e) (jget e "tool")) :test #'string=)))
          (is (string= "kunden betaler før retur" (jget entry "reason"))))
        ;; Pickup is only for orders with utleie lines.
        (let ((service-order (confirmed-order customer service "2026-07-01")))
          (is-error "invalid_transition" "henting/retur gjelder bare ordrer med produkter av type utleie"
                    (call "orders_register_pickup" "employee:anna" "id" service-order "condition" "ok"))
          (is (string= "send_faktura" (jget (call-ok "orders_ready_for_invoice" "employee:anna" "id" service-order) "status"))
              "no return needed without utleie lines")
          (is (string= "avbrutt" (jget (two-step "orders_cancel" "employee:anna" "id" service-order) "status"))))
        ;; Reactivate: avbrutt -> utkast.
        (let ((cancelled (jget (new-order customer "lines" (jarr (list (line machine 1)))) "id")))
          (two-step "orders_cancel" "employee:anna" "id" cancelled)
          (is (string= "utkast" (jget (call-ok "orders_reactivate" "employee:anna" "id" cancelled) "status"))))))))

;;; ------------------------------------------------------------------
;;; §5 quotes, invariants 3 and 4

(defun quote-of (order) (call-ok "quotes_get" "admin:jonas" "order_id" order))

(test quotes-are-objects-with-revisions-codes-and-expiry
  (with-test-app ()
    (let* ((customer (make-customer))
           (p (make-product :name "Ting" :kind "tjeneste" :price 10000 :units-owned 0))
           (order (jget (new-order customer "event_date" "2026-06-20" "lines" (jarr (list (line p 1)))) "id")))
      (is-error "not_found" nil (call "quotes_get" "viewer:vera" "order_id" order))
      (let ((preview (jget (call-ok "quotes_preview" "viewer:vera" "order_id" order) "snapshot")))
        (is (= 10000 (jget preview "total_ore")))
        (is (string= "Ting" (jget (aref (jget preview "lines") 0) "name"))))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (let* ((q (quote-of order))
             (code (jget q "access_code")))
        (is (= 1 (jget q "revision")))
        (is (string= "awaiting_response" (jget q "status")))
        (is (cl-ppcre:scan "^[A-Z2-7]{10}$" code))
        (is (json-null-p (jget (call-ok "quotes_get" "employee:anna" "order_id" order) "access_code"))
            "only an admin sees the code")
        (is (eq nil (jget q "stale")))
        ;; Editing after sending makes it stale; re-issuing bumps the revision, keeps id and code.
        (let ((o (order-of order)))
          (call-ok "orders_update" "employee:anna" "id" order "revision" (jget o "revision") "event_date" "2026-06-21"))
        (is (eq t (jget (quote-of order) "stale")))
        (call-ok "orders_send_quote" "employee:anna" "id" order)
        (let ((q2 (quote-of order)))
          (is (= 2 (jget q2 "revision")))
          (is (string= (jget q "id") (jget q2 "id")))
          (is (string= code (jget q2 "access_code")))
          (is (eq nil (jget q2 "stale"))))
        ;; Responses: wrong code is forbidden (audited), an old revision is conflict.
        (is-error "forbidden" nil (call "quotes_respond" "viewer:kunde" "quote_id" (jget q "id") "revision" 2
                                        "access_code" "AAAAAAAAAA" "response" "accept"))
        (is-error "conflict" "tilbudet er endret; last siden på nytt"
                  (call "quotes_respond" "viewer:kunde" "quote_id" (jget q "id") "revision" 1
                        "access_code" code "response" "accept"))
        ;; Decline: the order stays tilbud_sendt; the quote can be re-issued.
        (let ((declined (call-ok "quotes_respond" "viewer:kunde" "quote_id" (jget q "id") "revision" 2
                                 "access_code" (format nil " ~a " (string-downcase code)) "response" "decline")))
          (is (string= "declined" (jget declined "status"))))
        (is (string= "tilbud_sendt" (jget (order-of order) "status")))
        (is-error "invalid_transition" nil (call "quotes_respond" "viewer:kunde" "quote_id" (jget q "id") "revision" 2
                                                 "access_code" code "response" "accept"))
        (call-ok "orders_send_quote" "employee:anna" "id" order)
        ;; Accept with the current revision: the order is akseptert, audited as the customer.
        (let ((accepted (call-ok "quotes_respond" "viewer:kunde" "quote_id" (jget q "id") "revision" 3
                                 "access_code" code "response" "accept")))
          (is (string= "accepted" (jget accepted "status")))
          (is (stringp (jget accepted "responded_at"))))
        (is (string= "akseptert" (jget (order-of order) "status")))
        (let ((entries (coerce (jget (call-ok "audit_list" "viewer:vera" "entity_type" "quote" "entity_id" (jget q "id")) "items") 'list)))
          (is (find (format nil "customer:~a" (jget q "id")) entries :key (lambda (e) (jget e "actor")) :test #'string=))
          (is (find "rejected" entries :key (lambda (e) (jget e "outcome")) :test #'string=)))))
    ;; Expiry is derived: 14 days after sending.
    (let* ((customer (make-customer "Kari Utløp"))
           (p (make-product :name "Ting2" :kind "tjeneste" :price 10000 :units-owned 0))
           (order (jget (new-order customer "lines" (jarr (list (line p 1)))) "id")))
      (call-ok "orders_send_quote" "employee:anna" "id" order)
      (let ((q (quote-of order)))
        (call-ok "clock_set" "admin:jonas" "now" (format-rfc3339 (+ (now-of *app*) (* 15 86400))))
        (is (string= "expired" (jget (quote-of order) "status")))
        (is-error "conflict" "tilbudet er utløpt; send et nytt tilbud"
                  (call "quotes_respond" "viewer:kunde" "quote_id" (jget q "id") "revision" 1
                        "access_code" (jget q "access_code") "response" "accept"))))))

(defun now-of (app) (with-application (app) (now)))

;;; ------------------------------------------------------------------
;;; §7 checklists, invariant 7

(defvar *component* nil "The consumable each line needs 10 of per unit (checklist tests).")
(defclass component-feature () ())
(defclass checklist-app (component-feature application) ())
(defmethod tun.orders:compute-order-requirements ((app component-feature) order)
  (append (call-next-method)
          (loop for line in (tun.orders:order-lines order)
                collect (cons *component* (* 10 (tun.orders:order-line-quantity line))))))

(test checklists-follow-requirements-and-carry-packing-over
  (with-test-app (:class 'checklist-app)
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 5))
           (*component* (make-product :name "Beger" :kind "forbruk" :unit "stk" :price 100 :stock-tracked t
                                      :units-owned 0))
           (o (new-order customer "event_date" "2026-06-20" "lines" (jarr (list (line machine 2)))))
           (id (jget o "id")))
      (flet ((items () (coerce (jget (call-ok "checklists_list" "viewer:vera" "order_id" id) "items") 'list))
             (update (quantity)
               (let ((current (order-of id)))
                 (call-ok "orders_update" "employee:anna" "id" id "revision" (jget current "revision")
                          "lines" (jarr (list (jobj "product_id" machine "quantity" quantity)))))))
        (let ((item (first (items))))
          (is (= 1 (length (items))))
          (is (string= (format nil "lager:~a:stk" *component*) (jget item "source_key")))
          (is (string= "Beger: 20 stk" (jget item "description")))
          (is (string= "automatic" (jget item "origin")))
          (is (= 20 (jget item "computed_quantity")))
          (is (eq nil (jget (order-of id) "packed")))
          ;; Mark done: done_quantity = computed.
          (call-ok "checklists_mark" "employee:anna" "id" (jget item "id") "done" t))
        (is (eq t (jget (order-of id) "packed")))
        ;; Raising the quantity: carried 20 < 30 -> not done, 20 carried.
        (update 3)
        (let ((item (first (items))))
          (is (equal '(30 20 nil) (list (jget item "computed_quantity") (jget item "done_quantity") (jget item "done")))))
        ;; Lowering it to the carried amount: done again.
        (update 2)
        (let ((item (first (items))))
          (is (equal '(20 20 t) (list (jget item "computed_quantity") (jget item "done_quantity") (jget item "done")))))
        ;; Lowering further: carried 20 > 10 -> not done, 20 kept.
        (update 1)
        (let ((item (first (items))))
          (is (equal '(10 20 nil) (list (jget item "computed_quantity") (jget item "done_quantity") (jget item "done")))))
        ;; Manual items are never touched by sync; sync is idempotent.
        (let ((manual (call-ok "checklists_add_manual" "employee:anna" "order_id" id "description" "Skjøteledning")))
          (is (string= "manual" (jget manual "origin")))
          (let* ((rev (jget (order-of id) "revision"))
                 (sync (call-ok "checklists_sync" "employee:anna" "order_id" id)))
            (is (equal '(0 0 0) (list (jget sync "created") (jget sync "updated") (jget sync "deleted"))))
            (is (= rev (jget (order-of id) "revision")) "a sync that changes nothing stores nothing"))
          (is (find "Skjøteledning" (items) :key (lambda (i) (jget i "description")) :test #'string=))
          (is-error "invalid_input" nil (call "checklists_delete" "employee:anna" "id" (jget (first (items)) "id")))
          (is (eq t (jget (call-ok "checklists_delete" "employee:anna" "id" (jget manual "id")) "deleted"))))
        ;; A line removed -> its automatic item goes; partial packing with done false.
        (let ((item (first (items))))
          (call-ok "checklists_mark" "employee:anna" "id" (jget item "id") "done" nil "done_quantity" 4)
          (let ((marked (first (items))))
            (is (equal '(4 nil) (list (jget marked "done_quantity") (jget marked "done"))))))))))

;;; §3.2 and 12.1.24: only bekreftet reserves.  Pickup releases the
;;; reservations with the bookings, and completion from send_faktura consumes
;;; nothing.

(test pickup-releases-reservations-and-later-steps-consume-nothing
  (with-test-app (:class 'checklist-app)
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 1))
           (*component* (make-product :name "Beger" :kind "forbruk" :unit "stk" :price 100 :stock-tracked t
                                      :units-owned 0))
           (order (progn (call-ok "inventory_receive" "employee:anna" "product_id" *component* "quantity" 100)
                         (confirmed-order customer machine "2026-06-20"))))
      (flet ((balance () (let ((b (call-ok "inventory_balance" "viewer:vera" "product_id" *component*)))
                           (list (jget b "on_hand") (jget b "reserved")))))
        (is (equal '(100 10) (balance)) "confirmation reserves 10 beger")
        (call-ok "orders_register_pickup" "employee:anna" "id" order "condition" "ok")
        ;; Pickup consumes the plan (orders README §10.2).
        (is (equal '(90 0) (balance)) "pickup releases the reservation and consumes")
        (call-ok "orders_register_return" "employee:anna" "id" order "condition" "ok")
        (call-ok "orders_ready_for_invoice" "employee:anna" "id" order)
        (is (string= "fullført" (jget (call-ok "orders_complete" "employee:anna" "id" order) "status")))
        (is (equal '(90 0) (balance)) "completion from send_faktura consumes nothing more and reserves nothing")))))

(test multi-day-orders-book-and-check-every-date
  ;; Slice 1 12.1.28 (review finding 4): a multi-day order books
  ;; event_date..end_date, and confirming checks capacity on each of its dates.
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 1))
           (long (confirmed-order customer machine "2026-06-01" "2026-06-10")))
      (let ((booking (aref (jget (order-of long) "bookings") 0)))
        (is (equal '("2026-06-01" "2026-06-10") (list (jget booking "from") (jget booking "to")))))
      (flet ((free-on (date) (jget (call-ok "availability_check" "viewer:vera" "product_id" machine "date" date) "ok"))
             (accepted (date &optional end)
               (let ((id (jget (apply #'new-order customer "event_date" date "lines" (jarr (list (line machine 1)))
                                      (and end (list "end_date" end)))
                               "id")))
                 (advance-to-accepted id)
                 id)))
        (is (eq nil (free-on "2026-06-06")) "a date inside the order is taken")
        (is (eq t (free-on "2026-06-11")))
        (let ((inside (accepted "2026-06-06")))
          (is-error "unavailable" nil (two-step "orders_confirm" "employee:anna" "id" inside))
          (is (equal "akseptert" (jget (order-of inside) "status"))))
        (let ((overlapping (accepted "2026-05-25" "2026-06-02")))
          (is-error "unavailable" nil (two-step "orders_confirm" "employee:anna" "id" overlapping)))
        (is (stringp (confirmed-order customer machine "2026-06-11" "2026-06-12")) "the next day is free")))))

(test completion-counts-once-per-order
  ;; Slice 1 12.1.27: reopening from fullført decrements the customer's
  ;; completed-order count, so completing again counts the order once.
  (with-test-app ()
    (let* ((customer (make-customer))
           (machine (make-product :units-owned 1))
           (order (confirmed-order customer machine "2026-06-20")))
      (flet ((completed () (jget (call-ok "customers_get" "viewer:vera" "id" customer) "completed_orders"))
             (complete () (call-ok "orders_register_pickup" "employee:anna" "id" order "condition" "ok")
                          (call-ok "orders_register_return" "employee:anna" "id" order "condition" "ok")
                          (call-ok "orders_ready_for_invoice" "employee:anna" "id" order)
                          (call-ok "orders_complete" "employee:anna" "id" order)))
        (complete)
        (is (= 1 (completed)))
        (two-step "orders_reopen" "admin:a" "id" order)
        (is (equal "bekreftet" (jget (order-of order) "status")))
        (is (= 0 (completed)) "reopen from fullført decrements")
        (complete)
        (is (= 1 (completed)) "completing again counts the order once")))))
