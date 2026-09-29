#!/usr/bin/env bash
# Runs the exception check and the scan gate against the fixtures in ./fixtures.
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

export OUT=$work/out
image=example.invalid/fixture@sha256:$(printf '0%.0s' {1..64})
expired=(IGNOREFILE="$fixtures/ignore-expired.yaml" TRIVY_REPORT="$fixtures/report-expired-exception.json")
live=(IGNOREFILE="$fixtures/ignore-valid.yaml" TRIVY_REPORT="$fixtures/report-live-exception.json")
expect "block fails on a critical whose exception has expired" 1 env MODE=block "${expired[@]}" "$here/run.sh" "$image"
expect "report does not fail on the same report" 0 env MODE=report "${expired[@]}" "$here/run.sh" "$image"
expect "block passes when a live exception covers the critical" 0 env MODE=block "${live[@]}" "$here/run.sh" "$image"
expect "run refuses an image given by tag" 2 "$here/run.sh" example.invalid/fixture:latest

exit $((failures > 0))
