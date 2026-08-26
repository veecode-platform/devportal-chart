# AGENTS.md — drift manifest for devportal-chart

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
- The public distribution channel is veecode-platform/next-charts; this
  repository's publish workflow opens a package-only PR there.

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
| charts/backstage/values.yaml | Promotes the proven VeeCode plugin/config/image defaults into the product chart, keeps only host and runtime-secret overrides for consumers, adds the VeeCode pre-step inputs, and enables Kubernetes-plugin RBAC by default. | Values are an overlay on upstream defaults; review changed upstream keys and preserve the VeeCode defaults when regenerating this file. |
| charts/backstage/vendor/backstage/charts/backstage/templates/backstage-deployment.yaml | Adds the chart-owned pre-install command seam and filters the removable guest-auth ConfigMap from volumes, mounts, and config arguments. The installer name remains install-dynamic-plugins. | This is the one vendored upstream template patch. Reapply it after every vendor refresh; do not edit generated charts/*.tgz files. |
| charts/backstage/templates/veecode-configmaps.yaml | Creates the branding, guest-auth, and extensions ConfigMaps from chart files. | New chart-owned template; upstream updates should not overwrite it. |
| charts/backstage/templates/kubernetes-plugin-rbac.yaml | Ships the read-only ClusterRole and ClusterRoleBinding required by the Kubernetes plugin, gated by a values flag. | New chart-owned template; keep the rule set least-privilege and review new plugin API needs explicitly. |
| charts/backstage/files/veecode/app-config.veecode-auth.yaml | Carries the loud, removable guest-to-admin auth fragment as a chart file. | New product artifact; preserve its warning header byte-for-byte unless the security posture is intentionally changed. |
| charts/backstage/files/veecode/app-config.veecode-branding.yaml | Carries the VeeCode branding fragment and base64 logo without inflating values.yaml. | New product artifact; do not inline or replace the logo without a branding decision. |
| charts/backstage/files/veecode/app-config.extensions.yaml | Carries the marketplace installation/extraction config required by the VeeCode pre-step and restart path. | New product artifact; keep paths aligned with the shared devportal-data volume. |
| .github/workflows/publish-chart-release.yml | Packages charts/backstage on chart-v* or manual dispatch and attaches the package and checksum to a same-repository GitHub Release using GITHUB_TOKEN; it refuses an existing release with assets. | New VeeCode release path. The channel repository remains the owner of docs/index.yaml. |
| .github/workflows/bump-version.yaml | Removed inherited RHDH bot/version automation. | Resync must not restore it without a VeeCode release decision. |
| .github/workflows/nightly.yaml | Removed inherited nightly matrix that selects Red Hat RHDH/Quay images and release branches. | Resync must not restore it; any VeeCode nightly job needs its own image and branch contract. |
| .github/workflows/release.yaml | Removed inherited chart-releaser workflow for the upstream repository's release channel. | Publication is deliberately delegated to next-charts; do not reintroduce a second index owner. |
| .github/workflows/sync-lightspeed-configs.yaml | Removed inherited Red Hat AI Lightspeed sync and version-bump automation. | Lightspeed is not a VeeCode release dependency; add a separately reviewed workflow if that changes. |
| .github/workflows/sync-upstream-backstage.yaml | Removed inherited automatic Backstage subtree sync because it would bypass the pinned RHDH tag and the VeeCode patch review seam. | Resync is manual and pinned until a VeeCode-aware sync workflow is designed. |
| AGENTS.md | Records this fork's drift and resync discipline. | Must be updated whenever the table changes. |

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
