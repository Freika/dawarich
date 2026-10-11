export function createLifecycle() {
  const cleanups = []
  let destroyed = false

  const disposeOne = (cleanup) => {
    try {
      cleanup()
    } catch {}
  }

  return {
    own(cleanup) {
      if (typeof cleanup !== "function") return
      if (destroyed) disposeOne(cleanup)
      else cleanups.push(cleanup)
    },
    destroy() {
      if (destroyed) return
      destroyed = true
      while (cleanups.length) disposeOne(cleanups.pop())
    },
    get destroyed() {
      return destroyed
    },
  }
}
