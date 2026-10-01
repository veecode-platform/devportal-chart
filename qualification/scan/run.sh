#!/usr/bin/env bash
# Usage: run.sh IMAGE_REF, where IMAGE_REF ends in @sha256:<digest>.
# Writes OUT/trivy.json (the full report, every severity) and OUT/scan-summary.md.
#
#   MODE           report (default) exits 0 whatever the scan finds. block exits 1 on a critical
#                  vulnerability with a fix that no live exception covers, on a finding of any
#                  severity whose exception has expired, and on an exception file that fails
#                  check-ignorefile.sh.
#   OUT            output directory, default ./scan-out
#   IGNOREFILE     exception file, default .trivyignore.yaml at the repository root
#   TRIVY_BIN_DIR  where the pinned Trivy download is kept
#   TRIVY_REPORT   evaluate this Trivy JSON report of IMAGE_REF instead of scanning
#   LIST_ALL_PKGS  true makes Trivy list every package it parsed, so the report shows what was covered
#
# Exit 2 is a usage error. Exit 3 means the scan did not run (Trivy failed or wrote no
# report); it applies in both modes, so a run cannot pass without a report.
set -euo pipefail

TRIVY_VERSION=0.74.0
# From trivy_0.74.0_checksums.txt of the v0.74.0 release.
TRIVY_SHA256_LINUX_64BIT=2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a
TRIVY_SHA256_LINUX_ARM64=b94ce1976bbf3c15b514b605ee88be7c6d94a29be2302847ff01cb794d47aad5

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/../.." && pwd)
mode=${MODE:-report}
out=${OUT:-scan-out}
ignorefile=${IGNOREFILE:-$root/.trivyignore.yaml}

usage_error() {
  echo "run.sh: $*" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage_error "usage: run.sh IMAGE_REF"
image=$1
[[ $image =~ @sha256:[0-9a-f]{64}$ ]] || usage_error "IMAGE_REF must end in @sha256:<64 hex digits>: $image"
[[ $mode == report || $mode == block ]] || usage_error "MODE must be report or block, got: $mode"
[[ -f $ignorefile ]] || usage_error "exception file not found: $ignorefile"
[[ -z ${TRIVY_REPORT:-} || -f ${TRIVY_REPORT:-} ]] || usage_error "TRIVY_REPORT not found: ${TRIVY_REPORT:-}"
command -v jq >/dev/null || usage_error "jq is required"
if [[ -n ${TRIVY_REPORT:-} ]]; then
  jq -e --arg suffix "@${image##*@}" '([.ArtifactName] + (.Metadata.RepoDigests // [])) | any(. != null and endswith($suffix))' "$TRIVY_REPORT" >/dev/null 2>&1 ||
    usage_error "TRIVY_REPORT is not a Trivy report of $image"
fi

mkdir -p "$out"
report=$out/trivy.json
summary=$out/scan-summary.md
rm -f "$report"

# A vulnerability is blocking when its severity is CRITICAL and its status is
# "fixed". That is what --severity CRITICAL --ignore-unfixed keeps. Findings
# hidden by a live exception are not in .Vulnerabilities; --show-suppressed
# moves them to .ExperimentalModifiedFindings, and Trivy drops an expired
# exception before it matches, so that finding stays in .Vulnerabilities at
# its own severity. It is blocking too, matched by ID against the expired
# entries that check-ignorefile.sh lists.
jq_defs=$(
  cat <<'JQ'
def vulns: [(.Results // [])[] | . as $r | (.Vulnerabilities // [])[] | . + {Location: (if $r.Class == "os-pkgs" then "OS packages" else (.PkgPath // $r.Target) end)}];
def suppressed: [(.Results // [])[] | (.ExperimentalModifiedFindings // [])[] | select(.Type == "vulnerability") | .Finding];
def critical_with_fix: .Severity == "CRITICAL" and .Status == "fixed";
def expired_exception($expired): .VulnerabilityID as $id | $expired | any(. == $id);
def blocking($expired): vulns | map(
  . + {Why: ([(if critical_with_fix then "critical with a fix" else empty end),
              (if expired_exception($expired) then "exception expired" else empty end)] | join(", "))}
  | select(.Why != ""));
JQ
)

find_trivy() {
  if command -v trivy >/dev/null 2>&1 && [[ $(trivy --version 2>/dev/null | sed -n 1p) == "Version: $TRIVY_VERSION" ]]; then
    command -v trivy
    return
  fi
  local dir=${TRIVY_BIN_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/devportal-scan/trivy-$TRIVY_VERSION}
  if [[ ! -x $dir/trivy ]]; then
    local asset sha tmp
    case "$(uname -s)-$(uname -m)" in
      Linux-x86_64) asset=Linux-64bit sha=$TRIVY_SHA256_LINUX_64BIT ;;
      Linux-aarch64 | Linux-arm64) asset=Linux-ARM64 sha=$TRIVY_SHA256_LINUX_ARM64 ;;
      *)
        echo "run.sh: no pinned Trivy for this platform; put Trivy $TRIVY_VERSION on PATH" >&2
        return 1
        ;;
    esac
    tmp=$(mktemp -d) || return 1
    if ! curl -fsSL --retry 3 -o "$tmp/trivy.tar.gz" \
      "https://github.com/aquasecurity/trivy/releases/download/v$TRIVY_VERSION/trivy_${TRIVY_VERSION}_${asset}.tar.gz"; then
      echo "run.sh: could not download Trivy $TRIVY_VERSION" >&2
      rm -rf "$tmp"
      return 1
    fi
    if ! echo "$sha  $tmp/trivy.tar.gz" | sha256sum -c --status; then
      echo "run.sh: the Trivy $TRIVY_VERSION download does not match the pinned checksum" >&2
      rm -rf "$tmp"
      return 1
    fi
    mkdir -p "$dir"
    if ! tar -xzf "$tmp/trivy.tar.gz" -C "$dir" trivy; then
      rm -rf "$tmp"
      return 1
    fi
    rm -rf "$tmp"
  fi
  echo "$dir/trivy"
}

list_pkgs=()
[[ ${LIST_ALL_PKGS:-false} == true ]] && list_pkgs+=(--list-all-pkgs)
scan_error=
scan_seconds=
scanner="not run, the report was supplied with TRIVY_REPORT"

scan() {
  local trivy db_updated
  SECONDS=0
  trivy=$(find_trivy) || {
    scan_error="could not get Trivy $TRIVY_VERSION"
    return 1
  }
  "$trivy" image \
    --image-src remote --scanners vuln --timeout 10m \
    --no-progress --skip-version-check \
    --format json --output "$report" \
    "${list_pkgs[@]}" \
    --ignorefile "$ignorefile" --show-suppressed \
    "$image" || {
    scan_error="Trivy exited with an error"
    return 1
  }
  scan_seconds=$SECONDS
  db_updated=$("$trivy" version --format json | jq -r '.VulnerabilityDB.UpdatedAt // "unknown"') || db_updated=unknown
  scanner="Trivy $TRIVY_VERSION, vulnerability database updated $db_updated"
}

expired_file=$out/expired-ids.txt
: >"$expired_file"
ignore_check=PASS
"$here/check-ignorefile.sh" "$ignorefile" "$expired_file" || ignore_check=FAIL
expired_ids=$(jq -Rn '[inputs | select(. != "")]' <"$expired_file")

if [[ -n ${TRIVY_REPORT:-} ]]; then
  cp "$TRIVY_REPORT" "$report"
else
  scan || true
fi

if [[ -z $scan_error ]] && ! jq -e 'type == "object" and has("SchemaVersion")' "$report" >/dev/null 2>&1; then
  scan_error="the report is not a Trivy JSON report"
fi

blocking_count=0
if [[ -z $scan_error ]]; then
  blocking_count=$(jq -r --argjson expired "$expired_ids" "$jq_defs blocking(\$expired) | length" "$report")
fi

report_note=
[[ $mode == report ]] && report_note=" (report mode, the run does not fail)"

{
  echo "# Vulnerability scan"
  echo
  echo "- Image: \`$image\`"
  echo "- Scanner: $scanner"
  [[ -z $scan_seconds ]] || echo "- Scan time: $scan_seconds s (Trivy download, vulnerability database update and scan)"
  echo "- Mode: $mode"
  echo "- Exception file: \`${ignorefile#"$root"/}\`, check $ignore_check"
  if [[ -n $scan_error ]]; then
    echo "- Gate: FAIL, the scan did not complete: $scan_error"
  else
    jq -r '(.Metadata // {}) as $m
      | (if $m.ImageConfig.architecture then "- Platform: \($m.ImageConfig.os // "linux")/\($m.ImageConfig.architecture)" else empty end),
        (if $m.OS then "- Base OS: \($m.OS.Family) \($m.OS.Name)" else empty end)' "$report"
    jq -r --argjson expired "$expired_ids" "$jq_defs"'
      "- Critical vulnerabilities with a fix and no live exception: \(vulns | map(select(critical_with_fix)) | length)",
      "- Findings that match an expired exception: \(vulns | map(select(expired_exception($expired))) | length)"' "$report"
    if [[ $blocking_count -eq 0 && $ignore_check == PASS ]]; then gate=PASS; else gate=FAIL; fi
    echo "- Gate: $gate$report_note"
    echo
    echo "## Findings by severity"
    echo
    echo "| Severity | Reported | With a fix | Suppressed by an exception |"
    echo "| --- | ---: | ---: | ---: |"
    jq -r "$jq_defs"'
      ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"][] as $s
      | "| \($s) | \(vulns | map(select(.Severity == $s)) | length) | \(vulns | map(select(.Severity == $s and .Status == "fixed")) | length) | \(suppressed | map(select(.Severity == $s)) | length) |"' "$report"
    jq -r "$jq_defs"'
      "| Total | \(vulns | length) | \(vulns | map(select(.Status == "fixed")) | length) | \(suppressed | length) |"' "$report"
    if ((blocking_count > 0)); then
      echo
      echo "## Blocking vulnerabilities"
      echo
      echo "| ID | Package | Severity | Installed | Fixed in | Location | Why |"
      echo "| --- | --- | --- | --- | --- | --- | --- |"
      jq -r --argjson expired "$expired_ids" "$jq_defs"'
        blocking($expired) | sort_by(.PkgName, .VulnerabilityID)[]
        | "| \(.VulnerabilityID) | \(.PkgName) | \(.Severity) | \(.InstalledVersion) | \(.FixedVersion // "none") | \(.Location) | \(.Why) |"' "$report"
    fi
    if [[ $(jq -r "$jq_defs suppressed | length" "$report") -gt 0 ]]; then
      echo
      echo "## Suppressed by an exception"
      echo
      echo "| ID | Package | Severity | Statement |"
      echo "| --- | --- | --- | --- |"
      jq -r '
        [(.Results // [])[] | (.ExperimentalModifiedFindings // [])[] | select(.Type == "vulnerability")]
        | sort_by(.Finding.VulnerabilityID)[]
        | "| \(.Finding.VulnerabilityID) | \(.Finding.PkgName) | \(.Finding.Severity) | \(.Statement) |"' "$report"
    fi
  fi
} >"$summary"
cat "$summary"

if [[ -n $scan_error ]]; then
  echo "run.sh: the scan did not run: $scan_error" >&2
  exit 3
fi
[[ $mode == block ]] || exit 0
if [[ $ignore_check == FAIL || $blocking_count -gt 0 ]]; then
  echo "run.sh: MODE=block fails (exception check $ignore_check, blocking vulnerabilities $blocking_count)" >&2
  exit 1
fi
