# Calling other systems

Status: v1, 2026-10-21; §6 2026-10-30. How a client's code calls another
system's JSON API, such as asking TypeSafe's Jev to judge an item before it
is filed, with a key read from the environment, or runs a program on the
server, such as nixploy (§6); and how its tests answer for them.

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

## 6. Running a program

A client that drives a command-line tool, such as a dashboard that runs
`nixploy status --json` for each target it shows, runs it through a port
as it calls an API: declared, bounded, in the trace, and answered for in
tests.

```lisp
(define-application fleet ()
  (:programs "nixploy" "git")
  …)

(define-operation targets-status ((target :type (string :max 100) :required t))
    (:kind :read :policy :employee :title "Status of a target")
  (multiple-value-bind (output code)
      (run-program "nixploy" (list "status" "--target" target "--json")
                   :directory (project-checkout) :timeout 60)
    (jobj "exit" code "status" (parse-json output))))
```

- `(:programs NAME…)` in `define-application` declares the programs the
  application may run, each a file name looked up on the server's `PATH`.
  A server whose `PATH` lacks one is refused at start (exit 2), naming it.
  Calling an undeclared name is an error in the client's code, not a
  failure of the program.
- `(run-program NAME ARGUMENTS &key directory input environment
  (timeout 10) on-error-line)`, in the TUN package, runs NAME with
  ARGUMENTS, a list of strings passed as they are, with no shell between.
  DIRECTORY, an
  absolute path to a directory, is where it runs; without it, the
  server's working directory. INPUT, a text, is written to its standard
  input, which is then closed; without it, standard input is empty.
- It values the program's standard output as text, its exit code, and its
  standard error as text, both decoded as UTF-8 with an invalid byte
  replaced. A code other than 0 is an answer, not a failure: a program
  such as nixploy says what went wrong in its code and output, and the
  client decides what that means.
- `:on-error-line FUNCTION` reads a program's progress while it runs:
  FUNCTION is called with each line the program writes to its standard
  error, as soon as the line is complete, without its newline and decoded
  as UTF-8; a last line without a newline is passed when the program
  ends, and a line longer than 16 KiB is passed in pieces of 16 KiB. The
  lines are still in the standard error `run-program` values. FUNCTION
  runs in the thread that runs the program, between reads, and the
  program's time runs while it does. An error FUNCTION signals stops the
  program, as running past its time does, and is signalled from
  `run-program` as it is.
- The program's environment holds `PATH`, `HOME`, `TMPDIR`, `LANG` and
  `SSH_AUTH_SOCK` as the server has them, when it has them, and then
  ENVIRONMENT, an alist of names and values, both strings. Nothing else
  of the server's environment reaches it: not `DATABASE_URL` or any other
  secret of the deployment's SOPS file (`deploy.md` §3). A key the program
  needs is passed in ENVIRONMENT or INPUT, read from a setting declared
  with `:env` (§3), never in ARGUMENTS, which other users of the host can
  see while it runs and which the trace records (§6.1).
- It signals `program-failure`, an operation error with code
  `unavailable` like `remote-failure`, when the program cannot be started,
  when it runs past the time allowed, when it writes more than 8 MB to
  its standard output or its standard error, and when four programs of
  the tenant are running already. The message names the program and what
  happened, in English and translated in the catalogues: «nixploy did not
  finish within 60 seconds». `(program-failure-name C)` is the program,
  and `(program-failure-output C)` and `(program-failure-error-output C)`
  what it had written by then, or NIL.
- A program past its time is stopped with everything it started: it runs
  in a process group of its own, which is sent `SIGTERM` and, five
  seconds later, `SIGKILL`. A program that ends while its children go on
  holding its output open has ended; the children are stopped the same
  way.
- TIMEOUT is in seconds, from 1 to 3600. Inside an operation it is held
  to the operation's deadline less one second, as a call is (§1). A long
  program, such as a deploy, runs from a job with `:transaction nil`
  (`jobs.md` §4.2), whose own `:timeout` must allow it.

### 6.1 In the trace and in tests

- Each run is a step of kind `external` in the request's trace. Its
  name is the program and its arguments joined by spaces, clipped to 300
  characters, such as `nixploy status --target production --json`. Its
  detail is `exit 0`, or what came instead of an exit, and it has the
  run's duration. Input, environment and output are not recorded.
- `*program-handler*`, in the TUN package, is NIL or a function
  `(NAME ARGUMENTS DIRECTORY INPUT ENVIRONMENT)` that answers in place of
  the program, with its output, its exit code and its error output as
  three values; an exit code of NIL is a program that could not be
  started. `run-program` checks its arguments, records the step and
  signals as it does for a real program, and calls `:on-error-line` with
  each line of the handler's error output before it returns. A test binds
  it as it binds `*http-json-handler*` (§4).

```lisp
(let ((*program-handler* (lambda (name arguments directory input environment)
                           (declare (ignore name directory input environment))
                           (values (to-json-string (jobj "target" (third arguments))) 0 ""))))
  (invoke 'targets-status :target "production"))
```
