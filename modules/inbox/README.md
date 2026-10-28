# inbox

Requires customers, orders and notifications; core >= 2.0.0, < 3.0.
`request-defaults` is the client seam returning a draft JSON object or nil.
`inbox-history` supplies the public per-order/customer inbound history.
Inbound mail is deduplicated by message reference. A failed draft rolls back
its nested transaction while retaining the request with an explanatory note.

Text rules use the kernel's Unicode scanner: decimal digits, Unicode
whitespace (including newlines and carriage returns), and word boundaries
containing letters/digits only. Sign-off lines ignore all Unicode punctuation
and dashes. Forwarded quote credentials are masked even without an order match.

## Contract

Errors, policy, idempotency and audit are the kernel's (core.md §3.3–§3.8);
every mutation is audited and takes `request_key`. Settings and link tokens
are the kernel's (core.md §5.3, §5.4). Orders, quotes and their reminder
workflow are the orders module's (orders README §6, §13.2); customers and consent the
customers module's (customers README).

### 1. What the module does

The inbox receives what customers send: mail through an inbound port, the
public contact form, and feedback through a link. Each becomes a
inquiry. A reply is threaded to its order; a new request gets a drafted
customer and a dateless order through a client seam, so staff start from a
draft instead of a blank form. Staff then handle each inquiry. The
module publishes `inquiry_received` and `customer_reply_received` through the
notifications module, and gives the messaging module its inbound history.

It declares the setting `inbox.secret` (secret), which authenticates
the inbound endpoint.

### 2. Inquiry

`inquiry = {"id","kind","status","from_name","from_email","subject","body","received_at","message_ref","customer_id","order_id","match","created_order_id","questions","marketing_consent","handled_by","handled_at","note","request_id"}`.

| Field | Values |
|---|---|
| `kind` | `email`, `contact_form`, `feedback` |
| `status` | `new`, then `handled` or `dismissed` (§7) |
| `match` | `reference`, `quote`, `customer`, `none` (§4) |
| `created_order_id` | the drafted order (§6), or null |
| `questions` | the open questions put to the customer (§6) |
| `note` | why a draft was not made, or the handler's note |

For an actor who is not admin every projection masks quote access codes
(orders README §6.6), also in an inquiry matched to no order.

### 3. Intake

#### 3.1 Inbound mail

`inbound_mail_receive {"from_name"?,"from_email","subject","body","received_at"?,"message_ref"?}`
(create, admin; the endpoint calls it as `system:inbound`). `subject` is at
most 500 characters, `body` 20 000, else `invalid_input`. `from_email` is
trimmed and lower-cased; `received_at` defaults to now. A `message_ref` seen
before stores nothing and returns the first inquiry with
`"duplicate": true`; otherwise `{"inquiry","duplicate":false}`.

#### 3.2 The inbound endpoint

`POST /inbound/mail` with the header `X-Tun-Inbound-Secret` and the JSON
input of `inbound_mail_receive`. The header, read as UTF-8, must equal
`inbox.secret` (compared in constant time), checked before the body
is parsed; otherwise 403
`{"error":{"code":"forbidden","message":"Invalid secret"}}`, in
source text as every answer to a machine is (`spec/i18n.md` §7), the body
is never parsed, and nothing is stored. A body that is not JSON, or a refused input, is 422 with the
error.

#### 3.3 The contact form

`inquiries_create {"name","email","phone"?,"message","event_date"?,"guests"?,"marketing_consent"}`
(create, viewer: the public form needs no employee). `marketing_consent` is
required and must be true, else `invalid_input` `samtykke må gis`. The
inquiry has `kind: "contact_form"`, subject `Kontaktskjema`, the form's
name and email, and the message as its body with `Dato: dd.mm.yyyy` and
`Gjester: N` lines appended when given, so the client seam sees them.
`phone` is accepted and not stored.

#### 3.4 The feedback page

`/feedback/<token>`, a public page (no actor). The token is the link
token of kind `tilbakemelding` for the order's id, compared in constant
time. It resolves only to an order with a date whose last date plus 60
days is today or later and whose customer is not erased; anything else is
404 `Siden finnes ikke` / `Kontroller lenken i e-posten.`

| Request | Result |
|---|---|
| `GET` | 200, `Hva tenker du?` with a textarea `message` |
| `POST` with `message` | an inquiry `kind: "feedback"`, `match: "reference"`, from the order's customer, subject `Tilbakemelding`, threaded to the order as §5; run as `customer:<customer id>` and audited; 200 `Takk for tilbakemeldingen!` |
| `POST` with an empty message | 422 `Skriv en melding.` |
| `POST` with over 20 000 characters | `invalid_input` `Meldingen er for lang` |

### 4. Matching, in order

1. **Reference** (mail only, never the form): the subject or body contains
   `[ref:<order id>]`. The references are tried in order until one names an
   existing order → `reference`, that order and its customer.
2. **Quote**: customers whose email, trimmed and lower-cased, equals
   `from_email`; among their orders in `quote_sent` whose quote awaits a
   response, the newest → `quote`, that order and its customer.
3. **Customer**: such a customer exists → `customer`, the first, no order.
4. Otherwise `none`.

### 5. A reply

An inquiry matched to an order (`reference` or `quote`) is threaded to
it: it appears in the order's history as inbound (§9); the order's pending
`quote_reminder` workflows are cancelled with the note `kunden har
svart`; `customer_reply_received` goes to the admins and the order's active
assignees: `Kunden har svart på ordre <id>.`, linking to `/orders/<id>`
(notifications README §3). No draft is made. The status stays `new` until
someone handles it.

### 6. A new request: the draft

#### 6.1 The seam

For an inquiry matched to no order (`customer` or `none`) the module calls
the rule point `request_defaults` with the inquiry. It returns null (no
draft; the default without a client rule) or a draft:

```
{"customer":{customers_create input},"lines":[{"product_id","quantity",…}],
 "department"?,"delivery"?,"questions":[string]}
```

A seam that signals an error or returns `{"error":{"message"}}` refuses the
draft.

#### 6.2 Making the draft

In one nested transaction, as `system:inbound`:

1. The customer: the matched one, or a new one through `customers_create`
   (its validation and the client's rules apply) with the draft's fields and
   `email` = `from_email`; a contact form's `name` wins over the draft's.
2. A dateless `draft` order through `orders_create_request` (no lines) or
   `orders_create` (lines), with the draft's lines and department; staffing
   assigns automatically when a department is given (staffing README §5).
3. The reasons of `orders_suggest` for the new order are appended to the
   draft's questions.
4. The order records its source `{"type":"inquiry","id"}`, the questions
   as `open_questions`, and the delivery hint as the delivery method.
5. The inquiry gets `customer_id`, `created_order_id` and `questions`.

When any step fails, the nested transaction rolls back, nothing of the
draft remains, and the inquiry is stored with `note` `utkast ikke
opprettet: <message>`. Either way `inquiry_received` goes to the admins:
`Du har fått en ny henvendelse.`, linking to `/inquiries/<id>`.

#### 6.3 Consent

A contact form (consent is required, §3.3) sets the consent of the customer
it matched or created to true with source `contact_form` through
`customers_set_consent`, unless it already is; a form never unsets consent
and never touches another customer.

### 7. Handling

`inquiries_handle {"id","action","order_id"?,"note"?}` (update,
employee). Only an inquiry in `new`, else `invalid_transition`
`Henvendelsen er allerede behandlet`.

| Action | Effect | Status |
|---|---|---|
| `convert` | makes the draft of §6.2; when the seam returns null, an empty draft: a customer named from `from_name` or the email's local part and an order without lines. Already drafted → `invalid_transition` `Henvendelsen har allerede en ordre`; a failed draft → `invalid_input` with its note | `handled` |
| `attach` | threads to `order_id` as §5, without cancelling the reminder; no `order_id` → `invalid_input` `Oppgi ordre` | `handled` |
| `dismiss` | nothing more | `dismissed` |

Each sets `handled_by`, `handled_at`, and `note` when given.

### 8. Text rules for a client's seam

The module publishes helpers a client's `request_defaults` uses, with
Unicode semantics (the kernel's scanner: `\s` includes newlines and
carriage returns; a word character is any Unicode letter or digit):

- `request-text-matches-p pattern text`: a regular expression match;
- `request-postcodes text`: the four-digit tokens that are not part of a
  word and not next to `.` or `-` (so `20.06.2027`, `2027-06-20` and the
  `2040` in `Nordvik 2040.` give none);
- `request-name inquiry`: the first non-empty line after a line that is
  `hilsen`, `mvh`, `vennlig hilsen` or `med vennlig hilsen` (any case, any
  trailing punctuation or dash), or the rest of a line starting with
  `hilsen `; else the email's local part.

### 9. History, summary and erasure

`inbox-history` gives the messaging module the inbound items of an order or
a customer, oldest first, as history items: `kind: "inbound"`,
`inquiry_id`, `subject`, `body`, `status: "received"`, `template: null`,
`delivery: null`, `scheduled_at` = `received_at`, and the sender as both
`sender` and `recipient` (messaging README §11). The order's
`communication` summary gains `inbound` and `last_inbound_at`.

On `customer_erasing` (customers README §5) every inquiry of the
customer gets `[slettet]` for `from_name`, `from_email`, `subject` and
`body`, and the stored results of its receipts are redacted. When the module
opens it redacts the receipts of customers erased before.

A stored inquiry makes the rollback preflight refuse a rollback to a
deployment without this module's rules (core.md §6.4).

### 10. Tools and screens

| Tool | Kind, policy | Input | Result |
|---|---|---|---|
| `inbound_mail_receive` | create, admin | §3.1 | `{"inquiry","duplicate"}` |
| `inquiries_create` | create, viewer | §3.3 | inquiry |
| `inquiries_list` | read, employee | `{"status"?,"kind"?,"limit"?=20}` | `{"items"}`, newest first, at most 100 |
| `inquiries_get` | read, employee | `{"id"}` | inquiry |
| `inquiries_handle` | update, employee | §7 | inquiry |

`/inquiries` lists the newest 100 with a status filter;
`/inquiries/<id>` shows one, its note and questions, and while it is
`new` the handling form (spec/ui.md). The forms call the same tools.

### 11. Invariants

1. Matching follows §4's order; a reference wins over the email.
2. A reply never makes a draft; a new request makes at most one customer
   and one dateless order, in one transaction with the inquiry's draft
   fields; a repeated `message_ref` makes nothing.
3. Without a client rule the inbox drafts nothing.
4. The inbound endpoint needs the secret.
