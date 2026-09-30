# Qualification

The qualification installs a devportal chart candidate on throwaway KinD clusters and
checks that it survives what a release puts it through. Two jobs run in parallel. The
sequence job checks that the marketplace survives an upgrade from the previous chart, a
marketplace plugin whose image does not exist, restarts, and a rollback that restores the
database. The browser job installs the candidate fresh, runs the browser specs, and scans
its image. A last job, `Qualification`, turns their results into one check.
[`qualification.yaml`](../.github/workflows/qualification.yaml) runs it on GitHub Actions.
It needs no repository secret, so pull requests from forks run it too.

## Run it

The workflow runs on every pull request against `main`, and its first job decides what the
run qualifies:

- A pull request that changes `upstream.backstage.image` in
  `charts/backstage/values.yaml` qualifies its chart.
- A pull request that changes `qualification/` or the workflow, and not the image,
  self-tests the qualification against its chart.
- Any other pull request has nothing to qualify. The two jobs are skipped and
  `Qualification` passes.

To qualify a published package, dispatch the workflow with the chart version:

```bash
gh workflow run qualification.yaml -R veecode-platform/devportal-chart -f chart_version=0.1.25
```

Add `-f self_test=true` for a self-test. Both jobs download the candidate's
`devportal-<version>.tgz` and its `.sha256` from the `chart-v<version>` release and check
the checksum before they install anything, as the next-charts ingest does.

The previous chart is the newest final `x.y.z` version in the
[next-charts index](https://veecode-platform.github.io/next-charts/index.yaml) that
is older than the candidate. Its package is downloaded and checked the same way.

## The jobs

| Job | What it does |
|---|---|
| Decide what the run qualifies | Compares the pull request with its base and outputs whether to run and whether the run is a self-test. A dispatch always runs. |
| Sequence on KinD | Runs `sequence.sh`, described below. Uploads `qualification-sequence`, which holds the summary table, the logs, and the API responses of every step. |
| Browser on KinD | Runs `browser/run.sh`, then scans the candidate's image. Uploads `qualification-browser` (the Playwright report, traces, screenshots, and the cluster logs) and `qualification-scan` (`trivy.json` and `scan-summary.md`). |
| Qualification | Passes only when every job the run decided on succeeded. |

## What the sequence asserts

The sequence has six steps. After each one it checks that:

- the good plugin is loaded, or absent, as the step expects, in
  `GET /api/extensions/loaded-plugins`;
- every enabled plugin of the product face is loaded, and the installer logs hold no
  `Cannot find module`, no `already registered`, and no warning about a skipped entry. This is
  `scripts/check-loaded-plugins.sh` of devportal-local, which the workflow fetches at a pinned
  commit and which reads the face and the logs of the portal pod through `kubectl`;
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
| 5 | Stops the portal, restores the backup, and rolls back to revision 1. Then uninstalls the good plugin. | loaded | The broken package's row is gone, and the good row is stored as disabled. |
| 6 | Restarts the portal. | absent | |

The good plugin is an OCI package of the index whose reference has no `!` plugin path.
A bundled plugin cannot hold a digest, so it could never satisfy the `resolved_digest`
check.

Step 6 shows that the marketplace change survived the restart, which only holds when
the marketplace stores its state in the database.

`steps.log` records how many seconds the portal took to become ready after each change.

## Self-test

A check tagged with one of these names needs a change the candidate may lack:

- `prestep-skip`: the pre-step skips a row whose digest does not resolve, instead of
  abandoning the whole regeneration (devportal-core,
  `veecode/regenerate-extensions-install.js`).
- `marketplace-backend`: the marketplace backend stores `resolved_digest` and lists
  `failedInstalls` in `GET /api/extensions/pending-changes` (devportal-plugins,
  `devportal-marketplace-backend`).
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

## The browser job

`browser/run.sh` installs the candidate as release `devportal` in a new namespace, next to a
PostgreSQL and a Keycloak whose realm and users the run creates. It then runs the specs in
`browser/e2e`, adapted from redhat-developer/rhdh, which sign in as a guest and through
Keycloak with the upstream library's `LoginHelper`. The exit code of `run.sh` is the result.

The scan follows the specs and runs even when they fail. `scan/run.sh` scans the candidate's
image, which the chart pins by digest, with Trivy in report mode. The full report goes to
`qualification-scan` and the counts by severity to the job summary. Findings never fail the
job, but a scan that did not run does, so no run passes without the report.

## The Qualification job

`Qualification` is the check to require on `main`. It always runs, and it passes only when
`scope` succeeded and the two other jobs ended as `scope` decided: both succeeded when the
run qualifies the candidate, both skipped when there was nothing to qualify. A job that
failed, was cancelled, or was skipped when it should have run fails the check.

Requiring the jobs one by one would leave a hole: GitHub counts a skipped job as a pass, and
skips a job whose dependency failed, so a failed `scope` would skip both jobs and let their
checks pass with nothing tested. `Qualification` judges all three jobs instead. The workflow
has no path filter, because the required check of a workflow that GitHub skips stays pending
and blocks the pull request.

## Prove that it can fail

A dispatch takes `inject_failure`, which breaks one job on purpose:

| Value | What it breaks | What goes red |
|---|---|---|
| `missing-plugin` | The sequence expects two plugins that the portal does not have: the good plugin gets another name, and the product face that the loaded-plugins check reads gets one more enabled entry. | Sequence on KinD, and Qualification. |
| `failed-sign-in` | The specs sign in to Keycloak with a password that the realm does not hold. | Browser on KinD, and Qualification. |

Dispatch it with a self-test of a published version, for example:

```bash
gh workflow run qualification.yaml -R veecode-platform/devportal-chart --ref BRANCH \
  -f chart_version=0.1.25 -f self_test=true -f inject_failure=missing-plugin
```

The run must go red, and only the job that the value breaks. A dispatch's concurrency
group holds its ref, `chart_version`, `self_test` and `inject_failure`, so an injected run,
a self-test and a full run of the same version never cancel each other.

## Run it on another cluster

`sequence.sh` drives the cluster that `kubectl` reaches. It needs `kubectl`, `helm`,
`jq`, `yq` 4, `skopeo`, `curl`, `openssl`, `python3`, and `docker` to pull images inside the
node with `crictl`. These variables configure it:

| Variable | Default | Meaning |
|---|---|---|
| `CANDIDATE_CHART` | | A chart directory or package to qualify. |
| `CANDIDATE_VERSION` | | A published version to download and qualify instead. |
| `SELF_TEST` | `false` | Report the tagged checks as SKIP. |
| `LOADED_PLUGINS_CHECK` | | Required. The path of `scripts/check-loaded-plugins.sh` of devportal-local. |
| `INJECT_FAILURE` | `none` | `missing-plugin` makes the sequence expect plugins the portal lacks. `failed-sign-in` is read by the browser runner only. |
| `KIND_NODE` | `qualification-control-plane` | The node container that pulls the images. |
| `OUT` | `/tmp/qualification` | Where the summary, logs, and responses go. |
| `PORT` | `17007` | The local port of the port-forward. |
| `GOOD_PACKAGE` | `rhdh/backstage-community-plugin-todo-backend` | The package the sequence installs and later removes. |
| `GOOD_PLUGIN` | `@backstage-community/plugin-todo-backend-dynamic` | The name that package loads under. |

`OUT/summary.md` holds the table with PASS, FAIL, or SKIP per check. The workflow adds
it to the job summary and uploads `OUT` as the `qualification-sequence` artifact.

`browser/run.sh` takes `NAMESPACE`, `RELEASE`, `CHART` (a chart directory or package), and
`OUT` from the environment, and `INJECT_FAILURE` as above. It needs `kubectl`, `helm`,
`openssl`, Node.js 24, and root or `sudo` for `npx playwright install --with-deps`.
`scan/run.sh IMAGE_REF` needs `jq`, `curl`, and `python3` with PyYAML; `MODE=report`
is its default.
