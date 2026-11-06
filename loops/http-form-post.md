# Post a form to another system and read its JSON answer (http-form-post)

- loop: http-form-post
- mode: reviewed
- stage: done
- base: 26b2bbf7082279b157253e111dd3e69e0e8c9e0e
- client: /home/jonas/coding/kurs
- client-base: 942638344c23102952d766576ab70811eb08384b
- verified: e5c9c747d5ac3db878f3d506570cb176afc22320 4e8f3c48d276dd8d18b25efc75e847e62eebff9a
- shown: e5c9c747d5ac3db878f3d506570cb176afc22320 4e8f3c48d276dd8d18b25efc75e847e62eebff9a

## Brief

Jonas, in this session (2026-11-06), on kurs, his stock-trading client:
«You can start the implementation, let me know when you need me to do
anything!» The next kurs slice connects Saxo's practice environment.

Saxo hands out its sign-in tokens from an OAuth token endpoint that takes
`application/x-www-form-urlencoded` and answers JSON, and so does any OAuth
2 authorization server. Tun's public calls send only JSON
(`http-json-post`) or nothing (`http-json-get`). `http-post`, which takes
any body, is Tun's own (spec/outbound.md §5). So a client cannot make this
call through its public interface.

## Criteria

1. `(http-form-post URL FORM &key headers (timeout 10))` sends a POST to
   URL with `Content-Type: application/x-www-form-urlencoded`, `Accept:
   application/json` and FORM as its body, then HEADERS, and values the
   answer's JSON and its status for a status from 200 to 299.
2. FORM is an alist of names and values, both strings. Each is
   percent-encoded as UTF-8, and the pairs are joined with `&` in FORM's
   order: `a b` arrives as `a%20b`, `Bodø` as `Bod%C3%B8`, `&` and `=` in a
   value stay in that value. A name or a value that is not a string, or a
   FORM that is not an alist, is an error in the caller's code that names
   `http-form-post`. The error may say which name is at fault and never
   shows a value of FORM: an unset secret is the likely cause, and a fault's
   message is kept in «Feil», the log and the error mail.
3. A status outside 200 to 299, a body that is not JSON, no answer, no
   answer in time and a redirect are each a `remote-failure`, with the
   status, body and message `http-json-post` gives them, and an empty
   answer is `:null`.
4. The call is an `external` step in the trace named `POST` and the URL
   without its query or its user and password, with the status as its
   detail. Neither FORM nor HEADERS appears in the trace.
5. A `User-Agent` in HEADERS is the one the other system receives, once.
6. `*http-json-handler*` answers for a form too: it is called with the URL,
   FORM as a JSON object of its names and values, and the headers. What
   it is given for `http-json-post` and `http-json-get` does not change.
7. `http-form-post` is in the TUN package for clients, and
   spec/outbound.md and docs/client-api.md describe it.
8. A header that is not a pair of strings is an error in the caller's code,
   for all three calls, that shows no header's value, for the same reason:
   `Authorization` holds a key.

## Decisions

- **A function of its own beside the other two, not a public `http-post`.**
  `http-post` hands back any text, for a status of any kind, and never
  signals. A client wants what `http-json-post` gives: the JSON, or a
  `remote-failure`. Sharing `json-call` gives it the deadline, the limit of
  four calls, the trace and the failures unchanged.
- **The handler is given FORM as a JSON object.** A fake token endpoint
  then reads `(jget body "grant_type")`, as a fake reads a JSON body. A name
  given twice shows its last value there; the real request sends both.
- **Spaces go as `%20`, not `+`.** `url-encode` is what `query-string`
  already uses, and every form parser reads `%20`. A second encoder for one
  character would be a second thing to get right.
- **No Basic authentication helper.** RFC 6749 §2.3.1 lets a client send its
  credentials in the form, and Saxo says so too. A client that needs Basic
  writes the `Authorization` header in HEADERS.
- **`check-call` stops printing HEADERS.** It is older than this loop, but a
  form's call goes through it with the same exposure, and the fix is one
  line. A value in the message helps nobody: the caller's code is at fault,
  and the name of the bad header says where.
- **The query's check is the same check.** `check-query` printed the query,
  which spec §1.2's own example gives a key. FORM's check, `check-pairs`,
  takes its place, one function for headers, queries and forms.
- **An empty FORM is allowed**, an empty body, as an empty QUERY is.
- **`oidc.lisp`'s token exchange stays as it is.** It is Tun's own port, with
  a failure of its own (`provider-failure`), and nothing here changes it.

## Log

- 2026-11-06 18:52  started, reviewed
- 2026-11-06 18:52  gate A asked of a reviewer
- 2026-11-06 18:54  gate A: changes (reviewer): §1.3 must name http-form-post and the Status line §1.3 and §2; a caller error must not print FORM, which holds secrets, since faults keep messages in error_groups, the log and error mail; say a FORM that is not an alist is an error
- 2026-11-06 18:54  gate A asked of a reviewer
- 2026-11-06 18:55  gate A asked of a reviewer
- 2026-11-06 18:57  gate A: approve (reviewer): Criteria cover the brief, each is decidable, spec agrees; notes for build: check dotted tails, do not print entries, handler must get an object
- 2026-11-06 19:15  verify 1: passed build, test, check, client-check
- 2026-11-06 19:16  shown (/ui)
- 2026-11-06 19:16  gate B asked of a reviewer
- 2026-11-06 19:40  gate B: changes (reviewer): Code right; test that TUN exports http-form-post, and that a name is percent-encoded, not only a value
- 2026-11-06 19:55  verify 2: passed build, test, check, client-check
- 2026-11-06 19:56  shown (/ui)
- 2026-11-06 19:56  gate B asked of a reviewer
- 2026-11-06 19:59  gate B: changes (reviewer): pairs-problem takes a NIL entry for no bad entry (find-if-not), so a form or query gives a bare type error and a NIL header is accepted; use member-if-not and test all three
- 2026-11-06 20:15  verify 3: passed build, test, check, client-check
- 2026-11-06 20:15  shown (/ui)
- 2026-11-06 20:16  gate B asked of the person
- 2026-11-06 20:40  gate B: approve (jonas): «Yes, continue.»
- 2026-11-06 20:41  rebased: tun 0a0bec3 → 26b2bbf, kurs 9426383 → 9426383
- 2026-11-06 20:56  verify 4: passed build, test, check, client-check
- 2026-11-06 20:56  shown (/ui)
- 2026-11-06 20:56  gate B asked of a reviewer
- 2026-11-06 21:00  gate B: approve (reviewer): Fresh reviewer, as Jonas allowed («a fresh reviewer can make calls»): the NIL fix holds over 21 shapes, the rebase added nothing, criteria 1-8 met
- 2026-11-06 21:00  finished at tun c3cc49a, kurs 2172c92
