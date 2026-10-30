# jaffskils-sync: new marketplace plugins install themselves

Date: 2026-10-30
Status: design approved by user in chat; spec awaiting review.

## Purpose

A plugin added to `marketplace.json` reaches no machine today. Auto-update and
`scripts/update.sh` only update plugins that are already installed, so each machine
needs a manual `setup.sh` re-run, and even that re-run reads a stale marketplace clone
because `setup.sh` does not refresh an already-added marketplace.

After this change, one `setup.sh` run per machine is the last manual step: plugins
added to the marketplace later install themselves at the next session start.

## Decisions

| Topic | Decision |
|---|---|
| Mechanism | SessionStart **command** hook (the `rtk` pattern), not a mod: it must run `claude plugin install`, and it works on builds without mod support |
| Plugin name | `jaffskils-sync`, local plugin under `plugins/jaffskils-sync/`, no `version` |
| What gets installed | Only plugins that are **new** to the marketplace since the last sync. Plugins skipped with `--pick`/`--only`/`--preset`, or uninstalled on purpose, stay gone |
| First run | Records the current marketplace names and installs nothing |
| Frequency | At most once per hour per machine |
| Feedback | A `systemMessage` shown to the user, only when something was installed or failed |
| Never does | Uninstall, disable, enable, or run exclusive-mode cleanup |
| Rejected: background sync | Hook forks the sync and reports at the *next* session start. Never delays startup, but feedback is one session late and it needs extra result state |
| Rejected: hook calls `setup.sh --sync` | Reuses install code, but ties the plugin to `setup.sh` internals and the marketplace clone layout |

## Files

```
plugins/jaffskils-sync/
├── .claude-plugin/plugin.json      # name "jaffskils-sync", author jafforgehq
└── hooks/
    ├── hooks.json                  # SessionStart → sync.sh, "timeout": 30
    └── sync.sh                     # bash + python3, like setup.sh
tests/test-sync.sh
```

Also changed: `.claude-plugin/marketplace.json` (new entry), `presets.json`
(`jaffskils-sync` in all four presets), `setup.sh` (marketplace refresh),
`README.md`, `.github/workflows/ci.yml` (a `Run sync tests` step running
`tests/test-sync.sh`, after `Run tests`).

## State

Directory: `${CLAUDE_PLUGIN_DATA}` if Claude Code sets it for hooks, otherwise
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/jaffskils-sync/`. The first implementation step
checks which one is available. Contents:

| File | Meaning |
|---|---|
| `seen.json` | JSON list of plugin names already considered. Absent means first run |
| `last-sync` | Touched after each sync that reached the marketplace; its mtime drives the one-hour limit |
| `lock/` | `mkdir` lock so two sessions starting together do not both install |

## sync.sh flow

1. Exit 0 silently when `claude` or `python3` is missing, when `last-sync` is less
   than an hour old, or when `mkdir lock` fails. A lock older than 10 minutes is
   treated as stale and removed. The lock is released on exit (`trap`).
2. `claude plugin marketplace update jaffskils`. On failure (offline, marketplace not
   added): exit 0 silently, leave `last-sync` untouched so the next session retries.
3. Touch `last-sync`.
4. Read plugin names from the marketplace clone's `.claude-plugin/marketplace.json`.
   The clone is found the same way `setup.sh`'s `marketplace_dir` finds it.
5. No `seen.json`: write the current names to it and exit 0.
6. `new` = names not in `seen.json`. Installed names come from
   `claude plugin list --json` (ids ending in `@jaffskils`). For each name in `new`:
   - already installed: add to `seen.json`;
   - otherwise `claude plugin install <name>@jaffskils`; on success add to
     `seen.json`, on failure leave it out so the next sync retries.
7. Write `seen.json` once at the end (atomic: temp file, then `mv`).
8. If anything was installed or failed, print one JSON object to stdout:
   `{"systemMessage": "jaffskils: installed android-skills, swiftui-pro. Run /reload-plugins to load them."}`,
   plus `" Could not install X; run setup.sh --check."` when an install failed.
   Otherwise print nothing.

Names removed from the marketplace stay in `seen.json`; that is harmless.

## setup.sh change

In the "already added" branch, run `claude plugin marketplace update "$MARKETPLACE"`
before reading the plugin list, and fail with a clear message if it fails. This makes
the README's "re-run `setup.sh`" instruction work.

## README changes

- Intro list: add `jaffskils-sync`.
- New section `## jaffskils-sync`: what it does, the first-run rule, the one-hour
  limit, where its state lives, and how to opt out (disable the plugin).
- `## Updates`: replace the "re-run `setup.sh` for new plugins" paragraph with: new
  plugins arrive at the next session start through `jaffskils-sync`; machines set up
  before it existed need one more `setup.sh` run.
- `## Add my own skill`, step 3: push; the plugin installs itself on each machine at
  the next session start.

## Known limits

- Machines set up before this plugin existed need one last `setup.sh` run to get it.
- A machine set up from a preset also receives later plugins outside that preset.
- A session start that runs a sync can wait for the marketplace refresh and installs,
  up to the 30 s hook timeout. If the hook is killed mid-install, that plugin is not in
  `seen.json` and is retried.

## Tests

`tests/test-sync.sh`, in the style of `tests/test-setup.sh`: throwaway
`CLAUDE_CONFIG_DIR`, a small local marketplace, the real `claude` CLI. Cases:

1. First run writes `seen.json` with all names and installs nothing.
2. A plugin added to the marketplace afterwards is installed and named in the
   `systemMessage`.
3. A plugin present at first run but not installed stays uninstalled.
4. A second run within the hour does nothing (no marketplace refresh).
5. A failed install is reported, left out of `seen.json`, and retried next run.
6. With the lock held, the run exits silently.

`setup.sh` change: one case in `tests/test-setup.sh` showing that a re-run on an
already-added marketplace sees a plugin added to the source after the first run.
