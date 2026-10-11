#!/usr/bin/env bash
# Prints a markdown table of how far each upstream pin is behind its repo's HEAD.
# Changes nothing. Exits 0 either way; read the table. Needs gh and python3.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v gh >/dev/null || { echo "pin-drift.sh: 'gh' not found on PATH" >&2; exit 1; }

python3 -I - <<'PY'
import json, subprocess

def gh(*args):
    return subprocess.check_output(["gh", "api", *args], text=True).strip()

data = json.load(open(".claude-plugin/marketplace.json"))
rows, behind_any = [], False
for plugin in data["plugins"]:
    src = plugin["source"]
    if not isinstance(src, dict):
        continue
    repo = src.get("repo") or src["url"].removeprefix("https://github.com/").removesuffix(".git")
    pinned = src.get("sha", "")
    try:
        head = gh(f"repos/{repo}/commits/HEAD", "-q", ".sha")
        if head == pinned:
            rows.append((plugin["name"], repo, pinned[:7], "current", "0"))
            continue
        behind = gh(f"repos/{repo}/compare/{pinned}...{head}", "-q", ".ahead_by")
        rows.append((plugin["name"], repo, pinned[:7], head[:7], behind))
        behind_any = True
    except subprocess.CalledProcessError:
        rows.append((plugin["name"], repo, pinned[:7], "lookup failed", "?"))

print("## Pin drift\n")
print("| Plugin | Upstream | Pinned | Upstream HEAD | Commits behind |")
print("|---|---|---|---|---|")
for r in rows:
    print("| " + " | ".join(r) + " |")
print()
print("Run `scripts/update-pins.sh`, read the diff and commit to take upstream changes."
      if behind_any else "All pins are current.")
PY
