# Upstream drift manifest

This repository is a VeeCode fork of
[redhat-developer/rhdh-chart](https://github.com/redhat-developer/rhdh-chart)
for the VeeCode DevPortal product. The product chart is the upstream-shaped
directory charts/backstage; its directory name is intentionally retained so
future upstream subtree refreshes remain mechanically recognizable. Its
published identity is devportal, not backstage.

The current upstream baseline is the RHDH chart backstage-7.0.1 at commit
e476f2987dc3a4d764b10fab5c2fa9958f70c2d0. The chart has its own version
sequence beginning at 0.1.0; upstream lineage belongs in Chart.yaml
annotations and must not be encoded by reusing the upstream version.

## Branch and ownership rules

- `main` is the product branch for this fork (renamed from `veecode/main` on 2026-08-26; the former upstream mirror `main` is now `upstream/main`).
- Upstream lineage is the pinned RHDH tag and commit above. A resync must
  explicitly choose and record a new upstream tag/commit.
- Feature work stays in pull requests. The working tree may be inspected with
  uncommitted changes, but publication and commits belong to the orchestrator.
- The public distribution channel is veecode-platform/next-charts. This
  repository's publish workflow creates a GitHub Release with the package and
  checksum; next-charts imports it with its `ingest-devportal-chart` workflow.

## Additive-first rule

Prefer new chart files and values seams over edits to upstream-shaped files.
When an upstream-shaped edit is unavoidable, keep it localized, update this
manifest in the same change, and revalidate the rendered chart. A change that
is not listed here is eligible to disappear during the next upstream resync.

- baseUrl scheme is hardcoded https in the vendored template; a scheme/URL override in values would let local evaluators keep the minimal values file (candidate for 0.1.1, decision pending)

## Drift manifest

| Path | Why | Upstream impact |
|---|---|---|
| charts/backstage/Chart.yaml | Renames the published chart to devportal, starts VeeCode versioning at 0.1.0, records the RHDH lineage, and points metadata at VeeCode. | Must be reconciled if upstream changes chart metadata or dependency versions; keep the lineage annotations truthful. |
| charts/backstage/values.yaml | Promotes the proven VeeCode plugin/config/image defaults into the product chart, keeps only host and runtime-secret overrides for consumers, adds the VeeCode pre-step inputs, maps both PG_* and POSTGRES_* from the runtime Secret into the installer init container, and enables Kubernetes-plugin RBAC by default. It also defines opt-in CA trust and rollout deadline settings, plus optional namespace-qualified RBAC names. | Values are an overlay on upstream defaults; review changed upstream keys and preserve the VeeCode defaults when regenerating this file. The CA and deadline values are VeeCode extensions; their unset defaults keep the rendered Deployment unchanged. |
| `global.veecode.deployment.caBundle` (`charts/backstage/values.yaml`) | Names an existing ConfigMap or Secret and its data key for an extra CA bundle. | RHDH has no one-value equivalent; the vendored Deployment patch appends the volume, mount, and `NODE_EXTRA_CA_CERTS` only when a name is set. |
| `global.veecode.deployment.progressDeadlineSeconds` (`charts/backstage/values.yaml`) | Optionally sets the Deployment rollout deadline; `0` leaves the field absent and keeps Kubernetes' 600-second default. | RHDH has no equivalent setting. The vendored Deployment patch renders this field only for a positive value. |
| `kubernetesPlugin.rbac.namespaceQualifiedName` (`charts/backstage/values.yaml`) | Opts into appending the release namespace to the Kubernetes plugin ClusterRole and ClusterRoleBinding names. | VeeCode-specific opt-in for same-named releases in different namespaces; `false` keeps today's names. |
| charts/backstage/vendor/backstage/charts/backstage/templates/backstage-deployment.yaml | Adds the chart-owned pre-install command seam, filters the removable guest-auth ConfigMap from volumes, mounts, and config arguments, and conditionally adds CA bundle wiring and `progressDeadlineSeconds`. The installer name remains install-dynamic-plugins. | This is the one vendored upstream template patch. Reapply it after every vendor refresh; do not edit generated charts/*.tgz files. |
| charts/backstage/templates/veecode-configmaps.yaml | Creates the branding, guest-auth, and extensions ConfigMaps from chart files. | New chart-owned template; upstream updates should not overwrite it. |
| charts/backstage/templates/kubernetes-plugin-rbac.yaml | Ships the read-only ClusterRole and ClusterRoleBinding required by the Kubernetes plugin, gated by values; an opt-in suffix prevents same-named releases in different namespaces from colliding. | New chart-owned template; keep the rule set least-privilege and review new plugin API needs explicitly. |
| charts/backstage/files/veecode/app-config.veecode-auth.yaml | Carries the loud, removable guest-to-admin auth fragment as a chart file. | New product artifact; preserve its warning header byte-for-byte unless the security posture is intentionally changed. |
| charts/backstage/files/veecode/app-config.veecode-branding.yaml | Carries the VeeCode branding fragment and base64 logo without inflating values.yaml. | New product artifact; do not inline or replace the logo without a branding decision. |
| charts/backstage/files/veecode/app-config.extensions.yaml | Carries the marketplace installation/extraction config required by the VeeCode pre-step and restart path. | New product artifact; keep paths aligned with the shared devportal-data volume. |
| .github/workflows/publish-chart-release.yml | Packages charts/backstage on chart-v* or manual dispatch and attaches the package and checksum to a same-repository GitHub Release using GITHUB_TOKEN; it refuses an existing release with assets. For versions containing a hyphen, `gh release create` marks the release as a prerelease and passes `--latest=false`. | New VeeCode release path. The channel repository remains the owner of docs/index.yaml. |
| .github/workflows/qualification.yaml | Qualifies a chart candidate on KinD in two parallel jobs. The sequence covers the previous final chart, a marketplace install, the upgrade, a broken marketplace package, restarts, a rollback that restores the database, and devportal-local's loaded-plugins check at a pinned commit. It accepts published `x.y.z` and `x.y.z-rc.N` versions. The sequence artifact contains the candidate manifest, and the workflow appends it to the step summary after the complete results table. The browser job runs the specs, an image scan that blocks (report-only in a self-test), and a report-only scan of the OCI plugin artifacts the product face enables. A last job, Qualification, is the check to require. Runs on every pull request against main, where a first job decides whether anything needs qualifying, and on dispatch for a published package, with an input that breaks one job on purpose. Needs no repository secret. | New VeeCode workflow with no upstream counterpart. It has no path filter on purpose: a required check of a skipped workflow stays pending. |
| qualification/sequence.sh | Runs the qualification steps, asserts each one, including devportal-local's loaded-plugins check, packages a pull-request chart directory before installing it, and writes the manifest with the candidate deployment's image digest, catalog-index digest and source reference, plus the chart package checksum. | New VeeCode file. |
| qualification/lib.sh | Helpers the sequence sources: the checks table, the release download and checksum check, final-only previous-chart selection for final and release-candidate versions, manifest validation and writing, the throwaway database, the fixture server, and the portal API calls. The manifest resolves the deployment's catalog-index reference with `skopeo inspect`, records that reference alongside its digest, and fails if resolution fails or returns an invalid digest. Release and index URLs can be overridden for local fixtures. | New VeeCode file. |
| qualification/values/sequence.yaml | Test-only values: the port-forward URLs and the catalog location that serves the broken package. | New VeeCode file; none of it is a product default. |
| qualification/fixtures/broken-package.yaml | A Package entity whose artifact does not exist, served only through the qualification's catalog location. | New VeeCode file; it must never enter the overlays index. |
| qualification/README.md | How to run the qualification, what each job asserts, how the two vulnerability scans work, how to prove that it can fail, and the stable keys in the candidate manifest. | New VeeCode file. |
| qualification/test-release-helpers.sh | Uses local release and index fixtures to check release-candidate version acceptance, malformed-version and checksum rejection, environment overrides, final-only previous-chart selection for release-candidate and final versions, and resolution of the real moving catalog-index tag form. | New VeeCode test; RHDH has no equivalent. |
| .github/workflows/bump-version.yaml | Removed inherited RHDH bot/version automation. | Resync must not restore it without a VeeCode release decision. |
| .github/workflows/nightly.yaml | Removed inherited nightly matrix that selects Red Hat RHDH/Quay images and release branches. | Resync must not restore it; any VeeCode nightly job needs its own image and branch contract. |
| .github/workflows/release.yaml | Removed inherited chart-releaser workflow for the upstream repository's release channel. | Publication is deliberately delegated to next-charts; do not reintroduce a second index owner. |
| .github/workflows/sync-lightspeed-configs.yaml | Removed inherited Red Hat AI Lightspeed sync and version-bump automation. | Lightspeed is not a VeeCode release dependency; add a separately reviewed workflow if that changes. |
| .github/workflows/sync-upstream-backstage.yaml | Removed inherited automatic Backstage subtree sync because it would bypass the pinned RHDH tag and the VeeCode patch review seam. | Resync is manual and pinned until a VeeCode-aware sync workflow is designed. |
| charts/backstage/ci/*-values.yaml | Each CI scenario keeps both product includes (dynamic-plugins.default.yaml and the image-baked face) instead of the inherited empty list, because the VeeCode values schema rejects a list without them. The two orchestrator scenarios point SonataFlow at that CI database, since the bundled PostgreSQL is off. | Upstream CI values set includes to an empty list to skip plugin downloads; keep both entries when refreshing these files. |
| .github/actions/test-charts/action.yml | Runs a throwaway PostgreSQL, the veecode-runtime-secrets Secret and the orchestrator-ci-db Secret in the devportal-ci namespace and installs charts/backstage there. | The upstream action relies on the PostgreSQL subchart; keep this step after a resync, since the devportal chart disables that subchart. |
| qualification/browser/run.sh | The qualification's browser job: installs a candidate chart next to a PostgreSQL and a Keycloak it creates, runs the specs in qualification/browser/e2e, and exits with their result. It can give the specs a Keycloak password the realm does not hold, to prove the job goes red. | New VeeCode file; rhdh-chart has no browser qualification. |
| qualification/browser/keycloak.yaml, qualification/browser/realm.json | Keycloak from the official image in start-dev, and the realm, client and users it imports with credentials run.sh generates. | New VeeCode files. They replace the upstream e2e library's Keycloak chart, which needs OpenShift and Bitnami legacy images. |
| qualification/browser/values-oidc.yaml | The browser job's values: the portal on a port-forward, and guest plus OIDC sign-in through the in-cluster Keycloak. | New VeeCode file; follows the upstream e2e library's Keycloak app-config. |
| qualification/browser/e2e/ | Eleven specs adapted from redhat-developer/rhdh e2e-tests/playwright/e2e at 0a2efdf on @red-hat-developer-hub/e2e-test-utils, with a plain Playwright config. Each spec names its upstream source. | New VeeCode files. Refresh a spec by comparing it with its named source; library fixes arrive with a version bump in package.json and the lockfile. |
| charts/backstage/README.md.gotmpl | The title, TL;DR, prerequisites, usage, and Orchestrator sections describe VeeCode DevPortal from next-charts; Orchestrator uses external PostgreSQL, and the cluster-wide `redhat-developer-hub-orchestrator-infra` prerequisite comes from the Red Hat Developer Hub chart repository. | Keep the VeeCode install commands, external database contract, and external chart identity/source when refreshing the template. |
| .github/workflows/lint.yaml | Adds the image pin check before chart-testing. | Reapply after a resync of the inherited lint workflow. |
| hack/check-image-pin.py | Fails a pull request or release when appVersion differs from the image tag or the pinned digest is not what Docker Hub serves for that tag. | New VeeCode script; also called by publish-chart-release.yml. |
| .trivyignore.yaml | Lists the exceptions to the vulnerability gate. Trivy reads it only through `--ignorefile`, and each entry needs a statement and an expiry. | New VeeCode file with no upstream counterpart; a resync must not touch it. |
| qualification/scan/run.sh | Scans one image by digest with Trivy at a pinned version, writes the full report and a summary, and applies the blocking rule: a critical vulnerability with a fix that no live exception covers, and a finding of any severity whose exception has expired. It can ask Trivy to list every package it parsed. | New VeeCode script; RHDH scans in its internal pipeline, so there is nothing to copy. |
| qualification/scan/check-ignorefile.sh | Fails when an exception lacks a statement or a valid expiry, because Trivy treats both fields as optional, and lists the IDs of the expired entries for run.sh. | New VeeCode script; RHDH has no equivalent. |
| qualification/scan/test.sh, qualification/scan/fixtures/ | Run the exception check, the scan gate and the face-default scan against fixture files and a stub Trivy, with no network and no image. | New VeeCode test; RHDH has no equivalent. |
| qualification/scan/face-defaults.sh | Reads the product face from the running portal, scans by digest each OCI plugin artifact it enables with run.sh in report mode, and writes one report per artifact plus a summary table. It never fails the run. | New VeeCode script; RHDH scans in its internal pipeline, so there is nothing to copy. |
| docs/upstream-drift.md | Records this fork's drift and resync discipline. | Must be updated whenever the table changes. |
| ct-install.yaml | Drops `--debug` from `helm-extra-args`. With it, helm prints every rendered manifest, including the base64 branding logo, and ct fails with `signal: broken pipe` after a successful install. | The action still adds `--debug` when the job runs with runner debug on. |

The remaining inherited workflows are intentionally not listed as drift
because they are unchanged. The report for the milestone audits all of them:
generic lint/test, pre-commit, TOML, shellcheck, Renovate, and Snyk checks are
kept; upstream branch filters and any required external secrets remain review
items for the repository owner.

## Weekly resync discipline

1. Confirm the intended upstream tag and commit from
   redhat-developer/rhdh-chart; do not silently follow a moving branch.
2. Refresh the vendored upstream Backstage subtree and rebuild
   charts/backstage/Chart.lock only for the reviewed dependency set.
3. Reapply the localized deployment-template patch, then inspect the exact
   diff around init containers, ConfigMap mounts, and image rendering.
4. Recheck the VeeCode-owned files, values.yaml, chart identity annotations,
   the literal install-dynamic-plugins name, and the guest-auth off switch.
5. Run helm dependency build, helm lint, default rendering, and minimal
   consumer rendering. Verify that the installer volumes, ConfigMaps, and
   Kubernetes ClusterRole still appear.
6. Update this table and the report/evidence for the new baseline before the
   orchestrator commits. Never treat a clean merge as proof that a VeeCode
   seam survived; inspect the rendered manifest.

The intended consumer seam is small: set global.host (or explicit app/backend
base URLs) and upstream.backstage.extraEnvVarsSecrets. Do not replace
upstream.backstage.initContainers, extraVolumes, or extraVolumeMounts to
enable the marketplace pre-step. Guest auth is on by default for the stranger
test; turn it off with global.veecode.guestAuth.enabled: false and configure a
real provider.
