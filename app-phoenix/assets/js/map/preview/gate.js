import { cancelled } from "../data/request_scope.js"
export function createPreviewGate(limit = 2) {
  const queue = []
  let active = 0
  function drain() {
    while (active < limit && queue.length) {
      const job = queue.shift()
      job.signal.removeEventListener("abort", job.abort)
      if (job.signal.aborted) {
        job.reject(cancelled())
        continue
      }
      active++
      let released = false
      job.resolve(() => {
        if (released) return
        released = true
        active--
        drain()
      })
    }
  }
  return {
    acquire(signal) {
      if (signal.aborted) return Promise.reject(cancelled())
      return new Promise((resolve, reject) => {
        const job = {
          signal,
          resolve,
          reject,
          abort: () => {
            const i = queue.indexOf(job)
            if (i >= 0) queue.splice(i, 1)
            reject(cancelled())
          },
        }
        queue.push(job)
        signal.addEventListener("abort", job.abort, { once: true })
        drain()
      })
    },
    get active() {
      return active
    },
  }
}
const documents = new WeakMap()
export function documentPreviewGate(document) {
  if (!documents.has(document)) documents.set(document, createPreviewGate())
  return documents.get(document)
}
