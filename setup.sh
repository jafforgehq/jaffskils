#!/usr/bin/env bash
# jaffskils setup: add the jaffskils marketplace and install every plugin in it.
#
#   git clone https://github.com/jafforgehq/jaffskils && ./jaffskils/setup.sh
#   curl -fsSL https://raw.githubusercontent.com/jafforgehq/jaffskils/main/setup.sh | bash
#
# Environment: JAFFSKILS_SOURCE (marketplace source, default jafforgehq/jaffskils),
#              CLAUDE_CONFIG_DIR (default ~/.claude).
set -euo pipefail

MARKETPLACE=jaffskils
SOURCE=${JAFFSKILS_SOURCE:-jafforgehq/jaffskils}
AUTO_UPDATE=1

die() { echo "setup.sh: $*" >&2; exit 1; }

usage() { echo "Usage: setup.sh [--no-auto-update]" >&2; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH"; }

# Every claude call gets stdin from /dev/null: when this script is piped into
# bash, a command that reads stdin would otherwise swallow the rest of it.
marketplace_listed() {
  claude plugin marketplace list --json </dev/null |
    python3 -I -c '
import json, sys
sys.exit(0 if any(m.get("name") == sys.argv[1] for m in json.load(sys.stdin)) else 1)
' "$MARKETPLACE"
}

marketplace_dir() {
  claude plugin marketplace list --json </dev/null |
    python3 -I -c '
import json, sys
for m in json.load(sys.stdin):
    if m.get("name") == sys.argv[1]:
        print(m["installLocation"])
        sys.exit(0)
sys.exit(1)
' "$MARKETPLACE"
}

settings_path() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; }

# Die unless the settings file is absent or holds a JSON object. Runs before
# anything else so a broken file is never touched, by us or by the claude CLI.
check_settings() {
  [[ -e $1 ]] || return 0
  python3 -I -c '
import json, sys
if not isinstance(json.load(open(sys.argv[1], encoding="utf-8")), dict):
    raise ValueError("not a JSON object")
' "$1" 2>/dev/null ||
    die "$1 is not a valid JSON settings file; fix or move it, then re-run (nothing was changed)"
}

# Keep the original once: later runs must not overwrite it with edited copies.
backup_settings() {
  [[ -f $1 && ! -e $1.jaffskils.bak ]] || return 0
  cp -p "$1" "$1.jaffskils.bak"
}

# The claude CLI has no auto-update command; the setting lives on the
# marketplace's extraKnownMarketplaces entry. Writes only if something changes.
enable_auto_update() {
  python3 -I -c '
import json, os, sys, tempfile
path, name, source = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
markets = data.setdefault("extraKnownMarketplaces", {})
if not isinstance(markets, dict):
    sys.exit(path + ": extraKnownMarketplaces is not an object")
entry = markets.setdefault(name, {})
before = json.dumps(data, sort_keys=True)
if "source" not in entry:
    entry["source"] = (
        {"source": "directory", "path": os.path.abspath(source)}
        if os.path.isdir(source)
        else {"source": "github", "repo": source}
    )
entry["autoUpdate"] = True
if json.dumps(data, sort_keys=True) == before and os.path.exists(path):
    sys.exit(0)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".settings.", suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
if os.path.exists(path):
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
os.replace(tmp, path)
' "$1" "$MARKETPLACE" "$SOURCE" || die "could not enable auto-update in $1"
}

plugin_names() {
  python3 -I -c '
import json, sys
for p in json.load(open(sys.argv[1] + "/.claude-plugin/marketplace.json"))["plugins"]:
    print(p["name"])
' "$1"
}

main() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --no-auto-update) AUTO_UPDATE=0 ;;
      *) usage; exit 2 ;;
    esac
    shift
  done

  require_cmd claude
  require_cmd python3

  local settings
  settings=$(settings_path)
  if [[ $AUTO_UPDATE -eq 1 ]]; then
    check_settings "$settings"
    backup_settings "$settings"
  fi

  if marketplace_listed; then
    echo "Marketplace '$MARKETPLACE' is already added." >&2
  else
    claude plugin marketplace add "$SOURCE" </dev/null || die "could not add marketplace '$SOURCE'"
  fi

  local dir names name
  dir=$(marketplace_dir) || die "marketplace '$MARKETPLACE' not found after adding it"
  names=$(plugin_names "$dir") || die "could not read the plugin list in $dir"

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    claude plugin install "$name@$MARKETPLACE" --scope user </dev/null ||
      die "could not install $name@$MARKETPLACE"
  done <<<"$names"

  if [[ $AUTO_UPDATE -eq 1 ]]; then
    enable_auto_update "$settings"
    echo "Auto-update is on for '$MARKETPLACE'." >&2
  fi

  echo "Installed from $MARKETPLACE: $(echo "$names" | tr '\n' ' ')" >&2
  echo "Run /reload-plugins in Claude Code, or restart it, to load them." >&2
}

# Everything is defined above; running main last means a truncated download
# of this script cannot execute half of it.
main "$@"
