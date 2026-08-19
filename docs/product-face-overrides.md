# Customizing the VeeCode Product Face

The `backstage` chart ships a baked-in set of plugins — the "VeeCode product
face" (Home, header, RBAC UI, theme, About, Marketplace/Extensions, TechDocs,
Notifications, Signals, Tech Radar) — so a stock install looks and behaves
like VeeCode DevPortal out of the box.

The face is **not** declared in this chart's `values.yaml`. It is baked into
the `devportal-core` image at `/opt/app-root/src/dynamic-plugins.veecode.yaml`
and wired in ahead of the marketplace write-through via
`global.dynamic.includes` (an installer **level-0** source). `global.dynamic.plugins`
(installer **level 1**) is left empty by default and is purely additive: any
entry you add there is layered on top of the face, never replacing it.

This split exists because Helm replaces lists wholesale. Before this change,
the face lived in `global.dynamic.plugins` itself, so a values overlay that
added one custom plugin to that key silently deleted the entire product
face — the pod still booted, the UI was just gone, with no warning. Moving
the face into an image-baked include makes it non-destructible by a customer
values file.

## Supported overrides

### Add your own plugin

Set `global.dynamic.plugins` in your values file as usual. It only adds to
the face — it no longer replaces it:

```yaml
global:
  dynamic:
    plugins:
      - package: oci://my-registry.example.com/my-plugin@sha256:...!my-plugin
        disabled: false
```

### Disable one face plugin

Add an entry with the **exact package ref** from the reference table below
and `disabled: true`. The installer matches on that ref and overrides just
that one entry — the rest of the face is untouched:

```yaml
global:
  dynamic:
    plugins:
      - package: ./dynamic-plugins/dist/backstage-community-plugin-tech-radar
        disabled: true
```

### Reconfiguring a face plugin (edge case)

If your override for a face package **also** sets `pluginConfig`, the
installer replaces that plugin's `pluginConfig` wholesale — it does not
deep-merge with the face's own `pluginConfig`. You will lose every key you
didn't restate, not just the ones you meant to change.

Prefer `disabled: true` alone. If you must reconfigure a face plugin, copy
the full `pluginConfig` block for that package (see the face file reference
below or ask VeeCode for the current pin) and edit only what you need.

### Full-ref form only

Always use the **full package ref** (with its digest or version) in your
overrides, exactly as it appears in the reference table. Do not use bare
`{{inherit}}` — it is an internal chart/canonical-source mechanism, not a
customer-facing override syntax, and it has no meaning outside a package
already defined at a lower installer level.

## Face plugin reference

These are the 20 entries currently baked into the image
(`veecode/dynamic-plugins.veecode.yaml` in `devportal-core`). Use the
`package` value verbatim as the override key; `default` reflects the
face file's own `disabled` field. Digest-pinned refs are given in full below
the table — a truncated ref will not match and the override will be added as
a new plugin instead of disabling the face one.

| # | Purpose | Default |
| --- | --- | --- |
| 1 | RHDH stock home page (superseded by the VeeCode home below) | disabled |
| 2 | VeeCode analytics home page | enabled |
| 3 | Header, sidebar menu ordering | enabled |
| 4 | RBAC UI (enforcement is a separate `PERMISSION_ENABLED` env var, off by default) | enabled |
| 5 | Legacy OCI VeeCode theme (superseded by RHDH-native theming via app-config) | disabled |
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

18 enabled, 2 disabled (rows 1 and 5) of 20 total.

Full package refs, in table order:

1. `./dynamic-plugins/dist/red-hat-developer-hub-backstage-plugin-dynamic-home-page`
2. `oci://quay.io/veecode/veecode-homepage@sha256:13f6f2f61575d8523e90f2256e5711e5141670ae7ed717229524f3f23bc6d99a!veecode-platform-plugin-veecode-homepage`
3. `./dynamic-plugins/dist/red-hat-developer-hub-backstage-plugin-global-header`
4. `./dynamic-plugins/dist/backstage-community-plugin-rbac`
5. `oci://quay.io/veecode/veecode-theme@sha256:053c593f04adc2d35dd45adad4411458b6ccd85735961fe862126c7cc2677d90!veecode-platform-plugin-veecode-theme`
6. `@veecode-platform/backstage-plugin-about-dynamic@1.1.0`
7. `@veecode-platform/backstage-plugin-about-backend-dynamic@1.1.0`
8. `./dynamic-plugins/dist/red-hat-developer-hub-backstage-plugin-catalog-backend-module-extensions-dynamic`
9. `oci://quay.io/veecode/marketplace@sha256:d98b28a1f8a453fe697bbc50780ae92e0c54eb7f3c789b0d184728d5b3c07a9e!devportal-marketplace-backend`
10. `oci://quay.io/veecode/marketplace@sha256:d98b28a1f8a453fe697bbc50780ae92e0c54eb7f3c789b0d184728d5b3c07a9e!devportal-pending-changes-dynamic`
11. `oci://quay.io/veecode/marketplace@sha256:e30f090acb9b4d613f94ea11abc2cb0501c306be7c0bc7b83774e4ae62fbc3f0!devportal-marketplace-frontend-dynamic`
12. `./dynamic-plugins/dist/backstage-plugin-techdocs`
13. `./dynamic-plugins/dist/backstage-plugin-techdocs-backend-dynamic`
14. `./dynamic-plugins/dist/backstage-plugin-techdocs-module-addons-contrib`
15. `./dynamic-plugins/dist/backstage-plugin-notifications`
16. `./dynamic-plugins/dist/backstage-plugin-signals`
17. `./dynamic-plugins/dist/backstage-plugin-notifications-backend-dynamic`
18. `./dynamic-plugins/dist/backstage-plugin-signals-backend-dynamic`
19. `./dynamic-plugins/dist/backstage-community-plugin-tech-radar`
20. `./dynamic-plugins/dist/backstage-community-plugin-tech-radar-backend-dynamic`

These digests are current as of this doc's writing; treat
`devportal-core/veecode/dynamic-plugins.veecode.yaml` as the source of truth
if they've since been repinned.

For the exact current digests, consult
`devportal-core/veecode/dynamic-plugins.veecode.yaml` — it is the canonical
version source and is updated whenever a face plugin is repinned.

## Feature-gated plugins (Lightspeed, Orchestrator) and `{{inherit}}`

The chart also ships six optional, feature-gated plugin entries
(`global.lightspeed.plugins`, `orchestrator.plugins`) using RHDH's
`{{inherit}}` keyword in the path-omitted form
(`oci://registry.access.redhat.com/rhdh/<plugin>:{{inherit}}`). Both features
are disabled by default (`global.lightspeed.enabled: false`,
`orchestrator.enabled: false`).

`{{inherit}}` resolves a package's version against a plugin already defined,
with a real tag or digest, at a lower installer level (an `includes:` file).
Today there is **no canonical source for these six RHDH packages**: the
catalog index this deployment points `CATALOG_INDEX_IMAGE` at
(`quay.io/veecode/plugin-catalog-index`) ships a deliberately empty
`dynamic-plugins.default.yaml` stub (`plugins: []` — see
`devportal-planning` M3 decision Q9), and no `includes:` entry in this chart
references it. If you enable Lightspeed or Orchestrator, you must supply
your own version pin for each of the six packages via a values override
(full ref, digest or tag) — `{{inherit}}` has nothing to resolve against
until an authoritative source for these RHDH packages is wired in.
