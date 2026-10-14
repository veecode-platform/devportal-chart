#!/usr/bin/env bash
# Says what a pull request asks the qualification to do, by comparing it with its base.
#
#   pr-scope.sh BASE_SHA
#
# Prints one word on stdout and the reason on stderr:
#   pins            the pull request changes the pinned portal image (upstream.backstage.image) or
#                   the pinned catalog index (global.catalogIndex.image) in
#                   charts/backstage/values.yaml: qualify the candidate chart
#   qualification   it changes neither pin but changes a file under qualification/ or the
#                   qualification workflow: self-test the qualification
#   nothing         it changes none of them: nothing to qualify
# Run it at the root of the checkout. Needs git and yq.
set -euo pipefail

BASE=$1
VALUES=charts/backstage/values.yaml
say() { echo "$*" >&2; }

base_values=$(mktemp)
trap 'rm -f "$base_values"' EXIT
git show "$BASE:$VALUES" > "$base_values"

# Succeeds when the pull request leaves the value at the yq path as the base has it.
same() { [ "$(yq -o=json -I=0 "$1" "$base_values")" = "$(yq -o=json -I=0 "$1" "$VALUES")" ]; }

image_moved=false
index_moved=false
same '.upstream.backstage.image' || image_moved=true
same '.global.catalogIndex.image' || index_moved=true

if [ "$image_moved" = true ] || [ "$index_moved" = true ]; then
  [ "$image_moved" = false ] || say "The pinned image changed."
  [ "$index_moved" = false ] || say "The pinned catalog index changed."
  echo pins
elif [ -n "$(git diff --name-only "$BASE" HEAD -- qualification .github/workflows/qualification.yaml)" ]; then
  say "No pin moved, and the qualification changed."
  echo qualification
else
  say "Neither a pinned image or catalog index nor the qualification changed."
  echo nothing
fi
