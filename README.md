# jaffskils

A personal [Claude Code](https://claude.com/claude-code) skills marketplace by
[jafforgehq](https://github.com/jafforgehq). It currently lists
[superpowers](https://github.com/obra/superpowers),
[context7](https://github.com/upstash/context7),
[humanizer](https://github.com/blader/humanizer),
[marketing-skills](https://github.com/coreyhaines31/marketingskills),
[caveman](https://github.com/JuliusBrussee/caveman),
[godot-prompter](https://github.com/jame581/GodotPrompter),
[taste-skill](https://github.com/Leonxlnx/taste-skill),
[designlang](https://github.com/Manavarya09/design-extract),
[android-skills](https://github.com/android/skills),
[swiftui-pro](https://github.com/twostraws/SwiftUI-Agent-Skill),
[swift-concurrency](https://github.com/AvdLee/Swift-Concurrency-Agent-Skill) and
[ponytail](https://github.com/DietrichGebert/ponytail), all referenced from upstream,
and wrappers and plugins of my own: `rtk`, around [rtk](https://github.com/rtk-ai/rtk),
`ccusage`, around [ccusage](https://github.com/ccusage/ccusage), `domain-scout`,
`jaffskils-sync`, which installs newly added plugins on its own, and four terminal UI
mods: `status-bar`, `done-toast`, `session-recap` and `sidecar`. It is where my own skills will be
added over time.

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
| `--list` | Show every plugin the marketplace offers against what is installed; change nothing |
| `--check` | Like `--list`, and exit 1 if a plugin is missing, disabled or no longer in the marketplace |
| `--pick` | Choose plugins interactively: numbers, a preset name, or Enter for all |
| `--preset NAME` | Install a preset from `presets.json` (`minimal`, `gamedev`, `marketing`, `design`, or `all`) |
| `--only a,b,c` | Install only these plugins |

`--pick`, `--preset` and `--only` are mutually exclusive. Without them every plugin
is installed. Plugins you leave out are not uninstalled if already present.

`setup.sh` is safe to re-run, and a re-run refreshes the marketplace first, so it sees
what was pushed. It needs `claude` and `python3` on your `PATH`.

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

## Behaviour-changing plugins

`caveman`, `ponytail` and `superpowers` register SessionStart hooks that change how
Claude works in every session: terse prose, simplest-possible code, and checking for
a matching skill before acting. caveman and ponytail run their hooks with Node;
without `node` on your `PATH` their modes do not load. Disable one with `/plugin` if
you want the default behaviour back. `godot-prompter` has a SessionStart hook too,
but it acts only inside a Godot project.

`designlang` is different: its slash commands run `npx designlang`, which downloads
the latest npm package when you call one. The marketplace pin fixes the commands, not
that package. It needs Node and runs only when you invoke a command.

## ccusage

ccusage reports Claude Code token use and cost from the session logs already on your
machine. It publishes no Claude Code plugin of its own, so the `ccusage` plugin here is
a small skill of mine that teaches Claude its commands (`daily`, `monthly`, `session`,
`blocks`, `statusline`). Like `designlang`, it runs `npx ccusage@latest`, which
downloads the latest npm package when used; nothing is installed or pinned. It needs
Node. The status line is not switched on for you: the skill gives the `settings.json`
snippet and asks before editing.

## rtk

rtk shrinks command output before it reaches the context window. The `rtk` plugin
adds a PreToolUse hook that rewrites Bash commands through `rtk rewrite`, plus a
small skill. The plugin does not install the binary; get it with
`brew install rtk-ai/tap/rtk` (the hook also needs `jq`). Without them the hook
leaves commands unchanged. Do not also run `rtk init -g`, or the hook runs twice.

## domain-scout

Finds, shortlists and wires up a domain name. With the Namecheap MCP connected it
checks availability in one batch, prefers a purchase link over registering for you,
and reads existing DNS records before saving new ones. Without it, the skill says so
and falls back to manual mode: `whois` and `dig` for a "likely available" answer,
registrar links, and DNS records printed as a table to paste. The plugin does not
install or bundle the MCP; connect Namecheap yourself (a claude.ai connector, or your
own MCP config) and start a new session. Registering a domain, saving DNS records,
changing nameservers and saving contacts always wait for a yes.

## Terminal UI mods

Four small mods for Claude Code's mod system. They load like any plugin, and run on
a build that supports mods; elsewhere `/plugin` shows them but they do nothing.

| Mod | What it does |
|---|---|
| `status-bar` | One status line entry after each turn: session cost, git branch, model, context use (`$0.42 · main · opus · ctx 31%`) |
| `done-toast` | A toast when a turn that took 30 seconds or more ends, or a subagent finishes |
| `session-recap` | `/recap` prints the files changed, shell commands run, cost, context use and open TODOs |
| `sidecar` | A pane beside the chat: jaffskils logo, session cost and context, subagents, skills loaded and used, MCP servers, tool activity, files and todos. It docks by itself when the terminal is about 144 columns wide; `/sidecar` opens or closes it at any width |

Each has a `register.test.ts` (`.tsx` for `sidecar`); run one with `claude plugin test plugins/<name>`.

## jaffskils-sync

Installs plugins that were added to this marketplace after a machine was set up, so
`setup.sh` is a one-time step. A SessionStart hook, at most once an hour:

1. refreshes the marketplace (`claude plugin marketplace update jaffskils`);
2. installs every plugin that is new since its last run;
3. shows `jaffskils: installed <names>. Run /reload-plugins to load them.`

Its first run only records what the marketplace lists and installs nothing, so a
plugin you skipped with `--pick`, `--only` or `--preset`, or uninstalled later, stays
gone. It never uninstalls, disables or enables anything. If the refresh fails or takes
over 20 seconds (offline, a captive portal), it stays quiet and tries again an hour
later; a failed install is named in the message and retried.

State lives in the plugin's data folder (or `~/.claude/jaffskils-sync/` when Claude
Code does not provide one): `seen.json` holds the names already handled. To stop it,
disable `jaffskils-sync` with `/plugin`.

Limits: a machine set up before `jaffskils-sync` existed needs one more `setup.sh` run
to get it. A machine set up from a preset also receives later plugins outside that
preset. Needs `claude` and `python3`.

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
2. **The plugin is referenced, not copied.** Each upstream entry points at its repo
   and is pinned to a commit with `sha`. Every Monday the `update-pins` job moves
   each pin to its repo's latest commit, runs the full test suite, and commits to
   `main` only if it passes. The tests check that each plugin installs, not what its
   new code does, so upstream changes reach you unread. To move pins by hand, run
   `scripts/update-pins.sh`, read the diff and commit.
3. **The version string changes.** Most upstream plugins set a `version` in their
   `plugin.json`, so a pin bump only reaches you when that version moves; until
   then you keep the old copy. A plugin with no `version` (`taste-skill`, and every
   plugin of mine) is versioned by commit, so every pin bump or push reaches you.

All of this covers plugins you already have. Auto-update and `scripts/update.sh` never
install a plugin newly added to `marketplace.json`; [jaffskils-sync](#jaffskils-sync)
does, at a session start within the hour. Without it, re-run `setup.sh` or run
`/plugin install <name>@jaffskils` on each machine.

## Maintenance scripts

| Script | Use |
|---|---|
| `scripts/update.sh [--all \| --list]` | Refresh the marketplace, show installed plugins, update the ones you pick (or all) |
| `scripts/doctor.sh` | Check tools (`claude`, `python3`, `uvx`, `rtk`...), plugin sync, MCP server health and the Blender port; changes nothing |
| `scripts/update-pins.sh` | Move every upstream pin to its repo's HEAD |
| `scripts/pin-drift.sh` | Markdown table of how many commits each pin is behind; changes nothing |
| `scripts/pin-changelog.sh` | After `update-pins.sh`: the upstream commits behind each pin that moved |
| `scripts/marketplace-lint.sh [--remote]` | Fail on duplicate names, missing local plugin folders, bad `sha` values, unlisted `plugins/` folders; `--remote` also asks GitHub whether each sha exists |

CI runs the lint on every push. The weekly `update-pins` job puts the changelog in
its commit message and job summary; if the tests fail it commits nothing and the
run shows as failed. The `pin-drift` workflow writes the drift table to the job
summary every Monday, and comments it on any pull request that touches
`marketplace.json`.

`./setup.sh --check` is the multi-machine check: run it on any machine to see whether
it has every plugin the marketplace offers. Run
`claude plugin marketplace update jaffskils` first to compare against what is pushed,
and re-run `setup.sh` to install any plugin it reports missing.

## Add my own skill

1. Create `plugins/<name>/.claude-plugin/plugin.json` and
   `plugins/<name>/skills/<skill>/SKILL.md`.
2. Add an entry to `.claude-plugin/marketplace.json` with
   `"source": "./plugins/<name>"` and no `version`.
3. Push. `jaffskils-sync` installs it on each machine at a session start within the
   hour, and with auto-update on, every later push to it reaches my machines.

Check the manifest with `claude plugin validate .`. A "no version specified"
warning is expected for plugins without a `version`.

## Tests

`tests/test-setup.sh` runs `setup.sh` against throwaway config directories, so your
real `~/.claude` is never touched. Most cases use a small local marketplace; one
installs every plugin in the real manifest, so the suite needs network access.
`tests/test-sync.sh` does the same for the `jaffskils-sync` hook, offline.
`tests/test-lint.sh` checks, offline and on a copy of the repo, that
`scripts/marketplace-lint.sh` reports each kind of broken manifest. GitHub Actions
runs all three, plus `claude plugin validate .` and `scripts/marketplace-lint.sh
--remote`, on every push to `main` and every pull request; the weekly `update-pins`
job runs the same checks before it commits new pins:

```bash
tests/test-setup.sh
tests/test-sync.sh
tests/test-lint.sh
```

CI also runs every UI mod's tests with `claude plugin test`.
