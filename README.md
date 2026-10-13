
# VeeCode DevPortal Helm chart

This repository contains the VeeCode DevPortal chart: a renamed fork of [redhat-developer/rhdh-chart](https://github.com/redhat-developer/rhdh-chart), pinned at `backstage-7.0.1`. VeeCode defaults are baked into the chart, which is published as `devportal` through the [`next-charts`](https://veecode-platform.github.io/next-charts) channel.

## Install — STAGING

The DevPortal 3.x installation instructions are **STAGING** until promoted: follow the [DevPortal 3.x preview install guide](https://docs-next.platform.vee.codes/devportal/installation-guide/v3-preview/intro/).

After preparing the Secret and `values.yaml` described there, install the newest version `helm search repo veecode/devportal --versions` lists:

```console
helm install devportal veecode/devportal --version <version> -n devportal --create-namespace -f values.yaml
```

Guest sign-in is off by default. To evaluate the portal, set `global.veecode.guestAuth.enabled: true`. With it on, any visitor who signs in as a guest gets the `ADMIN` user. Do not expose a portal with guest sign-in on: configure a real authentication provider first.

## Upstream attribution and license

The fork retains the upstream RHDH chart lineage and Apache-2.0 licensing; see [LICENSE](LICENSE). The upstream chart was consolidated with the deprecated [`rhdh-bot/openshift-helm-charts`](https://github.com/rhdh-bot/openshift-helm-charts/) repository as recorded in [RHIDP-1477](https://issues.redhat.com/browse/RHIDP-1477). The upstream-shaped chart documentation remains in [charts/backstage/README.md](charts/backstage/README.md).

## Drift manifest

The pinned upstream baseline, VeeCode-owned seams, and resync rules are documented in [docs/upstream-drift.md](docs/upstream-drift.md).
