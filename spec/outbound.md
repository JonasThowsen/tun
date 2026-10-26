# Calling other systems

Status: v1, 2026-10-21. How a client's code calls another system's JSON
API, such as asking TypeSafe's Jev to judge an item before it is filed,
with a key read from the environment; and how its tests answer for that
system.

## 1. A JSON POST

```lisp
(define-setting "typesafe.api_key"
    (:type "secret" :env "TYPESAFE_API_KEY"
     :description "Nøkkelen til TypeSafe. Uten den sjekkes ikke saker før de meldes."))

(define-operation items-check ((title :type (string :max 200) :required t :label "Tittel"))
    (:kind :read :entity item :policy :employee :title "Sjekk en sak")
  (let ((key (setting-value-at-use "typesafe.api_key")))
    (if (null key)
        (jobj "checked" nil)
        (handler-case
            (http-json-post "https://api.typesafe.ai/v1/systemone" (jobj "input" title)
                            :headers `(("Authorization" . ,(format nil "Bearer ~a" key))))
          (remote-failure () (jobj "checked" nil))))))
```

- `(http-json-post URL BODY &key headers (timeout 10))`, in the TUN
  package, posts BODY, a JSON value, as UTF-8 JSON to URL, an `http` or
  `https` URL. It sends `Content-Type` and `Accept` as
  `application/json`, then HEADERS, an alist of names and values, both
  strings.
- An answer with a status from 200 to 299 is the result: its body
  parsed as JSON, read as `jget` reads any JSON, or `:null` for an empty
  body. The status is the second value.
- It signals `remote-failure` when no answer comes within the time
  allowed, when the connection fails, when the status is outside 200 to
  299, and when such an answer's body is not JSON. HTTPS is verified
  against the system's certificates. A redirect is not followed; it is
  an answer outside 200 to 299.
- `remote-failure` is an operation error with code `unavailable`, so one
  the client does not handle fails the operation `unavailable` (status
  409 on `/api`, `api.md` §3). It is not a fault (`errors.md` §2), so it
  is not kept in «Feil». Its message names the host and what happened,
  never the body: «api.typesafe.ai svarte 503», «api.typesafe.ai svarte
  ikke innen 10 sekunder», «api.typesafe.ai kunne ikke nås».
- `(remote-failure-status C)` is the status, or NIL when no answer came.
  `(remote-failure-body C)` is the answer's body as JSON, else its text,
  or NIL. `(remote-failure-url C)` is the URL. A client tells a refusal
  (4xx) from the other system's own failure (5xx) by the status.
- TIMEOUT is in seconds, from 1 to 60. A call is also held to the
  operation's deadline (`core.md` §7.1) less one second,
  so the operation can still answer when the other system does not;
  with less than a second left it fails at once, with no answer.
- A tenant has at most four calls to other systems at once, shared with
  mail delivery. A call beyond them fails at once, with no answer.

### 1.1 Where to call it

A call can be made anywhere in an application. It is best in a `:read`
or a `:wait` operation. In a write, such as a mutating operation or a job
with the default `:transaction t`, the call holds the store's single
writer while it waits, so every other write waits for the other system
too. Work that must call out and then write calls from a job with
`:transaction nil` (`jobs.md` §4.2) and stores the outcome with `invoke`
of an operation, which runs in a write of its own, as `invoices_send`
does with the accounting port (`core.md` §7.3).

## 2. In the trace

- Each call is a step of kind `external` in the request's trace
  (`introspect_request`, `core.md` §8.1). Its name is the
  method and the URL without its query, which may hold a key, such as
  `POST https://api.typesafe.ai/v1/systemone`. Its detail is the status,
  or what came instead of an answer, and it has the call's duration.
- Headers and bodies are not recorded, as they may hold a key or a
  person's text.
- A `remote-failure` that ends the operation shows in its log line with
  code `unavailable` (`errors.md` §6).

## 3. Settings from the environment

- `(define-setting KEY (:type TYPE :env "NAME" …))` declares a setting
  whose value is the environment variable NAME, read each time it is
  used. TYPE is `string`, `secret`, `url` or `email`. When the variable
  is unset or empty, the value is the declared default, or NIL without
  one.
- A value that does not fit TYPE, as `settings_set` checks it, is an
  error when it is read, naming the variable and not its value.
- The value is never stored. `settings_set` refuses such a setting with
  `invalid_input`. A secret read from the environment gets no random
  value at start.
- In `settings_list`, such a setting has `"env":"NAME"`. A secret's value
  is `"***"` when the variable is set and `null` when not, so an
  administrator sees whether it is there. The settings page shows the
  variable instead of a form.
- A server starts without the variable. What its absence means is the
  client's to decide, such as checking nothing before an item is filed.
- The variable belongs in the deployment's SOPS file (`deploy.md` §3),
  with the database URL. Every name in that file reaches the server.

## 4. Testing

- `*http-json-handler*`, in the TUN package, is NIL or a function
  `(URL BODY HEADERS)` that answers in place of the network. It is
  called with the body as the other system would receive it, parsed
  again from the text that would be sent. It returns the status and the
  answer, a JSON value or a text, as two values; a status of NIL is no
  answer at all. `http-json-post` treats the answer as it treats a real
  one (§1), and records the step (§2).
- A test binds it with `let` around calls made in its own thread. A call
  that runs in a server's thread sees its global value, so a test over
  HTTP sets that and restores it.

```lisp
(let ((*http-json-handler* (lambda (url body headers)
                             (declare (ignore url headers))
                             (values 200 (jobj "kind" "feil" "echo" (jget body "input"))))))
  (invoke 'items-check :title "Knappen virker ikke"))
```

## 5. Tun's own calls with other bodies

A port of Tun's that posts a body that is not JSON, such as a push
notification (`push.md` §5), makes the same call through
`tun.outbound:http-post`, which is internal to Tun: URL, the body's
octets, its content type and headers, and a timeout. It answers the
status and the answer's text for any status, and NIL and what came
instead when no answer did: a port decides for itself what a status
means. It has §1's limits (HTTPS verified, no redirect, the operation's
deadline, four calls at once) and is a step in the trace as §2 says,
with the name the port gives it.
