import { expect, mock, test } from 'claude-code/testing'

test('recap lists changed files, shell runs and open TODOs', async ($, on) => {
  mock.clock(on, { now: 600_000 })
  on('tool.call', () => ({ result: { type: 'update' }, isError: false }) as never)
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 200000, percent: 12 }, rateLimits: [], cost: { usd: 1.5 } },
  }) as never)

  await $.tool.call({ tool: 'Edit', file_path: '/a.ts', old_string: 'x', new_string: 'y' } as never)
  await $.tool.call({ tool: 'Edit', file_path: '/a.ts', old_string: 'y', new_string: 'z' } as never)
  await $.tool.call({ tool: 'Write', file_path: '/b.ts', content: '' } as never)
  await $.tool.call({ tool: 'Bash', command: 'ls' } as never)
  await $.tool.call({
    tool: 'TodoWrite',
    todos: [
      { content: 'ship it', status: 'in_progress', activeForm: 'shipping' },
      { content: 'done thing', status: 'completed', activeForm: 'done' },
    ],
  } as never)

  const out = await $.command.run({ command: 'recap', args: '' } as never)
  const text = JSON.stringify(out)

  expect(text).toContain('Files changed (2)')
  expect(text).toContain('Shell commands run: 1')
  expect(text).toContain('Open TODOs (1)')
  expect(text).toContain('ship it')
  expect(text).not.toContain('done thing')
  expect(text).toContain('$1.50')
})
