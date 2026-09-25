# Agent Guidelines

This repository is the VeeCode DevPortal Helm chart, a fork of
[redhat-developer/rhdh-chart](https://github.com/redhat-developer/rhdh-chart).
The product chart lives in `charts/backstage` and is published as `devportal`.
It installs `docker.io/veecode/devportal`, pinned by digest.

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
pre-commit run --all-files   # needs helm-docs; regenerates README.md and values.schema.json
ct lint --config ct-lint.yaml --target-branch main
```

## Invariants

- `appVersion` equals `upstream.backstage.image.tag`, and `image.digest` is the
  digest the registry serves for that tag. The digest wins over the tag at
  install time. `hack/check-image-pin.py` enforces both.
- `global.dynamic.includes` keeps `dynamic-plugins.default.yaml` and
  `/opt/app-root/src/dynamic-plugins.veecode.yaml`. The values schema rejects a
  list without them, including in the CI values.
- Every chart change bumps `version`, and a merged version is released right
  away with its `chart-v<version>` tag.

## Release path

A `chart-v<version>` tag runs `publish-chart-release.yml`, which creates the
GitHub Release. `veecode-platform/next-charts` then imports it with
`ingest-devportal-chart`, and `veecode-platform/devportal-local` opens its pin
pull request from the newest tag once a day.
