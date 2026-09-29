#!/usr/bin/env bash
# Runs the scan runner and the exception check against the fixtures in ./fixtures.
# Needs no Trivy, no network and no image.
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fixtures=$here/fixtures
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

expect() {
  local name=$1 want=$2 got=0
  shift 2
  "$@" >"$work/output" 2>&1 || got=$?
  if [[ $got -eq $want ]]; then
    echo "ok   $name (exit $got)"
  else
    echo "FAIL $name: exit $got, wanted $want"
    sed 's/^/     /' "$work/output"
    failures=$((failures + 1))
  fi
}

check=$here/check-ignorefile.sh
expect "check passes on a valid ignore file" 0 "$check" "$fixtures/ignore-valid.yaml"
expect "check passes on the repository ignore file" 0 "$check"
expect "check fails on an entry without expired_at" 1 "$check" "$fixtures/ignore-missing-expired-at.yaml"
expect "check fails on an entry without statement" 1 "$check" "$fixtures/ignore-missing-statement.yaml"
expect "check fails on a quoted expired_at" 1 "$check" "$fixtures/ignore-quoted-expired-at.yaml"

exit $((failures > 0))
