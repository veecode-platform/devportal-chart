#!/usr/bin/env bash
# Usage: face-defaults.sh FACE_FILE
# Scans, by digest and in report mode, each OCI artifact that FACE_FILE enables, and writes
# OUT/summary.md with one row per artifact. FACE_FILE is the product face of the image
# (/opt/app-root/src/dynamic-plugins.veecode.yaml), read from the running portal.
#
#   OUT            output directory, default ./scan-out/face-defaults. Each artifact gets a
#                  subdirectory with the trivy.json and scan-summary.md that run.sh writes.
#   TRIVY_BIN_DIR  as in run.sh
#
# Exit 0 whatever the scan finds, whether an artifact could not be scanned, and whether the
# face could not be read: the rows and the notes of summary.md say so. Exit 2 is a usage error.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
out=${OUT:-scan-out/face-defaults}

usage_error() {
  echo "face-defaults.sh: $*" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage_error "usage: face-defaults.sh FACE_FILE"
face=$1
command -v jq >/dev/null || usage_error "jq is required"
command -v yq >/dev/null || usage_error "yq is required"

mkdir -p "$out"
summary=$out/summary.md
# The image's exceptions record the risk the image accepts, and a plugin artifact is not the image.
printf 'vulnerabilities: []\n' >"$out/no-exceptions.yaml"

refs=
note=
if [[ ! -s $face ]]; then
  note="the face file could not be read from the portal"
elif ! refs=$(yq -r '(.plugins // [])[] | select(.disabled != true) | (.package // "") | select(test("^oci://"))' "$face"); then
  note="the face file is not a YAML list of plugins"
else
  refs=$(printf '%s\n' "$refs" | sed -e '/^$/d' -e 's#^oci://##' -e 's#!.*$##' | sort -u)
fi
count=$(printf '%s' "$refs" | grep -c . || true)

{
  echo "# OCI plugin artifacts the face enables by default"
  echo
  echo "- Mode: report only, the findings never fail the run"
  if [[ -n $note ]]; then
    echo "- Not scanned: $note"
  else
    echo "- Enabled OCI entries in the face: $count"
  fi
  if ((count > 0)); then
    echo
    echo "| Artifact | Digest | Packages | Critical | High | Medium | Low | Unknown | Critical with a fix | Result |"
    echo "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |"
  fi
} >"$summary"

while read -r ref; do
  [[ -n $ref ]] || continue
  if [[ ! $ref =~ ^(.+)@sha256:([0-9a-f]{64})$ ]]; then
    echo "| \`$ref\` | none | - | - | - | - | - | - | - | not pinned by digest, not scanned |" >>"$summary"
    continue
  fi
  repo=${BASH_REMATCH[1]}
  short=${BASH_REMATCH[2]:0:12}
  dir=$out/${repo##*/}-$short
  mkdir -p "$dir"
  rc=0
  MODE=report OUT=$dir IGNOREFILE=$out/no-exceptions.yaml TRIVY_REPORT='' LIST_ALL_PKGS=true \
    "$here/run.sh" "$ref" >"$dir/run.log" 2>&1 || rc=$?
  if ((rc != 0)); then
    echo "| \`$repo\` | \`$short\` | - | - | - | - | - | - | - | scan did not run (exit $rc), see ${dir##*/}/run.log |" >>"$summary"
    continue
  fi
  jq -r --arg repo "$repo" --arg short "$short" '
    [(.Results // [])[] | (.Vulnerabilities // [])[]] as $v
    | ([(.Results // [])[] | (.Packages // []) | length] | add // 0) as $pkgs
    | def n($s): $v | map(select(.Severity == $s)) | length;
      "| `\($repo)` | `\($short)` | \($pkgs) | \(n("CRITICAL")) | \(n("HIGH")) | \(n("MEDIUM")) | \(n("LOW")) | \(n("UNKNOWN")) | \($v | map(select(.Severity == "CRITICAL" and .Status == "fixed")) | length) | \(if $pkgs == 0 then "no packages found, nothing was checked" else "scanned" end) |"' \
    "$dir/trivy.json" >>"$summary"
done <<<"$refs"

if [[ -z $note ]] && ((count == 0)); then
  echo "- No OCI artifact is enabled by default in this face" >>"$summary"
fi

cat "$summary"
