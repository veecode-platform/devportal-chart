#!/usr/bin/env bash
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
LIB=${LIB:-$HERE/lib.sh}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

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

[ "$FAILURES" -eq 0 ]
