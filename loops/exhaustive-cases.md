# A case over a declared set that misses a value stops the build

- loop: exhaustive-cases
- mode: reviewed
- stage: ship
- base: e2f1a6ed18ae20a0ef367a676fd57acc19c23774
- item: sak_bqwf10atarkamxjq
- estimate: 1h 2h 4h
- like: tun/test-timing tun/search-reads
- tags: kind:language core
- verified: fe54624ada9d5de206de57e670b97f5e9d57901e
- shown: fe54624ada9d5de206de57e670b97f5e9d57901e

## Brief

Ferdig sak_bqwf10atarkamxjq («Exhaustive case analysis over declared
sets: a missing case stops the build»), brought by the factory's
orchestrator on 2026-11-15. The owner asked on 2026-11-14: «Is it possible
to build exhaustive pattern matching in tun?», and asked for the item. As
the orchestrator reads it: when a closed set of cases grows (a new order
state, a new kind of refusal), the build stops at every place that
handles the set and was not updated, instead of the gap being found at
run time.

The orchestrator's plan: (1) case analysis over a set the registry
already declares (an entity's states, a field's allowed values, a
refusal's kinds, a module's roles), as a macro the clients reach; the
form names the set, the set is looked up when compiling, and a missing
branch or one outside the set is a compile-time warning naming the set,
the values and where the set is declared; an explicit «the rest»;
(2) Serapeum's `ecase-of`, `etypecase-of`, `defunion` and `match-of`
allowed and documented for a client's own closed types, or thin Tun names
over them, decided and said why; (3) a guard a client can turn on that
finds a plain `case`, `ecase` or `cond` on a declared field; (4) Tun's
own `ecase` forms over a declared set moved onto the macro, the others
left, both listed, no behaviour changed; (5) `docs/client-api.md`,
`reference/style.md`, `reference/pitfalls.md`. To settle in the spec:
what happens when the set changes (the incremental build must never pass
falsely, proven by a test that adds a value and builds incrementally, in
the same system and another), a set declared in another module, sets a
client can extend, and the limits (closed sets of values and types, not
nested patterns; Coalton stays out). Criteria: a missing and an unknown
case each stop a strict build with that message; a complete form compiles
cleanly and runs the right branch for every value of every declared set
of Tun's registry; the incremental proof; the guard finds a planted
`ecase` in a test client and passes on it as it stands; Tun's moved forms
listed and the suites unchanged; one tested example per Serapeum form, in
the docs as in the test; core 2.40.0 with the five clients unchanged, and
what tun-erp would write where it switches on order, quote, invoice and
work-order states, with one real example rewritten (tun-erp read only).
The form's name and how it reads is the owner's choice: a question with
lettered answers in the report, one of them built.

## Criteria

1. **A gap stops the build.** `ecase-of` over `(ENTITY FIELD)` that
   lacks a branch for a value, and one whose branch names a value outside
   the set, each signal a full `warning` (`case-set-warning`) when
   compiled, whose text names the form's place, the set, the values
   missing or outside, where the set is declared (file:line and module)
   and the set's values. The same for a `member` type (`ecase-of
   error-code`) and for `etypecase-of` over an `or` type, whose message
   names the `deftype` and its file (the image keeps no line or module
   for a type). A set that is
   not there (an entity no one defined, a field it lacks, a `string`
   field, a type that is not `member`/`or`), `case-of` without
   `otherwise`, a `case-of` branch naming a value outside the set, and a
   value named twice each warn too, saying which. A test compiles each
   such form and reads the warnings. (test)
2. **A complete form is silent and right.** For every enum field and
   enum computed field of every entity in Tun's registry with every
   module loaded, and for every member type the kernel's code switches
   over (`error-code`, `role`, `policy`, `operation-kind`), a generated
   `ecase-of` with one branch per value compiles without a warning and
   returns each value's own branch; a value outside the set signals
   `case-not-handled`; with `otherwise` it takes that branch, and NIL
   too; `case-of` takes its named values and sends the rest to
   `otherwise`. (property test)
3. **The set changes, the build stops.** A child process builds, with
   ASDF as `bin/build` does, a scratch system that declares an entity
   with an enum and uses it with `ecase-of` in a later file, and a second
   system depending on it that uses the same set: clean. A value is
   added to the enum (the file's time moved past the fasls'), and the
   next, incremental build warns for both forms (same system, other
   system). A third system without `:serial t`, whose using file ASDF
   does not recompile, warns when loaded, naming the form and «compiled
   against another set». In the test image, defining an entity again
   with a changed enum warns for the loaded form over it. (test)
4. **Same file, other module.** A form after its `define-entity`,
   `extend-entity` or `define-computed-field` in the same file compiles
   against that set; one over an entity no loaded system defines warns
   with the advice to define it first or add the dependency. (test)
5. **The guard.** `plain-case-findings` (in `tun.test-support`) finds, in
   planted source text, an `ecase` on a declared field's reader, a `case`
   on one, and a `cond` comparing one form with two or more values of
   one set; each finding names the file, the top-level form's line and
   the set; it leaves `ecase-of`, `case-of`, a `when`/`member` test and
   a `cond` over strings of no set alone. Run on the test client's
   sources as they stand on the base, it reports one real finding:
   `tier-discount-percent` (`tests/client/customers.lisp`), a `cond`
   comparing `tier` with "gull" and "sølv", values of `(customer
   loyalty-tier)`, naming the file, the line and the set (a test holds
   the base's text of that function). After criterion 7 moves it, the
   test client turns the guard on with `(define-generated-tests … :cases
   t)` and passes; `generated-cases-over-declared-sets-name-their-set`
   exists only with `:cases t`. Tun's own `src/` and `modules/` pass it
   (a core test). (test)
6. **Tun's own code.** Every `ecase` of `src/` and `modules/` is listed
   under «Inventory» as moved or left with the reason; those over a
   declared set, and the `case` and `cond` forms the guard finds, are on
   `ecase-of`/`case-of`, with no behaviour changed: the suites pass with
   no test changed but the new ones. (inventory, verify)
7. **A client's own closed types.** The `etypecase-of` example of
   `docs/client-api.md` (deliveries) and its `ecase-of` and `case-of`
   examples are in the test client's suite as they are in the docs,
   each with a test of its branches; the test client's own
   `tier-discount-percent` switches with `ecase-of (customer
   loyalty-tier)`. (test)
8. **Where people read it.** `spec/core.md` §2.7, `spec/testing.md` §1
   (test 11), `docs/client-api.md` «Switching over a closed set»,
   `reference/style.md` and `reference/pitfalls.md` say it; core 2.40.0;
   `bin/test` green; the five clients compile and pass unchanged at
   their `origin/main`; «Clients» below shows what tun-erp would write
   for its order, quote, invoice and work-order states, with one real
   function rewritten (tun-erp unchanged). (verify, client runs, record)
9. **The owner's choices, asked.** The final report puts the form's name
   and how it reads to the owner as a question with lettered answers,
   each shown as code, the one built (A: `ecase-of`/`case-of` with the
   set first) and a recommendation; and Serapeum (Tun's own forms, built,
   or Serapeum as a dependency with its four forms open to clients) as a
   second question. (report)

## Decisions

- **Tun's own forms, not Serapeum.** The brief says Tun depends on
  Serapeum; it does not: Serapeum is in `flake.nix` only among the
  reference sources agents read, not in `coreLibs`. Adding it would put
  about fifteen libraries into every deployment and every client's
  build (Trivia and its dependencies, split-sequence, string-case,
  parse-number, trivial-garbage, global-vars, introspect-environment,
  parse-declarations, trivial-file-size, trivial-macroexpand-all,
  atomics), and its `ecase-of` knows only types: it cannot name an
  entity's field, whose values are strings that `case` never matches.
  The check it makes is small (a `subtypep` over the clauses), so Tun
  carries three forms of its own, named and shaped as Serapeum's
  `ecase-of`, `case-of` and `etypecase-of`, so code reads the same to
  someone who knows them, and one way of writing it holds for registry
  sets, member types and a client's types. `defunion` and `match-of`
  (algebraic data types with destructuring patterns, built on Trivia)
  are not offered: a client's closed set of kinds is classes or
  structures and a `deftype` of their `or`, matched with `etypecase-of`,
  which the docs show and the test client runs. Whether to take
  Serapeum after all is a question for the owner in the report.
- **The sets the registry declares.** The registry's closed sets are the
  enum fields: of `define-entity`, of `extend-entity` (a client's own
  field), of `define-computed-field`, and the elements of `(list-of
  (enum …))`. Tun has no separate state machine: an entity's states are
  its `status` (or `state`) enum, and `:kind :transition` operations move
  between them. The kinds of refusal are the kernel's `error-code` type,
  closed in the kernel, exported to `TUN` (no client's sources name a
  symbol `error-code`). Roles are the kernel's `role` and `policy`
  types: modules declare no roles of their own; they stay internal, as
  exporting `role` would collide with clients' fields and variables named
  `role`. An operation's enum parameter is not addressable: the
  operation is defined only after its body compiles; such a parameter
  copies a field's set, which is named instead. No set is open to a
  client: `extend-entity` refuses to redefine a module's field, so a
  client adds values only by adding a field of its own, a set of its
  own. Open sets (an order's departments, which a seam answers; any
  `string` field) are refused with a warning.
- **The set is noted when compiling, as well as loading.**
  `define-entity`, `extend-entity` and `define-computed-field` expand
  into one more form, `(eval-when (:compile-toplevel :load-toplevel
  :execute) (note-declared-fields …))` with the fields' names and type
  designators, so a form later in the same file sees the set (the class
  itself exists only once the file is loaded), and a compile, a load and
  a REPL evaluation all keep the noted set current. `ecase-of` reads
  that table, never the class. This is the one exception to the style
  rule «read no other definition while expanding», said in
  `reference/style.md`.
- **Stale expansions are caught three ways.** ASDF recompiles a file
  whose dependency was recompiled, in the same system (`:serial t`) and
  in dependent systems: measured with a plain ASDF experiment before the
  spec (a macro reading a list another file defines, in a serial system
  and in a system depending on it: both users recompiled and warned after
  the list grew). That covers `bin/build` and a second `tun preview`;
  `nix build` and both `bin/test`s compile afresh anyway. For a file ASDF
  does not know depends on the set's (no `:serial t`, no `:depends-on`)
  each form notes, at load time, the set it was compiled against and
  warns when the set now differs; and a redefinition in a running image
  warns for the loaded forms over the set. The forms still compare at run
  time, so a stale form never takes a wrong branch: it signals
  `case-not-handled`.
- **The forms' details.** Strings compare with `equal` (NIL and a
  non-string fall through rather than signal a type error); member types
  with `eql`. `otherwise` and `t` both end a form, as in `case`. In
  `ecase-of` a final `otherwise` takes only what is outside the set (no
  value of the set may lean on it), which is what a label function with a
  fallback for odd data needs, as the orders module's `status-label`
  does. `case-of` requires `otherwise`. The place a message names is the
  top-level form's file and line (`current-source-location`, as every
  definition records it).
- **The guard is opt-in and reads source.** As the existing generated
  tests do (`public-interface-violations`), it reads files with the
  reader, honouring `in-package`, and recognises a field's reader through
  the entity classes' slot readers. A `cond` is a case analysis when two
  or more of its branches compare the same form with string literals all
  in one set (`member` of a quoted list in a branch counts); a single
  comparison, `when`, `if` and a `member` outside a `cond` are not. Only
  sets the file can name count (the entity's symbol accessible in its
  package), so a module is never told to name another module's
  unpublished entity. It
  is a test of `define-generated-tests` under `:cases t`, the way a
  client already chooses its generated tests' options (`:isolate`), and
  `plain-case-findings` for a client's own test. Tun runs it on its own
  code in its core suite, so the adoption stays.
- **The test client changes, for the guard's one real finding.** On the
  base, the guard finds `tier-discount-percent` in the test client, a
  `cond` over the computed field `(customer loyalty-tier)`'s values. That
  is the kind of place the owner wants stopped when the tiers grow, so
  it moves to `ecase-of` with a branch per tier (and `otherwise` 0, as
  the `cond`'s `t` gave for anything else) before the test client turns
  the guard on; «as it stands» is read as «without a planted form».
  The test client also gains the docs' examples (criterion 7).
- **A kernel file's place names `src/`, not `modules/cli/src/`.**
  `asd-directory` took the first `.asd` of Tun's top directory, which is
  `tun-cli.asd` since that system was added, so every kernel
  definition's place read `modules/cli/src/…`; a `deftype`'s place in a
  message showed it. It now prefers `tun.asd` where there are several.
- **The core version** goes to 2.40.0: new exports in `TUN` and
  `TUN.CORE`; no public call changes shape.

## Inventory

`src/` and `modules/` hold 36 `ecase` forms and 7 `etypecase` forms (43;
the brief's 44 counted one more). None of the `ecase` forms is over an
enum field: an enum's values are strings, which `ecase` never matches.
One is over a declared set, the kernel's `role` type:

| Place | Over | Done |
|---|---|---|
| `src/core/actor.lisp` `role-rank` | `role`, the kernel's roles | moved: `ecase-of role` |
| `src/store/postgres.lisp` ×3, `src/store/sqlite.lisp` ×4, `src/store/memory.lisp` ×3 | a query's comparison operators and sort directions, the SQLite synchronous mode | left: keywords of a query's syntax, no declared set |
| `src/core/query.lisp`, `src/core/record-policy.lisp` | the parts of a parsed condition | left: parser output |
| `src/core/formats.lisp` ×4, `src/jobs/cron.lisp` | months and weekdays by number | left: numbers |
| `src/core/trace.lisp`, `src/web/ui/markdown.lisp` ×2, `src/web/ui/kit.lisp` | UTF-8 lengths, heading levels | left: numbers |
| `src/web/ui/toolbar.lisp` ×3, `src/web/ui/charts.lisp`, `src/web/ui/graph.lisp` | a filter's kind, a chart's kind, a graph node's state: options of a component | left: no type names them |
| `src/push/push.lisp`, `src/mail/mail.lisp`, `src/jobs/runner.lisp`, `src/outbound/programs.lisp`, `modules/orders/plans.lisp` | the outcome of one attempt, a function's own return values | left: no type names them |
| `src/platform/introspection.lisp`, `src/platform/errors.lisp`, `src/jobs/jobs.lisp`, `modules/staffing/unavailability.lisp` | a request's state, the transaction mode, a uniqueness scope, `to-utc`'s status | left: no type names them |
| the 7 `etypecase` forms | Lisp's own types (strings, vectors, functions) | left: open types |

Beyond `ecase`, the forms over a declared set that are `case` or `cond`:

| Place | Over | Done |
|---|---|---|
| `src/web/ui.lisp` `error-title` | `error-code` (from a JSON document: any keyword) | `case-of error-code`, `otherwise` as before |
| `src/core/conditions.lisp` `error-status` | `error-code` | left: `case`, since `conditions.lisp` is compiled before `cases.lisp` and what its expansion calls (`types.lisp`, `trace.lisp`) |
| `src/auth/accounts.lisp` `role-keyword` | `(account role)` | `ecase-of`, `otherwise` signals «Unknown role» as the `cond`'s `t` did |
| `modules/catalog/requirements.lisp` `resolve-line`'s `multiplier` | `(product-requirement basis)` | `ecase-of` with `per_day` named, `otherwise` days as the `t` gave |
| `modules/orders/orders.lisp` `apply-price-mode` | `(order price-mode)` | `ecase-of`: NIL with `automatic`; `manual_total` refuses without `allow-manual` as the `and` did; `otherwise` refuses as the `t` did |
| `modules/orders/package.lisp` `status-label` | `(order status)` | `ecase-of`, `otherwise` the status as it is; moved to `orders.lisp` after the entity, since `package.lisp` is compiled before the set is declared |
| `modules/orders/plans.lisp` `line-references-p` | `(catalog-change resource-type)` (published by catalog) | `ecase-of` with `recipe` named, `otherwise` the recipe test the `t` made |
| `src/core/actor.lisp` `parse-actor` | role names, which the guard matched to `(account role)` | left: `tun.core` cannot name `tun.auth`'s `account` (the guard counts only sets a file can name) |
| `modules/dashboard/errors.lisp` `error-status-label` | the errors tool's statuses, `(error-group status)` of `tun.errors` | left: no public package of the kernel publishes `error-group` to modules |

The guard, run on `src/` and `modules/` before these moves, found the
seven `cond` forms above; after them it finds none (criterion 5).

## Clients

On this loop's tree as committed at `e010f93c` (verify round 1), each
client's `bin/test` with `--override-input tun` at it (and `dashboard`,
and tun-erp's `customers`, at their `modules/` directories), one at a
time, from clones of their `origin/main` in a scratch folder, unchanged:
factory, nixploy-dashboard and ferdig (tunworks `0189370`: 690, 1421 and
812 checks), kurs `a82a83d` (352) and tun-erp `6ed8186` (its suites of
7828, 75830, 378, 349, 304, 8856, 255, 109918, 90918, 16264 and 26123
checks) pass, with no compiler warning and no failure.

The cases guard, run read-only over tun-erp's `modules/` with that tree
loaded, finds 19 `cond` forms over its declared sets, among them
`sales/order-pages.lisp:111 status-badge`, `sales/quote-pages.lisp:424
state-badge`, `work/work-order-pages.lisp:24 work-status-badge` and
`:243 action-part`, `work/work-time.lisp:189 check-registrable` (a
partial one: `case-of`), `billing/status.lisp:110 invoice-state` (over
`(invoice status)`) and eleven in billing's accounting calls and
payments; tun-erp does not turn the guard on, so its suite is unchanged.

**What tun-erp would write** (read at its main `6ed8186`, not changed).
Its states are enum fields of its own modules' entities, so each module
names its own sets; a page module that reads another module's records
through tools names the set when that module publishes the entity.

| States | The set | Where it switches today |
|---|---|---|
| order | `(order status)` in `tun.sales`: draft, quote_sent, accepted, confirmed, in_progress, fulfilled, closed, cancelled | `sales/order-pages.lisp` `status-badge` (below) |
| quote | `(quote-version recorded-state)`: open, accepted, declined, replaced, withdrawn, expired (the state a quote reads as, `expired` past its date, is a value of the same set) | `sales/quote-pages.lisp` `state-badge`, and the customer's notes in `quote-pages.lisp` (a `cond` over `status` and `state`) |
| invoice | `(invoice status)`: pending, issued, credited | `billing/invoice-pages.lisp` `invoice-badge` (an `if`: issued or not) |
| an invoice's payment state | not declared: `billing/status-pages.lisp`'s `+states+` (pending, open, part_paid, overdue, paid, credited), computed by a tool | `state-text`, `state-badge`, the pay page's `cond`; to be checked it must first be declared, as `(define-computed-field invoice state (i) (:type (enum "pending" "open" "part_paid" "overdue" "paid" "credited")) …)`, after which `(ecase-of (invoice state) …)` |
| work order | `(work-order status)` in `tun.work`: planned, started, finished, cancelled | `work/work-order-pages.lisp` `work-status-badge` and the start/finish buttons; `overview/front-page.lisp`'s tone (through tools: it names the set if `work` publishes `work-order`) |

One real function rewritten, `status-badge` of `modules/sales/order-pages.lisp`:

```lisp
;; Today: a status added to the order's set gets :outline here, silently.
(defun status-badge (status)
  (ui:badge (:variant (cond ((member status '("draft" "closed") :test #'equal) :secondary)
                            ((equal status "cancelled") :destructive)
                            ((equal status "fulfilled") :success)
                            ((member status '("confirmed" "in_progress") :test #'equal) :info)
                            (t :outline)))
    (status-text status)))

;; With ecase-of: every status names its variant, and a status added to
;; (order status) stops the build here until it has one.  The otherwise
;; keeps :outline for what is outside the set, such as a missing status.
(defun status-badge (status)
  (ui:badge (:variant (ecase-of (order status) status
                        (("draft" "closed") :secondary)
                        ("cancelled" :destructive)
                        ("fulfilled" :success)
                        (("confirmed" "in_progress") :info)
                        (("quote_sent" "accepted") :outline)
                        (otherwise :outline)))
    (status-text status)))
```

With `(define-generated-tests … :cases t)` the guard would find, among
others, this `status-badge`, `work-status-badge` and the quote's
`state-badge`, each a `cond` comparing one form with values of one set.

## Log

- 2026-11-15 03:46  started, reviewed
- 2026-11-15 03:47  estimated 1h 2h 4h at brief, like tun/test-timing tun/search-reads
- 2026-11-15 03:54  gate A asked of a reviewer
- 2026-11-15 03:56  gate A: changes (reviewer)
  I checked the packet against the brief, and the Decisions against the repository. Three gaps remain, all small. Each is a criterion or record item the brief asks for that the spec leaves out or contradicts.
  
  **What is right**
  - Criteria 1–4 cover the core of the brief as tests: a missing case and an unknown one, a complete form across every registry set, the incremental proof in the same system and in another, and a set declared in the same file or another module.
  - The spec text (`spec/core.md` §2.7, `spec/testing.md` test 11, docs, style, pitfalls) says the same as the criteria.
  - **Strict builds and the load-time warning:** §2.7 claims the strict builds count it. That holds: `scripts/setup.lisp:57` counts every `warning` raised during `load-system`, and loading is when this one is raised.
  - **Serapeum is not a dependency.** It appears in `flake.nix:133` only in the `reference` list, not in `coreLibs`. Since the brief's premise is false, writing Tun's own forms instead of pulling in about fifteen libraries is a reasonable call. The brief asked for this to be "decided and said why", the Decisions do that, and the owner gets the question in the report.
  - **The kernel's types match the record.** `error-code`, `role`, `policy` and `operation-kind` are `member` types, as stated (`src/core/conditions.lisp:12`, `src/core/actor.lisp:7-8`, `src/core/operation.lisp:23`).
  
  **Changes**
  1. **The owner's naming question is missing.** The brief ends: «The form's name and how it reads is the owner's choice: a question with lettered answers in the report, one of them built.» Neither the criteria nor the Decisions mention it. Only the Serapeum question is promised for the report. Add it to criterion 8's record items (lettered answers, which one was built), or as a criterion of its own.
  2. **The test client will not pass the guard as it stands.** The brief says the guard «passes on it as it stands». But `tests/client/customers.lisp:37-39`, in `tier-discount-percent`, is a `cond` that compares `tier` with `"gull"` and `"sølv"`. Both are values of `(customer loyalty-tier)`, so test 11 as specified flags it. Criterion 7 quietly rewrites the function so that criterion 5 passes. Make this explicit:
     - In criterion 5: the guard reports this `cond` in the unchanged source, naming the file, the line and the set. That is a real finding, not only a planted one.
     - In Decisions: the test client changes for this reason.
  3. **Criterion 1 never tests `case-of` with an unknown value.** The brief asks that «an unknown case» stop a strict build, and §2.7 says `case-of` checks the values it names. Criterion 1 only tests the outside-the-set branch for `ecase-of`, and for `case-of` only a missing `otherwise` and a value named twice. Add a `case-of` branch naming a value outside the set to the forms the test compiles.
- 2026-11-15 03:59  gate A asked of a reviewer
- 2026-11-15 04:00  gate A: approve (reviewer)
  The three changes asked for in round one are all in:
  
  1. **The naming question.** Criterion 9 now puts the form's name and how it reads to the owner as a question with lettered answers, each shown as code, with the one built (A) marked and a recommendation. Serapeum is a second question.
  2. **The test client's real finding.** Criterion 5 says the guard, run on the base's source, reports `tier-discount-percent` in `tests/client/customers.lisp`, naming the file, the line and `(customer loyalty-tier)`. A Decision says the test client changes for that reason. I checked the repository: `tests/client/customers.lisp:37-38` compares `tier` with "gull" and "sølv", and line 31 declares `(enum "bronse" "sølv" "gull")`, so the claim holds. Reading «as it stands» as «without a planted form» is reasonable and is recorded.
  3. **`case-of` with an unknown value.** Criterion 1 now includes «a `case-of` branch naming a value outside the set».
  
  **The rest still holds**
  - **The brief is covered:**
    - (1) the forms: criteria 1, 2 and 4
    - (2) Serapeum, decided and explained: Decisions, with criterion 9 asking the owner
    - (3) the guard: criterion 5
    - (4) the inventory: criterion 6 and «Inventory»
    - (5) the docs: criterion 8
    - the incremental proof, in the same system and another: criterion 3
    - client-extensible sets, other modules, the limits and Coalton: §2.7
    - 2.40.0, the five clients, tun-erp: criterion 8
  - **Each criterion can be decided** by a named test, an inventory, verify or the report.
  - **The spec says the same as the criteria.** That covers `spec/core.md` §2.7, test 11 and the cases-guard paragraph in `spec/testing.md`, and the docs, style and pitfalls texts.
  - **The examples match the code.** The §2.7 example's order statuses match `modules/orders/orders.lisp:47-48`, and the example's place for the declaration (`orders.lisp:47 (module orders)`) is right.
  - **No Decision takes a choice that belongs to the owner.** Two choices are the owner's to make: the form's name, and dropping `defunion`/`match-of` (which goes against «one tested example per Serapeum form»). Both are put to the owner in criterion 9 and not settled silently.
  
  **Two notes for gate B (they don't block):**
  - Criterion 1 asks for «the same» message for a member type, which includes «file:line and module». The draft `type-declared-at` (`src/core/cases.lisp:442`) gives only the file, and a `deftype` has no module. The test should check what §2.7 promises for types, or the criterion's wording should say what a type's message names.
  - §2.7 says that `ecase-of` signals `case-not-handled`, but `src/public.lisp` doesn't export it to `TUN`. If clients are meant to be able to handle it, export it.
- 2026-11-15 04:36  verify 1: passed build, test, check
- 2026-11-15 04:37  shown (/)
- 2026-11-15 05:00  gate B asked of a reviewer
- 2026-11-15 05:01  gate B: approve (reviewer)
  I'm approving this gate. Every criterion has a test that would fail without the change, every verify step and browser check passed, and the brief is met.
  
  **Verification**
  - All three steps in `verify.txt` passed: build, test and check.
  - None of the 50 check files in `checks/` has a failed result.
  - The change has no interface of its own, so the screenshots only show that nothing else moved.
  
  **Criteria against tests** (all in `tests/case-tests.lisp` unless named)
  1. **A gap stops the build.** Separate tests cover:
     - a missing branch (`case-tests.lisp:1284`);
     - a value outside the set, in both `ecase-of` and `case-of` (`:1295`; gate A asked for the `case-of` one);
     - `case-of` with no `otherwise`, and a value named twice (`:1309`);
     - a member type, whose message names `deftype error-code in src/core/conditions.lisp` (`:1320`). That check also proves the `asd-directory` fix in `src/core/trace.lisp:995`, since without it the place would read `modules/cli/src/…`.
     - an `or` type (`:1332`);
     - all seven ways a set can be missing (`:1344`).
  
     Each test checks the warning is a full warning, not a style warning.
  2. **A complete form is silent and right.** `every-declared-set-runs-the-branch-of-each-value` generates a form for every enum set in the registry (and asserts there are more than 40) and for the four kernel member types. It checks each value's branch, `case-not-handled`, `otherwise` including NIL, and `case-of`'s fall-through.
  3. **The set changes, the build stops.** The child-process build in `tests/fixtures/case-build.lisp` covers the same file, a later file and another system: exactly three warnings, exit 2. The system without `:serial t` gets the load-time «compiled against another set» warning. Redefining a set in a running image is tested (`:1431`), though through `note-declared-fields` directly; that is what `define-entity` now expands into.
  4. **Same file, other module.** `parcel.lisp` in the fixture declares the set with `define-entity`, `extend-entity` and `define-computed-field` and uses it in the same file. The advice for an entity no loaded system defines is tested.
  5. **The guard.**
     - On planted text it makes three findings, with the right lines, and leaves the other forms alone.
     - On the base's `tier-discount-percent` it reports `(customer loyalty-tier)`.
     - The generated test exists only with `:cases t`.
     - Tun's own `src/` and `modules/` come back clean.
  6. **Tun's own code.** The forms the inventory lists are moved, and I traced each one; none changes behaviour:
     - NIL and unknown values reach `otherwise` exactly where the old `string=` fell to `t`.
     - `apply-price-mode` still refuses `manual_total` without `allow-manual`.
     - `error-title` compares with `eql` as `case` did.
  
     The only test changed outside the new ones is the test client turning on `:cases t`, which criterion 5 asks for.
  7. **A client's own closed types.** `tests/client/cases.lisp` matches the docs' examples character for character, and each branch is tested. `tier-discount-percent` now uses `ecase-of`.
  8. **Where people read it.**
     - The texts are all there: `spec/core.md` §2.7, test 11 in `spec/testing.md`, the docs, style and pitfalls.
     - The core version is 2.40.0 in both `flake.nix` and `module.lisp`.
     - The «Clients» record covers the client runs and the tun-erp rewrite, with tun-erp left unchanged.
  
  Both notes left from gate A are handled: criterion 1 now says what a type's message names, and `case-not-handled` is exported to `TUN`.
  
  **Code:** It is readable, has no leftover debugging or dead code, and keeps to the style rule's one stated exception. The guard is opt-in for clients.
  
  **Notes (not blocking)**
  - The example message in `spec/core.md` §2.7 (diff line 365) doesn't match the code:
    - It says `(module orders)`, but `field-set` in `src/core/cases.lisp:660` prints `(orders)`, which the test also expects.
    - Its sample place `modules/orders/package.lisp:83` is stale, since `status-label` moved to `orders.lisp`.
  
    Worth fixing in a follow-up so a reader searching for the message finds it.
  - `top-level-forms` in `tests/case-guard.lisp:1092` stops reading a file at its first reader error without saying so, so the guard can miss findings in the rest of that file. A finding that says reading stopped would be safer.
