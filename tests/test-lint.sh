#!/usr/bin/env bash
# Offline tests for scripts/marketplace-lint.sh: the real manifest passes, and each
# kind of break is reported. Works on a copy of the repo, never the real files.
set -u
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
rc=0

check() { # name expected_exit manifest_edit_python
  local name=$1 want=$2 edit=$3 got=0
  rm -rf "$WORK/repo"; mkdir -p "$WORK/repo"
  cp -R "$REPO_ROOT/.claude-plugin" "$REPO_ROOT/plugins" "$REPO_ROOT/scripts" "$WORK/repo/"
  [[ -z $edit ]] || python3 -I -c "
import json
p='$WORK/repo/.claude-plugin/marketplace.json'
d=json.load(open(p)); $edit
open(p,'w').write(json.dumps(d))"
  (cd "$WORK/repo" && scripts/marketplace-lint.sh >"$WORK/out" 2>&1) || got=$?
  if [[ $got -eq $want ]]; then echo "ok   $name"; else echo "FAIL $name (exit $got, wanted $want)"; cat "$WORK/out"; rc=1; fi
}

check "real manifest passes" 0 ""
check "bad sha" 1 "d['plugins'][0]['source']['sha']='xyz'"
check "missing local dir" 1 "d['plugins'][2]['source']='./plugins/nope'"
check "duplicate name" 1 "d['plugins'].append(dict(d['plugins'][0]))"
check "unlisted plugin folder" 1 "d['plugins']=[p for p in d['plugins'] if p['name']!='ccusage']"
exit $rc
