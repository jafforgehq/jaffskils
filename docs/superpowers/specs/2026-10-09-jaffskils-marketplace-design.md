# jaffskils: personal Claude Code marketplace

Date: 2026-10-09
Status: spec approved by user; `setup.sh` added at the user's request (section below)

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
├── README.md
└── docs/superpowers/specs/2026-10-09-jaffskils-marketplace-design.md
```

No `plugins/` directory until the first own plugin exists.

## marketplace.json

```json
{
  "name": "jaffskils",
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
