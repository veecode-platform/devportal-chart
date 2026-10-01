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
expired_high=(IGNOREFILE="$fixtures/ignore-expired.yaml" TRIVY_REPORT="$fixtures/report-expired-high.json")
unmatched=(IGNOREFILE="$fixtures/ignore-expired.yaml" TRIVY_REPORT="$fixtures/report-live-exception.json")
expect "block fails on a high whose exception has expired" 1 env MODE=block "${expired_high[@]}" "$here/run.sh" "$image"
expect "report does not fail on the same high" 0 env MODE=report "${expired_high[@]}" "$here/run.sh" "$image"
expect "block passes when an expired exception matches no finding" 0 env MODE=block "${unmatched[@]}" "$here/run.sh" "$image"
other=example.invalid/other@sha256:$(printf '1%.0s' {1..64})
expect "run refuses a report of another image" 2 env MODE=block "${live[@]}" "$here/run.sh" "$other"
stub=$work/stub
mkdir "$stub"
cat >"$stub/trivy" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == --version ]]; then echo "Version: $STUB_VERSION"; exit 0; fi
exit "$STUB_EXIT"
STUB
chmod +x "$stub/trivy"
stubbed=(PATH="$stub:$PATH" STUB_VERSION="$(sed -n 's/^TRIVY_VERSION=//p' "$here/run.sh")")
expect "report exits non-zero when Trivy fails" 3 env MODE=report "${stubbed[@]}" STUB_EXIT=1 "$here/run.sh" "$image"
expect "report exits non-zero when Trivy writes no report" 3 env MODE=report "${stubbed[@]}" STUB_EXIT=0 "$here/run.sh" "$image"
expect "run refuses an image given by tag" 2 "$here/run.sh" example.invalid/fixture:latest

reporter=$work/reporter
mkdir "$reporter"
cat >"$reporter/trivy" <<'STUB'
#!/usr/bin/env bash
if [[ $1 == --version ]]; then echo "Version: $STUB_VERSION"; exit 0; fi
if [[ $1 == version ]]; then echo '{}'; exit 0; fi
image=${*: -1}
[[ $image != *"$STUB_FAIL_ON"* ]] || exit 1
while [[ $# -gt 0 ]]; do
  [[ $1 == --output ]] && cp "$STUB_REPORT" "$2"
  shift
done
STUB
chmod +x "$reporter/trivy"
jq '.Results[0].Packages = [{"Name": "minimist"}, {"Name": "other"}]' "$fixtures/report-expired-exception.json" >"$work/plugin-report.json"
reporting=(PATH="$reporter:$PATH" STUB_VERSION="$(sed -n 's/^TRIVY_VERSION=//p' "$here/run.sh")" STUB_REPORT="$work/plugin-report.json" STUB_FAIL_ON=none)
face=$here/face-defaults.sh
expect "face defaults exits 0 although an artifact has a critical with a fix" 0 env OUT="$work/face" "${reporting[@]}" "$face" "$fixtures/face.yaml"
expect "face defaults scans the enabled, digest-pinned OCI entries and no other" 0 test "$(grep -c '| 2 | 1 | 0 | 1 | 0 | 0 | 1 | scanned |$' "$work/face/summary.md")" -eq 2
expect "face defaults lists an enabled OCI entry that has no digest" 0 grep -q 'by-tag:1.0.0` | none .* not pinned by digest' "$work/face/summary.md"
expect "face defaults exits 0 when an artifact cannot be scanned" 0 env OUT="$work/face-failed" "${reporting[@]}" STUB_FAIL_ON=enabled-two "$face" "$fixtures/face.yaml"
expect "face defaults records the artifact that could not be scanned" 0 grep -q 'enabled-two` .* scan did not run (exit 3)' "$work/face-failed/summary.md"
expect "face defaults exits 0 when the face file is missing" 0 env OUT="$work/face-missing" "${reporting[@]}" "$face" "$work/missing.yaml"
expect "face defaults says that nothing was scanned" 0 grep -q 'Not scanned: the face file could not be read' "$work/face-missing/summary.md"

exit $((failures > 0))
