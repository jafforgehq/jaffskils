# sidecar: a live session pane with skills, agents and more

Date: 2026-10-31
Status: design approved by user in chat; user waived spec review.

## Purpose

A Claude Code session shows little of what is going on around the conversation:
which skills are loaded and used, which subagents run, which MCP servers failed,
what it costs. `sidecar` is a mod that keeps all of it in one pane docked beside
the chat, with the jaffskils logo, colour and a little motion.

## Decisions

| Topic | Decision |
|---|---|
| Form | One mod, one docked `Pane`, local plugin `plugins/sidecar/`, no `version` |
| Opening | `$.ui.open` at `session.start`; the engine seats an unasked pane only when the terminal is wide enough (about 144 columns) and waits otherwise. `/sidecar` toggles it at any width |
| Sections | SESSION, AGENTS, SKILLS, MCP, TOOLS, FILES/TODOS, in that order, under the logo |
| Skills view | Totals and token cost, skill counts per plugin, then skills used this session |
| Interaction | Display only, except: pressing an agent row opens its transcript (`$.ui.view`) |
| Motion | Logo shimmer, spinners, flash on new items; nothing animates while idle |
| Existing mods | `status-bar`, `done-toast`, `session-recap` stay unchanged; they serve narrow terminals |
| Tracking code | Files, todos and Bash counting are copied from `session-recap`, not shared, so `sidecar` needs no other plugin |
| Rejected: one mod per section | Installable one by one, but several panes compete for one dock |
| Rejected: grow `status-bar` into a pane | One plugin fewer, but `status-bar` is what still works in a narrow terminal |
| Rejected: `claude mcp list` for MCP state | Health-checks by starting every stdio server again (Blender too); slow and has side effects |

## Files

```
plugins/sidecar/
├── .claude-plugin/plugin.json   # name "sidecar", author jafforgehq, "types": "./types/index.d.ts"
├── hooks/
│   ├── hooks.json               # { "modules": ["./register.tsx"] }
│   ├── register.tsx             # hooks: data collection, pane render, /sidecar
│   ├── motion.tsx               # surface module (Client): logo shimmer, spinner, pulse
│   └── register.test.tsx
└── types/index.d.ts             # PluginState contract for sidecar's atoms
```

Also changed: `.claude-plugin/marketplace.json` (entry after `session-recap`),
`presets.json` (`sidecar` in `gamedev`, next to the other mods), `README.md` (intro
names four mods, a `sidecar` row in the Terminal UI mods table, Tests section),
`.github/workflows/ci.yml` (a `Run mod tests` step: `claude plugin test` for every
mod).

## Layout

```
┌────────────────────────────────────┐
│  █ ▄▀█ █▀▀ █▀▀ █▀ █▄▀ █ █   █▀     │
│ ▄█ █▀█ █▀  █▀  ▄█ █ █ █ █▄▄ ▄█  ●  │
│ SESSION  opus · $1.84 · 23 min     │
│ ctx ████████░░░░ 62%               │
│ AGENTS  1 running · 2 done         │
│  ⠹ Explore   find hooks    1m12s   │
│  ✓ general   review diff   done    │
│ SKILLS  220 · 19 plugins · ~9.1k   │
│  godot-prompter 59 · marketing 52  │
│  caveman 28 · superpowers 15 · …   │
│  used ▸ brainstorming      2m ago  │
│       ▸ plugin-authoring   6m ago  │
│ MCP  ✓ 9  ✗ blender  ✗ isoforge    │
│ TOOLS  Bash 41 · Edit 12 · Read 9  │
│  last $ git push -q origin main    │
│ FILES 3 · TODOS 2 open             │
│  ~ update README                   │
└────────────────────────────────────┘
```

The logo, exactly (2 rows, 30 columns):

```
 █ ▄▀█ █▀▀ █▀▀ █▀ █▄▀ █ █   █▀
▄█ █▀█ █▀  █▀  ▄█ █ █ █ █▄▄ ▄█
```

Below 32 body columns (`e.props.bodyColumns`) it becomes one line, `◆ jaffskils`.

Rules:

- Every section keeps its header line. When rows run short, detail lines go first,
  from the bottom section up, then the logo shrinks to its one-line form.
- AGENTS lists running agents, then finished ones for 3 minutes after they end;
  older finished ones only count in `N done`. Agent rows show type, the Agent
  call's `description` truncated, and elapsed time or `done` / `failed`.
- SKILLS lists the top plugins by skill count on as many lines as fit (two by
  default), then `· N more`; `used` lists up to 5 skills, newest first, with a
  relative time.
- TOOLS shows the three most-called tools and the last Bash command, truncated to
  the pane width.
- FILES/TODOS shows the changed-file count, the open-todo count, then up to 3 todos,
  in-progress first.
- The context bar is `bodyColumns - 10` cells wide.

## Look and motion

Colours use theme keys so light and dark themes both read: section headers bold in
`claude`; `✓`, `done` and connected counts in `success`; `✗` and `failed` in
`error`; in-progress todos in `warning`; secondary text `dimColor`. The context bar
is `success` below 50 %, `warning` below 80 %, `error` from 80 %. Only the logo uses
fixed colours: a per-character gradient from `#D97757` (orange) to `#9B7BFF`
(violet).

Animations, all in `motion.tsx` (a `Client` surface module with its own frame clock,
so the hooks module redraws nothing for them):

1. Logo shimmer: a bright band (`#FFF4E6`) sweeps the wordmark left to right over
   about 1.5 s, once when the pane opens and once per finished turn. The hooks module
   bumps a `shimmer` counter prop; the module sweeps when the counter changes.
2. Spinner: braille frames `⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏` at 80 ms beside each running agent, and a
   pulsing `●` beside the logo while a turn runs.
3. Flash: a newly used skill, finished agent or newly changed file draws `bold` for
   2 s after it appears; the hooks module stores `addedAt` and schedules one redraw
   with `$.clock.after(2000, ...)`.

Surfaces without `Client` (VS Code, mobile) draw the same pane with static glyphs:
`●` for spinners, no shimmer.

## Data

| Section | Source | Refreshed |
|---|---|---|
| SESSION | `$.session.usage()` (cost, context %, `startedAt`); model from `turn.complete`'s `usage.model`, shortened as `status-bar` does | `session.start`, `turn.complete`, every 30 s for elapsed minutes |
| Working dot | `turn.start` sets it, `turn.complete` clears it | on those events |
| AGENTS | `$.agent.list()`: `id`, `type`, `description`, `status` | `agent.spawn`, `turn.complete`, and every 1 s while any agent is `pending`, `running` or `waiting` (timer stopped otherwise) |
| SKILLS totals | `$.session.usage({ breakdown: 'summary' })` → `context.breakdown.skills`: `totalSkills`, `tokens`, `skillFrontmatter[].pluginName` | `session.start`, `turn.complete` |
| SKILLS used | `skill.prompt` event (`e.skill`) | on the event |
| MCP connected | distinct `serverName` in `context.breakdown.mcpTools` | with SKILLS totals |
| MCP configured | `~/.claude.json` (or `$CLAUDE_CONFIG_DIR/.claude.json`): top-level `mcpServers`, plus `projects[<root>].mcpServers`; `<root>/.mcp.json` `mcpServers` minus `projects[<root>].disabledMcpjsonServers`; minus `projects[<root>].disabledMcpServers`. `<root>` is `$.session.root()` | `session.start`, `turn.complete` |
| MCP not connected | configured names with no tools in `mcpTools` | derived |
| TOOLS | `tool.call` (all tools): count per `e.tool`; Bash `e.command` as last command | on the event |
| FILES | `tool.call` for `Edit` and `Write`: unique `file_path` | on the event |
| TODOS | `tool.call` for `TodoWrite`: the list | on the event |

State lives in `$.state` atoms declared in `types/index.d.ts`, each with a `shape`
tag, so a reload keeps the values and a later change of fields starts clean. The
render hook only reads; handlers and timers write.

## Error handling

- Each section loads its data in its own `try`; a failure leaves that section's
  header with `—` and the rest of the pane draws.
- A missing or unreadable `.claude.json` or `.mcp.json` means no `✗` list, only the
  connected count.
- A breakdown call that fails hides SKILLS totals and MCP; `used` still shows.
- Timers stop on `session.end`; a reload starts them again from `session.start`.

## Testing

`hooks/register.test.tsx`, run with `claude plugin test plugins/sidecar` (also in CI):

1. `session.start` opens the pane (`ui.open` with id `sidecar`) and registers
   `/sidecar`.
2. A `skill.prompt` event puts the skill at the top of `used`.
3. Three `tool.call` events (Bash, Edit, Bash) give `Bash 2 · Edit 1`, the last
   command, and one changed file.
4. With `mcpTools` naming `godot` and a config naming `godot` and `blender`, MCP
   shows `✓ 1` and `✗ blender`.
5. A `session.usage` that throws leaves SESSION as `—` and the other sections drawn.
6. Below 32 body columns the logo is `◆ jaffskils`.
7. Pressing an agent row calls `ui.view` with that agent's `id`.

`claude plugin validate plugins/sidecar` passes, and `scripts/marketplace-lint.sh`
passes with the new entry.

## Out of scope

Buttons that change anything (enable plugins, kill agents), a per-project skill
picker, sounds, settings for colours or sections.
