export const ORDER_TIMEOUT_MS = 600_000

const aborted = () => new DOMException("Print order aborted", "AbortError")

export function submitPrintOrder({
  url,
  blob,
  sku,
  title,
  themeBase,
  layoutId,
  onProgress,
  signal,
  timeoutMs = ORDER_TIMEOUT_MS,
  errors = {},
  XMLHttpRequest: Request = globalThis.XMLHttpRequest,
  timers = globalThis,
}) {
  if (signal?.aborted) return Promise.reject(aborted())
  const form = new FormData()
  form.append("file", blob, "poster.pdf")
  form.append("sku", sku)
  form.append("title", title || "")
  form.append("theme_base", themeBase || "")
  form.append("layout_id", layoutId)

  return new Promise((resolve, reject) => {
    const xhr = new Request()
    const cleanup = []
    const listen = (target, type, handler) => {
      target.addEventListener(type, handler)
      cleanup.push(() => target.removeEventListener(type, handler))
    }
    const settle = (callback) => {
      for (const remove of cleanup.splice(0)) remove()
      callback()
    }
    const fail = (error) =>
      settle(() => {
        xhr.abort()
        reject(error)
      })

    xhr.open("POST", url)
    xhr.responseType = "json"
    if (onProgress)
      listen(xhr.upload, "progress", (event) => {
        if (event.lengthComputable) onProgress(event.loaded / event.total)
      })
    listen(xhr, "load", () =>
      settle(() => {
        const body = xhr.response || {}
        if (xhr.status < 200 || xhr.status >= 300)
          reject(new Error(errors[body.error] || errors.generic || ""))
        else resolve({ token: body.token, checkoutUrl: body.checkout_url })
      }),
    )
    listen(xhr, "error", () =>
      settle(() => reject(new Error(errors.connection || ""))),
    )
    if (signal) listen(signal, "abort", () => fail(aborted()))
    const timer = timers.setTimeout(
      () => fail(new Error(errors.connection || "")),
      timeoutMs,
    )
    cleanup.push(() => timers.clearTimeout(timer))
    xhr.send(form)
  })
}
