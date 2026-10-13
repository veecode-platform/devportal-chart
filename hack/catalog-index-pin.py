#!/usr/bin/env python3
"""Pin the plugin catalog index by digest, and check that the pin holds.

The chart installs the index as <registry>/<repository>:<tag>. Pinned by digest,
repository ends in @sha256 and tag holds the 64 hex digits, as in the RHDH chart.

  catalog-index-pin.py pin [--chart-dir DIR] [TAG]
      Resolves TAG (default bs_1.52.0) on quay.io and rewrites repository and tag in
      DIR/values.yaml, and nothing else. Refuses a digest that no timestamped tag points at.
  catalog-index-pin.py check [--chart-dir DIR]
      Fails unless values.yaml pins the index by digest, quay.io serves that digest, and
      a timestamped tag points at it.

A timestamped tag, bs_<version>_<timestamp>, is never re-pointed, so a digest that
carries one stays available after the moving tag leaves it. CATALOG_INDEX_REGISTRY_URL
replaces https://<registry>, so the test can use a local registry.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

import yaml

DEFAULT_TAG = "bs_1.52.0"
TIMESTAMPED = re.compile(r"bs_\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?_\d{8}T\d{6}")
DIGEST = re.compile(r"[0-9a-f]{64}")
IMAGE_KEYS = re.compile(
    r"(?P<head>^  catalogIndex:\n    image:\n(?:      .*\n)*?      repository: ).*\n"
    r"(?P<middle>(?:      .*\n)*?      tag: ).*\n",
    re.M)
MANIFEST_TYPES = ",".join([
    "application/vnd.oci.image.index.v1+json",
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.manifest.v1+json",
    "application/vnd.docker.distribution.manifest.v2+json",
])


def fail(*errors):
    for error in errors:
        print(f"::error::{error}")
    sys.exit(1)


def fetch(url, method="GET", accept="application/json", attempts=3):
    """Returns the response, or None when the registry answers 404."""
    request = urllib.request.Request(url, method=method, headers={"Accept": accept})
    for attempt in range(1, attempts + 1):
        try:
            return urllib.request.urlopen(request, timeout=30)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code != 429 and e.code < 500:
                fail(f"{url} answered HTTP {e.code}")
            error = e
        except (urllib.error.URLError, TimeoutError) as e:
            error = e
        if attempt < attempts:
            time.sleep(5 * attempt)
    fail(f"registry unreachable after {attempts} attempts: {error}")


def read_image(chart_dir):
    with open(f"{chart_dir}/values.yaml") as f:
        return yaml.safe_load(f)["global"]["catalogIndex"]["image"]


def registry_url(registry):
    if registry != "quay.io":
        fail(f"unsupported registry {registry}: this script only resolves quay.io")
    return os.environ.get("CATALOG_INDEX_REGISTRY_URL", f"https://{registry}")


def tags(base, repository):
    """Yields (name, digest) of each active tag of the repository, newest first."""
    page, more = 1, True
    while more:
        response = fetch(f"{base}/api/v1/repository/{repository}/tag/"
                         f"?onlyActiveTags=true&limit=100&page={page}")
        if response is None:
            fail(f"{base} has no repository {repository}")
        body = json.load(response)
        for tag in body["tags"]:
            yield tag["name"], tag["manifest_digest"]
        page, more = page + 1, body["has_additional"]


def anchor(base, repository, digest):
    """Returns a timestamped tag that points at the digest, or None."""
    return next((name for name, published in tags(base, repository)
                 if published == f"sha256:{digest}" and TIMESTAMPED.fullmatch(name)), None)


def serves(base, repository, digest):
    response = fetch(f"{base}/v2/{repository}/manifests/sha256:{digest}",
                     method="HEAD", accept=MANIFEST_TYPES)
    return response is not None and response.headers["Docker-Content-Digest"] == f"sha256:{digest}"


def pin(chart_dir, tag):
    path = f"{chart_dir}/values.yaml"
    with open(path) as f:
        text = f.read()
    expected = yaml.safe_load(text)
    image = expected["global"]["catalogIndex"]["image"]
    registry, repository = image["registry"], image["repository"].removesuffix("@sha256")
    base = registry_url(registry)

    published = next((digest for name, digest in tags(base, repository) if name == tag), None)
    if published is None:
        fail(f"{tag} is not an active tag of {registry}/{repository}")
    digest = published.removeprefix("sha256:")
    named = anchor(base, repository, digest)
    if named is None:
        fail(f"{tag} serves {published}, but no bs_<version>_<timestamp> tag points at it, "
             "so the registry may garbage-collect it once the tag moves on")

    updated, count = IMAGE_KEYS.subn(
        lambda m: f'{m["head"]}{repository}@sha256\n{m["middle"]}"{digest}"\n', text)
    image.update(repository=f"{repository}@sha256", tag=digest)
    if count != 1 or yaml.safe_load(updated) != expected:
        fail(f"could not rewrite only global.catalogIndex.image repository and tag in {path}")
    if updated != text:
        with open(path, "w") as f:
            f.write(updated)
    print(f"{path} {'pins' if updated != text else 'already pins'} "
          f"{repository}@sha256:{digest} ({tag}, kept by {named})")


def check(chart_dir):
    image = read_image(chart_dir)
    registry, digest = image["registry"], str(image["tag"])
    repository, _, algorithm = image["repository"].partition("@")
    if algorithm != "sha256" or not DIGEST.fullmatch(digest):
        fail(f"the catalog index is not pinned by digest: {registry}/{image['repository']}:{digest}",
             "set repository to <name>@sha256 and tag to the 64 hex digits, or run "
             "hack/catalog-index-pin.py pin")
    base = registry_url(registry)

    errors = []
    if not serves(base, repository, digest):
        errors.append(f"{registry} does not serve {repository}@sha256:{digest}")
    named = anchor(base, repository, digest)
    if named is None:
        errors.append(f"no bs_<version>_<timestamp> tag points at sha256:{digest}, "
                      "so the registry may garbage-collect it")
    if errors:
        fail(*errors)
    print(f"chart pins {registry}/{repository}@sha256:{digest}, kept by {named}")


def main():
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--chart-dir", default="charts/backstage")
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    pin_parser = commands.add_parser("pin", parents=[common])
    pin_parser.add_argument("tag", nargs="?", default=DEFAULT_TAG)
    commands.add_parser("check", parents=[common])
    args = parser.parse_args()
    if args.command == "pin":
        pin(args.chart_dir, args.tag)
    else:
        check(args.chart_dir)


if __name__ == "__main__":
    main()
