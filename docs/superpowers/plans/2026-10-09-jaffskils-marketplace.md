# jaffskils Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a public GitHub repo `jafforgehq/jaffskils` that is a Claude Code marketplace referencing upstream superpowers, plus a `setup.sh` that installs the marketplace, every plugin in it, and auto-update.

**Architecture:** One manifest (`.claude-plugin/marketplace.json`) and one idempotent bash script that drives the `claude plugin` CLI and edits user `settings.json` with `python3` for the one thing the CLI cannot do (auto-update). The script reads the plugin list from the installed marketplace, so it never needs editing when plugins are added.

**Tech Stack:** bash, python3 (stdlib only), Claude Code CLI 2.1.292, `gh`.

**Spec:** `docs/superpowers/specs/2026-10-09-jaffskils-marketplace-design.md`

## Global Constraints

- Marketplace name `jaffskils`; owner `{ "name": "jafforgehq" }`, no email; repo `jafforgehq/jaffskils`, public.
- Superpowers entry: `"source": { "source": "github", "repo": "obra/superpowers" }`, with **no** `version`, `ref` or `sha`.
- `setup.sh`: `set -euo pipefail`; idempotent; no `sudo`; installs with `--scope user`; flag `--no-auto-update`.
- Env vars: `JAFFSKILS_SOURCE` (default `jafforgehq/jaffskils`), `CLAUDE_CONFIG_DIR` (default `~/.claude`).
- Auto-update is set as `extraKnownMarketplaces.jaffskils.autoUpdate = true` in `$CLAUDE_CONFIG_DIR/settings.json`; backup first to `settings.json.jaffskils.bak`; atomic write; keep all other keys.
- JSON editing uses `python3`, never `sed -i` (macOS differs).
- Every test and probe runs against a **throwaway** `CLAUDE_CONFIG_DIR`; the real `~/.claude` is never modified before the user approves (Task 6).
- Commit messages end with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

Failure modes the spec implies; each has a named test in the owning task.

1. Fresh machine, no `settings.json` yet: created, not an error. (Task 4 `autoupdate_creates_missing_settings`)
2. `settings.json` is malformed JSON: abort non-zero, file left byte-identical. (Task 4 `malformed_settings_aborts_untouched`)
3. `settings.json` already has other keys and other marketplaces: all preserved. (Task 4 `settings_other_keys_preserved`)
4. Run as `curl | bash` (script on stdin, no script directory): works. (Task 3 `runs_from_stdin`)
5. Re-run: no failure, no duplicates, settings byte-identical. (Task 3 `rerun_is_idempotent`, Task 4 asserts settings unchanged)

The throwaway config path contains a space (see Task 3 helper), so unquoted variables fail the tests.

---

### Task 1: Marketplace manifest

**Files:**
- Create: `.claude-plugin/marketplace.json`

**Interfaces:**
- Produces: marketplace `jaffskils` listing plugin `superpowers`. Later tasks read plugin names from this file.

- [ ] **Step 1:** Run `claude plugin validate . --strict`. Expected: fails because no manifest exists.
- [ ] **Step 2:** Create `.claude-plugin/marketplace.json` with exactly the JSON in the spec's "marketplace.json" section.
- [ ] **Step 3:** Run `claude plugin validate . --strict`. Expected: exit 0. If strict mode objects to missing metadata, add a top-level `description` string; never add `version`, `ref` or `sha`.
- [ ] **Step 4:** Assert the entry is unpinned: `python3 -I -c 'import json;p=json.load(open(".claude-plugin/marketplace.json"))["plugins"][0];assert p["name"]=="superpowers" and not {"version","ref","sha"}&(p.keys()|p["source"].keys())'`. Expected: no output, exit 0.
- [ ] **Step 5:** Commit `.claude-plugin/marketplace.json` as `feat: add jaffskils marketplace manifest`.

### Task 2: Probe CLI and settings behaviour (throwaway)

Question: how do `claude plugin` and `settings.json` behave in an isolated config directory? Task 3 and Task 4 depend on the answers. Probe scripts are not kept; only the findings are.

**Files:**
- Modify: `docs/superpowers/plans/2026-10-09-jaffskils-marketplace.md` (append a `## Probe findings` section)

**Interfaces:**
- Produces: the findings below, which Tasks 3 and 4 consume.

- [ ] **Step 1: Prove isolation.** Record `shasum` of the real `~/.claude/settings.json`, `~/.claude/plugins/known_marketplaces.json` and `~/.claude/plugins/installed_plugins.json`. With `CLAUDE_CONFIG_DIR` set to a fresh `mktemp -d` directory (set `TMPDIR` to the session scratchpad), run `claude plugin marketplace add <repo root path>` and confirm state landed under the temp dir and the three real checksums are unchanged. If not, retry with `HOME` set to the temp dir. If neither isolates, **stop and report to the user**; do not continue against the real config.
- [ ] **Step 2: Record these facts:**
  - the JSON shape printed by `claude plugin marketplace list --json` (exact key holding the install location, and the key holding the marketplace name);
  - whether installing `superpowers@jaffskils` works with no login, and the exact key it adds to `installed_plugins.json`;
  - exit code and message of a second `marketplace add` of the same source, and of a second `install` of the same plugin.
- [ ] **Step 3: Confirm the auto-update shape.** Read the `extraKnownMarketplaces` entry schema in the official settings docs. Write that entry into the temp `settings.json` and check whether `claude plugin marketplace list --json` or `known_marketplaces.json` reports auto-update as on. If neither does, record that the shape could not be confirmed by CLI and say what evidence the docs give.
- [ ] **Step 4:** Append the findings to this file under `## Probe findings` and commit as `docs: record CLI probe findings`.

### Task 3: setup.sh core (add marketplace, install plugins)

**Files:**
- Create: `setup.sh` (mode 755), `tests/test-setup.sh` (mode 755)

**Interfaces:**
- Produces, CLI: `setup.sh [--no-auto-update]`; exit 0 on success, 1 on any failure, 2 on an unknown flag (usage printed to stderr).
- Produces, functions in `setup.sh` (all output to stderr except where noted):
  - `die MESSAGE` prints `setup.sh: MESSAGE` and exits 1.
  - `require_cmd NAME` calls `die` naming the missing command.
  - `marketplace_listed` returns 0 if `jaffskils` appears in `claude plugin marketplace list --json`.
  - `marketplace_dir` prints the install location of `jaffskils` (stdout).
  - `plugin_names DIR` prints one plugin name per line from `DIR/.claude-plugin/marketplace.json` (stdout).
- Produces, test helpers in `tests/test-setup.sh`: `new_env` creates `"$TMPDIR/jaffskils test.XXXXXX"` (the space is deliberate), exports `CLAUDE_CONFIG_DIR` to it and `JAFFSKILS_SOURCE` to the repo root; each test is a function `case_<name>`; the runner prints `PASS <name>` or `FAIL <name>` and exits 1 if any failed.
- Consumes: Probe findings (Task 2) for the `list --json` shape and for how repeat `add`/`install` behave.

- [ ] **Step 1: Write `tests/test-setup.sh`** with these cases (assertions use `python3 -I` for JSON, never `jq`):
  - `case_installs_everything`: exit 0; `jaffskils` is in `marketplace list --json`; `installed_plugins.json` contains `superpowers@jaffskils`.
  - `case_rerun_is_idempotent`: second run exits 0 and installed plugin entries are unchanged.
  - `case_runs_from_stdin`: `bash < setup.sh` exits 0 from a different working directory.
  - `case_unknown_flag_exits_2`: `setup.sh --bogus` exits 2 and stderr contains `Usage`.
  - `case_missing_claude_fails_clearly`: `env PATH=/nonexistent /bin/bash setup.sh` exits 1 and stderr names `claude`.
- [ ] **Step 2:** Run `TMPDIR=<scratchpad> tests/test-setup.sh`. Expected: every case prints `FAIL` (no `setup.sh` yet).
- [ ] **Step 3: Implement `setup.sh`** with the functions above. Order: parse flags, `require_cmd claude`, `require_cmd python3`, add marketplace from `${JAFFSKILS_SOURCE:-jafforgehq/jaffskils}` unless `marketplace_listed`, then `claude plugin install "$name@jaffskils" --scope user` for each name from `plugin_names "$(marketplace_dir)"`, treating "already installed" as success per the Probe findings. Do not use `BASH_SOURCE` or `$0` to locate files. Print a final line telling the user to run `/reload-plugins` or restart Claude Code. Leave the auto-update step to Task 4 but parse `--no-auto-update` now.
- [ ] **Step 4:** Run the tests. Expected: all five `PASS`. Run `bash -n setup.sh` (no output) and `shellcheck setup.sh tests/test-setup.sh` if installed (no findings).
- [ ] **Step 5:** Commit both files as `feat: add setup.sh core install flow`.

### Task 4: setup.sh auto-update settings merge

**Files:**
- Modify: `setup.sh`, `tests/test-setup.sh`

**Interfaces:**
- Produces: `enable_auto_update SETTINGS_PATH` in `setup.sh`. Sets `extraKnownMarketplaces.jaffskils` to the entry shape confirmed in Probe findings, with `autoUpdate` true, preserving every other key. Creates the file if absent. Backs up an existing file to `SETTINGS_PATH.jaffskils.bak` (named `settings.json.jaffskils.bak` for the default path) before writing, writes via a temp file in the same directory plus rename, and exits non-zero without touching the file if its contents are not valid JSON. Called from the main flow unless `--no-auto-update`.
- Consumes: Probe findings for the exact entry shape.

- [ ] **Step 1: Add tests** to `tests/test-setup.sh`:
  - `case_autoupdate_enabled`: after a run, `settings.json` has `extraKnownMarketplaces.jaffskils.autoUpdate == true`.
  - `case_autoupdate_creates_missing_settings`: starting with no `settings.json`, the run exits 0 and the file exists with only that marketplace entry.
  - `case_settings_other_keys_preserved`: seed `{"sentinel":{"keep":1},"extraKnownMarketplaces":{"other":{"autoUpdate":false}}}`; after the run both `sentinel` and `other` are unchanged and a `.jaffskils.bak` file equals the seed byte for byte.
  - `case_malformed_settings_aborts_untouched`: seed `{not json`; exit is non-zero, the file is byte-identical, stderr names `settings.json`.
  - `case_autoupdate_rerun_unchanged`: a second run leaves `settings.json` byte-identical.
  - `case_no_auto_update_flag`: starting with no `settings.json`, a run with `--no-auto-update` exits 0 and does not create `settings.json`.
- [ ] **Step 2:** Run the tests. Expected: the six new cases `FAIL`, the Task 3 cases still `PASS`.
- [ ] **Step 3:** Implement `enable_auto_update` with a `python3 -I` here-document that takes the path as an argument (no string interpolation of the path into code), and call it from the main flow.
- [ ] **Step 4:** Run all tests, `bash -n`, and `shellcheck` if installed. Expected: all `PASS`, no findings.
- [ ] **Step 5:** Commit as `feat: enable marketplace auto-update from setup.sh`.

### Task 5: README and spec layout

**Files:**
- Create: `README.md`
- Modify: `docs/superpowers/specs/2026-10-09-jaffskils-marketplace-design.md` (add `tests/test-setup.sh` to the repo layout block)

- [ ] **Step 1:** Write `README.md` covering, in this order: what the repo is; the two `setup.sh` run commands from the spec; the manual install commands; the three update conditions and how to enable auto-update by hand; how to add an own skill (the three spec steps); how to run `tests/test-setup.sh`.
- [ ] **Step 2:** Check the README against the spec: `grep -c` each of `setup.sh`, `jafforgehq/jaffskils`, `Enable auto-update`, `/reload-plugins`, `tests/test-setup.sh` and expect every count to be at least 1.
- [ ] **Step 3:** Commit as `docs: add README`.

### Task 6: Publish and verify (needs the user's explicit yes)

- [ ] **Step 1:** Run the full pre-publish check: `claude plugin validate . --strict`, `bash -n setup.sh`, `tests/test-setup.sh`. Expected: all pass.
- [ ] **Step 2: Stop and ask the user to confirm** creating the **public** repo `jafforgehq/jaffskils` and pushing `main`. Do not continue without a clear yes.
- [ ] **Step 3:** `gh repo create jafforgehq/jaffskils --public --source . --remote origin --push`. Expected: repo URL printed, `main` pushed.
- [ ] **Step 4: Verify against the real GitHub source.** In a fresh throwaway `CLAUDE_CONFIG_DIR`, run `setup.sh` with `JAFFSKILS_SOURCE` unset; then run it as `curl -fsSL https://raw.githubusercontent.com/jafforgehq/jaffskils/main/setup.sh | bash`. Expected: both exit 0, `superpowers@jaffskils` installed, auto-update recorded.
- [ ] **Step 5:** Report the results to the user and **ask** before running `setup.sh` against their real `~/.claude`.

---

## Probe findings

Measured 2026-10-09 with Claude Code 2.1.292, against a throwaway `CLAUDE_CONFIG_DIR` and the local repo path as the marketplace source.

1. **Isolation works.** With `CLAUDE_CONFIG_DIR` set, everything lands under it (`settings.json`, `.claude.json`, `plugins/`). The checksums of the real `~/.claude/settings.json`, `plugins/known_marketplaces.json`, `plugins/installed_plugins.json` and `~/.claude.json` were identical before and after. The `HOME` fallback was not needed.
2. **`marketplace add <source>`** exits 0. It creates `$CLAUDE_CONFIG_DIR/settings.json` if absent and writes `extraKnownMarketplaces.jaffskils.source` into it (for a path: `{"source":"directory","path":"<abs path>"}`), and records the marketplace in `plugins/known_marketplaces.json`.
3. **`marketplace list --json`** prints a JSON array of objects with keys `name`, `source` (a type string such as `"directory"`), `path` and `installLocation`. Built-in marketplaces do not appear in the JSON. `installLocation` is the checkout to read `.claude-plugin/marketplace.json` from. A GitHub source will carry a repo field instead of `path`; that case is unverified until Task 6.
4. **`install superpowers@jaffskils --scope user`** works with no login and exits 0. It adds the key `superpowers@jaffskils` to `plugins/installed_plugins.json` (scope `user`, version 6.4.2 at the time) and sets `enabledPlugins["superpowers@jaffskils"] = true` in `settings.json`.
5. **Repeats are harmless.** A second `install` exits 0 with `already installed (scope: user)`. A second `marketplace add` of the same source exits 0 with `already on disk — declared in user settings`. `setup.sh` needs no special handling for either.
6. **Auto-update entry shape (docs, not CLI-confirmed).** The `extraKnownMarketplaces.<name>` entry takes a boolean `autoUpdate` beside `source`:
   `{ "source": { ... }, "autoUpdate": true }` (verbatim example on the plugins/org docs page; the plugins/loading page says this entry is the first source consulted for auto-update). The CLI does not report it: after setting it, `list --json` and `known_marketplaces.json` were unchanged, though the key survived `marketplace update` in `settings.json`. Tests can therefore assert only on `settings.json`; real auto-update behaviour rests on the docs.

### Consequences for Tasks 3 and 4

- `setup.sh` may skip `marketplace add` when the marketplace is already listed (as planned), but calling it again would also be safe.
- In the end-to-end flow `settings.json` already exists, with the marketplace entry and `enabledPlugins`, by the time auto-update is set. `enable_auto_update` therefore sets `autoUpdate: true` on the existing entry and keeps `source` untouched.
- If the entry or the whole file is absent (for example the user deleted it and re-ran), `enable_auto_update` creates the entry with a derived source: `{"source":"directory","path":<absolute path>}` when `JAFFSKILS_SOURCE` is an existing directory, otherwise `{"source":"github","repo":<JAFFSKILS_SOURCE>}`.
- Task 4's `case_autoupdate_creates_missing_settings` is reached end-to-end by running once, deleting `settings.json`, and re-running. Its assertion is that the file is recreated with the `jaffskils` entry and `autoUpdate == true`; it does not assert that the file holds nothing else.
