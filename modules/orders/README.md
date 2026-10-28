# tun module `orders`

ASDF system `tun-orders`, package `tun.orders`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** `order`, order lines (with `choices`), bookings, quotes, checklists, requirement plans (fingerprinted over lines sorted by line, article and unit, §9.1), plan impacts and the internal queue of orders a catalog change reached (§11); `orders_*` (with `orders_correct_plan`), `quotes_*`, `checklists_*`, `plans_list`, `plans_get`, `plan_impacts_list`, `availability_check`; the `catalog_change` and `quote_expiry` workflows and the `order_plan` review kind (§9, §10, §11). Order dates lie in 1970..2999, at most 731 days apart (§1.3); stock warnings are computed after the commit (§12.3).
- **Depends on:** `customers`, `catalog`, `inventory`, `reviews`.
- **Core range:** builds against core `>= 2.0.0, < 3.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** seams `discount`, `requirements` (a client that registers it overrides the catalog's resolver, §8.1), `booking_window` (it receives event_date and end_date, §5.2), `suggestions`, `checklist_items`, `departments`, `department_changed`, `closure_guard`, `communication`, `quote_expired` (§14), the `/orders` screens. A client method on a seam computes: if it changes a core field of a record it is given, the kernel refuses the request. Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4, §17 below): it refuses when a record holds a value the
  previous core cannot decode (a status, price mode or movement kind it
  lacks), an order-line field its next write would drop, or a plan that carries requirements or awaits review (the previous core would plan its own way or drop the proposal), and an order line whose `choices` it would drop
  (docs/architecture.md, "Tenants and deployment").

Quote credentials are masked on staff message projections in both raw and
dashed forms, including unthreaded forwarded messages and case variants
(§6.6). An additive, namespaced `access_code` index supports exact known-code
lookup; unrelated code-shaped text remains readable. Stored snapshots are
unchanged.

## Contract

What the module does, as the code implements it. Kernel rules are cited from
`spec/core.md`: data conventions (money in minor units, dates, instants, ids,
revisions, exact decimals) §2.1, local dates §2.2, lists §2.4,
policy §3.3, error codes §3.5, confirmation §3.6, idempotency §3.7, audit
§3.8, workflows §4, settings §5.3, link tokens §5.4. Error messages below are
verbatim, in Norwegian, the `nb` translation of the English in the code
(`spec/i18n.md` §3.7); `~a` stands for a value the message names.

### 1. Orders and lines

#### 1.1 Fields

`order` (id prefix `ord`, revisioned):

| Field | Rule |
|---|---|
| `status` | §2.1; output only, starts `draft` |
| `customer_id` | required; the customer must exist |
| `event_date`, `end_date` | §1.3; `end_date` null means a single day |
| `delivery_address` | ≤ 300; the same stored value as `logistics.site_address` (§4) |
| `lines` | `order_line`, 1..100 on `orders_create` and `orders_update` |
| `tags` | each of `rental`, `entertainment` at most once (`Hvert merke kan bare brukes én gang`) |
| `department` | null, or one of the `departments` seam (§14); else `Ukjent avdeling ~a (gyldige: …)` |
| `price_mode`, `discount_percent`, `discount_input_minor`, `price_reason` | §3.2 |
| `logistics` | §4 |
| `catalog_total_minor`, `subtotal_minor`, `discount_minor`, `adjustment_minor`, `total_minor` | derived, §3 |
| `requirements` | derived: `[{product_id, article_id, quantity}]` per article of the active plan (§8.3) |
| `pickup` | `{at, condition, by}`, set by `orders_register_pickup` |
| `return` | `{at, condition, damages, fee_minor, by}`, set by `orders_register_return` |
| `accepted_snapshot_stale` | true when a stale quote was accepted (§6.4) |
| `source`, `open_questions` | provenance of an order drafted from an inbound request (§13.2) |
| `created_at` | instant |

Computed on output: `bookings` (`[{product_id, quantity, from, to}]`, §5),
`requires_pickup` (some line's product is `rental`), `locked` (§2.3),
`dateless` (`event_date` null), `site_address`, `logistics_settled` and
`logistics_summary` (§4), `quote` (`{id, revision, status, expires_at}` or
null, §6), `packed` (§7.4), `plan` (§9.5), `communication` (§13.3), and on
`orders_get` only `stock_warnings` (§12.3).

`order_line` (embedded): `id`, `product_id`, `quantity` (1..100000),
`price_mode`, `discount_percent`, `discount_input_minor`, `manual_total_minor`,
`price_reason` (≤ 500), `notes` (≤ 1000), `choices` (§8.2), and the derived
`unit_price_minor`, `line_total_minor`, `line_effective_minor`,
`line_adjustment_minor` (§3.1). A client may add line fields; a field named
`servings` feeds the resolver (§8.1).

Rows an older core stored read with defaults: `choices` `{}`,
`line_effective_minor` = `line_total_minor`, `line_adjustment_minor` 0,
`catalog_total_minor` = Σ line totals, `adjustment_minor` = total − subtotal,
`price_mode` `automatic`.

#### 1.2 Revisions

Every accepted change to an order counts a revision (core.md §2.1): its own
fields, its lines, logistics, quote, checklist items, and the staffing
module's assignments and department. Checklist tools touch the order so its
revision moves. What the system derives on its own (an approved plan, a
catalog impact, §9, §11) is stored without a revision. `orders_update`
requires `revision`; every transition tool takes it optionally. A stale one
is `conflict` `Ordren er endret (revisjon ~d, ikke ~d)`.

#### 1.3 Dates

Checked before anything computes with them, so an extreme date is
`invalid_input`, never a failure later:

- each date within 1970-01-01..2999-12-31: `Datoen ~a må ligge mellom ~a og ~a`;
- `end_date` without `event_date`: `Sluttdato krever en startdato`;
- `end_date` before `event_date`: `Sluttdato kan ikke være før startdato`;
- at most 731 days apart: `Sluttdato kan være høyst ~d dager etter startdato`.

Every consumer uses `end_date ?? event_date` as the last day. An order may be
dateless in `draft` and `quote_sent` only (`orders_update` elsewhere:
`Ordren har status ~a og må ha arrangementsdato`). A dateless order can be
quoted, never books, never appears in the calendar and cannot be confirmed.

#### 1.4 Saving an order

`orders_create` and `orders_update` derive the same way: the customer exists,
own fields are valid (§1.3, tags, department), logistics follow the address
(§4), lines are priced (§3), choices are checked (§8.2), totals, discount and
requirements are computed. Derived fields are never inputs.

On `orders_update`, a line keeps its identity (and so its checklist items and
packed quantities) when it carries the id of a line of the order, or else sits
at the same position with the same product. Other lines get new ids; an id
that names no line of the order is `invalid_input` `Linjen ~a finnes ikke på
ordren`. `orders_create` ignores line ids.

`orders_update` refuses `ready_for_invoice` with the lock message (§2.3) and
`completed`/`cancelled` with `invalid_transition` `Ordren er ~a og kan ikke
endres`. In `confirmed` it books again (§5, `unavailable` when capacity is
gone) and the reservations follow (§10.1). A sent quote becomes stale (§6.4).

#### 1.5 Lists and counts

`orders_list` returns orders oldest first, paged (core.md §2.4), filtered by
`customer_id`, `status`, `dateless` (true: only dateless; false: only dated),
`department`, `tag`, and `from`/`to` (orders whose days
`[event_date, end_date ?? event_date]` overlap the range).

`orders_summary` counts all orders: `total`, `not_started`, `active`,
`awaiting_quote` (`quote_sent` with a quote awaiting a response),
`dateless`, `logistics_settled`, `logistics_not_agreed` (a side not agreed),
`closed`, and gives `today`.

### 2. Statuses and transitions

#### 2.1 Statuses

| Status | Label | Group |
|---|---|---|
| `draft` | UTKAST | not started |
| `quote_sent` | TILBUD SENDT | not started |
| `accepted` | AKSEPTERT AV KUNDE | not started |
| `confirmed` | BEKREFTET | active |
| `picked_up` | HENTET | active |
| `returned` | RETURNERT | active |
| `ready_for_invoice` | SEND FAKTURA | active, locked |
| `completed` | FERDIG | closed, final, locked |
| `cancelled` | AVLYST | closed, final |

Calendar-active: `draft`, `quote_sent`, `accepted`, `confirmed`.
Committed (counted by the forecast, §12.1): `confirmed`, `picked_up`,
`returned`, `ready_for_invoice`, `completed`.

#### 2.2 Transitions

A status changes only through these tools. Every other (from, to) pair is
`invalid_transition` `Ordren har status ~a og kan ikke bli ~a` and nothing is
stored. Guards run in the order listed.

| Tool | From | To | Guards | Effects |
|---|---|---|---|---|
| `orders_send_quote` | `draft`, `quote_sent` | `quote_sent` | the customer has an email (`invalid_transition` `Kunden har ingen e-postadresse; tilbudet kan ikke sendes`) | issues the quote (§6.2); sends `quote` through the messaging port (core.md §5.1); schedules its expiry (§6.5) |
| `orders_accept` | `quote_sent` | `accepted` | — | quote `accepted`, `responded_at` now (§6.3) |
| `quotes_respond` accept | `quote_sent` | `accepted` | §6.3 | as `orders_accept` |
| `orders_confirm` (confirm) | `accepted` | `confirmed` | `event_date` (`invalid_input` `Ordren mangler arrangementsdato (event_date)`); capacity (`unavailable`, §5) | books (§5); reserves the active plan (§10.1) |
| `orders_register_pickup` | `confirmed` | `picked_up` | not locked; `requires_pickup` (`invalid_transition` `henting/retur gjelder bare ordrer med produkter av type utleie`) | sets `pickup`, clears `return`; releases bookings and reservations; consumes (§10.2) |
| `orders_register_return` | `picked_up` | `returned` | not locked; `requires_pickup` | sets `return` (`fee_minor` default 0) |
| `orders_ready_for_invoice` | `confirmed`, `returned`, `picked_up` | `ready_for_invoice` | `force` needs an admin (`forbidden`); `closure_guard`; an order that requires pickup and has no `return` needs `force` (`invalid_transition` `kan ikke fakturere før retur er registrert; utleie-ordrer krever retur før faktura`) with a non-blank `reason` (`invalid_input`), recorded on the audit entry | locks; releases bookings and reservations; consumes (§10.2) |
| `orders_complete` | `confirmed`, `ready_for_invoice` | `completed` | `closure_guard` | consumes once (§10.2); releases reservations; counts a completed order for the customer; locks |
| `orders_cancel` (confirm) | `draft`, `quote_sent`, `accepted`, `confirmed`, `ready_for_invoice` | `cancelled` | `closure_guard` | releases bookings; reverses consumption (§10.2); releases reservations; cancels the order's pending workflows and the quote's expiry |
| `orders_reopen` (confirm, admin) | `ready_for_invoice`, `completed` | `confirmed` | capacity (`unavailable`) | unlocks; books again; reserves again unless consumed; every checklist item back to not done; from `completed` the customer's completed count goes down by one; consumption is not reversed |
| `orders_reactivate` | `cancelled`, `accepted`, `confirmed` | `draft` | — | releases bookings; reverses consumption; releases reservations; cancels pending workflows and the quote's expiry; a quote awaiting a response becomes `declined` with `responded_at` now |

From `picked_up` invoicing readiness therefore needs `force`: a pickup clears the
return record. Completion counts once per order: after a reopen from
`completed` the next completion counts it again, so the customer's count
equals its orders currently `completed` (customers README §3).

#### 2.3 Locks

`ready_for_invoice` and `completed` lock the order. A locked order refuses
`orders_update` (`ready_for_invoice` only; final orders answer as §1.4),
`orders_register_*`, `checklists_*` mutations and `quotes_respond` with
`conflict` and the lock message `Ordren er låst (send faktura eller
fullført). Åpne ordren for redigering først.` `orders_reopen` is the way back
to editing; `orders_cancel` and `orders_complete` from `ready_for_invoice` are
allowed. A transition whose from-list excludes the locked status answers
`invalid_transition`, not the lock message.

#### 2.4 Bookings by status

`confirmed` books. `completed` reached from `confirmed` keeps its bookings;
`picked_up`, `returned`, `ready_for_invoice`, `cancelled` and a `completed` reached
from `ready_for_invoice` hold none. `orders_reopen` books again.

### 3. Pricing

#### 3.1 Lines

Every save prices each line at its product's current unit price:
`line_total_minor = quantity × unit_price_minor`. Then `line_effective_minor` by
the line's `price_mode`:

| Mode | Input | Result | `invalid_input` |
|---|---|---|---|
| `automatic` (default) | — | `line_total_minor` | |
| `percent_discount` | `discount_percent`, 0..100, ≤ 2 decimals | total − ⌊total × p / 100⌋, floored at 0 | `Rabattprosent må fylles ut`; `Rabattprosent må være mellom 0 og 100` |
| `fixed_discount` | `discount_input_minor` ≥ 0 | total − input, floored at 0 | `Rabattbeløp må fylles ut`; `Rabattbeløp kan ikke være negativt` |
| `manual_total` | `manual_total_minor` ≥ 0 | that value (may exceed the total) | `Manuell total må fylles ut`; `Manuell total kan ikke være negativ` |

`line_adjustment_minor = line_effective_minor − line_total_minor` (signed). Inputs
that belong to another mode are stored as null.

#### 3.2 Order

`catalog_total_minor = Σ line_total_minor`; `subtotal_minor = Σ line_effective_minor`.
The order's `price_mode` is `automatic`, `percent_discount` or `fixed_discount`
with the same formulas and messages on the subtotal; `manual_total` is
`invalid_input` `Prisvalg er ikke tillatt her`. `total_minor` is the
customer-facing total; `adjustment_minor = total_minor − subtotal_minor`.

#### 3.3 The automatic discount

In `automatic` order mode the `discount` seam (§14) gives `discount_minor` on
the subtotal, an integer in 0..subtotal (anything else is an extension error),
and `total_minor = subtotal_minor − discount_minor`. An explicit order mode replaces
the seam: `discount_minor` is 0 and `adjustment_minor` carries the adjustment.

Every amount stored or returned is at most 2⁵³ − 1 øre, exact in JSON and
SQL integers; beyond that `invalid_input` `~a blir for stort (over ~d øre)`.

### 4. Logistics

`logistics = {delivery:{not_agreed, method, earliest, latest}, return:{…},
site_address}`. Delivery methods `we_deliver` (needs the address),
`customer_collects`; return methods `we_collect` (needs the address),
`customer_returns`. Times are `HH:MM` local wall-clock times (core.md §2.1).
`site_address` and `delivery_address` name the same stored value. Without
`logistics` on create both sides are not agreed.

Input: a `logistics` object replaces the whole stored object; a missing side
is not agreed; a missing `site_address` keeps the stored address. Unknown
keys, a `not_agreed` other than true/false, an unknown method or a malformed
time (`Fyll inn et gyldig klokkeslett`) are `invalid_input`; an address over
300 characters is `Adressen kan ikke være lengre enn 300 tegn`. An input
without `logistics` keeps the stored logistics and its address.

Normalisation, then validation (first failure wins, all `invalid_input`): a
side with `not_agreed: true` loses its method and times; the address is
trimmed and cleared when no agreed side needs it.

| # | Rule | Message |
|---|---|---|
| 1 | delivery agreed ⇒ method | `Velg utleveringsmetode` |
| 2 | return agreed ⇒ method | `Velg returmetode` |
| 3 | delivery agreed ⇒ both times | `Sett tidsvindu for utlevering` |
| 4 | return agreed ⇒ both times | `Sett tidsvindu for retur` |
| 5 | delivery latest ≥ earliest | `Utlevering senest kan ikke være før tidligst` |
| 6 | return latest ≥ earliest | `Retur senest kan ikke være før tidligst` |
| 7 | single-day order, both agreed ⇒ return earliest ≥ delivery latest | `Retur kan ikke starte før utlevering er ferdig samme dag` |
| 8 | `we_deliver` or `we_collect` on an agreed side ⇒ an address | `Adresse må fylles ut når vi leverer eller henter hos kunde` |

`logistics_settled`: both sides agreed with method and both times, and the
address non-blank when a side needs it. `logistics_summary`:
`{delivery, return}`, each `Ikke avtalt` or `<label> HH:MM-HH:MM` (`<label>
kl. HH:MM` for equal times), labels `Vi leverer`, `Kunde henter`, `Vi henter`,
`Kunde returnerer`.

### 5. Bookings and availability

#### 5.1 Availability on a date

Point semantics: `blocked(D)` is the quantity of bookings whose `[from, to]`
contains D; `available = units_owned − blocked` (may be negative).
`availability_check {product_id, date, quantity = 1}` returns `{product_id,
date, quantity, units_owned, blocked, available, ok, conflicts:[{order_id,
event_date, from, to}]}`.

#### 5.2 Booking an order

Confirming, reopening, or updating a `confirmed` order replaces its bookings:
one per `rental` product, the quantities of its lines summed. Each must fit
on every date of `[event_date, end_date ?? event_date]` beside the other
orders' bookings (the peak over those dates); otherwise `unavailable`
`~a: bare ~d ledig ~a (rengjøringsdager medregnet), ordren trenger ~d`. The
booking covers the window the `booking_window` seam gives for the product
and both dates (by default the order's own days); a window that does not
contain the order's days is an extension error. A client widens it, for
example by cleaning days on both sides.

### 6. Quotes

#### 6.1 The quote

`quote` (id prefix `qte`), one per order with a stable id and access code
across re-issues: `order_id`, `revision`, `status` (`awaiting_response`,
`accepted`, `declined`, `expired`), `offered_at`, `expires_at`,
`responded_at`, `snapshot`, `stale`, `access_code`. The snapshot is what the
customer is offered, frozen at send time: `{customer_name, customer_email,
event_date, end_date, site_address, total_minor, lines:[{name, quantity,
line_effective_minor}]}`. `status` reads `expired` when it is stored so or when
an awaiting quote is past `expires_at`. `access_code` is 10 random characters
from `[A-Z2-7]`, returned to admins only (null for everyone else).

`quotes_get {order_id}` returns the quote (`not_found` `Ordre ~a har ikke
noe tilbud` when none). `quotes_preview {order_id}` returns `{order_id,
snapshot}`, the snapshot the next send would freeze, and changes nothing.

#### 6.2 Sending

`orders_send_quote` creates the quote at revision 1 or re-issues it
(revision + 1, `awaiting_response`, `responded_at` null, a new snapshot, the
same code). `offered_at` is now; `expires_at` is now plus the setting
`quotes.valid_days` (core.md §5.3), 14 days when the tenant has none. It
clears `accepted_snapshot_stale`. A tenant without messaging records the
quote and sends nothing.

#### 6.3 Responses

`orders_accept` records an answer an employee received. `quotes_respond
{quote_id, revision, access_code, response: accept|decline}` is the
customer's own answer: policy viewer, the code is the authorisation. Checks
in order:

1. throttle: after 5 wrong codes for the quote within 900 s, every attempt
   (the right code too) is `forbidden` `For mange feil tilgangskoder for
   tilbudet; prøv igjen om ~d minutter` until the window has passed (kept in
   memory; a restart forgets);
2. the code, uppercased and stripped of characters outside `[A-Z2-7]`,
   compared over every character: wrong is `forbidden` `Feil tilgangskode for
   tilbudet`, audited as rejected by `customer:<quote id>`;
3. the lock (§2.3);
4. `revision` ≠ the quote's: `conflict` `tilbudet er endret; last siden på nytt`;
5. expired: `conflict` `tilbudet er utløpt; send et nytt tilbud`;
6. quote not awaiting: `invalid_transition` `Tilbudet er allerede besvart (~a)`;
7. order not `quote_sent`: `invalid_transition` `Ordren har status ~a og
   venter ikke på svar`.

Accept moves the order to `accepted` as `orders_accept`; decline sets the
quote `declined` and leaves the order in `quote_sent` (a declined quote can
be sent again). Either bumps the order revision, is audited with actor
`customer:<quote id>` and cancels the quote's expiry. The result is the quote.

#### 6.4 Editing after sending

`stale` is true when the order's total, dates, site address or any field of
any line (client fields included) differ from their values at send time;
undoing the change makes the quote fresh again. Accepting a stale quote
succeeds (the snapshot records what the customer saw) and sets
`accepted_snapshot_stale`, cleared by the next send or by confirmation.
Staleness never blocks confirmation.

#### 6.5 Expiry: `quote_expiry`

Sending schedules the workflow `quote_expiry` (core.md §4) for the quote at
`expires_at`, keyed `<quote id>:<revision>`, cancelling the pending one of
the earlier revision. `orders_accept`, `quotes_respond`, `orders_cancel` and
`orders_reactivate` cancel it. A run whose quote is still awaiting at the
same revision stores `expired`, cancels the order's pending
`quote_reminder` and calls the `quote_expired` seam in its transaction;
otherwise it notes `ikke nødvendig: tilbudet er ikke åpent`.

#### 6.6 The offer page and credentials

Public pages under `/offer/` (through the kernel's public-page port, no
actor):

| Request | Result |
|---|---|
| `GET /offer/<quote id>` | 200 gate `Tilbud fra <sender.name>` with a `code` field; 404 `Siden finnes ikke` / `Kontroller lenken i e-posten.` for an unknown quote, an erased customer, or an expired quote |
| `POST /offer/<quote id>/open` | right code: 200 offer page (period, place, `Gyldig til`, `Dette er inkludert` with one row per line and `Totalt`, buttons `Godta tilbudet` and `Avslå tilbudet`, a hidden `proof`); wrong: 422 `Koden stemmer ikke. Kontroller koden i e-posten og prøv igjen.`; from the sixth wrong code in one session: 429 `For mange forsøk`; a right code resets the count |
| `POST /offer/<quote id>/respond` | `proof` (core.md §5.4: quote id, revision and expiry, signed) and `response`; runs `quotes_respond` as `customer:<quote id>`. Accept 200 `Takk`; decline 200 `Svaret er registrert`; quote or proof expired 410 `Tilbudet er utløpt`; revision changed, already answered, order moved on or a bad response 409 `Tilbudet er oppdatert`; missing fields 404 |
| an answered quote | 200 `Svar registrert`, no buttons |

`sender.name` is the messaging module's setting (`Tun` without it). The
page never shows the access code.

Staff projections of messages and requests are passed through
`mask-quote-credentials`: for a non-admin actor every code-shaped substring
(`[A-Z2-7]{5}-?[A-Z2-7]{5}`, any case) that is a stored access code (looked
up by the `access_code` index) becomes `•••••-•••••`.

Erasing a customer (customers README §5) is refused with `conflict` while the
customer has an order that is not final (`kunden kan ikke slettes fordi
kunden har en åpen ordre` / `… har ~d åpne ordrer`); otherwise it cancels the
customer's pending `next_year` workflows, sets `customer_name` and
`customer_email` in every quote snapshot to `[slettet]` and redacts the
quote's stored idempotency receipts without the access code (core.md §3.7).
Opening the module repairs the receipts of customers erased earlier.

### 7. Checklists

#### 7.1 Items

`checklist_item` (id prefix `chk`): `order_id`, `order_line_id`, `origin`
(`automatic`, `manual`), `source_key`, `description`, `category`,
`computed_quantity`, `done_quantity`, `done`. Automatic items hang on a line;
manual items on a line or on the order.

#### 7.2 Generation

Automatic items are a pure function of the order's lines, their
requirements and dates. They follow the active plan on a started order and
the fresh requirement snapshot (§8.1) on a not-started one. One item per
(line, article, unit): `source_key` `lager:<article's product, or the
article>:<unit>`, `description` `<article name>: <quantity> <unit>`,
`category` the article name, `computed_quantity` the requirement. The
`checklist_items` seam adds rule items keyed `client:<key>` (quantity 1 by
default, category the description by default), synchronised the same way.

#### 7.3 Synchronisation

Runs after `orders_create`, `orders_update`, a plan approval, a correction,
an applied catalog impact, and on `checklists_sync {order_id}`. Per (line,
key): missing → create; an automatic item whose description, category or
quantity changed → update; an automatic item no longer planned → delete.
Manual items are never touched. When the computed quantity changes, the
packed quantity carries over (carried = `done_quantity`, or the old computed
quantity when done without one):

| Carried | Result |
|---|---|
| null or 0, not done | not done, `done_quantity` null |
| greater than the new quantity | not done, carried |
| equal | done, carried |
| less | not done, carried |

A zero-quantity item already done stays done. A sync that changes nothing
stores nothing and bumps no revision; `checklists_sync` returns `{created,
updated, deleted, items, packed}`.

#### 7.4 Marking and packing

`checklists_mark {id, done, done_quantity?}`: done without a quantity sets
`done_quantity` to the computed quantity; not done clears it, or records
partial packing with `done_quantity`. `checklists_add_manual {order_id,
order_line_id?, description, category?}` (a line of another order:
`invalid_input` `Linjen ~a hører ikke til ordre ~a`). `checklists_delete
{id}` deletes manual items only (`invalid_input` `Automatiske punkter kan
ikke slettes; de følger behovene`). `checklists_list {order_id}` returns
`{items, packed}`; `packed` is true when every item is done (true with
none). Every mutation refuses a locked order and touches the order (§1.2);
`orders_reopen` sets every item back to not done.

### 8. Requirements and choices

#### 8.1 Resolution

An order's requirement snapshot is computed per line by the catalog's
resolver (catalog README §8) from the line's product, `quantity`, `servings`
(a client line field; none counts as 0), `choices` and the order's inclusive
days (`end_date − event_date + 1`; 1 when single-day or dateless). When a
client adds a method to the `requirements` seam, the seam overrides the
resolver: it is asked per line (an order holding that line only) for
`(product-id . quantity)` pairs, each mapped to the product's article
(products without one are skipped), with source key `seam:<product id>`.

Per line the entries are summed per article; zero quantities drop out; lines
sort by article name, then id. A snapshot line is `{order_line_id,
article_id, article_name, quantity, unit, sources}`. A resolved quantity
above 10¹² is `invalid_input` `Behovet for ~a blir ~a, mer enn ~d; reduser
antall, porsjoner eller kravet`. Quantities are exact decimals with three
fractional digits (core.md §2.1).

#### 8.2 Choices

A line's `choices` is `{<requirement id>: [recipe id, …]}`, in placement
order, for the product's choice-group requirements. Anything but an object of
string arrays is `invalid_input` `choices må være et objekt med lister av
oppskrift-id-er`; an empty object is stored as null and read as `{}`. The
catalog module validates the picks against the product (catalog README §9:
quantity 1, the number of picks, divisible servings, active members). The module stamps when
a line's choices last changed (kept while the line keeps its identity and its
choices), which the stock warnings use (§12.3).

#### 8.3 The order's requirements

`order.requirements` are the totals per article of the plan the order is
planned by (§9.2): `{product_id, article_id, quantity}`, where `product_id`
is the article's product, or the article when it has none (the key
requirements had before stock articles existed).

### 9. Requirement plans

#### 9.1 The plan

`plan` (id prefix `pln`): `order_id`, `revision` (1, 2, … per order),
`status` (`proposed`, `active`, `superseded`, `rejected`), `fingerprint`,
`activation` (`automatic`, `review`, `correction`), `activated_at`,
`activated_by`, `note`, `order_revision`, `lines` (the snapshot of §8.1).
Immutable but for `status`; at most one active and one proposed per order.
Only the active plan drives reservation, consumption, the forecast and the
checklist of a started order.

The fingerprint is the SHA-256 of the canonical JSON of the lines without
names (`article_name`, and `requirement_name` and `pick_name` in sources, so
a rename never proposes), over the lines sorted by `order_line_id`, article
and unit: reordering lines, or any edit that leaves every line's
requirements as they were, does not change it. Comparisons recompute it from
the stored lines.

An order an older core wrote has no plan; until its next save it is planned
by its stored requirements. An order with plans but none active is planned
by nothing.

#### 9.2 Activation

On every `orders_create` and `orders_update`, in the save transaction, and
for every catalog impact (§11), the module builds the snapshot and decides.
For the order's own edit it first builds the snapshot of the order as it was,
on the current catalog: when both are equal the edit is neutral and keeps the
active plan and any proposal, pending review or rejection. Otherwise, in
this order:

| # | Condition | Decision |
|---|---|---|
| 1 | an active plan with an equal fingerprint | keep it; supersede a proposal and its pending review |
| 2 | consumption applied | `invalid_input` `Ordren har lagerforbruk og krever en eksplisitt korrigering`; nothing stored |
| 3 | no active plan, or the order is not started | activate a new revision (`automatic`); supersede active and proposed |
| 7 | (checked with 3) the source is the order's own edit | as rule 3: an own change applies at once, superseding a pending proposal and its review |
| 4 | a proposal with an equal fingerprint | keep it; ensure its review |
| 5 | the latest plan is `rejected` with an equal fingerprint | keep the active plan; no new proposal |
| 6 | otherwise (a catalog change on a `confirmed` order) | supersede the old proposal; create a `proposed` revision; request a review |

`orders_create` therefore activates revision 1 at once. Sources are
`{type: order_create, id: <order id>}`, `{type: order_update, id: <order
id>:<new revision>}` and `{type: catalog_change, id}`. Afterwards the order's
requirements are those of the plan it is planned by.

#### 9.3 The `order_plan` review

Rule 6 requests a review of kind `order_plan` through the reviews module
(reviews README §2–§4 hold the generic rules: one pending review per
proposal, unique idempotency key, admin resolution). Title `Gjennomgå endrede krav for ordre
<first 8 characters of the id>`, summary `Kravplan revisjon ~d venter på
godkjenning.`, idempotency key `order-plan:<order id>:<source type>:<source
id>`, subject `{type: order, id, revision: the active plan's or null}`,
proposal `{type: plan, id, revision}`, due 09:00Z on the event date (core.md
§2.3), priority by days from today to the event date: ≤ 2 `critical`, ≤ 7
`high`, else (or dateless) `normal`. Its details add `diff: [{article_id,
article_name, unit, before, after, change: added|removed|increased|decreased}]`
between the totals of the active plan and the proposal, unchanged articles
left out, sorted by article name.

Resolution runs the stale checks in order; each supersedes the proposal and
answers `superseded` with its reason:

- a. the proposal is no longer proposed: `Kravforslaget er ikke lenger aktivt`;
- b. its revision differs from the review's: `Kravforslaget samsvarer ikke med gjennomgangen`;
- c. the active revision differs from the subject's: `Ordren har fått en annen aktiv kravplan`;
- d. the order is not `confirmed`: `Ordrestatusen tillater ikke lenger godkjenning`;
- e. a fresh snapshot's fingerprint differs: `Katalogen eller ordren er endret etter forslaget`.

Reject: the proposal becomes `rejected`, the active plan stays, and an equal
snapshot is not proposed again (rule 5). Approve: with consumption applied it
is `invalid_transition` `Lagerforbruk er allerede registrert. Bruk
eksplisitt korrigering fra ordren.` and the review stays pending; otherwise
the active plan is superseded, the proposal activated (`review`, the
reviewer, now), and the reservations and checklist follow. Neither touches
prices.

#### 9.4 Explicit correction

`orders_correct_plan {id, note}` (admin, confirm): consumption must be
applied (`invalid_transition` `Det finnes ingen registrert lagerforbruk å
korrigere`); the fresh fingerprint must differ from the active plan's
(`invalid_transition` `Det finnes ingen ny kravendring å korrigere`); a blank
note is `invalid_input` `Oppgi en merknad for korrigeringen`. In one
transaction it supersedes the active and proposed plans and the order's
pending reviews, activates the snapshot (`correction`, the actor, now, the
note) at the order revision the save gives, re-syncs consumption at that
revision (§10.2) and the checklist, marks the order's `conflict` and
`proposed` impacts `corrected` with detail `Lagerkorrigering er gjennomført
eksplisitt`, and audits the note (core.md §3.8). Prices are untouched.

#### 9.5 The plan on the order

`orders_get.plan` = `{active_revision, proposed_revision, pending_review_id,
consumption_applied, correction_required, conflicts}`, where
`correction_required` is true when an impact with status `conflict` exists,
or a review is pending and consumption is applied; `conflicts` lists those
impacts. `plans_list {order_id, limit}` returns plans newest revision first;
`plans_get {id}` one plan (`not_found` `Fant ingen kravplan med id ~a`).

### 10. Reservation and consumption

#### 10.1 Reservations

Only a `confirmed` order whose consumption is not applied reserves: the
totals of its plan per article, on its event date (inventory README §5).
Confirmation, `orders_update`, an approval, an applied catalog impact and
every transition out of `confirmed` re-sync the reservations, so no other
state holds any.

#### 10.2 Consumption

Consumption is applied once, from the plan, at the first of
`orders_register_pickup`, `orders_ready_for_invoice` (forced or not) and
`orders_complete`; an order that skips pickup still consumes. It is one
command to the inventory module's consumption sync (inventory README §6
holds the ledger rules, the replacement and "a recount wins") carrying the order, the order
revision the transition's save gives, the effective date (`event_date`, or
today when dateless) and the totals. `insufficient_stock` aborts the whole
transition. `orders_cancel` and `orders_reactivate` on a consumed order sync
with nothing expected, so a reactivated order is editable again;
`orders_reopen` does not reverse. "Consumption applied" means the inventory
module holds consumption rows for the order.

### 11. Catalog impact: `catalog_change`

When the catalog records a change (catalog README §11), the module queues, in
that transaction, every order the change reaches today and schedules the
workflow `catalog_change` for the change, due now. An order is reached when
it is calendar-active, dated today or later, and one of its lines references
the change: a requirement change of the line's product; a choice group the
product's requirements target; a recipe they target, the line picked, or
that is a member of a targeted group.

A run handles one change (core.md §4.4). It takes the queued orders (fewest
attempts first) and any order the change reaches now without an impact yet,
each in its own write transaction under its own deadline, read again at its
turn:

- gone, or already given an impact: dropped from the queue;
- no longer reached (cancelled, completed, moved to the past): impact
  `unchanged`;
- otherwise §9.2 with the change as source; an `applied` outcome re-syncs
  reservations and checklist. The impact records the outcome and the plan
  revision it produced.

`plan_impact` (id prefix `imp`): `catalog_change_id`, `order_id`, `status`
(`pending`, `applied`, `proposed`, `unchanged`, `conflict`, `corrected`,
`failed`), `detail`, `plan_revision`. Details: `Ny kravplan aktivert
automatisk`, `Forslag opprettet for gjennomgang`, `Kravplanen var allerede
oppdatert`; a refusal (rule 2) gives `conflict` with its message. Any other
failure gives `failed` with `Påvirkningen kunne ikke beregnes; se forespørsel
<request id>`, never an exception's text (the request is in
`introspect_request`, core.md §8.1). One order's conflict or failure never
blocks the others.

An order that runs into its deadline is counted on its queue entry and tried
again in the next pass, after the others; the third time its impact is
`failed`. A pass longer than one request deadline (core.md §7.1) stops and
schedules a new run of the change a second later. Pending runs read the
current catalog, so the first one applies every change.
`plan_impacts_list {order_id, limit}` lists an order's impacts, oldest first.

### 12. Stock

#### 12.1 Demand for the forecast

The module answers the inventory module's demand question (inventory README
§7): every committed order (§2.1, plus the not-started ones when unconfirmed demand is asked for)
with an event date (on or after the asked date) and no consumption applied
contributes its plan totals on its event date. Consumed orders contribute
nothing more; their quantities are in the balance.

#### 12.2 Capacity

For the inventory module's availability grid (inventory README §10) the
module gives, per product and date, the units booked and the booking orders.
For the catalog's capacity guard (catalog README §3) it gives a product's
peak: the most units booked on one date by calendar-active orders, cleaning
windows included.

#### 12.3 Stock warnings

`stock_warnings = [{kind, article_id, name, quantity, date}]` appear on
`orders_get` and on the result of `orders_create` and `orders_update`
(computed after the write has committed), never on lists. Warnings never
block.

- `shortage`: for a dated order on or after today with an active plan, per
  article of its plan: the balance minus the committed demand targeted in
  `[today, event_date]` minus this order's own totals when it is not
  committed; negative gives a warning with the missing quantity. The demand
  is asked once and no per-day series is built, so the cost does not grow
  with the distance to the event.
- `not_in_stock`: per article of a picked recipe whose balance is zero or
  less and that has had no receipt since the line's choices last changed;
  once per article, `quantity` the balance, `date` the event date or null.

### 13. Suggestions, requests and communication

#### 13.1 Suggestions

`orders_suggest {id}` returns `{items:[{product_id, name, reason}]}` from the
`suggestions` seam (none by default). It never changes anything.

#### 13.2 Requests

`orders_create_request {customer_id, lines?, department?}` (employee) creates
an order as `orders_create` does, but lines may be empty: the inbox module
uses it for a request it drafts no lines for. `record-order-request` stores
on such an order its `source` `{type: inquiry, id}`, its
`open_questions`, and a delivery method hint in `logistics.delivery.method`.

#### 13.3 Communication

`orders_get.communication` comes from the `communication` seam:
`{outbound, inbound, failed, last_outbound_at, last_inbound_at}` (zeros and
nulls by default; the messaging and inbox modules add theirs).

### 14. Seams

Each is a published extension point (core.md §1.1) specialised on the
application class.

| Point | Function | Kind | Default | Contract |
|---|---|---|---|---|
| `discount` | `order-discount` | before | 0 | the automatic discount of the subtotal, integer 0..subtotal (§3.3) |
| `requirements` | `compute-order-requirements` | before | none | `(product-id . quantity)` per order; a method overrides the resolver (§8.1) |
| `booking_window` | `booking-window` | before | the order's days | values from and to for a product and both dates; must contain the order's days (§5.2) |
| `suggestions` | `order-suggestions` | before | none | `(product reason)` pairs; never mutates (§13.1) |
| `checklist_items` | `order-checklist-items` | before | none | plists `(:key :description :category :quantity)`, keyed `client:<key>` (§7.2) |
| `departments` | `order-departments` | rule | none | the departments an order may name (§1.1) |
| `department_changed` | `order-department-changed` | after | — | called in the save of `orders_create` (department set) and `orders_update` (department changed); a refusal fails the save |
| `closure_guard` | `order-closure-check` | rule | — | may refuse completing, invoicing readiness or cancelling (an operation error; a running work session is `conflict`, staffing README §6) |
| `communication` | `aggregate-order-communication` | before | zeros | §13.3 |
| `quote_expired` | `quote-expired` | after | — | called in the transaction that stores an expiry (§6.5) |

The module answers other modules' seams: the inventory module's demand and
bookings questions (§12.1, §12.2), the catalog's capacity peak and change
notice (§12.2, §11), the reviews module's details and resolution for
`order_plan` (§9.3), and the customers module's erasure (§6.6).

### 15. Tools

Policy is the kernel default (core.md §3.3: reads viewer, mutations
employee) unless marked. Mutations take `request_key` (core.md §3.7);
confirm tools take a confirmation token (core.md §3.6).

| Tool | Kind | Policy | Section |
|---|---|---|---|
| `orders_create`, `orders_create_request` | create | | §1.4, §13.2 |
| `orders_get`, `orders_list`, `orders_summary` | read | | §1 |
| `orders_update` | update | | §1.4 |
| `orders_send_quote`, `orders_accept` | transition | | §2.2, §6 |
| `orders_confirm`, `orders_cancel` | transition, confirm | | §2.2 |
| `orders_register_pickup`, `orders_register_return` | transition | | §2.2 |
| `orders_ready_for_invoice` | transition | `force` admin | §2.2 |
| `orders_complete`, `orders_reactivate` | transition | | §2.2 |
| `orders_reopen` | transition, confirm | admin | §2.2 |
| `orders_correct_plan` | transition, confirm | admin | §9.4 |
| `orders_suggest` | read | | §13.1 |
| `availability_check` | read | | §5.1 |
| `quotes_get`, `quotes_preview` | read | | §6.1 |
| `quotes_respond` | transition | viewer | §6.3 |
| `checklists_list` | read | | §7.4 |
| `checklists_sync`, `checklists_mark`, `checklists_delete` | update | | §7.3, §7.4 |
| `checklists_add_manual` | create | | §7.4 |
| `plans_list`, `plans_get`, `plan_impacts_list` | read | | §9.5, §11 |

Lists take `limit` (default 20, at most 100) and return `has_more` (core.md
§2.4). The `/orders` screens list and show orders through these tools.

### 16. Explain

`explain` (core.md §8.2) runs the same functions as the tools and stores
nothing. Its `would`:

- `orders_create`: `catalog_total_minor`, `subtotal_minor`, `discount_minor`,
  `adjustment_minor`, `total_minor`, `requirements`, and `bookings` `[]`:
  bookings exist only from confirmation;
- `orders_update`: the same, with the bookings confirming would make; for a
  `confirmed` order also `availability` per `rental` product (the check
  booking runs);
- `orders_confirm`: `availability` per `rental` product and `requirements`.

### 17. Rollback

The module's migrations only add tables and nullable columns. The rollback
preflight (core.md §6.4) counts as outside an older core: a stored status,
price mode or movement kind it lacks, an order-line field or `choices` its
next write would drop, and a plan that is proposed (the older core would drop
the proposal) or active with requirements (it would plan its own way).
