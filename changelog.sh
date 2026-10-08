#!/usr/bin/env bash
# changelog.sh — Generate a structured CHANGELOG.md from a project's git history.
#
# Usage:
#   bash changelog.sh [repo_dir]
#
# Behavior:
#   - Finds commits since the most recent git tag (or all commits if no tag).
#   - Auto-categorizes into: Added / Fixed / Changed / Removed
#     using Conventional Commits prefixes.
#   - Writes CHANGELOG.md in the current working directory.
#
# Requirements: git, python3 (>= 3.7).

set -euo pipefail

REPO_DIR="${1:-.}"
cd "$REPO_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required" >&2
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required" >&2
  exit 1
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "error: not a git repository: $REPO_DIR" >&2
  exit 1
fi

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "$LAST_TAG" ]; then
  RANGE="${LAST_TAG}..HEAD"
  echo "Collecting commits in range: $RANGE"
else
  RANGE="HEAD"
  echo "No previous tag found; collecting all commits."
fi

python3 - "$RANGE" <<'PY'
import re
import subprocess
import sys
import datetime

rng = sys.argv[1]
sep_rec = "\x1e"
sep_fld = "\x1f"
fmt = "%H{0}%an{0}%ad{0}%s{1}".format(sep_fld, sep_rec)

raw = subprocess.check_output(
    ["git", "log", rng, "--date=short", "--pretty=format:" + fmt],
    text=True,
    encoding="utf-8",
    errors="replace",
)

buckets = {"Added": [], "Fixed": [], "Changed": [], "Removed": []}
prefix_map = {
    "feat": "Added", "feature": "Added", "add": "Added", "adds": "Added",
    "fix": "Fixed", "bugfix": "Fixed", "hotfix": "Fixed",
    "refactor": "Changed", "change": "Changed", "chore": "Changed",
    "docs": "Changed", "doc": "Changed", "perf": "Changed",
    "style": "Changed", "build": "Changed", "ci": "Changed", "test": "Changed",
    "remove": "Removed", "removes": "Removed", "revert": "Removed",
    "deprecate": "Removed", "drop": "Removed",
}
pat = re.compile(r"^([A-Za-z]+)(?:\([^)]*\))?!?:\s*(.+)$")

for rec in raw.split(sep_rec):
    rec = rec.strip("\r\n")
    if not rec:
        continue
    parts = rec.split(sep_fld)
    if len(parts) != 4:
        continue
    sha, author, date, subject = parts
    cat = "Changed"
    text = subject
    m = pat.match(subject)
    if m:
        key = m.group(1).lower()
        text = m.group(2).strip()
        cat = prefix_map.get(key, "Changed")
    buckets[cat].append((date, sha[:7], text, author))

today = datetime.date.today().isoformat()
lines = []
lines.append("# Changelog")
lines.append("")
lines.append("## [Unreleased] - " + today)
lines.append("")
lines.append("_Range: `" + rng + "`_")
lines.append("")

total = 0
for cat in ("Added", "Fixed", "Changed", "Removed"):
    items = buckets[cat]
    if not items:
        continue
    lines.append("### " + cat)
    for date, sha, text, author in items:
        lines.append("- " + text + " (" + sha + ", " + date + ") - @" + author)
        total += 1
    lines.append("")

if total == 0:
    lines.append("_No commits found in the selected range._")
    lines.append("")

with open("CHANGELOG.md", "w", encoding="utf-8") as f:
    f.write("\n".join(lines).rstrip() + "\n")

print("CHANGELOG.md generated (" + str(total) + " entries).")
PY
