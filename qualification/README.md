# Qualification

The qualification installs a devportal chart candidate on throwaway KinD clusters and
checks that it survives what a release puts it through. Two jobs run in parallel. The
sequence job checks that the marketplace survives an upgrade from the previous chart, a
marketplace plugin whose image does not exist, restarts, and a rollback that restores the
database, and that an upgrade with values that omit `guestAuth` ends with guest sign-in off.
The browser job installs the candidate fresh, runs the browser specs, and scans
its image and the plugin artifacts its product face enables. A last job, `Qualification`, turns
their results into one check.
[`qualification.yaml`](../.github/workflows/qualification.yaml) runs it on GitHub Actions.
It needs no repository secret, so pull requests from forks run it too.

## Candidate manifest

The `qualification-sequence` artifact contains `qualification-manifest.json` beside `summary.md`. After the sequence finishes, the workflow appends that manifest to its step summary below the complete results table. The manifest records the candidate package, the portal image digest, and the catalog-index reference and digest resolved after the candidate portal is ready.

Keep these JSON keys stable because the release gate compares manifests from the candidate and final qualifications:

| Key | Value |
|---|---|
| `image_digest` | `sha256:` digest of the running `backstage-backend` image. |
| `chart_version` | Version embedded in the qualified chart package, including an optional `-rc.N` suffix. |
| `chart_package_sha256` | Lowercase hexadecimal SHA-256 checksum of the exact chart `.tgz` package. |
| `catalog_index_digest` | `sha256:` digest resolved from the catalog-index reference with `skopeo inspect`. |
| `catalog_index_ref` | Exact `CATALOG_INDEX_IMAGE` value from the deployment. From chart 1.0.4 it is the digest reference the chart pins; earlier charts used the moving tag. |

For pull requests, the sequence packages the chart directory before installing it so the recorded checksum identifies the package used by Helm. For dispatches, `fetch_release` verifies the published package against its release checksum before writing the manifest.

Run `qualification/test-release-helpers.sh` for the release version and checksum fixtures. The tests use local `file://` inputs and do not dispatch the full qualification.

Two more tests need no cluster and no network, and the first job of the workflow runs them on every run:

- `qualification/test-scope.sh` builds throwaway repositories and checks what a pull request asks the qualification to do (see below) in the cases of an image change, of only its digest or only its registry, a catalog index change, both, a qualification file or the workflow only, a qualification file with other chart changes, a pin with a qualification file, and nothing, and that `prior-qualification.sh` refuses to skip a pull request that re-pins the catalog index.
- `qualification/test-guest-check.sh` runs the sequence's guest sign-in check against a `curl` that answers like a portal with guest sign-in on and off, and against one whose connection is refused, and checks that the response it keeps holds no value under a key that ends in `token` or `Token`, camelCase or snake_case.

## Run it

The workflow runs on every pull request against `main`, and its first job decides what the
run qualifies:

- A pull request that changes a pin in `charts/backstage/values.yaml`, the portal image
  (`upstream.backstage.image`) or the catalog index (`global.catalogIndex.image`), qualifies
  its chart, unless it is a release pull request whose image is already qualified.
  `qualification/pr-scope.sh` makes that comparison with the base. `prior-qualification.sh`
  checks that the pull request changes only the release fields (version, appVersion, image
  tag and digest, the schema defaults that mirror them, the generated README), and that a
  successful run recorded this digest with the same `charts/backstage` as the base, which is
  what an `image_tag` dispatch before the release does. The two jobs are then skipped, the job
  summary links that run, and `Qualification` passes. A pull request that re-pins the catalog
  index is never skipped: an image qualification tested the index its chart pinned at the time,
  not the new one, so a release pull request that also re-pins the index runs in full.
- A pull request that changes `qualification/` or the workflow, and neither pin,
  self-tests the qualification against its chart.
- Any other pull request has nothing to qualify. The two jobs are skipped and
  `Qualification` passes.

To qualify a published package, dispatch the workflow with the chart version:

```bash
gh workflow run qualification.yaml -R veecode-platform/devportal-chart -f chart_version=1.0.4
```

Use 1.0.4 or later. A chart older than 1.0.4 fails step 7 of the sequence by design: its
default leaves guest sign-in on, so the upgrade cannot turn it off (see
[What the sequence asserts](#what-the-sequence-asserts)).

Add `-f self_test=true` for a self-test. Both jobs download the candidate's
`devportal-<version>.tgz` and its `.sha256` from the `chart-v<version>` release and check
the checksum before they install anything, as the next-charts ingest does.

To qualify an image before any chart pins it, dispatch the workflow with its tag instead:

```bash
gh workflow run qualification.yaml -R veecode-platform/devportal-chart -f image_tag=3.0.2-rc.1
```

The run resolves the tag of `docker.io/veecode/devportal` to its digest once, in the first
job, and both jobs install the chart at the dispatched ref with that digest. The chart gets the
version of the next patch with `-rc.0` (for example `1.0.2-rc.0` while the chart is 1.0.1). That
version is never published; it only makes the newest final chart the previous one. The manifest
records the digest the run qualified, so a release can promote a candidate whose digest a run
already qualified without publishing a candidate chart. The chart at that ref must be 1.0.4
or later, for step 7 as above.

Every night at 04:17 UTC the workflow qualifies `edge` the same way, so a candidate built from
`main` usually arrives qualified.

The previous chart is the newest final `x.y.z` version in the
[next-charts index](https://veecode-platform.github.io/next-charts/index.yaml) that
is older than the candidate. For an `x.y.z-rc.N` candidate, the final `x.y.z`
release is the exclusive upper bound, so the sequence cannot select a final
release newer than the candidate. Its package is downloaded and checked the same way.

## The jobs

| Job | What it does |
|---|---|
| Decide what the run qualifies | Runs the two tests above, compares the pull request with its base (`pr-scope.sh`), and outputs whether to run and whether the run is a self-test. A dispatch or the nightly always runs; for an image, it also resolves the tag to the digest both jobs install. |
| Sequence on KinD | Runs `sequence.sh`, described below. Uploads `qualification-sequence`, which holds the summary table, the logs, and the API responses of every step. |
| Browser on KinD | Runs `browser/run.sh`, then runs the two vulnerability scans below. Uploads `qualification-browser` (the Playwright report, traces, screenshots, and the cluster logs) and `qualification-scan` (`trivy.json` and `scan-summary.md` of the image, and `face-defaults/` with one report per plugin artifact). |
| Qualification | Passes only when every job the run decided on succeeded. |

## What the sequence asserts

The sequence has seven steps. After each of the first six it checks that:

- the good plugin is loaded, or absent, as the step expects, in
  `GET /api/extensions/loaded-plugins`;
- every enabled plugin of the product face is loaded, and the installer logs hold no
  `Cannot find module`, no `already registered`, and no warning about a skipped entry. This is
  `scripts/check-loaded-plugins.sh` of devportal-local, which the workflow fetches at a pinned
  commit and which reads the factory list and the logs of the portal pod through `kubectl`. A chart
  1.1.0 portal has no face file, so the check reads `/opt/app-root/src/factory-plugins.yaml`; an
  older portal without that file falls back to the face;
- on a chart 1.1.0 portal, the repositories of `/opt/app-root/src/factory-plugins.yaml` are the
  repositories of the enabled entries of the pinned catalog index (`check_factory_list`). Both
  lists are kept by hand, so this is the check that fails when they disagree;
- the backend logs `Marketplace installation service initialized (database-backed)`
  and not the fallback to file storage;
- the portal serves the broken package, which shows that the test-only catalog
  location works;
- the portal serves every package of its catalog index image, plus the broken
  package (`catalog-fixes`);
- the portal serves the index's `spec.version` of every package (`catalog-fixes`).
  A restart or an upgrade does not run the extensions package provider: Backstage
  keeps its next run in the database, up to 30 minutes after the last one, so each
  probe first triggers `extensions-package-provider` through the catalog scheduler
  route and waits up to five minutes for the new versions;
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
| 7 | Upgrades to the candidate again, with values that omit `guestAuth`. | | Guest sign-in turns off, see below. |

The good plugin is an OCI package of the index whose reference has no `!` plugin path.
A bundled plugin cannot hold a digest, so it could never satisfy the `resolved_digest`
check.

Step 6 shows that the marketplace change survived the restart, which only holds when
the marketplace stores its state in the database.

Step 7 is the upgrade a user gets from a chart that had guest sign-in on by default: the
values carry no `guestAuth`, so the chart default (off from 1.0.4) must apply. Steps 1 to 6
keep `global.veecode.guestAuth.enabled: true` in `values/sequence.yaml`, because `lib.sh`
takes its API token from the guest sign-in. Step 7 derives its values from that file with
`yq 'del(.global.veecode.guestAuth)'`, so the two differ in that key alone, and upgrades the
release without `--reuse-values`. It asserts that:

- guest sign-in issued a token before the upgrade, so the step shows a change from on to off;
- the upgrade values do not set `guestAuth`;
- the portal reports ready on `/.backstage/health/v1/readiness`;
- `GET /api/auth/guest/refresh` no longer issues a token. The check does not pin the status
  the backend answers, only that no `backstageIdentity.token` comes back, and it records the
  status in the table. It fails when no status comes back at all, as when the portal cannot be
  reached, so an unreachable portal never passes. Only a copy of the response with the value of every
  key ending in `token` or `Token` blanked reaches the output directory; the raw response stays in a temporary file;
- the ConfigMap `veecode-auth`, which carries the guest provider, is gone.

Step 1 turns guest on with values, so the check does not depend on the default of the
previous chart: once 1.0.4 is the previous chart, its default is already off and the step
still goes from on to off. No tag skips it in a self-test. A candidate older than 1.0.4, such
as a dispatch of a published older version, leaves guest on by default and fails it.

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

The image scan has no tag. A self-test qualifies the qualification, not an image, so its
scan runs in report mode; a fresh vulnerability in the pinned image would otherwise turn a
pull request red that changed nothing about it. A run that qualifies a candidate (a pull
request that changes the pinned image or catalog index, or a dispatch without `self_test`) blocks.

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
Keycloak with the upstream library's `LoginHelper`. Guest sign-in is off by default, so
`browser/values-oidc.yaml` sets `global.veecode.guestAuth.enabled: true`. The exit code of `run.sh` is the result.

The two scans follow the specs and run even when they fail.

## The vulnerability scans

**The image scan** (`scan/run.sh`) scans the candidate's image, which the chart pins by digest,
with Trivy at the version and checksum pinned in `run.sh`. One scan produces the full report,
every severity, in `qualification-scan`, and the counts by severity go to the job summary. The
job fails on:

- a critical vulnerability with a fix that no live exception covers, the rule of
  `--severity CRITICAL --ignore-unfixed --exit-code 1`;
- a finding whose exception has expired, whatever its severity or fix status. Trivy drops an
  expired entry before it matches, so the finding comes back at its own severity and a high
  would pass. `check-ignorefile.sh` lists the IDs of the expired entries and `run.sh` blocks on
  every finding with one of them. The match is by ID alone: an entry's `paths` and `purls`
  are not considered, which errs on the side of blocking. An expired entry with no finding
  blocks nothing;
- an exception file that fails `check-ignorefile.sh`, because Trivy treats `statement` and
  `expired_at` as optional;
- a scan that did not run, so no run passes without the report.

`MODE=report` runs the same scan and exits 0 whatever it finds; only a scan that did not run
still fails. The exceptions live in
[`.trivyignore.yaml`](../.trivyignore.yaml), which explains the fields.

**The face-default scan** (`scan/face-defaults.sh`) scans the plugin artifacts that leave the
image. It reads `dynamic-plugins.default.yaml` of the catalog index the chart pins
(`global.catalogIndex.image`), copied with `skopeo`, takes every `oci://` entry that is not
`disabled: true`, and runs `run.sh` in report mode on each one by digest, with no exceptions. The
index file is the source, not the installer's log, because the log also names the plugins the
marketplace installed and follows the installer's wording. The step takes no count from the index:
whatever it enables is scanned.

It writes `face-defaults/summary.md`, a table with one row per artifact that goes to the job
summary, and the `trivy.json` and `scan-summary.md` of each artifact next to it. The step never
fails the job, not on a finding and not on an artifact it could not scan; the row says what
happened. An entry without a digest is listed and not scanned.

An artifact is an OCI image whose layer holds the plugin's `package.json`, and `node_modules`
for a backend plugin. Trivy parses those as Node packages, and the `Packages` column counts
them: 1 is the plugin's own `package.json`, and a row reads "no packages found" when Trivy
parsed none. Code bundled into a frontend plugin's files is not visible to Trivy.

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

| Value | What it breaks | What goes red, on a chart of 1.0.4 or later |
|---|---|---|
| `missing-plugin` | The sequence expects two plugins that the portal does not have: the good plugin gets another name, and the factory list that the loaded-plugins check reads gets one more entry (the face, on an older portal). | Sequence on KinD, and Qualification. |
| `failed-sign-in` | The specs sign in to Keycloak with a password that the realm does not hold. | Browser on KinD, and Qualification. |

Dispatch it with a self-test of a published version, for example:

```bash
gh workflow run qualification.yaml -R veecode-platform/devportal-chart --ref BRANCH \
  -f chart_version=1.0.4 -f self_test=true -f inject_failure=missing-plugin
```

Use a chart of 1.0.4 or later. On an older chart step 7 fails in the sequence job whatever
the injection, so that job goes red for every value and the table no longer holds.

On a chart of 1.0.4 or later, the run must go red, and only the job that the value breaks.
A dispatch's concurrency group holds its ref, `chart_version`, `self_test` and `inject_failure`,
so an injected run, a self-test and a full run of the same version never cancel each other.

The scan needs no injection: a dispatch without `self_test` of a chart of 1.0.4 or later whose
image has a critical vulnerability with a fix goes red on the image scan step, and on nothing else.

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
is its default. `scan/face-defaults.sh DPDY_FILE` needs the same plus `yq` 4.
`scan/test.sh` checks both against fixtures, with no Trivy, no network and no image.
