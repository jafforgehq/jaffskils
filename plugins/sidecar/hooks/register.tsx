import { atom, read, update } from 'claude-code'
import type { Elements, Register, RenderElement, Timer } from 'claude-code'

import type { FileChange, SkillUse, Todo } from '../types'

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

type El = Elements[keyof Elements]
type Section = 'logo' | 'session' | 'agents' | 'skills' | 'mcp' | 'tools' | 'files'
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

function header(el: El, label: string, detail: string): RenderElement {
  const { Box, Text } = el
  return (
    <Box>
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
  const lines: Line[] = [{ section: 'tools', isHeader: true, node: header(el, 'TOOLS', top || '—') }]
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
        <Box>
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
    timers.push($.clock.every(30_000, () => void update($, tick, n => n + 1)))

    return next(e)
  })

  on('session.end', async (_$, e, next) => {
    for (const timer of timers) timer.cancel()
    timers = []

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
      { section: 'skills' as const, isHeader: true, node: header(el, 'SKILLS', '') },
      ...skillsUsedLines(el, await read($, skillsUsed), now),
      ...toolsLines(el, await read($, tools), await read($, lastCommand), columns),
      ...filesLines(el, await read($, files), await read($, todos)),
    ]

    return <Box flexDirection="column">{lines.map(line => line.node)}</Box>
  })
}
