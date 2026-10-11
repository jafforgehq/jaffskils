import { expect, test } from 'claude-code/testing'

test('shows cost, branch, model and context after a turn', async ($, on) => {
  const lines: (string | undefined)[] = []
  on('session.usage', () => ({
    value: { startedAt: 0, context: { window: 200000, percent: 31 }, rateLimits: [], cost: { usd: 0.4234 } },
  }) as never)
  on('process.run', () => ({ value: { exitCode: 0, stdout: 'main\n', stderr: '' } }) as never)
  on('ui.status', (_$, e) => {
    lines.push(e.text)
    return { value: undefined } as never
  })
  on('turn.complete', (_$, e) => ({ text: e.answer }))

  await $.turn.complete({
    answer: 'ok',
    durationMs: 1000,
    isAborted: false,
    turnId: 't1',
    reason: 'answer',
    usage: { model: 'claude-opus-5-5' } as never,
  })

  expect(lines.at(-1)).toBe('$0.42 · main · opus · ctx 31%')
})
