#!/usr/bin/env python3
"""Tests hack/catalog-index-pin.py against a local registry that answers like quay.io, and
the values schema guard that stops a tag from riding on a digest repository.

Run it from the repository root with the chart dependencies built (helm dependency build
charts/backstage): python hack/test-catalog-index-pin.py
"""
import http.server
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.parse
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "hack/catalog-index-pin.py"
CHART = ROOT / "charts/backstage"
REPOSITORY = "veecode/plugin-catalog-index"
CURRENT, OLDER = "a" * 64, "b" * 64
ANCHOR = "bs_1.52.0_20261009T013836"


class Registry:
    """The two quay.io endpoints the script reads: the tag listing and the manifest HEAD."""

    def __init__(self, tags, served=None, page_size=2):
        served = set(tags.values()) if served is None else served

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                url = urllib.parse.urlparse(self.path)
                if url.path != f"/api/v1/repository/{REPOSITORY}/tag/":
                    return self.send_error(404)
                page = int(urllib.parse.parse_qs(url.query)["page"][0])
                names = list(tags)[(page - 1) * page_size:page * page_size]
                body = json.dumps({
                    "page": page,
                    "has_additional": page * page_size < len(tags),
                    "tags": [{"name": n, "manifest_digest": f"sha256:{tags[n]}"} for n in names],
                }).encode()
                self.send_response(200)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_HEAD(self):
                prefix = f"/v2/{REPOSITORY}/manifests/sha256:"
                digest = self.path.removeprefix(prefix)
                if not self.path.startswith(prefix) or digest not in served:
                    return self.send_error(404)
                self.send_response(200)
                self.send_header("Docker-Content-Digest", f"sha256:{digest}")
                self.end_headers()

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        threading.Thread(target=self.server.serve_forever, args=(0.01,), daemon=True).start()

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def values(repository, tag):
    return f"""global:
  catalogIndex:
    image:
      registry: quay.io
      # A comment above the repository stays.
      repository: {repository}
      # A comment between the keys stays.
      tag: "{tag}"
    extraImages: []
upstream:
  backstage:
    image:
      tag: "3.0.3"
"""


class CatalogIndexPinTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.chart_dir = directory.name
        self.values = Path(directory.name) / "values.yaml"

    def run_script(self, registry_tags, command, *args, served=None, page_size=2, content=None):
        registry = Registry(registry_tags, served, page_size)
        self.addCleanup(registry.close)
        if content is not None:
            self.values.write_text(content)
        return subprocess.run(
            [sys.executable, str(SCRIPT), command, *args, "--chart-dir", self.chart_dir],
            env={**os.environ, "CATALOG_INDEX_REGISTRY_URL": registry.url},
            capture_output=True, text=True)

    def test_pin_rewrites_only_repository_and_tag(self):
        result = self.run_script(
            {"bs_1.52.0": CURRENT, "bs_1.52.0-m22n1": OLDER, ANCHOR: CURRENT}, "pin",
            content=values(REPOSITORY, "bs_1.52.0"))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.values.read_text(), values(f"{REPOSITORY}@sha256", CURRENT))
        self.assertIn(f"kept by {ANCHOR}", result.stdout)

    def test_pin_twice_changes_nothing(self):
        tags = {"bs_1.52.0": CURRENT, ANCHOR: CURRENT}
        self.run_script(tags, "pin", content=values(REPOSITORY, "bs_1.52.0"))
        pinned = self.values.read_text()
        result = self.run_script(tags, "pin")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.values.read_text(), pinned)
        self.assertIn("already pins", result.stdout)

    def test_pin_refuses_a_digest_that_only_the_moving_tag_holds(self):
        before = values(REPOSITORY, "bs_1.52.0")
        result = self.run_script(
            {"bs_1.52.0": CURRENT, "bs_1.52.0-m22n1": CURRENT}, "pin", content=before)
        self.assertEqual(result.returncode, 1)
        self.assertIn("no bs_<version>_<timestamp> tag points at it", result.stdout)
        self.assertEqual(self.values.read_text(), before)

    def test_pin_finds_a_timestamped_tag_of_a_prerelease_line_on_a_later_page(self):
        tags = {"bs_1.52.0": CURRENT, ANCHOR: CURRENT, "latest": OLDER, "bs_1.54.0-next.0": OLDER,
                "bs_1.54.0-next.0_20260820T172518": OLDER}
        result = self.run_script(tags, "pin", "bs_1.54.0-next.0", content=values(REPOSITORY, "bs_1.54.0-next.0"))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.values.read_text(), values(f"{REPOSITORY}@sha256", OLDER))

    def test_the_shipped_values_are_what_pin_writes(self):
        shipped = (CHART / "values.yaml").read_text()
        digest = yaml.safe_load(shipped)["global"]["catalogIndex"]["image"]["tag"]
        result = self.run_script(
            {"bs_1.52.0": digest, ANCHOR: digest}, "pin", content=shipped)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual(self.values.read_text(), shipped)

    def test_check_passes_for_a_served_digest_that_a_timestamped_tag_holds(self):
        result = self.run_script(
            {"bs_1.52.0": CURRENT, ANCHOR: CURRENT}, "check",
            content=values(f"{REPOSITORY}@sha256", CURRENT))
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(f"kept by {ANCHOR}", result.stdout)

    def test_check_fails_when_the_index_is_not_pinned_by_digest(self):
        for repository, tag in [(REPOSITORY, "bs_1.52.0"), (f"{REPOSITORY}@sha256", ANCHOR)]:
            with self.subTest(repository=repository, tag=tag):
                result = self.run_script(
                    {"bs_1.52.0": CURRENT, ANCHOR: CURRENT}, "check", content=values(repository, tag))
                self.assertEqual(result.returncode, 1)
                self.assertIn("is not pinned by digest", result.stdout)

    def test_check_fails_when_the_registry_does_not_serve_the_digest(self):
        result = self.run_script(
            {"bs_1.52.0": CURRENT, ANCHOR: CURRENT}, "check", served=set(),
            content=values(f"{REPOSITORY}@sha256", CURRENT))
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"quay.io does not serve {REPOSITORY}@sha256:{CURRENT}", result.stdout)

    def test_check_fails_when_no_timestamped_tag_points_at_the_digest(self):
        result = self.run_script(
            {"bs_1.52.0": CURRENT, "bs_1.52.0-m22n1": CURRENT, ANCHOR: OLDER}, "check",
            content=values(f"{REPOSITORY}@sha256", CURRENT))
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"no bs_<version>_<timestamp> tag points at sha256:{CURRENT}", result.stdout)


class SchemaGuardTest(unittest.TestCase):
    def render(self, **image):
        sets = [f"--set=global.catalogIndex.image.{key}={value}" for key, value in image.items()]
        return subprocess.run(["helm", "template", "t", str(CHART), *sets],
                              capture_output=True, text=True)

    def test_a_tag_on_a_digest_repository_is_rejected(self):
        result = self.render(tag=ANCHOR)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("^[0-9a-f]{64}$", result.stderr)

    def test_the_tag_form_renders_with_a_repository_without_a_digest(self):
        result = self.render(repository=REPOSITORY, tag=ANCHOR)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"value: quay.io/{REPOSITORY}:{ANCHOR}", result.stdout)

    def test_a_default_digest_tag_on_a_repository_without_a_digest_is_rejected(self):
        result = self.render(repository=REPOSITORY)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("@sha256$", result.stderr)


if __name__ == "__main__":
    unittest.main()
