import { atom, read, update } from 'claude-code'
import type { Elements, EngineInterface, Register, RenderElement, Timer } from 'claude-code'

import type { AgentRow, Facts, FileChange, Section, SkillUse, Todo } from '../types'

const PANE = 'sidecar'
const LOGO = [' █ ▄▀█ █▀▀ █▀▀ █▀ █▄▀ █ █   █▀', '▄█ █▀█ █▀  █▀  ▄█ █ █ █ █▄▄ ▄█'] as const
const LOGO_COLUMNS = 32
const FROM = [0xd9, 0x77, 0x57]
const TO = [0x9b, 0x7b, 0xff]

const shimmer = atom({ plugin: 'sidecar', key: 'shimmer' } as const, 0)
const tick = atom({ plugin: 'sidecar', key: 'tick' } as const, 0)
const skillsUsed = atom({ plugin: 'sidecar', key: 'skillsUsed' } as const, [], { shape: 'skills-used-1' })
const tools = atom({ plugin: 'sidecar', key: 'tools' } as const, {}, { shape: 'tools-1' })
const lastCommand = atom({ plugin: 'sidecar', key: 'lastCommand' } as const, '')
const files = atom({ plugin: 'sidecar', key: 'files' } as const, [], { shape: 'files-1' })
const todos = atom({ plugin: 'sidecar', key: 'todos' } as const, [], { shape: 'todos-1' })
const facts = atom({ plugin: 'sidecar', key: 'facts' } as const, { failed: [] }, { shape: 'facts-1' })
const isWorking = atom({ plugin: 'sidecar', key: 'isWorking' } as const, false)
const agents = atom({ plugin: 'sidecar', key: 'agents' } as const, [], { shape: 'agents-1' })

const ACTIVE = ['pending', 'running', 'waiting']
const FINISHED = ['completed', 'failed', 'killed']
const SHOW_FINISHED_MS = 180_000
const FLASH_MS = 2_000

type El = Elements[keyof Elements]
// height: rows the line takes when it is more than one (the animated logo).
type Line = { section: Section; isHeader: boolean; node: RenderElement; height?: number }

// Colour of column i of n along the logo's orange-to-violet gradient.
function gradient(i: number, n: number): string {
  const t = n <= 1 ? 0 : i / (n - 1)
  const hex = FROM.map((a, k) => Math.round(a + ((TO[k] ?? a) - a) * t).toString(16).padStart(2, '0'))
  return `#${hex.join('')}`
}

// First line of text, cut to width with a trailing ellipsis.
function oneLine(text: string, width: number): string {
  const line = text.split('\n')[0] ?? ''
  if (width < 1) return ''
  return line.length <= width ? line : `${line.slice(0, width - 1)}…`
}

function ago(ms: number): string {
  if (ms < 60_000) return 'now'
  if (ms < 3_600_000) return `${Math.floor(ms / 60_000)}m ago`
  return `${Math.floor(ms / 3_600_000)}h ago`
}

type McpProject = { mcpServers?: Record<string, unknown>; disabledMcpServers?: string[]; disabledMcpjsonServers?: string[] }
type ClaudeJson = { mcpServers?: Record<string, unknown>; projects?: Record<string, McpProject> }
type McpJson = { mcpServers?: Record<string, unknown> }

// Configured MCP servers that have no tools in the session, so did not connect.
function missingServers(claudeJson: ClaudeJson, mcpJson: McpJson, root: string, connected: string[]): string[] {
  const project = claudeJson.projects?.[root] ?? {}
  const disabled = project.disabledMcpServers ?? []
  const names = [
    ...Object.keys(claudeJson.mcpServers ?? {}),
    ...Object.keys(project.mcpServers ?? {}),
    ...Object.keys(mcpJson.mcpServers ?? {}).filter(n => !(project.disabledMcpjsonServers ?? []).includes(n)),
  ]
  return [...new Set(names)].filter(n => !disabled.includes(n) && !connected.includes(n))
}

function shortModel(model: string): string {
  return model.replace(/^claude-/, '').replace(/-\d.*$/, '')
}

async function readJson($: EngineInterface, path: string): Promise<object> {
  try {
    return JSON.parse(await $.fs.read(path)) ?? {}
  } catch {
    return {}
  }
}

async function loadFacts($: EngineInterface): Promise<void> {
  const next: Facts = { model: (await read($, facts)).model, failed: [] }
  try {
    const usage = await $.session.usage()
    next.costUsd = usage.cost?.usd
    next.contextPercent = usage.context.percent
    next.startedAt = usage.startedAt
  } catch {
    next.failed.push('session')
  }
  try {
    const breakdown = (await $.session.usage({ breakdown: 'summary' })).context.breakdown
    if (breakdown?.skills) {
      const counts = new Map<string, number>()
      for (const skill of breakdown.skills.skillFrontmatter) {
        const owner = skill.pluginName ?? skill.source
        counts.set(owner, (counts.get(owner) ?? 0) + 1)
      }
      next.skills = {
        total: breakdown.skills.totalSkills,
        tokens: breakdown.skills.tokens,
        byPlugin: [...counts].sort((a, b) => b[1] - a[1]),
      }
    }
    if (breakdown) {
      const connected = [...new Set(breakdown.mcpTools.map(t => t.serverName))]
      const dir = (await $.env.get('CLAUDE_CONFIG_DIR')) ?? (await $.env.get('HOME')) ?? ''
      const root = await $.session.root()
      const claudeJson = (await readJson($, `${dir}/.claude.json`)) as ClaudeJson
      const mcpJson = (await readJson($, `${root}/.mcp.json`)) as McpJson
      next.mcp = { connected, missing: missingServers(claudeJson, mcpJson, root, connected) }
    }
  } catch {
    next.failed.push('skills', 'mcp')
  }
  await update($, facts, () => next)
}

function elapsed(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000))
  if (s < 60) return `${s}s`
  if (s < 3600) return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, '0')}s`
  return `${Math.floor(s / 3600)}h${String(Math.floor((s % 3600) / 60)).padStart(2, '0')}m`
}

// Merges $.agent.list() into the agents atom. The API gives no start time, so
// seenAt is the first refresh that saw the agent.
// Redraws once the 2 s flash of a new item is over.
function settleFlash($: EngineInterface): void {
  $.clock.after(FLASH_MS + 1, () => void update($, tick, n => n + 1))
}

async function refreshAgents($: EngineInterface): Promise<void> {
  const list = await $.agent.list()
  const now = await $.clock.now()
  await update($, agents, rows => {
    const byId = new Map(rows.map(r => [r.id, r]))
    for (const info of list) {
      const row: AgentRow = { ...(byId.get(info.id) ?? { seenAt: now }), id: info.id, type: info.type, description: info.description, status: info.status }
      if (FINISHED.includes(row.status) && row.endedAt === undefined) {
        row.endedAt = now
        settleFlash($)
      }
      byId.set(info.id, row)
    }
    for (const row of byId.values()) {
      if (row.endedAt === undefined && !list.some(a => a.id === row.id)) byId.set(row.id, { ...row, status: 'completed', endedAt: now })
    }
    return [...byId.values()]
  })
}

// One poll at a time while any agent is active; it stops itself after.
let poll: Timer | undefined

async function pollTick($: EngineInterface): Promise<void> {
  await refreshAgents($)
  if (!(await read($, agents)).some(r => ACTIVE.includes(r.status))) {
    poll?.cancel()
    poll = undefined
  }
}

function pollAgents($: EngineInterface): void {
  poll ??= $.clock.every(1000, () => void pollTick($))
}

function header(el: El, label: string, detail: string, key: string): RenderElement {
  const { Box, Text } = el
  return (
    <Box key={key}>
      <Text bold color="claude">{label}</Text>
      <Text wrap="truncate">{detail ? `  ${detail}` : ''}</Text>
    </Box>
  )
}

function skillsUsedLines(el: El, used: SkillUse[], now: number): Line[] {
  // A skill used in the last 2 s draws bold.
  const { Box, Text } = el
  return used.map((skill, i) => ({
    section: 'skills',
    isHeader: false,
    node: (
      <Box key={`used-${skill.name}`}>
        <Text dimColor>{i === 0 ? ' used ' : '      '}</Text>
        <Text color="claude" bold={now - skill.at < FLASH_MS} wrap="truncate">▸ {skill.name}</Text>
        <Text dimColor> {ago(now - skill.at)}</Text>
      </Box>
    ),
  }))
}

function toolsLines(el: El, counts: Record<string, number>, last: string, columns: number): Line[] {
  const { Text } = el
  const top = Object.entries(counts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 3)
    .map(([tool, n]) => `${tool} ${n}`)
    .join(' · ')
  const lines: Line[] = [{ section: 'tools', isHeader: true, node: header(el, 'TOOLS', top || '—', 'head-tools') }]
  if (last) {
    lines.push({ section: 'tools', isHeader: false, node: <Text dimColor>{`last $ ${oneLine(last, columns - 7)}`}</Text> })
  }
  return lines
}

function filesLines(el: El, changed: FileChange[], list: Todo[], now: number): Line[] {
  const { Box, Text } = el
  const open = list.filter(t => t.status !== 'completed')
  const shown = [...open.filter(t => t.status === 'in_progress'), ...open.filter(t => t.status === 'pending')].slice(0, 3)
  return [
    {
      section: 'files',
      isHeader: true,
      node: (
        <Box key="head-files">
          <Text bold color="claude" inverse={changed.some(f => now - f.at < FLASH_MS)}>FILES {changed.length}</Text>
          <Text dimColor> · </Text>
          <Text bold color="claude">TODOS {open.length} open</Text>
        </Box>
      ),
    },
    ...shown.map(t => ({
      section: 'files' as const,
      isHeader: false,
      node:
        t.status === 'in_progress' ? (
          <Text color="warning" wrap="truncate">{` ~ ${t.content}`}</Text>
        ) : (
          <Text dimColor wrap="truncate">{` · ${t.content}`}</Text>
        ),
    })),
  ]
}

function sessionLines(el: El, f: Facts, now: number, columns: number): Line[] {
  const { Box, Text } = el
  if (f.failed.includes('session')) {
    return [{ section: 'session', isHeader: true, node: header(el, 'SESSION', '—', 'head-session') }]
  }
  const cost = f.costUsd === undefined ? '—' : `$${f.costUsd.toFixed(2)}`
  const minutes = Math.max(0, Math.floor((now - (f.startedAt ?? now)) / 60_000))
  const width = Math.max(4, columns - 10)
  const p = f.contextPercent
  const bar =
    p === undefined ? (
      <Text>ctx —</Text>
    ) : (
      <Box>
        <Text>ctx </Text>
        <Text color={p < 50 ? 'success' : p < 80 ? 'warning' : 'error'}>
          {'█'.repeat(Math.min(width, Math.round((p / 100) * width))).padEnd(width, '░')}
        </Text>
        <Text>{` ${p}%`}</Text>
      </Box>
    )
  return [
    { section: 'session', isHeader: true, node: header(el, 'SESSION', `${f.model ?? '—'} · ${cost} · ${minutes} min`, 'head-session') },
    { section: 'session', isHeader: false, node: bar },
  ]
}

function skillsTotalLines(el: El, f: Facts, columns: number): Line[] {
  const { Text } = el
  const s = f.skills
  const lines: Line[] = [
    {
      section: 'skills',
      isHeader: true,
      node: header(el, 'SKILLS', s ? `${s.total} · ${s.byPlugin.length} plugins · ~${(s.tokens / 1000).toFixed(1)}k` : '', 'head-skills'),
    },
  ]
  if (!s) return lines
  // Pack "plugin count" pairs into at most two lines, then say how many are left.
  const rows: string[] = []
  let i = 0
  while (i < s.byPlugin.length && rows.length < 2) {
    let row = ''
    while (i < s.byPlugin.length) {
      const [name, count] = s.byPlugin[i] ?? ['', 0]
      const part = `${name} ${count}`
      const next = row ? `${row} · ${part}` : part
      if (row && next.length > columns - 2) break
      row = next
      i += 1
    }
    rows.push(row)
  }
  if (i < s.byPlugin.length) rows[rows.length - 1] += ` · ${s.byPlugin.length - i} more`
  return [...lines, ...rows.map(row => ({ section: 'skills' as const, isHeader: false, node: <Text dimColor wrap="truncate">{` ${row}`}</Text> }))]
}

function mcpLines(el: El, f: Facts): Line[] {
  const { Box, Text } = el
  const mcp = f.mcp
  return [
    {
      section: 'mcp',
      isHeader: true,
      node: (
        <Box key="head-mcp">
          <Text bold color="claude">MCP</Text>
          {mcp ? <Text color="success">{`  ✓ ${mcp.connected.length}`}</Text> : <Text>  —</Text>}
          {(mcp?.missing ?? []).map(name => (
            <Text color="error">{`  ✗ ${name}`}</Text>
          ))}
        </Box>
      ),
    },
  ]
}

function agentLines(el: El, rows: AgentRow[], now: number, columns: number, motion: boolean, view: (id: string) => void): Line[] {
  const { Box, Button, Client, Text } = el as Elements['terminal']
  const running = rows.filter(r => ACTIVE.includes(r.status)).length
  const done = rows.filter(r => r.endedAt !== undefined).length
  const detail = rows.length === 0 ? '—' : [running && `${running} running`, done && `${done} done`].filter(Boolean).join(' · ')
  const shown = rows.filter(r => r.endedAt === undefined || now - r.endedAt <= SHOW_FINISHED_MS)
  return [
    { section: 'agents', isHeader: true, node: header(el, 'AGENTS', detail, 'head-agents') },
    ...shown.map(r => {
      const isFailed = r.status === 'failed' || r.status === 'killed'
      const glyph = r.status === 'completed' ? '✓' : isFailed ? '✗' : ACTIVE.includes(r.status) ? '●' : '·'
      const color = r.status === 'completed' ? 'success' : isFailed ? 'error' : 'claude'
      const time = r.status === 'completed' ? 'done' : isFailed ? 'failed' : r.status === 'idle' ? 'idle' : elapsed(now - r.seenAt)
      return {
        section: 'agents' as const,
        isHeader: false,
        node: (
          <Box key={`row-${r.id}`}>
            {motion && ACTIVE.includes(r.status) ? (
              <Client key={`spinner-${r.id}`} module="./motion.tsx" props={{ kind: 'spinner', color }} width={3} />
            ) : (
              <Text color={color} bold={r.endedAt !== undefined && now - r.endedAt < FLASH_MS}>{` ${glyph} `}</Text>
            )}
          <Button key={`agent-${r.id}`} plain onPress={() => view(r.id)}>
            {`${r.type.padEnd(9)} `}
            <Text dimColor>{oneLine(r.description, Math.max(4, columns - 22))}</Text>
            {` ${time}`}
          </Button>
          </Box>
        ),
      }
    }),
  ]
}

function logoLines(el: El, columns: number, motion = false, shimmerCount = 0, working = false): Line[] {
  const { Box, Client, Text } = el as Elements['terminal']
  const dot = !working ? null : motion ? (
    <Client key="pulse" module="./motion.tsx" props={{ kind: 'pulse', color: 'claude' }} width={3} />
  ) : (
    <Text color="claude">{'  ●'}</Text>
  )
  if (columns < LOGO_COLUMNS) {
    return [
      {
        section: 'logo',
        isHeader: true,
        node: (
          <Box>
            <Text color="claude" bold wrap="truncate">◆ jaffskils</Text>
            {dot}
          </Box>
        ),
      },
    ]
  }
  if (motion) {
    const colors = [...LOGO[0]].map((_, i) => gradient(i, LOGO[0].length))
    return [
      {
        section: 'logo',
        isHeader: true,
        height: 2,
        node: (
          <Box>
            <Client key="logo" module="./motion.tsx" props={{ kind: 'logo', rows: [...LOGO], colors, shimmer: shimmerCount }} width={LOGO[0].length} height={2} />
            {dot}
          </Box>
        ),
      },
    ]
  }
  return LOGO.map((row, r) => ({
    section: 'logo',
    isHeader: r === 0,
    node: (
      <Text>
        {[...row].map((ch, i) => (
          <Text color={gradient(i, row.length)}>{ch}</Text>
        ))}
        {r === 1 && working ? <Text color="claude">{'  ●'}</Text> : null}
      </Text>
    ),
  }))
}

// Fits the lines into the pane's rows: detail lines go first, from the bottom
// section up; then the logo shrinks to one line; then the end is cut.
function fitRows(lines: Line[], rows: number, compactLogo: Line[]): Line[] {
  const height = (ls: Line[]) => ls.reduce((n, l) => n + (l.height ?? 1), 0)
  let kept = [...lines]
  for (let i = kept.length - 1; i >= 0 && height(kept) > rows; i--) {
    const line = kept[i]
    if (line && !line.isHeader && line.section !== 'logo') kept.splice(i, 1)
  }
  if (height(kept) > rows) kept = [...compactLogo, ...kept.filter(l => l.section !== 'logo')]
  while (kept.length > 0 && height(kept) > rows) kept.pop()
  return kept
}

export const register: Register = on => {
  let timers: Timer[] = []

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: PANE, description: 'Open or close the sidecar pane' })
    void $.ui.open({ id: PANE, title: PANE })
    await update($, shimmer, n => n + 1)
    await loadFacts($)
    timers.push($.clock.every(30_000, () => void update($, tick, n => n + 1)))

    return next(e)
  })

  on('session.end', async (_$, e, next) => {
    for (const timer of timers) timer.cancel()
    timers = []
    poll?.cancel()
    poll = undefined

    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    await update($, isWorking, () => true)

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    await update($, isWorking, () => false)
    await update($, shimmer, n => n + 1)
    if (e.agentId === undefined && e.usage?.model) {
      const model = shortModel(e.usage.model)
      await update($, facts, f => ({ ...f, model }))
    }
    await loadFacts($)
    await refreshAgents($)

    return next(e)
  })

  on('agent.spawn', ($, e, next) => {
    pollAgents($)

    return next(e)
  })

  on('skill.prompt', async ($, e, next) => {
    const at = await $.clock.now()
    await update($, skillsUsed, list => [{ name: e.skill, at }, ...list.filter(s => s.name !== e.skill)].slice(0, 5))
    settleFlash($)

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    await update($, tools, counts => ({ ...counts, [e.tool]: (counts[e.tool] ?? 0) + 1 }))
    if (e.tool === 'Bash') {
      await update($, lastCommand, () => e.command)
    } else if (e.tool === 'Edit' || e.tool === 'Write') {
      const at = await $.clock.now()
      await update($, files, list => (list.some(f => f.path === e.file_path) ? list : [...list, { path: e.file_path, at }]))
      settleFlash($)
    } else if (e.tool === 'TodoWrite') {
      await update($, todos, () => e.todos.map(t => ({ content: t.content, status: t.status })))
    }

    return next(e)
  })

  on('command.run', { command: PANE }, async $ => {
    const isOpen = (await $.ui.panes()).some(p => p.id === PANE)
    if (isOpen) {
      await $.ui.close({ id: PANE })
      return { text: 'sidecar pane closed.' }
    }
    await $.ui.open({ id: PANE, title: PANE })
    return { text: 'sidecar pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const el = $.ui.resolve(e)
    const { Box } = el
    const columns = e.props.bodyColumns
    await read($, tick)
    const now = await $.clock.now()
    const motion = e.surface === 'terminal' || e.surface === 'desktop'
    const working = await read($, isWorking)
    const lines = [
      ...logoLines(el, columns, motion, await read($, shimmer), working),
      ...sessionLines(el, await read($, facts), now, columns),
      ...agentLines(el, await read($, agents), now, columns, motion, id => void $.ui.view({ agentId: id })),
      ...skillsTotalLines(el, await read($, facts), columns),
      ...skillsUsedLines(el, await read($, skillsUsed), now),
      ...mcpLines(el, await read($, facts)),
      ...toolsLines(el, await read($, tools), await read($, lastCommand), columns),
      ...filesLines(el, await read($, files), await read($, todos), now),
    ]

    const fitted = fitRows(lines, e.props.scroll.bodyRows, logoLines(el, 0, false, 0, working))

    return <Box flexDirection="column">{fitted.map(line => line.node)}</Box>
  })
}
