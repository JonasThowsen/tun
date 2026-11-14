# tun module `customers`

ASDF system `tun-customers`, package `tun.customers`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** `customer` (name, email, phone, notes, completed orders); `customers_create`, `customers_get`, `customers_list`, `customers_update`, `customers_set_consent`, `customers_erase`.
- **Depends on:** none.
- **Core range:** builds against core `>= 2.36.0, < 3.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** the kernel's extension kinds on `customer` (fields, rules and computed fields; core.md §1.1); the `/customers` list screen (`customer_list`); to `TUN`, the operations `customers-create`, `customers-get`, `customers-list`, `customers-update` and `customers-set-consent`, the accessors of `customer`'s name, email, phone, revision, completed orders, consent and erasure, and `marketing-allowed-p`. Its exported symbols are its interface for
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
| `customers_update` | update | `{"id","revision","fields"}` | customer (§2.1) |
| `customers_set_consent` | update | `{"id","marketing_consent","source"}` | customer (§4) |
| `customers_erase` | update, admin, confirm | `{"id"}` | customer (§5) |

`customers_list` matches `query` as a case-insensitive substring of the
name or the email, case folded beyond ASCII; lists follow core.md §2.4.

#### 2.1 Changing a customer

`customers_update {"id","revision","fields"}` changes the fields that
`fields`, an object, names, and leaves every other field as it was.

- `revision` is the customer's current revision; another is `conflict`
  `Kunden er endret (revisjon N, ikke M)`, and nothing changes. An
  accepted update raises the revision by one (core.md §2.1).
- `fields` takes the customer's input fields, `name`, `email`, `phone`,
  `notes` and the fields a client adds (§1), each with the rule it has in
  `customers_create`. A field sent as `null` is cleared; `null` or blank
  for a required field (`name`, `email`, a client's required field) is
  `invalid_input` at `fields.<name>`. The tool's input schema lists them
  under `fields`, a client's fields included.
- `fields` cannot name `marketing_consent`, which changes only through
  `customers_set_consent` with its source (§4): `invalid_input`
  `samtykke endres med customers_set_consent`. A field the module keeps
  (`id`, `revision`, `completed_orders`, `consent_source`, `consent_at`,
  `erased`, `erased_at`, `created_at`) or an unknown name is `invalid_input`
  `er ikke et kjent felt`, and so is an empty `fields`.
- The module's and the client's rules run on the changed customer, as on
  every write of it (core.md §1.1). The customer has no unique field.
- An erased customer → `invalid_input` `kunden er slettet`, whatever the
  revision.
- The audit entry's reason is the names of the changed fields, such as
  `name, email`, never their values, in the order of the customer's
  fields: `name`, `email`, `phone`, `notes`, then a client's fields as
  it added them, whatever the order in `fields`.
- From Lisp, a client or another module calls it as any operation:
  `(invoke 'customers-update "id" id "revision" revision "fields" (jobj
  "name" "Kari Hansen"))`. A client's `invoke` answers with JSON, so its
  revision is `(jget (invoke 'customers-get "id" id) "revision")`; a
  module gets the customer itself and reads `customer-revision`, which a
  client may also call on a customer a seam or rule hands it.

### 3. Completed orders

`completed_orders` is the number of the customer's orders that are
`completed` now. The orders module keeps it: `orders_complete` adds one
(`record-completed-order`), `orders_reopen` from `completed` takes one away
(`record-reopened-order`, never below 0). An order completed, reopened and
completed again counts once. A client's loyalty rule reads this count.

### 4. Marketing consent

`marketing_consent` (default false), `consent_source` (`manual`, `email`,
`contact_form`, `unsubscribe` or null) and `consent_at` record whether the
customer may get marketing mail and how that was decided.

- `customers_create` with `marketing_consent: true` sets source `manual`.
- `customers_set_consent` sets all three; an erased customer →
  `invalid_input` `kunden er slettet`. The audit entry carries the source as
  its reason.
- The inbox's contact form sets consent with source `contact_form` and never
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
   the customer from quote snapshots and cancels pending `next_year`
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

`/unsubscribe/<token>`, a public page (no actor). The token is the link token of
kind `avmeld` for the customer's id (core.md §5.4), compared in constant
time.

| Request | Result |
|---|---|
| `GET /unsubscribe/<token>` | 200, a page saying what unsubscribing means, with the button `Meld meg av` |
| `POST /unsubscribe/<token>` | `marketing_consent` false, `consent_source` `unsubscribe`, `consent_at` now; 200 `Du er avmeldt.`. Runs as `customer:<customer id>`, audited with reason `unsubscribe`. A second post changes nothing. |
| an unknown token, an erased customer, or a longer path | 404 `Siden finnes ikke` / `Kontroller lenken i e-posten.` |

Messages carry the link as the template value `link.unsubscribe` (messaging
README §3).

### 7. Screen

`/customers` lists, shows and creates customers through `customers_list`,
`customers_get` and `customers_create` (spec/ui.md §8). It has no form for
`customers_update`.

### 8. Search

The application's one search (spec/ui.md §6.4) finds customers, kind
`customer` («Customer»): by name, by email, and by email or phone written
whole (a phone's start too, from three digits), a phone stored with its
country code by its national number too («91234567» finds «+47 912 34
567»); an erased customer is not found. Each result's line is its email
and phone, and it leads to `/customers/ID`. It reads only the name,
email, phone and erasure of each customer. A module or the client that
shows customers its own way says so with `search-replacements`
(`("customer" "customers")`), and this module then reads none.
