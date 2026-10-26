# tun module `invoicing`

ASDF system `tun-invoicing`, package `tun.invoicing`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** `invoice`, send intents; `invoices_*`; reconciles pending sends at start-up.
- **Depends on:** `orders`.
- **Core range:** builds against core `>= 1.0, < 2.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** no extension points of its own; a client extends it with
  the kernel's extension kinds (core.md §1.1). Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4): it refuses when a record holds a value the previous
  core cannot decode (a status or price mode it lacks) or an order-line
  field its next write would drop (docs/architecture.md, "Tenants and deployment").

## Contract

Errors, policy, confirmation, idempotency and audit are the kernel's
(core.md §3.3–§3.8): reads are `viewer`, mutations `employee`. Money is
integer øre (core.md §2.1). The accounting port (intent, outcome,
reconciliation) is the kernel's (core.md §5.2); this module is its user.

### 1. What the module does

It turns an order into an invoice, a copy that later order changes do not
alter, and sends the invoice to the accounting system through the port.
Sending happens at most once per invoice, survives a crash between the
call and its outcome, and tells the customer through the `faktura` message.

### 2. Invoice

`invoice = {"id","order_id","status","customer","lines","subtotal_ore","discount_ore","adjustment_ore","total_ore","external_ref","created_at","sent_at"}`.

- `status` is `utkast` or `sendt`; the only transition is `utkast → sendt`.
- One invoice per order.
- `customer` is a snapshot of who the invoice is for: the customer's `name`
  and `email` and every input field a client added (such as `kind` and
  `org_number`). The kernel's free-text fields (`phone`, `notes`) stay off
  invoices and the port.
- `lines` copy the order's lines: `{"description","quantity","unit_price_ore","line_total_ore","line_effective_ore","line_adjustment_ore"}`,
  `description` being the product's name. `line_effective_ore` is the line
  after its price mode (or `line_total_ore`), and `line_adjustment_ore` the
  difference.
- `subtotal_ore`, `discount_ore`, `adjustment_ore` and `total_ore` copy the
  order's; `adjustment_ore` defaults to minus the discount.
- `external_ref` is the accounting system's reference, set when sent.

### 3. Creating an invoice

`invoices_create_from_order {"order_id"}` (create). The order must be
`bekreftet`, `hentet`, `returnert`, `send_faktura` or `fullført`, else
`invalid_transition` `Ordren har status <s>; faktura krever en bekreftet
ordre`. A second invoice for the same order is `conflict` `Ordre <id> er
allerede fakturert`. The result is the `utkast` invoice.

`create-invoice-from-order` does the same for a dependent module or a
client's workflow (for example an invoice created automatically on the
event date).

### 4. Sending an invoice

`invoices_send {"id"}` (transition, admin, confirm, destructive). Its
confirmation summary names the invoice, the order and the total. The steps:

1. The invoice is not `utkast` → `invalid_transition` `Fakturaen har status
   <s> og kan ikke sendes på nytt`.
2. Another call in this process is sending it → `conflict` `Fakturaen <id>
   er i ferd med å bli sendt`.
3. A send intent is stored, or the pending one reused. Its id,
   `send-<invoice id>`, is stable per invoice, so the accounting system can
   recognise a repeated call. The request's transaction commits.
4. After the commit, outside any transaction (core.md §7.3), the port's
   `create_invoice` is called with the intent: its id, the invoice id, the
   customer snapshot, the lines and the total.
5. In a new transaction: the intent is done, the invoice `sendt` with
   `external_ref` and `sent_at`, the `faktura` message goes to the customer
   through the kernel's messaging port (core.md §5.1; nothing is sent
   without a messaging module), and a system audit entry
   `invoices_send.completed` is written.

When the port fails, the answer is `unavailable` `Regnskapssystemet svarte
ikke (…); fakturaen er ikke sendt, prøv igjen`, the invoice stays `utkast`
and the intent pending; the next `invoices_send` resumes with the same
intent id. Recording an outcome is idempotent: an invoice already `sendt`
is left as it is.

### 5. Reconciliation at start

When the module opens, before any retry, each pending intent is looked up
in the accounting system (the port's `lookup_invoice`). If the system has
it, the send is completed from its reference as in step 5, audited as
`invoices_send.reconciled`. If not, the intent stays pending and the next
`invoices_send` creates it.

### 6. Tools

| Tool | Kind, policy | Input | Result |
|---|---|---|---|
| `invoices_create_from_order` | create | `{"order_id"}` | invoice (§3) |
| `invoices_get` | read | `{"id"}` | invoice |
| `invoices_list` | read | `{"order_id"?,"status"?,"limit"?=20}` | `{"items","returned","has_more"}` (core.md §2.4) |
| `invoices_send` | transition, admin, confirm | `{"id"}` | invoice (§4) |

### 7. Invariants

1. One invoice per order; it is a copy and does not follow the order.
2. Every create for an invoice carries the same intent id, committed before
   the call, and an outcome never recorded is looked up before any retry, so
   the accounting system creates the invoice once.
3. A sent invoice is never sent again.
