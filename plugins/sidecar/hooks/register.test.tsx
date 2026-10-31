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
  on('ui.view', (_: unknown, e: any) => {
    rec.viewed.push(e)
    return { value: {} }
  })
  on('agent.spawn', () => ({ model: 'm', agentId: 'a1' }))
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

  const wide = await $.ui.mount(pane(40, 40, 'vscode'))
  expect(await wide.find({ type: 'Text', text: /▄█ █▀█/ })).toBeDefined()
  await wide.unmount()

  const narrow = await $.ui.mount(pane(31))
  expect(await narrow.find({ type: 'Text', text: '◆ jaffskils' })).toBeDefined()
  expect(await narrow.find({ type: 'Text', text: /▄█/ })).toBeUndefined()
  await narrow.unmount()
})

const texts = async (ui: any, text: RegExp) => (await ui.findAll({ type: 'Text', text })).map((t: any) => t.text)

test('a used skill goes to the top of used', async ($, on) => {
  engine(on)
  on('skill.prompt', (_: unknown, e: any) => ({ text: e.text }))

  await $.skill.prompt({ skill: 'brainstorming', text: '' } as never)
  await $.skill.prompt({ skill: 'plugin-authoring', text: '' } as never)

  const ui = await $.ui.mount(pane())
  expect((await texts(ui, /▸/))[0]).toMatch(/plugin-authoring/)
  await ui.unmount()
})

test('a skill used twice shows once', async ($, on) => {
  engine(on)
  on('skill.prompt', (_: unknown, e: any) => ({ text: e.text }))

  for (const skill of ['a-skill', 'b-skill', 'a-skill']) {
    await $.skill.prompt({ skill, text: '' } as never)
  }

  const ui = await $.ui.mount(pane())
  const rows = await texts(ui, /▸/)
  expect(rows.map((t: string) => t.match(/▸ (\S+)/)?.[1])).toEqual(['a-skill', 'b-skill'])
  await ui.unmount()
})

test('tool calls give counts, last command and changed files', async ($, on) => {
  engine(on)
  on('tool.call', () => ({ result: {} }))

  await $.tool.call({ tool: 'Bash', command: 'ls' } as never)
  await $.tool.call({ tool: 'Edit', file_path: '/p/a.ts', old_string: 'a', new_string: 'b' } as never)
  await $.tool.call({ tool: 'Bash', command: 'git status' } as never)

  const ui = await $.ui.mount(pane())
  expect(await ui.find({ type: 'Text', text: /Bash 2 · Edit 1/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /last \$ git status/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /FILES 1/ })).toBeDefined()
  await ui.unmount()
})

test('a multi-line Bash command shows its first line, truncated', async ($, on) => {
  engine(on)
  on('tool.call', () => ({ result: {} }))

  await $.tool.call({ tool: 'Bash', command: `echo ${'x'.repeat(200)}\nrm -rf tmp` } as never)

  const ui = await $.ui.mount(pane())
  const last = (await ui.find({ type: 'Text', text: /last \$/ }))?.text ?? ''
  expect(last.endsWith('…')).toBe(true)
  expect(last.length).toBeLessThanOrEqual(40)
  expect(last.includes('rm -rf')).toBe(false)
  await ui.unmount()
})

test('todos list in-progress first, at most 3', async ($, on) => {
  engine(on)
  on('tool.call', () => ({ result: {} }))

  await $.tool.call({
    tool: 'TodoWrite',
    todos: [
      { content: 'ship it', status: 'completed' },
      { content: 'first pending', status: 'pending' },
      { content: 'second pending', status: 'pending' },
      { content: 'third pending', status: 'pending' },
      { content: 'doing now', status: 'in_progress' },
    ],
  } as never)

  const ui = await $.ui.mount(pane())
  expect(await ui.find({ type: 'Text', text: /TODOS 4 open/ })).toBeDefined()
  const rows = await texts(ui, /^ [~·] \S/)
  expect(rows).toHaveLength(3)
  expect(rows[0]).toMatch(/doing now/)
  await ui.unmount()
})

const usageWith = (context: object, extra: object = {}) => () => ({
  startedAt: 0,
  context: { window: 200000, ...context },
  rateLimits: [],
  ...extra,
})
const skillRow = (pluginName: string) => ({ name: 'x', source: 'plugin', pluginName, tokens: 1 })
const mcpTool = (serverName: string) => ({ name: `mcp__${serverName}__t`, serverName, tokens: 1, isLoaded: true })
const keyText = async (ui: any, key: string) => (await ui.find({ key }))?.text

test('skills totals and per-plugin counts come from the breakdown', async ($, on) => {
  engine(on, {
    usage: usageWith({
      percent: 31,
      breakdown: {
        skills: {
          totalSkills: 3,
          includedSkills: 3,
          tokens: 9100,
          skillFrontmatter: [skillRow('godot-prompter'), skillRow('godot-prompter'), skillRow('caveman')],
        },
        mcpTools: [],
      },
    }),
  })

  await start($)

  const ui = await $.ui.mount(pane())
  expect(await keyText(ui, 'head-skills')).toMatch(/SKILLS\s+3 · 2 plugins · ~9\.1k/)
  expect(await ui.find({ type: 'Text', text: /godot-prompter 2/ })).toBeDefined()
  await ui.unmount()
})

test('MCP shows connected count and configured servers without tools', async ($, on) => {
  engine(on, {
    usage: usageWith({ breakdown: { mcpTools: [mcpTool('godot')] } }),
    files: { '/home/u/.claude.json': JSON.stringify({ mcpServers: { godot: {}, blender: {} } }) },
  })

  await start($)

  const ui = await $.ui.mount(pane())
  expect(await ui.find({ type: 'Text', text: /✓ 1/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /✗ blender/ })).toBeDefined()
  await ui.unmount()
})

test('a server in disabledMcpServers is not listed as missing', async ($, on) => {
  engine(on, {
    usage: usageWith({ breakdown: { mcpTools: [mcpTool('godot')] } }),
    files: {
      '/home/u/.claude.json': JSON.stringify({
        mcpServers: { godot: {}, blender: {} },
        projects: { '/proj': { disabledMcpServers: ['blender'] } },
      }),
    },
  })

  await start($)

  const ui = await $.ui.mount(pane())
  expect(await ui.find({ type: 'Text', text: /✓ 1/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /blender/ })).toBeUndefined()
  await ui.unmount()
})

test('a failing session.usage leaves SESSION as — and other sections drawn', async ($, on) => {
  engine(on, {
    usage: () => {
      throw new Error('usage down')
    },
  })

  await start($)

  const ui = await $.ui.mount(pane())
  expect(await keyText(ui, 'head-session')).toMatch(/^SESSION\s+—$/)
  expect(await ui.find({ key: 'head-tools' })).toBeDefined()
  await ui.unmount()
})

test('before the first turn, missing cost and context draw —, not NaN', async ($, on) => {
  engine(on)

  await start($)

  const ui = await $.ui.mount(pane())
  const all = (await texts(ui, /./)).join('\n')
  expect(all).not.toMatch(/NaN|undefined/)
  expect(await keyText(ui, 'head-session')).toMatch(/—/)
  await ui.unmount()
})

const spawn = ($: any) => $.agent.spawn({ prompt: 'p', description: 'find hooks', subagentType: 'Explore' } as never)
const explorer = (status: string) => ({ id: 'a1', type: 'Explore', description: 'find hooks', status })

test('a running agent shows its row with elapsed time', async ($, on) => {
  const { clock } = engine(on, { agentList: () => [explorer('running')] })

  await spawn($)
  await clock.advance(73_000)

  const ui = await $.ui.mount(pane())
  expect(await keyText(ui, 'agent-a1')).toMatch(/Explore.*find hooks.*1m12s/)
  await ui.unmount()
})

test('a finished agent stays 3 minutes then only counts', async ($, on) => {
  let status = 'running'
  const { clock } = engine(on, { agentList: () => [explorer(status)] })

  await spawn($)
  await clock.advance(2_000)
  status = 'completed'
  await clock.advance(1_000)

  const soon = await $.ui.mount(pane())
  expect(await keyText(soon, 'agent-a1')).toMatch(/done/)
  await soon.unmount()

  await clock.advance(180_001)
  const later = await $.ui.mount(pane())
  expect(await later.find({ key: 'agent-a1' })).toBeUndefined()
  expect(await keyText(later, 'head-agents')).toMatch(/1 done/)
  await later.unmount()
})

test('pressing an agent row calls ui.view with its id', async ($, on) => {
  const { clock, rec } = engine(on, { agentList: () => [explorer('running')] })

  await spawn($)
  await clock.advance(1_000)

  const ui = await $.ui.mount(pane())
  await ui.press({ key: 'agent-a1' })
  expect(rec.viewed).toEqual([{ agentId: 'a1' }])
  await ui.unmount()
})

// A session with something in every section.
async function busy($: any, on: any, percent = 31) {
  const handles = engine(on, {
    usage: usageWith(
      {
        percent,
        breakdown: {
          skills: { totalSkills: 2, includedSkills: 2, tokens: 900, skillFrontmatter: [skillRow('superpowers'), skillRow('caveman')] },
          mcpTools: [mcpTool('godot')],
        },
      },
      { cost: { usd: 1.84 } },
    ),
    agentList: () => [explorer('running')],
    files: { '/home/u/.claude.json': JSON.stringify({ mcpServers: { godot: {}, blender: {} } }) },
  })
  on('tool.call', () => ({ result: {} }))
  on('skill.prompt', (_: unknown, e: any) => ({ text: e.text }))
  await start($)
  await $.tool.call({ tool: 'Bash', command: 'ls' } as never)
  await $.tool.call({ tool: 'Write', file_path: '/p/b.ts', content: '' } as never)
  await $.tool.call({ tool: 'TodoWrite', todos: [{ content: 'doing now', status: 'in_progress' }] } as never)
  await $.skill.prompt({ skill: 'brainstorming', text: '' } as never)
  await spawn($)
  await handles.clock.advance(1_000)
  return handles
}

test('on terminal the logo and spinners are Client modules; on vscode they are static', async ($, on) => {
  await busy($, on)

  const terminal = await $.ui.mount(pane(40, 40, 'terminal'))
  expect(await terminal.find({ type: 'Client', key: 'logo' })).toBeDefined()
  expect(await terminal.find({ type: 'Client', key: 'spinner-a1' })).toBeDefined()
  await terminal.unmount()

  const vscode = await $.ui.mount(pane(40, 40, 'vscode'))
  expect(await vscode.find({ type: 'Client' })).toBeUndefined()
  expect(await vscode.find({ type: 'Text', text: /●/ })).toBeDefined()
  await vscode.unmount()
})

test('in a 10-row pane every section header still shows', async ($, on) => {
  await busy($, on)

  const ui = await $.ui.mount(pane(40, 10))
  for (const key of ['head-session', 'head-agents', 'head-skills', 'head-mcp', 'head-tools', 'head-files']) {
    expect(await ui.find({ key })).toBeDefined()
  }
  expect((await ui.find({ type: 'Box' }))?.children.length).toBeLessThanOrEqual(10)
  await ui.unmount()
})

test('an 8-column pane draws a 4-cell bar, not a negative one', async ($, on) => {
  await busy($, on)

  const ui = await $.ui.mount(pane(8))
  expect((await ui.find({ type: 'Text', text: /^[█░]{4,}$/ }))?.text).toHaveLength(4)
  await ui.unmount()
})

test('context bar colour follows the 50/80 thresholds', async ($, on) => {
  let percent = 49
  engine(on, { usage: () => usageWith({ percent })() })
  const colour = async () => {
    await start($)
    const ui = await $.ui.mount(pane())
    const c = (await ui.find({ type: 'Text', text: /^[█░]{4,}$/ }))?.props.color
    await ui.unmount()
    return c
  }

  expect(await colour()).toBe('success')
  percent = 50
  expect(await colour()).toBe('warning')
  percent = 80
  expect(await colour()).toBe('error')
})

test('a new skill draws bold for 2 seconds', async ($, on) => {
  const { clock } = engine(on)
  on('skill.prompt', (_: unknown, e: any) => ({ text: e.text }))

  await $.skill.prompt({ skill: 'brainstorming', text: '' } as never)

  const now = await $.ui.mount(pane())
  expect((await now.find({ type: 'Text', text: /▸ brainstorming/ }))?.props.bold).toBe(true)
  await now.unmount()

  await clock.advance(2_001)
  const later = await $.ui.mount(pane())
  expect((await later.find({ type: 'Text', text: /▸ brainstorming/ }))?.props.bold).toBeFalsy()
  await later.unmount()
})

// Final review fixes.
const turnDone = (agentId?: string) => ({
  answer: 'ok',
  durationMs: 1000,
  isAborted: false,
  turnId: 't1',
  reason: 'answer',
  usage: { model: 'claude-opus-5-5' },
  ...(agentId ? { agentId } : {}),
})

test('a subagent turn leaves the working dot alone', async ($, on) => {
  engine(on)
  on('turn.start', (_: unknown, e: any) => ({ turnId: e.turnId }))
  on('turn.complete', (_: unknown, e: any) => ({ text: e.answer }))

  await $.turn.start({ text: 'go', turnId: 't1' } as never)
  await $.turn.complete(turnDone('a1') as never)

  const ui = await $.ui.mount(pane(40, 40, 'vscode'))
  expect(await ui.find({ type: 'Text', text: /●/ })).toBeDefined()
  await ui.unmount()
})

test('/clear keeps the elapsed clock ticking in an open pane', async ($, on) => {
  const { clock } = engine(on)
  on('session.end', (_: unknown, e: any) => ({ sessionId: e.sessionId }))

  await start($)
  const ui = await $.ui.mount(pane())
  await $.session.end({ reason: 'clear', sessionId: 's1' } as never)
  await clock.advance(300_000)

  expect(await keyText(ui, 'head-session')).toMatch(/5 min/)
  await ui.unmount()
})

test('a long agent type and a multi-line todo still fit their rows', async ($, on) => {
  const { clock } = engine(on, {
    agentList: () => [{ id: 'a1', type: 'general-purpose', description: 'review the whole diff carefully', status: 'running' }],
  })
  on('tool.call', () => ({ result: {} }))

  await spawn($)
  await clock.advance(73_000)
  await $.tool.call({ tool: 'TodoWrite', todos: [{ content: 'line one\nline two', status: 'pending' }] } as never)

  for (const columns of [40, 16]) {
    const ui = await $.ui.mount(pane(columns, 10, 'vscode'))
    expect(((await keyText(ui, 'row-a1')) ?? '').length).toBeLessThanOrEqual(columns)
    expect(await ui.find({ type: 'Text', text: /line two/ })).toBeUndefined()
    expect((await ui.find({ type: 'Text', text: /FILES 0 · TODOS 1 open/ }))?.props.wrap).toBe('truncate')
    expect((await ui.find({ type: 'Text', text: /^MCP/ }))?.props.wrap).toBe('truncate')
    await ui.unmount()
  }
})

test('a failing agent list stops the poll', async ($, on) => {
  let calls = 0
  const { clock } = engine(on, {
    agentList: () => {
      calls += 1
      throw new Error('agents down')
    },
  })

  await spawn($)
  await clock.advance(5_000)

  expect(calls).toBe(1)
})
