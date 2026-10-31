import { expect, mock, test } from 'claude-code/testing'

const PANE_PROPS = {
  plugin: 'sidecar',
  component: 'Pane',
  requestId: 'sidecar',
  props: {
    title: 'sidecar',
    isFocused: false,
    bodyColumns: 40,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

function pane(columns = 40, rows = 40, surface = 'terminal') {
  return {
    ...PANE_PROPS,
    surface,
    props: { ...PANE_PROPS.props, bodyColumns: columns, scroll: { offset: 0, bodyRows: rows } },
  } as never
}

type Mocks = {
  usage: () => unknown
  agentList: () => unknown[]
  files: Record<string, string>
  panes: { id: string; title: string }[]
  env: Record<string, string | undefined>
}

// Stands in for the engine: answers every `$` call the mod makes and records
// the ones a test asserts on.
function engine(on: any, over: Partial<Mocks> = {}) {
  const m: Mocks = {
    usage: () => ({ startedAt: 0, context: { window: 200000 }, rateLimits: [] }),
    agentList: () => [],
    files: {},
    panes: [],
    env: { HOME: '/home/u' },
    ...over,
  }
  const rec = { opened: [] as string[], closed: [] as string[], commands: [] as string[], viewed: [] as unknown[] }
  const clock = mock.clock(on)
  on('ui.open', (_: unknown, e: any) => {
    rec.opened.push(e.id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', (_: unknown, e: any) => {
    rec.closed.push(e.id)
    return { value: undefined }
  })
  on('ui.panes', () => ({ value: m.panes }))
  on('command.register', (_: unknown, e: any) => {
    rec.commands.push(e.name)
    return { value: { command: e.name } }
  })
  on('session.start', (_: unknown, e: any) => ({ cwd: e.cwd }))
  on('session.usage', () => ({ value: m.usage() }))
  on('session.root', () => ({ value: '/proj' }))
  on('agent.list', () => ({ value: m.agentList() }))
  on('env.get', (_: unknown, e: any) => ({ value: m.env[e.name] }))
  on('fs.read', (_: unknown, e: any) => {
    if (e.path in m.files) return { value: m.files[e.path] }
    throw new Error(`ENOENT: ${e.path}`)
  })
  return { rec, clock, m }
}

const start = ($: any) => $.session.start({ cwd: '/proj', surface: 'terminal', isInteractive: true })

test('session.start opens the pane and registers /sidecar', async ($, on) => {
  const { rec } = engine(on)

  await start($)

  expect(rec.opened).toEqual(['sidecar'])
  expect(rec.commands).toContain('sidecar')
})

test('/sidecar closes an open pane and opens a closed one', async ($, on) => {
  const { rec, m } = engine(on, { panes: [{ id: 'sidecar', title: 'sidecar' }] })

  await $.command.run({ command: 'sidecar', args: '' } as never)
  expect(rec.closed).toEqual(['sidecar'])

  m.panes = []
  await $.command.run({ command: 'sidecar', args: '' } as never)
  expect(rec.opened).toEqual(['sidecar'])
})

test('logo is two rows at 40 columns and one line below 32', async ($, on) => {
  engine(on)

  const wide = await $.ui.mount(pane(40))
  expect(await wide.find({ type: 'Text', text: /▄█ █▀█/ })).toBeDefined()
  await wide.unmount()

  const narrow = await $.ui.mount(pane(31))
  expect(await narrow.find({ type: 'Text', text: '◆ jaffskils' })).toBeDefined()
  expect(await narrow.find({ type: 'Text', text: /▄█/ })).toBeUndefined()
  await narrow.unmount()
})
