import type { EngineInterface, Register } from 'claude-code'

// Shows "$0.42 · main · opus · ctx 31%" in the status line after each turn.
async function refresh($: EngineInterface, model: string) {
  const { context, cost } = await $.session.usage()
  const git = await $.process.run(['git', 'branch', '--show-current'])
  const branch = git.exitCode === 0 ? git.stdout.trim() : ''
  const parts = [
    cost ? `$${cost.usd.toFixed(2)}` : '',
    branch,
    model,
    context.percent === undefined ? '' : `ctx ${context.percent}%`,
  ].filter(Boolean)

  $.ui.status(parts.length > 0 ? parts.join(' · ') : undefined)
}

export const register: Register = on => {
  let model = ''

  on('session.start', async ($, e, next) => {
    await refresh($, model)

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined && e.usage?.model) {
      model = e.usage.model.replace(/^claude-/, '').replace(/-\d.*$/, '')
    }
    await refresh($, model)

    return next(e)
  })
}
