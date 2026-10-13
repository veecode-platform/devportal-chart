#!/usr/bin/env bash
# Checks the guest sign-in assertion of the sequence against a curl that answers like a portal
# with guest sign-in on or off: a check that wants no token must fail when the
# portal still issues one, and one that wants a token must fail when it does not.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
FAILURES=0

mkdir -p "$TMP/bin"
cat > "$TMP/bin/curl" <<'MOCK'
#!/usr/bin/env bash
out=
while [ $# -gt 0 ]; do
  [ "$1" != -o ] || { out=$2; shift; }
  shift
done
printf '%s' "$MOCK_BODY" > "$out"
printf '%s' "$MOCK_STATUS"
MOCK
chmod +x "$TMP/bin/curl"
PATH="$TMP/bin:$PATH"
export PATH

TOKEN_BODY='{"backstageIdentity":{"token":"issued"},"profile":{}}'
NOT_FOUND_BODY='{"error":{"name":"NotFoundError","message":"Unknown auth provider guest"}}'

# $1 case name, $2 HTTP status, $3 response body, $4 yes or no (what the check wants),
# $5 PASS or FAIL (what the check must record), $6 the detail it must record.
run_case() {
  local name=$1 status=$2 body=$3 want=$4 result=$5 detail=$6 row
  row=$(MOCK_STATUS=$status MOCK_BODY=$body OUT="$TMP/out-$name" LIB="$HERE/lib.sh" WANT=$want bash -c '
    set -euo pipefail
    source "$LIB"
    check_guest_signin step "guest sign-in check" "$WANT"
    tail -1 "$OUT/summary.md"
  ' 2> /dev/null) || {
    printf 'FAIL %s: the check stopped the script\n' "$name" >&2
    FAILURES=$((FAILURES + 1))
    return
  }
  if [[ $row == *"| $result | $detail |" ]]; then
    printf 'PASS %s\n' "$name"
  else
    printf 'FAIL %s: expected %s with "%s", got: %s\n' "$name" "$result" "$detail" "$row" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

run_case still-issues-token-fails-the-off-check 200 "$TOKEN_BODY" no FAIL "HTTP 200"
run_case refusal-passes-the-off-check 404 "$NOT_FOUND_BODY" no PASS "HTTP 404"
run_case error-page-passes-the-off-check 502 "<html>Bad Gateway</html>" no PASS "HTTP 502"
run_case answer-without-token-passes-the-off-check 200 '{"backstageIdentity":{}}' no PASS "HTTP 200"
run_case token-passes-the-on-check 200 "$TOKEN_BODY" yes PASS "HTTP 200"
run_case refusal-fails-the-on-check 404 "$NOT_FOUND_BODY" yes FAIL "HTTP 404"

[ "$FAILURES" -eq 0 ]
