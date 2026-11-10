# customers_update in the customers module

- loop: customers-update
- mode: reviewed
- stage: ship
- base: d1a4019d2973344859b8ed013164a55c08e67845
- item: sak_k0jjnrp8b5mphf8t
- estimate: 45m 1h30m 3h
- like: tun/http-json-get tun/mcp-error-codes tun/card-link-fields
- tags: kind:module module:customers
- verified: b262b7a255d7a9a58c9d47729a63aa1f41f044ce
- shown: b262b7a255d7a9a58c9d47729a63aa1f41f044ce

## Brief

Asked by the factory's orchestrator for Tun ERP, the factory's first
product, whose CRM is built on Tun's `customers` module (Tun ERP's Ferdig
item sak_etn5sp378qjebynp; this loop's item sak_k0jjnrp8b5mphf8t). Jonas
authorized changes to Tun for this work on 2026-11-10.

The orchestrator's brief:

> Tun ERP builds its CRM on Tun's `customers` module, whose README says
> there is no `customers_update`. Add the operation to the module (who may
> call it, what it may change, what it must not: erased customers, consent
> rules, uniqueness, audit as the module's other operations do), with
> spec/README, tests and the Norwegian catalogue, so a client or another
> module can change a customer through the owning module's public
> operation. Keep the module's existing behaviour for every client that
> pins it (ferdig-style additive change; check what the test client and
> showcase expect). […] touch only the customers module and what its
> change strictly needs.

Its origin, `~/coding/tun-erp/factory/brief.md` §9: customers is «use,
generalise in Tun: add `customers_update` | general already (consent,
erasure with a seam, unsubscribe); «There is no `customers_update`» (its
README §2). The ERP's fields (kind, registration number, address,
language) are an extension in module crm».

The `tun-customers-update` entry of `~/coding/tun-erp/factory/plan.json`:

> «In Tun's repository (outside this one: only after Jonas's yes, product
> choice 2). Tun's customers module has no update tool; every business
> needs one. Adds customers_update with revision, the module's rules and
> audit, and its screen form. Nothing ERP-specific goes into Tun. Then
> `tun update` here.»

Its criteria:

> 1. customers_update {id, revision, fields} changes name, email, phone
>    and notes and bumps the revision; a stale revision is conflict
> 2. a client's own fields on customer (extend-entity) are updatable
>    through it and its rules run on update
> 3. an erased customer is refused with invalid_input
> 4. the /customers record page has an edit form that calls it, in
>    English and Norwegian
> 5. Tun's bin/test and bin/check are green, and erp's bin/test is green
>    after `tun update`

## Criteria

1. `customers_update {"id","revision","fields"}` by an employee changes
   the `name`, `email`, `phone` and `notes` named in `fields`, leaves every
   other field as it was, and returns the customer with its revision one
   higher.
2. A `revision` other than the customer's current one is refused with
   `conflict`, and nothing changes.
3. A field sent as `null` in `fields` clears it when the field is
   optional (`phone`, `notes`); `name` or `email` sent as null or blank
   is `invalid_input` at `fields.name` / `fields.email`, and the field
   rules of `customers_create` (lengths, the email's form, `name`
   trimmed, `phone` untrimmed) hold for the same values in an update.
4. `fields` naming `marketing_consent`, a field the module computes or
   keeps (`id`, `revision`, `completed_orders`, `consent_source`,
   `consent_at`, `erased`, `erased_at`, `created_at`) or an unknown name
   is `invalid_input`, and so is an empty `fields`; consent changes only
   through `customers_set_consent`.
5. An erased customer is refused with `invalid_input` («kunden er
   slettet» in Norwegian), whatever the revision.
6. A viewer is refused with `forbidden`; the call is audited like the
   module's other mutations, with the names (not the values) of the
   changed fields as the entry's reason, in the order of the customer's
   fields (`name, email, phone, notes`, then a client's fields, whatever
   the order in `fields`), and takes `request_key`.
7. In the test client, a client field added with `extend-entity`
   (`kind`, `org_number`) is updatable through `fields`, the tool's
   input schema lists it under `fields`, and the client's rule
   (`business_customers_need_org_number`) refuses an update that breaks
   it.
8. A client or another module calls it from Lisp: `customers-update`
   is exported from `tun.customers` and published to `TUN`, with
   `customer-revision`, as `customers-set-consent` is; the test client
   has an operation of its own that changes its customers' `kind` and
   `org_number` through `(invoke 'customers-update …)`, a test calls it,
   and the test client passes the build gate's interface check.
9. Every existing tool, field, screen and result of the module is as
   before, so a client pinning the module sees only a new tool; the
   README states the tool and its rules, and its copy is in the
   Norwegian catalogue.
10. `bin/build` is warning-free and `bin/test` (with the generated and
   fuzzed sequences over the new tool) and `bin/check` are green.

## Decisions

- **The shape is the plan's: `{id, revision, fields}`.** The changes go in
  one object, `fields`, rather than flat beside `id`, because a client's
  fields on customer are added after the module is compiled: an object
  validated when the call is made takes them, which flat parameters
  declared in the module cannot. The object has its own field type in the
  module (`customer-changes`, as messaging defines `provider-mode-type`),
  whose schema lists every changeable field at the time of the call, so
  an agent sees the client's fields too, and whose errors name
  `fields.<name>`. No kernel change.
- **`revision` is required.** An edit starts from a read; the CRM is
  edited by several people, and a lost update is the failure this guards
  against (core.md §2.1). products_update takes it optionally for older
  callers; a new tool has none.
- **What may change:** the customer's input fields (`name`, `email`,
  `phone`, `notes`, and a client's own) except `marketing_consent`, which
  has a source and a time and changes only through `customers_set_consent`
  (README §4). What the module keeps (`completed_orders`, consent source
  and time, erasure, revision, created) is not input and so not in
  `fields`.
- **Policy `employee`,** as every mutation of the module but erasure
  (README «Contract»); no confirmation, as `customers_set_consent` has
  none and an update is reversible by another update.
- **Rules run through `save`,** as for every write of the entity: the
  module's field rules and every client rule (core.md §1.1). The values
  are checked by the field's own type, so an update accepts exactly what
  `customers_create` accepts for that field.
- **Uniqueness:** the customer has no unique field (email is not unique
  in `customers_create`, and an extension cannot declare one), so the
  update adds no uniqueness rule; the store's own conflict on a unique
  column would apply as it does for insert.
- **Erased:** refused with `invalid_input` and the text set_consent
  already uses («the customer is erased»), before the revision is
  compared, so an erased customer's anonymised data cannot be overwritten
  with anything.
- **Audit:** the kernel's entry for a mutation, with the changed fields'
  names as its reason (as set_consent gives the source), never their
  values, since audit entries outlive an erasure.
- **From Lisp** a caller passes `fields` as a JSON object, `(jobj "name"
  …)`, through `invoke`, as every operation takes its input; the module
  publishes `customer-revision` too, since an update needs the revision
  and a client could not read it before.
- **The audit reason lists the fields in the customer's order** (its
  fields as defined, then a client's), so it reads the same whatever
  order the caller sent them in.
- **An empty `fields` is refused,** because every accepted update raises
  the revision (core.md §2.1) and an update of nothing is a mistake.
- **Plan criterion 4, the edit form on the /customers record page, is
  not in this loop.** `/customers` has no record page: the resource has a
  list screen and a create form only, and the generated resource pages
  have no edit form for any entity (`src/web/ui.lisp`). Giving it one
  means a kernel change (an update tool and an edit form on a resource's
  detail page), a core version raise while two other kernel loops are
  raising it, and a detail screen for customers would also move the home
  page of every client whose first resource with detail pages becomes
  `/customers`, which breaks «keep the module's behaviour for every
  client that pins it». The orchestrator's brief for this loop asks for
  the operation; the form is a follow-up loop (a kernel loop: «an update
  form on a resource's record page»), and Tun ERP's own crm module can
  render its form on the tool meanwhile.
- **Plan criterion 5's «erp's bin/test after `tun update`»** is Tun ERP's
  step after this loop is pushed; this loop ends at the Tun commit.
- **No version raise.** The kernel is unchanged, so `+core-version+`
  stays; modules are pinned by git revision, and their `.asd` version is
  not a contract (no module has raised it). The core range stays
  `>= 2.0.0, < 3.0`: the module uses nothing newer than 2.0.
- **No spec change outside the module.** The module's contract is its
  README; core.md's rules for revisions, errors and audit already cover
  the tool.
- **Shown in the tests, not in a preview.** The change has no screen, and
  the showcase does not enable customers; `tun loop show` takes the
  showcase's `/ui` as earlier loops without a screen did
  (`http-json-get`, `mcp-error-codes`). Gate B's packet carries the diff
  and the tests.

## Log

- 2026-11-10 08:54  started, reviewed
- 2026-11-10 08:56  estimated 45m 1h30m 3h at brief, like tun/http-json-get tun/mcp-error-codes tun/card-link-fields
- 2026-11-10 08:56  gate A asked of a reviewer
- 2026-11-10 08:58  gate A: changes (reviewer)
  I'm asking for changes. The spec is close and most of it is sound, but it leaves out one thing the brief asks for directly.
  
  **What is right**
  - Criteria 1–7 cover the brief's list (who may call it, what it may change, erased customers, consent, uniqueness, audit), and a test can decide each one.
  - Refusing a stale revision with `conflict` (criterion 2) matches the pattern the other modules already use, such as `The product has changed (revision ~d, not ~d)` in `modules/catalog/catalog.lisp:214`. The README's «kunden er endret (revisjon N, ikke M)» follows the same form.
  - The erased check (refused before the revision is compared) and the consent rules fit the existing code. `customers_set_consent` already fails with "the customer is erased" (`customers.lisp:108`), and README §4 says consent changes only with a source.
  - Leaving plan criterion 4 (the edit form) out of this loop is justified, and I checked the reasons against the code. `/customers` registers no `:detail-screen` (`customers.lisp:85-87`), so it has no record page: `detail-page` is only reached for a resource that has one (`src/web/ui.lisp:1769`). And `home-path` (`ui.lisp:1655`) picks the first resource with detail pages, so adding one would move other clients' home page. The brief also says "touch only the customers module and what its change strictly needs". The decision is recorded, with the kernel follow-up named, so the orchestrator can see it. Deferring the "erp's bin/test" check is also fine.
  - No uniqueness rule is needed, since `customer` has no unique field. No version raise is needed either, since the kernel is unchanged.
  
  **Changes**
  1. **The brief asks for something no criterion covers.** It says the point is "so a client or another module can change a customer through the owning module's public operation." Criteria 1–9 only cover the MCP/API tool. Clients can only call what a module publishes to `TUN`, and other modules only what it exports. Right now `tun.customers` exports and publishes `customers-set-consent` (`customers.lisp:10`, `:160`) but has no criterion requiring the same for `customers-update`. Add a criterion that:
     - `customers-update` is exported from `tun.customers` and published, like `customers-set-consent`;
     - a test-client test calls it from client Lisp code and passes the build gate.
  
     In `modules/customers/README.md`, say how a Lisp caller passes `fields`, and add the operation to the **Publishes** line (README line 11).
  2. **The README and criterion 4 disagree on the refused fields.** Criterion 4 lists `id` among the names `fields` refuses, but README §2.1 (diff lines 43–45) leaves it out. Make the two lists the same.
  3. **Fix the order of the audit reason so a test can decide it.** Criterion 6 and README §2.1 give the reason as the changed fields' names ("such as `name, email`") but don't say in what order. Fix one order, for example the order of the customer's fields, in both places.
- 2026-11-10 08:59  gate A asked of a reviewer
- 2026-11-10 09:00  gate A: approve (reviewer)
  I approved this one. All three changes I asked for at the first gate A review have been made, and the README now says the same thing as the criteria.
  
  **The three earlier changes**
  1. **Calling it from Lisp.** Criterion 8 now requires `customers-update` to be exported from `tun.customers` and published to `TUN`, along with `customer-revision`, the same way `customers-set-consent` is. Today neither is exported or published (`customers.lisp:8-13`, `:91-92`, `:160`), so a test can decide this. The criterion also asks for a test-client operation of its own that calls it through `invoke`, plus a test and the interface check. The README now names the operation and `customer-revision` on its **Publishes** line (line 11) and shows a Lisp call (lines 95-98). That call works for a client: `invoke` and `jobj` are both public in `src/public.lisp:93` and `:109`.
  2. **The list of refused fields.** Criterion 4 and README §2.1 (lines 84-86) now give the same list, including `id`.
  3. **The order in the audit reason.** It is now fixed in both places: `name, email, phone, notes`, then the client's fields in the order the client added them, whatever order `fields` came in (criterion 6, README lines 91-94). A test can check that exactly.
  
  **Brief and criteria**
  - The criteria cover everything the brief lists: who may call it, what it may change and what it must not (erased customers, consent, uniqueness, audit), the README, tests, the Norwegian catalogue, and keeping every existing tool, field and screen as before.
  - Criterion 7 names fields that really exist in the test client: `kind`, `org_number` and the rule `business_customers_need_org_number` (`tests/client/customers.lisp:7-21`). So that criterion can be tested as written.
  - I accept the decisions as recorded, as I did at the first review. Leaving the edit form out is justified: `/customers` has no record page, and adding one would move other clients' home page. The ERP's own `bin/test` is a step for after this loop. No version raise is needed. None of these needs the asker.
  - The **Owns** and **Publishes** lines also now list operations the module already had (`customers_set_consent`, `customers_erase`), which the old README left out. That brings the README up to date with the code and doesn't change any behaviour.
  
  **For gate B, not blocking**
  - The conflict message is written capitalised in the README (`Kunden er endret (revisjon N, ikke M)`, line 73), but the module's other messages start lowercase (`kunden er slettet`). Whatever the catalogue ends up with should match what the README says.
  - The README also says `null` or blank for a client's required field is refused, which goes beyond criterion 3. The two are consistent, and the tests should cover it.
- 2026-11-10 09:11  verify 1: failed test
- 2026-11-10 09:19  verify 2: passed build, test, check
- 2026-11-10 09:20  shown (/ui)
- 2026-11-10 09:21  gate B asked of a reviewer
- 2026-11-10 09:23  gate B: approve (reviewer)
  I've read the diff, the kernel code it relies on, and the test client. Here's my verdict.
  
  **What is right**
  
  - **Criteria 1–3.** `tests/customers-tests.lisp` checks each one. Only the named fields change, and the revision goes 1→2→3. A stale revision, older or newer, is `conflict` and nothing is stored. `null` clears `phone` and `notes`. `null` or blank `name`/`email` is refused at `fields.name`/`fields.email`. The rules of `customers_create` still hold: `name` is trimmed, `phone` is stored untrimmed, and the lengths and email form are checked. Values go through each field's own `coerce-input`, so an update accepts exactly what create accepts.
  - **Criterion 4.** `marketing_consent`, each of the fields the module keeps, `id`, an unknown name, an empty `fields` and a `fields` that is not an object are all `invalid_input`, and the revision stays 1.
  - **Criterion 5.** An erased customer is refused at its current revision and at revision 1, with «kunden er slettet» in Norwegian. The check comes before the revision is compared (`customers.lisp:151`).
  - **Criterion 6.** A viewer gets `forbidden`, and the refusal is audited. A repeated `request_key` gives the same result without raising the revision again. The audit reason is `name, notes` with no values. The client test sends `org_number, kind, name` and checks for `name, kind, org_number`, so the order is the customer's.
  - **Criterion 7.** The input schema lists `kind` and `org_number` under `fields`, along with `kind`'s enum. The client's rule refuses a change to `kind` alone and refuses clearing `org_number`, and an update that satisfies the rule is accepted.
  - **Criterion 8.** `customers-update` is exported, and `customers-update` and `customer-revision` are published to `TUN`. The test client's `customers-make-business` calls the update through `invoke`, a test exercises it (including a viewer being refused), and `verify.txt` passed `check`.
  - **Criterion 9.** The change only adds things. The README states the tool, its rules and that `/customers` has no form for it. The new copy is in `nb.lisp`, and the conflict text there matches the README.
  - **Criterion 10.** `verify.txt` passed `build`, `test` and `check`. The fuzzer builds its inputs from each tool's schema (`tests/fuzz-inputs.lisp`), and `customer-changes` gives an object schema, so the new tool is fuzzed without extra code.
  - **Screenshots.** They show the showcase's `/ui` only. That fits the decision accepted at gate A: the change has no screen, and the edit form is a separate kernel follow-up.
  - **The code.** It is readable, its comments explain why, there is no leftover debugging, and it follows the kernel's own `input->entity` and `parse-operation-input` closely.
  
  **Not blocking, for a later tidy-up**
  
  - `customers.lisp:104-107` and `:78`: `change-path` cuts a long name at a literal `100`, and `+most-unknown-changes+` repeats the kernel's `+most-unknown-names+`. The kernel exports `shown-name` (`src/core/package.lisp:53`), which does the same cut and adds `…`. Using it would make a nested path read like a top-level one. Past 20 unknown names the module also drops the rest silently, where the kernel adds "has N more unknown fields". Nothing is wrong as a result, because the call is still refused.
  - `tests/client/tests/extension-tests.lisp`, the first assertion of `a-client-operation-changes-a-customer-through-customers-update`: `"12ab"` is refused by `org_number`'s pattern, not by the rule `business_customers_need_org_number`, so the assertion's message overstates what it shows. The rule itself is covered by the test above it.
