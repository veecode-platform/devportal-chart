#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB=${LIB:-$HERE/lib.sh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

INDEX_REF=$(yq '.global.catalogIndex.image | .registry + "/" + .repository + ":" + .tag' "$HERE/../charts/backstage/values.yaml")
INDEX_DIGEST=${INDEX_REF##*@}
[[ $INDEX_DIGEST =~ ^sha256:[a-f0-9]{64}$ ]] || {
  printf 'the chart does not pin the catalog index by digest: %s\n' "$INDEX_REF" >&2
  exit 1
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/skopeo" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
image_ref=${@: -1}
if [ "$image_ref" != "docker://$INDEX_REF" ]; then
  printf 'unexpected catalog index reference: %s\n' "$image_ref" >&2
  exit 2
fi
if [ "${CATALOG_INDEX_FAIL:-false}" = true ]; then
  printf 'registry lookup unavailable\n' >&2
  exit 1
fi
printf '%s\n' "${INDEX_REF##*@}"
MOCK
chmod +x "$TMP/bin/skopeo"
PATH="$TMP/bin:$PATH"
export PATH TMP INDEX_REF INDEX_DIGEST
ZERO_SHA=$(printf '0%.0s' {1..64})
ONES_SHA=$(printf '1%.0s' {1..64})
export ZERO_SHA ONES_SHA

mkdir -p "$TMP/chart" "$TMP/releases/chart-v1.2.3-rc.4"
cat > "$TMP/chart/Chart.yaml" <<'EOF'
apiVersion: v2
name: devportal
version: 1.2.3-rc.4
EOF
helm package "$TMP/chart" --destination "$TMP/releases/chart-v1.2.3-rc.4" > /dev/null
PACKAGE=devportal-1.2.3-rc.4.tgz
(cd "$TMP/releases/chart-v1.2.3-rc.4" && sha256sum "$PACKAGE" > "$PACKAGE.sha256")

cat > "$TMP/index.yaml" <<'EOF'
apiVersion: v1
entries:
  devportal:
    - version: 1.2.2-rc.1
    - version: 1.2.2
    - version: 1.2.3-rc.4
    - version: 1.2.3
    - version: 1.2.4
EOF

RELEASES="file://$TMP/releases"
CHART_INDEX="file://$TMP/index.yaml"
export RELEASES_INPUT=$RELEASES
export CHART_INDEX_INPUT=$CHART_INDEX
FAILURES=0

run_case() {
  local name=$1 expected_status=$2 output status=0
  CATALOG_INDEX_FAIL=false
  [ "$name" != manifest-unresolvable ] || CATALOG_INDEX_FAIL=true
  export CATALOG_INDEX_FAIL
  if output=$(CASE="$name" LIB="$LIB" RELEASES="$RELEASES" CHART_INDEX="$CHART_INDEX" OUT="$TMP/out-$name" bash -c '
    set -euo pipefail
    source "$LIB"
    if [ "$CASE" = env-overrides ]; then
      [ "$RELEASES" = "$RELEASES_INPUT" ] && [ "$CHART_INDEX" = "$CHART_INDEX_INPUT" ]
      exit
    fi
    RELEASES=$RELEASES_INPUT
    CHART_INDEX=$CHART_INDEX_INPUT
    case "$CASE" in
      fetch-rc) fetch_release 1.2.3-rc.4 "$OUT/rc" ;;
      fetch-malformed) fetch_release 1.2.3-rc.bad "$OUT/malformed" ;;
      fetch-tampered) fetch_release 1.2.3-rc.4 "$OUT/tampered" ;;
      previous-rc) previous_final 1.2.3-rc.4 ;;
      previous-final) previous_final 1.2.3 ;;
      manifest-pinned-index)
        mkdir -p "$OUT"
        write_qualification_manifest \
          "quay.io/veecode/devportal@sha256:$ZERO_SHA" \
          1.2.3-rc.4 \
          "$ONES_SHA" \
          "$INDEX_REF"
        jq -e --arg ref "$INDEX_REF" \
          --arg digest "$INDEX_DIGEST" \
          ".catalog_index_ref == \$ref and .catalog_index_digest == \$digest" \
          "$OUT/qualification-manifest.json" > /dev/null
        ;;
      manifest-unresolvable)
        mkdir -p "$OUT"
        write_qualification_manifest \
          "quay.io/veecode/devportal@sha256:$ZERO_SHA" \
          1.2.3-rc.4 \
          "$ONES_SHA" \
          "$INDEX_REF"
        ;;
    esac
  ' 2>&1); then
    status=0
  else
    status=$?
  fi

  if [ "$status" != "$expected_status" ]; then
    printf 'FAIL %s: exit=%s, expected=%s\n%s\n' "$name" "$status" "$expected_status" "$output" >&2
    FAILURES=$((FAILURES + 1))
    return
  fi

  case "$name" in
    fetch-rc)
      [[ $output == *"$TMP/out-fetch-rc/rc/$PACKAGE" ]] || {
        printf 'FAIL %s: release package path missing from output\n%s\n' "$name" "$output" >&2
        FAILURES=$((FAILURES + 1))
        return
      }
      ;;
    fetch-malformed)
      [[ $output == *"chart version must be"* ]] || {
        printf 'FAIL %s: malformed version was not rejected at input validation\n%s\n' "$name" "$output" >&2
        FAILURES=$((FAILURES + 1))
        return
      }
      ;;
    fetch-tampered)
      [[ $output == *"does not match"* ]] || {
        printf 'FAIL %s: checksum mismatch did not reject the package\n%s\n' "$name" "$output" >&2
        FAILURES=$((FAILURES + 1))
        return
      }
      ;;
    previous-rc | previous-final)
      [[ $output == 1.2.2 ]] || {
        printf 'FAIL %s: got %s, expected latest final 1.2.2\n' "$name" "$output" >&2
        FAILURES=$((FAILURES + 1))
        return
      }
      ;;
    manifest-unresolvable)
      [[ $output == *"could not resolve catalog index tag"* ]] || {
        printf 'FAIL %s: missing catalog-index lookup failure\n%s\n' "$name" "$output" >&2
        FAILURES=$((FAILURES + 1))
        return
      }
      ;;
  esac

  printf 'PASS %s\n' "$name"
}

run_case env-overrides 0
run_case fetch-rc 0
run_case fetch-malformed 1

printf '%s  %s\n' "$(printf '0%.0s' {1..64})" "$PACKAGE" > "$TMP/releases/chart-v1.2.3-rc.4/$PACKAGE.sha256"
run_case fetch-tampered 1

run_case previous-rc 0
run_case previous-final 0
run_case manifest-pinned-index 0
run_case manifest-unresolvable 1

[ "$FAILURES" -eq 0 ]
