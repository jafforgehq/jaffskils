---
name: rtk
description: Use when shell output is large or noisy, or when asked about token savings from rtk. Explains how rtk filters command output and how to see the raw output when the filtered form hides something.
---

# rtk

rtk is a CLI proxy that shrinks command output (git, gh, ls, test runners, and
more) before it reaches the context window. The plugin's hook rewrites Bash
commands to their `rtk` form automatically, so you normally do nothing.

- `rtk gain` shows token savings so far.
- `rtk <command>` runs a command through rtk by hand, for example `rtk git log`.
- `rtk proxy <command>` runs a command unfiltered and still records the usage. Use
  it when rtk's summary leaves out detail you need, such as a full diff or a
  complete stack trace.
- `rtk rewrite "<command>"` prints the rtk form of a command, or exits 1 when it
  has none.

If output looks truncated or a flag seems ignored, re-run with `rtk proxy` before
assuming the command itself is at fault.

The hook does nothing when `rtk` or `jq` is not on `PATH`. Install rtk with
`brew install rtk-ai/tap/rtk`.
