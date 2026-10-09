# jaffskils: personal Claude Code marketplace

Date: 2026-10-09
Status: spec approved by user; `setup.sh` and, later, "Exclusive mode" added at the user's request. Exclusive mode is awaiting the user's approval.

## Purpose

A personal GitHub repo that works as a long-lived Claude Code plugin marketplace.
Superpowers is the first entry. The owner adds their own skills over time and
installs and updates everything from this one place on their machines.

## Decisions

| Topic | Decision |
|---|---|
| Marketplace name | `jaffskils` (this is the name used in `plugin@marketplace`, not the repo name) |
| GitHub repo | `jafforgehq/jaffskils`, **public** |
| Owner | `{ "name": "jafforgehq" }`, no email (the file is public) |
| Superpowers | Referenced from upstream `obra/superpowers`, not copied |
| Pinning | None: no `version`, `ref` or `sha` on the superpowers entry |
| Own skills | Added later as local plugins under `plugins/<name>/`, relative-path source, no `version` |

## Repo layout

```
jaffskils/
├── .claude-plugin/marketplace.json
├── setup.sh
├── tests/test-setup.sh
├── README.md
└── docs/superpowers/specs/2026-10-09-jaffskils-marketplace-design.md
```

No `plugins/` directory until the first own plugin exists.

## marketplace.json

```json
{
  "name": "jaffskils",
  "description": "Personal Claude Code skills marketplace by jafforgehq",
  "owner": { "name": "jafforgehq" },
  "plugins": [
    {
      "name": "superpowers",
      "description": "Superpowers skills, tracked from upstream obra/superpowers",
      "source": { "source": "github", "repo": "obra/superpowers" }
    }
  ]
}
```

## Update behaviour (what "automatic" means)

Upstream changes reach the user only when all three hold:

1. **Marketplace auto-update is enabled.** It is off by default for third-party
   marketplaces. The user enables it once per machine: `/plugin` → Marketplaces →
   `jaffskils` → Enable auto-update. Plugins refresh up to about ten minutes after
   the first message of a session; a running session needs `/reload-plugins` or a
   restart to load the new version.
2. **The plugin is referenced, not copied.** The `github` source tracks upstream's
   default branch.
3. **The version string changes.** Upstream's `plugin.json` pins a `version`
   (6.4.2 at the time of writing), so the user receives upstream *releases*, not
   every commit. A plugin with no `version` set is versioned by commit SHA, so the
   owner's own unversioned plugins update on every push.

## Adding an own skill later

1. Create `plugins/<name>/.claude-plugin/plugin.json` and
   `plugins/<name>/skills/<skill>/SKILL.md`.
2. Add an entry to `marketplace.json` with `"source": "./plugins/<name>"` and no `version`.
3. Push. With auto-update on, the change reaches the user's machines.

## setup.sh (one command installs everything)

"Everything" means: the `jaffskils` marketplace, **every plugin listed in its
`marketplace.json`**, and auto-update enabled for it. It does not install Claude
Code itself and does not touch other marketplaces' plugins. Because it reads the
plugin list from the marketplace, adding a plugin later needs no edit to `setup.sh`.

Runs two ways:

```
git clone https://github.com/jafforgehq/jaffskils && ./jaffskils/setup.sh
curl -fsSL https://raw.githubusercontent.com/jafforgehq/jaffskils/main/setup.sh | bash
```

Steps, in order:

1. Fail early with a clear message if `claude` or `python3` is not on `PATH`.
2. `claude plugin marketplace add "$JAFFSKILS_SOURCE"`, skipped if `jaffskils` is
   already listed. `JAFFSKILS_SOURCE` defaults to `jafforgehq/jaffskils`; it exists
   so the script can be tested against a local path before the repo is published.
3. Find the marketplace checkout via `claude plugin marketplace list --json`
   (its install location) and read the plugin names from its
   `.claude-plugin/marketplace.json`. This one code path works for both run modes.
4. `claude plugin install <name>@jaffskils --scope user` for each plugin.
   An already-installed plugin is not an error.
5. Unless `--no-auto-update` is passed, set
   `extraKnownMarketplaces.jaffskils.autoUpdate = true` in the user settings file
   (`$CLAUDE_CONFIG_DIR/settings.json`, default `~/.claude/settings.json`). The CLI has
   no command for this. The edit uses `python3` (not `sed -i`, which behaves
   differently on macOS), keeps all other keys, backs the file up to
   `settings.json.jaffskils.bak` first, and writes atomically.
6. Print what was installed and remind the user to run `/reload-plugins` or
   restart Claude Code.

Properties: `set -euo pipefail`, idempotent (safe to re-run), no `sudo`, no network
access beyond what the `claude` CLI does, and it never prints or reads credentials.

## Exclusive mode: only jaffskils skills (added at the user's request)

After a successful install, `setup.sh` makes jaffskils the only source of skills in
the user's Claude Code config (`$CLAUDE_CONFIG_DIR`, default `~/.claude`):

| What | Action | Recoverable? |
|---|---|---|
| Plugins from any other marketplace (user scope) | `claude plugin uninstall <name>@<marketplace> --scope user` | Yes, reinstall from that marketplace |
| Marketplaces other than `jaffskils` | `claude plugin marketplace remove <name>`; the built-in Anthropic directory cannot be removed and is left | Yes, re-add |
| Standalone skills in `$CLAUDE_CONFIG_DIR/skills/` except the app-managed `synced` folder | **Moved** to `$CLAUDE_CONFIG_DIR/skills-removed-<YYYY-MM-DD>/` (numeric suffix if that exists); never deleted. The script prints the one command that purges that folder | Yes, until the user purges it |
| Plugins synced from claude.ai (`<name>@synced`) | `claude plugin disable <name>@synced`; they are account-managed and cannot be uninstalled | Yes, enable again |

Why a move and not a delete: the standalone skills have no recorded origin, so a
permanent delete cannot be undone. The user purges the backup folder themselves.

Safeguards:

- Install first, clean up second, so a failed install never leaves the user with nothing.
- The script computes the cleanup list read-only at the start. If the list is not
  empty it prints it and asks `Proceed? [y/N]`, reading the answer from
  `${JAFFSKILS_TTY:-/dev/tty}`. With no terminal and no `--yes` it refuses
  before changing anything (exit 1). An empty list needs no confirmation.
- `--dry-run` prints the list and exits 0 without changing anything, including
  no marketplace add and no install.
- `--yes` skips the prompt. `--no-clean` installs without any cleanup.
- Nothing belonging to `jaffskils` is ever removed. Project- and local-scope
  installs in other directories are out of reach and left alone.

Limits, stated in the README: Claude Code's built-in commands and skills, skills
the Claude desktop app supplies, and organisation-managed plugins cannot be removed
by a script.

## Install flow (goes in README)

Primary: run `setup.sh` as above. Manual equivalent:

```
/plugin marketplace add jafforgehq/jaffskils
/plugin install superpowers@jaffskils
```

then enable auto-update as described above. If superpowers is also installed from
another marketplace, hooks run twice, so use one source only.

## Publishing and verification

1. Run `claude plugin validate . --strict` locally and fix anything it reports.
2. Lint `setup.sh` with `bash -n` (and `shellcheck` if installed).
3. Test `setup.sh` in a **throwaway config directory**: set `CLAUDE_CONFIG_DIR` to a
   temp dir and `JAFFSKILS_SOURCE` to the local repo path, run it twice (to prove
   idempotence), and inspect the resulting `settings.json` and installed plugin list.
   The user's real `~/.claude` is not touched by this test.
4. Create `jafforgehq/jaffskils` with `gh` and push `main`.
5. The owner explicitly confirms immediately before step 4, because it is outward-facing.

The throwaway test also settles one open point: the exact shape of an
`extraKnownMarketplaces` entry with `autoUpdate` is taken from the docs and has not
yet been confirmed against this Claude Code version (2.1.292). Step 3 must confirm it
before the script is considered done.

## Out of scope

- Vendoring or modifying superpowers.
- Any skill of the owner's own (added later, one at a time).
- Private-repo setup.
- Installing Claude Code itself, or plugins from other marketplaces, in `setup.sh`.
