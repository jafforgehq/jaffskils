# jaffskils

A personal [Claude Code](https://claude.com/claude-code) skills marketplace by
[jafforgehq](https://github.com/jafforgehq). It currently lists
[superpowers](https://github.com/obra/superpowers), referenced from upstream, and
is where my own skills will be added over time.

## Set up a machine

One command adds the marketplace, installs every plugin in it, turns on
auto-update, and makes jaffskils the only source of skills (see
[Exclusive mode](#exclusive-mode)):

```bash
git clone https://github.com/jafforgehq/jaffskils && ./jaffskils/setup.sh
```

or, without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/jafforgehq/jaffskils/main/setup.sh | bash
```

Look before you leap: `setup.sh --dry-run` prints what it would change and
changes nothing. With the curl form, pass flags after `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/jafforgehq/jaffskils/main/setup.sh | bash -s -- --dry-run
```

Afterwards run `/reload-plugins` in Claude Code, or restart it. The first run saves
your original `settings.json` as `settings.json.jaffskils.bak` and never overwrites
that copy.

| Flag | Effect |
|---|---|
| `--dry-run` | Show what exclusive mode would change; change nothing |
| `--yes` | Skip the confirmation prompt (needed when there is no terminal) |
| `--no-clean` | Install only; leave other skills alone |
| `--no-auto-update` | Do not touch the auto-update setting |

`setup.sh` is safe to re-run. It needs `claude` and `python3` on your `PATH`.

## Exclusive mode

After a successful install, `setup.sh` removes everything that is not from jaffskils
from your Claude Code config (`~/.claude`, or `$CLAUDE_CONFIG_DIR`):

| What | What happens |
|---|---|
| Plugins from other marketplaces (user scope) | Uninstalled |
| Marketplaces other than jaffskils, including Anthropic's `claude-plugins-official` | Removed. This also uninstalls their plugins, wherever they were installed, and deletes those plugins' saved options and data. Only the built-in Anthropic directory stays. Claude Code may re-add `claude-plugins-official` in a later session; it adds no skills, and re-running removes it again. To get it back: `claude plugin marketplace add anthropics/claude-plugins-official` |
| Standalone skills in `~/.claude/skills` (except the app-managed `synced` folder) | **Moved** to `~/.claude/skills-removed-<date>/`, never deleted |
| Plugins synced from claude.ai | Disabled (they are account-managed and cannot be uninstalled) |

It prints the full list first and asks `Proceed? [y/N]`. With no terminal and no
`--yes` it refuses before changing anything. To delete the moved skills for good,
remove the `skills-removed-<date>` folder yourself; the script prints the exact
command.

What a script cannot remove: Claude Code's built-in commands and skills, skills the
Claude desktop app supplies, and organisation-managed plugins.

## Install by hand

```
/plugin marketplace add jafforgehq/jaffskils
/plugin install superpowers@jaffskils
```

If superpowers is also installed from another marketplace, its hooks run twice, so
use one source only.

## Updates

Upstream changes reach you only when all three of these hold:

1. **Auto-update is on** for this marketplace. It is off by default for third-party
   marketplaces; `setup.sh` turns it on. By hand: `/plugin` → Marketplaces →
   jaffskils → Enable auto-update. Plugins refresh up to about ten minutes after the
   first message of a session, and a running session needs `/reload-plugins`.
2. **The plugin is referenced, not copied.** The superpowers entry points at
   `obra/superpowers` and tracks its default branch.
3. **The version string changes.** Upstream pins a `version` in its `plugin.json`, so
   you receive upstream releases rather than every commit. A plugin of mine with no
   `version` is versioned by commit, so every push reaches you.

## Add my own skill

1. Create `plugins/<name>/.claude-plugin/plugin.json` and
   `plugins/<name>/skills/<skill>/SKILL.md`.
2. Add an entry to `.claude-plugin/marketplace.json` with
   `"source": "./plugins/<name>"` and no `version`.
3. Push. With auto-update on, the change reaches my machines.

Check the manifest with `claude plugin validate . --strict`.

## Tests

`tests/test-setup.sh` runs `setup.sh` against throwaway config directories, so your
real `~/.claude` is never touched. It needs network access, because superpowers is
fetched from GitHub:

```bash
tests/test-setup.sh
```
