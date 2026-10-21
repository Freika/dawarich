export function createRefresh({ run, timers = globalThis, delay = () => 0 }) {
  let closed = false,
    timer = null,
    dueAt = 0,
    running = false,
    dirty = false,
    pending = null,
    settle = null
  const now = () => timers.now?.() ?? Date.now()
  function promise() {
    if (!pending)
      pending = new Promise((resolve) => {
        settle = resolve
      })
    return pending
  }
  function arm() {
    const wait = delay(),
      due = now() + wait
    if (timer !== null && dueAt <= due) return
    if (timer !== null) timers.clearTimeout(timer)
    dueAt = due
    timer = timers.setTimeout(flush, wait)
  }
  async function flush() {
    timer = null
    if (closed) return
    running = true
    dirty = false
    let result
    try {
      result = await run()
    } catch {
      result = "failed"
    }
    running = false
    if (closed) return
    if (dirty) arm()
    else {
      settle?.(result)
      pending = null
      settle = null
    }
  }
  return {
    schedule() {
      if (closed) return Promise.resolve("cancelled")
      const result = promise()
      if (running) dirty = true
      else arm()
      return result
    },
    destroy() {
      if (closed) return
      closed = true
      if (timer !== null) timers.clearTimeout(timer)
      timer = null
      dirty = false
      settle?.("cancelled")
      pending = null
      settle = null
    },
  }
}
