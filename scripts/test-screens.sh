#!/usr/bin/env bash
# What a client's Nix build does with a single-page screen
# (spec/typescript.md 6): the showcase's server built with its screen, whose
# source in the store holds the screen's built files and whose closure has
# no Node; and the check that a client without a screen pays nothing.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
command -v nix >/dev/null || { echo "test-screens: nix is not on the PATH" >&2; exit 1; }
work="$(mktemp -d "${TMPDIR:-/tmp}/typescript-screens-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
refusals="(import $here/scripts/test-screens.nix { flake = builtins.getFlake \"git+file://$here\"; })"

# The screen's build: type-checked and built offline, its output the built
# files and nothing that refers to the store.
screen="$(nix build "$here#showcase-screen" --no-link --print-out-paths)"
for file in index.html assets; do
  [ -e "$screen/$file" ] || { echo "test-screens: the screen's build has no $file" >&2; exit 1; }
done
if [ "$(nix-store -qR "$screen" | wc -l)" -ne 1 ]; then
  echo "test-screens: the screen's build refers to other store paths:" >&2
  nix-store -qR "$screen" >&2
  exit 1
fi
echo "== the showcase's screen built: $screen, referring to no other store path"

# Each must fail with its own message (WHAT, the attribute of
# test-screens.nix, the text its failure holds).
refused() {
  local what="$1" attribute="$2" text="$3" status=0
  "${@:4}" --impure --expr "$refusals.$attribute" >"$work/$attribute.log" 2>&1 || status=$?
  if [ "$status" -eq 0 ]; then
    echo "test-screens: $what was not refused" >&2
    exit 1
  fi
  if ! grep -qF -- "$text" "$work/$attribute.log"; then
    cat "$work/$attribute.log" >&2
    echo "test-screens: $what was refused, but not with «$text»" >&2
    exit 1
  fi
  echo "== $what is refused: $(grep -F -m1 -- "$text" "$work/$attribute.log" | sed 's/^ *//')"
}
refused "a type error in the screen" typeError "Type 'string' is not assignable to type 'number'" \
  nix build --no-link -L
refused "a build that writes no index.html" noIndex "its build wrote no dist/index.html" \
  nix build --no-link -L
refused "a screen's folder out of the source" outOfSource "a screen's folder is a path in the source, not ../elsewhere" \
  nix eval

server="$(nix build "$here#showcase" --no-link --print-out-paths)"
source="$(nix-store -qR "$server" | grep -E -- '-sbcl-showcase-[0-9.]+$' | head -1)"
index="$source/screen/dist/index.html"
if [ ! -f "$index" ] || ! grep -q 'src="/sign-off/assets/' "$index"; then
  echo "test-screens: the showcase's server has no built screen at $index" >&2
  exit 1
fi
echo "== the showcase's server has its screen's files in the store: $index"
if nix-store -qR "$server" | grep -E -- '-(nodejs|npm)-'; then
  echo "test-screens: the showcase's server has Node in its closure" >&2
  exit 1
fi
echo "== and no Node in its closure"
nix build "$here#checks.x86_64-linux.client-without-screen" --no-link --print-build-logs
echo "== a client without a screen: $(cat "$(nix build "$here#checks.x86_64-linux.client-without-screen" --no-link --print-out-paths)")"
