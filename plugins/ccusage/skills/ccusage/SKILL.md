---
name: ccusage
description: Use when asked about Claude Code token usage, spend or cost, the 5-hour billing window, or cost per project or session, or to put usage in the status line. Explains how to run ccusage and read its output.
---

# ccusage

ccusage reads the local session logs that Claude Code (and other coding agents)
already write and reports token use and cost from them. It makes no API calls to
Anthropic. Run it with `npx ccusage@latest` (or `bunx ccusage`, or plain `ccusage`
when it is installed). It needs Node, and the first run downloads the package.

## Reports

| Command | Shows |
|---|---|
| `ccusage daily` | Usage by day, all detected agents |
| `ccusage weekly` / `monthly` | Same, by week or month |
| `ccusage session` | Usage per conversation |
| `ccusage blocks` | Claude Code 5-hour billing windows, including the active one |
| `ccusage claude daily` | Claude Code only (also `codex`, `opencode`, `gemini` and others) |

Useful flags:

- `--json` for output you can parse. Prefer it whenever you will read the numbers
  yourself; the table layout changes with terminal width.
- `--since 2026-10-01 --until 2026-10-10` for a date range, or `--last 1` for today,
  this week or this month on `daily`, `weekly` and `monthly`.
- `--breakdown` for per-model cost.
- `--instances` to group Claude Code by project, with `--project <name>` to filter.
- `--timezone UTC` to control how days are cut.
- `--offline` to use cached pricing without network.
- `--no-cost` to hide cost columns and JSON cost fields.

## Reading the numbers

Cost is an estimate: ccusage multiplies token counts by public per-model prices. It
is not an invoice, and on a subscription plan it shows what the usage would cost at
API rates, not what you pay. Cache creation and cache read tokens are listed apart
from input and output tokens, so a large cache-read count is normal for long sessions.

## Status line

`ccusage statusline` (beta) prints session cost, today's cost, the active 5-hour
block and burn rate for Claude Code's status line. To enable it, add this to
`~/.claude/settings.json`, replacing any `statusLine` already there:

```json
{
  "statusLine": { "type": "command", "command": "npx -y ccusage statusline", "padding": 0 }
}
```

Ask before editing `settings.json`: it changes the user's status line in every
session.
