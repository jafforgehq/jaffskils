# jaffskils: personal Claude Code marketplace

Date: 2026-10-09
Status: design approved in chat; spec pending user review

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

## Install flow (goes in README)

```
/plugin marketplace add jafforgehq/jaffskils
/plugin install superpowers@jaffskils
```

Then enable auto-update as described above. If superpowers is also installed from
another marketplace, hooks run twice, so use one source only.

## Publishing and verification

1. Run `claude plugin validate .` locally and fix anything it reports.
2. Create `jafforgehq/jaffskils` with `gh` and push `main`.
3. The owner explicitly confirms immediately before step 2, because it is outward-facing.

Not yet verified: an end-to-end `marketplace add` and `install` against the
published repo. Facts above come from the Claude Code docs and a read of the
upstream repo, not from a test install.

## Out of scope

- Vendoring or modifying superpowers.
- Any skill of the owner's own (added later, one at a time).
- Private-repo setup.
