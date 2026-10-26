# Working in a running image: lisp

A person works on Tun with Emacs connected to a running SBCL image
(`emacs.md`). `lisp` gives an agent the same thing as a command: an image
of the checkout to evaluate in, a debugger that waits at an error, frames
to look into and restart, one form compiled at a time, and the way to a
definition. It comes from
[slynk-cli](https://github.com/JonasThowsen/slynk-cli), which the dev
shell puts on PATH. Its guide, `docs/guide.md` there, shows the way of
working; read it first. The contract is its README, and Tun's part of it
the section "Agent REPL" of `../spec/tooling.md`.

Use it to learn and to try things. The gates are still `bin/build` and
`bin/test` in fresh processes: the files are the truth, not the image.

## In Tun

```sh
lisp start                  # tun/tests: the kernel, the modules, their tests
lisp start test-client      # the test client, or any client system
lisp eval '(tun.tests:run-core-tests)'
lisp eval --package tun.core '(find-class (quote entity))'
lisp definition tun.core:insert
lisp xref calls tun.core:insert
```

`.slynk-cli.sexp` at the root starts the image as `bin/build` loads the
checkout, through `scripts/setup.lisp`, and compiles it with `(debug 3)`
into `.slynk-cli/fasl/`, apart from `bin/build`'s `.build/fasl/`. The
image's records and the full output of each evaluation are in
`.slynk-cli/` too. One image per checkout or worktree.

To pause a test where it fails, let FiveAM call the debugger:
`lisp eval '(let ((fiveam:*on-error* :debug) (fiveam:*on-failure* :debug)) (fiveam:run! (quote tun.tests::json-round-trip)))'`.

An error in a request to a server started from the image does not pause:
only evaluations do.

Never connect to a port you did not start: a person's editor may be
connected to it.
