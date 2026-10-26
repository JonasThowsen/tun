# Fleet

Status: idea, 2026-10-20. Not planned for building: until the fleet is
larger, an agent reaches each tenant as its own MCP server in its
configuration. Written down so the parts that pay off later are not
forgotten.

One Tun system that knows every tenant a supplier runs, so an agent asked to
find out what is wrong with one of them starts in one place. Each tenant
already answers the questions an agent asks over MCP: `introspect_runtime`,
`introspect_recent`, `introspect_request`, `introspect_record`,
`introspect_workflows`, `introspect_schema`, and `eval` where it is
allowed. The fleet adds what a list of MCP servers cannot.

## 1. What it would add

- **A registry.** A tenant is a record: its name, its customer, its URL
  and a token. Deploy targets (nixploy) could register them, so a new
  tenant is in the fleet when it is deployed.
- **One entry point.** Its tools call a tenant's tools by the tenant's
  name, so "what is wrong at Nordvik" needs no other configuration.
- **The whole fleet at once.** It reads `/health` and `introspect_recent`
  from every tenant, so an agent or a page answers which tenants have new
  errors, failed mail or slow requests since yesterday. It is the first
  step of the roadmap's Operations rows without a log store.
- **Memory.** Each diagnosis is a record on the tenant: the symptom, the
  cause, the fix and the commit that made it. The next agent starts from
  what the last one learned.

## 2. What it must get right

- **It holds a credential to every tenant.** Each token reaches only the
  introspection tools, read-only. `eval` and live changes need a token of
  their own, short-lived, asked for each time, and are audited in both
  the fleet and the tenant.
- **A live fix ends in git.** A change made in a running image is lost at
  the next deploy and drifts from the repository (`bin/drift`). The fleet
  records a live fix as open until a commit to the client's repository
  carries it.
- **Introspection shows customers' data.** For a supplier's own customers
  that belongs in the data processing agreement with each; offered to
  others it is a product with the duties that come with one.

## 3. When

- With the general link between Tun systems (`docs/roadmap.md`,
  Connected systems): the fleet and feedback (`feedback.md`) are the two
  pairs of systems that draw it out.
- When the number of tenants makes a list of MCP servers hard to keep, or
  when errors in one tenant go unnoticed for want of a fleet-wide view.
- Offered to clients only if others come to run several Tun systems.
