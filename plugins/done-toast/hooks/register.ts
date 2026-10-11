import type { Register } from 'claude-code'

const LONG_TURN_MS = 30_000

// Toasts when a turn that took a while ends, or when a subagent finishes, so you
// can look away while it works.
export const register: Register = on => {
  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) {
      $.ui.toast('A subagent finished.')
    } else if (!e.isAborted && e.durationMs >= LONG_TURN_MS) {
      $.ui.toast(`Done after ${Math.round(e.durationMs / 1000)}s.`)
    }

    return next(e)
  })
}
