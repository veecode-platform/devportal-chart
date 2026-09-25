#!/usr/bin/env python3
"""Fail when the chart announces one portal image and installs another.

Checks that appVersion equals the image tag and that the pinned digest is the
digest the registry serves for that tag. The digest wins over the tag at
install time, so a stale digest silently ships an older image.

Usage: hack/check-image-pin.py [chart-dir]
"""
import json
import sys
import urllib.request

import yaml

MANIFEST_TYPES = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
])

chart_dir = sys.argv[1] if len(sys.argv) > 1 else "charts/backstage"
with open(f"{chart_dir}/Chart.yaml") as f:
    chart = yaml.safe_load(f)
with open(f"{chart_dir}/values.yaml") as f:
    image = yaml.safe_load(f)["upstream"]["backstage"]["image"]

registry, repo = image["registry"], image["repository"]
tag, digest = str(image["tag"]), image.get("digest") or ""
app_version = str(chart.get("appVersion"))

if registry != "docker.io":
    sys.exit(f"unsupported registry {registry}: this check only resolves docker.io")

token = json.load(urllib.request.urlopen(
    "https://auth.docker.io/token?service=registry.docker.io"
    f"&scope=repository:{repo}:pull"))["token"]
request = urllib.request.Request(
    f"https://registry-1.docker.io/v2/{repo}/manifests/{tag}",
    method="HEAD",
    headers={"Authorization": f"Bearer {token}", "Accept": MANIFEST_TYPES})
published = urllib.request.urlopen(request).headers["Docker-Content-Digest"]

errors = []
if app_version != tag:
    errors.append(f"appVersion {app_version} does not match image tag {tag}")
if digest != published:
    errors.append(f"digest {digest or '<empty>'} is not what {repo}:{tag} "
                  f"serves ({published})")

for error in errors:
    print(f"::error::{error}")
if not errors:
    print(f"chart {chart['version']} installs {registry}/{repo}:{tag}@{published}")
sys.exit(1 if errors else 0)
