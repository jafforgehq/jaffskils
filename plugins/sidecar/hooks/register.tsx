import { atom, read, update } from 'claude-code'
import type { Elements, EngineInterface, Register, RenderElement, Timer } from 'claude-code'

import type { Facts, FileChange, Section, SkillUse, Todo } from '../types'

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

type El = Elements[keyof Elements]
type Line = { section: Section; isHeader: boolean; node: RenderElement }

// Colour of column i of n along the logo's orange-to-violet gradient.
function gradient(i: number, n: number): string {
  const t = n <= 1 ? 0 : i / (n - 1)
  const hex = FROM.map((a, k) => Math.round(a + (TO[k] - a) * t).toString(16).padStart(2, '0'))
  return `#${hex.join('')}`
}

// First line of text, cut to width with a trailing ellipsis.
function oneLine(text: string, width: number): string {
  const line = text.split('\n')[0]
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

function header(el: El, label: string, detail: string, key: string): RenderElement {
  const { Box, Text } = el
  return (
    <Box key={key}>
      <Text bold color="claude">{label}</Text>
      <Text>{detail ? `  ${detail}` : ''}</Text>
    </Box>
  )
}

function skillsUsedLines(el: El, used: SkillUse[], now: number): Line[] {
  const { Box, Text } = el
  return used.map((skill, i) => ({
    section: 'skills',
    isHeader: false,
    node: (
      <Box key={`used-${skill.name}`}>
        <Text dimColor>{i === 0 ? ' used ' : '      '}</Text>
        <Text color="claude" wrap="truncate">▸ {skill.name}</Text>
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

function filesLines(el: El, changed: FileChange[], list: Todo[]): Line[] {
  const { Box, Text } = el
  const open = list.filter(t => t.status !== 'completed')
  const shown = [...open.filter(t => t.status === 'in_progress'), ...open.filter(t => t.status === 'pending')].slice(0, 3)
  return [
    {
      section: 'files',
      isHeader: true,
      node: (
        <Box key="head-files">
          <Text bold color="claude">FILES {changed.length}</Text>
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
  const { Text } = el
  if (f.failed.includes('session')) {
    return [{ section: 'session', isHeader: true, node: header(el, 'SESSION', '—', 'head-session') }]
  }
  const cost = f.costUsd === undefined ? '—' : `$${f.costUsd.toFixed(2)}`
  const minutes = Math.max(0, Math.floor((now - (f.startedAt ?? now)) / 60_000))
  const width = columns - 10
  const bar =
    f.contextPercent === undefined
      ? 'ctx —'
      : `ctx ${'█'.repeat(Math.round((f.contextPercent / 100) * width)).padEnd(width, '░')} ${f.contextPercent}%`
  return [
    { section: 'session', isHeader: true, node: header(el, 'SESSION', `${f.model ?? '—'} · ${cost} · ${minutes} min`, 'head-session') },
    { section: 'session', isHeader: false, node: <Text>{bar}</Text> },
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
      const part = `${s.byPlugin[i][0]} ${s.byPlugin[i][1]}`
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

function logoLines(el: El, columns: number): Line[] {
  const { Text } = el
  if (columns < LOGO_COLUMNS) {
    return [{ section: 'logo', isHeader: true, node: <Text color="claude" bold>◆ jaffskils</Text> }]
  }
  return LOGO.map((row, r) => ({
    section: 'logo',
    isHeader: r === 0,
    node: (
      <Text>
        {[...row].map((ch, i) => (
          <Text color={gradient(i, row.length)}>{ch}</Text>
        ))}
      </Text>
    ),
  }))
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

    return next(e)
  })

  on('skill.prompt', async ($, e, next) => {
    const at = await $.clock.now()
    await update($, skillsUsed, list => [{ name: e.skill, at }, ...list.filter(s => s.name !== e.skill)].slice(0, 5))

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    await update($, tools, counts => ({ ...counts, [e.tool]: (counts[e.tool] ?? 0) + 1 }))
    if (e.tool === 'Bash') {
      await update($, lastCommand, () => e.command)
    } else if (e.tool === 'Edit' || e.tool === 'Write') {
      const at = await $.clock.now()
      await update($, files, list => (list.some(f => f.path === e.file_path) ? list : [...list, { path: e.file_path, at }]))
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
    const lines = [
      ...logoLines(el, columns),
      ...sessionLines(el, await read($, facts), now, columns),
      ...skillsTotalLines(el, await read($, facts), columns),
      ...skillsUsedLines(el, await read($, skillsUsed), now),
      ...mcpLines(el, await read($, facts)),
      ...toolsLines(el, await read($, tools), await read($, lastCommand), columns),
      ...filesLines(el, await read($, files), await read($, todos)),
    ]

    return <Box flexDirection="column">{lines.map(line => line.node)}</Box>
  })
}
