---
name: app-store-compliance
description: Use before submitting an iOS or Android app, or after an App Store or Google Play rejection. Runs the app-store-compliance guard on the project and points to the checklist and appeal playbook. Does not install a hook.
---

# App Store compliance scan

The scanner and the rejection reference come from
[mjmirza/app-store-compliance](https://github.com/mjmirza/app-store-compliance)
(licence: OpenRoots ORA 2.3, free for individuals and for companies under USD 20M
revenue; it does not grant AI-training use). This plugin ships none of its files.
It tells Claude how to fetch a pinned copy and run it.

## Get the pinned copy

The reviewed commit is `d2156bab9d7189835631c0a99adcc2479d32138d` (2026-11-15). Use it
unless the user asks for a newer one.

```bash
DIR="$HOME/.cache/app-store-compliance"
[ -d "$DIR/.git" ] || git clone https://github.com/mjmirza/app-store-compliance "$DIR"
git -C "$DIR" fetch origin d2156bab9d7189835631c0a99adcc2479d32138d
git -C "$DIR" checkout --detach d2156bab9d7189835631c0a99adcc2479d32138d
```

## Scan a project

```bash
bash "$HOME/.cache/app-store-compliance/agent-os/hooks/app-store-compliance-guard.sh" "/path/to/app"
```

The path is the folder holding the Xcode project, the Android app, or the Expo or
Flutter project. Findings are ranked, critical first, each with a file and line and a
`fix.` line. The last line says where the project stands:

| Exit | Last line | Meaning |
|---|---|---|
| 2 | `BLOCKED.` | At least one critical rejection risk. Fix it and run again. |
| 0 | `CLEAR.` | No critical risk in the code. Not proof of approval. |
| 1 | `NOT CHECKED.` or an error | No iOS or Android project found, or the path was wrong. A path that was not read is never a pass. |

The scan only reads the project. In the version reviewed it makes no network calls
and writes only temporary files.

## What the scan cannot see

Several findings are heuristics, for example the Ionic thin-wrapper check. Treat each as
a prompt to look, not a verdict. The scan cannot see the developer account, agreements,
the listing text, the demo account, whether the production backend is up during review,
or whether the privacy labels match runtime behaviour. For those, walk
`docs/PRE-SUBMISSION-CHECKLIST.md` in the clone with the user. After a rejection, use
`docs/MISTAKE-PATTERNS.md` (the appeal playbook) and `data/rejection-patterns.json`.

## Not part of the default flow

- **The upstream hook.** `scripts/install.sh` in the clone adds a PreToolUse hook to
  `~/.claude/settings.json` that blocks submit commands while a critical finding stands.
  Its command list is wide: it also matches `flutter build`, `cap sync`, `expo prebuild`,
  `xcodebuild ... archive` and `gradle assembleRelease`, so it can stop an ordinary local
  build. Setting `APP_STORE_GUARD_OK=1` overrides it. Do not run the installer unless the
  user asks, and say that it edits `settings.json` (a backup is written).
- **The monitor and metadata scripts** (`scripts/monitor*.py`, `scripts/metadata-audit.py`)
  fetch Apple, Google and EU pages. Run them only when the user asks.
