# jaffskils-sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Plugins added to the jaffskils marketplace install themselves at the next session start, and `setup.sh` re-runs see the latest marketplace.

**Architecture:** A new local plugin `jaffskils-sync` with a SessionStart command hook (`sync.sh`, the `rtk` hook pattern). It refreshes the marketplace at most once an hour, installs only names it has never seen, and reports through a `systemMessage`. `setup.sh` gains a marketplace refresh when the marketplace is already added.

**Tech Stack:** bash, python3 (`-I`), the `claude` CLI (2.1.x). No jq.

**Spec:** `docs/superpowers/specs/2026-10-30-jaffskils-sync-design.md`

## Global Constraints

- Marketplace name `jaffskils`; plugin name `jaffskils-sync`; no `version` in its `plugin.json` or marketplace entry (local plugins are versioned by commit).
- State dir: `${CLAUDE_PLUGIN_DATA:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jaffskils-sync}`. Files: `seen.json`, `last-sync`, `lock/`.
- Sync interval 3600 s (mtime of `last-sync`); stale lock 600 s; hook `"timeout": 30`.
- `sync.sh` always exits 0. Its stdout is empty or exactly one JSON object `{"systemMessage": "..."}`.
- Every `claude` call reads `</dev/null`, and its stdout and stderr never reach the hook's stdout.
- Message copy, exact:
  - installs only: `jaffskils: installed A, B. Run /reload-plugins to load them.`
  - installs and failures: the above, then ` Could not install X, Y; run setup.sh --check.`
  - failures only: `jaffskils: could not install X, Y; run setup.sh --check.`
  - names in marketplace order, joined with `, `.
- Never uninstall, disable or enable a plugin.

## Review Focus

- Stray CLI output on the hook's stdout (install progress lines) would break the JSON Claude Code parses: tests compare the whole stdout, not a substring (Task 2).
- The hook gets JSON on stdin; a `claude` call that reads it could hang or eat it: `run_sync` always feeds a SessionStart JSON on stdin (Task 2 harness).
- Config dirs with spaces (as `test-setup.sh` uses deliberately) must work: the test env dir name contains a space (Task 2 harness).
- A `seen.json` left unreadable by a killed hook must not crash every later session: it is treated as absent and re-seeded (Task 3, `corrupt_seen_reseeds`).
- A nonzero exit shows a hook error at every session start: every case asserts exit code 0 (Tasks 2 and 3).

---

### Task 1: setup.sh refreshes an already-added marketplace

**Files:**
- Create: `tests/claude-shim` (executable)
- Modify: `setup.sh:440-441` (the `marketplace_listed` branch)
- Modify: `tests/test-setup.sh` (shim helper and two cases)

**Interfaces:**
- Produces: `tests/claude-shim`, a stand-in for `claude` used by both test files. It execs `$REAL_CLAUDE "$@"`, except:
  - if `$CLAUDE_SHIM_LOG` is set, it first appends `"$*"` as one line to that file;
  - if `"$*"` equals `$CLAUDE_SHIM_FAIL`, it prints `shim: forced failure` to stderr and exits 1.
- Usage: a test puts a dir holding a `claude` symlink to the shim first on `PATH`, with `REAL_CLAUDE` set to the real `claude` found before the `PATH` change.

- [ ] **Step 1: Write the shim and the failing tests**

In `tests/test-setup.sh` add `use_shim()`: create `$ENV_DIR.bin/claude` → symlink to `$REPO_ROOT/tests/claude-shim`, export `REAL_CLAUDE` (resolved once) and `CLAUDE_SHIM_LOG="$ENV_DIR.log"`, prepend `$ENV_DIR.bin` to `PATH`. Then:

```bash
case_rerun_refreshes_marketplace() {
  run_setup --no-clean --only rtk
  assert_eq "$RC" 0 "first run exit code"
  use_shim
  run_setup --no-clean --only rtk
  assert_eq "$RC" 0 "second run exit code"
  grep -qx "plugin marketplace update jaffskils" "$CLAUDE_SHIM_LOG" ||
    fail "re-run did not refresh the marketplace"
}

case_rerun_fails_when_refresh_fails() {
  run_setup --no-clean --only rtk
  use_shim
  export CLAUDE_SHIM_FAIL="plugin marketplace update jaffskils"
  run_setup --no-clean --only rtk
  assert_eq "$RC" 1 "exit code"
  grep -q "could not refresh marketplace 'jaffskils'" "$ENV_DIR.err" || fail "stderr does not name the problem"
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `tests/test-setup.sh rerun_`
Expected: `FAIL rerun_refreshes_marketplace`, `FAIL rerun_fails_when_refresh_fails`, `PASS rerun_is_idempotent`.

- [ ] **Step 3: Refresh in setup.sh**

In the `marketplace_listed` branch, after the "already added" echo: `claude plugin marketplace update "$MARKETPLACE" </dev/null >&2 || die "could not refresh marketplace '$MARKETPLACE'"` (the same call and message `scripts/update.sh:24` uses).

- [ ] **Step 4: Run the whole suite**

Run: `tests/test-setup.sh`
Expected: every case `PASS`, then `all passed`.

- [ ] **Step 5: Commit**

```bash
git add setup.sh tests/claude-shim tests/test-setup.sh
git commit -m "fix: setup.sh refreshes an already-added marketplace"
```

---

### Task 2: jaffskils-sync installs new plugins

**Files:**
- Create: `plugins/jaffskils-sync/.claude-plugin/plugin.json`
- Create: `plugins/jaffskils-sync/hooks/hooks.json`
- Create: `plugins/jaffskils-sync/hooks/sync.sh` (executable)
- Create: `tests/test-sync.sh` (executable)

**Interfaces:**
- Consumes: `tests/claude-shim` (Task 1).
- Produces: `sync.sh`, no arguments, stdin ignored. Env read: `CLAUDE_PLUGIN_DATA`, `CLAUDE_CONFIG_DIR`, `HOME`. Contract as in Global Constraints. Marketplace clone dir = `installLocation` of the `jaffskils` entry in `claude plugin marketplace list --json`. Installed = ids ending `@jaffskils` in `claude plugin list --json`.
- Produces: `tests/test-sync.sh` harness for Task 3: `new_env`, `add_plugin NAME`, `run_sync`, `is_installed NAME`, `seen_names`, `$STATE`, `$OUT`, `$RC`.

`plugin.json`: `{"name": "jaffskils-sync", "description": "Installs plugins newly added to the jaffskils marketplace at session start", "author": {"name": "jafforgehq"}}`

`hooks.json`, exact:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PLUGIN_ROOT}/hooks/sync.sh", "timeout": 30 }
        ]
      }
    ]
  }
}
```

- [ ] **Step 1: Write the harness and failing tests**

`tests/test-sync.sh`, same shape as `tests/test-setup.sh` (`fail`, `assert_eq`, `case_*` functions, `main [substring]`, `RUN_ROOT` under `${TMPDIR:-/tmp}`, kept on failure):
- `new_env`: `ENV_DIR=$(mktemp -d "$RUN_ROOT/sync test.XXXXXX")`, export `CLAUDE_CONFIG_DIR="$ENV_DIR/config"`, unset `CLAUDE_PLUGIN_DATA`, set `STATE="$CLAUDE_CONFIG_DIR/jaffskils-sync"`; build a git-committed marketplace `jaffskils` in `$ENV_DIR/src` listing local plugins `alpha` and `beta` (each just `.claude-plugin/plugin.json` with its name); `claude plugin marketplace add "$ENV_DIR/src"`; `claude plugin install alpha@jaffskils`; enable the shim as in Task 1.
- `add_plugin NAME`: create the plugin dir and append its entry to `marketplace.json`.
- `run_sync`: `echo '{"hook_event_name":"SessionStart","source":"startup"}' | "$REPO_ROOT/plugins/jaffskils-sync/hooks/sync.sh"` with stdout to `$OUT` (a variable), stderr to `$ENV_DIR.err`, exit code to `RC`.
- `is_installed NAME`, `seen_names` (names in `seen.json`, one per line, or nothing).
- `message`: the `systemMessage` of `$OUT` parsed as JSON; fails if `$OUT` is not exactly one JSON object.

```bash
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `tests/test-sync.sh`
Expected: three `FAIL` lines (sync.sh does not exist yet).

- [ ] **Step 3: Write plugin.json, hooks.json and sync.sh**

`sync.sh` follows the spec's flow, steps 2 to 8. Leave step 1's interval and lock out of this task, except the exit-0 guard for a missing `claude` or `python3`. No `set -e`. Use python3 for the set operations and to write `seen.json` (temp file in `$STATE`, then `mv`). Build the message with `json.dumps`.

- [ ] **Step 4: Run the tests**

Run: `tests/test-sync.sh && claude plugin validate plugins/jaffskils-sync`
Expected: three `PASS`, `all passed`, and `✔ Validation passed` (a "no version" warning is expected).

- [ ] **Step 5: Commit**

```bash
git add plugins/jaffskils-sync tests/test-sync.sh
git commit -m "feat: add jaffskils-sync, installs new marketplace plugins at session start"
```

---

### Task 3: sync guards: interval, lock, failures

**Files:**
- Modify: `plugins/jaffskils-sync/hooks/sync.sh`
- Modify: `tests/test-sync.sh`

**Interfaces:**
- Consumes: the Task 2 harness and the shim's `CLAUDE_SHIM_FAIL` and `CLAUDE_SHIM_LOG`.

- [ ] **Step 1: Write the failing tests**

```bash
case_second_run_within_hour_does_nothing() {
  run_sync; add_plugin gamma; : >"$CLAUDE_SHIM_LOG"
  run_sync
  assert_eq "$RC" 0 "exit code"; assert_eq "$OUT" "" "stdout"
  ! is_installed gamma || fail "gamma installed within the hour"
  ! grep -q "marketplace update" "$CLAUDE_SHIM_LOG" || fail "marketplace refreshed within the hour"
}

case_failed_install_reported_and_retried() {
  run_sync; add_plugin gamma; rm "$STATE/last-sync"
  CLAUDE_SHIM_FAIL="plugin install gamma@jaffskils" run_sync
  assert_eq "$RC" 0 "exit code"
  assert_eq "$(message)" "jaffskils: could not install gamma; run setup.sh --check." "message"
  ! seen_names | grep -qx gamma || fail "failed gamma marked seen"
  rm "$STATE/last-sync"; run_sync
  is_installed gamma || fail "gamma not retried"
}

case_held_lock_exits_silently() {
  run_sync; add_plugin gamma; rm "$STATE/last-sync"; mkdir "$STATE/lock"
  run_sync
  assert_eq "$RC" 0 "exit code"; assert_eq "$OUT" "" "stdout"
  ! is_installed gamma || fail "installed while locked"
}

case_stale_lock_is_removed() {
  run_sync; add_plugin gamma; rm "$STATE/last-sync"; mkdir "$STATE/lock"
  python3 -I -c 'import os,sys,time; t=time.time()-660; os.utime(sys.argv[1],(t,t))' "$STATE/lock"
  run_sync
  is_installed gamma || fail "stale lock blocked the sync"
  [[ ! -d $STATE/lock ]] || fail "lock not released"
}

case_refresh_failure_is_silent_and_retried() {
  CLAUDE_SHIM_FAIL="plugin marketplace update jaffskils" run_sync
  assert_eq "$RC" 0 "exit code"; assert_eq "$OUT" "" "stdout"
  [[ ! -e $STATE/last-sync ]] || fail "last-sync written after a failed refresh"
}

case_missing_claude_exits_silently() {
  RC=0; OUT=$(PATH=/usr/bin:/bin "$REPO_ROOT/plugins/jaffskils-sync/hooks/sync.sh" </dev/null) || RC=$?
  assert_eq "$RC" 0 "exit code"; assert_eq "$OUT" "" "stdout"
}

case_corrupt_seen_reseeds() {
  run_sync; printf '["alp' >"$STATE/seen.json"; add_plugin gamma; rm "$STATE/last-sync"
  run_sync
  assert_eq "$RC" 0 "exit code"; assert_eq "$OUT" "" "stdout"
  assert_eq "$(seen_names)" $'alpha\nbeta\ngamma' "re-seeded seen.json"
}
```

`case_missing_claude_exits_silently` must use `/bin/bash` explicitly if `sync.sh`'s shebang is `#!/usr/bin/env bash`, and `/usr/bin:/bin` must not contain `claude` (true on macOS and the CI runner).

- [ ] **Step 2: Run to verify they fail**

Run: `tests/test-sync.sh`
Expected: the three Task 2 cases `PASS`. `second_run_within_hour_does_nothing`, `held_lock_exits_silently` and `corrupt_seen_reseeds` `FAIL`; the others may already pass.

- [ ] **Step 3: Add the guards to sync.sh**

Spec step 1: interval check on `last-sync` mtime (python3 `os.stat`, portable across macOS and Linux), `mkdir` lock with the 600 s stale rule and `trap` release. Spec step 2: on refresh failure, exit 0 without touching `last-sync`. An unparsable `seen.json` is treated as absent.

- [ ] **Step 4: Run the tests**

Run: `tests/test-sync.sh`
Expected: all ten cases `PASS`, `all passed`.

- [ ] **Step 5: Commit**

```bash
git add plugins/jaffskils-sync/hooks/sync.sh tests/test-sync.sh
git commit -m "feat: jaffskils-sync interval, lock and failure handling"
```

---

### Task 4: Ship it: manifest, presets, README, CI

**Files:**
- Modify: `.claude-plugin/marketplace.json` (entry after `session-recap`)
- Modify: `presets.json`
- Modify: `README.md`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `plugins/jaffskils-sync` (Tasks 2 and 3).

- [ ] **Step 1: Add the marketplace entry and presets**

Entry: `{"name": "jaffskils-sync", "description": "Installs plugins newly added to this marketplace at session start; skipped plugins stay skipped", "source": "./plugins/jaffskils-sync"}`. Append `"jaffskils-sync"` to all four lists in `presets.json`.

- [ ] **Step 2: Update the README**

Follow the spec's "README changes": intro list (with the other plugins of mine), a new `## jaffskils-sync` section after `## Terminal UI mods`, `## Updates` paragraph, `## Add my own skill` step 3. Also cover the spec's "Known limits": one last `setup.sh` run for existing machines, and presets receiving later plugins.

- [ ] **Step 3: Add the CI step**

After `Run tests`: `- name: Run sync tests` / `run: tests/test-sync.sh`.

- [ ] **Step 4: Verify**

Run: `scripts/marketplace-lint.sh --remote && tests/test-lint.sh && claude plugin validate . && tests/test-setup.sh && tests/test-sync.sh`
Expected: `marketplace-lint: 19 plugins OK`, `all passed` from each test file (`installs_everything` now installs `jaffskils-sync` too), `✔ Validation passed`.

- [ ] **Step 5: Commit**

```bash
git add .claude-plugin/marketplace.json presets.json README.md .github/workflows/ci.yml
git commit -m "feat: list jaffskils-sync in the marketplace, presets, README and CI"
```
