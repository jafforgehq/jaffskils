export type Todo = { content: string; status: 'pending' | 'in_progress' | 'completed' }

declare module 'claude-code' {
  interface PluginState {
    'session-recap': { files: string[]; commands: number; todos: Todo[] }
  }
}
