# notifications

Requires customers, orders and staffing, and core >= 2.0.0, < 3.0. Public interface:
`publish-notification` publishes atomically in the caller's transaction;
`notification-recipients` resolves active admins and active assignees.
Identity is `(type, event_id, recipient)`. Read operations and marking read
always scope by the current actor, including admins.

The kernel's `record_read` policy also enforces recipient ownership in record
introspection, related-record lists and the ordinary store reads used by eval.
An admin inspecting another recipient's notification receives `not_found`.

The `customer_erasing` hook redacts the customer name in linked delivery-failure
and reply notifications, including their retained idempotency results. Recipient,
event identity and read state remain unchanged.

## Contract

Errors, policy, idempotency and audit are the kernel's (core.md §3.3–§3.8);
every mutation is audited and takes `request_key`.

### 1. What the module does

It tells employees, inside the application, what needs them: a new
request, a customer's reply, a quote answered or expired, an order
confirmed, a new task, a mail that could not be sent. Each notification
belongs to one employee, who alone sees it and marks it read. Other modules
publish through `publish-notification`; this module also hooks operations
of the orders and staffing modules itself.

### 2. Notification

`notification = {"id","type","recipient","text","link","subject_type","subject_id","order_id","event_id","created_at","read_at"}`.

- `recipient` is the employee's actor text (`employee:kari`).
- Identity is `(type, event_id, recipient)`: publishing the same event again
  to the same recipient does nothing and keeps `read_at`. `event_id` is the
  id of what caused it (an inquiry, an assignment, a delivery, or the
  request that answered, confirmed or expired a quote).
- `publish-notification` writes in the caller's transaction: a notification
  that cannot be written fails the operation, and none is kept for an
  operation that rolls back.
- A notification carries nothing beyond its `text` and `link`.

`notification-recipients order-id` are the active employees whose actor has
the role `admin`, plus, for an order, the active employees actively
assigned to it (staffing README §3), each once.

### 3. Types

| Type | Published by | Recipients | `text` | `link` |
|---|---|---|---|---|
| `inquiry_received` | inbox, a new request (inbox README §6) | admins | `Du har fått en ny henvendelse.` | `/inquiries/<id>` |
| `customer_reply_received` | inbox, a reply or feedback threaded to an order (inbox README §5) | admins and the order's assignees | `Kunden har svart på ordre <id>.` | `/orders/<id>` |
| `quote_accepted`, `quote_declined` | after `quotes_respond`; after `orders_accept` (accepted) | admins and the order's assignees | `Tilbudet på ordre <id> er akseptert.` / `… er avslått.` | `/orders/<id>` |
| `quote_expired` | the orders seam `quote_expired` | admins and the order's assignees | `Tilbudet på ordre <id> er utløpt.` | `/orders/<id>` |
| `order_confirmed` | after `orders_confirm` | the order's assignees except the actor who confirmed | `Ordre <id> er bekreftet.` | `/orders/<id>` |
| `assignment_created` | staffing's `assignment_created`, manual or automatic | the assignee | `Du er tildelt en ny oppgave.` | `/orders/<id>` |
| `delivery_failed` | messaging, a delivery `failed` or `outcome_unknown` (messaging README §9) | admins | `En e-post til <name> kunne ikke sendes.` | `/orders/<id>` or `/customers/<id>` |

### 4. Reading

Every read and mark is scoped to the actor, admins included: there is no
admin bypass. The kernel's record read policy enforces the same in
introspection, related-record lists and store reads from eval, so an admin
asking for another employee's notification gets `not_found`.

| Tool | Kind, policy | Input | Result |
|---|---|---|---|
| `notifications_list` | read, employee | `{"unread_only"?,"limit"?=25}` | `{"items"}`, the actor's own, newest first, at most 100 |
| `notifications_mark_read` | update, employee | `{"id"}` | the notification; not the actor's → `not_found` `Varselet finnes ikke`; marking again keeps the first `read_at` |
| `notifications_unread_count` | read, employee | `{}` | `{"count","capped"}`: counts at most 100, `capped` true at 100 |

### 5. Erasure

On `customer_erasing` (customers README §5) the customer's name is replaced
by `[slettet]` in the text of `delivery_failed` and `customer_reply_received`
notifications that link to the customer or concern one of the customer's
orders, and the stored results of their receipts are redacted. Recipient,
identity and read state stay.

### 6. Screen

`/notifications` (spec/ui.md) shows the actor's notifications, newest first, each
`Ulest` or `Lest`, with `Marker som lest` while unread, and the number
unread. The menu entry shows the unread count, `99+` when capped.

### 7. Invariants

1. A notification is seen and marked only by its recipient, admins
   included.
2. One notification per event and recipient; it is written in the
   transaction of what caused it.
3. Read state only moves from unread to read.
