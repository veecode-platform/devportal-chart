# Qualification

The qualification installs a devportal chart candidate on a throwaway KinD cluster
and checks that the marketplace survives what a release puts it through: an upgrade
from the previous chart, a marketplace plugin whose image does not exist, restarts,
and a rollback that restores the database.
[`qualification.yaml`](../.github/workflows/qualification.yaml) runs it on GitHub
Actions. It needs no repository secret, so pull requests from forks run it too.

## Run it

The workflow runs by itself on pull requests against `main`:

- A pull request that changes `upstream.backstage.image` in
  `charts/backstage/values.yaml` qualifies its chart.
- A pull request that changes `qualification/` or the workflow, and not the image,
  self-tests the qualification against its chart.

To qualify a published package, dispatch the workflow with the chart version:

```bash
gh workflow run qualification.yaml -R veecode-platform/devportal-chart -f chart_version=0.1.25
```

Add `-f self_test=true` for a self-test. The run downloads `devportal-<version>.tgz`
and its `.sha256` from the `chart-v<version>` release and checks the checksum before
it installs anything, as the next-charts ingest does.

The previous chart is the newest final `x.y.z` version in the
[next-charts index](https://veecode-platform.github.io/next-charts/index.yaml) that
is older than the candidate. Its package is downloaded and checked the same way.

## What it asserts

The sequence has six steps. After each one it checks that:

- the good plugin is loaded, or absent, as the step expects, in
  `GET /api/extensions/loaded-plugins`;
- the backend logs `Marketplace installation service initialized (database-backed)`
  and not the fallback to file storage;
- the portal serves the broken package, which shows that the test-only catalog
  location works;
- the portal serves every package of its catalog index image, plus the broken
  package (`catalog-fixes`);
- no package fails catalog validation in the backend log (`catalog-fixes`);
- every artifact the marketplace offers resolves: OCI references anonymously with
  skopeo, bundled references inside the running image (`catalog-fixes`).

| Step | What it does | Good plugin | Extra checks |
|---|---|---|---|
| 1 | Installs the previous final chart, then installs the good plugin through the marketplace. | absent | The install returns 200 and is pending. |
| 2 | Restarts the portal, then backs up every database with `pg_dump`. | loaded | |
| 3 | Upgrades to the candidate, then installs the broken package through the marketplace. | loaded | The pre-step summary counts every row (`prestep-skip`). |
| 4 | Restarts the candidate twice. | loaded (`prestep-skip`) | The pre-step skips the broken package (`prestep-skip`). The broken package is in `failedInstalls`, and the good row holds `resolved_digest`, read with psql (`marketplace-backend`). |
| 5 | Stops the portal, restores the backup, and rolls back to revision 1. Then uninstalls the good plugin. | loaded | The broken package's row is gone, and the good row is stored as disabled. The good package is in `pendingRemovals` (`marketplace-backend`). |
| 6 | Restarts the portal. | absent | |

The good plugin is an OCI package of the index whose reference has no `!` plugin path.
A bundled plugin cannot hold a digest, so it could never satisfy the `resolved_digest`
check.

Step 6 shows that the marketplace change survived the restart, which only holds when
the marketplace stores its state in the database.

## Self-test

A check tagged with one of these names needs a change the candidate may lack:

- `prestep-skip`: the pre-step skips a row whose digest does not resolve, instead of
  abandoning the whole regeneration (devportal-core,
  `veecode/regenerate-extensions-install.js`).
- `marketplace-backend`: the marketplace backend stores `resolved_digest`, lists
  `failedInstalls` in `GET /api/extensions/pending-changes`, and matches a
  selector-less OCI reference to its loaded plugin, so that `pendingRemovals` lists it
  (devportal-plugins, `devportal-marketplace-backend`). Step 5 runs the previous
  chart, so a full run passes the `pendingRemovals` check only when the previous chart
  has that fix.
- `catalog-fixes`: the catalog index offers only packages whose artifacts exist and
  that the portal accepts (devportal-plugin-export-overlays).

A self-test reports each tagged check as SKIP with what it observed, never as PASS.
A full run treats them like every other check.

## The broken package

`fixtures/broken-package.yaml` is a `Package` entity whose `dynamicArtifact` points at
an image that does not exist. The pre-step only resolves OCI references that end in
a `!` plugin path, so the fixture has one. The sequence serves the file from a busybox
`httpd` pod in the cluster, and `values/sequence.yaml` adds its URL as a catalog
location that allows only `Package` entities. The fixture never enters the overlays
index.

## Run it on another cluster

`sequence.sh` drives the cluster that `kubectl` reaches. It needs `kubectl`, `helm`,
`jq`, `yq` 4, `skopeo`, `curl`, `openssl`, and `docker` to pull images inside the node
with `crictl`. These variables configure it:

| Variable | Default | Meaning |
|---|---|---|
| `CANDIDATE_CHART` | | A chart directory or package to qualify. |
| `CANDIDATE_VERSION` | | A published version to download and qualify instead. |
| `SELF_TEST` | `false` | Report the tagged checks as SKIP. |
| `KIND_NODE` | `qualification-control-plane` | The node container that pulls the images. |
| `OUT` | `/tmp/qualification` | Where the summary, logs, and responses go. |
| `PORT` | `17007` | The local port of the port-forward. |
| `GOOD_PACKAGE` | `rhdh/backstage-community-plugin-todo-backend` | The package the sequence installs and later removes. |
| `GOOD_PLUGIN` | `@backstage-community/plugin-todo-backend-dynamic` | The name that package loads under. |

`OUT/summary.md` holds the table with PASS, FAIL, or SKIP per check. The workflow adds
it to the job summary and uploads `OUT` as the `qualification-sequence` artifact.
