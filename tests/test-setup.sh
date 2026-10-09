#!/usr/bin/env bash
# Integration tests for setup.sh. Every case runs against a throwaway
# CLAUDE_CONFIG_DIR, so the real ~/.claude is never touched. Most cases use a
# small local marketplace (just the rtk plugin); installs_everything installs the
# real manifest and so needs network, because upstream plugins come from GitHub.
#
# Usage: TMPDIR=/some/dir tests/test-setup.sh
set -u

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SETUP="$REPO_ROOT/setup.sh"
RUN_ROOT=""
LITE_SOURCE=""
ENV_DIR=""
RC=0

fail() { echo "  assertion failed: $*" >&2; return 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "$3: expected '$2', got '$1'"; }

# Fresh throwaway config dir; the space in its name is deliberate.
new_env() {
  ENV_DIR=$(mktemp -d "$RUN_ROOT/jaffskils test.XXXXXX")
  export CLAUDE_CONFIG_DIR="$ENV_DIR"
  export JAFFSKILS_SOURCE="$LITE_SOURCE"
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

# A marketplace named jaffskils that lists only the local rtk plugin, so cases that
# are not about the plugin list do not clone every upstream repo.
make_lite_source() {
  LITE_SOURCE="$RUN_ROOT/lite"
  mkdir -p "$LITE_SOURCE/.claude-plugin" "$LITE_SOURCE/plugins"
  cp -R "$REPO_ROOT/plugins/rtk" "$LITE_SOURCE/plugins/rtk"
  cat >"$LITE_SOURCE/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "jaffskils",
  "owner": { "name": "jafforgehq" },
  "plugins": [{ "name": "rtk", "description": "rtk", "source": "./plugins/rtk" }]
}
JSON
  git -C "$LITE_SOURCE" init -q && git -C "$LITE_SOURCE" add -A &&
    git -C "$LITE_SOURCE" -c user.name=t -c user.email=t@t commit -q -m lite
}

case_installs_everything() {
  export JAFFSKILS_SOURCE="$REPO_ROOT"
  run_setup
  assert_eq "$RC" 0 "exit code"
  marketplace_names | grep -qx jaffskils || fail "jaffskils is not a configured marketplace"
  json_has_plugin rtk@jaffskils || fail "rtk@jaffskils is not installed"
  local name
  for name in $(python3 -I -c 'import json,sys; print(" ".join(p["name"] for p in json.load(open(sys.argv[1]))["plugins"]))' \
    "$REPO_ROOT/.claude-plugin/marketplace.json"); do
    json_has_plugin "$name@jaffskils" || fail "$name@jaffskils is not installed"
  done
}

case_rtk_hook_passes_through_without_rtk() {
  local out
  out=$(echo '{"tool_input":{"command":"git status"}}' |
    PATH=/nonexistent /bin/bash "$REPO_ROOT/plugins/rtk/hooks/rtk-rewrite.sh") ||
    fail "hook failed when rtk is missing"
  assert_eq "$out" "" "hook output without rtk"
}

case_rtk_hook_rewrites_when_rtk_present() {
  command -v rtk >/dev/null && command -v jq >/dev/null || return 0
  local out
  out=$(echo '{"tool_input":{"command":"git status"}}' |
    /bin/bash "$REPO_ROOT/plugins/rtk/hooks/rtk-rewrite.sh") || fail "hook failed"
  [[ $out == *'"command":"rtk git status"'* ]] || fail "git status was not rewritten: $out"
}

case_every_upstream_plugin_is_pinned() {
  python3 -I -c '
import json, sys
bad = [p["name"] for p in json.load(open(sys.argv[1]))["plugins"]
       if isinstance(p["source"], dict) and not p["source"].get("sha")]
sys.exit("unpinned: " + ", ".join(bad) if bad else 0)' \
    "$REPO_ROOT/.claude-plugin/marketplace.json" || fail "an upstream plugin has no sha"
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
  json_has_plugin rtk@jaffskils || fail "rtk@jaffskils is not installed"
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

# --- exclusive mode -------------------------------------------------------

FIXTURE=""

# A tiny marketplace (one plugin, one skill) standing in for "somebody else's".
make_fixture() {
  FIXTURE="$RUN_ROOT/fixture-mkt"
  mkdir -p "$FIXTURE/.claude-plugin" "$FIXTURE/plugins/fixtureplug/.claude-plugin" \
    "$FIXTURE/plugins/fixtureplug/skills/fixtureskill"
  cat >"$FIXTURE/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "fixturemkt",
  "description": "Test fixture marketplace",
  "owner": { "name": "tests" },
  "plugins": [ { "name": "fixtureplug", "description": "Fixture plugin", "source": "./plugins/fixtureplug" } ]
}
JSON
  printf '%s\n' '{ "name": "fixtureplug", "description": "Fixture plugin" }' \
    >"$FIXTURE/plugins/fixtureplug/.claude-plugin/plugin.json"
  printf -- '---\nname: fixtureskill\ndescription: Fixture skill\n---\nFixture.\n' \
    >"$FIXTURE/plugins/fixtureplug/skills/fixtureskill/SKILL.md"
}

add_fixture_plugin() {
  claude plugin marketplace add "$FIXTURE" </dev/null >/dev/null 2>&1 &&
    claude plugin install fixtureplug@fixturemkt --scope user </dev/null >/dev/null 2>&1
}

seed_skills() {
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/alpha" "$CLAUDE_CONFIG_DIR/skills/beta" "$CLAUDE_CONFIG_DIR/skills/synced"
  printf 'alpha skill\n' >"$CLAUDE_CONFIG_DIR/skills/alpha/SKILL.md"
  printf 'beta skill\n' >"$CLAUDE_CONFIG_DIR/skills/beta/SKILL.md"
  printf 'keep\n' >"$CLAUDE_CONFIG_DIR/skills/synced/keep.txt"
}

backup_dirs() { ls -d "$CLAUDE_CONFIG_DIR"/skills-removed-* 2>/dev/null; }

fixture_installed() { json_has_plugin fixtureplug@fixturemkt 2>/dev/null; }

case_cleanup_removes_other_plugins_and_marketplaces() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  fixture_installed || fail "fixture plugin not installed before the run"
  run_setup --yes
  assert_eq "$RC" 0 "exit code"
  if fixture_installed; then fail "fixture plugin is still installed"; fi
  if marketplace_names | grep -qx fixturemkt; then fail "fixture marketplace is still listed"; fi
  json_has_plugin rtk@jaffskils || fail "a jaffskils plugin was removed"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils autoUpdate)" true "autoUpdate after cleanup"
}

case_cleanup_moves_standalone_skills() {
  seed_skills
  run_setup --yes
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(ls -A "$CLAUDE_CONFIG_DIR/skills")" synced "what is left in skills/"
  local b
  b=$(backup_dirs)
  [[ -n $b ]] || fail "no backup folder was created"
  cmp -s "$b/alpha/SKILL.md" <(printf 'alpha skill\n') || fail "alpha was not moved intact"
  cmp -s "$b/beta/SKILL.md" <(printf 'beta skill\n') || fail "beta was not moved intact"
  assert_eq "$(cat "$CLAUDE_CONFIG_DIR/skills/synced/keep.txt")" keep "synced folder content"
  grep -q "rm -rf" "$ENV_DIR.err" || fail "the purge command was not printed"
}

case_cleanup_backup_never_overwritten() {
  seed_skills
  run_setup --yes
  assert_eq "$RC" 0 "first run exit code"
  mkdir -p "$CLAUDE_CONFIG_DIR/skills/gamma"
  printf 'gamma skill\n' >"$CLAUDE_CONFIG_DIR/skills/gamma/SKILL.md"
  run_setup --yes
  assert_eq "$RC" 0 "second run exit code"
  assert_eq "$(backup_dirs | wc -l | tr -d ' ')" 2 "number of backup folders"
  [[ -f "$(backup_dirs | sed -n 1p)/alpha/SKILL.md" ]] || fail "the first backup lost alpha"
  [[ -f "$(backup_dirs | sed -n 2p)/gamma/SKILL.md" ]] || fail "the second backup does not hold gamma"
}

case_dry_run_changes_nothing() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  seed_skills
  run_setup --dry-run
  assert_eq "$RC" 0 "exit code"
  cat "$ENV_DIR.out" "$ENV_DIR.err" >"$ENV_DIR.all"
  local w
  for w in fixtureplug fixturemkt alpha; do
    grep -q "$w" "$ENV_DIR.all" || fail "dry-run output does not mention $w"
  done
  fixture_installed || fail "dry run uninstalled the fixture plugin"
  [[ -d "$CLAUDE_CONFIG_DIR/skills/alpha" ]] || fail "dry run moved a skill"
  [[ ! -e "$(settings_file).jaffskils.bak" ]] || fail "dry run made a settings backup"
  if marketplace_names | grep -qx jaffskils; then fail "dry run added the jaffskils marketplace"; fi
}

case_dry_run_with_no_clean_is_a_usage_error() {
  run_setup --dry-run --no-clean
  assert_eq "$RC" 2 "exit code"
  grep -q "cannot be combined" "$ENV_DIR.err" || fail "stderr does not explain the conflicting flags"
}

case_no_clean_flag_skips_cleanup() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  seed_skills
  run_setup --no-clean
  assert_eq "$RC" 0 "exit code"
  fixture_installed || fail "the fixture plugin was removed despite --no-clean"
  [[ -d "$CLAUDE_CONFIG_DIR/skills/alpha" ]] || fail "a skill was moved despite --no-clean"
  json_has_plugin rtk@jaffskils || fail "rtk was not installed"
}

case_cleanup_refused_without_terminal() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  seed_skills
  JAFFSKILS_TTY=/nonexistent run_setup
  assert_eq "$RC" 1 "exit code"
  grep -q -- --yes "$ENV_DIR.err" || fail "stderr does not mention --yes"
  fixture_installed || fail "the fixture plugin was removed"
  [[ -d "$CLAUDE_CONFIG_DIR/skills/alpha" ]] || fail "a skill was moved"
  if marketplace_names | grep -qx jaffskils; then fail "the marketplace was added before the refusal"; fi
}

case_cleanup_declined_changes_nothing() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  seed_skills
  printf 'n\n' >"$ENV_DIR.answer"
  JAFFSKILS_TTY="$ENV_DIR.answer" run_setup
  assert_eq "$RC" 1 "exit code"
  fixture_installed || fail "the fixture plugin was removed"
  [[ -d "$CLAUDE_CONFIG_DIR/skills/alpha" ]] || fail "a skill was moved"
}

case_cleanup_confirmed_at_prompt() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  seed_skills
  printf 'y\n' >"$ENV_DIR.answer"
  JAFFSKILS_TTY="$ENV_DIR.answer" run_setup
  assert_eq "$RC" 0 "exit code"
  if fixture_installed; then fail "the fixture plugin is still installed"; fi
  [[ ! -d "$CLAUDE_CONFIG_DIR/skills/alpha" ]] || fail "alpha was not moved"
}

case_cleanup_noop_when_clean() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  run_setup --yes
  assert_eq "$RC" 0 "first run exit code"
  run_setup --yes
  assert_eq "$RC" 0 "second run exit code"
  grep -q "Nothing to clean up" "$ENV_DIR.err" || fail "second run did not report a clean state"
}

case_cleanup_missing_skills_dir() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  run_setup --yes
  assert_eq "$RC" 0 "exit code"
  [[ ! -e "$CLAUDE_CONFIG_DIR/skills" ]] || fail "a skills directory appeared"
  assert_eq "$(backup_dirs | wc -l | tr -d ' ')" 0 "number of backup folders"
}

# Synced plugins cannot be created in a throwaway config, so a shim reports one
# and records disable calls; everything else goes to the real CLI.
case_cleanup_disables_synced_plugins() {
  local bin="$ENV_DIR.bin" real
  real=$(command -v claude)
  mkdir -p "$bin"
  cat >"$bin/claude" <<SHIM
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "plugin list --json" ]]; then
  "$real" "\$@" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d.append({"id":"demo@synced","version":"1","scope":"synced","enabled":True,"installPath":"/x"}); print(json.dumps(d))'
elif [[ "\$1 \$2" == "plugin disable" ]]; then
  echo "\$3" >>"$ENV_DIR.disabled"
else
  exec "$real" "\$@"
fi
SHIM
  chmod +x "$bin/claude"
  PATH="$bin:$PATH" run_setup --yes
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(cat "$ENV_DIR.disabled")" demo@synced "plugin passed to disable"
}

# A step failing part-way through cleanup must say that auto-update is still off
# and that re-running is safe; the shim makes `marketplace remove` fail.
case_cleanup_failure_names_next_step() {
  add_fixture_plugin || fail "could not set up the fixture plugin"
  local bin="$ENV_DIR.bin" real
  real=$(command -v claude)
  mkdir -p "$bin"
  cat >"$bin/claude" <<SHIM
#!/usr/bin/env bash
if [[ "\$1 \$2 \$3" == "plugin marketplace remove" ]]; then
  echo "simulated failure" >&2
  exit 1
fi
exec "$real" "\$@"
SHIM
  chmod +x "$bin/claude"
  PATH="$bin:$PATH" run_setup --yes
  assert_eq "$RC" 1 "exit code"
  grep -q "Auto-update has NOT been enabled" "$ENV_DIR.err" || fail "stderr does not say auto-update is still off"
  grep -q "safe to re-run" "$ENV_DIR.err" || fail "stderr does not say re-running is safe"
  assert_eq "$(json_get "$(settings_file)" extraKnownMarketplaces jaffskils autoUpdate)" MISSING "autoUpdate after a failed cleanup"
}

# Usage: tests/test-setup.sh [substring]  (run only the cases whose name contains it)
main() {
  RUN_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/jaffskils-tests.XXXXXX") || exit 1
  make_fixture
  make_lite_source
  local failed=0 c rc
  for c in $(declare -F | awk '{print $3}' | grep '^case_'); do
    [[ -z ${1:-} || $c == *"$1"* ]] || continue
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

main "$@"
