#!/usr/bin/env bash
# Lints .claude-plugin/marketplace.json: unique names, local sources that exist
# and carry a matching plugin.json, upstream sources that carry a 40-hex sha.
# With --remote it also asks GitHub whether each pinned sha exists (needs gh).
# Exits 1 on any problem. Needs python3.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

REMOTE=0
case "${1:-}" in
  "") ;;
  --remote) REMOTE=1 ;;
  *) echo "Usage: marketplace-lint.sh [--remote]" >&2; exit 2 ;;
esac
if [[ $REMOTE -eq 1 ]]; then
  command -v gh >/dev/null || { echo "marketplace-lint.sh: 'gh' not found on PATH" >&2; exit 1; }
fi

REMOTE=$REMOTE python3 -I - <<'PY'
import json, os, re, subprocess, sys

problems = []
data = json.load(open(".claude-plugin/marketplace.json"))
seen = set()

def repo_of(src):
    repo = src.get("repo") or src.get("url", "")
    return repo.removeprefix("https://github.com/").removesuffix(".git")

for plugin in data.get("plugins", []):
    name = plugin.get("name")
    if not name:
        problems.append("a plugin entry has no name")
        continue
    if name in seen:
        problems.append(f"{name}: listed twice")
    seen.add(name)
    if not plugin.get("description"):
        problems.append(f"{name}: no description")

    src = plugin.get("source")
    if isinstance(src, str):
        path = src.removeprefix("./")
        manifest = os.path.join(path, ".claude-plugin", "plugin.json")
        if not os.path.isdir(path):
            problems.append(f"{name}: source directory {src} does not exist")
        elif not os.path.isfile(manifest):
            problems.append(f"{name}: {manifest} is missing")
        else:
            declared = json.load(open(manifest)).get("name")
            if declared != name:
                problems.append(f"{name}: {manifest} names the plugin '{declared}'")
        if "version" in plugin:
            problems.append(f"{name}: local plugins must not pin a version (versioned by commit)")
    elif isinstance(src, dict):
        sha = src.get("sha", "")
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            problems.append(f"{name}: sha '{sha}' is not 40 lowercase hex characters")
        elif os.environ["REMOTE"] == "1":
            repo = repo_of(src)
            found = subprocess.run(
                ["gh", "api", f"repos/{repo}/commits/{sha}", "-q", ".sha"],
                capture_output=True, text=True)
            if found.returncode != 0:
                problems.append(f"{name}: sha {sha[:7]} not found in {repo}")
        if not (src.get("repo") or src.get("url")):
            problems.append(f"{name}: source has neither repo nor url")
    else:
        problems.append(f"{name}: source is neither a path nor an object")

# Local plugin directories that no entry lists.
listed = {p["source"].removeprefix("./") for p in data.get("plugins", [])
          if isinstance(p.get("source"), str)}
if os.path.isdir("plugins"):
    for d in sorted(os.listdir("plugins")):
        if os.path.isdir(os.path.join("plugins", d)) and f"plugins/{d}" not in listed:
            problems.append(f"plugins/{d} exists but marketplace.json does not list it")

if problems:
    print("marketplace-lint: " + str(len(problems)) + " problem(s)", file=sys.stderr)
    for p in problems:
        print("  - " + p, file=sys.stderr)
    sys.exit(1)
print(f"marketplace-lint: {len(seen)} plugins OK")
PY
