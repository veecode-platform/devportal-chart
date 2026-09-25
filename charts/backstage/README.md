
# VeeCode DevPortal Helm Chart

![Version: 0.1.25](https://img.shields.io/badge/Version-0.1.25-informational?style=flat-square)
![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square)

A Helm chart for deploying VeeCode DevPortal, a VeeCode distribution of Backstage.

**Homepage:** <https://docs.platform.vee.codes>

This chart installs VeeCode DevPortal, a fork of Red Hat Developer Hub. It is
published as `devportal` in the [next-charts](https://veecode-platform.github.io/next-charts)
Helm repository.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| VeeCode |  | <https://veecode.com> |

## Source Code

* <https://github.com/veecode-platform/devportal-chart>

## TL;DR

```console
helm repo add veecode https://veecode-platform.github.io/next-charts
helm install devportal veecode/devportal --version 0.1.25 -n devportal --create-namespace -f values.yaml
```

The [DevPortal 3.x install guide](https://docs-next.platform.vee.codes/devportal/installation-guide/v3-preview/intro/)
explains the runtime Secret and the `values.yaml` the install needs.

## Introduction

This chart bootstraps a [Backstage](https://backstage.io/docs/deployment/docker) deployment on a [Kubernetes](https://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

See [docs/product-face-overrides.md](../../docs/product-face-overrides.md) for how the VeeCode product face (`global.dynamic.includes[0]`) is baked into the image and how to customize or disable individual face plugins without dropping the rest.

## Prerequisites

- Kubernetes 1.27+
- Helm 3.10+ or [latest release](https://github.com/helm/helm/releases)
- A PostgreSQL database. The chart ships no embedded database; it reads the connection from the `veecode-runtime-secrets` Secret.

## Usage

List the published versions and install the newest one:

```console
helm repo add veecode https://veecode-platform.github.io/next-charts
helm repo update
helm search repo veecode/devportal --versions
helm upgrade -i <release_name> veecode/devportal --version <version> -f values.yaml
```

Each chart version pins the portal image by digest, and `appVersion` names that image.

### Testing a Release

Once an Helm Release has been deployed, you can test it using the [`helm test`](https://helm.sh/docs/helm/helm_test/) command:

```sh
helm test <release_name>
```

This will run a simple Pod in the cluster to check that the application deployed is up and running.

You can control whether to disable this test pod or you can also customize the image it leverages.
See the `test.enabled` and `test.image` parameters in the [`values.yaml`](./values.yaml) file.

> **Tip**: Disabling the test pod will not prevent the `helm test` command from passing later on. It will simply report that no test suite is available.

Below are a few examples:

<details>

<summary>Disabling the test pod</summary>

```sh
helm install <release_name> <repo_or_oci_registry> \
  --set test.enabled=false
```

</details>

<details>

<summary>Customizing the test pod image</summary>

```sh
helm install <release_name> <repo_or_oci_registry> \
  --set test.image.repository=curl/curl-base \
  --set test.image.tag=8.11.1
```

</details>

### Uninstalling the Chart

To uninstall/delete the `my-backstage-release` deployment:

```console
helm uninstall my-backstage-release
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Requirements

Kubernetes: `>= 1.27.0-0`

| Repository | Name | Version |
|------------|------|---------|
| file://./vendor/backstage/charts/backstage/ | upstream(backstage) | 2.8.0 |
| https://charts.bitnami.com/bitnami | common | 2.40.0 |

## Values

| Key | Description | Type | Default |
|-----|-------------|------|---------|
| global.auth | Enable service authentication within Backstage instance | object | `{"backend":{"enabled":false,"existingSecret":"","value":""}}` |
| global.auth.backend | Backend service to service authentication <br /> Ref: https://backstage.io/docs/auth/service-to-service-auth/ | object | `{"enabled":false,"existingSecret":"","value":""}` |
| global.auth.backend.enabled | Enable backend service to service authentication, unless configured otherwise it generates a secret value | bool | `false` |
| global.auth.backend.existingSecret | Instead of generating a secret value, refer to existing secret | string | `""` |
| global.auth.backend.value | Instead of generating a secret value, use the following value | string | `""` |
| global.catalogIndex | Catalog index configuration for automatic plugin discovery. The `install-dynamic-plugins.py` script pulls this image if the `CATALOG_INDEX_IMAGE` environment variable is set. The `dynamic-plugins.default.yaml` file will be extracted and written to `dynamic-plugins-root` volume mount. | object | `{"extraImages":[],"image":{"registry":"quay.io","repository":"veecode/plugin-catalog-index","tag":"bs_1.52.0"}}` |
| global.catalogIndex.extraImages | Extra catalog index images for additional plugin discovery in the Extensions UI. Each item must include `registry`, `repository`, and `tag` fields; `name` is optional. Only catalog entities are extracted from extra images (no `dynamic-plugins.default.yaml` handling). | list | `[]` |
| global.clusterRouterBase | Shorthand for users who do not want to specify a custom HOSTNAME. Used ONLY with the DEFAULT upstream.backstage.appConfig value and with OCP Route enabled. | string | `"apps.example.com"` |
| global.dynamic.includes[0] |  | string | `"dynamic-plugins.default.yaml"` |
| global.dynamic.includes[1] |  | string | `"/opt/app-root/src/dynamic-plugins.veecode.yaml"` |
| global.dynamic.plugins |  | list | `[]` |
| global.host | Custom hostname shorthand, overrides `global.clusterRouterBase`, `upstream.ingress.host`, `route.host`, and url values in `upstream.backstage.appConfig`. | string | `""` |
| global.lightspeed | Built-in Lightspeed feature configuration. | object | Use Lightspeed compatible settings / configurations. |
| global.lightspeed.configMaps[0].create | Whether to create this ConfigMap from the bundled source file. Set to false and provide `nameOverride` to use a pre-existing ConfigMap. | bool | `true` |
| global.lightspeed.configMaps[0].nameOverride | Name of an existing ConfigMap to use instead. Required when `create` is false. | string | `""` |
| global.lightspeed.configMaps[0].sourceFile | Bundled file used to populate the ConfigMap data when `create` is true. | string | `"lightspeed-stack.yaml"` |
| global.lightspeed.configMaps[1].create | Whether to create this ConfigMap from the bundled source file. Set to false and provide `nameOverride` to use a pre-existing ConfigMap. | bool | `true` |
| global.lightspeed.configMaps[1].nameOverride | Name of an existing ConfigMap to use instead. Required when `create` is false. | string | `""` |
| global.lightspeed.configMaps[1].sourceFile | Bundled file used to populate the ConfigMap data when `create` is true. | string | `"config.yaml"` |
| global.lightspeed.configMaps[2].create | Whether to create this ConfigMap from the bundled source file. Set to false and provide `nameOverride` to use a pre-existing ConfigMap. | bool | `true` |
| global.lightspeed.configMaps[2].nameOverride | Name of an existing ConfigMap to use instead. Required when `create` is false. | string | `""` |
| global.lightspeed.configMaps[2].sourceFile | Bundled file used to populate the ConfigMap data when `create` is true. | string | `"rhdh-profile.py"` |
| global.lightspeed.enabled | Enable or disable the built-in Lightspeed feature. FIXME: temporarily disabled due to DPDY issues; to re-enable in [RHIDP-15458](https://redhat.atlassian.net/browse/RHIDP-15458) | bool | `false` |
| global.lightspeed.initContainer.image | Full image reference for the Lightspeed RAG bootstrap init container. Override for disconnected environments. | string | `"quay.io/redhat-ai-dev/rag-content:release-1.10-lls-0.5.0-8c231a3b5177f12fff9db042dfa4091d8f2f26b3"` |
| global.lightspeed.initContainer.resources | Resource requests/limits for the Lightspeed RAG bootstrap init container. | object | `{"limits":{"cpu":"100m","memory":"500Mi"},"requests":{"cpu":"50m","memory":"150Mi"}}` |
| global.lightspeed.plugins | Lightspeed plugins and their configuration. Override package references for disconnected environments. | list | `[{"enabled":true,"package":"oci://registry.access.redhat.com/rhdh/red-hat-developer-hub-backstage-plugin-lightspeed:{{ \"{{inherit}}\" }}"},{"enabled":true,"package":"oci://registry.access.redhat.com/rhdh/red-hat-developer-hub-backstage-plugin-lightspeed-backend:{{ \"{{inherit}}\" }}"}]` |
| global.lightspeed.ragVolume.emptyDir | `emptyDir` configuration for the RAG data volume. | object | `{}` |
| global.lightspeed.ragVolume.initMountPath | Mount path inside the init container for seeding RAG data. | string | `"/rag-content"` |
| global.lightspeed.ragVolume.mountPath | Mount path inside the sidecar container for serving RAG data. | string | `"/rag-content"` |
| global.lightspeed.ragVolume.name | Name of the Kubernetes volume used for Lightspeed RAG data. | string | `"lightspeed-rag"` |
| global.lightspeed.runtimeVolume.emptyDir | `emptyDir` configuration for the Lightspeed runtime data volume when `runtimeVolume.type=emptyDir`. | object | `{}` |
| global.lightspeed.runtimeVolume.mountPath | Mount path inside the container for Lightspeed runtime storage. | string | `"/tmp"` |
| global.lightspeed.runtimeVolume.name | Name of the Kubernetes volume used for writable Lightspeed runtime storage. | string | `"lightspeed-data"` |
| global.lightspeed.runtimeVolume.persistentVolumeClaim | Existing PVC reference for the Lightspeed runtime data volume when `runtimeVolume.type=persistentVolumeClaim`. | object | `{}` |
| global.lightspeed.runtimeVolume.type | Volume source used for writable Lightspeed runtime storage mounted at `/tmp`. Supported values: `emptyDir`, `persistentVolumeClaim`. | string | `"emptyDir"` |
| global.lightspeed.secret.create | Whether to create a Lightspeed Secret from the bundled source file. | bool | `true` |
| global.lightspeed.secret.name | Name of an existing Secret to use instead. Required when `create` is false. | string | `""` |
| global.lightspeed.secret.optional | Whether the Secret reference is optional in the pod spec. | bool | `false` |
| global.lightspeed.secret.sourceFile | Bundled file used to populate the Secret's `stringData` keys. | string | `"secret.yaml"` |
| global.lightspeed.sidecar.image | Full image reference for the Lightspeed Core sidecar. Override for disconnected environments. | string | `"quay.io/lightspeed-core/lightspeed-stack:0.5.3"` |
| global.lightspeed.sidecar.resources | Resource requests/limits for the Lightspeed Core sidecar. | object | `{"limits":{"cpu":"1000m","memory":"2Gi"},"requests":{"cpu":"100m","memory":"512Mi"}}` |
| global.veecode.branding | config chain (see extraAppConfig veecode-product), so these win. | object | `{"fullLogo":"","fullLogoWidth":180,"iconLogo":"","title":"VeeCode DevPortal"}` |
| global.veecode.guestAuth.enabled |  | bool | `true` |
| global.veecode.preInstallCommand |  | string | `"node regenerate-extensions-install.js --config app-config.yaml --config app-config.example.yaml --config app-config.example.production.yaml --config app-config-from-configmap.yaml && node merge-dynamic-plugins.js"` |
| global.veecode.support.docsUrl |  | string | `"https://github.com/veecode-platform/support/discussions"` |
| global.veecode.support.subtitle |  | string | `"VeeCode DevPortal support"` |
| global.veecode.support.url |  | string | `"https://github.com/veecode-platform/support/discussions"` |
| kubernetesPlugin.rbac.enabled | Grant the chart's service account read-only access used by the Kubernetes plugin. | bool | `true` |
| kubernetesPlugin.rbac.serviceAccountName | Optional override; empty follows the upstream chart's generated service account name. | string | `""` |
| nameOverride |  | string | `"developer-hub"` |
| orchestrator.enabled |  | bool | `false` |
| orchestrator.plugins | Orchestrator plugins and their configuration | list | `[{"enabled":true,"package":"oci://registry.access.redhat.com/rhdh/red-hat-developer-hub-backstage-plugin-orchestrator-backend:{{ \"{{inherit}}\" }}"},{"enabled":true,"package":"oci://registry.access.redhat.com/rhdh/red-hat-developer-hub-backstage-plugin-orchestrator-form-widgets:{{ \"{{inherit}}\" }}"},{"enabled":true,"package":"oci://registry.access.redhat.com/rhdh/red-hat-developer-hub-backstage-plugin-orchestrator:{{ \"{{inherit}}\" }}"},{"enabled":true,"package":"oci://registry.access.redhat.com/rhdh/red-hat-developer-hub-backstage-plugin-scaffolder-backend-module-orchestrator:{{ \"{{inherit}}\" }}"}]` |
| orchestrator.serverlessLogicOperator.enabled |  | bool | `true` |
| orchestrator.serverlessOperator.enabled |  | bool | `true` |
| orchestrator.sonataflowPlatform.createDBJobImage | Image for the container used by the create-db job | string | `"{{ .Values.upstream.postgresql.image.registry }}/{{ .Values.upstream.postgresql.image.repository }}:{{ .Values.upstream.postgresql.image.tag }}"` |
| orchestrator.sonataflowPlatform.dataIndexImage | Image for the container used by the sonataflow data index, optional and used for disconnected environments | string | `""` |
| orchestrator.sonataflowPlatform.dbCreationJobActiveDeadlineSeconds | Maximum time in seconds for the Sonataflow database creation Job to complete before being terminated | int | `120` |
| orchestrator.sonataflowPlatform.dbCreationJobBackoffLimit | Number of retries for the Sonataflow database creation job if it fails | int | `2` |
| orchestrator.sonataflowPlatform.dbCreationJobTTLSecondsAfterFinished | Time in seconds after which the Sonataflow database creation Job is automatically deleted. Leave empty to disable (recommended for GitOps/ArgoCD) | int | `nil` |
| orchestrator.sonataflowPlatform.eventing.broker.name |  | string | `""` |
| orchestrator.sonataflowPlatform.eventing.broker.namespace |  | string | `""` |
| orchestrator.sonataflowPlatform.externalDBHost | Host for the user-configured external Database | string | `""` |
| orchestrator.sonataflowPlatform.externalDBName | Name for the user-configured external Database | string | `""` |
| orchestrator.sonataflowPlatform.externalDBPort | Port for the user-configured external Database | string | `""` |
| orchestrator.sonataflowPlatform.externalDBsecretRef | Secret name for the user-created secret to connect an external DB | string | `""` |
| orchestrator.sonataflowPlatform.initContainerImage | Image for the init container used by the create-db job | string | `"{{ .Values.upstream.postgresql.image.registry }}/{{ .Values.upstream.postgresql.image.repository }}:{{ .Values.upstream.postgresql.image.tag }}"` |
| orchestrator.sonataflowPlatform.jobServiceImage | Image for the container used by the sonataflow jobs service, optional and used for disconnected environments | string | `""` |
| orchestrator.sonataflowPlatform.monitoring.enabled |  | bool | `true` |
| orchestrator.sonataflowPlatform.resources.limits.cpu |  | string | `"500m"` |
| orchestrator.sonataflowPlatform.resources.limits.memory |  | string | `"1Gi"` |
| orchestrator.sonataflowPlatform.resources.requests.cpu |  | string | `"250m"` |
| orchestrator.sonataflowPlatform.resources.requests.memory |  | string | `"64Mi"` |
| permission.enabled |  | bool | `false` |
| route | OpenShift Route parameters | object | `{"annotations":{},"enabled":false,"host":"{{ .Values.global.host }}","path":"/","tls":{"caCertificate":"","certificate":"","destinationCACertificate":"","enabled":true,"insecureEdgeTerminationPolicy":"Redirect","key":"","termination":"edge"},"wildcardPolicy":"None"}` |
| route.annotations | Route specific annotations | object | `{}` |
| route.enabled | Enable the creation of the route resource | bool | `false` |
| route.host | Set the host attribute to a custom value. If not set, OpenShift will generate it, please make sure to match your baseUrl | string | `"{{ .Values.global.host }}"` |
| route.path | Path that the router watches for, to route traffic for to the service. | string | `"/"` |
| route.tls | Route TLS parameters <br /> Ref: https://docs.openshift.com/container-platform/4.9/networking/routes/secured-routes.html | object | `{"caCertificate":"","certificate":"","destinationCACertificate":"","enabled":true,"insecureEdgeTerminationPolicy":"Redirect","key":"","termination":"edge"}` |
| route.tls.caCertificate | Cert authority certificate contents. Optional | string | `""` |
| route.tls.certificate | Certificate contents | string | `""` |
| route.tls.destinationCACertificate | Contents of the ca certificate of the final destination. <br /> When using reencrypt termination this file should be provided in order to have routers use it for health checks on the secure connection. If this field is not specified, the router may provide its own destination CA and perform hostname validation using the short service name (service.namespace.svc), which allows infrastructure generated certificates to automatically verify. | string | `""` |
| route.tls.enabled | Enable TLS configuration for the host defined at `route.host` parameter | bool | `true` |
| route.tls.insecureEdgeTerminationPolicy | Indicates the desired behavior for insecure connections to a route. <br /> While each router may make its own decisions on which ports to expose, this is normally port 80. The only valid values are None, Redirect, or empty for disabled. | string | `"Redirect"` |
| route.tls.key | Key file contents | string | `""` |
| route.tls.termination | Specify TLS termination. | string | `"edge"` |
| route.wildcardPolicy | Wildcard policy if any for the route. Currently only 'Subdomain' or 'None' is allowed. | string | `"None"` |
| test | Test pod parameters | object | `{"enabled":false,"image":{"registry":"quay.io","repository":"curl/curl","tag":"latest"},"injectTestNpmrcSecret":false}` |
| test.enabled | Whether to enable the test-connection pod used for testing the Release using `helm test`. | bool | `false` |
| test.image.registry | Test connection pod image registry | string | `"quay.io"` |
| test.image.repository | Test connection pod image repository. Note that the image needs to have both the `sh` and `curl` binaries in it. | string | `"curl/curl"` |
| test.image.tag | Test connection pod image tag. Note that the image needs to have both the `sh` and `curl` binaries in it. | string | `"latest"` |
| test.injectTestNpmrcSecret | Whether to inject a fake dynamic plugins npmrc secret. <br />See RHDHBUGS-1893 and RHDHBUGS-1464 for the motivation behind this. <br />This is only used for testing purposes and should not be used in production. <br />Only relevant when `test.enabled` field is set to `true`. | bool | `false` |
| upstream | Upstream Backstage [chart configuration](https://github.com/backstage/charts/blob/main/charts/backstage/values.yaml) | object | Use Openshift compatible settings |
| upstream.backstage.extraVolumes[0] | Ephemeral volume that will contain the dynamic plugins installed by the initContainer below at start. | object | `{"ephemeral":{"volumeClaimTemplate":{"spec":{"accessModes":["ReadWriteOnce"],"resources":{"requests":{"storage":"5Gi"}}}}},"name":"dynamic-plugins-root"}` |
| upstream.backstage.extraVolumes[0].ephemeral.volumeClaimTemplate.spec.resources.requests.storage | Size of the volume that will contain the dynamic plugins. It should be large enough to contain all the plugins. | string | `"5Gi"` |
| upstream.backstage.extraVolumes[5] | Ephemeral volume used by the install-dynamic-plugins init container to extract catalog entities from the catalog index image. Mounted at the /extensions path in the backstage-backend main container for automatic discovery by the extension catalog backend providers. | object | `{"emptyDir":{},"name":"extensions-catalog"}` |
| upstream.backstage.initContainers[0].image | Image used by the initContainer to install dynamic plugins into the `dynamic-plugins-root` volume mount. It could be replaced by a custom image based on this one. | string | `quay.io/rhdh-community/rhdh:next` |

## Opinionated Backstage deployment

This chart defaults to an opinionated deployment of Backstage that provides user with a usable Backstage instance out of the box.

Features enabled by the default chart configuration:

1. Uses [rhdh](https://github.com/redhat-developer/rhdh/) that pre-loads a lot of useful plugins and features
2. Exposes a `Route` for easy access to the instance
3. Enables OpenShift-compatible PostgreSQL database storage

For additional instance features please consult the [documentation for `rhdh`](https://github.com/redhat-developer/rhdh/tree/main/showcase-docs).

Additional features can be enabled by extending the default configuration at:

```yaml
upstream:
  backstage:
    appConfig:
      # Inline app-config.yaml for the instance
    extraEnvVars:
      # Additional environment variables
```

## Features

This charts defaults to using the [RHDH image](https://quay.io/rhdh-community/rhdh:next) that is OpenShift compatible:

```console
quay.io/rhdh-community/rhdh:next
```

Additionally this chart enhances the upstream Backstage chart with following OpenShift-specific features:

### OpenShift Routes

This chart offers a drop-in replacement for the `Ingress` resource already provided by the upstream chart via an OpenShift `Route`.

OpenShift routes are enabled by default. In order to use the chart without it, please set `route.enabled` to `false` and switch to the `Ingress` resource via `upstream.ingress` values.

Routes can be further configured via the `route` field.

To manually provide the Backstage pod with the right context, please add the following value:

```yaml
# values.yaml
global:
  clusterRouterBase: apps.example.com
```

> Tip: you can use `helm upgrade -i --set global.clusterRouterBase=apps.example.com ...` instead of a value file

Custom hosts are also supported via the following shorthand:

```yaml
# values.yaml
global:
  host: backstage.example.com
```

> Note: Setting either `global.host` or `global.clusterRouterBase` will disable the automatic hostname discovery.
        When both fields are set, `global.host` will take precedence.
        These are just templating shorthands. For full manual configuration please pay attention to values under the `route` key.

Any custom modifications to how backstage is being exposed may require additional changes to the `values.yaml`:

```yaml
# values.yaml
upstream:
  backstage:
    appConfig:
      app:
        baseUrl: 'https://{{- include "rhdh.hostname" . }}'
      backend:
        baseUrl: 'https://{{- include "rhdh.hostname" . }}'
        cors:
          origin: 'https://{{- include "rhdh.hostname" . }}'
```

### Catalog Index Configuration

The chart supports automatic plugin discovery through a catalog index OCI image. This is configured via `global.catalogIndex.image` (with `registry`, `repository`, and `tag` fields) and lets you use a pre-defined set of dynamic plugins.

You can also configure additional catalog index images via `global.catalogIndex.extraImages` to make plugins from other sources discoverable in the Extensions UI. Each extra image contributes catalog entities only (no `dynamic-plugins.default.yaml` handling).

For detailed information on configuring the catalog index, including how to override the default image, use a private registry, or add extra catalog index images, see the [Catalog Index Configuration documentation](../../docs/catalog-index-configuration.md).

### Lightspeed

Use `global.lightspeed.enabled` to enable or disable the built-in Lightspeed feature.

When enabled, the chart adds the default Lightspeed dynamic plugins, a RAG bootstrap init container, a Lightspeed Core sidecar listening on port `8080`, chart-generated ConfigMaps, a chart-generated Secret, and separate runtime and RAG data volumes. Override `global.lightspeed.plugins` for disconnected environments.

Use `global.lightspeed.runtimeVolume` to change the writable `/tmp` runtime storage between `emptyDir` and an existing PVC reference. The chart mounts that volume at `/tmp` so both generated temp files and `/tmp/data` remain writable. The `/rag-content` volume stays chart-managed and `emptyDir`-backed because the RAG assets are repopulated by the init container on each Pod start.

When using the built-in Lightspeed feature, do not also keep Lightspeed plugin packages in `global.dynamic.plugins`. Existing installations that previously configured Lightspeed there should remove those entries if the built-in defaults are sufficient, or move their custom package definitions to `global.lightspeed.plugins`; otherwise the rendered `dynamic-plugins.yaml` will contain duplicate Lightspeed plugin entries.

The Lightspeed Core sidecar loads the chart-created Lightspeed Secret as environment variables. If you update that Secret outside of Helm, Kubernetes does not guarantee that the Backstage Pod restarts automatically. Use a no-op `helm upgrade` or manually restart the Backstage deployment after changing the secret data.

### Vanilla Kubernetes compatibility mode

To deploy this chart on vanilla Kubernetes or any other non-OCP platform, apply the following changes. Note that further customizations might be required, depending on your exact Kubernetes setup:

```yaml
# values.yaml
global:
  host: # Specify your own Ingress host
route:
  enabled: false  # OpenShift Routes do not exist on vanilla Kubernetes
upstream:
  ingress:
    enabled: true  # Use Kubernetes Ingress instead of OpenShift Route
  backstage:
    podSecurityContext:  # Vanilla Kubernetes doesn't feature OpenShift default SCCs with dynamic UIDs, adjust accordingly to the deployed image
      runAsUser: 1001
      runAsGroup: 1001
      fsGroup: 1001
  postgresql:
    primary:
      podSecurityContext:
        enabled: true
        fsGroup: 26
        runAsUser: 26
    volumePermissions:
      enabled: true
```

## Install VeeCode DevPortal with Orchestrator on OpenShift

Orchestrator adds serverless workflows to Backstage. It supports application migration, developer onboarding, and workflows that use Backstage actions or external systems.

The `orchestrator-infra` chart installs cluster-wide prerequisites. VeeCode does not publish this chart in [next-charts](https://veecode-platform.github.io/next-charts). Install it from the [Red Hat Developer Hub chart repository](https://github.com/redhat-developer/rhdh-chart/tree/main/charts/orchestrator-infra#readme) with cluster-admin access:

```console
helm repo add redhat-developer https://redhat-developer.github.io/rhdh-chart
helm repo update
helm install devportal-orchestrator-infra redhat-developer/orchestrator-infra
```

Approve the Install Plans created by the chart. Wait for the OpenShift Serverless and OpenShift Serverless Logic Operators to become available. Follow the chart's [post-install notes](https://github.com/redhat-developer/rhdh-chart/blob/main/charts/orchestrator-infra/templates/NOTES.txt).

### Configure the external database

The DevPortal chart disables bundled PostgreSQL by default. Orchestrator requires an external PostgreSQL database. The chart creates a separate `sonataflow` database for workflow data, so the database user must be able to create databases.

Create the `devportal` namespace and a Secret with the keys `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, and `POSTGRES_PASSWORD`. Replace the sample host, user, and password with values for your external database:

```console
kubectl create namespace devportal --dry-run=client -o yaml | kubectl apply -f -
kubectl -n devportal create secret generic orchestrator-db-credentials \
  --from-literal=POSTGRES_HOST=postgres.example.svc \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=replace-me \
  --dry-run=client -o yaml | kubectl apply -f -
```

Set `externalDBName` to an existing database that the Secret's user can access. The host and port in the values file must match the Secret.

Save this configuration as `orchestrator-values.yaml`. Replace the sample database name, host, and Secret name with your values:

```yaml
orchestrator:
  enabled: true
  sonataflowPlatform:
    externalDBsecretRef: orchestrator-db-credentials
    externalDBName: appdb
    externalDBHost: postgres.example.svc
    externalDBPort: "5432"
```

Install VeeCode DevPortal with this configuration:

```console
helm repo add veecode https://veecode-platform.github.io/next-charts
helm repo update
helm install devportal veecode/devportal --namespace devportal -f orchestrator-values.yaml
```

The chart enables the Serverless and Serverless Logic Operators by default. If either operator is already installed in the cluster, disable its installation with `--set orchestrator.serverlessOperator.enabled=false` or `--set orchestrator.serverlessLogicOperator.enabled=false`.

### Enablement of Notifications Plugin

Workflows running with Orchestrator may use the Notifications plugin.
For this, you must enable the Notifications and Signals plugins.
Add the plugins below to `global.dynamic.plugins` in [values.yaml](values.yaml) before installing the chart, or upgrade the Helm release with the updated values file.

```yaml
- enabled: true
  package: "./dynamic-plugins/dist/backstage-plugin-notifications"
- enabled: true
  package: "./dynamic-plugins/dist/backstage-plugin-signals"
- enabled: true
  package: "./dynamic-plugins/dist/backstage-plugin-notifications-backend-dynamic"
- enabled: true
  package: "./dynamic-plugins/dist/backstage-plugin-signals-backend-dynamic"
```
These plugins let Orchestrator workflows send notifications.
