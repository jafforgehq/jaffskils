#!/usr/bin/env bash
# Refresh the jaffskils marketplace, show what is installed vs available, and
# update plugins. Interactive by default; --all updates every jaffskils plugin
# without asking; --list only shows the table. Restart Claude Code (or run
# /reload-plugins) afterwards to load new versions.
set -euo pipefail

MARKETPLACE=jaffskils
ALL=0
LIST=0
usage() { echo "Usage: update.sh [--all | --list]" >&2; }
die() { echo "update.sh: $*" >&2; exit 1; }

for arg in "$@"; do
  case $arg in
    --all) ALL=1 ;;
    --list) LIST=1 ;;
    *) usage; exit 2 ;;
  esac
done
command -v claude >/dev/null || die "'claude' not found on PATH"
command -v python3 >/dev/null || die "'python3' not found on PATH"

claude plugin marketplace update "$MARKETPLACE" </dev/null >&2 || die "could not refresh marketplace '$MARKETPLACE'"

# Rows: name<TAB>installed version<TAB>available (manifest) version or "-".
rows=$(claude plugin list --json </dev/null | python3 -I -c '
import json, sys
for p in json.load(sys.stdin):
    name, _, source = p["id"].rpartition("@")
    if source == sys.argv[1]:
        print(name + "\t" + str(p.get("version", "?")))
' "$MARKETPLACE")
[[ -n $rows ]] || die "no $MARKETPLACE plugins installed; run setup.sh first"

echo "Installed from $MARKETPLACE:" >&2
i=0
while IFS=$'\t' read -r name version; do
  i=$((i + 1))
  printf '  %2d) %-18s %s\n' "$i" "$name" "$version" >&2
done <<<"$rows"
[[ $LIST -eq 0 ]] || exit 0

names=$(cut -f1 <<<"$rows")
if [[ $ALL -eq 1 ]]; then
  chosen=$names
else
  printf 'Update which? numbers (e.g. 1 3), "all", or Enter to skip: ' >&2
  answer=""
  read -r answer 2>/dev/null <"${JAFFSKILS_TTY:-/dev/tty}" || die "no terminal to read from; use --all"
  case $answer in
    "") echo "Nothing updated." >&2; exit 0 ;;
    all) chosen=$names ;;
    *)
      chosen=$(python3 -I -c '
import re, sys
names = sys.argv[1].split()
idx = [int(x) for x in re.split(r"[ ,]+", sys.argv[2].strip()) if x.isdigit()]
if not idx or any(i < 1 or i > len(names) for i in idx):
    sys.exit("choice out of range 1-%d" % len(names))
print("\n".join(dict.fromkeys(names[i - 1] for i in idx)))
' "$names" "$answer") || die "bad choice"
      ;;
  esac
fi

failed=0
while IFS= read -r name; do
  [[ -n $name ]] || continue
  if claude plugin update "$name@$MARKETPLACE" </dev/null >&2; then :; else
    echo "update.sh: could not update $name" >&2
    failed=$((failed + 1))
  fi
done <<<"$chosen"
echo "Run /reload-plugins in Claude Code, or restart it, to load new versions." >&2
[[ $failed -eq 0 ]] || exit 1
