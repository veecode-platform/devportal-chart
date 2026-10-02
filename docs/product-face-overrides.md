# Customizing the VeeCode Product Face

This guide applies from DevPortal 3.0.0, chart 1.0.0.

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

Add an entry with the current full package ref from the reference table below
and `disabled: true`. The installer matches the registry and repository. If
both refs include a selector, those selectors must match. A different tag or
digest still matches but selects a different artifact version. Use the current
ref from the table so you do not pin an older artifact:

```yaml
global:
  dynamic:
    plugins:
      - package: oci://quay.io/veecode/backstage-community-plugin-tech-radar@sha256:2a5e149c22bdc02f6cf0d1ba6db0113105b284bf05b3806678cca601387f3b63!backstage-community-plugin-tech-radar
        disabled: true
```

An override written against an old local path no longer matches a face plugin after it moves to OCI. The face default stays enabled until you use its current full OCI reference.

### Reconfiguring a face plugin (edge case)

If your override for a face package **also** sets `pluginConfig`, the
installer replaces that plugin's `pluginConfig` wholesale — it does not
deep-merge with the face's own `pluginConfig`. You will lose every key you
didn't restate, not just the ones you meant to change. A tag or digest in the
override pins that artifact version; refresh or remove the override when the
face pin changes.

Prefer `disabled: true` alone. If you must reconfigure a face plugin, copy
the full `pluginConfig` block for that package (see the face file reference
below or ask VeeCode for the current pin) and edit only what you need.

### Full-ref form only

Always use a **full package ref** with a valid digest or tag. The installer
matches the registry and repository; when both refs include a selector, those
selectors must also match. A different digest or tag still matches and pins
the selected artifact version, so refresh or remove an override when the face
pin changes. Do not use bare `{{inherit}}`. It is an internal chart mechanism
for resolving a package version from a lower installer level, not a customer-
facing syntax. It only resolves a version for a package already defined at a
lower level.

## Face plugin reference

These are the 20 entries baked into the image from DevPortal 3.0.0, chart 1.0.0
(`veecode/dynamic-plugins.veecode.yaml` in `devportal-core`). Use the
`package` value verbatim as the override key; `default` reflects the
face file's own `disabled` field. Digest-pinned refs are given in full below
the table. The installer identifies a face plugin by registry and repository;
if both refs include a selector, the selectors must also match. A different
tag or digest still matches and selects that artifact version. An OCI ref
without a tag or digest is invalid.

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

1. `oci://quay.io/veecode/red-hat-developer-hub-backstage-plugin-dynamic-home-page@sha256:5fb22d07cb78b7bf4bd7fa5b4469aee089e292cd96eefd200197673a5fcd6b1c!red-hat-developer-hub-backstage-plugin-dynamic-home-page`
2. `oci://quay.io/veecode/veecode-platform-plugin-veecode-homepage@sha256:897d9ae74de429f5df809c1b315281e4926dac77f49848c3e51843203a28709e!veecode-platform-plugin-veecode-homepage`
3. `oci://quay.io/veecode/red-hat-developer-hub-backstage-plugin-global-header@sha256:2a622b6a8c30584eb1023869d7387f1ec09309f62ef3621b94a20fb5d81de1a1!red-hat-developer-hub-backstage-plugin-global-header`
4. `oci://quay.io/veecode/backstage-community-plugin-rbac@sha256:36e9f606223dd6f2e479c3a904d28dfbec7afdcbbb8e2f18cd1d1edbf7f238e6!backstage-community-plugin-rbac`
5. `oci://quay.io/veecode/veecode-theme@sha256:053c593f04adc2d35dd45adad4411458b6ccd85735961fe862126c7cc2677d90!veecode-platform-plugin-veecode-theme`
6. `oci://quay.io/veecode/veecode-platform-backstage-plugin-about@sha256:5746126ea0129d0125d0fada629b543c981d121bbfd27263dfec0fcae9568ead!veecode-platform-backstage-plugin-about`
7. `oci://quay.io/veecode/veecode-platform-backstage-plugin-about-backend@sha256:99ca46df8ebda0e36793c18533c3fc4f00dd099467931bc3bf7685cc35958ac7!veecode-platform-backstage-plugin-about-backend`
8. `oci://quay.io/veecode/red-hat-developer-hub-backstage-plugin-catalog-backend-module-extensions@sha256:9fad03e713fe046ab2b381d243bbc231497dcb27c260aa127fa6fd163254987d!red-hat-developer-hub-backstage-plugin-catalog-backend-module-extensions`
9. `oci://quay.io/veecode/devportal-marketplace-backend@sha256:153527c7d510eb07aa4cc14be40534419d55632b66c7ff254195fc08830f42ad!devportal-marketplace-backend`
10. `oci://quay.io/veecode/devportal-pending-changes-dynamic@sha256:18d75d59e287e9e3ab4794ce851e1aa947c8674615def00273550574e365b342!devportal-pending-changes-dynamic`
11. `oci://quay.io/veecode/devportal-marketplace-frontend-dynamic@sha256:311de8798d0db945e0ed0f333864ff260d394fe41336cb554aeae924d4a98e16!devportal-marketplace-frontend-dynamic`
12. `oci://quay.io/veecode/backstage-plugin-techdocs@sha256:d8222a85e6a4b61e230e2ff8944ccd794876c1f30eb9b49faeade3c6c308dcc9!backstage-plugin-techdocs`
13. `oci://quay.io/veecode/backstage-plugin-techdocs-backend@sha256:a52ab2f01ccf85a23352655b25d4449996cafed381cfb6d837cf537205021c3e!backstage-plugin-techdocs-backend`
14. `oci://quay.io/veecode/backstage-plugin-techdocs-module-addons-contrib@sha256:9feeac06c77eb32f9b5a7f2fa74e2eaa9d538bdb0dd62811ec5f9d010c437035!backstage-plugin-techdocs-module-addons-contrib`
15. `oci://quay.io/veecode/backstage-plugin-notifications@sha256:bb3c3f0739f81ac5aa1e40f63bbc7d1aa99bf8c80cd5f6c232f74ed88d2315a2!backstage-plugin-notifications`
16. `oci://quay.io/veecode/backstage-plugin-signals@sha256:8764b50b78b643aa8d2bbbd6a67427c8924e9226c40f0b5c371aed4d09f16610!backstage-plugin-signals`
17. `oci://quay.io/veecode/backstage-plugin-notifications-backend@sha256:b089cdda63806e0aff83f5b51631f2e30a84b346f01d73b01aadc31ebda78b96!backstage-plugin-notifications-backend`
18. `oci://quay.io/veecode/backstage-plugin-signals-backend@sha256:3767a18cdb454ac8aa156a1ca15bbd5086badd0cff0d55bd3b16fad68554133e!backstage-plugin-signals-backend`
19. `oci://quay.io/veecode/backstage-community-plugin-tech-radar@sha256:2a5e149c22bdc02f6cf0d1ba6db0113105b284bf05b3806678cca601387f3b63!backstage-community-plugin-tech-radar`
20. `oci://quay.io/veecode/backstage-community-plugin-tech-radar-backend@sha256:71f7f6c4816156120e693bf3c2ff29ee35c3725406c996c7de58607800df3a99!backstage-community-plugin-tech-radar-backend`

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
