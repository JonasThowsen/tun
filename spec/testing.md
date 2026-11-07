# Generated tests

Status: draft, 2026-11-07. A client gets tests it did not write: Tun
derives them from what the client declares (its entities, operations,
policies, pages and scenarios), so every client is checked the same way,
and a check added to Tun reaches every client with `tun update`.

## 1. The generated suite

- A client's `tests/tests.lisp` holds one form,
  `(define-generated-tests "NAME" :package "PACKAGE")`, from
  `tun.test-support`, in the client's suite. NAME is the client's system;
  PACKAGE its package. The application class is the value of
  `*APPLICATION-CLASS*` in PACKAGE.
- It defines the generated tests in the suite. Today they are:
  1. the client's package uses only `CL` and `TUN`;
  2. its sources use only Tun's public interface;
  3. its application opens on a fresh Postgres database, which runs every
     record policy and query (`store.md` §5, §6), with the modules it
     enables and no others;
  4. every text of its own has a translation into each language it offers
     besides its source language, and no entry of its catalogues is unused
     (`i18n.md` §3.7);
  5. every scenario the client defines makes its records, each on a
     fresh database (`preview.md` §3). The client's scenarios are those
     defined in its packages: PACKAGE and the package the form is in, its
     tests' package, where `tun new` puts them. Tun's and other systems'
     scenarios loaded in the same image are not the client's, and two
     packages may each define a scenario of the same name.
- Each generated test is named for what it checks, prefixed
  `generated-`, so a failure says which check found it.
- **Isolation.** A scenario may install handlers that answer for other
  systems for every thread, such as `*program-handler*` or
  `*http-json-handler*` (`outbound.md`). Around each generated test, and
  around each scenario the scenario test runs, Tun rebinds to NIL its own
  such variables, `*program-handler*` and `*http-json-handler*`, and those
  the client names:
  `(define-generated-tests "NAME" :package "PACKAGE" :isolate (VARIABLE...))`.
  What one scenario or test installs never reaches the next. A variable
  Tun adds of this kind joins the list in `tun.test-support`.
- **Fast.** A client's generated tests together take at most 30 seconds
  on the machine its suite runs on, so they run with every change.
- A client keeps its own tests beside the form, in the same suite or in
  other files. Removing or editing a generated test is not how a client
  skips one: a check that does not fit a client is fixed in Tun.
- `tun new` writes the form. A client made before writes it once in place
  of its copies of the checks.

## 2. Not yet

Fuzzing every tool, policy properties, sequences of operations and every
page for every role come in later loops, each a section here.
