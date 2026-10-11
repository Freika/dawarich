const abortError = () => {
  const error = new Error("Range change superseded")
  error.name = "AbortError"
  return error
}

export function createRangeRequests({
  pushEvent,
  timers = globalThis,
  timeoutMs = 15000,
}) {
  let latest = 0
  let pending = null
  let destroyed = false

  function settle(outcome, value) {
    const current = pending
    if (!current) return
    pending = null
    timers.clearTimeout(current.timer)
    current.signal?.removeEventListener("abort", current.onAbort)
    outcome === "resolve" ? current.resolve(value) : current.reject(value)
  }

  function applyDates(range, { signal } = {}) {
    settle("reject", abortError())
    if (destroyed || signal?.aborted) return Promise.reject(abortError())

    return new Promise((resolve, reject) => {
      const request = { resolve, reject, signal, revision: null }
      request.onAbort = () =>
        pending === request && settle("reject", abortError())
      request.timer = timers.setTimeout(
        () =>
          pending === request && settle("reject", new Error("range_timeout")),
        timeoutMs,
      )
      signal?.addEventListener("abort", request.onAbort, { once: true })
      pending = request

      pushEvent("map:range", range, (reply) => {
        if (pending !== request) return
        if (!Number.isInteger(reply?.revision))
          return settle("reject", new Error(reply?.error || "range_refused"))
        request.revision = reply.revision
        if (latest === reply.revision) settle("resolve", { revision: latest })
      })
    })
  }

  function config(next) {
    if (!Number.isInteger(next?.revision) || next.revision < latest) return
    latest = next.revision
    if (pending?.revision === latest) settle("resolve", { revision: latest })
  }

  function destroy() {
    destroyed = true
    settle("reject", abortError())
  }

  return { applyDates, config, destroy }
}
