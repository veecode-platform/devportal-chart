#!/usr/bin/env bash
# Decides whether a pull request that moves the pinned image is a release pull request whose
# image is already qualified, so the run need not qualify the same chart again.
#
#   prior-qualification.sh BASE_SHA
#
# Prints the id of a successful Qualification run and exits 0 when all of these hold:
#   - against BASE_SHA, the pull request changes only release fields under charts/backstage:
#     Chart.yaml version and appVersion, the image tag and digest in values.yaml, the schema
#     defaults that mirror them, and the generated README.md; nothing under qualification/
#     or in this workflow changes;
#   - a successful run, newest first among the last 50 on main, qualified this digest as an
#     image (an image_tag dispatch or the nightly), not a published chart: its scope job logged
#     "Qualify the image ... at <digest>", and its manifest recorded the same digest;
#   - that run was a dispatch or the nightly on main at a commit that BASE_SHA contains, so
#     trusted code ran it; pull_request runs, which a fork controls, never count;
#   - that commit has the same charts/backstage as BASE_SHA, so the chart it built its
#     candidate from is this pull request's chart apart from the release fields.
# Exits 1 with the reason on stderr otherwise. Needs gh with actions:read, git, yq and jq.
set -euo pipefail

BASE=$1
CHART=charts/backstage
WORKFLOW=qualification.yaml
say() { echo "$*" >&2; }

changed=$(git diff --name-only "$BASE" HEAD -- "$CHART" qualification .github/workflows/qualification.yaml)
allowed="$CHART/Chart.yaml $CHART/values.yaml $CHART/values.schema.json $CHART/README.md"
for f in $changed; do
  case " $allowed " in
    *" $f "*) ;;
    *) say "$f changed, which a release pull request does not touch"; exit 1 ;;
  esac
done

base_file() { git show "$BASE:$CHART/$1"; }
same() { [ "$(base_file "$1" | yq -o=json -I=0 "$2")" = "$(yq -o=json -I=0 "$2" "$CHART/$1")" ]; }
same Chart.yaml 'del(.version, .appVersion)' ||
  { say "Chart.yaml changes more than version and appVersion"; exit 1; }
same values.yaml 'del(.upstream.backstage.image.tag, .upstream.backstage.image.digest)' ||
  { say "values.yaml changes more than the image tag and digest"; exit 1; }

image_field() { yq ".upstream.backstage.image.$1" "$2"; }
base_values=$(mktemp)
trap 'rm -f "$base_values"' EXIT
base_file values.yaml > "$base_values"
old_tag=$(image_field tag "$base_values") old_digest=$(image_field digest "$base_values")
tag=$(image_field tag "$CHART/values.yaml") digest=$(image_field digest "$CHART/values.yaml")
schema_now=$(jq -cS . "$CHART/values.schema.json")
schema_base=$(base_file values.schema.json | jq -cS --arg ot "$old_tag" --arg t "$tag" --arg od "$old_digest" --arg d "$digest" \
  'walk(if . == $ot then $t elif . == $od then $d else . end)')
[ "$schema_now" = "$schema_base" ] ||
  { say "values.schema.json changes more than the image defaults"; exit 1; }
[[ $digest =~ ^sha256:[a-f0-9]{64}$ ]] || { say "no pinned digest in $CHART/values.yaml"; exit 1; }

dir=$(mktemp -d)
trap 'rm -rf "$dir" "$base_values"' EXIT
for row in $(gh run list --workflow "$WORKFLOW" --branch main --status success --limit 50 \
  --json databaseId,headSha,event --jq '.[] | "\(.databaseId):\(.headSha):\(.event)"'); do
  IFS=: read -r run sha event <<< "$row"
  case $event in workflow_dispatch | schedule) ;; *) continue ;; esac
  git cat-file -e "$sha^{commit}" 2> /dev/null || continue
  git merge-base --is-ancestor "$sha" "$BASE" || continue
  git diff --quiet "$sha" "$BASE" -- "$CHART" || continue
  scope_job=$(gh api "repos/{owner}/{repo}/actions/runs/$run/jobs" \
    --jq '.jobs[] | select(.name == "Decide what the run qualifies") | .id') || continue
  scope_log=$(gh api "repos/{owner}/{repo}/actions/jobs/$scope_job/logs" 2> /dev/null) || continue
  grep -F "Qualify the image docker.io/veecode/devportal:" <<< "$scope_log" |
    grep -qF " at $digest with the chart at this ref." || continue
  rm -rf "${dir:?}/$run"
  gh run download "$run" --name qualification-sequence --dir "$dir/$run" > /dev/null 2>&1 || continue
  [ "$(jq -r '.image_digest // ""' "$dir/$run/qualification-manifest.json" 2> /dev/null)" = "$digest" ] || continue
  say "run $run ($event on main) qualified the image $digest with the chart of $BASE"
  echo "$run"
  exit 0
done
say "no image qualification on main among the last 50 successful runs matches $digest and the chart of $BASE"
exit 1
