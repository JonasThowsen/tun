# A client names the sites its forms may lead to, such as Saxo's sign-in

- loop: form-sites
- mode: hands-on
- stage: done
- base: b543dd5c46c6aa1915c6d102acfb89acf9897170
- after: page-csp
- verified: 927e46dcfd65984699634693a35cf9f70b4fd4d6
- shown: 927e46dcfd65984699634693a35cf9f70b4fd4d6

## Brief

Found while updating the clients to page-csp (core 2.8.0), before any
deploy: kurs's «Koble til Saxo» is a form that posts to `/saxo/connect`,
which answers 303 to `https://sim.logonvalidation.net/authorize`. Chrome
holds that redirect to the page's `form-action`, which named only the
server and the sign-in providers, so the connection would have broken.
Asked how Tun should allow it, Jonas chose «Client declares the sites»
over dropping `form-action` or making the button a link.

## Criteria

1. `(:form-sites "https://sim.logonvalidation.net")` in
   `define-application` adds that origin to the page policy's
   `form-action`, after the sign-in providers, each origin once.
2. A form site that is not an `https://` origin with a lower-case host and
   no path (or `http://` on `127.0.0.1` or `localhost`) is refused when
   `define-application` is compiled, naming the application and the value.
3. A client without the option has the policy of page-csp unchanged.
4. kurs declares Saxo's sign-in site; in Chromium, «Koble til Saxo» in
   kurs's preview leads the browser to Saxo's authorize page (Playwright
   answers it), where under 2.8.0 alone it stopped.

## Decisions

- Origins only, checked at compile time: the value goes into a header, and
  a path or a `;` would change the policy's meaning.
- Literal strings, not `(:env ...)`: kurs keeps Saxo's address as a
  constant, and a site a form leads to belongs in the code, reviewed.
- Core 2.8.1. The page-csp clients are deployed from this loop's gate C:
  ferdig, kurs and nixploy-dashboard together.

## Log

- 2026-11-06 22:15  started, hands-on
- 2026-11-06 22:17  gate A asked of the person
- 2026-11-06 22:28  gate A: approve (jonas): «Approve»
- 2026-11-06 22:46  verify 1: passed build, test, check
- 2026-11-06 22:46  shown (/login)
- 2026-11-06 22:46  gate B asked of the person
- 2026-11-06 22:50  gate B: approve (jonas): «Approve and push»
- 2026-11-06 22:56  clients on f487a26, tested and checked: ferdig 2e49bf8 (750, 12 checks), kurs 424ff2a (296, with saxo-leaves-for-saxo), nixploy-dashboard c57b706 (1138, 12 checks)
- 2026-11-06 22:56  gate C asked of the person
- 2026-11-06 22:57  gate C: approve (jonas): «Deploy all»
- 2026-11-06 22:59  finished at tun f487a26
