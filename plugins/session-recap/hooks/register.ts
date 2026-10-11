import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Todo } from '../types'

const files = atom({ plugin: 'session-recap', key: 'files' } as const, [])
const commands = atom({ plugin: 'session-recap', key: 'commands' } as const, 0)
const todos = atom({ plugin: 'session-recap', key: 'todos' } as const, [])

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'recap',
      description: 'Recap this session: files changed, cost and open TODOs',
    })

    return next(e)
  })

  for (const tool of ['Edit', 'Write'] as const) {
    on('tool.call', { tool }, async ($, e, next) => {
      await update($, files, list =>
        list.includes(e.file_path) ? list : [...list, e.file_path],
      )

      return next(e)
    })
  }

  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    await update($, commands, n => n + 1)

    return next(e)
  })

  on('tool.call', { tool: 'TodoWrite' }, async ($, e, next) => {
    const list: Todo[] = e.todos.map(t => ({ content: t.content, status: t.status }))
    await update($, todos, () => list)

    return next(e)
  })

  on('command.run', { command: 'recap' }, async $ => {
    const [changed, ran, list, usage] = await Promise.all([
      read($, files),
      read($, commands),
      read($, todos),
      $.session.usage(),
    ])
    const open = list.filter(t => t.status !== 'completed')
    const minutes = Math.max(1, Math.round(((await $.clock.now()) - usage.startedAt) / 60000))
    const lines = [
      `Session recap (${minutes} min)`,
      `Cost: ${usage.cost ? `$${usage.cost.usd.toFixed(2)}` : 'unknown'}`,
      `Context: ${usage.context.percent ?? '?'}% used`,
      `Shell commands run: ${ran}`,
      `Files changed (${changed.length}):`,
      ...(changed.length > 0 ? changed.map(f => `  ${f}`) : ['  none']),
      `Open TODOs (${open.length}):`,
      ...(open.length > 0 ? open.map(t => `  [${t.status === 'in_progress' ? '~' : ' '}] ${t.content}`) : ['  none']),
    ]

    return { text: lines.join('\n') }
  })
}
