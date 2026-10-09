#!/usr/bin/env bash
# Integration tests for setup.sh. Every case runs against a throwaway
# CLAUDE_CONFIG_DIR, so the real ~/.claude is never touched. Needs network:
# superpowers is fetched from GitHub.
#
# Usage: TMPDIR=/some/dir tests/test-setup.sh
set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SETUP="$REPO_ROOT/setup.sh"
RUN_ROOT=""
ENV_DIR=""
RC=0

fail() { echo "  assertion failed: $*" >&2; return 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "$3: expected '$2', got '$1'"; }

# Fresh throwaway config dir; the space in its name is deliberate.
new_env() {
  ENV_DIR=$(mktemp -d "$RUN_ROOT/jaffskils test.XXXXXX")
  export CLAUDE_CONFIG_DIR="$ENV_DIR"
  export JAFFSKILS_SOURCE="$REPO_ROOT"
  [[ -n $CLAUDE_CONFIG_DIR && $CLAUDE_CONFIG_DIR != "$HOME/.claude" ]] || exit 99
}

# run_setup [args...]: sets RC; stdout and stderr go to "$ENV_DIR.out" / ".err".
run_setup() {
  RC=0
  "$SETUP" "$@" >"$ENV_DIR.out" 2>"$ENV_DIR.err" || RC=$?
}

marketplace_names() {
  claude plugin marketplace list --json </dev/null |
    python3 -I -c 'import json,sys; print("\n".join(m["name"] for m in json.load(sys.stdin)))'
}

installed_json() { echo "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"; }

json_has_plugin() {
  python3 -I -c 'import json,sys; sys.exit(0 if sys.argv[2] in json.load(open(sys.argv[1]))["plugins"] else 1)' \
    "$(installed_json)" "$1"
}

plugins_snapshot() {
  python3 -I -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["plugins"], sort_keys=True))' \
    "$(installed_json)"
}

case_installs_everything() {
  run_setup
  assert_eq "$RC" 0 "exit code"
  marketplace_names | grep -qx jaffskils || fail "jaffskils is not a configured marketplace"
  json_has_plugin superpowers@jaffskils || fail "superpowers@jaffskils is not installed"
}

case_rerun_is_idempotent() {
  run_setup
  assert_eq "$RC" 0 "first run exit code"
  local before
  before=$(plugins_snapshot)
  run_setup
  assert_eq "$RC" 0 "second run exit code"
  assert_eq "$(plugins_snapshot)" "$before" "installed plugins after re-run"
}

case_runs_from_stdin() {
  RC=0
  (cd "$ENV_DIR" && bash <"$SETUP" >"$ENV_DIR.out" 2>"$ENV_DIR.err") || RC=$?
  assert_eq "$RC" 0 "exit code when the script arrives on stdin"
  json_has_plugin superpowers@jaffskils || fail "superpowers@jaffskils is not installed"
}

case_unknown_flag_exits_2() {
  run_setup --bogus
  assert_eq "$RC" 2 "exit code"
  grep -q Usage "$ENV_DIR.err" || fail "stderr has no usage message"
}

case_missing_claude_fails_clearly() {
  RC=0
  env PATH=/nonexistent /bin/bash "$SETUP" >"$ENV_DIR.out" 2>"$ENV_DIR.err" || RC=$?
  assert_eq "$RC" 1 "exit code"
  grep -q claude "$ENV_DIR.err" || fail "stderr does not name the missing 'claude' command"
}

main() {
  RUN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/jaffskils-tests.XXXXXX") || exit 1
  local failed=0 c rc
  for c in $(declare -F | awk '{print $3}' | grep '^case_'); do
    ( set -e; new_env; "$c" )
    rc=$?
    if [[ $rc -eq 0 ]]; then echo "PASS ${c#case_}"; else echo "FAIL ${c#case_}"; failed=$((failed + 1)); fi
  done
  if [[ $failed -eq 0 ]]; then
    [[ $RUN_ROOT == */jaffskils-tests.* ]] && rm -rf -- "$RUN_ROOT"
    echo "all passed"
  else
    echo "$failed failed; kept $RUN_ROOT for inspection" >&2
    exit 1
  fi
}

main
