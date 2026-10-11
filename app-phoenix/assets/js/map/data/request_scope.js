export const cancelled = () =>
  new DOMException("Map operation cancelled", "AbortError")

export function createRequestScope(timers = globalThis) {
  const operations = new Set()
  let generation = 0
  let destroyed = false

  return {
    begin(signal, timeoutMs = 15000) {
      if (destroyed || signal?.aborted) throw cancelled()
      const controller = new AbortController()
      const revision = generation
      const abort = () => controller.abort()
      const timer = timers.setTimeout(abort, timeoutMs)
      signal?.addEventListener("abort", abort, { once: true })
      const operation = {
        signal: controller.signal,
        revision,
        check() {
          if (destroyed || revision !== generation || controller.signal.aborted)
            throw cancelled()
        },
        async wait(promise) {
          let rejectOnAbort
          const aborted = new Promise((_, reject) => {
            rejectOnAbort = () => reject(cancelled())
          })
          controller.signal.addEventListener("abort", rejectOnAbort, {
            once: true,
          })
          try {
            if (controller.signal.aborted) rejectOnAbort()
            return await Promise.race([promise, aborted])
          } finally {
            controller.signal.removeEventListener("abort", rejectOnAbort)
          }
        },
        close() {
          timers.clearTimeout(timer)
          signal?.removeEventListener("abort", abort)
          operations.delete(operation)
        },
        abort,
      }
      operations.add(operation)
      return operation
    },
    reset() {
      generation++
      for (const operation of operations) operation.abort()
    },
    destroy() {
      destroyed = true
      this.reset()
    },
    get revision() {
      return generation
    },
  }
}
