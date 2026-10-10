export const ENCODER_TIMEOUT_MS = 30_000

export const encoderTimedOut = () =>
  new DOMException("Video encoder timed out", "TimeoutError")

const abortReason = (signal) =>
  signal.reason?.name === "TimeoutError"
    ? signal.reason
    : new DOMException("Render cancelled", "AbortError")

export function waitForEncoder(
  work,
  { signal, timeoutMs = ENCODER_TIMEOUT_MS, timers = globalThis } = {},
) {
  if (signal?.aborted) return Promise.reject(abortReason(signal))
  return new Promise((resolve, reject) => {
    const settle = (finish, value) => {
      timers.clearTimeout(timer)
      signal?.removeEventListener("abort", cancel)
      finish(value)
    }
    const cancel = () => settle(reject, abortReason(signal))
    const timer = timers.setTimeout(
      () => settle(reject, encoderTimedOut()),
      timeoutMs,
    )
    signal?.addEventListener("abort", cancel, { once: true })
    let result
    try {
      result = work()
    } catch (error) {
      settle(reject, error)
      return
    }
    Promise.resolve(result).then(
      (value) => settle(resolve, value),
      (error) => settle(reject, error),
    )
  })
}
