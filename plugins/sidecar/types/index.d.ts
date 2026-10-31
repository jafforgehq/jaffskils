export type SkillUse = { name: string; at: number }
export type FileChange = { path: string; at: number }
export type Todo = { content: string; status: 'pending' | 'in_progress' | 'completed' }

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
    }
  }
}
