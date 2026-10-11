#!/usr/bin/env bash
# Prints markdown: for every pin that differs between the committed
# marketplace.json (git HEAD) and the working tree, the upstream commits between
# the old and the new sha. Run it after scripts/update-pins.sh. Needs gh, git,
# python3.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
command -v gh >/dev/null || { echo "pin-changelog.sh: 'gh' not found on PATH" >&2; exit 1; }

old=$(git show HEAD:.claude-plugin/marketplace.json)
OLD_JSON=$old python3 -I - <<'PY'
import json, os, subprocess

def repo_of(src):
    repo = src.get("repo") or src["url"].removeprefix("https://github.com/").removesuffix(".git")
    return repo

old = {p["name"]: p["source"] for p in json.loads(os.environ["OLD_JSON"])["plugins"]}
new = json.load(open(".claude-plugin/marketplace.json"))["plugins"]
out, count = [], 0
for plugin in new:
    src, was = plugin["source"], old.get(plugin["name"])
    if not isinstance(src, dict) or not isinstance(was, dict):
        continue
    a, b = was.get("sha"), src.get("sha")
    if not a or a == b:
        continue
    repo = repo_of(src)
    count += 1
    out.append(f"### {plugin['name']}: `{a[:7]}` -> `{b[:7]}`\n")
    out.append(f"[Compare on GitHub](https://github.com/{repo}/compare/{a}...{b})\n")
    try:
        raw = subprocess.check_output(
            ["gh", "api", f"repos/{repo}/compare/{a}...{b}", "-q",
             '.commits[] | "- " + (.sha[0:7]) + " " + (.commit.message | split("\\n")[0])'],
            text=True).strip().splitlines()
    except subprocess.CalledProcessError:
        raw = ["- (commit list unavailable)"]
    out.extend(raw[:30])
    if len(raw) > 30:
        out.append(f"- ... and {len(raw) - 30} more")
    out.append("")
if count == 0:
    print("No pins changed.")
else:
    print(f"Pins changed: {count}. Read each list below before merging.\n")
    print("\n".join(out))
PY
