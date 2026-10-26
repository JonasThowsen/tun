# Coalton

Coalton is a statically typed language in the style of ML and Haskell,
embedded in Common Lisp (https://github.com/coalton-lang/coalton, MIT). It
was evaluated hands-on for Tun on 2026-10-10 on SBCL 2.6.4.

## Decision

**Not now, and never in the extension surface.** Seams, operations,
entities and the `TUN` package stay plain Common Lisp. Coalton may later fit
inside a module, for pure arithmetic behind ordinary Lisp functions. Revisit
when Coalton tags a release and nixpkgs carries it.

## What works

- **Calling across.** Lisp calls Coalton functions directly, and Coalton
  calls Lisp, including Tun's generic functions. A client method added at run
  time was seen at once.
- **Same-type live redefinition.** Redefining a Coalton function with the
  same type is seen immediately by Lisp and Coalton callers, as with a
  `defun`.
- **Type errors are good.** They name the expected and actual types and
  point at the source.
- **Incompatible type changes are refused** with the affected callers named,
  and the old code keeps running.

## Why not now

- **The dialect in nixpkgs is obsolete.** The pinned nixpkgs carries the
  snapshot from 2026-01-01. Coalton broke its syntax several times in 2026,
  most recently three days before this evaluation. The online documentation
  describes the new syntax, which does not compile on the packaged version.
  Agents would meet two incompatible dialects.
- **It is pre-1.0 with one main maintainer.** No language release has been
  tagged. One person wrote about nine in ten commits in the last year.
- **Live patching weakens the guarantees.** Adding a constructor to a type in
  a running image does not re-check existing functions, so a match that was
  exhaustive can fail at run time. Forcing an incompatible redefinition
  leaves every caller broken until recompiled.
- **It does not fit the seam model.** Tun extends through generic functions
  that dispatch on the client's feature classes. Coalton's type classes are
  global and dispatch on types, so seam calls from Coalton are untyped glue.
  Clients would also need Coalton symbols, which the interface check refuses.
- **It costs start-up and build time.**

| Measure | Coalton | Common Lisp |
|---|---|---|
| Cold load of the system | 1.25 s, +37 MB heap | Tun's whole kernel: 1.20 s, +28 MB |
| Compiling a small pricing file | 0.30 s | 0.011 s |
| 200 small definitions, separate forms | 3.19 s | 0.20 s |
| 10 million line prices, release mode | 0.61 s | 0.27 s |

- **The error loop is slow for agents.** Compilation stops at the first
  Coalton error in a file, and errors inside macro expansions point at the
  expansion rather than the source.

## Getting most of the benefit in plain Lisp

- `(declaim (ftype (function (integer price-mode) integer) line-total))` on
  internal functions. SBCL checks the calls at compile time where it can and
  at run time under Tun's safety policy.
- `deftype` with `member` types for closed sets, such as price modes.
- `ecase` and `etypecase` over those types, so an unhandled case signals.
- Typed fields in `define-entity`, which already validate at the boundary.

## If we try it later

Time-box it to two days on a throwaway branch.

1. Pin current Coalton from git through `buildASDFSystem`, not the nixpkgs
   snapshot.
2. Move only the price-mode arithmetic of `modules/orders` into one Coalton
   file. Keep `apply-price-mode` and `reprice` as Lisp wrappers with the same
   signatures and errors. No Coalton symbols in any interface.
3. Keep it only if the build stays warning-free and every suite stays green,
   start-up grows by less than 1.5 s, a live same-type fix works over the
   REPL, and a fresh agent adds a price mode at no higher cost than in Lisp.
