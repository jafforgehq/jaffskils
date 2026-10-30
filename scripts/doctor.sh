#!/usr/bin/env bash
# Checks the tools and MCP servers jaffskils plugins rely on. Changes nothing.
# Exits 1 if a required check fails; optional ones only warn.
set -u

fails=0
ok() { printf '  ok    %s\n' "$1"; }
warn() { printf '  warn  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fails=$((fails + 1)); }

need() { command -v "$1" >/dev/null 2>&1 && ok "$1" || bad "$1 not found on PATH${2:+ ($2)}"; }
want() { command -v "$1" >/dev/null 2>&1 && ok "$1" || warn "$1 not found${2:+ ($2)}"; }

echo "Tools"
need claude "install Claude Code"
need python3
need git
want gh "pin-drift and update-pins need it"
want uvx "Blender MCP runs through it"
want rtk "the rtk plugin does nothing without it: brew install rtk-ai/tap/rtk"
want node "caveman, ponytail, designlang, ccusage and npx-based MCP servers need it"

if command -v claude >/dev/null 2>&1; then
  echo "Marketplace"
  if claude plugin marketplace list --json </dev/null | grep -q '"jaffskils"'; then
    ok "jaffskils marketplace added"
    if "$(dirname "${BASH_SOURCE[0]}")/../setup.sh" --check >/dev/null 2>&1; then
      ok "plugins in sync (setup.sh --check)"
    else
      warn "plugins out of sync; run setup.sh --list, then setup.sh or scripts/update.sh"
    fi
  else
    bad "jaffskils marketplace not added; run setup.sh"
  fi

  echo "MCP servers"
  mcp=$(claude mcp list 2>&1 </dev/null)
  while IFS= read -r line; do
    case $line in
      *"✔ Connected"*) ok "${line%% - *}" ;;
      *"Disabled"*) ;;
      *" - "*) warn "${line%% - *}: ${line##* - }" ;;
    esac
  done <<<"$mcp"

  # The Blender addon listens on the port shown in its sidebar panel; the MCP
  # server must be registered with the same --port or it connects to nothing.
  registered=$(grep -Eo 'mcp-for-blender --port [0-9]+' <<<"$mcp" | grep -Eo '[0-9]+$' | head -1)
  if [[ -n $registered ]]; then
    if command -v lsof >/dev/null 2>&1 && lsof -nP -iTCP:"$registered" -sTCP:LISTEN >/dev/null 2>&1; then
      ok "something listens on Blender port $registered"
    else
      warn "nothing listens on port $registered; in Blender click Connect in the MCP for Blender panel, and check its port matches"
    fi
  fi
fi

echo
if [[ $fails -eq 0 ]]; then echo "doctor: no required checks failed"; else echo "doctor: $fails required check(s) failed"; exit 1; fi
