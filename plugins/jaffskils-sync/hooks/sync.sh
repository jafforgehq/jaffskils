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

if not os.path.exists(seen_file):
    write_seen(names)
    sys.exit(0)
with open(seen_file) as f:
    seen = json.load(f)

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
