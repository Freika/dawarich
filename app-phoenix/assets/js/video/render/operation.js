export function createRenderRuns() {
  let current = null

  return {
    async perform(task, apply) {
      current?.controller.abort()
      const run = { controller: new AbortController() }
      current = run
      try {
        const result = await task(run.controller.signal)
        if (current === run && !run.controller.signal.aborted) apply(result)
        return result
      } finally {
        if (current === run) current = null
      }
    },
    cancel() {
      current?.controller.abort()
      current = null
    },
    get signal() {
      return current?.controller.signal ?? null
    },
    get active() {
      return current !== null
    },
  }
}
