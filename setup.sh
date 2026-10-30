#!/usr/bin/env bash
# jaffskils setup: add the jaffskils marketplace, install every plugin in it, turn
# on auto-update for it, and make it the only source of skills (exclusive mode).
#
#   git clone https://github.com/jafforgehq/jaffskils && ./jaffskils/setup.sh
#   curl -fsSL https://raw.githubusercontent.com/jafforgehq/jaffskils/main/setup.sh | bash
#
# Exclusive mode uninstalls plugins and removes marketplaces that are not
# jaffskils, disables plugins synced from claude.ai, and MOVES standalone skills
# from <config>/skills to <config>/skills-removed-<date> (never deletes them).
# It lists everything first and asks for confirmation.
#
# Flags: --dry-run       show what exclusive mode would change; change nothing
#        --yes           skip the confirmation prompt
#        --no-clean      install only; leave other skills alone
#        --no-auto-update  do not touch the auto-update setting
#        --list          show available vs installed plugins; change nothing
#        --check         like --list, and exit 1 if this machine is out of sync
#        --pick          choose plugins interactively (numbers or a preset name)
#        --preset NAME   install a preset from presets.json (minimal, gamedev, ...)
#        --only a,b,c    install only these plugins
#        Without --pick/--preset/--only every plugin is installed.
#
# Environment: JAFFSKILS_SOURCE (marketplace source, default jafforgehq/jaffskils),
#              CLAUDE_CONFIG_DIR (default ~/.claude),
#              JAFFSKILS_TTY (where prompts are read from, default /dev/tty).
set -euo pipefail

MARKETPLACE=jaffskils
SOURCE=${JAFFSKILS_SOURCE:-jafforgehq/jaffskils}
AUTO_UPDATE=1
CLEAN=1
DRY_RUN=0
ASSUME_YES=0
LIST=0
CHECK=0
PICK=0
PRESET=
ONLY=

die() { echo "setup.sh: $*" >&2; exit 1; }

usage() { echo "Usage: setup.sh [--pick | --preset NAME | --only a,b] [--no-auto-update] [--no-clean] [--dry-run] [--yes] | --list | --check" >&2; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "'$1' not found on PATH"; }

# Every claude call gets stdin from /dev/null: when this script is piped into
# bash, a command that reads stdin would otherwise swallow the rest of it.
marketplace_listed() {
  claude plugin marketplace list --json </dev/null |
    python3 -I -c '
import json, sys
sys.exit(0 if any(m.get("name") == sys.argv[1] for m in json.load(sys.stdin)) else 1)
' "$MARKETPLACE"
}

marketplace_dir() {
  claude plugin marketplace list --json </dev/null |
    python3 -I -c '
import json, sys
for m in json.load(sys.stdin):
    if m.get("name") == sys.argv[1]:
        print(m["installLocation"])
        sys.exit(0)
sys.exit(1)
' "$MARKETPLACE"
}

settings_path() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"; }

# Die unless the settings file is absent or holds a JSON object. Runs before
# anything else so a broken file is never touched, by us or by the claude CLI.
check_settings() {
  [[ -e $1 ]] || return 0
  python3 -I -c '
import json, sys
if not isinstance(json.load(open(sys.argv[1], encoding="utf-8")), dict):
    raise ValueError("not a JSON object")
' "$1" 2>/dev/null ||
    die "$1 is not a valid JSON settings file; fix or move it, then re-run (nothing was changed)"
}

# Keep the original once: later runs must not overwrite it with edited copies.
backup_settings() {
  [[ -f $1 && ! -e $1.jaffskils.bak ]] || return 0
  cp -p "$1" "$1.jaffskils.bak"
}

# The claude CLI has no auto-update command; the setting lives on the
# marketplace's extraKnownMarketplaces entry. Writes only if something changes.
enable_auto_update() {
  python3 -I -c '
import json, os, sys, tempfile
path, name, source = sys.argv[1:4]
try:
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
markets = data.setdefault("extraKnownMarketplaces", {})
if not isinstance(markets, dict):
    sys.exit(path + ": extraKnownMarketplaces is not an object")
entry = markets.setdefault(name, {})
before = json.dumps(data, sort_keys=True)
if "source" not in entry:
    entry["source"] = (
        {"source": "directory", "path": os.path.abspath(source)}
        if os.path.isdir(source)
        else {"source": "github", "repo": source}
    )
entry["autoUpdate"] = True
if json.dumps(data, sort_keys=True) == before and os.path.exists(path):
    sys.exit(0)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", prefix=".settings.", suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
if os.path.exists(path):
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
os.replace(tmp, path)
' "$1" "$MARKETPLACE" "$SOURCE" || die "could not enable auto-update in $1"
}

# --- exclusive mode: only jaffskils skills stay ---------------------------------
# The list functions print one item per line and never change anything.

skills_dir() { echo "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills"; }

# User-scope plugins that do not come from jaffskils.
other_plugins() {
  claude plugin list --json </dev/null |
    python3 -I -c '
import json, sys
for p in json.load(sys.stdin):
    if p.get("scope") == "user" and p["id"].rpartition("@")[2] != sys.argv[1]:
        print(p["id"])
' "$MARKETPLACE"
}

# Enabled plugins synced from claude.ai; they can be disabled, not uninstalled.
synced_plugins() {
  claude plugin list --json </dev/null |
    python3 -I -c '
import json, sys
for p in json.load(sys.stdin):
    if p.get("scope") == "synced" and p.get("enabled"):
        print(p["id"])
'
}

other_marketplaces() {
  claude plugin marketplace list --json </dev/null |
    python3 -I -c '
import json, sys
for m in json.load(sys.stdin):
    if m.get("name") != sys.argv[1]:
        print(m["name"])
' "$MARKETPLACE"
}

# Non-hidden directories in skills/ (loose files such as .DS_Store are ignored);
# the app-managed "synced" folder is never a candidate.
standalone_skills() {
  local dir entry
  dir=$(skills_dir)
  [[ -d $dir ]] || return 0
  for entry in "$dir"/*; do
    [[ -d $entry ]] || continue
    [[ ${entry##*/} != synced ]] || continue
    echo "${entry##*/}"
  done
}

# print_items LABEL ITEMS
print_items() {
  local item
  [[ -n $2 ]] || return 0
  echo "  $1" >&2
  while IFS= read -r item; do
    echo "    - $item" >&2
  done <<<"$2"
}

# print_plan PLUGINS MARKETPLACES SKILLS SYNCED
print_plan() {
  echo "Exclusive mode: only '$MARKETPLACE' skills stay. This will change:" >&2
  print_items "Uninstall plugins:" "$1"
  print_items "Remove marketplaces (this also uninstalls their plugins):" "$2"
  print_items "Move standalone skills to a backup folder inside $(dirname "$(skills_dir)"):" "$3"
  print_items "Disable plugins synced from claude.ai:" "$4"
}

# Reads the answer from ${JAFFSKILS_TTY:-/dev/tty} so it also works when the
# script itself arrives on stdin. No readable terminal counts as "no".
confirm_cleanup() {
  local answer=""
  printf 'Proceed? [y/N] ' >&2
  read -r answer 2>/dev/null <"${JAFFSKILS_TTY:-/dev/tty}" || return 1
  [[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

# skills-removed-<date>, with -2, -3... if it already exists: never overwrite.
next_backup_dir() {
  local base candidate n=1
  base="$(dirname "$(skills_dir)")/skills-removed-$(date +%F)"
  candidate=$base
  while [[ -e $candidate ]]; do
    n=$((n + 1))
    candidate="$base-$n"
  done
  echo "$candidate"
}

# run_cleanup PLUGINS MARKETPLACES SKILLS SYNCED. Skills are moved, never deleted.
run_cleanup() {
  local item backup=""
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    claude plugin uninstall "$item" --scope user </dev/null ||
      { echo "setup.sh: could not uninstall $item" >&2; return 1; }
    echo "Removed: plugin $item" >&2
  done <<<"$1"
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    claude plugin marketplace remove "$item" </dev/null ||
      { echo "setup.sh: could not remove marketplace $item" >&2; return 1; }
    echo "Removed: marketplace $item" >&2
  done <<<"$2"
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    claude plugin disable "$item" </dev/null ||
      { echo "setup.sh: could not disable $item" >&2; return 1; }
    echo "Disabled: $item" >&2
  done <<<"$4"
  while IFS= read -r item; do
    [[ -n $item ]] || continue
    if [[ -z $backup ]]; then
      backup=$(next_backup_dir)
      mkdir -- "$backup" || { echo "setup.sh: could not create $backup" >&2; return 1; }
    fi
    mv -- "$(skills_dir)/$item" "$backup/" ||
      { echo "setup.sh: could not move skill $item" >&2; return 1; }
    echo "Moved: skill $item" >&2
  done <<<"$3"
  if [[ -n $backup ]]; then
    printf 'Skills were moved to %s\nTo delete them for good: rm -rf %q\n' "$backup" "$backup" >&2
  fi
}

plugin_names() {
  python3 -I -c '
import json, sys
for p in json.load(open(sys.argv[1] + "/.claude-plugin/marketplace.json"))["plugins"]:
    print(p["name"])
' "$1"
}

# select_plugins DIR NAMES: print the names to install, one per line. Applies
# --only / --preset / --pick; with none of them it prints NAMES unchanged.
select_plugins() {
  local dir=$1 names=$2 answer=""
  if [[ -n $ONLY ]]; then
    python3 -I -c '
import sys
names = sys.argv[1].split()
want = [w for w in sys.argv[2].split(",") if w]
bad = [w for w in want if w not in names]
if bad or not want:
    sys.exit("unknown plugin(s): " + ", ".join(bad or ["(none given)"]))
print("\n".join(want))
' "$names" "$ONLY"
    return
  fi
  if [[ -n $PRESET ]]; then
    preset_names "$dir" "$PRESET" "$names"
    return
  fi
  if [[ $PICK -eq 1 ]]; then
    local i=0 n
    {
      echo "Plugins in $MARKETPLACE:"
      while IFS= read -r n; do
        i=$((i + 1))
        printf '  %2d) %s\n' "$i" "$n"
      done <<<"$names"
      echo "Presets: $(preset_list "$dir")"
      printf 'Numbers (e.g. 1 3 5), a preset name, or Enter for all: '
    } >&2
    read -r answer 2>/dev/null <"${JAFFSKILS_TTY:-/dev/tty}" || die "no terminal to read the choice from; use --preset or --only"
    if [[ -z $answer ]]; then echo "$names"; return; fi
    if [[ $answer =~ ^[0-9\ ,]+$ ]]; then
      python3 -I -c '
import sys, re
names = sys.argv[1].split()
idx = [int(x) for x in re.split(r"[ ,]+", sys.argv[2].strip()) if x]
if not idx or any(i < 1 or i > len(names) for i in idx):
    sys.exit("choice out of range 1-%d" % len(names))
print("\n".join(dict.fromkeys(names[i - 1] for i in idx)))
' "$names" "$answer"
      return
    fi
    preset_names "$dir" "$answer" "$names"
    return
  fi
  echo "$names"
}

preset_list() {
  python3 -I -c '
import json, os, sys
f = sys.argv[1] + "/presets.json"
print(", ".join(["all"] + (list(json.load(open(f))) if os.path.exists(f) else [])))
' "$1"
}

# preset_names DIR PRESET NAMES: members of the preset that the marketplace has.
preset_names() {
  python3 -I -c '
import json, os, sys
d, preset, names = sys.argv[1], sys.argv[2], sys.argv[3].split()
if preset == "all":
    print("\n".join(names)); sys.exit(0)
f = d + "/presets.json"
presets = json.load(open(f)) if os.path.exists(f) else {}
if preset not in presets:
    sys.exit("unknown preset '"'"'%s'"'"'; have: all, %s" % (preset, ", ".join(presets)))
print("\n".join(n for n in presets[preset] if n in names))
' "$1" "$2" "$3"
}

# Compare what the marketplace offers with what is installed. Prints one row per
# plugin and a verdict; returns 1 if anything is missing, disabled or stale.
# Reads the local marketplace clone, so run `claude plugin marketplace update
# jaffskils` first to compare against the latest pushed manifest.
list_plugins() {
  local dir
  dir=$(marketplace_dir) || die "marketplace '$MARKETPLACE' is not added; run setup.sh first"
  claude plugin list --json </dev/null |
    python3 -I -c '
import json, sys
market, manifest = sys.argv[1], sys.argv[2]
available = [p["name"] for p in json.load(open(manifest + "/.claude-plugin/marketplace.json"))["plugins"]]
installed = {}
for p in json.load(sys.stdin):
    name, _, source = p["id"].rpartition("@")
    if source == market:
        installed[name] = p
rows, bad = [], 0
for name in available:
    p = installed.get(name)
    if p is None:
        rows.append((name, "-", "MISSING: not installed")); bad += 1
    elif not p.get("enabled"):
        rows.append((name, p["version"], "DISABLED")); bad += 1
    else:
        rows.append((name, p["version"], "ok"))
for name, p in installed.items():
    if name not in available:
        rows.append((name, p["version"], "EXTRA: installed but no longer in the marketplace")); bad += 1
width = max(len(r[0]) for r in rows)
for name, version, status in rows:
    print(f"{name:<{width}}  {version:<14} {status}")
print()
print("in sync" if bad == 0 else f"{bad} plugin(s) out of sync; run setup.sh to fix")
sys.exit(1 if bad else 0)
' "$MARKETPLACE" "$dir"
}

main() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --no-auto-update) AUTO_UPDATE=0 ;;
      --no-clean) CLEAN=0 ;;
      --dry-run) DRY_RUN=1 ;;
      --yes) ASSUME_YES=1 ;;
      --list) LIST=1 ;;
      --check) LIST=1; CHECK=1 ;;
      --pick) PICK=1 ;;
      --preset) [[ $# -ge 2 ]] || { usage; exit 2; }; PRESET=$2; shift ;;
      --only) [[ $# -ge 2 ]] || { usage; exit 2; }; ONLY=$2; shift ;;
      *) usage; exit 2 ;;
    esac
    shift
  done
  local chosen=$PICK
  [[ -z $PRESET ]] || chosen=$((chosen + 1))
  [[ -z $ONLY ]] || chosen=$((chosen + 1))
  if [[ $chosen -gt 1 ]]; then
    echo "setup.sh: use only one of --pick, --preset, --only" >&2
    usage
    exit 2
  fi
  if [[ $DRY_RUN -eq 1 && $CLEAN -eq 0 ]]; then
    echo "setup.sh: --dry-run and --no-clean cannot be combined" >&2
    usage
    exit 2
  fi

  require_cmd claude
  require_cmd python3

  if [[ $LIST -eq 1 ]]; then
    local status=0
    list_plugins || status=$?
    [[ $CHECK -eq 1 ]] && exit "$status"
    exit 0
  fi

  local settings plugins="" markets="" skills="" synced="" has_cleanup=0
  settings=$(settings_path)
  if [[ $AUTO_UPDATE -eq 1 ]]; then
    check_settings "$settings"
  fi

  # Decide everything read-only first: a refusal or a dry run changes nothing.
  if [[ $CLEAN -eq 1 ]]; then
    plugins=$(other_plugins) || die "could not list installed plugins"
    markets=$(other_marketplaces) || die "could not list marketplaces"
    synced=$(synced_plugins) || die "could not list synced plugins"
    skills=$(standalone_skills)
    if [[ -z "$plugins$markets$skills$synced" ]]; then
      echo "Nothing to clean up." >&2
    else
      has_cleanup=1
      print_plan "$plugins" "$markets" "$skills" "$synced"
      if [[ $DRY_RUN -eq 0 && $ASSUME_YES -eq 0 ]]; then
        confirm_cleanup ||
          die "cleanup was not confirmed; nothing was changed. Use --yes to skip the prompt, or --no-clean to keep other skills."
      fi
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "Dry run: nothing was changed." >&2
      exit 0
    fi
  fi

  if [[ $AUTO_UPDATE -eq 1 ]]; then
    backup_settings "$settings"
  fi

  if marketplace_listed; then
    echo "Marketplace '$MARKETPLACE' is already added." >&2
    claude plugin marketplace update "$MARKETPLACE" </dev/null >&2 || die "could not refresh marketplace '$MARKETPLACE'"
  else
    claude plugin marketplace add "$SOURCE" </dev/null || die "could not add marketplace '$SOURCE'"
  fi

  local dir names name
  dir=$(marketplace_dir) || die "marketplace '$MARKETPLACE' not found after adding it"
  names=$(plugin_names "$dir") || die "could not read the plugin list in $dir"
  names=$(select_plugins "$dir" "$names") || die "could not choose plugins"
  [[ -n $names ]] || die "no plugins selected"

  while IFS= read -r name; do
    [[ -n $name ]] || continue
    claude plugin install "$name@$MARKETPLACE" --scope user </dev/null ||
      die "could not install $name@$MARKETPLACE"
  done <<<"$names"

  # Cleanup runs after the install succeeds, and before enable_auto_update so no
  # later CLI write can disturb the autoUpdate flag.
  if [[ $has_cleanup -eq 1 ]]; then
    local hint="Fix the cause above and re-run setup.sh; it is safe to re-run."
    [[ $AUTO_UPDATE -eq 0 ]] || hint="Auto-update has NOT been enabled yet. $hint"
    run_cleanup "$plugins" "$markets" "$skills" "$synced" || die "cleanup stopped part-way. $hint"
  fi

  if [[ $AUTO_UPDATE -eq 1 ]]; then
    enable_auto_update "$settings"
    echo "Auto-update is on for '$MARKETPLACE'." >&2
  fi

  echo "Installed from $MARKETPLACE: $(echo "$names" | tr '\n' ' ')" >&2
  if ! command -v rtk >/dev/null 2>&1; then
    echo "Note: the rtk plugin needs the rtk binary and does nothing without it." >&2
    echo "Install it with: brew install rtk-ai/tap/rtk" >&2
  fi
  echo "Run /reload-plugins in Claude Code, or restart it, to load them." >&2
}

# Everything is defined above; running main last means a truncated download
# of this script cannot execute half of it.
main "$@"
