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
# shellcheck disable=SC2034  # read by the auto-update step
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

  echo "Installed from $MARKETPLACE: $(echo "$names" | tr '\n' ' ')" >&2
  echo "Run /reload-plugins in Claude Code, or restart it, to load them." >&2
}

# Everything is defined above; running main last means a truncated download
# of this script cannot execute half of it.
main "$@"
