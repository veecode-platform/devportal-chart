#!/usr/bin/env bash
# Checks what a pull request asks the qualification to do, in throwaway repositories with no
# network: pr-scope.sh classifies a change, and prior-qualification.sh refuses to call a
# release pull request qualified when it re-pins the catalog index.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REPO=$TMP/repo
export GH_LOG=$TMP/gh.log
FAILURES=0

hex() {
  local out=
  for _ in $(seq 64); do out+=$1; done
  printf '%s' "$out"
}
OLD_DIGEST=sha256:$(hex b)
NEW_DIGEST=sha256:$(hex c)

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_LOG"
STUB
chmod +x "$TMP/bin/gh"
PATH="$TMP/bin:$PATH"

git_in() { git -C "$REPO" -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=test -c user.email=test@example.test "$@"; }

mkdir -p "$REPO/charts/backstage" "$REPO/qualification" "$REPO/.github/workflows" "$REPO/docs"
cat > "$REPO/charts/backstage/Chart.yaml" <<EOF
apiVersion: v2
name: devportal
version: 1.0.4
appVersion: 3.0.3
EOF
cat > "$REPO/charts/backstage/values.yaml" <<EOF
global:
  host: example.test
  catalogIndex:
    image:
      registry: quay.io
      repository: veecode/plugin-catalog-index@sha256
      tag: "$(hex a)"
upstream:
  backstage:
    image:
      registry: docker.io
      repository: veecode/devportal
      tag: 3.0.3
      digest: $OLD_DIGEST
      pullPolicy: IfNotPresent
EOF
printf '{"tag":"3.0.3","digest":"%s"}\n' "$OLD_DIGEST" > "$REPO/charts/backstage/values.schema.json"
echo "generated readme" > "$REPO/charts/backstage/README.md"
echo "#!/usr/bin/env bash" > "$REPO/qualification/sequence.sh"
echo "name: Qualification" > "$REPO/.github/workflows/qualification.yaml"
echo "notes" > "$REPO/docs/notes.md"
git -C "$REPO" init -q -b main
git_in add -A
git_in commit -q -m base
BASE=$(git_in rev-parse HEAD)

# The image moves the way a release pull request moves it: version, tag, digest, schema defaults.
move_image() {
  yq -i '.version = "1.0.5" | .appVersion = "3.0.4"' "$REPO/charts/backstage/Chart.yaml"
  yq -i ".upstream.backstage.image.tag = \"3.0.4\" | .upstream.backstage.image.digest = \"$NEW_DIGEST\"" "$REPO/charts/backstage/values.yaml"
  printf '{"tag":"3.0.4","digest":"%s"}\n' "$NEW_DIGEST" > "$REPO/charts/backstage/values.schema.json"
}
move_image_digest() { yq -i ".upstream.backstage.image.digest = \"$NEW_DIGEST\"" "$REPO/charts/backstage/values.yaml"; }
move_image_registry() { yq -i '.upstream.backstage.image.registry = "quay.io"' "$REPO/charts/backstage/values.yaml"; }
move_index() { yq -i ".global.catalogIndex.image.tag = \"$(hex d)\"" "$REPO/charts/backstage/values.yaml"; }
touch_qualification_file() { echo "# changed" >> "$REPO/qualification/sequence.sh"; }
touch_workflow() { echo "# changed" >> "$REPO/.github/workflows/qualification.yaml"; }
touch_unrelated() {
  echo "more notes" >> "$REPO/docs/notes.md"
  yq -i '.global.host = "other.example.test"' "$REPO/charts/backstage/values.yaml"
  yq -i '.version = "1.0.5"' "$REPO/charts/backstage/Chart.yaml"
}

# $1 case name, $2 what to run on the branch, $3 script, $4 expected exit status, $5 expected
# stdout, $6 text the stderr must hold, $7 whether the script must have asked gh for runs.
check() {
  local name=$1 change=$2 script=$3 want_status=$4 want_out=$5 want_err=$6 want_gh=$7 out status=0 gh_calls
  git_in checkout -q -B "$name" "$BASE"
  # shellcheck disable=SC2086 # $change is a function name followed by none, one or more of them.
  for fn in $change; do "$fn"; done
  git_in add -A
  git_in commit -q -m "$name"
  : > "$GH_LOG"
  out=$(cd "$REPO" && bash "$HERE/$script" "$BASE" 2> "$TMP/stderr") || status=$?
  gh_calls=$(wc -l < "$GH_LOG")
  if [ "$status" != "$want_status" ] || [ "$out" != "$want_out" ] || ! grep -qF "$want_err" "$TMP/stderr"; then
    printf 'FAIL %s: exit=%s stdout=[%s] stderr=[%s], expected exit=%s stdout=[%s] stderr holding [%s]\n' \
      "$name" "$status" "$out" "$(tr '\n' ' ' < "$TMP/stderr")" "$want_status" "$want_out" "$want_err" >&2
    FAILURES=$((FAILURES + 1))
  elif { [ "$want_gh" = asked ] && [ "$gh_calls" = 0 ]; } || { [ "$want_gh" = not-asked ] && [ "$gh_calls" != 0 ]; }; then
    printf 'FAIL %s: gh was called %s time(s), expected %s\n' "$name" "$gh_calls" "$want_gh" >&2
    FAILURES=$((FAILURES + 1))
  else
    printf 'PASS %s\n' "$name"
  fi
}

check scope-image-changed move_image pr-scope.sh 0 pins "The pinned image changed." any
check scope-image-digest-only move_image_digest pr-scope.sh 0 pins "The pinned image changed." any
check scope-image-registry-only move_image_registry pr-scope.sh 0 pins "The pinned image changed." any
check scope-index-changed move_index pr-scope.sh 0 pins "The pinned catalog index changed." any
check scope-image-and-index-changed "move_image move_index" pr-scope.sh 0 pins "The pinned catalog index changed." any
check scope-pin-and-qualification-changed "move_index touch_qualification_file" pr-scope.sh 0 pins "The pinned catalog index changed." any
check scope-qualification-file-changed touch_qualification_file pr-scope.sh 0 qualification "No pin moved, and the qualification changed." any
check scope-qualification-and-chart-changed "touch_unrelated touch_qualification_file" pr-scope.sh 0 qualification "No pin moved, and the qualification changed." any
check scope-workflow-changed touch_workflow pr-scope.sh 0 qualification "No pin moved, and the qualification changed." any
check scope-nothing-changed touch_unrelated pr-scope.sh 0 nothing "nor the qualification changed" any

check prior-image-only move_image prior-qualification.sh 1 "" "no image qualification on main" asked
check prior-index-only move_index prior-qualification.sh 1 "" "re-pins the catalog index" not-asked
check prior-image-and-index "move_image move_index" prior-qualification.sh 1 "" "re-pins the catalog index" not-asked

[ "$FAILURES" -eq 0 ]
