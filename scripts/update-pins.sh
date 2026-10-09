#!/usr/bin/env bash
# Pins every upstream plugin in .claude-plugin/marketplace.json to the current
# HEAD of its repo. Run it when you want to take upstream changes, review the
# diff, then commit. Needs gh and python3.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v gh >/dev/null || { echo "update-pins.sh: 'gh' not found on PATH" >&2; exit 1; }

python3 -I - <<'PY'
import json, subprocess

path = ".claude-plugin/marketplace.json"
data = json.load(open(path))
for plugin in data["plugins"]:
    src = plugin["source"]
    if not isinstance(src, dict):
        continue  # local plugin, versioned by commit
    repo = src.get("repo") or src["url"].removeprefix("https://github.com/").removesuffix(".git")
    sha = subprocess.check_output(
        ["gh", "api", f"repos/{repo}/commits/HEAD", "-q", ".sha"], text=True).strip()
    if src.get("sha") != sha:
        old = src.get("sha", "unpinned")[:7]
        print(f"{plugin['name']}: {old} -> {sha[:7]}")
    src["sha"] = sha
open(path, "w").write(json.dumps(data, indent=2) + "\n")
PY
