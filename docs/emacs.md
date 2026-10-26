# Working on Tun from Emacs

Tun is developed the Lisp way: Emacs talks to a running SBCL image, so a
function can be compiled, tried and inspected the moment it is written.

The normal setup is a local checkout: Emacs, the code and the image on one
machine. Agents work on the dev server in their own checkout, and the two
meet through git. Editing the server's checkout from a laptop over TRAMP is a
fallback for when the laptop cannot run the image, described at the end.

```
laptop                                   dev server (devbox)
──────                                   ───────────────────────
~/coding/tun   your checkout             ~/coding/tun   the agents' checkout
Emacs + SLY, and the SBCL it starts      agents: branches or worktrees,
in the dev shell (.envrc)                their own bin/repl ports, the gates
        └────────── git push / pull through GitHub ──────────┘
```

Separate checkouts keep each side's work apart. An agent's `bin/test` never
runs on a file you are halfway through, and your editor never shows an
agent's unfinished change. Push before handing work to an agent, and pull
its branch to review it.

## Set up the laptop

1. Install Nix with flakes. On Arch (Omarchy): `pacman -S nix`, then
   `systemctl enable --now nix-daemon.service`, add yourself to the
   `nix-users` group, and put `experimental-features = nix-command flakes`
   in `/etc/nix/nix.conf`. Elsewhere, use the installer from nixos.org.
2. Install direnv and nix-direnv: `pacman -S direnv`, then
   `nix profile install nixpkgs#nix-direnv` and the line
   `source $HOME/.nix-profile/share/nix-direnv/direnvrc` in
   `~/.config/direnv/direnvrc`. For the shell in terminals too, add
   `direnv hook fish | source` to the fish configuration.
3. Clone: `git clone git@github.com:JonasThowsen/tun.git ~/coding/tun`.
4. Allow the checkout's `.envrc` and check the dev shell:
   `cd ~/coding/tun && direnv allow && nix develop . -c bin/build`.
   The first run downloads SBCL and the libraries. `flake.lock` pins them,
   so they are the versions the server and the agents use.

Emacs needs SLY from MELPA and the `envrc` package. Nothing in the editor
configuration is particular to Tun: what Tun needs is in the checkout, in
`.envrc` and `.dir-locals.el`.

## Start the image

Open a file in the checkout and press `SPC m '` (`M-x sly`). The `envrc`
package gives each buffer in the checkout the environment direnv makes from
`.envrc`, the flake's dev shell, so `sly` starts the dev shell's SBCL with
the pinned libraries. The shell also tells ASDF where the checkout's systems
are. None of this is particular to Tun: any project with a flake and an
`.envrc` that says `use flake` works the same way.

Then load the code in the REPL:

```lisp
(asdf:load-system "tun/tests")
```

`tun/tests` is the kernel, every module and their tests; `"test-client"`
loads a client. Compiled files go to ASDF's cache in `~/.cache/common-lisp/`,
apart from `bin/build`'s `.build/fasl/`, so the strict build still sees
every warning. When a file fails to load, the debugger shows why; fix it and
load again.

After `flake.nix` or `flake.lock` changes, the first start takes a few
seconds while direnv builds the shell again; nix-direnv caches it. If Emacs
says the `.envrc` is blocked, run `M-x envrc-allow` once.

`M-x sly-restart-inferior-lisp` starts the image afresh, and
`M-x sly-quit-lisp` stops it.

### From a terminal: bin/repl

`nix develop . -c bin/repl` starts an image outside Emacs. It loads
`tun/tests` itself (`bin/repl test-client` for a client) and serves Slynk on
`127.0.0.1:4010` (`--port N` to move it). Connect with `M-x sly-connect`
(`SPC m C`) to `localhost` and the port; SLY offers the last ones you used.
Agents use it, and so does the fallback below. The contract is in
`../spec/tooling.md`. In short:

- Slynk listens on 127.0.0.1 only. It has no password and gives full access
  to the process, so never open the port in a firewall.
- Compiled files go to `.build/repl-debug-fasl/`, apart from `bin/build`'s,
  and with `(debug 3)`, so the debugger shows every local and can restart
  a frame.
- A file that fails to load is reported and the image stays up. Fix it and
  evaluate `(asdf:load-system "tun/tests")` again.

## Indentation

`bin/indent` is the authority. In a Tun buffer Emacs should indent the same
way: Emacs's own `common-lisp-indent-function` with the hints in
`scripts/indent.el`. SLY's indenter lines up some keyword arguments
differently, so the checkout's `.dir-locals.el` loads the hints and switches
the indenter in its Lisp buffers. It does that with an `eval` form, so the
first time Emacs asks whether to run it; answer `!` to remember the answer.
A new defining macro gets its hint in `scripts/indent.el`, where both read it.

## The loop

1. Change a definition and compile just that form: `C-c C-c` (`SPC m c`).
2. Try it in the REPL (`SPC m z`), or run its tests:
   `(fiveam:run! 'tun.tests::json-round-trip)`, a whole suite by its name,
   or everything with `(tun.tests:run-core-tests)`.
3. Jump to a definition with `M-.` (`SPC m gd`) and back with `M-,`. This
   works into SBCL and the libraries too, a good way to read real Lisp.
   `SPC m m` expands a macro form, the quickest way to see what
   `define-entity` or `define-operation` turns into.
4. When it works, run the gates: `nix develop . -c bin/build` and
   `nix develop . -c bin/test`. The REPL is where you learn and try things;
   the build and the tests, in fresh processes, decide.
5. Restart the image now and then (`M-x sly-restart-inferior-lisp`).
   After many live redefinitions it no longer matches the files, and the
   files are the truth.

## Agents

Agents on the dev server follow `../AGENTS.md`: their own branch or worktree,
and their own image, never the one an editor is connected to. An agent
starts it with `lisp start` and works in it with `lisp`, a command
for what SLY does in Emacs: evaluate, wait in the debugger at an error,
look into frames, compile one form, restart a frame. `lisp.md` shows how.

## Fallback: edit the server's checkout over TRAMP

When the laptop cannot run the image, Emacs can work on the server's checkout
instead. Files open over TRAMP, `/ssh:devbox:~/coding/tun/...`, and the
server's `bin/repl` reaches the laptop through an SSH tunnel. You then share
a working tree with the agents there, so agree who edits what.

`~/.ssh/config` on the laptop. The tunnel has its own host alias, so an
ordinary SSH session does not take port 4010 from a local `bin/repl`:

```
Host devbox devbox-repl
  HostName <the server's address>
  User you

Host devbox
  ControlMaster auto
  ControlPath ~/.ssh/cm-%C
  ControlPersist 10m

Host devbox-repl
  LocalForward 4010 127.0.0.1:4010
  ControlPath none
```

Then:

```sh
ssh devbox 'tmux new -d -s tun-repl "cd ~/coding/tun && nix develop . -c bin/repl"'
ssh -N devbox-repl        # the tunnel, while you work
```

and `SPC m C` in Emacs, to `localhost` and 4010. The editor configuration
needs a few more settings for an image on another machine:

- **File names.** The image reports `/home/you/coding/tun/...`. The
  `sly-tramp` contrib turns those into `/ssh:devbox:...` names, the ones
  you type, so `M-.` and compile file reuse the buffers you have open. Apply
  it only to an image whose `(machine-instance)` is one of your SSH hosts,
  so a local image is unaffected.
- **Indentation.** `enable-remote-dir-locals` lets the server checkout's
  `.dir-locals.el` apply over TRAMP too.
- **Searching.** `consult-fd` and `consult-ripgrep` start a remote process
  per search. `tramp-direct-async-process` for SSH hosts runs them over
  plain SSH. That made a search about 2.5 times faster in a test over
  `ssh localhost`. Over a real network the default mode makes more round
  trips, so the gain should be bigger.
- **The login shell.** TRAMP logs in with `TERM=dumb` and waits for a prompt
  ending in `$ `, `# ` or `> `. Make the shell's prompt print `$ ` then.

The Lisp runs on the server, so paths given to it are server paths. `SPC m k`
compiles the file as saved on the server. `SPC m c` sends the form's text
and works on unsaved edits. `SPC m '` would start an SBCL on the laptop
instead; use `SPC m C`.

## The tenant REPL is different

`bin/serve --debug-tools --repl-port N` starts Swank, SLIME's server, inside a
running tenant (`spec/core.md` §8.3), for diagnosing a live server. SLY cannot
connect to Swank. For everyday work use `bin/repl`.
