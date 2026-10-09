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

settings_file() { echo "$CLAUDE_CONFIG_DIR/settings.json"; }

# json_get FILE KEY...: prints the JSON value at that key path, or MISSING.
json_get() {
  python3 -I -c '
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))
for k in sys.argv[2:]:
    if not isinstance(v, dict) or k not in v:
        print("MISSING")
        sys.exit(0)
    v = v[k]
print(json.dumps(v, sort_keys=True))
' "$@"
}

case_autoupdate_enabled() {
  run_setup
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils autoUpdate)" true "autoUpdate"
}

# The first run leaves a settings.json; deleting it and re-running reaches the
# path where enable_auto_update must create the file and the entry itself.
case_autoupdate_creates_missing_settings() {
  run_setup
  assert_eq "$RC" 0 "first run exit code"
  rm -f "$(settings_file)"
  run_setup
  assert_eq "$RC" 0 "second run exit code"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils autoUpdate)" true "autoUpdate"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils source source)" '"directory"' "derived source type"
}

case_settings_other_keys_preserved() {
  local seed='{"sentinel":{"keep":1},"extraKnownMarketplaces":{"other":{"source":{"source":"github","repo":"example/other"},"autoUpdate":false}}}'
  printf '%s' "$seed" >"$(settings_file)"
  printf '%s' "$seed" >"$ENV_DIR.seed"
  run_setup
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(json_get "$(settings_file)" sentinel)" '{"keep": 1}' "sentinel key"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces other autoUpdate)" false "other marketplace"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils autoUpdate)" true "jaffskils autoUpdate"
  cmp -s "$(settings_file).jaffskils.bak" "$ENV_DIR.seed" || fail "backup is not the original file byte for byte"
}

case_malformed_settings_aborts_untouched() {
  printf '%s' '{not json' >"$(settings_file)"
  printf '%s' '{not json' >"$ENV_DIR.seed"
  run_setup
  assert_eq "$RC" 1 "exit code"
  cmp -s "$(settings_file)" "$ENV_DIR.seed" || fail "settings.json was modified"
  grep -q settings.json "$ENV_DIR.err" || fail "stderr does not name settings.json"
  if marketplace_names 2>/dev/null | grep -qx jaffskils; then fail "marketplace was added despite the bad settings.json"; fi
}

case_autoupdate_rerun_unchanged() {
  run_setup
  assert_eq "$RC" 0 "first run exit code"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils autoUpdate)" true "autoUpdate after first run"
  cp "$(settings_file)" "$ENV_DIR.after1"
  run_setup
  assert_eq "$RC" 0 "second run exit code"
  cmp -s "$(settings_file)" "$ENV_DIR.after1" || fail "settings.json changed on re-run"
}

case_no_auto_update_flag() {
  run_setup --no-auto-update
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils autoUpdate)" MISSING "autoUpdate"
  [[ ! -e "$(settings_file).jaffskils.bak" ]] || fail "a backup was made although settings were not edited"
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
