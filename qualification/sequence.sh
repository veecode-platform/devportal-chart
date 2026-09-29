#!/usr/bin/env bash
# Qualifies a devportal chart candidate against the previous final chart.
# README.md lists the steps and what each one asserts.
set -euo pipefail
# shellcheck source=qualification/lib.sh
source "$(dirname "$0")/lib.sh"

GOOD_PACKAGE=${GOOD_PACKAGE:-rhdh/backstage-community-plugin-todo-backend}
GOOD_PLUGIN=${GOOD_PLUGIN:-@backstage-community/plugin-todo-backend-dynamic}
FACE_FILE=/opt/app-root/src/dynamic-plugins.veecode.yaml
VALUES=$HERE/values/sequence.yaml
FIXTURE_ARTIFACT=$(yq '.spec.dynamicArtifact' "$HERE/fixtures/broken-package.yaml")
CATALOG_ERRORS='Policy check failed for package:|while validating the entity package:|entity="package:'
DONE=false

finish() {
  local rc=$?
  [ -z "$PF" ] || kill "$PF" 2> /dev/null || true
  collect_diagnostics
  [ "$DONE" = true ] || record end "the sequence ran to the end" "" 0 "stopped with exit code $rc, see steps.log"
  printf '\n%s check(s) failed.\n' "$FAILED" >> "$OUT/summary.md"
}
trap finish EXIT

portal_image() {
  helm show values "$1" > "$OUT/values-$2.yaml"
  yq '.upstream.backstage.image | .registry + "/" + .repository + "@" + .digest' "$OUT/values-$2.yaml"
}

storage_mode() {
  if grep -qF 'falling back to file storage' "$1"; then
    echo "file fallback"
  elif grep -qF 'Marketplace installation service initialized (database-backed)' "$1"; then
    echo database
  else
    echo "no storage line"
  fi
}

change_package() {
  local step=$1 package=$2 artifact=$3 disabled=$4 tag=$5 code stored
  code=$(set_disabled "$package" "$disabled" "$tag")
  assert "$step" "set $package disabled=$disabled through the marketplace" "" "HTTP $code" test "$code" = 200
  if [ "$disabled" = false ]; then
    api pending-changes > "$OUT/pending-$tag.json"
    assert "$step" "$package is in pendingInstalls" "" "$(jq -c '.pendingInstalls' "$OUT/pending-$tag.json")" \
      json_true "$OUT/pending-$tag.json" --arg a "$artifact" ".pendingInstalls | any(.[]; . == \$a)"
  else
    # Chart 0.1.24, which runs at the rollback, does not list a selector-less OCI row in pendingRemovals.
    stored=$(sql backstage_plugin_extensions "select disabled from marketplace_installations where package_name = '$artifact'")
    assert "$step" "the row of $package is stored as disabled" "" "disabled=${stored:-no row}" test "$stored" = t
  fi
}

check_loaded_plugins() {
  local tag=$1 step=$2 pod face code=0 detail
  pod=$(portal_pod)
  face="kubectl -n $NS exec $pod -c backstage-backend -- cat $FACE_FILE"
  FACE_CMD=$face LOGS_CMD="kubectl -n $NS logs $pod -c install-dynamic-plugins" DEVPORTAL_URL=$URL \
    sh "$LOADED_PLUGINS_CHECK" > "$OUT/loaded-plugins-check-$tag.txt" 2>&1 || code=$?
  detail=$({ grep -E 'found in API|FAIL' "$OUT/loaded-plugins-check-$tag.txt" || true; } | sed 's/^loaded plugins check: //' | paste -sd ';' -)
  assert "$step" "every enabled plugin of the product face is loaded" "" "${detail:-no output}" test "$code" -eq 0
}

check_catalog() {
  local tag=$1 step=$2 ref index missing extra errors
  ref=$("${K[@]}" get deploy "$DEPLOY" -o json |
    jq -r '.spec.template.spec.initContainers[] | select(.name == "install-dynamic-plugins") | .env[] | select(.name == "CATALOG_INDEX_IMAGE") | .value')
  if index=$(index_packages "$ref"); then
    assert "$step" "the catalog index image can be read" "" "$(wc -l < "$index") packages in $ref" true
  else
    record "$step" "the catalog index image can be read" "" 0 "$ref could not be fetched or lists no package, see steps.log"
    return 0
  fi
  jq -r '.items[] | (.metadata.namespace // "default") + "/" + .metadata.name' "$OUT/packages-$tag.json" |
    sort -u > "$OUT/served-$tag.txt"
  { cat "$index"; echo "$FIXTURE_PACKAGE"; } | sort -u > "$OUT/expected-$tag.txt"
  comm -23 "$OUT/expected-$tag.txt" "$OUT/served-$tag.txt" > "$OUT/not-served-$tag.txt"
  comm -13 "$OUT/expected-$tag.txt" "$OUT/served-$tag.txt" > "$OUT/unexpected-$tag.txt"
  missing=$(wc -l < "$OUT/not-served-$tag.txt")
  extra=$(wc -l < "$OUT/unexpected-$tag.txt")
  assert "$step" "the broken package is served" "" "$FIXTURE_PACKAGE" grep -qxF "$FIXTURE_PACKAGE" "$OUT/served-$tag.txt"
  assert "$step" "the portal serves every package of the index" catalog-fixes \
    "$(wc -l < "$OUT/served-$tag.txt") served, $(wc -l < "$index") in $ref plus the fixture; $missing not served, $extra unexpected" \
    test "$((missing + extra))" -eq 0
  errors=$(grep -cE "$CATALOG_ERRORS" "$OUT/backend-$tag.log" || true)
  assert "$step" "no package fails catalog validation in the backend log" catalog-fixes "$errors line(s)" test "$errors" -eq 0
}

check_artifacts() {
  local tag=$1 step=$2 total missing errors first
  jq -r --arg f "$FIXTURE_ARTIFACT" '.items[].spec.dynamicArtifact // empty | select(. != $f)' "$OUT/packages-$tag.json" |
    sort -u > "$OUT/offered-$tag.txt"
  resolve_artifacts "$OUT/offered-$tag.txt" > "$OUT/artifacts-$tag.tsv"
  awk -F'\t' '$2 != "resolves"' "$OUT/artifacts-$tag.tsv" > "$OUT/unresolved-$tag.txt"
  total=$(wc -l < "$OUT/offered-$tag.txt")
  missing=$(wc -l < "$OUT/unresolved-$tag.txt")
  errors=$(awk -F'\t' '$2 == "error"' "$OUT/artifacts-$tag.tsv" | wc -l)
  first=$(awk -F'\t' '$2 == "error" { print $1 ": " $3; exit }' "$OUT/artifacts-$tag.tsv")
  assert "$step" "every registry lookup got an answer" "" "$errors error(s)${first:+, first: $first}" test "$errors" -eq 0
  assert "$step" "the portal offers artifacts to resolve" "" "$total offered" test "$total" -gt 0
  assert "$step" "every offered artifact resolves" catalog-fixes "$((total - missing)) of $total resolve" test "$missing" -eq 0
}

check_prestep() {
  local tag=$1 step=$2 phase=$3 line
  local re='digest-pinned ([0-9]+) of ([0-9]+) selection\(s\) \(([0-9]+) non-OCI, ([0-9]+) skipped, ([0-9]+) disabled\)'
  line=$(grep -F 'VEECODE prestep: digest-pinned' "$OUT/init-$tag.log" | tail -1 || true)
  if [[ $line =~ $re ]]; then
    assert "$step" "the pre-step summary counts every row" prestep-skip "${BASH_REMATCH[0]}" \
      test $((BASH_REMATCH[1] + BASH_REMATCH[3] + BASH_REMATCH[4] + BASH_REMATCH[5])) -eq "${BASH_REMATCH[2]}"
  else
    record "$step" "the pre-step summary counts every row" prestep-skip 0 "${line:-no summary line}"
  fi
  if [ "$phase" = broken ]; then
    assert "$step" "the pre-step skips the broken package" prestep-skip "$(grep -c 'VEECODE prestep: WARNING' "$OUT/init-$tag.log" || true) warning(s)" \
      grep -qE 'VEECODE prestep: WARNING .*skipping "[^"]*qualification-broken-plugin' "$OUT/init-$tag.log"
  fi
}

check_broken_restart() {
  local tag=$1 step=$2 column digest='' detail
  # shellcheck disable=SC2016 # $a is a jq variable.
  assert "$step" "the broken package is in failedInstalls" marketplace-backend \
    "failedInstalls: $(jq -c '.failedInstalls // "absent"' "$OUT/pending-$tag.json")" \
    json_true "$OUT/pending-$tag.json" --arg a "$FIXTURE_ARTIFACT" '(.failedInstalls // []) | any(.[]; . == $a)'
  column=$(sql backstage_plugin_extensions "select count(*) from information_schema.columns where table_name = 'marketplace_installations' and column_name = 'resolved_digest'")
  if [ "$column" = 0 ]; then
    detail="the column does not exist"
  else
    digest=$(sql backstage_plugin_extensions "select coalesce(resolved_digest, '') from marketplace_installations where package_name = '$GOOD_ARTIFACT'")
    detail=${digest:-empty}
  fi
  assert "$step" "the good row holds resolved_digest" marketplace-backend "$detail" test -n "$digest"
}

# $1 tag for the saved files, $2 step label, $3 absent or loaded (the good plugin),
# $4 previous, candidate, or broken (the candidate with the broken package installed).
observe() {
  local tag=$1 step=$2 good=$3 phase=$4 found want=0 needs='' mode
  connect
  wait_catalog "$tag"
  collect "$tag"
  log_resources "$step"
  [ "$good" = absent ] || want=1
  [ "$phase" != broken ] || needs=prestep-skip
  found=$(jq --arg n "$GOOD_PLUGIN" '[.[] | select(.name == $n)] | length' "$OUT/loaded-$tag.json")
  assert "$step" "$GOOD_PLUGIN is $good" "$needs" "$(jq length "$OUT/loaded-$tag.json") plugins loaded" test "$found" -eq "$want"
  check_loaded_plugins "$tag" "$step"
  mode=$(storage_mode "$OUT/backend-$tag.log")
  assert "$step" "the marketplace uses its database" "" "$mode" test "$mode" = database
  check_catalog "$tag" "$step"
  check_artifacts "$tag" "$step"
  [ "$phase" = previous ] || check_prestep "$tag" "$step" "$phase"
  [ "$phase" != broken ] || check_broken_restart "$tag" "$step"
}

[ -f "${LOADED_PLUGINS_CHECK:-}" ] || fail "set LOADED_PLUGINS_CHECK to scripts/check-loaded-plugins.sh of devportal-local"
if [ -n "${CANDIDATE_VERSION:-}" ]; then
  CANDIDATE_CHART=$(fetch_release "$CANDIDATE_VERSION" "$OUT/candidate")
fi
[ -n "${CANDIDATE_CHART:-}" ] || fail "set CANDIDATE_CHART to a chart directory or package, or CANDIDATE_VERSION to a published version"
CAND=$(chart_field "$CANDIDATE_CHART" version)
PREV=$(previous_final "$CAND")
[ -n "$PREV" ] || fail "no final chart older than $CAND in $CHART_INDEX"
PREVIOUS_CHART=$(fetch_release "$PREV" "$OUT/previous")
if [ "$SELF_TEST" = true ]; then RUN=self-test; else RUN=full; fi
summary_header "Candidate devportal $CAND from $CANDIDATE_CHART, previous final chart $PREV, $RUN run. A self-test reports as SKIP each check tagged with a change the candidate may lack: prestep-skip, marketplace-backend or catalog-fixes, described in qualification/README.md."

setup_database
serve_fixture
FIXTURE_ANSWER=$(resolve_oci "$FIXTURE_ARTIFACT")
assert start "the broken package's artifact does not exist" "" "$FIXTURE_ARTIFACT: $(cut -f2- <<< "$FIXTURE_ANSWER" | tr '\t' ' ')" \
  test "$(cut -f2 <<< "$FIXTURE_ANSWER")" = missing

S1="1 install $PREV"
log "$S1"
node_pull "$(portal_image "$PREVIOUS_CHART" previous)"
helm install "$RELEASE" "$PREVIOUS_CHART" -n "$NS" -f "$VALUES" --timeout 20m > "$OUT/helm-install.log" 2>&1
wait_portal install
observe s1 "$S1" absent previous
GOOD_ARTIFACT=$(api "package/$GOOD_PACKAGE" | jq -r '.spec.dynamicArtifact')
change_package "$S1" "$GOOD_PACKAGE" "$GOOD_ARTIFACT" false s1-install

S2="2 restart on $PREV"
log "$S2"
restart_portal s2
observe s2 "$S2" loaded previous
backup_databases

S3="3 upgrade to $CAND"
log "$S3"
node_pull "$(portal_image "$CANDIDATE_CHART" candidate)"
helm upgrade "$RELEASE" "$CANDIDATE_CHART" -n "$NS" -f "$VALUES" --timeout 20m > "$OUT/helm-upgrade.log" 2>&1
wait_portal upgrade
observe s3 "$S3" loaded candidate
change_package "$S3" "$FIXTURE_PACKAGE" "$FIXTURE_ARTIFACT" false s3-install

S4="4 restart on $CAND"
log "$S4"
restart_portal s4a
observe s4a "$S4" loaded broken
restart_portal s4b
observe s4b "4 second restart on $CAND" loaded broken

S5="5 rollback to $PREV"
log "$S5: stop the portal, restore the backup, roll back"
stop_portal
restore_databases
helm rollback "$RELEASE" 1 -n "$NS" --wait --timeout 20m > "$OUT/helm-rollback.log" 2>&1
if [ "$("${K[@]}" get deploy "$DEPLOY" -o jsonpath='{.spec.replicas}')" = 0 ]; then
  log "helm rollback left $DEPLOY at 0 replicas; scaling it to 1"
  "${K[@]}" scale "deploy/$DEPLOY" --replicas=1 > /dev/null
fi
wait_portal rollback
observe s5 "$S5" loaded previous
ROWS=$(sql backstage_plugin_extensions "select count(*) from marketplace_installations where package_name = '$FIXTURE_ARTIFACT'")
assert "$S5" "the restore removed the broken package's row" "" "$ROWS row(s)" test "$ROWS" = 0
change_package "$S5" "$GOOD_PACKAGE" "$GOOD_ARTIFACT" true s5-change

S6="6 restart after the marketplace change"
log "$S6"
restart_portal s6
observe s6 "$S6" absent previous

DONE=true
[ "$FAILED" -eq 0 ]
