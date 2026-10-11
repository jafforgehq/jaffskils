import { expect, test } from 'claude-code/testing'

const turn = (durationMs: number, agentId?: string) => ({
  answer: 'ok',
  durationMs,
  isAborted: false,
  turnId: 't1',
  reason: 'answer' as const,
  ...(agentId ? { agentId } : {}),
})

test('toasts after a long main turn', async ($, on) => {
  const toasts: string[] = []
  on('turn.complete', ($$, e) => ({ text: e.answer }))
  on('ui.toast', ($$, e) => {
    toasts.push(e.text)
    return { value: undefined } as never
  })

  await $.turn.complete(turn(45_000))

  expect(toasts).toEqual(['Done after 45s.'])
})

test('stays quiet after a short turn', async ($, on) => {
  const toasts: string[] = []
  on('turn.complete', ($$, e) => ({ text: e.answer }))
  on('ui.toast', ($$, e) => {
    toasts.push(e.text)
    return { value: undefined } as never
  })

  await $.turn.complete(turn(2_000))

  expect(toasts).toEqual([])
})

test('toasts when a subagent finishes', async ($, on) => {
  const toasts: string[] = []
  on('turn.complete', ($$, e) => ({ text: e.answer }))
  on('ui.toast', ($$, e) => {
    toasts.push(e.text)
    return { value: undefined } as never
  })

  await $.turn.complete(turn(1_000, 'agent-1'))

  expect(toasts).toEqual(['A subagent finished.'])
})
