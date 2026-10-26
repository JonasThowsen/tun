# tun module `inventory`

ASDF system `tun-inventory`, package `tun.inventory`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** stock articles and their ledger (`aapning`, `mottak`, `justering`, `telling`, `forbruk`), reservations and the consumption synchroniser (keyed by opaque order ids), department transfers; `articles_*`, `transfers_list`, the product-keyed `inventory_*` tools (on the product's article, or `article_id`), `inventory_forecast`, `inventory_purchase_suggestions`, `inventory_availability_grid` (§2–§11). At start it adopts an older core's per-product stock levels as articles (§14). A balance above 10¹² is `invalid_input` (§3.3); a recount wins until a newer receipt (§6.4).
- **Depends on:** `catalog`. It knows no order status (§1).
- **Core range:** builds against core `>= 1.0, < 2.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** seams `article_demand` (with `from`: orders dated from then on) and `bookings_on` (orders answers them for the forecast and the grid); `purchase-suggestions` for the client's warehouse alert. Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4): it refuses when a record holds a value the
  previous core cannot decode (a status, price mode or movement kind it
  lacks), an order-line field its next write would drop, or an article that holds stock the previous core would not see (any but an untouched adoption of its stock level), a product linked to an article not made for it or unlinked from its own (a check it adds to the catalog's product), or a department transfer
  (docs/architecture.md, "Tenants and deployment").

## Contract

### 1. Scope

Inventory keeps stock: articles (the counted physical commodity), their
movement ledger, reservations, consumption by orders, the forecast and
purchase suggestions built on it, the availability grid of rental products,
and department transfers of articles and products. Products live in the
catalog and link to an article (catalog README §2.4).

Orders are opaque ids here: inventory never reads an order or its status.
Orders tells it what an order reserves (§5) and consumes (§6) and answers the
two seams the forecast and grid ask (§12). Another module that needs the
ledger asks through this module's functions (tun-platform.md §2.5). Kernel
rules (policy, results and error codes, idempotency, audit) are core.md §3;
lists are core.md §2.4; quantities are exact decimals with at most three
fractional digits (core.md §2.1).

### 2. Articles

#### 2.1 Fields

`article = {"id","revision","name","sku","unit","package_size","balance","movement_revision","min_level","max_level","cost_price_ore","supplier":{"name","contact","article_no","order_url"},"lead_days","department","department_revision","active","product_id","created_at"}`.

| Field | Rule |
|---|---|
| `name`, `unit` | required on create (`invalid_input` `Navn og enhet må fylles ut`); `unit` is free text, never converted |
| `sku` | optional, unique among all articles, else `conflict` `Varenummeret <sku> er allerede i bruk` |
| `package_size` | optional decimal > 0: the purchasing package in the article's unit |
| `min_level`, `max_level` | optional, ≥ 0; `min_level` raises a purchase suggestion (§9) |
| `cost_price_ore` | optional integer ≥ 0 |
| `supplier` | an object with only `name`, `contact`, `article_no`, `order_url`, each a string or null (≤ 200; `order_url` ≤ 2000); merged over the stored one; a blank value is stored as null |
| `supplier.order_url` | must match `^https?://[^@\s/:?#]+(:\d+)?([/?#]\S*)?$` (http(s), no user or password), else `invalid_input` `Bestillingslenken må være en http- eller https-adresse uten brukernavn eller passord` |
| `lead_days` | integer 0..3650, default 0 |
| `balance` | a projection of the ledger (§3); no tool sets it |
| `movement_revision` | counts the article's ledger rows (§3) |
| `department`, `department_revision` | as on products (catalog README §4); changed only by `articles_transfer` |
| `active` | false once archived |
| `product_id` | the product the article was made for by `products_create` or adoption (§14), if any |

#### 2.2 Tools

- `articles_create {name, unit, sku?, package_size?, min_level?, max_level?, cost_price_ore?, supplier?, lead_days?, department?, opening_balance?=0}`
  (create, admin): `department` is checked as in catalog README §4;
  `opening_balance ≥ 0` (`Startbeholdningen kan ikke være negativ`) is
  written as one `aapning` movement in the same transaction, also when 0.
- `articles_get {id}` (read).
- `articles_list {query?, department?, active?=true, limit?}` (read): sorted
  by name; `query` is a case-insensitive substring of `name` in which `%`
  and `_` are ordinary characters; `active: false` lists the archived.
- `articles_update {id, revision?, …}` (update, admin): every field of
  §2.1 except `balance`, `movement_revision` and `department`; a stale
  `revision` is `conflict`; passing `balance` is `invalid_input`
  `Beholdningen endres bare gjennom lagerbevegelser`, passing `department`
  is `invalid_input` `Avdelingen endres med articles_transfer`;
  `active: true` reactivates an archived article. Bumps `revision`.
- `articles_archive {id}` (update, admin): `active` false; the ledger is
  kept, and consumption may still be written and reversed (§6).
- `articles_recount` writes a `telling` (§3.1); `articles_transfer` §11.

### 3. The ledger

#### 3.1 Movements

`movement = {"id","article_id","product_id","kind","quantity","revision","balance_after","reason","order_id","balance_updated","by","at"}`.

| Kind | Written by | Balance | Rules |
|---|---|---|---|
| `aapning` | `articles_create` only | `:= quantity` | once per article, quantity ≥ 0 |
| `mottak` | `inventory_receive` | `+ quantity` | integer 1..10⁶; article active |
| `justering` | `inventory_adjust` | `+ delta` | signed integer, ≠ 0, \|delta\| ≤ 10⁶, reason required; article active; a negative result is `insufficient_stock` |
| `telling` | `articles_recount {article_id, quantity, reason}` (create, admin) | `:= quantity` | quantity ≥ 0 (`Talt mengde kan ikke være negativ`), reason required (`Oppgi årsaken til lagerkorrigeringen`); article active |
| `forbruk` | the consumption sync only (§6) | `− quantity` when `balance_updated` | quantity > 0, `order_id` set, at most one per (order, article) |
| `reservasjon`, `frigivelse` | never written; readable when an older core stored them | none | |

A movement on an archived article (except `forbruk`) is `invalid_input`
`Lagerartikkelen er arkivert`. `product_id` is the article's product, if
any.

#### 3.2 Locking and order

Every balance-changing movement locks the article, increments
`movement_revision`, sets the balance and `balance_after`, and inserts the
row with `revision` = the new counter, in one write transaction. Ledger
order is `revision`, not time. Concurrent movements on one article never
interleave: of concurrent adjustments that would together overdraw, exactly
the overdrawing ones fail with `insufficient_stock`.

#### 3.3 Bounds

A balance above 10¹² is `invalid_input` `Beholdningen kan være høyst
1000000000000`: up to it every balance is exact at three decimals (core.md
§2.1). The same bound holds for what a consumption reversal gives back
(§6.3).

### 4. Product-keyed stock tools

`inventory_receive`, `inventory_adjust`, `inventory_balance` and
`inventory_movements` keep the product-keyed input and output of the
original stock tools and act on the product's article. Each also accepts
`article_id` in place of `product_id`; the schema keeps `product_id`
required and the server accepts either. A product without an article is not
stock tracked: the writes refuse it (`invalid_input` `Produktet <name> er
ikke lagerført`), the reads answer zeros.

- `inventory_receive {product_id | article_id, quantity, reason?}` (create,
  employee): `mottak`.
- `inventory_adjust {product_id | article_id, delta, reason}` (create,
  admin): `justering`; `delta` 0 is `invalid_input` `Justeringen kan ikke
  være 0`; `insufficient_stock` names the article and quantities (`Ikke nok
  <name> på lager: <balance> på lager, trenger <n>`).
- `inventory_balance {product_id | article_id}` (read):
  `{"product_id","article_id","on_hand","reserved","available"}` with
  `on_hand` = balance and `available = on_hand − reserved`, which may be
  negative; `product_id` is the named product, else the article's product,
  else null; a product without an article answers `article_id` null and
  zeros.
- `inventory_movements {product_id | article_id, limit?}` (read):
  `{"items":[movement]}`, highest `revision` first.

The article that `products_create` makes for a stock-tracked product (the
`stock_article` seam, §12) writes no `aapning`, so its first receipt has
revision 1, as the product-keyed ledger always numbered.

### 5. Reservations

Reservations are by article and opaque order id:
`set-order-reservations order-id requirements needed-on` makes an order's
reservations equal `requirements` (`(article_id . quantity)`, positive
quantities only), and `release-order-reservations` removes them. When an
order reserves and releases is orders' rule (orders README, reservation and consumption).
`reserved-quantity` sums an article's reservations for
`inventory_balance`.

### 6. Consumption

#### 6.1 The command

Orders applies an order's consumption as one synchronising command
`sync-consumption order-id order-revision effective-date expected`, with
`expected` a list of `(article_id . quantity)`. The expected map is the
positive sum per article; its fingerprint is the SHA-256 of the canonical
JSON of the sorted `[article_id, quantity]` list. An order's consumption is
**applied** when at least one `forbruk` row with its `order_id` exists
(`consumption-applied-p`). When orders consumes, reverses and re-syncs is
orders' rule (orders README, reservation and consumption).

#### 6.2 No-ops and conflicts

The newest applied command per order is remembered (`order_revision`,
`effective_date`, `fingerprint`). An older revision, or the same revision
with an earlier date, is a no-op; the same revision and date with the same
fingerprint is a no-op; the same revision and date with another
fingerprint is `conflict` `Lagerforbruk er allerede registrert for denne
versjonen` and nothing changes.

#### 6.3 Replacement

Otherwise the affected articles are locked in id order and the order's
`forbruk` rows are replaced wholesale: every existing row is reversed (its
quantity added back, unless §6.4 says the count wins) and deleted, and new
rows are written in article-id order. The whole sync runs in the caller's
write transaction; a failure leaves the prior consumption intact. An empty
`expected` reverses everything.

#### 6.4 A recount wins

An article is **recounted** for an order's row when a `telling` with a
higher `revision` than the row exists, or when the row already had
`balance_updated: false` and the article's latest `telling` is still what
its balance rests on (no `mottak`, `justering` or `aapning` with a higher
revision). A recounted article's old row is not added back, and its new row
has `balance_updated: false` and reason `Reservert for ordre (beholdning
manuelt justert)`: it does not deduct. Other new rows have
`balance_updated: true` and reason `Reservert for ordre`. A second
correction therefore never deducts what a recount already counted.

#### 6.5 Insufficient stock

A deducting row that needs more than the article's balance is
`insufficient_stock` (as in §4) and aborts the caller's whole operation.
A recount can therefore make a later consumption fail.

### 7. Forecast

`inventory_forecast {from, to, article_id?, include_unconfirmed?}` (read):

- the window is at most 366 days and `to` not before `from`, else
  `invalid_input` `Ugyldig periode: …`; an unknown `article_id` is
  `not_found`;
- demand is the `article_demand` seam (§12): `(article_id, date, quantity)`
  of orders whose demand is committed (with `include_unconfirmed`, also the
  not-started ones) and whose consumption is not applied, so consumed
  orders never count twice; which statuses count is orders' rule (orders
  README, stock); it is asked from the earlier of `from` and today;
- a demand dated in `[from, to]` lands on its date; one dated before `from`
  but not before today lands on `from`; others are ignored;
- per article: `start_balance` = balance; for each date `d`,
  `demand(d)` = the targeted sum and `balance(d) = balance(d−1) − demand(d)`;
  days before today are `historical` and subtract nothing;
- `status`: `none` (no demand in the window), `shortage` (some
  `balance(d) < 0`), `watch` (`end_balance` 0, or some `balance(d)` below
  that day's demand), else `balanced`;
- output `{"articles":[{"article_id","name","unit","start_balance","end_balance","days":[{"date","demand","balance","historical"}],"status"}]}`,
  articles by name; an archived article appears only when demand reaches
  it in the window.

`forecast-demand` lets one request that forecasts several articles ask the
seam once.

### 8. Shortages

`inventory_shortages {before_date}` (read) keeps the original product-keyed
shape: the articles with `shortage` in the committed forecast over
`[today, before_date]`, as `{"items":[{"product_id","article_id","name","needed","on_hand","shortfall","before_date"}]}`
with `needed` = the demand in that window, `on_hand` = balance,
`shortfall = needed − on_hand`, only positive shortfalls, by name.
`product_id` is the article's product, or the article's own id. A
`before_date` before today gives no items.

### 9. Purchase suggestions

`inventory_purchase_suggestions {days?=30}` (read, 1..366) and the
function `purchase-suggestions` (for a client's warehouse alert): for every
article whose committed forecast over `[today, today + days]` has a
shortage,

`{"article_id","name","unit","shortage_quantity","packages","order_quantity","supplier","first_shortage_date","order_by"}`

with `shortage_quantity` = −(lowest balance), raised to reach `min_level`
when `end_balance` is below it; `packages = ceil(shortage ÷ package_size)`
when the article has a `package_size`, else null; `order_quantity =
packages × package_size`, else the shortage; `order_by =
first_shortage_date − lead_days`. Sorted by `order_by`, then name.

### 10. Availability grid

`inventory_availability_grid {from, to, product_ids}` (read; 1..6 products,
window as §7): `{"items":[{"product_id","name","days":[{"date","available","total","booked","order_ids"}]}]}`
with `total = units_owned`, `booked` and `order_ids` from the `bookings_on`
seam (cleaning windows included, by the point semantics of orders README,
bookings and availability) and `available = total − booked`, which may be negative.

### 11. Department transfers

`articles_transfer {id, department, note, department_revision}` (update,
admin) runs the checks of catalog README §4 on the locked article, changes
its `department`, bumps `department_revision` and writes a transfer in the
same transaction. Products' transfers arrive through the catalog's
`product_transferred` seam (§12) and are written the same way.

`transfer = {"id","target_type":"article"|"product","target_id","from_department","to_department","note","by","at"}`
is append-only. `transfers_list {target_type, target_id, limit?}` (read)
lists them newest first, bounded per core.md §2.4. A transfer moves
ownership only; stock never moves.

### 12. Seams

Answered for the catalog (catalog README §12):

- `stock_article`: creates the article of a new stock-tracked product (its
  name and unit, no `aapning`, §4);
- `article_reference`: an article's name, unit and active flag;
- `product_transferred`: writes the product's transfer (§11).

Published (core.md §1.1), answered by orders:

| Seam | Kind | Asks | Default |
|---|---|---|---|
| `article_demand` | rule | `(article_id, date, quantity)` of the orders that count as demand, by event date; with `from`, only orders dated then or later | none |
| `bookings_on` | rule | units of a rental product that bookings block on a date, and the ids of those orders | 0, none |

Functions other modules use: `find-article`, `on-hand`, `reserved-quantity`,
`set-order-reservations`, `release-order-reservations`, `sync-consumption`,
`consumption-applied-p`, `received-since-p` (whether an article has a
`mottak` after an instant), `forecast-demand`, `purchase-suggestions`,
`article-key-product` (the id a product-keyed view shows for an article).

### 13. Tools

Reads are viewer, mutations employee unless marked admin (core.md §3.3).

| Tool | Kind | Policy | § |
|---|---|---|---|
| `articles_create` | create | admin | 2.2 |
| `articles_get`, `articles_list` | read | viewer | 2.2 |
| `articles_update`, `articles_archive` | update | admin | 2.2 |
| `articles_recount` | create | admin | 3.1 |
| `articles_transfer` | update | admin | 11 |
| `transfers_list` | read | viewer | 11 |
| `inventory_receive` | create | employee | 4 |
| `inventory_adjust` | create | admin | 4 |
| `inventory_balance`, `inventory_movements` | read | viewer | 4 |
| `inventory_shortages` | read | viewer | 8 |
| `inventory_forecast` | read | viewer | 7 |
| `inventory_purchase_suggestions` | read | viewer | 9 |
| `inventory_availability_grid` | read | viewer | 10 |

### 14. Adoption and rollback

An older core kept each stock-tracked product's balance in a per-product
stock level (`stock_levels`). At start (`adopt-older-stock`, idempotent)
every stock-tracked product without an article gets one with that balance
and movement count, linked to it (catalog README §14); its movements and
reservations are keyed by the new article, and movements without an actor
get `system:migration`.

The rollback preflight (core.md §6.4) counts, for an older core that reads
stock from those levels:

- an article that is not an untouched adoption of its product's level
  (same balance and movement count);
- a product linked to an article not made for it, or unlinked from the one
  made for it;
- every department transfer.
