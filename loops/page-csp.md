# A Content-Security-Policy on every page: scripts and styles only from Tun's own files

- loop: page-csp
- mode: hands-on
- stage: done
- base: d6989d8d3492621cd0db58347f9aa9b1319c148e
- verified: 41abfdad74797fd9bcddb597d6e6ae8e25b43a73
- shown: 41abfdad74797fd9bcddb597d6e6ae8e25b43a73

## Brief

Jonas, 2026-11-06, after asking whether Datastar was worth it over htmx and
why Tun keeps code out of the HTML: «we should just keep iterating on using
htmx and making that better. I think security in the age of AI, and using
smart macros that keep security in mind is going to be key in AI-written
Applications.» Told that pages send no Content-Security-Policy (only
served files have one) and that it is the browser's backstop for the rule,
he answered: «Yes, do it.»

## Criteria

1. Every answer from the web dispatcher (a page, an htmx part, a redirect,
   a 401/403/404 page, the login page, `/ui`) carries exactly the policy of
   `spec/ui.md` §4, with `form-action 'self'` followed by the origin of
   each identity provider's authorization endpoint, once each.
2. `GET /files/ID` keeps the file's own policy, not the page's.
3. In Chromium, a tour of the showcase signed in (each page in the menu,
   `/ui`, the board, files with a chosen image's preview, the price chart,
   the login page) records no `securitypolicyviolation` event, and every
   existing showcase check still passes.
4. In Chromium, a script element written into a page with inline code does
   not run, and `eval` throws: the browser refuses both and reports a
   violation.
5. In Chromium, signing in on a server with `(:workos ...)` whose AuthKit
   is on another origin (the fake of `scripts/fake-workos.py`) ends signed
   in on the page asked for: the policy lets the sign-in redirect through.

## Decisions

- The policy is fixed, not per client: a client that needs another site's
  images or scripts is a request for a new loop, which would add an
  explicit, named option. No client uses an image from another site today.
- `blob:` for images: the file field previews a chosen image before it is
  sent (`URL.createObjectURL`). No `data:`: nothing uses it.
- Setting `element.style` from a script, as the board, the combobox and
  the chart do, is not inline style and is allowed by any policy.
- Style attributes: the tour found the showcase's `/mail` breaking the
  policy. It shows a rendered email in an `<iframe srcdoc>`, which inherits
  the page's policy, and an email's styles are all `style` attributes.
  Asked, Jonas chose «Allow style attributes» over a sandboxed document of
  its own or an unstyled preview: `style-src-attr 'unsafe-inline'`. A
  style attribute runs nothing, images stay on the server, and the HTML
  builder still refuses `style` in a client's output.
- `frame-ancestors 'none'` also stops another site from framing a page to
  trick a click (clickjacking); nothing frames Tun's pages.
- No reporting endpoint: it would be an anonymous write into the log. The
  checks catch violations before a deploy; a later loop can add one.
- The header is set for everything the web dispatcher answers, so a
  redirect or an error page is covered without each handler remembering.
- Core 2.8.0: a client whose page showed another site's image would stop
  showing it.
- Runs in its own worktree, as other sessions work in the main checkout.
- After ship, ferdig, kurs and nixploy-dashboard are updated to it, as
  with login-return.

## Log

- 2026-11-06 21:13  started, hands-on
- 2026-11-06 21:14  gate A asked of the person
- 2026-11-06 21:18  gate A: approve (jonas): «Approve»
- 2026-11-06 21:44  verify 1: failed check
- 2026-11-06 21:59  verify 2: passed build, test, check
- 2026-11-06 21:59  shown (/mail, /items)
- 2026-11-06 21:59  gate B asked of the person
- 2026-11-06 22:14  clients updated and tested on bc4ea87: ferdig 60e0ad0 and nixploy-dashboard 9facc52 pushed; kurs held: its «Connect Saxo» form redirects to Saxo's sign-in, which form-action would block. Jonas chose «Client declares the sites»: loop form-sites. Not deployed here; form-sites deploys all three
- 2026-11-06 22:15  gate B: approve (jonas): «Approve and push»
- 2026-11-06 22:15  finished at tun 7930c27
