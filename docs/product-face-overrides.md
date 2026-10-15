# Customizing the VeeCode Product Face

This guide applies from chart 1.1.0, with DevPortal 3.1.0.

The `backstage` chart enables the VeeCode product face, the "factory plugins"
(Home, header, RBAC UI, About, Marketplace and Extensions, TechDocs,
Notifications, Signals, Tech Radar), through the plugin catalog index that the
chart pins in `global.catalogIndex.image`. The index enables them, so a stock
install looks and behaves like VeeCode DevPortal out of the box.

The image keeps only the names of the factory plugins, in
`/opt/app-root/src/factory-plugins.yaml`. A plugin update therefore reaches
installs through a new index and a chart release, not a new image.

The installer reads the index through `global.dynamic.includes`, which holds
`dynamic-plugins.default.yaml` (an installer **level-0** source). The
`global.dynamic.plugins` list (installer **level 1**) is empty by default and
is purely additive: an entry there changes one plugin and leaves the rest of
the face in place.

Helm replaces lists wholesale. The face is therefore not declared in a list
that a customer values file might set, so an overlay that adds one plugin
cannot silently delete the whole face.

## Supported overrides

Override a factory plugin with its index ref, which has the form
`oci://quay.io/veecode/<repository>:{{inherit}}!<path>`. `{{inherit}}` takes the
version that the pinned index gives the plugin, so the override follows each
index release. Do not write a digest or a tag in an override of a factory
plugin: a pinned digest keeps an old artifact after the index moves on.

The chart pins an index that enables every factory plugin, so the `{{inherit}}`
form resolves for each of them. An index that does not list a plugin fails the
install, even for an override with `disabled: true`.

### Add your own plugin

Set `global.dynamic.plugins` in your values file as usual. It only adds to
the face and never replaces it:

```yaml
global:
  dynamic:
    plugins:
      - package: oci://my-registry.example.com/my-plugin@sha256:...!my-plugin
        disabled: false
```

### Disable one factory plugin

Give the plugin's index ref with `disabled: true`:

```yaml
global:
  dynamic:
    plugins:
      - package: oci://quay.io/veecode/backstage-community-plugin-tech-radar:{{inherit}}!backstage-community-plugin-tech-radar
        disabled: true
```

Disabling is the preferred override. The rest of the face stays as it is.

### Reconfigure one factory plugin

Give the same ref a full `pluginConfig` block:

```yaml
global:
  dynamic:
    plugins:
      - package: oci://quay.io/veecode/backstage-community-plugin-tech-radar:{{inherit}}!backstage-community-plugin-tech-radar
        pluginConfig:
          # Every key the plugin needs, copied from its index entry and then changed.
```

The installer replaces the plugin's `pluginConfig` wholesale and does not
deep-merge it. Copy every key you need, not only the one you change. The block
to copy is the one in the pinned index's `dynamic-plugins.default.yaml`.

## Upgrading from 1.0.x

Chart 1.0.x overrides name a factory plugin by its full ref with a digest,
`oci://quay.io/veecode/<repository>@sha256:<digest>!<path>`. Before you upgrade
to chart 1.1.0, change each such entry to the index form:

1. Replace `@sha256:<digest>` with `:{{inherit}}`. Keep the `!<path>`.
2. Keep `disabled` and `pluginConfig` as they are.
3. Remove `/opt/app-root/src/dynamic-plugins.veecode.yaml` from
   `global.dynamic.includes`. The values schema rejects that entry, and the
   image no longer has the file.
4. Remove any `DEVPORTAL_FACE_FILE` you set. The chart no longer sets it.

Behaviour after the upgrade of an override that still uses the full digest
ref: being verified. Do not rely on it until this note says otherwise.

## Factory plugin reference

These are the 20 entries of the image-baked face in chart 1.0.x. In chart 1.1.0,
the index enables 18 of them. The column "In the index" gives each entry's state
there. Use the `package` value verbatim, with `{{inherit}}` in place of the
digest, as the override key.

| # | Purpose | In the index |
| --- | --- | --- |
| 1 | RHDH stock home page (superseded by the VeeCode home below) | listed, disabled |
| 2 | VeeCode analytics home page | enabled |
| 3 | Header, sidebar menu ordering | enabled |
| 4 | RBAC UI (enforcement is a separate `PERMISSION_ENABLED` env var, off by default) | enabled |
| 5 | Legacy OCI VeeCode theme (superseded by RHDH-native theming via app-config) | not in the index, not enabled |
| 6 | About page | enabled |
| 7 | About backend | enabled |
| 8 | Extensions catalog provider (marketplace loop) | enabled |
| 9 | Marketplace backend (`/api/extensions/*`) | enabled |
| 10 | Pending-changes batch install/removal UX | enabled |
| 11 | Marketplace UI at `/marketplace` | enabled |
| 12 | TechDocs frontend (route + entity tab) | enabled |
| 13 | TechDocs backend | enabled |
| 14 | TechDocs addons | enabled |
| 15 | Notifications frontend | enabled |
| 16 | Signals frontend (notifications transport) | enabled |
| 17 | Notifications backend | enabled |
| 18 | Signals backend | enabled |
| 19 | Tech Radar frontend | enabled |
| 20 | Tech Radar backend | enabled |

The digest of each entry is in the `dynamic-plugins.default.yaml` of the catalog
index that the chart pins, not in this guide. The factory plugin names are in
`/opt/app-root/src/factory-plugins.yaml` of a running portal.

## Feature-gated plugins (Lightspeed, Orchestrator) and `{{inherit}}`

The chart also ships six optional, feature-gated plugin entries
(`global.lightspeed.plugins`, `orchestrator.plugins`) using RHDH's
`{{inherit}}` keyword in the path-omitted form
(`oci://registry.access.redhat.com/rhdh/<plugin>:{{inherit}}`). Both features
are disabled by default (`global.lightspeed.enabled: false`,
`orchestrator.enabled: false`).

`{{inherit}}` resolves a package's version against a plugin already defined,
with a real tag or digest, at a lower installer level (an `includes:` file).
The catalog index this deployment points `CATALOG_INDEX_IMAGE` at
(`quay.io/veecode/plugin-catalog-index`) lists none of the six RHDH packages in
its `dynamic-plugins.default.yaml` (checked on the digest that `values.yaml`
pins, 2026-10-15), and no `includes:` entry in this chart references another
source for them. If you enable Lightspeed or Orchestrator, you must supply
your own version pin for each of the six packages via a values override
(full ref, digest or tag). `{{inherit}}` has nothing to resolve against
until an authoritative source for these RHDH packages is wired in.
