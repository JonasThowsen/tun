# tun module `customers`

ASDF system `tun-customers`, package `tun.customers`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** `customer` (name, email, phone, notes, completed orders); `customers_create`, `customers_get`, `customers_list`.
- **Depends on:** none.
- **Core range:** builds against core `>= 1.2.0, < 2.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** the kernel's extension kinds on `customer` (fields, rules and computed fields; core.md §1.1); the `/customers` list screen (`customer_list`). Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4): it refuses when a record holds a value the previous
  core cannot decode (a status or price mode it lacks) or an order-line
  field its next write would drop (docs/architecture.md, "Tenants and deployment").

Erasure removes affected retained request payloads through core 1.1.6
`redact-request-traces`, including in-flight diagnostic payloads. Request IDs,
outcomes and timings remain available; unrelated completed traces remain intact.
The in-memory change is restored if the erasure transaction rolls back.

## Contract

Errors, policy, confirmation, idempotency and audit are the kernel's
(core.md §3.3–§3.8): reads are `viewer`, mutations `employee`. Every
mutation is audited and takes `request_key`.

### 1. Customer

`customer = {"id","revision","name","email","phone","notes","completed_orders","marketing_consent","consent_source","consent_at","erased","erased_at","created_at"}`,
plus the fields a client adds.

| Field | Rule |
|---|---|
| `name` | 1–120 characters, trimmed before it is checked |
| `email` | `local@domain.tld`, at most 160 characters |
| `phone` | at most 40 characters, stored as given (not trimmed) |
| `notes` | free text, at most 500 characters |
| `completed_orders` | computed by the module (§3), never input |
| `revision` | starts at 1 and grows with every change (core.md §2.1) |

A client extends the customer with fields, rules and computed fields
(core.md §1.1), never by editing this module. Example: Nordvik Utleie adds
`kind` (`privat` | `bedrift`) and `org_number`, with a rule that a
`bedrift` needs a nine-digit `org_number`, and a computed loyalty tier
from `completed_orders`. `registry_describe` marks such fields
`"source": "client"`.

### 2. Tools

| Tool | Kind, policy | Input | Result |
|---|---|---|---|
| `customers_create` | create | the customer's input fields, `marketing_consent`? | customer |
| `customers_get` | read | `{"id"}` | customer |
| `customers_list` | read | `{"query"?,"limit"?=20}` | `{"items","returned","has_more"}`, oldest first |
| `customers_set_consent` | update | `{"id","marketing_consent","source"}` | customer (§4) |
| `customers_erase` | update, admin, confirm | `{"id"}` | customer (§5) |

`customers_list` matches `query` as a case-insensitive substring of the
name or the email, case folded beyond ASCII; lists follow core.md §2.4.
There is no `customers_update`.

### 3. Completed orders

`completed_orders` is the number of the customer's orders that are
`fullført` now. The orders module keeps it: `orders_complete` adds one
(`record-completed-order`), `orders_reopen` from `fullført` takes one away
(`record-reopened-order`, never below 0). An order completed, reopened and
completed again counts once. A client's loyalty rule reads this count.

### 4. Marketing consent

`marketing_consent` (default false), `consent_source` (`manuelt`, `epost`,
`kontaktskjema`, `avmelding` or null) and `consent_at` record whether the
customer may get marketing mail and how that was decided.

- `customers_create` with `marketing_consent: true` sets source `manuelt`.
- `customers_set_consent` sets all three; an erased customer →
  `invalid_input` `kunden er slettet`. The audit entry carries the source as
  its reason.
- The inbox's contact form sets consent with source `kontaktskjema` and never
  unsets it (inbox README §6).
- The unsubscribe link (§6) is the only change a customer makes.

`marketing-allowed-p` is true when the customer has consented and is not
erased. The messaging module's consent guard uses it (messaging README §9).

### 5. Erasure

`customers_erase {"id"}` is admin and needs confirmation (core.md §3.6). In
one transaction:

1. The before point `customer_erasing` runs. Each module checks the erasure
   and anonymises its own records of the customer there: the orders module
   refuses while the customer has an open order (`conflict` `kunden kan ikke
   slettes fordi kunden har en åpen ordre`, or `… har N åpne ordrer`), clears
   the customer from quote snapshots and cancels pending `neste_år`
   workflows; messaging, inbox and notifications redact their content
   (their READMEs). A refusal fails the whole erasure.
2. Retained request traces that name the customer are redacted (core.md
   §8.4); the in-memory change is undone if the transaction rolls back.
3. `name` becomes `Slettet kunde <last 8 characters of the id>`, `email`
   `<last 8>@slettet.local`; `phone`, `notes` and `marketing_consent` are
   cleared; `erased` is true and `erased_at` set.
4. The stored results of the customer's idempotency receipts are replaced
   by the anonymised record, so a replay never returns the old data.

There is no reversal. When the module opens it redacts the receipts of
customers erased before, so every erased customer's receipts are
anonymised. Sends to an erased customer are refused (messaging README
§4.2).

### 6. The unsubscribe page

`/avmeld/<token>`, a public page (no actor). The token is the link token of
kind `avmeld` for the customer's id (core.md §5.4), compared in constant
time.

| Request | Result |
|---|---|
| `GET /avmeld/<token>` | 200, a page saying what unsubscribing means, with the button `Meld meg av` |
| `POST /avmeld/<token>` | `marketing_consent` false, `consent_source` `avmelding`, `consent_at` now; 200 `Du er avmeldt.`. Runs as `customer:<customer id>`, audited with reason `avmelding`. A second post changes nothing. |
| an unknown token, an erased customer, or a longer path | 404 `Siden finnes ikke` / `Kontroller lenken i e-posten.` |

Messages carry the link as the template value `lenke.avmeld` (messaging
README §3).

### 7. Screen

`/customers` lists, shows and creates customers through `customers_list`,
`customers_get` and `customers_create` (spec/ui.md §8).
