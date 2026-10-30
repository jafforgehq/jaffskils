#!/usr/bin/env bash
# Integration tests for plugins/jaffskils-sync/hooks/sync.sh. Every case runs
# against a throwaway CLAUDE_CONFIG_DIR and a small local marketplace named
# jaffskils (plugins alpha and beta, alpha installed), with tests/claude-shim in
# front of the real claude CLI. No network needed.
#
# Usage: tests/test-sync.sh [substring]  (run only the cases whose name contains it)
set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SYNC="$REPO_ROOT/plugins/jaffskils-sync/hooks/sync.sh"
RUN_ROOT=""
ENV_DIR=""
SRC=""
STATE=""
OUT=""
RC=0

fail() { echo "  assertion failed: $*" >&2; return 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "$3: expected '$2', got '$1'"; }

# add_plugin NAME: a minimal local plugin, appended to the marketplace.
add_plugin() {
  mkdir -p "$SRC/plugins/$1/.claude-plugin"
  echo "{\"name\": \"$1\"}" >"$SRC/plugins/$1/.claude-plugin/plugin.json"
  python3 -I -c '
import json, sys
f = sys.argv[1] + "/.claude-plugin/marketplace.json"
d = json.load(open(f))
d["plugins"].append({"name": sys.argv[2], "description": sys.argv[2], "source": "./plugins/" + sys.argv[2]})
json.dump(d, open(f, "w"), indent=2)
' "$SRC" "$1"
}

# Fresh config dir (the space in its name is deliberate) and marketplace.
new_env() {
  ENV_DIR=$(mktemp -d "$RUN_ROOT/sync test.XXXXXX")
  export CLAUDE_CONFIG_DIR="$ENV_DIR/config"
  [[ $CLAUDE_CONFIG_DIR != "$HOME/.claude" ]] || exit 99
  mkdir -p "$CLAUDE_CONFIG_DIR"
  unset CLAUDE_PLUGIN_DATA CLAUDE_SHIM_FAIL
  STATE="$CLAUDE_CONFIG_DIR/jaffskils-sync"
  SRC="$ENV_DIR/src"
  mkdir -p "$SRC/.claude-plugin"
  echo '{"name": "jaffskils", "owner": {"name": "jafforgehq"}, "plugins": []}' \
    >"$SRC/.claude-plugin/marketplace.json"
  add_plugin alpha
  add_plugin beta
  claude plugin marketplace add "$SRC" </dev/null >/dev/null
  claude plugin install alpha@jaffskils </dev/null >/dev/null
  mkdir -p "$ENV_DIR/bin"
  ln -s "$REPO_ROOT/tests/claude-shim" "$ENV_DIR/bin/claude"
  export CLAUDE_SHIM_LOG="$ENV_DIR/shim.log"
  export PATH="$ENV_DIR/bin:$PATH"
}

# run_sync: runs the hook as Claude Code would, JSON on stdin. Sets OUT and RC.
run_sync() {
  RC=0
  OUT=$(echo '{"hook_event_name":"SessionStart","source":"startup"}' | "$SYNC" 2>>"$ENV_DIR/sync.err") || RC=$?
}

is_installed() {
  claude plugin list --json </dev/null | python3 -I -c '
import json, sys
sys.exit(0 if any(p["id"] == sys.argv[1] + "@jaffskils" for p in json.load(sys.stdin)) else 1)
' "$1"
}

# Names in seen.json, one per line; nothing when it is missing or unreadable.
seen_names() {
  python3 -I -c '
import json, sys
try:
    print("\n".join(json.load(open(sys.argv[1]))))
except (OSError, ValueError):
    pass
' "$STATE/seen.json"
}

# The systemMessage in OUT; fails unless OUT is exactly one JSON object.
message() {
  python3 -I -c 'import json, sys; print(json.loads(sys.argv[1])["systemMessage"])' "$OUT"
}

case_first_run_seeds_and_installs_nothing() {
  run_sync
  assert_eq "$RC" 0 "exit code"; assert_eq "$OUT" "" "stdout"
  assert_eq "$(seen_names)" $'alpha\nbeta' "seen.json"
  ! is_installed beta || fail "beta was installed on first run"
}

case_new_plugin_installed_and_reported() {
  run_sync; add_plugin gamma; rm "$STATE/last-sync"
  run_sync
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(message)" "jaffskils: installed gamma. Run /reload-plugins to load them." "message"
  is_installed gamma || fail "gamma not installed"
  ! is_installed beta || fail "skipped beta was installed"
  seen_names | grep -qx gamma || fail "gamma not in seen.json"
}

case_new_plugin_already_installed_is_silent() {
  run_sync; add_plugin gamma; claude plugin install gamma@jaffskils </dev/null >/dev/null
  rm "$STATE/last-sync"; run_sync
  assert_eq "$RC" 0 "exit code"; assert_eq "$OUT" "" "stdout"
  seen_names | grep -qx gamma || fail "gamma not in seen.json"
}

main() {
  export REAL_CLAUDE
  REAL_CLAUDE=$(command -v claude) || { echo "claude not found on PATH" >&2; exit 1; }
  RUN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/jaffskils-sync-tests.XXXXXX") || exit 1
  local failed=0 c rc
  for c in $(declare -F | awk '{print $3}' | grep '^case_'); do
    [[ -z ${1:-} || $c == *"$1"* ]] || continue
    ( set -e; new_env; trap 'rc=$?; [[ $rc -eq 0 ]] || tail -n 20 "$ENV_DIR/sync.err" >&2 2>/dev/null' EXIT; "$c" )
    rc=$?
    if [[ $rc -eq 0 ]]; then echo "PASS ${c#case_}"; else echo "FAIL ${c#case_}"; failed=$((failed + 1)); fi
  done
  if [[ $failed -eq 0 ]]; then
    [[ $RUN_ROOT == */jaffskils-sync-tests.* ]] && rm -rf -- "$RUN_ROOT"
    echo "all passed"
  else
    echo "$failed failed; kept $RUN_ROOT for inspection" >&2
    exit 1
  fi
}

main "$@"
