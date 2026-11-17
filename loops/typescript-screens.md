# A single-page screen in Svelte, built by Nix in a client's build, with Tun's design tokens

- loop: typescript-screens
- mode: reviewed
- stage: ship
- base: bf706a67de0668287beee84cedf45bd698d5fa22
- after: typescript-client
- item: sak_b2dgtad9737941ws
- estimate: 3h 5h 10h
- like: tun/typescript-client tun/pdf
- tags: kind:feature core
- verified: 339acea045730bacf0ba216a323c50442df12fa6
- shown: 339acea045730bacf0ba216a323c50442df12fa6

## Brief

Ferdig sak_b2dgtad9737941ws, the orchestrator's brief of 2026-11-17: the
second half of `typescript-client` (that loop's «Two loops» and
`spec/typescript.md` §6 «Not yet»), on the owner's request of
2026-11-14 that loop quotes («There are definitely cases where a SPA
frontend is the best alternative, and that opens up the typescript
world …») and his decision of 2026-11-16 that the first such screen is
real, a client's screen for answering what waits for a person.

> 1. **A screen in Svelte, built by Nix.** A client's screen folder
>    (source, `package.json`, a lock file) is built inside the client's
>    `nix build` with no network: npm dependencies fetched by a
>    fixed-output derivation pinned by hash (the usual nixpkgs way for a
>    locked npm project; pick the one that fits Tun's flake and say why),
>    Svelte and a bundler, output into the folder `define-single-page`
>    serves. The client's `bin/test` type-checks the screen
>    (`svelte-check` or `tsc` as fits) and fails on a type error; the test
>    that renames a parameter and sees the screen's check fail is kept,
>    now against a Svelte component. A client without a screen pays
>    nothing: no Node in its shell or closure, no new step, proved by a
>    test or a closure check on a client with no screen.
> 2. **Design tokens.** A CSS file of custom properties (colours,
>    spacing, type, radii; light and dark as the pages have them)
>    generated from the same source the UI library's pages use, served to
>    screens, with a test that fails when the two drift.
> 3. **The showcase's screen in Svelte**, its built files no longer
>    committed, built by the showcase's Nix build; its browser check at
>    390 and 1280 px passes as before, in light and dark. The screen's
>    words follow the showcase's languages if the showcase is bilingual
>    (gate B noted they were English only).
> 4. **Docs**: `docs/client-api.md` «A single-page screen» updated start
>    to finish for Svelte and the Nix build (the exact files and commands
>    a client adds), `reference/pitfalls.md`, `spec/typescript.md` §6
>    closed.

The next screen built on this is a client's queue screen (a person
answers the top question of a queue with one tap, or sends it to the
back, and the next comes up; on a phone first): the case to serve, with
nothing built for it here. The content security policy of a single-page
page stays exactly as `typescript-client` made it; Svelte's output must
run under it. Every client of the installation passes unchanged. No
request leaves the machine in tests, previews or checks, except Nix's
own fixed-output fetch at build time. Mode reviewed, push to main
allowed, no deploy; core 2.49.0.

## Criteria

A screen built by Nix (`spec/typescript.md` §6):

1. **`buildScreen`.** `nix build .#showcase-screen` type-checks the
   showcase's screen (`npm run check`, `svelte-check
   --fail-on-warnings`) and builds it (`npm run build`, `vite build`) in
   Nix's sandbox, its npm packages from one fixed-output derivation
   pinned by `npmDepsHash`; its output is the built files,
   `index.html` and `assets/`, and refers to no store path. The same
   screen with a type error put in its code fails the build, with
   `svelte-check`'s message. (`scripts/test-screens.sh`, a job of
   `bin/test`)
2. **`buildClient`'s `screens`.** `nix build .#showcase`, the showcase's
   server built with `screens = { "screen/dist" = showcaseScreen; }`,
   has the screen's built `index.html` in its source in the store,
   where `define-single-page`'s `:files` looks, and neither Node nor npm
   in its closure; a screen's folder that is empty, absolute or holds
   `..` stops the evaluation with a message naming it. (test-screens)
3. **A client without a screen pays nothing.**
   `checks.x86_64-linux.client-without-screen`: the test client's server,
   built by `buildClient` without `screens`, has neither Node nor npm in
   its closure, and `clientShell { }` has no `node`, `npm`, `npx` or
   `tsc` among its programs. (test-screens; and the clients' runs,
   criterion 13)
4. **The type check, in Svelte.** `svelte-check` accepts the fixture's
   Svelte component (`tests/typescript/Screen.svelte`) against its
   module; after the fixture changes an operation the component calls (a
   parameter renamed; a value taken out of an enum; a key taken out of a
   declared output), the module written again makes `svelte-check` fail,
   naming `Screen.svelte`, and it accepts it again once each is undone.
   (test)
5. **The committed module, not the build.** `bin/tun typescript FOLDER
   --dir checks/showcase` writes byte for byte the committed
   `screen/src/api.ts`; no built file of the screen is in git (no
   `screen/dist/`, no `screen/public/`). (test)

Design tokens (`spec/ui.md` §3):

6. **`/assets/tokens.css`.** Signed out or in, `GET /assets/tokens.css`
   answers 200, `text/css; charset=utf-8`, `Cache-Control: no-cache`,
   `X-Content-Type-Options: nosniff`; the custom properties it declares,
   each with its selector, its media query and its value, are exactly
   those the pages' stylesheet declares on `:root` in any layer, both
   schemes' values among them (`--background` is `light-dark(#ffffff,
   #19191c)` in both). A token the stylesheet has that the file lacks,
   or a value that differs, fails the test. (test)

The screen (`spec/typescript.md` §4):

7. **Its language.** A screen's `index.html` is answered with its
   `<html lang>` the language of the person's pages, in place of the
   file's own: `en` on an English tenant, `nb` on a Norwegian one, the
   proof still right after `<head>`; an `<html>` without `lang` gets
   one. (test)
8. **In a browser, as before.** The showcase's Svelte screen, from the
   Nix build `bin/check` links, at 390 and 1280 px: loads under the
   page's policy with no violation reported; a tap calls a session-only
   operation through `/api` with the proof and shows its `ok` answer;
   a submission with the field left empty shows the `refused` answer's
   message at that field; a call Playwright aborts shows the `failed`
   `network` answer; never a page load, no sideways scroll; signed out,
   its address leads to the sign-in. (browser check)
9. **Svelte's output under the policy.** The built `index.html` has no
   inline `<script>` or `<style>`; the screen's icon, an SVG asset of
   its own, is served as a file under `/sign-off/assets/` and shows
   (Vite's `assetsInlineLimit: 0`, else a `data:` URL the policy
   refuses), and the component's styles come from a style sheet file
   (Svelte's `css: "external"`, else a `<style>` the policy refuses):
   criterion 8's «no violation» holds with both. (browser check)
10. **Light and dark.** At both widths, in the browser's light and dark
    schemes, the screen's ground and its button's fill are the pages'
    `--background` and `--primary` of that scheme (`#ffffff` and
    `#171717` light, `#19191c` and `#ededed` dark), from
    `/assets/tokens.css`; with `tun-theme` stored as `dark` in a light
    browser, the screen is dark. (browser check)
11. **Norwegian.** On the showcase's Norwegian tenant, the screen's
    `<html lang>` is `nb`, its heading, label, button, count and answer
    are Norwegian, and the refusal at the field is «må fylles ut».
    (browser check)

The rest:

12. **The docs.** `spec/typescript.md` (§4, §6 closed, §7),
    `spec/ui.md` §3, §8, §10, `docs/client-api.md` «A single-page
    screen» start to finish (the exact files and commands a client adds,
    what a client without a screen pays), `reference/pitfalls.md`. (by
    hand, gate B)
13. **Clients unchanged.** Core 2.49.0 in `+core-version+` and the
    flake; every client of the installation passes its `bin/test`
    unchanged on this tree, from scratch clones. (test for the version;
    the clients' runs logged)

## Decisions

### Nix builds the screen, in production and in the working tree

The screen has one build, `buildScreen`'s derivation, and everything
that serves it serves that build: `buildClient` copies it into the
server's source, and in the working tree `dist/` is a link to it (`nix
build .#screen-queue --out-link screens/queue/dist`), which the
preview, `tun check` and the client's `bin/test` serve. So no client's
dev shell gets Node, not even one with a screen, and what a check saw is
byte for byte what is deployed. The other way, Node and npm in the shell
of a client with a screen and `npm run build` in the working tree, would
build quicker while an agent iterates (a second rather than about ten)
and see files git does not track yet, but it is a second build that can
differ from the deployed one, and Node in the shell. Whether that trade
is right for the people and agents who build screens is the owner's to
say (question in the report); the safer reading, one build, is built.

### `fetchNpmDeps` with `npmDepsHash`, and the screen's own derivations

- **One fixed-output derivation, one hash.** nixpkgs has three ways for
  a locked npm project. `buildNpmPackage` is the common one, but it
  builds and installs an npm package; a screen's output is a folder of
  built files, and its `node_modules` are needed apart (by the suite's
  `svelte-check`, by an editor), so `buildScreen` uses what
  `buildNpmPackage` is made of: `fetchNpmDeps`, one fixed-output
  derivation of every package the lock names, checked against
  `npmDepsHash`, and `npmConfigHook`, which installs them offline. A
  lock file changed without a new hash fails the build and names the
  hash it needs. `importNpmLock` needs no hash (each package is its own
  fetch, pinned by the lock's `integrity`), but makes some fifty
  fixed-output derivations of a screen and reads the lock file while the
  flake is evaluated; the brief asks for one fetch pinned by a hash, and
  `fetchNpmDeps` is that.
- **`node_modules` its own derivation**, depending on `package.json` and
  the lock only, so a change to the screen's code installs nothing
  again, and Tun's dev shell has the showcase screen's packages
  (`TUN_SCREEN_NODE_MODULES`) for the suite's type check of the Svelte
  fixture, from the same derivation.
- **The two scripts.** The build runs the screen's `check` and `build`
  scripts with npm offline and its update check off (npm asks its
  registry for a newer npm otherwise), so the toolchain is the screen's
  `package.json`, not Tun's; Tun's model and docs are Svelte 5, Vite and
  `svelte-check`.
- **Versions**, exact in `package.json` and each at least two weeks old:
  Svelte 5.57.3, Vite 8.3.5, `@sveltejs/vite-plugin-svelte` 7.3.1,
  `svelte-check` 4.7.8, TypeScript 5.9.3 (Tun's `tsc` too; TypeScript 7
  is a native program that `svelte-check` 4.7 does not take). Vite 8's
  Rolldown and Lightning CSS are native Node addons from npm; they run
  under nixpkgs' Node in the sandbox as they are, as the build shows.

### The showcase built as a client, and the proof in `bin/test`

The showcase has no flake of its own; Tun's flake gives
`showcase-screen` and `showcase` (`buildClient` of `checks/showcase`
with its screen and its two modules), so `buildClient`'s `screens` is
exercised as a client's flake uses it. `scripts/test-screens.sh`, a job
of `bin/test`, builds the showcase's server and the
`client-without-screen` check and reads what criteria 1 to 3 ask from
the store, so every verify round decides them; it costs a `nix build`
whose parts are cached after the first. `bin/check` links the screen's
build before the browser checks, so they run the Nix build.

### Design tokens served, from the pages' own source

The tokens' source is `+tokens-css+` in `src/web/ui/kit.lisp`, which
the pages' stylesheet puts in its `tokens` layer. `/assets/tokens.css`
answers that same text, at an address without a hash (a built
`index.html` cannot know one) and `no-cache`. Served rather than
generated into a file the screen's build bundles, a screen always has
the tokens of the server it runs on: a client that moves to a newer Tun
gets its pages' and its screen's new tokens at once, without building
the screen again. The drift test does not compare a string with itself:
it parses every rule on `:root` in the pages' whole stylesheet (any
layer, any media query) and in the file into (media, selector, property,
value) and asks them equal, so a token a component adds on `:root`, a
file written by hand, or one served from elsewhere fails it.

### The screen's words and its theme

- The server writes the page's language into the screen's `<html lang>`
  as it puts the proof in its head: a screen has no other way to know
  the person's language (the tenant's, or the person's own choice), and
  `lang` is right for a screen reader as well. The words are the
  screen's own, a table per language in its code, as a page's script's
  texts would be Tun's catalogues' if the server wrote them; a screen's
  built code is not the server's to translate.
- A person's chosen theme is kept by the pages' theme switch in the
  browser (`tun-theme`); the screen reads it and sets `data-theme`, as
  the pages' script does, and the tokens' `:root[data-theme]` rules do
  the rest.

### What the policy needs of Svelte and Vite

Nothing is loosened. Vite's built `index.html` loads its script and
style sheet as files under `base`; Svelte 5 needs no `eval`. Two
settings are needed and set: `assetsInlineLimit: 0` (Vite inlines an
asset under 4 KB as a `data:` URL, which `img-src` and `font-src`
refuse) and `css: "external"` (Svelte can put a component's styles in a
`<style>` while it runs, which `style-src 'self'` refuses). The
showcase's screen has an SVG icon so criterion 9 decides the first in a
browser.

### Kept, changed, and left

- `tsc` and `node` stay in Tun's dev shell: the module's runtime test
  compiles it with `tsc` and runs it in Node (typescript-client's
  criterion 7). The type-check test now runs `svelte-check` on a Svelte
  component in place of `tsc` on `screen.ts`.
- The showcase's `src/api.ts` stays committed and compared byte for
  byte with `tun typescript`: the screen's build needs it, and
  generating it inside the Nix build would make the screen's build load
  the whole Lisp client.
- Nothing is built for the queue screen. It is served by this as it
  stands: `screens/queue/` as in `docs/client-api.md`, its operations
  with `:returns`, `tokens.css` for the look, `<html lang>` for its
  words.

## Evidence

Each criterion and what decides it:

1. `scripts/test-screens.sh` (`bin/test`'s job `check:test-screens`):
   `nix build .#showcase-screen`, its output `index.html` and `assets/`
   with `nix-store -qR` naming only itself; the screen with
   `export const wrong: number = "a text";` put in `src/main.ts`
   (`scripts/test-screens.nix`, `typeError`) refused with
   `svelte-check`'s «Type 'string' is not assignable to type 'number'»;
   a build whose `build` script writes nothing (`noIndex`) refused with
   «its build wrote no dist/index.html».
2. The same script: `nix build .#showcase`, its `sbcl-showcase` source
   in the store holding `screen/dist/index.html` with
   `src="/sign-off/assets/…`, no `nodejs` or `npm` in `nix-store -qR` of
   the server; `buildClient` with the folder `../elsewhere`
   (`outOfSource`) stops with «a screen's folder is a path in the source,
   not ../elsewhere».
3. The same script builds `checks.x86_64-linux.client-without-screen`
   (`flake.nix`): 127 paths in the test client's server's closure, none
   of Node or npm; no `node`, `npm`, `npx` or `tsc` in `clientShell { }`'s
   programs.
4. `svelte-check-takes-the-component-and-refuses-it-once-an-operation-changed`
   (`tests/typescript-tests.lisp`, fixture `tests/typescript/Screen.svelte`,
   `svelte-check` from `TUN_SCREEN_NODE_MODULES`).
5. `tun-typescript-writes-the-showcase-screen-s-committed-module`
   (the module byte for byte; `git ls-files` of `screen/dist` and
   `screen/public` empty).
6. `the-tokens-file-holds-the-pages-tokens-and-nothing-else` (every
   custom property on `:root` in the pages' whole stylesheet against the
   file's, parsed; the reader shown to tell a different value),
   `the-tokens-file-is-served-to-anyone`.
7. `a-single-page-screen-says-the-page-s-language`
   (`tests/session-api-tests.lisp`); `a-single-page-screen-is-behind-its-page-s-policy`
   now also holds the screen's policy to the exact text typescript-client
   gave it.
8. `checks/showcase/checks/single-page-screen.py` at 390 and 1280 px.
9. The same check: no inline `<script>` or `<style>` in the served
   `index.html` and no `<style>` in the page while it runs, the tokens and
   the screen's own style sheet linked, the icon loaded from
   `/sign-off/assets/signed-….svg`, no violation. Run once with
   `assetsInlineLimit: 0` and `css: "external"` taken out, it failed
   (Log, 19:12): the styles were put in a `<style>`, the colours were
   lost, and the icon never showed.
10. The same check: light at both widths, then `dark` on a dark phone and
    a dark wide page, and `tun-theme` stored as `dark` in a light phone.
11. `checks/showcase/checks/single-page-screen-norwegian.py` (scenario
    `norwegian`).
12. By hand at gate B.
13. `+core-version+` and `coreVersion` 2.49.0 (the core test that
    compares them); the clients' runs under «Clients».

## Verify rounds

1. 78b5894e: stopped by hand while it waited for the verify lock, after
   about three minutes and before any step ran, to put the pages' focus
   ring in the showcase's screen (a look seen in the pictures); its
   folder `verify-1/` holds no step's log. Not a failure.
2. 45f9fa56: build (10 s), test (215 s, 103 suites, `test-screens` 28 s
   among them) and check (715 s) passed, after 53m13s waiting for the
   verify lock behind other builders' rounds.

No round failed.

## Pictures

`~/coding/tun-wt/typescript-screens-shots/`: `tun loop show`'s
`phone-sign-off.png` and `desktop-sign-off.png`; in `after/`, the
screen's three states (`1-open`, `2-refused-at-the-field`,
`3-signed-off`) on a phone and wide, light and dark, in English (`en-`)
and on the Norwegian tenant (`nb-`), 24 pictures from a preview of
45f9fa56; in `before/`, typescript-client's pictures of the screen in
plain TypeScript with its own colours. The pairs that show the change
best: `before/phone-3-signed-off.png` against
`after/en-phone-light-3-signed-off.png` (the pages' tokens, the icon),
and `after/nb-phone-dark-2-refused-at-the-field.png` (dark, Norwegian,
the refusal at its field with the pages' focus ring). The pictures'
browser has only Open Sans and Source Code Pro (`browserPython`), so
`--font-sans` falls to the monospace one there, on the screen as on the
pages beside it; a person's browser uses its system font.

## Clients

Each client's `bin/test`, from scratch clones (tunworks 87cbde1, kurs
c2579ae, the two-client client repository 5b013cb), its Tun inputs
(`tun`, and `dashboard` and `customers` at their `modules/` directories)
overridden with this worktree's 45f9fa56, the tree verify round 2
passed, all six runs one after another under one hold of the verify
lock (`flock`, taken at 21:36 after 71 minutes' wait, let go at 21:53):
factory 12268 checks, nixploy-dashboard 1421, ferdig 812, kurs 352; the
two-client repository's first client's twelve suites (9674, 221, 71199,
529, 739, 373, 8856, 255, 127271, 91207, 16264 and 28159 checks) and its
second client's (160). Every one exit 0, no compiler warning, no
failure, unchanged.

Before the run, each client's dev shell was built with the same
overrides (no suite, no lock): each has `sbcl` and `tun`, and no `node`,
`npm` or `tsc` of its own on its `PATH` (the machine's own `node` is the
host's, not the shell's).

What a client sees differently on 2.49.0: nothing unless it uses it.
`/assets/tokens.css` answers where it was 404; a single-page screen's
`index.html` gets its `<html lang>` set; `buildClient` takes `screens`
and the flake's `lib` has `buildScreen`; a client's shell and server
have no Node.

## Log

- 2026-11-17 18:46  started, reviewed
- 2026-11-17 18:46  estimated 3h 5h 10h at brief, like tun/typescript-client tun/pdf
- 2026-11-17 18:56  gate A asked of a reviewer
- 2026-11-17 18:57  gate A: approve (reviewer)
  Gate A of typescript-screens looks right, and I'm approving it. The criteria cover the whole brief, each one can be decided by a check or test, and the spec says the same as the criteria.
  
  **Brief against the criteria**
  - **Built by Nix, offline, pinned by a hash:** criteria 1 and 2. The decision explains why `fetchNpmDeps` with `npmDepsHash` fits, which is what the brief asked for. `buildNpmPackage` builds an npm package rather than a folder of built files. `importNpmLock` would mean about fifty fetches and reading the lock file while the flake is evaluated.
  - **Type-checking, and a type error failing the build:** criterion 1 fails the Nix build on a type error. Criterion 4 keeps the test that renames a parameter, now against `Screen.svelte`, and adds a removed enum value and a removed output key. Criterion 5 checks that the committed `api.ts` matches what `tun typescript` writes. Together these cover "a changed operation fails the screen's check".
  - **A client without a screen pays nothing:** criterion 3 checks both the closure and the shell's programs, which is the proof the brief asked for.
  - **Design tokens:** criterion 6 compares parsed rules (selector, media query, property, value), not a string with itself. A real drift therefore fails, and both colour schemes are covered.
  - **The showcase in Svelte:** built files no longer committed (5), built by Nix and checked in a browser at 390 and 1280 px (8), light and dark including the stored `tun-theme` (10), and Norwegian (7, 11). Criterion 9 makes "Svelte's output runs under the policy" checkable: no inline script or style, a real SVG asset, and an external style sheet.
  - **Docs and version:** criteria 12 and 13.
  
  **The spec change**
  `spec/typescript.md` §4 and §6.1–6.5 and `spec/ui.md` §3 say what the criteria say: the `buildScreen` contract, `screens` and its rejection of bad paths, the no-Node guarantee, the working-tree link, `tokens.css` with its headers, and `<html lang>`. §6 is closed as the brief asked, and the evidence list in §7 is updated.
  
  **Decisions**
  - Whether a client with a screen gets Node in its shell is arguably the owner's call. The brief only forbids Node for clients without a screen. The builder chose the stricter reading (one Nix build, no Node in any client's shell), said why, and noted it as a question for the owner. It can be undone and is the safer default, so it doesn't block this gate.
  - Serving the tokens rather than bundling them, and setting the language through `<html lang>`, are implementation choices that still meet the brief.
  
  **Things to watch at gate B (not blocking)**
  - The brief says the page's content security policy "stays exactly as typescript-client made it". No new criterion checks that directly. It relies on the earlier header tests in `tests/session-api-tests.lisp`, so confirm they still assert the full policy.
  - The brief's "no request leaves the machine" has no criterion either. Confirm in `verify.txt` that `svelte-check` and the browser checks run offline.
  - §6.2 says a build that writes no `dist/index.html` fails, but no criterion tests it. It's minor.
  - Two lines added in the diff are over-long: in `spec/typescript.md`, the line ending "Server-rendered pages stay the rule"; in `spec/ui.md`, the line ending "(`tests/typescript-tests.lisp`); pages have the viewport tag". They need rewrapping.
- 2026-11-17 19:12  build: the browser check run with Vite's assetsInlineLimit: 0 and Svelte's css: "external" taken out failed 4 of 15 (a <style> put in the page, the screen's style sheet missing, the pages' colours lost, the icon never shown); with both, single-page-screen and single-page-screen-norwegian pass on the preview
- 2026-11-17 20:25  verify 2: passed build, test, check
- 2026-11-17 20:25  shown (/sign-off)
- 2026-11-17 21:54  clients at 45f9fa56, each bin/test from a scratch clone, all under one hold of the verify lock (71 min wait, 17 min of runs): factory 12268, nixploy-dashboard 1421, ferdig 812 (tunworks 87cbde1), kurs 352 (c2579ae), the two-client client repository (5b013cb) both clients: exit 0, no compiler warning, unchanged
- 2026-11-17 21:54  gate B asked of a reviewer
- 2026-11-17 21:55  gate B: approve (reviewer)
  I approve this gate. Every criterion has a test or browser check that would fail without the change, all three verify steps passed, and the code and docs match the spec.
  
  **Criteria against the diff**
  - **1–3 (Nix build, `screens`, no Node for a client without a screen):** `buildScreen` in `flake.nix:2832` takes the lock's packages from `fetchNpmDeps` pinned by `npmDepsHash`. It keeps `node_modules` as a separate derivation and runs `check` then `build` with npm offline. If there is no `dist/index.html` the build fails.
    - `scripts/test-screens.sh` checks that the output refers to no other store path. It also checks that a type error is refused with `svelte-check`'s message, and that a build which writes nothing is refused.
    - It also checks that the showcase's server has `screen/dist/index.html` in its source in the store and no Node in its closure. A folder containing `..` stops evaluation.
    - `checks.x86_64-linux.client-without-screen` (`flake.nix:2916`) checks both the server's closure and `clientShell`'s programs.
  - **4–5:** The fixture is now `tests/typescript/Screen.svelte`, run through `svelte-check --fail-on-warnings`. All three changes to an operation (renamed parameter, removed enum value, removed output key) must fail and name `Screen.svelte`. The test that compared the committed `dist` byte for byte is replaced by a `git ls-files` check that `screen/dist` and `screen/public` hold nothing. The old built files are deleted in the diff.
  - **6:** `css-root-properties` parses the whole stylesheet and the tokens file into (media query, selector, property, value). So it doesn't just compare a string with itself; its reader is also tested on its own, including that a different value counts as a difference. The headers test covers both signed out and signed in.
  - **7:** `with-page-language` (`src/web/single-page.lisp:3385`) is tested for English, Norwegian, exactly one `lang`, an `<html>` without `lang`, and an `<html>` with a single-quoted `LANG`. The proof still comes right after `<head>`.
  - **8–11:** `single-page-screen.json` and `single-page-screen-norwegian.json` both passed, every step `ok`. The checks look for:
    - no inline `<script>` or `<style>` in the served file or while the page runs;
    - the tokens and the screen's own style sheet linked;
    - the icon served from `/sign-off/assets/signed-….svg`;
    - colours computed in light and dark, plus a stored `tun-theme`;
    - Norwegian words and «må fylles ut» at the field.
  
    The log shows the check failed with `assetsInlineLimit: 0` and `css: "external"` removed, so it really decides criterion 9.
  - **12:** I read the docs by hand. `docs/client-api.md` now goes start to finish: the screen's files, `index.html`, the flake lines, the `npmDepsHash` workflow, `.gitignore`, the two `bin/test` lines and the editor link. `spec/typescript.md` closes §6 and splits it into 6.1–6.5. `spec/ui.md` §3 is updated, and `reference/pitfalls.md` gains five new entries. The two over-long lines gate A pointed out are rewrapped.
  - **13:** Core version is 2.49.0 in both `+core-version+` and the flake. The record logs every client's `bin/test` passing from scratch clones.
  
  **Brief**
  - The content security policy now has a test against its exact text (`tests/session-api-tests.lisp:3487`), which answers gate A's first note.
  - npm is told to stay offline and not check for a newer npm. The only network step is the fixed-output fetch.
  - The screenshots show the screen at 390 and 1280 px in the pages' tokens. The checks confirm dark mode and Norwegian, whose pictures are outside the packet.
  
  **Code**
  - It is readable, with no leftover debugging or dead code, and the comments explain why rather than recount history.
  - The screen's words live in `words.ts` rather than Tun's catalogues. That differs from `AGENTS.md`'s rule that copy goes in catalogues, but the spec explains the choice in `spec/typescript.md` §4: a screen's built code is not the server's to translate.
  
  **Not blocking**
  - Criterion 2 lists three bad folders: empty, absolute, and containing `..`. Only the `..` case is tested (`scripts/test-screens.nix`, `outOfSource`). The code in `flake.nix:2800` handles all three plainly. Adding `""` and `"/abs"` to `test-screens.nix` would cover the rest of the criterion.
  - Tun's own dev shell now depends on the showcase screen's npm fetch (`TUN_SCREEN_NODE_MODULES`). That is acceptable, since it is cached after the first fetch and a client's shell doesn't get it.
