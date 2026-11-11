# A staff page shows that it is loading when a link or form takes more than a moment

- loop: loading-sign
- mode: reviewed
- stage: ship
- base: 0a9f48a3d8a35c7e4356070800c606390fc5b93b
- item: sak_d6c25jh5w82q8t93
- tags: kind:ui core module:ui
- drafted: 30m
- estimate: 1h 2h 4h
- like: ui-graph-fit home-page chart-tooltip-height
- verified: d10def6bf9143a675b00613a30ac0b090b477f02
- shown: d10def6bf9143a675b00613a30ac0b090b477f02

## Brief

Ferdig sak_d6c25jh5w82q8t93, brought by the factory's orchestrator on
2026-11-11. Jonas, 2026-11-10, on the factory's pages:

> opening the pages that have quite a lot of graphs etc, and there is no
> loading indicator to show that something is loading … the same can be
> said when i try to open a point in the graph

Every staff page's links and forms go through htmx (`hx-boost`), which
swaps the body when the answer arrives; until then nothing says anything
is happening, and Tun turns htmx's own indicator styles off.

What must hold, from the orchestrator:

- In the design system, for every Tun client with no change of theirs:
  when a navigation or a form submission through htmx has not been
  answered after a short delay (so fast pages never flash; choose and
  spec the delay), a visible sign that the page is working, such as a
  thin bar at the top, cleared when the swap, an error or a cancelled
  request arrives, including after a failed request and after the
  browser's back button. It never shows for preloads (requests with
  `Tun-Preload: true`), and a part of a page loading by itself
  (`hx-trigger="load"` fragments) does not show the page-wide sign
  unless decided and specced otherwise.
- Accessible: a screen reader hears that the page is loading once, not
  repeatedly (`aria-busy` on the swapped region or a polite live region:
  decide); it respects `prefers-reduced-motion`; it works at phone width,
  in light and dark, with the page's content security policy (no inline
  script or style: in the shared stylesheet and script, found by
  `data-tun-*` attributes and event delegation; htmx 4's events are
  named with colons).
- Without JavaScript nothing changes.
- Spec in `spec/ui.md`, the specimen if it fits, a browser check that
  makes a page slow and asserts the sign appears after the delay and is
  gone after the swap, and that a fast page never shows it.

Mode: reviewed. A core change, additive.

## Criteria

1. Every `app-shell` holds, after the skip link, a bar `<div
   class="tun-app-shell-loading" data-tun-loading hidden
   aria-hidden="true">` and an empty live region `<div
   class="tun-app-shell-loading-status" role="status"
   data-tun-loading-status="Loading…">`, the text in the page's language
   («Laster…» in Norwegian); no style attribute. No client changes
   anything to get them. (`tests/ui-layout-tests.lisp`)
2. On the showcase's `/wait` at 390 px, a link to a page that answers at
   once and a part that loads by itself (`hx-trigger="load"`, answered
   after 1 s) never show the bar. (`loading-sign.py`)
3. A link to a page that answers after 1.5 s: 150 ms after the press the
   bar is hidden; it shows between 300 and 700 ms after the press,
   spanning the window's width, and the region then says «Loading…»,
   once for that wait; when the page is swapped in, the bar is hidden
   and the region empty. (`loading-sign.py`)
4. A form whose answer takes 1.5 s shows the bar, and it is gone once
   the page after it (a 303) is shown. (`loading-sign.py`)
5. A request that fails on the network after 0.8 s shows the bar and
   clears it. Back to a boosted page while a slow page loads: htmx
   restores that page (`htmx:before:history:restore`, the address the
   earlier page's), the bar is shown on the restored page 300 ms later
   while the slow request is under way, and once it has ended the bar
   is hidden and the region empty. (`loading-sign.py`)
6. A preload never shows it: at 1280 px, the pointer rests on «A slow
   page» for 2 s without a click (a preload of the 1.5 s page, which the
   check sees requested with `Tun-Preload: true`), and the bar never
   shows. (`loading-sign.py`)
7. A request cancelled with `htmx:abort` on the form that asked clears
   the bar and the region within 200 ms, and the page stays. «A slow
   page», and «A fast page» once the bar shows: htmx 4 cancels neither,
   so 300 ms later the fast page is in and the bar still shown (the slow
   request is under way), and once that has ended the bar is hidden and
   the region empty.
   (`loading-sign.py`)
8. An error: a link whose answer is a 500 page after 0.8 s shows the
   bar, and once the error page is swapped in the bar is hidden.
   (`loading-sign.py`, the answer made by the check's route)
9. At 1280 px in the dark it shows; under `prefers-reduced-motion:
   reduce` it has no animation and stands still as stripes; without
   JavaScript it stays hidden. (`loading-sign.py`)
10. Its CSS is in the stylesheet (the shell's component CSS, the
   keyframes named for it) and its script in the components' script,
   listening on `document` for `htmx:before:request` and
   `htmx:finally:request`; the page's policy is unchanged.
   (`tests/ui-layout-tests.lisp`)
11. `spec/ui.md` §4.1 «The loading sign» and §10 say this; the core
   version is the next free on main when pushed, 2.22.0 now, in
   `src/core/module.lisp` and `flake.nix`.

## Decisions

- **300 ms.** Below about 100 ms a change feels instant and up to about
  a second a person's flow is kept (Nielsen's limits); a sign before
  300 ms flashes on pages that are only a little slow, one after
  500 ms leaves a dead page for half a second. Most of Tun's pages
  answer well within 300 ms, so they show nothing.
- **A bar at the top, not a spinner or a dimmed page.** It is what
  browsers and most applications show for a navigation, it does not
  move the layout, and it is visible on a phone and a desktop, beside
  the sidebar or not. 3px in `--primary` over its own 20 % track, a 40 %
  part sliding across, as `progress` does when its length is unknown.
  Under reduced motion it stands still as stripes, as `progress` does.
- **A polite live region, not `aria-busy`.** Screen readers do not
  announce `aria-busy`, and htmx swaps the whole body, so a flag on it
  would be gone with it. The region is in the page from the start
  (a live region added later is often not read), says «Loading…» once
  when the bar shows, and is emptied when it goes; the new page's region
  is empty. A fast page says nothing at all.
- **Which requests.** A request for the whole page (`HX-Request-Type:
  full`: boosted links and forms, Back, `HX-Location`) and a part a
  click or a submission started (a board's move by its menu); not a
  part that loads by itself (`load`, `revealed`, polling, a search as
  one types), which has its own place on the page and would otherwise
  show the page-wide sign on every slow fragment.
- **Preloads** are fetches of Tun's own script, not htmx requests, so
  htmx's events never fire for them. A click served by a preload that
  is still loading is a person waiting, so it counts from the click.
- **Cleared on `htmx:finally:request`**, which htmx 4 fires after the
  swap, after an error and after a cancelled request, on `document`
  when the element that asked is no longer in the page. A count of the
  requests that show it clears the bar when the last ends. `pageshow`
  with `persisted` clears a page the browser shows from its cache.
- **In the app shell's markup and script.** Every staff page is an
  `app-shell`; a guest page has no htmx requests of its own. The text is
  the server's (`tr "Loading…"`, which the spinner already uses), so the
  script holds no copy.
- **The specimen** shows the shell already; the bar is hidden there as
  on any page that has loaded, so no example is added for it.
- **The showcase's `/wait`** answers after `?ms=` (at most 5 s), with
  links to a slow and a fast page, a slow form, and a part that loads
  by itself, for the check.
- **htmx 4 cancels no navigation for another** (found at gate B): a
  boosted link pressed, or Back, while a boosted request is under way
  leaves the earlier request running, and htmx swaps its page in when it
  ends, after the later page. The sign tells the truth about that (it
  stays until the earlier request ends) rather than changing how
  navigation works, which is not this loop's; spec §4.1 says so. A
  request that is cancelled (`htmx:abort`) ends with
  `htmx:finally:request` and clears it. A page swapped in meanwhile
  brings its own hidden bar, so the script shows it again after each
  swap while it is showing (`htmx:after:swap`); the new page's region
  stays empty, since «Loading…» was said once for that wait.
- **Core version** 2.22.0, the next free minor after `home-page`'s
  2.21.0; additive.

## Log

- 2026-11-11 09:55  started, reviewed
- 2026-11-11 09:56  estimated 1h 2h 4h at brief, like ui-graph-fit home-page chart-tooltip-height
- 2026-11-11 09:58  gate A asked of a reviewer
- 2026-11-11 09:58  gate A: changes (reviewer)
  The brief is mostly covered. The 300 ms delay, the bar, the polite live region, which requests count, no-JS behaviour, the content security policy, the dark scheme, phone width and reduced motion all have criteria. The decisions on the delay and on live region versus `aria-busy` were ones the brief left to the builder. Nothing under **Decisions** needed the asker. The §4.1 and §10 text in `spec/ui.md` matches the criteria. The criteria do stay within the brief. But the brief names three things explicitly, and no criterion checks them.
  
  **What is right**
  - Criteria 1–4 and 7–9 are concrete, and a test or check can decide each one: the exact markup, the timing windows (150 ms hidden, shown by 300–700 ms), the width, saying it once, the 303, dark, reduced motion and no JS.
  - The `hx-trigger="load"` part gets a criterion of its own: answered after 1 s, never shows the bar (criterion 2).
  - The version rule (2.22.0 in both `module.lisp` and `flake.nix`) is stated.
  
  **Changes**
  
  1. **Criterion 6 (preloads) can't be decided by a check as written.** The brief says the sign "never shows for preloads". But criterion 6 is a claim about the design ("preloads are plain fetches outside htmx"), and the unit test only looks for strings in the script. In `loading-sign.py` every preload is followed by a click, and the click's htmx request is what shows the bar. So the check can't tell whether a preload on its own would show it. Add a criterion like: "At 1280 px, the pointer rests on «A slow page» for 1 s without clicking (a preload of a 1.5 s page); the bar never shows." Back it with that step in `loading-sign.py`.
  
  2. **No criterion covers a cancelled request, and that is the riskiest path.** The brief says the bar clears when "a cancelled request arrives". `spec/ui.md` §4.1 «When it goes» promises this ("cancelled, as by another request or Back"). The script keeps a count (`waiting`), and it only clears when every request that showed the bar gets `htmx:finally:request`. If a request replaced by a newer one never gets that event, the count stays at 1 and the bar stays up forever. Criterion 5's Back step doesn't show this, because Back may restore the page from history rather than cancel the request. Add: "Pressing «A slow page», then «A fast page» before the first answers: once the fast page is shown, the bar is hidden and the region is empty."
  
  3. **No criterion covers an error response.** The brief lists "an error" apart from "a failed request", and §4.1 promises "refused (a 4xx or 5xx page is swapped in too)". Criterion 5 only covers a network abort. Add: "A link whose answer is a 500 after 0.8 s shows the bar and clears it once the error page is shown." `/wait` could take a `status=` parameter, or the check could use `page.route` to answer with `status=500`.
  
  The rest of the spec can stay as it is.
- 2026-11-11 10:02  gate A asked of a reviewer
- 2026-11-11 10:03  gate A: approve (reviewer)
  Gate A, second round. The three changes asked for in the first round are now in the criteria, the spec says the same thing, and nothing here needs to go back to the asker.
  
  **The three earlier changes**
  - **Preload (criterion 6):** this can now be checked. The pointer rests on «A slow page» for 2 s without a click. The check confirms a request went out with `Tun-Preload: true` for the 1.5 s page, and that the bar never showed. This is the "never shows for preloads" the brief asks for.
  - **Cancelled request (criterion 7):** «A slow page» is pressed, then «A fast page» 100 ms later. After 2.5 s the bar must be hidden and the region empty, whichever page htmx ends up showing. That catches a count that never gets back to zero, which was the risk named last round.
  - **Error (criterion 8):** a 500 answer after 0.8 s, built by the check's own route, must show the bar and clear it once the error page is swapped in. The brief lists this apart from a network failure, and criterion 5 still covers that failure.
  
  **Against the brief**
  - **Delay:** 300 ms is chosen and written into the spec, so fast pages never flash. Criterion 3 tests both sides of it: hidden at 150 ms, shown between 300 and 700 ms.
  - **When it clears:** after the swap, an error, a cancelled request, a failed request and Back. These are criteria 3, 8, 7 and 5. The spec also handles a page the browser shows from its cache (`pageshow` with `persisted`).
  - **Parts that load by themselves:** a `hx-trigger="load"` part doesn't show the bar (criterion 2). Not showing it for such parts is the brief's default, and it is specced in §4.1 «Which requests».
  - **Screen readers:** the builder picked a polite live region over `aria-busy`, and the brief left that choice to them. "Says it once" can be checked (criterion 3).
  - **The rest of the brief:**
    - reduced motion, dark mode, desktop width and no JavaScript are in criterion 9;
    - phone width is in criteria 2 and 3;
    - the page's content security policy, `data-tun-*` attributes, listeners on `document` and htmx 4's colon-named events are in criteria 1 and 10;
    - "no client changes anything" is in criterion 1.
  - **The asker's two complaints:** heavy graph pages are boosted navigations. Opening a point in the graph is following a node's link (`:href`, `spec/ui.md:821`). So both are whole-page requests, and criteria 3 and 4 cover them.
  
  **Spec against criteria**
  - §4.1 «The loading sign» matches the criteria: what the bar looks like, which requests count, when it goes, the screen reader region and where it all lives.
  - The §10 entries list each criterion's check or test.
  - The version (2.22.0 in both `src/core/module.lisp` and `flake.nix`) is stated.
  
  **Decisions**
  - The delay, the bar, the live region, which requests count, leaving the specimen alone and the `/wait` page are all things the brief asked the builder to decide.
  - One small gap, not a reason to block: §4.1 also has a part-of-a-page request started by a click show the sign (a board's move). No criterion checks that. It goes a little past "a navigation or a form submission", but it is additive and in line with what the brief wants.
- 2026-11-11 10:12  verify 1: passed build, test, check
- 2026-11-11 10:13  shown (/wait?ms=0)
- 2026-11-11 10:13  the bar while /wait?ms=3000 loads, 390 and 1280 px, light and dark: .build/loop/loading-sign/show/loading-*.png (the shown pages have loaded, so their bar is hidden)
- 2026-11-11 10:13  gate B asked of a reviewer
- 2026-11-11 10:15  gate B: changes (reviewer)
  I'm asking for changes. The feature itself works: all three verify steps passed (build, test, check), every step of `loading-sign.py` passed, and the screenshots show the bar at 390 px and 1280 px in both light and dark. The problem is that two of the checks would pass even without the change, and they guard the riskiest path gate A named.
  
  **What is right**
  - **Markup:** `layout.lisp:973-979` puts the bar (`hidden`, `aria-hidden`) and an empty `role="status"` region in every `app-shell`, with the text from the server via `tr`. There is no style attribute and no client change. The unit test also covers «Laster…».
  - **CSS:** it is in the shell's component CSS, with keyframes named for the shell. Reduced motion turns into still stripes, and `[hidden]` hides the bar. Within the page's policy.
  - **Script:**
    - It listens on `document` for `htmx:before:request` / `htmx:finally:request` and keeps a count that clears when it reaches zero.
    - `pageshow` with `persisted` clears a page the browser shows from its cache.
    - It reads `HX-Request-Type` the same way `kit.lisp:531` does.
    - It sits before the popover early `return` (`layout.lisp:908`), so it runs even without popover support.
    - The component script is wrapped in a function (that `return` shows it), so names like `show` and `clear` don't leak.
    - A preload's fetch happens after `before:request`, so a click served by a preload counts from the click, as decided.
  - **Check results:**
    - Fast page and the `load` part: nothing seen.
    - Slow link: hidden at 150 ms, shown at 304 ms, 3 px high and 390 px wide, «Loading…» said once, cleared after the swap.
    - Slow form: shows and clears.
    - Network failure and 500: the bar showed, then cleared.
    - Preload: a request with `Tun-Preload: true` went out and nothing showed.
    - Dark: shows. Reduced motion: `animation: none`. No JavaScript: hidden.
  - **Spec and version:** §4.1 and §10 match the criteria. The version is 2.22.0 in both `module.lisp` and `flake.nix`.
  
  **Changes**
  
  1. **Criterion 7 (a request given up for another) is not actually tested** (`checks/showcase/checks/loading-sign.py:106-112`).
     - The step only asserts `not shown and said == ""` at the end, which also holds on a page with no loading sign at all.
     - The result shows the URL `…/wait?ms=1500`. So the slow page won and the fast press was dropped or never sent; nothing was cancelled.
     - Gate A asked for this criterion because a request that never gets `htmx:finally:request` would leave `waiting` stuck above zero and the bar up for good.
     - Fix:
       - Assert the bar was seen during the step (`seen(page) > before`).
       - Make the step really cancel an in-flight request that counts. For example, record each `htmx:before:request` / `htmx:finally:request` and assert the fast press started its own request. Or use a pair of requests that htmx does cancel.
       - Then assert the bar is hidden and the region empty.
     - If htmx 4 never cancels in this situation, say that in §4.1 and change the criterion to match, rather than claim it.
  
  2. **Criterion 5's Back step doesn't use htmx's history** (`loading-sign.py:126-134`).
     - `page.goto("/wait?ms=0")` just before it makes `go_back()` a navigation between documents. The old document is unloaded or restored from the browser's cache, and the result shows the URL `…ms=1500`, which is the error page's entry.
     - `not shown(page)` would pass without the change, and the case the asker will actually hit is never run: Back inside boosted pages while a request is in flight.
     - Fix: reach the starting page by a boosted link, not `goto`. Then press «A slow page» and wait for the bar, press Back, and assert:
       - the URL is the earlier boosted page's;
       - the bar is hidden;
       - the region is empty.
  
  3. **Minor, not blocking:** `spec/ui.md:15-17` now wraps as "How / every Tun / page looks". Reflow the paragraph.
- 2026-11-11 10:26  verify 2: passed build, test, check
- 2026-11-11 10:27  shown (/wait?ms=0)
- 2026-11-11 10:27  the bar while /wait?ms=3000 loads, 390 and 1280 px, light and dark: .build/loop/loading-sign/show/loading-*.png
- 2026-11-11 10:27  gate B asked of a reviewer
- 2026-11-11 10:28  gate B: changes (reviewer)
  I've finished reading the packet. Here is my review. The change is mostly right, but one thing it promises in the spec is not true at runtime, and the checks don't catch it.
  
  **What is right**
  - **Verification:** all three steps of `verify.txt` passed (build, test, check). All 23 steps of `loading-sign.py` passed.
  - **Screenshots:** the bar shows across the top at 390 px and 1280 px, in light and dark.
  - **Markup:** `layout.lisp:973-979` adds the bar and the empty `role="status"` region to every `app-shell`. The text comes from the server via `tr`, with no style attribute and no client change. The unit test also covers «Laster…».
  - **CSS:** it is in the shell's component CSS, with the keyframes named for the shell. Under reduced motion it becomes still stripes.
  - **Script:** it listens on `document` for `htmx:before:request` and `htmx:finally:request`, keeps a count, and handles `pageshow` with `persisted`. It contains no debugging leftovers.
  - **The two changes from round 1 are done:**
    - **Criterion 7:** the `htmx:abort` step now waits for the bar to be visible, so it would fail without the change. The slow-then-fast step asserts `seen > before and shown`. The finding that htmx 4 cancels neither request is recorded under Decisions and in §4.1. The criterion was changed to match rather than claim a cancellation.
    - **Criterion 5:** the Back step now reaches the page by a boosted link. It records `htmx:before:history:restore` and asserts that the restored address is `/wait?ms=0`.
  - **Version:** 2.22.0 in both `module.lisp` and `flake.nix`. The status paragraph at the top of `spec/ui.md` is reflowed.
  
  **Changes**
  
  1. **The bar disappears whenever the body is swapped while a slow request is still under way. The spec says it stays.**
     - **Cause:** `show()` (`layout.lisp`, the script at about line 470) runs only once, from the 300 ms timer. htmx swaps the body, and the new body's bar comes from the server with `hidden`. If a page is swapped in while `waiting > 0` and the timer has already fired, the bar vanishes and nothing shows it again.
     - **Back:** this is exactly the Back case. The results show Back restoring `…ms=0`, then the slow page swapping in later at `…ms=1500`, with no sign in between. Yet §4.1 «When it goes» says "the sign stays until then", and §10 says that after Back "it stays while the slow request is under way". Criterion 5 only checks the end state, so it misses this.
     - **Slow then fast:** the same flaw affects that step. It passes only because the fast page is swapped in before the 300 ms timer fires. If the fast link were pressed at 400 ms, after the bar had shown, the bar would go while the slow request ran on.
     - **Fix:** when a swap or history restore lands while a counted request is still under way and the bar has already shown, show it again. For example, on `htmx:after:swap` and `htmx:after:history:restore`, run `if (waiting > 0 && timer === null) show();`.
     - **Checks to add in `loading-sign.py`:**
       - In the Back step (lines 143-160), about 300 ms after `go_back()`, assert that the bar is shown while the slow request is still under way.
       - In the slow-then-fast step (lines 117-128), press «A fast page» after the bar has appeared, not 100 ms after the press, and assert that the bar is still shown.
     - **If you would rather not change the behaviour:** correct §4.1 and §10 to say what really happens instead.
  
  2. **Minor, fix while there:** `spec/ui.md` line 391 of the diff (the §10 entry, "…resting on a slow link preloads it and shows nothing; in the dark at 1280 px it shows; under reduced") is not wrapped like the rest of the paragraph.
- 2026-11-11 10:39  verify 3: passed build, test, check
- 2026-11-11 10:39  shown (/wait?ms=0)
- 2026-11-11 10:40  the bar while /wait?ms=3000 loads, 390 and 1280 px, light and dark: .build/loop/loading-sign/show/loading-*.png
- 2026-11-11 10:40  gate B asked of a reviewer
- 2026-11-11 10:40  gate B: approve (reviewer)
  I've read the packet and the round 3 change. I'm approving: both points from the last round are fixed, and the checks now cover what they missed.
  
  **The two changes asked for in round 2 are done**
  - **Back, and a fast page pressed after a slow one:** before, a page swapped in while a slow request was still running came with its own hidden bar, so the sign disappeared. The script now keeps a `showing` flag and shows the bars again on `htmx:after:swap` while the sign is up (`diff.patch:493-495`). As the spec says, the new page's region is not made to say «Loading…» a second time.
  - **The checks now cover it:**
    - The slow-then-fast step presses «A fast page» only after the bar is visible. It then asserts that the fast page is in *and* the bar still shows (`loading-sign.py:119-127`).
    - The Back step asserts the bar is shown 300 ms after `go_back()`, on the page htmx restored (`:152-157`).
    - Both would fail without the new handler, and both passed: "keeps it while the slow one is under way" and "the bar stays on it while the slow request is under way".
  - **The minor wrapping fix:** the §10 entry in `spec/ui.md` is now wrapped like the rest of the paragraph.
  
  **Criteria against checks**
  - Criterion 1 and 10: covered by `tests/ui-layout-tests.lisp`:
    - the exact markup, «Laster…», and no `style=`;
    - the script strings, now including `htmx:after:swap`;
    - the keyframes and reduced motion in the stylesheet.
  - Criteria 2–9: each has a step in `loading-sign.py`, and all 24 results passed:
    - the fast page and the `load` part show nothing;
    - the slow link: hidden at 150 ms, shown at 304 ms, 3 px high and 390 px wide, «Loading…» said once, cleared after the swap;
    - the slow form, the network failure, `htmx:abort`, the 500 page and Back each show the bar and clear it;
    - a preload goes out with `Tun-Preload: true` and shows nothing;
    - it shows in the dark at 1280 px, has `animation: none` under reduced motion, and stays hidden without JavaScript.
  - **Screenshots:** the bar runs across the top at 390 px and 1280 px, in light and dark.
  - **Verification:** `verify.txt` round 3 passed build, test and check.
  
  **Against the brief**
  - The asker's two complaints are covered: heavy graph pages, and opening a point in a graph, which follows a node's link. Both are whole-page boosted requests, and those show the sign after 300 ms.
  - htmx 4 doesn't cancel the first request when a second link is followed. The sign now shows that honestly: it stays until the first request ends. That is recorded under Decisions and in §4.1.
  
  **Code**
  - The CSS sits in the shell's component CSS and the script listens on `document`, so nothing breaks the page's content security policy.
  - I checked whether the new names (`show`, `waiting` and the others) could clash with names in other component scripts. They don't: the other `show` and `waiting` are inside their own blocks, and the push, files and other checks all passed.
  - There's no leftover debugging and no dead code. The spec, the unit test and the version (2.22.0 in both `module.lisp` and `flake.nix`) all agree.
