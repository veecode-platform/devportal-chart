#!/usr/bin/env bash
# The qualification's browser job (contract K5). It installs CHART as RELEASE in a
# new NAMESPACE, next to a PostgreSQL and a Keycloak whose realm and users it
# creates, then runs the RHDH specs adapted in e2e/. The Playwright report, traces,
# screenshots and the cluster logs land under OUT, and the exit code is the result.
set -euo pipefail

: "${NAMESPACE:?set NAMESPACE}" "${RELEASE:?set RELEASE}" "${CHART:?set CHART}" "${OUT:?set OUT}"
[[ -e "$CHART" ]] || { echo "CHART $CHART is neither a chart directory nor a package" >&2; exit 2; }
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
PORTAL_URL=http://localhost:17007
KEYCLOAK_URL=http://localhost:18080
FORWARDS=()

log() { printf '=== %s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
kc() { kubectl -n "$NAMESPACE" "$@"; }
secret() { openssl rand -hex 16; }
fail() {
  log "$1 failed; the end of $2:"
  tail -n 40 "$2"
  exit 1
}

collect() {
  local rc=$?
  for pid in "${FORWARDS[@]}"; do kill "$pid" 2> /dev/null || true; done
  kc get pods -o wide > "$OUT/pods.txt" 2>&1 || true
  kc get events --sort-by=.lastTimestamp > "$OUT/events.txt" 2>&1 || true
  kc logs "deploy/$RELEASE-developer-hub" -c install-dynamic-plugins > "$OUT/install-dynamic-plugins.log" 2>&1 || true
  kc logs "deploy/$RELEASE-developer-hub" -c backstage-backend > "$OUT/backstage-backend.log" 2>&1 || true
  kc logs deploy/keycloak > "$OUT/keycloak.log" 2>&1 || true
  log "exit $rc after ${SECONDS}s"
  exit "$rc"
}
trap collect EXIT

# Restarted whenever it drops, because two specs restart the portal pod.
forward() {
  local name=$1
  shift
  (
    pid=
    trap 'kill "$pid" 2> /dev/null; exit 0' TERM
    while true; do
      kc port-forward "$@" >> "$OUT/port-forward-$name.log" 2>&1 &
      pid=$!
      wait "$pid" || true
      sleep 1
    done
  ) &
  FORWARDS+=("$!")
}

wait_for() {
  for _ in $(seq 1 90); do
    curl -sf -o /dev/null "$1" && return 0
    sleep 2
  done
  log "no answer from $1"
  return 1
}

log "playwright and the upstream library, in the background"
(cd "$HERE/e2e" && npm ci --no-audit --no-fund && npx playwright install --with-deps chromium) > "$OUT/npm.log" 2>&1 &
SETUP=$!

KEYCLOAK_CLIENT_SECRET=$(secret)
KEYCLOAK_USER_PASSWORD=$(secret)
DB_PASSWORD=$(secret)

log "namespace $NAMESPACE with PostgreSQL and Keycloak"
kubectl create namespace "$NAMESPACE" > /dev/null
kc create secret generic devportal-db \
  --from-literal=POSTGRES_USER=devportal \
  --from-literal=POSTGRES_PASSWORD="$DB_PASSWORD" \
  --from-literal=POSTGRES_DB=devportal > /dev/null
# Not named pg or postgres: service links would inject PG_PORT or POSTGRES_PORT
# as tcp://IP:5432 into every pod in the namespace.
kc create deployment devportal-db --image=postgres:16 > /dev/null
kc set env deployment/devportal-db --from=secret/devportal-db > /dev/null
kc expose deployment devportal-db --port 5432 > /dev/null
kc create secret generic veecode-runtime-secrets \
  --from-literal=PG_HOST=devportal-db \
  --from-literal=PG_PORT=5432 \
  --from-literal=PG_USER=devportal \
  --from-literal=PG_PASSWORD="$DB_PASSWORD" \
  --from-literal=PG_DATABASE=devportal \
  --from-literal=BACKEND_SECRET="$(secret)" \
  --from-literal=AUTH_SESSION_SECRET="$(secret)" \
  --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" > /dev/null
kc create secret generic keycloak-realm-env \
  --from-literal=KEYCLOAK_CLIENT_SECRET="$KEYCLOAK_CLIENT_SECRET" \
  --from-literal=KEYCLOAK_USER_PASSWORD="$KEYCLOAK_USER_PASSWORD" > /dev/null
kc create configmap keycloak-realm --from-file=rhdh-realm.json="$HERE/realm.json" > /dev/null
kc apply -f "$HERE/keycloak.yaml" > /dev/null
kc rollout status deployment/devportal-db --timeout=5m > /dev/null

log "install $CHART as $RELEASE"
if [[ -d "$CHART" ]]; then
  helm repo add bitnami https://charts.bitnami.com/bitnami --force-update > /dev/null
  helm dependency build "$CHART" > "$OUT/helm-dependency-build.log" 2>&1 || fail "helm dependency build" "$OUT/helm-dependency-build.log"
fi
helm install "$RELEASE" "$CHART" -n "$NAMESPACE" -f "$HERE/values-oidc.yaml" --wait --timeout 20m > "$OUT/helm-install.log" 2>&1 || fail "helm install" "$OUT/helm-install.log"
kc rollout status deployment/keycloak --timeout=5m > /dev/null

forward portal "svc/$RELEASE-developer-hub" 17007:7007
forward keycloak svc/keycloak 18080:8080
wait_for "$PORTAL_URL/.backstage/health/v1/readiness"
wait_for "$KEYCLOAK_URL/realms/rhdh/.well-known/openid-configuration"

wait "$SETUP" || fail "npm ci or playwright install" "$OUT/npm.log"
log "specs"
cd "$HERE/e2e"
BASE_URL=$PORTAL_URL KEYCLOAK_URL=$KEYCLOAK_URL KEYCLOAK_USER_PASSWORD=$KEYCLOAK_USER_PASSWORD \
  NAMESPACE=$NAMESPACE RELEASE=$RELEASE OUT=$OUT npx playwright test
