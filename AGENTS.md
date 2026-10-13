# Agent Guidelines

This repository is the VeeCode DevPortal Helm chart, a fork of
[redhat-developer/rhdh-chart](https://github.com/redhat-developer/rhdh-chart).
The product chart lives in `charts/backstage` and is published as `devportal`.
It installs `docker.io/veecode/devportal` and the plugin catalog index
`quay.io/veecode/plugin-catalog-index`, each pinned by digest.

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the change checklist and the release
rules. Read [docs/upstream-drift.md](docs/upstream-drift.md) before editing any
upstream-shaped file, and update its table in the same change. Platform
vocabulary (image, chart, product face, catalog index) lives in
`devportal-planning/CONTEXT.md`.

## Verify a change

```bash
helm dependency build charts/backstage
for f in charts/backstage/ci/*-values.yaml; do helm template t charts/backstage -f "$f" > /dev/null; done
python3 hack/check-image-pin.py charts/backstage
python3 hack/catalog-index-pin.py check
python3 hack/test-catalog-index-pin.py
pre-commit run --all-files   # needs helm-docs; regenerates README.md and values.schema.json
ct lint --config ct-lint.yaml --target-branch main
```

## Invariants

- `appVersion` equals `upstream.backstage.image.tag`, and `image.digest` is the
  digest the registry serves for that tag. The digest wins over the tag at
  install time. `hack/check-image-pin.py` enforces both.
- `global.catalogIndex.image` pins the plugin catalog index by digest:
  `repository` ends in `@sha256` and `tag` holds the 64 hex digits. The registry
  must serve that digest, and a `bs_<version>_<timestamp>` tag must point at it:
  nothing re-points that tag, so the registry keeps the digest after the moving
  tag moves on. `hack/catalog-index-pin.py check` enforces both, and the values
  schema rejects a tag that is not a digest on a `@sha256` repository.
- `global.dynamic.includes` keeps `dynamic-plugins.default.yaml` and
  `/opt/app-root/src/dynamic-plugins.veecode.yaml`. The values schema rejects a
  list without them, including in the CI values.
- Every chart change bumps `version`, and a merged version is released right
  away with its `chart-v<version>` tag.

## Release path

Every chart release re-pins the catalog index first:
`python3 hack/catalog-index-pin.py pin` rewrites `global.catalogIndex.image` to
the current digest of `bs_1.52.0`, and the release pull request carries the
result.

A `chart-v<version>` tag runs `publish-chart-release.yml`, which creates the
GitHub Release. `veecode-platform/next-charts` then imports it with
`ingest-devportal-chart`, and `veecode-platform/devportal-local` opens its pin
pull request from the newest tag once a day.
