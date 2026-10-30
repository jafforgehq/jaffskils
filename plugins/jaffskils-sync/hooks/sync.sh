#!/usr/bin/env bash
# SessionStart hook: installs plugins added to the jaffskils marketplace since
# the last sync. The first run only records what the marketplace lists, so
# plugins skipped at setup (or uninstalled later) are never installed here.
# Always exits 0. Prints nothing, or one {"systemMessage": ...} line for Claude
# Code to show. Needs claude and python3.
MARKETPLACE=jaffskils
STATE=${CLAUDE_PLUGIN_DATA:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jaffskils-sync}

command -v claude >/dev/null && command -v python3 >/dev/null || exit 0
mkdir -p "$STATE" || exit 0

# At most one sync an hour, one session at a time. A lock older than 10 minutes
# is left over from a hook that was killed.
age() { python3 -I -c 'import os, sys, time; print(int(time.time() - os.stat(sys.argv[1]).st_mtime))' "$1" 2>/dev/null; }
if a=$(age "$STATE/last-sync") && ((a < 3600)); then exit 0; fi
if a=$(age "$STATE/lock") && ((a >= 600)); then rmdir "$STATE/lock" 2>/dev/null; fi
mkdir "$STATE/lock" 2>/dev/null || exit 0
trap 'rmdir "$STATE/lock" 2>/dev/null' EXIT

# Offline or marketplace not added: stay quiet, and retry next session.
claude plugin marketplace update "$MARKETPLACE" </dev/null >/dev/null 2>&1 || exit 0
touch "$STATE/last-sync"

STATE=$STATE MARKETPLACE=$MARKETPLACE python3 -I - <<'PY'
import json, os, subprocess, sys

state, market = os.environ["STATE"], os.environ["MARKETPLACE"]
seen_file = os.path.join(state, "seen.json")


def claude_json(*args):
    out = subprocess.run(["claude", *args], stdin=subprocess.DEVNULL,
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def write_seen(names):
    tmp = seen_file + ".tmp"
    with open(tmp, "w") as f:
        json.dump(names, f)
    os.replace(tmp, seen_file)


try:
    clone = next(m["installLocation"] for m in claude_json("plugin", "marketplace", "list", "--json")
                 if m.get("name") == market)
    with open(os.path.join(clone, ".claude-plugin", "marketplace.json")) as f:
        names = [p["name"] for p in json.load(f)["plugins"]]
    installed = {p["id"].rpartition("@")[0] for p in claude_json("plugin", "list", "--json")
                 if p["id"].endswith("@" + market)}
except (OSError, ValueError, KeyError, StopIteration, subprocess.CalledProcessError):
    sys.exit(0)

# Missing (first run) or unreadable (hook killed mid-write): record, install nothing.
try:
    with open(seen_file) as f:
        seen = json.load(f)
    if not isinstance(seen, list):
        raise ValueError
except (OSError, ValueError):
    write_seen(names)
    sys.exit(0)

done, failed = [], []
for name in names:
    if name in seen:
        continue
    if name in installed:
        seen.append(name)
        continue
    rc = subprocess.run(["claude", "plugin", "install", f"{name}@{market}"], stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
    if rc == 0:
        seen.append(name)
        done.append(name)
    else:
        failed.append(name)
write_seen(seen)

if done:
    msg = f"jaffskils: installed {', '.join(done)}. Run /reload-plugins to load them."
    if failed:
        msg += f" Could not install {', '.join(failed)}; run setup.sh --check."
elif failed:
    msg = f"jaffskils: could not install {', '.join(failed)}; run setup.sh --check."
else:
    sys.exit(0)
print(json.dumps({"systemMessage": msg}))
PY
exit 0
