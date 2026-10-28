#!/usr/bin/env bash
# tests/fixtures/core-1.23.1/make-fixtures.sh OUT
#
# Make the dumps of spec/i18n.md 4.7 into OUT.  Run from a checkout of core
# 1.23.1, inside `nix develop` and bin/with-postgres:
#   bin/with-postgres PATH/make-fixtures.sh OUT
# Each kind (core, business, inbox) is a tenant core 1.23.1 wrote, on SQLite
# and on Postgres; make-fixture.lisp says what each holds.
set -euo pipefail
out="$1"; mkdir -p "$out"; work="$(mktemp -d)"
for kind in core business inbox; do
  sbcl --noinform --non-interactive --no-userinit --no-sysinit \
       --load "$(dirname "$0")/make-fixture.lisp" "$kind" "$work" >"$work/$kind.log" 2>&1 \
    || { tail -40 "$work/$kind.log"; exit 1; }
  sqlite3 "$work/$kind.sqlite" .dump > "$out/$kind.sqlite.sql"
  url="$(cat "$work/$kind.pgurl")"
  host="$(echo "$url" | sed -E 's/.*host=([^&]*).*/\1/')"
  db="$(echo "$url" | sed -E 's|^postgresql://[^/]*/([^?]*).*|\1|')"
  pg_dump --no-owner --no-privileges --inserts -h "$host" -U tun "$db" > "$out/$kind.postgres.sql"
done
