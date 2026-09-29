#!/usr/bin/env bash
# Usage: check-ignorefile.sh [FILE]   (default: .trivyignore.yaml at the repository root)
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
exec python3 - "${1:-$root/.trivyignore.yaml}" <<'PY'
import datetime
import sys

try:
    import yaml
except ImportError:
    sys.exit("check-ignorefile: PyYAML is required (pip install pyyaml)")

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        doc = yaml.safe_load(f)
except (OSError, yaml.YAMLError) as e:
    sys.exit(f"check-ignorefile: cannot read {path}: {e}")

utc = datetime.timezone.utc
now = datetime.datetime.now(utc)
problems = []
notes = []
entries = []

if not isinstance(doc, dict):
    problems.append("top level must be a mapping with a `vulnerabilities` list")
else:
    for key in doc:
        if key != "vulnerabilities":
            problems.append(f"unknown top-level key `{key}`, which Trivy skips without a warning")
    entries = doc.get("vulnerabilities")
    if not isinstance(entries, list):
        problems.append("`vulnerabilities` must be a list (`vulnerabilities: []` when empty)")
        entries = []

for i, entry in enumerate(entries):
    where = f"vulnerabilities[{i}]"
    if not isinstance(entry, dict):
        problems.append(f"{where}: must be a mapping")
        continue
    if not isinstance(entry.get("id"), str) or not entry["id"].strip():
        problems.append(f"{where}: missing id")
    else:
        where += f" ({entry['id']})"
    if not isinstance(entry.get("statement"), str) or not entry["statement"].strip():
        problems.append(f"{where}: missing statement")
    expired_at = entry.get("expired_at")
    if expired_at is None:
        problems.append(f"{where}: missing expired_at")
    elif isinstance(expired_at, datetime.datetime):
        when = expired_at if expired_at.tzinfo else expired_at.replace(tzinfo=utc)
    elif isinstance(expired_at, datetime.date):
        when = datetime.datetime(expired_at.year, expired_at.month, expired_at.day, tzinfo=utc)
    else:
        problems.append(f"{where}: expired_at must be an unquoted YAML date such as 2026-12-31, got {expired_at!r}")
    if isinstance(expired_at, datetime.date) and when <= now:
        notes.append(f"{where}: expired on {when:%Y-%m-%d}, so the finding blocks again")

for note in notes:
    print(f"note: {note}")
if problems:
    for problem in problems:
        print(f"FAIL {path}: {problem}", file=sys.stderr)
    sys.exit(1)
print(f"ignore file check: PASS ({len(entries)} entries) {path}")
PY
