import { atom, update } from 'claude-code'
import type { Elements, Register, RenderElement, Timer } from 'claude-code'

const PANE = 'sidecar'
const LOGO = [' █ ▄▀█ █▀▀ █▀▀ █▀ █▄▀ █ █   █▀', '▄█ █▀█ █▀  █▀  ▄█ █ █ █ █▄▄ ▄█'] as const
const LOGO_COLUMNS = 32
const FROM = [0xd9, 0x77, 0x57]
const TO = [0x9b, 0x7b, 0xff]

const shimmer = atom({ plugin: 'sidecar', key: 'shimmer' } as const, 0)
const tick = atom({ plugin: 'sidecar', key: 'tick' } as const, 0)

type El = Elements[keyof Elements]
type Section = 'logo' | 'session' | 'agents' | 'skills' | 'mcp' | 'tools' | 'files'
type Line = { section: Section; isHeader: boolean; node: RenderElement }

// Colour of column i of n along the logo's orange-to-violet gradient.
function gradient(i: number, n: number): string {
  const t = n <= 1 ? 0 : i / (n - 1)
  const hex = FROM.map((a, k) => Math.round(a + (TO[k] - a) * t).toString(16).padStart(2, '0'))
  return `#${hex.join('')}`
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
    const lines = [...logoLines(el, e.props.bodyColumns)]

    return <Box flexDirection="column">{lines.map(line => line.node)}</Box>
  })
}
