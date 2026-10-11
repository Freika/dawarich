export function createRefresh({ run, timers = globalThis }) {
  let closed = false,
    timer = null,
    running = false,
    dirty = false,
    pending = null,
    settle = null
  function promise() {
    if (!pending)
      pending = new Promise((resolve) => {
        settle = resolve
      })
    return pending
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
    if (dirty) timer = timers.setTimeout(flush, 0)
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
      else if (timer === null) timer = timers.setTimeout(flush, 0)
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
