import type { ClientModule } from 'claude-code'

type MotionProps =
  | { kind: 'logo'; rows: [string, string]; colors: string[]; shimmer: number }
  | { kind: 'spinner'; color: string }
  | { kind: 'pulse'; color: string }

// frame: the spinner or pulse step, or the shimmer band's column (-1: no band).
// sweptFor: the shimmer count the last sweep ran for.
type State = { frame: number; sweptFor?: number }

const FRAMES = '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
const SPIN_MS = 80
const PULSE_MS = 500
const SWEEP_MS = 1500
const BAND = 3
const SHINE = '#FFF4E6'

// Draws on its own frame clock, so the hooks module redraws nothing for motion.
const Motion: ClientModule<MotionProps, State> = (props, surface) => {
  const { Box, Text } = surface.elements
  const state = surface.state

  if (props.kind === 'logo') {
    const width = props.rows[0].length
    if (state?.sweptFor !== props.shimmer) {
      // A new shimmer count: sweep the band across once, then stop the timer.
      let column = 0
      const shimmer = props.shimmer
      const stop = surface.every(Math.round(SWEEP_MS / (width + BAND)), () => {
        column += 1
        if (column > width + BAND) {
          stop()
          surface.setState({ frame: -1, sweptFor: shimmer })
        } else {
          surface.setState({ frame: column, sweptFor: shimmer })
        }
      })
      surface.setState({ frame: 0, sweptFor: shimmer })
    }
    const band = state?.frame ?? -1
    return (
      <Box flexDirection="column">
        {props.rows.map(row => (
          <Text>
            {[...row].map((ch, i) => (
              <Text color={band >= 0 && i < band && i >= band - BAND ? SHINE : props.colors[i]}>{ch}</Text>
            ))}
          </Text>
        ))}
      </Box>
    )
  }

  if (state === undefined) {
    let frame = 0
    surface.every(props.kind === 'spinner' ? SPIN_MS : PULSE_MS, () => {
      frame += 1
      surface.setState({ frame })
    })
    surface.setState({ frame })
  }
  const frame = state?.frame ?? 0
  if (props.kind === 'spinner') {
    return <Text color={props.color}>{` ${FRAMES[frame % FRAMES.length]} `}</Text>
  }
  return (
    <Text color={props.color} bold={frame % 2 === 0} dimColor={frame % 2 === 1}>
      {'  ●'}
    </Text>
  )
}

export default Motion
