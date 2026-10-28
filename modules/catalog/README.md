# tun module `catalog`

ASDF system `tun-catalog`, package `tun.catalog`; pinned by clients through
`flake.nix` in this directory (tun-platform.md §2, §4).

- **Owns:** `product` (with `article_id`, `department`, `requirements`, and `lite_requirement_id`, `lite_recipe_id`: what `set-lite-recipe` made, the only recipe it updates, §10), `recipe`, `choice_group`, `catalog_change`; `products_create`, `_get`, `_list`, `_update` (the capacity guard), `_transfer`, `_set_requirements`, `recipes_*`, `choice_groups_*`, `catalog_changes_list`; the resolver (§8). A client's `products_set_recipe` (the per-100-servings recipe shape) stays a client operation, sugar over `set-lite-recipe` (§10). A new or retargeted requirement must target an active article, recipe or group (§7.3).
- **Depends on:** none. What it needs from stock and orders it asks through seams that later modules answer.
- **Core range:** builds against core `>= 2.0.0, < 3.0` (`flake.nix` `core`,
  and `define-module` in the Lisp source; the client build and the module's
  load both refuse a core outside it, naming the constraint).
- **Publishes:** seams `stock_article` (inventory: the article of a new stock-tracked product), `article_reference` (inventory: an article's name and unit), `booked_peak` (orders: the capacity guard's peak), `catalog_departments` (staffing: the client's departments), `product_transferred` (inventory: the transfer record), `catalog_changed` (orders: `catalog_change`). Its exported symbols are its interface for
  the modules that depend on it; what clients may use is what it publishes
  to `TUN`.
- **Rollback:** its migrations only add tables and nullable columns, so the
  previous revision starts on a migrated database; whether it can also read
  every stored record is what the rollback preflight checks
  (core.md §6.4): it refuses when a record holds a value the
  previous core cannot decode (a status, price mode or movement kind it
  lacks), an order-line field its next write would drop, or a record of an entity the previous core lacks; recipes and choice groups themselves are not counted (an older core ignores them; a plan that carries their requirements is counted under orders)
  (docs/architecture.md, "Tenants and deployment").

## Contract

### 1. Scope

The catalog holds products: rental equipment (`rental`), consumables
(`consumable`) and services (`service`); the department that owns each; and
what each requires from stock (requirements, recipes, choice groups). It
resolves one order line into the stock it needs (§8); it does not plan,
reserve or consume. It knows no stock article and no order: what it needs
from them it asks through the seams of §12, which `inventory`, `orders` and
`staffing` answer. Kernel rules (policy, results and error codes,
idempotency, audit) are core.md §3; lists are core.md §2.4.

### 2. Products

#### 2.1 Fields

`product = {"id","revision","name","kind","unit","unit_price_minor","stock_tracked","units_owned","manual_url","created_at","article_id","department","department_revision","requirements","lite_requirement_id","lite_recipe_id"}`.

| Field | Rule |
|---|---|
| `name` | 1..120, required |
| `kind` | `rental`, `consumable` or `service`, required |
| `unit` | 1..20, required |
| `unit_price_minor` | integer ≥ 0, required (money in minor units, core.md §2.1) |
| `stock_tracked` | boolean, required; a relink sets it to whether a link remains (§2.4) |
| `units_owned` | 0..100000, default 0: units that can be rented at once (`rental`) |
| `manual_url` | optional, ≤ 2000, an `http(s)://` address without spaces, else `invalid_input` `Bruksanvisningen må ha en gyldig http(s)-adresse` |
| `article_id` | server-set: the stock article the product counts in; several products may share one |
| `department` | optional, one of the client's departments (§4); afterwards changed only by `products_transfer` |
| `department_revision` | server-set, starts at 1, bumped by every transfer |
| `requirements` | server-set, ≤ 50, set by `products_set_requirements` (§7) |
| `lite_requirement_id`, `lite_recipe_id` | server-set: the requirement and recipe `set-lite-recipe` created for the product (§10) |

`revision` starts at 1 and every accepted update bumps it (core.md §2.1).
Client fields such as a cleaning window are added by the client (core.md
§1.1).

#### 2.2 Create, get and list

- `products_create` (create, employee): checks `department` (§4); a
  stock-tracked product gets its article from the `stock_article` seam
  (inventory creates one with the product's name and unit; without
  inventory `article_id` stays null).
- `products_get {id}` (read): one product, with `requirements`.
- `products_list {query?, kind?, limit?}` (read): `query` is a
  case-insensitive substring of `name`; default limit 20, max 100,
  `has_more` (core.md §2.4).

#### 2.3 Update

`products_update {id, revision?, name?, kind?, unit?, unit_price_minor?, units_owned?, manual_url?, article_id?}`
(update, employee):

- a given `revision` that is not the current one is `conflict`;
- passing `department` is `invalid_input` `Avdelingen endres med
  products_transfer`;
- `manual_url: null` clears it;
- `kind` and `units_owned` pass the capacity guard (§3).

#### 2.4 The stock article link

`products_update {article_id}` relinks the product to an existing article,
and `article_id: null` unlinks it. Only an admin may do either, else
`forbidden` `Bare en administrator kan koble produktet til en
lagerartikkel`; an unknown article is `not_found`. `stock_tracked` becomes
whether a link remains. The stock tools that act on a product's article are
inventory README §4.

### 3. The capacity guard

When `products_update` changes `units_owned` of a `rental` product, or
changes its `kind` away from `rental`, the guard asks `booked_peak` for the
most units that calendar-active orders block on any one date (cleaning
windows included; orders README, bookings and availability):

- `units_owned` below the peak: `invalid_input` `Antall enheter kan ikke
  settes til <n>; opptil <peak> er allerede booket i aktive ordrer.`
- `kind` away from `rental` with a peak above 0: `invalid_input`
  `Tilgjengelighet kan ikke deaktiveres mens opptil <peak> er booket i
  aktive ordrer.`

Without orders the peak is 0. Other kinds have no guard. The per-date view
of the same numbers is inventory README §10.

### 4. Departments and transfers

A product's or article's `department` must be one of the client's
departments (`catalog_departments`, answered by staffing), else
`invalid_input` `Ukjent avdeling <d> (gyldige: …)`. Without that answer no
department is valid.

`products_transfer {id, department, note, department_revision}` (update,
admin) moves ownership; the checks, shared with `articles_transfer`
(`check-transfer`), run in this order, all `invalid_input` unless marked:

1. blank `department`: `Velg avdelingen lageret skal overføres til`;
2. an unknown department (above);
3. the current department: `Velg en annen avdeling`;
4. blank `note`: `Oppgi årsaken til overføringen`;
5. `department_revision` missing or not the current one: `conflict`
   `Avdelingen er endret siden du lastet siden; last siden på nytt`.

Then `department` changes, `department_revision` is bumped, and the
`product_transferred` seam records the transfer in the same transaction
(inventory's append-only transfer record, inventory README §11). Without
a module answering it the transfer is `invalid_transition` `Ingen modul
fører overføringer mellom avdelinger her`. A transfer moves ownership only;
`units_owned` never moves.

### 5. Quantities

Requirement and recipe quantities are decimals with at most three
fractional digits, transported as JSON numbers and stored exactly (core.md
§2.1). A quantity that is missing, not a number, negative or zero is
`invalid_input` with the field's message; more than three decimals is
`Mengder kan ha høyst tre desimaler`; above 10⁹ is `Mengden kan være høyst
1000000000`. Resolved entries are bounded by orders (orders README,
requirements and choices).

### 6. Recipes and choice groups

#### 6.1 Recipes

`recipe = {"id","revision","name","description","active","lines":[{"id","article_id","quantity","position"}]}`.
A recipe "use" consumes each line's quantity (§8).

- `recipes_create {name, description?, lines?}` (create, admin): `lines` is
  `[{article_id, quantity}]`, at most 100; every article must exist
  (`not_found` `Fant ingen lagerartikkel med id <id>`); quantity per §5
  (`Mengden må være større enn 0`).
- `recipes_update {id, name?, description?, lines?, active?}` (update,
  admin): `lines` replaces the list; a line naming an `id` keeps it, and an
  `id` the recipe does not have is `invalid_input` `Ukjent
  oppskriftslinje <id>`. Only a real change bumps `revision` and is a
  catalog change (§11).
- `recipes_archive {id}` (update, admin): `active` false.
- `recipes_get {id}`, `recipes_list {query?, active?, limit?}` (read):
  oldest first; an unknown id is `not_found`.

#### 6.2 Choice groups

`choice_group = {"id","revision","name","active","members":[recipe_id…]}`:
the recipes a customer picks among (flavours). A recipe may be in several
groups; in one group at most once (`invalid_input` `En oppskrift kan bare
stå én gang i en valggruppe`); every member must exist (`not_found`).

- `choice_groups_create {name, members?}`, `choice_groups_update {id,
  name?, members?, active?}`, `choice_groups_archive {id}` (admin writes;
  a real change bumps `revision` and is a catalog change).
- `choice_groups_get {id}`, `choice_groups_list {active?, limit?}` (read):
  oldest first.

### 7. Requirements

#### 7.1 Declarations

A product or service carries ordered requirements, embedded in it so the
two change together:

`requirement = {"id","name","target":{"kind":"article"|"recipe"|"choice_group","id"},"quantity","basis":"per_line"|"per_quantity"|"per_serving"|"per_day","picks","rounding":"exact"|"ceil_per_100","position"}`.

`position` is the index in the list; `rounding` defaults to `exact` (§8.4).

#### 7.2 Checks

`checked-requirement` checks each declaration in this order, all
`invalid_input` unless marked:

1. not an object: `Et krav må være et objekt`; a key outside the shape:
   `Kravet har ikke feltet <key>`;
2. `target` not an object: `Kravets mål må være et objekt med kind og id`;
3. `quantity` or `basis` missing: `Fyll inn mengde og hva kravet beregnes
   fra`; then `quantity` per §5;
4. an unknown `basis`: `Ukjent beregningsgrunnlag <b>; bruk …`;
5. an unknown target kind: `Kravet må gjelde en lagerartikkel, en oppskrift
   eller en valggruppe`;
6. no target id: `Velg en lagerartikkel for dette kravet`, `Velg en
   oppskrift for dette kravet` or `Velg en oppskriftgruppe for dette
   kravet`;
7. a target that does not exist: `not_found`;
8. a `choice_group` target needs integer `picks ≥ 1` (`Antall valg må være
   minst 1`) and basis `per_serving` (`Valggruppe-krav må beregnes per
   porsjon`); `picks` on another kind is `Antall valg er kun tillatt for
   valggruppe-krav`;
9. `rounding` outside `exact`, `ceil_per_100`: `Avrundingen må være exact
   eller ceil_per_100`;
10. `name` over 120: `Navnet kan være høyst 120 tegn`; a blank name is
    stored as null, others trimmed.

#### 7.3 Active targets

A new requirement, or one whose target changes, must target an active
article, recipe or group, else `invalid_input` `Lagerartikkelen er
arkivert`, `Oppskriften er arkivert` or `Valggruppen er arkivert`. What was
archived is not taken into use again; an existing requirement on it stays
and is still resolved, consumed and forecast.

#### 7.4 Replacing the list

`products_set_requirements {product_id | service_id, requirements}` (update,
admin) replaces the list (≤ 50). A declaration without `id` is new; one with
the `id` of an existing requirement updates it; an `id` the product does not
carry is `invalid_input` `Ukjent krav <id> for dette produktet`; those left
out are deleted. Each created, updated (with its changed fields) or deleted
requirement is a catalog change (§11). Services (`service`) carry
requirements like any product and never take part in availability.

### 8. The resolver

`resolve-line` turns one order line (its product, `quantity`, `servings`,
`choices` and the order's inclusive days) into entries `(article_id,
quantity, source)`. Orders aggregates them into requirement plans (orders
README, requirement plans). Requirements are taken in `position` order.

#### 8.1 Multipliers

| Basis | Multiplier |
|---|---|
| `per_line` | 1 |
| `per_quantity` | `quantity` |
| `per_serving` | `servings` (null counts as 0) |
| `per_day` | inclusive days of the order (single-day and dateless: 1) |

#### 8.2 Static requirements

`n = requirement.quantity × multiplier`. An article target gives one entry
of `n`; a recipe target gives one entry per recipe line of `line.quantity ×
n`. A static per-serving requirement on a product that also has a choice
group uses the full `servings` (cups for every serving of a two-flavour
machine).

#### 8.3 Choice groups

With `picks` set and `servings` divisible by `picks`,
`base = (servings ÷ picks) × requirement.quantity`, and each pick (1-based
`position`, in the line's order) expands its recipe's lines × `base`. No
picks, servings not divisible, or a group or recipe that no longer exists
gives nothing; a pick that is not a member is skipped.

#### 8.4 Rounding

`exact` keeps the decimal. `ceil_per_100` rounds each entry up to a whole
unit: with recipe lines of `per_100_servings ÷ 100` and quantity 1 per
serving, an entry is `ceil(servings × per_100_servings ÷ 100)` (§10).

#### 8.5 Sources

Each entry's source is `{"requirement_id","requirement_name","recipe_id","pick_name","position","source_key"}`
with `source_key = "krav:<requirement_id>:<recipe_id>:<position>:<line_id>:<article_id>"`
(null parts dropped).

### 9. Order-line choices

A line's `choices` is `{"<requirement_id>": [recipe_id, …]}`, in placement
order. `check-line-choices`, which orders calls when it saves a line, checks
(all `invalid_input`):

- a key that is not a choice-group requirement of the product: `Valget <key>
  hører ikke til et valggruppe-krav på produktet`;
- a product with a choice-group requirement needs `quantity` 1: `Ordrelinjer
  med valggruppekrav må ha antall 1. Legg til én linje per enhet.`;
- per group requirement, missing choices count as zero picks; a count other
  than `picks`: `<name> krever <picks> valg (<n> valgt)`; servings not
  divisible by `picks`: `Porsjoner må deles likt på <picks> valg`; a pick
  that is not an active recipe and member of an active group: `<name>
  inneholder ugyldige valg`.

`<name>` is the requirement's name or `Valggruppe-krav`.

### 10. The per-100-servings recipe

A client may offer `products_set_recipe {product_id, lines:
[{component_product_id, per_100_servings}]}`, the per-100-servings recipe
shape of the original contract; it is a client operation and sugar over
`set-lite-recipe`, which takes `(article_id . per_100_servings)` pairs:

- the pairs become the lines (`quantity = per_100_servings ÷ 100`) of the
  product's own recipe, which one requirement `{target: that recipe,
  quantity: 1, basis: per_serving, rounding: ceil_per_100}` targets, so the
  numbers are `ceil(servings × per_100_servings ÷ 100)` per component (§8.4);
- the recipe and requirement it created are recorded on the product
  (`lite_recipe_id`, `lite_requirement_id`); only that recipe is ever
  updated, and only while it is active and no other product requires it
  (directly or through a choice group);
- otherwise a new recipe named after the product is created and the own
  requirement, if the product still has it, is retargeted to it: a recipe
  shared with another product is never rewritten;
- a product given its requirement before these fields existed has nothing
  recorded; then its own requirement is the `per_serving`, `ceil_per_100`
  requirement of quantity 1 on a recipe whose lines equal the components
  being replaced;
- every write is a catalog change (§11), except when the client adopts a
  recipe stored by an older core at start (`:adopting`), which records none:
  the numbers planned with are unchanged.

The client checks its own input (`per_100_servings` is an integer ≥ 1) and
adopts stored recipes once.

### 11. Catalog changes

Every write to a requirement, recipe or choice group records

`catalog_change = {"id","resource_type":"requirement"|"recipe"|"choice_group","resource_id","operation":"created"|"updated"|"deleted","changed_fields","at","by","product_id"}`

(`changed_fields` sorted; `product_id` for a requirement: the product that
carries it) and calls the `catalog_changed` seam in the same transaction;
orders answers it by scheduling `catalog_change` (orders README, catalog
impact). `catalog_changes_list {limit?}` (read) lists them newest first,
bounded per core.md §2.4. Nothing is recorded while an older database's
catalog is adopted at start.

### 12. Seams

Extension protocols (core.md §1.1, tun-platform.md §2.4) the catalog
publishes and a later module answers:

| Seam | Kind | Asks | Default | Answered by |
|---|---|---|---|---|
| `stock_article` | after | the article a new stock-tracked product counts in | null | inventory |
| `article_reference` | rule | an article's name, unit and active flag | none | inventory |
| `booked_peak` | rule | most units of a rental product booked on one date (§3) | 0 | orders |
| `catalog_departments` | rule | the departments products and articles may belong to (§4) | none | staffing |
| `product_transferred` | after | record a product's change of department (§4) | `invalid_transition` | inventory |
| `catalog_changed` | after | react to a recorded catalog change (§11) | nothing | orders |

### 13. Tools

Reads are viewer, mutations employee unless marked admin (core.md §3.3).

| Tool | Kind | Policy | § |
|---|---|---|---|
| `products_create` | create | employee | 2.2 |
| `products_get`, `products_list` | read | viewer | 2.2 |
| `products_update` | update | employee; `article_id` admin | 2.3, 2.4, 3 |
| `products_transfer` | update | admin | 4 |
| `products_set_requirements` | update | admin | 7 |
| `recipes_create`, `recipes_update`, `recipes_archive` | create, update | admin | 6.1 |
| `recipes_get`, `recipes_list` | read | viewer | 6.1 |
| `choice_groups_create`, `choice_groups_update`, `choice_groups_archive` | create, update | admin | 6.2 |
| `choice_groups_get`, `choice_groups_list` | read | viewer | 6.2 |
| `catalog_changes_list` | read | viewer | 11 |

### 14. Upgrade, adoption and rollback

The module's migrations only add tables and nullable columns (core.md
§6.3). `link-product-article` lets inventory link an older core's product
to the article it adopts for it (inventory README §14). The rollback
preflight (core.md §6.4) counts the records an older core cannot read, as
the summary above says; recipes and choice groups are not counted.
