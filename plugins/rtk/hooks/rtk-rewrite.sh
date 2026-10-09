#!/usr/bin/env bash
# PreToolUse hook: rewrites a Bash command to its rtk equivalent.
# Adapted from rtk-ai/rtk hooks/claude/rtk-rewrite.sh. All rewrite and permission
# logic lives in `rtk rewrite`; this script only relays it.
#
# `rtk rewrite` exit codes:
#   0 + stdout  rewritten, an allow rule matched   -> rewrite and auto-allow
#   3 + stdout  rewritten, ask rule or no rule     -> rewrite, let Claude Code prompt
#   1, 2, other no rtk equivalent, or deny rule     -> pass through unchanged
#
# Missing rtk or jq is not an error: the command runs unchanged.

command -v jq >/dev/null 2>&1 || exit 0
command -v rtk >/dev/null 2>&1 || exit 0

INPUT=$(cat)
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
[ -n "$CMD" ] || exit 0

# RTK_REWRITE_HOST relaxes rtk's approval gate; an inherited value must not reach it.
REWRITTEN=$(env -u RTK_REWRITE_HOST rtk rewrite "$CMD" 2>/dev/null)
CODE=$?

case $CODE in
  0) [ "$CMD" = "$REWRITTEN" ] && exit 0
     DECISION=allow ;;
  3) DECISION= ;;
  *) exit 0 ;;
esac

jq -c --arg cmd "$REWRITTEN" --arg decision "$DECISION" \
  '.tool_input.command = $cmd | {
    hookSpecificOutput: ({
      hookEventName: "PreToolUse",
      updatedInput: .tool_input
    } + (if $decision == "" then {} else {
      permissionDecision: $decision,
      permissionDecisionReason: "RTK auto-rewrite"
    } end))
  }' <<<"$INPUT"
