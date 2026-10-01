# shellcheck shell=bash
# Sourced by sequence.sh.

NS=${NS:-devportal}
RELEASE=dp
DEPLOY=dp-developer-hub
SEL=app.kubernetes.io/component=backstage
NODE=${KIND_NODE:-qualification-control-plane}
OUT=${OUT:-/tmp/qualification}
SELF_TEST=${SELF_TEST:-false}
PORT=${PORT:-17007}
URL=http://localhost:$PORT
CHART_INDEX=${CHART_INDEX:-https://veecode-platform.github.io/next-charts/index.yaml}
RELEASES=${RELEASES:-https://github.com/veecode-platform/devportal-chart/releases/download}
POSTGRES_IMAGE=docker.io/library/postgres:16
FIXTURES_IMAGE=registry.k8s.io/e2e-test-images/busybox:1.36.1-1@sha256:a9155b13325b2abef48e71de77bb8ac015412a566829f621d06bfae5c699b1b9
FIXTURE_PACKAGE=default/qualification-broken-plugin
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
K=(kubectl -n "$NS")
T0=$(date +%s)
FAILED=0
HEADER=false
PF=
TOKEN=

mkdir -p "$OUT"
: > "$OUT/summary.md"

log() { echo "=== $(date -u +%H:%M:%S) $*" | tee -a "$OUT/steps.log" >&2; }

fail() {
  log "FATAL: $*"
  exit 1
}

retry() {
  "$@" && return
  log "retrying once in 15s: $*"
  sleep 15
  "$@"
}

elapsed() {
  local s
  s=$(($(date +%s) - T0))
  printf '%d:%02d' $((s / 60)) $((s % 60))
}

summary_header() {
  printf '%s\n\n| Step | Elapsed | Check | Result | Detail |\n|---|---|---|---|---|\n' "$1" >> "$OUT/summary.md"
  HEADER=true
}

write_qualification_manifest() {
  local image_ref=$1 chart_version=$2 chart_sha256=$3 catalog_index_ref=$4
  local image_digest catalog_index_digest
  [[ $image_ref =~ @sha256:[a-f0-9]{64}$ ]] || fail "portal image is not pinned by a sha256 digest: $image_ref"
  [[ $catalog_index_ref =~ @sha256:[a-f0-9]{64}$ ]] || fail "catalog index is not pinned by a sha256 digest: $catalog_index_ref"
  [[ $chart_version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || fail "invalid qualified chart version: $chart_version"
  [[ $chart_sha256 =~ ^[a-f0-9]{64}$ ]] || fail "invalid chart package sha256: $chart_sha256"
  image_digest=${image_ref##*@}
  catalog_index_digest=${catalog_index_ref##*@}
  jq -n \
    --arg image_digest "$image_digest" \
    --arg chart_version "$chart_version" \
    --arg chart_package_sha256 "$chart_sha256" \
    --arg catalog_index_digest "$catalog_index_digest" \
    '{image_digest: $image_digest, chart_version: $chart_version, chart_package_sha256: $chart_package_sha256, catalog_index_digest: $catalog_index_digest}' \
    > "$OUT/qualification-manifest.json"
  {
    printf '\n## Qualified candidate manifest\n\n```json\n'
    jq . "$OUT/qualification-manifest.json"
    printf '```\n'
  } >> "$OUT/summary.md"
}

# NEEDS tags a check with the change it depends on, as listed in README.md.
record() {
  local step=$1 check=$2 needs=$3 ok=$4 detail=${5//|/\\|} result
  [ "$HEADER" = true ] || summary_header "Qualification sequence"
  if [ -n "$needs" ] && [ "$SELF_TEST" = true ]; then
    result="SKIP (needs $needs)"
  elif [ "$ok" = 1 ]; then
    result=PASS
  else
    result=FAIL
    FAILED=$((FAILED + 1))
  fi
  printf '| %s | %s | %s | %s | %s |\n' "$step" "$(elapsed)" "$check" "$result" "$detail" | tee -a "$OUT/summary.md" >&2
}

assert() {
  local step=$1 check=$2 needs=$3 detail=$4
  shift 4
  if "$@"; then
    record "$step" "$check" "$needs" 1 "$detail"
  else
    record "$step" "$check" "$needs" 0 "$detail"
  fi
}

json_true() { jq -e "${@:2}" "$1" > /dev/null; }

log_resources() {
  local used avail mem
  read -r used avail < <(df -BG --output=used,avail / | tail -1)
  mem=$(docker stats --no-stream --format '{{.MemUsage}}' "$NODE" 2> /dev/null | cut -d/ -f1 | xargs)
  log "resources after $1: disk used $used, free $avail, node memory ${mem:-unknown}"
}

chart_field() { helm show chart "$1" | yq ".$2"; }

# The same download and checks next-charts runs before it indexes a package.
fetch_release() {
  local version=$1 dir=$2 package
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || fail "chart version must be x.y.z or x.y.z-rc.N, got '$version'"
  package=devportal-$version.tgz
  mkdir -p "$dir"
  retry curl --fail --location --silent --show-error "$RELEASES/chart-v$version/$package" --output "$dir/$package"
  retry curl --fail --location --silent --show-error "$RELEASES/chart-v$version/$package.sha256" --output "$dir/$package.sha256"
  (cd "$dir" && sha256sum --check --strict "$package.sha256") >&2 || fail "$package does not match $package.sha256"
  [ "$(chart_field "$dir/$package" name)" = devportal ] || fail "$package does not embed the chart name devportal"
  [ "$(chart_field "$dir/$package" version)" = "$version" ] || fail "$package does not embed the version $version"
  echo "$dir/$package"
}

previous_final() {
  local candidate=$1 cutoff=$1 v prev=
  [[ $candidate == *-rc.* ]] && cutoff=${candidate%%-rc.*}
  retry curl --fail --location --silent --show-error "$CHART_INDEX" --output "$OUT/chart-index.yaml"
  while read -r v; do
    [ "$v" = "$cutoff" ] && break
    prev=$v
  done < <({
    yq '.entries.devportal[].version' "$OUT/chart-index.yaml" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'
    echo "$cutoff"
  } | sort -V -u)
  echo "$prev"
}

node_pull() { retry docker exec "$NODE" crictl pull "$1" > /dev/null; }

setup_database() {
  local password backend_secret
  password=$(openssl rand -hex 12)
  backend_secret=$(openssl rand -hex 16)
  kubectl create namespace "$NS" > /dev/null
  "${K[@]}" create secret generic veecode-runtime-secrets \
    --from-literal=PG_HOST="devportal-db.$NS.svc" --from-literal=PG_PORT=5432 \
    --from-literal=PG_USER=devportal --from-literal=PG_PASSWORD="$password" --from-literal=PG_DATABASE=devportal \
    --from-literal=POSTGRES_USER=devportal --from-literal=POSTGRES_PASSWORD="$password" --from-literal=POSTGRES_DB=devportal \
    --from-literal=BACKEND_SECRET="$backend_secret" > /dev/null
  node_pull "$POSTGRES_IMAGE"
  # Not named pg or postgres: service links would inject PG_PORT=tcp://<ip>:5432 into
  # every pod, and chart 0.1.24's pre-step then reads a NaN port.
  "${K[@]}" create deployment devportal-db --image="$POSTGRES_IMAGE" --port=5432 > /dev/null
  "${K[@]}" set env deployment/devportal-db --from=secret/veecode-runtime-secrets \
    --keys=POSTGRES_USER,POSTGRES_PASSWORD,POSTGRES_DB > /dev/null
  "${K[@]}" expose deployment devportal-db --port=5432 > /dev/null
  "${K[@]}" rollout status deployment/devportal-db --timeout=5m > /dev/null
  for _ in $(seq 1 30); do
    "${K[@]}" exec deploy/devportal-db -- pg_isready -U devportal > /dev/null 2>&1 && return 0
    sleep 2
  done
  fail "PostgreSQL did not accept connections"
}

serve_fixture() {
  "${K[@]}" create configmap qualification-fixtures \
    --from-file=FIXTURE="$HERE/fixtures/broken-package.yaml" > /dev/null
  # shellcheck disable=SC2016 # $FIXTURE expands inside the container.
  "${K[@]}" create deployment qualification-fixtures --image="$FIXTURES_IMAGE" -- sh -c \
    'mkdir -p /tmp/www && printf "%s\n" "$FIXTURE" > /tmp/www/broken-package.yaml && exec httpd -f -p 8080 -h /tmp/www' > /dev/null
  "${K[@]}" set env deployment/qualification-fixtures --from=configmap/qualification-fixtures > /dev/null
  "${K[@]}" expose deployment qualification-fixtures --port=80 --target-port=8080 > /dev/null
  "${K[@]}" rollout status deployment/qualification-fixtures --timeout=5m > /dev/null
}

sql() { "${K[@]}" exec deploy/devportal-db -- psql -U devportal -d "$1" -Atc "$2"; }

backup_databases() {
  local db dbs
  sql postgres "select datname from pg_database where not datistemplate and datname <> 'postgres'" > "$OUT/databases.txt"
  mapfile -t dbs < "$OUT/databases.txt"
  for db in "${dbs[@]}"; do
    "${K[@]}" exec deploy/devportal-db -- sh -c "pg_dump -U devportal --clean --create --if-exists -d '$db' > '/tmp/backup-$db.sql'"
  done
}

restore_databases() {
  local db dbs
  mapfile -t dbs < "$OUT/databases.txt"
  for db in "${dbs[@]}"; do
    "${K[@]}" exec deploy/devportal-db -- psql -U devportal -d postgres -v ON_ERROR_STOP=1 -q \
      -f "/tmp/backup-$db.sql" > "$OUT/restore-$db.log" 2>&1
  done
}

portal_pod() {
  "${K[@]}" get pod -l "$SEL" -o json |
    jq -r '[.items[] | select(.metadata.deletionTimestamp == null)] | sort_by(.metadata.creationTimestamp) | last | .metadata.name'
}

portal_pods() { "${K[@]}" get pod -l "$SEL" -o json | jq "[.items[] | $1] | length"; }

wait_portal() {
  local start=$SECONDS
  for _ in $(seq 1 90); do
    if [ "$(portal_pods .)" = 1 ] &&
      [ "$(portal_pods 'select(.metadata.deletionTimestamp == null) | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))')" = 1 ]; then
      log "the portal was ready $((SECONDS - start))s after the wait began ($1)"
      return 0
    fi
    sleep 10
  done
  "${K[@]}" get pods -o wide >&2
  "${K[@]}" describe pod -l "$SEL" > "$OUT/describe-$1.txt" 2>&1
  fail "no single Ready portal pod after 15 minutes ($1)"
}

restart_portal() {
  "${K[@]}" delete pod -l "$SEL" --wait=true > /dev/null
  wait_portal "$1"
}

stop_portal() {
  "${K[@]}" scale "deploy/$DEPLOY" --replicas=0 > /dev/null
  for _ in $(seq 1 60); do
    [ "$(portal_pods .)" = 0 ] && return 0
    sleep 5
  done
  fail "the portal pod did not stop"
}

connect() {
  if [ -n "$PF" ]; then
    kill "$PF" 2> /dev/null || true
    wait "$PF" 2> /dev/null || true
  fi
  "${K[@]}" port-forward "svc/$DEPLOY" "$PORT:7007" >> "$OUT/port-forward.log" 2>&1 &
  PF=$!
  for _ in $(seq 1 30); do
    if curl -s -o /dev/null "$URL/"; then
      TOKEN=$(curl -s -H 'X-Requested-With: XMLHttpRequest' "$URL/api/auth/guest/refresh" | jq -r '.backstageIdentity.token // empty')
      [ -n "$TOKEN" ] && return 0
    fi
    sleep 2
  done
  fail "the portal did not issue a guest token"
}

api() { curl -s --fail -H "Authorization: Bearer $TOKEN" "$URL/api/extensions/$1"; }

set_disabled() {
  curl -s -o "$OUT/patch-$3.json" -w '%{http_code}' -X PATCH \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
    -d "{\"disabled\":$2}" "$URL/api/extensions/package/$1/configuration/disable"
}

collect() {
  local pod
  pod=$(portal_pod)
  "${K[@]}" logs "$pod" -c install-dynamic-plugins > "$OUT/init-$1.log" 2>&1
  "${K[@]}" logs "$pod" -c backstage-backend > "$OUT/backend-$1.log" 2>&1
  api loaded-plugins > "$OUT/loaded-$1.json"
  api pending-changes > "$OUT/pending-$1.json"
}

# The catalog keeps ingesting the index and the fixture location after the pod is Ready.
wait_catalog() {
  local last=-1 n
  for _ in $(seq 1 30); do
    api packages > "$OUT/packages-$1.json"
    n=$(jq '.items | length' "$OUT/packages-$1.json")
    # shellcheck disable=SC2016 # $p is a jq variable.
    if [ "$n" = "$last" ] && json_true "$OUT/packages-$1.json" --arg p "${FIXTURE_PACKAGE#*/}" 'any(.items[]; .metadata.name == $p)'; then
      return 0
    fi
    last=$n
    sleep 10
  done
  log "the package list did not settle with the fixture in five minutes ($1)"
}

# Fails, and leaves no package list, when the index cannot be fetched, unpacked or read, or lists no package.
index_packages() {
  local dir layers layer
  dir=$OUT/index/$(printf '%s' "$1" | sha256sum | cut -c1-12)
  if [ ! -s "$dir/packages.txt" ]; then
    rm -rf "$dir"
    mkdir -p "$dir/fs"
    retry skopeo --override-os linux --override-arch amd64 copy --quiet --src-no-creds "docker://$1" "dir:$dir/image" >&2 || return 1
    layers=$(jq -r '.layers[].digest' "$dir/image/manifest.json") || return 1
    for layer in $layers; do
      tar -xzf "$dir/image/${layer#sha256:}" -C "$dir/fs" || return 1
    done
    yq -N 'select(.kind == "Package") | (.metadata.namespace // "default") + "/" + .metadata.name' \
      "$dir"/fs/catalog-entities/extensions/packages/*.yaml | sort -u > "$dir/packages.tmp" || return 1
    [ -s "$dir/packages.tmp" ] || { log "$1 lists no package"; return 1; }
    mv "$dir/packages.tmp" "$dir/packages.txt"
  fi
  echo "$dir/packages.txt"
}

# Prints the reference and resolves, missing, or error with the registry's message. Missing is
# an answer that says the image is not there: manifest unknown, name unknown, or the unauthorized
# or denied that quay.io and Docker Hub give an anonymous client for a repository that does not exist.
# A rate limit, a timeout, a TLS failure or a server error is an error, retried once.
resolve_oci() {
  local image=${1#oci://} msg attempt
  image=${image%%!*}
  for attempt in 1 2; do
    if msg=$(skopeo inspect --raw --no-creds "docker://$image" 2>&1 > /dev/null); then
      printf '%s\tresolves\n' "$1"
      return
    fi
    case $msg in
      *"manifest unknown"* | *"name unknown"* | *"StatusCode: 404"* | *"unauthorized:"* | *"requested access to the resource is denied"*)
        printf '%s\tmissing\n' "$1"
        return
        ;;
    esac
    [ "$attempt" = 2 ] || sleep 5
  done
  printf '%s\terror\t%s\n' "$1" "$(printf '%s' "$msg" | tail -1 | tr '\t\n' '  ' | cut -c1-300)"
}

# Registry answers are cached for the run, errors are not; bundled refs depend on the running image.
resolve_artifacts() {
  local pod ref
  pod=$(portal_pod)
  touch "$OUT/oci-artifacts.tsv"
  export -f resolve_oci
  { grep '^oci://' "$1" || true; } | comm -23 - <(cut -f1 "$OUT/oci-artifacts.tsv" | sort -u) > "$OUT/oci-new.txt"
  # shellcheck disable=SC2016 # $1 expands in the child bash.
  xargs -r -P 8 -I{} bash -c 'resolve_oci "$1"' _ {} < "$OUT/oci-new.txt" > "$OUT/oci-answers.tsv"
  awk -F'\t' '$2 != "error"' "$OUT/oci-answers.tsv" >> "$OUT/oci-artifacts.tsv"
  awk -F'\t' '$2 == "error"' "$OUT/oci-answers.tsv"
  awk -F'\t' 'NR == FNR { wanted[$1] = 1; next } $1 in wanted' "$1" "$OUT/oci-artifacts.tsv"
  while read -r ref; do
    case $ref in
      oci://*) ;;
      ./*)
        if "${K[@]}" exec "$pod" -c backstage-backend -- test -d "/opt/app-root/src/${ref#./}" < /dev/null; then
          printf '%s\tresolves\n' "$ref"
        else
          printf '%s\tmissing\n' "$ref"
        fi
        ;;
      *) printf '%s\tunsupported\n' "$ref" ;;
    esac
  done < "$1"
}

collect_diagnostics() {
  kubectl get pods,events -A -o wide > "$OUT/cluster.txt" 2>&1 || true
  helm history "$RELEASE" -n "$NS" > "$OUT/helm-history.txt" 2>&1 || true
  docker exec "$NODE" crictl images > "$OUT/node-images.txt" 2>&1 || true
}
