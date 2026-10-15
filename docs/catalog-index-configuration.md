# Catalog Index Configuration

The `backstage` Helm chart supports loading default plugin configurations from an OCI container image (catalog index). For general information about how the catalog index works, see [Using a Catalog Index Image for Default Plugin Configurations](https://github.com/redhat-developer/rhdh/blob/main/docs/dynamic-plugins/installing-plugins.md#using-a-catalog-index-image-for-default-plugin-configurations).

By default, the `backstage` chart configures the catalog index image using `global.catalogIndex.image` with `registry`, `repository`, and `tag` fields. You can override these values in your values file to use a different version or a mirrored image:

```yaml
global:
  catalogIndex:
    image:
      registry: quay.io
      repository: rhdh/plugin-catalog-index
      tag: "1.9"
```

### VeeCode default: pinned by digest at each release

The VeeCode distribution pins `global.catalogIndex.image` by digest, the way the Red Hat Developer Hub chart pins its index. `repository` ends in `@sha256` and `tag` holds the 64 hexadecimal digits of the digest, so the chart installs `quay.io/veecode/plugin-catalog-index@sha256:<digest>`. A chart version always installs the same index, and a new index reaches a deployment through a new chart release. The chart is the only place this reference lives; per-tenant `CATALOG_INDEX_IMAGE` overrides are not needed.

Every chart release re-pins the index before the version is tagged:

```bash
python3 hack/catalog-index-pin.py pin
```

The command resolves the digest that the moving tag `bs_1.54.9` serves on quay.io, confirms that a timestamped tag `bs_<backstage-version>_<timestamp>` points at the same digest, and rewrites `repository` and `tag` in `charts/backstage/values.yaml`, and nothing else. Pass another tag to pin another Backstage line. Running it again changes nothing until the moving tag moves.

`python3 hack/catalog-index-pin.py check` runs in every pull request and in the release workflow. It fails when the index is not pinned by digest, when quay.io does not serve the digest, or when no timestamped tag points at it. The timestamped tag is what keeps the digest available: it stays where it was created, while the moving tag moves on with every index build and the registry can garbage-collect a digest that only the moving tag held.

#### Move a deployment to another index

Override `tag` with another digest and keep the `@sha256` repository:

```yaml
global:
  catalogIndex:
    image:
      registry: quay.io
      repository: veecode/plugin-catalog-index@sha256
      tag: "<the 64 hexadecimal digits of the other digest>"
```

Or use the tag form, with a repository that has no `@sha256` and a timestamped tag:

```yaml
global:
  catalogIndex:
    image:
      registry: quay.io
      repository: veecode/plugin-catalog-index
      tag: "bs_1.54.9_20261015T134717"
```

The values schema rejects a `tag` that is not 64 hexadecimal digits while `repository` ends in `@sha256`. Helm then stops the install or upgrade with a schema error on `global.catalogIndex.image.tag`, instead of starting a pod that cannot pull the index. From chart 1.1.0, the schema also rejects the reverse: a `tag` of 64 hexadecimal digits while `repository` does not end in `@sha256`, which is the default digest tag with a mirror `repository` that drops the suffix. Helm then stops with a schema error on `global.catalogIndex.image.repository`. To use a mirror, set `registry` to the mirror host and keep the `@sha256` form in `repository`.

#### Upgrading from a chart that installed the moving tag

Before chart 1.0.4 the default `repository` had no `@sha256`, so a values file that overrides only `tag`, such as a temporary pin to a timestamped tag, worked. From chart 1.0.4 the default `repository` ends in `@sha256`. An installation that overrides only `tag` must also set `repository: veecode/plugin-catalog-index` (the tag form above), or drop the override, before it moves to chart 1.0.4. Otherwise Helm rejects the upgrade with the schema error described above.

An installation that sets `repository` to a mirror path without `@sha256`, and leaves `tag` at the default digest, is different, whether or not it also sets `registry`. Chart 1.0.4 accepts that values file and renders `<registry>/<repository>:<digest>`, for example `quay.io/mirror/plugin-catalog-index:<digest>`. A mirror usually has no tag with that name, so the pod fails when it pulls the index, not at render time. Before you upgrade, set `tag` to a `bs_` tag that the mirror holds; chart 1.0.3 and chart 1.0.4 both accept it. Or, in the same upgrade that moves to chart 1.0.4, set `repository` to the mirror path with `@sha256` and leave `tag` at the default digest. Never add `@sha256` to `repository` for a chart before 1.0.4: there the default `tag` is a tag name, so the reference renders `@sha256:<tag>`, which no registry can pull.

From chart 1.1.0, the schema rejects that same override at render time, with a schema error on `global.catalogIndex.image.repository`. Use the same two remedies: set `tag` to a `bs_` tag, or set `repository` to the mirror path with `@sha256`.

## Extra catalog index images

You can configure additional catalog index images alongside the primary one using `global.catalogIndex.extraImages`. Each extra image contributes catalog entities only to the Extensions UI — only the primary `CATALOG_INDEX_IMAGE` is used for extracting and handling the `dynamic-plugins.default.yaml`.

```yaml
global:
  catalogIndex:
    image:
      registry: quay.io
      repository: rhdh/plugin-catalog-index
      tag: "1.10"
    extraImages:
      - name: community
        registry: ghcr.io
        repository: redhat-developer/rhdh-plugin-community-index
        tag: "1.10"
      - registry: my-registry.example.com
        repository: my-org/my-rhdh-internal-plugin-catalog
        tag: "1.2.3"
```

Each entry requires `registry`, `repository`, and `tag` fields. The optional `name` field produces cleaner extraction directory names (e.g., `/extensions/extra/community/`); when omitted, the name is auto-derived from the image reference.

The chart constructs the `EXTRA_CATALOG_INDEX_IMAGES` environment variable for the `install-dynamic-plugins` init container as a comma-separated list. Named entries use the format `name=registry/repository:tag`, while unnamed entries use `registry/repository:tag`.

## Using a Private Registry

If your catalog index image is stored in a private registry that requires authentication, create a secret named `<release_name>-dynamic-plugins-registry-auth` containing an `auth.json` file with your registry credentials.

For detailed instructions on configuring private registry authentication, see the [official Red Hat Developer Hub documentation](https://docs.redhat.com/en/documentation/red_hat_developer_hub/1.8/html/installing_and_viewing_plugins_in_red_hat_developer_hub/assembly-third-party-plugins#proc-load-plugin-oci-image_assembly-install-third-party-plugins-rhdh).

## Extensions Catalog Entities

When the catalog index image is configured, the `backstage` chart instructs the RHDH `install-dynamic-plugins` init container to extract catalog entities from the catalog index image to a new `/extensions` volume mount by default.
This allows the extensions backend providers to automatically discover plugin metadata for display in the RHDH Extensions UI.

The extraction directory can be configured via the `CATALOG_ENTITIES_EXTRACT_DIR` environment variable in the `install-dynamic-plugins` init container.

More details in [Catalog Entities Extraction](https://github.com/redhat-developer/rhdh/blob/main/docs/dynamic-plugins/installing-plugins.md#catalog-entities-extraction).
