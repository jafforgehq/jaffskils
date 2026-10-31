export type SkillUse = { name: string; at: number }
export type FileChange = { path: string; at: number }
export type Todo = { content: string; status: 'pending' | 'in_progress' | 'completed' }
export type Section = 'logo' | 'session' | 'agents' | 'skills' | 'mcp' | 'tools' | 'files'
export type Facts = {
  model?: string
  costUsd?: number
  contextPercent?: number
  startedAt?: number
  skills?: { total: number; tokens: number; byPlugin: [string, number][] }
  mcp?: { connected: string[]; missing: string[] }
  failed: Section[]
}

declare module 'claude-code' {
  interface PluginState {
    sidecar: {
      shimmer: number
      tick: number
      skillsUsed: Shaped<SkillUse[]>
      tools: Shaped<Record<string, number>>
      lastCommand: string
      files: Shaped<FileChange[]>
      todos: Shaped<Todo[]>
      facts: Shaped<Facts>
      isWorking: boolean
    }
  }
}
